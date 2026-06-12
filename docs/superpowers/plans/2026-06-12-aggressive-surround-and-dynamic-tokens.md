# Aggressive Surround & Dynamic Attack Tokens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make enemies keep pressing and circling a stationary player instead of freezing on the surround ring, and make the horde's attack pressure rise as the player kills and ease off as the player takes damage.

**Architecture:** Three independent changes. (1) `EncounterDirector` gains a persistent `aggression_delta` that rides on top of the per-floor token base; kills raise it, player hits lower it. (2) `Enemy._process_chase` lets active enemies claim an attack token anywhere on the ring (then march in to attack), and makes non-attackers strafe tangentially around the player instead of charging/freezing. (3) Event wiring: `Enemy.die()` reports kills; a new `PlayerInventory.damaged` signal reports hits; `WorldManager` connects the signal to the director.

**Tech Stack:** Godot 4 / GDScript, gdUnit4 for headless unit tests.

---

## Test command

All test runs in this plan use the gdUnit4 headless command tool. The `.godot/`
import cache already exists in this worktree (the project has been imported). If a
run fails to resolve assets, regenerate it once with
`godot --headless --path . --import`.

Single suite:

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/<suite>.gd
```

A passing suite ends with a `Statistics:` line showing `0 errors | 0 failures` and
exit code `0`. (Note: `tests/unit/test_player_inventory.gd::test_take_damage_reduces_health`
is a **pre-existing** failure on this branch unrelated to this work — it calls
`take_damage` on an inventory with no parent node. Do not attempt to fix it here;
just confirm you introduce no *new* failures.)

---

## File Structure

- `src/core/encounter_director.gd` — add `aggression_delta`, tuning constants,
  `effective_*_tokens()`, `register_kill()`, `register_player_hit()`; route
  `try_claim_attack` budget through the effective helpers. (Task 1)
- `tests/unit/test_encounter_director.gd` — dynamic-token tests. (Task 1)
- `src/enemies/enemy.gd` — `die()` reports a kill (Task 2); chase rewrite for
  ring-claim commit + tangential strafe, plus orbit-sign fields and
  `_ring_strafe_dir()` (Task 4).
- `tests/unit/test_enemy_pursuit.gd` — kill-reporting test (Task 2); committed-
  attacker and ring-strafe tests (Task 4).
- `src/player/player_inventory.gd` — `damaged` signal emitted from `take_damage`
  and `take_status_damage`. (Task 3)
- `tests/unit/test_player_inventory.gd` — `damaged` emission test. (Task 3)
- `src/core/world_manager.gd` — lazy one-time connect of `damaged` to
  `register_player_hit`. (Task 3, code + manual verification)

---

## Task 1: Dynamic aggression tokens in EncounterDirector

**Files:**
- Modify: `src/core/encounter_director.gd`
- Test: `tests/unit/test_encounter_director.gd`

- [ ] **Step 1: Write the failing tests**

Append these test functions to the end of `tests/unit/test_encounter_director.gd`
(the file already has `const Director = preload(...)` and the `_enemy_at` helper):

```gdscript
func test_effective_tokens_add_aggression_delta() -> void:
	var d = Director.new()
	d.melee_token_count = 2
	d.aggression_delta = 1
	assert_int(d.effective_melee_tokens()).is_equal(3)
	assert_int(d.effective_ranged_tokens()).is_equal(d.ranged_token_count + 1)

func test_effective_tokens_never_below_one() -> void:
	var d = Director.new()
	d.melee_token_count = 1
	d.aggression_delta = -5
	assert_int(d.effective_melee_tokens()).is_equal(1)

func test_register_kill_raises_delta_by_gain() -> void:
	var d = Director.new()
	d.register_kill()
	assert_int(d.aggression_delta).is_equal(Director.KILL_GAIN)

func test_register_kill_clamps_at_max() -> void:
	var d = Director.new()
	for i in range(10):
		d.register_kill()
	assert_int(d.aggression_delta).is_equal(Director.AGGRO_MAX)

func test_register_player_hit_lowers_delta_by_loss() -> void:
	var d = Director.new()
	d.register_player_hit()
	assert_int(d.aggression_delta).is_equal(-Director.HIT_LOSS)

func test_register_player_hit_clamps_at_min() -> void:
	var d = Director.new()
	for i in range(10):
		d.register_player_hit()
	assert_int(d.aggression_delta).is_equal(Director.AGGRO_MIN)

