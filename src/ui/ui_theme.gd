extends Node

## Centralized theme for the game's UI. Runs as an autoload so accent colors
## can react to biome changes via LevelManager.floor_changed.

signal palette_changed

const PIXEL_FONT := preload("res://textures/Assets/DawnLike/GUI/SDS_8x8.ttf")

const FONT_SIZE_BODY := 16
const FONT_SIZE_TITLE := 32

# Neutral base palette (constant across biomes).
const BG_DEEP := Color(0.102, 0.078, 0.063, 1)        # #1a1410
const BG_MID := Color(0.165, 0.125, 0.102, 1)         # #2a201a
const INK := Color(0.910, 0.847, 0.722, 1)            # #e8d8b8
const INK_DIM := Color(0.541, 0.471, 0.376, 1)        # #8a7860

# Default accent (caves orange) — used until LevelManager reports a biome.
const DEFAULT_ACCENT := Color(0.851, 0.467, 0.259, 1) # #d97742

# Status colors (palette-independent).
const DANGER := Color(0.85, 0.20, 0.20, 1)
const SUCCESS := Color(0.267, 0.667, 0.267, 1)
const SHADOW := Color(0, 0, 0, 0.5)

# Backward-compatibility aliases for existing callers
const DEEP_BG := BG_DEEP
const SURFACE_BG := BG_MID
const PANEL_BG := BG_DEEP
const TEXT_PRIMARY := INK
const TEXT_SECONDARY := INK_DIM

const RARITY_COMMON := Color(1, 1, 1, 1)
const RARITY_UNCOMMON := Color(0.35, 0.66, 1.0, 1)
const RARITY_RARE := Color(1.0, 0.843, 0.0, 1)

# Mutable accent + derived border color, swapped on biome change.
static var accent: Color = DEFAULT_ACCENT
static var _theme: Theme = null

static var ACCENT: Color = DEFAULT_ACCENT
static var ACCENT_GOLD: Color = DEFAULT_ACCENT
static var PANEL_BORDER: Color = DEFAULT_ACCENT

func _ready() -> void:
	_build_theme()
	if Engine.has_singleton("LevelManager") or _has_autoload("LevelManager"):
		LevelManager.floor_changed.connect(_on_floor_changed)
		_on_floor_changed(0)

func _has_autoload(name: String) -> bool:
	return get_tree() != null and get_tree().root.has_node(name)

static func get_theme() -> Theme:
	if _theme == null:
		_build_theme()
	return _theme

static func get_rarity_color(rarity: int) -> Color:
	match rarity:
		DropTable.ItemTier.UNCOMMON:
			return RARITY_UNCOMMON
		DropTable.ItemTier.RARE:
			return RARITY_RARE
		_:
			return RARITY_COMMON

func set_accent(c: Color) -> void:
	accent = c
	ACCENT = c
	ACCENT_GOLD = c
	PANEL_BORDER = c
	_apply_accent()
	palette_changed.emit()

func _on_floor_changed(_floor: int) -> void:
	var biome: BiomeDef = LevelManager.get_biome()
	if biome == null:
		return
	set_accent(biome.ui_accent)

static func _build_theme() -> void:
	var t := Theme.new()
	t.default_font = PIXEL_FONT
	t.default_font_size = FONT_SIZE_BODY
	_set_button_styles(t)
	_set_label_styles(t)
	_set_panel_styles(t)
	_set_slider_styles(t)
	_set_separator_styles(t)
	_set_container_constants(t)
	_theme = t
	_apply_accent()

