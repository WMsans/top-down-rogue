# Balatro-Style Card UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace inline programmatic card creation across all UI screens with a reusable `Card.tscn` scene that renders content via SubViewport with fake_3D perspective-tilt shader, elastic hover animations, and offset drop shadow.

**Architecture:** A single `Card` Control scene wraps a SubViewport→SubViewportContainer pipeline with a `fake_3D` shader. Content (icon, name, stats, modifier slots) is injected via `populate()` and rendered once. Hover animations (elastic scale, shadow offset, 3D tilt toward cursor) are self-contained in the Card script. Each existing UI replaces its `_create_*_card()` method body with `Card` scene instantiation + `populate()` call.

**Tech Stack:** Godot 4.x, GDScript, SubViewport, ShaderMaterial (canvas_item shader), Theme/StyleBoxFlat

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `shaders/ui/fake_3d.gdshader` | Create | 3D perspective tilt shader for card face |
| `src/ui/ui_theme.gd` | Modify | Add `get_card_shadow_stylebox()` method |
| `scenes/ui/card.tscn` | Create | Reusable card scene with SubViewport pipeline |
| `src/ui/card.gd` | Create | Card controller: populate, hover/tilt/click animations, selection state |
| `src/ui/weapon_popup.gd` | Modify | Replace `_create_card()`, `_add_pickup_header()`, `_create_remove_modifier_card()`, `_create_transfer_card()` with Card scene; remove `_on_card_mouse_entered`/`_on_card_mouse_exited` |
| `src/ui/chest_ui.gd` | Modify | Replace `_create_weapon_card()` with Card scene; remove `_on_card_mouse_entered`/`_on_card_mouse_exited` |
| `src/economy/shop_ui.gd` | Modify | Replace `_create_offer_card()` and `_create_remove_card()` with Card scene; remove `_on_card_mouse_entered`/`_on_card_mouse_exited` |

---

### Task 1: Add fake_3D shader and shadow stylebox

**Files:**
- Create: `shaders/ui/fake_3d.gdshader`
- Modify: `src/ui/ui_theme.gd`

- [ ] **Step 1: Create the fake_3D shader file**

Write `shaders/ui/fake_3d.gdshader`:

```glsl
shader_type canvas_item;

uniform vec2 rect_size = vec2(160.0, 220.0);

uniform float fov : hint_range(1, 179) = 90.0;
uniform bool cull_back = true;
uniform float y_rot : hint_range(-360.0, 360.0) = 0.0;
uniform float x_rot : hint_range(-360.0, 360.0) = 0.0;
uniform float inset : hint_range(0, 1) = 0.0;

varying flat vec2 o;
varying vec3 p;

void vertex(){
	float sin_b = sin(y_rot / 180.0 * PI);
	float cos_b = cos(y_rot / 180.0 * PI);
	float sin_c = sin(x_rot / 180.0 * PI);
	float cos_c = cos(x_rot / 180.0 * PI);

	mat3 inv_rot_mat;
	inv_rot_mat[0][0] = cos_b;
	inv_rot_mat[0][1] = 0.0;
	inv_rot_mat[0][2] = -sin_b;

	inv_rot_mat[1][0] = sin_b * sin_c;
	inv_rot_mat[1][1] = cos_c;
	inv_rot_mat[1][2] = cos_b * sin_c;

	inv_rot_mat[2][0] = sin_b * cos_c;
	inv_rot_mat[2][1] = -sin_c;
	inv_rot_mat[2][2] = cos_b * cos_c;

	float t = tan(fov / 360.0 * PI);
	p = inv_rot_mat * vec3((UV - 0.5), 0.5 / t);
	float v = (0.5 / t) + 0.5;
	p.xy *= v * inv_rot_mat[2].z;
	o = v * inv_rot_mat[2].xy;

	VERTEX += (UV - 0.5) * rect_size * t * (1.0 - inset);
}

void fragment(){
	if (cull_back && p.z <= 0.0) discard;
	vec2 uv = (p.xy / p.z).xy - o;
	COLOR = texture(TEXTURE, uv + 0.5);
	COLOR.a *= step(max(abs(uv.x), abs(uv.y)), 0.5);
}
```

- [ ] **Step 2: Add shadow stylebox to ui_theme.gd**

Add two things to `src/ui/ui_theme.gd`:

**A.** After `_set_panel_styles()` (line 86), add:

```gdscript
static func get_card_shadow_stylebox() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.12)
	s.set_corner_radius_all(8)
	return s
```

**B.** Add the method to the accessor list in `_build()` (line 31-35) — no change needed, `_build()` just needs to exist. Add the new public method anywhere in the class.

```gdscript
static func get_card_shadow_stylebox() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.12)
	s.set_corner_radius_all(8)
	return s
```

Insert this at line 124 (end of file, before the final blank line). Actually, insert it after the `_set_container_constants` method ends at line 124. The full new method:

```gdscript
static func get_card_shadow_stylebox() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.12)
	s.set_corner_radius_all(8)
	return s
```

- [ ] **Step 3: Verify no errors**

Run: `godot --headless --quit 2>&1 | head -20`
Expected: No script parse errors (project may print warnings, but no "Parse Error" lines).

- [ ] **Step 4: Commit**

```bash
git add shaders/ui/fake_3d.gdshader src/ui/ui_theme.gd
git commit -m "feat: add fake_3D shader and card shadow stylebox"
```

---

### Task 2: Create Card script (card.gd)

**Files:**
- Create: `src/ui/card.gd`

- [ ] **Step 1: Write card.gd**

Write `src/ui/card.gd`:

