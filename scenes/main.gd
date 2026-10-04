class_name MainApp
extends Control

const MSDFProjectManager = preload("res://scripts/project_manager.gd")

@onready var file_btn: MenuButton = $VBoxMain/TopMenuBar/File
@onready var presets_btn: MenuButton = $VBoxMain/TopMenuBar/Presets
@onready var view_btn: MenuButton = $VBoxMain/TopMenuBar/View
@onready var help_btn: MenuButton = $VBoxMain/TopMenuBar/Help

var file_menu: PopupMenu
var presets_menu: PopupMenu
var view_menu: PopupMenu
var help_menu: PopupMenu

@onready var tab_container: TabContainer = $VBoxMain/HSplitMain/CenterRightSplit/CenterArea/TabContainer
@onready var atlas_viewport: AtlasViewport = $VBoxMain/HSplitMain/CenterRightSplit/CenterArea/TabContainer/AtlasView
@onready var text_preview: TextPreviewViewport = $VBoxMain/HSplitMain/CenterRightSplit/CenterArea/TabContainer/LiveTextSandbox
@onready var glyph_grid: GlyphMatrixView = $VBoxMain/HSplitMain/CenterRightSplit/CenterArea/TabContainer/GlyphGrid

@onready var hsplit_main: HSplitContainer = $VBoxMain/HSplitMain
@onready var left_sidebar: PanelContainer = $VBoxMain/HSplitMain/LeftSidebar
@onready var center_right_split: HSplitContainer = $VBoxMain/HSplitMain/CenterRightSplit
@onready var center_area: PanelContainer = $VBoxMain/HSplitMain/CenterRightSplit/CenterArea
@onready var right_sidebar: PanelContainer = $VBoxMain/HSplitMain/CenterRightSplit/RightSidebar

@onready var font_loader_panel: FontLoaderPanel = $VBoxMain/HSplitMain/LeftSidebar/Scroll/Margin/VBox/FontLoaderPanel
@onready var unicode_range_picker: UnicodeRangePicker = $VBoxMain/HSplitMain/LeftSidebar/Scroll/Margin/VBox/UnicodeRangePicker
@onready var atlas_settings_panel: AtlasSettingsPanel = $VBoxMain/HSplitMain/LeftSidebar/Scroll/Margin/VBox/AtlasSettingsPanel

var save_project_dialog: FileDialog
var open_project_dialog: FileDialog

@onready var char_tile_lbl: Label = $VBoxMain/HSplitMain/CenterRightSplit/RightSidebar/Scroll/Margin/VBox/InspectorSection/Tile/CharLabel
@onready var glyph_unicode_lbl: Label = $VBoxMain/HSplitMain/CenterRightSplit/RightSidebar/Scroll/Margin/VBox/InspectorSection/UnicodeValue
@onready var glyph_advance_lbl: Label = $VBoxMain/HSplitMain/CenterRightSplit/RightSidebar/Scroll/Margin/VBox/InspectorSection/AdvanceValue
@onready var glyph_plane_lbl: Label = $VBoxMain/HSplitMain/CenterRightSplit/RightSidebar/Scroll/Margin/VBox/InspectorSection/PlaneValue
@onready var glyph_atlas_lbl: Label = $VBoxMain/HSplitMain/CenterRightSplit/RightSidebar/Scroll/Margin/VBox/InspectorSection/AtlasValue

@onready var metrics_glyphs_lbl: Label = $VBoxMain/HSplitMain/CenterRightSplit/RightSidebar/Scroll/Margin/VBox/MetricsSection/GlyphsValue
@onready var metrics_packed_lbl: Label = $VBoxMain/HSplitMain/CenterRightSplit/RightSidebar/Scroll/Margin/VBox/MetricsSection/PackedValue
@onready var metrics_memory_lbl: Label = $VBoxMain/HSplitMain/CenterRightSplit/RightSidebar/Scroll/Margin/VBox/MetricsSection/MemoryValue
@onready var metrics_format_lbl: Label = $VBoxMain/HSplitMain/CenterRightSplit/RightSidebar/Scroll/Margin/VBox/MetricsSection/FormatValue
@onready var metrics_kerning_lbl: Label = $VBoxMain/HSplitMain/CenterRightSplit/RightSidebar/Scroll/Margin/VBox/MetricsSection/KerningValue

