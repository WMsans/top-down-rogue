# Enemy & Status Performance Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the ~110-enemy scene to a stable 60 fps by removing redundant physics work and per-frame allocations in the enemy crowd and status systems.

**Architecture:** Eliminate the per-enemy detection `Area2D`s (replace with a distance check), stop enemies physically colliding with each other (dedicated physics layer), replace O(n²) separation steering with an O(n) spatial-hash (`SwarmGrid`), cache per-frame node lookups, and gate `StatusComponent`'s per-frame signal so idle enemies cost almost nothing.

**Tech Stack:** Godot 4.6 (GDScript, Forward+), gdUnit4 6.0.0 test framework.

---

## Background for the implementer

- Tests use **gdUnit4**. A suite is a `.gd` file that `extends GdUnitTestSuite`, with `test_*()` methods and `assert_*()` matchers (`assert_that`, `assert_int`, `assert_float`, `assert_bool`, `assert_vector`). Allocate nodes with `auto_free(...)` so they are freed after the test.
- Run a single suite with:
  ```bash
  GODOT_BIN=/path/to/godot addons/gdUnit4/runtest.sh -a tests/unit/<file>.gd
  ```
  (If `GODOT_BIN` is already exported in your shell, omit the prefix.) Run the whole unit folder with `-a tests/unit`.
- `Enemy` (`src/enemies/enemy.gd`) is a `CharacterBody2D`. Its `_ready()` builds child nodes; tests that need `_ready` add the enemy to the scene tree, otherwise they set fields directly (see `tests/unit/test_enemy_state_machine.gd`).
- `StatusComponent` (`src/status/status_component.gd`) is a `Node` attached as a child named `"StatusComponent"` on the player and every enemy.
- `world_manager.gd` (`src/core/world_manager.gd`) is the per-frame driver; it is in group `"world_manager"` and its `_process(delta)` already orchestrates the frame (line 92).
- **Physics layers today:** both player (`scenes/player.tscn`) and enemy (`scenes/enemies/enemy.tscn`) use `collision_layer = 129` (layers 1 + 8). Only `2d_physics/layer_8="attackable_hit"` is named in `project.godot`. Terrain `StaticBody2D`s use the default layer 1. Default `collision_mask` is `1`.
- Bit values: layer 1 = `1`, layer 2 = `2`, layer 3 = `4`, layer 8 = `128`.

---

## File structure

- **Create** `src/core/swarm_grid.gd` — `SwarmGrid` (RefCounted): per-frame spatial hash of enemy positions; `rebuild(nodes)` + `query_neighbors(pos)`.
- **Create** `tests/unit/test_swarm_grid.gd` — unit tests for `SwarmGrid`.
- **Modify** `src/core/world_manager.gd` — own one `SwarmGrid`, rebuild it each frame from the `attackable` group.
- **Modify** `src/enemies/enemy.gd` — distance-based player detection (drop `DetectionArea`); grid-based separation; cache `StatusComponent` + `world_manager` refs; reuse `_player_ref`.
- **Modify** `scenes/enemies/enemy.tscn` — collision layer/mask for the enemy body.
- **Modify** `scenes/player.tscn` — add `enemy_body` to the player's collision mask.
- **Modify** `project.godot` — name physics layer 3 `enemy_body`.
- **Modify** `src/status/status_component.gd` — early-out idle entities; emit `changed` only when state changed.
- **Modify** `tests/unit/test_enemy_state_machine.gd` — add detection + separation tests.
- **Modify** `tests/unit/test_status_component.gd` — add signal-gating tests.

---

## Task 1: `SwarmGrid` spatial hash

**Files:**
- Create: `src/core/swarm_grid.gd`
- Test: `tests/unit/test_swarm_grid.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_swarm_grid.gd`:

```gdscript
extends GdUnitTestSuite

const SwarmGridScript = preload("res://src/core/swarm_grid.gd")

func _node_at(parent: Node, pos: Vector2) -> Node2D:
	var n: Node2D = auto_free(Node2D.new())
	parent.add_child(n)
	n.global_position = pos
	return n

func test_neighbors_includes_nearby_node() -> void:
	var grid = SwarmGridScript.new(32.0)
	var a := _node_at(self, Vector2(0, 0))
	var b := _node_at(self, Vector2(20, 0))
	grid.rebuild([a, b])
	var near := grid.query_neighbors(Vector2(0, 0))
	assert_bool(near.has(b)).is_true()

func test_neighbors_excludes_far_node() -> void:
	var grid = SwarmGridScript.new(32.0)
	var a := _node_at(self, Vector2(0, 0))
	var far := _node_at(self, Vector2(500, 500))
	grid.rebuild([a, far])
	var near := grid.query_neighbors(Vector2(0, 0))
	assert_bool(near.has(far)).is_false()

func test_query_spans_three_by_three_cells() -> void:
	# cell_size 32: a node one cell away (diagonally) is still a neighbor.
	var grid = SwarmGridScript.new(32.0)
	var center := _node_at(self, Vector2(0, 0))
	var diag := _node_at(self, Vector2(40, 40))  # cell (1,1) relative to (0,0)
	grid.rebuild([center, diag])
	var near := grid.query_neighbors(Vector2(0, 0))
	assert_bool(near.has(diag)).is_true()

func test_rebuild_clears_previous_contents() -> void:
	var grid = SwarmGridScript.new(32.0)
	var a := _node_at(self, Vector2(0, 0))
	grid.rebuild([a])
	grid.rebuild([])
	var near := grid.query_neighbors(Vector2(0, 0))
	assert_int(near.size()).is_equal(0)

func test_rebuild_skips_freed_nodes() -> void:
	var grid = SwarmGridScript.new(32.0)
	var a := Node2D.new()
	add_child(a)
	a.global_position = Vector2(0, 0)
	a.free()
	grid.rebuild([a])
	var near := grid.query_neighbors(Vector2(0, 0))
	assert_int(near.size()).is_equal(0)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `addons/gdUnit4/runtest.sh -a tests/unit/test_swarm_grid.gd`
Expected: FAIL — `res://src/core/swarm_grid.gd` does not exist / cannot preload.

- [ ] **Step 3: Write the implementation**

Create `src/core/swarm_grid.gd`:

```gdscript
class_name SwarmGrid
extends RefCounted

# Per-frame spatial hash of enemy positions used for O(n) crowd separation.
# Rebuilt once per frame by WorldManager; enemies query only their 3x3 cell
# neighbourhood instead of iterating the whole "attackable" group.
#
# cell_size must be >= the largest enemy separation_radius so a 3x3 query around
# a position covers every node within that radius. Enemy.separation_radius
# defaults to 16; 32 leaves headroom for elites/larger bodies.

var _cell_size: float
var _cells: Dictionary = {}  # Vector2i -> Array[Node2D]


func _init(cell_size: float = 32.0) -> void:
	_cell_size = maxf(1.0, cell_size)


func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / _cell_size), floori(pos.y / _cell_size))


func rebuild(nodes: Array) -> void:
	_cells.clear()
	for n in nodes:
		if not is_instance_valid(n) or not (n is Node2D):
			continue
		var key := _cell_of((n as Node2D).global_position)
		if not _cells.has(key):
			_cells[key] = []
		_cells[key].append(n)


func query_neighbors(pos: Vector2) -> Array:
	var result: Array = []
	var base := _cell_of(pos)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var key := base + Vector2i(dx, dy)
			if _cells.has(key):
				result.append_array(_cells[key])
	return result
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `addons/gdUnit4/runtest.sh -a tests/unit/test_swarm_grid.gd`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add src/core/swarm_grid.gd tests/unit/test_swarm_grid.gd
git commit -m "feat: add SwarmGrid spatial hash for O(n) crowd separation"
```

---

## Task 2: WorldManager owns and rebuilds the SwarmGrid each frame

**Files:**
- Modify: `src/core/world_manager.gd` (declare field + create in `_ready` + rebuild in `_process`)

This is integration wiring driven by the real per-frame loop; there is no isolated unit test (it depends on the live scene tree). Verified end-to-end in Task 8.

- [ ] **Step 1: Declare the field**

In `src/core/world_manager.gd`, add a member variable near the other `var` declarations at the top of the class (after the existing members, before `_ready`):

```gdscript
var swarm_grid: SwarmGrid = SwarmGrid.new(32.0)
```