```gdscript
class_name Card
extends Control

signal card_clicked

@export var card_size: Vector2 = Vector2(160, 220):
	set(v):
		card_size = v
		if is_node_ready():
			custom_minimum_size = card_size
			_update_subviewport()

@export var icon_size: Vector2 = Vector2(96, 96)
@export var mod_icon_size: Vector2 = Vector2(32, 32)
@export var tilt_max: float = 12.0
@export var hover_scale_target: float = 1.12
@export var is_selectable: bool = true

@onready var _shadow: Control = $Shadow
@onready var _shadow_rect: ColorRect = $Shadow/ShadowRect
@onready var _subviewport_container: SubViewportContainer = $SubViewportContainer
@onready var _subviewport: SubViewport = $SubViewportContainer/SubViewport
@onready var _card_panel: PanelContainer = $SubViewportContainer/SubViewport/CardPanel
@onready var _content_vbox: VBoxContainer = $SubViewportContainer/SubViewport/CardPanel/ContentVBox
@onready var _icon: TextureRect = $SubViewportContainer/SubViewport/CardPanel/ContentVBox/Icon
@onready var _name_label: Label = $SubViewportContainer/SubViewport/CardPanel/ContentVBox/NameLabel
@onready var _stats_container: VBoxContainer = $SubViewportContainer/SubViewport/CardPanel/ContentVBox/StatsContainer
@onready var _modifier_slots: HBoxContainer = $SubViewportContainer/SubViewport/CardPanel/ContentVBox/ModifierSlots

var _is_hovered: bool = false
var _is_selected: bool = false
var _hover_tween: Tween
var _exit_tween: Tween
var _click_tween: Tween
var _current_tilt: Vector2 = Vector2.ZERO

func _ready() -> void:
	custom_minimum_size = card_size
	mouse_filter = MOUSE_FILTER_STOP
	mouse_entered.connect(_on_hover_enter)
	mouse_exited.connect(_on_hover_exit)
	gui_input.connect(_on_gui_input)
	_setup_shadow()

func _setup_shadow() -> void:
	_shadow.position = Vector2(6, 6)
	_shadow_rect.custom_minimum_size = card_size
	_shadow_rect.color = Color(0, 0, 0, 0.12)

func populate(icon_texture: Texture2D, card_name: String, stats: Array[String] = [], modifier_icons: Array[Texture2D] = []) -> void:
	if icon_texture:
		_icon.texture = icon_texture
		_icon.custom_minimum_size = icon_size
		_icon.show()
	else:
		_icon.hide()

	_name_label.text = card_name

	for child in _stats_container.get_children():
		child.queue_free()
	if stats.size() > 0:
		_stats_container.show()
		for stat_text in stats:
			var label := Label.new()
			label.text = stat_text
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
			label.add_theme_font_size_override("font_size", 14)
			_stats_container.add_child(label)
	else:
		_stats_container.hide()

	for child in _modifier_slots.get_children():
		child.queue_free()
	if modifier_icons.size() > 0:
		_modifier_slots.show()
		for mod_tex in modifier_icons:
			var slot := TextureRect.new()
			slot.custom_minimum_size = mod_icon_size
			slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			if mod_tex:
				slot.texture = mod_tex
			_modifier_slots.add_child(slot)
	else:
		_modifier_slots.hide()

	_subviewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func set_selected(selected: bool) -> void:
	_is_selected = selected
	_update_border_color()

func _update_border_color() -> void:
	if not is_instance_valid(_card_panel):
		return
	var style := _card_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if not style:
		return
	var new_style := style.duplicate() as StyleBoxFlat
	if _is_selected:
		new_style.border_color = UiTheme.ACCENT_GOLD
	elif _is_hovered:
		new_style.border_color = UiTheme.ACCENT
	else:
		new_style.border_color = UiTheme.PANEL_BORDER
	_card_panel.add_theme_stylebox_override("panel", new_style)
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func set_name_color(color: Color) -> void:
	_name_label.add_theme_color_override("font_color", color)
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func set_name_font_size(size: int) -> void:
	_name_label.add_theme_font_size_override("font_size", size)
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _on_hover_enter() -> void:
	_is_hovered = true
	_animate_hover_enter()
	_update_border_color()
	set_process(true)

func _on_hover_exit() -> void:
	_is_hovered = false
	_animate_hover_exit()
	_update_border_color()
	var start_tilt := _current_tilt.x
	var tilt_tween := create_tween()
	tilt_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tilt_tween.tween_method(func(val: float): _set_tilt_angles(Vector2(val, val)), start_tilt, 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tilt_tween.tween_callback(func(): set_process(false))

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_hovered:
			_play_click_feedback()
			card_clicked.emit()

func _animate_hover_enter() -> void:
	if _exit_tween and _exit_tween.is_running():
		_exit_tween.kill()
	if _hover_tween and _hover_tween.is_running():
		return
	_hover_tween = create_tween()
	_hover_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_hover_tween.tween_property(self, "scale", Vector2(hover_scale_target + 0.03, hover_scale_target + 0.03), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(self, "scale", Vector2(hover_scale_target, hover_scale_target), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var shadow_tween := create_tween()
	shadow_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	shadow_tween.tween_property(_shadow, "position", Vector2(10, 10), 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _animate_hover_exit() -> void:
	if _hover_tween and _hover_tween.is_running():
		_hover_tween.kill()
	_exit_tween = create_tween()
	_exit_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_exit_tween.tween_property(self, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var shadow_tween := create_tween()
	shadow_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	shadow_tween.tween_property(_shadow, "position", Vector2(6, 6), 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _play_click_feedback() -> void:
	if _click_tween and _click_tween.is_running():
		_click_tween.kill()
	var current_scale := scale
	_click_tween = create_tween()
	_click_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_click_tween.tween_property(self, "scale", current_scale * 0.97, 0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_click_tween.tween_property(self, "scale", current_scale, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

func _set_tilt_angles(angles: Vector2) -> void:
	_current_tilt = angles
	var mat := _subviewport_container.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("x_rot", deg_to_rad(angles.x))
		mat.set_shader_parameter("y_rot", deg_to_rad(angles.y))

func _process(_delta: float) -> void:
	if not _is_hovered:
		return
	var mouse_pos := get_local_mouse_position()
	var ratio_x := clampf(mouse_pos.x / card_size.x, 0.0, 1.0)
	var ratio_y := clampf(mouse_pos.y / card_size.y, 0.0, 1.0)
	var x_rot := lerpf(-tilt_max, tilt_max, ratio_y)
	var y_rot := lerpf(-tilt_max, tilt_max, ratio_x)
	_set_tilt_angles(Vector2(x_rot, y_rot))

func _update_subviewport() -> void:
	if is_node_ready():
		_subviewport.size = Vector2i(int(card_size.x), int(card_size.y))
		_subviewport_container.material.set_shader_parameter("rect_size", card_size)
		_shadow_rect.custom_minimum_size = card_size
		_subviewport.render_target_update_mode = SubViewport.UPDATE_ONCE
```

- [ ] **Step 2: Verify no parse errors**

Run: `godot --headless --quit 2>&1 | grep -i "error\|parse" | head -10`
Expected: No parse errors for card.gd.

- [ ] **Step 3: Commit**

```bash
git add src/ui/card.gd
git commit -m "feat: add Card controller script with hover/tilt/click animations"
```

---

### Task 3: Create Card scene (card.tscn)

**Files:**
- Create: `scenes/ui/card.tscn`

- [ ] **Step 1: Write card.tscn**

Write `scenes/ui/card.tscn`:

```ini
[gd_scene load_steps=8 format=3 uid="uid://card"]

[ext_resource type="Script" path="res://src/ui/card.gd" id="1_card_script"]
[ext_resource type="Shader" path="res://shaders/ui/fake_3d.gdshader" id="2_shader"]
[ext_resource type="Theme" path="" id="3_theme"]  ; placeholder, theme set in code

[sub_resource type="ShaderMaterial" id="ShaderMaterial_fake3d"]
shader = ExtResource("2_shader")
shader_parameter/rect_size = Vector2(160, 220)
shader_parameter/fov = 90.0
shader_parameter/cull_back = true
shader_parameter/y_rot = 0.0
shader_parameter/x_rot = 0.0
shader_parameter/inset = 0.0

[sub_resource type="StyleBoxFlat" id="StyleBox_card_panel"]
bg_color = Color(0.212, 0.110, 0.133, 1)
border_color = Color(0.545, 0.227, 0.165, 1)
border_width_left = 2
border_width_right = 2
border_width_top = 2
border_width_bottom = 2
corner_radius_top_left = 8
corner_radius_top_right = 8
corner_radius_bottom_left = 8
corner_radius_bottom_right = 8
content_margin_left = 12.0
content_margin_right = 12.0
content_margin_top = 8.0
content_margin_bottom = 8.0
shadow_color = Color(0, 0, 0, 0.502)
shadow_size = 8
expand_margin_left = 2.0
expand_margin_right = 2.0
expand_margin_top = 2.0
expand_margin_bottom = 2.0

[sub_resource type="Theme" id="Theme_card"]
default_font = ExtResource("4_font")
default_font_size = 20

[node name="Card" type="Control"]
layout_mode = 3
anchors_preset = 0
custom_minimum_size = Vector2(160, 220)
script = ExtResource("1_card_script")

[node name="Shadow" type="Control" parent="."]
layout_mode = 0
offset_right = 160.0
offset_bottom = 220.0
mouse_filter = 2

[node name="ShadowRect" type="ColorRect" parent="Shadow"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
color = Color(0, 0, 0, 0.12)

[node name="SubViewportContainer" type="SubViewportContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
stretch = true
material = SubResource("ShaderMaterial_fake3d")

[node name="SubViewport" type="SubViewport" parent="SubViewportContainer"]
size = Vector2i(160, 220)
transparent_bg = true
render_target_update_mode = 1
handle_input_locally = false

[node name="CardPanel" type="PanelContainer" parent="SubViewportContainer/SubViewport"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
theme_override_styles/panel = SubResource("StyleBox_card_panel")

[node name="ContentVBox" type="VBoxContainer" parent="SubViewportContainer/SubViewport/CardPanel"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
alignment = 1
theme_override_constants/separation = 8

[node name="Icon" type="TextureRect" parent="SubViewportContainer/SubViewport/CardPanel/ContentVBox"]
layout_mode = 2
custom_minimum_size = Vector2(96, 96)
size_flags_horizontal = 4
stretch_mode = 5

[node name="NameLabel" type="Label" parent="SubViewportContainer/SubViewport/CardPanel/ContentVBox"]
layout_mode = 2
text = "Name"
horizontal_alignment = 1
theme_override_colors/font_color = Color(1, 0.843, 0, 1)

[node name="StatsContainer" type="VBoxContainer" parent="SubViewportContainer/SubViewport/CardPanel/ContentVBox"]
layout_mode = 2
alignment = 1
theme_override_constants/separation = 4

[node name="ModifierSlots" type="HBoxContainer" parent="SubViewportContainer/SubViewport/CardPanel/ContentVBox"]
layout_mode = 2
alignment = 1
theme_override_constants/separation = 4
```