@onready var text_color_picker: ColorPickerButton = $VBoxMain/HSplitMain/CenterRightSplit/RightSidebar/Scroll/Margin/VBox/ShaderSection/TextColorPicker
@onready var outline_chk: CheckBox = $VBoxMain/HSplitMain/CenterRightSplit/RightSidebar/Scroll/Margin/VBox/ShaderSection/OutlineCheck
@onready var outline_thickness_slider: HSlider = $VBoxMain/HSplitMain/CenterRightSplit/RightSidebar/Scroll/Margin/VBox/ShaderSection/OutlineSlider
@onready var outline_color_picker: ColorPickerButton = $VBoxMain/HSplitMain/CenterRightSplit/RightSidebar/Scroll/Margin/VBox/ShaderSection/OutlineColorPicker
@onready var shadow_chk: CheckBox = $VBoxMain/HSplitMain/CenterRightSplit/RightSidebar/Scroll/Margin/VBox/ShaderSection/ShadowCheck
@onready var shadow_color_picker: ColorPickerButton = $VBoxMain/HSplitMain/CenterRightSplit/RightSidebar/Scroll/Margin/VBox/ShaderSection/ShadowColorPicker
@onready var shadow_softness_slider: HSlider = $VBoxMain/HSplitMain/CenterRightSplit/RightSidebar/Scroll/Margin/VBox/ShaderSection/ShadowSoftnessSlider

@onready var export_dialog: ExportDialog = $ExportDialog
@onready var export_button: Button = $VBoxMain/HSplitMain/CenterRightSplit/RightSidebar/Scroll/Margin/VBox/ExportButton

@onready var status_worker_lbl: Label = $VBoxMain/StatusBarMargin/StatusBar/WorkerLabel
@onready var status_time_lbl: Label = $VBoxMain/StatusBarMargin/StatusBar/TimeLabel
@onready var status_msg_lbl: Label = $VBoxMain/StatusBarMargin/StatusBar/MessageLabel

var _last_window_w: float = 0.0

func _ready() -> void:
	_setup_window_icon()
	_setup_menus()
	_setup_project_dialogs()
	_setup_shader_controls()
	export_button.pressed.connect(_on_export_button_pressed)

func _setup_window_icon() -> void:
	if ResourceLoader.exists("res://icon.svg"):
		var icon_tex = load("res://icon.svg") as Texture2D
		if icon_tex:
			var img = icon_tex.get_image()
			if img:
				DisplayServer.set_icon(img)

	if AppState:
		AppState.generation_started.connect(_on_gen_started)
		AppState.generation_completed.connect(_on_gen_completed)
		AppState.generation_failed.connect(_on_gen_failed)
		AppState.generation_cancelled.connect(_on_gen_cancelled)
		AppState.glyph_selected.connect(_on_glyph_selected)
		AppState.status_message_updated.connect(_on_status_updated)

	get_viewport().size_changed.connect(_on_viewport_size_changed)
	call_deferred("_update_dynamic_layout")

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_WM_SIZE_CHANGED:
		_update_dynamic_layout()

func _setup_project_dialogs() -> void:
	var proj_filters := PackedStringArray([
		"*.msdfproj,*.msdfatlas,*.glyphproj,*.glyphforge ; MSDF Atlas Project (*.msdfproj, *.msdfatlas)",
		"* ; All Files (*)"
	])
	var initial_dir := ""
	var candidates := [
		OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS),
		OS.get_environment("HOME"),
		OS.get_executable_path().get_base_dir()
	]
	for dir in candidates:
		if not dir.is_empty() and DirAccess.dir_exists_absolute(dir):
			initial_dir = dir
			break

	save_project_dialog = FileDialog.new()
	save_project_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_project_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_project_dialog.use_native_dialog = true
	save_project_dialog.min_size = Vector2i(750, 500)
	save_project_dialog.filters = proj_filters
	if not initial_dir.is_empty():
		save_project_dialog.current_dir = initial_dir
	save_project_dialog.file_selected.connect(_on_save_project_file_selected)
	add_child(save_project_dialog)

	open_project_dialog = FileDialog.new()
	open_project_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	open_project_dialog.access = FileDialog.ACCESS_FILESYSTEM
	open_project_dialog.use_native_dialog = true
	open_project_dialog.min_size = Vector2i(750, 500)
	open_project_dialog.filters = proj_filters
	if not initial_dir.is_empty():
		open_project_dialog.current_dir = initial_dir
	open_project_dialog.file_selected.connect(_on_open_project_file_selected)
	add_child(open_project_dialog)

