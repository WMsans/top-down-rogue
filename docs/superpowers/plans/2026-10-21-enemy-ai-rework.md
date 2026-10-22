# Enemy AI Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make enemies dangerous through behavior — tier profiles, attack tokens, an engagement ring, reaction/alert, shot leading, melee chains, lunge redirect, and a Soul Knight-style ranged move–stop–volley loop.

**Architecture:** A pure-data `EnemyProfile` per tier scales telegraphs, cadence, reaction, chaining, volleys and leading. `EncounterDirector` (already ticked every frame by `WorldManager`) gains attack tokens, engagement-ring slots, firing-spot claims and a cached player facing. `Enemy`'s existing state machine gains `REPOSITION` and renames `COOLDOWN` → `RECOVER`; subclasses keep overriding the same hooks.

**Tech Stack:** Godot 4 / GDScript, gdUnit4 tests.

**Spec:** `docs/superpowers/specs/2026-10-21-enemy-ai-rework-design.md`

## Global Constraints

- Every number is a pre-playtest starting value; keep each one as a named constant or profile field.
- Profiles — EASY: telegraph 1.25, cadence 1.2, reaction 0.35s, chain 1, volley +0, lead 0.0, redirect false. NORMAL: 1.0, 1.0, 0.2s, 2, +1, 0.5, false. HARD: 0.75, 0.7, 0.1s, 2, +2, 0.9, true.
- Elite step-up: next tier's `telegraph_mult`, `cadence_mult`, `lead_factor` (HARD stays HARD); `lunge_redirect = true`.
- `max_tokens = 4` (EASY band), `6` (any active enemy NORMAL or HARD), `+1` per active elite, no other cap. Melee/lunge cost 1.0, ranged/sniper 0.5. Token timeout 3.0s without entering ATTACK. Bosses don't use tokens.
- Player facing is cached by the director and refreshed every `FACING_POLL_INTERVAL = 2.0`s; never read `PlayerController.get_facing_direction()` live for AI decisions.
- Aim cone ±45° of cached facing; requests outside it are granted first, ties by distance.
- Ring radius = `_attack_range + 24`; ring movement at **normal effective speed**; ±8px radial jitter every 0.4s; token retry every 0.6s; slots refreshed every 0.5s; with ≥3 members one slot is at cached facing + 180°.
- Firing spots: 100–150px from player, LOS, ≥40px from other claimed spots, not solid, ≤8 candidates; re-pick every 1.5s, on LOS loss, after each volley. REPOSITION time limit 0.6–1.2s.
- Alert radius 120px, delayed by each listener's `reaction_time`.
- Melee lock 0.1s before swing; chain windup 0.2s × telegraph; chain range reach + 16px; chain step 16px.
- Lunge redirect: once, at half dash duration, ≤30°.
- Sniper windup 1.2s × telegraph. Boss uses the HARD profile.
- Never add enemy damage values; hits stay 1.
- Test command (from `AGENTS.md`): `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a <res://path>`. In a fresh worktree run `godot --headless --path . --import` first.

## Review Focus

1. **Enemy freed without `die()`** (chunk unload, `queue_free`) while holding a token, ring slot or firing spot → the director prunes it on the next `update()`; the pool never leaks. Test: Task 3 `test_freed_holder_is_pruned`.
2. **No player / dead player** → prediction returns the enemy's own position, the director keeps its last facing; nothing crashes. Test: Task 6 `test_predict_without_player_returns_self_position`.
3. **Chain follow-up while the weapon is still on cooldown** → the second swing must actually fire (`Weapon.use` early-returns while cooling down). Test: Task 7 `test_chain_second_swing_fires_despite_weapon_cooldown`.
4. **Ranged enemy in a tight cave with no valid firing spot** → it keeps strafing and still attacks; it never loops in REPOSITION. Test: Task 9 `test_no_valid_spot_still_attacks`.
5. **Elite hit or stunned mid-lunge dash** → the dash ends, fire VFX stops, the dash does not restart. Test: Task 8 `test_cancel_mid_dash_stops_dash`.

---

### Task 1: `EnemyProfile`

**Files:**
- Create: `src/enemies/enemy_profile.gd`
- Test: `tests/unit/test_enemy_profile.gd`

**Interfaces:**
- Produces: `class_name EnemyProfile extends RefCounted` with fields `telegraph_mult: float`, `cadence_mult: float`, `reaction_time: float`, `chain_attacks: int`, `volley_bonus: int`, `lead_factor: float`, `lunge_redirect: bool`; `static func for_tier(tier: int, elite: bool = false) -> EnemyProfile`. Unknown tiers return NORMAL values.

- [ ] **Step 1: Write the failing test**

`tests/unit/test_enemy_profile.gd`:

```gdscript
extends GdUnitTestSuite


func test_easy_profile() -> void:
	var p := EnemyProfile.for_tier(DropTable.EnemyTier.EASY)
	assert_float(p.telegraph_mult).is_equal(1.25)
	assert_float(p.cadence_mult).is_equal(1.2)
	assert_float(p.reaction_time).is_equal(0.35)
	assert_int(p.chain_attacks).is_equal(1)
	assert_int(p.volley_bonus).is_equal(0)
	assert_float(p.lead_factor).is_equal(0.0)
	assert_bool(p.lunge_redirect).is_false()


func test_normal_profile() -> void:
	var p := EnemyProfile.for_tier(DropTable.EnemyTier.NORMAL)
	assert_float(p.telegraph_mult).is_equal(1.0)
	assert_float(p.cadence_mult).is_equal(1.0)
	assert_float(p.reaction_time).is_equal(0.2)
	assert_int(p.chain_attacks).is_equal(2)
	assert_int(p.volley_bonus).is_equal(1)
	assert_float(p.lead_factor).is_equal(0.5)
	assert_bool(p.lunge_redirect).is_false()


func test_hard_profile() -> void:
	var p := EnemyProfile.for_tier(DropTable.EnemyTier.HARD)
	assert_float(p.telegraph_mult).is_equal(0.75)
	assert_float(p.cadence_mult).is_equal(0.7)
	assert_float(p.reaction_time).is_equal(0.1)
	assert_int(p.chain_attacks).is_equal(2)
	assert_int(p.volley_bonus).is_equal(2)
	assert_float(p.lead_factor).is_equal(0.9)
	assert_bool(p.lunge_redirect).is_true()


func test_elite_steps_up_timing_and_lead_only() -> void:
	var p := EnemyProfile.for_tier(DropTable.EnemyTier.EASY, true)
	# Stepped to NORMAL for these three...
	assert_float(p.telegraph_mult).is_equal(1.0)
	assert_float(p.cadence_mult).is_equal(1.0)
	assert_float(p.lead_factor).is_equal(0.5)
	# ...always gets the redirect...
	assert_bool(p.lunge_redirect).is_true()
	# ...and keeps EASY for the rest.
	assert_float(p.reaction_time).is_equal(0.35)
	assert_int(p.chain_attacks).is_equal(1)
	assert_int(p.volley_bonus).is_equal(0)


func test_hard_elite_stays_hard() -> void:
	var p := EnemyProfile.for_tier(DropTable.EnemyTier.HARD, true)
	assert_float(p.telegraph_mult).is_equal(0.75)
	assert_float(p.cadence_mult).is_equal(0.7)
	assert_float(p.lead_factor).is_equal(0.9)


func test_unknown_tier_falls_back_to_normal() -> void:
	var p := EnemyProfile.for_tier(99)
	assert_float(p.telegraph_mult).is_equal(1.0)
	assert_int(p.chain_attacks).is_equal(2)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_profile.gd`
Expected: FAIL — parse error, `EnemyProfile` not declared.

- [ ] **Step 3: Write the implementation**

`src/enemies/enemy_profile.gd`:

```gdscript
class_name EnemyProfile
extends RefCounted

## Behavior knobs for one enemy tier. Difficulty comes from behavior, never
## stats: these scale telegraphs, cadence, aim and volley size, not hits.

var telegraph_mult: float = 1.0
var cadence_mult: float = 1.0
var reaction_time: float = 0.2
var chain_attacks: int = 2
var volley_bonus: int = 1
var lead_factor: float = 0.5
var lunge_redirect: bool = false


## Elites take the next tier's timing and aim (HARD stays HARD) and always
## redirect their lunge; everything else keeps the base tier's value.
static func for_tier(tier: int, elite: bool = false) -> EnemyProfile:
	var p := EnemyProfile.new()
	p._fill(tier)
	if elite:
		var step := EnemyProfile.new()
		step._fill(mini(tier + 1, DropTable.EnemyTier.HARD))
		p.telegraph_mult = step.telegraph_mult
		p.cadence_mult = step.cadence_mult
		p.lead_factor = step.lead_factor
		p.lunge_redirect = true
	return p


func _fill(tier: int) -> void:
	match tier:
		DropTable.EnemyTier.EASY:
			telegraph_mult = 1.25
			cadence_mult = 1.2
			reaction_time = 0.35
			chain_attacks = 1
			volley_bonus = 0
			lead_factor = 0.0
			lunge_redirect = false
		DropTable.EnemyTier.HARD:
			telegraph_mult = 0.75
			cadence_mult = 0.7
			reaction_time = 0.1
			chain_attacks = 2
			volley_bonus = 2
			lead_factor = 0.9
			lunge_redirect = true
		_:
			pass  # NORMAL: the field defaults above
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_profile.gd`
Expected: PASS (6 tests). The `--import` registers the new `class_name`.

- [ ] **Step 5: Commit**

```bash
git add src/enemies/enemy_profile.gd src/enemies/enemy_profile.gd.uid tests/unit/test_enemy_profile.gd tests/unit/test_enemy_profile.gd.uid
git commit -m "feat(enemies): add EnemyProfile tier behavior profiles"
```

---

### Task 2: Profile-driven timing, `RECOVER`, remove targeted/passive multipliers

**Files:**
- Modify: `src/enemies/enemy.gd` (State enum line 7; consts lines 41–44; `_ready`; `_process` match ~line 183; `_physics_process`; `_process_attack`; `_process_cooldown`; `_change_state` ~line 540; `_get_effective_speed` and below, end of file)
- Modify: `src/enemies/lunge_enemy.gd:61,75`
- Delete: `tests/unit/test_enemy_aggression.gd`, `tests/unit/test_enemy_aggression.gd.uid`
- Modify: `tests/unit/test_enemy_state_machine.gd:237`, `tests/unit/test_enemy_burst_attack.gd:36`, `tests/unit/test_lunge_enemy.gd:87,120` (`COOLDOWN` → `RECOVER`)
- Test: `tests/unit/test_enemy_ai_profile.gd`

**Interfaces:**
- Consumes: `EnemyProfile.for_tier(tier, elite)` (Task 1).
- Produces on `Enemy`: `enum State { WANDER, CHASE, REPOSITION, WINDUP, ATTACK, RECOVER, HURT, DEATH }`; `var profile: EnemyProfile`; `func _build_profile() -> EnemyProfile` (overridable); `func _get_profile() -> EnemyProfile` (lazy, safe before `_ready`); `func _state_after_attack() -> int` (returns `State.RECOVER`; subclasses override); `func _process_reposition(delta)` stub reached from `_process` (filled in Task 9). `_get_effective_speed()` no longer looks at `targeted_enemy`.

- [ ] **Step 1: Write the failing test**

`tests/unit/test_enemy_ai_profile.gd`:

```gdscript
extends GdUnitTestSuite

class MockEnemy extends Enemy:
	func _execute_attack() -> void:
		pass

class MockPlayer extends Node2D:
	var targeted_enemy: Node2D = null


func _make(tier: int, elite: bool = false) -> MockEnemy:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.enemy_tier = tier
	e.is_elite = elite
	add_child(e)
	return e


func test_profile_built_from_tier() -> void:
	var e := _make(DropTable.EnemyTier.HARD)
	assert_float(e.profile.telegraph_mult).is_equal(0.75)


func test_elite_profile_steps_up() -> void:
	var e := _make(DropTable.EnemyTier.EASY, true)
	assert_float(e.profile.telegraph_mult).is_equal(1.0)


func test_windup_scales_with_telegraph() -> void:
	var e := _make(DropTable.EnemyTier.HARD)
	e.windup_duration = 0.4
	e._change_state(Enemy.State.WINDUP)
	assert_float(e._state_timer).is_equal_approx(0.3, 0.0001)


func test_recover_scales_with_cadence() -> void:
	var e := _make(DropTable.EnemyTier.EASY)
	e.cooldown_duration = 1.0
	e._change_state(Enemy.State.RECOVER)
	assert_float(e._state_timer).is_equal_approx(1.2, 0.0001)


func test_get_profile_safe_before_ready() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	assert_object(e._get_profile()).is_not_null()


func test_attack_end_goes_to_recover() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL)
	e._change_state(Enemy.State.ATTACK)
	e._process_attack(0.0)
	assert_int(e._state).is_equal(Enemy.State.RECOVER)


func test_speed_ignores_player_targeting() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL)
	e.speed = 100.0
	# The player targets someone else; the old code slowed this enemy to 0.7x.
	var other: Node2D = auto_free(Node2D.new())
	add_child(other)
	var p: MockPlayer = auto_free(MockPlayer.new())
	p.targeted_enemy = other
	add_child(p)
	e._player_ref = p
	assert_float(e._get_effective_speed()).is_equal(100.0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_ai_profile.gd`
