class_name GodotResourceExporter
extends RefCounted

static func export_font_resource(path: String, metadata: Dictionary, atlas_image: Image, shader_params: Dictionary = {}) -> Error:
	var atlas: Dictionary = metadata.get("atlas", {})
	var metrics: Dictionary = metadata.get("metrics", {})
	var glyphs: Array = metadata.get("glyphs", [])
	var kerning: Array = metadata.get("kerning", [])

	var font_file: FontFile = FontFile.new()
	font_file.multichannel_signed_distance_field = (atlas.get("type", "msdf") == "msdf" or atlas.get("type", "msdf") == "mtsdf")
	font_file.msdf_pixel_range = int(round(atlas.get("distanceRange", 4.0)))
	var font_size: int = int(round(atlas.get("size", 32.0)))
	if font_size <= 0: font_size = 32
	font_file.msdf_size = font_size

	var _tex_width: int = atlas.get("width", 1024)
	var tex_height: int = atlas.get("height", 1024)

	var em_size: float = metrics.get("emSize", 1.0)
	if em_size <= 0.0: em_size = 1.0
	var scale_factor: float = float(font_size) / em_size

	var ascender: float = metrics.get("ascender", 0.8) * scale_factor
	var descender: float = metrics.get("descender", -0.2) * scale_factor
	
	font_file.set_cache_ascent(0, font_size, ascender)
	font_file.set_cache_descent(0, font_size, abs(descender))
	font_file.set_cache_underline_position(0, font_size, metrics.get("underlineY", -0.1) * scale_factor)
	font_file.set_cache_underline_thickness(0, font_size, metrics.get("underlineThickness", 0.05) * scale_factor)

	if atlas_image:
		font_file.set_texture_image(0, Vector2i(font_size, 0), 0, atlas_image)

	for g in glyphs:
		var unicode: int = g.get("unicode", 0)
		var advance: float = g.get("advance", 0.0) * font_size
		var ab: Dictionary = g.get("atlasBounds", {})
		var pb: Dictionary = g.get("planeBounds", {})

		# godot bitmap font caches use unicode codepoints directly as glyph indices
		var glyph_idx: int = unicode
		font_file.set_glyph_advance(0, font_size, glyph_idx, Vector2(advance, 0))

		if ab.has("left") and ab.has("right"):
			var gw: float = ab["right"] - ab["left"]
			var gh: float = ab["top"] - ab["bottom"]
			var gx: float = ab["left"]
			var gy: float = tex_height - ab["top"]

			font_file.set_glyph_size(0, Vector2i(font_size, 0), glyph_idx, Vector2(gw, gh))
			font_file.set_glyph_uv_rect(0, Vector2i(font_size, 0), glyph_idx, Rect2(gx, gy, gw, gh))
			font_file.set_glyph_texture_idx(0, Vector2i(font_size, 0), glyph_idx, 0)

			if pb.has("left") and pb.has("top"):
				var x_off: float = pb["left"] * font_size
				# vertical offset points down from the baseline so top bounds become negative
				var y_off: float = -pb["top"] * font_size
				font_file.set_glyph_offset(0, Vector2i(font_size, 0), glyph_idx, Vector2(x_off, y_off))

	for k in kerning:
		var u1: int = k.get("unicode1", 0)
		var u2: int = k.get("unicode2", 0)
		var adv: float = k.get("advance", 0.0) * font_size
		font_file.set_kerning(0, font_size, Vector2i(u1, u2), Vector2(adv, 0))

	var save_err: Error = ResourceSaver.save(font_file, path)
	if save_err != OK:
		return save_err

	if not shader_params.is_empty():
		var label_settings: LabelSettings = LabelSettings.new()
		label_settings.font = font_file
		label_settings.font_size = font_size
		label_settings.font_color = shader_params.get("text_color", Color.WHITE)

		var outline_thick: float = shader_params.get("outline_thickness", 0.0)
		if outline_thick > 0.001:
			label_settings.outline_size = max(1, int(round(outline_thick * font_size * 0.25)))
			label_settings.outline_color = shader_params.get("outline_color", Color.BLACK)

		var shadow_col: Color = shader_params.get("shadow_color", Color(0, 0, 0, 0))
		if shadow_col.a > 0.001:
			label_settings.shadow_color = shadow_col
			var s_off: Vector2 = Vector2(3.0, 3.0)
			if shader_params.has("shadow_distance") and shader_params.has("shadow_angle"):
				var s_dist: float = float(shader_params.get("shadow_distance", 4.24))
				var s_ang: float = float(shader_params.get("shadow_angle", 45.0))
				var s_rad: float = deg_to_rad(s_ang)
				s_off = Vector2(cos(s_rad), sin(s_rad)) * s_dist
			else:
				s_off = shader_params.get("shadow_offset", Vector2(3.0, 3.0))
			label_settings.shadow_offset = s_off
			var s_soft: float = shader_params.get("shadow_softness", 0.03)
			label_settings.shadow_size = max(1, int(round(s_soft * font_size * 2.0)))

		var out_dir: String = path.get_base_dir()
		var base_name: String = path.get_file().get_basename()
		var ls_path: String = out_dir.path_join(base_name + "_label_settings.tres")
		ResourceSaver.save(label_settings, ls_path)

		var shader_res = load("res://shaders/msdf_text_renderer.gdshader")
		if shader_res:
			var mat: ShaderMaterial = ShaderMaterial.new()
			mat.shader = shader_res
			mat.set_shader_parameter("is_shadow", false)
			mat.set_shader_parameter("field_type", atlas.get("type_code", 2) if atlas.has("type_code") else 2)
			mat.set_shader_parameter("px_range", atlas.get("distanceRange", 4.0))
			mat.set_shader_parameter("text_color", shader_params.get("text_color", Color.WHITE))
			mat.set_shader_parameter("outline_color", shader_params.get("outline_color", Color.BLACK))
			mat.set_shader_parameter("outline_thickness", shader_params.get("outline_thickness", 0.0))
			mat.set_shader_parameter("outline_inward", shader_params.get("outline_inward", true))
			mat.set_shader_parameter("shadow_color", shader_params.get("shadow_color", Color(0, 0, 0, 0.5)))
			mat.set_shader_parameter("shadow_softness", shader_params.get("shadow_softness", 0.03))
			var mat_path: String = out_dir.path_join(base_name + "_material.tres")
			ResourceSaver.save(mat, mat_path)

	return OK
