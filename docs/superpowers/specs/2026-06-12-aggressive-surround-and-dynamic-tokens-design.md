# Aggressive Surround & Dynamic Attack Tokens

**Date:** 2026-06-12
**Branch:** feat/content-expansion
**Status:** Approved (design)

## Problem

When the player stands still, enemies chase up to the surround ring and then stop
moving and stop attacking — they only jitter in place until the player moves
again. Drawing closer makes them attack correctly; backing away makes them chase
correctly. The stationary-player case is the broken one.

### Root cause

The surround ring sits at `attack_range + surround_offset` (32 + 56 = 88px).
In `Enemy._process_chase()` (`src/enemies/enemy.gd:262-302`) there is a
chicken-and-egg deadlock between the attack token and attack range:

- An enemy can only *claim* a melee attack token when `dist <= _attack_range` (32px).
- But every frame, any enemy *without* a token is steered back out to the 88px
  ring by the `_surround_dir` override.
- On its own, no enemy ever reaches 32px → no token is claimed → no attack.

When the player walks into an enemy, distance drops below 32 externally, the
claim fires, and the attack works — matching the observed "draw close = attack."

### Jitter source

Once a ring-sitter reaches its slot, `_surround_dir` returns `Vector2.ZERO`
(within 6px of the slot), so `move_dir` falls back to "charge the player." It
steps inward, next frame it is inside the ring so the slot direction points back
outward, it gets pushed out — oscillating every frame, amplified by separation.

## Goals

1. Stationary player still draws committed attackers off the ring.
2. Ring-sitters *circle* the player (pace around the ring) instead of freezing.
3. Attack pressure is dynamic: killing enemies makes the horde more aggressive;
   taking damage eases the horde off.

## Design

### 1. Break the attack deadlock (decouple permission from range)

In `_process_chase`, let an **active** enemy claim a melee token while it is
still on the ring, not only at attack range. A token-holder already bypasses the
surround override and marches straight at the player; it transitions to WINDUP
only once it actually reaches `attack_range`.

New chase flow (melee/base `Enemy`):

```
to_player, dist, sees  (unchanged)
move_dir = toward player (seen) or nav-field (unseen)   # unchanged

# Commit check: claim a token anywhere within the ring once settled.
if sees and _settle_timer >= min_attack_settle_time \
        and dist <= _attack_range + surround_offset \
        and _try_claim_attack():
    if dist <= _attack_range:
        velocity = ZERO
        _change_state(WINDUP)
        return
    # committed attacker: push straight in (skip surround), attack on arrival
    move_dir = to_player.normalized()
    velocity = _apply_separation(move_dir) * _get_effective_speed()
    return

# Not committed: orbit the ring.
var speed_mult := 1.0
if not _holds_attack_token:
    slot_dir = _surround_dir(_attack_range + surround_offset)
    if slot_dir != ZERO:
        move_dir = slot_dir                  # still travelling to the slot
    else:
        move_dir = _ring_strafe_dir()        # at the slot: circle (see §2)
        speed_mult = RING_STRAFE_MULT
velocity = _apply_separation(move_dir) * _get_effective_speed() * speed_mult
```

`_try_claim_attack()` returns `true` for an enemy that already holds the token,
and `_release_attack()` (called on any state change away from
WINDUP/ATTACK/COOLDOWN) frees it. So a committed attacker keeps its token while
closing from the ring to attack range. Effective committed-attacker count equals
the director's effective melee token count.

`ranged_enemy.gd` keeps its own attack logic; the shared token API is unchanged,
so ranged behavior is unaffected except for the dynamic token count (§3).

### 2. Wander on the ring (replace "freeze at slot")

When a non-committed enemy is at its slot (`slot_dir == ZERO`), it strafes
tangentially around the player instead of charging or stopping.

`_ring_strafe_dir()`:
- Radial = `(global_position - player_pos).normalized()`.
- Tangent = radial rotated 90° times the enemy's `_orbit_sign` (`+1`/`-1`).
- Returns the **unit** tangent. The caller sets `speed_mult = RING_STRAFE_MULT`
  (0.4) for this branch so pacing is slower than chasing. The 0.4 is applied as a
  speed scalar *after* `_apply_separation` (which normalizes direction to unit),
  so separation still spreads crowded ring-sitters without cancelling the slowdown.

Per-enemy state added to `Enemy`:
- `var _orbit_sign: float` — randomly `+1.0` or `-1.0` at `_ready`.
- `var _orbit_flip_timer: float` — counts down; on reaching 0 the sign flips and
  the timer resets to `randf_range(1.5, 3.0)`. Ticked in `_process` while in CHASE.

