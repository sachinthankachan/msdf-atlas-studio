#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <vector>
#include <string>
#include <thread>
#include <atomic>
#include <mutex>

namespace godot {

class MSDFGenerator : public RefCounted {
    GDCLASS(MSDFGenerator, RefCounted);

public:
    enum FieldType {
        FIELD_SDF = 0,
        FIELD_PSDF = 1,
        FIELD_MSDF = 2,
        FIELD_MTSDF = 3
    };

    enum PackingMethod {
        PACKING_MAXRECTS = 0,
        PACKING_SHELF = 1
    };

    struct Config {
        FieldType field_type = FIELD_MSDF;
        int texture_width = 1024;
        int texture_height = 1024;
        bool auto_size = false;
        double pixel_range = 4.0;
        int glyph_padding = 2;
        double edge_coloring_angle = 3.0;
        double miter_limit = 1.0;
        PackingMethod packing_method = PACKING_MAXRECTS;
        double em_size = -1.0; // zero or negative means automatic scaling
    };

    MSDFGenerator();
    ~MSDFGenerator();

    bool load_font_file(const String &p_path);
    bool load_font_data(const PackedByteArray &p_data, const String &p_path = String());
    bool add_fallback_font_file(const String &p_path);
    bool add_fallback_font_data(const PackedByteArray &p_data, const String &p_path = String());
    void clear_fallback_fonts();
    void set_unicode_ranges(const PackedInt32Array &p_codepoints);
    void configure_atlas(const Dictionary &p_config);
    void generate_async();
    float get_progress() const;
    void cancel();
    bool is_running() const;

    void _emit_progress(float p_progress);
    void _emit_completed(const Ref<Image> &p_image, const Dictionary &p_metadata);
    void _emit_failed(const String &p_error);

protected:
    static void _bind_methods();

private:
    std::vector<uint8_t> primary_font_data;
    String primary_font_path;
    std::vector<std::vector<uint8_t>> fallback_font_data;
    std::vector<String> fallback_font_paths;

    std::vector<int32_t> unicode_codepoints;
    Config config;

    std::thread worker_thread;
    std::atomic<bool> running{false};
    std::atomic<bool> cancel_requested{false};
    std::atomic<float> progress{0.0f};
    mutable std::mutex data_mutex;

    void _worker_thread_func();
    static bool _load_file_bytes(const String &p_path, std::vector<uint8_t> &r_data);
};

}

VARIANT_ENUM_CAST(godot::MSDFGenerator::FieldType);
VARIANT_ENUM_CAST(godot::MSDFGenerator::PackingMethod);
