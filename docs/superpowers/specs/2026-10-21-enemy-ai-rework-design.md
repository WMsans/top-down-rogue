# Enemy AI Rework (Katana ZERO Aggression / Soul Knight Pressure) — Design

**Date:** 2026-10-21
**Scope:** Phase 0 task "Behavior-based difficulty" and Phase 1 task "Enemy tier behavior profiles" in `docs/design_docs/implementation_todo2.md`, plus a general enemy AI upgrade.
**Status:** Approved design, ready for implementation plan.
**Builds on:** `2026-10-20-combat-rework-design.md` (hit-count model; enemies have no damage stat; difficulty comes from behavior).

> **Pre-playtest numbers.** Every number in this spec is a tuning starting point.

---

## 1. Problem

After the combat rework, normal enemies die in one hit and the player has 3 HP + 3 regenerating armor. Enemy behavior was tuned for the old HP model and now feels easy on every axis:

- **Too passive.** Every enemy the player is *not* targeting runs at 0.7× speed and 1.5× cooldown (`TARGETED_*` / `PASSIVE_*` in `enemy.gd`), so effectively one enemy fights at a time. Melee rests ~0.8s after each swing.
- **Too predictable.** Melee locks its swing direction at windup start; ranged fires at the player's current position; nothing follows up a whiffed dodge.
- **No group pressure.** Enemies don't surround, flank or space out; the player handles them one by one.

## 2. Goals

- **Katana ZERO aggression:** enemies react fast on sight, commit, track through their telegraph, chain attacks, and leave a clear punish window.
- **Soul Knight pressure:** ranged enemies move between volleys, fire readable patterns, lead their shots; groups threaten together.
- **Fair:** every attack keeps a visible telegraph ("!", aim line, flash). Difficulty comes from behavior, never from stats.
- **Tiers as behavior:** EASY / NORMAL / HARD differ in telegraph, cadence, reaction, chaining, volley size and leading.

## 3. Architecture

### 3.1 `EnemyProfile` (`src/enemies/enemy_profile.gd`, new)

`class_name EnemyProfile extends RefCounted`. Pure data; built by `static func for_tier(tier: int, elite: bool = false) -> EnemyProfile`.

| Field | EASY | NORMAL | HARD |
|---|---|---|---|
| `telegraph_mult` (scales windup durations) | 1.25 | 1.0 | 0.75 |
| `cadence_mult` (scales recovery/cooldown) | 1.2 | 1.0 | 0.7 |
| `reaction_time` (first sight → acting) | 0.35s | 0.2s | 0.1s |
| `chain_attacks` (melee swings per commit) | 1 | 2 | 2 |
| `volley_bonus` (extra projectiles or burst shots) | 0 | 1 | 2 |
| `lead_factor` (shot leading, 0–1) | 0.0 | 0.5 | 0.9 |
| `lunge_redirect` (one mid-dash steer) | false | false | true |

**Elite step-up:** `for_tier(tier, true)` returns the next tier's values for `telegraph_mult`, `cadence_mult` and `lead_factor` (HARD stays HARD) and sets `lunge_redirect = true`. Other fields keep the base tier's values.

Each `Enemy` builds its profile once in `_ready()` from `enemy_tier` and `is_elite` and stores it in `profile`. Bosses use `for_tier(HARD)`.

### 3.2 Attack tokens (`src/core/encounter_director.gd`)

An enemy must hold a token to enter `WINDUP`. Tokens limit how many enemies attack *at once*; they never slow anyone down.

- `request_token(enemy) -> bool`, `release_token(enemy)`, `has_token(enemy) -> bool`.
- **Capacity:** `max_tokens = 4` at the start of a floor (tier band EASY), `6` from the second tier band onward (NORMAL/HARD — derived from the highest `enemy_tier` among active enemies), `+1` per elite currently in `_active`. No other cap.
- **Cost:** melee and lunge cost 1.0; ranged and sniper cost 0.5. The pool is a float sum against `max_tokens`.
- **Player facing (sampled):** the director keeps a cached `_player_facing: Vector2`, refreshed from `PlayerController.get_facing_direction()` only every `FACING_POLL_INTERVAL = 2.0`s (ticked in `update()`). The live facing flips too often to steer the group; everything below that says "player facing" means this cached value.
- **Priority:** when more enemies request than the pool can admit in a tick, enemies **outside the player's aim cone (±45° of the cached player facing)** are admitted first; ties go to the closest enemy.
- **Release:** on death, stun/frozen, entering `HURT`, losing aggro, finishing `RECOVER`, or **timeout** (token held 3.0s without entering `ATTACK`).
- `update()` (already called every tick by `WorldManager`) also prunes tokens and slots owned by invalid or non-pursuing enemies and ticks token timeouts.
- **Bosses** don't use tokens: they always may attack and don't count against the pool.

