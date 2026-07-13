# Boss Design — Design

Implements **Phase 3: Boss Design** of `docs/design_docs/implementation_todo2.md`.

## Problem

The game has one generic boss (`BossEnemy` in `src/enemies/boss_enemy.gd`): a
100-line script that fires a `boss_staff` projectile, switches to a 3-projectile
fan at phase 2, and stamps random lava splotches on phase 3. All 20 boss arena
compositions (4 variants × 5 biomes under `assets/arenas/boss/`) spawn this
*same* generic scene — every biome's boss is identical. There is no boss HUD,
no intro, no death sequence beyond a portal rising instantly, and no telegraph
variety. Boss fights don't read as boss fights.

We want biome-specific bosses with distinct identities, multiple attack patterns
per phase, a health-bar HUD, a dramatic intro, and a beautiful Saltmire-driven
death that dissolves the boss into streaming motes pulled into the portal.

## Goals

1. **Refactor `BossEnemy` into a thin base** — health-gate state machine plus
   clean hooks; biome behavior lives in subclasses.
2. **Five biome bosses**, one subclass + scene each, each fully defining all
   three phases with **≥2 distinct attack patterns per phase**.
3. **A `BossEncounter` controller** that owns the fight lifecycle: HUD, intro,
   ongoing phase/health sync, and death sequence (including the portal spawn
   previously owned by the dispatchers).
4. **Repoint the 20 arena compositions** to biome-specific boss scenes and
   consolidate to a single canonical spawn path.
5. **Beautiful death**: Saltmire `FX.dissolve` on the boss sprite *plus*
   silhouette-sampled fragment particles streaming into the rising portal.
6. **No audio** — Phase 4 territory; this design emits no audio signals/hooks.

## Non-goals

- **Audio / FMOD** of any kind (Phase 4). No `boss_music_requested` signal, no
  sting hooks, no parameter buses. Phase 4 can later attach to the existing
  `boss_spawned` / `phase_changed` / `boss_died` signals without this design
  pre-empting them.
- **New sprite art**. Each biome boss reuses the existing `boss_test.png`
  placeholder, tinted per biome via `modulate` (matching how
  `SpawnDispatcher._spawn_enemy` already tints the generic boss with
  `LevelManager.current_biome.tint`). Real commissioned sprite art is a separate
  Phase 5 task.
- **New terrain materials or props.** All phase hazards reuse the existing
  material system (`MaterialRegistry.MAT_*`, `TerrainSurface.place_*`,
  `CompositionDispatcher.place_material_*`), existing status effects
  (`StatusRegistry` chilly/frozen), and existing prop scenes
  (`scenes/props/barrel.tscn`, `scenes/portal.tscn`, `scenes/gold_drop.tscn`).
- **Ranged-weapon rework.** Projectile behaviors (ricochet, mild homing) use
  the existing projectile system; minor flag additions are localized to the
  boss/projectile, not a system rewrite.
- **Phase 6 UI consolidation.** The HUD uses `UILayout` / `JuicyPanel` tokens
  where they already exist; if a token isn't ready it falls back to local
  constants in one place so Phase 6 can absorb it cleanly.
- **Player-camera system rework.** A single small `CameraEffect` helper wraps
  the main camera's `offset`/`zoom` for the intro pan and death shake; it is not
  a general camera framework.

## Architecture

Five decisions were made during brainstorming and constrain this design:

1. **One behavior-subclass + scene per biome** (Burrower, Pyrelord, Glacier
   Titan, Drill Construct, Golden Warden), mirroring the existing per-archetype
   enemy pattern (`brute_enemy.tscn`, `archer_enemy.tscn`, …).
2. **Each boss fully defines all three phases** per the per-biome table in the
   todo. There is no shared "template phase" beyond whatever a biome boss
   chooses to author; phases are biome-specific, not a generic frame with one
   unique coat of paint.
3. **`BossEnemy` is the thin base.** Behavior lives in subclasses via virtual
   hooks — not in a per-phase virtual weapon set, and not in a data-driven
   action resource.
