# Crowd AI & Pursuit Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make enemy crowds create natural tension — enemies pursue relentlessly (you can't skip to the boss), surround the player, and only a bounded number attack at once (Hades-style attack tokens).

**Architecture:** A new `EncounterDirector` (`RefCounted`, owned by `WorldManager` exactly like `swarm_grid`) holds the active-pursuer set (soft-capped), surround-slot angles, and split melee/ranged attack-token pools. It is reconciled once per frame from the `attackable` group. `enemy.gd` / `melee_enemy.gd` / `ranged_enemy.gd` gain small, null-safe hooks that query the director: persistent aggro, aggro contagion, rubber-band catch-up speed, surround orbiting, and token-gated attacks. `spawn_dispatcher.gd` gains gauntlet density + reinforcement. All logic is pure where possible so it unit-tests without a live scene tree.

**Tech Stack:** Godot 4.6, GDScript, GdUnit4 test framework.

**Spec:** `docs/superpowers/specs/2026-06-10-crowd-ai-pursuit-foundation-design.md`

---

## File Structure

- **Create** `src/core/encounter_director.gd` — `class_name EncounterDirector extends RefCounted`. Owns active-pursuer set, soft cap, surround-slot angles, melee/ranged token pools, and pure static helpers (`catch_up_speed`, `should_aggro_from_neighbors`, `tokens_for_floor`).
- **Create** `tests/unit/test_encounter_director.gd` — director unit tests.
- **Modify** `src/core/world_manager.gd` — instantiate `encounter_director`; reconcile it each frame; set token counts from floor.
- **Modify** `src/enemies/enemy.gd` — persistent aggro, `is_pursuing()`, director resolution, rubber-band speed, contagion, token helpers, surround orbit, token release in `_change_state`, unregister on death.
- **Modify** `src/enemies/ranged_enemy.gd` — token gating + surround orbit in its `_process_chase` override; ranged token flag.
- **Modify** `tests/unit/test_enemy_state_machine.gd` — new AI-behavior tests (reuses existing `MockEnemy`).
- **Create** `tests/unit/test_ranged_enemy_surround.gd` — ranged-specific behavior tests.
- **Modify** `src/core/spawn_dispatcher.gd` — gauntlet density multiplier + reinforcement trickle.
- **Create** `tests/unit/test_spawn_gauntlet.gd` — gauntlet density tests.

**Tunables** (all on `EncounterDirector` as constants unless noted):
`HORDE_SOFT_CAP = 14`, `CONTAGION_RADIUS = 48.0`, `SPEED_CAP_FRACTION = 0.95`, `TETHER_DISTANCE = 80.0`, `RAMP_BAND = 120.0`, melee/ranged token base `= 2` (+1 at floor ≥ 4).

**Test command** (run from repo root `/home/jeremy/Development/Godot/top-down-rogue`):
```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/<file>.gd 2>&1 | tail -40
```

---

## Task 1: EncounterDirector — token pools + floor scaling

**Files:**
- Create: `src/core/encounter_director.gd`
- Test: `tests/unit/test_encounter_director.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_encounter_director.gd`:

```gdscript
extends GdUnitTestSuite

const Director = preload("res://src/core/encounter_director.gd")

func _enemy_at(parent: Node, pos: Vector2) -> Node2D:
	var n: Node2D = auto_free(Node2D.new())
	parent.add_child(n)
	n.global_position = pos
	return n

func test_melee_pool_grants_up_to_count_then_denies() -> void:
	var d = Director.new()
	d.melee_token_count = 2
	var a := _enemy_at(self, Vector2(0, 0))
	var b := _enemy_at(self, Vector2(10, 0))
	var c := _enemy_at(self, Vector2(20, 0))
	# All three must be active to be eligible.
	d._active = [a, b, c]
	assert_bool(d.try_claim_attack(a, false)).is_true()
	assert_bool(d.try_claim_attack(b, false)).is_true()
	assert_bool(d.try_claim_attack(c, false)).is_false()

func test_release_frees_a_melee_slot() -> void:
	var d = Director.new()
	d.melee_token_count = 1
	var a := _enemy_at(self, Vector2(0, 0))
	var b := _enemy_at(self, Vector2(10, 0))
	d._active = [a, b]
	assert_bool(d.try_claim_attack(a, false)).is_true()
	assert_bool(d.try_claim_attack(b, false)).is_false()
	d.release_attack(a)
	assert_bool(d.try_claim_attack(b, false)).is_true()

func test_melee_and_ranged_pools_are_independent() -> void:
	var d = Director.new()
	d.melee_token_count = 1
	d.ranged_token_count = 1
	var m := _enemy_at(self, Vector2(0, 0))
	var r := _enemy_at(self, Vector2(10, 0))
	d._active = [m, r]
	assert_bool(d.try_claim_attack(m, false)).is_true()   # melee pool
	assert_bool(d.try_claim_attack(r, true)).is_true()    # ranged pool, separate

func test_claim_denied_when_not_active() -> void:
	var d = Director.new()
	d.melee_token_count = 2
	var a := _enemy_at(self, Vector2(0, 0))
	d._active = []  # not admitted
	assert_bool(d.try_claim_attack(a, false)).is_false()

func test_claim_is_idempotent_for_holder() -> void:
	var d = Director.new()
	d.melee_token_count = 1
	var a := _enemy_at(self, Vector2(0, 0))
	d._active = [a]
	assert_bool(d.try_claim_attack(a, false)).is_true()
	assert_bool(d.try_claim_attack(a, false)).is_true()  # already holds, still true

func test_tokens_for_floor_scales_gently() -> void:
	assert_int(Director.tokens_for_floor(2, 1)).is_equal(2)
	assert_int(Director.tokens_for_floor(2, 3)).is_equal(2)
	assert_int(Director.tokens_for_floor(2, 4)).is_equal(3)
	assert_int(Director.tokens_for_floor(2, 9)).is_equal(3)  # capped at +1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_encounter_director.gd 2>&1 | tail -40`
Expected: FAIL — cannot load `res://src/core/encounter_director.gd`.

- [ ] **Step 3: Write minimal implementation**

Create `src/core/encounter_director.gd`:

