# Wall-Block Detection Auto-Facing

**Date**: 2026-05-11
**Status**: Draft

## Problem

The auto-facing system in `player_controller.gd` always snaps the player's facing direction toward the nearest enemy within 250px. This prevents the player from carving terrain in a direction that differs from the enemy direction — the attack always fires toward the enemy, not the wall.

## Solution

Add wall-block detection to auto-facing logic: when the player is holding a movement direction and a wall blocks movement in that direction, override auto-face to use the input direction (carving intent). Otherwise, auto-face to enemies as before.

```
Input direction held?
  ├─ Yes → Blocked by terrain in that direction? (short raycast)
  │          ├─ Yes → Face input direction (carve mode)
  │          └─ No  → Auto-face to nearest enemy
  └─ No  → Auto-face to nearest enemy
```

## Implementation

### Files to modify

- `src/player/player_controller.gd`

### Changes

#### 1. Add `_is_blocked_by_terrain()` function

Short raycast from the player's leading edge in the movement direction. Query only the terrain collision layer (`collision_mask = 1`, which is `collision_layer = 1` used by `chunk_manager.gd:115`).

- Ray length: 4px (small enough to only trigger when pressed against a wall, reliable enough to catch nearby walls)
- Exclude the player's own body from the query via `exclude` parameter
- Check for `StaticBody2D` in the result

```gdscript
func _is_blocked_by_terrain(direction: Vector2) -> bool:
    var space_state := get_world_2d().direct_space_state
    var query := PhysicsRayQueryParameters2D.create(
        global_position,
        global_position + direction * 4.0,
        1,  # terrain collision_layer
        [self]
    )
    var result := space_state.intersect_ray(query)
    return not result.is_empty()
```

#### 2. Modify auto-facing logic in `_physics_process()`

Replace lines 73-77:

```gdscript
var enemy_dir := _find_closest_enemy_direction()
if enemy_dir != Vector2.ZERO:
    _last_facing = enemy_dir
elif input_dir != Vector2.ZERO:
    _last_facing = input_dir
```

With:

```gdscript
var enemy_dir := _find_closest_enemy_direction()
var is_pushing_wall := input_dir != Vector2.ZERO and _is_blocked_by_terrain(input_dir)
if is_pushing_wall:
    _last_facing = input_dir
elif enemy_dir != Vector2.ZERO:
    _last_facing = enemy_dir
elif input_dir != Vector2.ZERO:
    _last_facing = input_dir
```

### Priority Table

| Condition | Facing |
|---|---|
| Holding input + blocked by terrain | Input direction |
| Holding input + NOT blocked | Nearest enemy |
| No input | Nearest enemy |
| No enemy in range | Input direction (if holding) or last facing |

### Why 4px ray length?

- The player body is 8x12px. A 4px ray from center will hit walls 4px away from the body center, which means ~0-2px from the body edge. This triggers only when the player is truly pressing against a wall, avoiding false positives from nearby-but-not-blocking walls.
- `CharacterBody2D.move_and_slide()` already stops the player at walls, so the player's position relative to walls is reliable.

### Edge Cases

- **Fluids (gas, water, lava)**: Not affected — the raycast queries only collision layer 1 (solid terrain), not fluids. Carving through fluids uses the existing push-materials pass.
- **Creative mode**: The player has `collision_mask = 0` in creative, so `_is_blocked_by_terrain()` will never return true. Auto-facing behaves identically to current behavior.
- **Projectiles**: Direction is read from `get_facing_direction()` at spawn time, so the fix propagates to ranged weapons and projectile carving.
- **Multiple enemies**: Closest enemy still wins (unchanged), unless wall-block overrides.

## Non-Goals

- No new input bindings
- No changes to enemy AI facing
- No changes to weapon arc/angle logic
- No aim assist or target lock system additions
