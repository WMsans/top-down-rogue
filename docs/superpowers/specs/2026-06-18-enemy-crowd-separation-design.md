# Enemy Crowd Separation — Design

**Date:** 2026-06-18
**Status:** Approved, pending implementation plan

## Problem

When many enemies converge on the player they cram into a single overlapping
point rather than reading as a crowd with volume. Root cause:

- **One shared target point.** In CHASE with line-of-sight, every enemy steers
  straight at the player's exact position (`enemy.gd` `_process_chase`,
  `move_dir = to_player.normalized()`). Off-sight, the shared BFS flow field
  (`flow_field.gd`) also points every enemy at the player's cell.
- **Weak personal space.** `_apply_separation` (`enemy.gd`) only pushes apart
  neighbors within `separation_radius = 16px` at weight `0.5`, then renormalizes
  to a unit vector still aimed mostly at the player. The chase pull dominates, so
  bodies overlap.
- **No spreading while waiting.** Separation steering only runs in CHASE.
  Enemies in WINDUP / ATTACK / COOLDOWN are stationary and stack freely — this is
  where the blob is most visible.

## Goal

Enemies approaching the player keep personal space and never visually stack.
They still approach from their own direction (no forced encirclement) but spread
into a **loose, no-overlap crowd**. Hybrid approach:

1. Tuned separation steering does the natural spreading.
2. A depenetration safety net guarantees near-zero stacking under heavy pressure.

Non-goals: encirclement / slot reservation around the player; physics-body
collision between enemies; pathfinding changes to the flow field.

## Existing structures this builds on

- `SwarmGrid` (`src/core/swarm_grid.gd`): per-frame spatial hash of enemy
  positions, rebuilt once per frame in `WorldManager._process`. `cell_size = 32`.
  `query_neighbors(pos)` returns the 3×3 cell neighbourhood — covers every node
  within 32px. Already used by `_apply_separation`.
- Custom movement: enemies use `MOTION_MODE_FLOATING` and a custom
  `_move_with_clamp` / `_edge_blocked` (`enemy.gd`) that clamps against solid nav
  cells. Enemies do **not** physically collide with each other.
- `_body_radius`: each enemy measures its collision half-extent in
  `_measure_body_radius()` (default 8px; elites scale up).

## Components

### Component 1 — Stronger separation steering

Modify `_apply_separation` (`enemy.gd`):

- Raise default `separation_radius` from 16 → ~22px.
- Let the separation push scale with local crowd density (sum of per-neighbor
  overlap magnitudes) so a packed enemy produces a strong lateral push instead of
  being renormalized back toward the player.
- Blend with a tunable weight (new `@export var separation_weight`) so separation
  can balance the chase pull when crowded — a deeply packed enemy steers
  sideways/around the pile rather than into it.
- Keep cost flat: same single `query_neighbors` 3×3 lookup it already does.

New/changed `@export`s:
- `separation_radius: float` (default ~22) — already exists; new default.
- `separation_weight: float` (default tuned during implementation, ~1.0–1.5).

### Component 2 — Depenetration safety net

New method `_resolve_crowd_overlap()` on `Enemy`, called from
`_physics_process` for **every non-DEATH state** (independent of the existing
move gate), so stationary enemies in WINDUP / ATTACK / COOLDOWN also spread.

Algorithm (per enemy, per frame):

- Query `swarm_grid.query_neighbors(global_position)`.
- For each valid neighbor closer than `crowd_spacing`
  (= sum of the two bodies' radii, ~16–18px for default bodies):
  - Compute overlap = `crowd_spacing - dist`.
  - Push self out by **half** the overlap along the separating axis. The neighbor
    independently pushes its own half → symmetric, no oscillation.
  - Coincident pair (`dist < epsilon`): use a small deterministic jitter
    direction (e.g. derived from instance id) so the pair separates.
- Sum the corrections, **cap** the total per-frame correction (e.g. to a few px)
  to prevent jitter / explosions in dense piles.
- Apply the correction through the existing wall clamp (`_edge_blocked`) so
  crowds in corridors are never shoved into solid terrain — an overlap that can
  only be resolved into a wall is left unresolved that frame.

Spacing derives from each enemy's measured `_body_radius`, so elites (scaled-up
bodies) claim proportionally more room.

New `@export`:
- `crowd_spacing_scale: float` (default 1.0) — optional multiplier on the
  body-radius-derived spacing, for tuning.

## Constraints & interactions

- **Swarm grid coverage.** All spacing values stay under the 32px cell size, so
  the 3×3 `query_neighbors` still covers every relevant neighbor — no grid
  change. (Note for implementation: if any tuned radius approaches 32, the grid
  `cell_size` must grow to match.)
- **Attack reachability.** `crowd_spacing` (~16px) stays well below melee
  `_attack_range` (~28–32px), so the front rank still reaches the player; back
  ranks queue behind them. Spacing is enemy↔enemy; attack range is
  enemy↔player — independent.
- **Knockback.** Depenetration runs alongside knockback in HURT; the per-frame
  cap keeps the two from fighting into jitter.

## Testing

Follow existing patterns in `tests/unit/test_swarm_grid.gd` and
`tests/unit/test_enemy_*.gd`.

1. **Depenetration converges.** Spawn N enemies stacked on one point, tick the
   depenetration pass repeatedly, assert min pairwise distance converges to
   ≥ `crowd_spacing` (within tolerance) and stays stable across further ticks.
2. **Separation direction.** `_apply_separation` with a dense neighbor cluster on
   one side returns a direction pointing away from the cluster centroid, not into
   it.
3. **Wall safety.** Depenetration with a solid cell adjacent never moves an enemy
   into the wall (position stays on the passable side).

## Tuning defaults (starting points, refined during implementation)

| Param | Default | Notes |
|---|---|---|
| `separation_radius` | 22px | steering influence radius |
| `separation_weight` | ~1.2 | blend strength vs chase pull |
| `crowd_spacing` | `r_self + r_other` (~16px) | hard min center distance |
| `crowd_spacing_scale` | 1.0 | tuning multiplier |
| per-frame correction cap | ~4px | anti-jitter |
