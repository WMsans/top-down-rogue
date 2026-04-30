# Lava Dynamic Lighting — Design

**Date:** 2026-04-29
**Status:** Approved (brainstorming phase)
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

## Future extensions (out of scope now)

- Splitting `tint_color` from a separate `emission_color` if a future material needs decoupled surface tint and emission.
- Light2D-occluded variant (option C from the original menu) if specific gameplay scenarios need real shadowing.
- Feeding the grid into entity material shaders directly (I2-style integration) instead of the additive overlay, if the overlay's "lights everything in front of dark walls" look becomes a problem.
- Temporal blend in the overlay shader to fully hide the 4-frame tick step.
