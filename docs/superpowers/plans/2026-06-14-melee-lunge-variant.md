# Melee Lunge Variant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a telegraphed melee "lunge" enemy that winds up, dashes/overshoots through the player's locked position dealing a one-shot body-check, then recovers in a punishable window — while the default melee enemy stays exactly as it is.

**Architecture:** One opt-in base hook (`_moves_during_attack()`, default `false`) lets an enemy move during the existing `ATTACK` state. A new thin `LungeEnemy extends MeleeEnemy` drives a dash entirely within the existing WANDER → CHASE → WINDUP → ATTACK → COOLDOWN state machine: WINDUP telegraphs, ATTACK is the dash + body-check, COOLDOWN is the recovery window. A minority of melee spawns become lunges.

**Tech Stack:** Godot 4.6 / GDScript; GdUnit4 headless tests; `CharacterBody2D` enemies; `Weapon extends Resource`.

**Test command (used throughout):**
```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/<file>.gd 2>&1 | tail -40
```
A run prints a summary table; "passed" with `0` failures/errors is success.

**Reference (do not modify, read for context):** `src/enemies/enemy.gd` (state machine: `_process_attack` ~304, `_process_cooldown` ~316, `_change_state` ~405, `_physics_process` ~191, `get_facing_direction` ~632, `_move_with_clamp` ~396), `src/enemies/melee_enemy.gd`, `src/enemies/sniper_enemy.gd` (telegraph subclass precedent), `src/player/player_controller.gd:322` (`on_hit_impact`), `tests/unit/test_sniper_enemy.gd` (mock-player test pattern), `tests/unit/test_ranged_pattern_spawn.gd` (dispatcher test pattern).

---

## File Structure

- **Modify** `src/enemies/enemy.gd` — add the `_moves_during_attack()` hook (default `false`) and one clause in the `_physics_process` movement gate.
- **Create** `src/enemies/lunge_enemy.gd` — `LungeEnemy extends MeleeEnemy`; all lunge behavior.
- **Create** `scenes/enemies/lunge_enemy.tscn` — instances `enemy.tscn`, attaches `lunge_enemy.gd`.
- **Modify** `src/core/spawn_dispatcher.gd` — preload the lunge scene, add the `roll_melee_is_lunge` helper + constant, split the melee spawn branch.
- **Create** `tests/unit/test_lunge_enemy.gd` — all `LungeEnemy`/base-hook unit tests.
- **Create** `tests/unit/test_lunge_spawn.gd` — spawn-distribution helper tests.

---

## Task 1: Opt-in `_moves_during_attack()` base hook

**Files:**
- Modify: `src/enemies/enemy.gd` (add method near `_attack_in_progress` ~312; edit `_physics_process` movement gate ~206)
- Test: `tests/unit/test_lunge_enemy.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_lunge_enemy.gd`:

```gdscript
extends GdUnitTestSuite

# --- Task 1: base hook defaults off ---

func test_base_enemy_does_not_move_during_attack() -> void:
	var e: MeleeEnemy = auto_free(MeleeEnemy.new())
	add_child(e)
	assert_bool(e._moves_during_attack()).is_false()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lunge_enemy.gd 2>&1 | tail -40`
Expected: FAIL — `Invalid call. Nonexistent function '_moves_during_attack'`.

- [ ] **Step 3: Add the hook and the gate clause**

In `src/enemies/enemy.gd`, add this method directly below `_attack_in_progress()`:

```gdscript
func _moves_during_attack() -> bool:
	return false
```

Then change the movement gate in `_physics_process` from:

```gdscript
	if _state == State.WANDER or _state == State.CHASE or _state == State.HURT:
		_move_with_clamp(delta)
```

to:

```gdscript
	if _state == State.WANDER or _state == State.CHASE or _state == State.HURT \
			or (_state == State.ATTACK and _moves_during_attack()):
		_move_with_clamp(delta)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lunge_enemy.gd 2>&1 | tail -40`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add src/enemies/enemy.gd tests/unit/test_lunge_enemy.gd
git commit -m "feat: opt-in _moves_during_attack hook for enemy ATTACK movement"
```

---

## Task 2: `LungeEnemy` skeleton — class, tunables, `_ready`, dash-begin

**Files:**
- Create: `src/enemies/lunge_enemy.gd`
- Test: `tests/unit/test_lunge_enemy.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_lunge_enemy.gd`:

```gdscript
# --- Task 2: skeleton ---