### 3.3 State machine (`src/enemies/enemy.gd`)

States become `WANDER, CHASE, REPOSITION, WINDUP, ATTACK, RECOVER, HURT, DEATH`. `COOLDOWN` is renamed `RECOVER`: the enemy stands still (velocity decays as today) for `cooldown_duration × profile.cadence_mult`, releases its token on exit, and returns to `CHASE` (or `WANDER` if the player is out of range).

`REPOSITION` moves the enemy to a target point (`_reposition_target`) at full effective speed, with separation, until within 6px or a per-entry time limit; then returns to `CHASE`.

**Removed:** `TARGETED_SPEED_MULT`, `TARGETED_COOLDOWN_MULT`, `PASSIVE_SPEED_MULT`, `PASSIVE_COOLDOWN_MULT`, `_is_targeted()`, `_base_effective_speed()`'s target branching, and `_get_cooldown_multiplier()`. `_get_effective_speed()` keeps status multipliers and catch-up.

Subclasses keep overriding the same hooks (`_process_chase`, `_execute_attack`, `_process_attack`, `_change_state`); scenes are unchanged.

## 4. Group pressure

### 4.1 Engagement ring (melee and lunge without a token)

- Ring radius = the enemy's `_attack_range + 24px` around the player.
- `EncounterDirector.assign_slot(enemy) -> Vector2` hands out angle slots: slots are spaced evenly by angle across the enemies currently on the ring; each enemy gets the free slot nearest its current angle. With **3 or more** enemies on the ring, one slot is fixed directly **behind the player** (cached player facing + 180°, see 3.2).
- Slots are re-evaluated every 0.5s and when ring membership changes.
- On the ring an enemy moves toward its slot at **normal effective speed** along the ring, with ±8px radial jitter re-rolled every 0.4s, so it never freezes.
- Every 0.6s it re-requests a token; on success it leaves the ring and attacks (Section 5).
- A slot inside solid terrain (`nav_field.is_solid_world`) is skipped for the next free angle; if none is valid the enemy falls back to plain chase.

### 4.2 Ranged spacing (ranged and sniper without a token)

The enemy picks a firing spot and walks there in `REPOSITION`. A candidate spot must be:

- 100–150px from the player,
- in line of sight of the player (one raycast per candidate, ≤8 candidates per pick),
- ≥40px from every other ranged enemy's current firing spot,
- not in solid terrain.

Candidates are sampled on an arc around the player biased toward the enemy's current side. A spot is re-picked every 1.5s, when line of sight breaks, or after each volley. If no candidate passes, the enemy keeps its current position and strafes as today.

### 4.3 Alert broadcast

The existing 48px neighbor contagion stays. Additionally, when an enemy first sees the player it calls `EncounterDirector.alert(position, 120.0)`; every non-aggroed enemy within 120px aggroes after its own `profile.reaction_time`.

## 5. Per-enemy behavior

### 5.1 Shared helpers (`enemy.gd`)

- `_predict_player_pos(travel_time: float) -> Vector2` = player position + player velocity × `travel_time` × `profile.lead_factor`.
- **Reaction delay:** on the WANDER → CHASE transition from direct sight, the enemy waits `profile.reaction_time` (velocity zero, "!" not shown) before chasing.
- Windup durations are multiplied by `profile.telegraph_mult` in `_change_state(WINDUP)`.
- Losing line of sight during `WINDUP` releases the token and returns to `CHASE` (keeps aggro) instead of `WANDER`.

### 5.2 Melee (`melee_enemy.gd`, weaponed and weaponless)

- **Tracking windup:** the swing direction follows the player during `WINDUP` and locks for the final 0.1s. `get_facing_direction()` returns the locked direction once locked.
- **Chain:** after a swing, if `profile.chain_attacks ≥ 2` and the player is within reach + 16px, the enemy steps 16px toward the player and does a follow-up swing with windup `0.2s × telegraph_mult` (re-aimed, own "!"). Max swings per commit = `chain_attacks`.
- Then `RECOVER`.

### 5.3 Lunge (`lunge_enemy.gd`)