- [ ] **Step 2: Rebuild the grid at the start of the frame**

In `src/core/world_manager.gd`, `_process(delta)` (currently starting at line 92), add the rebuild as the first action after the editor-hint guard:

```gdscript
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	swarm_grid.rebuild(get_tree().get_nodes_in_group("attackable"))
	_update_chunks()
	_run_simulation()
	_collision_helper.rebuild_dirty(chunks, delta)
	_run_terrain_probes()
	_update_lights()
	_drain_terrain_impacts()
	terrain_physical.set_center(Vector2i(tracking_position))
```

- [ ] **Step 3: Verify the project still loads**

Run: `addons/gdUnit4/runtest.sh -a tests/unit/test_terrain_physical.gd`
Expected: PASS — confirms `world_manager.gd` still parses/loads with the new field (this suite imports the world stack). No behavior change yet.

- [ ] **Step 4: Commit**

```bash
git add src/core/world_manager.gd
git commit -m "feat: WorldManager rebuilds SwarmGrid from attackable group each frame"
```

---

## Task 3: Enemy separation uses the SwarmGrid (O(n))

**Files:**
- Modify: `src/enemies/enemy.gd` (add cached refs; rewrite `_apply_separation`)
- Test: `tests/unit/test_enemy_state_machine.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_enemy_state_machine.gd`:

```gdscript
# Minimal stand-in for WorldManager exposing a swarm_grid for separation tests.
class FakeWorld extends Node:
	var swarm_grid = preload("res://src/core/swarm_grid.gd").new(32.0)

func test_separation_uses_grid_neighbors_only() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	e.global_position = Vector2(0, 0)
	e.separation_radius = 16.0

	# A crowding neighbour 8px to the right.
	var other: MockEnemy = auto_free(MockEnemy.new())
	add_child(other)
	other.global_position = Vector2(8, 0)

	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	world.swarm_grid.rebuild([e, other])
	e._world_manager = world

	# Moving right (toward the neighbour); separation should bend the vector
	# away from +X (its x-component drops below the raw 1.0).
	var result: Vector2 = e._apply_separation(Vector2.RIGHT)
	assert_bool(result.x < 1.0).is_true()

func test_separation_without_world_returns_input() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	e._world_manager = null
	var result: Vector2 = e._apply_separation(Vector2.RIGHT)
	assert_vector(result).is_equal(Vector2.RIGHT)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `addons/gdUnit4/runtest.sh -a tests/unit/test_enemy_state_machine.gd`
Expected: FAIL — `_world_manager` does not exist and `_apply_separation` still iterates the group (the no-world case will not return the input unchanged).

- [ ] **Step 3: Add the cached field**

In `src/enemies/enemy.gd`, add a member variable alongside the other `var` declarations (e.g. after `var _player_ref: Node2D = null` at line 52):

```gdscript
var _world_manager: Node = null
```

- [ ] **Step 4: Rewrite `_apply_separation`**

In `src/enemies/enemy.gd`, replace the entire existing `_apply_separation` function (lines 334-343) with:

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
	return (move_dir + sep * 0.5).normalized()
```

- [ ] **Step 5: Cache the world_manager reference in `_ready`**

In `src/enemies/enemy.gd`, `_ready()`, add a line right after the existing player lookup (line 79, `_player_ref = get_tree().get_first_node_in_group("player")`):

```gdscript
	_world_manager = get_tree().get_first_node_in_group("world_manager")
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `addons/gdUnit4/runtest.sh -a tests/unit/test_enemy_state_machine.gd`
Expected: PASS (including the two new tests).

- [ ] **Step 7: Commit**

```bash
git add src/enemies/enemy.gd tests/unit/test_enemy_state_machine.gd
git commit -m "perf: enemy separation queries SwarmGrid neighbors instead of full group"
```

---

## Task 4: Distance-based player detection (remove per-enemy DetectionArea)

**Files:**
- Modify: `src/enemies/enemy.gd` (remove the `Area2D` build + handlers; add `_update_player_in_range`)
- Test: `tests/unit/test_enemy_state_machine.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_enemy_state_machine.gd`:

```gdscript
func test_player_in_range_true_when_close() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.detection_radius = 100.0
	e._player_ref = auto_free(Node2D.new())
	add_child(e._player_ref)
	e.global_position = Vector2.ZERO
	e._player_ref.global_position = Vector2(50, 0)
	e._update_player_in_range()
	assert_bool(e._player_in_range).is_true()

