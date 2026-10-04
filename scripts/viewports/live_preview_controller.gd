class_name LivePreviewController
extends Control

@export var app_state: Node = null

var preview_text: String = "The quick brown fox jumps over the lazy dog.\n0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz !@#$%^&*()_+"
var font_size_pt: float = 48.0
var line_spacing_factor: float = 1.25

var glyph_lookup: Dictionary = {}
var kerning_lookup: Dictionary = {}
var kerning_enabled: bool = true
var atlas_width: float = 1024.0
var atlas_height: float = 1024.0
var em_size: float = 1000.0
var line_height_em: float = 1.15
var ascender_em: float = 0.89

var shadow_layer: Control = null
var text_layer: Control = null
var shadow_material: ShaderMaterial = null
var text_material: ShaderMaterial = null
var shadow_mesh: ArrayMesh = null
var text_mesh: ArrayMesh = null
var placeholder_label: Label = null

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	placeholder_label = get_node_or_null("../../PlaceholderLabel")
	if not placeholder_label:
		placeholder_label = Label.new()
		placeholder_label.text = "Generate or load an MSDF atlas to preview live text."
		placeholder_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7, 0.85))
		placeholder_label.add_theme_font_size_override("font_size", 16)
		placeholder_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		placeholder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		placeholder_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		placeholder_label.use_parent_material = false
		add_child(placeholder_label)

	var shader_res = load("res://shaders/msdf_text_renderer.gdshader")

	shadow_material = ShaderMaterial.new()
	shadow_material.shader = shader_res
	shadow_material.set_shader_parameter("is_shadow", true)

	text_material = ShaderMaterial.new()
	text_material.shader = shader_res
	text_material.set_shader_parameter("is_shadow", false)

	shadow_layer = Control.new()
	shadow_layer.name = "ShadowLayer"
	shadow_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	shadow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shadow_layer.material = shadow_material
	shadow_layer.draw.connect(_on_shadow_layer_draw)
	add_child(shadow_layer)

	text_layer = Control.new()
	text_layer.name = "TextLayer"
	text_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	text_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	text_layer.material = text_material
	text_layer.draw.connect(_on_text_layer_draw)
	add_child(text_layer)

	if not app_state:
		if get_node_or_null("/root/AppState"):
			app_state = get_node("/root/AppState")
		elif AppState:
			app_state = AppState

	if app_state:
		app_state.generation_completed.connect(_on_generation_completed)
		app_state.shader_params_changed.connect(_on_shader_params_changed)
		if not app_state.current_metadata.is_empty():
			_build_lookups(app_state.current_metadata)

	visibility_changed.connect(_on_visibility_changed)

	_update_shader_uniforms()
	rebuild_text()

func _on_visibility_changed() -> void:
	if is_visible_in_tree() and app_state:
		if not app_state.current_metadata.is_empty() and glyph_lookup.is_empty():
			_build_lookups(app_state.current_metadata)
		_update_shader_uniforms()
		rebuild_text()

func set_preview_text(p_text: String) -> void:
	preview_text = p_text
	rebuild_text()

func set_font_size(p_pt: float) -> void:
	font_size_pt = clamp(p_pt, 6.0, 256.0)
	rebuild_text()

func set_kerning_enabled(enabled: bool) -> void:
	kerning_enabled = enabled
	rebuild_text()

func _on_generation_completed(_image: Image, metadata: Dictionary) -> void:
	_build_lookups(metadata)
	_update_shader_uniforms()
	rebuild_text()

func _on_shader_params_changed() -> void:
	_update_shader_uniforms()
	rebuild_text()

func _build_lookups(metadata: Dictionary) -> void:
	glyph_lookup.clear()
	kerning_lookup.clear()

	var atlas_dict: Dictionary = metadata.get("atlas", {})
	atlas_width = atlas_dict.get("width", 1024.0)
	atlas_height = atlas_dict.get("height", 1024.0)
	if atlas_width <= 0: atlas_width = 1024.0
	if atlas_height <= 0: atlas_height = 1024.0

	var metrics_dict: Dictionary = metadata.get("metrics", {})
	em_size = metrics_dict.get("emSize", 1000.0)
	if em_size <= 0: em_size = 1000.0
	line_height_em = metrics_dict.get("lineHeight", 1.15) / em_size
	ascender_em = metrics_dict.get("ascender", 0.89) / em_size

	var glyphs: Array = metadata.get("glyphs", [])
	for g in glyphs:
		var u: int = g.get("unicode", 0)
		glyph_lookup[u] = g

	var kerning: Array = metadata.get("kerning", [])
	for k in kerning:
		var u1: int = k.get("unicode1", 0)
		var u2: int = k.get("unicode2", 0)
		var adv: float = k.get("advance", 0.0)
		kerning_lookup[Vector2i(u1, u2)] = adv