4. **Every phase rotates between ≥2 distinct attack patterns** (rotating index,
   one pattern per attack tick, distinct telegraph per pattern so the player can
   read the windup).
5. **A `BossEncounter` controller owns all presentation.** It is the single
   owner of HUD, intro, death, and portal timing; neither the boss entity nor
   the dispatchers reach into HUD/camera/portal code directly.

Component layout:

```
Enemy (base, unchanged)
  └─ BossEnemy (refactored base: health gates + hooks + drop table + scaling)
       ├─ BurrowerBoss     (Caves)
       ├─ PyrelordBoss     (Magma)
       ├─ GlacierBoss      (Frozen)
       ├─ DrillBoss        (Mines)
       └─ WardenBoss       (Vault)

BossEncounter (controller, group "boss_encounter")
  ├─ BossHud (CanvasLayer overlay: name + health bar + phase pips)
  ├─ CameraEffect (thin wrapper over the main Camera2D)
  └─ BossDeathSequencer (Saltmire dissolve + silhouette fragment streamer)
```

Dispatchers:
- `CompositionDispatcher` and `SpawnDispatcher` **emit** `boss_spawned` /
  `boss_died` (or call `BossEncounter.notify_spawned/notify_died`) and **stop**
  spawning portals themselves — the controller spawns the portal after the
  death animation.

## `BossEnemy` base class refactor

Current state: `boss_enemy.gd` owns the weapon, hardcodes phase transitions,
hardcodes `_execute_attack` = `weapon.use(self)`, hardcodes phase-2 spread
tweak, hardcodes phase-3 lava `_spawn_hazards`. The refactor turns it into a
thin, well-documented base.

New responsibilities:

- **Health-gate state machine** (math unchanged, verified chain-safe):
  `current_phase`, `phase_count`, `_check_phase_transition()`,
  `_phase_threshold()`.
- **Lifecycle signals**: `died` (exists); newly added
  `phase_changed(phase: int)` and `boss_ready` (fires after `_ready`, lets the
  controller attach HUD before the first attack).
- **Clean virtual hooks** (all default-bodied, all overridable):
  - `_on_phase_enter(phase: int)` — called once per transition *after*
    `current_phase` is set. Subclasses put phase-specific setup here (swap
    movement mode, queue an intro telegraph, reset an internal timer). Base:
    no-op.
  - `_tick_phase(delta: float)` — called every `_process` while alive.
    Subclasses put per-frame phase behavior here (charge steering, magnet-pull
    accumulation, pillar-summon timer). Base: no-op.
  - `_do_attack()` — called when the attack cadence elapses; the subclass
    decides what "an attack" means this phase. Base default: if `weapon_resource`
    is set and a player is in `_attack_range`, call `weapon.use(self)` (preserves
    the legacy ranged path for bosses that want it — Pyrelord orbs, Glacier
    shards, Warden ricochet).
- **Shared attack cadence**: `attack_interval` (s) + `_attack_cooldown` timer,
  driven in `_process` → calls `_do_attack()` when ready. Replaces the implicit
  `cooldown_duration` / weapon-cooldown coupling so melee/movement bosses aren't
  forced to own a `RangedWeapon`.
- **Pattern rotation** (standardized across all subclasses): the base tracks a
  per-phase `_pattern_index`. `_do_attack` calls
  `_pick_pattern(phase) -> int` (default: rotating index modulo the phase's
  pattern count) and dispatches to `_execute_pattern(phase, index)`. Subclasses
  override `_execute_pattern` (and optionally `_pick_pattern` for non-uniform
  rotation). Telegraphs are distinct per (phase, pattern) so the player reads
  the windup, not the outcome.
- **Stat defaults + scaling hook**: `_apply_floor_scaling(floor_num)`
  centralizes the +HP/+speed/+dmg math currently duplicated in
  `SpawnDispatcher._spawn_enemy`'s `is_boss` branches; the dispatcher's boss
  scaling branches are deleted.