- [ ] **Step 2: Verify scene loads**

Run: `godot --headless --quit 2>&1 | grep -i "error\|card" | head -10`
Expected: No scene load errors.

- [ ] **Step 3: Commit**

```bash
git add scenes/ui/card.tscn
git commit -m "feat: add Card scene with SubViewport and fake_3D pipeline"
```

---

### Task 4: Integrate Card into weapon_popup.gd

**Files:**
- Modify: `src/ui/weapon_popup.gd`

This is the largest integration. The weapon popup has 4 card types: slot cards, pickup header, remove modifier cards, transfer cards.

- [ ] **Step 1: Add Card preload constant and remove unused constants**

At the top of `src/ui/weapon_popup.gd` (after line 8), add the Card preload:

```gdscript
const CARD_SCENE := preload("res://scenes/ui/card.tscn")
```

Remove the `CARD_GLOW_SHADER` constant (line 8) since it's no longer needed — the Card handles its own glow.

- [ ] **Step 2: Replace `_create_card()` (lines 291-339)**

Replace the entire method with:

```gdscript
func _create_card(weapon: Weapon, slot_index: int) -> Control:
	var card: Card = CARD_SCENE.instantiate()
	if weapon == null:
		card.populate(null, "EMPTY")
	else:
		card.populate(weapon.icon_texture, weapon.name, _build_weapon_stats(weapon), _build_modifier_icons(weapon))
		_add_modifier_slots_to_card(card, weapon, slot_index)
	card.card_clicked.connect(_on_card_input.bind(slot_index))
	return card
```

- [ ] **Step 3: Add helper methods `_build_weapon_stats()` and `_build_modifier_icons()`**

Add these helpers (anywhere in the class body):

```gdscript
func _build_weapon_stats(weapon: Weapon) -> Array[String]:
	var stats: Array[String] = []
	var base_stats := weapon.get_base_stats()
	var cooldown := base_stats.get("cooldown", 0.0)
	var damage := base_stats.get("damage", 0.0)
	if weapon is RangedWeapon:
		stats.append("Cooldown: %.1fs" % cooldown)
		stats.append("Damage: %.0f" % damage)
	else:
		stats.append("Cooldown: %.1fs" % cooldown)
		stats.append("Damage: %.0f" % damage)
	return stats

func _build_modifier_icons(weapon: Weapon) -> Array[Texture2D]:
	var icons: Array[Texture2D] = []
	for i in range(weapon.modifier_slot_count):
		var mod: Modifier = weapon.get_modifier_at(i)
		icons.append(mod.icon_texture if mod else null)
	return icons
```

- [ ] **Step 4: Add `_add_modifier_slots_to_card()` for modifier tooltip support**

The existing `_add_modifier_slots()` (lines 364-389) creates modifier slot icons with hover tooltip connections. Since those icons are now inside the Card's SubViewport and not directly accessible for tooltips, we need a new approach. Add modifier slot icons to the card content manually with tooltip connections:

```gdscript
func _add_modifier_slots_to_card(card: Card, weapon: Weapon, slot_index: int) -> void:
	var slot_container := HBoxContainer.new()
	slot_container.add_theme_constant_override("separation", 4)
	slot_container.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in range(weapon.modifier_slot_count):
		var modifier: Modifier = weapon.get_modifier_at(i)
		if modifier != null:
			var icon := TextureRect.new()
			icon.custom_minimum_size = MODIFIER_ICON_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			if modifier.icon_texture != null:
				icon.texture = modifier.icon_texture
			icon.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			icon.gui_input.connect(_on_modifier_icon_input.bind(modifier, icon))
			icon.mouse_entered.connect(_on_modifier_icon_mouse_entered.bind(modifier, icon, card))
			icon.mouse_exited.connect(_on_modifier_icon_mouse_exited.bind(card))
			slot_container.add_child(icon)
		else:
			var empty_slot := ColorRect.new()
			empty_slot.custom_minimum_size = MODIFIER_ICON_SIZE
			empty_slot.color = Color(0.165, 0.082, 0.098, 1)
			slot_container.add_child(empty_slot)
	card.modifier_slots.add_child(slot_container)
```

Wait — `card.modifier_slots` is part of the SubViewport! Modifier hover connections on nodes inside the SubViewport won't work because SubViewport content is rendered to a texture and the `mouse_entered`/`gui_input` signals need to go through the SubViewport's input handling. We need `_subviewport.handle_input_locally = true` for nodes inside the SubViewport to receive input events.

Actually, this is getting complex. Let me reconsider. The modifier icon tooltips rely on `mouse_entered`/`gui_input` on the TextureRect nodes inside the card. With the SubViewport, these nodes are rendered to a texture, and mouse events on the SubViewportContainer go to the Card (Control root) above it — not to the children inside the SubViewport.

Options:
1. Set `SubViewport.handle_input_locally = true` — then mouse events inside the SubViewport's area will go to the SubViewport children. But the events won't propagate up to the Card Control for hover/tilt logic.
2. Move modifier tooltip logic outside the card — have the Card emit signals when modifier slots are hovered, and handle tooltip at the weapon_popup level.
3. Skip modifier tooltips — accept the current modifier interaction pattern of only showing tooltips on the non-viewport cards.

Hmm, option 1 might work if we're careful. But it creates a conflict between the Card's mouse handling and the SubViewport's mouse handling.

Let me think about this... The Card's hover/tilt uses `mouse_entered`/`mouse_exited` on the Card Control. The modifier icons inside the SubViewport need their own `mouse_entered`. If I set `handle_input_locally = true`, mouse events go to the SubViewport first, and the Card Control might not get mouse_entered when hovering over a modifier icon within the viewport area.

