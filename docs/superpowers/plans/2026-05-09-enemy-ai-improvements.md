# Enemy AI Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix speed=0 bug, add wander behavior, exclamation-mark telegraph, and velocity-based keep-away for ranged enemies.

**Architecture:** All changes confined to `enemy.gd`, `melee_enemy.gd`, `ranged_enemy.gd`. IDLE state renamed to WANDER with random-direction + pause cycle. WINDUP state gains a `"!"` Label popup. RangedEnemy keep-away refactored from direct `global_position` manipulation to `velocity`.

**Tech Stack:** Godot 4.6, GDScript, GdUnit4 test framework

---

### Task 1: Fix speed in MeleeEnemy

**Files:**
- Modify: `src/enemies/melee_enemy.gd:8-8`

- [ ] **Step 1: Add speed init in weapon_resource branch**

In `melee_enemy.gd`, inside the `if weapon_resource:` block in `_ready()`, add `speed = 60.0` before `super._ready()`:

```gdscript
func _ready() -> void:
	if weapon_resource:
		weapon = weapon_resource.duplicate()
		_attack_range = weapon.weapon_reach
		cooldown_duration = weapon_resource.cooldown
		speed = 60.0
	else:
		weapon = MeleeWeapon.new()
		_attack_range = 28.0
		speed = 60.0
		max_health = 15
		_speed_base = speed
		cooldown_duration = weapon.cooldown
	super._ready()
	_setup_drop_table()
```

- [ ] **Step 2: Commit**

```bash
git add src/enemies/melee_enemy.gd
git commit -m "fix: set default speed in MeleeEnemy when weapon_resource is assigned"
```

---

### Task 2: Fix speed in RangedEnemy

**Files:**
- Modify: `src/enemies/ranged_enemy.gd:15-18`

- [ ] **Step 1: Add speed init in weapon_resource branch**

In `ranged_enemy.gd`, inside the `if weapon_resource:` block in `_ready()`, add `speed = 50.0` before `super._ready()`:

```gdscript
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
		max_health = 12
		_speed_base = speed
		cooldown_duration = weapon.cooldown
	detection_radius = 250.0
	windup_duration = 0.4
	min_attack_settle_time = 0.5
	super._ready()
	_setup_drop_table()
```

- [ ] **Step 2: Commit**

```bash
git add src/enemies/ranged_enemy.gd
git commit -m "fix: set default speed in RangedEnemy when weapon_resource is assigned"
```

---

### Task 3: Change default speed in base Enemy

**Files:**
- Modify: `src/enemies/enemy.gd:11`

- [ ] **Step 1: Change default speed export**

Change line 11 in `enemy.gd`:

```gdscript
# Before:
@export var speed: float = 0.0
# After:
@export var speed: float = 50.0
```

- [ ] **Step 2: Commit**

```bash
git add src/enemies/enemy.gd
git commit -m "fix: set non-zero default speed in base Enemy class"
```

---

### Task 4: Rename IDLE → WANDER in base Enemy

**Files:**
- Modify: `src/enemies/enemy.gd:7,39,42,127-128,178,181,184,204,222,296`

- [ ] **Step 1: Rename enum and state defaults**

Change the State enum:

```gdscript
# Before:
enum State { IDLE, CHASE, WINDUP, ATTACK, COOLDOWN, HURT, DEATH }
# After:
enum State { WANDER, CHASE, WINDUP, ATTACK, COOLDOWN, HURT, DEATH }
```

Change the default state:

```gdscript
# Before:
var _state: int = State.IDLE
var _prev_state: int = State.IDLE
# After:
var _state: int = State.WANDER
var _prev_state: int = State.WANDER
```

- [ ] **Step 2: Update all IDLE references to WANDER**

Replace all remaining `State.IDLE` references in `enemy.gd` with `State.WANDER`:

In `_process()` (line ~128):
```gdscript
State.WANDER:
    _process_idle(delta)
```