```gdscript
class_name EncounterDirector
extends RefCounted

# Per-frame coordinator for the aggroed enemy crowd. Owned by WorldManager
# (mirrors swarm_grid). Holds the active-pursuer set, surround-slot angles, and
# split melee/ranged attack-token pools. Reconciled once per frame from the
# "attackable" group via update().

const HORDE_SOFT_CAP := 14
const CONTAGION_RADIUS := 48.0
const SPEED_CAP_FRACTION := 0.95
const TETHER_DISTANCE := 80.0
const RAMP_BAND := 120.0

# Set each frame by WorldManager from the current floor.
var melee_token_count: int = 2
var ranged_token_count: int = 2

var _active: Array = []               # active pursuers (Node2D), <= HORDE_SOFT_CAP
var _melee_claims: Dictionary = {}    # enemy -> true
var _ranged_claims: Dictionary = {}   # enemy -> true
var _slots: Dictionary = {}           # enemy -> target angle (float, radians)


func is_active(enemy) -> bool:
	return _active.has(enemy)


func try_claim_attack(enemy, is_ranged: bool) -> bool:
	if not is_active(enemy):
		return false
	var claims: Dictionary = _ranged_claims if is_ranged else _melee_claims
	if claims.has(enemy):
		return true
	var budget: int = ranged_token_count if is_ranged else melee_token_count
	if claims.size() >= budget:
		return false
	claims[enemy] = true
	return true


func release_attack(enemy) -> void:
	_melee_claims.erase(enemy)
	_ranged_claims.erase(enemy)


static func tokens_for_floor(base: int, floor_number: int) -> int:
	return base + clampi((floor_number - 1) / 3, 0, 1)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_encounter_director.gd 2>&1 | tail -40`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add src/core/encounter_director.gd tests/unit/test_encounter_director.gd
git commit -m "feat: EncounterDirector attack-token pools + floor scaling"
```

---

## Task 2: EncounterDirector — rubber-band catch-up speed

**Files:**
- Modify: `src/core/encounter_director.gd`
- Test: `tests/unit/test_encounter_director.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_encounter_director.gd`:

```gdscript
func test_catch_up_returns_base_when_close() -> void:
	# Within tether: pursuer moves at its own base speed.
	var s := Director.catch_up_speed(60.0, 40.0, 120.0)
	assert_float(s).is_equal_approx(60.0, 0.001)

func test_catch_up_ramps_toward_cap_when_far() -> void:
	# Far beyond tether+ramp: speed reaches the cap (player_speed * 0.95).
	var s := Director.catch_up_speed(60.0, 1000.0, 120.0)
	assert_float(s).is_equal_approx(114.0, 0.001)  # 120 * 0.95

func test_catch_up_never_exceeds_player_cap() -> void:
	# Even a fast base never exceeds the cap, at any distance.
	for dist in [0.0, 90.0, 300.0, 5000.0]:
		var s := Director.catch_up_speed(200.0, dist, 120.0)
		assert_float(s).is_less_equal(114.0 + 0.001)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_encounter_director.gd 2>&1 | tail -40`
Expected: FAIL — `Invalid call. Nonexistent function 'catch_up_speed'`.

- [ ] **Step 3: Write minimal implementation**

Add to `src/core/encounter_director.gd` (after `tokens_for_floor`):

```gdscript
# "Keep pace, never exceed." Within TETHER_DISTANCE the pursuer uses its own
# base speed; beyond it, speed ramps over RAMP_BAND toward player_speed *
# SPEED_CAP_FRACTION, hard-capped so it never outruns the player.
static func catch_up_speed(base_speed: float, dist_to_player: float, player_speed: float) -> float:
	var cap := player_speed * SPEED_CAP_FRACTION
	if dist_to_player <= TETHER_DISTANCE:
		return minf(base_speed, cap)
	var t := clampf((dist_to_player - TETHER_DISTANCE) / RAMP_BAND, 0.0, 1.0)
	var target := maxf(base_speed, cap)
	return minf(lerpf(base_speed, target, t), cap)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_encounter_director.gd 2>&1 | tail -40`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add src/core/encounter_director.gd tests/unit/test_encounter_director.gd
git commit -m "feat: rubber-band catch-up speed (keep pace, never exceed)"
```

---

## Task 3: EncounterDirector — aggro contagion helper

**Files:**
- Modify: `src/core/encounter_director.gd`
- Test: `tests/unit/test_encounter_director.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_encounter_director.gd`:

```gdscript
class _PursuerStub extends Node2D:
	var pursuing: bool = false
	func is_pursuing() -> bool:
		return pursuing

func _stub_at(parent: Node, pos: Vector2, pursuing: bool) -> _PursuerStub:
	var n: _PursuerStub = auto_free(_PursuerStub.new())
	parent.add_child(n)
	n.global_position = pos
	n.pursuing = pursuing
	return n

func test_contagion_true_for_close_aggroed_neighbor() -> void:
	var me := _stub_at(self, Vector2(0, 0), false)
	var aggro := _stub_at(self, Vector2(30, 0), true)  # within 48px
	var spread := Director.should_aggro_from_neighbors(me, [me, aggro])
	assert_bool(spread).is_true()

func test_contagion_false_for_far_aggroed_neighbor() -> void:
	var me := _stub_at(self, Vector2(0, 0), false)
	var aggro := _stub_at(self, Vector2(100, 0), true)  # beyond 48px
	var spread := Director.should_aggro_from_neighbors(me, [me, aggro])
	assert_bool(spread).is_false()

func test_contagion_false_for_close_idle_neighbor() -> void:
	var me := _stub_at(self, Vector2(0, 0), false)
	var idle := _stub_at(self, Vector2(20, 0), false)  # close but not aggroed
	var spread := Director.should_aggro_from_neighbors(me, [me, idle])
	assert_bool(spread).is_false()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_encounter_director.gd 2>&1 | tail -40`
Expected: FAIL — `Nonexistent function 'should_aggro_from_neighbors'`.

- [ ] **Step 3: Write minimal implementation**

Add to `src/core/encounter_director.gd`:

```gdscript
# True when `me` has any aggroed neighbor within CONTAGION_RADIUS. `neighbors`
# is a swarm_grid 3x3 query (may include `me` itself, which is skipped).
static func should_aggro_from_neighbors(me: Node2D, neighbors: Array) -> bool:
	var my_pos := me.global_position
	for n in neighbors:
		if n == me or not is_instance_valid(n):
			continue
		if not n.has_method("is_pursuing") or not n.is_pursuing():
			continue
		if my_pos.distance_to(n.global_position) <= CONTAGION_RADIUS:
			return true
	return false
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_encounter_director.gd 2>&1 | tail -40`
Expected: PASS (12 tests).

- [ ] **Step 5: Commit**

