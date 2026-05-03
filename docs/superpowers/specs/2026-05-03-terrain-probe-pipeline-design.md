# Terrain Probe Pipeline Design

## Problem

`TerrainPhysical.query(world_pos)` always returns a default empty
`TerrainCell` because its CPU cache (`_grid`) is never populated —
`invalidate_rect` only erases entries; nothing writes them. Two visible
symptoms share this single root cause:

1. **`CaveSpawner` never spawns enemies outside rooms.** Its
   `_has_solid_floor` and `_has_headroom` checks query terrain and
   always see `is_solid = false`, so every candidate is rejected.
2. **Lava deals no damage to the player.** `LavaDamageChecker` queries
   nine cells around the player each physics frame and always reads
   `damage = 0`.

A previous attempt populated `_grid` via `rd.texture_get_data` on full
chunk textures (256 × 256 × 4 = 256 KB per chunk). Per-frame full-chunk
readback caused a severe stall and was abandoned in favour of
marching-cubes collision generation. The new fix must avoid full-chunk
readback.

## Solution Overview

Add a small **GPU probe pipeline** that gathers up to 64 individual cells
per frame from active chunk textures into a 256-byte output SSBO. CPU
reads back the SSBO once per frame and populates a small result cache.
`query()` keeps its current signature; internally it returns the most
recent cached result and registers the cell coord for the next probe
batch.

This decouples readback cost from chunk size: each frame transfers
~256 bytes regardless of how many chunks the call sites span.

**Freshness model.** A query at frame N is dispatched at end of frame N
and readable at frame N+1 (one-frame lag). Both call sites poll on a
stable hot set, so the cache stays warm. Lag is irrelevant for the
spawner (1 Hz tick) and acceptable for lava damage at 60 Hz.

## Components

### New shader — `shaders/compute/terrain_probe.glsl`

Bindings (set 0):

- binding 0: chunk storage image, layout `rgba8` — matches the existing
  `R8G8B8A8_UNORM` chunk texture used by generation and simulation. The
  material id is stored in the red channel (consistent with how
  `WorldManager.read_region` decodes byte 0 of each pixel).
- binding 1: input SSBO, `ivec2[] local_coords`
- binding 2: output SSBO, `uint[] mat_ids`

Push constant: `uint probe_start, uint probe_count`.

Each invocation reads
`uint(round(imageLoad(chunk, local_coords[probe_start + gid]).r * 255.0))`
and writes to `mat_ids[probe_start + gid]`. Workgroup size 8×1×1.
Dispatch `ceil(probe_count / 8)` workgroups per chunk. Threads with
`gid >= probe_count` early-out.

### `ComputeDevice` additions

New fields:

- `terrain_probe_shader: RID`
- `terrain_probe_pipeline: RID`
- `terrain_probe_input_buffer: RID` — `PROBE_BUDGET * 8` bytes (512 B for
  64 probes)
- `terrain_probe_output_buffer: RID` — `PROBE_BUDGET * 4` bytes (256 B
  for 64 probes)

Constants:

- `const PROBE_BUDGET := 64`

New methods:

- `init_terrain_probe()` — load shader, create pipeline, create input
  and output SSBOs. Called from `_ready` analogous to other init calls.
- `dispatch_terrain_probe(chunks: Dictionary, batch: Array) -> void`
  where `batch` is an ordered list of
  `{chunk_coord: Vector2i, local_coords: PackedInt32Array, start: int}`.
  Uploads packed local coords into the input SSBO with a single
  `buffer_update`, opens a compute list, binds the probe pipeline, and
  for each entry creates a per-chunk uniform set bound to the chunk's
  texture + the input/output SSBOs, sets the push constant
  `(start, count)`, and dispatches.
- `read_terrain_probe(byte_count: int) -> PackedByteArray` — wraps
  `rd.buffer_get_data(terrain_probe_output_buffer, 0, byte_count)`.
- Free new RIDs in `free_resources`.

### `TerrainPhysical` rewrite

Replace state:

- Remove `_grid: Dictionary`.
- Add `_result_cache: Dictionary` (`Vector2i → {mat_id: int, frame: int}`).
- Add `_pending_probes: Dictionary` (`Vector2i → true`, used as a set).
- Add `_current_frame: int` (incremented each apply).

Constants:

- `const TTL_FRAMES := 8`

Methods:

- `query(world_pos: Vector2) -> TerrainCell`
  - Compute `cell_pos := Vector2i(floor(world_pos))`.
  - Set `_pending_probes[cell_pos] = true` (dedupes).
  - If `_result_cache.has(cell_pos)` and
    `(_current_frame - entry.frame) <= TTL_FRAMES`, return
    `_cell_from_material(entry.mat_id)`.
  - Else return `TerrainCell.new()` (default — preserves current safe
    behaviour during warmup).
- `prepare_probe_batch() -> Array`
  - Drain up to `PROBE_BUDGET` coords from `_pending_probes`.
  - Bin by chunk coord (`world_coord / CHUNK_SIZE`); skip coords whose
    chunk is not in `world_manager.chunks`.
  - Build an ordered list of entries
    `{chunk_coord, local_coords: PackedInt32Array, world_coords: Array[Vector2i], start: int}`
    where `start` is the offset into the global probe range.
  - Return the list (consumed by `WorldManager._run_terrain_probes`).