In `_process_chase()` (lines ~178, 181, 184):
```gdscript
if _player_ref == null or not is_instance_valid(_player_ref):
    _change_state(State.WANDER)
    return
if not _player_in_range:
    _change_state(State.WANDER)
    return
if not _can_see_player():
    _change_state(State.WANDER)
    return
```

In `_process_windup()` (line ~204):
```gdscript
if not _can_see_player():
    _change_state(State.WANDER)
    return
```

In `_process_cooldown()` (line ~222):
```gdscript
if _player_ref and is_instance_valid(_player_ref) and _player_in_range:
    _change_state(State.CHASE)
else:
    _change_state(State.WANDER)
```

Also in `_process_idle()` (line ~173):
```gdscript
if _player_in_range:
    _change_state(State.CHASE)
```

- [ ] **Step 3: Commit**

```bash
git add src/enemies/enemy.gd
git commit -m "refactor: rename IDLE state to WANDER throughout base Enemy"
```

---

### Task 5: Add wander behavior logic

**Files:**
- Modify: `src/enemies/enemy.gd` — add wander members + rewrite `_process_idle()`

- [ ] **Step 1: Add wander member variables**

Add after the existing private members (after line ~50, before `func _ready()`):

```gdscript
var _wander_direction: Vector2 = Vector2.RIGHT
var _wander_timer: float = 0.0
var _wander_is_paused: bool = true
```

- [ ] **Step 2: Replace `_process_idle()` with wander logic**

Replace the entire `_process_idle` function:

```gdscript
func _process_idle(delta: float) -> void:
	if _player_ref and is_instance_valid(_player_ref) and _player_in_range:
		_change_state(State.CHASE)
		return

	_wander_timer -= delta
	if _wander_timer <= 0.0:
		if _wander_is_paused:
			_wander_is_paused = false
			_wander_direction = Vector2.RIGHT.rotated(randf() * TAU)
			_wander_timer = randf_range(1.0, 3.0)
		else:
			_wander_is_paused = true
			velocity = Vector2.ZERO
			_wander_timer = randf_range(0.5, 1.5)
			return

	if not _wander_is_paused:
		velocity = _wander_direction * speed * 0.5
```

- [ ] **Step 3: Commit**

```bash
git add src/enemies/enemy.gd
git commit -m "feat: add wander behavior to WANDER state with random-direction + pause cycle"
```

---

### Task 6: Update _physics_process for WANDER state

**Files:**
- Modify: `src/enemies/enemy.gd:148-148`

- [ ] **Step 1: Add WANDER to physics processing**

Change the `_physics_process` condition:

```gdscript
# Before:
func _physics_process(_delta: float) -> void:
	if _state == State.DEATH:
		return
	if _state == State.CHASE or _state == State.HURT:
		move_and_slide()
# After:
func _physics_process(_delta: float) -> void:
	if _state == State.DEATH:
		return
	if _state == State.WANDER or _state == State.CHASE or _state == State.HURT:
		move_and_slide()
```

- [ ] **Step 2: Commit**

```bash
git add src/enemies/enemy.gd
git commit -m "feat: call move_and_slide for WANDER state in physics process"
```

---

### Task 7: Add exclamation mark telegraph

**Files:**
- Modify: `src/enemies/enemy.gd` — add Label setup in `_ready()`, telegraph logic in `_process()` and `_change_state()`

- [ ] **Step 1: Add telegraph member variable**

Add after the wander members (before `func _ready()`):

```gdscript
var _exclaim_label: Label = null
var _exclaim_tween: Tween = null
```

- [ ] **Step 2: Create exclamation Label in `_ready()`**

Add at the end of `_ready()`, before `_setup_weapon_visual.call_deferred()`:

```gdscript
	_exclaim_label = Label.new()
	_exclaim_label.name = "ExclaimLabel"
	_exclaim_label.text = "!"
	_exclaim_label.position = Vector2(0, -16)
	_exclaim_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_exclaim_label.add_theme_font_size_override("font_size", 22)
	_exclaim_label.add_theme_color_override("font_color", Color.RED)
	_exclaim_label.scale = Vector2.ZERO
	add_child(_exclaim_label)
```

