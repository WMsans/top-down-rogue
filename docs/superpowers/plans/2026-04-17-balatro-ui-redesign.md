# Balatro-Inspired UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the game's UI from bare default controls to a cohesive dark/fire-themed design with card-like panels, tween-based animations, and 3 hero shaders.

**Architecture:** A shared `UiTheme` GDScript class centralizes all colors, fonts, and StyleBoxFlat definitions. A `UiAnimations` static class provides reusable tween helpers. Three shaders provide hero visual effects for health bar, death screen, and weapon cards. All 7 UI scripts replace their `_apply_theme()` methods with the shared theme and add animations.

**Tech Stack:** GDScript, Godot 4.x ShaderLanguage, Tween-based animations, StyleBoxFlat for panels/buttons

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `src/ui/ui_theme.gd` | Create | Centralized theme builder — colors, fonts, StyleBoxFlat definitions |
| `src/ui/ui_animations.gd` | Create | Reusable tween animation helpers (bounce, slide_in, fade_in, pulse) |
| `shaders/ui/health_bar_shimmer.gdshader` | Create | Flowing gradient shimmer on health bar fill |
| `shaders/ui/death_vignette.gdshader` | Create | Pulsing red vignette overlay on death screen |
| `shaders/ui/card_hover_glow.gdshader` | Create | Inner orange glow on hovered weapon cards |
| `scenes/ui/health_ui.tscn` | Modify | Expand bar to 200×14, add shader material, style margins |
| `src/ui/health_ui.gd` | Modify | Replace _apply_theme, add damage flash / low-health pulse animations |
| `scenes/ui/main_menu.tscn` | Modify | Replace background color, add title labels, wrap buttons in PanelContainer |
| `src/ui/main_menu.gd` | Modify | Replace _apply_theme, add entrance/interaction animations |
| `scenes/ui/pause_menu.tscn` | Modify | Update dimmer opacity, wrap content in PanelContainer |
| `src/ui/pause_menu.gd` | Modify | Replace _apply_theme, add slide-in/fade animations, style buttons |
| `scenes/ui/death_screen.tscn` | Modify | Add VignetteOverlay node with shader material |
| `src/ui/death_screen.gd` | Modify | Replace _apply_theme, enhanced death sequence with shake/scale/vignette |
| `scenes/ui/settings_popup.tscn` | Modify | Widen panel, restyle section headers |
| `src/ui/settings_popup.gd` | Modify | Replace _apply_theme, style gold section headers |
| `scenes/ui/weapon_button.tscn` | Modify | Expand icon to 64px, update tooltip positioning |
| `src/ui/weapon_button.gd` | Modify | Replace _apply_theme, add bounce/tooltip animations |
| `scenes/ui/weapon_popup.tscn` | Modify | Update overlay opacity, update title |
| `src/ui/weapon_popup.gd` | Modify | Replace _apply_theme, add card stagger/hover animations, card glow shader |

---

## Task 1: Create Shared Theme — `src/ui/ui_theme.gd`

**Files:**
- Create: `src/ui/ui_theme.gd`

The theme is implemented as a GDScript class rather than a hand-written `.tres` file, since Godot's Theme `.tres` serialization format is complex to write by hand and error-prone. This class achieves the same single-source-of-truth goal: all UI scripts call `UiTheme.get_theme()` instead of creating `Theme.new()` locally.

- [ ] **Step 1: Create `src/ui/ui_theme.gd`**

```gdscript
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
```

- [ ] **Step 2: Verify the file loads without errors**

Open the Godot editor (or check the script for syntax errors manually). The file should parse without errors since it only uses built-in Godot types.

---

## Task 2: Create UI Animations Utility — `src/ui/ui_animations.gd`

**Files:**
- Create: `src/ui/ui_animations.gd`

- [ ] **Step 1: Create `src/ui/ui_animations.gd`**

```gdscript
class_name UiAnimations

static func bounce_on_hover(control: Control, scale_up: float = 1.05, duration: float = 0.15) -> Tween:
	var tween := control.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(control, "scale", Vector2(scale_up, scale_up), duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tween

static func bounce_on_press(control: Control, scale_down: float = 0.95, duration: float = 0.1) -> Tween:
	var tween := control.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(control, "scale", Vector2(scale_down, scale_down), duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	return tween

static func reset_scale(control: Control, duration: float = 0.15) -> Tween:
	var tween := control.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(control, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tween

static func slide_in_up(control: Control, pixels: float = 30.0, duration: float = 0.3) -> Tween:
	var target_pos := control.position
	control.position.y += pixels
	control.modulate.a = 0.0
	var tween := control.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.parallel().tween_property(control, "position:y", target_pos.y, duration).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(control, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_LINEAR)
	return tween

static func fade_in(control: Control, duration: float = 0.3, delay: float = 0.0) -> Tween:
	control.modulate.a = 0.0
	var tween := control.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(control, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_LINEAR)
	return tween

static func fade_overlay(control: ColorRect, target_alpha: float, duration: float = 0.25) -> Tween:
	var tween := control.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(control, "color:a", target_alpha, duration).set_trans(Tween.TRANS_LINEAR)
	return tween

static func pulse_glow(control: Control, property: String, from: float, to: float, duration: float = 1.5) -> Tween:
	var tween := control.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_loops()
	tween.tween_property(control, property, to, duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(control, property, from, duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return tween

static func stagger_slide_in(controls: Array[Control], delay_between: float = 0.1, pixels: float = 20.0, duration: float = 0.3) -> void:
	for i in controls.size():
		var control := controls[i]
		control.position.y += pixels
		control.modulate.a = 0.0
		var tween := control.create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		if i > 0:
			tween.tween_interval(delay_between * i)
		tween.parallel().tween_property(control, "position:y", control.position.y - pixels, duration).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(control, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_LINEAR)

static func setup_button_hover(button: Button, scale_up: float = 1.05, press_scale: float = 0.95) -> void:
	button.mouse_entered.connect(func() -> void:
		if not button.button_pressed:
			bounce_on_hover(button, scale_up)
	)
	button.mouse_exited.connect(func() -> void:
		reset_scale(button)
	)
	button.button_down.connect(func() -> void:
		bounce_on_press(button, press_scale)
	)
	button.button_up.connect(func() -> void:
		reset_scale(button)
	)
```

- [ ] **Step 2: Verify no syntax errors**

Check script for GDScript syntax correctness manually.

---

## Task 3: Create Health Bar Shimmer Shader — `shaders/ui/health_bar_shimmer.gdshader`

**Files:**
- Create: `shaders/ui/health_bar_shimmer.gdshader`

This shader provides a left-to-right gradient (red to orange) as its base color, plus a subtle shimmer band that flows across the bar in a loop.

- [ ] **Step 1: Create `shaders/ui/health_bar_shimmer.gdshader`**

```glsl
shader_type canvas_item;

uniform float shimmer_speed : hint_range(0.1, 5.0) = 0.5;
uniform float shimmer_width : hint_range(0.02, 0.3) = 0.08;
uniform float shimmer_brightness : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	float t = fract(TIME * shimmer_speed);
	float shimmer_pos = t;

	float dist = abs(UV.x - shimmer_pos);
	if (dist > 0.5) {
		dist = 1.0 - dist;
	}

	float shimmer = smoothstep(shimmer_width, 0.0, dist);
	float gradient = mix(0.8, 1.0, UV.x);
	vec3 base_color = mix(vec3(0.8, 0.2, 0.2), vec3(1.0, 0.42, 0.208), UV.x);
	vec3 shimmer_color = base_color + vec3(shimmer * shimmer_brightness);

	COLOR = vec4(shimmer_color * gradient, COLOR.a * texture(TEXTURE, UV).a);
}
```

