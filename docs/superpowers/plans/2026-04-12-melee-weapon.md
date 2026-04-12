# Melee Weapon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a melee weapon that disperses GAS and LAVA fluids within a frontal arc when the player attacks.

**Architecture:** MeleeWeapon extends Weapon base class, uses WorldManager's new `disperse_materials_in_arc()` method to push fluids away. Visual feedback via MeleeSwingEffect scene that auto-destroys after animation.

**Tech Stack:** GDScript, Godot 4.x, GPU compute shaders (existing)

---

## Files

| File | Status | Purpose |
|------|--------|---------|
| `src/weapons/melee_weapon.gd` | Create | MeleeWeapon class |
| `src/effects/melee_swing_effect.gd` | Create | Visual effect controller |
| `scenes/melee_swing_effect.tscn` | Create | Effect scene |
| `src/core/world_manager.gd` | Modify | Add `disperse_materials_in_arc()` |
| `src/player/player_controller.gd` | Modify | Add `get_facing_direction()`, equip melee weapon |

---

### Task 1: Add disperse_materials_in_arc to WorldManager

**Files:**
- Modify: `src/core/world_manager.gd`

- [ ] **Step 1: Add the disperse_materials_in_arc method to WorldManager**

Add this method after the `place_lava` method (around line 681):

```gdscript
func disperse_materials_in_arc(
    origin: Vector2,
    direction: Vector2,
    radius: float,
    arc_angle: float,
    push_speed: float,
    materials: Array[int]
) -> void:
    var origin_int := Vector2i(int(origin.x), int(origin.y))
    var r_int := int(ceil(radius))
    var half_arc := arc_angle / 2.0
    var dir_angle := direction.angle()
    var start_angle := dir_angle - half_arc
    var end_angle := dir_angle + half_arc
    
    var affected: Dictionary = {}
    
    for dx in range(-r_int, r_int + 1):
        for dy in range(-r_int, r_int + 1):
            var dist_sq := dx * dx + dy * dy
            if dist_sq > r_int * r_int:
                continue
            
            var pixel_angle := atan2(float(dy), float(dx))
            var delta_start := pixel_angle - start_angle
            while delta_start > PI:
                delta_start -= TAU
            while delta_start < -PI:
                delta_start += TAU
            var delta_end := pixel_angle - end_angle
            while delta_end > PI:
                delta_end -= TAU
            while delta_end < -PI:
                delta_end += TAU
            
            if delta_start < 0.0 or delta_end > 0.0:
                continue
            
            var wx := origin_int.x + dx
            var wy := origin_int.y + dy
            var chunk_coord := Vector2i(floori(float(wx) / CHUNK_SIZE), floori(float(wy) / CHUNK_SIZE))
            if not chunks.has(chunk_coord):
                continue
            var local := Vector2i(posmod(wx, CHUNK_SIZE), posmod(wy, CHUNK_SIZE))
            if not affected.has(chunk_coord):
                affected[chunk_coord] = []
            affected[chunk_coord].append([local, Vector2(float(dx), float(dy)).normalized()])
    
    if affected.is_empty():
        return
    
    for chunk_coord in affected:
        var chunk: Chunk = chunks[chunk_coord]
        var data := rd.texture_get_data(chunk.rd_texture, 0)
        var modified := false
        for entry in affected[chunk_coord]:
            var pixel_pos: Vector2i = entry[0]
            var push_dir: Vector2 = entry[1]
            var idx := (pixel_pos.y * CHUNK_SIZE + pixel_pos.x) * 4
            var material := data[idx]
            
            var is_target := false
            for mat_id in materials:
                if material == mat_id:
                    is_target = true
                    break
            if not is_target:
                continue
            
            var push_vx := int(round(push_dir.x * push_speed / 60.0))
            var push_vy := int(round(push_dir.y * push_speed / 60.0))
            var vx_encoded := clampi(push_vx + 8, 0, 15)
            var vy_encoded := clampi(push_vy + 8, 0, 15)
            var packed_velocity: int = (vx_encoded << 4) | vy_encoded
            
            data[idx + 3] = packed_velocity
            modified = true
        
        if modified:
            rd.texture_update(chunk.rd_texture, 0, data)
```

- [ ] **Step 2: Commit**

```bash
git add src/core/world_manager.gd
git commit -m "feat: add disperse_materials_in_arc method to WorldManager"
```

---

### Task 2: Create MeleeWeapon class

**Files:**
- Create: `src/weapons/melee_weapon.gd`

- [ ] **Step 1: Create the MeleeWeapon class**

Create file `src/weapons/melee_weapon.gd`:

```gdscript
class_name MeleeWeapon
extends Weapon

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
    effect.rotation = direction.angle()
    user.get_tree().current_scene.add_child(effect)
```

- [ ] **Step 2: Commit**

