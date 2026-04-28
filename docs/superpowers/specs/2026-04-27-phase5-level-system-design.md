# Phase 5: Level System Design (Noita-style)

**Date:** 2026-04-27
**Status:** Approved

---

## Goal

Phase 5 layers procedural level structure on top of the existing GPU Simplex cave generator, with the explicit aim of recreating Noita's "self-organized world" feel: every floor looks bespoke, every room shape is distinct, material pools cluster naturally, and entities sit at deliberate-feeling positions.

The core idea, mirroring Noita: **floors are biomes, rooms are PNG templates, entities spawn from marker pixels.**

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ CPU: BiomeRegistry (resources, indexed by floor)         │
│   • room template list  • material palette  • noise cfg  │
└────────────────┬────────────────────────────────────────┘
                 │
┌─────────────────────────────────────────────────────────┐
│ CPU: SectorGrid (deterministic, hash(seed,coord))        │
│   • room slot per sector (template + rotation)           │
│   • boss sector forced at chebyshev_distance == N        │
└────────────────┬────────────────────────────────────────┘
                 │  upload stamp buffer + biome UBO
                 ▼
┌─────────────────────────────────────────────────────────┐
│ GPU: generation.glsl (extended pipeline)                 │
│   1. wood_fill (background bootstrap, existing)          │
│   2. biome_cave (noise params from BiomeDef)             │
│   3. biome_pools (per-material low-frequency threshold)  │
│   4. pixel_scene_stamp (samples PNG room textures)       │
│   5. secret_ring (annular wall around secret rooms)      │
└────────────────┬────────────────────────────────────────┘
                 │  chunks_generated signal (new)
                 ▼