func _update_shader_uniforms() -> void:
	if not shadow_material or not text_material:
		return

	var cur_tex: Texture2D = null
	if app_state and app_state.current_texture:
		cur_tex = app_state.current_texture

	var sp: Dictionary = app_state.shader_params if app_state else {}
	var ft: int = sp.get("field_type", 2)
	var px_r: float = sp.get("px_range", 4.0)
	var t_col: Color = sp.get("text_color", Color.WHITE)
	var o_col: Color = sp.get("outline_color", Color.BLACK)
	var o_thick: float = sp.get("outline_thickness", 0.0)
	var s_col: Color = sp.get("shadow_color", Color(0, 0, 0, 0))
	var s_soft: float = sp.get("shadow_softness", 0.03)

	text_material.set_shader_parameter("is_shadow", false)
	text_material.set_shader_parameter("field_type", ft)
	text_material.set_shader_parameter("px_range", px_r)
	text_material.set_shader_parameter("text_color", t_col)
	text_material.set_shader_parameter("outline_color", o_col)
	text_material.set_shader_parameter("outline_thickness", o_thick)
	if cur_tex:
		text_material.set_shader_parameter("msdf_texture", cur_tex)

	shadow_material.set_shader_parameter("is_shadow", true)
	shadow_material.set_shader_parameter("field_type", ft)
	shadow_material.set_shader_parameter("px_range", px_r)
	shadow_material.set_shader_parameter("shadow_color", s_col)
	shadow_material.set_shader_parameter("shadow_softness", s_soft)
	shadow_material.set_shader_parameter("outline_thickness", o_thick)
	if cur_tex:
		shadow_material.set_shader_parameter("msdf_texture", cur_tex)