```bash
git add src/core/encounter_director.gd tests/unit/test_encounter_director.gd
git commit -m "feat: aggro contagion neighbor helper"
```

---

## Task 4: EncounterDirector — active-set reconciliation + soft cap + unregister

**Files:**
- Modify: `src/core/encounter_director.gd`
- Test: `tests/unit/test_encounter_director.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_encounter_director.gd`:

```gdscript
func test_update_admits_only_pursuing_enemies() -> void:
	var d = Director.new()
	var a := _stub_at(self, Vector2(40, 0), true)
	var b := _stub_at(self, Vector2(0, 40), false)  # idle, not admitted
	d.update(Vector2.ZERO, [a, b])
	assert_bool(d.is_active(a)).is_true()
	assert_bool(d.is_active(b)).is_false()

func test_update_enforces_soft_cap() -> void:
	var d = Director.new()
	var list: Array = []
	for i in range(Director.HORDE_SOFT_CAP + 5):
		list.append(_stub_at(self, Vector2(i * 20, 0), true))
	d.update(Vector2.ZERO, list)
	assert_int(d._active.size()).is_equal(Director.HORDE_SOFT_CAP)

func test_update_prunes_dead_holder_and_frees_token() -> void:
	var d = Director.new()
	d.melee_token_count = 1
	var a := _PursuerStub.new()      # NOT auto_free: we free it manually
	add_child(a)
	a.global_position = Vector2(40, 0)
	a.pursuing = true
	var b := _stub_at(self, Vector2(0, 40), true)
	d.update(Vector2.ZERO, [a, b])
	assert_bool(d.try_claim_attack(a, false)).is_true()
	assert_bool(d.try_claim_attack(b, false)).is_false()  # pool full
	a.free()                          # holder dies
	d.update(Vector2.ZERO, [b])       # reconcile without the freed node
	assert_bool(d.try_claim_attack(b, false)).is_true()   # slot freed

func test_unregister_releases_membership_and_token() -> void:
	var d = Director.new()
	d.melee_token_count = 1
	var a := _stub_at(self, Vector2(40, 0), true)
	var b := _stub_at(self, Vector2(0, 40), true)
	d.update(Vector2.ZERO, [a, b])
	assert_bool(d.try_claim_attack(a, false)).is_true()
	d.unregister(a)
	assert_bool(d.is_active(a)).is_false()
	assert_bool(d.try_claim_attack(b, false)).is_true()   # a's token freed
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_encounter_director.gd 2>&1 | tail -40`
Expected: FAIL — `Nonexistent function 'update'`.

- [ ] **Step 3: Write minimal implementation**

Add to `src/core/encounter_director.gd`:

```gdscript
# Reconcile the active set against the live attackable list once per frame:
# drop invalid / no-longer-pursuing members (releasing their tokens + slots),
# admit new pursuers up to HORDE_SOFT_CAP, then reassign surround slots.
func update(player_pos: Vector2, attackable: Array) -> void:
	# 1. Drop members that died or stopped pursuing.
	var still: Array = []
	for e in _active:
		if is_instance_valid(e) and e.has_method("is_pursuing") and e.is_pursuing():
			still.append(e)
		else:
			_drop_bookkeeping(e)
	_active = still

	# 2. Admit new pursuers, up to the soft cap.
	for e in attackable:
		if _active.size() >= HORDE_SOFT_CAP:
			break
		if not is_instance_valid(e):
			continue
		if not e.has_method("is_pursuing") or not e.is_pursuing():
			continue
		if not _active.has(e):
			_active.append(e)

	# 3. Reassign surround slots (filled in Task 5).
	_assign_slots(player_pos)


func unregister(enemy) -> void:
	_active.erase(enemy)
	_drop_bookkeeping(enemy)


func _drop_bookkeeping(enemy) -> void:
	_melee_claims.erase(enemy)
	_ranged_claims.erase(enemy)
	_slots.erase(enemy)


func _assign_slots(_player_pos: Vector2) -> void:
	pass  # implemented in Task 5
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_encounter_director.gd 2>&1 | tail -40`
Expected: PASS (16 tests).

- [ ] **Step 5: Commit**

```bash
git add src/core/encounter_director.gd tests/unit/test_encounter_director.gd
git commit -m "feat: active-set reconciliation, soft cap, unregister"
```

---

## Task 5: EncounterDirector — surround slot assignment

**Files:**
- Modify: `src/core/encounter_director.gd`
- Test: `tests/unit/test_encounter_director.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_encounter_director.gd`:

```gdscript
func test_slots_are_distinct_for_each_active() -> void:
	var d = Director.new()
	var list: Array = []
	for ang in [0.0, PI * 0.5, PI, PI * 1.5]:
		list.append(_stub_at(self, Vector2.from_angle(ang) * 50.0, true))
	d.update(Vector2.ZERO, list)
	var seen: Dictionary = {}
	for e in list:
		var a: float = d.get_slot_angle(e)
		seen[snappedf(a, 0.0001)] = true
	assert_int(seen.size()).is_equal(4)  # four distinct angles

func test_slots_spread_around_full_circle() -> void:
	# Four evenly distributed pursuers should span > 3 radians of arc total.
	var d = Director.new()
	var list: Array = []
	for ang in [0.0, PI * 0.5, PI, PI * 1.5]:
		list.append(_stub_at(self, Vector2.from_angle(ang) * 50.0, true))
	d.update(Vector2.ZERO, list)
	var angles: Array = []
	for e in list:
		angles.append(d.get_slot_angle(e))
	angles.sort()
	var span: float = angles[angles.size() - 1] - angles[0]
	assert_float(span).is_greater(3.0)

func test_get_slot_angle_falls_back_to_current_bearing() -> void:
	# An enemy with no assigned slot returns its current bearing to the player.
	var d = Director.new()
	var e := _stub_at(self, Vector2(0, 50), true)  # due south of player
	var a := d.get_slot_angle(e)                   # not in _active yet
	assert_float(a).is_equal_approx((Vector2(0, 50)).angle(), 0.01)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_encounter_director.gd 2>&1 | tail -40`
Expected: FAIL — `Nonexistent function 'get_slot_angle'`.

- [ ] **Step 3: Write minimal implementation**

In `src/core/encounter_director.gd`, **replace** the placeholder `_assign_slots` with the real one and add `get_slot_angle`. Store the player position for the bearing fallback:

```gdscript
var _player_pos: Vector2 = Vector2.ZERO


# Spread the active pursuers evenly around the player. Order them by their
# current bearing (so each keeps roughly its side of the ring), then assign
# evenly spaced target angles starting from the first member's bearing.
func _assign_slots(player_pos: Vector2) -> void:
	_player_pos = player_pos
	_slots.clear()
	var n := _active.size()
	if n == 0:
		return
	var ordered := _active.duplicate()
	ordered.sort_custom(func(x, y):
		return (x.global_position - player_pos).angle() < (y.global_position - player_pos).angle())
	var start: float = (ordered[0].global_position - player_pos).angle()
	for i in range(n):
		_slots[ordered[i]] = start + TAU * float(i) / float(n)


func get_slot_angle(enemy) -> float:
	if _slots.has(enemy):
		return _slots[enemy]
	# Fallback: current bearing from player to the enemy.
	if is_instance_valid(enemy):
		return (enemy.global_position - _player_pos).angle()
	return 0.0
```

Note: the bearing-fallback test uses player at origin, so `_player_pos` defaults to `Vector2.ZERO` and the bearing is `enemy.global_position.angle()`.

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_encounter_director.gd 2>&1 | tail -40`
Expected: PASS (19 tests).

- [ ] **Step 5: Commit**

```bash
git add src/core/encounter_director.gd tests/unit/test_encounter_director.gd
git commit -m "feat: surround slot assignment around the player"
```

---

## Task 6: Wire EncounterDirector into WorldManager

**Files:**
- Modify: `src/core/world_manager.gd:27-28` (declare), `:85` (instantiate), `:99-113` (`_process`)

- [ ] **Step 1: Declare the director field**

In `world_manager.gd`, after the `swarm_grid` / `nav_field` declarations (lines 27-28), add:

```gdscript
var swarm_grid: RefCounted = preload("res://src/core/swarm_grid.gd").new(32.0)
var nav_field  # NavField
var encounter_director: EncounterDirector = EncounterDirector.new()
```

- [ ] **Step 2: Reconcile the director each frame**

In `world_manager.gd` `_process` (currently lines 99-113), after the `swarm_grid.rebuild(...)` line (line 102), add the director update. Read the current floor to size the token pools:

```gdscript
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var attackable := get_tree().get_nodes_in_group("attackable")
	swarm_grid.rebuild(attackable)
	encounter_director.melee_token_count = EncounterDirector.tokens_for_floor(2, LevelManager.floor_number)
	encounter_director.ranged_token_count = EncounterDirector.tokens_for_floor(2, LevelManager.floor_number)
	encounter_director.update(tracking_position, attackable)
	_update_chunks()
	for coord in compute_device.read_solidity_flags(chunks):
		mark_terrain_dirty(coord)
	_run_simulation()
	_collision_helper.rebuild_dirty(chunks, delta)
	if nav_field != null:
		nav_field.update(tracking_position, delta)
	_run_terrain_probes()
	_update_lights()
	_drain_terrain_impacts()
	terrain_physical.set_center(Vector2i(tracking_position))
```

(Replaces the original `swarm_grid.rebuild(get_tree().get_nodes_in_group("attackable"))` line — we now fetch `attackable` once and reuse it.)

- [ ] **Step 3: Verify the project still loads (no test yet — integration wiring)**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_swarm_grid.gd 2>&1 | tail -20`
Expected: PASS — confirms `world_manager.gd` + `encounter_director.gd` parse and the autoload graph is intact (no parse/preload errors surface during suite boot).

- [ ] **Step 4: Commit**

```bash
git add src/core/world_manager.gd
git commit -m "feat: WorldManager owns + reconciles EncounterDirector each frame"
```

---

## Task 7: Enemy — is_pursuing(), director resolution, persistent aggro

**Files:**
- Modify: `src/enemies/enemy.gd` — add fields/methods; edit `_process_chase` (lines 243-283), `die()` (lines 521-523)
- Test: `tests/unit/test_enemy_state_machine.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_enemy_state_machine.gd` (the `MockEnemy` class already exists at the top of the file):

```gdscript
const _Director = preload("res://src/core/encounter_director.gd")

func test_is_pursuing_reflects_aggro() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	assert_bool(e.is_pursuing()).is_false()
	e._aggroed = true
	assert_bool(e.is_pursuing()).is_true()

func test_aggroed_enemy_does_not_leash_when_far() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e._player_ref = auto_free(Node2D.new())
	add_child(e._player_ref)
	e._player_ref.global_position = Vector2(10000, 0)  # well beyond leash_radius
	e.global_position = Vector2.ZERO
	e._aggroed = true
	e._state = Enemy.State.CHASE
	e._process_chase(0.1)
	assert_that(e._state).is_equal(Enemy.State.CHASE)  # never gives up once aggroed

func test_die_unregisters_from_director() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	var d = _Director.new()
	e._director = d
	e._aggroed = true
	d._active = [e]
	d.try_claim_attack(e, false)
	e.die()
	assert_bool(d.is_active(e)).is_false()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_state_machine.gd 2>&1 | tail -40`
Expected: FAIL — `Nonexistent function 'is_pursuing'`.

- [ ] **Step 3: Add fields + director resolver + is_pursuing**

In `enemy.gd`, add near the other private vars (after line 63 `var _weapon_visual`):

```gdscript
var _director = null
var _holds_attack_token: bool = false
```

Add these methods (anywhere among the helpers, e.g. after `_base_effective_speed`):

```gdscript
func is_pursuing() -> bool:
	return _aggroed


func _get_director():
	if _director != null:
		return _director
	if _world_manager != null and is_instance_valid(_world_manager):
		_director = _world_manager.get("encounter_director")
	return _director
```

- [ ] **Step 4: Make aggro persistent in `_process_chase`**

In `enemy.gd` `_process_chase` (lines 243-283), **delete** the leash give-up block:

```gdscript
	# Sticky pursuit: give up only once the player escapes the leash radius.
	if dist > leash_radius:
		_aggroed = false
		_change_state(State.WANDER)
		return
```

Leave the sight-to-acquire block above it intact. An aggroed enemy now pursues via `nav_field` indefinitely.

- [ ] **Step 5: Unregister on death**

In `enemy.gd` `die()` (lines 521-523), add a director cleanup before emitting:

```gdscript
func die() -> void:
	var dir := _get_director()
	if dir != null:
		dir.unregister(self)
	died.emit()
	_on_death()
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_state_machine.gd 2>&1 | tail -40`
Expected: PASS (existing tests + 3 new).

- [ ] **Step 7: Commit**

