# Weapon Manager Decoupling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a WeaponManager node that handles all weapon logic, fully decoupling it from PlayerController.

**Architecture:** WeaponManager is a child node of Player that handles weapon creation, input, and ticking. PlayerController retains only movement logic and provides world_manager/facing_direction through public methods.

**Tech Stack:** GDScript, Godot 4.x

---

### Task 1: Create WeaponManager Node

**Files:**
- Create: `src/weapons/weapon_manager.gd`

- [ ] **Step 1: Create weapon_manager.gd**

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

- [ ] **Step 2: Commit WeaponManager**

```bash
git add src/weapons/weapon_manager.gd
git commit -m "feat: add WeaponManager node for weapon handling"
```

---

### Task 2: Update player.tscn to Include WeaponManager

**Files:**
- Modify: `scenes/player.tscn`

- [ ] **Step 1: Add WeaponManager node to player.tscn**

Add after the PointLight2D node block (before the final closing bracket):

```gdscene
[sub_resource type="RectangleShape2D" id="1"]
size = Vector2(8, 12)

[sub_resource type="Gradient" id="Gradient_3vyb7"]
colors = PackedColorArray(1, 1, 1, 1, 0, 0, 0, 1)

[sub_resource type="GradientTexture2D" id="GradientTexture2D_g2els"]
gradient = SubResource("Gradient_3vyb7")
fill = 1
fill_from = Vector2(0.5, 0.5)
fill_to = Vector2(1, 0.5)

[ext_resource type="Script" path="res://src/weapons/weapon_manager.gd" id="weapon_manager"]

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

- [ ] **Step 2: Commit scene update**

```bash
git add scenes/player.tscn
git commit -m "feat: add WeaponManager to player scene"
```

---

### Task 3: Remove Weapon Code from PlayerController

**Files:**
- Modify: `src/player/player_controller.gd`

- [ ] **Step 1: Remove weapon preloads**

Remove lines 8-9:
```gdscript
const TestWeaponScript := preload("res://src/weapons/test_weapon.gd")
const MeleeWeaponScript := preload("res://src/weapons/melee_weapon.gd")
```

- [ ] **Step 2: Remove weapon array declaration**

Remove line 15:
```gdscript
var weapons: Array[Weapon] = []
```

- [ ] **Step 3: Remove weapon initialization from _ready()**

Remove lines 33-35:
```gdscript
weapons.resize(3)
weapons[0] = TestWeaponScript.new()
weapons[1] = MeleeWeaponScript.new()
```

- [ ] **Step 4: Remove weapon tick call from _physics_process()**

Remove line 56:
```gdscript
_tick_weapons(delta)
```

- [ ] **Step 5: Remove _input() method**

Remove the entire `_input()` method (lines 85-93):
```gdscript
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var slot := -1
		match event.keycode:
			KEY_Z: slot = 0
			KEY_X: slot = 1
			KEY_C: slot = 2
		if slot >= 0 and slot < weapons.size() and weapons[slot] != null:
			weapons[slot].use(self)
```

- [ ] **Step 6: Remove _tick_weapons() method**

Remove the entire `_tick_weapons()` method (lines 96-99):
```gdscript
func _tick_weapons(delta: float) -> void:
	for weapon in weapons:
		if weapon != null and weapon.has_method("tick"):
			weapon.tick(delta)
```

- [ ] **Step 7: Verify final player_controller.gd**

The file should now only contain:
- Body constants
- ShadowGridScript preload
- Movement exports (acceleration, friction, max_speed)
- shadow_grid and _last_facing variables
- _world_manager reference
- _ready() (without weapon initialization)
- _physics_process() (without weapon tick)
- _get_input_direction()
- _apply_movement()
- get_world_manager()
- get_facing_direction()

- [ ] **Step 8: Commit PlayerController cleanup**

```bash
git add src/player/player_controller.gd
git commit -m "refactor: remove weapon handling from PlayerController"
```

---

### Task 4: Verify Implementation

- [ ] **Step 1: Run the game**

Launch Godot and run the project. Verify:
- Player movement works (WASD)
- Weapon slot 1 (Z key) places gas
- Weapon slot 2 (X key) swings melee
- No errors in console

- [ ] **Step 2: Check scene structure**

Inspect the Player node in the scene tree. Verify WeaponManager appears as a child node.

---

### Task 5: Final Commit

- [ ] **Step 1: Create summary commit if needed**

If any uncommitted changes remain:
```bash
git status
git add -A
git commit -m "refactor: complete weapon manager decoupling"
```