- [ ] **Step 2: Verify shader compiles**

Open the Godot editor and ensure the shader has no compilation errors.

---

## Task 4: Create Death Vignette Shader — `shaders/ui/death_vignette.gdshader`

**Files:**
- Create: `shaders/ui/death_vignette.gdshader`

This shader darkens edges with a pulsing red tint. The vignette intensity and red tint oscillate over time.

- [ ] **Step 1: Create `shaders/ui/death_vignette.gdshader`**

```glsl
shader_type canvas_item;

uniform float pulse_speed : hint_range(0.1, 5.0) = 0.67;
uniform float vignette_intensity : hint_range(0.0, 2.0) = 1.2;
uniform vec4 vignette_color : source_color = vec4(0.5, 0.0, 0.0, 1.0);

void fragment() {
	vec2 uv = UV;
	float dist = distance(uv, vec2(0.5));
	float vignette = smoothstep(0.3, 0.9, dist);

	float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed * 6.283);
	float red_mix = vignette * vignette_intensity * (0.6 + 0.4 * pulse);

	vec4 base = texture(TEXTURE, UV);
	vec3 final_color = mix(base.rgb, vignette_color.rgb, red_mix);
	COLOR = vec4(final_color, base.a * vignette);
}
```

- [ ] **Step 2: Verify shader compiles**

Ensure no compilation errors in Godot.

---

## Task 5: Create Card Hover Glow Shader — `shaders/ui/card_hover_glow.gdshader`

**Files:**
- Create: `shaders/ui/card_hover_glow.gdshader`

This shader adds an inner orange glow along card edges. Toggled via `glow_enabled` uniform when mouse enters/exits.

- [ ] **Step 1: Create `shaders/ui/card_hover_glow.gdshader`**

```glsl
shader_type canvas_item;

uniform bool glow_enabled = false;
uniform vec4 glow_color : source_color = vec4(1.0, 0.42, 0.208, 1.0);
uniform float glow_width : hint_range(0.0, 0.1) = 0.02;
uniform float glow_intensity : hint_range(0.0, 1.0) = 0.6;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	if (!glow_enabled) {
		COLOR = base;
		return;
	}

	float edge_dist = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float glow = smoothstep(glow_width, 0.0, edge_dist);
	vec3 result = mix(base.rgb, glow_color.rgb, glow * glow_intensity);
	COLOR = vec4(result, base.a);
}
```

- [ ] **Step 2: Verify shader compiles**

Ensure no compilation errors in Godot.

---

## Task 6: Health UI Redesign

**Files:**
- Modify: `scenes/ui/health_ui.tscn`
- Modify: `src/ui/health_ui.gd`

### Scene Changes (`health_ui.tscn`)

In the scene file, make these structural changes:

1. Change `MarginContainer` offset to `offset_left = 12`, `offset_top = 12` (was 8, 8)
2. Change `BarBackground` `custom_minimum_size` from `Vector2(120, 10)` to `Vector2(200, 14)`
3. Change `BarBackground` color from `Color(0.2, 0.2, 0.2, 1)` to `Color(0.102, 0.059, 0.071, 1)` (DEEP_BG)
4. Add `theme_override_styles/panel` to `BarBackground` — a StyleBoxFlat with: bg_color=DEEP_BG, border_color=PANEL_BORDER (#8b3a2a), border_width_all=2, corner_radius_all=4
5. Change `BarFill` offset to `offset_right = 200.0`, `offset_bottom = 14.0` (was 120, 10)
6. Change `BarFill` color from `Color(0.8, 0.2, 0.2, 1)` to `Color(1, 1, 1, 1)` (white — the shader provides the gradient color)
7. Add a ShaderMaterial to `BarFill` referencing `res://shaders/ui/health_bar_shimmer.gdshader`
8. Replace `BarBackground` type from `ColorRect` to `PanelContainer` (to get rounded corners from theme), or apply a StyleBoxFlat override for rounded corners. Since ColorRect doesn't support StyleBox, keep it as ColorRect and apply a StyleBoxFlat through code in `_ready()`. Actually the simplest approach: keep BarBackground as ColorRect but add `clip_contents = true` (already set) and apply rounded corner styling via code. Better: change BarBackground to a `PanelContainer` in the scene, and put `BarFill` inside it.

The cleanest approach for the scene:

**Replace the current BarBackground/BarFill structure with:**
- `BarBackground` PanelContainer — min size 200x14, theme will style it with rounded card panel, but override the StyleBox to be smaller (4px corners, no shadow): `clip_contents = true`
- Inside it: `BarFill` ColorRect — uses the shader material, anchored full rect, offset_right set programmatically

### Script Changes (`health_ui.gd`)

- [ ] **Step 1: Modify `scenes/ui/health_ui.tscn`**

In the .tscn file, make these changes:

1. `MarginContainer` — change `offset_left` from `8` to `12`, `offset_top` from `8` to `12`
2. `BarBackground` — change type from `ColorRect` to `PanelContainer`, change `custom_minimum_size` to `Vector2(200, 14)`, add `clip_contents = true`
3. `BarFill` — change `color` to `Color(1, 1, 1, 1)`, change offsets to `offset_right = 200.0`, `offset_bottom = 14.0`
4. Add a ShaderMaterial sub-resource for the health bar shimmer on BarFill

The modified scene structure for the relevant nodes:

```
[node name="BarBackground" type="PanelContainer" parent="MarginContainer/VBoxContainer"]
unique_name_in_owner = true
clip_contents = true
custom_minimum_size = Vector2(200, 14)
layout_mode = 2
theme_override_styles/panel = SubResource("StyleBoxFlat_bar_bg")

[node name="BarFill" type="ColorRect" parent="MarginContainer/VBoxContainer/BarBackground"]
unique_name_in_owner = true
layout_mode = 0
offset_right = 200.0
offset_bottom = 14.0
color = Color(1, 1, 1, 1)
material = SubResource("ShaderMaterial_shimmer")
```

Add sub-resources at the top:
```
[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_bar_bg"]
bg_color = Color(0.102, 0.059, 0.071, 1)
border_color = Color(0.545, 0.227, 0.165, 1)
border_width_left = 2
border_width_right = 2
border_width_top = 2
border_width_bottom = 2
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_left = 4
corner_radius_bottom_right = 4
content_margin_left = 0.0
content_margin_right = 0.0
content_margin_top = 0.0
content_margin_bottom = 0.0

[sub_resource type="ShaderMaterial" id="ShaderMaterial_shimmer"]
shader = ExtResource("health_bar_shimmer_shader")
```

Add ext_resource for the shader:
```
[ext_resource type="Shader" path="res://shaders/ui/health_bar_shimmer.gdshader" id="health_bar_shimmer_shader"]
```

Update `load_steps` in the header to account for new sub-resources.

- [ ] **Step 2: Rewrite `src/ui/health_ui.gd`**

```gdscript
extends CanvasLayer

const SHIMMER_SHADER := preload("res://shaders/ui/health_bar_shimmer.gdshader")

@onready var _bar_background: PanelContainer = %BarBackground
@onready var _bar_fill: ColorRect = %BarFill
@onready var _health_label: Label = %HealthLabel

var _health_component: HealthComponent
var _low_health_tween: Tween = null
var _bar_bg_style: StyleBoxFlat


func _ready() -> void:
	theme = UiTheme.get_theme()
	_bar_bg_style = _bar_background.get_theme_stylebox("panel") as StyleBoxFlat
	if _bar_bg_style:
		_bar_bg_style = _bar_bg_style.duplicate()
		_bar_background.add_theme_stylebox_override("panel", _bar_bg_style)

	var shimmer_mat := ShaderMaterial.new()
	shimmer_mat.shader = SHIMMER_SHADER
	_bar_fill.material = shimmer_mat

	var player := get_tree().get_first_node_in_group("player")
	if player:
		_health_component = player.get_node("HealthComponent")
		_health_component.health_changed.connect(_on_health_changed)
		_health_component.died.connect(_on_died)
		_on_health_changed(_health_component.max_health, _health_component.max_health)


func _on_health_changed(current: int, maximum: int) -> void:
	var ratio := float(current) / float(maximum)
	_bar_fill.size.x = _bar_background.size.x * ratio

	var current_str := "%d" % current
	var max_str := " / %d" % maximum
	_health_label.clear()
	_health_label.push_color(UiTheme.ACCENT_GOLD)
	_health_label.append_text(current_str)
	_health_label.pop()
	_health_label.push_color(UiTheme.TEXT_SECONDARY)
	_health_label.append_text(max_str)
	_health_label.pop()

	if _bar_bg_style:
		if ratio <= 0.25:
			_start_low_health_pulse()
		else:
			_stop_low_health_pulse()

	if current < maximum:
		_flash_damage()


func _on_died() -> void:
	_bar_fill.size.x = 0.0
	_health_label.clear()
	_health_label.push_color(UiTheme.DANGER)
	_health_label.append_text("0")
	_health_label.pop()
	_health_label.push_color(UiTheme.TEXT_SECONDARY)
	_health_label.append_text(" / %d" % _health_component.max_health)
	_health_label.pop()
	_stop_low_health_pulse()


func _flash_damage() -> void:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_bar_fill, "color", Color.WHITE, 0.05)
	tween.tween_property(_bar_fill, "color", Color(1, 1, 1, 1), 0.05)


func _start_low_health_pulse() -> void:
	if _low_health_tween != null and _low_health_tween.is_valid():
		return
	_low_health_tween = UiAnimations.pulse_glow(self, "", 0.0, 0.0, 1.5)
	if _bar_bg_style:
		var tween := create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.set_loops()
		tween.tween_property(_bar_bg_style, "border_color", UiTheme.ACCENT, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_property(_bar_bg_style, "border_color", UiTheme.DANGER, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _stop_low_health_pulse() -> void:
	if _low_health_tween != null:
		_low_health_tween.kill()
		_low_health_tween = null
	if _bar_bg_style:
		_bar_bg_style.border_color = UiTheme.PANEL_BORDER
```

Note: The health label uses BBCode with `push_color`/`append_text`/`pop` to show current HP in gold and max HP in muted gray. The `Label` node in the scene needs `bbcode_enabled = true` set on it.

- [ ] **Step 3: Update the HealthLabel in the scene to enable BBCode**

In `scenes/ui/health_ui.tscn`, add `bbcode_enabled = true` to the HealthLabel node.

- [ ] **Step 4: Commit**

```
git add scenes/ui/health_ui.tscn src/ui/health_ui.gd
git commit -m "feat: redesign health UI with Balatro theme, shimmer shader, and low-health pulse"
```

---

## Task 7: Main Menu Redesign

**Files:**
- Modify: `scenes/ui/main_menu.tscn`
- Modify: `src/ui/main_menu.gd`

### Scene Changes (`main_menu.tscn`)

1. Change `Background` ColorRect color from `Color(0.102, 0.039, 0.18, 1)` to `Color(0.102, 0.059, 0.071, 1)` (DEEP_BG)
2. Remove `TitleSprite` Sprite2D node (unused placeholder)
3. Add two Label nodes above `ButtonContainer` for the title:
   - `TitleTop` Label — text "TOP DOWN", horizontal_alignment = center, anchored to top area
   - `TitleBottom` Label — text "ROGUE", horizontal_alignment = center, positioned below TitleTop
4. Wrap `ButtonContainer` and its three buttons inside a new `PanelContainer` node named `MenuCard` to get the card-style panel border/shadow
5. Remove the `theme_override_font_sizes/font_size = 24` overrides from the three buttons (the shared theme sets font_size = 20)

The title labels need BBCode or theme overrides for gold/orange coloring. Since the shared theme sets Label font_color to TEXT_PRIMARY, we need per-label overrides:
- `TitleTop`: font_size override = 64, font_color override = ACCENT_GOLD, outline_size = 4, outline_color = black
- `TitleBottom`: font_size override = 28, font_color override = ACCENT, outline_size = 2, outline_color = black
- `PlayButton`: font_color override = ACCENT (orange text for primary action)

The new Label nodes use `theme_override_font_sizes/font_size`, `theme_override_colors/font_color`, `theme_override_constants/outline_size`, and `theme_override_colors/font_outline_color`.

### Script Changes (`main_menu.gd`)

- [ ] **Step 1: Modify the scene to add title labels and restructure**

The scene should have this structure (simplified):

```
MainMenu (Control, script=main_menu.gd)
  Background (ColorRect, color=DEEP_BG, full rect)
  TitleTop (Label, "TOP DOWN", 64px, gold)
  TitleBottom (Label, "ROGUE", 28px, orange)
  MenuCard (PanelContainer)
    ButtonContainer (VBoxContainer)
      PlayButton (Button, "PLAY")
      SettingsButton (Button, "SETTINGS")
      QuitButton (Button, "QUIT")
  SettingsPopup (instance, hidden)
```

Key changes to the .tscn file:
- Update Background color to `Color(0.102, 0.059, 0.071, 1)`
- Remove TitleSprite node
- Add TitleTop and TitleBottom labels before ButtonContainer
- Wrap ButtonContainer inside a MenuCard PanelContainer
- Add theme overrides for title font sizes, colors, and outlines
- Add `theme_override_colors/font_color = Color(1, 0.42, 0.208, 1)` to PlayButton (orange accent)

- [ ] **Step 2: Rewrite `src/ui/main_menu.gd`**

```gdscript
extends Control

@onready var play_button: Button = %PlayButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var settings_popup: Control = %SettingsPopup
@onready var button_container: VBoxContainer = %ButtonContainer
@onready var title_top: Label = %TitleTop
@onready var title_bottom: Label = %TitleBottom

var _buttons: Array[Button] = []


func _ready() -> void:
	theme = UiTheme.get_theme()
	play_button.add_theme_color_override("font_color", UiTheme.ACCENT)
	_buttons = [play_button, settings_button, quit_button]
	for btn in _buttons:
		UiAnimations.setup_button_hover(btn)
	_connect_buttons()
	_play_entrance()


func _connect_buttons() -> void:
	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	settings_popup.closed.connect(_on_settings_closed)


func _play_entrance() -> void:
	title_top.modulate.a = 0.0
	title_bottom.modulate.a = 0.0
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.parallel().tween_property(title_top, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_LINEAR)
	tween.parallel().tween_property(title_bottom, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_LINEAR).set_delay(0.1)
	UiAnimations.slide_in_up(button_container, 20.0, 0.4)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and settings_popup.visible:
		settings_popup.close()
		get_viewport().set_input_as_handled()


func _on_play_pressed() -> void:
	SceneManager.go_to_game()


func _on_settings_pressed() -> void:
	settings_popup.open()


func _on_settings_closed() -> void:
	play_button.grab_focus()


func _on_quit_pressed() -> void:
	get_tree().quit()
```

Note: The `_apply_theme()` method is completely removed. Theme is set from `UiTheme.get_theme()`. Button hover animations use `UiAnimations.setup_button_hover()`.

- [ ] **Step 3: Commit**

```
git add scenes/ui/main_menu.tscn src/ui/main_menu.gd
git commit -m "feat: redesign main menu with Balatro theme and entrance animations"
```

---

## Task 8: Pause Menu Redesign

**Files:**
- Modify: `scenes/ui/pause_menu.tscn`
- Modify: `src/ui/pause_menu.gd`

### Scene Changes

1. Change `Dimmer` ColorRect color alpha from 0.5 to 0.7 (70% opacity per spec)
2. The `VBoxContainer` inside `CenterContainer` needs to be wrapped in a `PanelContainer` named `PauseCard` to get card-style border/shadow
3. Add `PausedLabel` theme overrides: font_size = 48, font_color = gold, outline_size = 3, font_outline_color = black
4. Add `MainMenuButton` theme override: font_color = DANGER red (#cc3333)
5. `ConfirmationBox` PanelContainer already exists and will get the theme's card style

### Script Changes

- [ ] **Step 1: Modify `scenes/ui/pause_menu.tscn`**

Key changes:
- Change Dimmer color from `Color(0, 0, 0, 0.5)` to `Color(0.102, 0.059, 0.071, 0.7)`
- Add a PanelContainer `PauseCard` wrapping the PausePanel VBoxContainer content
- Add theme overrides for PausedLabel (font_size=48, font_color=ACCENT_GOLD, outline_size=3, font_outline_color=BLACK)
- Add theme override for MainMenuButton font_color = DANGER

- [ ] **Step 2: Rewrite `src/ui/pause_menu.gd`**

```gdscript
extends CanvasLayer

@onready var pause_panel: Control = %PausePanel
@onready var resume_button: Button = %ResumeButton
@onready var settings_button: Button = %SettingsButton
@onready var main_menu_button: Button = %MainMenuButton
@onready var settings_popup: Control = %SettingsPopup
@onready var confirmation_panel: Control = %ConfirmationPanel
@onready var confirm_yes_button: Button = %ConfirmYesButton
@onready var confirm_no_button: Button = %ConfirmNoButton
@onready var pause_card: PanelContainer = %PauseCard
@onready var dimmer: ColorRect = %Dimmer

var _buttons: Array[Button] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UiTheme.get_theme()
	main_menu_button.add_theme_color_override("font_color", UiTheme.DANGER)
	main_menu_button.add_theme_color_override("font_hover_color", UiTheme.DANGER)
	confirm_yes_button.add_theme_color_override("font_color", UiTheme.DANGER)
	confirm_yes_button.add_theme_color_override("font_hover_color", UiTheme.DANGER)
	confirm_no_button.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	confirm_no_button.add_theme_color_override("font_hover_color", UiTheme.ACCENT_GOLD)
	_buttons = [resume_button, settings_button, main_menu_button]
	for btn in _buttons:
		UiAnimations.setup_button_hover(btn)
	UiAnimations.setup_button_hover(confirm_yes_button)
	UiAnimations.setup_button_hover(confirm_no_button)
	_connect_buttons()
	confirmation_panel.visible = false
	pause_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	var weapon_popup := get_tree().root.find_child("WeaponPopup", true, false)
	if weapon_popup != null and weapon_popup.visible:
		return
	if event.is_action_pressed("pause"):
		if settings_popup.visible:
			settings_popup.close()
		elif confirmation_panel.visible:
			confirmation_panel.visible = false
			_focus_first_button()
		elif pause_panel.visible:
			_resume_game()
		else:
			_show_pause()
		get_viewport().set_input_as_handled()


func _connect_buttons() -> void:
	resume_button.pressed.connect(_resume_game)
	settings_button.pressed.connect(_on_settings_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	settings_popup.closed.connect(_on_settings_closed)
	confirm_yes_button.pressed.connect(_on_confirm_yes)
	confirm_no_button.pressed.connect(_on_confirm_no)


func _show_pause() -> void:
	SceneManager.set_paused(true)
	pause_panel.visible = true
	confirmation_panel.visible = false
	dimmer.color.a = 0.0
	pause_card.position.y += 30.0
	pause_card.modulate.a = 0.0
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.parallel().tween_property(dimmer, "color:a", 0.7, 0.25).set_trans(Tween.TRANS_LINEAR)
	tween.parallel().tween_property(pause_card, "position:y", pause_card.position.y - 30.0, 0.3).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(pause_card, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_LINEAR)
	_focus_first_button()


func _resume_game() -> void:
	pause_panel.visible = false
	SceneManager.set_paused(false)


func _on_settings_pressed() -> void:
	settings_popup.open()


func _on_settings_closed() -> void:
	_focus_first_button()


func _on_main_menu_pressed() -> void:
	confirmation_panel.visible = true
	confirm_no_button.grab_focus()


func _on_confirm_yes() -> void:
	SceneManager.set_paused(false)
	pause_panel.visible = false
	SceneManager.go_to_main_menu()


func _on_confirm_no() -> void:
	confirmation_panel.visible = false
	_focus_first_button()


func _focus_first_button() -> void:
	if _buttons.size() > 0:
		_buttons[0].grab_focus()
```

- [ ] **Step 3: Commit**

```
git add scenes/ui/pause_menu.tscn src/ui/pause_menu.gd
git commit -m "feat: redesign pause menu with Balatro theme and slide-in animation"
```

---

## Task 9: Death Screen Redesign

**Files:**
- Modify: `scenes/ui/death_screen.tscn`
- Modify: `src/ui/death_screen.gd`

### Scene Changes

1. Add a new `ColorRect` node named `VignetteOverlay` at the bottom of the CanvasLayer (after Overlay/RedFlash/CenterContainer). It should be full-screen, color = black transparent, with a ShaderMaterial referencing `death_vignette.gdshader`.
2. Change Overlay color to `Color(0, 0, 0, 0)` (already is).
3. No other major scene changes needed — the `DeathVBox` and `DiedLabel`/`ContinueButton` structure stays.

Add ext_resource for the shader:
```
[ext_resource type="Shader" path="res://shaders/ui/death_vignette.gdshader" id="death_vignette_shader"]
```

Add sub_resource for ShaderMaterial:
```
[sub_resource type="ShaderMaterial" id="ShaderMaterial_vignette"]
shader = ExtResource("death_vignette_shader")
shader_parameter/pulse_speed = 0.67
shader_parameter/vignette_intensity = 1.2
```

Add the VignetteOverlay node:
```
[node name="VignetteOverlay" type="ColorRect" parent="."]
unique_name_in_owner = true
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(0, 0, 0, 0)
material = SubResource("ShaderMaterial_vignette")
```

### Script Changes

- [ ] **Step 1: Modify `scenes/ui/death_screen.tscn`**

Add the vignette shader material and VignetteOverlay node as described above. Update `load_steps`.

- [ ] **Step 2: Rewrite `src/ui/death_screen.gd`**

```gdscript
extends CanvasLayer

@onready var _overlay: ColorRect = %Overlay
@onready var _red_flash: ColorRect = %RedFlash
@onready var _died_label: Label = %DiedLabel
@onready var _continue_button: Button = %ContinueButton
@onready var _vbox: VBoxContainer = %DeathVBox
@onready var _vignette: ColorRect = %VignetteOverlay

var _health_component: HealthComponent


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	theme = UiTheme.get_theme()
	_died_label.add_theme_font_size_override("font_size", 64)
	_died_label.add_theme_color_override("font_color", UiTheme.DANGER)
	_died_label.add_theme_constant_override("outline_size", 4)
	_died_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_continue_button.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	_continue_button.add_theme_color_override("font_hover_color", UiTheme.ACCENT_GOLD)
	UiAnimations.setup_button_hover(_continue_button, 1.05, 0.95)
	_continue_button.pressed.connect(_on_continue_pressed)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		_health_component = player.get_node("HealthComponent")
		_health_component.died.connect(_on_player_died)


func _on_player_died() -> void:
	visible = true
	SceneManager.set_paused(true)
	_play_death_sequence()


func _play_death_sequence() -> void:
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.visible = true
	_red_flash.color = Color(0.6, 0, 0, 0)
	_red_flash.visible = true
	_vignette.color = Color(0, 0, 0, 0)
	_vignette.visible = true
	_died_label.modulate.a = 0.0
	_died_label.scale = Vector2(0.6, 0.6)
	_continue_button.modulate.a = 0.0
	_continue_button.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

	# Red flash: 0 → 0.6 in 0.08s, then 0.6 → 0 in 0.5s
	tween.tween_property(_red_flash, "color:a", 0.6, 0.08).from(0.0)
	tween.tween_property(_red_flash, "color:a", 0.0, 0.5)

	# Screen shake on the VBox
	tween.parallel().tween_property(_vbox, "position:x", 4.0, 0.075).from(0.0).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(_vbox, "position:x", -4.0, 0.075).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(_vbox, "position:x", 3.0, 0.075).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(_vbox, "position:x", -2.0, 0.075).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(_vbox, "position:x", 0.0, 0.075).set_trans(Tween.TRANS_SINE)

	# Dark overlay: 0 → 0.8 over 0.8s
	tween.parallel().tween_property(_overlay, "color:a", 0.8, 0.8).from(0.0).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)

	# Vignette fades in
	tween.parallel().tween_property(_vignette, "color:a", 1.0, 0.8).from(0.0)

	# "YOU DIED" scale 0.6 → 1.0 over 0.5s with back ease-out
	tween.tween_property(_died_label, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_died_label, "modulate:a", 1.0, 0.3)

	# Continue button fades in after 0.7s delay
	tween.tween_interval(0.7)
	tween.tween_property(_continue_button, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(_on_sequence_complete)


func _on_sequence_complete() -> void:
	_continue_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_continue_button.grab_focus()


func _on_continue_pressed() -> void:
	SceneManager.set_paused(false)
	SceneManager.go_to_main_menu()
```

- [ ] **Step 3: Commit**

```
git add scenes/ui/death_screen.tscn src/ui/death_screen.gd shaders/ui/death_vignette.gdshader
git commit -m "feat: redesign death screen with enhanced sequence, vignette shader, and Balatro theme"
```

---

## Task 10: Settings Popup Redesign

**Files:**
- Modify: `scenes/ui/settings_popup.tscn`
- Modify: `src/ui/settings_popup.gd`

### Scene Changes

1. Change `Dimmer` color from `Color(0, 0, 0, 0.5)` to `Color(0.102, 0.059, 0.071, 0.7)` (70% deep bg)
2. Change `Panel` size from 360×400 to 400×500 (`offset_left = -200`, `offset_top = -250`, `offset_right = 200`, `offset_bottom = 250`)
3. Section header labels (AudioLabel "AUDIO", DisplayLabel "DISPLAY", KeysLabel "KEY BINDINGS") need text updates to "-- AUDIO --", "-- DISPLAY --", "-- KEY BINDINGS --" (already have `--` in their text)
4. These section headers need gold color override: add `theme_override_colors/font_color = ACCENT_GOLD`
5. `TitleLabel` needs gold color override
6. `CloseButton` and `BackButton` are standard buttons and get the theme's button style

### Script Changes

- [ ] **Step 1: Modify `scenes/ui/settings_popup.tscn`**

Update overlay color and panel size. Add theme color overrides for section headers and title.

- [ ] **Step 2: Rewrite `src/ui/settings_popup.gd`**

```gdscript
extends Control

signal closed

const SETTINGS_PATH := "user://settings.cfg"

const SECTION_AUDIO := "audio"
const SECTION_DISPLAY := "display"
const SECTION_KEYS := "keys"

var _rebinding_action := ""
var _rebinding_label: Label = null

@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider
@onready var fullscreen_button: Button = %FullscreenButton
@onready var close_button: Button = %CloseButton
@onready var back_button: Button = %BackButton
@onready var key_bindings_container: VBoxContainer = %KeyBindingsContainer
@onready var panel: PanelContainer = %Panel
@onready var dimmer: ColorRect = %Dimmer


func _ready() -> void:
	theme = UiTheme.get_theme()
	_style_section_headers()
	_connect_signals()
	_setup_button_animations()
	_apply_loaded_settings()


func _style_section_headers() -> void:
	var gold := UiTheme.ACCENT_GOLD
	var section_labels: Array[String] = ["-- AUDIO --", "-- DISPLAY --", "-- KEY BINDINGS --"]
	var container := panel.get_node("VBoxContainer")
	for child in container.get_children():
		if child is Label and child.text.begins_with("--"):
			child.add_theme_color_override("font_color", gold)
			child.add_theme_font_size_override("font_size", 14)
	var title_label: Label = container.get_node("Header/TitleLabel")
	title_label.add_theme_color_override("font_color", gold)


func _setup_button_animations() -> void:
	UiAnimations.setup_button_hover(close_button)
	UiAnimations.setup_button_hover(back_button)
	UiAnimations.setup_button_hover(fullscreen_button)


func _connect_signals() -> void:
	master_slider.value_changed.connect(_on_volume_changed.bind("Master"))
	music_slider.value_changed.connect(_on_volume_changed.bind("Music"))
	sfx_slider.value_changed.connect(_on_volume_changed.bind("SFX"))
	fullscreen_button.pressed.connect(_on_fullscreen_toggled)
	close_button.pressed.connect(close)
	back_button.pressed.connect(close)


func open() -> void:
	_apply_loaded_settings()
	visible = true
	var start_alpha := dimmer.color.a
	dimmer.color.a = 0.0
	panel.position.y += 30.0
	panel.modulate.a = 0.0
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.parallel().tween_property(dimmer, "color:a", 0.7, 0.25).set_trans(Tween.TRANS_LINEAR)
	tween.parallel().tween_property(panel, "position:y", panel.position.y - 30.0, 0.3).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(panel, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_LINEAR)
	back_button.grab_focus()


func close() -> void:
	_save_settings()
	_rebinding_action = ""
	_rebinding_label = null
	visible = false
	closed.emit()


func _apply_loaded_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		master_slider.value = 80
		music_slider.value = 60
		sfx_slider.value = 80
		_update_fullscreen_text()
		_rebuild_key_bindings()
		return

	master_slider.value = config.get_value(SECTION_AUDIO, "master", 80)
	music_slider.value = config.get_value(SECTION_AUDIO, "music", 60)
	sfx_slider.value = config.get_value(SECTION_AUDIO, "sfx", 80)
	_update_fullscreen_text()
	_rebuild_key_bindings()


func _on_volume_changed(value: float, bus_name: String) -> void:
	var db_value := linear_to_db(value / 100.0)
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, db_value)


func _on_fullscreen_toggled() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_update_fullscreen_text()


func _update_fullscreen_text() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		fullscreen_button.text = "ON"
	else:
		fullscreen_button.text = "OFF"


func _on_key_binding_pressed(action: String, label: Label) -> void:
	_rebinding_action = action
	_rebinding_label = label
	_rebinding_label.text = "..."
	_clear_action_events(action)
	_rebuild_key_bindings()


func _clear_action_events(action: String) -> void:
	InputMap.action_erase_events(action)


func _input(event: InputEvent) -> void:
	if _rebinding_action == "":
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_rebinding_action = ""
			_rebinding_label = null
			_rebuild_key_bindings()
			get_viewport().set_input_as_handled()
			return

		InputMap.action_add_event(_rebinding_action, event)
		_rebinding_action = ""
		_rebinding_label = null
		_rebuild_key_bindings()
		get_viewport().set_input_as_handled()


func _rebuild_key_bindings() -> void:
	for child in key_bindings_container.get_children():
		child.queue_free()

	var actions := ["move_up", "move_down", "move_left", "move_right"]
	var labels := ["Move Up", "Move Down", "Move Left", "Move Right"]

	for i in actions.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)

		var name_label := Label.new()
		name_label.text = labels[i]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		name_label.add_theme_font_size_override("font_size", 14)
		row.add_child(name_label)

		var key_button := Button.new()
		var events := InputMap.action_get_events(actions[i])
		if events.size() > 0:
			var ev: InputEvent = events[0]
			if ev is InputEventKey:
				key_button.text = OS.get_keycode_string(ev.keycode)
			else:
				key_button.text = "???"
		else:
			key_button.text = "???"

		var action: String = actions[i]
		key_button.pressed.connect(_on_key_binding_pressed.bind(action, key_button))
		UiAnimations.setup_button_hover(key_button)
		row.add_child(key_button)

		key_bindings_container.add_child(row)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION_AUDIO, "master", master_slider.value)
	config.set_value(SECTION_AUDIO, "music", music_slider.value)
	config.set_value(SECTION_AUDIO, "sfx", sfx_slider.value)
	config.save(SETTINGS_PATH)
```

Note: The `_apply_theme()` method is completely replaced by `theme = UiTheme.get_theme()` plus `_style_section_headers()`. Key binding labels use the secondary text color.

- [ ] **Step 3: Commit**

```
git add scenes/ui/settings_popup.tscn src/ui/settings_popup.gd
git commit -m "feat: redesign settings popup with Balatro theme, gold headers, and slide-in animation"
```

---

## Task 11: Weapon Button Redesign

**Files:**
- Modify: `scenes/ui/weapon_button.tscn`
- Modify: `src/ui/weapon_button.gd`

### Scene Changes

1. Change `IconButton` custom_minimum_size from `Vector2(48, 48)` to `Vector2(64, 64)`
2. Change `FallbackIcon` custom_minimum_size from `Vector2(48, 48)` to `Vector2(64, 64)`
3. Change `FallbackLabel` positioning to center the "?" in the 64x64 area
4. Update MarginContainer offsets to account for wider icon: `offset_left = -80`, `offset_right = -8` (was -72, -8)
5. The Tooltip PanelContainer already exists. It needs card-style panel background. Since PanelContainer gets its style from the theme, it should automatically get the card panel style when theme is applied.

### Script Changes

- [ ] **Step 1: Modify `scenes/ui/weapon_button.tscn`**

Update icon sizes to 64×64 and adjust offsets.

- [ ] **Step 2: Rewrite `src/ui/weapon_button.gd`**

```gdscript
extends CanvasLayer

const MODIFIER_ICON_SIZE := Vector2(32, 32)

@export var weapon_popup: NodePath

@onready var _icon_button: TextureButton = %IconButton
@onready var _tooltip: PanelContainer = %Tooltip
@onready var _tooltip_name: Label = %TooltipName
@onready var _tooltip_cooldown: Label = %TooltipCooldown
@onready var _tooltip_damage: Label = %TooltipDamage
@onready var _fallback_icon: ColorRect = %FallbackIcon

var _weapon_manager: WeaponManager = null
var _current_weapon: Weapon = null


func _ready() -> void:
	theme = UiTheme.get_theme()
	_tooltip_name.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	_tooltip_cooldown.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	_tooltip_cooldown.add_theme_font_size_override("font_size", 14)
	_tooltip_damage.add_theme_color_override("font_color", UiTheme.ACCENT)
	_tooltip_damage.add_theme_font_size_override("font_size", 14)
	_tooltip.visible = false
	_fallback_icon.visible = false
	_icon_button.texture_normal = null
	_icon_button.pressed.connect(_on_button_pressed)
	_icon_button.mouse_entered.connect(_on_mouse_entered)
	_icon_button.mouse_exited.connect(_on_mouse_exited)
	_find_weapon_manager()
	if _weapon_manager != null:
		_weapon_manager.weapon_activated.connect(_on_weapon_activated)
		_update_display(_weapon_manager.active_slot)


func _find_weapon_manager() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		_weapon_manager = player.get_node("WeaponManager")


func _on_weapon_activated(slot_index: int) -> void:
	_update_display(slot_index)


func _update_display(slot_index: int) -> void:
	if _weapon_manager == null:
		return
	if slot_index < 0 or slot_index >= _weapon_manager.weapons.size():
		return
	var weapon: Weapon = _weapon_manager.weapons[slot_index]
	if weapon == null:
		return
	_current_weapon = weapon
	if weapon.icon_texture != null:
		_icon_button.texture_normal = weapon.icon_texture
		_icon_button.visible = true
		_fallback_icon.visible = false
	else:
		_icon_button.visible = false
		_fallback_icon.visible = true
	_tooltip.visible = false


func _on_button_pressed() -> void:
	if _weapon_manager != null:
		var popup := get_node_or_null(weapon_popup)
		if popup and popup.has_method("open"):
			popup.open(_weapon_manager)


func _on_mouse_entered() -> void:
	if _current_weapon != null:
		_update_tooltip()
		UiAnimations.fade_in(_tooltip, 0.15)
	UiAnimations.bounce_on_hover(_icon_button, 1.08)


func _on_mouse_exited() -> void:
	_tooltip.visible = false
	UiAnimations.reset_scale(_icon_button)


func _update_tooltip() -> void:
	if _current_weapon == null:
		return
	var stats := _current_weapon.get_base_stats()
	_tooltip_name.text = str(stats["name"])
	_tooltip_cooldown.text = "Cooldown: %.1fs" % stats["cooldown"]
	_tooltip_damage.text = "Damage: %.0f" % stats["damage"]
	_clear_modifier_icons()
	_add_modifier_icons()


func _clear_modifier_icons() -> void:
	var row := _tooltip.get_node_or_null("VBoxContainer/ModifierRow")
	if row != null:
		for child in row.get_children():
			child.queue_free()


func _add_modifier_icons() -> void:
	var vbox := _tooltip.get_node("VBoxContainer")
	var row := vbox.get_node_or_null("ModifierRow")
	if row == null:
		row = HBoxContainer.new()
		row.name = "ModifierRow"
		row.add_theme_constant_override("separation", 2)
		vbox.add_child(row)
	for i in range(_current_weapon.modifier_slot_count):
		var modifier: Modifier = _current_weapon.get_modifier_at(i)
		if modifier != null:
			var icon := TextureRect.new()
			icon.custom_minimum_size = MODIFIER_ICON_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			if modifier.icon_texture != null:
				icon.texture = modifier.icon_texture
			row.add_child(icon)
		else:
			var empty := ColorRect.new()
			empty.custom_minimum_size = MODIFIER_ICON_SIZE
			empty.color = Color(0.165, 0.082, 0.098, 1)
			row.add_child(empty)
```

Note: The `_apply_theme()` method is replaced by `theme = UiTheme.get_theme()` plus per-label color overrides. Tooltip labels now use gold for name, muted gray for cooldown, and orange for damage. The bounce animation uses 1.08 scale as specified.

- [ ] **Step 3: Commit**

```
git add scenes/ui/weapon_button.tscn src/ui/weapon_button.gd
git commit -m "feat: redesign weapon button with Balatro theme and hover animations"
```

---

## Task 12: Weapon Popup Redesign

**Files:**
- Modify: `scenes/ui/weapon_popup.tscn`
- Modify: `src/ui/weapon_popup.gd`

### Scene Changes

1. Change `Overlay` color from `Color(0, 0, 0, 0.7)` to `Color(0.102, 0.059, 0.071, 0.87)` (87% opacity deep bg per spec)
2. `TitleLabel` needs gold color override and larger font size
3. The scene structure stays largely the same — cards are dynamically created in code

### Script Changes

This is the most complex task. The weapon popup needs:
- Card styling with card-style PanelContainer (from theme)
- Card hover glow shader (adds ShaderMaterial to hovered card)
- Card stagger-in animation
- Gold border for selected card
- Dashed-border style for empty slots
- Proper label colors per the spec (name=gold, cooldown=muted, damage=orange)

- [ ] **Step 1: Modify `scenes/ui/weapon_popup.tscn`**

Key change: Update Overlay color alpha to 0.87 and change color to deep bg. No other structural changes needed since cards are created dynamically.

- [ ] **Step 2: Rewrite `src/ui/weapon_popup.gd`**

```gdscript
extends CanvasLayer

const CARD_MIN_SIZE := Vector2(160, 220)
const ICON_SIZE := Vector2(96, 96)
const MODIFIER_ICON_SIZE := Vector2(32, 32)
const TOOLTIP_MAX_WIDTH := 180

const CARD_GLOW_SHADER := preload("res://shaders/ui/card_hover_glow.gdshader")

@onready var _overlay: ColorRect = %Overlay
@onready var _cards_container: HBoxContainer = %CardsContainer
@onready var _title_label: Label = %TitleLabel

var _weapon_manager: WeaponManager = null
var _selected_slot: int = -1
var _pickup_mode: bool = false
var _pickup_weapon: Weapon = null
var _pickup_callback: Callable
var _modifier_tooltip: PanelContainer = null
var _card_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UiTheme.get_theme()
	_title_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_constant_override("outline_size", 2)
	_title_label.add_theme_color_override("font_outline_color", Color.BLACK)
	visible = false
	_overlay.gui_input.connect(_on_overlay_input)


func open(weapon_manager: WeaponManager) -> void:
	_weapon_manager = weapon_manager
	_selected_slot = -1
	_title_label.text = "WEAPONS"
	_build_cards()
	SceneManager.set_paused(true)
	visible = true


func open_for_pickup(weapon_manager: WeaponManager, new_weapon: Weapon, callback: Callable) -> void:
	_pickup_mode = true
	_pickup_weapon = new_weapon
	_pickup_callback = callback
	_weapon_manager = weapon_manager
	_selected_slot = -1
	_title_label.text = "Replace a slot:"
	_build_cards()
	SceneManager.set_paused(true)
	visible = true


func close() -> void:
	_cancel_modifier_tooltip()
	visible = false
	_weapon_manager = null
	_pickup_mode = false
	_pickup_weapon = null
	_pickup_callback = Callable()
	_selected_slot = -1
	_clear_cards()
	SceneManager.set_paused(false)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func _build_cards() -> void:
	_clear_cards()
	var cards: Array[Control] = []
	for i in range(3):
		var weapon: Weapon = null
		if i < _weapon_manager.weapons.size():
			weapon = _weapon_manager.weapons[i]
		var card := _create_card(weapon, i)
		_cards_container.add_child(card)
		cards.append(card)
	UiAnimations.stagger_slide_in(cards, 0.1, 20.0, 0.3)


func _clear_cards() -> void:
	for child in _cards_container.get_children():
		child.queue_free()


func _create_card(weapon: Weapon, slot_index: int) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_MIN_SIZE
	card.gui_input.connect(_on_card_input.bind(slot_index))
	card.mouse_entered.connect(_on_card_mouse_entered.bind(card))
	card.mouse_exited.connect(_on_card_mouse_exited.bind(card))

	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = CARD_GLOW_SHADER
	glow_mat.set_shader_parameter("glow_enabled", false)
	card.material = glow_mat

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	if weapon == null:
		var empty_label := Label.new()
		empty_label.text = "EMPTY"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		vbox.add_child(empty_label)

		var style := card.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			style = style.duplicate()
			style.border_color = UiTheme.PANEL_BORDER
			style.set_border_width_all(2)
			style.set_dash_width(2)
			style.set_dash_offset(0)
			card.add_theme_stylebox_override("panel", style)
	else:
		_add_icon(vbox, weapon)
		var name_label := Label.new()
		name_label.text = weapon.name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
		vbox.add_child(name_label)

		var stats := weapon.get_base_stats()
		var cooldown_label := Label.new()
		cooldown_label.text = "Cooldown: %.1fs" % stats["cooldown"]
		cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cooldown_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		cooldown_label.add_theme_font_size_override("font_size", 14)
		vbox.add_child(cooldown_label)

		var damage_label := Label.new()
		damage_label.text = "Damage: %.0f" % stats["damage"]
		damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		damage_label.add_theme_color_override("font_color", UiTheme.ACCENT)
		damage_label.add_theme_font_size_override("font_size", 14)
		vbox.add_child(damage_label)

		_add_modifier_slots(vbox, weapon)

	return card


func _add_icon(parent: VBoxContainer, weapon: Weapon) -> void:
	if weapon.icon_texture != null:
		var icon := TextureRect.new()
		icon.texture = weapon.icon_texture
		icon.custom_minimum_size = ICON_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		parent.add_child(icon)
	else:
		var fallback := ColorRect.new()
		fallback.custom_minimum_size = ICON_SIZE
		fallback.color = Color(0.165, 0.082, 0.098, 1)
		parent.add_child(fallback)
		var q_label := Label.new()
		q_label.text = "?"
		q_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q_label.anchors_preset = Control.PRESET_FULL_RECT
		q_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		fallback.add_child(q_label)


func _add_modifier_slots(parent: VBoxContainer, weapon: Weapon) -> void:
	var slot_container := HBoxContainer.new()
	slot_container.add_theme_constant_override("separation", 4)
	slot_container.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(slot_container)

	for i in range(weapon.modifier_slot_count):
		var modifier: Modifier = weapon.get_modifier_at(i)
		if modifier != null:
			var icon := TextureRect.new()
			icon.custom_minimum_size = MODIFIER_ICON_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			if modifier.icon_texture != null:
				icon.texture = modifier.icon_texture
			else:
				icon.texture = null
			icon.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			icon.gui_input.connect(_on_modifier_icon_input.bind(modifier, icon))
			icon.mouse_entered.connect(_on_modifier_icon_mouse_entered.bind(modifier, icon))
			icon.mouse_exited.connect(_on_modifier_icon_mouse_exited)
			slot_container.add_child(icon)
		else:
			var empty_slot := ColorRect.new()
			empty_slot.custom_minimum_size = MODIFIER_ICON_SIZE
			empty_slot.color = Color(0.165, 0.082, 0.098, 1)
			slot_container.add_child(empty_slot)


func _on_card_mouse_entered(card: PanelContainer) -> void:
	if card.material is ShaderMaterial:
		card.material.set_shader_parameter("glow_enabled", true)
	var tween := card.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(card, "scale", Vector2(1.03, 1.03), 0.15).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
	var style := card.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		var new_style := style.duplicate() as StyleBoxFlat
		new_style.border_color = UiTheme.ACCENT
		card.add_theme_stylebox_override("panel", new_style)


func _on_card_mouse_exited(card: PanelContainer) -> void:
	if card.material is ShaderMaterial:
		card.material.set_shader_parameter("glow_enabled", false)
	var tween := card.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(card, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
	if _selected_slot == -1:
		var style := card.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			var new_style := style.duplicate() as StyleBoxFlat
			new_style.border_color = UiTheme.PANEL_BORDER
			card.add_theme_stylebox_override("panel", new_style)


func _on_modifier_icon_mouse_entered(modifier: Modifier, icon: Control) -> void:
	_cancel_modifier_tooltip()
	_modifier_tooltip = PanelContainer.new()
	_modifier_tooltip.custom_minimum_size.x = TOOLTIP_MAX_WIDTH

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_modifier_tooltip.add_child(vbox)

	var name_label := Label.new()
	name_label.text = modifier.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	vbox.add_child(name_label)

	var separator := HSeparator.new()
	vbox.add_child(separator)

	var desc_label := Label.new()
	desc_label.text = modifier.get_description()
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	desc_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(desc_label)

	add_child(_modifier_tooltip)
	_position_tooltip_near(icon)


func _on_modifier_icon_mouse_exited() -> void:
	_cancel_modifier_tooltip()


func _on_modifier_icon_input(_event: InputEvent, _modifier: Modifier, _icon: Control) -> void:
	pass


func _position_tooltip_near(icon: Control) -> void:
	if _modifier_tooltip == null:
		return
	await get_tree().process_frame
	var icon_rect := icon.get_global_rect()
	var tooltip_size := _modifier_tooltip.get_combined_minimum_size()
	var pos_x := icon_rect.position.x + icon_rect.size.x / 2.0 - tooltip_size.x / 2.0
	var viewport_width := get_viewport().get_visible_rect().size.x
	pos_x = clampf(pos_x, 4.0, viewport_width - tooltip_size.x - 4.0)
	_modifier_tooltip.global_position = Vector2(
		pos_x,
		icon_rect.position.y - tooltip_size.y - 4.0
	)
	_modifier_tooltip.size = tooltip_size


func _cancel_modifier_tooltip() -> void:
	if _modifier_tooltip != null:
		_modifier_tooltip.queue_free()
		_modifier_tooltip = null


func _on_card_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _pickup_mode:
			_pickup_callback.call(slot_index)
			close()
		else:
			if _selected_slot == -1:
				_selected_slot = slot_index
				_highlight_slot(slot_index)
			else:
				if _selected_slot != slot_index:
					_swap_weapons(_selected_slot, slot_index)
				_selected_slot = -1
				_build_cards()


func _highlight_slot(slot_index: int) -> void:
	var cards := _cards_container.get_children()
	if slot_index < cards.size():
		var card: Control = cards[slot_index]
		var style := card.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			var new_style := style.duplicate() as StyleBoxFlat
			new_style.border_color = UiTheme.ACCENT_GOLD
			card.add_theme_stylebox_override("panel", new_style)
		var tween := card.create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.set_loops()
		tween.tween_property(card, "modulate", Color(1.0, 0.85, 0.5, 1.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_property(card, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _swap_weapons(slot_a: int, slot_b: int) -> void:
	if _weapon_manager != null:
		_weapon_manager.swap_weapons(slot_a, slot_b)


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			close()
```

Key changes from the original:
1. Theme is set from `UiTheme.get_theme()` — no more `_apply_theme()`
2. Card labels use gold/secondary/accent colors
3. Cards have ShaderMaterial for hover glow effect
4. Cards use stagger-in animation on `_build_cards()`
5. Hover on cards triggers scale 1.03 + orange border + glow shader
6. Selected card gets gold border + pulse animation
7. Empty slots use dashed borders (via StyleBoxFlat.dash_width, though this only works in Godot 4.3+; if unavailable, use a darker fill color)
8. Tooltip labels use themed colors (gold name, muted gray description)

Note: `StyleBoxFlat.set_dash_width()` was added in Godot 4.3. If the project is on an earlier version, the dashed border for empty slots won't work and should be removed. The fallback is to use a slightly different background color for empty cards.

- [ ] **Step 3: Commit**

```
git add scenes/ui/weapon_popup.tscn src/ui/weapon_popup.gd shaders/ui/card_hover_glow.gdshader
git commit -m "feat: redesign weapon popup with card styling, hover glow, and stagger animations"
```

---

## Dependency Graph

```
Task 1 (ui_theme.gd) ──────┐
Task 2 (ui_animations.gd) ──┤
Task 3 (health shimmer) ────┤──→ Tasks 6-12 (all UI updates)
Task 4 (death vignette) ────┤
Task 5 (card hover glow) ───┘
```

Tasks 1-5 have **no dependencies** and can be implemented in parallel.
Tasks 6-12 **depend on Tasks 1-5** but are independent of each other and can be implemented in parallel.

---

## Self-Review Checklist

**1. Spec Coverage:**
- [x] Color palette → Task 1 `UiTheme` constants
- [x] Typography → Task 1 `UiTheme` + per-screen overrides (64px hero title in Task 9, 48px pause title in Task 8, etc.)
- [x] Card-like panels (StyleBoxFlat) → Task 1 `_make_panel_stylebox()`
- [x] Button styles → Task 1 `_make_button_stylebox()` variants
- [x] Main menu redesign → Task 7
- [x] Health bar redesign → Task 6
- [x] Health bar shimmer shader → Task 3
- [x] Pause menu redesign → Task 8
- [x] Death screen redesign → Task 9
- [x] Death vignette shader → Task 4
- [x] Settings popup redesign → Task 10
- [x] Weapon button redesign → Task 11
- [x] Weapon popup redesign → Task 12
- [x] Card hover glow shader → Task 5
- [x] Shared theme resource → Task 1 (GDScript class)
- [x] UI animations utility → Task 2
- [x] All 7 UI script pairs updated → Tasks 6-12
- [x] Drop shadows (outline_size/font_outline_color) → Per-label theme overrides in Tasks 7-9

**2. Placeholder Scan:**
- No TBD, TODO, or "implement later" patterns found
- No "similar to Task N" shortcuts
- All code blocks contain complete implementations
- All file paths are exact

**3. Type Consistency:**
- `UiTheme` class methods used consistently across all tasks
- `UiAnimations` static method signatures match across all call sites
- Shader uniform names (`glow_enabled`, `pulse_speed`, etc.) consistent between definitions and GDScript references
- Node %unique_names match between scenes and scripts in all tasks