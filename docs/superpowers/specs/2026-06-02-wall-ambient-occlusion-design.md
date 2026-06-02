# Ambient Occlusion for Wall Rendering — Design

**Date:** 2026-06-02
**Status:** Approved, pending implementation plan
**Branch:** feat/better-ao

## Overview

Add uniform contact-shadow ambient occlusion (AO) to the terrain renderer, covering
floors, wall faces, and corners. Darkness at a pixel is driven purely by local solid
density — more surrounding solid means darker — which uniformly produces floor contact
shadows, wall-face shading, and (the key feature) darker concave corners. There is no
light direction; the look is "dirt in the creases" and stays correct as the destructible
cellular world changes.

All AO is computed inside a single shader, `shaders/visual/render_chunk.gdshader`, which
already has access to the chunk solidity texture. No new nodes and no new data plumbing
are required. A hard cap of **8 new texture samples** applies to any pixel.

## Context: current rendering architecture

- **Floor** is drawn by a separate node tree, `FloorContainer` → `FloorChunk` (a tiled
  `Sprite2D`), at `z_index = -10` (`src/core/world_manager.gd:33`). It has no access to
  terrain solidity data.
- **Chunk geometry** is drawn by two `MeshInstance2D` quads per chunk, both running
  `render_chunk.gdshader` over the chunk solidity texture (`src/core/chunk_manager.gd:77-108`):
  - `mesh_instance`, `layer_mode = 1`, `z_index = 0` — fake-3D vertical wall faces,
    extruded downward into air.
  - `wall_mesh_instance`, `layer_mode = 0`, `z_index = 1` — flat tops/caps of solid cells.
- Both chunk quads cover the full 256×256 chunk and sit **above** the floor (`z = -10`),
  using the default canvas_item `mix` blend. On air pixels with no wall face, the faces
  pass currently writes `vec4(0.0)` (transparent) at `render_chunk.gdshader:221-223`.

Because the faces pass already rasterizes every floor pixel and composites over the floor
sprite beneath it, **floor AO is achievable as a pure shader edit** — writing
semi-transparent black there instead of transparent.

### Layer ownership of AO

| Surface | Pass | Pixels |
|---|---|---|
| Floor AO | faces (`layer_mode = 1`) | air pixels with no wall face — composited over the `z=-10` floor |
| Wall-face AO | faces (`layer_mode = 1`) | air pixels that find a wall face |
| Cap AO | caps (`layer_mode = 0`) | `near_air` solid-top pixels |

## Tunable uniforms

Set from `src/core/chunk_manager.gd` on both materials:

- `uniform float ao_strength = 0.6;` — master darkness. `0.0` disables AO entirely; the
  sampling early-out makes it effectively free when off.
- `uniform float ao_reach = 3.0;` — ring radius in px for floor and wall-face AO. Caps use
  the existing radius-3 `near_air` disc (fixed, tight — matches the chosen ~3px reach).

## Sampling core

One shared 8-tap ring function drives floor and wall-face AO:

```
float ring_occlusion(ivec2 center):
    r = round(ao_reach)
    # 4 cardinal taps first
    s = solid_ao(center + (r,0)) + solid_ao(center + (-r,0))
      + solid_ao(center + (0,r)) + solid_ao(center + (0,-r))   # 4 samples
    if s == 0.0: return 0.0          # early reject -> open floor costs only 4 samples
    d = round(ao_reach * 0.7071)     # diagonal taps stay on the ring
    s += solid_ao(center + (d,d))  + solid_ao(center + (-d,d))
       + solid_ao(center + (d,-d)) + solid_ao(center + (-d,-d)) # 4 more samples
    return s / 8.0
```

- Returns occlusion ∈ [0,1] = fraction of the ring that is solid.
- `solid_ao()` is a new helper identical to the existing `is_solid()` **except that
  out-of-bounds returns air, not solid** (see Chunk-edge handling).

## Per-surface integration in `fragment()`

