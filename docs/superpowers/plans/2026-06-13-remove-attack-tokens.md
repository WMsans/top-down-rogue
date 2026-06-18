# Remove Attack Tokens — Infinite Enemy Aggression

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the attack token mechanic entirely so all enemies always pursue and attack freely, with no concurrency gating.

**Architecture:** Strip token/aggression/slot system from EncounterDirector, remove token-claim branching and orbit behavior from Enemy and RangedEnemy chase logic, clean up WorldManager wiring, and delete/update tests. Enemies will now enter WINDUP immediately when in attack range — no settle timer, no token claim, no surround slots.

**Tech Stack:** GDScript, Godot 4.x, gdUnit4 test framework

---

### Task 1: Simplify EncounterDirector

**Files:**
- Modify: `src/core/encounter_director.gd`
- Delete: `tests/unit/test_encounter_director.gd`

- [ ] **Step 1: Remove token/aggression/slot code from EncounterDirector**

Replace the entire file content of `src/core/encounter_director.gd` with:

```gdscript
class_name EncounterDirector
extends RefCounted

const HORDE_SOFT_CAP := 14
const CONTAGION_RADIUS := 48.0
const SPEED_CAP_FRACTION := 0.95
const TETHER_DISTANCE := 80.0
const RAMP_BAND := 120.0

var _active: Array = []


func is_active(enemy) -> bool:
	return _active.has(enemy)


static func catch_up_speed(base_speed: float, dist_to_player: float, player_speed: float) -> float:
	var cap := player_speed * SPEED_CAP_FRACTION
	if dist_to_player <= TETHER_DISTANCE:
		return minf(base_speed, cap)
	var t := clampf((dist_to_player - TETHER_DISTANCE) / RAMP_BAND, 0.0, 1.0)
	var target := maxf(base_speed, cap)
	return minf(lerpf(base_speed, target, t), cap)


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


func update(player_pos: Vector2, attackable: Array) -> void:
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


func unregister(enemy) -> void:
	_active.erase(enemy)
```

- [ ] **Step 2: Delete the EncounterDirector test file**

Delete `tests/unit/test_encounter_director.gd`.

- [ ] **Step 3: Run EncounterDirector-related tests to verify nothing broke**

The test file is deleted, so just confirm the project parses:

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_state_machine.gd
```

Expected: Tests that don't reference EncounterDirector token methods should pass. Some tests in `test_enemy_state_machine.gd` may fail due to removed methods — that's expected and will be fixed in Task 2.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "refactor: remove token/aggression/slot system from EncounterDirector"
```

---

### Task 2: Simplify Enemy chase behavior

**Files:**
- Modify: `src/enemies/enemy.gd`

- [ ] **Step 1: Remove token-related fields, methods, and constants**

In `src/enemies/enemy.gd`, apply the following edits:

**Remove `@export var surround_offset` (line 21):**

```gdscript
# REMOVE this line:
@export var surround_offset: float = 56.0
```

**Remove `@export var min_attack_settle_time` (line 22):**

```gdscript
# REMOVE this line:
@export var min_attack_settle_time: float = 0.5
```

**Remove `RING_STRAFE_MULT` constant (line 40):**

```gdscript
# REMOVE this line:
const RING_STRAFE_MULT: float = 0.4
```

**Remove `_settle_timer` variable (line 54):**

```gdscript
# REMOVE this line:
var _settle_timer: float = 0.0
```

**Remove `_holds_attack_token` variable (line 69):**

```gdscript
# REMOVE this line:
var _holds_attack_token: bool = false
```

**Remove `_orbit_sign` and `_orbit_flip_timer` variables (lines 75-76):**

```gdscript
# REMOVE these lines:
var _orbit_sign: float = 1.0
var _orbit_flip_timer: float = 0.0
```

- [ ] **Step 2: Remove `_ready` references to orbit variables**

In `_ready()`, remove the lines that initialize orbit:

```gdscript
# REMOVE these two lines from _ready():
_orbit_sign = 1.0 if randf() < 0.5 else -1.0
_orbit_flip_timer = randf_range(1.5, 3.0)
```

- [ ] **Step 3: Remove settle_timer accumulation in `_process`**

In the `_process` method, remove the settle timer block (lines 179-182):

```gdscript
# REMOVE these lines from _process:
if _player_in_range:
	_settle_timer += delta
else:
	_settle_timer = 0.0
```

- [ ] **Step 4: Rewrite `_process_chase` to remove token logic and orbit**

Replace the entire `_process_chase` method body with:

```gdscript
func _process_chase(_delta: float) -> void:
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
		_change_state(State.WANDER)
		return

	if dist < 1.0:
		velocity = Vector2.ZERO
		return

	if sees and dist <= _attack_range:
		velocity = Vector2.ZERO
		_change_state(State.WINDUP)
		return

	var move_dir: Vector2
	if sees:
		move_dir = to_player.normalized()
	else:
		var fd := _nav_field_dir()
		move_dir = fd if fd != Vector2.ZERO else to_player.normalized()

	move_dir = _apply_separation(move_dir)
	velocity = move_dir * _get_effective_speed()
```

- [ ] **Step 5: Remove `_change_state` token release**

In `_change_state`, remove the token release lines (lines 437-438):

```gdscript
# REMOVE these lines from _change_state:
if new_state != State.WINDUP and new_state != State.ATTACK and new_state != State.COOLDOWN:
	_release_attack()
```

And remove the settle timer reset in the WINDUP branch:

```gdscript
# In the State.WINDUP branch, REMOVE this line:
_settle_timer = 0.0
```

- [ ] **Step 6: Remove `register_kill` from `die()`**

In `die()`, remove the `register_kill` call (line 575):

```gdscript
# REMOVE this line from die():
dir.register_kill()
```

The method should just be:

```gdscript
func die() -> void:
	var dir = _get_director()
	if dir != null:
		dir.unregister(self)
	died.emit()
	_on_death()
```

- [ ] **Step 7: Remove token, surround, and strafe methods**

Remove these methods entirely from `enemy.gd`:

```gdscript
# REMOVE _uses_ranged_token():
func _uses_ranged_token() -> bool:
	return false

# REMOVE _try_claim_attack():
func _try_claim_attack() -> bool:
	var dir = _get_director()
	if dir == null:
		return true
	if dir.try_claim_attack(self, _uses_ranged_token()):
		_holds_attack_token = true
		return true
	return false

# REMOVE _release_attack():
func _release_attack() -> void:
	if not _holds_attack_token:
		return
	_holds_attack_token = false
	var dir = _get_director()
	if dir != null:
		dir.release_attack(self)

# REMOVE _surround_dir():
func _surround_dir(preferred_radius: float) -> Vector2:
	...

# REMOVE _ring_strafe_dir():
func _ring_strafe_dir() -> Vector2:
	...
```

- [ ] **Step 8: Verify the resulting file compiles**

```bash
godot --headless --path . --import
```

Expected: No parse errors for `enemy.gd`.

- [ ] **Step 9: Commit**

```bash
git add -A && git commit -m "refactor: remove token claim, orbit, settle from Enemy chase behavior"
```

---

### Task 3: Simplify RangedEnemy pursuit

**Files:**
- Modify: `src/enemies/ranged_enemy.gd`

- [ ] **Step 1: Remove `_uses_ranged_token` override**

Remove the method (lines 14-15):

```gdscript
# REMOVE:
func _uses_ranged_token() -> bool:
	return true
```

- [ ] **Step 2: Rewrite `_process_chase` to remove token claim and surround**

