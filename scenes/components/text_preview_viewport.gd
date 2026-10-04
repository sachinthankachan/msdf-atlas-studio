class_name TextPreviewViewport
extends Control

@onready var pan_zoom: SmoothPanZoom = $PanZoomContainer
@onready var preview_controller: LivePreviewController = $PanZoomContainer/Content/PreviewController
@onready var background_rect: ColorRect = $PanZoomContainer/Background
@onready var size_slider: HSlider = $Toolbar/FontSizeContainer/SizeSlider
@onready var size_spin: SpinBox = $Toolbar/FontSizeContainer/SizeSpin
@onready var bg_option: OptionButton = $Toolbar/BgOption
@onready var kern_toggle: Button = $Toolbar/KernToggle
@onready var zoom_label: Label = $Toolbar/ZoomLabel
@onready var btn_zoom_in: Button = $Toolbar/ZoomIn
@onready var btn_zoom_out: Button = $Toolbar/ZoomOut
@onready var btn_zoom_reset: Button = $Toolbar/ZoomReset
@onready var btn_zoom_fit: Button = $Toolbar/ZoomFit
@onready var text_edit: TextEdit = $InputDrawer/TextEdit

var bg_material: ShaderMaterial = null

func _ready() -> void:
	bg_material = ShaderMaterial.new()
	bg_material.shader = load("res://shaders/checkerboard_background.gdshader")
	background_rect.material = bg_material

	_setup_toolbar()
	_on_bg_selected(bg_option.selected)
	pan_zoom.zoom_changed.connect(_on_zoom_changed)
	size_slider.value_changed.connect(_on_font_size_changed)
	size_spin.value_changed.connect(_on_font_size_changed)
	text_edit.text_changed.connect(_on_text_changed)
	visibility_changed.connect(_on_visibility_changed)

	pan_zoom.target_pan = Vector2(50, 40)
	pan_zoom.current_pan = Vector2(50, 40)
	pan_zoom.target_zoom = 1.0
	pan_zoom.current_zoom = 1.0

	text_edit.text = "The quick brown fox jumps over the lazy dog.\n0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz !@#$%^&*()_+"
	preview_controller.set_preview_text(text_edit.text)

func get_preview_settings() -> Dictionary:
	return {
		"sample_text": text_edit.text,
		"font_size": size_slider.value,
		"bg_option": bg_option.selected,
		"kerning_enabled": kern_toggle.button_pressed if kern_toggle else true
	}

func set_preview_settings(data: Dictionary) -> void:
	if data.has("sample_text"):
		text_edit.text = str(data["sample_text"])
		preview_controller.set_preview_text(text_edit.text)
	if data.has("font_size"):
		var sz: float = float(data["font_size"])
		size_slider.value = sz
		size_spin.value = sz
		preview_controller.set_font_size(sz)
	if data.has("bg_option"):
		var bg_idx: int = int(data["bg_option"])
		bg_option.select(bg_idx)
		_on_bg_selected(bg_idx)
	if data.has("kerning_enabled") and kern_toggle:
		kern_toggle.button_pressed = bool(data["kerning_enabled"])
		preview_controller.set_kerning_enabled(kern_toggle.button_pressed)

func _setup_toolbar() -> void:
	bg_option.clear()
	bg_option.add_item("Dark (#121214)", 0)
	bg_option.add_item("Light (#FAFAFA)", 1)
	bg_option.add_item("Checkerboard", 2)
	bg_option.item_selected.connect(_on_bg_selected)
	kern_toggle.toggled.connect(_on_kern_toggled)

	btn_zoom_in.pressed.connect(func(): pan_zoom.set_zoom_level(pan_zoom.target_zoom * 1.25))
	btn_zoom_out.pressed.connect(func(): pan_zoom.set_zoom_level(pan_zoom.target_zoom / 1.25))
	btn_zoom_fit.pressed.connect(_fit_text_to_view)
	btn_zoom_reset.pressed.connect(func():
		pan_zoom.target_zoom = 1.0
		pan_zoom.target_pan = Vector2(50, 40)
		pan_zoom.zoom_changed.emit(1.0)
		pan_zoom.pan_changed.emit(Vector2(50, 40))
	)

func _fit_text_to_view() -> void:
	var view_size: Vector2 = pan_zoom.size
	if view_size.x <= 0 or view_size.y <= 0:
		return
	var text_size: Vector2 = preview_controller.custom_minimum_size
	if text_size.x <= 0 or text_size.y <= 0:
		text_size = Vector2(800, 400)
	var margin: float = 60.0
	var scale_x: float = (view_size.x - margin * 2.0) / text_size.x
	var scale_y: float = (view_size.y - margin * 2.0) / text_size.y
	var fit_zoom: float = clamp(min(scale_x, scale_y), pan_zoom.min_zoom, 2.0)
	pan_zoom.target_zoom = fit_zoom
	pan_zoom.target_pan = Vector2(margin, margin)
	pan_zoom.zoom_changed.emit(fit_zoom)
	pan_zoom.pan_changed.emit(pan_zoom.target_pan)

func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		if pan_zoom.current_pan == Vector2.ZERO or pan_zoom.target_pan.x < 0 or pan_zoom.target_pan.y < 0:
			pan_zoom.target_pan = Vector2(50, 40)
			pan_zoom.current_pan = Vector2(50, 40)
			pan_zoom.target_zoom = 1.0
			pan_zoom.current_zoom = 1.0
		preview_controller.rebuild_text()

func _on_font_size_changed(val: float) -> void:
	if size_slider.value != val: size_slider.value = val
	if size_spin.value != val: size_spin.value = val
	preview_controller.set_font_size(val)

func _on_text_changed() -> void:
	preview_controller.set_preview_text(text_edit.text)

func _on_bg_selected(idx: int) -> void:
	if bg_material:
		bg_material.set_shader_parameter("bg_mode", idx)

func _on_zoom_changed(z: float) -> void:
	zoom_label.text = "%d%%" % int(round(z * 100.0))

func _on_kern_toggled(pressed: bool) -> void:
	preview_controller.set_kerning_enabled(pressed)