func _lunge_at(origin: Vector2, player_pos: Vector2) -> LungeEnemy:
	var e: LungeEnemy = auto_free(LungeEnemy.new())
	add_child(e)
	e.global_position = origin
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = player_pos
	e._player_ref = p
	return e

func test_ready_sets_lunge_attack_range() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	assert_float(e._attack_range).is_equal(e.lunge_range)

func test_begin_dash_locks_direction_toward_player() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	e._begin_dash()
	assert_float(e._lock_dir.angle()).is_equal_approx(0.0, 0.01)
	assert_float(e._dash_timer).is_equal(e.dash_duration)
	assert_bool(e._dash_hit).is_false()

func test_moves_during_attack_tracks_state_and_dash_done() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	e._state = Enemy.State.CHASE
	assert_bool(e._moves_during_attack()).is_false()
	e._state = Enemy.State.ATTACK
	e._dash_done = false
	assert_bool(e._moves_during_attack()).is_true()
	e._dash_done = true
	assert_bool(e._moves_during_attack()).is_false()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lunge_enemy.gd 2>&1 | tail -40`
Expected: FAIL — `Could not find type "LungeEnemy"` / parser error.

- [ ] **Step 3: Create the class**

Create `src/enemies/lunge_enemy.gd`:

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
var _dash_done: bool = false  # set when a dash finishes; blocks restart after a HURT interrupt


func _ready() -> void:
	super._ready()
	_attack_range = lunge_range
	windup_duration = 0.45
	cooldown_duration = recovery_duration


func _begin_dash() -> void:
	_lock_dir = get_facing_direction()
	_dash_timer = dash_duration
	_dash_hit = false


func _moves_during_attack() -> bool:
	return _state == State.ATTACK and not _dash_done
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lunge_enemy.gd 2>&1 | tail -40`
Expected: PASS (4 tests total).

- [ ] **Step 5: Commit**

```bash
git add src/enemies/lunge_enemy.gd tests/unit/test_lunge_enemy.gd
git commit -m "feat: LungeEnemy skeleton with dash tunables and direction lock"
```

---

## Task 3: The dash — movement, body-check, termination

Implements the full `ATTACK`-state dash: drive velocity along the locked direction, deal a one-shot body-check, and transition to `COOLDOWN` when the dash timer expires. The `_dash_done` guard makes a re-entered `ATTACK` (e.g. after a HURT interrupt) fall straight through to recovery instead of dashing again.

**Files:**
- Modify: `src/enemies/lunge_enemy.gd`
- Test: `tests/unit/test_lunge_enemy.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_lunge_enemy.gd`:

```gdscript
# --- Task 3: dash tick + body-check + termination ---

class _RecordingPlayer extends Node2D:
	var hits: Array = []
	func on_hit_impact(pos: Vector2, dir: Vector2, dmg: int) -> void:
		hits.append({"pos": pos, "dir": dir, "dmg": dmg})

func _lunge_with_recording_player(origin: Vector2, player_pos: Vector2) -> LungeEnemy:
	var e: LungeEnemy = auto_free(LungeEnemy.new())
	add_child(e)
	e.global_position = origin
	var p := _RecordingPlayer.new()
	auto_free(p)
	add_child(p)
	p.global_position = player_pos
	e._player_ref = p
	return e

func test_dash_sets_velocity_along_lock_dir() -> void:
	var e := _lunge_with_recording_player(Vector2.ZERO, Vector2(100, 0))
	e._state = Enemy.State.ATTACK
	e._attack_started = false
	e._dash_done = false
	e._process_attack(0.05)
	assert_float(e.velocity.x).is_equal_approx(e.dash_speed, 0.01)
	assert_float(e.velocity.y).is_equal_approx(0.0, 0.01)

func test_dash_terminates_into_cooldown() -> void:
	var e := _lunge_with_recording_player(Vector2.ZERO, Vector2(100, 0))
	e._state = Enemy.State.ATTACK
	e._attack_started = false
	e._dash_done = false
	# Run more than dash_duration worth of frames.
	for i in range(20):
		if e._state != Enemy.State.ATTACK:
			break
		e._process_attack(0.05)
	assert_int(e._state).is_equal(Enemy.State.COOLDOWN)
	assert_bool(e._dash_done).is_true()

func test_body_check_hits_once_within_contact_radius() -> void:
	# Player sits on top of the enemy (within contact_radius).
	var e := _lunge_with_recording_player(Vector2.ZERO, Vector2(5, 0))
	e.weapon.damage = 7.0
	e._state = Enemy.State.ATTACK
	e._attack_started = false
	e._dash_done = false
	for i in range(20):
		if e._state != Enemy.State.ATTACK:
			break
		e._process_attack(0.05)
	assert_int(e._player_ref.hits.size()).is_equal(1)
	assert_int(e._player_ref.hits[0]["dmg"]).is_equal(7)

func test_sidestepped_player_takes_no_hit() -> void:
	# Player well outside contact_radius for the whole dash.
	var e := _lunge_with_recording_player(Vector2.ZERO, Vector2(200, 0))
	e._state = Enemy.State.ATTACK
	e._attack_started = false
	e._dash_done = false
	for i in range(20):
		if e._state != Enemy.State.ATTACK:
			break
		e._process_attack(0.05)
	assert_int(e._player_ref.hits.size()).is_equal(0)

func test_dash_done_blocks_restart() -> void:
	var e := _lunge_with_recording_player(Vector2.ZERO, Vector2(5, 0))
	e._state = Enemy.State.ATTACK
	e._attack_started = false
	e._dash_done = true  # simulate a dash already consumed this cycle
	e._process_attack(0.05)
	assert_int(e._state).is_equal(Enemy.State.COOLDOWN)
	assert_int(e._player_ref.hits.size()).is_equal(0)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lunge_enemy.gd 2>&1 | tail -40`