Expected: FAIL — `profile` / `RECOVER` not found.

- [ ] **Step 3: Implement in `src/enemies/enemy.gd`**

1. Replace the enum (line 7):

```gdscript
enum State { WANDER, CHASE, REPOSITION, WINDUP, ATTACK, RECOVER, HURT, DEATH }
```

2. Delete the four constants `TARGETED_SPEED_MULT`, `TARGETED_COOLDOWN_MULT`, `PASSIVE_SPEED_MULT`, `PASSIVE_COOLDOWN_MULT`.

3. Add next to `var hits_remaining: int`:

```gdscript
var profile: EnemyProfile = null
```

4. In `_ready()`, immediately before `if is_elite:`:

```gdscript
	profile = _build_profile()
```

5. Add after `_apply_elite_scaling()`:

```gdscript
func _build_profile() -> EnemyProfile:
	return EnemyProfile.for_tier(enemy_tier, is_elite)


# Tests and pre-_ready calls can reach timing code before _ready builds the profile.
func _get_profile() -> EnemyProfile:
	if profile == null:
		profile = _build_profile()
	return profile
```

6. In `_process`'s `match _state:` replace the `State.COOLDOWN:` arm and add REPOSITION:

```gdscript
			State.REPOSITION:
				_process_reposition(delta)
			State.WINDUP:
				_process_windup(delta)
			State.ATTACK:
				_process_attack(delta)
			State.RECOVER:
				_process_recover(delta)
```

(keep `WANDER` / `CHASE` arms as they are).

7. In `_physics_process`, the movement condition becomes:

```gdscript
	if _state == State.WANDER or _state == State.CHASE or _state == State.HURT \
			or _state == State.REPOSITION \
			or (_state == State.ATTACK and _moves_during_attack()):
```

8. In `_process_attack`, replace `_change_state(State.COOLDOWN)` with `_change_state(_state_after_attack())` and add below it:

```gdscript
## The state an attack hands off to once it finishes. Melee overrides this to
## chain a follow-up swing; ranged overrides it to re-pick a firing spot.
func _state_after_attack() -> int:
	return State.RECOVER


func _process_reposition(_delta: float) -> void:
	_change_state(State.CHASE)
```

9. Rename `func _process_cooldown(delta: float)` → `func _process_recover(delta: float)` (body unchanged).

10. In `_change_state`, the WINDUP and COOLDOWN arms become:

```gdscript
		State.WINDUP:
			_state_timer = windup_duration * _get_profile().telegraph_mult
			_show_exclaim()
		State.RECOVER:
			_state_timer = cooldown_duration * _get_profile().cadence_mult
```

11. At the end of the file delete `_is_targeted()`, `_base_effective_speed()` and `_get_cooldown_multiplier()`, and change `_get_effective_speed()` to:

```gdscript
func _get_effective_speed() -> float:
	var base := speed
	if _status_component != null and is_instance_valid(_status_component):
		base *= _status_component.get_move_speed_multiplier()
	return _apply_catch_up(base)
```

12. `src/enemies/lunge_enemy.gd` lines 61 and 75: `State.COOLDOWN` → `State.RECOVER`.

13. `grep -rn "COOLDOWN\b\|_is_targeted\|_get_cooldown_multiplier\|_base_effective_speed" src tests --include='*.gd'` — replace remaining `Enemy.State.COOLDOWN` with `Enemy.State.RECOVER` in the three test files listed above; delete `tests/unit/test_enemy_aggression.gd` and its `.uid` (it only tests the removed multipliers). Expect no other hits (`COOLDOWN_FLOOR` is unrelated; leave it).

- [ ] **Step 4: Run tests**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_ai_profile.gd`
Expected: PASS (7 tests).
Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit`
Expected: no new failures versus the baseline in `docs/superpowers/plans/2026-10-20-combat-rework-baseline.txt` (record the pre-task failure list first if unsure).

- [ ] **Step 5: Commit**

```bash
git add -A src/enemies tests/unit
git commit -m "feat(enemies): profile-scaled windup/recover; drop targeted/passive multipliers"
```

---

### Task 3: Director tokens and cached player facing

**Files:**
- Modify: `src/core/encounter_director.gd`
- Modify: `src/core/world_manager.gd:106`
- Test: `tests/unit/test_encounter_director_tokens.gd`

**Interfaces:**
- Consumes: enemies expose `is_pursuing() -> bool`, `enemy_tier: int`, `is_elite: bool`, optional `token_cost() -> float` (default 1.0), `global_position`.
- Produces on `EncounterDirector`:
  - consts `BASE_TOKENS := 4.0`, `DEEP_TOKENS := 6.0`, `ELITE_TOKEN_BONUS := 1.0`, `TOKEN_TIMEOUT := 3.0`, `AIM_CONE_HALF_ANGLE := PI / 4.0`, `FACING_POLL_INTERVAL := 2.0`
  - `func update(player_pos: Vector2, attackable: Array, delta: float = 0.0, player_facing: Vector2 = Vector2.ZERO) -> void`
  - `func request_token(enemy) -> bool` (queues; grants happen in `update`; returns `has_token(enemy)`)
  - `func release_token(enemy) -> void`, `func has_token(enemy) -> bool`, `func mark_attacking(enemy) -> void`
  - `func max_tokens() -> float`, `func used_tokens() -> float`, `func get_player_facing() -> Vector2`, `func get_token_holders() -> Array`
  - `unregister(enemy)` also releases the token.

- [ ] **Step 1: Write the failing test**

`tests/unit/test_encounter_director_tokens.gd`:

```gdscript
extends GdUnitTestSuite

class Agent extends Node2D:
	var pursuing: bool = true
	var enemy_tier: int = DropTable.EnemyTier.EASY
	var is_elite: bool = false
	var cost: float = 1.0
	func is_pursuing() -> bool:
		return pursuing
	func token_cost() -> float:
		return cost


func _agent(pos: Vector2, tier: int = DropTable.EnemyTier.EASY) -> Agent:
	var a: Agent = auto_free(Agent.new())
	a.enemy_tier = tier
	add_child(a)
	a.global_position = pos
	return a


func test_capacity_easy_band_is_four() -> void:
	var d := EncounterDirector.new()
	d.update(Vector2.ZERO, [_agent(Vector2(10, 0))])
	assert_float(d.max_tokens()).is_equal(4.0)


func test_capacity_deep_band_is_six() -> void:
	var d := EncounterDirector.new()
	d.update(Vector2.ZERO, [_agent(Vector2(10, 0)), _agent(Vector2(20, 0), DropTable.EnemyTier.NORMAL)])
	assert_float(d.max_tokens()).is_equal(6.0)


func test_capacity_plus_one_per_elite() -> void:
	var d := EncounterDirector.new()
	var a := _agent(Vector2(10, 0))
	var b := _agent(Vector2(20, 0))
	a.is_elite = true
	b.is_elite = true
	d.update(Vector2.ZERO, [a, b])
	assert_float(d.max_tokens()).is_equal(6.0)


func test_grant_happens_on_update() -> void:
	var d := EncounterDirector.new()
	var a := _agent(Vector2(10, 0))
	d.update(Vector2.ZERO, [a])
	assert_bool(d.request_token(a)).is_false()
	d.update(Vector2.ZERO, [a])
	assert_bool(d.has_token(a)).is_true()
	assert_bool(d.request_token(a)).is_true()


func test_pool_caps_grants() -> void:
	var d := EncounterDirector.new()
	var agents: Array = []
	for i in range(5):
		agents.append(_agent(Vector2(-10 - i, 0)))
	d.update(Vector2.ZERO, agents)
	for a in agents:
		d.request_token(a)
	d.update(Vector2.ZERO, agents)
	assert_float(d.used_tokens()).is_equal(4.0)


func test_ranged_costs_half() -> void:
	var d := EncounterDirector.new()
	var agents: Array = []
	for i in range(8):
		var a := _agent(Vector2(-10 - i, 0))
		a.cost = 0.5
		agents.append(a)
	d.update(Vector2.ZERO, agents)
	for a in agents:
		d.request_token(a)
	d.update(Vector2.ZERO, agents)
	for a in agents:
		assert_bool(d.has_token(a)).is_true()


func test_aim_cone_requests_lose_to_flankers() -> void:
	var d := EncounterDirector.new()
	# Facing RIGHT. One agent sits in the cone and is closest; four flank.
	var front := _agent(Vector2(5, 0))
	var flankers: Array = [_agent(Vector2(-20, 0)), _agent(Vector2(0, 20)), _agent(Vector2(0, -20)), _agent(Vector2(-20, 5))]
	var all: Array = flankers.duplicate()
	all.append(front)
	d.update(Vector2.ZERO, all, 0.0, Vector2.RIGHT)
	d.request_token(front)
	for f in flankers:
		d.request_token(f)
	d.update(Vector2.ZERO, all, 0.0, Vector2.RIGHT)
	assert_bool(d.has_token(front)).is_false()
	for f in flankers:
		assert_bool(d.has_token(f)).is_true()


func test_release_frees_capacity() -> void:
	var d := EncounterDirector.new()
	var a := _agent(Vector2(10, 0))
	d.update(Vector2.ZERO, [a])
	d.request_token(a)
	d.update(Vector2.ZERO, [a])
	d.release_token(a)
	assert_bool(d.has_token(a)).is_false()
	assert_float(d.used_tokens()).is_equal(0.0)


func test_token_times_out_without_attacking() -> void:
	var d := EncounterDirector.new()
	var a := _agent(Vector2(10, 0))
	d.update(Vector2.ZERO, [a])
	d.request_token(a)
	d.update(Vector2.ZERO, [a])
	d.update(Vector2.ZERO, [a], 1.5)
	assert_bool(d.has_token(a)).is_true()
	d.update(Vector2.ZERO, [a], 1.5)
	assert_bool(d.has_token(a)).is_false()


func test_attacking_token_does_not_time_out() -> void:
	var d := EncounterDirector.new()
	var a := _agent(Vector2(10, 0))
	d.update(Vector2.ZERO, [a])
	d.request_token(a)
	d.update(Vector2.ZERO, [a])
	d.mark_attacking(a)
	d.update(Vector2.ZERO, [a], 5.0)
	assert_bool(d.has_token(a)).is_true()


func test_non_pursuing_holder_is_pruned() -> void:
	var d := EncounterDirector.new()
	var a := _agent(Vector2(10, 0))
	d.update(Vector2.ZERO, [a])
	d.request_token(a)
	d.update(Vector2.ZERO, [a])
	a.pursuing = false
	d.update(Vector2.ZERO, [a])
	assert_bool(d.has_token(a)).is_false()


func test_freed_holder_is_pruned() -> void:
	var d := EncounterDirector.new()
	var a: Agent = Agent.new()
	add_child(a)
	d.update(Vector2.ZERO, [a])
	d.request_token(a)
	d.update(Vector2.ZERO, [a])
	a.free()
	d.update(Vector2.ZERO, [])
	assert_float(d.used_tokens()).is_equal(0.0)


func test_unregister_releases_token() -> void:
	var d := EncounterDirector.new()
	var a := _agent(Vector2(10, 0))
	d.update(Vector2.ZERO, [a])
	d.request_token(a)
	d.update(Vector2.ZERO, [a])
	d.unregister(a)
	assert_bool(d.has_token(a)).is_false()


func test_facing_polls_every_two_seconds() -> void:
	var d := EncounterDirector.new()
	d.update(Vector2.ZERO, [], 0.0, Vector2.RIGHT)
	assert_that(d.get_player_facing()).is_equal(Vector2.RIGHT)
	d.update(Vector2.ZERO, [], 1.0, Vector2.LEFT)
	assert_that(d.get_player_facing()).is_equal(Vector2.RIGHT)
	d.update(Vector2.ZERO, [], 1.0, Vector2.LEFT)
	assert_that(d.get_player_facing()).is_equal(Vector2.LEFT)


func test_zero_facing_keeps_last_value() -> void:
	var d := EncounterDirector.new()
	d.update(Vector2.ZERO, [], 0.0, Vector2.UP)
	d.update(Vector2.ZERO, [], 2.0, Vector2.ZERO)
	assert_that(d.get_player_facing()).is_equal(Vector2.UP)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_encounter_director_tokens.gd`
Expected: FAIL — `max_tokens` / `request_token` not found.

- [ ] **Step 3: Implement in `src/core/encounter_director.gd`**

Add constants under the existing ones:

```gdscript
const BASE_TOKENS := 4.0
const DEEP_TOKENS := 6.0
const ELITE_TOKEN_BONUS := 1.0
const TOKEN_TIMEOUT := 3.0
const AIM_CONE_HALF_ANGLE := PI / 4.0
# The live player facing flips too often to steer a group; sample it slowly.
const FACING_POLL_INTERVAL := 2.0
```