static func _make_shortcut(key: Key, ctrl: bool = false, shift: bool = false) -> Shortcut:
	var sc := Shortcut.new()
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	sc.events = [ev]
	return sc

func _setup_menus() -> void:
	file_menu = file_btn.get_popup()
	presets_menu = presets_btn.get_popup()
	view_menu = view_btn.get_popup()
	help_menu = help_btn.get_popup()

	var empty_style := StyleBoxEmpty.new()
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(1.0, 1.0, 1.0, 0.1)
	hover_style.corner_radius_top_left = 4
	hover_style.corner_radius_top_right = 4
	hover_style.corner_radius_bottom_left = 4
	hover_style.corner_radius_bottom_right = 4

	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = Color(1.0, 1.0, 1.0, 0.2)
	pressed_style.corner_radius_top_left = 4
	pressed_style.corner_radius_top_right = 4
	pressed_style.corner_radius_bottom_left = 4
	pressed_style.corner_radius_bottom_right = 4

	for btn in [file_btn, presets_btn, view_btn, help_btn]:
		btn.add_theme_stylebox_override("normal", empty_style)
		btn.add_theme_stylebox_override("focus", empty_style)
		btn.add_theme_stylebox_override("hover", hover_style)
		btn.add_theme_stylebox_override("pressed", pressed_style)

	file_menu.clear()
	file_menu.add_item("New Project", 0)
	file_menu.set_item_shortcut(file_menu.get_item_index(0), _make_shortcut(KEY_N, true))
	file_menu.add_item("Open Project...", 1)
	file_menu.set_item_shortcut(file_menu.get_item_index(1), _make_shortcut(KEY_O, true))
	file_menu.add_item("Save Project", 2)
	file_menu.set_item_shortcut(file_menu.get_item_index(2), _make_shortcut(KEY_S, true))
	file_menu.add_item("Save Project As...", 3)
	file_menu.set_item_shortcut(file_menu.get_item_index(3), _make_shortcut(KEY_S, true, true))
	file_menu.add_separator()
	file_menu.add_item("Export Assets...", 4)
	file_menu.set_item_shortcut(file_menu.get_item_index(4), _make_shortcut(KEY_E, true))
	file_menu.add_separator()
	file_menu.add_item("Quit", 5)
	file_menu.id_pressed.connect(_on_file_menu_id_pressed)

	presets_menu.clear()
	presets_menu.add_item("Basic Latin (ASCII)", 0)
	presets_menu.add_item("Latin-1 Supplement", 1)
	presets_menu.id_pressed.connect(_on_presets_menu_id_pressed)

	view_menu.clear()
	view_menu.add_item("Reset Zoom (Home)", 0)
	view_menu.add_item("Fit to View (F)", 1)
	view_menu.add_separator()
	view_menu.add_item("Toggle Left Sidebar (Ctrl+B)", 2)
	view_menu.set_item_shortcut(view_menu.get_item_index(2), _make_shortcut(KEY_B, true))
	view_menu.add_item("Toggle Right Sidebar (Ctrl+J)", 3)
	view_menu.set_item_shortcut(view_menu.get_item_index(3), _make_shortcut(KEY_J, true))
	view_menu.add_item("Reset Panel Layout", 4)
	view_menu.id_pressed.connect(_on_view_menu_id_pressed)

	help_menu.clear()
	help_menu.add_item("About MSDF Atlas Studio", 0)
	help_menu.id_pressed.connect(_on_help_menu_id_pressed)

