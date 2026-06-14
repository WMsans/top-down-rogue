# SP3: Melee Lunge Variant — Design

Phase 9 (Enemy Combat & Crowd Tension), Sub-project 3. Builds on SP1 (Crowd AI &
Pursuit Foundation) and the SP2 enemy-attack hooks. This sub-project ships the
**Lunge** variant only; Shield-front and Pounce remain documented future work.

## Problem

SP1 made crowds pursue and SP2 gave ranged enemies readable firing patterns, but every
melee enemy still does exactly one thing: walk into reach and swing. There is no melee
threat that punishes standing still or rewards reading a tell and side-stepping. The
player can hold ground against a melee crowd and trade hits with no positional pressure.

## Goals

- A telegraphed melee enemy that **commits** to a dash: windup → dash/overshoot →
  recovery/punish window (references: Hades committed attacks, Dark Souls-style
  reposition-and-punish).
- Reward **movement**: a player who reads the tell and side-steps takes no damage and gets
  a free hit on the helpless attacker.
- Keep the default melee enemy — walk-in-and-swing — exactly as it is today, as the
  majority of melee spawns.

## Non-goals

- **Shield-front variant** — deferred to a future sub-project (frontal-block + flank).
- **Pounce variant** — deferred (P3, ground-ring leap).
- **No new telegraph widget** — the lunge tell reuses the existing `!` exclaim plus a
  windup flash/anticipation; no aim-line or ground decal (chosen for a lightweight tell).
- **No new state-machine states** — the lunge maps onto the existing
  WANDER → CHASE → WINDUP → ATTACK → COOLDOWN flow.
- **No director/spawning-rules changes** beyond adding the lunge to the melee weighting.

## Architecture

One new thin subclass plus one opt-in base hook:

```
Enemy (CharacterBody2D)
 ├─ _moves_during_attack() -> bool   [NEW hook, default false]
 │     gates one extra line in _physics_process
 └─ MeleeEnemy
      └─ LungeEnemy   [NEW]
           - overrides _ready (longer trigger range + lunge tunables)
           - overrides _process_attack / _execute_attack (the dash)
           - overrides _moves_during_attack (true while dashing)
           - adds a windup-flash telegraph
```

Rationale: the lunge **is** a committed dash during the existing `ATTACK` state, with the
recovery window living in the existing `COOLDOWN` state. This mirrors how `SniperEnemy`
reused `WINDUP` for its telegraph and how SP2 added the opt-in `_attack_in_progress()`
hook without disturbing other enemies. Every existing enemy is behaviorally unchanged
because the one new hook defaults to `false`.

`LungeEnemy extends MeleeEnemy` (not `Enemy`) to reuse the `weapon_resource` duplication,
drop-table setup, and weapon-visual plumbing. The lunge carries a normal melee weapon
purely for `weapon.damage` (so floor `damage_scale` applies), the held-weapon visual, and
the weapon drop on death — it does **not** call `weapon.use()`; its damage comes from the
body-check.

## State flow

Reuses the existing five states; only the per-state behavior in `ATTACK`/`COOLDOWN` and
the trigger range differ from a normal melee enemy.

| State | Lunge behavior |
|-------|----------------|
| WANDER / CHASE | Inherited from `MeleeEnemy`. The only difference: `_attack_range ≈ 120px` (a gap-closer) instead of the small melee reach, so it commits from further out. |
| WINDUP (`~0.45s`) | Stands still, faces the player, shows the existing `!` exclaim **plus** a warning flash / anticipation squash. The **dash direction locks at the end of windup** — the player can side-step the telegraph. |
| ATTACK (the dash, `~0.22s`) | Moves fast (`dash_speed ≈ 420`) along the locked direction, overshooting the player's telegraphed position. **Body-check**: the first frame it comes within `contact_radius (~18px)` of the player it deals `weapon.damage` once via `player.on_hit_impact(pos, lock_dir, dmg)` and sets a one-hit flag. The dash ends on a timer **or** when `_move_with_clamp` stops it against terrain (no phasing through walls). |
| COOLDOWN (the punish window, `~1.0s`) | Stationary and helpless — the existing `_process_cooldown` already lerps velocity to zero. A desaturate / stagger tint reads "punish me now." After it expires, returns to CHASE/WANDER as normal. |

## Components

### 1. Base hook — `src/enemies/enemy.gd`

```gdscript
func _moves_during_attack() -> bool:
    return false
```

And the movement gate in `_physics_process` gains one clause:

```gdscript
if _state == State.WANDER or _state == State.CHASE or _state == State.HURT \
        or (_state == State.ATTACK and _moves_during_attack()):
    _move_with_clamp(delta)
```

This keeps dash movement consistent with all other movement (velocity set in `_process`,
applied with terrain clamping in `_physics_process`). Default `false` ⇒ no behavior change
for any existing enemy.

### 2. `LungeEnemy` — `src/enemies/lunge_enemy.gd`