static func _apply_accent() -> void:
	if _theme == null:
		return
	var t := _theme
	t.set_color("font_color", "TitleLabel", accent)
	# Button hover/focus colors track the accent.
	t.set_color("font_hover_color", "Button", accent)
	t.set_color("font_focus_color", "Button", accent)
	# Stylebox border colors track the accent.
	var btn_hover: StyleBoxFlat = t.get_stylebox("hover", "Button")
	if btn_hover != null:
		btn_hover.border_color = accent
	var btn_focused: StyleBoxFlat = t.get_stylebox("focused", "Button")
	if btn_focused != null:
		btn_focused.border_color = accent
	var panel_sb: StyleBoxFlat = t.get_stylebox("panel", "PanelContainer")
	if panel_sb != null:
		panel_sb.border_color = accent
	var slider_track: StyleBoxFlat = t.get_stylebox("slider", "HSlider")
	if slider_track != null:
		slider_track.border_color = accent
	var slider_grab: StyleBoxFlat = t.get_stylebox("grabber_area", "HSlider")
	if slider_grab != null:
		slider_grab.bg_color = accent
		slider_grab.border_color = accent
	var slider_grab_hi: StyleBoxFlat = t.get_stylebox("grabber_area_highlight", "HSlider")
	if slider_grab_hi != null:
		slider_grab_hi.bg_color = accent
		slider_grab_hi.border_color = accent

static func _make_panel_stylebox() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BG_DEEP
	s.border_color = accent
	s.set_border_width_all(2)
	s.set_corner_radius_all(0)
	s.set_content_margin_all(16)
	return s

static func _make_button_stylebox(normal: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BG_MID if normal else BG_DEEP
	s.border_color = INK_DIM if normal else accent
	s.set_border_width_all(2)
	s.set_corner_radius_all(0)
	s.set_content_margin_all(8)
	s.content_margin_left = 16
	s.content_margin_right = 16
	return s

static func _set_button_styles(t: Theme) -> void:
	var normal := _make_button_stylebox(true)
	var hover := _make_button_stylebox(false)
	var pressed := _make_button_stylebox(false)
	var focused := _make_button_stylebox(false)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focused", "Button", focused)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", accent)
	t.set_color("font_pressed_color", "Button", INK_DIM)
	t.set_color("font_focus_color", "Button", accent)
	t.set_color("font_disabled_color", "Button", INK_DIM)
	t.set_font_size("font_size", "Button", FONT_SIZE_BODY)

static func _set_label_styles(t: Theme) -> void:
	t.set_color("font_color", "Label", INK)
	t.set_font_size("font_size", "Label", FONT_SIZE_BODY)
	# Variation "Title" for screen/section headers.
	t.set_type_variation("TitleLabel", "Label")
	t.set_color("font_color", "TitleLabel", accent)
	t.set_font_size("font_size", "TitleLabel", FONT_SIZE_TITLE)

static func _set_panel_styles(t: Theme) -> void:
	t.set_stylebox("panel", "PanelContainer", _make_panel_stylebox())

static func _set_slider_styles(t: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = BG_DEEP
	track.border_color = accent
	track.set_border_width_all(2)
	track.set_corner_radius_all(0)
	track.set_content_margin_all(4)
	track.content_margin_left = 0
	track.content_margin_right = 0
	var fill := StyleBoxFlat.new()
	fill.bg_color = accent
	fill.border_color = accent
	fill.set_border_width_all(2)
	fill.set_corner_radius_all(0)
	fill.set_content_margin_all(4)
	fill.content_margin_left = 0
	fill.content_margin_right = 0
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_font_size("font_size", "HSlider", FONT_SIZE_BODY)

static func _set_separator_styles(t: Theme) -> void:
	var sep := StyleBoxFlat.new()
	sep.bg_color = Color(0, 0, 0, 0)
	sep.border_color = INK_DIM
	sep.border_width_top = 1
	sep.set_content_margin_all(4)
	sep.content_margin_left = 0
	sep.content_margin_right = 0
	t.set_stylebox("separator", "HSeparator", sep)

static func _set_container_constants(t: Theme) -> void:
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)

static func get_card_shadow_stylebox() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.12)
	s.set_corner_radius_all(0)
	return s