┌─────────────────────────────────────────────────────────┐
│ CPU: SpawnDispatcher (reads PNG G channel from cache)    │
│   • per stamp, walks marker pixels                       │
│   • dispatches: enemy, elite, chest, shop, secret, boss  │
│   • dedup via _spawned_sectors                           │
└─────────────────────────────────────────────────────────┘
```

**Key reuses:** existing chunk pipeline, `MaterialRegistry`, GLSL stage pattern (`wood_fill_stage`, `simplex_cave_stage`), chest/shop scenes.

**Key additions:** biome stratification per floor, PNG room templates, pool noise per material, spawn marker readback.

---

## Subsystem 1 — Biomes & Materials

### `BiomeDef` (Resource)
- `display_name: String`
- `cave_noise_scale: float`, `cave_threshold: float`, `ridge_weight: float`, `ridge_scale: float`, `octaves: int`
- `background_material: int` — biome's default solid (e.g., STONE, ICE, WOOD)
- `pool_materials: Array[PoolDef]`
- `room_templates: Array[RoomTemplate]`
- `boss_templates: Array[RoomTemplate]`
- `secret_ring_thickness: int = 3` — pixels for annular wall
- `tint: Color`

### `PoolDef` (Resource)
- `material_id: int`
- `noise_scale: float` (low frequency → larger blobs)
- `noise_threshold: float`
- Each pool has its own seed offset (`hash(world_seed, material_id)`) to ensure pools don't perfectly overlap

### `RoomTemplate` (Resource)
- `png_path: String`
- `weight: float` (selection probability)
- `size_class: int` (16 / 32 / 64 / 128 — must match a Texture2DArray)
- `is_secret: bool`
- `is_boss: bool`
- `rotatable: bool` — if false, only 0° rotation (asymmetric rooms)

### Biomes shipped in Phase 5

| Floor | Biome | Background | Pool materials | Notes |
|-------|-------|-----------|---------------|-------|
| 1 | Caves | STONE | DIRT pools | Default — wide noise, gentle |
| 2 | Mines | STONE | COAL, WOOD | Tighter corridors, more rooms |
| 3 | Magma Caverns | STONE | LAVA, GAS | Hazardous, sparse |
| 4 | Frozen Depths | ICE | WATER | Brittle walls |
| 5 | Vault | WOOD | STONE | Constructed, dense |

Floors > 5 loop back to Caves with stat scaling continuing.

### New materials

`DIRT`, `COAL`, `ICE`, `WATER` — registered as static-solid materials (no fluid sim). Tint colors only at first; texture art deferred. Existing materials (STONE, WOOD, LAVA, GAS, AIR) are reused without change.

### Why "self-organized"

The per-pool noise stage (separate threshold per material with different scales) creates emergent material clusters: coal seams trail through mines, lava lakes pool naturally, water trickles. Player perceives deliberate placement; emerges from layered noise.

---

## Subsystem 2 — Sector Grid

`SectorGrid` is a pure class instantiated per floor with the floor's seed.

- `SECTOR_SIZE_PX = 384` (1.5 chunks — sectors are smaller than original spec to increase room density)
- `BOSS_RING_DISTANCE = 10` (Chebyshev sectors from origin)
- `world_to_sector(pos)`, `sector_to_world_center(coord)`, `chebyshev_distance(a, b)` — basic math
- `resolve_sector(coord) -> RoomSlot`:
  - If `chebyshev_distance(coord, ZERO) == BOSS_RING_DISTANCE` → pick from `biome.boss_templates`
  - If `chebyshev_distance > BOSS_RING_DISTANCE` → forced EMPTY (no rooms beyond boss ring)
  - Else: weighted pick from `biome.room_templates`, plus EMPTY weight (~30%)
- `RoomSlot` holds: `template_index`, `rotation` (0/90/180/270), or `EMPTY`
- All RNG uses `hash(world_seed ^ coord.x*73856093 ^ coord.y*19349663)` for full determinism

Tests: world↔sector conversions, chebyshev symmetry, boss ring forced, determinism across instances, seed sensitivity.

---

## Subsystem 3 — PNG Templates & GPU Stamping

### PNG channel encoding

| Channel | Use |
|---------|-----|
| R | Material ID (0..254). `0xFF` (255) = "biome native" — resolved on GPU to `biome.background_material` |
| G | Spawn marker (0=none, 1=enemy, 2=elite, 3=chest, 4=shop, 5=secret_loot, 6=boss, 7=portal_anchor) |
| B | Reserved (future: variant tag) |
| A | **Stamp mask: 0 = skip this pixel (preserve underlying terrain), 255 = write material from R**. This lets generators draw rooms without rectangular footprints. |

### `TemplatePack`

- Loads all PNGs at startup (called by `BiomeRegistry`)
- Groups by `size_class` → packs into `Texture2DArray` (one array per size: 16, 32, 64, 128)
- Caches the source `Image` per template for CPU-side G-channel readback (no GPU readback needed for spawning)
- Exposes `get_array(size_class) -> Texture2DArray` and `get_image(template_id) -> Image`

### Stamp buffer (storage buffer, set=1, binding=0)

```glsl
struct Stamp {
    vec2 world_center;          // .xy
    int  template_index;        // .z (in size_class array)
    int  packed;                // size_class (low 8) | rotation*90 (next 8) | flags (next 8)
};
StampBuffer { int count; int _pad[3]; Stamp stamps[128]; }
```

Up to 128 stamps per dispatch. Worst case: a generation pass loads ~30 chunks and each chunk touches up to 4 sectors → ~30-40 unique stamps; 128 leaves comfortable headroom. CPU dedupes stamps by sector before upload.

### Biome storage buffer (set=2, binding=0, std430)

Using a storage buffer (std430 layout) instead of a UBO to avoid std140 padding surprises and to match the existing stamp buffer convention.

```glsl
layout(set=2, binding=0, std430) readonly buffer BiomeBuffer {
    float cave_scale;
    float cave_threshold;
    float ridge_weight;
    float ridge_scale;
    int   octaves;
    int   background_material;
    int   secret_ring_thickness;
    int   _pad;
    // up to 4 pool entries, each: (material_id_as_float, noise_scale, noise_threshold, seed_offset)
    vec4 pools[4];
} biome;
```

Updated by CPU once per floor change (cheap — small buffer, low-frequency update).

### GLSL stages

**`biome_cave_stage.glslinc`** — replaces existing `simplex_cave_stage` with biome-driven params; same FBM + ridge structure.

**`biome_pools_stage.glslinc`** — for each pool, sample low-freq simplex; if `> threshold` and current pixel is solid (`> AIR`), overwrite with pool material. Order matters: first pool wins.

**`pixel_scene_stamp.glslinc`** — for each stamp:
1. Compute local UV in template (apply rotation transform on world_pos relative to stamp center). If outside [0,1], skip.
2. Sample template texel from appropriate `Texture2DArray`
3. If A == 0, skip pixel (preserve underlying terrain — this is how non-rectangular room footprints work)
4. If R == 0xFF, write `biome.background_material` to chunk; else write R as material id
5. G channel ignored on GPU (CPU handles markers via cached `Image`)

**`secret_ring_stage.glslinc`** — for each stamp flagged secret (flags bit), draw annulus of `biome.background_material` at `radius = template_size*0.45 .. template_size*0.45 + thickness` from stamp center. Runs after pixel_scene to override AIR at the ring.

### Generation pipeline order

```glsl
stage_wood_fill(ctx);
stage_biome_cave(ctx);
stage_biome_pools(ctx);
stage_pixel_scene_stamp(ctx);
stage_secret_ring(ctx);
```

---

## Subsystem 4 — Spawn Dispatcher

### Flow

1. `WorldManager._update_chunks` dispatches generation; emits `chunks_generated(new_coords)` (new signal).
2. `SpawnDispatcher` (child of `LevelManager`) listens.
3. For each chunk, finds sector centers contained in that chunk. For each sector:
   - Skip if `_spawned_sectors[coord]` already true
   - Get `RoomSlot` from `SectorGrid`
   - Get the template's source `Image` from `TemplatePack`
   - For each pixel where G > 0: compute world position via `stamp_center + rotated_local_offset`, dispatch by marker value

### Marker → handler

| Marker | Scene | Notes |
|--------|-------|-------|
| 1 ENEMY | `dummy_enemy.tscn` | tier+stat scaling |
| 2 ELITE | `dummy_enemy.tscn` (x2 health) | placeholder for future enemy types |
| 3 CHEST | `chest.tscn` | normal drop |
| 4 SHOP | `shop_ui.tscn` | uses existing system |
| 5 SECRET_LOOT | `chest.tscn` | rare drop flag (future) |
| 6 BOSS | scaled `dummy_enemy.tscn` | x5 hp, x1.5 speed, biome tint, `died` → spawn portal |
| 7 PORTAL_ANCHOR | (reserved location) | portal spawns here on boss death; if absent, falls back to boss death position |

### Tier & floor scaling (applied at spawn)

- `tier_index = clamp(floor(chebyshev_distance / BOSS_RING * 2), 0, 2)` → NORMAL/RARE/UNIQUE
- Per floor: `health *= 1 + 0.25*(floor-1)`, `damage *= 1 + 0.15*(floor-1)`, `speed *= 1 + 0.10*(floor-1)`

### Rotation handling

Only cardinal rotations (0/90/180/270). Marker offsets transformed via integer rotation matrices. `rotatable=false` templates locked to 0°.

### Why CPU-side readback

PNGs are static assets — `Image.get_pixel()` is fast and synchronous. GPU readback (`rd.texture_get_data`) is async and stalls. CPU-side keeps spawn determinism tight and avoids frame hitches.

---

## Subsystem 5 — Floor Transitions

### `LevelManager` (autoload)
- `floor_number: int = 1`, `world_seed: int = randi()`, `current_biome: BiomeDef`
- Owns `SectorGrid` (rebuilt per floor) and `SpawnDispatcher` (child node)
- `advance_floor()`:
  1. `floor_number += 1`
  2. `world_seed = randi()`
  3. `current_biome = BiomeRegistry.get_biome(floor_number)` (loops if past end)
  4. `_grid = SectorGrid.new(world_seed, current_biome)`
  5. `_spawn_dispatcher.clear()`
  6. `WorldManager.reset()` — unloads chunks, despawns entities, frees physics
  7. Player respawned at origin via existing `find_spawn_position`
  8. `floor_changed.emit(floor_number)`

### `Portal` (`scenes/portal.tscn` + `src/portal.gd`)
- Area2D with sprite + collision
- `body_entered` (player) → show "[E] Enter Portal" prompt
- On `interact`: `LevelManager.advance_floor()`; `queue_free()`

### Boss → portal flow
- `SpawnDispatcher` connects boss enemy's `died` signal to `_on_boss_died(world_pos)`
- Handler: instantiate `Portal`, position at `PORTAL_ANCHOR` marker location if any, else at `world_pos`

### `WorldManager.reset()` (new method)
- `chunk_manager.clear_all_chunks()` (existing)
- Despawn all entities under `chunk_container`
- Re-bind biome's stamp template arrays to GPU (template arrays change between biomes)
- Reset `tracking_position = Vector2.ZERO`

### No HUD this phase
Per design discussion: floor counter HUD is not added. `floor_changed` signal is emitted for future UI hooks, but no label changes in `game.tscn`.

---

## Subsystem 6 — Script-Generated Room Templates

PNGs are not hand-painted in Phase 5. They're generated by GDScript `@tool` scripts in `tools/`.

### Entry point: `tools/generate_room_templates.gd`
- `@tool` script, runnable via `godot --headless --script tools/generate_room_templates.gd` or invoked from editor
- Iterates a config table `[(biome, generator, size, seed, count)]` and writes PNGs to `assets/rooms/<biome>/`
- Emits per-biome BiomeDef `.tres` resource pointing at the generated PNGs

### Generators (`tools/room_generators/*.gd`)

| File | Function | Output |
|------|----------|--------|
| `blob_room.gd` | `generate_blob(size, pool_material, enemy_count, seed) -> Image` | Irregular blob carved into stone, optional pool material patch, enemy markers scattered |
| `arena.gd` | `generate_arena(size, enemy_count, is_boss, seed) -> Image` | Rectangular arena with wall border, enemies clustered, boss marker if flagged |
| `corridor.gd` | `generate_corridor(length, width, has_chest, seed) -> Image` | Long thin room, chest at one end if flagged |
| `secret_vault.gd` | `generate_secret_vault(size, seed) -> Image` | Small chamber, secret_loot marker; ring stage handles wall |
| `shop_chamber.gd` | `generate_shop_chamber(size, seed) -> Image` | Small room, shop marker centered |

### Bootstrap content (Phase 5 ships with):

| Biome | Templates |
|-------|-----------|
| Caves | 2× blob (size 64), 1× corridor (96×32), 1× secret_vault (32) |
| Mines | 2× corridor (96×32), 1× arena (64), 1× secret_vault (32) |
| Magma Caverns | 2× blob (64) with LAVA pools, 1× arena (64) |
| Frozen Depths | 2× blob (64) with WATER pools, 1× corridor (96×32) |
| Vault | 2× arena (64), 1× shop_chamber (32) |

Plus 1 boss template per biome (size 128). Total: ~25 templates.

Adding more is `godot --headless --script tools/generate_room_templates.gd` after editing the config table.

---

## File Plan

### New files

| Path | Purpose |
|------|---------|
| `src/autoload/biome_registry.gd` | Holds `BiomeDef[]`; `get_biome(floor)` |
| `src/autoload/level_manager.gd` | Floor state, sector grid, advance_floor |
| `src/core/biome_def.gd` | Resource — biome config |
| `src/core/room_template.gd` | Resource — PNG path + flags |
| `src/core/pool_def.gd` | Resource — pool material + noise |
| `src/core/sector_grid.gd` | Pure class — sector math |
| `src/core/spawn_dispatcher.gd` | Marker readback, entity spawning |
| `src/core/template_pack.gd` | PNG → Texture2DArray loader, image cache |
| `src/portal.gd` | Area2D interactable |
| `scenes/portal.tscn` | Portal scene |
| `shaders/include/biome_cave_stage.glslinc` | Biome-driven cave noise |
| `shaders/include/biome_pools_stage.glslinc` | Per-material pool noise |
| `shaders/include/pixel_scene_stamp.glslinc` | Stamp PNGs via texture array |
| `shaders/include/secret_ring_stage.glslinc` | Annular wall for secrets |
| `tools/generate_room_templates.gd` | Entry point — runs all generators |
| `tools/room_generators/blob_room.gd` | Irregular blob generator |
| `tools/room_generators/arena.gd` | Rectangular arena |
| `tools/room_generators/corridor.gd` | Long thin corridor |
| `tools/room_generators/secret_vault.gd` | Small treasure room |
| `tools/room_generators/shop_chamber.gd` | Shop chamber |
| `assets/rooms/<biome>/*.png` | Generated templates |
| `assets/biomes/<biome>.tres` | BiomeDef resources |
| `tests/unit/test_sector_grid.gd` | Determinism + math |
| `tests/unit/test_template_pack.gd` | Marker readback |

### Modified files

| Path | Change |
|------|--------|
| `src/autoload/material_registry.gd` | Add DIRT, COAL, ICE, WATER (static-solid) |
| `src/core/world_manager.gd` | `chunks_generated` signal; `reset()`; biome+stamps to dispatch |
| `src/core/compute_device.gd` | Stamp buffer, biome UBO, template Texture2DArray bindings |
| `shaders/compute/generation.glsl` | New stage chain |
| `project.godot` | Register `BiomeRegistry`, `LevelManager` |

---

## Out of Scope

- Difficulty scaling beyond per-floor stat multipliers (no enemy variety yet — all `dummy_enemy`)
- Boss-specific abilities and attack patterns (gameplay.md → future)
- Distinct enemy types per biome (placeholder elites x2 hp only)
- Texture art for new materials (tint colors only)
- Fluid simulation for WATER (static solid)
- Floor counter HUD (per design discussion)
- Visual hint that a secret exists
- Hand-painted templates (script-generated only)
- Free rotation (cardinal only)
- `rotatable=false` enforcement at generation time

---

## Implementation Order

1. `MaterialRegistry` — DIRT, COAL, ICE, WATER
2. `RoomTemplate`, `PoolDef`, `BiomeDef` resources + 5 placeholder `.tres` biomes
3. `tools/generate_room_templates.gd` + 5 generators + bootstrap content (~25 PNGs)
4. `TemplatePack` + tests (marker readback)
5. `SectorGrid` + tests (determinism, math)
6. Shader pipeline rewrite (biome_cave, biome_pools, pixel_scene_stamp, secret_ring)
7. `ComputeDevice` extensions (stamp buffer, biome UBO, template arrays)
8. `BiomeRegistry`, `LevelManager` autoloads + project.godot wiring
9. `SpawnDispatcher` + dedup
10. `Portal` + `WorldManager.reset()` + advance_floor flow
11. End-to-end smoke test (walk through all 5 biomes)
