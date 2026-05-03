# Cave Enemy Spawning Design

**Date:** 2026-05-02
**Status:** Approved

## Overview

Enemies currently spawn only in rooms (sectors with template PNG markers). The vast cave tunnels between rooms are empty. This design adds a Minecraft-style natural spawning system that populates cave corridors with enemies, coexisting with the existing room-based `SpawnDispatcher`.

## Design Decisions

| Decision | Choice |
|----------|--------|
| Light-based spawning | Material-based — spawn on any solid cave floor. Glowing-material suppression deferred. |
| Enemy types | DummyEnemy only for now. Per-biome enemy types deferred. |
| Room vs cave spawning | Both coexist — room template markers and cave natural spawns run independently. |
| Terrain validation | Use existing `TerrainPhysical.query()` — O(1) dictionary lookup, already purpose-built. |
| Creative mode | Cave spawns active in all game modes including creative. |
| Spawn radius | Min 600px, max 2000px from player. |
| Spawn frequency | 2 attempts every 1s across loaded chunks. |
| Mob cap | 15 enemies total (room + cave combined). |
| Despawn distance | Enemies beyond 2500px from player are removed every 1s. |
| Biome awareness | Design supports biome-specific spawn rates; initially all biomes use DummyEnemy at rate 1.0. |

## Architecture

### 1. CaveSpawner: `src/core/cave_spawner.gd`

New node owned by `LevelManager`, running alongside the existing `SpawnDispatcher`.

**Lifecycle:**
- Created in `LevelManager._setup()`, added as child
- `_ready()`: stores references to `WorldManager`, `TerrainSurface`, `BiomeRegistry`, `GameModeManager`; starts spawn timer (1s) and despawn timer (1s)

**Scene tree integration:**
```
LevelManager
├── SpawnDispatcher (existing) — room template marker spawning
└── CaveSpawner (new) — natural cave spawning
```

### 2. Spawn Cycle (every 1s)

```
_on_spawn_tick():
    1. Count live enemies in scene tree → if >= mob_cap (15), return
    2. Get active chunk coordinates from TerrainSurface
    3. Shuffle chunks, pick up to attempts_per_cycle (2) chunks
    4. For each chunk:
        a. Pick random (x, y) within chunk bounds (256x256 px)
        b. validate_position(world_pos)
        c. If valid: instantiate enemy_scene at world_pos; parent to WorldManager.chunk_container (same parent as SpawnDispatcher enemies)
```

### 3. Position Validation

`validate_position(world_pos: Vector2) → bool`:

1. **Distance check:** Clamp world_pos distance from player to `[spawn_min_dist, spawn_max_dist]`. Fail if outside.
2. **Floor check:** Sample 3 points downward from candidate (offset 0, 16px, 32px). Query `TerrainPhysical.query(point).is_solid`. At least one must be solid → floor exists.
3. **Headroom check:** Sample 2 cells directly above the floor → `TerrainPhysical.query(point).is_solid == false` for both → air space for enemy to occupy.
4. **Collision check:** Ensure no overlap with existing enemies or other entities at the candidate position.
5. Return `true` if all pass.

**Fallback:** If the random position fails, retry up to 3 times within the same chunk with different random offsets. If all fail, skip to next chunk.

### 4. Despawn Cycle (every 1s)

```
_on_despawn_tick():
    For each Enemy in scene tree:
        If enemy.global_position.distance_to(player.global_position) > despawn_dist:
            enemy.queue_free()
```

Enemies parented to `WorldManager.chunk_container` (not chunk children), same as `SpawnDispatcher`. They survive chunk unloading. Despawn catches any that end up in unloaded territory.

### 5. Parameters

All `@export` on `CaveSpawner`:

| Parameter | Type | Default | Notes |
|-----------|------|---------|-------|
| `spawn_interval` | float | 1.0 | Seconds between spawn cycles |
| `attempts_per_cycle` | int | 2 | Spawn attempts per cycle |
| `spawn_min_dist` | float | 600 | Min px from player |
| `spawn_max_dist` | float | 2000 | Max px from player |
| `despawn_dist` | float | 2500 | Despawn px from player |
| `mob_cap` | int | 15 | Max concurrent enemies |
| `spawn_rate` | float | 1.0 | Per-biome multiplier (0.0 = no spawns) |
| `enemy_scene` | PackedScene | `res://scenes/dummy_enemy.tscn` | Scene to instantiate |

### 6. Biome Awareness

`BiomeDef` resource gets new field:

```gdscript
@export var cave_spawn_rate: float = 1.0
```

On floor/level change, `LevelManager` calls `CaveSpawner.set_biome_params(biome.cave_spawn_rate)`. Future: `BiomeDef` can also export an alternate `enemy_scene` path.

The actual per-attempt spawn chance is `spawn_rate * base_chance` where `base_chance` is internal (suggested 0.5).

### 7. Dependency on Existing Systems

| System | Usage |
|--------|-------|
| `TerrainPhysical.query(pos)` | Check if pixel is solid (wall) or air |
| `TerrainSurface.get_active_chunk_coords()` | Get loaded chunk positions for spawn sampling |
| `WorldManager` | Access player position for distance checks |
| `BiomeRegistry` / `BiomeDef` | Read per-biome spawn rate |
| `GameModeManager` | (No gate — spawns run in all modes) |
| `Enemy` scene tree nodes | Count live enemies for mob cap |

## Files Changed

| File | Action |
|------|--------|
| `src/core/cave_spawner.gd` | **New** — all cave spawning logic |
| `src/autoload/level_manager.gd` | **Modify** — instantiate CaveSpawner in `_setup()` |
| `src/core/biome_def.gd` | **Modify** — add `cave_spawn_rate` field |
| `tests/unit/test_cave_spawner.gd` | **New** — unit tests |

## Edge Cases

- **Chunk not yet loaded for position:** `TerrainPhysical` has no entry → skip attempt silently.
- **Entirely solid chunk:** All validation attempts fail → skip chunk, no error.
- **Mob cap overshoot:** Check at cycle start; 1–2 extra enemies possible in a single cycle, self-corrects next cycle.
- **Player teleports:** Next despawn cycle (≤1s) cleans up enemies beyond 2500px.
- **Boss ring / empty sectors:** Sectors beyond the boss ring are all wood (solid) → floor+headroom validation fails naturally, no spawns.
- **Enemy parented to chunk_container:** Survives chunk unload. Despawn cycle handles cleanup.

## Testing

Unit tests (`tests/unit/test_cave_spawner.gd`) using GdUnit4:

1. **Mob cap enforcement:** Manually add 15 enemies to scene. Call spawn tick. Verify no new spawns.
2. **Distance validation:** Test positions inside/outside [600, 2000] range — expect correct pass/fail.
3. **Terrain validation:** Query a known-solid position → rejected. Query air-over-solid → accepted.
4. **Despawn:** Place enemy beyond 2500px, run despawn tick, verify enemy freed.
