# Enemy Navigation — Flow-Field Pursuit + Grid Clamp — Design

Date: 2026-06-05
Branch context: `feat/content-expansion`

## Problem

Per-enemy terrain physics was disabled for performance (the mob cap is 70 and
`move_and_slide` against the chunk `StaticBody` colliders dominated the physics
budget — see `2026-06-05-enemy-status-perf-design.md`). With that gone, enemies
no longer respect walls, and chasing is a naive straight line
(`enemy.gd:_process_chase` steers `to_player.normalized()` + separation). Two
gaps result:

1. **Enemies ignore walls.** Nothing stops a chasing or knocked-back enemy from
   moving into solid terrain.
2. **No routing.** Even when collision worked, a straight-line chase jams an
   enemy against any wall between it and the player. Worse, today
   `_process_chase` *abandons the chase the instant line-of-sight breaks*
   (`enemy.gd:248`), so enemies never attempt to go around an obstacle.

We want enemies to **respect walls again cheaply** (without re-enabling the
physics engine for the crowd) and to **route around walls** toward the player —
with **flat, distributed CPU cost**, no periodic stall.

## Constraints & context

- **Destructible GPU falling-sand terrain.** Walls are materials in a per-chunk
  256×256 grid; "solid" = `MaterialRegistry.has_collider(mat)`. Geometry
  changes constantly, so any navigation data must refresh as chunks change.
- **Dirty chunks are already tracked.** `WorldManager.mark_terrain_dirty(coord)`
  is the central hook (called from `compute_device`, `chunk_manager`,
  `terrain_modifier`); `TerrainCollisionHelper` already consumes it and
  rate-limits rebuilds.
- **CPU material reads exist.** `WorldManager.read_region(rect)` returns material
  bytes for a region (per-chunk `texture_get_data`). Used already by spawning and
  terrain modifiers; an accepted cost pattern when bounded/rate-limited.
- **Mob cap 70** (`cave_spawner.gd:13`), all pursuing one target → a shared,
  single-source field beats per-agent search.
- **Terrain `StaticBody` colliders stay.** The player still collides with them,
  and enemy `_can_see_player()` raycasts against them (`collision_mask = 1`).
  Those raycasts are independent of the enemy's own collision mask.
- **Headless tests.** Pure-CPU `RefCounted` classes run in the CLI test runner
  (the reason `swarm_grid` is `RefCounted`); nav classes follow that pattern.

## Approach (chosen)

A coarse CPU **passability grid** derived from terrain, a shared
**double-buffered incremental flow field** built outward from the player, and
**per-enemy pursuit + a manual wall clamp** that replaces physics collision.

Rejected alternatives:

- **NavigationServer2D navmesh + per-agent `NavigationAgent2D`.** Destructible
  terrain forces constant navmesh rebakes (far heavier than a flow field), plus
  70 per-agent A* searches. Wrong fit for falling-sand terrain.
- **Local-only obstacle avoidance (clamp without a field).** Cheapest, but
  enemies still jam on large/concave walls — no global routing.
- **BFS on a `WorkerThreadPool` thread.** Time-slicing on the main thread is
  simpler, deterministic (unit-testable by stepping frames), and avoids
  shared-state hazards with the passability tiles. Revisit only if profiling
  demands it.

## Components

All three are CPU-side. `PassabilityGrid` and `FlowField` are `RefCounted` with
no node dependencies so they run headless. A thin owner, `NavField`, bundles
them and is held by `WorldManager`, ticked from its existing `_process`.

### 1. PassabilityGrid

Coarse "is this cell solid?" lookup backed by cached per-chunk tiles.

- **Cell size: 8px (tunable).** A cell is **solid if any pixel in its block uses
  a `has_collider` material**. This conservative rule effectively inflates walls
  by ~one enemy radius (enemy `CircleShape2D` radius is 8px), keeping bodies out
  of walls the way agent-radius inflation does in a navmesh.
- **Per-chunk tiles.** Each 256px chunk → a 32×32-cell tile. Tiles are cached;
  `mark_terrain_dirty(coord)` flags the tile stale, and stale tiles are rebuilt
  from `read_region` on that one chunk, **rate-limited to a small budget per
  frame** (e.g. 2), mirroring `TerrainCollisionHelper`'s cadence.
- **Unloaded/unknown chunks read as open** (passable). Enemies only chase near
  the player, where chunks are loaded; this avoids trapping enemies on data gaps.
- API: `is_solid(cell: Vector2i) -> bool`, plus a world→cell helper. No
  per-query GPU readback — all lookups hit the cached tiles.

Wiring: `WorldManager.mark_terrain_dirty` also calls into the grid (alongside the
existing `_collision_helper.mark_dirty`). Tile drain runs in the
`NavField.update()` call from `WorldManager._process`.

### 2. FlowField (double-buffered, incremental — flat cost)

A shared field of directions pointing toward the player, built by BFS over the
passability grid. The build is **spread evenly across frames** so there is never
a periodic stall.

- **Double-buffered:** a *live* field (last completed build) that enemies sample,
  and a *work* field being filled in the background.
- **Time-sliced BFS:** 8-connected BFS from the player's cell, bounded to a
  square region of radius ≈ `leash + margin` around the build origin. Each frame
  pops up to a **per-frame cell budget** from the frontier and expands into the
  work buffer. Budget = `ceil(region_cells / target_frames)`, sized so a full
  build spans the target window (a few seconds). Cost is **constant per frame**,
  not a spike. Each cell stores a direction toward its lowest-distance neighbor;
  solid and unreachable cells store "no flow."