func test_dynamic_budget_grants_more_claims_when_aggro_high() -> void:
	var d = Director.new()
	d.melee_token_count = 1
	d.aggression_delta = 1   # effective budget = 2
	var a := _enemy_at(self, Vector2(0, 0))
	var b := _enemy_at(self, Vector2(10, 0))
	var c := _enemy_at(self, Vector2(20, 0))
	d._active = [a, b, c]
	assert_bool(d.try_claim_attack(a, false)).is_true()
	assert_bool(d.try_claim_attack(b, false)).is_true()
	assert_bool(d.try_claim_attack(c, false)).is_false()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_encounter_director.gd
```
Expected: FAIL — `Invalid call. Nonexistent function 'effective_melee_tokens'`
(and the other new members).

- [ ] **Step 3: Add the constants and field**

In `src/core/encounter_director.gd`, after the existing constants block (the line
`const RAMP_BAND := 120.0`, currently line 8) add:

```gdscript
const AGGRO_MIN := -2
const AGGRO_MAX := 4
const KILL_GAIN := 2
const HIT_LOSS := 1
```

Then, immediately after the line `var ranged_token_count: int = 2` (currently
line 11) add:

```gdscript
var aggression_delta: int = 0
```

- [ ] **Step 4: Route the claim budget through effective helpers**

In `try_claim_attack`, replace this line:

```gdscript
	var budget: int = ranged_token_count if is_ranged else melee_token_count
```

with:

```gdscript
	var budget: int = effective_ranged_tokens() if is_ranged else effective_melee_tokens()
```

- [ ] **Step 5: Add the helper and event methods**

Add these functions to `src/core/encounter_director.gd` (place them just after
`release_attack`, before the `tokens_for_floor` static func):

```gdscript
func effective_melee_tokens() -> int:
	return maxi(1, melee_token_count + aggression_delta)


func effective_ranged_tokens() -> int:
	return maxi(1, ranged_token_count + aggression_delta)


func register_kill() -> void:
	aggression_delta = clampi(aggression_delta + KILL_GAIN, AGGRO_MIN, AGGRO_MAX)


func register_player_hit() -> void:
	aggression_delta = clampi(aggression_delta - HIT_LOSS, AGGRO_MIN, AGGRO_MAX)
```

- [ ] **Step 6: Run the tests to verify they pass**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_encounter_director.gd
```
Expected: PASS — `0 errors | 0 failures`. The pre-existing director tests (which
set `melee_token_count` with `aggression_delta == 0`) still pass because the
effective budget equals the base when the delta is zero.

- [ ] **Step 7: Commit**

```bash
git add src/core/encounter_director.gd tests/unit/test_encounter_director.gd
git commit -m "feat: dynamic aggression delta on attack token budget"
```

---

## Task 2: Enemy.die() reports a kill to the director

**Files:**
- Modify: `src/enemies/enemy.gd` (function `die`, currently lines 544-549)
- Test: `tests/unit/test_enemy_pursuit.gd`

- [ ] **Step 1: Write the failing test**

In `tests/unit/test_enemy_pursuit.gd`, add a stub director class near the other
stub classes (after the `StubWM` class, before `_make_enemy`):

```gdscript
# Stub director that counts kills and absorbs unregister calls.
class StubDirector:
	var kills: int = 0
	func register_kill() -> void:
		kills += 1
	func unregister(_enemy) -> void:
		pass
```

Then add this test function at the end of the file:

```gdscript
func test_die_reports_kill_to_director() -> void:
	var e := _make_enemy()
	var dir := StubDirector.new()
	e._director = dir            # _get_director() returns the cached _director
	e.die()
	assert_int(dir.kills).is_equal(1)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_pursuit.gd
```
Expected: FAIL — `dir.kills` is `0` (currently `die()` only calls `unregister`).

- [ ] **Step 3: Report the kill in die()**

In `src/enemies/enemy.gd`, change `die()` from:

```gdscript
func die() -> void:
	var dir = _get_director()
	if dir != null:
		dir.unregister(self)
	died.emit()
	_on_death()
```

to:

```gdscript
func die() -> void:
	var dir = _get_director()
	if dir != null:
		dir.register_kill()
		dir.unregister(self)
	died.emit()
	_on_death()
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_pursuit.gd
```
Expected: PASS — `0 errors | 0 failures` (existing pursuit tests still pass).

- [ ] **Step 5: Commit**

```bash
git add src/enemies/enemy.gd tests/unit/test_enemy_pursuit.gd
git commit -m "feat: enemy death reports a kill to the encounter director"
```

---

## Task 3: Player damage drives aggression down

**Files:**
- Modify: `src/player/player_inventory.gd` (add signal + two emits)
- Modify: `src/core/world_manager.gd` (lazy connect)
- Test: `tests/unit/test_player_inventory.gd`