```bash
git add src/enemies/enemy.gd tests/unit/test_enemy_state_machine.gd
git commit -m "feat: persistent aggro + director resolution on Enemy"
```

---

## Task 8: Enemy — rubber-band catch-up in effective speed

**Files:**
- Modify: `src/enemies/enemy.gd` — `_get_effective_speed` (lines 615-619)
- Test: `tests/unit/test_enemy_state_machine.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_enemy_state_machine.gd`:

```gdscript
func test_effective_speed_capped_below_player_when_far() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.speed = 60.0
	e._speed_base = 60.0
	e._aggroed = true
	e._player_ref = auto_free(Node2D.new())
	add_child(e._player_ref)
	e._player_ref.set("max_speed", 120.0)
	e._player_ref.global_position = Vector2(2000, 0)  # far -> ramps to cap
	e.global_position = Vector2.ZERO
	var s := e._get_effective_speed()
	assert_float(s).is_equal_approx(114.0, 0.001)  # 120 * 0.95

func test_effective_speed_uses_base_when_not_aggroed() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.speed = 60.0
	e._speed_base = 60.0
	e._aggroed = false
	e._player_ref = null
	assert_float(e._get_effective_speed()).is_equal_approx(60.0, 0.001)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_state_machine.gd 2>&1 | tail -40`
Expected: FAIL — far-distance speed is `60.0`, not `114.0`.

- [ ] **Step 3: Implement catch-up in `_get_effective_speed`**

In `enemy.gd`, **replace** `_get_effective_speed` (lines 615-619) with:

```gdscript
func _get_effective_speed() -> float:
	var base := _base_effective_speed()
	if _status_component != null and is_instance_valid(_status_component):
		base *= _status_component.get_move_speed_multiplier()
	return _apply_catch_up(base)


func _apply_catch_up(base: float) -> float:
	if not _aggroed or _player_ref == null or not is_instance_valid(_player_ref):
		return base
	var dist := global_position.distance_to(_player_ref.global_position)
	var player_speed: float = 120.0
	if "max_speed" in _player_ref:
		player_speed = _player_ref.max_speed
	return EncounterDirector.catch_up_speed(base, dist, player_speed)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_state_machine.gd 2>&1 | tail -40`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/enemies/enemy.gd tests/unit/test_enemy_state_machine.gd
git commit -m "feat: rubber-band catch-up applied to Enemy effective speed"
```

---

## Task 9: Enemy — aggro contagion in WANDER

**Files:**
- Modify: `src/enemies/enemy.gd` — `_process_idle` (lines 222-241)
- Test: `tests/unit/test_enemy_state_machine.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_enemy_state_machine.gd`:

```gdscript
class _FakeWorld extends Node:
	var swarm_grid
	var encounter_director

func test_contagion_aggros_idle_enemy_near_pursuer() -> void:
	var d = _Director.new()
	var world := auto_free(_FakeWorld.new())
	add_child(world)
	world.encounter_director = d
	world.swarm_grid = preload("res://src/core/swarm_grid.gd").new(64.0)

	var idle: MockEnemy = auto_free(MockEnemy.new())
	idle.global_position = Vector2.ZERO
	idle._world_manager = world
	idle._director = d
	idle._state = Enemy.State.WANDER
	idle._player_ref = null

	var pursuer: MockEnemy = auto_free(MockEnemy.new())
	pursuer.global_position = Vector2(30, 0)  # within CONTAGION_RADIUS (48)
	pursuer._aggroed = true

	world.swarm_grid.rebuild([idle, pursuer])
	idle._process_idle(0.1)
	assert_bool(idle._aggroed).is_true()
	assert_that(idle._state).is_equal(Enemy.State.CHASE)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_state_machine.gd 2>&1 | tail -40`
Expected: FAIL — `idle._aggroed` stays `false`.

- [ ] **Step 3: Add the contagion check to `_process_idle`**

In `enemy.gd` `_process_idle`, immediately after the existing player-in-range check that changes to CHASE (the first `if` block, lines 223-225), insert:

```gdscript
func _process_idle(delta: float) -> void:
	if _player_ref and is_instance_valid(_player_ref) and _player_in_range:
		_change_state(State.CHASE)
		return

	# Aggro contagion: an aggroed neighbor within CONTAGION_RADIUS wakes us, so a
	# moving horde sweeps up stragglers as it passes them.
	if _get_director() != null and _world_manager != null and is_instance_valid(_world_manager):
		var grid = _world_manager.swarm_grid
		if grid != null:
			var neighbors: Array = grid.query_neighbors(global_position)
			if EncounterDirector.should_aggro_from_neighbors(self, neighbors):
				_aggroed = true
				_change_state(State.CHASE)
				return

	_wander_timer -= delta
	# ... (rest of _process_idle unchanged)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_state_machine.gd 2>&1 | tail -40`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/enemies/enemy.gd tests/unit/test_enemy_state_machine.gd
git commit -m "feat: aggro contagion wakes idle enemies near the horde"
```

---

## Task 10: Enemy — token-gated attacks + surround orbit (melee path)

**Files:**
- Modify: `src/enemies/enemy.gd` — add token/orbit helpers; edit `_process_chase` (lines 243-283), `_change_state` (lines 390-408)
- Test: `tests/unit/test_enemy_state_machine.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_enemy_state_machine.gd`:

```gdscript
func test_chase_attacks_when_token_available() -> void:
	var d = _Director.new()
	d.melee_token_count = 1
	var e: MockEnemy = auto_free(MockEnemy.new())
	e._director = d
	e._aggroed = true
	d._active = [e]
	e._player_ref = auto_free(Node2D.new())
	add_child(e._player_ref)
	e._player_ref.global_position = Vector2(10, 0)
	e.global_position = Vector2.ZERO
	e._attack_range = 32.0
	e._settle_timer = e.min_attack_settle_time + 1.0
	e._process_chase(0.1)
	assert_that(e._state).is_equal(Enemy.State.WINDUP)

func test_chase_holds_when_no_token() -> void:
	var d = _Director.new()
	d.melee_token_count = 0  # no tokens available
	var e: MockEnemy = auto_free(MockEnemy.new())
	e._director = d
	e._aggroed = true
	d._active = [e]
	e._player_ref = auto_free(Node2D.new())
	add_child(e._player_ref)
	e._player_ref.global_position = Vector2(10, 0)
	e.global_position = Vector2.ZERO
	e._attack_range = 32.0
	e._settle_timer = e.min_attack_settle_time + 1.0
	e._process_chase(0.1)
	assert_that(e._state).is_equal(Enemy.State.CHASE)  # cannot commit, keeps circling

