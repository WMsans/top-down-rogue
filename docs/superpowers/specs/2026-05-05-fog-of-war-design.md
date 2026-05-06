# Fog of War — Design

**Date**: 2026-05-05
**Status**: Design

## Goal

Entities (enemies, chests, drops, projectiles, portals) are only visible when illuminated by a light source with clear line of sight. Terrain always remains visible. Unlit entities smoothly fade to transparent.

## Non-Goals

- Exploration fog (permanently revealed map) — out of scope
- Terrain darkness — terrain always renders normally
- Changing existing light behavior — PointLight2D nodes and occluders unchanged

## Architecture

`FogOfWar` node (`src/core/fog_of_war.gd`) added to `game.tscn`. It manages visibility of all tracked entities by checking proximity and line-of-sight to registered light sources each frame.

```
Light Sources (PointLight2D nodes)
    |  register(position, range)
    v
FogOfWar
    |  per-frame: for each tracked entity
    |  -> find nearest light within range
    |  -> raycast entity->light against terrain collision layer
    |  -> set target_alpha (1.0 visible, 0.0 hidden)
    |  -> lerp modulate.a toward target_alpha
    v
Entities (modulate.a interpolated)
```

## Registration

**Light sources** — `register_light(light: PointLight2D, range: float)`. Called when:
- Player spawns (player's PointLight2D, range ~128px matching light texture scale)
- Chunk lights created/destroyed (range defaults to `ChunkLights.DEFAULT_LIGHT_RANGE = 64`)

**Entities** — Entities are auto-discovered by group membership. Add `"fow_tracked"` group to enemy, chest, drop, projectile, and portal scenes. `FogOfWar` scans the group each frame for additions/removals.

## Visibility Evaluation (per-frame, throttled to every 2 frames)

For each tracked entity:
1. Find the closest registered light where `distance < light.range * 1.2` (buffer so fade starts before edge)
2. If no light in range → `target_alpha = 0.0`
3. If light in range → `PhysicsRayQueryParameters2D` from entity position to light position, collision mask = layer 1 (terrain)
4. Hit anything → blocked → `target_alpha = 0.0`
5. Hit nothing → clear line of sight → `target_alpha = 1.0`

## Smoothing

```gdscript
const SMOOTH_SPEED := 10.0
entity.modulate.a = move_toward(entity.modulate.a, target_alpha, delta * SMOOTH_SPEED)
```

## Performance

- Visibility checks throttled to every 2 frames
- Spatial bucketing (coarse grid, e.g. 256px cells) for O(1) light proximity queries
- Raycast only when within detection range of a light
- Cache raycast results when entity position hasn't changed significantly

## Edge Cases

| Case | Handling |
|------|----------|
| Entity spawns (e.g., gold drop from kill) | `_ready()` includes it in group, FogOfWar picks it up next scan |
| Entity dies | `queue_free()` removes from group before free |
| Chunk unloads (lights removed) | `unregister_light()` called, entities re-evaluated next frame |
| Player light range changes | `update_light_range()` updates stored value |
| Multiple lights overlap | Entity visible if ANY light has clear line of sight |
| Entity partially behind wall edge | Center-point raycast suffices; edge cases rare at 320x180 resolution |

## Files

| File | Action |
|------|--------|
| `src/core/fog_of_war.gd` | Create — main manager |
| `scenes/game.tscn` | Modify — add FogOfWar node |
| `src/player/player_controller.gd` | Modify — register player PointLight2D on spawn |
| `src/core/chunk_lights.gd` | Modify — register/unregister per-chunk lights |
| `scenes/enemies/enemy.tscn` | Modify — add `"fow_tracked"` group |
| `scenes/chest.tscn` | Modify — add `"fow_tracked"` group |
| `scenes/drop.tscn` | Modify — add `"fow_tracked"` group |
| `scenes/gold_drop.tscn` | Modify — add `"fow_tracked"` group |
| `scenes/weapon_drop.tscn` | Modify — add `"fow_tracked"` group |
| `scenes/modifier_drop.tscn` | Modify — add `"fow_tracked"` group |
| `scenes/projectile.tscn` | Modify — add `"fow_tracked"` group |
| `scenes/portal.tscn` | Modify — add `"fow_tracked"` group |

## Dependencies

- `TerrainSurface` / terrain collision layer 1 — for line-of-sight raycasts
- `ChunkLights` — for per-chunk light registration
- `Player` — for player light registration
