class_name FontLoaderPanel
extends VBoxContainer

@onready var primary_path_edit: LineEdit = $PrimaryFontContainer/PathEdit
@onready var browse_primary_btn: Button = $PrimaryFontContainer/BrowseButton
@onready var bundled_font_btn: Button = $BundledFontButton
@onready var fallback_list: VBoxContainer = $FallbackContainer/FallbackList
@onready var add_fallback_btn: Button = $FallbackContainer/ButtonBox/AddFallbackButton
@onready var clear_fallback_btn: Button = $FallbackContainer/ButtonBox/ClearFallbackButton
@onready var font_info_label: Label = $FontInfoLabel

var primary_file_dialog: FileDialog
var fallback_file_dialog: FileDialog

func _ready() -> void:
	_setup_file_dialogs()
	browse_primary_btn.pressed.connect(_on_browse_primary_pressed)
	bundled_font_btn.pressed.connect(_on_use_bundled_font_pressed)
	add_fallback_btn.pressed.connect(_on_add_fallback_pressed)
	clear_fallback_btn.pressed.connect(_on_clear_fallbacks_pressed)

	if AppState:
		AppState.font_loaded.connect(_on_font_loaded)
		AppState.project_loaded.connect(func(_p): refresh_from_app_state())

	call_deferred("_check_default_font")

func refresh_from_app_state() -> void:
	if AppState.primary_font_path.is_empty():
		primary_path_edit.text = ""
		font_info_label.text = "No font loaded"
	else:
		_on_font_loaded(AppState.primary_font_path, true)

	for child in fallback_list.get_children():
		child.queue_free()
	for fb in AppState.fallback_font_paths:
		_on_font_loaded(fb, false)

func _setup_file_dialogs() -> void:
	var font_filters := PackedStringArray([
		"*.ttf,*.otf,*.TTF,*.OTF ; Font Files (*.ttf, *.otf)",
		"*.ttf,*.TTF ; TrueType Fonts (*.ttf)",
		"*.otf,*.OTF ; OpenType Fonts (*.otf)",
		"* ; All Files (*)"
	])
	var initial_dir := _get_initial_browse_dir()

	primary_file_dialog = FileDialog.new()
	primary_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	primary_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	primary_file_dialog.use_native_dialog = true
	primary_file_dialog.min_size = Vector2i(700, 480)
	primary_file_dialog.filters = font_filters
	if not initial_dir.is_empty():
		primary_file_dialog.current_dir = initial_dir
	primary_file_dialog.file_selected.connect(_on_primary_file_selected)
	add_child(primary_file_dialog)

	fallback_file_dialog = FileDialog.new()
	fallback_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fallback_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	fallback_file_dialog.use_native_dialog = true
	fallback_file_dialog.min_size = Vector2i(700, 480)
	fallback_file_dialog.filters = font_filters
	if not initial_dir.is_empty():
		fallback_file_dialog.current_dir = initial_dir
	fallback_file_dialog.file_selected.connect(_on_fallback_file_selected)
	add_child(fallback_file_dialog)

func _get_initial_browse_dir() -> String:
	var candidates := [
		OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS),
		OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS),
		OS.get_environment("HOME"),
		OS.get_executable_path().get_base_dir()
	]
	for dir in candidates:
		if not dir.is_empty() and DirAccess.dir_exists_absolute(dir):
			return dir
	return ""

func _get_bundled_font_path() -> String:
	var candidates := [
		"res://assets/fonts/DejaVuSans.ttf",
		OS.get_executable_path().get_base_dir().path_join("assets/fonts/DejaVuSans.ttf"),
		OS.get_executable_path().get_base_dir().path_join("DejaVuSans.ttf")
	]
	for p in candidates:
		if p.begins_with("res://"):
			if ResourceLoader.exists(p) or FileAccess.file_exists(p):
				return p
		elif FileAccess.file_exists(p):
			return p
	return ""

func _check_default_font() -> void:
	var font_path := _get_bundled_font_path()
	if not font_path.is_empty() and AppState.primary_font_path.is_empty():
		_load_font(font_path, true)

func _on_browse_primary_pressed() -> void:
	if primary_file_dialog.use_native_dialog:
		primary_file_dialog.show()
	else:
		primary_file_dialog.popup_centered_ratio(0.7)

func _on_use_bundled_font_pressed() -> void:
	var font_path := _get_bundled_font_path()
	if not font_path.is_empty():
		_load_font(font_path, true)
	else:
		push_warning("Bundled font DejaVuSans.ttf not found.")

func _on_add_fallback_pressed() -> void:
	if fallback_file_dialog.use_native_dialog:
		fallback_file_dialog.show()
	else:
		fallback_file_dialog.popup_centered_ratio(0.7)

func _on_clear_fallbacks_pressed() -> void:
	AppState.clear_fallbacks()
	for child in fallback_list.get_children():
		child.queue_free()

func _on_primary_file_selected(path: String) -> void:
	primary_file_dialog.current_dir = path.get_base_dir()
	fallback_file_dialog.current_dir = path.get_base_dir()
	_load_font(path, true)

func _on_fallback_file_selected(path: String) -> void:
	fallback_file_dialog.current_dir = path.get_base_dir()
	_load_font(path, false)

func _load_font(path: String, is_primary: bool) -> void:
	if is_primary:
		primary_path_edit.text = path
		AppState.load_primary_font(path)
	else:
		AppState.add_fallback_font(path)

func _on_font_loaded(path: String, is_primary: bool) -> void:
	if is_primary:
		primary_path_edit.text = path.get_file()
		primary_path_edit.tooltip_text = path
		if path.ends_with("DejaVuSans.ttf"):
			font_info_label.text = "Active: DejaVu Sans (Bundled Demo)"
		else:
			font_info_label.text = "Active: %s" % path.get_file()
	else:
		var lbl: Label = Label.new()
		lbl.text = "• " + path.get_file()
		lbl.tooltip_text = path
		lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lbl.clip_text = true
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
		fallback_list.add_child(lbl)
