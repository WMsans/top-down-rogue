# Chunk-Load Lag Fix — Design

## Problem

When the player crosses a chunk boundary, an entire row or column of new chunks
enters view at once. The game stalls for ~0.5s every time this happens.

## Diagnosis

In `world_manager.gd`, every newly-created chunk is marked
`collision_dirty = true` with `last_collision_time = 0`. On the very next call
to `_rebuild_dirty_collisions`, **all** new chunks pass the time gate
simultaneously and rebuild collision in a single frame.

For each rebuild, two separate full GPU→CPU sync stalls occur:

1. `_rebuild_chunk_collision_gpu` calls `rd.buffer_get_data(collider_storage_buffer)`
   immediately after dispatching the compute shader. Because
   `collider_storage_buffer` is a single shared resource, dispatches cannot
   pipeline — they serialize.
2. On success, `_check_chunk_burning` calls
   `rd.texture_get_data(chunk.rd_texture)` and iterates 65 536 pixels on the
   main thread.

N chunks × (sync stall + sync stall + CPU polygon work) = the half-second
hitch the user is seeing.

## Goal

Eliminate the visible hitch when chunks enter view. The fix should keep
collision behavior correct (player cannot fall through terrain that has been
visible for more than a few frames) and should not introduce new memory/CPU
costs in steady state.

## Approach

**Two changes to `world_manager.gd`:**

### 1. Frame-budget the collision rebuilds

Limit `_rebuild_dirty_collisions` to processing **one chunk per frame**.
A queue of dirty chunks is walked each frame; the first eligible chunk is
rebuilt and the rest wait for subsequent frames.

Priority: closest-to-player first (sorted by squared distance from
`tracking_position` in chunk coordinates), so the chunk most likely to be
walked into gets its collider first.

This means N new chunks spread their work over N frames instead of stacking
on one. At 60 fps, even 8 new chunks finish in ~130ms — well below the
distance the player can travel (a chunk is 256 px wide).

The existing `COLLISION_UPDATE_INTERVAL` (0.3s) stays in place for
*re-rebuilds* of already-built chunks (e.g. burning terrain), but is
**bypassed** for the initial build of a freshly-loaded chunk so new chunks
get collision as soon as their turn in the queue arrives.

### 2. Eliminate the `_check_chunk_burning` readback

Replace the synchronous texture readback with CPU-side bookkeeping:

- Add `chunk.has_burning: bool` (default false).
- `place_fire(...)` sets `has_burning = true` on every affected chunk
  (it already iterates them).
- `_rebuild_dirty_collisions` keeps `collision_dirty = chunk.has_burning`
  after a successful GPU rebuild — same semantics as before, but with no
  texture readback.
- Burning state decays naturally: a chunk that was burning continues to
  rebuild collision every `COLLISION_UPDATE_INTERVAL` (driven by
  `has_burning`). When fires burn out, we need a way to clear the flag
  so we don't rebuild forever. To handle this without a per-frame readback,
  add a low-frequency check: every Nth rebuild (e.g. every 10th, ~3 seconds),
  do a single readback to refresh `has_burning`. Stale-by-3-seconds is fine
  for terrain destruction.

This removes the second sync stall entirely from the hot path.

## Non-goals

- Async/pipelined GPU readback for the collider buffer itself
  (Approach 2 from brainstorming). With the per-frame budget, only one
  collider sync happens per frame anyway, so the stall is bounded and
  acceptable. If profiling later shows a *single* chunk's rebuild is itself
  too slow, escalate to a per-chunk collider buffer pool with deferred
  readback.
- Pre-loading chunks beyond the visible rect. Increases steady-state cost
  without removing the spike at the new ring boundary.
- Threading `TerrainCollider.build_from_segments` to a worker. With one
  chunk per frame, the CPU work is small enough to stay on the main thread.

## Files affected

- `scripts/world_manager.gd`
  - `_rebuild_dirty_collisions`: new queue/budget logic
  - `_rebuild_chunk_collision_gpu`: drop the `_check_chunk_burning` call
  - `place_fire`: set `chunk.has_burning = true`
  - new helper for periodic burning re-check
- `scripts/chunk.gd`
  - add `has_burning: bool`

No shader changes. No new GPU resources. Diff should be ~50 lines.

## Risk

- **Player walks onto a chunk that has not been collided yet.** Mitigated by
  priority ordering (nearest-first) and the fact that the player can't cross
  256 px in <130ms. If this turns out to bite in practice, raise the per-frame
  budget to 2 chunks for *initial* builds only.
- **Burning chunks get rebuilt slightly less often** (every 10th rebuild
  refreshes the flag). 3-second staleness is acceptable for terrain
  destruction visuals.