```bash
git add src/weapons/melee_weapon.gd
git commit -m "feat: create MeleeWeapon class"
```

---

### Task 3: Create MeleeSwingEffect scene and script

**Files:**
- Create: `src/effects/melee_swing_effect.gd`
- Create: `scenes/melee_swing_effect.tscn`

- [ ] **Step 1: Create the effects directory and script**

Create directory `src/effects/` then create file `src/effects/melee_swing_effect.gd`:

```gdscript
class_name MeleeSwingEffect
extends Node2D

const DURATION: float = 0.25
const ARC_POINTS: int = 12
const ARC_RADIUS: float = 40.0
const HALF_ARC: float = PI / 4.0

@onready var line: Line2D = $Line2D

var _elapsed: float = 0.0


func _ready() -> void:
    _elapsed = 0.0
    _build_arc()


func _build_arc() -> void:
    var points: PackedVector2Array = []
    for i in range(ARC_POINTS + 1):
        var angle := -HALF_ARC + (HALF_ARC * 2.0) * float(i) / float(ARC_POINTS)
        var point := Vector2(cos(angle), sin(angle)) * ARC_RADIUS
        points.append(point)
    line.points = points


func _process(delta: float) -> void:
    _elapsed += delta
    var t := _elapsed / DURATION
    
    if t >= 1.0:
        queue_free()
        return
    
    var scale_val := 0.8 + t * 0.4
    scale = Vector2(scale_val, scale_val)
    modulate.a = 1.0 - t
```

- [ ] **Step 2: Create the effect scene**

Create file `scenes/melee_swing_effect.tscn`:

```
[gd_scene load_steps=2 format=3 uid="uid://d2qwmeleeswing"]

[ext_resource type="Script" path="res://src/effects/melee_swing_effect.gd" id="1_script"]

[node name="MeleeSwingEffect" type="Node2D"]
script = ExtResource("1_script")

[node name="Line2D" type="Line2D" parent="."]
width = 3.0
default_color = Color(1, 1, 1, 0.6)
```

- [ ] **Step 3: Commit**

```bash
git add src/effects/melee_swing_effect.gd scenes/melee_swing_effect.tscn
git commit -m "feat: create MeleeSwingEffect scene and script"
```

---

### Task 4: Add get_facing_direction to PlayerController

**Files:**
- Modify: `src/player/player_controller.gd`

- [ ] **Step 1: Add facing direction tracking**

Add after line 15 (after `var shadow_grid: Node`):

```gdscript
var _last_facing: Vector2 = Vector2.DOWN
```

- [ ] **Step 2: Add get_facing_direction method**

Add at the end of the file (after `get_world_manager`):

```gdscript

func get_facing_direction() -> Vector2:
    if velocity.length_squared() > 0.01:
        _last_facing = velocity.normalized()
    return _last_facing
```

- [ ] **Step 3: Commit**

```bash
git add src/player/player_controller.gd
git commit -m "feat: add get_facing_direction to PlayerController"
```

---

### Task 5: Equip melee weapon in PlayerController

**Files:**
- Modify: `src/player/player_controller.gd`

- [ ] **Step 1: Add preload for MeleeWeapon**

Add after line 8 (after TestWeaponScript preload):

```gdscript
const MeleeWeaponScript := preload("res://src/weapons/melee_weapon.gd")
```

- [ ] **Step 2: Equip melee weapon in weapon slot 1**

In `_ready()` after `weapons[0] = TestWeaponScript.new()`, add:

```gdscript
weapons[1] = MeleeWeaponScript.new()
```

- [ ] **Step 3: Commit**

```bash
git add src/player/player_controller.gd
git commit -m "feat: equip melee weapon in player weapon slot 1"
```

---

### Task 6: Manual testing

- [ ] **Step 1: Run the game**

Run the game from Godot editor.

- [ ] **Step 2: Test gas dispersal**

1. Press Z to place gas using TestWeapon
2. Press X to attack with melee weapon
3. Verify gas pushes away in arc pattern

- [ ] **Step 3: Test lava dispersal**

1. If you have a way to place lava, test same behavior
2. Verify lava pushes away correctly

- [ ] **Step 4: Test at chunk boundaries**

1. Move near chunk edge (chunk size is 256 pixels)
2. Place gas near boundary
3. Attack and verify gas disperses correctly across chunks

- [ ] **Step 5: Test cooldown**

1. Press X rapidly
2. Verify attacks are spaced by ~0.5 seconds

- [ ] **Step 6: Test visual effect**

1. Attack and verify arc line appears briefly
2. Verify effect fades and disappears

---

## Summary

This plan implements a melee weapon system with:
1. WorldManager extension for arc-based fluid dispersal
2. MeleeWeapon class with cooldown and effect spawning
3. MeleeSwingEffect visual feedback
4. PlayerController integration for facing direction

The implementation follows the existing patterns in the codebase and integrates with the GPU-based simulation system.