func test_change_state_releases_token_on_return_to_chase() -> void:
	var d = _Director.new()
	d.melee_token_count = 1
	var holder: MockEnemy = auto_free(MockEnemy.new())
	var waiter: MockEnemy = auto_free(MockEnemy.new())
	holder._director = d
	waiter._director = d
	d._active = [holder, waiter]
	assert_bool(holder._try_claim_attack()).is_true()
	assert_bool(waiter._try_claim_attack()).is_false()
	holder._change_state(Enemy.State.CHASE)  # leaving the attack cycle
	assert_bool(waiter._try_claim_attack()).is_true()  # token released
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_state_machine.gd 2>&1 | tail -40`
Expected: FAIL — `Nonexistent function '_try_claim_attack'`.

- [ ] **Step 3: Add token + surround helpers**

In `enemy.gd`, add these methods (near `_get_director`):

```gdscript
# Override in ranged enemies so they draw from the ranged token pool.
func _uses_ranged_token() -> bool:
	return false


func _try_claim_attack() -> bool:
	var dir := _get_director()
	if dir == null:
		return true  # no director (legacy / tests): unrestricted
	if dir.try_claim_attack(self, _uses_ranged_token()):
		_holds_attack_token = true
		return true
	return false


func _release_attack() -> void:
	if not _holds_attack_token:
		return
	_holds_attack_token = false
	var dir := _get_director()
	if dir != null:
		dir.release_attack(self)


# Direction to this enemy's assigned surround slot at `preferred_radius`, or
# Vector2.ZERO if unmanaged / already on its slot.
func _surround_dir(preferred_radius: float) -> Vector2:
	var dir := _get_director()
	if dir == null or not dir.is_active(self):
		return Vector2.ZERO
	if _player_ref == null or not is_instance_valid(_player_ref):
		return Vector2.ZERO
	var ang: float = dir.get_slot_angle(self)
	var slot_pos: Vector2 = _player_ref.global_position + Vector2.from_angle(ang) * preferred_radius
	var to_slot := slot_pos - global_position
	if to_slot.length() < 6.0:
		return Vector2.ZERO
	return to_slot.normalized()
```

- [ ] **Step 4: Release the token in `_change_state`**

In `enemy.gd`, **replace** `_change_state` (lines 390-408) with a version that releases the token whenever the enemy leaves the attack cycle (any state that is not WINDUP/ATTACK/COOLDOWN):

```gdscript
func _change_state(new_state: int) -> void:
	if new_state != State.WINDUP and new_state != State.ATTACK and new_state != State.COOLDOWN:
		_release_attack()

	if new_state == State.HURT:
		_prev_state = _state
		_state = new_state
		_state_timer = hurt_duration
		return

	_state = new_state
	match new_state:
		State.WINDUP:
			_state_timer = windup_duration
			_settle_timer = 0.0
			_show_exclaim()
		State.COOLDOWN:
			_state_timer = cooldown_duration * _get_cooldown_multiplier()
		State.DEATH:
			_state_timer = death_duration
			_death_tween = null
```

- [ ] **Step 5: Gate the attack + orbit in `_process_chase`**

In `enemy.gd`, **replace** the tail of `_process_chase` (from `var move_dir: Vector2` at line 270 through the end at line 283) with:

```gdscript
	var move_dir: Vector2
	if sees:
		move_dir = to_player.normalized()
	else:
		var fd := _nav_field_dir()
		move_dir = fd if fd != Vector2.ZERO else to_player.normalized()

	# Try to commit to an attack — only if in range, settled, and a token is free.
	if sees and dist <= _attack_range and _settle_timer >= min_attack_settle_time:
		if _try_claim_attack():
			velocity = Vector2.ZERO
			_change_state(State.WINDUP)
			return

	# No commit this frame: if we're a managed pursuer without a token, orbit our
	# surround slot (just outside attack range) instead of pressing in.
	if not _holds_attack_token:
		var slot_dir := _surround_dir(_attack_range + 8.0)
		if slot_dir != Vector2.ZERO:
			move_dir = slot_dir

	move_dir = _apply_separation(move_dir)
	velocity = move_dir * _get_effective_speed()
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_state_machine.gd 2>&1 | tail -40`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/enemies/enemy.gd tests/unit/test_enemy_state_machine.gd
git commit -m "feat: token-gated attacks + surround orbit for melee enemies"
```

---

## Task 11: RangedEnemy — token gating + surround orbit

**Files:**
- Modify: `src/enemies/ranged_enemy.gd` — `_process_chase` (lines 38-74); add `_uses_ranged_token`
- Test: `tests/unit/test_ranged_enemy_surround.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_ranged_enemy_surround.gd`:

```gdscript
extends GdUnitTestSuite

const _Director = preload("res://src/core/encounter_director.gd")

func test_ranged_uses_ranged_token_pool() -> void:
	var e := auto_free(RangedEnemy.new())
	assert_bool(e._uses_ranged_token()).is_true()

func test_ranged_holds_when_no_ranged_token() -> void:
	var d = _Director.new()
	d.ranged_token_count = 0
	var e := auto_free(RangedEnemy.new())
	e._director = d
	e._aggroed = true
	d._active = [e]
	e._player_ref = auto_free(Node2D.new())
	add_child(e._player_ref)
	e._player_ref.global_position = Vector2(10, 0)
	e.global_position = Vector2.ZERO
	e._attack_range = 200.0
	e.preferred_distance = 120.0
	e._settle_timer = e.min_attack_settle_time + 1.0
	e._process_chase(0.1)
	assert_that(e._state).is_equal(Enemy.State.CHASE)  # no ranged token -> no WINDUP

func test_ranged_attacks_with_ranged_token() -> void:
	var d = _Director.new()
	d.ranged_token_count = 1
	var e := auto_free(RangedEnemy.new())
	e._director = d
	e._aggroed = true
	d._active = [e]
	e._player_ref = auto_free(Node2D.new())
	add_child(e._player_ref)
	e._player_ref.global_position = Vector2(10, 0)
	e.global_position = Vector2.ZERO
	e._attack_range = 200.0
	e.preferred_distance = 120.0
	e._settle_timer = e.min_attack_settle_time + 1.0
	e._process_chase(0.1)
	assert_that(e._state).is_equal(Enemy.State.WINDUP)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ranged_enemy_surround.gd 2>&1 | tail -40`
