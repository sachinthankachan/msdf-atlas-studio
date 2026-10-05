class_name GlyphMatrixView
extends Control

@onready var scroll_container: ScrollContainer = $ScrollContainer
@onready var grid_container: GridContainer = $ScrollContainer/MarginContainer/GridContainer
@onready var info_label: Label = $Header/InfoLabel
@onready var filter_edit: LineEdit = $Header/FilterEdit

var packed_glyphs_map: Dictionary = {}
var is_mmb_dragging: bool = false
var mmb_drag_start_pos: Vector2 = Vector2.ZERO
var mmb_scroll_start: Vector2 = Vector2.ZERO

var _is_dirty: bool = true
var _buttons_by_cp: Dictionary = {}
var _selected_cp: int = -1

var _styles_initialized: bool = false
var _style_normal: StyleBoxFlat
var _style_hover: StyleBoxFlat
var _style_selected: StyleBoxFlat
var _style_selected_hover: StyleBoxFlat
var _style_missing: StyleBoxFlat
var _style_missing_hover: StyleBoxFlat
var _style_missing_selected: StyleBoxFlat
var _style_missing_selected_hover: StyleBoxFlat

func _init_styles() -> void:
	if _styles_initialized:
		return
	_styles_initialized = true

	_style_normal = _create_flat_style(
		Color(0.13, 0.15, 0.19, 1.0),
		Color(0.24, 0.28, 0.35, 1.0),
		1, 5
	)
	_style_hover = _create_flat_style(
		Color(0.20, 0.24, 0.32, 1.0),
		Color(0.40, 0.52, 0.68, 1.0),
		1, 5
	)
	_style_selected = _create_flat_style(
		Color(0.10, 0.30, 0.52, 0.98),
		Color(0.18, 0.88, 1.0, 1.0),
		3, 5,
		Color(0.15, 0.85, 1.0, 0.55), 4
	)
	_style_selected_hover = _create_flat_style(
		Color(0.14, 0.38, 0.64, 0.98),
		Color(0.45, 0.95, 1.0, 1.0),
		3, 5,
		Color(0.30, 0.90, 1.0, 0.70), 5
	)

	_style_missing = _create_flat_style(
		Color(0.18, 0.10, 0.12, 0.88),
		Color(0.50, 0.18, 0.22, 0.85),
		1, 5
	)
	_style_missing_hover = _create_flat_style(
		Color(0.26, 0.13, 0.16, 0.95),
		Color(0.75, 0.25, 0.30, 0.95),
		1, 5
	)
	_style_missing_selected = _create_flat_style(
		Color(0.38, 0.12, 0.16, 0.98),
		Color(1.0, 0.48, 0.20, 1.0),
		3, 5,
		Color(1.0, 0.45, 0.20, 0.55), 4
	)
	_style_missing_selected_hover = _create_flat_style(
		Color(0.48, 0.16, 0.22, 0.98),
		Color(1.0, 0.65, 0.35, 1.0),
		3, 5,
		Color(1.0, 0.55, 0.25, 0.70), 5
	)

func _create_flat_style(bg: Color, border_c: Color, border_w: int, radius: int, shadow_c: Color = Color(0, 0, 0, 0), shadow_sz: int = 0) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border_c
	sb.border_width_left = border_w
	sb.border_width_top = border_w
	sb.border_width_right = border_w
	sb.border_width_bottom = border_w
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	if shadow_sz > 0:
		sb.shadow_color = shadow_c
		sb.shadow_size = shadow_sz
	return sb

