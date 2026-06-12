# Ranged & Sniper Threat Patterns Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give ranged enemies distinct, readable firing patterns — an aimed burst (default), split-shot and fan variants, and a telegraphed cover-destroying sniper — all riding one shared burst engine.

**Architecture:** Add a burst timeline to the `RangedWeapon` base (one place owns shot scheduling, interval, and re-aim). Each pattern is a thin `RangedWeapon` subclass that only configures defaults / overrides one shot's spatial emission. The enemy gains one hook (`_attack_in_progress()`) so its ATTACK state persists while the weapon is mid-burst; everything else reuses the existing per-frame `weapon.tick()` that enemies (`enemy.gd:191`) and the player (`weapon_manager.gd:113`) already call. The sniper is a `RangedEnemy` subclass (movement unchanged) with a tracking aim-line that locks, firing a high-damage round that penetrates terrain via a small `ProjectileBehavior`.

**Tech Stack:** Godot 4.6, GDScript, GdUnit4 tests. Builds on SP1 (EncounterDirector + ranged token pool, already merged).

---

## Spec

`docs/superpowers/specs/2026-06-12-ranged-sniper-threat-patterns-design.md`

## Test command

Run a single suite headless:

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/<file>.gd 2>&1 | tail -40
```

(`godot` is at `/usr/bin/godot`. "Expected: PASS" below means the GdUnit summary reports 0 failures / 0 errors for the named suite.)

## File Structure

**Create:**
- `src/weapons/aimed_burst_weapon.gd` — `AimedBurstWeapon`: 3-round re-aiming burst (the default ranged pattern).
- `src/weapons/split_shot_weapon.gd` — `SplitShotWeapon`: two diverging bullets, no bullet down the center.
- `src/weapons/fan_weapon.gd` — `FanWeapon`: center + two spread shots.
- `src/weapons/sniper_weapon.gd` — `SniperWeapon`: single heavy round, attaches the penetration behavior.
- `src/weapons/sniper_penetration_behavior.gd` — `SniperPenetrationBehavior`: keeps a round alive (carving) through a budget of terrain hits.
- `src/enemies/sniper_enemy.gd` — `SniperEnemy`: tracking aim-line telegraph that locks; uses `SniperWeapon`.
- `scenes/enemies/sniper_enemy.tscn` — sniper enemy scene (instances `enemy.tscn`, sets the sniper script).
- Test files under `tests/unit/` (one per task, named in each task).

**Modify:**
- `src/weapons/ranged_weapon.gd` — add the burst timeline, the `shot_sink` test seam, the `_emit_shot` / `_configure` / `_make_behaviors` hooks.
- `src/enemies/enemy.gd` — add `_attack_in_progress()` hook + sustained ATTACK in `_process_attack` + `_attack_started` reset.
- `src/enemies/ranged_enemy.gd` — override `_attack_in_progress()`.
- `src/weapons/projectile.gd` — let the enemy-projectile terrain branch consult `behaviors` (enables sniper penetration).
- `src/core/spawn_dispatcher.gd` — assign the new patterns; add a rare sniper spawn.

---

## Task 1: Test seam + extract `_emit_shot` on RangedWeapon

Establish a headless-testable firing seam and pull the volley logic out of `_use_impl` into an overridable `_emit_shot`. Pure refactor — single-shot behavior is unchanged.

**Files:**
- Modify: `src/weapons/ranged_weapon.gd`
- Test: `tests/unit/test_ranged_weapon_burst.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_ranged_weapon_burst.gd`:

```gdscript
extends GdUnitTestSuite

const RangedWeaponScript = preload("res://src/weapons/ranged_weapon.gd")

class _FakeShooter extends Node2D:
	var facing := Vector2.RIGHT
	func get_facing_direction() -> Vector2:
		return facing

func _shooter(facing: Vector2) -> _FakeShooter:
	var s: _FakeShooter = auto_free(_FakeShooter.new())
	add_child(s)
	s.facing = facing
	return s

func test_single_shot_emits_one_along_facing() -> void:
	var w := RangedWeaponScript.new()
	var dirs: Array = []
	w.shot_sink = func(d): dirs.append(d)
	w.use(_shooter(Vector2.RIGHT))
	assert_int(dirs.size()).is_equal(1)
	assert_float(dirs[0].angle()).is_equal_approx(0.0, 0.01)

