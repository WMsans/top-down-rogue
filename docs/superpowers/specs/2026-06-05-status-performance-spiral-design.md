# Status System Performance: Physics Death-Spiral Fix

**Date:** 2026-06-05
**Status:** Approved design

## Problem

After the status system shipped, framerate collapses from ~90 fps to ~7 fps as a
level progresses, especially after a lot of blood and many enemies have been
fought. Profiling shows the frame dominated by `StatusComponent` terrain polling.

## Diagnosis

The profiler call counts are the key evidence:

- `Enemy._physics_process`: **688** calls in one rendered frame
- `Enemy._process`: **86** calls
- `StatusComponent._physics_process`: **696** calls
- `StatusComponent._poll_terrain`: ~110 ms; `TerrainPhysical.query` a large child cost

`_process` runs once per *rendered* frame, so there are only **~86 status-bearing
entities** (≈ `mob_cap` 70 + elite/in-flight groups + the player). This is **not**
an entity leak.

`688 / 86 = 8` and `696 = (86 + 1 player) × 8`. The `×8` is Godot's
`max_physics_steps_per_frame` (default **8**), which the project does not override.

### The spiral

1. Each of ~87 entities runs `StatusComponent._poll_terrain` every physics step,
   firing up to **45 terrain queries** each (5 origins × 9 footprint samples) →
   ~3,900 `query()` calls per step ≈ **13.7 ms**.
2. As play progresses (enemies near the cap, blood staining terrain), one physics
   step's cost creeps past the 16.6 ms budget.
3. Godot runs catch-up substeps — up to **8 per rendered frame** — to keep
   simulation time correct.
4. 8× the work makes the next frame slower → more catch-up → **90 fps → 7 fps**.

`StatusComponent` does no physics work; it only lives in `_physics_process` for the
velocity look-ahead. That placement is what lets a heavy step get multiplied into a
freeze.

### Secondary (process-side) cost

`world_manager._process` → `_update_chunks` generates every newly-desired chunk in a
single frame (`read_region` 32 ms + `FloorChunk.populate` + decoration +
`bake_decor_lights`, surfacing as `FloorContainer._on_chunks_generated` 41 ms and
`_update_chunks` 54 ms). Separately, blood staining marks chunks dirty, so
`_collision_helper.rebuild_dirty` (12 ms + `build_occluders` 5.7 ms +
`create_occluder_polygons` 5.4 ms) rebuilds occluders. These are real but distinct
from the sustained spiral — chunk-streaming hitches and blood-driven rebuild churn.

## Goals

- Eliminate the physics death-spiral so frame time stays under budget with ~70
  enemies and heavy blood.
- Reduce blood/chunk process-side hitches.
- Preserve gameplay behavior: stain accumulation/decay rates, burn DoT, movement
  block/slow.

## Non-goals

- No change to the status reaction model or stain semantics.
- No entity-count/cap changes (count is within expectations).
- No central `StatusManager` refactor in this pass (noted as a future option).

## Design

### Front A — Status cost & the death-spiral (primary)

**A1. Move status updates off `_physics_process`.**
Drive `_poll_terrain` + `tick` from `_process` (once per rendered frame) instead of
`_physics_process`. `_process` never substeps, so the 8× amplification disappears.
- Stain accumulation/decay already scale by `delta`; use the `_process` delta.
- Velocity look-ahead still reads `_owner_node.velocity`; render-frame cadence is
  fine for priming approach cells.
- Movement gating (`get_move_speed_multiplier`, `is_movement_blocked`) continues to
  be *read* by the owners' `_physics_process`; it now reflects status from the most
  recent rendered frame (≤1 render frame stale — imperceptible).

**A2. Stagger + throttle the terrain poll.**
Poll terrain every `K` frames (K ≈ 3–4) per component, with a per-instance phase
offset (e.g. derived from instance id) so the ~87 entities' polls spread across
frames rather than firing together. Accumulate elapsed delta between polls and pass
it to the stain rate so totals are unchanged.
- `tick()` (decay/reactions/burn) may run every `_process` frame (it is cheap,
  ~6 ms/696 ≈ unamplified ~0.75 ms) or share the same throttle; default: run
  `tick` every frame, throttle only `_poll_terrain`.

**A3. Reduce sample fan-out.**
`_SAMPLE_STEPS` 3 → 2 (9 → 4 samples per origin) and cap the number of sample
origins. Roughly halves remaining poll cost with negligible gameplay change.

**A4. Defense-in-depth: cap physics substeps.**
Set `physics/common/max_physics_steps_per_frame = 2` in project settings so no
future regression can re-trigger the 8× catastrophe; under extreme load the game
degrades to mild slow-mo instead of freezing.

*Alternative considered:* a central `StatusManager` ticking components round-robin
under a hard per-frame budget — cleaner budget control, but larger refactor and more
coupling. Deferred.

### Front B — Blood / chunk process cost (secondary)

**B1. Amortize chunk generation.**
In `world_manager._update_chunks`, cap newly-generated chunks to `N` per frame
(queue the remainder for following frames) so `read_region` + `FloorChunk.populate`
+ decoration + light bake spread out. Converts the 41/54/32 ms hitch into a smooth
ramp. Pick `N` (start ~1–2) to keep the per-frame generation budget bounded.

**B2. (Already handled — no change needed.)**
Investigation of `terrain_collision_helper.gd` shows blood-driven collision
rebuilds are already debounced: `MAX_DISPATCH_PER_FRAME = 4` caps work per frame,
`_last_seg_hash` skips rebuilds when a chunk's collision segments are unchanged, and
fresh-vs-stale prioritization bounds latency. No further debounce is warranted
(YAGNI); adding more would destabilize a tuned budget for marginal gain.

## Verification

Re-profile after each front under the repro (≈70 enemies + heavy blood):

- **Spiral gone:** `Enemy._physics_process` call count ≈ enemy count (no ×8
  multiplier); sustained frame time back under ~11 ms (90 fps).
- **Status totals unchanged:** existing `tests/unit/test_status_component.gd` and
  reaction/visual tests still pass; stain pickup/decay/burn rates match pre-change
  behavior (cover throttled accumulation with a unit test).
- **Chunk hitch reduced:** no single-frame spike from batch chunk generation when
  crossing chunk boundaries.

## Affected code

- `src/status/status_component.gd` — A1, A2, A3
- `project.godot` — A4
- `src/core/world_manager.gd` — B1
- `tests/unit/test_status_component.gd` — throttled-accumulation coverage
