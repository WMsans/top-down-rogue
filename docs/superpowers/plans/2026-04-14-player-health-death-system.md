# Player Health & Death System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a player health and death system with HP tracking, i-frames, lava damage, a health UI bar, and a Slay the Spire-style death screen with visual effects.

**Architecture:** Component-based — `HealthComponent` (manages HP, i-frames, blink), `LavaDamageChecker` (samples terrain for damage), `HealthUI` (HUD bar), `DeathScreen` (overlay + effects). All wired via signals. MaterialDef gains a `damage` property for data-driven hazard damage.

**Tech Stack:** GDScript, Godot 4.6, existing project patterns (CanvasLayer UI, pixel font, SceneManager for transitions).

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `src/player/health_component.gd` | HP tracking, i-frames, blink effect, signals |
| Create | `src/player/lava_damage_checker.gd` | Sample terrain materials, apply damage |
| Create | `src/ui/health_ui.gd` | Health bar + numeric label in HUD |
| Create | `scenes/ui/health_ui.tscn` | Health UI scene |
| Create | `src/ui/death_screen.gd` | Death overlay animation + continue button |
| Create | `scenes/ui/death_screen.tscn` | Death screen scene |
| Modify | `src/autoload/material_registry.gd` | Add `damage` property to MaterialDef |
| Modify | `src/player/player_controller.gd` | Add "player" group, stop movement on death |

---

### Task 1: Add damage property to MaterialDef

**Files:**
- Modify: `src/autoload/material_registry.gd`

- [ ] **Step 1: Add `damage` property and `p_damage` parameter to MaterialDef**

In `material_registry.gd`, add `var damage: int` to the `MaterialDef` class and `p_damage: int = 0` to the `_init` parameters.

```gdscript
class MaterialDef:
	var id: int
	var name: String
	var texture_path: String
	var flammable: bool
	var ignition_temp: int
	var burn_health: int
	var has_collider: bool
	var has_wall_extension: bool
	var tint_color: Color
	var fluid: bool
	var damage: int

	func _init(
		p_name: String,
		p_texture_path: String,
		p_flammable: bool,
		p_ignition_temp: int,
		p_burn_health: int,
		p_has_collider: bool,
		p_has_wall_extension: bool,
		p_tint_color: Color = Color(0, 0, 0, 0),
		p_fluid: bool = false,
		p_damage: int = 0
	):
		name = p_name
		texture_path = p_texture_path
		flammable = p_flammable
		ignition_temp = p_ignition_temp
		burn_health = p_burn_health
		has_collider = p_has_collider
		has_wall_extension = p_has_wall_extension
		tint_color = p_tint_color
		fluid = p_fluid
		damage = p_damage
```

- [ ] **Step 2: Update LAVA material definition with `damage = 10`**

Change the `mat_lava` definition to pass `p_damage = 10`:

```gdscript
	var mat_lava := MaterialDef.new(
		"LAVA", "",
		false, 0, 0,
		false, false,
		Color(0.9, 0.4, 0.1, 1.0),
		true,
		10
	)
```

(AIR, WOOD, STONE, GAS all get the default `p_damage = 0`, so no changes needed for them.)

- [ ] **Step 3: Add `get_damage` lookup method**

Add this method after the existing `get_fluids` method:

```gdscript
func get_damage(material_id: int) -> int:
	if material_id < 0 or material_id >= materials.size():
		return 0
	return materials[material_id].damage
```

- [ ] **Step 4: Commit**

```bash
git add src/autoload/material_registry.gd
git commit -m "feat: add damage property to MaterialDef for hazard damage"
```

---

### Task 2: Create HealthComponent

**Files:**
- Create: `src/player/health_component.gd`

- [ ] **Step 1: Write the HealthComponent script**

Create `src/player/health_component.gd`:

```gdscript
class_name HealthComponent
extends Node

signal health_changed(current: int, maximum: int)
signal died

@export var max_health: int = 100
@export var invincibility_duration: float = 1.0

const BLINK_INTERVAL := 0.08

var _current_health: int
var _invincible_timer: float = 0.0
var _is_dead: bool = false
var _is_invincible: bool = false
var _blink_timer: float = 0.0
var _color_rect: ColorRect


func _ready() -> void:
	_current_health = max_health
	_color_rect = get_parent().get_node("ColorRect")


func take_damage(amount: int) -> void:
	if _is_dead or _is_invincible:
		return
	_current_health = maxi(_current_health - amount, 0)
	_is_invincible = true
	_invincible_timer = invincibility_duration
	health_changed.emit(_current_health, max_health)
	if _current_health <= 0:
		_is_dead = true
		_color_rect.visible = true
		died.emit()


func heal(amount: int) -> void:
	if _is_dead:
		return
	_current_health = mini(_current_health + amount, max_health)
	health_changed.emit(_current_health, max_health)


func is_dead() -> bool:
	return _is_dead


func _physics_process(delta: float) -> void:
	if _is_invincible:
		_invincible_timer -= delta
		if _invincible_timer <= 0.0:
			_is_invincible = false
			_invincible_timer = 0.0
			if not _is_dead:
				_color_rect.visible = true


func _process(_delta: float) -> void:
	if _is_invincible and not _is_dead:
		_blink_timer += _delta
		if _blink_timer >= BLINK_INTERVAL:
			_blink_timer -= BLINK_INTERVAL
			_color_rect.visible = not _color_rect.visible
```

- [ ] **Step 2: Commit**

```bash
git add src/player/health_component.gd
git commit -m "feat: add HealthComponent with HP tracking, i-frames, and blink"
```

---

### Task 3: Create LavaDamageChecker

**Files:**
- Create: `src/player/lava_damage_checker.gd`

- [ ] **Step 1: Write the LavaDamageChecker script**

Create `src/player/lava_damage_checker.gd`. Note: `_shadow_grid` is lazily initialized in `_physics_process` because it's set by `PlayerController._ready()`, which runs *after* child `_ready()` calls. By the first `_physics_process` frame, it's guaranteed to be available.

```gdscript
class_name LavaDamageChecker
extends Node

const BODY_WIDTH := 8
const BODY_HEIGHT := 12
const SAMPLE_POINTS_X := 3
const SAMPLE_POINTS_Y := 3

var _health_component: HealthComponent
var _shadow_grid: ShadowGrid


func _ready() -> void:
	var player := get_parent()
	_health_component = player.get_node("HealthComponent")


func _physics_process(_delta: float) -> void:
	if _health_component.is_dead():
		return
	if _shadow_grid == null:
		_shadow_grid = get_parent().shadow_grid
		if _shadow_grid == null:
			return

	var total_damage := 0
	var pos: Vector2 = get_parent().position
	var half_w := BODY_WIDTH / 2.0
	var half_h := BODY_HEIGHT / 2.0

	for ix in range(SAMPLE_POINTS_X):
		for iy in range(SAMPLE_POINTS_Y):
			var sample_x := int(round(pos.x - half_w + float(ix) * BODY_WIDTH / float(SAMPLE_POINTS_X - 1)))
			var sample_y := int(round(pos.y - half_h + float(iy) * BODY_HEIGHT / float(SAMPLE_POINTS_Y - 1)))
			var material_id := _shadow_grid.get_material(sample_x, sample_y)
			total_damage += MaterialRegistry.get_damage(material_id)

	if total_damage > 0:
		_health_component.take_damage(total_damage)
```

- [ ] **Step 2: Commit**

```bash
git add src/player/lava_damage_checker.gd
git commit -m "feat: add LavaDamageChecker for data-driven terrain hazard damage"
```

---

### Task 4: Update PlayerController + Modify player.tscn

**Files:**
- Modify: `src/player/player_controller.gd`
- Modify: `scenes/player.tscn`

- [ ] **Step 1: Add "player" group and death-movement stop to PlayerController**

In `player_controller.gd`, add `add_to_group("player")` in `_ready()` and add a death check at the top of `_physics_process`:

The `_ready()` function becomes:

```gdscript
func _ready() -> void:
	add_to_group("player")
	shadow_grid = ShadowGridScript.new()
	shadow_grid.world_manager = _world_manager
	add_child(shadow_grid)

	_world_manager.tracking_position = global_position
	_world_manager.shadow_grid = shadow_grid

	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("gas_interactors")

	await get_tree().process_frame
	await get_tree().process_frame
	var spawn_pos: Vector2i = _world_manager.find_spawn_position(Vector2i.ZERO, Vector2i(BODY_WIDTH, BODY_HEIGHT))
	position = Vector2(spawn_pos) + Vector2(BODY_WIDTH / 2.0, BODY_HEIGHT)
	shadow_grid.force_sync(Vector2i(position))
```

The `_physics_process()` function becomes:

```gdscript
func _physics_process(delta: float) -> void:
	if shadow_grid == null:
		return

	var health_component := get_node_or_null("HealthComponent")
	if health_component and health_component.is_dead():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var input_dir := _get_input_direction()
	if input_dir != Vector2.ZERO:
		_last_facing = input_dir
	_apply_movement(input_dir, delta)
	move_and_slide()

	_world_manager.tracking_position = global_position
	shadow_grid.update_sync(Vector2i(int(floor(position.x)), int(floor(position.y))))
```

- [ ] **Step 2: Add HealthComponent and LavaDamageChecker nodes to player.tscn**

In `scenes/player.tscn`, add two ext_resource entries after the existing ones (lines 3-4):

```
[ext_resource type="Script" path="res://src/player/health_component.gd" id="health_comp"]
[ext_resource type="Script" path="res://src/player/lava_damage_checker.gd" id="lava_dmg"]
```

Add two new node entries after the WeaponManager node (after line 45):

```
[node name="HealthComponent" type="Node" parent="."]
script = ExtResource("health_comp")

[node name="LavaDamageChecker" type="Node" parent="."]
script = ExtResource("lava_dmg")
```

- [ ] **Step 3: Commit**

```bash
git add src/player/player_controller.gd scenes/player.tscn
git commit -m "feat: integrate HealthComponent and LavaDamageChecker into player scene"
```

---

### Task 5: Create HealthUI

**Files:**
- Create: `src/ui/health_ui.gd`
- Create: `scenes/ui/health_ui.tscn`

- [ ] **Step 1: Write the HealthUI script**

Create `src/ui/health_ui.gd`:

```gdscript
extends CanvasLayer

const PIXEL_FONT := preload("res://textures/DawnLike/GUI/SDS_8x8.ttf")

@onready var _bar_background: ColorRect = %BarBackground
@onready var _bar_fill: ColorRect = %BarFill
@onready var _health_label: Label = %HealthLabel

var _health_component: HealthComponent


func _ready() -> void:
	_apply_theme()
	var player := get_tree().get_first_node_in_group("player")
	if player:
		_health_component = player.get_node("HealthComponent")
		_health_component.health_changed.connect(_on_health_changed)
		_health_component.died.connect(_on_died)
		_on_health_changed(_health_component.max_health, _health_component.max_health)


func _on_health_changed(current: int, maximum: int) -> void:
	_bar_fill.size.x = _bar_background.size.x * (float(current) / float(maximum))
	_health_label.text = "%d / %d" % [current, maximum]


func _on_died() -> void:
	_bar_fill.size.x = 0.0
	_health_label.text = "0 / %d" % _health_component.max_health


func _apply_theme() -> void:
	var t := Theme.new()
	t.default_font = PIXEL_FONT
	t.set_font_size("font_size", "Label", 16)
	t.set_color("font_color", "Label", Color(0.976, 0.988, 0.953))
	_health_label.theme = t
```

- [ ] **Step 2: Create the HealthUI scene file**

Create `scenes/ui/health_ui.tscn`:

```
[gd_scene format=3]

[node name="HealthUI" type="CanvasLayer"]
layer = 5

[node name="MarginContainer" type="MarginContainer" parent="."]
anchors_preset = -1
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 8.0
offset_top = 8.0

[node name="VBoxContainer" type="VBoxContainer" parent="MarginContainer"]
layout_mode = 2
theme_override_constants/separation = 2

[node name="HealthLabel" type="Label" parent="MarginContainer/VBoxContainer"]
unique_name_in_owner = true
layout_mode = 2
text = "100 / 100"

[node name="BarBackground" type="ColorRect" parent="MarginContainer/VBoxContainer"]
unique_name_in_owner = true
custom_minimum_size = Vector2(120, 10)
layout_mode = 2
color = Color(0.2, 0.2, 0.2, 1)
clip_contents = true

[node name="BarFill" type="ColorRect" parent="MarginContainer/VBoxContainer/BarBackground"]
unique_name_in_owner = true
offset_right = 120.0
offset_bottom = 10.0
color = Color(0.8, 0.2, 0.2, 1)
```

`BarBackground` has `clip_contents = true` so `BarFill` (its child) is clipped to the background's bounds. `BarFill` is positioned at (0,0) with initial size 120×10 matching the background. In code, we set `_bar_fill.size.x` proportionally to the health ratio, and clipping handles the rest.

- [ ] **Step 3: Commit**

```bash
git add src/ui/health_ui.gd scenes/ui/health_ui.tscn
git commit -m "feat: add HealthUI with bar and numeric health display"
```

---

### Task 6: Create DeathScreen

**Files:**
- Create: `src/ui/death_screen.gd`
- Create: `scenes/ui/death_screen.tscn`

- [ ] **Step 1: Write the DeathScreen script**

Create `src/ui/death_screen.gd`:

```gdscript
extends CanvasLayer

const PIXEL_FONT := preload("res://textures/DawnLike/GUI/SDS_8x8.ttf")

@onready var _overlay: ColorRect = %Overlay
@onready var _red_flash: ColorRect = %RedFlash
@onready var _died_label: Label = %DiedLabel
@onready var _continue_button: Button = %ContinueButton
@onready var _vbox: VBoxContainer = %DeathVBox

var _health_component: HealthComponent


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.visible = false
	_red_flash.visible = false
	_vbox.visible = false
	_apply_theme()
	_continue_button.pressed.connect(_on_continue_pressed)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		_health_component = player.get_node("HealthComponent")
		_health_component.died.connect(_on_player_died)


func _on_player_died() -> void:
	SceneManager.set_paused(true)
	_play_death_sequence()


func _play_death_sequence() -> void:
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.visible = true
	_red_flash.color = Color(1, 0, 0, 0)
	_red_flash.visible = true
	_vbox.visible = true
	_died_label.modulate.a = 0.0
	_continue_button.modulate.a = 0.0
	_continue_button.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

	tween.parallel().tween_property(_red_flash, "color:a", 0.4, 0.15).from(0.0)
	tween.parallel().tween_property(_overlay, "color:a", 0.7, 0.8).from(0.0)
	tween.parallel().tween_property(_red_flash, "color:a", 0.0, 0.15).from(0.4).set_delay(0.15)
	tween.chain().tween_interval(0.5)
	tween.tween_property(_died_label, "modulate:a", 1.0, 0.5).from(0.0)
	tween.tween_property(_continue_button, "modulate:a", 1.0, 0.3).from(0.0)
	tween.tween_callback(_on_sequence_complete)


func _on_sequence_complete() -> void:
	_continue_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_continue_button.grab_focus()


func _on_continue_pressed() -> void:
	SceneManager.set_paused(false)
	SceneManager.go_to_main_menu()


func _apply_theme() -> void:
	var t := Theme.new()
	t.default_font = PIXEL_FONT
	t.set_font_size("font_size", "Button", 24)
	t.set_font_size("font_size", "Label", 32)
	t.set_color("font_color", "Button", Color(0.976, 0.988, 0.953))
	t.set_color("font_color", "Label", Color(0.976, 0.988, 0.953))
	t.set_color("font_hover_color", "Button", Color(0.741, 0.576, 0.976))
	_vbox.theme = t
```

