# Fog of War — Design

**Date**: 2026-05-05
**Status**: Design

## Goal

Entities (enemies, chests, drops, projectiles, portals) are only visible when illuminated by a light source with clear line of sight. Terrain always remains visible. Entities fade smoothly based on light proximity — not a binary on/off switch.

## Non-Goals

- Exploration fog (permanently revealed map) — out of scope
- Terrain darkness — terrain always renders normally
- Changing existing light behavior — PointLight2D nodes and occluders unchanged

## Architecture

`FogOfWar` node (`src/core/fog_of_war.gd`) added to `game.tscn`. It manages visibility of all tracked entities by checking proximity and line-of-sight to registered light sources.

```
Entities                     Light Sources
    |  register(self)              |  register_light(position, range)
    v                              v
        FogOfWar
            |  per-frame (throttled every 2 frames):
            |  for each tracked entity:
            |    max_visibility = 0.0
            |    for each in-range light:
            |      raycast entity→light, exclude entity's own RID
            |      if clear LOS:
            |        visibility = 1.0 - distance/range
            |        max_visibility = max(max_visibility, visibility)
            |    lerp modulate.a toward max_visibility
            v
        Entity.modulate.a (0.0 hidden ↔ 1.0 visible)
```

## Registration

### Light Sources

`register_light(node: Node2D, range: float)` — stores `{weakref(node), position, range}`.

- **Player light**: Player scene already has `PointLight2D` child. `player_controller.gd` registers it in `_ready()` with range ~128px matching the player light's texture scale.
- **Chunk lights**: `ChunkLights` gains a `get_active_lights() -> Array[Dictionary]` method returning `{position, range, energy}` for each light with `current_energies[i] >= 0.005`. `FogOfWar` polls all `ChunkLights` instances (tracked by `chunk_lights_registered`/`chunk_lights_unregistered` signals or direct calls on create/free). Alternatively, `ChunkLights` calls `FogOfWar.update_chunk_lights(self, light_array)` on each `apply_light_data()` call and `FogOfWar.unregister_chunk_lights(self)` in `_exit_tree()`.

### Entities

Entities call `FogOfWar.register(self)` in `_ready()` and `FogOfWar.unregister(self)` in `_exit_tree()`. FogOfWar maintains an internal `_entities: Array[WeakRef]` list. No group scanning overhead.

Tracked entity types: enemies, chests, drops (gold/weapon/modifier), projectiles, portals.

## Visibility Evaluation (throttled every 2 frames)

For each tracked entity (skip if weakref freed):

1. **Collect in-range lights** — Filter registered lights where `distance(entity.global_position, light.position) < light.range * 1.2`. The 1.2× buffer allows fade to start slightly before the light edge.
2. **Compute max visibility** — For each in-range light:
   - **Line-of-sight raycast**: `PhysicsRayQueryParameters2D.create(entity_pos, light_pos, collision_mask=1, exclude=[entity_rid])`. The `exclude` parameter prevents the entity's own collision body from self-hitting.
   - **If blocked** (ray hit terrain) → skip this light.
   - **If clear** → `visibility = clamp(1.0 - distance / light.range, 0.0, 1.0)`. Closer to light = more visible.
   - `max_visibility = max(max_visibility, visibility)`
3. **Set target alpha** — `target_alpha = max_visibility`. Entity visible if ANY in-range light has clear LOS.

## Smoothing

```gdscript
const SMOOTH_SPEED := 10.0
entity.modulate.a = move_toward(entity.modulate.a, target_alpha, delta * SMOOTH_SPEED)
```

This ensures entities fade gradually when moving away from a light (the user asked for this specifically).

**Modulation inheritance**: Setting `modulate.a` on the entity's root node (CharacterBody2D, Area2D, etc.) propagates to all sprite/rendering children. No child must override its own `self_modulate` or `modulate` — verify existing entity scenes don't do this.

## Performance

| Technique | Detail |
|-----------|--------|
| Throttling | Full visibility evaluation every 2 frames; smoothing runs every frame |
| Spatial bucketing | Lights bucketed into 256px grid cells; entity only checks lights in nearby cells |
| Raycast caching | Cache result when entity position delta < 4px Euclidean since last check; skip raycast, reuse cached target_alpha |
| Early exit | Skip entities with no lights in range; skip dead entities |
| WeakRef | Internal entity list uses `WeakRef` to avoid dangling references; cleaned when `get_ref()` returns null |

## Edge Cases

| Case | Handling |
|------|----------|
| Entity spawns (e.g., gold drop from kill) | `_ready()` sets `modulate.a = 0.0`, calls `FogOfWar.register(self)`. FogOfWar evaluates next throttle cycle. |
| Entity dies | `_exit_tree()` calls `FogOfWar.unregister(self)`. WeakRef cleans up if missed. |
| Stale light reference (chunk freed) | All light lookups guard with `is_instance_valid(node)` before accessing position. |
| Chunk unloads (lights removed) | `ChunkLights._exit_tree()` calls `FogOfWar.unregister_chunk_lights(self)`. |
| Multiple lights overlap | Entity gets max visibility across all in-range lights with clear LOS. |
| Entity behind thin/partial wall | Center-point raycast is sufficient at 320×180 resolution with 8×12 character sizes. |
| Player light range changes | `FogOfWar.update_light_range(light_node, new_range)` updates stored value. |

## Files

| File | Action |
|------|--------|
| `src/core/fog_of_war.gd` | **Create** — Main manager |
| `scenes/game.tscn` | **Modify** — Add FogOfWar node at root, sibling to WorldManager |
| `src/player/player_controller.gd` | **Modify** — Register `$PointLight2D` in `_ready()` with range 128 |
| `src/core/chunk_lights.gd` | **Modify** — Add `get_active_lights()`, register/unregister with FogOfWar on tree enter/exit |
| `src/enemies/enemy.gd` | **Modify** — Set `modulate.a = 0.0` in `_ready()`, register/unregister with FogOfWar |
| `src/drops/chest.gd` | **Modify** — Set `modulate.a = 0.0` in `_ready()`, register/unregister |
| `src/drops/drop.gd` | **Modify** — Set `modulate.a = 0.0` in `_ready()`, register/unregister |
| `src/drops/gold_drop.gd` | **Modify** — Set `modulate.a = 0.0` in `_ready()`, register/unregister (if overrides drop.gd) |
| `src/drops/weapon_drop.gd` | **Modify** — Set `modulate.a = 0.0` in `_ready()`, register/unregister (if overrides drop.gd) |
| `src/drops/modifier_drop.gd` | **Modify** — Set `modulate.a = 0.0` in `_ready()`, register/unregister (if overrides drop.gd) |
| `src/weapons/projectile.gd` | **Modify** — Set `modulate.a = 0.0` in `_ready()`, register/unregister |
| `scenes/portal.tscn` (needs script) | **Modify** — Add script or scene hook for register/unregister |

## Dependencies

- `TerrainSurface` / terrain collision layer 1 — for line-of-sight raycasts
- `ChunkLights` — for per-chunk light registration
- `Player` / `player_controller.gd` — for player light registration via `$PointLight2D`
