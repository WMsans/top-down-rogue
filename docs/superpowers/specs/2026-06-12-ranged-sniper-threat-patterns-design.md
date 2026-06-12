# SP2: Ranged & Sniper Threat Patterns — Design

**Phase 9, Sub-project 2.** Part of the Enemy Combat & Crowd Tension initiative
(see `docs/design_docs/implementation_todo.md`). Builds directly on **SP1 (Crowd AI &
Pursuit Foundation)**, which is implemented and merged — the attack-token pools, surround
slots, and pursuit substrate already exist.

## Problem

SP1 gave ranged enemies a *crowd* (persistent aggro, surround orbit, a ranged token pool so
only ~2 volleys are ever in flight). But every ranged enemy still fires the **same single
instantaneous bullet**. There is no per-enemy texture to the threat: nothing rewards constant
movement, nothing creates the Enter-the-Gungeon "safe gap," and there is no heavy-hitting
telegraphed threat to respect. Ranged combat reads as uniform chip damage.

This sub-project gives ranged enemies **distinct, readable firing patterns** — a default that
punishes standing still, two variants that shape the player's movement differently, and a
rare **sniper** that lands a heavy, telegraphed, cover-destroying round.

## Goals

- Each pattern is **simple and readable** — the player learns one tell and one correct
  response per pattern (move / sidestep / don't-stand-in-the-fan / break the lock).
- The **default** (aimed burst) rewards **constant movement** — re-aiming between shots means
  a stationary player gets hit, a moving player out-runs the stream.
- **Split** delivers the EtG beat: a stationary player sits **safely in the gap**; moving
  sweeps them across the bullets.
- A **sniper** adds a high-stakes, telegraphed threat that **destroys cover**, without
  out-stacking the rest (it draws from SP1's shared ranged token pool).
- All patterns ride **one shared burst engine** so timing logic lives in exactly one place.

### Non-goals (this sub-project)

- New projectile *physics* — homing, bouncing, gravity, splitting-on-impact → the separate
  Phase 9 "Projectile Behaviors" sub-project (`projectile.gd` already has a `behaviors` hook).
- Melee threat variants (lunge / shield / etc.) → **SP3**.
- Director / attack-token / pursuit changes → **SP1, done**. This SP only *consumes* the
  ranged token pool, it does not modify it.
- Terrain-hazard tension (Noita-like environmental damage) → future sub-project. The sniper's
  cover destruction uses the *existing* projectile terrain-carve; it does not add hazards.

## Design Pillars (reference feel)

- **Enter the Gungeon** — a single enemy's shot pressures *positioning*, not unavoidable
  damage. Split is the canonical case: idle = safe, movement = risk.
- **Soul Knight** — bullets *shape movement*; they are a threat you route around, not a damage
  race. The token cap (SP1) keeps the bullet count honest.
- **Hades** — committed, telegraphed attacks with a recovery window. The sniper's tracking
  aim-line that **locks** before firing is the strongest expression of this here.

## Architecture

A **burst engine added to the `RangedWeapon` base**, **one subclass per pattern**, and a
small **sustained-attack hook on the enemy**. Nothing changes in `Projectile`, the
`EncounterDirector`, or the swarm/nav systems.

```
Weapon (already has tick / _tick_impl / _cooldown_timer)
  └ RangedWeapon         ← gains the shared burst timeline
      ├ AimedBurstWeapon   _emit_shot → 1 bullet at current facing   (DEFAULT — most enemies)
      ├ SplitShotWeapon    _emit_shot → 2 bullets diverging ±gap/2   (variant)
      ├ FanWeapon          _emit_shot → 3 bullets: center + ±spread  (variant)
      └ SniperWeapon       _emit_shot → 1 heavy, penetrating round   (variant)

Enemy (already ticks its weapon every frame — enemy.gd:191)
  └ RangedEnemy          ← ATTACK state persists while weapon.is_bursting()
      └ SniperEnemy        ← long tracking aim-line telegraph that locks; weapon = SniperWeapon
                             (movement is unchanged — kites/strafes like a normal RangedEnemy)
```

Why this shape:

- **Subclass per pattern** mirrors the existing melee weapon subclasses
  (`blood_blade_weapon.gd`, etc.) — a familiar pattern in this codebase.
- **The base owns the timeline** (shot scheduling, interval, re-aim, count) so burst timing is
  written **once**, not duplicated per subclass. Each subclass overrides only the spatial
  emission of a single shot.
- **Weapon-driven cadence** (not enemy-driven) means the burst advances through the weapon's
  existing per-frame `tick(delta)` — already called for enemies (`enemy.gd:191`) **and** for
  the player (`weapon_manager.gd:113`). A player who picks up one of these ranged weapons gets
  the burst for free.

All tunables are exposed as named exports/constants for a later tuning pass.

## Component 1 — Burst timeline (in `RangedWeapon`)

New exported fields on `RangedWeapon`:

- `burst_count: int = 1` — shots per attack. **Default 1 reproduces today's single-shot
  behavior exactly** (full backward-compatibility for every existing ranged enemy/weapon).
- `burst_interval: float = 0.12` — seconds between shots in a burst.
- `reaim_each_shot: bool = false` — recompute aim from the user's facing before each shot.

Internal state: `_shots_left`, `_burst_timer`, `_burst_user` (weak/plain ref to the firing
node, used to re-aim and to spawn).

Flow:

1. `use(user)` (base `Weapon.use`, unchanged) calls `_use_impl(user)`. `RangedWeapon._use_impl`
   now **starts a burst**: fires shot 0 immediately via `_emit_shot(user, base_dir)`, stores
   `_burst_user`, sets `_shots_left = burst_count - 1`, `_burst_timer = burst_interval`.
2. `tick(delta)` (already called every frame) runs `_tick_impl(delta)`: decrement
   `_burst_timer`; when it reaches 0 and `_shots_left > 0`, fire the next shot, refill the
   timer, decrement `_shots_left`. If `reaim_each_shot`, recompute `base_dir` from
   `_get_facing_direction(_burst_user)` (which already points at the player); otherwise reuse
   the locked-in initial direction.
3. `is_bursting()` returns `_shots_left > 0` — the enemy uses this to hold its ATTACK state.

`_emit_shot(user, base_dir)` is the **only override point**. The base implementation emits the
current `projectile_count`/`spread_angle` volley (the present `_use_impl` body, relocated), so
a plain `RangedWeapon` with `burst_count == 1` behaves identically to today.

**Re-aim is the core mechanic.** With `reaim_each_shot = true`, each successive shot is aimed
where the player currently is:

- For **aimed** that is *pressure* — stand still and every shot lands; keep moving and the
  stream trails behind you.
- For **split** that is *safety* — the gap re-centers on a stationary player every shot, so
  holding still is the correct read; moving drags you across the diverging bullets.

## Component 2 — The three bullet patterns

Each is a `RangedWeapon` subclass overriding only `_emit_shot`. Starting values; **final
numbers come from playtest, not this spec.**

### AimedBurstWeapon (default — most ranged enemies)

```
o → → →     3 shots, re-aim each, ~0.12s apart
```

- `burst_count = 3`, `burst_interval ≈ 0.12`, `reaim_each_shot = true`, `damage ≈ 4`,
  `projectile_speed ≈ 140`.
- `_emit_shot` → one bullet along `base_dir`.

### SplitShotWeapon (variant)

```
  \   /     each shot = 2 bullets at ±gap/2
 o  X  you  re-aims → stationary player sits in the gap
  /   \
```

- `burst_count ≈ 2–3` pairs, `reaim_each_shot = true`, `gap_angle ≈ 30°` (±15°), `damage ≈ 4`.
- `_emit_shot` → two bullets at `base_dir ± deg_to_rad(gap_angle)/2`. No bullet ever travels
  straight down `base_dir`, so a stationary, correctly-positioned player is safe.

### FanWeapon (variant)

```
 \ | /      1–2 volleys of 3: center aimed + ±spread
 o-X→ you   a wider wall; move through a gap
```

- `burst_count ≈ 1–2`, `spread_angle ≈ 40°` (center + ±20°), `damage ≈ 4`.
- `_emit_shot` → three bullets: one along `base_dir`, two at `± spread/2`. Reuses the existing
  `projectile_count`/`spread_angle` spread math.

All three share the Component 1 loop; the only difference is the bullets one shot emits.

## Component 3 — Sniper (`SniperEnemy` + `SniperWeapon`)

The sniper is its **own enemy class** purely for its **telegraph and weapon** — its
**movement is unchanged**: it kites and strafes exactly like a normal `RangedEnemy`
(inherited `_process_chase`), surround-orbits when it lacks a token, and is subject to the
same pursuit/rubber-band rules from SP1.

### Tracking aim-line telegraph that locks

Rendered by `SniperEnemy` as a `Line2D` child, driven by the existing WINDUP state (which
already gates the enemy's telegraph):

- **Track phase** (most of a long `windup_duration ≈ 1.2s`): the line follows the player —
  amber, thin.
- **Lock window** (final `lock_time ≈ 0.3s`): the line **freezes** on the player's
  then-current position and shifts colour (amber → red). The freeze is the dodge cue.
- **Fire**: on ATTACK the shot travels down the **locked** direction, not live facing. The
  sniper overrides the aim source so that a player who moves *after* the lock is not tracked.

Implementation: `SniperEnemy` adds a `_lock_dir` captured at the start of the lock window and a
`_lock_timer` sub-phase within WINDUP; `SniperWeapon` fires along the user's
`get_facing_direction()`, and `SniperEnemy.get_facing_direction()` returns `_lock_dir` once
locked. `burst_count = 1` (a single round — no burst loop needed).

### Heavy round + cover destruction

- `SniperWeapon`: `burst_count = 1`, high `damage ≈ 20`, fast `projectile_speed`,
  long `cooldown ≈ 2.5–3s`.
- The round **penetrates** a short distance through terrain via a small `ProjectileBehavior`
  (returns `true` from `on_terrain_hit` until a penetration budget is spent), carving a
  **channel** rather than stopping at first contact. `Projectile._carve_terrain` already scales
  its arc by `damage`, so a heavy round destroys cover — the "heavy terrain destruction" beat,
  and a natural tie-in to the future terrain-tension sub-project.
- Draws from SP1's **shared ranged token pool**, so a sniper volley counts against the ~2
  ranged budget and never stacks on top of other ranged fire.

## Component 4 — Enemy integration

The one enemy-side change: the **ATTACK state must persist while the weapon is mid-burst**
(today it fires once and immediately goes to COOLDOWN — `enemy.gd:319-321`).

- New hook `Enemy._attack_in_progress() -> bool`, **default `false`**. Melee enemies and any
  single-shot ranged weapon keep today's instantaneous fire — **zero behavior change, existing
  state-machine tests untouched.**
- `RangedEnemy` overrides it: `return weapon != null and weapon.is_bursting()`.
- `_process_attack` becomes: on entering ATTACK, `_execute_attack()` starts the burst (fires
  shot 0); while `_attack_in_progress()`, **stay in ATTACK** so the per-frame `weapon.tick`
  runs the remaining shots; once it returns `false`, transition to COOLDOWN.
- The SP1 **ranged attack token is held across the whole burst** (claimed at
  CHASE → WINDUP, released at end of COOLDOWN — unchanged). Bursts simply make ATTACK a little
  longer, which is intended.

### Distribution / content wiring

- A plain `RangedEnemy` defaults to an `AimedBurstWeapon` resource → most ranged enemies fire
  the aimed burst.
- **Split** and **fan** are assigned by giving an enemy the corresponding `weapon_resource`
  `.tres` on its spawn marker / tier table — a content-wiring step, not new code.
- **Sniper** is a distinct, rarer spawn entry, gated to deeper sectors.

## Testing

Pure-logic unit tests (GdUnit4, `tests/`). Weapons are kept headless-testable by injecting a
spawn sink (a `Callable`/override capturing emitted shot directions) instead of instancing the
projectile scene:

- **Burst count & cadence**: `burst_count` shots fire, one per `burst_interval`;
  `is_bursting()` is `true` during the burst and `false` after the last shot.
- **Backward-compat**: `burst_count == 1` emits exactly one shot and never enters the burst
  loop (existing single-shot enemies unchanged).
- **Re-aim**: with `reaim_each_shot = true`, changing the user's facing mid-burst changes the
  direction of later shots; with it `false`, all shots share the initial direction.
- **Pattern geometry**: aimed emits 1 bullet along facing; split emits 2 at `±gap/2` with none
  along facing; fan emits 3 (center + `±spread/2`).
- **Sniper lock**: the fired direction equals the direction captured at the lock window, even
  if the player moves afterward.
- **Enemy sustain**: `RangedEnemy._attack_in_progress()` is `true` mid-burst and holds ATTACK;
  a melee enemy reports `false` and keeps instantaneous attack (regression guard).

Manual playtest checklist:

- Standing still is *safe* vs split but *punished* vs aimed burst; fan forces a sidestep.
- The sniper's lock is readable; its round visibly destroys cover and hurts.
- With a ranged crowd, only ~2 volleys are ever in flight at once (SP1 token cap still holds).
- A player who picks up a burst/split/fan ranged weapon fires it correctly (weapon-driven
  cadence works outside the enemy too).

## Risks

- **Burst mid-flight on death/despawn** — the firing enemy can die between shots. The weapon
  must guard `is_instance_valid(_burst_user)` before each scheduled shot and end the burst if
  the user is gone (no orphaned shots, no held ATTACK on a dead node). Covered by the SP1
  token-release-on-death backstop plus a direct guard.
- **Re-aim feels unfair if too tight** — re-aiming every 0.12s on the aimed burst could feel
  like perfect tracking. `burst_interval` and `burst_count` are the dials; the player must be
  able to out-run the stream by moving. Watch in the tuning pass.
- **Sniper cover destruction vs. level integrity** — a penetrating, terrain-carving round could
  over-erode the world over a long fight. Penetration budget and carve radius are bounded and
  tuned; this is the #1 thing to watch when the round lands repeatedly in one spot.
- **ATTACK-state hold + interrupts** — a sustained ATTACK must still yield to HURT/DEATH (knock-
  back, death) the way the instantaneous one does; the burst is abandoned cleanly on a state
  change out of ATTACK.
- **Token held longer during bursts** — a burst extends ATTACK, so a ranged token is held
  marginally longer. Intended, but if ranged fire feels too sparse, the ranged pool size (an
  SP1 tunable) is the lever, not this SP.
