# Interspersed Boss Rings — Design

**Date:** 2026-06-02
**Branch:** fix/boss-density
**Status:** Approved for planning

## Problem

Bosses spawn only on a single square ring at Chebyshev distance `BOSS_RING_DISTANCE = 10`
sectors from spawn, with anchors every `BOSS_RING_STRIDE = 8` ring-steps (~10 anchors around
the whole perimeter). A portal — the only way to progress — appears only when a boss dies.

Each boss arena is a carved cavern of radius ~960px (`ArenaComposition.nominal_radius`), about
2.5 sectors. On the d=10 ring (~3840px radius) an arena subtends ~28° of angle but anchors are
~36° apart, leaving ~8° angular gaps. A player who walks radially outward into one of those gaps
hits the solid void wall beyond the ring and can wander indefinitely without ever reaching a
boss — a soft-lock.

## Goal

**Guaranteed coverage:** make it geometrically impossible to miss. Every radial direction out
from spawn must pass through at least one boss arena before reaching the world edge.

## Approach

Replace the single boss ring with **three concentric, phase-offset (interspersed) rings** at
Chebyshev distances `[8, 10, 12]`. Inner rings' anchors are angularly offset to land in the
outer rings' gaps. Because angular arena width = `arena_radius / distance`, the inner rings cover
*more* angle per arena, patching gaps efficiently.

The square (Chebyshev) ring geometry makes closed-form angular coverage math awkward, especially
near corners, so the guarantee is locked by a **radial-ray regression test** (see Testing) rather
than by hand-proof. Ring parameters are tuned until that test passes with zero uncovered rays.

The outer ring moves from d=10 to **d=12**, so the playable world edge extends to d=12.

### Alternatives considered

- **Single denser ring** (reduce stride until arenas nearly touch): guarantees coverage with one
  ring but the first reachable boss stays at the far edge and it isn't the "interspersed rings"
  the design calls for. Rejected.
- **Angular wedge partition** (one boss per angular wedge, distance cycling per wedge): cleanest
  closed-form guarantee, but mapping a wedge to a single canonical anchor sector purely from a
  coordinate is fiddly on the square grid. Rejected in favor of the simpler ring + test approach.

## Components

### 1. Geometry model — `src/core/sector_grid.gd`

Replace the single-ring constants with a ring set:

```gdscript
const BOSS_RING_DISTANCES := [8, 10, 12]  # innermost → outermost (Chebyshev sectors)
const BOSS_WORLD_EDGE := 12               # dist > this is empty void
```

Changes:

- **Generalize `_ring_index`** from the hardcoded d=10 form to `_ring_index(coord, d)`, mapping
  any sector on the square ring of radius `d` to an index `0 .. (8·d − 1)` walking the perimeter.
- **Per-ring anchor pattern with phase offset.** Each ring `d` places its anchors at evenly
  spaced perimeter indices with a ring-specific phase so anchors on different rings project to
  interleaved angles. Starting point: ~8 anchors per ring, phases offset by ~⅓ of the anchor
  spacing between successive rings. Exact anchor counts and phases are tuning parameters resolved
  by the radial-coverage test — adding a fourth ring or shrinking spacing is permitted if needed
  to reach zero uncovered rays.
- **`is_boss_anchor(coord)`** returns true if `coord` sits on any ring in `BOSS_RING_DISTANCES`
  (its Chebyshev distance equals some `d`) *and* matches that ring's anchor pattern.
- **`resolve_sector(coord)`** restructured:
  - `dist > BOSS_WORLD_EDGE` → `is_empty` (unchanged behavior, new boundary value).
  - `is_boss_anchor(coord)` → boss slot (composition chosen from `biome.boss_compositions` as
    today; empty fallback if none).
  - else if `_find_claiming_anchor(coord)` hits → claimed empty.
  - else → normal room weighted roll (unchanged).

`BOSS_CLAIM_RADIUS` (±3 sector claim) and `_find_claiming_anchor` already key off
`is_boss_anchor`, so every ring's arenas auto-clear their surroundings with no extra work.

### 2. Radial-coverage guarantee — new test

`tests/unit/test_boss_ring_coverage.gd` (GdUnit):

- Build a grid from a representative biome with boss compositions.
- Enumerate all boss anchor sectors within d ≤ `BOSS_WORLD_EDGE` (scan the bounded sector square,
  collect those where `is_boss_anchor` is true) and convert to world centers.
- Fire N rays from spawn (origin) outward — e.g. 3600 rays, one per 0.1° — marching in small
  steps out to the world edge radius.
- For each ray, assert it passes within `nominal_radius` (~960px) of at least one anchor.
- Assert **zero** rays reach the edge uncovered.

This test is the definition of "guaranteed coverage"; the §1 parameters are tuned until it is
green.

## What stays unchanged

- **Dispatch** — `composition_dispatcher` spawns for any sector whose slot has a composition;
  more anchors just means more boss slots. No change.
- **Tiering** — `spawn_dispatcher` scales difficulty by `sector_dist / BOSS_RING_DISTANCE`. The
  reference must point at the outer value (12) so scaling is unchanged in shape; inner-ring bosses
  come out slightly easier, which is acceptable/desirable. (Confirm the constant name it reads;
  keep the divisor equal to the outer edge.)
- **Progression** — any boss death still drops the portal at that arena. Extra bosses are optional
  content; the guarantee is only that the player cannot cross the ring band without entering an
  arena.
- **No** new boss content, arena-size, dispatcher, or composition changes.

## Test impact (existing suites)

These existing assertions in `tests/unit/` reference the old single-ring layout and must be
updated as part of the work:

- `test_sector_grid.gd::test_outside_boss_ring_is_empty` uses `Vector2i(11, 0)` and expects
  empty. With the edge at d=12, d=11 is now inside the playable disc. Repoint to a sector with
  `dist > 12` (e.g. `Vector2i(13, 0)`).
- `test_sector_grid.gd::test_boss_ring_returns_boss_slot` uses `Vector2i(10, -10)` (a corner) and
  expects `is_boss`. Whether that exact corner is an anchor depends on the new pattern; repoint to
  a sector that the finalized pattern guarantees is an anchor.
- `test_sector_grid.gd` line ~89 (`Vector2i(10, 0)`, "boss, rotatable=false") and
  `test_sector_grid_claim.gd` (`Vector2i(10, -10)`, `Vector2i(10, -9)`) similarly assume specific
  d=10 anchors/claims — re-point to anchors the finalized pattern guarantees.

All other `test_sector_grid*` assertions (coordinate math, determinism, weighting) are unaffected.

## Out of scope

- Connectivity of carved caverns (whether a navigable path actually links spawn to an arena). The
  guarantee here is angular/radial coverage, which directly addresses the reported "walk in a
  direction and miss every boss" symptom. Path-connectivity is a separate concern.
- Rebalancing boss difficulty or rewards.