- **Drop table + `_spawn_drops()`** stays in the base; `_roll_weapon_modifier()`
  stays a no-op override point.

What leaves the base: the `weapon_resource`-as-attacker coupling (now
optional — `weapon_resource` may be null for movement bosses), the phase-2
spread tweak, and the phase-3 `_spawn_hazards` lava logic. These move into
subclasses.

**Backwards compatibility:** the existing `boss_enemy.tscn` (still referenced by
all 20 arena compositions until we repoint them) keeps working because the
base's default `_do_attack` still does `weapon.use(self)` when `weapon_resource`
is set. The repoint (Section: Data wiring) makes this legacy scene unused; the
`SpawnDispatcher` hardcoding of `BOSS_ENEMY_SCENE` + `boss_staff` is removed
once the composition path is the only spawn path. Planning verifies nothing else
spawns a boss before deleting the const.

## The five biome bosses

Each subclass extends the refactored `BossEnemy`; each scene lives under
`scenes/enemies/bosses/`. Each phase rotates ≥2 distinct attack patterns (one
per attack tick, distinct telegraph per pattern). Telegraphs are lightweight
visual cues the subclass spawns — kept inside the entity so the controller stays
presentation-agnostic for the *fight* (the controller only owns *lifecycle*
presentation: HUD, intro, death).

Telegraph primitives (added once, reused across bosses):
- **Ground-crack line** — for charges (a short line indicator along the dash
  path, ~0.4–0.6s).
- **Expanding circle** — for AoE pulses / pit drop-ins (~0.8–1.2s).
- **Flash on projectile** — projectile glows before firing (~0.6s).
- **Column-rise vignette** — for pillar stamps (brief vertical highlight before
  the column appears).
- **Converging particles / shockwave ring** — for magnet pull / repulse.

All bosses route terrain/status/prop/minion actions through a **facade** on the
base — `_stamp_material(...)`, `_apply_status(...)`, `_spawn_minion(...)`,
`_spawn_prop(...)` — that delegates to `CompositionDispatcher` (or the world
manager) rather than reaching for singletons. This keeps subclasses testable
(the facade is injectable/overridable).

### 1. Caves — "Burrower" (`burrower_boss.gd` / `.tscn`)

`weapon_resource = null` — charge-based.

- **Phase 1 — Charge tier:**
  - A) **Directed charge** — ground-crack line telegraph toward player (~0.4s),
    then dash to the player's position-at-telegraph; recover on wall hit or
    ~400px.
  - B) **Sweep charge** — wide-arc indicator telegraph, then a curving dash
    sweeping a half-circle around the arena center; covers area the player
    thought was safe.
- **Phase 2 — Dust + pressure:**
  - A) **Dust-burst on charge** — after any charge, spawn `MAT_DUST` blobs at
    the landing point + along the dash path (lingering vision/dodge zones).
  - B) **Dust eruption** — stationary; spawn `MAT_DUST` bursts at 3 random
    positions around the player (expanding-circle telegraphs), forcing
    repositioning without the boss moving.
- **Phase 3 — Collapsing arena:**
  - A) **Pit stamp** — every `hazard_interval`, sinkhole telegraph (expanding
    circle ~1s) then `MAT_AIR` pit at a random position; pits persist.
  - B) **Tremor stagger** — brief arena-wide shake + a ring of dust bursts at
    fixed radius; no pits but punishes standing near walls. Rotates with A so the
    phase alternates "pit appears" / "tremor pressure."

### 2. Magma — "Pyrelord" (`pyrelord_boss.gd` / `.tscn`)

`weapon_resource` = a fire-orb projectile (slow, mild homing). One of three
bosses with a weapon-based phase 1 (alongside Glacier's shards and Warden's
ricochet); Burrower and Drill are charge-based.

- **Phase 1 — Fire orbs:**
  - A) **Single homing orb** — slow, mild-homing fire orb at the player (the
    rhythm-learner).
  - B) **Orb spread** — 3 non-homing orbs in a fixed fan away from the player
    (no spread tracking — readable pattern).