func _apply_button_styles(btn: Button, is_packed: bool, is_selected: bool) -> void:
	if not _styles_initialized:
		_init_styles()

	var s_normal: StyleBoxFlat
	var s_hover: StyleBoxFlat
	if is_packed:
		s_normal = _style_selected if is_selected else _style_normal
		s_hover = _style_selected_hover if is_selected else _style_hover
	else:
		s_normal = _style_missing_selected if is_selected else _style_missing
		s_hover = _style_missing_selected_hover if is_selected else _style_missing_hover

	btn.add_theme_stylebox_override("normal", s_normal)
	btn.add_theme_stylebox_override("hover", s_hover)
	btn.add_theme_stylebox_override("pressed", s_hover)
	btn.add_theme_stylebox_override("focus", s_normal)

	var vbox: VBoxContainer = btn.get_node_or_null("VBox")
	if not vbox:
		for c in btn.get_children():
			if c is VBoxContainer:
				vbox = c
				break
	if vbox:
		var char_lbl: Label = vbox.get_node_or_null("CharLabel")
		var hex_lbl: Label = vbox.get_node_or_null("HexLabel")
		if char_lbl and hex_lbl:
			if is_packed:
				if is_selected:
					char_lbl.modulate = Color(1.0, 1.0, 1.0, 1.0)
					hex_lbl.modulate = Color(0.4, 0.95, 1.0, 1.0)
				else:
					char_lbl.modulate = Color(0.88, 0.90, 0.92, 1.0)
					hex_lbl.modulate = Color(0.5, 0.85, 0.6, 0.85)
			else:
				if is_selected:
					char_lbl.modulate = Color(1.0, 0.8, 0.75, 1.0)
					hex_lbl.modulate = Color(1.0, 0.65, 0.35, 1.0)
				else:
					char_lbl.modulate = Color(0.75, 0.45, 0.45, 0.75)
					hex_lbl.modulate = Color(0.9, 0.35, 0.35, 0.8)

func _ready() -> void:
	_init_styles()
	filter_edit.text_changed.connect(func(_t):
		_is_dirty = true
		_refresh_grid()
	)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			if _is_dirty:
				_refresh_grid()
			else:
				_update_columns()
				if _selected_cp != -1 and _buttons_by_cp.has(_selected_cp):
					_ensure_button_visible(_buttons_by_cp[_selected_cp])
	)
	if AppState:
		AppState.generation_completed.connect(_on_generation_completed)
		AppState.glyph_selected.connect(_on_glyph_selected)
		AppState.codepoints_changed.connect(func(_cnt):
			_is_dirty = true
			if is_visible_in_tree():
				_refresh_grid()
		)
		if not AppState.current_metadata.is_empty():
			_on_generation_completed(null, AppState.current_metadata)
		else:
			if is_visible_in_tree():
				_refresh_grid()

func _on_generation_completed(_img: Image, metadata: Dictionary) -> void:
	packed_glyphs_map.clear()
	var glyphs: Array = metadata.get("glyphs", [])
	for g in glyphs:
		packed_glyphs_map[g.get("unicode", 0)] = g
	_is_dirty = true
	if is_visible_in_tree():
		_refresh_grid()

static func safe_chr(cp: int) -> String:
	if cp < 32 or (cp >= 127 and cp <= 159) or (cp >= 0xD800 and cp <= 0xDFFF):
		return "␣"
	return String.chr(cp)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not scroll_container:
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE or (mb.button_index == MOUSE_BUTTON_RIGHT and not Input.is_key_pressed(KEY_CTRL)):
			if mb.pressed:
				if scroll_container.get_global_rect().has_point(mb.global_position):
					is_mmb_dragging = true
					mmb_drag_start_pos = mb.global_position
					mmb_scroll_start = Vector2(scroll_container.scroll_horizontal, scroll_container.scroll_vertical)
					get_viewport().set_input_as_handled()
			else:
				if is_mmb_dragging:
					is_mmb_dragging = false
					get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		if is_mmb_dragging:
			var mm: InputEventMouseMotion = event as InputEventMouseMotion
			var delta: Vector2 = mm.global_position - mmb_drag_start_pos
			scroll_container.scroll_horizontal = int(mmb_scroll_start.x - delta.x)
			scroll_container.scroll_vertical = int(mmb_scroll_start.y - delta.y)
			get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_columns()

func _update_columns() -> void:
	if not is_inside_tree() or not grid_container:
		return
	var avail_w: float = size.x - 48.0
	if avail_w > 100.0:
		var col_w: float = 64.0 + 6.0
		var new_cols: int = max(4, int(avail_w / col_w))
		if grid_container.columns != new_cols:
			grid_container.columns = new_cols

