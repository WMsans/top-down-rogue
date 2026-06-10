# SP1: Crowd AI & Pursuit Foundation — Design

**Phase 9, Sub-project 1.** Part of the Enemy Combat & Crowd Tension initiative
(see `docs/design_docs/implementation_todo.md`).

## Problem

Enemies are individually too weak. With starting weapons the player either out-damages
everything trivially or simply **skips every fight** — in the open, streamed world, enemies
leash and give up (~280px) while the player moves at 2× their speed, so the optimal play is
to walk straight to the boss. There is no crowd tension and no reason to engage.

The fix must live in **AI + spawning**, not level geometry — the open layout is fixed and
intentional (it's a roguelike, the freedom to roam stays).

## Goals

- Each enemy stays **simple and readable**; tension comes from **crowds** and **unavoidable
  pursuit**, not per-enemy lethality.
- The player **cannot trivially skip** to the boss; skipping converts into dragging a growing
  horde that overwhelms when they finally stop.
- A crowd **surrounds and choreographs** — only a bounded number commit to an attack at once,
  the rest circle and flank, so fights are tense but **fair and readable** (Hades model).
- Disengagement feels fair: the player **always sets the tempo** (the horde keeps pace but
  never outruns them).

### Non-goals (this sub-project)

- New per-enemy attack patterns (burst/split/fan/sniper ranged, lunge/shield melee) → **SP2,
  SP3**.
- Terrain hazard buffs (Noita-like environmental tension) → future sub-project.
- Level geometry / room-locking changes — the open layout is intentionally unchanged.
- New enemy classes — we enrich the existing `MeleeEnemy` / `RangedEnemy`.

## Design Pillars (reference feel)

- **Enter the Gungeon** — a single enemy's attack should pressure *positioning*, not deal
  unavoidable damage; danger emerges from many threats at once.
- **Hades** — telegraphed, committed attacks with recovery windows; an **attack-token**
  budget so a crowd surrounds you but only a few commit at a time.
- **Soul Knight** — melee and terrain carry the threat; bullets shape movement. (Bullet/melee
  *patterns* land in SP2/SP3; this SP builds the crowd substrate they plug into.)

## Architecture

A new **`EncounterDirector`** — a `RefCounted` owned by `WorldManager`, mirroring how
`WorldManager` already owns `swarm_grid` (a per-frame enemy spatial hash) and `nav_field` (a
player-centered flow field enemies sample for pathing). Every enemy already holds a
`_world_manager` reference, so enemies reach the director through that existing handle with no
new dependencies.

`WorldManager` already rebuilds `swarm_grid` each frame from the `attackable` group; the
director's per-frame update (surround-slot assignment, token bookkeeping) hooks into the same
`_process` step, after the swarm grid is rebuilt.

The `EncounterDirector` owns:

- **Active-pursuer set** — the aggroed horde, soft-capped (see below).
- **Surround-slot assignment** — a target angle on a ring around the player for each active
  pursuer.
- **Attack-token pools** — separate small budgets for melee and ranged commits.

`enemy.gd` (and `melee_enemy.gd` / `ranged_enemy.gd`) gain a small number of hooks that query
the director; the AI state machine is otherwise unchanged in shape.

All tunables in this design are exposed as named constants/exports for a later tuning pass.

## Component 1 — Pursuit subsystem (persistent aggro + contagion + rubber-band)

### Persistent aggro

In `Enemy._process_chase`, once `_aggroed` is `true`, the `dist > leash_radius` give-up no
longer applies — the enemy paths toward the player indefinitely. It already falls back to
`_nav_field_dir()` when it loses line-of-sight, so pursuit through walls/around corners works
via the existing nav field. `leash_radius` continues to govern only the *pre-aggro* sticky
window (before the enemy has ever seen the player).

### Aggro contagion

Each frame, a `WANDER` enemy queries its `swarm_grid` neighbors; if any neighbor is aggroed
within `CONTAGION_RADIUS` (~48px), it aggros as well. This chains enemy-to-enemy, so a moving
horde sweeps up stragglers as it passes them. There is **no aggro aura on the player** — a
pocket of enemies stays asleep until the horde physically reaches it, preserving the choice of
*where* to start a fight while removing the ability to *skip* it.

### Rubber-band catch-up ("keep pace, never exceed")

A pursuer's effective movement speed lerps from its base speed (when within a tether distance)
up toward `player_speed * SPEED_CAP_FRACTION` (≈0.95) when it falls beyond the tether,
**hard-capped just under player speed**. The horde therefore never falls away and never
outruns the player — the player always sets the tempo and can fight on the move. This layers
on top of the existing lock-on speed multipliers (`TARGETED_SPEED_MULT`, etc.); the
player-speed cap is applied **last** so it always holds.

### Horde soft-cap

The director admits at most `HORDE_SOFT_CAP` (~12–15) enemies to the active-pursuer set.
Additional woken enemies remain aggroed in spirit but **hang back / wander** until a slot frees
(an active pursuer dies or despawns). This bounds both fairness (fights stay readable even if
the player sweeps a whole floor) and frame time.

## Component 2 — Surround steering

Each frame the director distributes the active pursuers around the player by assigning each a
**target angle** on a ring at its preferred radius:

- Melee: just outside its attack range.
- Ranged: around its `preferred_distance`.

Angles are spread to fill the ring (even angular distribution over the active set, biased
toward each enemy's current bearing to avoid whiplash). An enemy **without an attack token**
steers toward its assigned slot and **orbits** there instead of pressing into attack range.
Existing `swarm_grid` separation keeps bodies from overlapping. The result is a crowd that
fans out and cuts off escape routes — replacing today's clump-on-one-side — while staying
spread enough to read.

## Component 3 — Attack-token budget

A shared budget gates who is allowed to *commit* to an attack, with **separate pools for melee
and ranged**:

- An enemy may transition `CHASE → WINDUP` (raise the `!`, begin its attack) only if it can
  **claim a token** from its pool (melee enemies from the melee pool, ranged from the ranged
  pool).
- It **holds** the token through `WINDUP → ATTACK → COOLDOWN` and **releases** it when
  cooldown ends — or immediately on death/despawn (see Risks).
- With no token available, it stays in `CHASE`, orbiting at its surround slot, awaiting a turn.

Budgets are small and scale gently with floor depth:

- Melee pool: `~2`, +1 deep into a run (cap ~3).
- Ranged pool: `~2`, scaling similarly.

So a mob of 12 has at most ~2 melee committing and ~2 ranged volleys in flight at once; the
rest circle. High tension, preserved readability — the player always has a tell to react to.

## Component 4 — Gauntlet spawning (seasoning, P2)

Builds on the existing `spawn_dispatcher`, which places enemies from room markers and already
scales enemy *tier* by sector distance from origin:

- **Density multiplier** keyed to the same sector distance — sectors closer to the boss spawn
  more bodies.
- **Reinforcement trickle** — if the player lingers in a sector past a timer, spawn 1–2 extra
  enemies, **hard-capped per sector** and never within the player's view.

Deliberately light: it accents the horde, it does not replace it.

## Component 5 — Baseline tuning pass (P2)

The token gate is what makes harder hits safe — since only ~2 melee + 2 ranged land at once,
per-hit damage can rise without a damage-race:

- **Individual enemies stay low-HP / killable** (~melee 15, ~ranged 12 today, roughly kept) —
  simplicity preserved.
- **Per-hit damage up moderately** so a crowd genuinely threatens the player's 100 HP.
- **Pursuit speed band**: base ~50–60, rubber-band cap ≈ `player_speed * 0.95` (~114).
- **Crowd sizes** bumped moderately per sector.

All values are starting points + dials; **final numbers come from playtest, not this spec.**

## Testing

Unit tests (GdUnit4, `tests/`):

- Token pool never exceeds its budget; a claim fails when the pool is empty.
- A token is **released on enemy death/despawn** mid-attack (no leak).
- Rubber-band effective speed **never exceeds** player speed, even combined with the lock-on
  multipliers.
- Aggro contagion: an idle enemy with an aggroed neighbor inside `CONTAGION_RADIUS` becomes
  aggroed; one outside does not.
- Surround assignment distributes active pursuers across distinct angles around the player.
- Horde soft-cap: active-pursuer set never exceeds `HORDE_SOFT_CAP`; a freed slot admits a
  waiting enemy.

Manual playtest checklist:

- Walking toward the boss accumulates a horde that does not fall away.
- On stopping, the crowd surrounds rather than clumping; escape routes get cut off.
- At most ~2 melee + ~2 ranged are attacking at any instant; others circle.
- The horde keeps pace but never outruns the player.
- Reaching the boss with a dragged horde is tense but survivable with skilled play.

## Risks

- **Token / slot leaks on death** — a killed enemy mid-attack must release its token and free
  its surround slot, or the budget starves and attacks stop. Explicitly tested; the director
  must reconcile against the live `attackable` set each frame as a backstop.
- **Performance with large hordes** — bounded by `HORDE_SOFT_CAP` plus **throttled
  `_can_see_player()` raycasts** (every ~3–4 frames per enemy, staggered). `nav_field` is a
  single shared field, so per-enemy pathing is O(1).
- **Rubber-band vs. lock-on multipliers** — apply the player-speed cap last so it always holds.
- **Aggro contagion runaway** — bounded by the soft-cap; only capped active pursuers steer with
  full speed/aggression.
- **Horde-meets-boss** — the dragged horde arrives at the boss arena. This is intended tension,
  but is the #1 thing to watch in the tuning pass so it does not become an unfair wall.