- [ ] **Step 3: Add exclamation popup on WINDUP enter**

In `_change_state()`, inside the `match new_state:` block, add WINDUP handling:

```gdscript
match new_state:
    State.WINDUP:
        _state_timer = windup_duration
        _settle_timer = 0.0
        _show_exclaim()
    State.COOLDOWN:
        _state_timer = cooldown_duration
    State.DEATH:
        _state_timer = death_duration
        _death_tween = null
```

Add the `_show_exclaim()` and `_hide_exclaim()` helper methods after `_change_state()`:

```gdscript
func _show_exclaim() -> void:
	if _exclaim_label == null:
		return
	if _exclaim_tween and _exclaim_tween.is_valid():
		_exclaim_tween.kill()
	_exclaim_label.scale = Vector2.ZERO
	_exclaim_tween = create_tween()
	_exclaim_tween.set_trans(Tween.TRANS_BACK)
	_exclaim_tween.set_ease(Tween.EASE_OUT)
	_exclaim_tween.tween_property(_exclaim_label, "scale", Vector2(1.2, 1.2), 0.05)
	_exclaim_tween.tween_property(_exclaim_label, "scale", Vector2.ONE, 0.05)
```

- [ ] **Step 4: Hide exclamation on WINDUP exit**

Hide the exclamation when WINDUP transitions to ATTACK or aborts to WANDER. In `_process_windup()`, add `_hide_exclaim()` on abort:

```gdscript
func _process_windup(delta: float) -> void:
	_state_timer -= delta
	if not _can_see_player():
		_hide_exclaim()
		_change_state(State.WANDER)
		return
	if _state_timer <= 0.0:
		_hide_exclaim()
		_change_state(State.ATTACK)
```

- [ ] **Step 5: Commit**

```bash
git add src/enemies/enemy.gd
git commit -m "feat: add '!' exclamation mark popup telegraph on WINDUP"
```

---

### Task 8: Fix RangedEnemy keep-away to use velocity

**Files:**
- Modify: `src/enemies/ranged_enemy.gd:37-68`

- [ ] **Step 1: Rewrite `_process_chase()` with velocity-based movement**

Replace the entire `_process_chase` function in `ranged_enemy.gd`:

```gdscript
func _process_chase(delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		_change_state(State.WANDER)
		return
	if not _player_in_range:
		_change_state(State.WANDER)
		return
	if not _can_see_player():
		_change_state(State.WANDER)
		return

	var to_player := _player_ref.global_position - global_position
	var dist := to_player.length()
	if dist < 1.0:
		velocity = Vector2.ZERO
		return

	var move_dir: Vector2

	if dist < preferred_distance - 20.0:
		move_dir = -to_player.normalized()
		velocity = move_dir * speed
	elif dist > preferred_distance + 20.0:
		move_dir = to_player.normalized()
		velocity = move_dir * speed
	else:
		_strafe_re_roll -= delta
		if _strafe_re_roll <= 0.0:
			_strafe_direction = 1.0 if randf() > 0.5 else -1.0
			_strafe_re_roll = 1.5
		var perpendicular := Vector2(-to_player.y, to_player.x).normalized()
		velocity = perpendicular * _strafe_direction * strafe_speed

	velocity = _apply_separation(velocity)

	if dist <= _attack_range and _settle_timer >= min_attack_settle_time:
		_change_state(State.WINDUP)
```

- [ ] **Step 2: Update IDLE references in RangedEnemy to WANDER**

The `_change_state(State.IDLE)` calls in the keep-away code above should already say `State.WANDER` from Task 4. But verify: the existing code on lines 39, 42, 45 of `ranged_enemy.gd` says `_change_state(State.IDLE)` — these will be changed to `_change_state(State.WANDER)` in the step above.

- [ ] **Step 3: Commit**

```bash
git add src/enemies/ranged_enemy.gd
git commit -m "fix: use velocity-based movement for RangedEnemy keep-away instead of direct position manipulation"
```

