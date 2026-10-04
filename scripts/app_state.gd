extends Node

const KerningExtractor = preload("res://scripts/kerning_extractor.gd")

signal font_loaded(path: String, is_primary: bool)
signal generation_started()
signal generation_progress(ratio: float)
signal generation_completed(image: Image, metadata: Dictionary)
signal generation_failed(error_message: String)
signal glyph_selected(glyph_data: Dictionary)
signal shader_params_changed()
signal status_message_updated(message: String)
signal codepoints_changed(count: int)
signal generation_cancelled()
signal project_loaded(path: String)

var generator = null
var current_project_path: String = ""
var primary_font_path: String = ""
var fallback_font_paths: Array[String] = []

var selected_codepoints: PackedInt32Array = PackedInt32Array()
var atlas_config: Dictionary = {
	"field_type": 2,
	"texture_width": 1024,
	"texture_height": 1024,
	"auto_size": false,
	"pixel_range": 4.0,
	"glyph_padding": 2,
	"edge_coloring_angle": 3.0,
	"miter_limit": 1.0,
	"packing_method": 0,
	"em_size": -1.0
}

var current_image: Image = null
var current_texture: ImageTexture = null
var current_metadata: Dictionary = {}
var selected_glyph: Dictionary = {}

var shader_params: Dictionary = {
	"text_color": Color(1.0, 1.0, 1.0, 1.0),
	"outline_color": Color(0.0, 0.0, 0.0, 1.0),
	"outline_thickness": 0.0,
	"shadow_color": Color(0.0, 0.0, 0.0, 0.5),
	"shadow_offset": Vector2(3.0, 3.0),
	"shadow_softness": 0.03,
	"px_range": 4.0,
	"field_type": 2
}

var generation_start_time: int = 0
var last_generation_duration_ms: int = 0

func _init() -> void:
	set_preset_ascii()
	_init_generator()

func _init_generator() -> void:
	if ClassDB.class_exists("MSDFGenerator"):
		generator = ClassDB.instantiate("MSDFGenerator")
		generator.generation_progress.connect(_on_generation_progress)
		generator.generation_completed.connect(_on_generation_completed)
		generator.generation_failed.connect(_on_generation_failed)
	else:
		push_warning("MSDFGenerator GDExtension class not yet loaded into engine runtime.")

func set_preset_ascii() -> void:
	var cp_set: Dictionary = {}
	for cp in range(32, 127):
		cp_set[cp] = true
	_update_codepoints_from_set(cp_set)

func set_preset_latin1_supplement() -> void:
	var cp_set: Dictionary = {}
	for cp in selected_codepoints:
		cp_set[cp] = true
	for cp in range(160, 256):
		cp_set[cp] = true
	_update_codepoints_from_set(cp_set)

func remove_range(start_cp: int, end_cp: int) -> void:
	var cp_set: Dictionary = {}
	for cp in selected_codepoints:
		if cp < start_cp or cp > end_cp:
			cp_set[cp] = true
	_update_codepoints_from_set(cp_set)

func add_range(start_cp: int, end_cp: int) -> void:
	var cp_set: Dictionary = {}
	for cp in selected_codepoints:
		cp_set[cp] = true
	for cp in range(start_cp, end_cp + 1):
		cp_set[cp] = true
	_update_codepoints_from_set(cp_set)

func _update_codepoints_from_set(cp_set: Dictionary) -> void:
	var arr: Array = cp_set.keys()
	arr.sort()
	selected_codepoints = PackedInt32Array(arr)
	codepoints_changed.emit(selected_codepoints.size())