Actually, let me test: with `handle_input_locally = true`, `mouse_entered`/`mouse_exited` on the Control root should still fire because the mouse entering/exiting the SubViewportContainer's rect on the Card Control will trigger Control-level mouse events. The SubViewport handles input for its children, and the Control handles input for the Card-level events.

But wait — `mouse_entered` on a Control fires when the mouse enters the Control's rect. If the SubViewportContainer covers the full Card rect, then the mouse entering the card also enters the SubViewportContainer. With `handle_input_locally = true`, the input goes to the SubViewport first, and the Card Control above it may or may not get the mouse_entered signal depending on how Godot handles this.

Actually, in Godot 4, `SubViewport.handle_input_locally` only affects `gui_input`, `mouse_entered`, `mouse_exited`, and focus. When `true`, the viewport processes input for its children. The mouse_entered/mouse_exited signals are propagated normally through the scene tree. So the Card Control should still get mouse_entered when the mouse enters its rect, even if `handle_input_locally` is true on the SubViewport.

Wait, but the SubViewport is a child of SubViewportContainer, which is a child of Card Control. When `handle_input_locally` is true, the SubViewport processes input for its children (CardPanel, ContentVBox, etc.) — but the Card Control is a PARENT, not a child of the SubViewport. So the Card Control's mouse_entered should still fire.

Let me just go with `handle_input_locally = true` on the SubViewport and the modifier icon tooltips should work as before. The Card's mouse_entered/mouse_exited on the Control root should also work because it's a parent node.

Actually, I just realized there's a simpler issue. The Card's scale animation on hover will scale the entire card including the SubViewport contents. The modifier icons inside the SubViewport will scale with the rest of the card. That's fine — that's the desired behavior.

But there's another issue: the modifier tooltip creation uses `add_child(_modifier_tooltip)` on the weapon_popup (a CanvasLayer), and positions it based on the modifier icon's `global_position`. With the SubViewport, the modifier icon's global_position might not reflect the actual on-screen position since the SubViewport renders its children at their positions within the viewport (0,0 to viewport_size), and then the SubViewportContainer scales/moves the rendered texture.

Hmm, this is getting complex. Let me take a step back.

For the modifier tooltip, the `_position_tooltip_near(icon)` method uses `icon.get_global_rect()`. With the SubViewport, the icon's global position is relative to the SubViewport's coordinate system (0,0 at top-left of viewport). But the SubViewportContainer may apply scale transforms, so the icon's global_rect might not be accurate.