- Dash direction aims at `_predict_player_pos(distance / dash_speed)`.
- If `profile.lunge_redirect`: at half the dash duration, steer the dash direction toward the player's current position by at most 30°, once.
- Windup = 0.45s × `telegraph_mult`. Recovery = `recovery_duration × cadence_mult`.

### 5.4 Ranged (`ranged_enemy.gd`)

Loop: `REPOSITION` (0.6–1.2s, to a firing spot from 4.2) → stop → request token → `WINDUP` ("!") → volley → `RECOVER` → `REPOSITION`. It never stands still between volleys except during windup and recovery.

- **Volley shape:** the enemy's weapon copy gets `projectile_count += volley_bonus` if the base weapon is a fan (`projectile_count > 1`), otherwise `burst_count += volley_bonus`. Applied once in `_ready()`.
- **Aim:** shots fire at `_predict_player_pos(distance / projectile_speed)`.

### 5.5 Sniper (`sniper_enemy.gd`)

- The aim line tracks the *predicted* position; the lock 0.3s before firing freezes on the predicted direction at that moment.
- Windup = 1.2s × `telegraph_mult`.
- Always `REPOSITION` to a new firing spot after a shot.

### 5.6 Boss (`boss_enemy.gd`)

- HARD profile for `lead_factor` and `cadence_mult`; shots aim with `_predict_player_pos`.
- No tokens. Phase mechanics unchanged.

### 5.7 Elites

FAST / TANK / TELEPORT / ENRAGE stay as they are and apply on top of the profile. A hit on an elite during `WINDUP` or a chain cancels the attack (enters `HURT`) and releases its token.

## 6. Debug overlay

Console command `ai_debug` (new `AiDebugCommands`, registered in `console_manager.gd` like the other command groups) toggles a world-space overlay node that draws:

- token holders (red ring around the enemy),
- assigned ring slots (dots),
- ranged firing spots (crosses),
- predicted aim points (small circle + line from the enemy).

## 7. Testing

New unit tests (gdUnit4):

- `EnemyProfile.for_tier` values per tier; elite step-up.
- Cached player facing refreshes only every 2.0s and ignores facing changes in between.
- Token capacity (4 / 6 / +1 per elite), 0.5 cost for ranged, aim-cone priority, release on death/stun/hurt/timeout, pruning in `update()`, bosses bypass tokens.
- Slot assignment: distinct slots for N enemies; with N ≥ 3 one slot is behind the player; solid slots skipped.
- Ranged spot picker: distance band, 40px spacing, solid rejection.
- Alert broadcast aggroes enemies within 120px only.
- `_predict_player_pos` with lead 0 / 0.5 / 1.
- Melee windup tracks then locks; chain only when `chain_attacks ≥ 2` and in range.
- Lunge aims at prediction; redirect capped at 30° and only when enabled.
- Ranged volley shape from `volley_bonus` (fan vs. burst).
- Sniper locks predicted direction.
- Windup/recovery durations scale with the profile.

Updated tests: `tests/unit/test_enemy_aggression.gd` only covers the removed `_is_targeted` and `TARGETED_*` / `PASSIVE_*` behavior — delete it. Any test referencing `State.COOLDOWN` moves to `State.RECOVER`.

## 8. Files

| File | Change |
|---|---|
| `src/enemies/enemy_profile.gd` | new |
| `src/core/encounter_director.gd` | tokens, slots, alert broadcast |
| `src/enemies/enemy.gd` | REPOSITION/RECOVER, profile, tokens, reaction delay, prediction; remove targeted/passive multipliers |
| `src/enemies/melee_enemy.gd` | tracking windup, chain |
| `src/enemies/lunge_enemy.gd` | predicted dash, redirect |
| `src/enemies/ranged_enemy.gd` | move–stop–volley loop, volley shape, leading |
| `src/enemies/sniper_enemy.gd` | predicted lock, post-shot reposition |
| `src/enemies/boss_enemy.gd` | HARD profile, leading, no tokens |
| `src/autoload/console_manager.gd` + new `AiDebugCommands` + overlay node | `ai_debug` |
| `docs/design_docs/implementation_todo2.md` | mark behavior-based difficulty / tier profile tasks |
| `tests/unit/` | new and updated tests above |

## 9. Out of scope

- New enemy types, sprites, biome rosters.
- Boss phase redesign and per-boss mechanics.
- SHIELD / SUMMONER elite abilities.
- Hazard avoidance (lava, gas) and cover-seeking.
- Per-floor behavior curve beyond the tier bands, and playtest tuning.