func rebuild_text() -> void:
	if glyph_lookup.is_empty() or not app_state or not app_state.current_texture:
		if placeholder_label:
			placeholder_label.visible = true
		if shadow_layer:
			shadow_layer.visible = false
		if text_layer:
			text_layer.visible = false
		return

	if placeholder_label:
		placeholder_label.visible = false
	if text_layer:
		text_layer.visible = true

	var shadow_col: Color = app_state.shader_params.get("shadow_color", Color(0, 0, 0, 0)) if app_state else Color(0, 0, 0, 0)
	var has_shadow: bool = shadow_col.a > 0.001
	if shadow_layer:
		shadow_layer.visible = has_shadow

	var start_pos: Vector2 = Vector2(40, 60 + ascender_em * font_size_pt)
	var cursor: Vector2 = start_pos
	var max_x: float = start_pos.x
	var prev_char_code: int = 0
	var line_step: float = line_height_em * font_size_pt * line_spacing_factor
	if line_step <= 0.0: line_step = font_size_pt * 1.25

	var shadow_offset_base: Vector2 = app_state.shader_params.get("shadow_offset", Vector2(3.0, 3.0)) if app_state else Vector2(3.0, 3.0)
	var s_off: Vector2 = shadow_offset_base * (font_size_pt / 48.0)

	var points: PackedVector2Array = PackedVector2Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var vert_idx: int = 0

	var s_points: PackedVector2Array = PackedVector2Array()
	var s_uvs: PackedVector2Array = PackedVector2Array()
	var s_colors: PackedColorArray = PackedColorArray()
	var s_indices: PackedInt32Array = PackedInt32Array()
	var s_vert_idx: int = 0

	var lines: PackedStringArray = preview_text.split("\n")

	for line_str in lines:
		cursor.x = start_pos.x
		prev_char_code = 0

		for i in range(line_str.length()):
			var c: String = line_str[i]
			var code: int = c.unicode_at(0)

			if code == 32:
				prev_char_code = 0
				if glyph_lookup.has(32):
					var sp_adv: float = glyph_lookup[32].get("advance", 0.3) * font_size_pt
					cursor.x += sp_adv
				else:
					cursor.x += font_size_pt * 0.3
				continue

			if not glyph_lookup.has(code):
				if glyph_lookup.has(63):
					code = 63
				else:
					prev_char_code = 0
					continue

			if kerning_enabled and prev_char_code != 0:
				var k_key: Vector2i = Vector2i(prev_char_code, code)
				if kerning_lookup.has(k_key):
					var k_adv: float = clampf(float(kerning_lookup[k_key]), -0.35, 0.35)
					cursor.x += k_adv * font_size_pt

			prev_char_code = code

			var g: Dictionary = glyph_lookup[code]
			var advance: float = g.get("advance", 0.5) * font_size_pt
			var pb: Dictionary = g.get("planeBounds", {})
			var ab: Dictionary = g.get("atlasBounds", {})

			if not pb.is_empty() and not ab.is_empty():
				var q_left: float = cursor.x + pb.get("left", 0.0) * font_size_pt
				var q_bottom: float = cursor.y - pb.get("bottom", 0.0) * font_size_pt
				var q_right: float = cursor.x + pb.get("right", 0.0) * font_size_pt
				var q_top: float = cursor.y - pb.get("top", 0.0) * font_size_pt

				# flip vertical coordinates because atlas origin starts at the bottom
				var uv_l: float = ab.get("left", 0.0) / atlas_width
				var uv_r: float = ab.get("right", 0.0) / atlas_width
				var uv_b: float = (atlas_height - ab.get("bottom", 0.0)) / atlas_height
				var uv_t: float = (atlas_height - ab.get("top", 0.0)) / atlas_height

				points.append(Vector2(q_left, q_top))
				points.append(Vector2(q_right, q_top))
				points.append(Vector2(q_right, q_bottom))
				points.append(Vector2(q_left, q_bottom))

				uvs.append(Vector2(uv_l, uv_t))
				uvs.append(Vector2(uv_r, uv_t))
				uvs.append(Vector2(uv_r, uv_b))
				uvs.append(Vector2(uv_l, uv_b))

				for _c in range(4):
					colors.append(Color.WHITE)

				indices.append(vert_idx + 0)
				indices.append(vert_idx + 1)
				indices.append(vert_idx + 2)
				indices.append(vert_idx + 0)
				indices.append(vert_idx + 2)
				indices.append(vert_idx + 3)
				vert_idx += 4

				if has_shadow:
					s_points.append(Vector2(q_left + s_off.x, q_top + s_off.y))
					s_points.append(Vector2(q_right + s_off.x, q_top + s_off.y))
					s_points.append(Vector2(q_right + s_off.x, q_bottom + s_off.y))
					s_points.append(Vector2(q_left + s_off.x, q_bottom + s_off.y))

					s_uvs.append(Vector2(uv_l, uv_t))
					s_uvs.append(Vector2(uv_r, uv_t))
					s_uvs.append(Vector2(uv_r, uv_b))
					s_uvs.append(Vector2(uv_l, uv_b))

					for _sc in range(4):
						s_colors.append(Color.WHITE)

					s_indices.append(s_vert_idx + 0)
					s_indices.append(s_vert_idx + 1)
					s_indices.append(s_vert_idx + 2)
					s_indices.append(s_vert_idx + 0)
					s_indices.append(s_vert_idx + 2)
					s_indices.append(s_vert_idx + 3)
					s_vert_idx += 4

			cursor.x += advance

		if cursor.x > max_x:
			max_x = cursor.x
		cursor.y += line_step

	custom_minimum_size = Vector2(max_x + 80.0, cursor.y + 80.0)

	if not text_mesh:
		text_mesh = ArrayMesh.new()
	else:
		text_mesh.clear_surfaces()

	if indices.size() > 0:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = points
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		text_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	if not shadow_mesh:
		shadow_mesh = ArrayMesh.new()
	else:
		shadow_mesh.clear_surfaces()

	if s_indices.size() > 0:
		var s_arrays: Array = []
		s_arrays.resize(Mesh.ARRAY_MAX)
		s_arrays[Mesh.ARRAY_VERTEX] = s_points
		s_arrays[Mesh.ARRAY_TEX_UV] = s_uvs
		s_arrays[Mesh.ARRAY_COLOR] = s_colors
		s_arrays[Mesh.ARRAY_INDEX] = s_indices
		shadow_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, s_arrays)

	if shadow_layer:
		shadow_layer.queue_redraw()
	if text_layer:
		text_layer.queue_redraw()

func _on_shadow_layer_draw() -> void:
	if not app_state or not app_state.current_texture or not shadow_mesh or shadow_mesh.get_surface_count() == 0:
		return
	var sc: Color = app_state.shader_params.get("shadow_color", Color(0, 0, 0, 0))
	if sc.a <= 0.001:
		return
	shadow_layer.draw_mesh(shadow_mesh, app_state.current_texture)

func _on_text_layer_draw() -> void:
	if not app_state or not app_state.current_texture or not text_mesh or text_mesh.get_surface_count() == 0:
		return
	text_layer.draw_mesh(text_mesh, app_state.current_texture)