Expected: FAIL — `Nonexistent function '_uses_ranged_token'` (base returns false; not yet overridden — actually base exists returning false, so first assert fails as `false`).

- [ ] **Step 3: Override the ranged token flag and gate the attack**

In `ranged_enemy.gd`, add the override (after the exports, before `_ready`):

```gdscript
func _uses_ranged_token() -> bool:
	return true
```

Then **replace** the attack-trigger tail of `_process_chase`. The current final block (lines 73-74) is:

```gdscript
	if dist <= _attack_range and _settle_timer >= min_attack_settle_time:
		_change_state(State.WINDUP)
```

Replace it with token-gated commit plus surround orbit when holding no token:

```gdscript
	if dist <= _attack_range and _settle_timer >= min_attack_settle_time:
		if _try_claim_attack():
			_change_state(State.WINDUP)
			return

	# Managed pursuer without a token: drift to the assigned surround slot at
	# preferred distance instead of free-strafing.
	if not _holds_attack_token:
		var slot_dir := _surround_dir(preferred_distance)
		if slot_dir != Vector2.ZERO:
			velocity = _apply_separation(slot_dir) * _get_effective_speed()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ranged_enemy_surround.gd 2>&1 | tail -40`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/enemies/ranged_enemy.gd tests/unit/test_ranged_enemy_surround.gd
git commit -m "feat: ranged enemies use ranged token pool + surround orbit"
```

---

## Task 12: Gauntlet spawning — density multiplier + reinforcement

**Files:**
- Modify: `src/core/spawn_dispatcher.gd` — add density helper + extra spawns; add reinforcement to `_process`
- Test: `tests/unit/test_spawn_gauntlet.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_spawn_gauntlet.gd`:

```gdscript
extends GdUnitTestSuite

const Dispatcher = preload("res://src/core/spawn_dispatcher.gd")

func test_gauntlet_extra_count_is_zero_near_origin() -> void:
	assert_int(Dispatcher.gauntlet_extra_count(0)).is_equal(0)
	assert_int(Dispatcher.gauntlet_extra_count(2)).is_equal(0)

func test_gauntlet_extra_count_grows_with_distance() -> void:
	assert_int(Dispatcher.gauntlet_extra_count(3)).is_equal(1)
	assert_int(Dispatcher.gauntlet_extra_count(6)).is_equal(2)

func test_gauntlet_extra_count_is_capped() -> void:
	assert_int(Dispatcher.gauntlet_extra_count(100)).is_less_equal(4)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_spawn_gauntlet.gd 2>&1 | tail -40`
Expected: FAIL — `Nonexistent function 'gauntlet_extra_count'`.

- [ ] **Step 3: Add the density helper + extra spawns**

In `spawn_dispatcher.gd`, add the pure helper near the top (after the `const` block):

```gdscript
# Gauntlet density: sectors farther from origin (closer to the boss) spawn extra
# enemies per enemy marker. Gentle ramp (~1 extra per 3 rings), hard-capped.
const GAUNTLET_EXTRA_PER_RING := 0.34
const GAUNTLET_EXTRA_CAP := 4

static func gauntlet_extra_count(sector_dist: int) -> int:
	return clampi(int(floor(float(sector_dist) * GAUNTLET_EXTRA_PER_RING)), 0, GAUNTLET_EXTRA_CAP)
```

Then in `_spawn_entity` (currently lines 125-135), change the normal-enemy marker case (`1`) to spawn the base enemy plus the gauntlet extras with small positional jitter:

```gdscript
func _spawn_entity(marker: int, world_pos: Vector2, sector_dist: int, floor_num: int, is_boss_room: bool) -> void:
	match marker:
		1:
			_spawn_enemy_validated(world_pos, sector_dist, floor_num, false, false)
			for _i in range(gauntlet_extra_count(sector_dist)):
				var jitter := Vector2(randf_range(-16, 16), randf_range(-16, 16))
				_spawn_enemy_validated(world_pos + jitter, sector_dist, floor_num, false, false)
		2: _spawn_enemy_validated(world_pos, sector_dist, floor_num, false, true)
		3: _spawn_chest(world_pos, false)
		4: _spawn_shop(world_pos)
		5: _spawn_chest(world_pos, true)
		6: _spawn_enemy(world_pos, sector_dist, floor_num, true, false)
		7: pass
		8: _spawn_lantern(world_pos)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_spawn_gauntlet.gd 2>&1 | tail -40`
Expected: PASS (3 tests).

- [ ] **Step 5: Add the reinforcement trickle**

In `spawn_dispatcher.gd`, add lingering reinforcement. Add fields near `_spawned_sectors` (line 19):

```gdscript
var _reinforce_timer: float = 0.0
const REINFORCE_INTERVAL := 12.0   # seconds of lingering before a reinforcement
const REINFORCE_SPAWN_DIST := 360.0  # spawn this far from the player (offscreen-ish)
```

The dispatcher already has a `_process(_delta)` (lines 24-33) that resolves `_world_manager`. Extend it so that, once the world is resolved, it ticks the reinforcement timer and spawns one extra enemy near the player when it fires:

```gdscript
func _process(delta: float) -> void:
	if _world_manager == null or not is_instance_valid(_world_manager):
		var wm := get_tree().get_first_node_in_group("world_manager")
		if wm == null:
			return
		_world_manager = wm
		_spawn_parent = _world_manager.get_chunk_container()
		_spawned_sectors.clear()
		_world_manager.chunks_generated.connect(_on_chunks_generated)
		return
	_tick_reinforcement(delta)


func _tick_reinforcement(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player):
		return
	_reinforce_timer += delta
	if _reinforce_timer < REINFORCE_INTERVAL:
		return
	_reinforce_timer = 0.0
	var angle := randf() * TAU
	var spawn_pos: Vector2 = player.global_position + Vector2.from_angle(angle) * REINFORCE_SPAWN_DIST
	var resolved: Variant = _resolve_clear_position(spawn_pos)
	if resolved == null:
		return
	var grid: SectorGrid = LevelManager.get_grid()
	var sector_dist: int = 1
	if grid != null:
		sector_dist = grid.chebyshev_distance(grid.world_to_sector(spawn_pos), Vector2i.ZERO)
	_spawn_enemy(resolved, sector_dist, LevelManager.floor_number, false, false)