func test_spread_emits_count_shots_at_edges() -> void:
	var w := RangedWeaponScript.new()
	w.projectile_count = 3
	w.spread_angle = 90.0
	var dirs: Array = []
	w.shot_sink = func(d): dirs.append(d)
	w.use(_shooter(Vector2.RIGHT))
	assert_int(dirs.size()).is_equal(3)
	assert_float(dirs[0].angle()).is_equal_approx(deg_to_rad(-45.0), 0.01)
	assert_float(dirs[2].angle()).is_equal_approx(deg_to_rad(45.0), 0.01)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ranged_weapon_burst.gd 2>&1 | tail -40`
Expected: FAIL — `shot_sink` is not a property of `RangedWeapon` (invalid set), or assertion failure.

- [ ] **Step 3: Add the seam and extract `_emit_shot`**

In `src/weapons/ranged_weapon.gd`, add the injectable sink near the other vars (after line 14, `projectile_texture`):

```gdscript
# Injectable spawn sink for headless tests; when valid, _spawn_projectile calls
# this with the bullet direction instead of instancing the projectile scene.
var shot_sink: Callable = Callable()
```

Replace the existing `_use_impl` (lines 47-63) with a thin starter that delegates to `_emit_shot`:

```gdscript
func _use_impl(user: Node) -> void:
	_emit_shot(user, _get_facing_direction(user))


# Emits one "shot" — a volley of projectile_count bullets across spread_angle,
# centered on base_dir. Subclasses override this to change the spatial pattern.
func _emit_shot(user: Node, base_dir: Vector2) -> void:
	var base_angle := base_dir.angle()
	var half_spread := deg_to_rad(spread_angle) / 2.0
	for i in range(projectile_count):
		var angle_offset: float = 0.0
		if projectile_count > 1:
			angle_offset = lerpf(-half_spread, half_spread, float(i) / float(projectile_count - 1))
		var proj_dir := Vector2(cos(base_angle + angle_offset), sin(base_angle + angle_offset))
		_spawn_projectile(user, proj_dir)
	notify_attack(user, {
		"direction": base_dir,
		"origin": user.global_position,
		"charged": false,
		"charge_ratio": 0.0,
	})
```

In `_spawn_projectile` (currently line 66), add the sink short-circuit as the first lines of the function body:

```gdscript
func _spawn_projectile(user: Node, direction: Vector2) -> void:
	if shot_sink.is_valid():
		shot_sink.call(direction.normalized())
		return
	# ... existing body unchanged ...
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ranged_weapon_burst.gd 2>&1 | tail -40`
Expected: PASS (2 tests).

- [ ] **Step 5: Run the existing ranged weapon suite to confirm no regression**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ranged_weapon.gd 2>&1 | tail -40`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/weapons/ranged_weapon.gd tests/unit/test_ranged_weapon_burst.gd
git commit -m "refactor: extract RangedWeapon._emit_shot + add shot_sink test seam"
```

---

## Task 2: Burst timeline on RangedWeapon

Add the timed multi-shot timeline: `burst_count` shots fired `burst_interval` apart, optionally re-aiming each shot, advanced by the weapon's existing per-frame `tick()`.

**Files:**
- Modify: `src/weapons/ranged_weapon.gd`
- Test: `tests/unit/test_ranged_weapon_burst.gd` (extend)

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_ranged_weapon_burst.gd`:

```gdscript
func test_single_shot_weapon_is_not_bursting() -> void:
	var w := RangedWeaponScript.new()  # burst_count defaults to 1
	w.shot_sink = func(_d): pass
	w.use(_shooter(Vector2.RIGHT))
	assert_bool(w.is_bursting()).is_false()

func test_burst_fires_count_shots_over_time() -> void:
	var w := RangedWeaponScript.new()
	w.burst_count = 3
	w.burst_interval = 0.1
	var dirs: Array = []
	w.shot_sink = func(d): dirs.append(d)
	w.use(_shooter(Vector2.RIGHT))
	assert_int(dirs.size()).is_equal(1)
	assert_bool(w.is_bursting()).is_true()
	w.tick(0.1)
	assert_int(dirs.size()).is_equal(2)
	w.tick(0.1)
	assert_int(dirs.size()).is_equal(3)
	assert_bool(w.is_bursting()).is_false()
	w.tick(0.1)
	assert_int(dirs.size()).is_equal(3)

func test_reaim_changes_later_shot_directions() -> void:
	var w := RangedWeaponScript.new()
	w.burst_count = 2
	w.burst_interval = 0.1
	w.reaim_each_shot = true
	var shooter := _shooter(Vector2.RIGHT)
	var dirs: Array = []
	w.shot_sink = func(d): dirs.append(d)
	w.use(shooter)
	shooter.facing = Vector2.UP
	w.tick(0.1)
	assert_float(dirs[0].angle()).is_equal_approx(0.0, 0.01)
	assert_float(dirs[1].angle()).is_equal_approx(Vector2.UP.angle(), 0.01)

func test_no_reaim_keeps_initial_direction() -> void:
	var w := RangedWeaponScript.new()
	w.burst_count = 2
	w.burst_interval = 0.1
	w.reaim_each_shot = false
	var shooter := _shooter(Vector2.RIGHT)
	var dirs: Array = []
	w.shot_sink = func(d): dirs.append(d)
	w.use(shooter)
	shooter.facing = Vector2.UP
	w.tick(0.1)
	assert_float(dirs[1].angle()).is_equal_approx(0.0, 0.01)

func test_burst_ends_if_user_freed() -> void:
	var w := RangedWeaponScript.new()
	w.burst_count = 3
	w.burst_interval = 0.1
	var shooter := _FakeShooter.new()
	add_child(shooter)
	w.shot_sink = func(_d): pass
	w.use(shooter)
	shooter.free()
	w.tick(0.1)
	assert_bool(w.is_bursting()).is_false()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ranged_weapon_burst.gd 2>&1 | tail -40`
