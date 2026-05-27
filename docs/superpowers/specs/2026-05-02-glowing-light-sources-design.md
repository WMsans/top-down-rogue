# Glowing Material Light Sources Design

**Date:** 2026-05-02
**Status:** Approved

## Overview

Currently, glowing materials (lava, coal) use a `MATERIAL_GLOW[]` multiplier in the render shader to appear self-illuminated, but there are no actual Godot light sources illuminating surrounding terrain. This design adds `PointLight2D` nodes driven by a compute shader pass that aggregates glowing pixels per chunk into light sources.

## Design Decisions

| Decision | Choice |
|----------|--------|
| Which materials emit light | Any material with `MATERIAL_GLOW > 1.0` (currently LAVA=10, COAL=20) |
| Aggregation method | Simple count + average position per 64x64 cell |
| Update frequency | Dispatch every ~5 frames; readback distributed across those frames (see §3) |
| Shader glow vs Godot lights | Both layers coexist — shader glow for self-illumination, PointLight2D adds light to the scene under the existing CanvasModulate-style ambient darkness |
| Light range | Fixed per light, configurable (default 64px) |
| Light energy | Scales with `pixel_count` (saturates above ~half-cell coverage) × average glow factor |
| Shadows | Disabled — too expensive at 16 lights/chunk |
| Smooth interpolation | Linear lerp in `_process`, frame-rate independent (exponential decay) |
| Light texture | Default PointLight2D circle falloff |
| Average-position ghost lights | Accepted limitation — two separated blobs in one cell collapse to one light at their midpoint |

## Architecture

### 1. Compute Shader: `light_pack.glsl`

New compute pipeline that scans each chunk's GPU texture for glowing pixels.

**Dispatch:** 16 workgroups per chunk (4x4 grid), each workgroup 8x8 threads.
Each workgroup scans one 64x64 cell. Each thread scans 8x8 pixels locally, accumulates in registers, parallel-reduces via shared memory.

**Inputs:**
- Binding 0: chunk RD texture (256x256 RGBA8)
- `MATERIAL_GLOW[]` is **codegen'd into the GLSL source** (matches existing `simulation.glsl` / `generation.glsl` pattern in `compute_device.gd:73`). No materials UBO binding.
- Push constant: `chunk_coord` (ivec2)

**Output SSBO (packed):** 16 entries × 8 bytes = **128 bytes per chunk** (halved from initial 256B design):
```
struct LightCell {
    uint packed_count_glow;   // pixel_count (16 bits) | avg_glow_q8 (16 bits, fixed-point glow÷max × 65535)
    uint packed_pos;          // avg_x (16 bits) | avg_y (16 bits), already-divided in shader
};
```
Averaging happens in-shader (final thread divides sums by count) so CPU only reads the four small values it needs. Bounds: pixel_count max 4096 (fits 16 bits), coords 0–255 (fit 16 bits trivially).

**Overflow note:** intermediate `sum_glow` uses uint accumulator; max ≈ 4096 × MATERIAL_GLOW(20) × 1000 = 82M. Safe for any glow ≤ ~1M.

**Threshold:** cells with `pixel_count < 4` produce `packed_count_glow = 0` (avoids speck lights).

### 2. Light Node Manager: `src/core/chunk_lights.gd`

Per-chunk component managing up to 16 `PointLight2D` nodes.

**Lifecycle:**
- 16 PointLight2D nodes pre-allocated at chunk creation, parented under a `Lights` Node2D (z=2), all hidden by default
- At 12Hz: SSBO read back, lights positioned/energized for active cells, empty cells hidden
- No runtime create/destroy — avoids allocation spikes

**Light properties:**
- `shadow_enabled = false`
- `blend_mode = ADD`
- `texture_scale = range / default_texture_radius` (a unit-radius texture is pre-baked at init; `range` is the configurable value, default 64px)
- `light_mask` matches the bits used by `FloorMesh` and `WallMesh` so the terrain is illuminated. Verify mask values when wiring up.
- `color` derived from material tint (LAVA = orange-red, COAL = near-white)
- `energy = clamp(pixel_count / 32.0, 0.0, 1.0) * (avg_glow / MAX_GLOW)` — saturates above ~half-cell coverage so a large pool isn't equivalent to a speck

**Smooth interpolation:**
- Two arrays: `target_positions[16]` / `target_energies[16]` (set from SSBO at 12Hz) and `current_positions[16]` / `current_energies[16]` (lerped every frame)
- `_process` uses exponential decay: `lerp(current, target, 1.0 - exp(-smooth_speed * delta))`
- `smooth_speed` defaults to 30 (~95% convergence in 100ms)
- Empty cells fade out smoothly as energy decays to 0

**Scene tree:**
```
Chunk (Node2D)
  ├── FloorMesh (MeshInstance2D, z=0)
  ├── WallMesh (MeshInstance2D, z=1)
  └── Lights (Node2D, z=2)
        ├── PointLight2D [0]
        ├── PointLight2D [1]
        └── ... (16 total)
```

### 3. Compute Device Integration

**Modifications to `src/core/compute_device.gd`:**