func test_player_in_range_false_when_far() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.detection_radius = 100.0
	e._player_ref = auto_free(Node2D.new())
	add_child(e._player_ref)
	e.global_position = Vector2.ZERO
	e._player_ref.global_position = Vector2(200, 0)
	e._update_player_in_range()
	assert_bool(e._player_in_range).is_false()

func test_player_in_range_false_when_no_player() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e._player_ref = null
	e._update_player_in_range()
	assert_bool(e._player_in_range).is_false()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `addons/gdUnit4/runtest.sh -a tests/unit/test_enemy_state_machine.gd`
Expected: FAIL — `_update_player_in_range()` does not exist.

- [ ] **Step 3: Add the detection method**

In `src/enemies/enemy.gd`, add this function (place it just above `_on_detection_body_entered`, around line 477):

```gdscript
func _update_player_in_range() -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		_player_in_range = false
		return
	var r: float = detection_radius
	_player_in_range = global_position.distance_squared_to(_player_ref.global_position) <= r * r
```

- [ ] **Step 4: Call it from `_process` and remove the Area2D**

In `src/enemies/enemy.gd`, `_process(delta)`: add the detection refresh near the top of `_process`, immediately after the `_teleport_cooldown` block and before the `if _state == State.DEATH:` check (around line 156):

```gdscript
	_update_player_in_range()
```

Then **delete** the detection `Area2D` construction in `_ready()` (lines 88-99 — the block from `var detection_area := Area2D.new()` through `add_child(detection_area)`).

Then **delete** the two now-unused handlers `_on_detection_body_entered` (lines 477-479) and `_on_detection_body_exited` (lines 482-484).

- [ ] **Step 5: Run the test to verify it passes**

Run: `addons/gdUnit4/runtest.sh -a tests/unit/test_enemy_state_machine.gd`
Expected: PASS (including the three new tests). The existing `test_transitions_to_chase_*` tests still pass because they set `_player_in_range` directly before calling `_process`, and `_update_player_in_range` runs first using their `_player_ref`/positions — confirm those positions keep them in/out of range as before (they use `Vector2(10,0)` within the default `detection_radius` of 150).

- [ ] **Step 6: Commit**

```bash
git add src/enemies/enemy.gd tests/unit/test_enemy_state_machine.gd
git commit -m "perf: replace per-enemy detection Area2D with distance check"
```

---

## Task 5: Cache StatusComponent + player refs in enemy.gd

**Files:**
- Modify: `src/enemies/enemy.gd`

These remove per-frame string/group lookups done across all enemies. Behavior is unchanged; the existing `test_enemy_state_machine.gd` and `test_enemy_aggression.gd` suites guard against regressions.

- [ ] **Step 1: Add the cached StatusComponent field**

In `src/enemies/enemy.gd`, add a member variable near the other status-related vars (e.g. after `var _world_manager: Node = null` from Task 3):

```gdscript
var _status_component: Node = null
```

- [ ] **Step 2: Populate it in `_ready`**

In `src/enemies/enemy.gd`, `_ready()`, the `StatusComponent` is created and added around lines 114-116:

```gdscript
	var status := StatusComponent.new()
	status.name = "StatusComponent"
	add_child(status)
```

Add immediately after it:

```gdscript
	_status_component = status
```

- [ ] **Step 3: Use the cached ref in `_physics_process`**

In `src/enemies/enemy.gd`, `_physics_process` (line 194) currently does:

```gdscript
	var tint_status := get_node_or_null("StatusComponent")
```

Replace that line with:

```gdscript
	var tint_status := _status_component
```

- [ ] **Step 4: Replace the four targeting/speed helpers in one block**

In `src/enemies/enemy.gd`, these four functions are contiguous at the end of the file (lines 562-598), in this order: `_is_targeted`, `_get_effective_speed`, `_base_effective_speed`, `_get_cooldown_multiplier`. Each currently calls `get_tree().get_first_node_in_group("player")` (or, for `_get_effective_speed`, `get_node_or_null("StatusComponent")`). Replace the **entire block (lines 562-598)** with the cached-ref versions below — paste these four functions exactly once, preserving their order:

```gdscript
func _is_targeted() -> bool:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return false
	return _player_ref.get("targeted_enemy") == self


func _get_effective_speed() -> float:
	var base := _base_effective_speed()
	if _status_component != null and is_instance_valid(_status_component):
		base *= _status_component.get_move_speed_multiplier()
	return base


func _base_effective_speed() -> float:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return speed
	var target = _player_ref.get("targeted_enemy")
	if target == null:
		return speed
	if target == self:
		return speed * TARGETED_SPEED_MULT
	return speed * PASSIVE_SPEED_MULT


func _get_cooldown_multiplier() -> float:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return 1.0
	var target = _player_ref.get("targeted_enemy")
	if target == null:
		return 1.0
	if target == self:
		return TARGETED_COOLDOWN_MULT
	return PASSIVE_COOLDOWN_MULT
```

- [ ] **Step 5: Run the enemy suites to verify no regression**

Run: `addons/gdUnit4/runtest.sh -a tests/unit/test_enemy_state_machine.gd`
Then: `addons/gdUnit4/runtest.sh -a tests/unit/test_enemy_aggression.gd`
Expected: PASS for both.

- [ ] **Step 6: Commit**

```bash
git add src/enemies/enemy.gd
git commit -m "perf: cache StatusComponent and player refs in enemy per-frame paths"
```

---

## Task 6: Gate StatusComponent's per-frame signal + early-out idle entities

**Files:**
- Modify: `src/status/status_component.gd`
- Test: `tests/unit/test_status_component.gd`

The current `tick()` (lines 122-127) always calls `changed.emit()`, firing `StatusVisuals.refresh` for every component every frame. Idle entities (no stains, no burn) should do nothing and emit nothing.

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_status_component.gd`:

```gdscript
func test_tick_does_not_emit_when_idle() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	var count := [0]
	c.changed.connect(func() -> void: count[0] += 1)
	c.tick(1.0)  # no stains, no burn
	assert_int(count[0]).is_equal(0)

func test_tick_emits_when_decaying_stain() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("wet", 5.0)
	var count := [0]
	c.changed.connect(func() -> void: count[0] += 1)
	c.tick(1.0)  # decay changes the stain -> should emit
	assert_int(count[0]).is_equal(1)

func test_idle_tick_keeps_stains_empty() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.tick(1.0)
	assert_int(c._stains.size()).is_equal(0)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `addons/gdUnit4/runtest.sh -a tests/unit/test_status_component.gd`
Expected: FAIL — `test_tick_does_not_emit_when_idle` fails because `tick()` emits unconditionally.

- [ ] **Step 3: Rewrite `tick` to early-out and emit conditionally**

In `src/status/status_component.gd`, replace `tick` (lines 122-127):

```gdscript
func tick(delta: float) -> void:
	# Idle fast path: nothing to decay, no burn in flight -> no work, no signal.
	# Reactions only matter when at least one stain is present, so an empty
	# component with no pending burn can safely do nothing this frame.
	if _stains.is_empty() and _burn_accum == 0.0:
		return
	_decay(delta)
	StatusRegistry.apply_reactions(self, delta)
	_apply_effects(delta)
	changed.emit()
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `addons/gdUnit4/runtest.sh -a tests/unit/test_status_component.gd`
Expected: PASS (all existing tests plus the three new ones).

Rationale for safety: `_decay`, `apply_reactions`, and `_apply_effects` all operate on existing stains or `_burn_accum`; with both empty there is no state they could change, so skipping them and the emit is behavior-preserving. The terrain poll (which *adds* stains) runs separately in `update()` before `tick()`, so a frame that picks up a new stain still has a non-empty `_stains` when `tick()` runs and proceeds normally.

- [ ] **Step 5: Commit**

```bash
git add src/status/status_component.gd tests/unit/test_status_component.gd
git commit -m "perf: StatusComponent skips work and signal when idle"
```

---

## Task 7: Physics layer reorg — enemies stop colliding with each other

**Files:**
- Modify: `project.godot` (name layer 3)
- Modify: `scenes/enemies/enemy.tscn` (enemy body layer/mask)
- Modify: `scenes/player.tscn` (player mask)

These are declarative config edits to scene/project files; they have no isolated unit test and are verified manually in this task's final step and in Task 8.

Target after this task:
- Enemy `collision_layer = 132` (layer 3 `enemy_body` = 4, layer 8 `attackable_hit` = 128) — **dropped layer 1**.
- Enemy `collision_mask = 1` (collide with terrain + player, both on layer 1) — **not** layer 3, so enemies ignore each other.
- Player `collision_mask = 5` (terrain layer 1 + `enemy_body` layer 3 = 4) — player still pushes/blocks enemies.
- Player `collision_layer = 129` (unchanged — keeps layer 1 so enemies' mask sees the player).

- [ ] **Step 1: Name physics layer 3**

In `project.godot`, the `[layer_names]` section currently contains only:

```
[layer_names]