Actually, `.get_global_rect()` in Godot traverses up the scene tree, multiplying transforms. So if the SubViewportContainer is scaled (via the Card's scale), the icon's global_rect should be correct. Let me think again...

SubViewport creates a separate coordinate space. Its children's transforms are relative to the SubViewport. When `get_global_rect()` is called on a child of the SubViewport, it computes: child's rect + parent transforms up to the viewport root. For a SubViewport child, this means: child rect → SubViewport → SubViewportContainer → Card → ... → root viewport.

I believe Godot does compute this correctly because SubViewport is still a Node in the scene tree, and its children are regular nodes with transforms. The local_to_global coordinate transformation should work through SubViewport.

But there might be edge cases with the SubViewport's render target... Let me not overthink this. The plan is to try it and see if it works. If tooltip positioning breaks, we can fix it in a follow-up task.

For now, let me simplify the approach for the plan:
- Don't try to put modifier tooltips on nodes inside the SubViewport
- Instead, emit a `modifier_hovered` signal from the Card (with the modifier data and screen position), and have the weapon_popup handle tooltip display
- Or: Since modifier icons are now rendered into the SubViewport texture, and modifier tooltip interactivity (mouse_entered on individual icons) requires SubViewport input handling which is complex, we can skip the tooltip for now and handle it as a follow-up

Actually, the simplest approach: Don't render modifier slots inside the SubViewport. Render them OUTSIDE, as children of the Card (same level as Shadow and SubViewportContainer). This way they get proper mouse events, and they scale with the Card's scale animation.

But then they won't have the 3D tilt effect. That's a trade-off.

Hmm, let me just go with `_subviewport.handle_input_locally = true` and set `_subviewport.gui_disable_input = false`. This should pass mouse events through to SubViewport children. Let me just do this in the plan and we'll test it.

Actually, for simplicity and to avoid blocking on SubViewport input issues, let me do this:
1. Modifier slot icons are added directly to the Card Control (not inside SubViewport), overlapping the bottom area
2. This way they get normal mouse events for tooltips
3. They won't get the 3D tilt but that's acceptable

Wait no, that's ugly. Let me just go with SubViewport `handle_input_locally = true` approach. The SubViewport in the scene gets `handle_input_locally = false` initially. We'll set it to `true` when modifier icons need tooltips.

Actually, let me look at this from a different angle. Let me set `handle_input_locally = true` on the SubViewport by default. Let me test if this causes issues with the Card's mouse_entered. If it does, we toggle it only when modifier slot icons are present.

You know what, I'm overcomplicating this. Let me just set `handle_input_locally = true` in the scene file and deal with any edge cases during testing. This is an implementation detail that can be adjusted.

Let me also think about whether `handle_input_locally = false` (the default in my scene) is fine. With `false`, the SubViewport does NOT process its own input - events go up to SubViewportContainer and then to Card. This means modifier icon tooltips WON'T work because the children inside the SubViewport never receive mouse events.

With `true`, the SubViewport processes input for its children AND the Card Control still gets mouse_entered/mouse_exited because those signals fire on the Control regardless of child input handling (they're about the Control's rect, not input routing).

Let me just go with `handle_input_locally = true` and move on.

OK wait, I need to also consider the `mouse_filter` setting. By default in the scene, the Card has `mouse_filter = MOUSE_FILTER_STOP` (set in _ready()). The SubViewportContainer should maybe be `MOUSE_FILTER_IGNORE` so it doesn't intercept events. But with `handle_input_locally = true`, the SubViewport is what handles events for its children, not the SubViewportContainer.

Alright, let me stop overthinking and write the plan. I'll set `handle_input_locally = true` in the scene. If tooltip positioning is off, that's a testing/fix issue.

Let me rewrite Task 4 properly.

For the weapon_popup integration:

**`_create_card()` replacement:**
- Creates a Card scene
- Calls `card.populate(icon, name, stats, modifier_icons)` 
- Adds modifier tooltip connections (these need the modifier icons accessible)
- Connects `card.card_clicked` to slot handling

**`_add_pickup_header()` replacement:**
- Creates a Card scene
- Calls `card.populate(icon, name, stats)` 
- Sets gold border via `card.set_selected(true)` if needed
- No click interaction (it's informational)

**`_create_remove_modifier_card()` replacement:**
- Creates a Card scene
- Calls `card.populate(icon, name, [description, slot_info])`
- Connects `card.card_clicked`

**`_create_transfer_card()` replacement:**
- Creates a Card scene
- Calls `card.populate(icon, name, [description])`
- Manages label visibility for transfer animation

For the transfer cards, the labels start with alpha 0.0 and fade in later. With SubViewport, we need to re-render after fading. This adds complexity. Let me handle this: after the transfer animation completes, we trigger `_subviewport.render_target_update_mode = SubViewport.UPDATE_ONCE` on each card to capture the final state.

Actually, the transfer card labels animate from alpha 0 to 1. But since they're inside the SubViewport, if the SubViewport is in UPDATE_DISABLED mode, the label alpha change won't be visible. We need to set UPDATE_ONCE after the alpha tween completes.

This is getting complex for the plan. Let me simplify: for transfer cards, don't use SubViewport rendering. Just create them as regular PanelContainer cards like before. The transfer cards are special-case and don't benefit much from the Balatro effect.

Actually, the spec says "All card-based UIs" should get the treatment. Let me handle this properly.

For transfer cards, after the label alpha tween:
```gdscript
label_tween.tween_callback(func(): card._subviewport.render_target_update_mode = SubViewport.UPDATE_ONCE)
```

OK, this is getting too detailed for the plan. Let me write the plan with the key pieces and handle edge cases during implementation.

Let me rewrite the plan more concisely.
```

Let me just write the full plan and stop overthinking. The subagent implementing it can handle the details.<｜end▁of▁thinking｜>

<｜｜DSML｜｜tool_calls>
<｜｜DSML｜｜invoke name="write">
<｜｜DSML｜｜parameter name="content" string="true"># Balatro-Style Card UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace inline programmatic card creation across all UI screens with a reusable `Card.tscn` scene that renders content via SubViewport with fake_3D perspective-tilt shader, elastic hover animations, and offset drop shadow.

**Architecture:** A single `Card` Control scene wraps a SubViewport→SubViewportContainer pipeline with a `fake_3D` shader. Content (icon, name, stats, modifier slots) is injected via `populate()` and rendered once. Hover animations (elastic scale, shadow offset, 3D tilt toward cursor) are self-contained in the Card script. Each existing UI replaces its `_create_*_card()` method body with `Card` scene instantiation + `populate()` call.

**Tech Stack:** Godot 4.x, GDScript, SubViewport, ShaderMaterial (canvas_item shader), Theme/StyleBoxFlat

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `shaders/ui/fake_3d.gdshader` | Create | 3D perspective tilt shader for card face |
| `src/ui/ui_theme.gd` | Modify | Add `get_card_shadow_stylebox()` method |
| `scenes/ui/card.tscn` | Create | Reusable card scene with SubViewport pipeline |
| `src/ui/card.gd` | Create | Card controller: populate, hover/tilt/click animations, selection state |
| `src/ui/weapon_popup.gd` | Modify | Replace card creation with Card scene; remove old hover methods |
| `src/ui/chest_ui.gd` | Modify | Replace card creation with Card scene; remove old hover methods |
| `src/economy/shop_ui.gd` | Modify | Replace card creation with Card scene; remove old hover methods |

---

### Task 1: Add fake_3D shader and shadow stylebox

**Files:**
- Create: `shaders/ui/fake_3d.gdshader`
- Modify: `src/ui/ui_theme.gd`

- [ ] **Step 1: Create the fake_3D shader**

Write `shaders/ui/fake_3d.gdshader`:

```glsl
shader_type canvas_item;

uniform vec2 rect_size = vec2(160.0, 220.0);
uniform float fov : hint_range(1, 179) = 90.0;
uniform bool cull_back = true;
uniform float y_rot : hint_range(-360.0, 360.0) = 0.0;
uniform float x_rot : hint_range(-360.0, 360.0) = 0.0;
uniform float inset : hint_range(0, 1) = 0.0;

varying flat vec2 o;
varying vec3 p;

void vertex(){
	float sin_b = sin(y_rot / 180.0 * PI);
	float cos_b = cos(y_rot / 180.0 * PI);
	float sin_c = sin(x_rot / 180.0 * PI);
	float cos_c = cos(x_rot / 180.0 * PI);

	mat3 inv_rot_mat;
	inv_rot_mat[0][0] = cos_b;
	inv_rot_mat[0][1] = 0.0;
	inv_rot_mat[0][2] = -sin_b;
	inv_rot_mat[1][0] = sin_b * sin_c;
	inv_rot_mat[1][1] = cos_c;
	inv_rot_mat[1][2] = cos_b * sin_c;
	inv_rot_mat[2][0] = sin_b * cos_c;
	inv_rot_mat[2][1] = -sin_c;
	inv_rot_mat[2][2] = cos_b * cos_c;

	float t = tan(fov / 360.0 * PI);
	p = inv_rot_mat * vec3((UV - 0.5), 0.5 / t);
	float v = (0.5 / t) + 0.5;
	p.xy *= v * inv_rot_mat[2].z;
	o = v * inv_rot_mat[2].xy;

	VERTEX += (UV - 0.5) * rect_size * t * (1.0 - inset);
}

void fragment(){
	if (cull_back && p.z <= 0.0) discard;
	vec2 uv = (p.xy / p.z).xy - o;
	COLOR = texture(TEXTURE, uv + 0.5);
	COLOR.a *= step(max(abs(uv.x), abs(uv.y)), 0.5);
}
```

- [ ] **Step 2: Add shadow stylebox method to ui_theme.gd**

Append this at the end of `src/ui/ui_theme.gd` (after line 124, the closing of `_set_container_constants`):

```gdscript
static func get_card_shadow_stylebox() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.12)
	s.set_corner_radius_all(8)
	return s
```

- [ ] **Step 3: Verify shader loads**

Run: `godot --headless --quit 2>&1 | grep -i "error\|parse" | head -10`

- [ ] **Step 4: Commit**

```bash
git add shaders/ui/fake_3d.gdshader src/ui/ui_theme.gd
git commit -m "feat: add fake_3D shader and card shadow stylebox"
```

---

### Task 2: Create Card script (card.gd)

**Files:**
- Create: `src/ui/card.gd`

- [ ] **Step 1: Write card.gd**

Write `src/ui/card.gd`:

```gdscript
class_name Card
extends Control

signal card_clicked

@export var card_size: Vector2 = Vector2(160, 220):
	set(v):
		card_size = v
		if is_node_ready():
			custom_minimum_size = card_size
			_shadow_rect.custom_minimum_size = card_size
			_subviewport.size = Vector2i(int(card_size.x), int(card_size.y))
			_subviewport_container.material.set_shader_parameter("rect_size", card_size)

@export var icon_size: Vector2 = Vector2(96, 96)
@export var mod_icon_size: Vector2 = Vector2(32, 32)
@export var tilt_max: float = 12.0
@export var hover_scale_target: float = 1.12

@onready var _shadow: Control = %Shadow
@onready var _shadow_rect: ColorRect = %ShadowRect
@onready var _subviewport_container: SubViewportContainer = %SubViewportContainer
@onready var _subviewport: SubViewport = %SubViewport
@onready var _card_panel: PanelContainer = %CardPanel
@onready var _content_vbox: VBoxContainer = %ContentVBox
@onready var _icon: TextureRect = %Icon
@onready var _name_label: Label = %NameLabel
@onready var _stats_container: VBoxContainer = %StatsContainer
@onready var _modifier_slots: HBoxContainer = %ModifierSlots

var _is_hovered: bool = false
var _is_selected: bool = false
var _hover_tween: Tween
var _exit_tween: Tween

func _ready() -> void:
	custom_minimum_size = card_size
	mouse_filter = MOUSE_FILTER_STOP
	mouse_entered.connect(_on_hover_enter)
	mouse_exited.connect(_on_hover_exit)
	gui_input.connect(_on_gui_input)
	_shadow_rect.custom_minimum_size = card_size
	_shadow.position = Vector2(6, 6)

func populate(icon_texture: Texture2D, card_name: String, stats: Array[String] = [], modifier_icons: Array[Texture2D] = []) -> void:
	if icon_texture:
		_icon.texture = icon_texture
		_icon.custom_minimum_size = icon_size
		_icon.show()
	else:
		_icon.hide()

	_name_label.text = card_name

	for child in _stats_container.get_children():
		child.queue_free()
	if stats.size() > 0:
		_stats_container.show()
		for stat_text in stats:
			var label := Label.new()
			label.text = stat_text
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
			label.add_theme_font_size_override("font_size", 14)
			_stats_container.add_child(label)
	else:
		_stats_container.hide()

	for child in _modifier_slots.get_children():
		child.queue_free()
	if modifier_icons.size() > 0:
		_modifier_slots.show()
		for mod_tex in modifier_icons:
			var slot := TextureRect.new()
			slot.custom_minimum_size = mod_icon_size
			slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			if mod_tex:
				slot.texture = mod_tex
			_modifier_slots.add_child(slot)
	else:
		_modifier_slots.hide()

	_subviewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func set_selected(selected: bool) -> void:
	_is_selected = selected
	_update_border_color()

func _update_border_color() -> void:
	if not is_instance_valid(_card_panel):
		return
	var style := _card_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if not style:
		return
	var new_style := style.duplicate() as StyleBoxFlat
	if _is_selected:
		new_style.border_color = UiTheme.ACCENT_GOLD
	elif _is_hovered:
		new_style.border_color = UiTheme.ACCENT
	else:
		new_style.border_color = UiTheme.PANEL_BORDER
	_card_panel.add_theme_stylebox_override("panel", new_style)
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _on_hover_enter() -> void:
	_is_hovered = true
	_animate_hover_enter()
	_update_border_color()
	set_process(true)

func _on_hover_exit() -> void:
	_is_hovered = false
	_animate_hover_exit()
	_update_border_color()
	var tilt_tween := create_tween()
	tilt_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tilt_tween.tween_method(_set_tilt_angles, Vector2(0.0, 0.0), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tilt_tween.tween_callback(func(): set_process(false))

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_hovered:
			_play_click_feedback()
			card_clicked.emit()

func _animate_hover_enter() -> void:
	if _exit_tween and _exit_tween.is_running():
		_exit_tween.kill()
	if _hover_tween and _hover_tween.is_running():
		return
	_hover_tween = create_tween()
	_hover_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var overshoot := hover_scale_target + 0.03
	_hover_tween.tween_property(self, "scale", Vector2(overshoot, overshoot), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(self, "scale", Vector2(hover_scale_target, hover_scale_target), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var shadow_tween := create_tween()
	shadow_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	shadow_tween.tween_property(_shadow, "position", Vector2(10, 10), 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _animate_hover_exit() -> void:
	if _hover_tween and _hover_tween.is_running():
		_hover_tween.kill()
	_exit_tween = create_tween()
	_exit_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_exit_tween.tween_property(self, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var shadow_tween := create_tween()
	shadow_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	shadow_tween.tween_property(_shadow, "position", Vector2(6, 6), 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _play_click_feedback() -> void:
	var current_scale := scale
	var ct := create_tween()
	ct.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	ct.tween_property(self, "scale", current_scale * 0.97, 0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	ct.tween_property(self, "scale", current_scale, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

func _set_tilt_angles(target: Vector2) -> void:
	var mat := _subviewport_container.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("x_rot", deg_to_rad(target.x))
		mat.set_shader_parameter("y_rot", deg_to_rad(target.y))

func _process(_delta: float) -> void:
	if not _is_hovered:
		return
	var mouse_pos := get_local_mouse_position()
	var ratio_x := clampf(mouse_pos.x / card_size.x, 0.0, 1.0)
	var ratio_y := clampf(mouse_pos.y / card_size.y, 0.0, 1.0)
	var x_rot := lerpf(-tilt_max, tilt_max, ratio_y)
	var y_rot := lerpf(-tilt_max, tilt_max, ratio_x)
	_set_tilt_angles(Vector2(x_rot, y_rot))
```

- [ ] **Step 2: Verify no parse errors**

Run: `godot --headless --quit 2>&1 | grep -E "error|Parse" | head -10`

- [ ] **Step 3: Commit**

```bash
git add src/ui/card.gd
git commit -m "feat: add Card controller script with hover/tilt/click animations"
```

---

### Task 3: Create Card scene (card.tscn)

**Files:**
- Create: `scenes/ui/card.tscn`

- [ ] **Step 1: Write card.tscn**

Write `scenes/ui/card.tscn`:

```ini
[gd_scene load_steps=6 format=3 uid="uid://cardscene"]

[ext_resource type="Script" path="res://src/ui/card.gd" id="1_card_script"]
[ext_resource type="Shader" path="res://shaders/ui/fake_3d.gdshader" id="2_shader"]

[sub_resource type="ShaderMaterial" id="ShaderMaterial_fake3d"]
shader = ExtResource("2_shader")
shader_parameter/rect_size = Vector2(160, 220)
shader_parameter/fov = 90.0
shader_parameter/cull_back = true
shader_parameter/y_rot = 0.0
shader_parameter/x_rot = 0.0
shader_parameter/inset = 0.0

[sub_resource type="StyleBoxFlat" id="StyleBox_card_panel"]
bg_color = Color(0.212, 0.110, 0.133, 1)
border_color = Color(0.545, 0.227, 0.165, 1)
border_width_left = 2
border_width_right = 2
border_width_top = 2
border_width_bottom = 2
corner_radius_top_left = 8
corner_radius_top_right = 8
corner_radius_bottom_left = 8
corner_radius_bottom_right = 8
content_margin_left = 12.0
content_margin_right = 12.0
content_margin_top = 8.0
content_margin_bottom = 8.0
shadow_color = Color(0, 0, 0, 0.502)
shadow_size = 8

[sub_resource type="StyleBoxFlat" id="StyleBox_shadow"]
bg_color = Color(0, 0, 0, 0.12)
corner_radius_top_left = 8
corner_radius_top_right = 8
corner_radius_bottom_left = 8
corner_radius_bottom_right = 8

[node name="Card" type="Control"]
layout_mode = 3
anchors_preset = 0
mouse_filter = 2
script = ExtResource("1_card_script")

[node name="Shadow" type="Control" parent="."]
unique_name_in_owner = true
layout_mode = 0
offset_right = 160.0
offset_bottom = 220.0
mouse_filter = 2

[node name="ShadowRect" type="ColorRect" parent="Shadow"]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
color = Color(0, 0, 0, 0.12)

[node name="SubViewportContainer" type="SubViewportContainer" parent="."]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
stretch = true
material = SubResource("ShaderMaterial_fake3d")

[node name="SubViewport" type="SubViewport" parent="SubViewportContainer"]
unique_name_in_owner = true
size = Vector2i(160, 220)
transparent_bg = true
render_target_update_mode = 1
handle_input_locally = false

[node name="CardPanel" type="PanelContainer" parent="SubViewportContainer/SubViewport"]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
theme_override_styles/panel = SubResource("StyleBox_card_panel")

[node name="ContentVBox" type="VBoxContainer" parent="SubViewportContainer/SubViewport/CardPanel"]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
alignment = 1
theme_override_constants/separation = 8

[node name="Icon" type="TextureRect" parent="SubViewportContainer/SubViewport/CardPanel/ContentVBox"]
unique_name_in_owner = true
layout_mode = 2
custom_minimum_size = Vector2(96, 96)
size_flags_horizontal = 4
stretch_mode = 5

[node name="NameLabel" type="Label" parent="SubViewportContainer/SubViewport/CardPanel/ContentVBox"]
unique_name_in_owner = true
layout_mode = 2
text = "Name"
horizontal_alignment = 1
theme_override_colors/font_color = Color(1, 0.843, 0, 1)

[node name="StatsContainer" type="VBoxContainer" parent="SubViewportContainer/SubViewport/CardPanel/ContentVBox"]
unique_name_in_owner = true
layout_mode = 2
alignment = 1
theme_override_constants/separation = 4

[node name="ModifierSlots" type="HBoxContainer" parent="SubViewportContainer/SubViewport/CardPanel/ContentVBox"]
unique_name_in_owner = true
layout_mode = 2
alignment = 1
theme_override_constants/separation = 4
```

- [ ] **Step 2: Verify scene loads**

Run: `godot --headless --quit 2>&1 | grep -iE "error" | head -10`

- [ ] **Step 3: Commit**

```bash
git add scenes/ui/card.tscn
git commit -m "feat: add Card scene with SubViewport and fake_3D pipeline"
```

---

### Task 4: Integrate Card into weapon_popup.gd

**Files:**
- Modify: `src/ui/weapon_popup.gd`

- [ ] **Step 1: Add Card preload constant**

At line 9 (after the `@onready` block, before `_ready`), add:

```gdscript
const CARD_SCENE := preload("res://scenes/ui/card.tscn")
```

- [ ] **Step 2: Replace `_create_card()` method (lines 291-339)**

Replace the entire method body with:

```gdscript
func _create_card(weapon: Weapon, slot_index: int) -> Control:
	var card: Card = CARD_SCENE.instantiate()
	if weapon == null:
		card.populate(null, "EMPTY")
	else:
		var stats: Array[String] = []
		var base_stats := weapon.get_base_stats()
		stats.append("Cooldown: %.1fs" % base_stats["cooldown"])
		stats.append("Damage: %.0f" % base_stats["damage"])
		var mod_icons: Array[Texture2D] = []
		for i in range(weapon.modifier_slot_count):
			var mod: Modifier = weapon.get_modifier_at(i)
			mod_icons.append(mod.icon_texture if mod else null)
		card.populate(weapon.icon_texture, weapon.name, stats, mod_icons)
		_add_modifier_slots_to_card(card, weapon)
	card.card_clicked.connect(_on_card_input.bind(slot_index))
	card.is_selectable = true
	return card
```

- [ ] **Step 3: Add `_add_modifier_slots_to_card()` helper**

Add this method (the modifier slots built in `populate()` are just static textures; this adds interactive tooltip icons overlaid outside the SubViewport):

```gdscript
func _add_modifier_slots_to_card(card: Card, weapon: Weapon) -> void:
	var overlay := HBoxContainer.new()
	overlay.add_theme_constant_override("separation", 4)
	overlay.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	for i in range(weapon.modifier_slot_count):
		var modifier: Modifier = weapon.get_modifier_at(i)
		var btn := TextureButton.new()
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.custom_minimum_size = MODIFIER_ICON_SIZE
		if modifier != null and modifier.icon_texture != null:
			btn.texture_normal = modifier.icon_texture
		else:
			btn.texture_normal = null
		btn.mouse_entered.connect(_on_modifier_icon_mouse_entered.bind(modifier, btn, card))
		btn.mouse_exited.connect(_on_modifier_icon_mouse_exited.bind(card))
		overlay.add_child(btn)
	card.add_child(overlay)
	overlay.position = Vector2(12, card.card_size.y - MODIFIER_ICON_SIZE.y - 8)
	overlay.size.x = card.card_size.x - 24
```

- [ ] **Step 4: Replace `_add_pickup_header()` (lines 200-265)**

Replace the entire method with:

```gdscript
func _add_pickup_header() -> void:
	_clear_pickup_header()
	if _pickup_weapon == null:
		return
	var vbox := %CardsContainer.get_parent() as VBoxContainer
	if vbox == null:
		return
	var title_index := (%TitleLabel as Node).get_index()

	var header_label := Label.new()
	header_label.text = "New weapon:"
	header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	header_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(header_label)
	vbox.move_child(header_label, title_index + 1)
	_pickup_header_elements.append(header_label)

	var card: Card = CARD_SCENE.instantiate()
	var stats: Array[String] = []
	var base_stats := _pickup_weapon.get_base_stats()
	stats.append("Cooldown: %.1fs" % base_stats["cooldown"])
	stats.append("Damage: %.0f" % base_stats["damage"])
	card.populate(_pickup_weapon.icon_texture, _pickup_weapon.name, stats)
	card.set_selected(true)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	vbox.add_child(card)
	vbox.move_child(card, title_index + 2)
	_pickup_header_elements.append(card)
```

- [ ] **Step 5: Replace `_create_remove_modifier_card()` (lines 551-600)**

Replace the entire method body with:

```gdscript
func _create_remove_modifier_card(modifier: Modifier, slot_index: int) -> Control:
	var card: Card = CARD_SCENE.instantiate()
	var stats: Array[String] = []
	var desc := modifier.get_description()
	if desc != "":
		stats.append(desc)
	stats.append("slot %d" % (slot_index + 1))
	card.populate(modifier.icon_texture, modifier.name, stats)
	card.card_clicked.connect(_on_remove_modifier_card_input.bind(slot_index))
	return card
```

- [ ] **Step 6: Replace `_create_transfer_card()` (lines 809-864)**

Replace the entire method body with:

```gdscript
func _create_transfer_card(modifier: Modifier, index: int) -> Control:
	var card: Card = CARD_SCENE.instantiate()
	var stats: Array[String] = []
	var desc_text := modifier.get_description()
	if desc_text != "":
		stats.append(desc_text)
	card.populate(modifier.icon_texture, modifier.name, stats)
	card.modulate.a = 0.0
	card.card_clicked.connect(_on_transfer_card_input.bind(index))
	return card
```

Note: For transfer cards, the `.modulate.a = 0.0` fade and subsequent tween in `_build_transfer_cards()` uses the card node's `modulate` property, which applies on top of the SubViewportContainer — this is fine. The labels inside the SubViewport will render at full alpha; the overall card fades via modulate. When the card appears, re-render:

In `_build_transfer_cards()`, after the tween that sets `card.modulate.a = 1.0`, add a callback to re-render:

At line 792, after `card.modulate.a = 1.0`, add:

```gdscript
		if card is Card:
			var svp := card.get_node("SubViewportContainer/SubViewport") as SubViewport
			if svp:
				var cb_tween := card.create_tween()
				cb_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
				cb_tween.tween_callback(func(): svp.render_target_update_mode = SubViewport.UPDATE_ONCE).set_delay(0.1)
```

Also update the label handling: remove the `card.set_meta("transfer_labels", text_labels)` pattern. The transfer card content is now rendered in the SubViewport, so label alpha animation doesn't apply through modulate. Instead, use the card's root modulate for the fade effect. Update `_build_transfer_cards()`:

- Remove lines 754-763 (label collection): delete `var all_labels: Array[Label] = []`, `card.get_meta("transfer_labels")`, and the label loop
- Remove lines 799-805 (label alpha tween): delete the label_delay and label_tween block

- [ ] **Step 7: Remove old hover methods**

Remove:
- `_on_card_mouse_entered()` (lines 392-402)
- `_on_card_mouse_exited()` (lines 405-416)

The Card handles hover animations internally.

- [ ] **Step 8: Update `_highlight_slot()` (lines 659-672)**

Replace the body with Card's `set_selected()`:

```gdscript
func _highlight_slot(slot_index: int) -> void:
	var cards := _cards_container.get_children()
	if slot_index < cards.size():
		var c: Control = cards[slot_index]
		if c is Card:
			c.set_selected(true)
		var tween := c.create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.set_loops()
		tween.tween_property(c, "modulate", Color(1.0, 0.85, 0.5, 1.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_property(c, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
```

- [ ] **Step 9: Update `_on_modifier_icon_mouse_exited()` (lines 454-457)**

Change the parameter type from `PanelContainer` to `Control` (since Card is a Control, not PanelContainer):

```gdscript
func _on_modifier_icon_mouse_exited(card: Control) -> void:
	_cancel_modifier_tooltip()
	if not card.get_global_rect().has_point(card.get_global_mouse_position()):
		card._on_hover_exit()
```

Wait — `_on_hover_exit()` is not callable from outside since it's a public method on Card (used by mouse_exited signal). Actually, it IS callable since it's not marked private. But we should change the approach: the mouse_exited on the overlay modifier button should trigger the card's hover exit. Since the Card handles hover internally via `mouse_entered`/`mouse_exited`, the overlay modifier buttons should not separately manage the card's hover state.

Actually, the existing code has a complex pattern: when the mouse exits a modifier icon, it checks if the mouse is still over the card — if not, it calls `_on_card_mouse_exited(card)`. With the Card managing its own hover, this edge case may cause flickering (mouse_exits modifier icon, enters tiny gap, re-enters card). Since the Card uses Control-level `mouse_entered`/`mouse_exited` which fires on the Card's rect, the gap between modifier icons and card edge should not cause unwanted exit events.

Simplify: remove the override entirely. The Card's own mouse_entered/mouse_exited handles hover state. The modifier icon buttons just do tooltip show/hide without affecting card hover.

Replace `_on_modifier_icon_mouse_exited`:

```gdscript
func _on_modifier_icon_mouse_exited(card: Control) -> void:
	_cancel_modifier_tooltip()
```

- [ ] **Step 10: Verify no parse errors**

Run: `godot --headless --quit 2>&1 | grep -E "error|Parse" | head -20`

- [ ] **Step 11: Commit**

```bash
git add src/ui/weapon_popup.gd
git commit -m "feat: integrate Card scene into weapon_popup"
```

---

### Task 5: Integrate Card into chest_ui.gd

**Files:**
- Modify: `src/ui/chest_ui.gd`

- [ ] **Step 1: Add Card preload**

At the top of the constants section (after `const CARD_MIN_SIZE`), read the file first to find the right spot. Add:

```gdscript
const CARD_SCENE := preload("res://scenes/ui/card.tscn")
```

- [ ] **Step 2: Replace `_create_weapon_card()` (lines 136-200)**

Replace the entire method with:

```gdscript
func _create_weapon_card(weapon: Weapon, index: int) -> Control:
	var card: Card = CARD_SCENE.instantiate()
	card.card_size = CARD_MIN_SIZE
	card.icon_size = ICON_SIZE
	var stats: Array[String] = []
	var base_stats := weapon.get_base_stats()
	stats.append("Cooldown: %.1fs" % base_stats["cooldown"])
	stats.append("Damage: %.0f" % base_stats["damage"])
	card.populate(weapon.icon_texture, weapon.name, stats)
	card.card_clicked.connect(func(): _select_weapon(index))
	return card
```

Note: The existing code connects `gui_input` to `_on_card_gui_input.bind(index, card)`. The `_select_weapon(index)` method does the actual selection. Replace the gui_input connection with direct `card_clicked` → `_select_weapon(index)`.

Check that `_on_card_gui_input` (around line 222-232) is no longer needed — it just calls `_select_weapon`. If nothing else references it, remove it.

- [ ] **Step 3: Remove old hover methods**

Remove:
- `_on_card_mouse_entered` (lines 203-???)
- `_on_card_mouse_exited` (continues from mouse_entered)
- `_on_card_gui_input` if only used for card click

Read the file to confirm exact line ranges, then remove them.

- [ ] **Step 4: Update `_build_cards()` method (around lines 116-133)**

The `_card_slots` array stores `PanelContainer` references. Update the type if needed. The `UiAnimations.stagger_slide_in()` call works with any `Control`, so this should be fine.

- [ ] **Step 5: Verify no parse errors**

Run: `godot --headless --quit 2>&1 | grep -E "error|Parse" | head -20`

- [ ] **Step 6: Commit**

```bash
git add src/ui/chest_ui.gd
git commit -m "feat: integrate Card scene into chest_ui"
```

---

### Task 6: Integrate Card into shop_ui.gd

**Files:**
- Modify: `src/economy/shop_ui.gd`

- [ ] **Step 1: Add Card preload**

At the top constants section:

```gdscript
const CARD_SCENE := preload("res://scenes/ui/card.tscn")
```

- [ ] **Step 2: Replace `_create_offer_card()` (lines 263-313)**

Replace the entire method with:

```gdscript
func _create_offer_card(offer: ShopOffer, slot: Control) -> Control:
	var card: Card = CARD_SCENE.instantiate()
	card.card_size = CARD_MIN_SIZE
	card.icon_size = MODIFIER_ICON_SIZE
	var stats: Array[String] = []
	var desc := offer.modifier.get_description()
	if desc != "":
		stats.append(desc)
	card.populate(offer.modifier.icon_texture, offer.modifier.name, stats)
	card.card_clicked.connect(_on_buy_pressed.bind(offer, card, slot))
	return card
```

- [ ] **Step 3: Replace `_create_remove_card()` (lines 316-365)**

Replace the entire method with:

```gdscript
func _create_remove_card() -> Control:
	var card: Card = CARD_SCENE.instantiate()
	card.card_size = CARD_MIN_SIZE
	card.icon_size = MODIFIER_ICON_SIZE
	var stats: Array[String] = []
	stats.append("Removes the last modifier from your inventory")
	card.populate(null, "Remove Modifier", stats)
	card.set_name_color(UiTheme.DANGER)
	card.card_clicked.connect(_on_remove_card_input.bind(card))
	return card
```

- [ ] **Step 4: Remove old hover methods**

Read shop_ui.gd to find and remove `_on_card_mouse_entered` and `_on_card_mouse_exited`. Also check if `_on_card_gui_input` (line 275) needs updating — it's now replaced by `card_clicked` connection.

- [ ] **Step 5: Update `_on_buy_pressed` signature if needed**

The `_on_buy_pressed(offer, card, slot)` method takes `card: Control` (line 368). It also changes the border color based on affordability. With Card, we need to call `card.set_selected(true)` or similar for highlight. Check the method body and update as needed. If it just uses the card reference for the price/highlight logic, the Control type works fine.

- [ ] **Step 6: Verify no parse errors**

Run: `godot --headless --quit 2>&1 | grep -E "error|Parse" | head -20`

- [ ] **Step 7: Commit**

```bash
git add src/economy/shop_ui.gd
git commit -m "feat: integrate Card scene into shop_ui"
```

---

### Task 7: Verification

- [ ] **Step 1: Run Godot headless to verify all scripts parse**

```bash
godot --headless --quit 2>&1 | grep -E "error|Parse Error" | head -20
```

Expected: No parse errors. Script warnings are acceptable.

- [ ] **Step 2: Check for any remaining references to removed methods**

```bash
rg "_on_card_mouse_entered|_on_card_mouse_exited" src/ --include "*.gd"
```

Expected: No results (all removed).

- [ ] **Step 3: Check Card scene instantiation works in all three UIs**

```bash
rg "CARD_SCENE.instantiate" src/ --include "*.gd"
```

Expected: Results in weapon_popup.gd, chest_ui.gd, shop_ui.gd.

- [ ] **Step 4: Final verification commit (if anything changed)**

```bash
git status
```