Add state under `var _active: Array = []`:

```gdscript
# enemy -> {"cost": float, "age": float, "attacking": bool}
var _tokens: Dictionary = {}
var _requests: Array = []
var _player_pos: Vector2 = Vector2.ZERO
var _player_facing: Vector2 = Vector2.RIGHT
var _facing_timer: float = 0.0
```

Replace `update()` and `unregister()`:

```gdscript
func update(player_pos: Vector2, attackable: Array, delta: float = 0.0, player_facing: Vector2 = Vector2.ZERO) -> void:
	var still: Array = []
	for e in _active:
		if is_instance_valid(e) and e.has_method("is_pursuing") and e.is_pursuing():
			still.append(e)
	_active = still

	for e in attackable:
		if _active.size() >= HORDE_SOFT_CAP:
			break
		if not is_instance_valid(e):
			continue
		if not e.has_method("is_pursuing") or not e.is_pursuing():
			continue
		if not _active.has(e):
			_active.append(e)

	_player_pos = player_pos
	_poll_facing(delta, player_facing)
	_tick_tokens(delta)
	_grant_requests()


func unregister(enemy) -> void:
	_active.erase(enemy)
	release_token(enemy)
```

Add the token API:

```gdscript
func request_token(enemy) -> bool:
	if _tokens.has(enemy):
		return true
	if not _requests.has(enemy):
		_requests.append(enemy)
	return false


func release_token(enemy) -> void:
	_tokens.erase(enemy)
	_requests.erase(enemy)


func has_token(enemy) -> bool:
	return _tokens.has(enemy)


## An attacking holder is exempt from the timeout; the timeout only reclaims
## tokens from enemies that never got their attack off (stuck on terrain).
func mark_attacking(enemy) -> void:
	if _tokens.has(enemy):
		_tokens[enemy]["attacking"] = true


func max_tokens() -> float:
	var deep := false
	var elites := 0
	for e in _active:
		if not is_instance_valid(e):
			continue
		if "enemy_tier" in e and e.enemy_tier >= DropTable.EnemyTier.NORMAL:
			deep = true
		if "is_elite" in e and e.is_elite:
			elites += 1
	return (DEEP_TOKENS if deep else BASE_TOKENS) + ELITE_TOKEN_BONUS * elites


func used_tokens() -> float:
	var total := 0.0
	for e in _tokens:
		total += _tokens[e]["cost"]
	return total


func get_player_facing() -> Vector2:
	return _player_facing


func get_token_holders() -> Array:
	return _tokens.keys().filter(func(e): return is_instance_valid(e))


func _poll_facing(delta: float, player_facing: Vector2) -> void:
	_facing_timer -= delta
	if _facing_timer > 0.0:
		return
	_facing_timer = FACING_POLL_INTERVAL
	if player_facing.length_squared() > 0.0001:
		_player_facing = player_facing.normalized()


func _tick_tokens(delta: float) -> void:
	for e in _tokens.keys():
		if not is_instance_valid(e) or not e.is_pursuing():
			_tokens.erase(e)
			continue
		var t: Dictionary = _tokens[e]
		if t["attacking"]:
			continue
		t["age"] += delta
		if t["age"] >= TOKEN_TIMEOUT:
			_tokens.erase(e)


func _grant_requests() -> void:
	var pending: Array = []
	for e in _requests:
		if is_instance_valid(e) and e.has_method("is_pursuing") and e.is_pursuing() and not _tokens.has(e):
			pending.append(e)
	_requests.clear()
	pending.sort_custom(_request_before)
	var cap := max_tokens()
	var used := used_tokens()
	for e in pending:
		var cost := _token_cost(e)
		if used + cost > cap + 0.0001:
			continue
		_tokens[e] = {"cost": cost, "age": 0.0, "attacking": false}
		used += cost


func _request_before(a, b) -> bool:
	var a_cone := _in_aim_cone(a.global_position)
	var b_cone := _in_aim_cone(b.global_position)
	if a_cone != b_cone:
		return not a_cone
	return a.global_position.distance_squared_to(_player_pos) < b.global_position.distance_squared_to(_player_pos)


func _in_aim_cone(pos: Vector2) -> bool:
	var to := pos - _player_pos
	if to.length_squared() < 0.01:
		return true
	return absf(_player_facing.angle_to(to)) <= AIM_CONE_HALF_ANGLE


static func _token_cost(enemy) -> float:
	return enemy.token_cost() if enemy.has_method("token_cost") else 1.0
```

In `src/core/world_manager.gd` replace line 106 (`encounter_director.update(tracking_position, attackable)`) with:

```gdscript
	var player := get_tree().get_first_node_in_group("player")
	var facing := Vector2.ZERO
	if player != null and player.has_method("get_facing_direction"):
		facing = player.get_facing_direction()
	encounter_director.update(tracking_position, attackable, delta, facing)
```

- [ ] **Step 4: Run tests**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_encounter_director_tokens.gd`
Expected: PASS (15 tests).

- [ ] **Step 5: Commit**

```bash
git add src/core/encounter_director.gd src/core/world_manager.gd tests/unit/test_encounter_director_tokens.gd tests/unit/test_encounter_director_tokens.gd.uid
git commit -m "feat(ai): attack tokens and sampled player facing in EncounterDirector"
```

---

### Task 4: Enemies take, hold and release tokens

**Files:**
- Modify: `src/enemies/enemy.gd` (`_process` stun branch, `_process_chase`, `_process_windup`, `_change_state`, `take_hit`)
- Modify: `src/enemies/ranged_enemy.gd` (`_process_chase` attack trigger only; full rework is Task 9)
- Test: `tests/unit/test_enemy_tokens.gd`

**Interfaces:**
- Consumes: director `request_token`, `release_token`, `has_token`, `mark_attacking` (Task 3).
- Produces on `Enemy`: `var uses_tokens: bool = true`; `func token_cost() -> float` (1.0); `func _try_take_token() -> bool` (true when no director, `uses_tokens == false`, or token held; false while disabled); `func _release_token() -> void`; `func _is_disabled() -> bool` (stunned or any `frozen` stain); `func _cancel_attack() -> void`; overridable hook `func _on_attack_cancelled() -> void`.
- Token rule: every `_change_state` into a state other than `WINDUP`, `ATTACK`, `RECOVER` releases the token; entering `ATTACK` calls `mark_attacking`.

- [ ] **Step 1: Write the failing test**

`tests/unit/test_enemy_tokens.gd`:

```gdscript
extends GdUnitTestSuite

class FakeWorld extends Node:
	var swarm_grid = preload("res://src/core/swarm_grid.gd").new(32.0)
	var encounter_director := EncounterDirector.new()
	var nav_field = null

class MockEnemy extends Enemy:
	var sight: bool = true
	func _execute_attack() -> void:
		pass
	func _can_see_player() -> bool:
		return sight


var _world: FakeWorld


func before_test() -> void:
	_world = auto_free(FakeWorld.new())
	add_child(_world)


func _make(player_pos: Vector2) -> MockEnemy:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	e._world_manager = _world
	e._director = null
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = player_pos
	e._player_ref = p
	e._player_in_range = true
	e._attack_range = 32.0
	e._state = Enemy.State.CHASE
	return e


func _tick_director(e: Enemy) -> void:
	_world.encounter_director.update(e._player_ref.global_position, [e])


func test_waits_for_token_before_windup() -> void:
	var e := _make(Vector2(20, 0))
	e._process_chase(0.016)
	assert_int(e._state).is_equal(Enemy.State.CHASE)
	_tick_director(e)
	e._process_chase(0.016)
	assert_int(e._state).is_equal(Enemy.State.WINDUP)


func test_no_director_attacks_immediately() -> void:
	var e := _make(Vector2(20, 0))
	e._world_manager = null
	e._process_chase(0.016)
	assert_int(e._state).is_equal(Enemy.State.WINDUP)


func test_uses_tokens_false_bypasses_pool() -> void:
	var e := _make(Vector2(20, 0))
	e.uses_tokens = false
	e._process_chase(0.016)
	assert_int(e._state).is_equal(Enemy.State.WINDUP)


func test_attack_marks_token_attacking() -> void:
	var e := _make(Vector2(20, 0))
	e._process_chase(0.016)
	_tick_director(e)
	e._process_chase(0.016)
	e._change_state(Enemy.State.ATTACK)
	_world.encounter_director.update(Vector2(20, 0), [e], 5.0)
	assert_bool(_world.encounter_director.has_token(e)).is_true()


func test_recover_exit_releases_token() -> void:
	var e := _make(Vector2(20, 0))
	e._process_chase(0.016)
	_tick_director(e)
	e._process_chase(0.016)
	e._change_state(Enemy.State.RECOVER)
	assert_bool(_world.encounter_director.has_token(e)).is_true()
	e._change_state(Enemy.State.CHASE)
	assert_bool(_world.encounter_director.has_token(e)).is_false()


func test_elite_hit_during_windup_cancels_and_releases() -> void:
	var e := _make(Vector2(20, 0))
	e.is_elite = true
	e.max_hits = 2
	e.hits_remaining = 2
	e._process_chase(0.016)
	_tick_director(e)
	e._process_chase(0.016)
	assert_int(e._state).is_equal(Enemy.State.WINDUP)
	e.take_hit()
	assert_int(e._state).is_equal(Enemy.State.HURT)
	assert_bool(_world.encounter_director.has_token(e)).is_false()
	e._state_timer = 0.0
	e._process_hurt(0.016)
	assert_int(e._state).is_equal(Enemy.State.CHASE)


func test_stun_during_windup_cancels_and_releases() -> void:
	var e := _make(Vector2(20, 0))
	e._process_chase(0.016)
	_tick_director(e)
	e._process_chase(0.016)
	e._status_component.add_timed_status("stun", 0.5)
	e._process(0.016)
	assert_int(e._state).is_equal(Enemy.State.CHASE)
	assert_bool(_world.encounter_director.has_token(e)).is_false()


func test_disabled_enemy_cannot_take_token() -> void:
	var e := _make(Vector2(20, 0))
	e._status_component.add_timed_status("stun", 0.5)
	_world.encounter_director.request_token(e)
	_tick_director(e)
	assert_bool(e._try_take_token()).is_false()


func test_losing_sight_in_windup_returns_to_chase_keeping_aggro() -> void:
	var e := _make(Vector2(20, 0))
	e._process_chase(0.016)
	_tick_director(e)
	e._process_chase(0.016)
	e.sight = false
	e._process_windup(0.016)
	assert_int(e._state).is_equal(Enemy.State.CHASE)
	assert_bool(e._aggroed).is_true()
	assert_bool(_world.encounter_director.has_token(e)).is_false()


func test_ranged_costs_half_token() -> void:
	var r: RangedEnemy = auto_free(RangedEnemy.new())
	add_child(r)
	assert_float(r.token_cost()).is_equal(0.5)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_tokens.gd`
Expected: FAIL — `uses_tokens` / `_try_take_token` not found.

- [ ] **Step 3: Implement**

In `src/enemies/enemy.gd`:

1. Add to the exported/vars block:

```gdscript
var uses_tokens: bool = true
```

2. Add helpers (near `_get_director`):

```gdscript
func token_cost() -> float:
	return 1.0


## True when this enemy may enter WINDUP now. Without a director (tests, menus)
## or with tokens disabled (bosses) the answer is always yes.
func _try_take_token() -> bool:
	if _is_disabled():
		return false
	if not uses_tokens:
		return true
	var dir = _get_director()
	if dir == null:
		return true
	return dir.request_token(self)


func _release_token() -> void:
	var dir = _get_director()
	if dir != null:
		dir.release_token(self)


func _is_disabled() -> bool:
	if _status_component == null:
		return false
	return _status_component.is_stunned() or _status_component.get_stain("frozen") > 0.0


func _cancel_attack() -> void:
	_hide_exclaim()
	_on_attack_cancelled()


## Subclasses stop attack-specific motion or VFX here (lunge dash).
func _on_attack_cancelled() -> void:
	pass
```

3. `_process`, replace the stun block:

```gdscript
	if _is_disabled():
		if _state == State.WINDUP or _state == State.ATTACK:
			_cancel_attack()
			_change_state(State.CHASE)
		else:
			_release_token()
		velocity = Vector2.ZERO
		return
```

> Note: the existing `test_parry_stun_extends_cooldown` still passes — a stunned enemy in `RECOVER` stays in `RECOVER` and its timer does not tick.

4. `_process_chase`: replace

```gdscript
	if sees and dist <= _attack_range:
		velocity = Vector2.ZERO
		_change_state(State.WINDUP)
		return
```

with

```gdscript
	if sees and dist <= _attack_range:
		velocity = Vector2.ZERO
		if _try_take_token():
			_change_state(State.WINDUP)
		return