Replace the entire `_process_chase` method in `ranged_enemy.gd` with:

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
		velocity = move_dir * _get_effective_speed()
	elif dist > preferred_distance + 20.0:
		move_dir = to_player.normalized()
		velocity = move_dir * _get_effective_speed()
	else:
		_strafe_re_roll -= delta
		if _strafe_re_roll <= 0.0:
			_strafe_direction = 1.0 if randf() > 0.5 else -1.0
			_strafe_re_roll = 1.5
		var perpendicular := Vector2(-to_player.y, to_player.x).normalized()
		velocity = perpendicular * _strafe_direction * strafe_speed

	velocity = _apply_separation(velocity)

	if dist <= _attack_range:
		_change_state(State.WINDUP)
		return
```

Key changes: Removed `_settle_timer >= min_attack_settle_time` check, removed `_try_claim_attack()` call, removed `_holds_attack_token` check and fallback `_surround_dir` block. Attack now triggers purely on `dist <= _attack_range`.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "refactor: remove token claim and surround from RangedEnemy pursuit"
```

---

### Task 4: Clean up WorldManager

**Files:**
- Modify: `src/core/world_manager.gd`

- [ ] **Step 1: Remove `_player_hit_connected` variable**

Remove line 29:

```gdscript
# REMOVE:
var _player_hit_connected: bool = false
```

- [ ] **Step 2: Remove damage signal connection and token assignment in `_process`**

In the `_process` method, remove the signal-wiring block (lines 105-111) and the token count assignments (lines 113-114). The relevant portion should change from:

```gdscript
var attackable := get_tree().get_nodes_in_group("attackable")
if not _player_hit_connected:
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		var inv = player.get_node_or_null("PlayerInventory")
		if inv != null:
			inv.damaged.connect(encounter_director.register_player_hit.unbind(1))
			_player_hit_connected = true
swarm_grid.rebuild(attackable)
encounter_director.melee_token_count = EncounterDirector.tokens_for_floor(2, LevelManager.floor_number)
encounter_director.ranged_token_count = EncounterDirector.tokens_for_floor(2, LevelManager.floor_number)
encounter_director.update(tracking_position, attackable)
```

to:

```gdscript
var attackable := get_tree().get_nodes_in_group("attackable")
swarm_grid.rebuild(attackable)
encounter_director.update(tracking_position, attackable)
```

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "refactor: remove token assignment and damage signal from WorldManager"
```

---

### Task 5: Clean up tests

**Files:**
- Delete: `tests/unit/test_enemy_pursuit.gd`
- Delete: `tests/unit/test_ranged_enemy_surround.gd`
- Modify: `tests/unit/test_enemy_state_machine.gd`
- Modify: `tests/unit/test_enemy_aggression.gd`

- [ ] **Step 1: Delete pursuit and ranged surround test files**

```bash
rm tests/unit/test_enemy_pursuit.gd tests/unit/test_ranged_enemy_surround.gd
```

- [ ] **Step 2: Remove token-related tests from `test_enemy_state_machine.gd`**

In `test_enemy_state_machine.gd`, remove these tests entirely:

- `test_chase_attacks_when_token_available` (lines 279-295)
- `test_chase_holds_when_no_token` (lines 297-318)
- `test_change_state_releases_token_on_return_to_chase` (lines 328-341)
- `test_die_unregisters_from_director` (lines 218-226) — this test creates a `_Director` and calls `try_claim_attack`, which no longer exists

Also remove the `_Director` constant at line 199:

```gdscript
# REMOVE:
const _Director = preload("res://src/core/encounter_director.gd")
```

Keep all other tests (wander, chase, speed, separation, contagion, etc.).

- [ ] **Step 3: Remove token-related tests from `test_enemy_aggression.gd`**

The file `test_enemy_aggression.gd` does not have token-specific tests — it only tests targeted/passive speed and cooldown multipliers. No changes needed. Verify by reading the file.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "test: remove token-related tests, keep aggression speed tests"
```

---

### Task 6: Verify all tests pass

- [ ] **Step 1: Run all unit tests**

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/
```

Expected: All remaining tests pass. No parse errors.

- [ ] **Step 2: Final commit if any fixes were needed**

```bash
git add -A && git commit -m "fix: test fixes after token removal"
```