- [ ] **Step 1: Write the failing test**

Add this test to `tests/unit/test_player_inventory.gd`. It uses the clean
`take_status_damage` path (no `get_parent()`/`HitReaction`) and adds the inventory
to the tree so `_ready` initializes health to `max_health`:

```gdscript
func test_take_status_damage_emits_damaged_signal() -> void:
	var inv := auto_free(PlayerInventory.new())
	add_child(inv)                       # runs _ready -> health = max_health
	var monitor := monitor_signals(inv)
	inv.take_status_damage(7)
	await assert_signal(monitor).is_emitted("damaged", [7])
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_player_inventory.gd
```
Expected: FAIL — the `damaged` signal does not exist / is never emitted.
(The pre-existing `test_take_damage_reduces_health` failure is unrelated; ignore it.)

- [ ] **Step 3: Add the signal**

In `src/player/player_inventory.gd`, after the line `signal player_died()`
(currently line 9) add:

```gdscript
signal damaged(amount: int)
```

- [ ] **Step 4: Emit on the direct-damage path**

In `take_damage`, locate this line:

```gdscript
	health_changed.emit(_current_health, max_health)
	if _current_health <= 0:
```

and insert the emit between them so it reads:

```gdscript
	health_changed.emit(_current_health, max_health)
	damaged.emit(amount)
	if _current_health <= 0:
```

(`take_damage` already returns early when invincible or dead, so this fires only
on real damage.)

- [ ] **Step 5: Emit on the status-damage path**

In `take_status_damage`, locate this line:

```gdscript
	_current_health = maxi(_current_health - amount, 0)
	health_changed.emit(_current_health, max_health)
	if _current_health <= 0:
```

and insert the emit so it reads:

```gdscript
	_current_health = maxi(_current_health - amount, 0)
	health_changed.emit(_current_health, max_health)
	damaged.emit(amount)
	if _current_health <= 0:
```

- [ ] **Step 6: Run the test to verify it passes**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_player_inventory.gd
```
Expected: the new `test_take_status_damage_emits_damaged_signal` PASSES. The
pre-existing `test_take_damage_reduces_health` failure remains (unchanged, not our
concern); no other test regresses.

- [ ] **Step 7: Wire the signal to the director in WorldManager**

This glue is verified manually (running the full WorldManager headless requires
the compute device and is out of scope for a unit test).

In `src/core/world_manager.gd`, after the line `var encounter_director:
EncounterDirector = EncounterDirector.new()` (currently line 28) add a guard
field:

```gdscript
var _player_hit_connected: bool = false
```

Then in `_process(delta)`, immediately after the line
`var attackable := get_tree().get_nodes_in_group("attackable")`
(currently line 103) add the lazy one-time connection:

```gdscript
	if not _player_hit_connected:
		var player := get_tree().get_first_node_in_group("player")
		if player != null:
			var inv = player.get_node_or_null("PlayerInventory")
			if inv != null:
				inv.damaged.connect(encounter_director.register_player_hit.unbind(1))
				_player_hit_connected = true
```

(`damaged` carries one argument; `register_player_hit` takes none, so `.unbind(1)`
drops the argument.)

- [ ] **Step 8: Manual verification of the wiring**

Run the game, aggro a horde, and confirm:
- Taking a hit visibly thins the number of simultaneous attackers (delta drops).
- Killing several enemies increases simultaneous attackers (delta rises).

Confirm `world_manager.gd` still parses by running a suite that loads it:

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_world_manager_chunk_budget.gd
```
Expected: the suite loads `world_manager.gd` without a parse/compile error and
reports its own `0 errors | 0 failures`. (Behavioural confirmation of the
aggression easing is by playing.)

- [ ] **Step 9: Commit**

```bash
git add src/player/player_inventory.gd src/core/world_manager.gd tests/unit/test_player_inventory.gd
git commit -m "feat: player damage eases horde aggression via director"
```

---

## Task 4: Break the attack deadlock and circle the ring

**Files:**
- Modify: `src/enemies/enemy.gd` (new fields, constant, `_ready` init,
  `_process_chase` rewrite, new `_ring_strafe_dir`)
- Test: `tests/unit/test_enemy_pursuit.gd`

- [ ] **Step 1: Write the failing tests**

In `tests/unit/test_enemy_pursuit.gd`, extend the `StubDirector` class from Task 2
so it can drive surround/commit behavior. Replace the Task 2 `StubDirector` with
this fuller version:

```gdscript
# Stub director: counts kills, controls activeness and whether claims succeed,
# and reports a slot angle equal to the enemy's current bearing (so the enemy is
# treated as already "at" its ring slot).
class StubDirector:
	var kills: int = 0
	var active: bool = true
	var grant: bool = true
	var player_pos: Vector2 = Vector2.ZERO
	func register_kill() -> void:
		kills += 1
	func unregister(_enemy) -> void:
		pass
	func is_active(_enemy) -> bool:
		return active
	func try_claim_attack(_enemy, _is_ranged) -> bool:
		return grant
	func release_attack(_enemy) -> void:
		pass
	func get_slot_angle(enemy) -> float:
		return (enemy.global_position - player_pos).angle()
```

Then add these tests at the end of the file:

```gdscript
func test_committed_attacker_presses_in_from_ring() -> void:
	# Seen, settled, within the ring but outside attack range, token granted:
	# the enemy should claim the token and move toward the player.
	var e := _make_enemy()
	e._state = Enemy.State.CHASE
	e.can_see = true
	e._settle_timer = 1.0                       # past min_attack_settle_time
	_make_player(e, Vector2(70, 0))             # dist 70: inside ring (88), outside range (32)
	var dir := StubDirector.new()
	dir.player_pos = e._player_ref.global_position
	dir.grant = true
	e._director = dir
	e._world_manager = null                     # separation passes through
	e._process_chase(0.1)
	assert_bool(e._holds_attack_token).is_true()
	assert_bool(e.velocity.x > 0.0).is_true()   # pressing toward the player

func test_committed_attacker_winds_up_in_range() -> void:
	var e := _make_enemy()
	e._state = Enemy.State.CHASE
	e.can_see = true
	e._settle_timer = 1.0
	_make_player(e, Vector2(20, 0))             # dist 20: within attack range (32)
	var dir := StubDirector.new()
	dir.player_pos = e._player_ref.global_position
	dir.grant = true
	e._director = dir
	e._world_manager = null
	e._process_chase(0.1)
	assert_that(e._state).is_equal(Enemy.State.WINDUP)

func test_non_attacker_strafes_along_ring() -> void:
	# Active, at its slot, but token denied: the enemy should circle (move
	# perpendicular to the player) instead of charging straight in or freezing.
	var e := _make_enemy()
	e._state = Enemy.State.CHASE
	e.can_see = true
	e._settle_timer = 1.0
	e.global_position = Vector2(0, 0)
	e._orbit_sign = 1.0
	_make_player(e, Vector2(88, 0))             # exactly at ring radius along +x
	var dir := StubDirector.new()
	dir.player_pos = e._player_ref.global_position
	dir.active = true
	dir.grant = false                            # token pool full -> orbit
	e._director = dir
	e._world_manager = null
	e._process_chase(0.1)
	assert_bool(e._holds_attack_token).is_false()
	# Tangential motion: mostly along y, little along the player (x) axis.
	assert_float(absf(e.velocity.y)).is_greater(1.0)
	assert_float(absf(e.velocity.x)).is_less(absf(e.velocity.y))
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_pursuit.gd
```
Expected: FAIL — `_orbit_sign` does not exist yet, and the commit/strafe behavior
is not implemented (`_holds_attack_token` stays false, velocity points straight at
the player).

- [ ] **Step 3: Add the strafe constant and orbit fields**

In `src/enemies/enemy.gd`, after the line
`const PASSIVE_COOLDOWN_MULT: float = 1.5` (currently line 39) add:

```gdscript
const RING_STRAFE_MULT: float = 0.4
```

After the line `var _wander_is_paused: bool = true` (currently line 72) add:

```gdscript
var _orbit_sign: float = 1.0
var _orbit_flip_timer: float = 0.0
```

- [ ] **Step 4: Initialize the orbit direction in _ready**

In `_ready`, just after the line `_speed_base = speed` (currently line 81) add:

```gdscript
	_orbit_sign = 1.0 if randf() < 0.5 else -1.0
	_orbit_flip_timer = randf_range(1.5, 3.0)
```

- [ ] **Step 5: Rewrite _process_chase**

Replace the entire `_process_chase` function in `src/enemies/enemy.gd`
(currently lines 262-302) with:

```gdscript
func _process_chase(delta: float) -> void:
	_orbit_flip_timer -= delta
	if _orbit_flip_timer <= 0.0:
		_orbit_sign = -_orbit_sign
		_orbit_flip_timer = randf_range(1.5, 3.0)

	if _player_ref == null or not is_instance_valid(_player_ref):
		_aggroed = false
		_change_state(State.WANDER)
		return

	var to_player := _player_ref.global_position - global_position
	var dist := to_player.length()
	var sees := _can_see_player()

	if sees:
		_aggroed = true
	elif not _aggroed:
		# Sight-to-acquire: never seen the player and currently blocked — don't commit.
		_change_state(State.WANDER)
		return

	if dist < 1.0:
		velocity = Vector2.ZERO
		return

	var move_dir: Vector2
	if sees:
		move_dir = to_player.normalized()
	else:
		var fd := _nav_field_dir()
		move_dir = fd if fd != Vector2.ZERO else to_player.normalized()

	# Commit: an active enemy may claim a token anywhere on the ring once settled,
	# then press straight in and attack only when it actually reaches attack range.
	if sees and _settle_timer >= min_attack_settle_time and dist <= _attack_range + surround_offset:
		if _try_claim_attack():
			if dist <= _attack_range:
				velocity = Vector2.ZERO
				_change_state(State.WINDUP)
				return
			velocity = _apply_separation(to_player.normalized()) * _get_effective_speed()
			return

	# Not committed: orbit the ring — strafe at the slot, otherwise travel to it.
	var speed_mult := 1.0
	if not _holds_attack_token:
		var d = _get_director()
		if d != null and d.is_active(self):
			var slot_dir := _surround_dir(_attack_range + surround_offset)
			if slot_dir != Vector2.ZERO:
				move_dir = slot_dir
			else:
				move_dir = _ring_strafe_dir()
				speed_mult = RING_STRAFE_MULT

	move_dir = _apply_separation(move_dir)
	velocity = move_dir * _get_effective_speed() * speed_mult
```

- [ ] **Step 6: Add the _ring_strafe_dir helper**

Add this function to `src/enemies/enemy.gd`, just after `_surround_dir`
(currently ends at line 673):

```gdscript
func _ring_strafe_dir() -> Vector2:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return Vector2.ZERO
	var radial := global_position - _player_ref.global_position
	if radial.length() < 0.001:
		return Vector2.ZERO
	# Unit tangent: rotate the radial 90 degrees in the enemy's orbit direction.
	return radial.normalized().rotated(_orbit_sign * PI * 0.5)
```

- [ ] **Step 7: Run the tests to verify they pass**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_pursuit.gd
```
Expected: PASS — the three new tests pass and all pre-existing pursuit tests
(`test_direct_steer_when_seen`, `test_follows_field_when_los_blocked`,
`test_persistent_aggro_past_leash`, `test_unseen_and_unaggroed_reverts`,
`test_clamp_blocks_into_wall_allows_slide`, `test_die_reports_kill_to_director`)
still pass. `0 errors | 0 failures`.

- [ ] **Step 8: Run the enemy state-machine and ranged-surround suites for regressions**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_state_machine.gd -a res://tests/unit/test_ranged_enemy_surround.gd -a res://tests/unit/test_enemy_aggression.gd
```
Expected: PASS — `0 errors | 0 failures`. (Ranged enemies override their own
attack logic; the shared chase change must not regress their surround behavior.)

- [ ] **Step 9: Manual verification**

Run the game, aggro a horde, and stand still. Confirm:
- A couple of enemies peel off the ring and attack (no permanent stall).
- The rest pace/circle around you on the ring instead of jittering in place.
- Walking toward and away still attacks / chases as before.

- [ ] **Step 10: Commit**

```bash
git add src/enemies/enemy.gd tests/unit/test_enemy_pursuit.gd
git commit -m "feat: ring-claim commit + tangential strafe so enemies press a still player"
```

---

## Final verification

- [ ] **Run the full affected test set**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode \
  -a res://tests/unit/test_encounter_director.gd \
  -a res://tests/unit/test_enemy_pursuit.gd \
  -a res://tests/unit/test_player_inventory.gd \
  -a res://tests/unit/test_enemy_state_machine.gd \
  -a res://tests/unit/test_ranged_enemy_surround.gd \
  -a res://tests/unit/test_enemy_aggression.gd
```
Expected: only the pre-existing `test_take_damage_reduces_health` failure remains;
every test added or touched by this plan passes.

## Notes for the implementer

- **DRY:** `_ring_strafe_dir` and `_surround_dir` both derive a radial from the
  player; keep them separate (different responsibilities — one points to a slot,
  one points tangentially) rather than merging.
- **YAGNI:** No aggression decay, no separate melee/ranged aggression tracks, no
  HUD indicator — all explicitly out of scope per the spec.
- **Order independence:** Tasks 1-3 and Task 4 are independent; if executing in
  parallel, only Task 4's tests depend on the `StubDirector` introduced in Task 2,
  so do Task 2 before Task 4.
