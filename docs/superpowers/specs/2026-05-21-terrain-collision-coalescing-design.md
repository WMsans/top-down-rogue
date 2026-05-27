# Terrain Collision Coalescing & Async Readback

**Date:** 2026-05-21
**Status:** Approved design, pending plan

## Problem

Profiling shows `TerrainCollisionHelper.rebuild_dirty` consumes 28.21ms per spike, with `rebuild_chunk_collision_gpu` at 28.17ms across 4 calls and `TerrainCollider.create_occluder_polygons` adding 8.36ms. Frame time is 37.33ms — well above the 16.6ms / 60 FPS target. The spike repeats every 0.2s (the `COLLISION_REBUILD_INTERVAL`).

Root causes:

1. **Synchronous GPU readback.** Each of 4 chunks calls `rd.buffer_get_data` on its own SSBO, stalling the CPU while the GPU drains. The light pipeline solved this same problem in commits `245a8bd`..`0ae913c` by coalescing into a single SSBO read one frame later.
2. **Per-call `uniform_set_create`.** Each rebuild rebuilds its uniform set instead of reusing a persistent per-chunk set.
3. **Per-call `compute_list_begin/end`.** Four separate compute lists where one would do.
4. **No dirty tracking.** `rebuild_dirty` round-robins through *all* visible chunks every interval, even when nothing changed.
5. **Occluder polygon construction in lockstep with collision.** 8ms of CPU geometry + `LightOccluder2D` allocation runs on the same frame as physics shape rebuild instead of being amortized.

## Goal

Drive frame time to ≤16.6ms (60 FPS) in the editor under the same scene used for the profile. Target steady-state cost of terrain collision rebuild at ~0ms when nothing dirty, and ≤5ms worst-case when 4 chunks burst-dirty.

## Non-goals

- Moving occluder polygon simplification to the GPU.
- Changing the collision shape format or the `TerrainCollider.build_from_segments` algorithm.
- Improving collision latency below "≥0.2s acceptable". The user has confirmed loose latency is fine.

## Architecture

Two cooperating objects mirror the light pipeline already in the codebase.

### `TerrainCollisionHelper` (existing, rewritten)

Owns the CPU side: dirty set, dispatch selection, async readback consumption, occluder amortization.

State:

- `_dirty_chunks: Dictionary` — keys are `Vector2i` chunk coords; used as a set.
- `_in_flight: Array[Vector2i]` — chunk coords dispatched on frame N, to be read on frame N+1. Index in array = slot index in the coalesced SSBO.
- `_pending_collision_builds: Array[Vector2i]` — drained fully each frame.
- `_pending_occluder_builds: Array[Vector2i]` — at most one drained per frame.
- `_dispatch_cursor: int` — round-robin index across `_dirty_chunks` for fairness.

Public API:

- `mark_dirty(coord: Vector2i) -> void`
- `rebuild_dirty(chunks: Dictionary, delta: float) -> void` — call per `_process` frame. Steps: (1) consume prior frame's readback, (2) drain one occluder build, (3) drain all collision builds, (4) dispatch up to `MAX_DISPATCH_PER_FRAME` newly-selected dirty chunks.
- `on_chunk_unloaded(coord: Vector2i) -> void` — purges `_dirty_chunks`, `_in_flight`, and pending queues for that coord.

The existing `rebuild_chunk_collision_cpu` is preserved as the failure fallback.

### `ComputeDevice` (additions)

Owns the GPU side. New state:

- `collider_coalesced_buffer: RID` — single SSBO sized for all slots.
- `MAX_DISPATCH_PER_FRAME = 4`, `MAX_SEGMENTS_PER_CHUNK = 1024` (constants).

New methods:

- `dispatch_collider_pack(chunks: Dictionary, coords: Array[Vector2i]) -> void` — clears all slot headers, opens one compute list, binds each chunk's persistent uniform set, pushes the slot index, dispatches `16×16×1`, closes the list.
- `read_collider_buffer_coalesced(coords: Array[Vector2i]) -> Dictionary` — single `buffer_get_data`, decodes per-slot `(segment_count, segments)`, returns `Dictionary[Vector2i, PackedVector2Array]`.

### `chunk_manager.gd` (addition)

When a chunk is created (alongside existing `light_pack_uniform_sets`), build one persistent uniform set per chunk binding `(chunk.rd_texture @ binding 0, collider_coalesced_buffer @ binding 1)`. Store on `chunk.collider_uniform_set`. Free in chunk unload alongside the texture.

### GPU layout (coalesced SSBO)

```
Slot layout, repeated MAX_DISPATCH_PER_FRAME times:

  offset 0:     u32 segment_count
  offset 4:     u32[4 * MAX_SEGMENTS_PER_CHUNK]   // packed (x1, y1, x2, y2) per segment
  slot stride = 4 + 16 * MAX_SEGMENTS_PER_CHUNK = 16388 bytes (round up to 16-byte align)

Total size = MAX_DISPATCH_PER_FRAME * slot_stride ≈ 64 KB
```

### Shader change (`shaders/compute/collider.glsl`)

Add a small push constant:

```glsl
layout(push_constant, std430) uniform Params { uint slot_index; uint _pad0; uint _pad1; uint _pad2; } pc;
```

Replace direct writes to `segments_out[...]` with offset writes into the slot:

```glsl
uint slot_offset_u32 = pc.slot_index * (1 + 4 * MAX_SEGMENTS_PER_CHUNK);
// header at slot_offset_u32, segments at slot_offset_u32 + 1
```

`atomicAdd` on segment_count remains scoped to the slot's header word.

## Frame flow

In `world_manager._process`:

```
1. readback = compute_device.read_collider_buffer_coalesced(helper._in_flight)
   helper._in_flight = []
   for each (coord, segments) in readback:
       helper._pending_collision_builds.append(coord)
       helper._pending_occluder_builds.append(coord)
       helper._pending_segments[coord] = segments

2. helper.drain_one_occluder()
3. helper.drain_all_collision_builds()

4. dispatch_coords = helper._select_dispatch_candidates()  # up to 4 from _dirty_chunks
   if dispatch_coords:
       compute_device.dispatch_collider_pack(chunks, dispatch_coords)
       helper._in_flight = dispatch_coords
       for c in dispatch_coords: helper._dirty_chunks.erase(c)
```

When `_dirty_chunks` is empty and nothing is in flight or pending, the entire path is zero-cost beyond a dictionary `is_empty()` check.

## Dirty tracking

Mark sites — every place that writes to `chunk.rd_texture`:

- `terrain_modifier.gd`: after each `rd.texture_update` call. Each modifier function already has the affected `chunk` in scope; add one `world_manager.mark_terrain_dirty(chunk.coord)` line per site (5+ sites in this file).
- `chunk_manager.gd`: after initial generation completes for a chunk, mark dirty so first-time collision builds.
- `compute_device.gd`: any compute that writes terrain (terrain damage at ~317, ~733) — after dispatch, iterate the chunk list and mark dirty.

`world_manager.mark_terrain_dirty(coord)` is a thin forwarder to `_collision_helper.mark_dirty(coord)`.

### Latency guarantee

A chunk dirtied during frame N is collision-correct by end of frame N+2 (dispatched N+1, read+built N+2). Occluder may lag up to `MAX_DISPATCH_PER_FRAME - 1` additional frames in worst-case burst. All well inside the loose latency requirement.

## Occluder amortization

`create_occluder_polygons` + `LightOccluder2D` instancing accounted for 8.36ms across 4 chunks. Split from collision shape construction:

- Collision shapes are cheap to build (`build_from_segments` was 2ms for 4 chunks) — drain the full `_pending_collision_builds` queue each frame.
- Occluder builds are throttled to **one chunk per frame** via `_pending_occluder_builds`. Worst case for a 4-chunk burst: 4 frames (~66ms) before occluders are fully caught up. Imperceptible for light shadows.

Old occluder cleanup (`occluder_instances.queue_free()`) moves to immediately before the replacement is added for that chunk, preventing visual flicker.

## Failure handling

- If the GPU dispatch fails (e.g. invalid RID), helper falls back to `rebuild_chunk_collision_cpu` for that chunk and removes it from `_in_flight`.
- If a chunk is unloaded between dispatch and readback, the readback for that slot is discarded. `on_chunk_unloaded` is called from `chunk_manager.gd` chunk teardown.
- `MAX_SEGMENTS_PER_CHUNK` exceeded: shader's `atomicAdd` saturates at the cap, helper logs a `push_warning` once per chunk per session, and uses whatever segments were captured. This degrades gracefully — collision is slightly under-detailed, not broken.

## Components & dependencies

```
TerrainCollisionHelper
  ├── depends on → ComputeDevice (dispatch_collider_pack, read_collider_buffer_coalesced)
  ├── depends on → TerrainCollider (build_from_segments, create_occluder_polygons, build_collision)
  └── consumed by → WorldManager._process

ComputeDevice
  ├── owns → collider_coalesced_buffer
  ├── owns → collider_shader (modified)
  └── reads → Chunk.collider_uniform_set (built by ChunkManager)

ChunkManager
  └── creates → Chunk.collider_uniform_set on chunk_create, frees on chunk_unload

Mark sites (call WorldManager.mark_terrain_dirty)
  ├── terrain_modifier.gd (5+ sites)
  ├── chunk_manager.gd (post-generation)
  └── compute_device.gd (post-terrain-damage dispatches)
```

## Testing

### Unit-ish (helper in isolation, mock ComputeDevice)

- `mark_dirty(coord)` adds to set; duplicates are idempotent.
- `rebuild_dirty` with empty `_dirty_chunks` and empty `_in_flight` does no work (no compute calls, no readback).
- Round-robin: dispatch 8 dirty chunks with `MAX_DISPATCH_PER_FRAME = 4` over two frames; assert every chunk is dispatched exactly once and order is fair.
- `on_chunk_unloaded(coord)` removes from `_dirty_chunks`, `_in_flight`, and both pending queues.
- Occluder queue throttle: 4 chunks readback simultaneously → only 1 occluder built per frame, all 4 collision shapes built same frame.

### Integration (real RenderingDevice)

Existing test scene. Dirty 4 chunks via `mark_terrain_dirty` in one frame, step 3 frames, then:

- Assert each chunk's `static_body` has exactly one `CollisionShape2D` child.
- Compare the GPU-built shape's segment count and bounding box against `rebuild_chunk_collision_cpu` output for the same texture data (oracle).
- After 4 additional frames, assert all 4 chunks have populated `occluder_instances`.

### Perf verification (manual)

Re-run the profiling scene from the bug report. Confirm:

- `rebuild_chunk_collision_gpu` no longer appears in the top 5 hotspots.
- Frame time ≤16.6ms during steady gameplay.
- 60 FPS sustained in editor.

## Open knobs

- `MAX_DISPATCH_PER_FRAME = 4` — matches today's `COLLISIONS_PER_FRAME`. Tunable downward if burst cost still exceeds budget.
- `MAX_SEGMENTS_PER_CHUNK = 1024` — sized from current worst-case. If `push_warning` fires in practice, raise and reallocate SSBO.
- `COLLISION_REBUILD_INTERVAL = 0.2` is **removed**. With dirty tracking, we dispatch as soon as something is marked, not on a fixed cadence.
