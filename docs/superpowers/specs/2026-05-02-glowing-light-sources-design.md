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
| Update frequency | Every ~5 frames (~12Hz at 60fps) |
| Shader glow vs Godot lights | Both layers coexist — shader glow for self-illumination, PointLight2D for surrounding illumination |
| Light range | Fixed per light, configurable (default 64px) |
| Light energy | Proportional to average glow intensity in cell |
| Shadows | Disabled — too expensive at 16 lights/chunk |
| Smooth interpolation | Linear lerp in `_process`, frame-rate independent (exponential decay) |
| Light texture | Default PointLight2D circle falloff |

## Architecture

### 1. Compute Shader: `light_pack.glsl`

New compute pipeline that scans each chunk's GPU texture for glowing pixels.

**Dispatch:** 16 workgroups per chunk (4x4 grid), each workgroup 8x8 threads.
Each workgroup scans one 64x64 cell. Each thread scans 8x8 pixels locally, accumulates in registers, parallel-reduces via shared memory.

**Inputs:**
- Binding 0: chunk RD texture (256x256 RGBA8)
- Binding 1: materials uniform buffer (for `MATERIAL_GLOW[]` array)
- Push constant: `chunk_coord` (ivec2)

**Output SSBO:** 16 entries × 4 uints = 256 bytes per chunk:
```
struct LightCell {
    uint pixel_count;   // number of glowing pixels in this 64x64 cell
    uint sum_x;         // sum of x coordinates (for averaging)
    uint sum_y;         // sum of y coordinates (for averaging)
    uint sum_glow;      // sum of MATERIAL_GLOW × 1000 (fixed-point)
};
```

**Threshold:** cells with `pixel_count < 4` produce no light (avoids speck lights).

### 2. Light Node Manager: `src/core/chunk_lights.gd`

Per-chunk component managing up to 16 `PointLight2D` nodes.

**Lifecycle:**
- 16 PointLight2D nodes pre-allocated at chunk creation, parented under a `Lights` Node2D (z=2), all hidden by default
- At 12Hz: SSBO read back, lights positioned/energized for active cells, empty cells hidden
- No runtime create/destroy — avoids allocation spikes

**Light properties:**
- `shadow_enabled = false`
- `blend_mode = ADD`
- `texture_scale = range / texture_size`
- `color` derived from material tint (LAVA = orange-red, COAL = near-white)

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
- `light_pack_uniform_set: RID` — binds chunk RD texture + materials buffer
- `light_output_buffer: RID` — 256-byte SSBO
- `light_output_staging: PackedByteArray` — CPU-side readback staging (256 bytes)

**Dispatch loop (every ~5 frames, for visible chunks):**
```
for each visible chunk:
    if chunk_needs_light_update:
        dispatch light_pack_pipeline (16 workgroups)
barrier (compute → host)
for each chunk:
    read SSBO to staging buffer
    emit signal / pass data to ChunkLights
```

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
| SSBO size per chunk | 256 bytes |
| Update frequency | ~12Hz |
| GPU→CPU readback | 256 bytes/chunk/update |
| Frame latency | 1 frame (from GPU readback) |
| Light count ceiling | ~400 (25 chunks × 16), but most cells dark in practice |

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
- **Material glow changed at runtime:** Unlikely (materials static after generation), but uniform buffer is always current.
- **Chunk unload:** Free SSBO, uniform set, and destroy ChunkLights node alongside other chunk resources.
