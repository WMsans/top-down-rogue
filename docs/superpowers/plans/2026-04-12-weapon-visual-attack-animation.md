# Weapon Visual Attack Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the weapon swing during attacks, leaving ghost trail sprites behind, by giving weapons control over their visuals.

**Architecture:** Each weapon owns its visual instance. Weapon base class has `visual_scene` reference and `trigger_visual()` method. MeleeWeapon implements swing animation. WeaponVisual handles idle display + swing animation + ghost trail spawning.

**Tech Stack:** GDScript, Godot 4.x

---

## File Structure

| File | Responsibility |
|------|----------------|
| `src/weapons/weapon.gd` | Base class: visual Scene reference, trigger_visual() method |
| `src/weapons/melee_weapon.gd` | Implements trigger_visual() to call visual.swing() |
| `src/weapons/test_weapon.gd` | No visual (or placeholder) |
| `src/weapons/weapon_manager.gd` | Creates weapon visuals when weapons are added |
| `src/player/weapon_visual.gd` | Idle display + swing animation + trail spawning |
| `src/effects/melee_swing_effect.gd` | DELETE (merged into WeaponVisual) |
| `scenes/melee_swing_effect.tscn` | DELETE |
| `scenes/weapon_visual.tscn` | Add Trails container node for ghost sprites |

---

### Task 1: Update Weapon Base Class

**Files:**
- Modify: `src/weapons/weapon.gd`

**Changes:** Add `visual_scene` reference and `visual` instance property. Add `trigger_visual()` method that calls virtual `_do_visual()`.

- [ ] **Step 1: Add visual properties and methods to Weapon base class**

```gdscript
class_name Weapon
extends RefCounted

var name: String = "Weapon"
var visual_scene: PackedScene = null
var visual: Node2D = null


func use(_user: Node) -> void:
	push_error("Weapon.use() must be overridden")


func tick(_delta: float) -> void:
	pass


func is_ready() -> bool:
	return true


func trigger_visual(direction: Vector2) -> void:
	if visual and visual.has_method("swing"):
		_do_visual(direction)


func _do_visual(_direction: Vector2) -> void:
	pass
```

- [ ] **Step 2: Commit**

```bash
git add src/weapons/weapon.gd
git commit -m "feat(weapon): add visual_scene and trigger_visual() to base class"
```

---

### Task 2: Refactor WeaponVisual for Swing Animation

**Files:**
- Modify: `src/player/weapon_visual.gd`
- Modify: `scenes/weapon_visual.tscn`

**Changes:** 
- Add swing state machine (idle/swinging)
- Add `swing(direction, arc, duration)` method
- Animate weapon rotation through arc in `_process()`
- Spawn ghost trails behind weapon during swing

- [ ] **Step 1: Update weapon_visual.gd with swing animation**