Death sequence timing:
- t=0.0s: Red flash fades in (0.15s) + Dim overlay starts fading in (0.8s)
- t=0.15s: Red flash starts fading out (0.15s)
- t=0.3s: Red flash gone
- t=0.8s: Dim overlay at 0.7 alpha. After overlay: 0.5s pause.
- ~t=1.3s: "YOU DIED" text fades in over 0.5s
- ~t=1.8s: Continue button fades in over 0.3s
- ~t=2.1s: Sequence complete, button becomes interactive

- [ ] **Step 2: Create the DeathScreen scene file**

Create `scenes/ui/death_screen.tscn`:

```
[gd_scene format=3]

[node name="DeathScreen" type="CanvasLayer"]
layer = 20

[node name="Overlay" type="ColorRect" parent="."]
unique_name_in_owner = true
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(0, 0, 0, 0)

[node name="RedFlash" type="ColorRect" parent="."]
unique_name_in_owner = true
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(1, 0, 0, 0)

[node name="CenterContainer" type="CenterContainer" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

[node name="DeathVBox" type="VBoxContainer" parent="CenterContainer"]
unique_name_in_owner = true
layout_mode = 2
theme_override_constants/separation = 24

[node name="DiedLabel" type="Label" parent="CenterContainer/DeathVBox"]
unique_name_in_owner = true
layout_mode = 2
text = "YOU DIED"
horizontal_alignment = 1

[node name="ContinueButton" type="Button" parent="CenterContainer/DeathVBox"]
unique_name_in_owner = true
layout_mode = 2
text = "CONTINUE"
```

- [ ] **Step 3: Commit**

```bash
git add src/ui/death_screen.gd scenes/ui/death_screen.tscn
git commit -m "feat: add DeathScreen with Slay the Spire-style overlay and effects"
```

---

### Task 7: Add HealthUI and DeathScreen to game scene

**Files:**
- Modify: `scenes/game.tscn`

- [ ] **Step 1: Add ext_resource entries and scene instances to game.tscn**

In `scenes/game.tscn`, add two new ext_resource entries. After the last existing ext_resource line (line 9, the PauseMenu PackedScene), add:

```
[ext_resource type="PackedScene" path="res://scenes/ui/health_ui.tscn" id="10"]
[ext_resource type="PackedScene" path="res://scenes/ui/death_screen.tscn" id="11"]
```

Add two new node entries at the end of the scene, after the PauseMenu node (line 49):

```
[node name="HealthUI" parent="." instance=ExtResource("10")]

[node name="DeathScreen" parent="." instance=ExtResource("11")]
```

- [ ] **Step 2: Commit**

```bash
git add scenes/game.tscn
git commit -m "feat: add HealthUI and DeathScreen to game scene"
```

---

### Task 8: Integration test

- [ ] **Step 1: Run the project in Godot editor**

Launch the project and verify:

1. **HealthUI appears** in the top-left corner showing "100 / 100" with a red bar
2. **Walking into lava** causes the health bar to decrease and the player ColorRect blinks during i-frames
3. **Health reaching 0** triggers the death sequence:
   - Game pauses
   - Red flash appears and fades
   - Dark overlay fades in
   - "YOU DIED" text fades in
   - Continue button appears and is focusable
4. **Clicking Continue** transitions to the main menu
5. **Starting a new game** resets health to 100

- [ ] **Step 2: Fix any issues found during testing**

Address any scene wiring or visual issues. Common fixes:
- If HealthUI can't find the player: verify the "player" group is set up in PlayerController._ready()
- If LavaDamageChecker can't find shadow_grid: it uses lazy-init in _physics_process, should work after first frame
- If damage numbers seem wrong: check `get_damage` returns correct values for lava (should be 10)
- If the death sequence doesn't play: verify `HealthComponent.died` signal is connected
- If BarFill doesn't resize correctly: verify `clip_contents` is set on BarBackground and BarFill is a child of BarBackground

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "fix: integration adjustments for health and death system"
```