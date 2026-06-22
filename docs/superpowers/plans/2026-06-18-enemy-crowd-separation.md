# Enemy Crowd Separation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make swarming enemies keep personal space so they read as a no-overlap crowd around the player instead of stacking into one point.

**Architecture:** Two changes in `src/enemies/enemy.gd`. (1) Strengthen the existing boids-style separation steering (`_apply_separation`) with a tunable weight and a larger radius so packed enemies steer around a pile instead of into it. (2) Add a depenetration safety net (`_resolve_crowd_overlap`) called every non-DEATH frame from `_physics_process`, which pushes overlapping bodies apart through the existing wall clamp — so even stationary enemies (winding up / attacking) spread out.

**Tech Stack:** Godot 4 / GDScript, gdUnit4 test framework. Existing `SwarmGrid` spatial hash (`src/core/swarm_grid.gd`) provides O(neighbors) lookups.

---

## Spec

`docs/superpowers/specs/2026-06-18-enemy-crowd-separation-design.md`

## Background for the implementer

- **Where enemies live:** `src/enemies/enemy.gd` (`class_name Enemy extends CharacterBody2D`). Subclasses like `MeleeEnemy` set stats but inherit all movement/steering.
- **Separation today:** `_apply_separation(move_dir)` queries the `SwarmGrid` 3×3 neighbourhood, sums a push away from neighbors within `separation_radius` (default 16px), and returns `(move_dir + sep * 0.5).normalized()`. The hardcoded `0.5` and small radius make the push too weak.
- **Movement today:** Enemies use `MOTION_MODE_FLOATING` and a custom `_move_with_clamp` / `_edge_blocked(step)` that clamps against solid nav cells. `_edge_blocked` takes a single-axis delta and returns true if moving the body's leading edge by it would enter a solid cell. Enemies do **not** physically collide with each other.
- **`_body_radius`:** each enemy's measured collision half-extent (default `DEFAULT_BODY_RADIUS = 8.0`; elites scale up). Plain `var`, default 8 when `_ready()` hasn't run (as in unit tests).
- **`SwarmGrid`:** `query_neighbors(pos)` returns all enemies in the 3×3 cell block (cell size 32px). Rebuilt once/frame by `WorldManager._process`.
- **Walls in tests:** `_edge_blocked` → `_is_blocked(pos)` → `_world_manager.get("nav_field")`; if `nav_field` is null it returns `false` (nothing solid). Tests can supply a fake nav_field to simulate a wall.

## Running tests

Single suite (gdUnit4, headless):

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_crowd.gd
```

If the worktree is fresh (no `.godot/` import cache), prepend the import step once:

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_crowd.gd
```

Regression suite for existing enemy behavior:

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_state_machine.gd
```

## File structure

- **Modify** `src/enemies/enemy.gd`:
  - New `@export var separation_weight: float`; raise default `separation_radius`.
  - Rewrite `_apply_separation` to use the weight.
  - New methods `_resolve_crowd_overlap()` and `_apply_crowd_push(offset)`; new `@export var crowd_spacing_scale` and a push-cap const.
  - One-line call in `_physics_process`.
- **Create** `tests/unit/test_enemy_crowd.gd`: gdUnit4 suite with local `MockEnemy`, `FakeWorld`, `FakeNavField` helpers.

---

## Task 1: Strengthen separation steering

**Files:**
- Modify: `src/enemies/enemy.gd` (`separation_radius` default at line ~20; `_apply_separation` at lines ~374-388)
- Test: `tests/unit/test_enemy_crowd.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_enemy_crowd.gd` with the shared helpers and the first test:

```gdscript
extends GdUnitTestSuite

# Minimal Enemy subclass: _execute_attack is abstract-ish (base does nothing),
# overridden here so instances are concrete and side-effect free.
class MockEnemy extends Enemy:
	func _execute_attack() -> void:
		pass

# Stand-in WorldManager exposing the two members enemies read.
class FakeWorld extends Node:
	var swarm_grid = preload("res://src/core/swarm_grid.gd").new(32.0)
	var nav_field = null

# Fake nav field: everything at x >= wall_x is solid. Default disabled.
class FakeNavField extends RefCounted:
	var wall_x: float = 1.0e20
	func is_solid_world(pos: Vector2) -> bool:
		return pos.x >= wall_x

