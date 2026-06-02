# Glowing Cave Flora — Design

**Date:** 2026-06-02
**Status:** Approved

## Overview

The cave level (floor 1) is too dark. The scene is darkened globally by a
`DirectionalLight2D` (SUB blend) plus `WorldEnvironment` glow; `PointLight2D`
sources (player light, set-piece lanterns, glowing lava/coal via `chunk_lights`)
punch through. Normal cave chunks carry **no light sources of their own**, so the
space between the player and any set-piece is pitch black.

This design fills cave chunks with **bioluminescent flora** — decorative sprites
that each emit a soft, shadow-less, flickering glow — so the cave reads as dimly
but genuinely lit and is navigable by the flora alone, with the player light as a
supplement.

It is delivered by upgrading the existing per-chunk decoration scatter
(`floor_chunk.gd`) from a flat texture list into a reusable, light-aware
`DecorDef` data model. Only the caves biome uses it now, but the system is
biome-agnostic so future levels can opt in (glowing or not) via config alone.

## Design Decisions

| Decision | Choice |
|---|---|
| What the flora are | Bioluminescent flora reusing the existing `grass1` / `grass2` / `small_tree` sprites in `textures/Environments/Decors` |
| How they glow | A real `PointLight2D` per flora (ADD blend) — actually lights surrounding terrain, not just bloom |
| Brightness target | "Meaningfully lit" — dense/bright enough to navigate by; player light becomes a supplement |
| Shadows | **Disabled.** 150–250 shadow-casting lights would tank framerate on the integrated-GPU baseline (same rationale as `chunk_lights.gd`) |
| Flicker | **On.** Soft sine-jitter, reusing the existing lantern flicker logic |
| Placement | Floor-only — flora spawn only on `MAT_AIR` cells, never buried in solid rock |
| Data model | New `DecorDef` resource; `BiomeDef.decor_defs` replaces the flat `decor_textures` array |
| Node construction | Built in code in `floor_chunk` (no scene instanced per flora) — matches current approach and avoids ~200 scene instantiations |
| Scope | Caves only for now; the system is biome-agnostic and reusable |

## Architecture

### 1. `DecorDef` resource — `src/core/decor_def.gd`

```gdscript
class_name DecorDef
extends Resource

@export var texture: Texture2D
@export var weight: float = 1.0          # relative pick weight within a biome
@export var emits_light: bool = true
@export var light_color: Color = Color(0.5, 0.9, 1.0, 1.0)  # soft cyan/teal
@export var light_energy: float = 1.0
@export var light_radius: float = 56.0   # px; maps to PointLight2D.texture_scale
@export var flicker_amplitude: float = 0.08  # 0 = steady glow
```

A biome's decorations are a weighted set of these. Non-glowing decor (future
biomes) is simply `emits_light = false`, which also skips the flicker.

### 2. `BiomeDef` changes — `src/core/biome_def.gd`

- **Remove** `decor_textures: Array[Texture2D]`.
- **Add** `decor_defs: Array[DecorDef] = []`.
- Keep `decor_chance: float = 0.02` (per-cell spawn probability).

Migration is trivial: the only consumer is caves, which currently sets no
`decor_textures` at all.

### 3. Shared flicker — `src/core/flicker_light.gd`

The lantern's flicker logic (`src/props/lantern.gd`) is extracted into a small
reusable script attached directly to a `PointLight2D`:

```gdscript
class_name FlickerLight
extends PointLight2D

var base_energy: float = 1.0
var amplitude: float = 0.08
var _phase: float = 0.0

func _ready() -> void:
    base_energy = energy
    _phase = randf() * TAU

func _process(delta: float) -> void:
    if amplitude <= 0.0:
        set_process(false)
        return
    _phase += delta * 8.0
    var jitter := sin(_phase) * 0.6 + sin(_phase * 2.3) * 0.4
    energy = base_energy + jitter * amplitude
```

`src/props/lantern.gd` is refactored to use this (the lantern scene's `Light`
node becomes a `FlickerLight`, or lantern keeps a thin wrapper that delegates) so
the jitter math lives in one place. Flora with `flicker_amplitude == 0` disable
their own `_process` immediately.

### 4. Floor-only placement — `src/terrain/floor_container.gd`

`FloorContainer._on_chunks_generated` already holds `_world_manager`. For each
newly generated chunk it reads the chunk's material region once and passes the
bytes to the floor chunk:

```gdscript
var rect := Rect2i(coord.x * CHUNK_SIZE, coord.y * CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE)
var material_bytes := _world_manager.read_region(rect)   # 256*256 bytes
fc.populate(coord, biome, world_seed, material_bytes)
```

One GPU readback per newly generated chunk — the same `read_region`-on-
`chunks_generated` pattern the spawn and composition dispatchers already use. The
terrain texture is ready at this point (those dispatchers read it on the same
signal).

### 5. Decoration build — `src/terrain/floor_chunk.gd`

`populate()` / `_add_decorations()` gain the material bytes and use `decor_defs`:

```gdscript
func _add_decorations(coord, biome, world_seed, material_bytes) -> void:
    if biome.decor_defs.is_empty() or biome.decor_chance <= 0.0:
        return
    var rng := RandomNumberGenerator.new()
    rng.seed = _hash_seed(world_seed, coord)
    var cells_per_side := CHUNK_SIZE / TILE_SIZE  # 16
    for cy in range(cells_per_side):
        for cx in range(cells_per_side):
            if rng.randf() >= biome.decor_chance:
                continue
            # floor-only: sample the cell's center pixel
            var px := cx * TILE_SIZE + TILE_SIZE / 2
            var py := cy * TILE_SIZE + TILE_SIZE / 2
            if material_bytes[py * CHUNK_SIZE + px] != MaterialRegistry.MAT_AIR:
                continue
            var def := _weighted_pick(biome.decor_defs, rng)
            _spawn_decor(def, Vector2(cx * TILE_SIZE, cy * TILE_SIZE))
```

`_spawn_decor`:
- create `Sprite2D` with `def.texture`, `centered = false`, positioned at the cell;
- if `def.emits_light`, add a child `FlickerLight` (`PointLight2D`):
  - `blend_mode = BLEND_MODE_ADD`, `shadow_enabled = false`;
  - `texture` = a prebaked radial gradient (a single shared `GradientTexture2D`,
    same gradient shape the lantern uses);
  - `texture_scale = def.light_radius / 64.0`;
  - `color = def.light_color`, `energy = def.light_energy`;
  - `amplitude = def.flicker_amplitude`.

The radial gradient texture is built once and shared across all flora lights
(not one per node).

`_weighted_pick` selects a `DecorDef` proportional to `weight` using the same
seeded `rng`, keeping placement deterministic per `(world_seed, coord)`.

### 6. Caves configuration — `assets/biomes/caves.tres`

Add three `DecorDef` sub-resources:

| Sprite | `light_color` (approx) | notes |
|---|---|---|
| `grass1` | soft cyan `(0.5, 0.9, 1.0)` | most common (higher weight) |
| `grass2` | teal-green `(0.45, 1.0, 0.8)` | common |
| `small_tree` | cool green `(0.55, 0.95, 0.7)` | larger radius, rarer |

All `emits_light = true`, `light_radius ≈ 48–64`, `flicker_amplitude ≈ 0.08`.
`decor_chance` tuned so ~6–10 flora land per chunk (the "meaningfully lit"
density). Exact values dialed in by eye after first run.

## Lifecycle

- `FloorChunk.populate()` frees existing children before repopulating.
- `FloorContainer._on_chunk_unloaded()` frees the whole floor chunk on
  `chunk_unloaded`.

Flora sprites and their lights are children of the floor chunk, so both paths
already clean them up — no new teardown code, no light leaks.

## Performance Profile

| Metric | Value |
|---|---|
| Lit flora on screen | ~150–250 (≈6–10/chunk × ~25 loaded chunks) |
| Light type | `PointLight2D`, ADD blend, **no shadows** |
| Shared light texture | 1 `GradientTexture2D` reused by all flora |
| Per-chunk GPU readback | one `read_region` (65,536 bytes) per newly generated chunk |
| Flicker cost | ~200 cheap `_process` callbacks (2 `sin()` each); disabled when `amplitude == 0` |
| Main tuning knobs | `decor_chance` (density), `light_radius`, `light_energy` |

Shadow-less 2D lights are the known-acceptable envelope here (the glowing-
material system already runs up to 16 shadow-less lights/chunk). If profiling on
the integrated-GPU baseline shows strain, reduce `decor_chance` and/or
`light_radius` first.

## Files Changed

| File | Action |
|---|---|
| `src/core/decor_def.gd` | **New** — `DecorDef` resource |
| `src/core/flicker_light.gd` | **New** — shared `FlickerLight` (`PointLight2D`) |
| `src/core/biome_def.gd` | **Modify** — remove `decor_textures`, add `decor_defs` |
| `src/terrain/floor_container.gd` | **Modify** — read chunk region, pass bytes to `populate` |
| `src/terrain/floor_chunk.gd` | **Modify** — floor-only check, weighted pick, sprite + light build |
| `src/props/lantern.gd` | **Modify** — reuse `flicker_light.gd` |
| `assets/biomes/caves.tres` | **Modify** — three flora `DecorDef`s |

## Edge Cases

- **Biome with no `decor_defs`:** `_add_decorations` early-returns; no flora, no
  lights (current behavior for every non-caves biome).
- **Decor cell is solid rock:** skipped by the `MAT_AIR` center-pixel test.
- **Cell partially floor/partially wall:** the 16×16 cell is classified by its
  center pixel only — acceptable approximation; flora are small and centered.
- **`emits_light = false`:** plain decorative sprite, no light, no flicker —
  supports ordinary (non-glowing) decor for future biomes.
- **`flicker_amplitude == 0`:** steady glow; the flicker `_process` disables
  itself on first frame.
- **Chunk regenerated / unloaded:** existing `queue_free` paths free sprites and
  lights together.
- **`read_region` returns empty/short (chunk not ready):** guard the length;
  if the byte array is undersized, skip decoration for that chunk (it will be
  re-attempted only on regeneration — acceptable, and not expected given the
  existing dispatchers read successfully on the same signal).

## Out of Scope

- Glowing *materials* (lava/coal) and their compute-driven lights — already
  handled by `chunk_lights.gd` / `light_pack.glsl`.
- Set-piece lanterns and arena features — unchanged.
- New flora art (crystals/mushrooms) — this design reuses the existing flora
  sprites; new art can be added later as additional `DecorDef`s with no code
  change.
- Per-biome decor configs beyond caves — the system supports them, but only
  caves is populated here.
