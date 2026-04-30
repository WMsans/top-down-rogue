# Lava Dynamic Lighting — Design

**Date:** 2026-04-29
**Status:** Approved (brainstorming phase) — amended 2026-04-29 with G1 GPU-pipeline redesign (see "Implementation amendment" below)
**Scope:** Implement soft, world-space dynamic lighting for emissive falling-sand materials (lava first, future emitters supported), composing additively with the existing Godot Light2D pipeline.

---

## Problem

`MaterialDef.glow` is set on lava (10.0) and coal (20.0) in `src/autoload/material_registry.gd`, but the world has no lighting consumer for that field. The world's baselight is intentionally very dark; without dedicated light sources the glow is invisible. Assigning a `PointLight2D` to every emissive pixel is infeasible at falling-sand resolution.

## Goals

- Soft local glow: lava visibly tints nearby stone/walls (and entities) within roughly half a tile, fading smoothly to ambient.
- No occlusion required (light can bleed through thin walls).
- Composes additively with the existing player carry-light (`PointLight2D`) and any future Light2D sources.
- Cost stays bounded as more lava enters the world (per-chunk amortization, not per-pixel).
- Extensible to future emissive materials without re-plumbing.

## Non-goals

- Per-pixel occluded lighting (Noita-grade emissive propagation).
- Bloom / HDR tonemapping changes (HDR pipeline already exists).
- Lighting for off-loaded-chunk emitters.

---

## Requirements (locked-in answers)

| Topic | Choice |
|---|---|
| Visual fidelity | **B** — soft local glow, no occlusion |
| Granularity | **Light grid** (coarse 2D grid, bilinear-sampled) |
| Cell size | **R1: 1 light cell per 4×4 terrain pixels** |
| Update cadence | **U3 hybrid**: every 4 frames, dirty-chunk lazy re-accumulation |
| Kernel | **K3 medium (~5-cell radius)**, separable Gaussian over the whole grid per tick |
| Coverage | **E2** — loaded chunks only |
| Integration | **I2** — shared `light_grid_tex` global uniform, sampled by overlay shader |
| Color source | **C1** — reuse `MaterialDef.tint_color × glow`; emitter iff `glow > 0` |
| Ambient | ~0.05 (very dark) |
| HDR | Already enabled |
| Player carry-light | Already implemented as `PointLight2D` |
| Light2D coexistence | **X1** — additive fullscreen overlay; Light2D pipeline untouched |

---

## Architecture

A new autoload `LightingManager` owns a CPU-side **light grid** (RGB float buffer) sized to cover currently loaded chunks at 1 cell per 4×4 terrain pixels. Every 4 frames:

1. **Accumulate** — for each chunk flagged dirty since its last contribution, re-splat its emissive pixels (cells with `glow > 0`) into that chunk's cached splat buffer: `cache[cell] += tint_color.rgb * glow * k_global`. Clean chunks reuse their existing cache.
2. **Compose** — zero the main grid, then add each chunk's cache at its grid offset.
3. **Blur** — separable horizontal+vertical Gaussian (~5-cell radius, 11-tap) over the main grid into a same-size scratch buffer.
4. **Upload** — write the blurred buffer into a reused `ImageTexture` (`FORMAT_RGBH`); set as global shader uniform `light_grid_tex`.

The composite (overlay) draws every frame using the most recent texture, so the visual is glued to world space even between ticks.

---

## Components

### `LightingManager` (autoload — `src/autoload/lighting_manager.gd`)

Owns:
- `main_grid : PackedFloat32Array` — RGB, sized to loaded-chunk AABB.
- `scratch_grid : PackedFloat32Array` — same size; blur target.
- `chunk_caches : Dictionary[Vector2i, PackedFloat32Array]` — per-chunk splat caches.
- `dirty_chunks : Dictionary[Vector2i, bool]`.
- `light_grid_tex : ImageTexture` — exposed via `RenderingServer.global_shader_parameter_set`.
- `light_grid_world_rect : Rect2` — exposed as global uniform.

API:
- `register_chunk(chunk)` / `unregister_chunk(chunk)` — called from `chunk_manager` lifecycle hooks.
- `mark_chunk_dirty(chunk_coord: Vector2i)` — called from terrain-mutation paths whenever a cell with `glow > 0` is added/removed/replaced (old-or-new emitter triggers).
- `_process(delta)` — increments tick counter; runs steps 1–4 every `tick_interval` frames.

Exported tunables:
- `enabled : bool = true`
- `cell_size : int = 4`
- `tick_interval : int = 4`
- `blur_radius_cells : int = 5`
- `intensity_k : float = 1.0`
- `ambient : Color = Color(0.05, 0.05, 0.05)`
- `max_grid_cells : int = 1024 * 1024` (kill-switch cap)

### `LightingOverlay` (scene node)

