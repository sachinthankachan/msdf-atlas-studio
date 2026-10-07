class_name ExportDialog
extends ConfirmationDialog

@onready var dir_edit: LineEdit = $VBox/DirContainer/DirEdit
@onready var browse_dir_btn: Button = $VBox/DirContainer/BrowseButton
@onready var filename_edit: LineEdit = $VBox/FileContainer/FilenameEdit

@onready var chk_png: CheckBox = $VBox/FormatsGrid/ChkPng
@onready var chk_json: CheckBox = $VBox/FormatsGrid/ChkJson
@onready var chk_bmfont_txt: CheckBox = $VBox/FormatsGrid/ChkBMFontTxt
@onready var chk_bmfont_xml: CheckBox = $VBox/FormatsGrid/ChkBMFontXml
@onready var chk_godot_tres: CheckBox = $VBox/FormatsGrid/ChkGodotTres
@onready var chk_c_header: CheckBox = $VBox/FormatsGrid/ChkCHeader
@onready var chk_shaders: CheckBox = $VBox/FormatsGrid/ChkShaders
@onready var status_label: Label = $VBox/StatusLabel

var folder_dialog: FileDialog

func _ready() -> void:
	title = "Export Assets & Metadata"
	ok_button_text = "Export Assets"

	dir_edit.text = "user://exports"
	filename_edit.text = "msdf_atlas"

	_setup_folder_dialog()

	browse_dir_btn.pressed.connect(_on_browse_dir_pressed)
	confirmed.connect(_on_export_confirmed)
	dir_edit.focus_exited.connect(_on_dir_edit_focus_exited)

func _setup_folder_dialog() -> void:
	folder_dialog = FileDialog.new()
	folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	folder_dialog.use_native_dialog = false
	folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	folder_dialog.title = "Select Export Destination Folder"
	folder_dialog.ok_button_text = "Select Current Folder"
	folder_dialog.min_size = Vector2i(750, 500)
	folder_dialog.dir_selected.connect(_apply_selected_directory)
	folder_dialog.file_selected.connect(func(file_path: String):
		_apply_selected_directory(file_path.get_base_dir())
	)
	add_child(folder_dialog)

func _get_browse_start_dir() -> String:
	var current_text := dir_edit.text.strip_edges()
	if not current_text.is_empty():
		var global_current := ProjectSettings.globalize_path(current_text)
		if DirAccess.dir_exists_absolute(global_current):
			return global_current
		elif FileAccess.file_exists(global_current):
			return global_current.get_base_dir()
		elif DirAccess.dir_exists_absolute(current_text):
			return current_text
		elif FileAccess.file_exists(current_text):
			return current_text.get_base_dir()

	var candidates := [
		OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS),
		OS.get_environment("HOME"),
		OS.get_environment("USERPROFILE"),
		OS.get_executable_path().get_base_dir()
	]
	for dir in candidates:
		if not dir.is_empty() and DirAccess.dir_exists_absolute(dir):
			return dir
	return ""

func _on_browse_dir_pressed() -> void:
	var start_dir := _get_browse_start_dir()

	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG):
		var err := DisplayServer.file_dialog_show(
			"Select Export Destination Folder",
			start_dir,
			"",
			false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_DIR,
			PackedStringArray(),
			_on_native_folder_callback
		)
		if err == OK:
			return

	if not start_dir.is_empty():
		folder_dialog.current_dir = start_dir
	folder_dialog.popup_centered_ratio(0.7)

func _on_native_folder_callback(status: bool, selected_paths: PackedStringArray, _selected_filter_index: int) -> void:
	if not status or selected_paths.is_empty():
		return
	var picked := selected_paths[0].strip_edges()
	if picked.is_empty():
		return
	_apply_selected_directory(picked)

func _apply_selected_directory(path: String) -> void:
	var resolved := path.strip_edges()
	if FileAccess.file_exists(resolved):
		resolved = resolved.get_base_dir()
	elif not DirAccess.dir_exists_absolute(resolved) and not resolved.get_extension().is_empty():
		resolved = resolved.get_base_dir()
	if resolved.is_empty():
		resolved = "user://exports"
	dir_edit.text = resolved

func _on_dir_edit_focus_exited() -> void:
	var text_val := dir_edit.text.strip_edges()
	if text_val.is_empty():
		dir_edit.text = "user://exports"
		return
	if FileAccess.file_exists(text_val):
		dir_edit.text = text_val.get_base_dir()

func _on_export_confirmed() -> void:
	if not AppState or AppState.current_metadata.is_empty():
		status_label.text = "Error: No generated atlas to export."
		return

	var out_dir: String = dir_edit.text.strip_edges()
	if FileAccess.file_exists(out_dir):
		out_dir = out_dir.get_base_dir()
	elif not DirAccess.dir_exists_absolute(out_dir) and not out_dir.get_extension().is_empty():
		out_dir = out_dir.get_base_dir()
	if out_dir.is_empty():
		out_dir = "user://exports"
	dir_edit.text = out_dir

	var base_name: String = filename_edit.text.strip_edges()
	if base_name.is_empty(): base_name = "msdf_atlas"

	if not DirAccess.dir_exists_absolute(out_dir):
		DirAccess.make_dir_recursive_absolute(out_dir)

	var metadata: Dictionary = AppState.current_metadata
	var img: Image = AppState.current_image
	var png_filename: String = base_name + ".png"
	var png_path: String = out_dir.path_join(png_filename)

	var exported_count: int = 0

	if chk_png.button_pressed and img:
		if img.save_png(png_path) == OK:
			exported_count += 1

	if chk_json.button_pressed:
		var json_path: String = out_dir.path_join(base_name + ".json")
		if JsonExporter.export_to_file(json_path, metadata) == OK:
			exported_count += 1

	if chk_bmfont_txt.button_pressed:
		var fnt_path: String = out_dir.path_join(base_name + ".fnt")
		if BMFontExporter.export_text(fnt_path, metadata, png_filename, base_name) == OK:
			exported_count += 1

	if chk_bmfont_xml.button_pressed:
		var xml_path: String = out_dir.path_join(base_name + "_bmfont.xml")
		if BMFontExporter.export_xml(xml_path, metadata, png_filename, base_name) == OK:
			exported_count += 1

	if chk_godot_tres.button_pressed:
		var tres_path: String = out_dir.path_join(base_name + ".tres")
		var sp: Dictionary = AppState.shader_params if AppState else {}
		if GodotResourceExporter.export_font_resource(tres_path, metadata, img, sp) == OK:
			exported_count += 1

	if chk_c_header.button_pressed:
		var h_path: String = out_dir.path_join(base_name + ".h")
		if CHeaderExporter.export_header(h_path, metadata, base_name) == OK:
			exported_count += 1

	if chk_shaders.button_pressed:
		if CHeaderExporter.export_shader_bundle(out_dir) == OK:
			exported_count += 3

	status_label.text = "Successfully exported %d files to:\n%s" % [exported_count, out_dir]
	AppState.status_message_updated.emit("Export complete: %d assets saved." % exported_count)
