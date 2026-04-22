class_name UiTheme

const PIXEL_FONT := preload("res://textures/Assets/DawnLike/GUI/SDS_8x8.ttf")

const DEEP_BG := Color(0.102, 0.059, 0.071, 1)
const SURFACE_BG := Color(0.165, 0.082, 0.098, 1)
const PANEL_BG := Color(0.212, 0.110, 0.133, 1)
const PANEL_BORDER := Color(0.545, 0.227, 0.165, 1)
const ACCENT := Color(1.000, 0.420, 0.208, 1)
const ACCENT_GOLD := Color(1.000, 0.843, 0.000, 1)
const TEXT_PRIMARY := Color(0.941, 0.902, 0.827, 1)
const TEXT_SECONDARY := Color(0.659, 0.565, 0.502, 1)
const DANGER := Color(0.800, 0.200, 0.200, 1)
const SUCCESS := Color(0.267, 0.667, 0.267, 1)
const SHADOW := Color(0, 0, 0, 0.502)

static var _theme: Theme

static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme

static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = PIXEL_FONT
	t.default_font_size = 20

	_set_button_styles(t)
	_set_label_styles(t)
	_set_panel_styles(t)
	_set_slider_styles(t)
	_set_separator_styles(t)
	_set_container_constants(t)
	return t

static func _make_panel_stylebox() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL_BG
	s.border_color = PANEL_BORDER
	s.set_border_width_all(2)
	s.set_corner_radius_all(8)
	s.set_content_margin_all(8)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.shadow_color = SHADOW
	s.shadow_offset = Vector2(4, 4)
	s.shadow_size = 8
	return s

static func _make_button_stylebox(normal: bool = true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = SURFACE_BG if normal else PANEL_BG
	s.border_color = PANEL_BORDER
	s.set_border_width_all(2)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(6)
	s.content_margin_left = 10
	s.content_margin_right = 10
	return s

static func _set_button_styles(t: Theme) -> void:
	var normal := _make_button_stylebox(true)
	var hover := _make_button_stylebox(false)
	hover.border_color = ACCENT
	var pressed := _make_button_stylebox(true)
	pressed.bg_color = DEEP_BG
	var focused := _make_button_stylebox(true)
	focused.border_color = ACCENT_GOLD

	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focused", "Button", focused)
	t.set_color("font_color", "Button", TEXT_PRIMARY)
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_pressed_color", "Button", TEXT_SECONDARY)
	t.set_color("font_focus_color", "Button", ACCENT_GOLD)
	t.set_font_size("font_size", "Button", 20)

static func _set_label_styles(t: Theme) -> void:
	t.set_color("font_color", "Label", TEXT_PRIMARY)
	t.set_font_size("font_size", "Label", 20)

static func _set_panel_styles(t: Theme) -> void:
	t.set_stylebox("panel", "PanelContainer", _make_panel_stylebox())

static func _set_slider_styles(t: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = DEEP_BG
	track.border_color = PANEL_BORDER
	track.set_border_width_all(2)
	track.set_corner_radius_all(4)
	track.set_content_margin_all(4)
	track.content_margin_left = 0
	track.content_margin_right = 0

	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.border_color = PANEL_BORDER
	fill.set_border_width_all(2)
	fill.set_corner_radius_all(4)
	fill.set_content_margin_all(4)
	fill.content_margin_left = 0
	fill.content_margin_right = 0

	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_font_size("font_size", "HSlider", 14)

static func _set_separator_styles(t: Theme) -> void:
	var sep := StyleBoxFlat.new()
	sep.bg_color = Color(0, 0, 0, 0)
	sep.border_color = PANEL_BORDER
	sep.border_width_top = 1
	sep.set_content_margin_all(4)
	sep.content_margin_left = 0
	sep.content_margin_right = 0
	t.set_stylebox("separator", "HSeparator", sep)

static func _set_container_constants(t: Theme) -> void:
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 8)