A `ColorRect` on a `CanvasLayer` placed above the Light2D-lit world layer and below UI. Material uses `light_overlay.gdshader`:
- Read `SCREEN_UV`, convert to world position via the camera's canvas transform.
- Map world position into `light_grid_tex` UV using `light_grid_world_rect`.
- Sample bilinearly; output `vec4(sample.rgb * intensity_k + ambient.rgb, 1.0)` with `BLEND_ADD`.
- Outside the grid rect: output ambient only.

### `material_registry.gd` (existing — minimal change)

Add helper:
```gdscript
func is_emitter(material_id: int) -> bool:
    return get_glow(material_id) > 0.0
```
No schema change. C1 contribution rule: `tint_color.rgb * glow * intensity_k`.

### Hooks into existing code

- `chunk_manager.gd`: call `LightingManager.register_chunk` / `unregister_chunk` from existing chunk load/unload paths.
- The single cell-write function in `terrain_*` / `chunk.gd`: when the cell's old or new material is an emitter, call `LightingManager.mark_chunk_dirty(chunk_coord)`. Per-chunk granularity — no need to track per-cell deltas.

### Console integration

Register `lighting <on|off|reload>` via `command_registry.gd` for runtime toggling.

---

## Data flow & memory

**Grid coordinate system.** Anchored to an integer "grid origin" in world-cell space. When the loaded-chunk set changes, the AABB is recomputed; if the buffer must grow or shift, existing chunk caches are blitted into the new buffer at their correct offsets — no re-walking of clean chunks.

**Per-chunk cached splat.** For a chunk of size `chunk_w × chunk_h`, the cache is `(chunk_w/4) * (chunk_h/4) * 3` floats. Dirty-tick procedure:
1. Zero the cache.
2. Walk the chunk's cells; for every emitter cell at `(cx, cy)`: `cache[cy>>2 * grid_w + cx>>2] += tint_color.rgb * glow * intensity_k`.
3. Clear the dirty flag.

**Compose.** Zero `main_grid`, then add each chunk cache at the chunk's offset. Cheap float adds over the loaded-window union.

**Blur.** Two passes (horizontal → scratch → vertical → main_grid) with a precomputed 11-tap Gaussian.

**Upload.** Wrap the final buffer as an `Image` (`FORMAT_RGBH`); call `ImageTexture.update` — no per-tick allocation. Update `light_grid_world_rect` global uniform.

**Memory.** ~470 KB main + ~470 KB scratch + ~470 KB summed chunk caches for a 5×5 chunk window of 256×256-pixel chunks. ~1.4 MB total. Negligible.

---

## Edge cases & failure modes

- **Camera moves fast** — grid is anchored to chunks, not camera; the overlay's `SCREEN_UV → world` mapping uses the live camera transform every frame.
- **Chunk unloaded** — its cache is freed; next tick rebuilds the main grid from remaining caches; glow disappears cleanly.
- **Chunk newly loaded with lava** — first-time-loaded chunks default to dirty; lights up within ≤4 frames (~67 ms at 60 FPS), acceptable since usually off-screen.
- **Falling-sand splashes** — fluid-move code calls `mark_chunk_dirty` for source and destination chunks. Per-chunk granularity makes repeat marks free.
- **Tick stepping at 4-frame cadence** — masked in practice by bilinear upscaling. Optional mitigation: blend previous-tick and current-tick textures in the overlay (one extra sample + mix). Off by default.
- **Grid size explosion** — `max_grid_cells` cap; if exceeded, skip the tick and log a warning. Should never trigger at R1 with a sane chunk window.

---

## Testing

### Unit-style (headless)

- `register_chunk` allocates the expected buffer size for a given chunk dimension and `cell_size`.
- `mark_chunk_dirty` flips the flag; `_tick()` clears it.
- Single-pixel splat: one lava pixel at known coord → exactly one grid cell receives `tint_color * glow * intensity_k`; neighbors zero.
- Separable blur: single-cell impulse → energy-conserving and symmetric output.
- AABB recompute: load `{(0,0),(1,0)}`, add `(2,0)` → new buffer has old caches blitted at correct offsets.

### Visual smoke tests

1. Empty cave, no lava — screen at ambient floor; player carry-light works.
2. Single lava pixel in dark room — orange smudge ~5 cells across, soft falloff, no square edges.
3. Lava pool — surrounding stone visibly orange within ~half a tile, fading to black.
4. Falling lava blob — glow follows cells without gaps; source dims as lava leaves.
5. Player walks past lava — carry-light + grid sum naturally; no banding.
6. Camera pans fast — glow stays glued to world position; no visible swimming beyond 4-frame step.
7. `LightingManager.enabled = false` mid-game — overlay hides instantly; re-enabling restores.

### Perf

`_tick()` budget: <1 ms with a typical 5×5 chunk window and a few hundred dirty emitter pixels. Per-frame cost outside ticks: just the overlay shader.

---

---

## Implementation amendment — G1 GPU pipeline (2026-04-29)

The original architecture above assumed CPU-side accumulation by walking each dirty chunk's cells. This is incompatible with the project's reality: chunk cells live in GPU `RID` textures (`Chunk.rd_texture`, RGBA8) driven by compute shaders in `shaders/compute/simulation.glsl`. CPU-walking would require `RenderingDevice.texture_get_data` per dirty chunk every tick — a synchronous GPU→CPU readback that stalls the pipeline.

