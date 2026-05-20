# Coalesced + Double-Buffered Light Output SSBO

**Goal:** Eliminate the GPU→CPU readback stall in `_update_lights` so the editor frame time clears 16.66 ms (60 FPS) with headroom.

## Context

Current profile (editor, 12 active light chunks, 101 enemies):

- Frame time: **17.21 ms** (over the 60 FPS budget)
- `_update_lights`: **4.41 ms**
- `ComputeDevice.read...`: **4.21 ms** across 3 calls / frame

`_update_lights` (`src/core/world_manager.gd:355`) dispatches light-pack compute on 1/5 of active chunks each frame and reads back from 4 older buckets at a rate of 1 slice per bucket, resulting in ~3 calls to `compute_device.read_light_buffer()` per frame. Each call invokes `rd.buffer_get_data()` on a per-chunk `light_output_buffer`, which forces a GPU fence/sync. The per-call submission/fence cost — not the payload size — dominates the 4.21 ms.

The CPU-side readback is required: the decoded cells drive Light2D node generation in `ChunkLights.apply_light_data` *and* are used as a fast pre-filter for enemy-on-lava detection (`hazard_cells`).

The terrain-probe pipeline solved the same class of problem in commit `855348d` ("perf(terrain): double-buffer probe SSBOs to remove sync stall") using a double-buffered output SSBO. This design applies the same pattern, additionally **coalescing** all per-chunk outputs into a single shared SSBO so there is at most one `buffer_get_data` call per frame.

## Approach

Replace per-chunk `light_output_buffer` with **two shared output SSBOs** sized for the maximum simultaneously-active chunks. The compute shader writes into a chunk-indexed slice of the active buffer. CPU reads the other buffer — which holds the previous dispatch cycle's results and is GPU-idle.

### Data Flow

```
Frame N:
  dispatch bucket[N % 5] → writes into shared_buffer[N % 2],
                          slices recorded in manifest[N % 2]
  read shared_buffer[(N - 1) % 2] → decode using manifest[(N - 1) % 2]
                                  → apply to ChunkLights + hazard_cells
```

A chunk dispatched at frame N is read no earlier than frame N+1, after the buffer-index flip. The existing 1/5 bucketed dispatch cadence is preserved.

## Components

### `compute_device.gd`

- New fields:
  - `light_output_buffers: Array[RID]` — size 2, each `MAX_ACTIVE_CHUNKS * LIGHT_OUTPUT_SIZE` bytes.
  - `light_write_index: int` — 0/1, toggled after each dispatch frame.
  - `light_dispatch_manifest: Array[PackedInt32Array]` — size 2; entries are flat `[chunk_x, chunk_y, slice_idx, ...]` recorded per dispatch cycle.
  - `light_first_frame: bool` — guards the read on frame 0 (mirrors `terrain_probe_first_frame`).
- `dispatch_light_pack(chunks, bucket_coords)`:
  - Clears `light_dispatch_manifest[light_write_index]`.
  - For each chunk in `bucket_coords`, assigns a `slice_idx` (its index within the bucket), records `(coord, slice_idx)` into the manifest, binds the uniform set associated with `light_write_index`, sets the push constant `(chunk_x, chunk_y, slice_idx)`, and dispatches.
  - Does **not** flip `light_write_index` here — the flip happens after the matching read (see `read_light_buffer_coalesced`).
- `read_light_buffer_coalesced() -> Dictionary`:
  - Returns `{}` on the first frame.
  - Reads `light_output_buffers[1 - light_write_index]` once via `rd.buffer_get_data`, sized to `manifest_length * LIGHT_OUTPUT_SIZE`.
  - Returns `{ "bytes": PackedByteArray, "manifest": PackedInt32Array }`.
  - Flips `light_write_index` so the next dispatch targets the buffer just consumed.
- `decode_light_ssbo_slice(bytes: PackedByteArray, slice_idx: int) -> Array[Dictionary]`: existing decode logic, offset by `slice_idx * LIGHT_OUTPUT_SIZE`.

### `Chunk`

- Remove the per-chunk `light_output_buffer` allocation and the RID field.
- Keep `light_pack_uniform_set`. Replace the single field with `light_pack_uniform_sets: Array[RID]` of size 2 — one uniform set per output-buffer index. Both bind the same per-chunk input texture and biome data but differ in the bound `light_output_buffers[i]`.

### `shaders/light_pack.glsl` (or current equivalent)

- Extend the push constant struct to include `slice_idx: u32`.
- Replace `output[cell_idx] = ...` with `output[slice_idx * 16u + cell_idx] = ...`.

### `world_manager.gd::_update_lights`

- Dispatch path: unchanged in structure — still cycles through the 5 buckets — but now calls a single `compute_device.dispatch_light_pack(chunks, bucket)` that internally writes into the shared SSBO.
- Readback path collapses from "iterate 4 buckets × slice" to:
  1. `var readback = compute_device.read_light_buffer_coalesced()`.
  2. If empty, return.
  3. Walk the manifest; for each `(coord, slice_idx)`, decode the slice and apply to `chunk.chunk_lights` and `chunk.hazard_cells` as today.
- Remove `_light_readback_counter` and the 4-bucket-slice fan-out logic; they're no longer needed.

## Sizing

- `MAX_ACTIVE_CHUNKS = 32` (observed peak ~12; 32 gives headroom for future view-distance changes).
- Per buffer: `32 * 16 * 12 = 6 KB`. Two buffers: 12 KB GPU memory. Negligible.

## Edge cases

- **First frame:** `light_first_frame` returns an empty readback (matches `terrain_probe` pattern).
- **Chunk freed between dispatch and read:** the manifest entry's `chunks.get(coord)` returns null; skip that slice (existing guard).
- **Bucket size exceeds `MAX_ACTIVE_CHUNKS`:** clamp the bucket and log a warning; with current bucketing this cannot happen, but guard defensively.
- **Resize / reset (`world_manager.reset`):** zero `light_dispatch_manifest`, set `light_first_frame = true`, leave SSBOs allocated.

## Testing

- **Visual sanity:** Spawn lava in a test arena; confirm Light2Ds appear/fade and lava damages enemies that step into it within the same perceived latency as the current pipeline.
- **Profiler verification:** In the same scene that produced the 4.21 ms reading, confirm `ComputeDevice.read...` drops below 0.5 ms and the frame time clears 16 ms with margin.
- **Regression:** Terrain-probe and melee-hit-list pipelines must remain untouched; run the existing tests under `tests/` that cover those paths.
- **Stress:** Move the camera so all 32 slice positions are used at least once; verify no out-of-bounds writes (validate via Renderdoc capture or by reading the buffer with a known pattern in a debug build).

## Non-goals

- Reworking the 1/5 dispatch cadence. Once the readback fence cost is gone, dispatching all active chunks every frame may become viable, but that is a follow-up.
- Optimizing `_drain_terrain_impact` (0.61 ms) and `play_impact` (0.49 ms / 9 calls). These are the next tier but not required to clear 60 FPS once this lands.
- Threading the readback. Godot 4's RenderingDevice does not support safe off-thread reads.