- **Phase 2 — Arena fire:**
  - A) **Lava trail** — while kiting/chasing, stamp a thin `MAT_LAVA` trail
    behind the boss; arena becomes a pathing puzzle.
  - B) **Lava spit** — stationary burst: lob 2–3 `MAT_LAVA` splotches at the
    player's position with arcing telegraphs (ground circles ~0.8s lead).
- **Phase 3 — Ring ignite:**
  - A) **Expanding ring** — glowing expanding-circle telegraph (~1.2s), then
    `MAT_LAVA` placed on a ring at `ring_radius` bounding a safe donut the
    player must reach.
  - B) **Center-safe collapse** — inverse: lava floods inward from the arena
    edges (contracting-ring telegraph); the safe zone shrinks to center then
    reopens. Rotates with A so the safe donut keeps relocating.

### 3. Frozen — "Glacier Titan" (`glacier_boss.gd` / `.tscn`)

`weapon_resource` = an ice-shard projectile (fast, straight, no spread).

- **Phase 1 — Ice shards:**
  - A) **Single fast shard** — straight projectile at the player.
  - B) **Shard volley** — 3 shards straight ahead in a tight burst (short delay
    between), side-steppable if the windup is read.
- **Phase 2 — Chill zones:**
  - A) **Chilly disc** — place disc-shaped `chilly_zone` stamps
    (expanding-circle telegraph); standing applies `chilly` (slow) → `frozen`
    if stacked (reuses `StatusRegistry`).
  - B) **Frost nova** — expanding ring of chilly aura centered on the boss;
    player must be outside the ring at peak (ring-radius telegraph), then it
    lingers as a circular zone.
- **Phase 3 — Ice pillars:**
  - A) **Truncating pillars** — stamp `MAT_ICE` columns positioned to cut the
    player→boss line, forcing repositioning (column-rise telegraph). Pillars
    are solid (block projectiles).
  - B) **Pillar ring** — spawn a ring of pillars around the player (cages them
    briefly) with a gap on one random side; the player must exit through the gap
    before shards fire down the closed sides.

### 4. Mines — "Drill Construct" (`drill_boss.gd` / `.tscn`)

`weapon_resource = null` — charge/mine-based.

- **Phase 1 — Drill charge:**
  - A) **Committed straight bore** — long ground-crack telegraph (~0.6s)
    toward the player's position-at-start, then a fixed straight-line dash;
    side-steppable.
  - B) **Double-bore** — two shorter charges in sequence at angles offset ±30°
    from the first; the second punishes dodging in the same direction twice.
- **Phase 2 — Mine scatter:**
  - A) **Random scatter** — scatter `mine` props (reuse
    `scenes/props/barrel.tscn` logic via a lightweight `mine` variant) at random
    nearby positions; arm after ~1s telegraph, explode on proximity/timeout.
  - B) **Patterned grid** — drop mines in a fixed grid pattern across the
    arena floor (predictable layout, wide coverage); forces pathing through
    gaps.
- **Phase 3 — Wall reconfigure:**
  - A) **Pillar raise/lower** — raise `MAT_STONE` pillar rows that block
    access; lower existing pillars to open lines (per-tile telegraph, then
    stamp toggle).
  - B) **Corridor slam** — spawn two long parallel walls forming a corridor
    the player is funneled into, then a charge down that corridor (reuses the
    phase-1 charge AI); corridor walls sink after the charge.

### 5. Vault — "Golden Warden" (`warden_boss.gd` / `.tscn`)

`weapon_resource` = a ricochet projectile (bounces off walls a few times).

- **Phase 1 — Ricochet shots:**
  - A) **Single bouncing shot** — projectile flagged to bounce off walls N
    times (glows ~0.6s before firing as telegraph).
  - B) **Ricochet pair** — two bouncing shots in mirrored directions, crossing
    the arena; harder to read both trajectories at once.
