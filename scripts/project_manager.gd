class_name MSDFProjectManager
extends RefCounted

const EXTENSION_PRIMARY = "msdfproj"
const EXTENSION_COMPAT = "msdfatlas"
const FORMAT_IDENTIFIER = "msdf_atlas_project"
const CURRENT_VERSION = 1

static func color_to_array(c: Color) -> Array:
	return [snappedf(c.r, 0.0001), snappedf(c.g, 0.0001), snappedf(c.b, 0.0001), snappedf(c.a, 0.0001)]

static func array_to_color(arr: Array, default_color: Color = Color.WHITE) -> Color:
	if arr.size() >= 4:
		return Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
	elif arr.size() == 3:
		return Color(float(arr[0]), float(arr[1]), float(arr[2]), 1.0)
	return default_color

static func vec2_to_array(v: Vector2) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01)]

static func array_to_vec2(arr: Array, default_vec: Vector2 = Vector2.ZERO) -> Vector2:
	if arr.size() >= 2:
		return Vector2(float(arr[0]), float(arr[1]))
	return default_vec

static func make_relative_path(target_path: String, base_dir: String) -> String:
	if target_path.begins_with("res://") or target_path.begins_with("user://"):
		return target_path
	if base_dir.is_empty():
		return target_path
	var norm_target := target_path.replace("\\", "/")
	var norm_base := base_dir.replace("\\", "/")
	if not norm_base.ends_with("/"):
		norm_base += "/"
	if norm_target.begins_with(norm_base):
		return norm_target.substr(norm_base.length())
	return norm_target.get_file()

static func resolve_font_path(saved_path: String, rel_path: String, project_dir: String) -> String:
	if FileAccess.file_exists(saved_path):
		return saved_path
	if not project_dir.is_empty():
		if not rel_path.is_empty():
			var resolved_rel := project_dir.path_join(rel_path)
			if FileAccess.file_exists(resolved_rel):
				return resolved_rel
		var filename_only := project_dir.path_join(saved_path.get_file())
		if FileAccess.file_exists(filename_only):
			return filename_only
	return saved_path

static func build_project_dict(
	primary_font: String,
	fallback_fonts: Array[String],
	codepoints: PackedInt32Array,
	custom_ranges: Array[Vector2i],
	atlas_cfg: Dictionary,
	shader_params: Dictionary,
	preview_data: Dictionary,
	project_dir: String = ""
) -> Dictionary:
	var root: Dictionary = {}
	root["format"] = FORMAT_IDENTIFIER
	root["version"] = CURRENT_VERSION
	root["app"] = "MSDF Atlas Studio"
	root["timestamp"] = Time.get_datetime_string_from_system()

	var fonts_dict: Dictionary = {}
	fonts_dict["primary_path"] = primary_font
	fonts_dict["primary_relative"] = make_relative_path(primary_font, project_dir)
	var fb_arr: Array = []
	for fb in fallback_fonts:
		fb_arr.append({
			"path": fb,
			"relative": make_relative_path(fb, project_dir)
		})
	fonts_dict["fallbacks"] = fb_arr
	root["fonts"] = fonts_dict

	var charset_dict: Dictionary = {}
	var cp_list: Array = []
	for cp in codepoints:
		cp_list.append(cp)
	charset_dict["codepoints"] = cp_list

	var rng_list: Array = []
	for r in custom_ranges:
		rng_list.append({"from": r.x, "to": r.y})
	charset_dict["custom_ranges"] = rng_list
	root["charset"] = charset_dict

	root["atlas_config"] = atlas_cfg.duplicate(true)

	var sp_dict: Dictionary = {}
	sp_dict["text_color"] = color_to_array(shader_params.get("text_color", Color.WHITE))
	sp_dict["outline_color"] = color_to_array(shader_params.get("outline_color", Color.BLACK))
	sp_dict["outline_thickness"] = shader_params.get("outline_thickness", 0.0)
	sp_dict["outline_inward"] = shader_params.get("outline_inward", true)
	sp_dict["shadow_color"] = color_to_array(shader_params.get("shadow_color", Color(0, 0, 0, 0.5)))
	sp_dict["shadow_distance"] = shader_params.get("shadow_distance", 4.24)
	sp_dict["shadow_angle"] = shader_params.get("shadow_angle", 45.0)
	sp_dict["shadow_offset"] = vec2_to_array(shader_params.get("shadow_offset", Vector2(3, 3)))
	sp_dict["shadow_softness"] = shader_params.get("shadow_softness", 0.03)
	sp_dict["px_range"] = shader_params.get("px_range", 4.0)
	sp_dict["field_type"] = shader_params.get("field_type", 2)
	root["shader_params"] = sp_dict

	root["preview"] = preview_data.duplicate(true)

	return root