func _setup_shader_controls() -> void:
	text_color_picker.color = AppState.shader_params["text_color"]
	outline_color_picker.color = AppState.shader_params["outline_color"]
	shadow_color_picker.color = AppState.shader_params["shadow_color"]
	outline_thickness_slider.value = AppState.shader_params["outline_thickness"]
	shadow_softness_slider.value = AppState.shader_params["shadow_softness"]

	text_color_picker.edit_alpha = true
	outline_color_picker.edit_alpha = true
	shadow_color_picker.edit_alpha = true

	outline_thickness_slider.editable = outline_chk.button_pressed
	shadow_softness_slider.editable = shadow_chk.button_pressed
	if not shadow_chk.button_pressed:
		AppState.update_shader_param("shadow_color", Color(0, 0, 0, 0))
	if not outline_chk.button_pressed:
		AppState.update_shader_param("outline_thickness", 0.0)

	text_color_picker.color_changed.connect(func(c): AppState.update_shader_param("text_color", c))
	outline_color_picker.color_changed.connect(func(c): AppState.update_shader_param("outline_color", c))
	shadow_color_picker.color_changed.connect(func(c):
		if shadow_chk.button_pressed:
			AppState.update_shader_param("shadow_color", c)
	)

	outline_chk.toggled.connect(func(enabled):
		outline_thickness_slider.editable = enabled
		if enabled and outline_thickness_slider.value <= 0.0:
			outline_thickness_slider.value = 0.25
		AppState.update_shader_param("outline_thickness", outline_thickness_slider.value if enabled else 0.0)
	)
	outline_thickness_slider.value_changed.connect(func(v):
		if outline_chk.button_pressed:
			AppState.update_shader_param("outline_thickness", v)
	)

	shadow_chk.toggled.connect(func(enabled):
		shadow_softness_slider.editable = enabled
		var col = shadow_color_picker.color if enabled else Color(0, 0, 0, 0)
		AppState.update_shader_param("shadow_color", col)
	)
	shadow_softness_slider.value_changed.connect(func(v):
		AppState.update_shader_param("shadow_softness", v)
	)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed or event.meta_pressed:
			if event.shift_pressed and event.keycode == KEY_S:
				_on_save_project_as()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_S:
				_on_save_project()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_O:
				_on_open_project()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_N:
				_on_new_project()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_E:
				export_dialog.popup_centered()
				get_viewport().set_input_as_handled()

func _on_export_button_pressed() -> void:
	export_dialog.popup_centered()

func _on_file_menu_id_pressed(id: int) -> void:
	match id:
		0: _on_new_project()
		1: _on_open_project()
		2: _on_save_project()
		3: _on_save_project_as()
		4: export_dialog.popup_centered()
		5: get_tree().quit()

func _on_new_project() -> void:
	AppState.reset_project()
	unicode_range_picker.set_custom_ranges([])
	text_preview.set_preview_settings({
		"sample_text": "The quick brown fox jumps over the lazy dog.\n0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz !@#$%^&*()_+",
		"font_size": 48.0,
		"bg_option": 0,
		"kerning_enabled": true
	})
	_sync_shader_controls_from_app_state()
	_update_window_title()
	metrics_glyphs_lbl.text = "0"
	metrics_packed_lbl.text = "0.0%"
	metrics_memory_lbl.text = "0.00 MB"
	metrics_kerning_lbl.text = "0 pairs"

func _on_open_project() -> void:
	if open_project_dialog.use_native_dialog:
		open_project_dialog.show()
	else:
		open_project_dialog.popup_centered_ratio(0.7)

func _on_save_project() -> void:
	if AppState.current_project_path.is_empty():
		_on_save_project_as()
	else:
		_execute_save_project(AppState.current_project_path)

func _on_save_project_as() -> void:
	if save_project_dialog.use_native_dialog:
		save_project_dialog.show()
	else:
		save_project_dialog.popup_centered_ratio(0.7)

func _on_save_project_file_selected(path: String) -> void:
	_execute_save_project(path)