Expected: FAIL — `_process_attack` is inherited from `Enemy` and calls `_execute_attack` (a swing), so velocity is never set; the new assertions fail.

- [ ] **Step 3: Implement the dash**

Add to `src/enemies/lunge_enemy.gd` (below `_moves_during_attack`):

```gdscript
func _process_attack(delta: float) -> void:
	if not _attack_started:
		_attack_started = true
		if _dash_done:
			_change_state(State.COOLDOWN)
			return
		_begin_dash()
	_tick_dash(delta)


func _tick_dash(delta: float) -> void:
	velocity = _lock_dir * dash_speed
	_check_body_contact()
	_dash_timer -= delta
	if _dash_timer <= 0.0:
		_dash_done = true
		velocity = Vector2.ZERO
		_change_state(State.COOLDOWN)


func _check_body_contact() -> void:
	if _dash_hit:
		return
	if _player_ref == null or not is_instance_valid(_player_ref):
		return
	if global_position.distance_to(_player_ref.global_position) > contact_radius:
		return
	_dash_hit = true
	if _player_ref.has_method("on_hit_impact"):
		var dmg: int = int(weapon.damage) if weapon else 0
		_player_ref.on_hit_impact(global_position, _lock_dir, dmg)
```

Note: `LungeEnemy` never calls `weapon.use()` — overriding `_process_attack` bypasses the inherited `_execute_attack` swing entirely; the weapon exists only for `weapon.damage`, the held-weapon visual, and the drop. Terrain is handled by `_move_with_clamp` (in `_physics_process`), which axis-clamps the dash against solids so it cannot phase through walls.

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lunge_enemy.gd 2>&1 | tail -40`
Expected: PASS (9 tests total).

- [ ] **Step 5: Commit**

```bash
git add src/enemies/lunge_enemy.gd tests/unit/test_lunge_enemy.gd
git commit -m "feat: lunge dash with one-shot body-check and recovery transition"
```

---

## Task 4: Windup reset + telegraph (`_change_state` override)

On entering `WINDUP`, clear `_dash_done` so the next dash can fire, and play the commit telegraph (exclaim is already shown by the base; add a flash + anticipation squash by reusing existing `Enemy` feedback methods).

**Files:**
- Modify: `src/enemies/lunge_enemy.gd`
- Test: `tests/unit/test_lunge_enemy.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_lunge_enemy.gd`:

```gdscript
# --- Task 4: windup reset + telegraph ---

func test_entering_windup_resets_dash_done() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	e._dash_done = true
	e._change_state(Enemy.State.WINDUP)
	assert_bool(e._dash_done).is_false()
	assert_int(e._state).is_equal(Enemy.State.WINDUP)