2d_physics/layer_8="attackable_hit"
```

Add the `enemy_body` name (alphabetical/numeric order within the section):

```
[layer_names]

2d_physics/layer_3="enemy_body"
2d_physics/layer_8="attackable_hit"
```

- [ ] **Step 2: Update the enemy body layer/mask**

In `scenes/enemies/enemy.tscn`, the root node is:

```
[node name="Enemy" type="CharacterBody2D" unique_id=693161229]
collision_layer = 129
script = ExtResource("1")
```

Change it to:

```
[node name="Enemy" type="CharacterBody2D" unique_id=693161229]
collision_layer = 132
collision_mask = 1
script = ExtResource("1")
```

- [ ] **Step 3: Update the player mask**

In `scenes/player.tscn`, the root node is:

```
[node name="Player" type="CharacterBody2D" unique_id=1776190034]
collision_layer = 129
```

Change it to:

```
[node name="Player" type="CharacterBody2D" unique_id=1776190034]
collision_layer = 129
collision_mask = 5
```

- [ ] **Step 4: Manual verification in-engine**

Launch the game and confirm each interaction explicitly:
- Enemies are **blocked by terrain** (cannot walk through walls).
- Enemies **collide with the player** (player can push into a crowd and feel resistance; enemies cannot stack on top of the player without contact).
- Enemies **pass through / softly overlap each other** (no hard bumping; the steering from Task 3 keeps them loosely spaced).
- **Weapons/projectiles still hit enemies** (melee + ranged register damage) — this uses `attackable_hit` (layer 8), which is unchanged.

If any of the above is wrong, the bit math is the place to look (layer 1 = 1, layer 3 = 4, layer 8 = 128).

- [ ] **Step 5: Commit**

```bash
git add project.godot scenes/enemies/enemy.tscn scenes/player.tscn
git commit -m "perf: dedicated enemy_body physics layer; enemies no longer collide with each other"
```

---

## Task 8: Profiler verification

**Files:** none (measurement only).

- [ ] **Step 1: Run the full unit suite**

Run: `addons/gdUnit4/runtest.sh -a tests/unit`
Expected: all suites PASS (no regressions from the refactors).

- [ ] **Step 2: Profile the ~110-enemy scene**

Open the same stress scene used to capture the original profile, run with the Godot profiler enabled (Debugger → Profiler → Monitors / Frame profiler), and capture a frame under load.

- [ ] **Step 3: Confirm the targets**

Verify against the baseline (Frame Time 48.97 ms, Physics 2D 32.79 ms):
- `Physics 2D` is well below the 16.6 ms 60fps budget (detection areas gone, enemy-enemy contacts gone).
- `Enemy._process` no longer shows O(n²) separation cost; `get_tree().get_nodes_in_group` calls per enemy are gone.
- `StatusComponent._process` / `update` per-frame cost is reduced for idle enemies; `StatusVisuals.refresh` no longer fires ×111/frame.
- Frame rate holds at a stable 60 fps.

- [ ] **Step 4: Record the result**

Note the before/after frame time in the PR / branch description. If still short of 60 fps, the next lever is the deferred terrain/GPU readback work (out of scope here — see the design doc's Non-goals).

---

## Done

When all tasks are checked off, the branch is ready for `requesting-code-review` and then `finishing-a-development-branch`.