```

(Note: the original `_process` returned early once `_world_manager` was set; the new version resolves on the first qualifying frame and ticks reinforcement on subsequent frames.)

- [ ] **Step 6: Re-run gauntlet tests (confirm no regression from the edits)**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_spawn_gauntlet.gd 2>&1 | tail -40`
Expected: PASS (3 tests; file still parses with the new `_process`).

- [ ] **Step 7: Commit**

```bash
git add src/core/spawn_dispatcher.gd tests/unit/test_spawn_gauntlet.gd
git commit -m "feat: gauntlet density multiplier + lingering reinforcement"
```

---

## Task 13: Baseline tuning pass — per-hit damage scaling

**Files:**
- Modify: `src/enemies/enemy.gd` — add `damage_scale` export, apply in `_ready`
- Modify: `src/core/spawn_dispatcher.gd` — set `damage_scale` from floor for normal enemies (`_spawn_enemy`, lines 160-200)
- Test: `tests/unit/test_enemy_state_machine.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_enemy_state_machine.gd`:

```gdscript
func test_damage_scale_multiplies_weapon_damage_on_ready() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.weapon = MeleeWeapon.new()
	e.weapon.damage = 5.0
	e.damage_scale = 2.0
	e._apply_damage_scale()
	assert_float(e.weapon.damage).is_equal_approx(10.0, 0.001)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_state_machine.gd 2>&1 | tail -40`
Expected: FAIL — `Invalid set index 'damage_scale'`.

- [ ] **Step 3: Add `damage_scale` to Enemy**

In `enemy.gd`, add the export near the other tunables (after line 23 `leash_radius`):

```gdscript
@export var damage_scale: float = 1.0
```

Add the helper and call it from `_ready` after the weapon is set up. In `_ready`, the subclass sets `weapon` before calling `super._ready()`, so apply scaling early in the base `_ready` (right after `health = max_health` near line 76 is fine, but `weapon` may be null for the base — guard it). Add the method:

```gdscript
func _apply_damage_scale() -> void:
	if weapon != null and damage_scale != 1.0:
		weapon.damage *= damage_scale
```

And call it inside `_ready()` after `_speed_base = speed` (line 77):

```gdscript
	add_to_group("attackable")
	health = max_health
	_speed_base = speed
	_apply_damage_scale()
	motion_mode = MOTION_MODE_FLOATING
```

- [ ] **Step 4: Set `damage_scale` from floor in the dispatcher**

In `spawn_dispatcher.gd` `_spawn_enemy` (lines 160-200), the `damage_mult` is currently computed but only applied to the boss weapon. Assign it to normal enemies via `damage_scale` **before** `add_child` (so it applies during `_ready`). After the existing `enemy.max_health = ...` / `enemy.speed = ...` lines (around line 187-188), add:

```gdscript
	if not is_boss and "damage_scale" in enemy:
		enemy.damage_scale = damage_mult
```

(`damage_mult` is already defined at line 184: `var damage_mult := 1.0 + (floor_num - 1) * 0.15`.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_state_machine.gd 2>&1 | tail -40`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/enemies/enemy.gd src/core/spawn_dispatcher.gd tests/unit/test_enemy_state_machine.gd
git commit -m "feat: per-enemy damage_scale, applied to normal enemies by floor"
```

---

## Task 14: Full suite run + manual playtest checklist

**Files:** none (verification only)

- [ ] **Step 1: Run all new + touched suites**

Run:
```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd \
  -a tests/unit/test_encounter_director.gd \
  -a tests/unit/test_enemy_state_machine.gd \
  -a tests/unit/test_ranged_enemy_surround.gd \
  -a tests/unit/test_spawn_gauntlet.gd \
  -a tests/unit/test_swarm_grid.gd \
  -a tests/unit/test_melee_enemy.gd 2>&1 | tail -60
```
Expected: All suites PASS, zero failures/errors.

- [ ] **Step 2: Run the entire unit suite to catch regressions**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit 2>&1 | tail -60`
Expected: No new failures introduced by this plan (pre-existing unrelated failures, if any, unchanged).

- [ ] **Step 3: Manual playtest checklist (launch the game, verify by feel)**

Launch the project and confirm:
- Walking toward the boss accumulates a horde that does **not** fall away (persistent aggro + rubber-band).
- Passing near idle enemies wakes them into the horde (contagion).
- On stopping, the crowd **surrounds** rather than clumping on one side.
- At most ~2 melee + ~2 ranged attack at any instant; the rest orbit (attack tokens).
- The horde keeps pace but never outruns the player.
- Reaching the boss with a dragged horde is tense but survivable — **watch this for unfair walls** (the #1 tuning risk from the spec).

- [ ] **Step 4: Commit any tuning constant adjustments discovered during playtest**

If playtest reveals needed tweaks, adjust the named constants (`HORDE_SOFT_CAP`, token bases, `TETHER_DISTANCE`, `RAMP_BAND`, `GAUNTLET_EXTRA_PER_RING`, `damage_scale` via floor mult) and commit:

```bash
git add -A
git commit -m "tune: crowd AI baseline constants from playtest"
```

---

## Self-Review Notes

- **Spec coverage:** persistent aggro (T7), contagion (T3/T9), rubber-band keep-pace-never-exceed (T2/T8), horde soft-cap (T4), surround steering (T5/T10/T11), split melee+ranged attack tokens (T1/T10/T11), token release on death/despawn (T4 reconcile + T7 `die()` + T10 `_change_state`), gauntlet density + reinforcement (T12), baseline damage tuning (T13). All spec sections map to a task.
- **Type consistency:** director method names (`update`, `is_active`, `try_claim_attack`, `release_attack`, `unregister`, `get_slot_angle`, static `catch_up_speed` / `should_aggro_from_neighbors` / `tokens_for_floor`) are used identically across tasks. Enemy hooks (`is_pursuing`, `_get_director`, `_try_claim_attack`, `_release_attack`, `_surround_dir`, `_uses_ranged_token`, `_apply_catch_up`, `_apply_damage_scale`, `damage_scale`, `_holds_attack_token`, `_director`) are defined before use.
- **Null-safety:** every enemy hook degrades to legacy behavior when `_get_director()` is null, so the existing `MockEnemy` tests and any non-managed enemy still work.
- **Over-cap behavior (documented simplification):** an aggroed enemy beyond `HORDE_SOFT_CAP` is not in `_active`, so it cannot claim a token (won't attack) and `_surround_dir` returns ZERO (it plain-chases). The cap bounds *attackers* and slot assignments; this is acceptable for v1 and noted as a tuning lever.
