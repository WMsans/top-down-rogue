# Melee Swing Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current semi-circle Line2D melee effect with a blade sprite that animates swinging through the attack arc.

**Architecture:** MeleeSwingEffect uses a Polygon2D node to draw a simple blade shape. The blade rotates from start_angle to end_angle over the swing duration, positioned along a circular path around the player.

**Tech Stack:** Godot 4.x, GDScript

---

## File Structure

| File | Responsibility |
|------|----------------|
| `scenes/melee_swing_effect.tscn` | Scene with Polygon2D for blade |
| `src/effects/melee_swing_effect.gd` | Swing animation, blade positioning/rotation |

---

### Task 1: Update MeleeSwingEffect Scene

**Files:**
- Modify: `scenes/melee_swing_effect.tscn`

- [ ] **Step 1: Rewrite scene with Polygon2D for blade**

Replace the entire `scenes/melee_swing_effect.tscn` content:

```gdscript
[gd_scene load_steps=2 format=3 uid="uid://d2qwmeleeswing"]

[ext_resource type="Script" path="res://src/effects/melee_swing_effect.gd" id="1_script"]

[node name="MeleeSwingEffect" type="Node2D"]
script = ExtResource("1_script")

[node name="Blade" type="Polygon2D" parent="."]
color = Color(0.9, 0.9, 0.95, 0.85)
```

The `Polygon2D.polygon` property will be set in the script to create a tapered blade shape.

- [ ] **Step 2: Commit scene changes**

```bash
git add scenes/melee_swing_effect.tscn
git commit -m "refactor: replace Line2D with Polygon2D in MeleeSwingEffect"
```

---

### Task 2: Rewrite MeleeSwingEffect Script for Swing Animation

**Files:**
- Modify: `src/effects/melee_swing_effect.gd`

- [ ] **Step 1: Replace entire script with swing animation logic**

Replace the entire `src/effects/melee_swing_effect.gd` content:

```gdscript
class_name MeleeSwingEffect
extends Node2D

const SWING_DURATION: float = 0.2
const HALF_ARC: float = PI / 4.0
const BLADE_DISTANCE: float = 20.0
const BLADE_LENGTH: float = 30.0
const BLADE_WIDTH: float = 4.0

@onready var blade: Polygon2D = $Blade

var _elapsed: float = 0.0
var _start_angle: float = 0.0
var _end_angle: float = 0.0
var _base_rotation: float = 0.0

func _ready() -> void:
    var half_length := BLADE_LENGTH / 2.0
    var half_width := BLADE_WIDTH / 2.0
    blade.polygon = PackedVector2Array([
        Vector2(-half_width, -half_length),
        Vector2(half_width, -half_length),
        Vector2(half_width * 0.5, half_length),
        Vector2(-half_width * 0.5, half_length)
    ])
    
    _base_rotation = rotation
    _start_angle = _base_rotation - HALF_ARC
    _end_angle = _base_rotation + HALF_ARC
    rotation = 0.0
    _update_blade(0.0)

func _process(delta: float) -> void:
    _elapsed += delta
    var t := _elapsed / SWING_DURATION
    
    if t >= 1.0:
        queue_free()
        return
    
    var eased_t := ease(t, 2.0)
    _update_blade(eased_t)
    blade.color.a = 0.85 * (1.0 - t)

func _update_blade(progress: float) -> void:
    var current_angle := lerpf(_start_angle, _end_angle, progress)
    blade.position = Vector2(cos(current_angle), sin(current_angle)) * BLADE_DISTANCE
    blade.rotation = current_angle + PI / 2.0
```

Key implementation details:
- `SWING_DURATION = 0.2` seconds for the swing
- `HALF_ARC = PI/4` gives 90° total arc (45° each side)
- `BLADE_DISTANCE = 20` pixels from player center
- `BLADE_LENGTH =30`, `BLADE_WIDTH = 4` for the blade shape
- Blade polygon is tapered (wider at base, narrower at tip)
- `ease(t, 2.0)` provides ease-out for natural swing deceleration
- Blade rotation is `current_angle + PI/2` to stay tangent to arc
- Alpha fades from 0.85 to 0 during swing

- [ ] **Step 2: Commit script changes**

```bash
git add src/effects/melee_swing_effect.gd
git commit -m "feat: implement swing animation for MeleeSwingEffect"
```

---

### Task 3: Test and Verify

**Files:**
- Test: Manual testing in game

- [ ] **Step 1: Run the game**

```bash
godot4 --path .
```

- [ ] **Step 2: Test swing in all directions**

1. Walk around using WASD/arrows
2. Press attack key to trigger melee weapon
3. Verify blade appears and swings through the arc
4. Test facing each direction (up, down, left, right)
5. Verify swing always matches facing direction

- [ ] **Step 3: Verify material dispersal still works**

1. Use TestWeapon (key Z) to spawn GAS materials
2. Switch to melee weapon (key X)
3. Face GAS cloud and attack
4. Confirm GAS is pushed away in arc pattern
5. Confirm visual swing animation plays correctly

---

## Self-Review Checklist

- [x] Spec coverage: All requirements implemented
- [x] No placeholders: All code is complete and specific
- [x] Type consistency: Polygon2D type used consistently
- [x] Constants: All values defined as named constants for easy tuning
- [x] Blade shape: Tapered polygon creates natural blade look
- [x] Animation: Ease-out + fade provides smooth finish