- **Floor AO** — in the `MAT_AIR`, `layer_mode == 1` branch, the `!found_wall` case
  (currently transparent at `:221-223`):

  ```
  occ = ring_occlusion(px)
  base_color = vec4(0.0, 0.0, 0.0, occ * ao_strength)
  ```

  Black with AO alpha composites over the floor via the default `mix` blend. `occ == 0`
  yields alpha 0 — identical to current transparent behavior.

- **Wall-face AO** — in the `found_wall` case, keep the sampled face color, then:

  ```
  occ = ring_occlusion(check_pos)            # check_pos = face's source solid cell
  base_color.rgb *= (1.0 - occ * ao_strength)
  ```

  Sampling around the source cell measures how enclosed that wall is.

- **Cap AO** — refactor `near_air()` into a disc scan returning
  `vec2(any_air, solid_fraction)`. The cull test is unchanged (interior → black). When the
  cap is rendered:

  ```
  rgb *= (1.0 - smoothstep(0.5, 0.85, solid_fraction) * ao_strength)
  ```

  The `smoothstep(0.5, 0.85, ...)` keeps straight edges bright and only darkens concave
  corners. **Zero added samples** — it folds into the disc loop `near_air` already runs.

## Chunk-edge handling

`is_solid()` treats out-of-bounds as **solid** (`render_chunk.gdshader:36`), and AO only
has the north-neighbor texture bound. If AO sampled OOB as solid, every chunk border would
get a false dark seam (a visible grid). AO sampling therefore treats **OOB as air**:

- Floor / wall-face ring: `solid_ao()` returns air for OOB.
- Cap disc: `solid_fraction` counts in-bounds cells only. The cull logic keeps its existing
  OOB=solid semantics, unchanged.

Trade-off: AO within ~3px of a chunk edge is slightly under-darkened where a real wall
continues into the neighbor. This is invisible in practice (walls span chunks; the in-chunk
portion still darkens) and far preferable to border seams.

## Performance

- Maximum **+8** new samples on any pixel — the 8-sample constraint is satisfied.
- **Cap AO adds 0 samples** (folded into the existing `near_air` disc scan).
- **Open floor is held to +4** samples by the cardinal early reject; only pixels near a wall
  pay the full 8.
- All AO taps fall within a ≤6px window of a 256KB `filter_nearest` RGBA8 texture →
  cache-resident, negligible added bandwidth.
- This sits on top of an existing per-pixel budget already at ~28 samples (cap `near_air`
  disc) to ~32 samples (faces wall scan), so the net increase is ~0–25% on affected paths.
- `ao_strength = 0.0` short-circuits the ring to zero cost.

**Caveat:** floor AO is a black-alpha overlay, so where a bright `ChunkLights` light overlaps
a contact shadow the AO reads slightly weaker (2D lights add after). This is consistent with
the uniform look and tunable via `ao_strength`.

## Testing / verification

Fragment shaders are not unit-testable in this project, so:

- **Regression guard:** a gdUnit test that `load()`s `render_chunk.gdshader` and asserts it
  compiles with the new `ao_strength` and `ao_reach` uniforms present. Cheap; catches typos
  and breakage.
- **Visual verification:** run via the Godot MCP and screenshot. Confirm contact shadows at
  wall bases, darker concave corners, no chunk-border seams, and that `ao_strength = 0`
  matches current output.
- Existing `test_floor_chunk` and floor-overlay tests are unaffected (no node changes).

## Files touched

- `shaders/visual/render_chunk.gdshader` — all AO logic (`solid_ao`, `ring_occlusion`,
  refactored `near_air` disc scan, the two uniforms, three integration points).
- `src/core/chunk_manager.gd` — set `ao_strength` / `ao_reach` on both materials (~2 lines each).
- `tests/unit/test_render_chunk_shader.gd` — new compile / uniform-presence guard.

## Out of scope (YAGNI)

- Directional / light-aware AO (explicitly rejected in favor of the uniform look).
- Baking AO into the compute pipeline / a chunk data channel.
- Giving `FloorChunk` its own AO shader.
- Per-surface independent reach controls beyond the single `ao_reach` (+ fixed cap disc).
