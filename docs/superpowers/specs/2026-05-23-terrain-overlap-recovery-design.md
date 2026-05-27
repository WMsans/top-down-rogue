# Terrain Overlap Recovery for Player Controller

## Problem

When the player digs into walls (a core mechanic), they can get stuck inside terrain. The player's 8x12 collision rectangle becomes trapped in tight concave cavities carved by the digging arc. Two root causes:

1. **Async collision lag**: Terrain collision shapes (ConcavePolygonShape2D on StaticBody2D) are rebuilt with a multi-frame delay via GPU compute. The player can walk into a position that becomes solid before the collision shape updates.
2. **Concave pocket trap**: A 6px-deep, 45-degree arc in stone creates an air pocket barely wider than the player hitbox. `move_and_slide()` slides along surfaces but cannot resolve a pre-existing overlap inside a tight concave cavity.

Once stuck, the only escape is digging out — which is not always possible and feels frustrating.

## Solution

Add post-movement overlap recovery to the player controller. After `move_and_slide()`, detect if the player overlaps terrain collision and push them to the nearest open position.

### Algorithm

After `move_and_slide()` in `_physics_process()`:

1. **Detect overlap**: Call `PhysicsDirectSpaceState2D.intersect_shape()` with the player's collision shape, checking against terrain layer (collision mask bit 0 = layer 1). If no overlap, record current position as `_last_safe_position` and return.

2. **Recovery push**: If overlapping, attempt stepwise position adjustments in priority order:
   - **Priority direction**: last input/movement direction (the direction the player is trying to go — likely where they dug from)
   - **Cardinal fallback**: UP, RIGHT, DOWN, LEFT (2px steps)
   - **Diagonal fallback**: the four 45-degree diagonals (2px steps)
   - For each direction, test whether shifting the player by `RECOVERY_STEP` (2px) resolves the overlap. Accept the first direction that clears it.

3. **Iterate**: Repeat up to `MAX_RECOVERY_STEPS` (8) times until the player is free, or all directions are exhausted for a given step.

4. **Hard fallback**: If still stuck after max steps, snap to `_last_safe_position`. This should be extremely rare.

### New State

In `player_controller.gd`:
- `var _last_safe_position: Vector2` — saved each frame when not overlapping terrain
- `const MAX_RECOVERY_STEPS := 8`
- `const RECOVERY_STEP := 2.0`

### Integration Point

In `_physics_process()`, insert `_resolve_terrain_overlap()` after `move_and_slide()` (line 95):

```gdscript
move_and_slide()
_resolve_terrain_overlap()
```

### What Does Not Change

- Terrain collision shape rebuild pipeline (`TerrainCollisionHelper`) — no forced synchronous rebuilds
- Digging mechanic — no guaranteed exit path carved into terrain
- `move_and_slide()` — remains primary physics resolution; recovery only activates on pre-existing overlaps

## Files Changed

- `src/player/player_controller.gd` — add `_resolve_terrain_overlap()` method and supporting state/constants