func test_separation_steers_away_from_dense_cluster() -> void:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.global_position = Vector2.ZERO
	e._world_manager = world
	e.separation_radius = 22.0
	var c1: MockEnemy = auto_free(MockEnemy.new())
	c1.global_position = Vector2(10, 0)
	var c2: MockEnemy = auto_free(MockEnemy.new())
	c2.global_position = Vector2(12, 3)
	var c3: MockEnemy = auto_free(MockEnemy.new())
	c3.global_position = Vector2(12, -3)
	world.swarm_grid.rebuild([e, c1, c2, c3])
	# Steering toward the cluster (+X). Strong separation must flip it away (x < 0).
	var result: Vector2 = e._apply_separation(Vector2.RIGHT)
	assert_bool(result.x < 0.0).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_crowd.gd
```
Expected: FAIL — with the current `0.5` weight the result still leans toward +X, so `result.x < 0.0` is false. (The suite must load and report a failed assertion, not a parse/compile error.)

- [ ] **Step 3: Add the `separation_weight` export**

In `src/enemies/enemy.gd`, change the separation_radius default and add the weight just after it (around line 20):

```gdscript
@export var separation_radius: float = 22.0
@export var separation_weight: float = 1.2
```

(Was `@export var separation_radius: float = 16.0`.)

- [ ] **Step 4: Rewrite `_apply_separation`**

Replace the existing `_apply_separation` (lines ~374-388) with:

```gdscript
func _apply_separation(move_dir: Vector2) -> Vector2:
	if _world_manager == null or not is_instance_valid(_world_manager):
		return move_dir
	var grid = _world_manager.swarm_grid
	if grid == null:
		return move_dir
	var sep := Vector2.ZERO
	for enemy in grid.query_neighbors(global_position):
		if enemy == self or not is_instance_valid(enemy):
			continue
		var to_other: Vector2 = global_position - enemy.global_position
		var dist: float = to_other.length()
		if dist < separation_radius and dist > 0.001:
			sep += to_other.normalized() * ((separation_radius - dist) / separation_radius)
	if sep == Vector2.ZERO:
		return move_dir
	return (move_dir + sep * separation_weight).normalized()
