# Weapon Visual Attack Animation Design

## Problem

The current melee attack effect is incorrect:
- `WeaponVisual` stays static (always pointing at facing direction)
- `MeleeSwingEffect` animates separate trail sprites through an arc
- The weapon itself never moves during attack

**Desired behavior:** The weapon swings through the arc, leaving a ghost trail behind it.

## Solution Overview

Merge the swing animation into `WeaponVisual` and give weapons control over their visuals through a base class method.

## Architecture

```
Weapon (base class in weapon.gd)
├── visual: WeaponVisual property
├── use(user) -> calls trigger_visual() then attack logic
└── trigger_visual(direction: Vector2) -> virtual method

MeleeWeapon extends Weapon
└── trigger_visual(direction) -> tells visual to swing

WeaponVisual
├── swing(direction: Vector2, arc: float, duration: float)
├── _process() -> animates weapon rotation during swing
└── Spawns ghost trails during swing
```

## Design Details

### 1. Weapon Base Class Changes

```gdscript
# weapon.gd
class_name Weapon
extends RefCounted

var visual: WeaponVisual = null

func use(user: Node) -> void:
    pass

func tick(delta: float) -> void:
    pass

func is_ready() -> bool:
    return true

func trigger_visual(direction: Vector2) -> void:
    if visual:
        _do_visual(direction)

func _do_visual(direction: Vector2) -> void:
    pass  # Override in subclasses
```

### 2. MeleeWeapon Implementation

```gdscript
# melee_weapon.gd
func _do_visual(direction: Vector2) -> void:
    if visual:
        visual.swing(direction, ARC_ANGLE, SWING_DURATION)
```

### 3. WeaponVisual Refactor

`WeaponVisual` becomes a per-weapon visual instance that:
- Handles idle display (weapon points at facing direction when not attacking)
- Handles swing animation when `swing()` is called
- Spawns ghost trail sprites behind the weapon during swing

**Swing Animation:**
- Starts at `direction.angle() - HALF_ARC` (45° behind facing direction)
- Ends at `direction.angle() + HALF_ARC` (45° ahead of facing direction)
- Total arc: 90 degrees
- Duration: 0.25 seconds (use ease-out interpolation)

**Ghost Trail:**
- 4 ghost sprites behind the main weapon sprite
- Each ghost has decreasing alpha (70%, 50%, 35%, 20%)
- Ghosts fade out over the swing duration
- Cyan-to-purple gradient for visual appeal

### 4. File Changes

| File | Change |
|------|--------|
| `src/weapons/weapon.gd` | Add `visual` property, `trigger_visual()` method, `_do_visual()` virtual |
| `src/weapons/melee_weapon.gd` | Implement `_do_visual()` to call `visual.swing()` |
| `src/player/weapon_visual.gd` | Refactor to handle swing animation + trail spawning |
| `src/effects/melee_swing_effect.gd` | **Delete** |
| `scenes/melee_swing_effect.tscn` | **Delete** |

### 5. Integration Flow

1. Player presses attack key (Z/X/C)
2. `WeaponManager._input()` -> `MeleeWeapon.use()`
3. `MeleeWeapon.use()`:
   - Calls `trigger_visual(direction)` -> `visual.swing()`
   - Performs material dispersal logic
4. `WeaponVisual.swing()` starts swing animation
5. `WeaponVisual._process()` animates weapon rotation, spawns ghost trails
6. Animation completes, weapon returns to idle state

## Implementation Notes

- The weapon visual remains visible during idle
- During swing, the weapon visual is animated; ghost trails are spawned as children
- The visual needs a reference to the player to get facing direction for idle
- Ghost trails should be cleaned up after swing completes
- Use `ease(t, 2.0)` for ease-out interpolation (same as current implementation)