func test_entering_windup_runs_telegraph_without_error() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	# Should not error and should set the windup timer via super._change_state.
	e._change_state(Enemy.State.WINDUP)
	assert_float(e._state_timer).is_equal(e.windup_duration)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lunge_enemy.gd 2>&1 | tail -40`
Expected: FAIL — `_dash_done` stays `true` (base `_change_state` doesn't touch it).

- [ ] **Step 3: Override `_change_state`**

Add to `src/enemies/lunge_enemy.gd`:

```gdscript
func _change_state(new_state: int) -> void:
	if new_state == State.WINDUP:
		_dash_done = false
		_play_windup_telegraph()
	super._change_state(new_state)


func _play_windup_telegraph() -> void:
	# Reuse existing Enemy feedback: a bright flash + squash pop reads the commit.
	# (The "!" exclaim is already shown by Enemy._change_state on WINDUP entry.)
	_play_hit_flash()
	_play_squash()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lunge_enemy.gd 2>&1 | tail -40`
Expected: PASS (11 tests total).

- [ ] **Step 5: Commit**

```bash
git add src/enemies/lunge_enemy.gd tests/unit/test_lunge_enemy.gd
git commit -m "feat: lunge windup telegraph and dash-done reset"
```

---

## Task 5: Lunge enemy scene

**Files:**
- Create: `scenes/enemies/lunge_enemy.tscn`
- Test: `tests/unit/test_lunge_enemy.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_lunge_enemy.gd`:

```gdscript
# --- Task 5: scene ---

func test_scene_instantiates_as_lunge_enemy() -> void:
	var scene: PackedScene = load("res://scenes/enemies/lunge_enemy.tscn")
	assert_object(scene).is_not_null()
	var e = auto_free(scene.instantiate())
	add_child(e)
	assert_bool(e is LungeEnemy).is_true()
	assert_float(e._attack_range).is_equal(e.lunge_range)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lunge_enemy.gd 2>&1 | tail -40`
Expected: FAIL — `load(...)` returns null (scene does not exist).

- [ ] **Step 3: Create the scene file**

Create `scenes/enemies/lunge_enemy.tscn` (modeled on `melee_enemy.tscn`, reusing the melee sprite):

```
[gd_scene format=3 uid="uid://lungeenemy01"]

[ext_resource type="PackedScene" uid="uid://enemybase01" path="res://scenes/enemies/enemy.tscn" id="1"]
[ext_resource type="Script" path="res://src/enemies/lunge_enemy.gd" id="2"]
[ext_resource type="Texture2D" uid="uid://dmbgucc3swig" path="res://textures/Enemies/melee_test.png" id="3"]

[node name="LungeEnemy" instance=ExtResource("1")]
script = ExtResource("2")
weapon_resource = null

[node name="Sprite2D" parent="." index="0"]
texture = ExtResource("3")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lunge_enemy.gd 2>&1 | tail -40`
Expected: PASS (12 tests total).

- [ ] **Step 5: Commit**

```bash
git add scenes/enemies/lunge_enemy.tscn tests/unit/test_lunge_enemy.gd
git commit -m "feat: lunge enemy scene"
```

---

## Task 6: Spawn wiring — a minority of melee spawns become lunges

**Files:**
- Modify: `src/core/spawn_dispatcher.gd` (constants ~3-9; `_spawn_enemy` melee branch ~209-211; add helper near `_pick_melee_weapon` ~245)
- Test: `tests/unit/test_lunge_spawn.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_lunge_spawn.gd`:

```gdscript
extends GdUnitTestSuite

const SpawnDispatcher = preload("res://src/core/spawn_dispatcher.gd")

func test_roll_melee_is_lunge_boundaries() -> void:
	assert_bool(SpawnDispatcher.roll_melee_is_lunge(0.0)).is_true()
	assert_bool(SpawnDispatcher.roll_melee_is_lunge(0.24)).is_true()
	assert_bool(SpawnDispatcher.roll_melee_is_lunge(0.25)).is_false()
	assert_bool(SpawnDispatcher.roll_melee_is_lunge(0.9)).is_false()

func test_lunge_chance_keeps_default_melee_majority() -> void:
	assert_float(SpawnDispatcher.LUNGE_MELEE_CHANCE).is_less(0.5)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lunge_spawn.gd 2>&1 | tail -40`
Expected: FAIL — `Invalid call ... roll_melee_is_lunge` / nonexistent constant `LUNGE_MELEE_CHANCE`.

- [ ] **Step 3: Add the constant, helper, scene preload, and branch split**

In `src/core/spawn_dispatcher.gd`, add the scene preload alongside the other scene consts (after the `SNIPER_ENEMY_SCENE` line ~6):

```gdscript
const LUNGE_ENEMY_SCENE := preload("res://scenes/enemies/lunge_enemy.tscn")
```

Add the chance constant near the other gameplay constants (e.g. after `GAUNTLET_EXTRA_CAP` ~21):

```gdscript
const LUNGE_MELEE_CHANCE := 0.25
```

Add the helper next to `_pick_melee_weapon` (~245):

```gdscript
static func roll_melee_is_lunge(r: float) -> bool:
	return r < LUNGE_MELEE_CHANCE