- **Phase 2 — Magnet control:**
  - A) **Magnet pull** — `_tick_phase` applies inward force on the player
    within `magnet_radius`, ramping with proximity (golden particle telegraph
    converging on the boss + faint vignette). Player breaks LOS or staggers the
    boss to cancel.
  - B) **Repulse shove** — inverse: brief powerful outward shove from the boss
    (knockback pulse), telegraphed by an expanding shockwave ring. Rotates
    with A so the phase alternates "sucked in" / "thrown out."
- **Phase 3 — Elite adds + gold rain:**
  - A) **Elite summon** — every `hazard_interval`, summon an elite enemy at a
    corner (via the base's `_spawn_minion` facade → `CompositionDispatcher`);
    the Warden stays ranged during the summon windup (banner telegraph at the
    corner).
  - B) **Gold rain** — rain `gold_drop` clusters from arena top; shadow
    circles telegraph impact ~0.8s ahead, damage on impact then become
    collectible. Rotates with A so the phase cycles adds → hazard → adds.

### Cross-cutting notes

- **Materials** — all phase 3 hazards use the existing terrain material
  system. Planning verifies each material ID (`MAT_DUST`, `MAT_LAVA`,
  `chilly_zone`, `MAT_AIR`, `MAT_ICE`, `MAT_STONE`) exists and has a usable
  stamp API on `CompositionDispatcher` / `TerrainSurface`.
- **Movement for charge bosses** — Burrower and Drill override the base
  movement for the duration of a charge. The base exposes a
  `_steer_toward(target, accel)` hook and a `_lock_navigation(lock: bool)`
  helper so subclasses can take direct velocity control during a dash and
  restore the `Enemy` AI navigation afterward, without touching `Enemy`
  movement internals directly. The exact hook signature is finalized during
  planning.
- **Singletons** — subclasses never call `CompositionDispatcher` /
  `TerrainSurface` / `StatusRegistry` directly. All such calls go through base
  facade methods (overridable in tests), keeping subclasses unit-testable
  without a full arena/tilemap.
- **Projectile behaviors** (ricochet, mild homing) — added as small flags on
  the existing projectile scene or per-boss projectile resource, localized to
  the boss/projectile. No projectile system rewrite.

## `BossEncounter` controller, HUD, intro & death

The controller owns the *fight lifecycle* — start, ongoing health/phase
display, end — and decouples presentation from the boss entity. It lives as a
node registered in group `boss_encounter`, found by dispatchers via
`get_tree().get_first_node_in_group("boss_encounter")` (the same lookup pattern
the rest of the codebase uses). One boss is active at a time by design (one
boss arena per floor); a second spawn mid-fight is logged and ignored (shouldn't
happen). `clear()` is called from `LevelManager.advance_floor` alongside the
existing dispatcher clears.

### Lifecycle

1. `notify_spawned(boss, arena_center)` — stores the ref, connects
   `boss.phase_changed` and `boss.died`, starts the intro.
2. **Intro sequence (~1.5s):** set the boss idle
   (`boss.set_encounter_active(false)`), camera pan to the boss,
   `FX.appear(sprite, 1.2, biome_edge_color)` for a reverse-dissolve materialize
   as the boss "emerges," name banner + HUD reveal, then
   `boss.set_encounter_active(true)` and the fight begins. Implemented via a
   `Tween`; the pan uses a single small `CameraEffect` helper wrapping the main
   camera's `offset` / `zoom`.
3. **Ongoing** — every frame, sync the HUD health bar to
   `boss.health / max_health`; on `phase_changed`, animate the phase-marker pip
   and a short "PHASE 2" banner flash.
4. `notify_died(boss, arena_center)` — disconnect, hide HUD, play the death
   sequence, spawn the portal after the animation.

### HUD (`boss_hud.tscn`, top-of-screen overlay on a CanvasLayer above gameplay)

- Large bar centered at top: boss name (left-aligned, pixel font), health bar
  (fills width), phase pips (3 small segments under the bar, lit by
  `phase_changed`).
- Health-gate markers shown as tick lines on the bar (one per phase threshold)
  so the player can see where phases flip.
- Hidden by default; the controller shows it during the intro and hides it
  after the death sequence.