func _execute_save_project(path: String) -> void:
	var final_path := path
	var ext := final_path.get_extension().to_lower()
	if ext != "msdfproj" and ext != "msdfatlas" and ext != "glyphforge" and ext != "glyphproj":
		final_path += ".msdfproj"

	var custom_ranges: Array = unicode_range_picker.get_custom_ranges()
	var preview_data: Dictionary = text_preview.get_preview_settings()
	var project_dir := final_path.get_base_dir()

	var dict: Dictionary = MSDFProjectManager.build_project_dict(
		AppState.primary_font_path,
		AppState.fallback_font_paths,
		AppState.selected_codepoints,
		custom_ranges,
		AppState.atlas_config,
		AppState.shader_params,
		preview_data,
		project_dir
	)

	var err: Error = MSDFProjectManager.save_project(final_path, dict)
	if err == OK:
		if AppState.current_image and not AppState.current_image.is_empty():
			var base_path := final_path.get_basename()
			var cache_png := base_path + "_atlas.png"
			var cache_meta := base_path + "_meta.json"
			AppState.current_image.save_png(cache_png)
			if not AppState.current_metadata.is_empty():
				var f := FileAccess.open(cache_meta, FileAccess.WRITE)
				if f:
					f.store_string(JSON.stringify(AppState.current_metadata, "  "))
					f.close()

		AppState.current_project_path = final_path
		AppState.status_message_updated.emit("✓ Project saved: %s" % final_path.get_file())
		_update_window_title()
	else:
		var err_dlg := AcceptDialog.new()
		err_dlg.title = "Save Error"
		err_dlg.dialog_text = "Failed to save project file (Error %d)." % err
		add_child(err_dlg)
		err_dlg.popup_centered()

func _on_open_project_file_selected(path: String) -> void:
	var res: Dictionary = MSDFProjectManager.load_project(path)
	if res.get("error", OK) != OK:
		var err_dlg := AcceptDialog.new()
		err_dlg.title = "Open Error"
		err_dlg.dialog_text = res.get("error_message", "Failed to load project file.")
		add_child(err_dlg)
		err_dlg.popup_centered()
		return

	var data: Dictionary = res.get("data", {})
	AppState.apply_project_dict(data, path)

	var charset_dict: Dictionary = data.get("charset", {})
	var custom_ranges: Array = charset_dict.get("custom_ranges", [])
	unicode_range_picker.set_custom_ranges(custom_ranges)

	var preview_dict: Dictionary = data.get("preview", {})
	text_preview.set_preview_settings(preview_dict)

	_sync_shader_controls_from_app_state()
	_update_window_title()

	var base_path := path.get_basename()
	var cache_png := base_path + "_atlas.png"
	var cache_meta := base_path + "_meta.json"
	var restored := false

	if FileAccess.file_exists(cache_png) and FileAccess.file_exists(cache_meta):
		var img := Image.load_from_file(cache_png)
		if img and not img.is_empty():
			var meta_str := FileAccess.get_file_as_string(cache_meta)
			var parsed = JSON.parse_string(meta_str)
			if parsed is Dictionary and not parsed.is_empty():
				AppState.restore_atlas_cache(img, parsed)
				restored = true

	if not restored and not AppState.primary_font_path.is_empty():
		AppState.start_generation()

func _sync_shader_controls_from_app_state() -> void:
	text_color_picker.color = AppState.shader_params.get("text_color", Color.WHITE)
	outline_color_picker.color = AppState.shader_params.get("outline_color", Color.BLACK)
	shadow_color_picker.color = AppState.shader_params.get("shadow_color", Color(0, 0, 0, 0.5))
	var ot: float = float(AppState.shader_params.get("outline_thickness", 0.0))
	outline_chk.button_pressed = ot > 0.001
	outline_thickness_slider.value = ot
	outline_thickness_slider.editable = outline_chk.button_pressed
	var sc: Color = AppState.shader_params.get("shadow_color", Color(0, 0, 0, 0.5))
	shadow_chk.button_pressed = sc.a > 0.001
	shadow_softness_slider.value = float(AppState.shader_params.get("shadow_softness", 0.03))

func _update_window_title() -> void:
	var base_title := "MSDF Atlas Studio"
	if not AppState.current_project_path.is_empty():
		get_window().title = "%s - %s" % [base_title, AppState.current_project_path.get_file()]
	else:
		get_window().title = base_title