```gdscript
class_name WeaponVisual
extends Node2D

const WEAPON_TEXTURE := preload("res://textures/weapon.png")
const PIVOT_DISTANCE: float = 15.0

const SWING_DURATION: float = 0.25
const HALF_ARC: float = PI / 4.0
const TRAIL_COUNT: int = 4
const TRAIL_COLORS: Array[Color] = [
	Color(0.3, 0.9, 1.0, 0.7),
	Color(0.4, 0.6, 1.0, 0.5),
	Color(0.7, 0.4, 1.0, 0.35),
	Color(1.0, 1.0, 1.0, 0.2)
]

@onready var _sprite: Sprite2D = $Sprite2D

var _is_swinging: bool = false
var _elapsed: float = 0.0
var _start_angle: float = 0.0
var _end_angle: float = 0.0
var _facing_angle: float = 0.0
var _trails: Array[Sprite2D] = []


func _ready() -> void:
	_sprite.texture = WEAPON_TEXTURE
	var tex_size: Vector2 = WEAPON_TEXTURE.get_size()
	_sprite.offset = Vector2(tex_size.x / 2.0, -tex_size.y / 4.0)


func _process(delta: float) -> void:
	var player := _get_player()
	if player == null:
		return
	
	_facing_angle = player.get_facing_direction().angle()
	
	if _is_swinging:
		_process_swing(delta)
	else:
		_process_idle()


func _process_idle() -> void:
	position = Vector2(cos(_facing_angle), sin(_facing_angle)) * PIVOT_DISTANCE
	rotation = _facing_angle + PI / 2.0


func _process_swing(delta: float) -> void:
	_elapsed += delta
	
	var t := _elapsed / SWING_DURATION
	if t >= 1.0:
		_is_swinging = false
		_clear_trails()
		_process_idle()
		return
	
	var eased_t := ease(t, 2.0)
	var current_angle := lerpf(_start_angle, _end_angle, eased_t)
	
	_sprite.position = _get_position_at_angle(current_angle, PIVOT_DISTANCE)
	_sprite.rotation = current_angle + PI / 2.0
	
	_update_trails(current_angle, t)


func swing(direction: Vector2) -> void:
	_facing_angle = direction.angle()
	_start_angle = _facing_angle - HALF_ARC
	_end_angle = _facing_angle + HALF_ARC
	_elapsed = 0.0
	_is_swinging = true
	_spawn_trails()


func _spawn_trails() -> void:
	_clear_trails()
	for i in range(TRAIL_COUNT):
		var trail := Sprite2D.new()
		trail.texture = WEAPON_TEXTURE
		trail.modulate = TRAIL_COLORS[i]
		var tex_size: Vector2 = WEAPON_TEXTURE.get_size()
		trail.offset = Vector2(tex_size.x / 2.0, -tex_size.y / 4.0)
		trail.position = _get_position_at_angle(_start_angle, PIVOT_DISTANCE)
		trail.rotation = _start_angle + PI / 2.0
		add_child(trail)
		_trails.append(trail)


func _clear_trails() -> void:
	for trail in _trails:
		trail.queue_free()
	_trails.clear()


func _update_trails(current_angle: float, t: float) -> void:
	var fade_alpha := 1.0 - t
	var trail_delay := 0.08
	
	for i in range(TRAIL_COUNT):
		var trail := _trails[i]
		var trail_t := max(0.0, t - trail_delay * float(i + 1))
		if trail_t > 0:
			var trail_eased := ease(trail_t, 2.0)
			var trail_angle := lerpf(_start_angle, _end_angle, trail_eased)
			trail.position = _get_position_at_angle(trail_angle, PIVOT_DISTANCE)
			trail.rotation = trail_angle + PI / 2.0
		
		var base_color := TRAIL_COLORS[i]
		trail.modulate = Color(base_color.r, base_color.g, base_color.b, base_color.a * fade_alpha)


func _get_position_at_angle(angle: float, distance: float) -> Vector2:
	return Vector2(cos(angle), sin(angle)) * distance


func _get_player() -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	if parent.has_method("get_facing_direction"):
		return parent
	return null
```

- [ ] **Step 2: Commit**

```bash
git add src/player/weapon_visual.gd
git commit -m "feat(weapon-visual): add swing animation with ghost trails"
```

---

### Task 3: Update MeleeWeapon to Trigger Visual

**Files:**
- Modify: `src/weapons/melee_weapon.gd`

**Changes:** 
- Remove effect spawning code
- Implement `_do_visual()` to call `visual.swing()`

- [ ] **Step 1: Update melee_weapon.gd**

```gdscript
class_name MeleeWeapon
extends Weapon

const WEAPON_TEXTURE := preload("res://textures/weapon.png")
const RANGE: float = 40.0
const ARC_ANGLE: float = PI / 2.0
const COOLDOWN: float = 0.5
const PUSH_SPEED: float = 60.0

var _cooldown_timer: float = 0.0


func _init() -> void:
	name = "Melee Weapon"
	visual_scene = preload("res://scenes/weapon_visual.tscn")


func use(user: Node) -> void:
	if _cooldown_timer > 0.0:
		return
	
	var world_manager := _get_world_manager(user)
	if world_manager == null:
		return
	
	var pos: Vector2 = user.global_position
	var direction := _get_facing_direction(user)
	
	trigger_visual(direction)
	
	var materials: Array[int] = [
		MaterialRegistry.MAT_GAS,
		MaterialRegistry.MAT_LAVA
	]
	world_manager.disperse_materials_in_arc(pos, direction, RANGE, ARC_ANGLE, PUSH_SPEED, materials)
	
	_cooldown_timer = COOLDOWN


func _do_visual(direction: Vector2) -> void:
	if visual:
		visual.swing(direction)


func tick(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta


func is_ready() -> bool:
	return _cooldown_timer <= 0.0


func _get_world_manager(user: Node) -> Node:
	if user.has_method("get_world_manager"):
		return user.get_world_manager()
	var parent := user.get_parent()
	if parent:
		return parent.get_node_or_null("WorldManager")
	return null


func _get_facing_direction(user: Node) -> Vector2:
	if user.has_method("get_facing_direction"):
		return user.get_facing_direction()
	if "velocity" in user:
		var vel = user.get("velocity")
		if vel is Vector2 and vel.length_squared() > 0.01:
			return vel.normalized()
	return Vector2.DOWN
```

- [ ] **Step 2: Commit**

```bash
git add src/weapons/melee_weapon.gd
git commit -m "feat(melee-weapon): trigger visual swing instead of spawning effect"
```

---

### Task 4: Update WeaponManager to Create Visuals

**Files:**
- Modify: `src/weapons/weapon_manager.gd`

**Changes:**
- After creating weapons, instantiate their visuals and parent to player
- Set weapon.visual reference