- Uses existing UI tokens where available: `UILayout` spacing, `JuicyPanel`
  reveal, pixel font `SDS_8x8` (16/32px). If a token isn't ready, fall back to
  local constants in one place so Phase 6 UI consolidation can absorb it
  cleanly. Planning checks which tokens exist.

### Death sequence (~2.2s) — the beautiful part

1. **Hit-stop + shake onset** — brief freeze-frame (~0.05s) + camera shake
   intensity ~3.0 decaying over ~0.4s (via `CameraEffect`).
2. **Silhouette burst** — sample the boss sprite's *silhouette* by reading
   `sprite.texture.get_image()` once at death and rejection-sampling random
   points in the boss's AABB, keeping those whose sprite pixel alpha is
   non-zero. Each accepted point spawns a fragment: a small `Sprite2D` (a tiny
   clipped piece of the boss texture, or a `EnemyVfxShared.soft_dot_texture()`
   dot tinted with the boss modulate + biome accent) parented to the arena
   layer. Each fragment gets a `Tween` flying it toward `arena_center` (the
   future portal) with a slight randomized arc, staggered start (0–0.5s),
   ease-in-out, shrinking + fading as it nears the portal — so the boss
   appears to come apart into motes that stream inward.
3. **Dissolve** — simultaneously call
   `FX.dissolve(boss_sprite, ~1.4, edge_color)` where `edge_color` is
   biome-tinted (magma orange, frozen cyan, etc.). The sprite burns away with a
   glowing noise edge *as* the fragments detach — designed to read together:
   the body dissolves while pieces of it peel off and fly.
4. **Portal rises** — `await` the dissolve tween's `finished`; at that moment
   spawn `portal.tscn` at `arena_center` (replaces the per-dispatcher portal
   spawn — the controller owns this timing so it lines up with the animation).
   Fragment endpoints converge on the portal so the streams visibly get "sucked
   in."
5. **Weapon drop flies out** — tween the weapon drop from the boss position
   outward to a reachable spot near (not on) the portal, staggered start.
6. **Cleanup** — `FX.clear(sprite)`, `queue_free` the boss, hide the HUD.

**Silhouette-sampling detail:** read `sprite.texture.get_image().get_pixelv()`
once at death (the texture must be readable — Godot 4 imports usually permit
`get_image()` after import; planning verifies with the placeholder texture).
Cache accepted positions. `EnemyVfxShared.soft_dot_texture()` is the fragment
visual fallback should a per-fragment clipped sprite prove too costly. Fragment
count is ~28–36, capped for performance.

**Saltmire dependency:** verified installed (`addons/saltmire_fx/`, enabled in
`project.godot` as the `FX` autoload). The dissolve shader's API contract
(`FX.dissolve(target, duration, edge_color) -> Tween`, `progress` 0→1 via
`tween_method`, `edge_color`/`edge_width`/`noise_scale` uniforms) is concrete
and used directly. No guessing at the API.

### Controller wiring (touches `SpawnDispatcher` and `CompositionDispatcher`)

- Both dispatchers currently call a local `_on_boss_died` to spawn a portal.
  This responsibility moves to the controller: each dispatcher calls
  `BossEncounter.notify_died(...)` (or emits `boss_died` which the controller
  listens to) instead of spawning the portal itself.
- Each dispatcher calls `BossEncounter.notify_spawned(...)` on spawn so the
  controller attaches HUD/intro.
- The `LevelManager.boss_arena_entered` signal already exists but is unused.
  Planning decides whether to wire it as an early "HUD prep" hint or drop it as
  redundant — the controller's `notify_spawned` is the canonical entry.

## Data wiring (compositions, biomes, spawn paths)

### Per-biome boss scenes

Five new scenes under `scenes/enemies/bosses/`:

| File | Biome | Base stats source |
|------|-------|-------------------|
| `burrower_boss.tscn` | Caves | BurrowerBoss |
| `pyrelord_boss.tscn` | Magma | PyrelordBoss |
| `glacier_boss.tscn` | Frozen | GlacierBoss |
| `drill_boss.tscn` | Mines | DrillBoss |
| `warden_boss.tscn` | Vault | WardenBoss |