func _on_presets_menu_id_pressed(id: int) -> void:
	match id:
		0: AppState.set_preset_ascii()
		1: AppState.set_preset_latin1_supplement()

func _on_view_menu_id_pressed(id: int) -> void:
	match id:
		0:
			if tab_container.current_tab == 0:
				atlas_viewport.pan_zoom.center_view()
			elif tab_container.current_tab == 1:
				text_preview.pan_zoom.target_zoom = 1.0
				text_preview.pan_zoom.target_pan = Vector2(50, 40)
		1:
			if tab_container.current_tab == 0:
				atlas_viewport.pan_zoom.fit_to_view()
			elif tab_container.current_tab == 1:
				text_preview._fit_text_to_view()
		2:
			toggle_left_sidebar()
		3:
			toggle_right_sidebar()
		4:
			reset_panel_layout()

func toggle_left_sidebar() -> void:
	if left_sidebar:
		left_sidebar.visible = not left_sidebar.visible
		_last_window_w = 0.0
		_update_dynamic_layout()

func toggle_right_sidebar() -> void:
	if right_sidebar:
		right_sidebar.visible = not right_sidebar.visible
		_last_window_w = 0.0
		_update_dynamic_layout()

func reset_panel_layout() -> void:
	if left_sidebar: left_sidebar.visible = true
	if right_sidebar: right_sidebar.visible = true
	_last_window_w = 0.0
	_update_dynamic_layout()

func _on_viewport_size_changed() -> void:
	_update_dynamic_layout()

func _update_dynamic_layout() -> void:
	if not is_inside_tree() or not is_node_ready():
		return

	var current_w: float = size.x
	if current_w <= 0.0:
		current_w = float(get_viewport_rect().size.x)
	if current_w <= 0.0:
		current_w = float(DisplayServer.window_get_size().x)
	if current_w <= 0.0:
		current_w = 1240.0

	if absf(current_w - _last_window_w) < 1.0:
		return
	_last_window_w = current_w

	# keep left sidebar wide enough so buttons never clip
	var target_left_w: float = clampf(current_w * 0.27, 320.0, 380.0)
	var target_right_w: float = clampf(current_w * 0.20, 230.0, 300.0)

	var left_min: float = 320.0
	var right_min: float = min(230.0, current_w * 0.22)
	var center_min: float = min(280.0, current_w * 0.35)

	if left_sidebar and left_sidebar.visible:
		left_sidebar.custom_minimum_size.x = left_min
	if right_sidebar and right_sidebar.visible:
		right_sidebar.custom_minimum_size.x = right_min
	if center_area:
		center_area.custom_minimum_size.x = center_min

	if hsplit_main and left_sidebar:
		if left_sidebar.visible:
			hsplit_main.split_offset = int(target_left_w - left_sidebar.custom_minimum_size.x)
		else:
			hsplit_main.split_offset = 0

	if center_right_split and center_area and right_sidebar:
		if right_sidebar.visible:
			var left_effective_w: float = target_left_w if left_sidebar.visible else 0.0
			var center_right_avail: float = current_w - left_effective_w - 12.0
			var desired_center_w: float = max(center_min, center_right_avail - target_right_w)
			center_right_split.split_offset = int(desired_center_w - center_area.custom_minimum_size.x)
		else:
			center_right_split.split_offset = int(current_w)

func _on_help_menu_id_pressed(id: int) -> void:
	if id == 0:
		var dlg: AcceptDialog = AcceptDialog.new()
		dlg.title = "About MSDF Atlas Studio"
		dlg.dialog_text = "MSDF Atlas Studio v0.1.0\nCreated by Sachin Thankachan\n\nGodot 4 & C++ GDExtension MSDF Atlas Generator\nWraps Viktor Chlumsky's msdf-atlas-gen and FreeType."
		add_child(dlg)
		dlg.popup_centered()

func _on_gen_started() -> void:
	status_worker_lbl.text = "Thread: Generating..."
	status_worker_lbl.modulate = Color(1.0, 0.8, 0.3)