static func save_project(file_path: String, project_dict: Dictionary) -> Error:
	var final_path := file_path
	var ext := final_path.get_extension().to_lower()
	if ext != EXTENSION_PRIMARY and ext != EXTENSION_COMPAT and ext != "glyphproj" and ext != "glyphforge":
		final_path += "." + EXTENSION_PRIMARY

	var json_str := JSON.stringify(project_dict, "  ")
	var file := FileAccess.open(final_path, FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()

	file.store_string(json_str)
	file.close()
	return OK

static func load_project(file_path: String) -> Dictionary:
	var result: Dictionary = {
		"error": OK,
		"error_message": "",
		"data": {}
	}

	if not FileAccess.file_exists(file_path):
		result["error"] = ERR_FILE_NOT_FOUND
		result["error_message"] = "Project file does not exist: %s" % file_path
		return result

	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		result["error"] = FileAccess.get_open_error()
		result["error_message"] = "Cannot open project file: %s" % file_path
		return result

	var json_str := file.get_as_text()
	file.close()

	var test_json_conv := JSON.new()
	var parse_err := test_json_conv.parse(json_str)
	if parse_err != OK:
		result["error"] = parse_err
		result["error_message"] = "JSON parse error: %s at line %d" % [test_json_conv.get_error_message(), test_json_conv.get_error_line()]
		return result

	var raw_data: Variant = test_json_conv.data
	if typeof(raw_data) != TYPE_DICTIONARY:
		result["error"] = ERR_INVALID_DATA
		result["error_message"] = "Invalid project format: root is not a dictionary."
		return result

	var dict: Dictionary = raw_data
	var project_dir: String = file_path.get_base_dir()

	var fonts_dict: Dictionary = dict.get("fonts", {})
	var primary_path: String = fonts_dict.get("primary_path", "")
	var primary_rel: String = fonts_dict.get("primary_relative", "")
	dict["resolved_primary_font"] = resolve_font_path(primary_path, primary_rel, project_dir)

	var resolved_fallbacks: Array[String] = []
	var fb_arr: Array = fonts_dict.get("fallbacks", [])
	for item in fb_arr:
		if item is Dictionary:
			var p: String = item.get("path", "")
			var rel: String = item.get("relative", "")
			resolved_fallbacks.append(resolve_font_path(p, rel, project_dir))
		elif item is String:
			resolved_fallbacks.append(resolve_font_path(item, "", project_dir))
	dict["resolved_fallback_fonts"] = resolved_fallbacks

	var sp_dict: Dictionary = dict.get("shader_params", {})
	if not sp_dict.is_empty():
		var parsed_sp: Dictionary = {}
		parsed_sp["text_color"] = array_to_color(sp_dict.get("text_color", [1, 1, 1, 1]), Color.WHITE)
		parsed_sp["outline_color"] = array_to_color(sp_dict.get("outline_color", [0, 0, 0, 1]), Color.BLACK)
		parsed_sp["outline_thickness"] = float(sp_dict.get("outline_thickness", 0.0))
		parsed_sp["outline_inward"] = bool(sp_dict.get("outline_inward", true))
		parsed_sp["shadow_color"] = array_to_color(sp_dict.get("shadow_color", [0, 0, 0, 0.5]), Color(0, 0, 0, 0.5))
		var s_off := array_to_vec2(sp_dict.get("shadow_offset", [3, 3]), Vector2(3, 3))
		var s_dist: float = float(sp_dict.get("shadow_distance", s_off.length()))
		var s_ang: float = float(sp_dict.get("shadow_angle", rad_to_deg(s_off.angle()) if s_off.length() > 0.001 else 45.0))
		if s_ang < 0.0:
			s_ang += 360.0
		parsed_sp["shadow_distance"] = s_dist
		parsed_sp["shadow_angle"] = s_ang
		parsed_sp["shadow_offset"] = s_off
		parsed_sp["shadow_softness"] = float(sp_dict.get("shadow_softness", 0.03))
		parsed_sp["px_range"] = float(sp_dict.get("px_range", 4.0))
		parsed_sp["field_type"] = int(sp_dict.get("field_type", 2))
		dict["parsed_shader_params"] = parsed_sp

	result["data"] = dict
	return result