```

5. `_process_windup`: replace the stun check and the LOS branch:

```gdscript
func _process_windup(delta: float) -> void:
	if _is_disabled():
		_cancel_attack()
		_change_state(State.CHASE)
		return
	_state_timer -= delta
	if not _can_see_player():
		_cancel_attack()
		_change_state(State.CHASE)
		return
	if _state_timer <= 0.0:
		_hide_exclaim()
		_change_state(State.ATTACK)
```

6. `_process_attack`: its stun check also uses `_is_disabled()` and calls `_cancel_attack()` before `_change_state(State.CHASE)`.

7. `_change_state`, at the very top of the function (before the HURT branch):

```gdscript
	if new_state != State.WINDUP and new_state != State.ATTACK and new_state != State.RECOVER:
		_release_token()
```

and in the `match`, the ATTACK arm becomes:

```gdscript
		State.ATTACK:
			_attack_started = false
			var dir = _get_director()
			if dir != null and uses_tokens:
				dir.mark_attacking(self)
```

8. `take_hit()` becomes:

```gdscript
func take_hit() -> void:
	if not _consume_hit():
		return
	_on_hit()
	if _state == State.DEATH:
		return
	if _state != State.HURT:
		_prev_state = _state
	# A hit interrupts an elite's attack: it recovers into CHASE and gives its
	# token back. Bosses keep attacking through hits.
	if is_elite and (_prev_state == State.WINDUP or _prev_state == State.ATTACK):
		_cancel_attack()
		_prev_state = State.CHASE
		_release_token()
	_state = State.HURT
	_state_timer = hurt_duration
```

9. `die()`: `dir.unregister(self)` already releases the token (Task 3) — no change.

In `src/enemies/ranged_enemy.gd`:

```gdscript
func token_cost() -> float:
	return 0.5
```

and in `_process_chase` replace the final block with:

```gdscript
	if dist <= _attack_range and _try_take_token():
		_change_state(State.WINDUP)
		return
```

- [ ] **Step 4: Run tests**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_tokens.gd`
Expected: PASS (10 tests).
Run the enemy suites: `... -a res://tests/unit/test_enemy_state_machine.gd`, `test_lunge_enemy.gd`, `test_enemy_burst_attack.gd`. Expected: PASS. If a state-machine test asserted WANDER on windup LOS loss, update it to CHASE (spec 5.1).

- [ ] **Step 5: Commit**

```bash
git add src/enemies/enemy.gd src/enemies/ranged_enemy.gd tests/unit/test_enemy_tokens.gd tests/unit/test_enemy_tokens.gd.uid tests/unit/test_enemy_state_machine.gd
git commit -m "feat(enemies): attack through director tokens; hits/stuns cancel elite attacks"
```

---

### Task 5: Engagement ring

**Files:**
- Modify: `src/core/encounter_director.gd`
- Modify: `src/core/world_manager.gd` (`solid_check` wiring)
- Modify: `src/enemies/enemy.gd` (`_process_chase`, `_change_state`)
- Test: `tests/unit/test_engagement_ring.gd`

**Interfaces:**
- Consumes: Task 3 director state (`_player_pos`, `_player_facing`), Task 4 token helpers.
- Produces on `EncounterDirector`: `const RING_REFRESH := 0.5`; `var solid_check: Callable` (`func(world_pos: Vector2) -> bool`); `func join_ring(enemy, radius: float) -> void`; `func leave_ring(enemy) -> void`; `func get_slot(enemy) -> Vector2` (`Vector2.INF` when not a member or no valid angle); `func get_ring_slots() -> Array`. `update()` prunes invalid/non-pursuing members and marks slots for refresh every 0.5s; `unregister()` also leaves the ring.
- Produces on `Enemy`: consts `RING_MARGIN := 24.0`, `RING_ENTER_MARGIN := 32.0`, `TOKEN_RETRY := 0.6`, `RING_JITTER := 8.0`, `RING_JITTER_INTERVAL := 0.4`; `func _ring_radius() -> float`; `func _process_ring(delta: float, dir) -> void`.

- [ ] **Step 1: Write the failing test**

`tests/unit/test_engagement_ring.gd`:

```gdscript
extends GdUnitTestSuite

class Agent extends Node2D:
	var pursuing: bool = true
	var enemy_tier: int = DropTable.EnemyTier.EASY
	var is_elite: bool = false
	func is_pursuing() -> bool:
		return pursuing

class FakeWorld extends Node:
	var swarm_grid = preload("res://src/core/swarm_grid.gd").new(32.0)
	var encounter_director := EncounterDirector.new()
	var nav_field = null

class MockEnemy extends Enemy:
	func _execute_attack() -> void:
		pass
	func _can_see_player() -> bool:
		return true


func _agent(pos: Vector2) -> Agent:
	var a: Agent = auto_free(Agent.new())
	add_child(a)
	a.global_position = pos
	return a


func _ring_of(d: EncounterDirector, positions: Array) -> Array:
	var agents: Array = []
	for p in positions:
		agents.append(_agent(p))
	d.update(Vector2.ZERO, agents, 0.0, Vector2.RIGHT)
	for a in agents:
		d.join_ring(a, 50.0)
	return agents


func test_slots_are_distinct_and_on_radius() -> void:
	var d := EncounterDirector.new()
	var agents := _ring_of(d, [Vector2(40, 0), Vector2(0, 40)])
	var s0 := d.get_slot(agents[0])
	var s1 := d.get_slot(agents[1])
	assert_bool(s0.is_equal_approx(s1)).is_false()
	assert_float(s0.length()).is_equal_approx(50.0, 0.01)
	assert_float(s1.length()).is_equal_approx(50.0, 0.01)


func test_three_members_put_one_behind_player() -> void:
	var d := EncounterDirector.new()
	var agents := _ring_of(d, [Vector2(40, 0), Vector2.from_angle(2.0) * 40.0, Vector2.from_angle(-2.0) * 40.0])
	var behind := false
	for a in agents:
		if d.get_slot(a).is_equal_approx(Vector2(-50, 0)):
			behind = true
	assert_bool(behind).is_true()


func test_solid_slot_rotates_to_open_angle() -> void:
	var d := EncounterDirector.new()
	d.solid_check = func(p: Vector2) -> bool: return p.x < -1.0
	var agents := _ring_of(d, [Vector2(-40, 0)])
	var s := d.get_slot(agents[0])
	assert_bool(s == Vector2.INF).is_false()
	assert_float(s.x).is_greater_equal(-1.0)


func test_all_solid_returns_inf() -> void:
	var d := EncounterDirector.new()
	d.solid_check = func(_p: Vector2) -> bool: return true
	var agents := _ring_of(d, [Vector2(40, 0)])
	assert_that(d.get_slot(agents[0])).is_equal(Vector2.INF)


func test_leave_ring_and_prune() -> void:
	var d := EncounterDirector.new()
	var agents := _ring_of(d, [Vector2(40, 0), Vector2(0, 40)])
	d.leave_ring(agents[0])
	assert_that(d.get_slot(agents[0])).is_equal(Vector2.INF)
	agents[1].pursuing = false
	d.update(Vector2.ZERO, agents)
	assert_that(d.get_slot(agents[1])).is_equal(Vector2.INF)


func test_enemy_without_token_moves_to_ring_at_normal_speed() -> void:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	e._world_manager = world
	e._director = null
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	e._player_ref = p
	e._player_in_range = true
	e._attack_range = 28.0
	e.speed = 60.0
	e.global_position = Vector2(20, 0)
	e._state = Enemy.State.CHASE
	world.encounter_director.update(Vector2.ZERO, [e], 0.0, Vector2.RIGHT)
	# Fill the pool (NORMAL band = 6) so this enemy cannot get a token.
	for i in range(6):
		var blocker := _agent(Vector2(-100 - i, 0))
		world.encounter_director._tokens[blocker] = {"cost": 1.0, "age": 0.0, "attacking": true}
	e._process_chase(0.016)
	assert_int(e._state).is_equal(Enemy.State.CHASE)
	assert_that(world.encounter_director.get_slot(e)).is_not_equal(Vector2.INF)
	assert_float(e.velocity.length()).is_equal_approx(60.0, 0.5)


func test_enemy_leaves_ring_on_windup() -> void:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	e._world_manager = world
	e._director = null
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	e._player_ref = p
	e._player_in_range = true
	e._attack_range = 28.0
	e.global_position = Vector2(20, 0)
	e._state = Enemy.State.CHASE
	world.encounter_director.update(Vector2.ZERO, [e])
	e._process_chase(0.016)   # joins ring, requests
	world.encounter_director.update(Vector2.ZERO, [e])
	e._process_chase(0.016)   # has token, in range
	assert_int(e._state).is_equal(Enemy.State.WINDUP)
	assert_that(world.encounter_director.get_slot(e)).is_equal(Vector2.INF)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_engagement_ring.gd`
Expected: FAIL — `join_ring` not found.

- [ ] **Step 3: Implement**

`src/core/encounter_director.gd` — add:

```gdscript
const RING_REFRESH := 0.5
const RING_ROTATE_STEP := TAU / 16.0
const RING_ROTATE_TRIES := 8

## func(world_pos: Vector2) -> bool; set by WorldManager from its nav field.
var solid_check: Callable = Callable()
# enemy -> {"radius": float, "slot": Vector2}
var _ring: Dictionary = {}
var _ring_dirty: bool = true
var _ring_timer: float = 0.0


func join_ring(enemy, radius: float) -> void:
	if _ring.has(enemy):
		_ring[enemy]["radius"] = radius
		return
	_ring[enemy] = {"radius": radius, "slot": Vector2.INF}
	_ring_dirty = true


func leave_ring(enemy) -> void:
	if _ring.erase(enemy):
		_ring_dirty = true


func get_slot(enemy) -> Vector2:
	if not _ring.has(enemy):
		return Vector2.INF
	if _ring_dirty:
		_assign_slots()
	return _ring[enemy]["slot"]


func get_ring_slots() -> Array:
	if _ring_dirty:
		_assign_slots()
	var out: Array = []
	for e in _ring:
		out.append(_ring[e]["slot"])
	return out


## Spread members evenly by angle around the player. With three or more, the
## slot pattern is anchored behind the player's (sampled) facing so someone
## always flanks. Each member takes the free slot nearest its current angle.
func _assign_slots() -> void:
	_ring_dirty = false
	var members: Array = _ring.keys().filter(func(e): return is_instance_valid(e))
	var n := members.size()
	if n == 0:
		return
	var step := TAU / n
	var start: float
	if n >= 3:
		start = (-_player_facing).angle()
	else:
		start = (members[0].global_position - _player_pos).angle()
	var taken := {}
	members.sort_custom(_angle_before)
	for e in members:
		var mine: float = (e.global_position - _player_pos).angle()
		var best := -1
		var best_d := INF
		for i in range(n):
			if taken.has(i):
				continue
			var d := absf(wrapf(start + step * i - mine, -PI, PI))
			if d < best_d:
				best_d = d
				best = i
		taken[best] = true
		_ring[e]["slot"] = _open_slot(start + step * best, _ring[e]["radius"])


func _angle_before(a, b) -> bool:
	return (a.global_position - _player_pos).angle() < (b.global_position - _player_pos).angle()


func _open_slot(angle: float, radius: float) -> Vector2:
	for k in range(RING_ROTATE_TRIES):
		var offset := RING_ROTATE_STEP * ceilf(k / 2.0) * (1.0 if k % 2 == 1 else -1.0)
		var pos := _player_pos + Vector2.from_angle(angle + offset) * radius
		if not solid_check.is_valid() or not solid_check.call(pos):
			return pos
	return Vector2.INF
```

> `k = 0` gives offset 0; `k = 1, 2` give ±22.5°; … `k = 7` gives +90°.

In `update()`, after `_tick_tokens(delta)`:

```gdscript
	_tick_ring(delta)
```

and add:

```gdscript
func _tick_ring(delta: float) -> void:
	for e in _ring.keys():
		if not is_instance_valid(e) or not e.is_pursuing():
			_ring.erase(e)
			_ring_dirty = true
	_ring_timer -= delta
	if _ring_timer <= 0.0:
		_ring_timer = RING_REFRESH
		_ring_dirty = true
```

`unregister()` gains `leave_ring(enemy)`.

`src/core/world_manager.gd` — in `_process`, just before the `encounter_director.update(...)` call:

```gdscript
	if nav_field != null and not encounter_director.solid_check.is_valid():
		encounter_director.solid_check = nav_field.is_solid_world
```

`src/enemies/enemy.gd`:

1. Constants and vars:

```gdscript
const RING_MARGIN: float = 24.0
const RING_ENTER_MARGIN: float = 32.0
const TOKEN_RETRY: float = 0.6
const RING_JITTER: float = 8.0
const RING_JITTER_INTERVAL: float = 0.4
```

```gdscript
var _token_retry_timer: float = 0.0
var _ring_jitter: float = 0.0
var _ring_jitter_timer: float = 0.0
```

2. `_process_chase(_delta)` → `_process_chase(delta)`. Replace the in-range block from Task 4 and the movement tail with:

```gdscript
	var dir = _get_director()
	var holds: bool = not uses_tokens or dir == null or dir.has_token(self)
	if sees and dist <= _attack_range and holds:
		velocity = Vector2.ZERO
		if _try_take_token():
			_change_state(State.WINDUP)
		return

	if not holds and dist <= _ring_radius() + RING_ENTER_MARGIN:
		_process_ring(delta, dir)
		return
	if dir != null:
		dir.leave_ring(self)

	var move_dir: Vector2
	if sees:
		move_dir = _safe_normalized(to_player)
	else:
		var fd := _nav_field_dir()
		if fd != Vector2.ZERO:
			move_dir = fd
		else:
			move_dir = _safe_normalized(to_player)

	move_dir = _apply_separation(move_dir)
	velocity = move_dir * _get_effective_speed()
```

3. Add:

```gdscript
func _ring_radius() -> float:
	return _attack_range + RING_MARGIN


## Without a token, hold a slot on the ring around the player and keep asking.
func _process_ring(delta: float, dir) -> void:
	dir.join_ring(self, _ring_radius())
	_token_retry_timer -= delta
	if _token_retry_timer <= 0.0:
		_token_retry_timer = TOKEN_RETRY
		dir.request_token(self)
	_ring_jitter_timer -= delta
	if _ring_jitter_timer <= 0.0:
		_ring_jitter_timer = RING_JITTER_INTERVAL
		_ring_jitter = randf_range(-RING_JITTER, RING_JITTER)
	var player_pos := _player_ref.global_position
	var slot: Vector2 = dir.get_slot(self)
	var target: Vector2
	if slot == Vector2.INF:
		# No open angle: close to ring distance along the straight line.
		target = player_pos + _safe_normalized(global_position - player_pos) * _ring_radius()
	else:
		target = slot + _safe_normalized(slot - player_pos) * _ring_jitter
	var to_target := target - global_position
	if to_target.length() < 2.0:
		velocity = Vector2.ZERO
		return
	velocity = _apply_separation(_safe_normalized(to_target)) * _get_effective_speed()
```

4. `_change_state`: right after the token-release block from Task 4, add:

```gdscript
	if new_state != State.CHASE:
		var ring_dir = _get_director()
		if ring_dir != null:
			ring_dir.leave_ring(self)
```

- [ ] **Step 4: Run tests**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_engagement_ring.gd`
Expected: PASS (7 tests). Re-run `test_enemy_tokens.gd` and `test_enemy_state_machine.gd`: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/encounter_director.gd src/core/world_manager.gd src/enemies/enemy.gd tests/unit/test_engagement_ring.gd tests/unit/test_engagement_ring.gd.uid
git commit -m "feat(ai): engagement ring with flank slot for enemies waiting on a token"
```

---

### Task 6: Reaction delay, alert broadcast, player prediction

**Files:**
- Modify: `src/core/encounter_director.gd` (static `alert`)
- Modify: `src/enemies/enemy.gd` (`_process_idle`, `_process_chase` top, new helpers)
- Test: `tests/unit/test_enemy_awareness.gd`

**Interfaces:**
- Produces on `EncounterDirector`: `static func alert(origin: Vector2, radius: float, candidates: Array, source) -> void` (calls `receive_alert()` on candidates within radius, excluding `source`).
- Produces on `Enemy`: `const ALERT_RADIUS := 120.0`; `func receive_alert() -> void`; `func _predict_player_pos(travel_time: float) -> Vector2`; `func _dir_to_predicted(projectile_speed: float) -> Vector2`; `var _debug_aim_point: Vector2 = Vector2.INF` (set by `_dir_to_predicted`; read by Task 11).

- [ ] **Step 1: Write the failing test**

`tests/unit/test_enemy_awareness.gd`:

```gdscript
extends GdUnitTestSuite

class MockEnemy extends Enemy:
	var sight: bool = true
	func _execute_attack() -> void:
		pass
	func _can_see_player() -> bool:
		return sight


func _make(pos: Vector2 = Vector2.ZERO) -> MockEnemy:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	e.global_position = pos
	return e


func _moving_player(pos: Vector2, vel: Vector2) -> CharacterBody2D:
	var p: CharacterBody2D = auto_free(CharacterBody2D.new())
	add_child(p)
	p.global_position = pos
	p.velocity = vel
	return p


func test_predict_scales_with_lead() -> void:
	var e := _make()
	e._player_ref = _moving_player(Vector2(100, 0), Vector2(0, 50))
	e._get_profile().lead_factor = 0.0
	assert_that(e._predict_player_pos(1.0)).is_equal(Vector2(100, 0))
	e.profile.lead_factor = 0.5
	assert_that(e._predict_player_pos(1.0)).is_equal(Vector2(100, 25))
	e.profile.lead_factor = 1.0
	assert_that(e._predict_player_pos(1.0)).is_equal(Vector2(100, 50))


func test_predict_without_velocity_is_current_position() -> void:
	var e := _make()
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = Vector2(30, 40)
	e._player_ref = p
	assert_that(e._predict_player_pos(2.0)).is_equal(Vector2(30, 40))


func test_predict_without_player_returns_self_position() -> void:
	var e := _make(Vector2(7, 9))
	e._player_ref = null
	assert_that(e._predict_player_pos(1.0)).is_equal(Vector2(7, 9))
	assert_that(e._dir_to_predicted(100.0)).is_equal(Vector2.DOWN)


func test_dir_to_predicted_uses_travel_time() -> void:
	var e := _make()
	e._player_ref = _moving_player(Vector2(100, 0), Vector2(0, 100))
	e._get_profile().lead_factor = 1.0
	# travel = 100px / 100px/s = 1s -> aim at (100, 100)
	var d := e._dir_to_predicted(100.0)
	assert_float(d.angle()).is_equal_approx(PI / 4.0, 0.001)
	assert_that(e._debug_aim_point).is_equal(Vector2(100, 100))


func test_reaction_delay_holds_chase() -> void:
	var e := _make()
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = Vector2(100, 0)
	e._player_ref = p
	e._player_in_range = true
	e._get_profile().reaction_time = 0.2
	e._process_idle(0.016)
	assert_int(e._state).is_equal(Enemy.State.CHASE)
	e._process_chase(0.1)
	assert_that(e.velocity).is_equal(Vector2.ZERO)
	e._process_chase(0.15)
	e._process_chase(0.016)
	assert_float(e.velocity.length()).is_greater(0.0)


func test_alert_reaches_only_nearby() -> void:
	var src := _make(Vector2.ZERO)
	var near := _make(Vector2(100, 0))
	var far := _make(Vector2(200, 0))
	EncounterDirector.alert(Vector2.ZERO, 120.0, [src, near, far], src)
	assert_float(near._alert_timer).is_greater_equal(0.0)
	assert_float(far._alert_timer).is_less(0.0)
	assert_float(src._alert_timer).is_less(0.0)


func test_alerted_enemy_aggroes_after_reaction_time() -> void:
	var e := _make()
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = Vector2(300, 0)
	e._player_ref = p
	e._player_in_range = false
	e._get_profile().reaction_time = 0.2
	e.receive_alert()
	e._process_idle(0.1)
	assert_int(e._state).is_equal(Enemy.State.WANDER)
	e._process_idle(0.15)
	assert_int(e._state).is_equal(Enemy.State.CHASE)
	assert_bool(e._aggroed).is_true()


func test_first_sight_broadcasts_alert() -> void:
	var seer := _make(Vector2.ZERO)
	var buddy := _make(Vector2(80, 0))
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = Vector2(40, 0)
	seer._player_ref = p
	seer._player_in_range = true
	seer._state = Enemy.State.CHASE
	seer._process_chase(0.016)
	assert_float(buddy._alert_timer).is_greater_equal(0.0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_awareness.gd`
Expected: FAIL — `_predict_player_pos` not found.

- [ ] **Step 3: Implement**

`src/core/encounter_director.gd`:

```gdscript
static func alert(origin: Vector2, radius: float, candidates: Array, source) -> void:
	var r2 := radius * radius
	for e in candidates:
		if e == source or not is_instance_valid(e):
			continue
		if not e.has_method("receive_alert"):
			continue
		if origin.distance_squared_to(e.global_position) <= r2:
			e.receive_alert()
```

`src/enemies/enemy.gd`:

1. Add:

```gdscript
const ALERT_RADIUS: float = 120.0
```

```gdscript
var _reaction_timer: float = 0.0
var _alert_timer: float = -1.0
var _debug_aim_point: Vector2 = Vector2.INF
```

2. `_process_idle` — insert at the top:

```gdscript
	if _alert_timer >= 0.0:
		_alert_timer -= delta
		velocity = Vector2.ZERO
		if _alert_timer < 0.0:
			_aggroed = true
			_change_state(State.CHASE)
		return
```

and in the existing first branch set the reaction timer before switching:

```gdscript
	if _player_ref and is_instance_valid(_player_ref) and _player_in_range:
		_reaction_timer = _get_profile().reaction_time
		_change_state(State.CHASE)
		return
```

3. `_process_chase` — after computing `to_player` / `dist`, replace the sight block with:

```gdscript
	var sees := _can_see_player()
	if sees:
		if not _aggroed:
			_aggroed = true
			_broadcast_alert()
	elif not _aggroed:
		_change_state(State.WANDER)
		return

	if _reaction_timer > 0.0:
		_reaction_timer -= delta
		velocity = Vector2.ZERO
		return
```

4. Add:

```gdscript
func receive_alert() -> void:
	if _aggroed or _state == State.DEATH or _alert_timer >= 0.0:
		return
	_alert_timer = _get_profile().reaction_time


func _broadcast_alert() -> void:
	if not is_inside_tree():
		return
	EncounterDirector.alert(global_position, ALERT_RADIUS, get_tree().get_nodes_in_group("attackable"), self)


## Where the player will be after `travel_time`, scaled by how well this tier leads.
func _predict_player_pos(travel_time: float) -> Vector2:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return global_position
	var pos := _player_ref.global_position
	var v = _player_ref.get("velocity")
	if not (v is Vector2):
		return pos
	return pos + (v as Vector2) * maxf(travel_time, 0.0) * _get_profile().lead_factor


func _dir_to_predicted(projectile_speed: float) -> Vector2:
	if _player_ref == null or not is_instance_valid(_player_ref):
		_debug_aim_point = Vector2.INF
		return Vector2.DOWN
	var dist := global_position.distance_to(_player_ref.global_position)
	var travel := dist / projectile_speed if projectile_speed > 0.0 else 0.0
	_debug_aim_point = _predict_player_pos(travel)
	var d := _safe_normalized(_debug_aim_point - global_position)
	return d if d != Vector2.ZERO else Vector2.DOWN
```

- [ ] **Step 4: Run tests**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_awareness.gd`
Expected: PASS (8 tests). Re-run `test_enemy_state_machine.gd`, `test_enemy_tokens.gd`, `test_engagement_ring.gd`: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/encounter_director.gd src/enemies/enemy.gd tests/unit/test_enemy_awareness.gd tests/unit/test_enemy_awareness.gd.uid
git commit -m "feat(ai): reaction delay, alert broadcast and player movement prediction"
```

---

### Task 7: Melee tracking windup and chain

**Files:**
- Modify: `src/weapons/weapon.gd` (add `reset_cooldown`)
- Modify: `src/enemies/melee_enemy.gd`
- Test: `tests/unit/test_melee_enemy_ai.gd`

**Interfaces:**
- Consumes: `_state_after_attack()` hook (Task 2), `_get_profile()`, `_apply_crowd_push()`, `CROWD_PUSH_CAP`.
- Produces on `Weapon`: `func reset_cooldown() -> void`.
- Produces on `MeleeEnemy`: consts `AIM_LOCK_TIME := 0.1`, `CHAIN_WINDUP := 0.2`, `CHAIN_REACH_BONUS := 16.0`, `CHAIN_STEP := 16.0`; vars `_aim_locked`, `_lock_dir`, `_swings_done`, `_chain_pending`; `get_facing_direction()` returns the locked direction while locked.

- [ ] **Step 1: Write the failing test**

`tests/unit/test_melee_enemy_ai.gd`:

```gdscript
extends GdUnitTestSuite

class CountingWeapon extends MeleeWeapon:
	var uses: int = 0
	func _use_impl(_user: Node) -> void:
		uses += 1

class MockMelee extends MeleeEnemy:
	var real_attack: bool = false
	func _can_see_player() -> bool:
		return true
	func _execute_attack() -> void:
		if real_attack:
			super._execute_attack()


func _make(tier: int, player_pos: Vector2) -> MockMelee:
	var e: MockMelee = auto_free(MockMelee.new())
	e.enemy_tier = tier
	add_child(e)
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = player_pos
	e._player_ref = p
	e._attack_range = 28.0
	return e


func test_windup_tracks_then_locks() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL, Vector2(20, 0))
	e.windup_duration = 0.35
	e._change_state(Enemy.State.WINDUP)
	e._process_windup(0.1)
	assert_float(e.get_facing_direction().angle()).is_equal_approx(0.0, 0.01)
	e._player_ref.global_position = Vector2(0, 20)
	assert_float(e.get_facing_direction().angle()).is_equal_approx(PI / 2.0, 0.01)
	e._process_windup(0.16)  # timer 0.09 -> inside lock window next tick
	e._process_windup(0.01)
	assert_bool(e._aim_locked).is_true()
	var locked := e.get_facing_direction()
	e._player_ref.global_position = Vector2(-20, 0)
	assert_that(e.get_facing_direction()).is_equal(locked)


func test_lock_cleared_on_recover() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL, Vector2(20, 0))
	e._aim_locked = true
	e._change_state(Enemy.State.RECOVER)
	assert_bool(e._aim_locked).is_false()


func test_normal_chains_one_follow_up() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL, Vector2(20, 0))
	e._change_state(Enemy.State.WINDUP)
	e._change_state(Enemy.State.ATTACK)
	e._process_attack(0.0)
	assert_int(e._state).is_equal(Enemy.State.WINDUP)
	assert_float(e._state_timer).is_equal_approx(0.2, 0.0001)
	e._change_state(Enemy.State.ATTACK)
	e._process_attack(0.0)
	assert_int(e._state).is_equal(Enemy.State.RECOVER)


func test_chain_steps_toward_player() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL, Vector2(30, 0))
	e._change_state(Enemy.State.WINDUP)
	e._change_state(Enemy.State.ATTACK)
	e._process_attack(0.0)
	assert_float(e.global_position.x).is_equal_approx(16.0, 0.01)


func test_easy_does_not_chain() -> void:
	var e := _make(DropTable.EnemyTier.EASY, Vector2(20, 0))
	e._change_state(Enemy.State.WINDUP)
	e._change_state(Enemy.State.ATTACK)
	e._process_attack(0.0)
	assert_int(e._state).is_equal(Enemy.State.RECOVER)


func test_no_chain_when_player_out_of_reach() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL, Vector2(80, 0))
	e._change_state(Enemy.State.WINDUP)
	e._change_state(Enemy.State.ATTACK)
	e._process_attack(0.0)
	assert_int(e._state).is_equal(Enemy.State.RECOVER)


func test_chain_second_swing_fires_despite_weapon_cooldown() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL, Vector2(20, 0))
	var w := CountingWeapon.new()
	w.cooldown = 5.0
	e.weapon = w
	e.real_attack = true
	e._change_state(Enemy.State.WINDUP)
	e._change_state(Enemy.State.ATTACK)
	e._process_attack(0.0)
	e._change_state(Enemy.State.ATTACK)
	e._process_attack(0.0)
	assert_int(w.uses).is_equal(2)


func test_fresh_windup_resets_swing_count() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL, Vector2(20, 0))
	e._swings_done = 2
	e._change_state(Enemy.State.WINDUP)
	assert_int(e._swings_done).is_equal(0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_melee_enemy_ai.gd`
Expected: FAIL — `_aim_locked` not found.

- [ ] **Step 3: Implement**

`src/weapons/weapon.gd`, after `use()`:

```gdscript
func reset_cooldown() -> void:
	_cooldown_timer = 0.0
```

`src/enemies/melee_enemy.gd` — append:

```gdscript
const AIM_LOCK_TIME: float = 0.1
const CHAIN_WINDUP: float = 0.2
const CHAIN_REACH_BONUS: float = 16.0
const CHAIN_STEP: float = 16.0

var _aim_locked: bool = false
var _lock_dir: Vector2 = Vector2.DOWN
var _swings_done: int = 0
var _chain_pending: bool = false


## The swing follows the player through the windup and only commits in the
## last AIM_LOCK_TIME, so dodging is about timing, not leaving early.
func _process_windup(delta: float) -> void:
	if not _aim_locked and _state_timer <= AIM_LOCK_TIME:
		_lock_dir = super.get_facing_direction()
		_aim_locked = true
	super._process_windup(delta)


func get_facing_direction() -> Vector2:
	if _aim_locked:
		return _lock_dir
	return super.get_facing_direction()


func _change_state(new_state: int) -> void:
	if new_state != State.ATTACK:
		_aim_locked = false
	super._change_state(new_state)
	if new_state == State.WINDUP:
		if _chain_pending:
			_chain_pending = false
			_state_timer = CHAIN_WINDUP * _get_profile().telegraph_mult
		else:
			_swings_done = 0


func _state_after_attack() -> int:
	_swings_done += 1
	if _can_chain():
		_chain_pending = true
		_step_toward_player(CHAIN_STEP)
		if weapon:
			weapon.reset_cooldown()
		return State.WINDUP
	return State.RECOVER


func _can_chain() -> bool:
	if _swings_done >= _get_profile().chain_attacks:
		return false
	if _player_ref == null or not is_instance_valid(_player_ref):
		return false
	return global_position.distance_to(_player_ref.global_position) <= _attack_range + CHAIN_REACH_BONUS


# Wall-safe step: crowd pushes are clamped per axis and capped below one nav cell.
func _step_toward_player(distance: float) -> void:
	var dir := _safe_normalized(_player_ref.global_position - global_position)
	var remaining := distance
	while remaining > 0.0:
		var s := minf(remaining, CROWD_PUSH_CAP)
		_apply_crowd_push(dir * s)
		remaining -= s
```

> The windup in `test_windup_tracks_then_locks`: timer starts 0.35 → after 0.1 → 0.25 → after 0.16 → 0.09; the next `_process_windup` sees `0.09 <= 0.1` and locks.

- [ ] **Step 4: Run tests**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_melee_enemy_ai.gd`
Expected: PASS (8 tests). Re-run `test_lunge_enemy.gd` and `test_enemy_burst_attack.gd`: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/weapon.gd src/enemies/melee_enemy.gd tests/unit/test_melee_enemy_ai.gd tests/unit/test_melee_enemy_ai.gd.uid
git commit -m "feat(enemies): melee windup tracks then locks; NORMAL+ chains a follow-up swing"
```

---

### Task 8: Lunge prediction and redirect

**Files:**
- Modify: `src/enemies/lunge_enemy.gd`
- Test: `tests/unit/test_lunge_enemy_ai.gd`

**Interfaces:**
- Consumes: `_predict_player_pos` (Task 6), `_on_attack_cancelled` hook (Task 4), `profile.lunge_redirect`.
- Produces on `LungeEnemy`: `const REDIRECT_MAX_ANGLE := deg_to_rad(30.0)` (declare as `var` if a const call is rejected: `const REDIRECT_MAX_ANGLE: float = PI / 6.0`); `var _redirected: bool`.

- [ ] **Step 1: Write the failing test**

`tests/unit/test_lunge_enemy_ai.gd`:

```gdscript
extends GdUnitTestSuite


func _make(tier: int, player_pos: Vector2, player_vel: Vector2 = Vector2.ZERO) -> LungeEnemy:
	var e: LungeEnemy = auto_free(LungeEnemy.new())
	e.enemy_tier = tier
	add_child(e)
	var p: CharacterBody2D = auto_free(CharacterBody2D.new())
	add_child(p)
	p.global_position = player_pos
	p.velocity = player_vel
	e._player_ref = p
	return e


func test_dash_aims_at_predicted_position() -> void:
	var e := _make(DropTable.EnemyTier.HARD, Vector2(105, 0), Vector2(0, 100))
	e._get_profile().lead_factor = 1.0
	e._begin_dash()
	var travel := 105.0 / e.dash_speed
	var expected := Vector2(105, 100 * travel).normalized()
	assert_float(e._lock_dir.angle()).is_equal_approx(expected.angle(), 0.001)


func test_easy_dash_aims_at_current_position() -> void:
	var e := _make(DropTable.EnemyTier.EASY, Vector2(100, 0), Vector2(0, 100))
	e._begin_dash()
	assert_float(e._lock_dir.angle()).is_equal_approx(0.0, 0.001)


func test_redirect_capped_at_30_degrees() -> void:
	var e := _make(DropTable.EnemyTier.HARD, Vector2(100, 0))
	e._get_profile().lead_factor = 0.0
	e._state = Enemy.State.ATTACK
	e._begin_dash()
	e._player_ref.global_position = e.global_position + Vector2(0, 100)
	e._tick_dash(e.dash_duration * 0.5 + 0.001)
	e._tick_dash(0.001)
	assert_bool(e._redirected).is_true()
	assert_float(e._lock_dir.angle()).is_equal_approx(PI / 6.0, 0.01)


func test_no_redirect_when_profile_disables_it() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL, Vector2(100, 0))
	e._get_profile().lead_factor = 0.0
	e._state = Enemy.State.ATTACK
	e._begin_dash()
	e._player_ref.global_position = e.global_position + Vector2(0, 100)
	e._tick_dash(e.dash_duration * 0.5 + 0.001)
	e._tick_dash(0.001)
	assert_float(e._lock_dir.angle()).is_equal_approx(0.0, 0.001)


func test_cancel_mid_dash_stops_dash() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL, Vector2(100, 0))
	e.is_elite = true
	e.max_hits = 2
	e.hits_remaining = 2
	e._state = Enemy.State.ATTACK
	e._attack_started = false
	e._dash_done = false
	e._process_attack(0.016)
	e.take_hit()
	assert_bool(e._dash_done).is_true()
	assert_that(e.velocity).is_equal(Vector2.ZERO)
	e._state_timer = 0.0
	e._process_hurt(0.016)
	assert_int(e._state).is_equal(Enemy.State.CHASE)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_lunge_enemy_ai.gd`
Expected: FAIL — `_redirected` not found.

- [ ] **Step 3: Implement in `src/enemies/lunge_enemy.gd`**

Add:

```gdscript
const REDIRECT_MAX_ANGLE: float = PI / 6.0

var _redirected: bool = false
```

Replace `_begin_dash()`:

```gdscript
func _begin_dash() -> void:
	var target := global_position
	if _player_ref and is_instance_valid(_player_ref):
		var dist := global_position.distance_to(_player_ref.global_position)
		target = _predict_player_pos(dist / dash_speed)
	_lock_dir = _safe_normalized(target - global_position)
	if _lock_dir == Vector2.ZERO:
		_lock_dir = Vector2.DOWN
	_dash_timer = dash_duration
	_dash_hit = false
	_redirected = false
	_fire_vfx.start(_lock_dir)
```

In `_tick_dash`, insert at the top:

```gdscript
	if not _redirected and _get_profile().lunge_redirect and _dash_timer <= dash_duration * 0.5:
		_redirected = true
		_lock_dir = _steer_toward_player(_lock_dir)
```

Add:

```gdscript
## One mid-dash correction toward the player's current position, capped so a
## sidestep still beats it.
func _steer_toward_player(dir: Vector2) -> Vector2:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return dir
	var to := _player_ref.global_position - global_position
	if to.length_squared() < 0.01:
		return dir
	var turn := clampf(dir.angle_to(to), -REDIRECT_MAX_ANGLE, REDIRECT_MAX_ANGLE)
	return dir.rotated(turn)


func _on_attack_cancelled() -> void:
	_dash_done = true
	velocity = Vector2.ZERO
	if _fire_vfx:
		_fire_vfx.stop()
```

> In `test_redirect_capped_at_30_degrees` the first tick (timer = half + 0.001) is still above half; the redirect fires on the second tick. If the order inside `_tick_dash` (redirect check before the timer decrement) is kept as written above, that holds.

- [ ] **Step 4: Run tests**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_lunge_enemy_ai.gd`
Expected: PASS (5 tests). Re-run `test_lunge_enemy.gd`: PASS (its player is a plain `Node2D`, so prediction = current position).

- [ ] **Step 5: Commit**

```bash
git add src/enemies/lunge_enemy.gd tests/unit/test_lunge_enemy_ai.gd tests/unit/test_lunge_enemy_ai.gd.uid
git commit -m "feat(enemies): lunge leads its dash and HARD/elites redirect once"
```

---

### Task 9: Firing spots, `REPOSITION`, ranged move–stop–volley loop

**Files:**
- Create: `src/enemies/firing_spot_picker.gd`
- Modify: `src/core/encounter_director.gd` (spot claims)
- Modify: `src/enemies/enemy.gd` (`_process_reposition`, `_begin_reposition`, `_has_line_of_sight`)
- Modify: `src/enemies/ranged_enemy.gd`
- Test: `tests/unit/test_firing_spot_picker.gd`, `tests/unit/test_ranged_enemy_ai.gd`

**Interfaces:**
- Produces: `class_name FiringSpotPicker extends RefCounted` with consts `MIN_DIST := 100.0`, `MAX_DIST := 150.0`, `SPACING := 40.0`, `CANDIDATES := 8`, `ARC_SPREAD := PI` and `static func pick(origin: Vector2, player_pos: Vector2, taken: Array, solid_check: Callable, los_check: Callable, rng: RandomNumberGenerator) -> Vector2` (`Vector2.INF` if none). `los_check` is `func(from: Vector2, to: Vector2) -> bool`.
- Produces on `EncounterDirector`: `claim_spot(enemy, pos: Vector2)`, `release_spot(enemy)`, `get_taken_spots(except) -> Array`; pruned in `update()`, cleared by `unregister()`.
- Produces on `Enemy`: `const REPOSITION_ARRIVE := 6.0`; `var _reposition_target: Vector2`; `func _begin_reposition(target: Vector2, time_limit: float) -> void`; `func _has_line_of_sight(from: Vector2, to: Vector2) -> bool`; `_can_see_player()` uses it.
- Produces on `RangedEnemy`: `const SPOT_REFRESH := 1.5`; `var _has_spot: bool`; `var _spot_timer: float`; `func _apply_volley_bonus() -> void` (overridable; Sniper disables it in Task 10); `get_facing_direction()` leads the player.

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_firing_spot_picker.gd`:

