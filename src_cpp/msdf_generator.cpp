#include "msdf_generator.h"

#include <msdfgen.h>
#include <msdfgen-ext.h>
#include <msdf-atlas-gen/msdf-atlas-gen.h>
#include <msdf-atlas-gen/BitmapAtlasStorage.h>
#include <msdf-atlas-gen/ImmediateAtlasGenerator.h>
#include <msdf-atlas-gen/TightAtlasPacker.h>
#include <msdf-atlas-gen/GridAtlasPacker.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/font_file.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <ft2build.h>
#include FT_FREETYPE_H

#include <algorithm>
#include <cstdio>
#include <cstring>

namespace godot {

MSDFGenerator::MSDFGenerator() {
    progress.store(0.0f);
    running.store(false);
    cancel_requested.store(false);
}

MSDFGenerator::~MSDFGenerator() {
    cancel();
    if (worker_thread.joinable()) {
        worker_thread.join();
    }
}

void MSDFGenerator::_bind_methods() {
    ClassDB::bind_method(D_METHOD("load_font_file", "path"), &MSDFGenerator::load_font_file);
    ClassDB::bind_method(D_METHOD("load_font_data", "data", "path"), &MSDFGenerator::load_font_data, DEFVAL(String()));
    ClassDB::bind_method(D_METHOD("add_fallback_font_file", "path"), &MSDFGenerator::add_fallback_font_file);
    ClassDB::bind_method(D_METHOD("add_fallback_font_data", "data", "path"), &MSDFGenerator::add_fallback_font_data, DEFVAL(String()));
    ClassDB::bind_method(D_METHOD("clear_fallback_fonts"), &MSDFGenerator::clear_fallback_fonts);
    ClassDB::bind_method(D_METHOD("set_unicode_ranges", "codepoints"), &MSDFGenerator::set_unicode_ranges);
    ClassDB::bind_method(D_METHOD("configure_atlas", "config"), &MSDFGenerator::configure_atlas);
    ClassDB::bind_method(D_METHOD("generate_async"), &MSDFGenerator::generate_async);
    ClassDB::bind_method(D_METHOD("get_progress"), &MSDFGenerator::get_progress);
    ClassDB::bind_method(D_METHOD("cancel"), &MSDFGenerator::cancel);
    ClassDB::bind_method(D_METHOD("is_running"), &MSDFGenerator::is_running);

    ClassDB::bind_method(D_METHOD("_emit_progress", "progress"), &MSDFGenerator::_emit_progress);
    ClassDB::bind_method(D_METHOD("_emit_completed", "texture_image", "layout_metadata"), &MSDFGenerator::_emit_completed);
    ClassDB::bind_method(D_METHOD("_emit_failed", "error_message"), &MSDFGenerator::_emit_failed);

    ADD_SIGNAL(MethodInfo("generation_progress", PropertyInfo(Variant::FLOAT, "progress_ratio")));
    ADD_SIGNAL(MethodInfo("generation_completed", PropertyInfo(Variant::OBJECT, "texture_image", PROPERTY_HINT_RESOURCE_TYPE, "Image"), PropertyInfo(Variant::DICTIONARY, "layout_metadata")));
    ADD_SIGNAL(MethodInfo("generation_failed", PropertyInfo(Variant::STRING, "error_message")));

    BIND_ENUM_CONSTANT(FIELD_SDF);
    BIND_ENUM_CONSTANT(FIELD_PSDF);
    BIND_ENUM_CONSTANT(FIELD_MSDF);
    BIND_ENUM_CONSTANT(FIELD_MTSDF);

    BIND_ENUM_CONSTANT(PACKING_MAXRECTS);
    BIND_ENUM_CONSTANT(PACKING_SHELF);
}

bool MSDFGenerator::_load_file_bytes(const String &p_path, std::vector<uint8_t> &r_data) {
    if (p_path.is_empty()) {
        return false;
    }

    if (p_path.begins_with("res://")) {
        ResourceLoader *rl = ResourceLoader::get_singleton();
        if (rl && rl->exists(p_path)) {
            Ref<Resource> res = rl->load(p_path);
            Ref<FontFile> ff = res;
            if (ff.is_valid()) {
                PackedByteArray pba = ff->get_data();
                if (pba.size() > 0) {
                    r_data.resize(pba.size());
                    memcpy(r_data.data(), pba.ptr(), pba.size());
                    return true;
                }
            }
        }

        OS *os = OS::get_singleton();
        if (os) {
            String exe_dir = os->get_executable_path().get_base_dir();
            String rel_sub = p_path.trim_prefix("res://");
            String disk_try = exe_dir.path_join(rel_sub);
            if (FileAccess::file_exists(disk_try)) {
                PackedByteArray disk_bytes = FileAccess::get_file_as_bytes(disk_try);
                if (disk_bytes.size() > 0) {
                    r_data.resize(disk_bytes.size());
                    memcpy(r_data.data(), disk_bytes.ptr(), disk_bytes.size());
                    return true;
                }
            }
            String base_try = exe_dir.path_join(p_path.get_file());
            if (FileAccess::file_exists(base_try)) {
                PackedByteArray disk_bytes = FileAccess::get_file_as_bytes(base_try);
                if (disk_bytes.size() > 0) {
                    r_data.resize(disk_bytes.size());
                    memcpy(r_data.data(), disk_bytes.ptr(), disk_bytes.size());
                    return true;
                }
            }
        }
    }

    PackedByteArray pba = FileAccess::get_file_as_bytes(p_path);
    if (pba.size() > 0) {
        if (pba.size() >= 4 && pba[0] == 'R' && pba[1] == 'S' && pba[2] == 'C' && pba[3] == 'C') {
            ResourceLoader *rl = ResourceLoader::get_singleton();
            if (rl && rl->exists(p_path)) {
                Ref<Resource> res = rl->load(p_path);
                Ref<FontFile> ff = res;
                if (ff.is_valid()) {
                    PackedByteArray font_bytes = ff->get_data();
                    if (font_bytes.size() > 0) {
                        r_data.resize(font_bytes.size());
                        memcpy(r_data.data(), font_bytes.ptr(), font_bytes.size());
                        return true;
                    }
                }
            }
        } else {
            r_data.resize(pba.size());
            memcpy(r_data.data(), pba.ptr(), pba.size());
            return true;
        }
    }

    Ref<FileAccess> fa = FileAccess::open(p_path, FileAccess::READ);
    if (fa.is_valid() && fa->is_open()) {
        uint64_t len = fa->get_length();
        if (len > 0) {
            PackedByteArray buffer = fa->get_buffer(len);
            if (buffer.size() > 0) {
                if (buffer.size() >= 4 && buffer[0] == 'R' && buffer[1] == 'S' && buffer[2] == 'C' && buffer[3] == 'C') {
                    ResourceLoader *rl = ResourceLoader::get_singleton();
                    if (rl && rl->exists(p_path)) {
                        Ref<Resource> res = rl->load(p_path);
                        Ref<FontFile> ff = res;
                        if (ff.is_valid()) {
                            PackedByteArray font_bytes = ff->get_data();
                            if (font_bytes.size() > 0) {
                                r_data.resize(font_bytes.size());
                                memcpy(r_data.data(), font_bytes.ptr(), font_bytes.size());
                                return true;
                            }
                        }
                    }
                } else {
                    r_data.resize(buffer.size());
                    memcpy(r_data.data(), buffer.ptr(), buffer.size());
                    return true;
                }
            }
        }
    }

    CharString utf8 = p_path.utf8();
    FILE *f = fopen(utf8.get_data(), "rb");
    if (f) {
        fseek(f, 0, SEEK_END);
        long len = ftell(f);
        fseek(f, 0, SEEK_SET);
        if (len > 0) {
            r_data.resize(len);
            size_t read_bytes = fread(r_data.data(), 1, len, f);
            fclose(f);
            return read_bytes == (size_t)len;
        }
        fclose(f);
    }
    return false;
}

bool MSDFGenerator::load_font_file(const String &p_path) {
    std::vector<uint8_t> bytes;
    if (!_load_file_bytes(p_path, bytes)) {
        return false;
    }

    msdfgen::FreetypeHandle *ft = msdfgen::initializeFreetype();
    if (!ft) {
        return false;
    }
    msdfgen::FontHandle *font = msdfgen::loadFontData(ft, bytes.data(), (int)bytes.size());
    if (!font) {
        msdfgen::deinitializeFreetype(ft);
        return false;
    }
    msdfgen::destroyFont(font);
    msdfgen::deinitializeFreetype(ft);

    std::lock_guard<std::mutex> lock(data_mutex);
    primary_font_data = std::move(bytes);
    primary_font_path = p_path;
    return true;
}

bool MSDFGenerator::load_font_data(const PackedByteArray &p_data, const String &p_path) {
    if (p_data.size() == 0) {
        return false;
    }
    std::vector<uint8_t> bytes(p_data.size());
    memcpy(bytes.data(), p_data.ptr(), p_data.size());

    msdfgen::FreetypeHandle *ft = msdfgen::initializeFreetype();
    if (!ft) {
        return false;
    }
    msdfgen::FontHandle *font = msdfgen::loadFontData(ft, bytes.data(), (int)bytes.size());
    if (!font) {
        msdfgen::deinitializeFreetype(ft);
        return false;
    }
    msdfgen::destroyFont(font);
    msdfgen::deinitializeFreetype(ft);

    std::lock_guard<std::mutex> lock(data_mutex);
    primary_font_data = std::move(bytes);
    primary_font_path = p_path;
    return true;
}

bool MSDFGenerator::add_fallback_font_file(const String &p_path) {
    std::vector<uint8_t> bytes;
    if (!_load_file_bytes(p_path, bytes)) {
        return false;
    }

    msdfgen::FreetypeHandle *ft = msdfgen::initializeFreetype();
    if (!ft) {
        return false;
    }
    msdfgen::FontHandle *font = msdfgen::loadFontData(ft, bytes.data(), (int)bytes.size());
    if (!font) {
        msdfgen::deinitializeFreetype(ft);
        return false;
    }
    msdfgen::destroyFont(font);
    msdfgen::deinitializeFreetype(ft);

    std::lock_guard<std::mutex> lock(data_mutex);
    fallback_font_data.push_back(std::move(bytes));
    fallback_font_paths.push_back(p_path);
    return true;
}

bool MSDFGenerator::add_fallback_font_data(const PackedByteArray &p_data, const String &p_path) {
    if (p_data.size() == 0) {
        return false;
    }
    std::vector<uint8_t> bytes(p_data.size());
    memcpy(bytes.data(), p_data.ptr(), p_data.size());

    msdfgen::FreetypeHandle *ft = msdfgen::initializeFreetype();
    if (!ft) {
        return false;
    }
    msdfgen::FontHandle *font = msdfgen::loadFontData(ft, bytes.data(), (int)bytes.size());
    if (!font) {
        msdfgen::deinitializeFreetype(ft);
        return false;
    }
    msdfgen::destroyFont(font);
    msdfgen::deinitializeFreetype(ft);

    std::lock_guard<std::mutex> lock(data_mutex);
    fallback_font_data.push_back(std::move(bytes));
    fallback_font_paths.push_back(p_path);
    return true;
}

void MSDFGenerator::clear_fallback_fonts() {
    std::lock_guard<std::mutex> lock(data_mutex);
    fallback_font_data.clear();
    fallback_font_paths.clear();
}

void MSDFGenerator::set_unicode_ranges(const PackedInt32Array &p_codepoints) {
    std::lock_guard<std::mutex> lock(data_mutex);
    unicode_codepoints.clear();
    unicode_codepoints.reserve(p_codepoints.size());
    for (int64_t i = 0; i < p_codepoints.size(); ++i) {
        unicode_codepoints.push_back(p_codepoints[i]);
    }
}

void MSDFGenerator::configure_atlas(const Dictionary &p_config) {
    std::lock_guard<std::mutex> lock(data_mutex);
    if (p_config.has("field_type")) {
        config.field_type = (FieldType)(int)p_config["field_type"];
    }
    if (p_config.has("texture_width")) {
        config.texture_width = (int)p_config["texture_width"];
    }
    if (p_config.has("texture_height")) {
        config.texture_height = (int)p_config["texture_height"];
    }
    if (p_config.has("auto_size")) {
        config.auto_size = (bool)p_config["auto_size"];
    }
    if (p_config.has("pixel_range")) {
        config.pixel_range = (double)p_config["pixel_range"];
    }
    if (p_config.has("glyph_padding")) {
        config.glyph_padding = (int)p_config["glyph_padding"];
    }
    if (p_config.has("edge_coloring_angle")) {
        config.edge_coloring_angle = (double)p_config["edge_coloring_angle"];
    }
    if (p_config.has("miter_limit")) {
        config.miter_limit = (double)p_config["miter_limit"];
    }
    if (p_config.has("packing_method")) {
        config.packing_method = (PackingMethod)(int)p_config["packing_method"];
    }
    if (p_config.has("em_size")) {
        config.em_size = (double)p_config["em_size"];
    }
}

void MSDFGenerator::generate_async() {
    if (running.load()) {
        return;
    }

    if (worker_thread.joinable()) {
        worker_thread.join();
    }

    running.store(true);
    cancel_requested.store(false);
    progress.store(0.0f);

    worker_thread = std::thread(&MSDFGenerator::_worker_thread_func, this);
}

float MSDFGenerator::get_progress() const {
    return progress.load();
}

void MSDFGenerator::cancel() {
    cancel_requested.store(true);
}

bool MSDFGenerator::is_running() const {
    return running.load();
}

void MSDFGenerator::_emit_progress(float p_progress) {
    emit_signal("generation_progress", p_progress);
}

void MSDFGenerator::_emit_completed(const Ref<Image> &p_image, const Dictionary &p_metadata) {
    emit_signal("generation_completed", p_image, p_metadata);
}

void MSDFGenerator::_emit_failed(const String &p_error) {
    emit_signal("generation_failed", p_error);
}

void MSDFGenerator::_worker_thread_func() {
    std::vector<uint8_t> primary_bytes;
    std::vector<std::vector<uint8_t>> fallback_bytes_list;
    std::vector<int32_t> codepoints;
    Config cfg;

    {
        std::lock_guard<std::mutex> lock(data_mutex);
        primary_bytes = primary_font_data;
        fallback_bytes_list = fallback_font_data;
        codepoints = unicode_codepoints;
        cfg = config;
    }

    if (primary_bytes.empty()) {
        running.store(false);
        call_deferred("_emit_failed", "No primary font loaded.");
        return;
    }

    if (codepoints.empty()) {
        for (int32_t cp = 32; cp <= 126; ++cp) {
            codepoints.push_back(cp);
        }
    }

    msdfgen::FreetypeHandle *ft = msdfgen::initializeFreetype();
    if (!ft) {
        running.store(false);
        call_deferred("_emit_failed", "Failed to initialize FreeType.");
        return;
    }

    msdfgen::FontHandle *primary_font = msdfgen::loadFontData(ft, primary_bytes.data(), (int)primary_bytes.size());
    if (!primary_font) {
        msdfgen::deinitializeFreetype(ft);
        running.store(false);
        call_deferred("_emit_failed", "Failed to parse primary font file.");
        return;
    }

    std::vector<msdfgen::FontHandle *> fallback_fonts;
    for (const auto &fb_bytes : fallback_bytes_list) {
        msdfgen::FontHandle *fb = msdfgen::loadFontData(ft, fb_bytes.data(), (int)fb_bytes.size());
        if (fb) {
            fallback_fonts.push_back(fb);
        }
    }

    std::vector<msdf_atlas::GlyphGeometry> glyphs;
    msdf_atlas::FontGeometry primary_fg(&glyphs);
    double font_scale = cfg.em_size > 0 ? cfg.em_size : 1.0;
    if (!primary_fg.loadMetrics(primary_font, font_scale)) {
        for (auto *fb : fallback_fonts) msdfgen::destroyFont(fb);
        msdfgen::destroyFont(primary_font);
        msdfgen::deinitializeFreetype(ft);
        running.store(false);
        call_deferred("_emit_failed", "Failed to read font metrics.");
        return;
    }

    for (int32_t cp : codepoints) {
        if (cancel_requested.load()) {
            for (auto *fb : fallback_fonts) msdfgen::destroyFont(fb);
            msdfgen::destroyFont(primary_font);
            msdfgen::deinitializeFreetype(ft);
            running.store(false);
            return;
        }

        msdf_atlas::GlyphGeometry glyph;
        bool loaded = false;
        if (glyph.load(primary_font, primary_fg.getGeometryScale(), (msdfgen::unicode_t)cp, false)) {
            primary_fg.addGlyph((msdf_atlas::GlyphGeometry &&)glyph);
            loaded = true;
        } else {
            for (auto *fb : fallback_fonts) {
                if (glyph.load(fb, primary_fg.getGeometryScale(), (msdfgen::unicode_t)cp, false)) {
                    primary_fg.addGlyph((msdf_atlas::GlyphGeometry &&)glyph);
                    loaded = true;
                    break;
                }
            }
        }
    }

    primary_fg.loadKerning(primary_font);

    if (glyphs.empty()) {
        for (auto *fb : fallback_fonts) msdfgen::destroyFont(fb);
        msdfgen::destroyFont(primary_font);
        msdfgen::deinitializeFreetype(ft);
        running.store(false);
        call_deferred("_emit_failed", "No glyphs could be loaded from fonts.");
        return;
    }

    int atlas_w = cfg.texture_width;
    int atlas_h = cfg.texture_height;
    double final_scale = cfg.em_size > 0 ? cfg.em_size : 0.0;
    msdfgen::Range px_range(cfg.pixel_range);
    int spacing = (cfg.field_type == FIELD_MSDF || cfg.field_type == FIELD_MTSDF) ? 0 : -1;
    if (cfg.glyph_padding > 0) {
        spacing += cfg.glyph_padding;
    }

    if (cfg.packing_method == PACKING_MAXRECTS) {
        msdf_atlas::TightAtlasPacker packer;
        if (!cfg.auto_size && atlas_w > 0 && atlas_h > 0) {
            packer.setDimensions(atlas_w, atlas_h);
        } else {
            packer.setDimensionsConstraint(msdf_atlas::DimensionsConstraint::POWER_OF_TWO_SQUARE);
        }
        packer.setSpacing(spacing);
        if (cfg.em_size > 0) {
            packer.setScale(cfg.em_size);
        } else {
            packer.setMinimumScale(12.0);
        }
        packer.setPixelRange(px_range);
        packer.setMiterLimit(cfg.miter_limit);
        packer.setOuterPixelPadding(cfg.glyph_padding);

        int remaining = packer.pack(glyphs.data(), (int)glyphs.size());
        if (remaining > 0) {
            int fitted = (int)glyphs.size() - remaining;
            for (auto *fb : fallback_fonts) msdfgen::destroyFont(fb);
            msdfgen::destroyFont(primary_font);
            msdfgen::deinitializeFreetype(ft);
            running.store(false);
            call_deferred("_emit_failed", String("Atlas full: ") + String::num_int64(fitted) + " glyphs fit, " + String::num_int64(remaining) + " omitted. Increase resolution or enable Auto-Size.");
            return;
        } else if (remaining < 0) {
            for (auto *fb : fallback_fonts) msdfgen::destroyFont(fb);
            msdfgen::destroyFont(primary_font);
            msdfgen::deinitializeFreetype(ft);
            running.store(false);
            call_deferred("_emit_failed", "Failed to pack glyphs into atlas.");
            return;
        }
        packer.getDimensions(atlas_w, atlas_h);
        final_scale = packer.getScale();
        px_range = packer.getPixelRange();
    } else {
        msdf_atlas::GridAtlasPacker packer;
        if (!cfg.auto_size && atlas_w > 0 && atlas_h > 0) {
            packer.setDimensions(atlas_w, atlas_h);
        } else {
            packer.setDimensionsConstraint(msdf_atlas::DimensionsConstraint::POWER_OF_TWO_SQUARE);
        }
        packer.setSpacing(spacing);
        if (cfg.em_size > 0) {
            packer.setScale(cfg.em_size);
        } else {
            packer.setMinimumScale(12.0);
        }
        packer.setPixelRange(px_range);
        packer.setMiterLimit(cfg.miter_limit);
        packer.setOuterPixelPadding(cfg.glyph_padding);

        int remaining = packer.pack(glyphs.data(), (int)glyphs.size());
        if (remaining > 0) {
            int fitted = (int)glyphs.size() - remaining;
            for (auto *fb : fallback_fonts) msdfgen::destroyFont(fb);
            msdfgen::destroyFont(primary_font);
            msdfgen::deinitializeFreetype(ft);
            running.store(false);
            call_deferred("_emit_failed", String("Atlas full: ") + String::num_int64(fitted) + " glyphs fit, " + String::num_int64(remaining) + " omitted. Increase resolution or enable Auto-Size.");
            return;
        } else if (remaining < 0) {
            for (auto *fb : fallback_fonts) msdfgen::destroyFont(fb);
            msdfgen::destroyFont(primary_font);
            msdfgen::deinitializeFreetype(ft);
            running.store(false);
            call_deferred("_emit_failed", "Failed to pack glyphs into grid atlas.");
            return;
        }
        packer.getDimensions(atlas_w, atlas_h);
        final_scale = packer.getScale();
        px_range = packer.getPixelRange();
    }

    if (cfg.field_type == FIELD_MSDF || cfg.field_type == FIELD_MTSDF) {
        unsigned long long seed = 0x12345678ULL;
        for (size_t i = 0; i < glyphs.size(); ++i) {
            if (cancel_requested.load()) {
                for (auto *fb : fallback_fonts) msdfgen::destroyFont(fb);
                msdfgen::destroyFont(primary_font);
                msdfgen::deinitializeFreetype(ft);
                running.store(false);
                return;
            }
            seed = seed * 6364136223846793005ULL + 1ULL;
            glyphs[i].edgeColoring(msdfgen::edgeColoringByDistance, cfg.edge_coloring_angle, seed);
        }
    }

    int channels = 3;
    Image::Format img_fmt = Image::FORMAT_RGB8;
    if (cfg.field_type == FIELD_SDF || cfg.field_type == FIELD_PSDF) {
        channels = 1;
        img_fmt = Image::FORMAT_L8;
    } else if (cfg.field_type == FIELD_MSDF) {
        channels = 3;
        img_fmt = Image::FORMAT_RGB8;
    } else if (cfg.field_type == FIELD_MTSDF) {
        channels = 4;
        img_fmt = Image::FORMAT_RGBA8;
    }

    PackedByteArray atlas_buffer;
    int64_t total_bytes = (int64_t)atlas_w * atlas_h * channels;
    atlas_buffer.resize(total_bytes);
    memset(atlas_buffer.ptrw(), 0, total_bytes);

    msdf_atlas::GeneratorAttributes attribs;
    attribs.config.overlapSupport = true;
    attribs.scanlinePass = true;
    attribs.config.errorCorrection.mode = msdfgen::ErrorCorrectionConfig::EDGE_PRIORITY;
    attribs.config.errorCorrection.distanceCheckMode = msdfgen::ErrorCorrectionConfig::CHECK_DISTANCE_AT_EDGE;

    size_t total_glyphs = glyphs.size();
    for (size_t i = 0; i < total_glyphs; ++i) {
        if (cancel_requested.load()) {
            for (auto *fb : fallback_fonts) msdfgen::destroyFont(fb);
            msdfgen::destroyFont(primary_font);
            msdfgen::deinitializeFreetype(ft);
            running.store(false);
            return;
        }

        const msdf_atlas::GlyphGeometry &g = glyphs[i];
        if (!g.isWhitespace()) {
            int l, b, w, h;
            g.getBoxRect(l, b, w, h);
            if (w > 0 && h > 0) {
                if (channels == 1) {
                    msdfgen::Bitmap<float, 1> glyphBmp(w, h);
                    if (cfg.field_type == FIELD_SDF) {
                        msdf_atlas::sdfGenerator(glyphBmp, g, attribs);
                    } else {
                        msdf_atlas::psdfGenerator(glyphBmp, g, attribs);
                    }
                    for (int y = 0; y < h; ++y) {
                        for (int x = 0; x < w; ++x) {
                            int dest_x = l + x;
                            int dest_y = atlas_h - 1 - (b + y);
                            if (dest_x >= 0 && dest_x < atlas_w && dest_y >= 0 && dest_y < atlas_h) {
                                int64_t idx = (dest_y * atlas_w + dest_x);
                                atlas_buffer.set(idx, msdfgen::pixelFloatToByte(*glyphBmp(x, y)));
                            }
                        }
                    }
                } else if (channels == 3) {
                    msdfgen::Bitmap<float, 3> glyphBmp(w, h);
                    msdf_atlas::msdfGenerator(glyphBmp, g, attribs);
                    for (int y = 0; y < h; ++y) {
                        for (int x = 0; x < w; ++x) {
                            int dest_x = l + x;
                            int dest_y = atlas_h - 1 - (b + y);
                            if (dest_x >= 0 && dest_x < atlas_w && dest_y >= 0 && dest_y < atlas_h) {
                                int64_t idx = (dest_y * atlas_w + dest_x) * 3;
                                const float *px = glyphBmp(x, y);
                                atlas_buffer.set(idx + 0, msdfgen::pixelFloatToByte(px[0]));
                                atlas_buffer.set(idx + 1, msdfgen::pixelFloatToByte(px[1]));
                                atlas_buffer.set(idx + 2, msdfgen::pixelFloatToByte(px[2]));
                            }
                        }
                    }
                } else if (channels == 4) {
                    msdfgen::Bitmap<float, 4> glyphBmp(w, h);
                    msdf_atlas::mtsdfGenerator(glyphBmp, g, attribs);
                    for (int y = 0; y < h; ++y) {
                        for (int x = 0; x < w; ++x) {
                            int dest_x = l + x;
                            int dest_y = atlas_h - 1 - (b + y);
                            if (dest_x >= 0 && dest_x < atlas_w && dest_y >= 0 && dest_y < atlas_h) {
                                int64_t idx = (dest_y * atlas_w + dest_x) * 4;
                                const float *px = glyphBmp(x, y);
                                atlas_buffer.set(idx + 0, msdfgen::pixelFloatToByte(px[0]));
                                atlas_buffer.set(idx + 1, msdfgen::pixelFloatToByte(px[1]));
                                atlas_buffer.set(idx + 2, msdfgen::pixelFloatToByte(px[2]));
                                atlas_buffer.set(idx + 3, msdfgen::pixelFloatToByte(px[3]));
                            }
                        }
                    }
                }
            }
        }

        float p = (float)(i + 1) / (float)total_glyphs;
        progress.store(p);
        if ((i % 5 == 0) || (i + 1 == total_glyphs)) {
            call_deferred("_emit_progress", p);
        }
    }

    Ref<Image> image = Image::create_from_data(atlas_w, atlas_h, false, img_fmt, atlas_buffer);

    Dictionary metadata;
    Dictionary atlas_dict;
    const char *type_names[] = { "sdf", "psdf", "msdf", "mtsdf" };
    atlas_dict["type"] = type_names[cfg.field_type];
    atlas_dict["distanceRange"] = px_range.upper - px_range.lower;
    atlas_dict["size"] = final_scale;
    atlas_dict["width"] = atlas_w;
    atlas_dict["height"] = atlas_h;
    atlas_dict["yOrigin"] = "bottom";
    metadata["atlas"] = atlas_dict;

    Dictionary metrics_dict;
    const msdfgen::FontMetrics &fm = primary_fg.getMetrics();
    metrics_dict["emSize"] = fm.emSize;
    metrics_dict["lineHeight"] = fm.lineHeight;
    metrics_dict["ascender"] = fm.ascenderY;
    metrics_dict["descender"] = fm.descenderY;
    metrics_dict["underlineY"] = fm.underlineY;
    metrics_dict["underlineThickness"] = fm.underlineThickness;
    metadata["metrics"] = metrics_dict;

    Array glyphs_arr;
    for (const msdf_atlas::GlyphGeometry &g : glyphs) {
        Dictionary gd;
        gd["unicode"] = (int)g.getCodepoint();
        gd["advance"] = g.getAdvance();
        double pl, pb, pr, pt;
        g.getQuadPlaneBounds(pl, pb, pr, pt);
        Dictionary plane_bounds;
        plane_bounds["left"] = pl;
        plane_bounds["bottom"] = pb;
        plane_bounds["right"] = pr;
        plane_bounds["top"] = pt;
        gd["planeBounds"] = plane_bounds;

        double al, ab, ar, at;
        g.getQuadAtlasBounds(al, ab, ar, at);
        Dictionary atlas_bounds;
        atlas_bounds["left"] = al;
        atlas_bounds["bottom"] = ab;
        atlas_bounds["right"] = ar;
        atlas_bounds["top"] = at;
        gd["atlasBounds"] = atlas_bounds;

        glyphs_arr.push_back(gd);
    }
    metadata["glyphs"] = glyphs_arr;

    Array kerning_arr;
    for (const auto &kp : primary_fg.getKerning()) {
        const msdf_atlas::GlyphGeometry *glyph1 = primary_fg.getGlyph(msdfgen::GlyphIndex(kp.first.first));
        const msdf_atlas::GlyphGeometry *glyph2 = primary_fg.getGlyph(msdfgen::GlyphIndex(kp.first.second));
        if (glyph1 && glyph2 && glyph1->getCodepoint() && glyph2->getCodepoint()) {
            Dictionary kd;
            kd["unicode1"] = (int)glyph1->getCodepoint();
            kd["unicode2"] = (int)glyph2->getCodepoint();
            kd["advance"] = kp.second;
            kerning_arr.push_back(kd);
        }
    }
    metadata["kerning"] = kerning_arr;

    for (auto *fb : fallback_fonts) msdfgen::destroyFont(fb);
    msdfgen::destroyFont(primary_font);
    msdfgen::deinitializeFreetype(ft);

    progress.store(1.0f);
    running.store(false);

    call_deferred("_emit_progress", 1.0f);
    call_deferred("_emit_completed", image, metadata);
}

}