- **Rolling rebuild:** when the frontier empties, the work buffer swaps in as the
  new live field and the next build starts immediately from the **current**
  player cell. The effective refresh interval is emergent (≈ build duration), and
  the live field is never more than one build-length stale.
- **Idle skip:** if the player has not moved more than a threshold (~8 cells /
  64px) since the current build's origin and the live field is not too old, skip
  starting a new build — no wasted compute while stationary.
- API: `sample_direction(world_pos: Vector2) -> Vector2` → flow direction at a
  position, or `Vector2.ZERO` if outside the field or unreachable.

The few-second field latency only affects *routing around walls*; close-range
tracking rides on direct line-of-sight steering (below), where stale-by-a-few-
seconds wall geometry is fine.

### 3. Enemy integration (`enemy.gd`)

Enemies read the field via their cached `_world_manager`
(`_world_manager.nav_field`).

**Pursuit:**

- **Acquire (unchanged):** enter `CHASE` only when the player is within detection
  radius **and** `_can_see_player()` returns true. On acquire, mark the enemy
  aggroed and record a **leash radius**.
- **Pursue (`_process_chase`):**
  - If `_can_see_player()` → steer **directly** toward the player (today's
    behavior; best close-up fidelity, immune to field staleness).
  - Else (LOS blocked) → steer along `nav_field.sample_direction(global_position)`
    to route around the wall. If the field returns zero, fall back to
    straight-line toward the player.
  - Separation (`_apply_separation`) is applied to the resulting direction as it
    is today.
- **De-aggro:** revert to `WANDER` only when the player exceeds the **leash
  radius** (straight-line distance) — *not* the instant LOS breaks.
- **Attacks unchanged:** entering `WINDUP`/`ATTACK` still requires being within
  attack range and `_can_see_player()`, so enemies never attack through a wall.

**Wall clamp (replaces physics collision — this is the per-enemy cost avoided):**

- Set the enemy's terrain `collision_mask = 0` and stop relying on
  `move_and_slide` for terrain. (Layer/`attackable_hit` bits are unchanged so the
  enemy can still be hit; terrain `StaticBody` colliders remain for the player and
  for LOS raycasts.)
- Integrate movement manually each frame: `target = position + velocity * delta`.
  If the target cell `is_solid`, perform an **axis-separated slide** — try moving
  on X only, then Y only, else stop. This reproduces "slide along the wall" cheaply
  (O(1) per enemy) with no physics solver.
- **Knockback is clamped the same way**, so enemies cannot be knocked through walls.

### NavField owner & tick order

`WorldManager` gains a `nav_field` member (a `NavField`), created in `_ready()`.
Its `update(player_world_pos)` is called once in `_process` after the existing
crowd/terrain updates (the player position source is the already-tracked
`tracking_position`). `update()`:

1. Drains a budget of stale passability tiles.
2. Advances the incremental flow-field build by one frame budget (or starts a new
   build per the rolling/idle rules).

## Performance

- **Flow field: flat per frame.** A fixed small cell budget every frame; full
  builds amortized over seconds. No periodic spike — the explicit goal.
- **Passability upkeep: bounded.** Only dirty chunks rebuild tiles, rate-limited
  to a couple per frame, reusing the existing dirty cadence.
- **Per enemy per frame:** one field sample + 1–2 grid lookups for the clamp.
  Negligible across the 70-cap, and strictly cheaper than the removed
  `move_and_slide`-vs-terrain solve.

## Testing (headless gdUnit, matching `test_swarm_grid` / `test_enemy_*`)

- **PassabilityGrid:** classifies a known material region correctly (solid where
  `has_collider`, open elsewhere); marking a chunk dirty and draining rebuilds the
  affected tile.
- **FlowField — routing:** on a hand-built grid with a wall between origin and a
  cell, sampled directions route *around* the obstacle toward the player; solid
  cells return zero flow; unreachable cells return zero.
- **FlowField — incremental equivalence:** step the time-sliced build frame by
  frame until it swaps, then assert the live field matches a reference one-shot
  BFS over the same grid — proving the distributed build is equivalent to the
  one-shot version.
- **FlowField — idle skip:** with the player stationary and a fresh field, no new
  build starts; after moving past the threshold, a new build starts.
- **Enemy pursuit:** with a stub nav field, a chasing enemy whose LOS is blocked
  follows the field direction; the enemy de-aggros once the player passes the
  leash radius; the clamp prevents stepping into a solid cell (axis slide along a
  wall).

## Tunables

- Cell size (default 8px)
- Leash radius (de-aggro distance)
- Field region radius / margin
- Build target window (frames) → per-frame cell budget
- Idle move threshold (default ~64px)
- Passability tile rebuild budget per frame (default ~2)

## Non-goals

- Hazard avoidance — enemies may still walk into lava/fire; the field routes
  around solid walls only.
- Wall-ignoring enemy variants (e.g. ghosts/teleporters).
- Path smoothing beyond the gradient + existing separation.
- Pathfinding for `WANDER` — wandering stays a random walk plus the wall clamp.
- Threaded BFS (rejected above; revisit only if profiling requires it).
