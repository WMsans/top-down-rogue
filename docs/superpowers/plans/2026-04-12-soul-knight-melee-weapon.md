# Soul Knight-Style Melee Weapon with Trail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a persistent visible weapon on the player that creates colored trail copies during attack swings.

**Architecture:** WeaponVisual component displays weapon sprite following player facing direction. MeleeSwingEffect spawns trail sprites during attack animation. MeleeWeapon passes its texture reference to the effect.

**Tech Stack:** Godot 4.x, GDScript, Sprite2D, Node2D

---

## File Structure

| File | Action | Purpose |
|------|--------|---------|
| `textures/weapon.png` | CREATE | Weapon sprite (user provides) |
| `src/player/weapon_visual.gd` | CREATE | WeaponVisual component script |
| `scenes/weapon_visual.tscn` | CREATE | WeaponVisual scene |
| `src/effects/melee_swing_effect.gd` | MODIFY | Add trail spawning logic |
| `scenes/melee_swing_effect.tscn` | MODIFY | Remove Line2D, add Trails container |
| `src/weapons/melee_weapon.gd` | MODIFY | Add texture constant, pass to effect |
| `scenes/player.tscn` | MODIFY | Add WeaponVisual node |

---

### Task 1: Create Weapon Sprite Asset

**Files:**
- Create: `textures/weapon.png`

- [ ] **Step 1: Create placeholder weapon sprite**

Create a simple sword-shaped sprite (16x48 pixels recommended) at `textures/weapon.png`. The sprite should:
- Have the handle at the bottom (pivot point)
- Blade extending upward
- Simple monochrome design for testing

User will provide the final artwork. For now, create a simple colored rectangle or use an existing placeholder.

- [ ] **Step 2: Verify file exists**

Run: `ls textures/weapon.png`
Expected: File exists

---

### Task 2: Create WeaponVisual Scene

**Files:**
- Create: `scenes/weapon_visual.tscn`
- Create: `src/player/weapon_visual.gd`

- [ ] **Step 1: Create weapon_visual.gd script**

Create file `src/player/weapon_visual.gd`:

```gdscript
class_name WeaponVisual
extends Node2D

const WEAPON_TEXTURE := preload("res://textures/weapon.png")
const PIVOT_DISTANCE: float = 15.0

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_sprite.texture = WEAPON_TEXTURE
	var tex_size: Vector2 = WEAPON_TEXTURE.get_size()
	_sprite.offset = Vector2(tex_size.x / 2.0, -tex_size.y / 4.0)


func _process(_delta: float) -> void:
	var player := _get_player()
	if player == null:
		return
	
	var facing := player.get_facing_direction()
	var angle := facing.angle()
	
	position = Vector2(cos(angle), sin(angle)) * PIVOT_DISTANCE
	rotation = angle + PI / 2.0


func _get_player() -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	if parent.has_method("get_facing_direction"):
		return parent
	return null
```

- [ ] **Step 2: Create weapon_visual.tscn scene**

Create file `scenes/weapon_visual.tscn`:

```gdscene
[gd_scene load_steps=2 format=3 uid="uid://weaponvisual"]

[ext_resource type="Script" path="res://src/player/weapon_visual.gd" id="1_script"]

[node name="WeaponVisual" type="Node2D"]
script = ExtResource("1_script")

[node name="Sprite2D" type="Sprite2D" parent="."]
```

- [ ] **Step 3: Verify scene loads**

Run Godot editor and verify the scene opens without errors.

---

### Task 3: Add WeaponVisual to Player Scene

**Files:**
- Modify: `scenes/player.tscn`

- [ ] **Step 1: Add WeaponVisual node to player.tscn**

Edit `scenes/player.tscn` to add the WeaponVisual node after WeaponManager:

```gdscene
[gd_scene format=3 uid="uid://dyro2k6hacg2y"]

[ext_resource type="Script" uid="uid://hixog1elal7b" path="res://src/player/player_controller.gd" id="1"]
[ext_resource type="Script" path="res://src/weapons/weapon_manager.gd" id="weapon_manager"]
[ext_resource type="PackedScene" path="res://scenes/weapon_visual.tscn" id="weapon_visual"]

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

[node name="WeaponVisual" parent="." instance=ExtResource("weapon_visual")]
```

- [ ] **Step 2: Test weapon visual in editor**

Run the game and verify the weapon sprite appears near the player and rotates based on movement direction.

---

### Task 4: Modify MeleeSwingEffect Scene

**Files:**
- Modify: `scenes/melee_swing_effect.tscn`

- [ ] **Step 1: Remove Line2D and add Trails container**

Edit `scenes/melee_swing_effect.tscn`:

```gdscene
[gd_scene load_steps=2 format=3 uid="uid://d2qwmeleeswing"]

[ext_resource type="Script" path="res://src/effects/melee_swing_effect.gd" id="1_script"]

[node name="MeleeSwingEffect" type="Node2D"]
script = ExtResource("1_script")

[node name="Trails" type="Node2D" parent="."]
```

- [ ] **Step 2: Verify scene structure**

Run Godot editor and confirm the scene loads with Trails node instead of Line2D.

---

### Task 5: Implement Trail Logic in MeleeSwingEffect

**Files:**
- Modify: `src/effects/melee_swing_effect.gd`

- [ ] **Step 1: Rewrite melee_swing_effect.gd with trail logic**

Replace entire contents of `src/effects/melee_swing_effect.gd`:

```gdscript
class_name MeleeSwingEffect
extends Node2D

const SWING_DURATION: float = 0.25
const HALF_ARC: float = PI / 4.0
const BLADE_DISTANCE: float = 20.0
const TRAIL_COUNT: int = 4

const TRAIL_COLORS: Array[Color] = [
	Color(0.3, 0.9, 1.0, 0.7),
	Color(0.4, 0.6, 1.0, 0.5),
	Color(0.7, 0.4, 1.0, 0.35),
	Color(1.0, 1.0, 1.0, 0.2)
]

@onready var _trails_container: Node2D = $Trails

var _elapsed: float = 0.0
var _start_angle: float = 0.0
var _end_angle: float = 0.0
var _weapon_texture: Texture2D = null
var _trails: Array[Sprite2D] = []


func setup(direction: Vector2, texture: Texture2D) -> void:
	_weapon_texture = texture
	_start_angle = direction.angle() - HALF_ARC
	_end_angle = direction.angle() + HALF_ARC
	_spawn_trails()


func _spawn_trails() -> void:
	for i in range(TRAIL_COUNT):
		var sprite := Sprite2D.new()
		sprite.texture = _weapon_texture
		sprite.modulate = TRAIL_COLORS[i]
		var tex_size: Vector2 = _weapon_texture.get_size()
		sprite.offset = Vector2(tex_size.x / 2.0, -tex_size.y / 4.0)
		sprite.position = _get_position_at_angle(_start_angle)
		sprite.rotation = _start_angle + PI / 2.0
		_trails_container.add_child(sprite)
		_trails.append(sprite)


func _process(delta: float) -> void:
	_elapsed += delta
	var t := _elapsed / SWING_DURATION
	
	if t >= 1.0:
		queue_free()
		return
	
	var eased_t := ease(t, 2.0)
	var current_angle := lerpf(_start_angle, _end_angle, eased_t)
	
	var last_trail := _trails[TRAIL_COUNT - 1]
	last_trail.position = _get_position_at_angle(current_angle)
	last_trail.rotation = current_angle + PI / 2.0
	
	var fade_alpha := 1.0 - t
	for i in range(TRAIL_COUNT):
		var trail := _trails[i]
		var base_color := TRAIL_COLORS[i]
		trail.modulate = Color(base_color.r, base_color.g, base_color.b, base_color.a * fade_alpha)


func _get_position_at_angle(angle: float) -> Vector2:
	return Vector2(cos(angle), sin(angle)) * BLADE_DISTANCE
```

- [ ] **Step 2: Test swing effect**

Run the game, press attack key (X key), and verify:
- Trail sprites appear during attack
- Trail has multiple colored copies
- Effect fades and removes itself after ~0.25 seconds

---

### Task 6: Modify MeleeWeapon to Pass Texture

**Files:**
- Modify: `src/weapons/melee_weapon.gd`

- [ ] **Step 1: Add texture constant and modify _spawn_effect**

Edit `src/weapons/melee_weapon.gd`:

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


func use(user: Node) -> void:
	if _cooldown_timer > 0.0:
		return
	
	var world_manager := _get_world_manager(user)
	if world_manager == null:
		return
	
	var pos: Vector2 = user.global_position
	var direction := _get_facing_direction(user)
	
	var materials: Array[int] = [
		MaterialRegistry.MAT_GAS,
		MaterialRegistry.MAT_LAVA
	]
	world_manager.disperse_materials_in_arc(pos, direction, RANGE, ARC_ANGLE, PUSH_SPEED, materials)
	
	_spawn_effect(user, direction)
	_cooldown_timer = COOLDOWN


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


func _spawn_effect(user: Node, direction: Vector2) -> void:
	var effect_scene := preload("res://scenes/melee_swing_effect.tscn")
	var effect := effect_scene.instantiate()
	effect.global_position = user.global_position
	effect.setup(direction, WEAPON_TEXTURE)
	user.get_tree().current_scene.add_child(effect)
```

- [ ] **Step 2: Verify weapon passes texture to effect**

Run the game and attack. Verify the trail sprites use the weapon texture.

---

### Task 7: Integration Testing

**Files:**
- None (testing only)

- [ ] **Step 1: Test idle weapon visual**

Run the game. Verify:
- Weapon sprite is visible on player
- Weapon rotates to follow player's facing direction
- Weapon positioned 15 pixels from player center

- [ ] **Step 2: Test attack trail**

Press X key to attack. Verify:
- 4 trail sprites spawn
- Trails have distinct colors (cyan, blue, purple, white)
- Swords sweep through 90-degree arc
- Trail copies remain in world (don't follow player)
- Effect fades and cleans up after 0.25 seconds

- [ ] **Step 3: Test multiple directions**

Move in each direction and attack:
- Facing right: swing downward
- Facing left: swing upward
- Facing up: swing rightward
- Facing down: swing leftward

- [ ] **Step 4: Test cooldown**

Attack multiple times rapidly. Verify:
- Cooldown of 0.5 seconds between attacks
- Material dispersal still works correctly

- [ ] **Step 5: Commit changes**

```bash
git add textures/weapon.png src/player/weapon_visual.gd scenes/weapon_visual.tscn scenes/player.tscn scenes/melee_swing_effect.tscn src/effects/melee_swing_effect.gd src/weapons/melee_weapon.gd
git commit -m "feat: implement Soul Knight-style melee weapon with trail effect"
```