func _read_font_bytes(path: String) -> PackedByteArray:
	if path.is_empty():
		return PackedByteArray()

	# 1. If res:// path, try loading through Godot ResourceLoader as FontFile first
	if path.begins_with("res://"):
		if ResourceLoader.exists(path):
			var res = ResourceLoader.load(path)
			if res is FontFile:
				var data: PackedByteArray = (res as FontFile).data
				if not data.is_empty():
					return data

	# 2. Try direct read via FileAccess
	if FileAccess.file_exists(path):
		var bytes := FileAccess.get_file_as_bytes(path)
		if not bytes.is_empty():
			# If file starts with Godot's binary resource signature RSCC, decompress via ResourceLoader
			if bytes.size() >= 4 and bytes[0] == 0x52 and bytes[1] == 0x53 and bytes[2] == 0x43 and bytes[3] == 0x43:
				if ResourceLoader.exists(path):
					var res = ResourceLoader.load(path)
					if res is FontFile:
						var data: PackedByteArray = (res as FontFile).data
						if not data.is_empty():
							return data
			return bytes

	# 3. Bundled resource fallback on exported standalone releases (check directory of executable)
	if path.begins_with("res://"):
		var rel_sub := path.trim_prefix("res://")
		var exe_dir := OS.get_executable_path().get_base_dir()
		var disk_candidate := exe_dir.path_join(rel_sub)
		if FileAccess.file_exists(disk_candidate):
			return FileAccess.get_file_as_bytes(disk_candidate)
		var base_candidate := exe_dir.path_join(path.get_file())
		if FileAccess.file_exists(base_candidate):
			return FileAccess.get_file_as_bytes(base_candidate)

	return PackedByteArray()

func load_primary_font(path: String) -> bool:
	if not generator:
		_init_generator()
	if not generator:
		generation_failed.emit("GDExtension MSDFGenerator not initialized.")
		return false

	var font_bytes := _read_font_bytes(path)
	var ok: bool = false
	if not font_bytes.is_empty() and generator.has_method("load_font_data"):
		ok = generator.load_font_data(font_bytes, path)
	else:
		ok = generator.load_font_file(path)

	if ok:
		primary_font_path = path
		font_loaded.emit(path, true)
		status_message_updated.emit("Primary font loaded: " + path.get_file())
	else:
		generation_failed.emit("Failed to load primary font: " + path.get_file())
	return ok

func add_fallback_font(path: String) -> bool:
	if not generator:
		_init_generator()
	if not generator:
		return false

	var font_bytes := _read_font_bytes(path)
	var ok: bool = false
	if not font_bytes.is_empty() and generator.has_method("add_fallback_font_data"):
		ok = generator.add_fallback_font_data(font_bytes, path)
	else:
		ok = generator.add_fallback_font_file(path)

	if ok:
		fallback_font_paths.append(path)
		font_loaded.emit(path, false)
		status_message_updated.emit("Fallback font added: " + path.get_file())
	return ok

func clear_fallbacks() -> void:
	fallback_font_paths.clear()
	if generator and generator.has_method("clear_fallback_fonts"):
		generator.clear_fallback_fonts()

func start_generation() -> void:
	if not generator:
		_init_generator()
	if not generator:
		generation_failed.emit("GDExtension MSDFGenerator not initialized.")
		return
	
	if primary_font_path.is_empty():
		generation_failed.emit("No primary font loaded. Please select a TTF or OTF font.")
		return
	
	if selected_codepoints.is_empty():
		set_preset_ascii()
	
	generator.set_unicode_ranges(selected_codepoints)
	generator.configure_atlas(atlas_config)
	
	generation_start_time = Time.get_ticks_msec()
	generation_started.emit()
	status_message_updated.emit("Generating MSDF atlas on background thread...")
	generator.generate_async()

func cancel_generation() -> void:
	if generator and generator.is_running():
		generator.cancel()
		generation_cancelled.emit()
		status_message_updated.emit("Generation cancelled.")

func _on_generation_progress(ratio: float) -> void:
	generation_progress.emit(ratio)

func _on_generation_completed(image: Image, metadata: Dictionary) -> void:
	last_generation_duration_ms = Time.get_ticks_msec() - generation_start_time
	current_image = image
	current_texture = ImageTexture.create_from_image(image)

	# make sure kerning pairs exist and use valid unicode values
	var kerning_arr: Array = metadata.get("kerning", [])
	var needs_extraction: bool = false
	if kerning_arr.is_empty():
		needs_extraction = true
	else:
		var first_k: Dictionary = kerning_arr[0]
		var u1: int = first_k.get("unicode1", 0)
		if u1 < 32:
			needs_extraction = true

	if needs_extraction and not primary_font_path.is_empty():
		var extracted: Array[Dictionary] = KerningExtractor.extract_kerning(primary_font_path, selected_codepoints)
		if not extracted.is_empty():
			metadata["kerning"] = extracted

	current_metadata = metadata

	var atlas_dict: Dictionary = metadata.get("atlas", {})
	var dr: float = atlas_dict.get("distanceRange", 4.0)
	shader_params["px_range"] = dr
	shader_params["field_type"] = atlas_config["field_type"]

	var kerning_count: int = metadata.get("kerning", []).size()
	generation_completed.emit(image, metadata)
	status_message_updated.emit("Atlas generated in %d ms (%dx%d, %d glyphs, %d kerning pairs)" % [
		last_generation_duration_ms,
		atlas_dict.get("width", 0),
		atlas_dict.get("height", 0),
		metadata.get("glyphs", []).size(),
		kerning_count
	])