```gdscript
class_name LungeEnemy
extends MeleeEnemy

@export var lunge_range: float = 120.0
@export var dash_speed: float = 420.0
@export var dash_duration: float = 0.22
@export var contact_radius: float = 18.0
@export var recovery_duration: float = 1.0

var _lock_dir: Vector2 = Vector2.DOWN
var _dash_timer: float = 0.0
var _dash_hit: bool = false
var _dash_done: bool = false   # prevents dash restart after a HURT interrupt
```

Responsibilities:
- `_ready`: call `super._ready()`, then widen `_attack_range = lunge_range`, lengthen
  `windup_duration ≈ 0.45`, and set `cooldown_duration = recovery_duration`.
- `_change_state`: on entering `WINDUP`, reset `_dash_done = false`. (So the dash can only
  fire once per windup→attack cycle.)
- `_execute_attack` / dash begin: lock `_lock_dir` to the player direction, set
  `_dash_timer = dash_duration`, clear `_dash_hit`.
- `_process_attack(delta)`: if `_dash_done`, go straight to `COOLDOWN`. Otherwise drive the
  dash — set `velocity = _lock_dir * dash_speed`, count down `_dash_timer`, run the
  body-check, and when the timer hits zero (or terrain halts it) set `_dash_done = true`
  and `_change_state(COOLDOWN)`.
- `_moves_during_attack`: returns `true` while the dash is live.
- Windup telegraph: a warning color pulse (and optional anticipation squash) during
  WINDUP, reusing the existing tween/flash mechanics.

### 3. Scene — `scenes/enemies/lunge_enemy.tscn`

Instances `enemy.tscn` (or duplicates `melee_enemy.tscn`), attaches `lunge_enemy.gd`,
reuses an existing enemy sprite. No new art.

### 4. Spawn wiring — `src/core/spawn_dispatcher.gd`

A minority of non-elite melee spawns become lunges; the default walk-in-and-swing enemy
stays the majority. Within the current melee branch (`randf() < 0.8`), roll ~25% →
`LungeEnemy`, else the existing `MeleeEnemy`. `LungeEnemy` still gets a melee weapon via the
existing `_pick_melee_weapon()`.

## Edge cases & handling

- **Hit mid-dash**: `HURT` preempts (knockback) as it does for any enemy. Because
  `_process_hurt` returns to `_prev_state` (the `ATTACK` state) and `_change_state(ATTACK)`
  resets `_attack_started`, the dash would otherwise *restart*. The `_dash_done` flag —
  reset only on `WINDUP` entry — prevents that: on return the dash is already "done" and it
  falls through to `COOLDOWN`/recovery.
- **Body-check vs. player i-frames**: the player's inventory grants invincibility frames
  after a hit, so repeated `on_hit_impact` calls would not double-damage — but they *would*
  re-apply knockback/flash. The one-hit-per-dash `_dash_hit` flag prevents that.
- **Loses sight during windup**: inherits the existing
  `_process_windup` → WANDER bail when the player can't be seen.
- **Terrain mid-dash**: `_move_with_clamp` axis-clamps against solids, so the dash stops at
  a wall instead of phasing through; the recovery window still triggers.
- **Death mid-dash**: `_state == DEATH` short-circuits `_process` before `_process_attack`
  runs, as for any enemy — no special handling needed.

## Testing

GdUnit4 headless (`tests/unit/test_lunge_enemy.gd`), with a `_MockPlayer extends Node2D`
in the `player` group that records `on_hit_impact(pos, dir, dmg)` calls:

- Base regression: a plain `Enemy`/`MeleeEnemy` reports `_moves_during_attack() == false`.
- Dash begins on `ATTACK` entry: `_lock_dir` is set toward the player and `velocity`
  points along it during the dash.
- Body-check fires exactly **once** within `contact_radius`, with `weapon.damage`.
- A player outside `contact_radius` for the whole dash takes **zero** hits (side-step is
  safe).
- The dash terminates into `COOLDOWN` after `dash_duration`.
- `_dash_done` blocks a second dash within the same attack cycle (HURT-interrupt guard).
- Spawn distribution: rolling the melee branch yields some `LungeEnemy` instances while the
  default `MeleeEnemy` stays the majority.

Manual playtest checklist: tell is readable; side-stepping dodges and exposes a punish
window; the dash stops at walls; default melee enemies are unchanged.

## Risks

- **Tuning** (`lunge_range`, `dash_speed`, `dash_duration`, `recovery_duration`): too fast
  or too long an overshoot makes the tell unreadable or the punish window unfair. Values
  above are starting points; expect a tuning pass during the manual playtest.
- **Dash + separation/knockback interplay**: the dash sets `velocity` directly each frame,
  overriding separation steering during `ATTACK` (intended — a committed attack ignores the
  crowd). Knockback only applies via `HURT`, which preempts the dash, so they don't fight.
- **Recovery readability**: if the desaturate/stagger tint is too subtle, players may not
  register the punish window. Polish item, flagged for playtest.