func _on_gen_completed(_img: Image, metadata: Dictionary) -> void:
	status_worker_lbl.text = "Thread: Idle"
	status_worker_lbl.modulate = Color(0.5, 0.9, 0.5)
	status_time_lbl.text = "Generation Time: %d ms" % AppState.last_generation_duration_ms

	var atlas_dict: Dictionary = metadata.get("atlas", {})
	var glyphs: Array = metadata.get("glyphs", [])
	var w: int = atlas_dict.get("width", 1024)
	var h: int = atlas_dict.get("height", 1024)
	var ftype_str: String = atlas_dict.get("type", "msdf").to_upper()

	metrics_glyphs_lbl.text = str(glyphs.size())
	metrics_format_lbl.text = ftype_str
	var kerning_arr: Array = metadata.get("kerning", [])
	metrics_kerning_lbl.text = "%d pairs" % kerning_arr.size()

	var channels: int = 3
	if ftype_str == "SDF" or ftype_str == "PSDF": channels = 1
	elif ftype_str == "MTSDF": channels = 4
	var mem_mb: float = float(w * h * channels) / (1024.0 * 1024.0)
	metrics_memory_lbl.text = "%.2f MB" % mem_mb

	# calculate packing efficiency as glyph area over total atlas area
	var glyph_area: float = 0.0
	for g in glyphs:
		var ab = g.get("atlasBounds", {})
		if ab.has("left") and ab.has("right"):
			glyph_area += (ab["right"] - ab["left"]) * (ab["top"] - ab["bottom"])
	var total_area: float = float(w * h)
	var efficiency: float = (glyph_area / total_area) * 100.0 if total_area > 0 else 0.0
	metrics_packed_lbl.text = "%.1f%%" % efficiency

func _on_gen_failed(error_msg: String) -> void:
	status_worker_lbl.text = "Thread: Error"
	status_worker_lbl.modulate = Color(1.0, 0.4, 0.4)
	status_msg_lbl.text = "Error: " + error_msg

func _on_gen_cancelled() -> void:
	status_worker_lbl.text = "Thread: Idle"
	status_worker_lbl.modulate = Color(0.7, 0.7, 0.7)
	status_msg_lbl.text = "Generation cancelled."

func _on_glyph_selected(g: Dictionary) -> void:
	if g.is_empty():
		char_tile_lbl.text = "-"
		glyph_unicode_lbl.text = "None"
		glyph_advance_lbl.text = "-"
		glyph_plane_lbl.text = "-"
		glyph_atlas_lbl.text = "-"
		return

	var cp: int = g.get("unicode", 0)
	var disp_str: String = "␣"
	if cp >= 32 and (cp < 127 or cp >= 160) and (cp < 0xD800 or cp > 0xDFFF):
		disp_str = String.chr(cp)
	char_tile_lbl.text = disp_str
	if g.get("missing", false):
		glyph_unicode_lbl.text = "%s (0x%04X) [MISSING]" % [disp_str if cp > 32 else "Space", cp]
		glyph_advance_lbl.text = "N/A"
		glyph_plane_lbl.text = "N/A"
		glyph_atlas_lbl.text = "N/A"
		return

	glyph_unicode_lbl.text = "%s (0x%04X)" % [disp_str if cp > 32 else "Space", cp]
	glyph_advance_lbl.text = "%.3f em" % g.get("advance", 0.0)

	var pb: Dictionary = g.get("planeBounds", {})
	if pb.is_empty():
		glyph_plane_lbl.text = "[0, 0, 0, 0]"
	else:
		glyph_plane_lbl.text = "[%.2f, %.2f, %.2f, %.2f]" % [pb.get("left", 0.0), pb.get("bottom", 0.0), pb.get("right", 0.0), pb.get("top", 0.0)]

	var ab: Dictionary = g.get("atlasBounds", {})
	if ab.is_empty():
		glyph_atlas_lbl.text = "[0, 0, 0, 0]"
	else:
		glyph_atlas_lbl.text = "[%d, %d, %d, %d]" % [int(ab.get("left", 0)), int(ab.get("bottom", 0)), int(ab.get("right", 0)), int(ab.get("top", 0))]

func _on_status_updated(msg: String) -> void:
	status_msg_lbl.text = msg