- `apply_probe_results(batch: Array, raw_bytes: PackedByteArray) -> void`
  - For each entry, decode the corresponding bytes
    (`mat_id = raw_bytes.decode_u32(start*4 + i*4)` per probe) and write
    `_result_cache[entry.world_coords[i]] = {mat_id, frame: _current_frame}`.
  - Increment `_current_frame`.
- `invalidate_rect(rect: Rect2i)` — keeps current API; erases overlapping
  entries from `_result_cache`. (`_pending_probes` is left alone — those
  cells will be re-queried next frame anyway.)
- `set_center` and `_cell_from_material` unchanged.

### `WorldManager` changes

Insert a step in `_process` between `_collision_helper.rebuild_dirty`
and `_update_lights`:

```
_run_terrain_probes()
```

`_run_terrain_probes()`:

1. `var batch := terrain_physical.prepare_probe_batch()`
2. If `batch.is_empty()` return.
3. Compute total probe count and pack local coords into a
   `PackedByteArray` matching the input SSBO layout.
4. Call `compute_device.dispatch_terrain_probe(chunks, batch)`.
5. `var raw := compute_device.read_terrain_probe(total_count * 4)`
6. `terrain_physical.apply_probe_results(batch, raw)`

No changes to `LavaDamageChecker`, `CaveSpawner`, `TerrainModifier`, or
any other consumer of `query()`.

## Data Flow Per Frame

```
Frame N:
  CPU queries (lava_damage_checker, cave_spawner)
    → query(p) returns cached value (from frame N-1) or default
    → p added to _pending_probes
  WorldManager._process:
    _update_chunks
    _run_simulation
    _collision_helper.rebuild_dirty
    _run_terrain_probes:
      batch = terrain_physical.prepare_probe_batch()  # drain ≤ 64
      compute_device.dispatch_terrain_probe(chunks, batch)
      raw = compute_device.read_terrain_probe(...)    # ~256 B readback
      terrain_physical.apply_probe_results(batch, raw)
    _update_lights
    terrain_physical.set_center
Frame N+1:
  query(p) → cache hit, returns correct TerrainCell
```

## Edge Cases

- **Chunk unloaded between queue and dispatch.** `prepare_probe_batch`
  skips coords whose containing chunk is no longer in
  `world_manager.chunks`. Skipped coords are dropped from
  `_pending_probes`; they will be re-queued by the next `query()` call.
- **Over-budget queue (> 64 unique probes).** `prepare_probe_batch`
  drains up to `PROBE_BUDGET`; remaining entries stay in
  `_pending_probes` and are picked up next frame. Hot sets are expected
  to be ~15–20 cells, so this is only a safety bound.
- **TTL expiry.** A probe not re-queried for `TTL_FRAMES` is treated as
  default by `query()` (cache miss path). Both consumers re-query every
  frame/tick, so genuine hot cells refresh continually.
- **`invalidate_rect`.** Erases overlapping `_result_cache` entries; the
  next `query()` returns default and re-queues. Matches current safe
  behaviour for terrain edits.
- **Empty active chunk set.** `_run_terrain_probes` early-returns when
  the batch is empty (binning naturally produces an empty batch when no
  probes have valid chunks).

## Testing

- **Unit (TerrainPhysical, no GPU):**
  - `query` queues coord and returns default before any
    `apply_probe_results`.
  - After `apply_probe_results` with synthetic bytes,
    `query(same coord)` returns the expected `TerrainCell`.
  - TTL expiry: advance `_current_frame` past TTL → `query` returns
    default again until re-applied.
  - `invalidate_rect` clears overlapping entries.
- **Unit (binning):** mixed coords across multiple chunks → correct
  per-chunk ranges, contiguous `start` offsets, packed local coords
  matching expected SSBO layout. Coords in unloaded chunks are dropped.
- **Integration:**
  - Existing `CaveSpawner` tests pass with the new query path.
  - Existing `LavaDamageChecker` test (or new one) confirms damage
    triggers when the player overlaps lava.
- **Manual smoke:** drop player into lava → HP drops; explore caves
  outside any room → enemies spawn.

## Constants

| Name           | Value | Where             | Notes                                                 |
| -------------- | ----- | ----------------- | ----------------------------------------------------- |
| `PROBE_BUDGET` | 64    | `ComputeDevice`   | Max probes per frame; 256 B output, 512 B input.       |
| `TTL_FRAMES`   | 8     | `TerrainPhysical` | Cache freshness window; ≈ 133 ms at 60 Hz.            |

## Out of Scope

- Per-cell GPU writes from `terrain_modifier` (the existing
  `invalidate_rect` path remains; modified cells are simply re-probed).
- Coalescing CPU-side material mirror for solid cells (option C from
  brainstorming) — not needed once probes are cheap.
- Async/persistent-mapped readback — `buffer_get_data` of 256 B per
  frame is well within budget; revisit only if profiling shows a stall.