**Pipeline setup (one-time init):**
- Compile `light_pack.glsl` → SPIR-V
- Create `light_pack_pipeline: RID` via `RenderingDevice.compute_pipeline_create()`

**Per-chunk state (added to chunk creation):**
- `light_pack_uniform_set: RID` — binds chunk RD texture only (materials are codegen'd)
- `light_output_buffer: RID` — 128-byte SSBO

**Dispatch + distributed readback (5-frame rotation):**

A chunk's full update spans 5 frames. The dispatch is single-frame; the readback is split across the next 4 frames so we never read all visible chunks in the same frame.

```
frame N (dispatch frame, every 5th frame per chunk):
    rd.compute_list_begin()
    for each visible chunk in this phase's bucket:
        bind light_pack_pipeline + chunk uniform set
        push chunk_coord, dispatch (4,4,1)
    rd.compute_list_add_barrier()
    rd.compute_list_end()
    rd.submit()  # results available next frame

frame N+1 .. N+4 (drain frames):
    read 1/4 of the bucket's SSBOs via buffer_get_data()
    push results into ChunkLights for those chunks
```

Chunks are bucketed by `(chunk_id % 5)` so each frame dispatches one bucket and drains a slice of older buckets — readback work per frame is roughly `visible_chunks / 5 × 128 bytes` instead of a single-frame burst. This also gives readback a full extra frame of GPU latency to complete before the CPU stalls on `buffer_get_data`.

**Synchronization with terrain edits:** `terrain_modifier.gd` writes to the same chunk texture. Existing pattern in `compute_device.gd` issues all dispatches under a single `compute_list_begin/end` with explicit `compute_list_add_barrier` between read/write phases (see `compute_device.gd:307`). The light_pack dispatch must be queued in the **same compute list** as the simulation pass and follow a barrier, so the texture state is consistent. **TODO during implementation:** confirm `terrain_modifier.gd`'s CPU-driven texture updates also flush before the light_pack dispatch fires (image upload happens via `texture_update`, which is queued on the rendering thread).

**Culling:** Only chunks in camera view + 1 border chunk are processed.

### 4. Material Color Configuration

Lights use the material tint already in `MaterialRegistry`:
- LAVA `(0.9, 0.4, 0.1)` → PointLight2D.color = orange-red
- COAL `(0.12, 0.12, 0.14)` → PointLight2D.color = near-white (ember-hot)

The `MATERIAL_GLOW[]` array in generated GLSL determines whether a pixel is considered "glowing" (`glow > 1.0`).

**Configurable per-material overrides (future):** `light_range_overrides = {MAT_LAVA: 80, MAT_COAL: 48}` in `MaterialRegistry`.

### 5. Performance Profile

| Metric | Value |
|--------|-------|
| Lights per chunk (max) | 16 |
| Workgroups per chunk | 16 (4×4 × 8×8 threads each) |
| SSBO size per chunk | 128 bytes |
| Dispatch cadence | every 5 frames per chunk (~12Hz) |
| Readback distribution | 1/5 of visible chunks read per frame |
| GPU→CPU readback | 128 bytes/chunk/update; ~25 chunks × 128B / 5 ≈ 640 B/frame |
| Frame latency | 1–2 frames dispatch→read; perceived lag up to ~80–180 ms (acceptable) |
| Light count ceiling | ~400 (25 chunks × 16), but most cells dark in practice |
| **TODO: measure** | dispatch wall-time and `buffer_get_data` stall on integrated GPU baseline |

## Files Changed

| File | Action |
|------|--------|
| `shaders/compute/light_pack.glsl` | **New** — light aggregation compute shader |
| `src/core/chunk_lights.gd` | **New** — PointLight2D manager per chunk |
| `src/core/compute_device.gd` | **Modify** — add light_pack pipeline, per-chunk buffers, dispatch |
| `src/core/chunk.gd` | **Modify** — add `chunk_lights` member, cleanup in free |
| `src/core/chunk_manager.gd` | **Modify** — instantiate ChunkLights at chunk creation |
| `src/core/world_manager.gd` | **Modify** — trigger light updates at 12Hz cadence |

## Edge Cases

- **No glowing pixels in chunk:** All 16 lights disabled. Skip dispatch (detectable via CPU-side flag).
- **Chunk not yet generated:** SSBO is zeroed → no lights.
- **Lights at chunk borders:** A light near chunk edge illuminates neighbor naturally via falloff.
- **Material glow changed at runtime:** Materials are static after init; codegen'd `MATERIAL_GLOW[]` is baked at shader compile time.
- **Chunk edited mid-readback:** The packed result reflects the texture state at dispatch time (frame N). An edit on frame N+1 won't show until the next dispatch (≤5 frames). Acceptable.
- **Chunk unload during in-flight readback:** Mark chunk's pending-read entry as cancelled; skip `buffer_get_data` for it; free SSBO + uniform set + ChunkLights node after the drain frame passes.
- **Two separated lava blobs in one cell:** Average position produces a single ghost light at the midpoint. Accepted limitation — cells are 64px so the visual error is bounded.
