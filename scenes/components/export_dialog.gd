class_name ExportDialog
extends ConfirmationDialog

const JsonExporter = preload("res://scripts/exporters/json_exporter.gd")
const BMFontExporter = preload("res://scripts/exporters/bmfont_exporter.gd")
const GodotResourceExporter = preload("res://scripts/exporters/godot_resource_exporter.gd")
const CHeaderExporter = preload("res://scripts/exporters/c_header_exporter.gd")

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

	folder_dialog = FileDialog.new()
	folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	folder_dialog.use_native_dialog = true
	folder_dialog.min_size = Vector2i(700, 480)
	var initial_dir := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if initial_dir.is_empty() or not DirAccess.dir_exists_absolute(initial_dir):
		initial_dir = OS.get_environment("HOME")
	if not initial_dir.is_empty():
		folder_dialog.current_dir = initial_dir
	folder_dialog.dir_selected.connect(_on_dir_selected)
	add_child(folder_dialog)

	browse_dir_btn.pressed.connect(func(): folder_dialog.popup_centered_ratio(0.6))
	confirmed.connect(_on_export_confirmed)

func _on_dir_selected(dir: String) -> void:
	dir_edit.text = dir

func _on_export_confirmed() -> void:
	if not AppState or AppState.current_metadata.is_empty():
		status_label.text = "Error: No generated atlas to export."
		return

	var out_dir: String = dir_edit.text.strip_edges()
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