Separation continues to apply, so enemies spread along the ring as they pace.

### 3. Dynamic aggression tokens

`world_manager.gd` already overwrites `melee_token_count` / `ranged_token_count`
every frame from the floor number. We keep those two fields **as the per-floor
base** (no rename, no change to the world-manager assignment) and ride a
persistent **delta** on top, applied only where the budget is consumed. This
keeps existing director tests (which set `melee_token_count` directly) valid:
with `aggression_delta == 0`, the effective budget equals the base.

`EncounterDirector` changes:
- New field: `var aggression_delta: int = 0` (persists across frames; never reset
  by the per-frame base assignment).
- Constants: `const AGGRO_MIN := -2`, `const AGGRO_MAX := 4`,
  `const KILL_GAIN := 2`, `const HIT_LOSS := 1`.
- New helpers returning the dynamic budget (base + delta, floored at 1 so combat
  never fully stalls):
  - `func effective_melee_tokens() -> int: return maxi(1, melee_token_count + aggression_delta)`
  - `func effective_ranged_tokens() -> int: return maxi(1, ranged_token_count + aggression_delta)`
- `try_claim_attack` computes its budget from `effective_ranged_tokens()` /
  `effective_melee_tokens()` instead of reading the raw field directly.
- `func register_kill() -> void: aggression_delta = clampi(aggression_delta + KILL_GAIN, AGGRO_MIN, AGGRO_MAX)`
- `func register_player_hit() -> void: aggression_delta = clampi(aggression_delta - HIT_LOSS, AGGRO_MIN, AGGRO_MAX)`
- **No decay** — momentum persists until countered by the opposite event.

### 4. Wiring the events

**Kills** — in `Enemy.die()` (`src/enemies/enemy.gd:544`), after resolving the
director, call `dir.register_kill()`. All enemy deaths count as kills (enemies die
almost exclusively from player action or player-induced hazards); precise
attribution is not worth the added coupling.

**Player damage** — add a `signal damaged(amount: int)` to `PlayerInventory`,
emitted inside `take_damage` and `take_status_damage` *after* the health
reduction and the invincibility/dead guards (so it fires only on real damage).
`WorldManager` lazily connects this once: on the first `_process` frame where a
player exists, find `get_tree().get_first_node_in_group("player")`, get its
`PlayerInventory` child, and connect `damaged` to
`encounter_director.register_player_hit`. Guard with a `bool` so it connects
exactly once.

**Per-frame update** — `world_manager.gd:105-106` is **unchanged**: it keeps
setting `melee_token_count` / `ranged_token_count` from `tokens_for_floor`, which
now act as the per-floor base. `aggression_delta` lives independently and is not
touched by this assignment.

## Testing

New/updated GdUnit tests:

- **test_enemy_pursuit.gd** — stationary seen player at ring distance with a
  director that grants a token: enemy commits (claims token and moves toward the
  player, eventually WINDUP) rather than stalling. A second non-committed enemy
  at its slot produces a non-zero tangential (ring-strafe) velocity, not zero and
  not straight at the player.
- **test_encounter_director.gd** —
  - `effective_melee_tokens` = `maxi(1, melee_token_count + aggression_delta)`.
  - `register_kill` raises the delta by `KILL_GAIN`, clamped at `AGGRO_MAX`.
  - `register_player_hit` lowers it by `HIT_LOSS`, clamped at `AGGRO_MIN`.
  - Effective tokens never drop below 1 even at `AGGRO_MIN`.
  - `try_claim_attack` budget follows the effective (dynamic) count: with delta
    raising tokens, more concurrent claims succeed; with it lowered, fewer.
- Existing pursuit/surround/state-machine tests continue to pass (committed
  attackers still reach WINDUP; ranged surround unaffected).

## Out of scope

- Aggression decay over time (deliberately omitted).
- Separate melee vs. ranged aggression tracks (single shared delta).
- HUD/visual indicator of current aggression level.
- Director-driven global ring rotation (handled per-enemy via strafe instead).

## Tunables (summary)

| Name | Value | Where |
|------|-------|-------|
| `RING_STRAFE_MULT` | 0.4 | Enemy |
| orbit flip interval | 1.5–3.0s | Enemy |
| `AGGRO_MIN` / `AGGRO_MAX` | -2 / +4 | EncounterDirector |
| `KILL_GAIN` | +2 | EncounterDirector |
| `HIT_LOSS` | -1 | EncounterDirector |
| token floor | 1 | EncounterDirector (effective_*) |
