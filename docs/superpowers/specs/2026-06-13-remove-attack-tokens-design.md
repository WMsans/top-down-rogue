# Remove Attack Tokens — Infinite Enemy Aggression

**Date:** 2026-06-13
**Status:** Approved

## Goal

Remove the attack token mechanic entirely so that all enemies always pursue and attack the player freely, with no concurrency gating. Enemies charge in and attack as soon as they're in range.

## Background

The current system uses an `EncounterDirector`-managed token pool (2 melee, 2 ranged by default) as a semaphore: only token-holders can transition from CHASE to WINDUP (attack). Non-holders orbit the player on a surround ring at reduced speed. An `aggression_delta` dynamically adjusts token budgets on kills. This throttles how many enemies attack simultaneously.

The player wants maximum aggression: every enemy attacks freely, no turn-taking.

## Design

### Approach

**Remove token mechanics entirely.** Strip claiming/releasing, orbit behavior, aggression delta, and slot assignment. Every aggroed enemy proceeds directly to WINDUP when in range.

**Keep** separation, catch-up speed, and aggro contagion — these make AI look good without throttling aggression.

### Section 1: EncounterDirector simplification

Remove from `encounter_director.gd`:
- Token pools: `melee_token_count`, `ranged_token_count`, `_melee_claims`, `_ranged_claims`
- Aggression constants: `AGGRO_MIN`, `AGGRO_MAX`, `KILL_GAIN`, `HIT_LOSS`
- Aggression field: `aggression_delta`
- Methods: `try_claim_attack()`, `release_attack()`, `effective_melee_tokens()`, `effective_ranged_tokens()`, `register_kill()`, `register_player_hit()`, `tokens_for_floor()`
- Slot system: `_slots` dict, `_assign_slots()`
- Call to `_assign_slots()` inside `update()`

Keep: `HORDE_SOFT_CAP`, `CONTAGION_RADIUS`, `SPEED_CAP_FRACTION`, `TETHER_DISTANCE`, `RAMP_BAND`, `_active` pursuer set, `update()` (pruning + admission), `admit()`, `catch_up_speed()`.

### Section 2: Enemy chase behavior simplification

Remove from `enemy.gd`:
- `_holds_attack_token` field
- `_try_claim_attack()`, `_release_attack()` methods
- `_uses_ranged_token()`
- `_surround_dir()`, `_ring_strafe_dir()`
- `RING_STRAFE_MULT` constant
- `_settle_timer` field and `min_attack_settle_time` export, plus `_settle_timer` accumulation/reset in `_process()`

Simplify `_process_chase()`:
- If player is seen and within `_attack_range`: enter WINDUP immediately
- If player is seen but out of range: move directly toward player (with separation)
- If player is not seen: de-aggro to WANDER
- Remove all token-claim branching and orbit/strafe logic

Keep: separation, catch-up speed, targeted/passive speed and cooldown multipliers, `_aggroed` flag.

Remove from `_change_state()`: all `_release_attack()` calls.

Remove from `die()`: `dir.register_kill()` call.

### Section 3: Subclass and related changes

**`ranged_enemy.gd`:**
- Remove token-claim branching in `_process_chase()` (line 86 area)
- Remove `_uses_ranged_token()` override
- Keep ranged-specific positioning (preferred_distance, lateral strafe, backing away)

**`boss_enemy.gd`:** No token-related changes needed.

**`sniper_enemy.gd`:** No changes needed.

**`world_manager.gd`:**
- Remove `melee_token_count`/`ranged_token_count` assignment per floor (lines 113-114)
- Remove `PlayerInventory.damaged` → `register_player_hit()` signal connection

### Section 4: Tests

Remove entirely:
- `test_encounter_director.gd`
- `test_enemy_pursuit.gd`
- `test_ranged_enemy_surround.gd`

Keep/update:
- `test_enemy_state_machine.gd` — keep state machine tests, remove token-release-on-state-change tests
- `test_enemy_aggression.gd` — keep targeted/passive speed and cooldown tests, remove token-related assertions

## Files affected

| File | Change |
|---|---|
| `src/core/encounter_director.gd` | Remove token/aggression/slot system; keep pursuer management and catch-up |
| `src/enemies/enemy.gd` | Remove token fields, orbit/strafe, settle timer; simplify chase |
| `src/enemies/ranged_enemy.gd` | Remove token claim; remove `_uses_ranged_token` |
| `src/core/world_manager.gd` | Remove token count assignment and damage signal wiring |
| `tests/unit/test_encounter_director.gd` | Delete |
| `tests/unit/test_enemy_pursuit.gd` | Delete |
| `tests/unit/test_ranged_enemy_surround.gd` | Delete |
| `tests/unit/test_enemy_state_machine.gd` | Remove token-release assertions |
| `tests/unit/test_enemy_aggression.gd` | Remove token assertions, keep speed/cooldown tests |