```

Then change the non-elite melee branch in `_spawn_enemy` from:

```gdscript
			if randf() < 0.8:
				enemy = MELEE_ENEMY_SCENE.instantiate()
				enemy.weapon_resource = _pick_melee_weapon()
```

to:

```gdscript
			if randf() < 0.8:
				if roll_melee_is_lunge(randf()):
					enemy = LUNGE_ENEMY_SCENE.instantiate()
				else:
					enemy = MELEE_ENEMY_SCENE.instantiate()
				enemy.weapon_resource = _pick_melee_weapon()
```

(`LungeEnemy` inherits the `weapon_resource: MeleeWeapon` export from `MeleeEnemy`, so the same assignment works for both.)

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lunge_spawn.gd 2>&1 | tail -40`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/core/spawn_dispatcher.gd tests/unit/test_lunge_spawn.gd
git commit -m "feat: spawn a minority of melee enemies as lunge variants"
```

---

## Task 7: Full-suite verification + manual playtest

**Files:** none (verification only)

- [ ] **Step 1: Run the full unit suite**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit 2>&1 | tail -50`
Expected: all suites pass, `0` failures and `0` errors. In particular `test_lunge_enemy.gd` (12), `test_lunge_spawn.gd` (2), and the existing `test_enemy_state_machine.gd` / `test_sniper_enemy.gd` / ranged-pattern suites are green (confirms the `_physics_process` gate change didn't regress other enemies).

- [ ] **Step 2: Manual playtest checklist**

Launch the game and confirm:
- Lunge enemies appear among melee spawns but are the minority; default melee enemies still walk in and swing unchanged.
- The lunge telegraphs (`!` + flash/squash) and **holds** during windup, then commits a fast dash along the direction it was facing at lock time.
- Standing still gets hit; reading the tell and side-stepping dodges the dash and leaves the enemy overshooting into a visible recovery window where it can be freely hit.
- The dash does not phase through walls — it stops against terrain.
- Getting a hit in on the lunger mid-dash interrupts it (knockback) and it does not re-dash; it recovers.

- [ ] **Step 3: Commit any tuning changes**

If the playtest needs tuning (`lunge_range`, `dash_speed`, `dash_duration`, `recovery_duration`, `windup_duration`, `LUNGE_MELEE_CHANCE`), adjust and commit:

```bash
git add -A
git commit -m "tune: lunge enemy pacing from playtest"
```

---

## Self-Review (spec coverage)

- **Telegraphed commit (windup → dash/overshoot → recovery)** → Tasks 2 (windup range/duration), 3 (dash + termination to COOLDOWN recovery), 4 (windup telegraph). ✅
- **Reward movement / side-step is safe** → Task 3 `test_sidestepped_player_takes_no_hit`; direction locks at dash begin (Task 2/3). ✅
- **Default melee unchanged** → Task 1 base hook defaults `false`; Task 6 keeps default the majority (`LUNGE_MELEE_CHANCE = 0.25`); Task 7 full-suite regression. ✅
- **Body-check damage model (one hit, contact radius, weapon.damage, i-frame-safe via one-hit flag)** → Task 3 `_check_body_contact` + tests. ✅
- **No new states; reuse WANDER→…→COOLDOWN** → Tasks 2-4 map onto existing states; only `_process_attack`/`_change_state` overridden. ✅
- **`_moves_during_attack()` opt-in hook** → Task 1. ✅
- **`LungeEnemy extends MeleeEnemy` reusing weapon/drop/visual** → Task 2; weapon only for damage/visual/drop (Task 3 note). ✅
- **Scene + spawn wiring** → Tasks 5, 6. ✅
- **HURT-interrupt guard (`_dash_done`)** → Task 3 `test_dash_done_blocks_restart`, Task 4 reset on WINDUP. ✅
- **Terrain stop (no phasing)** → handled by `_move_with_clamp`; noted in Task 3, verified in Task 7 playtest. ✅
- **Out of scope: Shield-front, Pounce** → not in any task (correctly deferred). ✅