```gdscript
extends GdUnitTestSuite


func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 1234
	return r


func test_spot_is_inside_distance_band() -> void:
	for i in range(20):
		var s := FiringSpotPicker.pick(Vector2(200, 0), Vector2.ZERO, [], Callable(), Callable(), _rng())
		assert_float(s.length()).is_between(100.0, 150.0)


func test_spot_biased_to_enemy_side() -> void:
	var s := FiringSpotPicker.pick(Vector2(200, 0), Vector2.ZERO, [], Callable(), Callable(), _rng())
	assert_float(s.x).is_greater(0.0)


func test_spot_respects_spacing() -> void:
	var rng := _rng()
	var first := FiringSpotPicker.pick(Vector2(200, 0), Vector2.ZERO, [], Callable(), Callable(), rng)
	var second := FiringSpotPicker.pick(Vector2(200, 0), Vector2.ZERO, [first], Callable(), Callable(), rng)
	assert_float(first.distance_to(second)).is_greater_equal(40.0)


func test_solid_candidates_rejected() -> void:
	var solid := func(p: Vector2) -> bool: return p.y > 0.0
	var s := FiringSpotPicker.pick(Vector2(200, 0), Vector2.ZERO, [], solid, Callable(), _rng())
	assert_float(s.y).is_less_equal(0.0)


func test_no_valid_candidate_returns_inf() -> void:
	var solid := func(_p: Vector2) -> bool: return true
	assert_that(FiringSpotPicker.pick(Vector2(200, 0), Vector2.ZERO, [], solid, Callable(), _rng())).is_equal(Vector2.INF)


func test_blocked_sight_returns_inf() -> void:
	var los := func(_a: Vector2, _b: Vector2) -> bool: return false
	assert_that(FiringSpotPicker.pick(Vector2(200, 0), Vector2.ZERO, [], Callable(), los, _rng())).is_equal(Vector2.INF)
```

`tests/unit/test_ranged_enemy_ai.gd`:

```gdscript
extends GdUnitTestSuite

class FakeWorld extends Node:
	var swarm_grid = preload("res://src/core/swarm_grid.gd").new(32.0)
	var encounter_director := EncounterDirector.new()
	var nav_field = null

class MockRanged extends RangedEnemy:
	func _can_see_player() -> bool:
		return true
	func _has_line_of_sight(_from: Vector2, _to: Vector2) -> bool:
		return true
	func _execute_attack() -> void:
		pass


func _fan_weapon() -> RangedWeapon:
	var w := RangedWeapon.new()
	w.projectile_count = 3
	w.spread_angle = 30.0
	return w


func _make(tier: int, weapon: RangedWeapon = null) -> MockRanged:
	var e: MockRanged = auto_free(MockRanged.new())
	e.enemy_tier = tier
	e.weapon_resource = weapon
	add_child(e)
	var p: CharacterBody2D = auto_free(CharacterBody2D.new())
	add_child(p)
	p.global_position = Vector2(120, 0)
	e._player_ref = p
	e._player_in_range = true
	e._state = Enemy.State.CHASE
	return e


func test_volley_bonus_adds_burst_shots() -> void:
	var e := _make(DropTable.EnemyTier.HARD)
	assert_int((e.weapon as RangedWeapon).burst_count).is_equal(3)


func test_volley_bonus_widens_fan() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL, _fan_weapon())
	assert_int((e.weapon as RangedWeapon).projectile_count).is_equal(4)


func test_easy_volley_unchanged() -> void:
	var e := _make(DropTable.EnemyTier.EASY)
	assert_int((e.weapon as RangedWeapon).burst_count).is_equal(1)


func test_chase_without_spot_repositions() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL)
	e._process_chase(0.016)
	assert_int(e._state).is_equal(Enemy.State.REPOSITION)
	assert_float(e._reposition_target.distance_to(Vector2(120, 0))).is_between(100.0, 150.0)


func test_reposition_arrives_back_in_chase() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL)
	e._begin_reposition(Vector2(3, 0), 1.0)
	e._process_reposition(0.016)
	assert_int(e._state).is_equal(Enemy.State.CHASE)


func test_reposition_times_out() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL)
	e._begin_reposition(Vector2(500, 0), 0.5)
	e._process_reposition(0.3)
	assert_int(e._state).is_equal(Enemy.State.REPOSITION)
	e._process_reposition(0.3)
	assert_int(e._state).is_equal(Enemy.State.CHASE)


func test_at_spot_in_range_attacks() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL)
	e._has_spot = true
	e._spot_timer = 1.0
	e._process_chase(0.016)
	assert_int(e._state).is_equal(Enemy.State.WINDUP)


func test_volley_end_forces_new_spot() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL)
	e._has_spot = true
	assert_int(e._state_after_attack()).is_equal(Enemy.State.RECOVER)
	assert_bool(e._has_spot).is_false()


func test_no_valid_spot_still_attacks() -> void:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	world.encounter_director.solid_check = func(_p: Vector2) -> bool: return true
	var e := _make(DropTable.EnemyTier.NORMAL)
	e._world_manager = world
	e._director = null
	world.encounter_director.update(Vector2(120, 0), [e])
	e._process_chase(0.016)   # no spot found -> stays, requests token
	assert_int(e._state).is_equal(Enemy.State.CHASE)
	world.encounter_director.update(Vector2(120, 0), [e])
	e._process_chase(0.016)
	assert_int(e._state).is_equal(Enemy.State.WINDUP)


func test_spot_is_claimed_with_director() -> void:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	var e := _make(DropTable.EnemyTier.NORMAL)
	e._world_manager = world
	e._director = null
	e._process_chase(0.016)
	assert_int(world.encounter_director.get_taken_spots(null).size()).is_equal(1)


func test_facing_leads_moving_player() -> void:
	var e := _make(DropTable.EnemyTier.HARD)
	(e._player_ref as CharacterBody2D).velocity = Vector2(0, 100)
	var d := e.get_facing_direction()
	assert_float(d.y).is_greater(0.0)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_firing_spot_picker.gd` and the same for `test_ranged_enemy_ai.gd`.
Expected: FAIL — `FiringSpotPicker` not declared / `_has_spot` not found.

- [ ] **Step 3: Implement**

`src/enemies/firing_spot_picker.gd`:

```gdscript
class_name FiringSpotPicker
extends RefCounted

## Picks where a ranged enemy stands to shoot: inside a distance band around
## the player, in line of sight, spaced from other shooters, on open ground.
## Candidates fan out from the enemy's current side so it doesn't cross the
## player to get there.

const MIN_DIST := 100.0
const MAX_DIST := 150.0
const SPACING := 40.0
const CANDIDATES := 8
const ARC_SPREAD := PI


static func pick(origin: Vector2, player_pos: Vector2, taken: Array, solid_check: Callable,
		los_check: Callable, rng: RandomNumberGenerator) -> Vector2:
	var side: float
	if origin.distance_squared_to(player_pos) > 0.01:
		side = (origin - player_pos).angle()
	else:
		side = rng.randf() * TAU
	var step := ARC_SPREAD / CANDIDATES
	for i in range(CANDIDATES):
		var k := ceilf(i / 2.0)
		var sgn := 1.0 if i % 2 == 1 else -1.0
		var angle := side + sgn * k * step + rng.randf_range(-0.1, 0.1)
		var spot := player_pos + Vector2.from_angle(angle) * rng.randf_range(MIN_DIST, MAX_DIST)
		if solid_check.is_valid() and solid_check.call(spot):
			continue
		if _too_close(spot, taken):
			continue
		# Raycasts are the expensive check; run them last.
		if los_check.is_valid() and not los_check.call(spot, player_pos):
			continue
		return spot
	return Vector2.INF


static func _too_close(spot: Vector2, taken: Array) -> bool:
	for t in taken:
		if spot.distance_to(t) < SPACING:
			return true
	return false
```

`src/core/encounter_director.gd`:

```gdscript
# enemy -> Vector2 firing spot
var _spots: Dictionary = {}


func claim_spot(enemy, pos: Vector2) -> void:
	_spots[enemy] = pos


func release_spot(enemy) -> void:
	_spots.erase(enemy)


func get_taken_spots(except) -> Array:
	var out: Array = []
	for e in _spots:
		if e != except and is_instance_valid(e):
			out.append(_spots[e])
	return out
```

In `_tick_ring` (or a new `_tick_spots` called from `update`), prune: `for e in _spots.keys(): if not is_instance_valid(e) or not e.is_pursuing(): _spots.erase(e)`. `unregister()` gains `release_spot(enemy)`.

`src/enemies/enemy.gd`:

```gdscript
const REPOSITION_ARRIVE: float = 6.0
```

```gdscript
var _reposition_target: Vector2 = Vector2.INF
```

Replace the Task 2 stub `_process_reposition` with:

```gdscript
func _begin_reposition(target: Vector2, time_limit: float) -> void:
	_reposition_target = target
	_change_state(State.REPOSITION)
	_state_timer = time_limit


func _process_reposition(delta: float) -> void:
	_state_timer -= delta
	var to_target := _reposition_target - global_position
	if _reposition_target == Vector2.INF or _state_timer <= 0.0 or to_target.length() <= REPOSITION_ARRIVE:
		velocity = Vector2.ZERO
		_change_state(State.CHASE)
		return
	velocity = _apply_separation(_safe_normalized(to_target)) * _get_effective_speed()
```

Refactor `_can_see_player()`:

```gdscript
func _can_see_player() -> bool:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return false
	return _has_line_of_sight(global_position, _player_ref.global_position)


func _has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	if not is_inside_tree():
		return false
	var world := get_world_2d()
	if world == null:
		return false
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = 1
	query.exclude = [self, _player_ref] if _player_ref != null else [self]
	return world.direct_space_state.intersect_ray(query).is_empty()
```

`src/enemies/ranged_enemy.gd` — full new body below the exports (keep `class_name`, `extends`, `weapon_resource`, `preferred_distance`, `strafe_speed`, `back_away_acceleration`, `token_cost()` from Task 4, `_attack_in_progress`, `_setup_drop_table`, `_execute_attack`):

```gdscript
const SPOT_REFRESH: float = 1.5
const REPOSITION_MIN: float = 0.6
const REPOSITION_MAX: float = 1.2

var _strafe_direction: float = 1.0
var _strafe_re_roll: float = 0.0
var _has_spot: bool = false
var _spot_timer: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if weapon_resource:
		weapon = weapon_resource.duplicate()
		_attack_range = preferred_distance * 1.5
		cooldown_duration = weapon_resource.cooldown
		speed = 50.0
	else:
		weapon = RangedWeapon.new()
		_attack_range = 180.0
		speed = 50.0
		_speed_base = speed
		cooldown_duration = weapon.cooldown
	detection_radius = 250.0
	windup_duration = 0.4
	_rng.randomize()
	super._ready()
	_apply_volley_bonus()
	_setup_drop_table()


## Fans get wider, single-shot weapons get longer bursts.
func _apply_volley_bonus() -> void:
	var rw := weapon as RangedWeapon
	if rw == null:
		return
	var bonus := _get_profile().volley_bonus
	if bonus <= 0:
		return
	if rw.projectile_count > 1:
		rw.projectile_count += bonus
	else:
		rw.burst_count += bonus


func get_facing_direction() -> Vector2:
	var rw := weapon as RangedWeapon
	return _dir_to_predicted(rw.projectile_speed if rw != null else 0.0)


## Soul Knight loop: walk to a firing spot, stop, volley, then move again.
func _process_chase(delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref) or not _player_in_range:
		_change_state(State.WANDER)
		return
	var sees := _can_see_player()
	if sees and not _aggroed:
		_aggroed = true
		_broadcast_alert()

	_spot_timer -= delta
	if not _has_spot or _spot_timer <= 0.0 or not sees:
		if _pick_spot_and_move():
			return
		if not sees:
			_change_state(State.WANDER)
			return

	var to_player := _player_ref.global_position - global_position
	var dist := to_player.length()
	if dist < 1.0:
		velocity = Vector2.ZERO
		return

	_strafe_re_roll -= delta
	if _strafe_re_roll <= 0.0:
		_strafe_direction = 1.0 if randf() > 0.5 else -1.0
		_strafe_re_roll = 1.5
	var perpendicular := Vector2(-to_player.y, to_player.x).normalized()
	velocity = _apply_separation(perpendicular * _strafe_direction) * strafe_speed

	if dist <= _attack_range and _try_take_token():
		_change_state(State.WINDUP)


# Returns true when it started a REPOSITION. With no valid spot it keeps the
# current position (strafing) until the next refresh.
func _pick_spot_and_move() -> bool:
	_spot_timer = SPOT_REFRESH
	_has_spot = true
	var dir = _get_director()
	var taken: Array = dir.get_taken_spots(self) if dir != null else []
	var solid: Callable = dir.solid_check if dir != null else Callable()
	var spot := FiringSpotPicker.pick(global_position, _player_ref.global_position, taken, solid,
			_has_line_of_sight, _rng)
	if spot == Vector2.INF:
		return false
	if dir != null:
		dir.claim_spot(self, spot)
	_begin_reposition(spot, _rng.randf_range(REPOSITION_MIN, REPOSITION_MAX))
	return true


func _state_after_attack() -> int:
	_has_spot = false
	return State.RECOVER
```