Expected: FAIL — `burst_count` / `is_bursting` not defined.

- [ ] **Step 3: Implement the burst timeline**

In `src/weapons/ranged_weapon.gd`, add exported fields near the other exports (after `projectile_count`, line 9):

```gdscript
@export var burst_count: int = 1
@export var burst_interval: float = 0.12
@export var reaim_each_shot: bool = false
```

> These MUST be `@export` — enemies receive their weapon via `weapon_resource.duplicate()`, and `duplicate()` drops plain `var`s (see memory: weapon-csv-fields-must-be-export).

Add internal state near `shot_sink`:

```gdscript
var _shots_left: int = 0
var _burst_timer: float = 0.0
var _burst_dir: Vector2 = Vector2.RIGHT
var _burst_user: Node = null
```

At the end of the existing `_init()` (after line 22, `rarity = ...`), call a config hook so subclasses can set defaults:

```gdscript
	_configure()


# Override point for pattern subclasses to set their default field values.
func _configure() -> void:
	pass
```

Replace the `_use_impl` body from Task 1 with a burst starter:

```gdscript
func _use_impl(user: Node) -> void:
	_burst_user = user
	_burst_dir = _get_facing_direction(user)
	_shots_left = maxi(0, burst_count - 1)
	_burst_timer = burst_interval
	_emit_shot(user, _burst_dir)


func _tick_impl(delta: float) -> void:
	if _shots_left <= 0:
		return
	if not is_instance_valid(_burst_user):
		_shots_left = 0
		return
	_burst_timer -= delta
	if _burst_timer <= 0.0:
		_burst_timer += burst_interval
		_burst_dir = _get_facing_direction(_burst_user) if reaim_each_shot else _burst_dir
		_emit_shot(_burst_user, _burst_dir)
		_shots_left -= 1


func is_bursting() -> bool:
	return _shots_left > 0
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ranged_weapon_burst.gd 2>&1 | tail -40`
Expected: PASS (7 tests total in the file).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/ranged_weapon.gd tests/unit/test_ranged_weapon_burst.gd
git commit -m "feat: RangedWeapon burst timeline (count, interval, re-aim)"
```

---

## Task 3: AimedBurstWeapon (default pattern)

A thin subclass: 3-round burst, re-aims each shot, single bullet per shot.

**Files:**
- Create: `src/weapons/aimed_burst_weapon.gd`
- Test: `tests/unit/test_ranged_pattern_weapons.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_ranged_pattern_weapons.gd`:

```gdscript
extends GdUnitTestSuite

class _FakeShooter extends Node2D:
	var facing := Vector2.RIGHT
	func get_facing_direction() -> Vector2:
		return facing

func _shooter(facing: Vector2) -> _FakeShooter:
	var s: _FakeShooter = auto_free(_FakeShooter.new())
	add_child(s)
	s.facing = facing
	return s

func test_aimed_burst_defaults() -> void:
	var w := AimedBurstWeapon.new()
	assert_int(w.burst_count).is_equal(3)
	assert_bool(w.reaim_each_shot).is_true()
	assert_int(w.projectile_count).is_equal(1)

func test_aimed_burst_fires_three_aimed_shots() -> void:
	var w := AimedBurstWeapon.new()
	w.burst_interval = 0.1
	var dirs: Array = []
	w.shot_sink = func(d): dirs.append(d)
	w.use(_shooter(Vector2.RIGHT))
	w.tick(0.1)
	w.tick(0.1)
	assert_int(dirs.size()).is_equal(3)
	for d in dirs:
		assert_float(d.angle()).is_equal_approx(0.0, 0.01)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ranged_pattern_weapons.gd 2>&1 | tail -40`
Expected: FAIL — `AimedBurstWeapon` not declared.

- [ ] **Step 3: Implement the class**

Create `src/weapons/aimed_burst_weapon.gd`:

```gdscript
class_name AimedBurstWeapon
extends RangedWeapon

# Default ranged pattern: a re-aiming 3-round burst. Standing still gets hit;
# moving out-runs the stream.
func _configure() -> void:
	burst_count = 3
	burst_interval = 0.12
	reaim_each_shot = true
	projectile_count = 1
	spread_angle = 0.0
	damage = 4.0
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ranged_pattern_weapons.gd 2>&1 | tail -40`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/aimed_burst_weapon.gd tests/unit/test_ranged_pattern_weapons.gd
git commit -m "feat: AimedBurstWeapon (default re-aiming 3-round burst)"
```