- [ ] **Step 1: Update weapon_manager.gd**

```gdscript
class_name WeaponManager
extends Node

const TestWeaponScript := preload("res://src/weapons/test_weapon.gd")
const MeleeWeaponScript := preload("res://src/weapons/melee_weapon.gd")

var weapons: Array[Weapon] = []
var _player: Node = null


func _ready() -> void:
	_player = get_parent()
	weapons.resize(3)
	weapons[0] = TestWeaponScript.new()
	weapons[1] = MeleeWeaponScript.new()
	
	for weapon in weapons:
		if weapon != null and weapon.visual_scene != null:
			var visual_instance := weapon.visual_scene.instantiate()
			_player.add_child(visual_instance)
			weapon.visual = visual_instance


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var slot := -1
		match event.keycode:
			KEY_Z: slot = 0
			KEY_X: slot = 1
			KEY_C: slot = 2
		if slot >= 0 and slot < weapons.size() and weapons[slot] != null:
			weapons[slot].use(_player)


func _physics_process(delta: float) -> void:
	for weapon in weapons:
		if weapon != null and weapon.has_method("tick"):
			weapon.tick(delta)
```

- [ ] **Step 2: Commit**

```bash
git add src/weapons/weapon_manager.gd
git commit -m "feat(weapon-manager): create and parent weapon visuals for each weapon"
```

---

### Task 5: Remove Player Scene's Static WeaponVisual

**Files:**
- Modify: `scenes/player.tscn`

**Changes:**
- Remove the static WeaponVisual node (visuals are now created dynamically by WeaponManager)

- [ ] **Step 1: Update player.tscn**

```gdscene
[gd_scene format=3 uid="uid://dyro2k6hacg2y"]

[ext_resource type="Script" uid="uid://hixog1elal7b" path="res://src/player/player_controller.gd" id="1"]
[ext_resource type="Script" path="res://src/weapons/weapon_manager.gd" id="weapon_manager"]

[sub_resource type="RectangleShape2D" id="1"]
size = Vector2(8, 12)

[sub_resource type="Gradient" id="Gradient_3vyb7"]
colors = PackedColorArray(1, 1, 1, 1, 0, 0, 0, 1)

[sub_resource type="GradientTexture2D" id="GradientTexture2D_g2els"]
gradient = SubResource("Gradient_3vyb7")
fill = 1
fill_from = Vector2(0.5, 0.5)
fill_to = Vector2(1, 0.5)

[node name="Player" type="CharacterBody2D" unique_id=1776190034]
script = ExtResource("1")

[node name="ColorRect" type="ColorRect" parent="." unique_id=1475446360]
offset_left = -4.0
offset_top = -6.0
offset_right = 4.0
offset_bottom = 6.0
color = Color(0.2, 0.8, 0.3, 1)

[node name="Camera2D" type="Camera2D" parent="." unique_id=524568655]
zoom = Vector2(8, 8)
position_smoothing_enabled = true
position_smoothing_speed = 12.0

[node name="CollisionShape2D" type="CollisionShape2D" parent="." unique_id=2000232908]
shape = SubResource("1")

[node name="PointLight2D" type="PointLight2D" parent="." unique_id=693124189]
energy = 2.0
texture = SubResource("GradientTexture2D_g2els")
shadow_enabled = true
shadow_filter = 3
shadow_filter_smooth = 2.0
shadow_color = Color(0, 0, 0, 0.5)

[node name="WeaponManager" type="Node" parent="."]
script = ExtResource("weapon_manager")
```

- [ ] **Step 2: Commit**

```bash
git add scenes/player.tscn
git commit -m "refactor(player): remove static WeaponVisual (now created by WeaponManager)"
```

---

### Task 6: Delete Old MeleeSwingEffect Files

**Files:**
- Delete: `src/effects/melee_swing_effect.gd`
- Delete: `scenes/melee_swing_effect.tscn`

- [ ] **Step 1: Delete melee_swing_effect.gd**

```bash
rm src/effects/melee_swing_effect.gd
```

- [ ] **Step 2: Delete melee_swing_effect.tscn**

```bash
rm scenes/melee_swing_effect.tscn
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "refactor: remove MeleeSwingEffect (functionality merged into WeaponVisual)"
```

---

### Task 7: Verify Implementation

**Files:**
- None (verification)

- [ ] **Step 1: Run the game and test melee attack**

1. Run the game
2. Press 'X' key to use melee weapon (slot 1)
3. Verify:
   - Weapon is visible near player during idle
   - When attacking, weapon swings through 90° arc
   - Ghost trails follow behind the weapon
   - Trails fade out during swing
   - Weapon returns to idle position after swing

- [ ] **Step 2: Check for console errors**

Look for any GDScript errors or warnings in the console output.

- [ ] **Step 3: Final commit**

```bash
git status
git log --oneline -5
```