func restore_atlas_cache(image: Image, metadata: Dictionary) -> void:
	current_image = image
	current_texture = ImageTexture.create_from_image(image)
	current_metadata = metadata

	var atlas_dict: Dictionary = metadata.get("atlas", {})
	var dr: float = atlas_dict.get("distanceRange", 4.0)
	shader_params["px_range"] = dr
	shader_params["field_type"] = atlas_config.get("field_type", 2)

	var kerning_count: int = metadata.get("kerning", []).size()
	generation_completed.emit(image, metadata)
	status_message_updated.emit("Restored cached atlas (%dx%d, %d glyphs, %d kerning pairs)" % [
		atlas_dict.get("width", 0),
		atlas_dict.get("height", 0),
		metadata.get("glyphs", []).size(),
		kerning_count
	])

func _on_generation_failed(error_msg: String) -> void:
	generation_failed.emit(error_msg)
	status_message_updated.emit("Error: " + error_msg)

func select_glyph_by_unicode(unicode: int) -> void:
	selected_glyph = {}
	var glyphs: Array = current_metadata.get("glyphs", [])
	for g in glyphs:
		if g.get("unicode", 0) == unicode:
			selected_glyph = g
			break
	if selected_glyph.is_empty():
		selected_glyph = {"unicode": unicode, "missing": true}
	glyph_selected.emit(selected_glyph)

func update_shader_param(param_name: String, value: Variant) -> void:
	shader_params[param_name] = value
	shader_params_changed.emit()

func reset_project() -> void:
	current_project_path = ""
	set_preset_ascii()
	atlas_config = {
		"field_type": 2,
		"texture_width": 1024,
		"texture_height": 1024,
		"auto_size": false,
		"pixel_range": 4.0,
		"glyph_padding": 2,
		"edge_coloring_angle": 3.0,
		"miter_limit": 1.0,
		"packing_method": 0,
		"em_size": -1.0
	}
	shader_params = {
		"text_color": Color(1.0, 1.0, 1.0, 1.0),
		"outline_color": Color(0.0, 0.0, 0.0, 1.0),
		"outline_thickness": 0.0,
		"shadow_color": Color(0.0, 0.0, 0.0, 0.5),
		"shadow_offset": Vector2(3.0, 3.0),
		"shadow_softness": 0.03,
		"px_range": 4.0,
		"field_type": 2
	}
	clear_fallbacks()
	var default_font := "res://assets/fonts/DejaVuSans.ttf"
	if FileAccess.file_exists(default_font):
		load_primary_font(default_font)
	else:
		primary_font_path = ""
	selected_glyph = {}
	shader_params_changed.emit()
	status_message_updated.emit("New project initialized.")

func apply_project_dict(dict: Dictionary, file_path: String) -> void:
	current_project_path = file_path

	clear_fallbacks()
	var font_to_load: String = dict.get("resolved_primary_font", "")
	if not font_to_load.is_empty() and FileAccess.file_exists(font_to_load):
		load_primary_font(font_to_load)

	var fb_to_load: Array = dict.get("resolved_fallback_fonts", [])
	for fb in fb_to_load:
		if FileAccess.file_exists(fb):
			add_fallback_font(fb)

	var charset_dict: Dictionary = dict.get("charset", {})
	var cp_list: Array = charset_dict.get("codepoints", [])
	if not cp_list.is_empty():
		var cp_set: Dictionary = {}
		for cp in cp_list:
			cp_set[int(cp)] = true
		_update_codepoints_from_set(cp_set)

	var cfg: Dictionary = dict.get("atlas_config", {})
	if not cfg.is_empty():
		atlas_config.merge(cfg, true)

	var sp: Dictionary = dict.get("parsed_shader_params", {})
	if not sp.is_empty():
		shader_params.merge(sp, true)
		shader_params_changed.emit()

	project_loaded.emit(file_path)
	status_message_updated.emit("Project loaded: %s" % file_path.get_file())