Each sets `boss_name`, `phase_count = 3`, biome-appropriate base stats, and
points `weapon_resource` at the right per-boss projectile where applicable
(Pyrelord fire orb, Glacier ice shard, Warden ricochet). Burrower and Drill set
`weapon_resource = null`.

### Repointing the 20 arena compositions

Today all 20 `assets/arenas/boss/*.tres` reference the generic
`boss_enemy.tscn` via their `FeatureBossSpawn.boss_scene`. Each biome's four
variants get repointed to that biome's boss scene — a one-line `.tres` edit per
file (the `FeatureBossSpawn` is data-driven via its `boss_scene` export, so this
is a resource edit, not a code change). Variety becomes "arena layout × biome
boss," not "arena layout × generic boss."

Planning verifies the `.tres` files are text-editable (they are committed text
resources) and that `godot --headless --path . --import` regenerates `.uid`
files cleanly after the swap.

### Spawn path consolidation

Two code paths currently spawn bosses:

1. `CompositionDispatcher.spawn_boss` — instantiates from the arena
   composition's `boss_scene` (the *intended* path; arena-composed boss rooms
   use it).
2. `SpawnDispatcher._spawn_enemy` with `is_boss = true` — hardcodes
   `BOSS_ENEMY_SCENE` + `WeaponRegistry.get_weapon_by_id("boss_staff")` (a
   duplicate legacy path).

To remove the generic-boss hardcoding:

- `SpawnDispatcher._spawn_enemy`'s `is_boss` branch is replaced with "delegate
  to the current biome's `boss_scene`" (loaded via
  `LevelManager.current_biome.boss_scene`), removing the `BOSS_ENEMY_SCENE`
  const and `boss_staff` reference. If `current_biome.boss_scene` is null, it
  falls back to skipping (logging a safe skip) — the composition path is the
  canonical one.
- `BiomeDef.boss_scene` is populated per biome (Caves→burrower, Magma→pyrelord,
  Frozen→glacier, Mines→drill, Vault→warden) so both spawn paths agree on
  biome-specific bosses.
- Planning traces *which path actually triggers* marker type 6
  (`SpawnDispatcher._spawn_entity` → `_spawn_enemy(world_pos, …, true, false)`)
  vs the composition feature. If marker 6 is dead in the composition-driven
  world, it is deleted; if both are live, one is canonicalized and the other
  removed to avoid double-spawning.

### Portal ownership migration

- `CompositionDispatcher._on_boss_died` (spawns portal locally) → replaced: the
  dispatcher calls `BossEncounter.notify_died(...)`; the controller spawns the
  portal post-animation.
- `SpawnDispatcher._on_boss_died` (spawns portal locally) → same.
- Both dispatchers' local portal-spawn helpers are deleted.

## Testing strategy

Testing follows the project's gdUnit4 patterns (suite per unit, `auto_free`,
headless via `runtest.sh`). The import step
(`godot --headless --path . --import`) is run first in any fresh worktree per
`AGENTS.md`.

### Base class `BossEnemy`

- `test_boss_phase_transition.gd` — **kept**; existing math unchanged.
  **Add** an assertion that `phase_changed` is emitted on each transition and
  that chaining on burst damage still works. Existing assertions pass unchanged.
- `test_boss_attack_cadence.gd` — **new**: `_do_attack` is called when the
  cadence timer elapses, not before; subclasses can override `_do_attack`
  cleanly; `attack_interval` / `_attack_cooldown` resets after each attack.
- `test_boss_floor_scaling.gd` — **new**: `_apply_floor_scaling(floor_num)`
  produces the documented HP/speed/damage multipliers so the duplicated
  `SpawnDispatcher` math can be deleted safely.

### Subclass phase patterns — one suite per boss

Each boss gets `test_<boss>_phases.gd` covering:

- Pattern rotation: `_pick_pattern` returns 0,1,0,1,…; `_execute_pattern` is
  called with the right index per `_do_attack`.
- Phase-specific setup: `_on_phase_enter(N)` configures the right per-phase
  state.
- Per-pattern dispatch hits only that pattern's code path — verified via
  stubbed/injected helper methods (`_start_charge`, `_spawn_dust_burst`,
  `_stamp_pit`, `_summon_elite`, …) rather than real terrain/singletons. This
  is why the base exposes facade methods — so subclasses are unit-testable
  without a full arena.
- Phase 3 hazard timer: hazards fire at `hazard_interval`, not sooner.

### `BossEncounter` controller

`test_boss_encounter_lifecycle.gd` — verifies:

- `notify_spawned` → intro runs → `set_encounter_active(true)` flips at the
  right time; HUD refs are wired.
- `phase_changed` updates HUD markers (via a HUD stub or by reading the HUD's
  public state).
- `notify_died` → death sequence plays → portal spawns exactly once, *after*
  the dissolve tween completes (tween timings injected via a `_tween_factory`
  so tests run deterministically or skip tweens entirely).
- A second `notify_spawned` while a fight is active → safely ignored/logged
  (no double-intro, no crash).
- `clear()` disconnects and hides the HUD.

The controller is tested by injecting a fake dispatcher (a `Node` that emits
the spawn/die signals) and a stubbed boss (extends `BossEnemy` with overridden
`_do_attack` / `_on_phase_enter` that just record calls). Camera/camera-effect
components are stubbed — the controller takes its camera handle via dependency
injection so headless tests don't need a real `Camera2D`.

### Saltmire dissolve integration (smoke test)

`test_boss_death_dissolve.gd` — construct the controller with a fake boss whose
sprite uses a real test texture, call `notify_died`, advance the tween, assert
the boss sprite's `material` is the Saltmire dissolve `ShaderMaterial` with
`progress` ending at 1.0, that `FX.clear` was called, and that `queue_free`
happened after. Validates the asset API contract we depend on. Headless and
deterministic via the injected-tween approach.

### Fragment streamer

`test_boss_fragment_stream.gd` — the silhouette sampler rejects transparent
pixels (feed it a known test texture with a hard-edged shape; assert all
spawned fragments land inside the silhouette) and that fragments are tweened
toward the portal position. Same injected-tween approach.

### Arena composition repoint (smoke)

`test_boss_arena_biome_match.gd` — for each biome, load its 4
`boss_compositions`; assert each `FeatureBossSpawn.boss_scene` resolves to a
`.tscn` whose root script extends the *correct* biome boss class (e.g. Caves
compositions reference `burrower_boss.tscn`, not the generic one). Catches
accidental `.tres` mis-edits.

### Existing test impact

- `test_boss_drops.gd` — unaffected (`_setup_drop_table` stays public).
- `test_boss_ring_coverage.gd` — unaffected (sector-ring geometry, unrelated).
- Any test pinning on the `BOSS_ENEMY_SCENE` const or `boss_staff` is updated to
  expect the biome scene instead; planning greps for these references.

### Run command

`GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_<suite>.gd`
(preceded by `godot --headless --path . --import` in a fresh worktree).

## Open questions for planning (not for this design)

These are implementation details the plan resolves; they do not change the
design's shape:

- Exact signature of `_steer_toward` / `_lock_navigation` movement hooks on the
  base, and whether charge bosses override `_physics_process` or a base method.
- Whether `UILayout` / `JuicyPanel` tokens are already present (Phase 6 work) or
  whether the HUD uses local constants for now.
- Whether marker type 6 (`SpawnDispatcher` boss marker) is live or dead in the
  composition-driven world — determines whether it's deleted or canonicalized.
- Whether `LevelManager.boss_arena_entered` is wired as a HUD-prep hint or
  dropped.
- Readability of `boss_test.png` via `get_image()` for silhouette sampling.
- The exact `mine` prop variant (new scene vs. configured `barrel.tscn`) for
  Drill's phase 2.