func _refresh_grid() -> void:
	_is_dirty = false
	_update_columns()
	_buttons_by_cp.clear()

	var filter_text: String = filter_edit.text.strip_edges().to_lower()
	var total_count: int = 0
	var missing_count: int = 0
	var cur_selected_cp: int = AppState.selected_glyph.get("unicode", -1) if AppState else -1
	_selected_cp = cur_selected_cp

	# 1. Filter matching codepoints
	var matched_cps: Array[int] = []
	for cp in AppState.selected_codepoints:
		var char_str: String = safe_chr(cp)
		var hex_str: String = "U+%04X" % cp
		if not filter_text.is_empty():
			if not (char_str.to_lower().contains(filter_text) or hex_str.to_lower().contains(filter_text)):
				continue
		matched_cps.append(cp)

	var needed_count: int = matched_cps.size()
	var existing_children: Array = grid_container.get_children()

	# 2. Prune any excess button nodes beyond needed_count
	for i in range(needed_count, existing_children.size()):
		existing_children[i].queue_free()

	# 3. Populate / reuse button nodes
	for i in range(needed_count):
		var cp: int = matched_cps[i]
		var char_str: String = safe_chr(cp)
		var hex_str: String = "U+%04X" % cp
		var is_packed: bool = packed_glyphs_map.has(cp)
		total_count += 1
		if not is_packed:
			missing_count += 1

		var btn: Button
		var char_lbl: Label
		var hex_lbl: Label

		if i < existing_children.size() and is_instance_valid(existing_children[i]):
			btn = existing_children[i]
			btn.visible = true
			var vbox: VBoxContainer = btn.get_node_or_null("VBox")
			char_lbl = vbox.get_node_or_null("CharLabel") if vbox else null
			hex_lbl = vbox.get_node_or_null("HexLabel") if vbox else null
		else:
			btn = Button.new()
			btn.custom_minimum_size = Vector2(64, 64)
			btn.focus_mode = Control.FOCUS_NONE
			btn.clip_contents = true

			var vbox: VBoxContainer = VBoxContainer.new()
			vbox.name = "VBox"
			vbox.custom_minimum_size = Vector2(64, 64)
			vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			vbox.add_theme_constant_override("separation", 2)
			btn.add_child(vbox)
			vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

			char_lbl = Label.new()
			char_lbl.name = "CharLabel"
			char_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			char_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			char_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			char_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
			char_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			char_lbl.add_theme_font_size_override("font_size", 22)
			vbox.add_child(char_lbl)

			hex_lbl = Label.new()
			hex_lbl.name = "HexLabel"
			hex_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hex_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			hex_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hex_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hex_lbl.add_theme_font_size_override("font_size", 9)
			vbox.add_child(hex_lbl)

			btn.pressed.connect(func():
				var btn_cp: int = btn.get_meta("codepoint", -1)
				if btn_cp != -1:
					AppState.select_glyph_by_unicode(btn_cp)
			)
			grid_container.add_child(btn)

		btn.set_meta("codepoint", cp)
		btn.set_meta("is_packed", is_packed)

		if char_lbl:
			char_lbl.text = char_str if cp > 32 else "␣"
		if hex_lbl:
			hex_lbl.text = hex_str if is_packed else "MISSING"

		if is_packed:
			btn.tooltip_text = "%s (%s)\nStatus: Packed in Atlas" % [char_str, hex_str]
		else:
			btn.tooltip_text = "%s (%s)\nStatus: Missing / Not found in font" % [char_str, hex_str]

		var is_selected: bool = (cp == cur_selected_cp and cur_selected_cp != -1)
		_apply_button_styles(btn, is_packed, is_selected)
		_buttons_by_cp[cp] = btn

	info_label.text = "Total: %d | Packed: %d | Missing: %d" % [
		total_count,
		total_count - missing_count,
		missing_count
	]

	if _selected_cp != -1 and _buttons_by_cp.has(_selected_cp):
		_ensure_button_visible(_buttons_by_cp[_selected_cp])

func _on_glyph_selected(glyph_data: Dictionary) -> void:
	var new_cp: int = glyph_data.get("unicode", -1)
	if new_cp == _selected_cp:
		return

	# Deselect previously selected button
	if _selected_cp != -1 and _buttons_by_cp.has(_selected_cp):
		var prev_btn: Button = _buttons_by_cp[_selected_cp]
		if is_instance_valid(prev_btn):
			var was_packed: bool = prev_btn.get_meta("is_packed", false)
			_apply_button_styles(prev_btn, was_packed, false)

	_selected_cp = new_cp

	# Select newly selected button
	if _selected_cp != -1 and _buttons_by_cp.has(_selected_cp):
		var cur_btn: Button = _buttons_by_cp[_selected_cp]
		if is_instance_valid(cur_btn):
			var is_packed: bool = cur_btn.get_meta("is_packed", false)
			_apply_button_styles(cur_btn, is_packed, true)
			if is_visible_in_tree():
				_ensure_button_visible(cur_btn)

func _ensure_button_visible(btn: Button) -> void:
	if not scroll_container or not is_instance_valid(btn):
		return
	if scroll_container.has_method("ensure_control_visible"):
		scroll_container.ensure_control_visible(btn)