```

- [ ] **Step 5: Run tests to verify they pass**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_crowd.gd && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_state_machine.gd
```
Expected: PASS for the new test, and the existing `test_separation_uses_grid_neighbors_only` / `test_separation_without_world_returns_input` in the state-machine suite still PASS (the new code preserves their behavior: bends a single neighbor's push below 1.0, and returns input unchanged when no world).

- [ ] **Step 6: Commit**

```bash
git add src/enemies/enemy.gd tests/unit/test_enemy_crowd.gd
git commit -m "feat: stronger enemy separation steering (tunable weight + radius)"
```

---

## Task 2: Depenetration safety net

**Files:**
- Modify: `src/enemies/enemy.gd` (add methods near `_apply_separation`; add export near other crowd params; add const near other consts ~line 29)
- Test: `tests/unit/test_enemy_crowd.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_enemy_crowd.gd`:

```gdscript
func test_depenetration_separates_stacked_enemies() -> void:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	var a: MockEnemy = auto_free(MockEnemy.new())
	var b: MockEnemy = auto_free(MockEnemy.new())
	a._world_manager = world
	b._world_manager = world
	a.global_position = Vector2(0, 0)
	b.global_position = Vector2(2, 0)  # heavily overlapping (< 16px min spacing)
	for _i in range(80):
		world.swarm_grid.rebuild([a, b])
		a._resolve_crowd_overlap()
		b._resolve_crowd_overlap()
	# Two 8px-radius bodies converge toward 16px centre distance.
	var d := a.global_position.distance_to(b.global_position)
	assert_float(d).is_greater_equal(15.0)

func test_depenetration_splits_coincident_enemies() -> void:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	var a: MockEnemy = auto_free(MockEnemy.new())
	var b: MockEnemy = auto_free(MockEnemy.new())
	a._world_manager = world
	b._world_manager = world
	a.global_position = Vector2.ZERO
	b.global_position = Vector2.ZERO  # exactly coincident
	for _i in range(80):
		world.swarm_grid.rebuild([a, b])
		a._resolve_crowd_overlap()
		b._resolve_crowd_overlap()
	var d := a.global_position.distance_to(b.global_position)
	assert_float(d).is_greater(1.0)

func test_depenetration_respects_walls() -> void:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	world.nav_field = FakeNavField.new()
	world.nav_field.wall_x = 10.0  # solid at x >= 10
	var a: MockEnemy = auto_free(MockEnemy.new())
	var b: MockEnemy = auto_free(MockEnemy.new())
	a._world_manager = world
	b._world_manager = world
	a.global_position = Vector2(0, 0)
	b.global_position = Vector2(-3, 0)  # pushes a toward the +X wall
	world.swarm_grid.rebuild([a, b])
	a._resolve_crowd_overlap()
	# a's leading edge (radius 8) + push would cross x=10, so the push is blocked.
	assert_float(a.global_position.x).is_less_equal(0.001)
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_crowd.gd
```
Expected: FAIL — `_resolve_crowd_overlap` does not exist yet, so these three tests error/fail (the Task 1 test still passes).

- [ ] **Step 3: Add the crowd-push const and export**

In `src/enemies/enemy.gd`, add the const next to the other movement consts (after `MOVE_STEP_PX` around line 29):

```gdscript
# Max depenetration correction applied per frame, in px. Small enough to avoid
# jitter/explosions in dense piles while still resolving overlap in a few frames.
const CROWD_PUSH_CAP: float = 4.0
```

Add the export right after `separation_weight` (from Task 1):

```gdscript
@export var crowd_spacing_scale: float = 1.0
```

- [ ] **Step 4: Implement the depenetration methods**

In `src/enemies/enemy.gd`, add these two methods immediately after `_apply_separation`:

```gdscript
## Push this body out of any neighbor it overlaps. Each body resolves HALF of a
## pair's overlap; the neighbor resolves its own half, so the pair separates
## symmetrically without oscillating. Runs every non-DEATH frame, so stationary
## enemies (windup/attack/cooldown) spread out too. Wall-safe: corrections that
## would enter solid terrain are dropped.
func _resolve_crowd_overlap() -> void:
	if _world_manager == null or not is_instance_valid(_world_manager):
		return
	var grid = _world_manager.swarm_grid
	if grid == null:
		return
	var push := Vector2.ZERO
	for enemy in grid.query_neighbors(global_position):
		if enemy == self or not is_instance_valid(enemy):
			continue
		var other_radius: float = DEFAULT_BODY_RADIUS
		if "_body_radius" in enemy:
			other_radius = enemy._body_radius
		var min_dist: float = (_body_radius + other_radius) * crowd_spacing_scale
		var to_self: Vector2 = global_position - enemy.global_position
		var dist: float = to_self.length()
		if dist >= min_dist:
			continue
		var dir: Vector2
		if dist > 0.001:
			dir = to_self / dist
		else:
			# Coincident: split deterministically along X by instance-id order so
			# the pair always pushes apart (never the same direction).
			var sign_dir: float = 1.0 if get_instance_id() > enemy.get_instance_id() else -1.0
			dir = Vector2(sign_dir, 0.0)
		push += dir * ((min_dist - dist) * 0.5)
	if push == Vector2.ZERO:
		return
	if push.length() > CROWD_PUSH_CAP:
		push = push.normalized() * CROWD_PUSH_CAP
	_apply_crowd_push(push)


## Apply a small positional correction, clamped per-axis against solid cells so a
## crowd in a corridor is never shoved into a wall. The cap keeps each axis step
## under MOVE_STEP_PX, so single-step edge checking can't tunnel.
func _apply_crowd_push(offset: Vector2) -> void:
	if offset.x != 0.0 and not _edge_blocked(Vector2(offset.x, 0.0)):
		global_position.x += offset.x
	if offset.y != 0.0 and not _edge_blocked(Vector2(0.0, offset.y)):
		global_position.y += offset.y
```

- [ ] **Step 5: Run tests to verify they pass**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_crowd.gd
```
Expected: PASS for all tests in the suite (Task 1 test + the three new ones).

- [ ] **Step 6: Commit**

```bash
git add src/enemies/enemy.gd tests/unit/test_enemy_crowd.gd
git commit -m "feat: depenetration safety net for enemy crowd spacing"
```

---

## Task 3: Run depenetration every non-DEATH frame

**Files:**
- Modify: `src/enemies/enemy.gd` (`_physics_process`, lines ~193-211)
- Test: `tests/unit/test_enemy_crowd.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_enemy_crowd.gd`:

```gdscript
func test_waiting_enemies_spread_in_physics_process() -> void:
	# ATTACK is a stationary state (no _moves_during_attack), so without the
	# depenetration call in _physics_process these would stay stacked.
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	var a: MockEnemy = auto_free(MockEnemy.new())
	var b: MockEnemy = auto_free(MockEnemy.new())
	a._world_manager = world
	b._world_manager = world
	a._state = Enemy.State.ATTACK
	b._state = Enemy.State.ATTACK
	a.global_position = Vector2(0, 0)
	b.global_position = Vector2(3, 0)
	for _i in range(80):
		world.swarm_grid.rebuild([a, b])
		a._physics_process(0.016)
		b._physics_process(0.016)
	var d := a.global_position.distance_to(b.global_position)
	assert_float(d).is_greater_equal(15.0)
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_crowd.gd
```
Expected: FAIL — `_physics_process` does not yet call `_resolve_crowd_overlap`, so the ATTACK-state enemies stay ~3px apart and `d >= 15.0` is false. (The four earlier tests still pass.)

- [ ] **Step 3: Wire the call into `_physics_process`**

In `src/enemies/enemy.gd`, find the end of `_physics_process` (the move-gate block, lines ~208-210):

```gdscript
	if _state == State.WANDER or _state == State.CHASE or _state == State.HURT \
			or (_state == State.ATTACK and _moves_during_attack()):
		_move_with_clamp(delta)
```

Add the depenetration call immediately after it (still inside `_physics_process`, which already early-returned on DEATH at the top):

```gdscript
	if _state == State.WANDER or _state == State.CHASE or _state == State.HURT \
			or (_state == State.ATTACK and _moves_during_attack()):
		_move_with_clamp(delta)
	# Every non-DEATH frame: keep bodies from stacking, even when stationary
	# (windup/attack/cooldown). DEATH already returned above.
	_resolve_crowd_overlap()
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_crowd.gd && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_state_machine.gd
```
Expected: PASS for the whole crowd suite and the enemy state-machine suite (no regression).

- [ ] **Step 5: Commit**

```bash
git add src/enemies/enemy.gd tests/unit/test_enemy_crowd.gd
git commit -m "feat: run enemy depenetration each non-death physics frame"
```

---

## Task 4: Full regression check

**Files:** none (verification only)

- [ ] **Step 1: Run the related enemy/swarm suites**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode \
  -a res://tests/unit/test_enemy_crowd.gd \
  -a res://tests/unit/test_enemy_state_machine.gd \
  -a res://tests/unit/test_swarm_grid.gd \
  -a res://tests/unit/test_melee_enemy.gd \
  -a res://tests/unit/test_enemy_wall_clamp.gd
```
Expected: all suites PASS. If any fail, fix before proceeding — do not edit tests to pass unless the test itself is demonstrably wrong.

- [ ] **Step 2: Manual smoke (optional but recommended)**

Launch the game, draw a crowd of enemies toward the player, and confirm they form a spread-out crowd around the player rather than stacking into a single point. Knockback and corridors should look stable (no jitter, no enemies shoved into walls).
```bash
godot --path .
```

---

## Self-review notes

- **Spec coverage:** Component 1 (steering) → Task 1. Component 2 (depenetration: half-overlap symmetric resolve, coincident jitter, per-frame cap, wall clamp) → Task 2. "Runs every non-DEATH state so waiting enemies spread" → Task 3. Testing section (converge, separation direction, wall safety) → Tasks 1-2 tests; plus the waiting-state integration test in Task 3.
- **Constraints:** spacing values (sep radius 22, min spacing ~16, cap 4) all stay under the 32px swarm-grid cell — no grid change. `crowd_spacing` (~16) < melee `_attack_range` (~28-32) so the front rank still reaches the player.
- **Type consistency:** `_resolve_crowd_overlap()`, `_apply_crowd_push(offset)`, `separation_weight`, `crowd_spacing_scale`, `CROWD_PUSH_CAP`, `_edge_blocked`, `_body_radius`, `DEFAULT_BODY_RADIUS` used consistently across tasks and match `enemy.gd`.