---

### Task 9: Update tests for renamed state + add new tests

**Files:**
- Modify: `tests/unit/test_enemy_state_machine.gd`

- [ ] **Step 1: Update all IDLE references to WANDER in tests**

Replace `State.IDLE` → `State.WANDER` throughout the test file:

Line 10: `assert_that(e._state).is_equal(Enemy.State.WANDER)`
Line 29: `assert_that(e._state).is_equal(Enemy.State.WANDER)`
Line 18: Set `e._player_in_range = true` should now transition to chase — this should still work as-is since wander checks for player_in_range.

- [ ] **Step 2: Add wander behavior test**

Add after the existing tests (before end of file):

```gdscript
func test_wander_enters_pause_after_move() -> void:
	var e := auto_free(MockEnemy.new())
	e._state = Enemy.State.WANDER
	e._wander_is_paused = false
	e._wander_timer = 0.01
	e._process(0.1)
	assert_that(e._wander_is_paused).is_true()
	assert_that(e.velocity).is_equal(Vector2.ZERO)

func test_wander_stays_wander_without_player() -> void:
	var e := auto_free(MockEnemy.new())
	e._state = Enemy.State.WANDER
	e._player_in_range = false
	e._player_ref = null
	e._process(0.1)
	assert_that(e._state).is_equal(Enemy.State.WANDER)

func test_exclaim_shown_on_windup() -> void:
	var e := auto_free(MockEnemy.new())
	e._state = Enemy.State.CHASE
	e._change_state(Enemy.State.WINDUP)
	await get_tree().process_frame
	if e._exclaim_label:
		assert_that(e._exclaim_label.scale).is_not_equal(Vector2.ZERO)

func test_exclaim_hidden_on_attack() -> void:
	var e := auto_free(MockEnemy.new())
	e._state = Enemy.State.WINDUP
	e._change_state(Enemy.State.ATTACK)
	await get_tree().process_frame
	if e._exclaim_label:
		assert_that(e._exclaim_label.scale).is_equal(Vector2.ZERO)
```

- [ ] **Step 3: Add MeleeEnemy speed test**

Create `tests/unit/test_melee_enemy.gd`:

```gdscript
extends GdUnitTestSuite


func test_melee_enemy_has_speed_with_weapon_resource() -> void:
	var e := MeleeEnemy.new()
	e.weapon_resource = MeleeWeapon.new()
	e.weapon_resource.weapon_reach = 32.0
	e.weapon_resource.cooldown = 0.5
	e._ready()
	assert_that(e.speed).is_greater(0.0)
```

- [ ] **Step 4: Run tests to verify old tests still pass with rename**

```bash
godot --headless --path /Users/jeremyzhao/Development/godot/top-down-rogue -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_state_machine.gd 2>&1 | tail -30
```

Expected: All tests pass (old tests adapted, new tests pass).

- [ ] **Step 5: Commit**

```bash
git add tests/unit/test_enemy_state_machine.gd tests/unit/test_melee_enemy.gd
git commit -m "test: update tests for WANDER rename, add wander/telegraph/speed tests"
```

---

### Task 10: Run full test suite

- [ ] **Step 1: Run all enemy-related tests**

```bash
godot --headless --path /Users/jeremyzhao/Development/godot/top-down-rogue -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_state_machine.gd tests/unit/test_melee_enemy.gd 2>&1 | tail -30
```

Expected: All tests pass.

- [ ] **Step 2: Run full test suite**

```bash
godot --headless --path /Users/jeremyzhao/Development/godot/top-down-rogue -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/ 2>&1 | tail -40
```

Expected: No regressions. Fix any failures before completing.

---

### Task 11: Verification — run the game

- [ ] **Step 1: Launch the game in editor and verify enemies**

1. Open project in Godot editor
2. Start a new game
3. Confirm enemies move (wander when idle, chase/keep-away when aggro'd)
4. Confirm `"!"` popup appears above enemies during windup
5. Confirm ranged enemies strafe and maintain distance properly