---

## Task 4: SplitShotWeapon (variant)

Two diverging bullets per shot, none down the center — a stationary, correctly-placed player sits in the gap. Reuses the base spread math (`projectile_count = 2`).

**Files:**
- Create: `src/weapons/split_shot_weapon.gd`
- Test: `tests/unit/test_ranged_pattern_weapons.gd` (extend)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_ranged_pattern_weapons.gd`:

```gdscript
func test_split_defaults() -> void:
	var w := SplitShotWeapon.new()
	assert_int(w.projectile_count).is_equal(2)
	assert_bool(w.reaim_each_shot).is_true()

func test_split_emits_two_diverging_with_gap() -> void:
	var w := SplitShotWeapon.new()
	w.spread_angle = 30.0
	var dirs: Array = []
	w.shot_sink = func(d): dirs.append(d)
	w.use(_shooter(Vector2.RIGHT))  # first shot only
	assert_int(dirs.size()).is_equal(2)
	assert_float(dirs[0].angle()).is_equal_approx(deg_to_rad(-15.0), 0.01)
	assert_float(dirs[1].angle()).is_equal_approx(deg_to_rad(15.0), 0.01)
	# No bullet travels straight down the facing axis (the safe gap).
	for d in dirs:
		assert_bool(abs(d.angle()) < 0.01).is_false()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ranged_pattern_weapons.gd 2>&1 | tail -40`
Expected: FAIL — `SplitShotWeapon` not declared.

- [ ] **Step 3: Implement the class**

Create `src/weapons/split_shot_weapon.gd`:

```gdscript
class_name SplitShotWeapon
extends RangedWeapon

# Two diverging bullets per shot with an empty center. Re-aim keeps the gap
# centered on a stationary player (safe); moving drags them across the bullets.
func _configure() -> void:
	burst_count = 2
	burst_interval = 0.18
	reaim_each_shot = true
	projectile_count = 2
	spread_angle = 30.0
	damage = 4.0
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ranged_pattern_weapons.gd 2>&1 | tail -40`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/split_shot_weapon.gd tests/unit/test_ranged_pattern_weapons.gd
git commit -m "feat: SplitShotWeapon (two diverging bullets, safe center gap)"
```

---

## Task 5: FanWeapon (variant)

Center bullet + two spread shots — a wider wall the player must move through.

**Files:**
- Create: `src/weapons/fan_weapon.gd`
- Test: `tests/unit/test_ranged_pattern_weapons.gd` (extend)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_ranged_pattern_weapons.gd`:

```gdscript
func test_fan_emits_center_plus_two_spread() -> void:
	var w := FanWeapon.new()
	w.spread_angle = 40.0
	var dirs: Array = []
	w.shot_sink = func(d): dirs.append(d)
	w.use(_shooter(Vector2.RIGHT))  # first volley
	assert_int(dirs.size()).is_equal(3)
	assert_float(dirs[0].angle()).is_equal_approx(deg_to_rad(-20.0), 0.01)
	assert_float(dirs[1].angle()).is_equal_approx(0.0, 0.01)
	assert_float(dirs[2].angle()).is_equal_approx(deg_to_rad(20.0), 0.01)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ranged_pattern_weapons.gd 2>&1 | tail -40`
Expected: FAIL — `FanWeapon` not declared.

- [ ] **Step 3: Implement the class**

Create `src/weapons/fan_weapon.gd`:

```gdscript
class_name FanWeapon
extends RangedWeapon

# Center bullet plus two spread shots: a wider wall to route around.
func _configure() -> void:
	burst_count = 1
	burst_interval = 0.12
	reaim_each_shot = false
	projectile_count = 3
	spread_angle = 40.0
	damage = 4.0
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ranged_pattern_weapons.gd 2>&1 | tail -40`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/fan_weapon.gd tests/unit/test_ranged_pattern_weapons.gd
git commit -m "feat: FanWeapon (center + two spread shots)"
```

---

## Task 6: Enemy sustained-ATTACK hook

Let the ATTACK state persist while the weapon is mid-burst, without changing melee or single-shot behavior.

**Files:**
- Modify: `src/enemies/enemy.gd` (`_process_attack` ~319-321, `_change_state` match ~421-430, add hook + var)
- Modify: `src/enemies/ranged_enemy.gd` (override hook)
- Test: `tests/unit/test_enemy_burst_attack.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_enemy_burst_attack.gd`:

```gdscript
extends GdUnitTestSuite

# Mock burst weapon: controllable is_bursting, no real projectile spawn.
class _MockBurstWeapon extends RangedWeapon:
	var bursting: bool = false
	func is_bursting() -> bool:
		return bursting
	func _use_impl(_user: Node) -> void:
		pass

func test_melee_attack_not_in_progress() -> void:
	var m: MeleeEnemy = auto_free(MeleeEnemy.new())
	add_child(m)
	assert_bool(m._attack_in_progress()).is_false()

func test_ranged_attack_in_progress_tracks_weapon_burst() -> void:
	var e: RangedEnemy = auto_free(RangedEnemy.new())
	add_child(e)
	var w := _MockBurstWeapon.new()
	e.weapon = w
	w.bursting = true
	assert_bool(e._attack_in_progress()).is_true()
	w.bursting = false
	assert_bool(e._attack_in_progress()).is_false()

func test_attack_state_holds_until_burst_done() -> void:
	var e: RangedEnemy = auto_free(RangedEnemy.new())
	add_child(e)
	var w := _MockBurstWeapon.new()
	e.weapon = w
	w.bursting = true
	e._change_state(Enemy.State.ATTACK)
	e._process_attack(0.0)
	assert_int(e._state).is_equal(Enemy.State.ATTACK)
	w.bursting = false
	e._process_attack(0.0)
	assert_int(e._state).is_equal(Enemy.State.COOLDOWN)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_burst_attack.gd 2>&1 | tail -40`
Expected: FAIL — `_attack_in_progress` not defined.

- [ ] **Step 3: Implement the hook and sustained ATTACK**

In `src/enemies/enemy.gd`, add an instance var near the other state vars (next to `_holds_attack_token`, line 68):

```gdscript
var _attack_started: bool = false
```

Replace `_process_attack` (lines 319-321):

```gdscript
func _process_attack(_delta: float) -> void:
	if not _attack_started:
		_attack_started = true
		_execute_attack()
	if not _attack_in_progress():
		_change_state(State.COOLDOWN)
```

Add the default hook next to `_execute_attack` (line 458):

```gdscript
# Override: return true while a multi-shot attack (burst) is still firing, so the
# ATTACK state holds instead of dropping to COOLDOWN after one frame.
func _attack_in_progress() -> bool:
	return false
```

In `_change_state`, add an ATTACK case to the `match new_state` block (before the `State.COOLDOWN:` case at line 426):

```gdscript
		State.ATTACK:
			_attack_started = false
```

In `src/enemies/ranged_enemy.gd`, add the override (after `_uses_ranged_token`, line 15):

```gdscript
func _attack_in_progress() -> bool:
	return weapon != null and weapon.is_bursting()
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_burst_attack.gd 2>&1 | tail -40`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the enemy state-machine suite to confirm no regression**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_state_machine.gd 2>&1 | tail -40`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/enemies/enemy.gd src/enemies/ranged_enemy.gd tests/unit/test_enemy_burst_attack.gd
git commit -m "feat: ATTACK state holds while weapon is mid-burst"
```

---

## Task 7: Projectile terrain-behavior consult + penetration behavior

Enemy projectiles currently always carve-and-free on terrain. Let them consult `behaviors` first (mirroring the player path), then add a penetration behavior the sniper round will use.

**Files:**
- Modify: `src/weapons/projectile.gd` (enemy-projectile terrain branch, lines 64-66)
- Create: `src/weapons/sniper_penetration_behavior.gd`
- Test: `tests/unit/test_sniper_penetration.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_sniper_penetration.gd`:

```gdscript
extends GdUnitTestSuite

const SniperPenetration = preload("res://src/weapons/sniper_penetration_behavior.gd")

func test_penetration_keeps_alive_while_budget_remains() -> void:
	var b = SniperPenetration.new()
	b.pierces = 2
	var proj: Projectile = auto_free(Projectile.new())
	# First two terrain hits: keep alive. Third: stop.
	assert_bool(b.on_terrain_hit(proj)).is_true()
	assert_bool(b.on_terrain_hit(proj)).is_true()
	assert_bool(b.on_terrain_hit(proj)).is_false()

func test_enemy_projectile_with_keep_behavior_survives_terrain() -> void:
	var b = SniperPenetration.new()
	b.pierces = 1
	var proj: Projectile = auto_free(Projectile.new())
	proj.is_enemy_projectile = true
	proj.behaviors = [b]
	proj.solidity_oracle = func(_p): return false  # _carve_terrain path tolerated
	add_child(proj)
	var wall := auto_free(StaticBody2D.new())
	add_child(wall)
	proj._handle_hit(wall)
	assert_bool(is_instance_valid(proj)).is_true()  # not freed: penetrated
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_sniper_penetration.gd 2>&1 | tail -40`
Expected: FAIL — `sniper_penetration_behavior.gd` does not exist / enemy branch still frees.

- [ ] **Step 3: Implement the behavior and the projectile change**

Create `src/weapons/sniper_penetration_behavior.gd`:

```gdscript
class_name SniperPenetrationBehavior
extends ProjectileBehavior

# Heavy sniper round bores through a budget of terrain hits, carving a channel,
# before finally stopping. Returns true (keep alive) while budget remains.
@export var pierces: int = 2

func on_terrain_hit(proj) -> bool:
	if pierces <= 0:
		return false
	pierces -= 1
	if proj != null and proj.has_method("_carve_terrain"):
		proj._carve_terrain()
	return true
```

In `src/weapons/projectile.gd`, replace the enemy-projectile terrain branch (lines 64-66):

```gdscript
		elif target is StaticBody2D:
			_carve_terrain()
			queue_free()
		return
```

with a behavior-consulting version:

```gdscript
		elif target is StaticBody2D:
			var keep := false
			for b in behaviors:
				keep = b.on_terrain_hit(self) or keep
			if keep:
				return
			_carve_terrain()
			queue_free()
		return
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_sniper_penetration.gd 2>&1 | tail -40`
Expected: PASS (2 tests).

- [ ] **Step 5: Run the projectile suites to confirm no regression**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_projectile.gd 2>&1 | tail -40`
Then: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_projectile_behaviors.gd 2>&1 | tail -40`
Expected: PASS for both.

- [ ] **Step 6: Commit**

```bash
git add src/weapons/projectile.gd src/weapons/sniper_penetration_behavior.gd tests/unit/test_sniper_penetration.gd
git commit -m "feat: enemy projectiles consult behaviors on terrain + sniper penetration"
```

---

## Task 8: SniperWeapon

A single heavy round that attaches the penetration behavior to each projectile it spawns.

**Files:**
- Modify: `src/weapons/ranged_weapon.gd` (add `_make_behaviors` hook + use it in `_spawn_projectile`)
- Create: `src/weapons/sniper_weapon.gd`
- Test: `tests/unit/test_ranged_pattern_weapons.gd` (extend)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_ranged_pattern_weapons.gd`:

```gdscript
func test_sniper_defaults() -> void:
	var w := SniperWeapon.new()
	assert_int(w.burst_count).is_equal(1)
	assert_float(w.damage).is_greater(15.0)
	assert_float(w.cooldown).is_greater(2.0)

func test_sniper_makes_penetration_behavior() -> void:
	var w := SniperWeapon.new()
	var behaviors: Array = w._make_behaviors()
	assert_int(behaviors.size()).is_equal(1)
	assert_bool(behaviors[0] is SniperPenetrationBehavior).is_true()

func test_sniper_fires_one_shot() -> void:
	var w := SniperWeapon.new()
	var dirs: Array = []
	w.shot_sink = func(d): dirs.append(d)
	w.use(_shooter(Vector2.RIGHT))
	assert_int(dirs.size()).is_equal(1)
	assert_bool(w.is_bursting()).is_false()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ranged_pattern_weapons.gd 2>&1 | tail -40`
Expected: FAIL — `SniperWeapon` / `_make_behaviors` not defined.

- [ ] **Step 3: Add the behaviors hook and the class**

In `src/weapons/ranged_weapon.gd`, add the hook (next to `_configure`):

```gdscript
# Override point: behaviors to attach to each spawned projectile.
func _make_behaviors() -> Array:
	return []
```

In `_spawn_projectile`, set the projectile's behaviors right after the projectile is instantiated (after `var proj := PROJECTILE_SCENE.instantiate()` / before it is added to the tree):

```gdscript
	proj.behaviors = _make_behaviors()
```

Create `src/weapons/sniper_weapon.gd`:

```gdscript
class_name SniperWeapon
extends RangedWeapon

# Single heavy, slow-firing round that penetrates and destroys cover. Telegraphed
# by SniperEnemy's locking aim-line.
func _configure() -> void:
	burst_count = 1
	reaim_each_shot = false
	projectile_count = 1
	spread_angle = 0.0
	damage = 20.0
	cooldown = 2.5
	projectile_speed = 260.0


func _make_behaviors() -> Array:
	var pen := SniperPenetrationBehavior.new()
	pen.pierces = 2
	return [pen]
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ranged_pattern_weapons.gd 2>&1 | tail -40`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/ranged_weapon.gd src/weapons/sniper_weapon.gd tests/unit/test_ranged_pattern_weapons.gd
git commit -m "feat: SniperWeapon (heavy penetrating round) + _make_behaviors hook"
```

---

## Task 9: SniperEnemy with locking aim-line telegraph

A `RangedEnemy` (movement unchanged) whose aim direction locks during the final windup window, so a player who moves after the lock is not tracked.

**Files:**
- Create: `src/enemies/sniper_enemy.gd`
- Create: `scenes/enemies/sniper_enemy.tscn`
- Test: `tests/unit/test_sniper_enemy.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_sniper_enemy.gd`:

```gdscript
extends GdUnitTestSuite

func _player_at(pos: Vector2) -> Node2D:
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = pos
	return p

func test_facing_tracks_player_before_lock() -> void:
	var s: SniperEnemy = auto_free(SniperEnemy.new())
	add_child(s)
	s.global_position = Vector2.ZERO
	s._player_ref = _player_at(Vector2(100, 0))
	# Not locked yet: facing points at the player (to the right).
	assert_float(s.get_facing_direction().angle()).is_equal_approx(0.0, 0.01)

func test_facing_returns_locked_direction_after_lock() -> void:
	var s: SniperEnemy = auto_free(SniperEnemy.new())
	add_child(s)
	s.global_position = Vector2.ZERO
	s._player_ref = _player_at(Vector2(100, 0))
	s._lock_aim()  # captures current direction (right)
	# Player moves up; facing must stay locked to the right.
	s._player_ref.global_position = Vector2(0, 100)
	assert_bool(s._aim_locked).is_true()
	assert_float(s.get_facing_direction().angle()).is_equal_approx(0.0, 0.01)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_sniper_enemy.gd 2>&1 | tail -40`
Expected: FAIL — `SniperEnemy` not declared.

- [ ] **Step 3: Implement the SniperEnemy**

Create `src/enemies/sniper_enemy.gd`:

```gdscript
class_name SniperEnemy
extends RangedEnemy

@export var lock_time: float = 0.3  # final windup window where aim freezes

var _aim_locked: bool = false
var _lock_dir: Vector2 = Vector2.DOWN
var _aim_line: Line2D = null


func _ready() -> void:
	if weapon_resource == null:
		weapon_resource = SniperWeapon.new()
	super._ready()
	windup_duration = 1.2
	cooldown_duration = weapon.cooldown if weapon else 2.5
	_aim_line = Line2D.new()
	_aim_line.width = 1.5
	_aim_line.default_color = Color(1.0, 0.7, 0.2, 0.5)
	_aim_line.visible = false
	add_child(_aim_line)


# During WINDUP, track the player until lock_time remains, then freeze the aim.
func _process_windup(delta: float) -> void:
	if not _aim_locked and _state_timer <= lock_time:
		_lock_aim()
	_update_aim_line()
	super._process_windup(delta)


func _lock_aim() -> void:
	_lock_dir = _to_player_dir()
	_aim_locked = true
	if _aim_line:
		_aim_line.default_color = Color(1.0, 0.2, 0.2, 0.9)


func _update_aim_line() -> void:
	if _aim_line == null:
		return
	var dir := _lock_dir if _aim_locked else _to_player_dir()
	_aim_line.visible = true
	_aim_line.points = PackedVector2Array([Vector2.ZERO, dir * 600.0])


func _to_player_dir() -> Vector2:
	if _player_ref and is_instance_valid(_player_ref):
		var d := _player_ref.global_position - global_position
		if d.length() > 0.01:
			return d.normalized()
	return Vector2.DOWN


# Fire down the locked direction, not live facing.
func get_facing_direction() -> Vector2:
	if _aim_locked:
		return _lock_dir
	return _to_player_dir()


# Reset the telegraph each time the attack resolves / aborts.
func _change_state(new_state: int) -> void:
	if new_state != State.WINDUP and new_state != State.ATTACK:
		_aim_locked = false
		if _aim_line:
			_aim_line.visible = false
			_aim_line.default_color = Color(1.0, 0.7, 0.2, 0.5)
	super._change_state(new_state)
```

Create `scenes/enemies/sniper_enemy.tscn` (mirrors `ranged_enemy.tscn`; reuses the ranged enemy texture):

```
[gd_scene format=3 uid="uid://sniperenemy01"]

[ext_resource type="PackedScene" uid="uid://enemybase01" path="res://scenes/enemies/enemy.tscn" id="1"]
[ext_resource type="Script" path="res://src/enemies/sniper_enemy.gd" id="2"]
[ext_resource type="Texture2D" uid="uid://jf368i2hd33h" path="res://textures/Enemies/ranged_test.png" id="3"]

[node name="SniperEnemy" instance=ExtResource("1")]
script = ExtResource("2")
preferred_distance = 160.0

[node name="Sprite2D" parent="." index="0"]
texture = ExtResource("3")
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_sniper_enemy.gd 2>&1 | tail -40`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/enemies/sniper_enemy.gd scenes/enemies/sniper_enemy.tscn tests/unit/test_sniper_enemy.gd
git commit -m "feat: SniperEnemy with locking aim-line telegraph"
```

---

## Task 10: Spawn wiring

Make plain ranged enemies fire the aimed burst, mix in split/fan, and add a rare sniper spawn.

**Files:**
- Modify: `src/core/spawn_dispatcher.gd` (`_pick_ranged_weapon` ~248-251, ranged branch ~212-213, add sniper scene const + branch)
- Test: `tests/unit/test_ranged_pattern_spawn.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_ranged_pattern_spawn.gd`:

```gdscript
extends GdUnitTestSuite

const SpawnDispatcher = preload("res://src/core/spawn_dispatcher.gd")