> The old advance/back-away branches are gone: spot picking keeps the 100–150px band. `preferred_distance` still sets `_attack_range` (×1.5). Delete the old `_process_chase` entirely.

- [ ] **Step 4: Run tests**

Run the two new files: PASS (6 + 11 tests). Re-run `test_enemy_burst_attack.gd`, `test_enemy_tokens.gd`: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/enemies/firing_spot_picker.gd src/enemies/firing_spot_picker.gd.uid src/core/encounter_director.gd src/enemies/enemy.gd src/enemies/ranged_enemy.gd tests/unit/test_firing_spot_picker.gd tests/unit/test_firing_spot_picker.gd.uid tests/unit/test_ranged_enemy_ai.gd tests/unit/test_ranged_enemy_ai.gd.uid
git commit -m "feat(enemies): ranged move-stop-volley loop with spaced firing spots and led shots"
```

---

### Task 10: Sniper and boss

**Files:**
- Modify: `src/enemies/sniper_enemy.gd`
- Modify: `src/enemies/boss_enemy.gd`
- Test: `tests/unit/test_sniper_boss_ai.gd`

**Interfaces:**
- Consumes: `_dir_to_predicted` (Task 6), `_apply_volley_bonus` (Task 9), `uses_tokens` / `_build_profile` (Tasks 2, 4).
- Produces: Sniper aims, draws and locks on the predicted direction; never gets a volley bonus. Boss uses the HARD profile, `uses_tokens = false`, leads its shots.

- [ ] **Step 1: Write the failing test**

`tests/unit/test_sniper_boss_ai.gd`:

```gdscript
extends GdUnitTestSuite

class FakeWorld extends Node:
	var swarm_grid = preload("res://src/core/swarm_grid.gd").new(32.0)
	var encounter_director := EncounterDirector.new()
	var nav_field = null


func _player(pos: Vector2, vel: Vector2) -> CharacterBody2D:
	var p: CharacterBody2D = auto_free(CharacterBody2D.new())
	add_child(p)
	p.global_position = pos
	p.velocity = vel
	return p


func test_sniper_locks_on_predicted_direction() -> void:
	var e: SniperEnemy = auto_free(SniperEnemy.new())
	e.enemy_tier = DropTable.EnemyTier.HARD
	add_child(e)
	e._player_ref = _player(Vector2(200, 0), Vector2(0, 100))
	e._get_profile().lead_factor = 1.0
	e._lock_aim()
	var spd := (e.weapon as RangedWeapon).projectile_speed
	var expected := Vector2(200, 100.0 * 200.0 / spd).normalized()
	assert_float(e._lock_dir.angle()).is_equal_approx(expected.angle(), 0.001)


func test_sniper_has_no_volley_bonus() -> void:
	var e: SniperEnemy = auto_free(SniperEnemy.new())
	e.enemy_tier = DropTable.EnemyTier.HARD
	add_child(e)
	var base := SniperWeapon.new()
	assert_int((e.weapon as RangedWeapon).burst_count).is_equal(base.burst_count)
	assert_int((e.weapon as RangedWeapon).projectile_count).is_equal(base.projectile_count)


func test_sniper_windup_scales() -> void:
	var e: SniperEnemy = auto_free(SniperEnemy.new())
	e.enemy_tier = DropTable.EnemyTier.HARD
	add_child(e)
	e._change_state(Enemy.State.WINDUP)
	assert_float(e._state_timer).is_equal_approx(0.9, 0.0001)


func test_boss_uses_hard_profile() -> void:
	var b: BossEnemy = auto_free(BossEnemy.new())
	b.enemy_tier = DropTable.EnemyTier.EASY
	add_child(b)
	assert_float(b.profile.cadence_mult).is_equal(0.7)
	assert_float(b.profile.lead_factor).is_equal(0.9)


func test_boss_attacks_without_token() -> void:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	var b: BossEnemy = auto_free(BossEnemy.new())
	add_child(b)
	b._world_manager = world
	b._director = null
	b._player_ref = _player(Vector2(50, 0), Vector2.ZERO)
	b._player_in_range = true
	b._aggroed = true
	b._state = Enemy.State.CHASE
	b._process_chase(0.016)
	assert_int(b._state).is_equal(Enemy.State.WINDUP)
	assert_float(world.encounter_director.used_tokens()).is_equal(0.0)


func test_boss_leads_shots() -> void:
	var b: BossEnemy = auto_free(BossEnemy.new())
	add_child(b)
	b._player_ref = _player(Vector2(100, 0), Vector2(0, 100))
	assert_float(b.get_facing_direction().y).is_greater(0.0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_sniper_boss_ai.gd`
Expected: FAIL (sniper aims at current position; boss uses its own tier).

- [ ] **Step 3: Implement**

`src/enemies/sniper_enemy.gd`:

```gdscript
func _apply_volley_bonus() -> void:
	pass  # one deliberate shot; tiers change its telegraph and lead instead


func _to_player_dir() -> Vector2:
	var rw := weapon as RangedWeapon
	return _dir_to_predicted(rw.projectile_speed if rw != null else 0.0)
```

(Replace the existing `_to_player_dir`. `_lock_aim`, `_update_aim_line` and `get_facing_direction` already route through it.)

`src/enemies/boss_enemy.gd`:

In `_ready()` before `super._ready()`:

```gdscript
	uses_tokens = false
```

Add:

```gdscript
func _build_profile() -> EnemyProfile:
	return EnemyProfile.for_tier(DropTable.EnemyTier.HARD)


func get_facing_direction() -> Vector2:
	var rw := weapon as RangedWeapon
	return _dir_to_predicted(rw.projectile_speed if rw != null else 0.0)
```

- [ ] **Step 4: Run tests**

Run: `test_sniper_boss_ai.gd`: PASS (6 tests). Re-run `test_boss_phase_transition.gd`, `test_boss_drops.gd`, `test_boss_ring_coverage.gd`: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/enemies/sniper_enemy.gd src/enemies/boss_enemy.gd tests/unit/test_sniper_boss_ai.gd tests/unit/test_sniper_boss_ai.gd.uid
git commit -m "feat(enemies): sniper locks on predicted aim; boss uses HARD profile without tokens"
```

---

### Task 11: `ai_debug` overlay, docs, full suite

**Files:**
- Create: `src/debug/ai_debug_overlay.gd`
- Create: `src/console/commands/ai_debug_command.gd`
- Modify: `src/autoload/console_manager.gd:36-51` (register)
- Modify: `docs/design_docs/implementation_todo2.md:29,100`
- Test: `tests/unit/test_ai_debug_command.gd`

**Interfaces:**
- Consumes: director `get_token_holders()`, `get_ring_slots()`, `get_taken_spots(null)`; enemy `_debug_aim_point`.
- Produces: `class_name AiDebugOverlay extends Node2D` with `var director`; console command `ai_debug` that toggles a child named `AiDebugOverlay` under the world manager.

- [ ] **Step 1: Write the failing test**

`tests/unit/test_ai_debug_command.gd`:

```gdscript
extends GdUnitTestSuite

const AiDebugCommand := preload("res://src/console/commands/ai_debug_command.gd")

class FakeWorld extends Node2D:
	var encounter_director := EncounterDirector.new()


func test_toggles_overlay() -> void:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	var args: Array[String] = []
	var ctx := {"world_manager": world}
	assert_str(AiDebugCommand._ai_debug(args, ctx)).is_equal("AI debug overlay on")
	var overlay := world.get_node_or_null("AiDebugOverlay")
	assert_object(overlay).is_not_null()
	assert_object(overlay.director).is_same(world.encounter_director)
	assert_str(AiDebugCommand._ai_debug(args, ctx)).is_equal("AI debug overlay off")


func test_errors_without_world() -> void:
	var args: Array[String] = []
	assert_str(AiDebugCommand._ai_debug(args, {"world_manager": null})).starts_with("error:")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_ai_debug_command.gd`
Expected: FAIL — preload path missing.

- [ ] **Step 3: Implement**

`src/debug/ai_debug_overlay.gd`:

```gdscript
class_name AiDebugOverlay
extends Node2D

## World-space view of the encounter director for tuning enemy AI:
## token holders (red ring), ring slots (yellow dots), firing spots (cyan
## crosses), predicted aim points (blue line + circle).

const TOKEN_COLOR := Color(1.0, 0.2, 0.2, 0.9)
const SLOT_COLOR := Color(1.0, 0.9, 0.2, 0.9)
const SPOT_COLOR := Color(0.2, 1.0, 1.0, 0.9)
const AIM_COLOR := Color(0.3, 0.6, 1.0, 0.6)

var director = null


func _ready() -> void:
	top_level = true
	z_index = 4096


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if director == null:
		return
	for e in director.get_token_holders():
		draw_arc(e.global_position, 12.0, 0.0, TAU, 24, TOKEN_COLOR, 1.5)
	for slot in director.get_ring_slots():
		if slot != Vector2.INF:
			draw_circle(slot, 2.5, SLOT_COLOR)
	for spot in director.get_taken_spots(null):
		draw_line(spot + Vector2(-4, -4), spot + Vector2(4, 4), SPOT_COLOR, 1.5)
		draw_line(spot + Vector2(-4, 4), spot + Vector2(4, -4), SPOT_COLOR, 1.5)
	for e in get_tree().get_nodes_in_group("attackable"):
		if not ("_debug_aim_point" in e) or e._debug_aim_point == Vector2.INF:
			continue
		draw_line(e.global_position, e._debug_aim_point, AIM_COLOR, 1.0)
		draw_arc(e._debug_aim_point, 3.0, 0.0, TAU, 12, AIM_COLOR, 1.0)
```

`src/console/commands/ai_debug_command.gd`:

```gdscript
extends RefCounted

const OVERLAY_NAME := "AiDebugOverlay"


static func register(registry: CommandRegistry) -> void:
	registry.register("ai_debug", "Toggle enemy AI overlay (tokens, ring slots, firing spots, aim)", _ai_debug)


static func _ai_debug(_args: Array[String], ctx: Dictionary) -> String:
	var wm: Node = ctx.get("world_manager")
	if wm == null:
		return "error: No world loaded."
	var existing := wm.get_node_or_null(OVERLAY_NAME)
	if existing != null:
		wm.remove_child(existing)
		existing.queue_free()
		return "AI debug overlay off"
	var overlay := AiDebugOverlay.new()
	overlay.name = OVERLAY_NAME
	overlay.director = wm.get("encounter_director")
	wm.add_child(overlay)
	return "AI debug overlay on"
```

`src/autoload/console_manager.gd`, at the end of `_register_commands()`:

```gdscript
	var AiDebugCommands := preload("res://src/console/commands/ai_debug_command.gd")
	AiDebugCommands.register(_registry)
```

`docs/design_docs/implementation_todo2.md`:
- Line 29 (Behavior-based difficulty): set the Done column to `x`.
- Line 100 (Enemy tier behavior profiles): leave Done empty and append to the description: ` Profiles implemented in \`EnemyProfile\` (2026-10-21 enemy AI rework); playtest verification pending.`

- [ ] **Step 4: Run tests**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_ai_debug_command.gd`
Expected: PASS (2 tests).

Run the full suite: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit`
Expected: every failure, if any, also appears in `docs/superpowers/plans/2026-10-20-combat-rework-baseline.txt`. Fix anything new before committing.

- [ ] **Step 5: Commit**

```bash
git add src/debug/ai_debug_overlay.gd src/debug/ai_debug_overlay.gd.uid src/console/commands/ai_debug_command.gd src/console/commands/ai_debug_command.gd.uid src/autoload/console_manager.gd docs/design_docs/implementation_todo2.md tests/unit/test_ai_debug_command.gd tests/unit/test_ai_debug_command.gd.uid
git commit -m "feat(debug): ai_debug overlay for tokens, ring slots, firing spots and aim"
```