The accumulation, compose, and blur are therefore moved entirely to the GPU. Everything else in the spec is unchanged: same R1 cell size, same K3 kernel, same overlay integration, same X1 additive composition, same `tint_color × glow` rule, same console command surface.

### Pipeline (replaces "Architecture" steps 1–4 above)

1. **Emission reduce** (compute) — for every loaded chunk, dispatch `emission_reduce.glsl`. Input: chunk's `rd_texture`. Output: a per-chunk **emission tile** texture sized `(CHUNK_SIZE/4) × (CHUNK_SIZE/4)` (= 64×64) in `RGBA16F`. Each invocation handles one 4×4 block: loads 16 cells, decodes material id with `get_material(pixel)`, sums `MATERIAL_TINT[m].rgb * MATERIAL_GLOW[m]` over the block, writes to the tile cell.
2. **Compose** (compute) — `light_compose.glsl`. Inputs: an array of chunk emission tiles + their grid offsets. Output: the main **light grid texture** sized to the loaded-chunk AABB, `RGBA16F`. Implementation: dispatch one compute pass per loaded chunk that copies its emission tile into the corresponding region of the main grid (or one big pass that maps each grid cell to the owning chunk tile).
3. **Blur** (compute) — `light_blur.glsl`. Two dispatches: horizontal pass (main grid → scratch), then vertical (scratch → main grid). 11-tap Gaussian, weights as `const float[]` in the shader.
4. **Sample** (canvas shader) — the main grid is exposed as a `Texture2DRD` global shader parameter (`light_grid_tex`) plus a `vec4 light_grid_world_rect` uniform. The overlay `ColorRect` shader samples it bilinearly each frame in world space and additively blends.

### Material data path

`MATERIAL_TINT[]` and `MATERIAL_GLOW[]` are already auto-generated into `shaders/generated/materials.glslinc` by `tools/generate_material_glsl.gd`. The new compute shader simply `#includes` that file — no runtime LUT buffer needed.

### Dirty tracking simplification

Re-reducing every loaded chunk every tick is cheap on GPU (a 5×5 chunk window = 25 chunks × 256² = 1.6M invocations every 4 frames, sub-millisecond on modern GPUs) **and** is necessary anyway because the falling-sand simulation moves emitter cells inside chunks each frame without informing the CPU. So G1 drops the "dirty-chunk lazy" optimization from the original spec — every loaded chunk's emission tile is recomputed each tick. This is simpler, more correct, and still well under budget.

### Resources owned by `LightingManager` (replaces "Components" `LightingManager` body)

- `emission_pipeline`, `compose_pipeline`, `blur_pipeline` — compute pipelines.
- `emission_tiles : Dictionary[Vector2i → RID]` — per-chunk emission tile textures.
- `main_grid_tex : RID`, `scratch_grid_tex : RID` — RGBA16F textures sized to current loaded-chunk AABB.
- `main_grid_2d : Texture2DRD` — wrapper exposed to canvas shaders.
- `loaded_aabb : Rect2i` — current AABB in chunk coords.

### Tick cadence

Frame counter; runs the four-phase pipeline every `tick_interval` frames (default 4). The overlay always samples the most recent `main_grid_tex`.

### Hooks (replaces "Hooks into existing code" body)

- `chunk_manager.gd::create_chunk` calls `LightingManager.register_chunk(chunk)`. `chunk_manager.gd::unload_chunk` calls `LightingManager.unregister_chunk(chunk)`.
- No terrain-mutation hooks needed (re-reduce-everything model).
- `material_registry.gd`: add `is_emitter` helper as before (used by tests, not the GPU pipeline).

### Memory ballpark (revised)

- Per-chunk emission tile: 64 × 64 × 8 bytes (RGBA16F) = 32 KB per chunk × 25 chunks = **800 KB**.
- Main grid + scratch (5×5 chunks → 320×320 cells): 320² × 8 × 2 = **640 KB**.
- Total: ~1.4 MB. Same order as the original CPU plan.

### What stays unchanged from the original design

Spec Sections 1–4 ("Problem", "Goals", "Non-goals", "Requirements") are unchanged. The "Edge cases", "Testing", and "Future extensions" sections still apply with one substitution: anywhere the test plan mentions "single-cell impulse splat", read it as "single emitter pixel reduces to exactly one tile cell with `tint_color × glow * (1/16)`" (the 1/16 factor is the 4×4 block average; intensity_k absorbs it).

---

## Future extensions (out of scope now)

- Splitting `tint_color` from a separate `emission_color` if a future material needs decoupled surface tint and emission.
- Light2D-occluded variant (option C from the original menu) if specific gameplay scenarios need real shadowing.
- Feeding the grid into entity material shaders directly (I2-style integration) instead of the additive overlay, if the overlay's "lights everything in front of dark walls" look becomes a problem.
- Temporal blend in the overlay shader to fully hide the 4-frame tick step.