func test_pick_ranged_weapon_returns_a_pattern_weapon() -> void:
	var d = SpawnDispatcher.new()
	# Sample enough draws to see the distribution covers the pattern classes.
	var seen_aimed := false
	for i in range(200):
		var w = d._pick_ranged_weapon()
		assert_bool(w is RangedWeapon).is_true()
		if w is AimedBurstWeapon:
			seen_aimed = true
	assert_bool(seen_aimed).is_true()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ranged_pattern_spawn.gd 2>&1 | tail -40`
Expected: FAIL — `_pick_ranged_weapon` still returns registry weapons (`throwing_knife`/`fire_orb`), never an `AimedBurstWeapon`.

- [ ] **Step 3: Wire the spawner**

In `src/core/spawn_dispatcher.gd`, add a sniper scene const near the other scene preloads (next to `RANGED_ENEMY_SCENE`, line 4):

```gdscript
const SNIPER_ENEMY_SCENE := preload("res://scenes/enemies/sniper_enemy.tscn")
```

Replace `_pick_ranged_weapon` (lines 248-251) with the pattern distribution (aimed-burst is the common case):

```gdscript
func _pick_ranged_weapon() -> Weapon:
	var roll := randf()
	if roll < 0.6:
		return AimedBurstWeapon.new()
	elif roll < 0.8:
		return SplitShotWeapon.new()
	return FanWeapon.new()
```

In `_spawn_enemy`, replace the ranged `else` branch (lines 211-213) so a fraction of ranged spawns become snipers:

```gdscript
				elif randf() < 0.15:
					enemy = SNIPER_ENEMY_SCENE.instantiate()
				else:
					enemy = RANGED_ENEMY_SCENE.instantiate()
					enemy.weapon_resource = _pick_ranged_weapon()
```

> The sniper sets its own `SniperWeapon` in `SniperEnemy._ready`, so no `weapon_resource` assignment is needed for that branch.

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ranged_pattern_spawn.gd 2>&1 | tail -40`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/spawn_dispatcher.gd tests/unit/test_ranged_pattern_spawn.gd
git commit -m "feat: spawn aimed/split/fan ranged patterns + rare sniper"
```

---

## Task 11: Full suite + manual playtest

- [ ] **Step 1: Run the full unit suite**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit 2>&1 | tail -60`
Expected: PASS — 0 failures, 0 errors across the suite. Fix any regression before proceeding.

- [ ] **Step 2: Manual playtest (run the project)**

Launch the game and verify, against a ranged crowd:

- Standing still vs an aimed-burst enemy gets you hit; moving out-runs the stream.
- Standing in the gap of a split-shot enemy is safe; moving sweeps you across both bullets.
- A fan enemy forces a sidestep through a gap.
- The sniper's aim-line tracks, then visibly **freezes red** ~0.3s before firing; the round hurts and visibly destroys cover.
- With several ranged enemies, only ~2 volleys are ever in flight at once (SP1 token cap still holds).
- A player who picks up one of these ranged weapons fires its pattern correctly.

- [ ] **Step 3: Commit any tuning changes**

```bash
git add -A
git commit -m "chore: SP2 ranged/sniper tuning from playtest"
```

---

## Self-Review

**Spec coverage:**
- Burst attack support → Tasks 1–2 (timeline on `RangedWeapon`, advanced by existing `tick`).
- Aimed 3-round burst (default) → Task 3 + Task 10 distribution (60% aimed).
- Split-shot variant → Task 4.
- Fan variant → Task 5.
- Sniper variant (low fire rate, long telegraph that locks, high damage, terrain destruction) → Tasks 7 (penetration), 8 (`SniperWeapon`), 9 (`SniperEnemy` aim-line lock).
- Sustained ATTACK / token held across burst → Task 6 (token behavior is SP1, unchanged; the burst only lengthens ATTACK).
- Re-aim mechanic → Task 2 tests (`reaim_each_shot`), exercised by aimed/split.
- Player-compatible (weapon-driven) → covered implicitly (player ticks weapons at `weapon_manager.gd:113`); verified in Task 11 manual checklist.
- Testing section (burst count/cadence, re-aim, geometry, sniper lock, enemy sustain regression) → Tasks 1–9 tests.

**Placeholder scan:** No TBD/TODO; every code step shows full code.

**Type consistency:** `_emit_shot(user, base_dir)`, `_configure()`, `_make_behaviors() -> Array`, `is_bursting() -> bool`, `_attack_in_progress() -> bool`, `_aim_locked` / `_lock_dir` / `_lock_aim()`, `SniperPenetrationBehavior.pierces`, `shot_sink` — names match across all tasks and tests.

**Known v1 simplifications (intended, flagged for tuning in Task 11):** sniper penetration is a fixed `pierces` budget (runtime feel of boring through a single large terrain body is a playtest dial); split/fan reuse the base spread math rather than bespoke emission; all damage/interval/cooldown numbers are starting points per the spec.
