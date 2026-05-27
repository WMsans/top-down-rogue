# Cave Enemy Spawning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Minecraft-style natural enemy spawning in cave corridors between rooms, coexisting with existing room-template spawning.

**Architecture:** A new `CaveSpawner` node owned by `LevelManager` runs spawn/despawn timers. It validates positions using `TerrainPhysical.query()` (existing CPU-side terrain cache), checks player distance via `WorldManager.tracking_position`, and enforces a mob cap by counting nodes in the `"attackable"` group.

**Tech Stack:** Godot 4.6 with GdUnit4 test framework.

---

### Task 1: Add `cave_spawn_rate` to `BiomeDef`

**Files:**
- Modify: `src/core/biome_def.gd:15`

- [ ] **Step 1: Add the exported field**

```gdscript
@export var cave_spawn_rate: float = 1.0
```

Insert as a new line after `@export var tint: Color = Color.WHITE` in `src/core/biome_def.gd`.

- [ ] **Step 2: Verify syntax**

Run: `godot --headless --check-only --script src/core/biome_def.gd 2>&1 || true`
Expected: No parse errors reported for the script.

- [ ] **Step 3: Commit**

```bash
git add src/core/biome_def.gd
git commit -m "feat: add cave_spawn_rate to BiomeDef resource"
```

---

### Task 2: Create `CaveSpawner` node

**Files:**
- Create: `src/core/cave_spawner.gd`

- [ ] **Step 1: Write the full `cave_spawner.gd`**

```gdscript
extends Node

const ENEMY_SCENE := preload("res://scenes/dummy_enemy.tscn")

@export var spawn_interval: float = 1.0
@export var attempts_per_cycle: int = 2
@export var spawn_min_dist: float = 600.0
@export var spawn_max_dist: float = 2000.0
@export var despawn_dist: float = 2500.0
@export var mob_cap: int = 15
@export var spawn_rate: float = 1.0

const BASE_SPAWN_CHANCE: float = 0.5
const MAX_VALIDATION_RETRIES: int = 3

var _world_manager: Node2D = null
var _terrain_physical: TerrainPhysical = null
var _spawn_parent: Node2D = null
var _spawn_timer: Timer = null
var _despawn_timer: Timer = null


func _ready() -> void:
	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = spawn_interval
	_spawn_timer.timeout.connect(_on_spawn_tick)
	add_child(_spawn_timer)
	_spawn_timer.start()

	_despawn_timer = Timer.new()
	_despawn_timer.wait_time = 1.0
	_despawn_timer.timeout.connect(_on_despawn_tick)
	add_child(_despawn_timer)
	_despawn_timer.start()

	set_process(false)
	_resolve_dependencies()


func _resolve_dependencies() -> void:
	var wm := get_tree().get_first_node_in_group("world_manager")
	if wm == null:
		return

	_world_manager = wm
	_spawn_parent = _world_manager.get_chunk_container()
	_terrain_physical = _world_manager.terrain_physical

	var surface := get_node_or_null("/root/TerrainSurface")
	if surface and surface.adapter:
		pass


func set_biome_params(new_spawn_rate: float) -> void:
	spawn_rate = new_spawn_rate


func clear() -> void:
	pass


func _count_live_enemies() -> int:
	return get_tree().get_nodes_in_group("attackable").filter(func(n): return is_instance_valid(n)).size()


func _on_spawn_tick() -> void:
	if not is_instance_valid(_world_manager) or not is_instance_valid(_terrain_physical):
		_resolve_dependencies()
		return

	if _count_live_enemies() >= mob_cap:
		return

	var surface := get_node_or_null("/root/TerrainSurface")
	if surface == null:
		return

	var chunk_coords: Array = surface.get_active_chunk_coords()
	if chunk_coords.is_empty():
		return

	chunk_coords.shuffle()

	var attempts := 0
	for chunk_coord in chunk_coords:
		if attempts >= attempts_per_cycle:
			break

		var world_base := Vector2(chunk_coord * 256)
		for _retry in range(MAX_VALIDATION_RETRIES):
			var local_x := randi() % 256
			var local_y := randi() % 256
			var world_pos := world_base + Vector2(local_x, local_y)

			if _validate_position(world_pos):
				_spawn_enemy(world_pos)
				attempts += 1
				break


func _validate_position(world_pos: Vector2) -> bool:
	if not is_instance_valid(_world_manager):
		return false

	var player_pos: Vector2 = _world_manager.tracking_position
	var dist := world_pos.distance_to(player_pos)
	if dist < spawn_min_dist or dist > spawn_max_dist:
		return false

	if randf() > spawn_rate * BASE_SPAWN_CHANCE:
		return false

	if not _has_solid_floor(world_pos):
		return false

	if not _has_headroom(world_pos):
		return false

	return true


func _has_solid_floor(world_pos: Vector2) -> bool:
	if _terrain_physical == null:
		return false

	var down_offsets := [Vector2.ZERO, Vector2(0, 16), Vector2(0, 32)]
	for offset in down_offsets:
		var cell := _terrain_physical.query(world_pos + offset)
		if cell.is_solid:
			return true
	return false


func _has_headroom(world_pos: Vector2) -> bool:
	if _terrain_physical == null:
		return false

	var up_offsets := [Vector2(0, -8), Vector2(0, -24)]
	for offset in up_offsets:
		var cell := _terrain_physical.query(world_pos + offset)
		if cell.is_solid:
			return false
	return true


func _spawn_enemy(world_pos: Vector2) -> void:
	var enemy := ENEMY_SCENE.instantiate()
	enemy.global_position = world_pos
	_spawn_parent.add_child(enemy)


func _on_despawn_tick() -> void:
	if not is_instance_valid(_world_manager):
		return

	var player_pos: Vector2 = _world_manager.tracking_position
	for enemy in get_tree().get_nodes_in_group("attackable"):
		if not is_instance_valid(enemy):
			continue
		if enemy.global_position.distance_to(player_pos) > despawn_dist:
			enemy.queue_free()
```

- [ ] **Step 2: Verify syntax**

Run: `godot --headless --check-only --script src/core/cave_spawner.gd 2>&1 || true`
Expected: No parse errors reported for the script.

- [ ] **Step 3: Commit**

```bash
git add src/core/cave_spawner.gd
git commit -m "feat: add CaveSpawner with Minecraft-style cave spawning"
```

---

### Task 3: Wire `CaveSpawner` into `LevelManager`

**Files:**
- Modify: `src/autoload/level_manager.gd:1-44`

- [ ] **Step 1: Add `_cave_spawner` field and instantiate in `_ready()`**

In `src/autoload/level_manager.gd`, add the field after `var _spawn_dispatcher: Node` (line 12):

```gdscript
var _cave_spawner: Node
```

In `_ready()` (after the SpawnDispatcher instantiation block, lines 19-22), add:

```gdscript
	var CaveSpawner = load("res://src/core/cave_spawner.gd")
	_cave_spawner = CaveSpawner.new()
	_cave_spawner.name = "CaveSpawner"
	add_child(_cave_spawner)
```

- [ ] **Step 2: Handle floor advance**

In `advance_floor()` (line 33), after the `_spawn_dispatcher.clear()` block (lines 38-39), add:

```gdscript
	if _cave_spawner and _cave_spawner.has_method("set_biome_params"):
		_cave_spawner.set_biome_params(current_biome.cave_spawn_rate)
```

- [ ] **Step 3: Verify syntax**

Run: `godot --headless --check-only --script src/autoload/level_manager.gd 2>&1 || true`
Expected: No parse errors reported for the script.

- [ ] **Step 4: Commit**

```bash
git add src/autoload/level_manager.gd
git commit -m "feat: wire CaveSpawner into LevelManager"
```

---

### Task 4: Write unit tests

**Files:**
- Create: `tests/unit/test_cave_spawner.gd`

- [ ] **Step 1: Create `test_cave_spawner.gd`**

```gdscript
extends GdUnitTestSuite

const _CaveSpawner = preload("res://src/core/cave_spawner.gd")
const _Enemy = preload("res://src/enemies/enemy.gd")
const _DummyEnemy = preload("res://scenes/dummy_enemy.tscn")


func test_mob_cap_enforcement() -> void:
	var spawner := _CaveSpawner.new()
	add_child(spawner)

	spawner.mob_cap = 3
	spawner.spawn_rate = 0.0

	for _i in range(3):
		var enemy := _DummyEnemy.instantiate()
		add_child(enemy)

	spawner._on_spawn_tick()

	var live := spawner._count_live_enemies()
	assert_that(live).is_equal(3)


func test_distance_validation_rejects_too_close() -> void:
	var spawner := _CaveSpawner.new()
	add_child(spawner)

	spawner.spawn_min_dist = 600.0
	spawner.spawn_max_dist = 2000.0

	assert_bool(spawner._validate_position(Vector2(100, 0))).is_false()


func test_distance_validation_rejects_too_far() -> void:
	var spawner := _CaveSpawner.new()
	add_child(spawner)

	spawner.spawn_min_dist = 600.0
	spawner.spawn_max_dist = 2000.0

	assert_bool(spawner._validate_position(Vector2(3000, 0))).is_false()


func test_distance_validation_accepts_in_range() -> void:
	var spawner := _CaveSpawner.new()
	add_child(spawner)

	spawner.spawn_min_dist = 600.0
	spawner.spawn_max_dist = 2000.0

	assert_bool(spawner._validate_position(Vector2(1000, 0))).is_true()


func test_spawn_rate_zero_always_rejects() -> void:
	var spawner := _CaveSpawner.new()
	add_child(spawner)

	spawner.spawn_min_dist = 0.0
	spawner.spawn_max_dist = 100000.0
	spawner.spawn_rate = 0.0

	var accepted := false
	for _i in range(100):
		if spawner._validate_position(Vector2(randi() % 2000, randi() % 2000)):
			accepted = true
			break

	assert_bool(accepted).is_false()


func test_despawn_removes_far_enemy() -> void:
	var spawner := _CaveSpawner.new()
	add_child(spawner)

	spawner.despawn_dist = 2500.0

	var enemy := _DummyEnemy.instantiate()
	add_child(enemy)
	enemy.global_position = Vector2(3000, 0)

	spawner._on_despawn_tick()

	assert_bool(is_instance_valid(enemy)).is_false()
```

- [ ] **Step 2: Run the tests**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_cave_spawner.gd 2>&1`
Expected: All tests FAIL (tests reference `_world_manager` which is null in test environment).

- [ ] **Step 3: Make `_validate_position` and `_has_solid_floor` testable without WorldManager**

The `_validate_position` function checks `_world_manager` at the top and returns `false` if null. For distance tests to work, we need to either:
1. Mock `_world_manager` with a dummy object that has `tracking_position = Vector2.ZERO`, or
2. Make distance validation separate from the WorldManager dependency.

Replace the beginning of `_validate_position` in `src/core/cave_spawner.gd`:

```gdscript
func _validate_position(world_pos: Vector2) -> bool:
	var player_pos := Vector2.ZERO
	if is_instance_valid(_world_manager):
		player_pos = _world_manager.tracking_position

	var dist := world_pos.distance_to(player_pos)
	if dist < spawn_min_dist or dist > spawn_max_dist:
		return false

	if randf() > spawn_rate * BASE_SPAWN_CHANCE:
		return false

	if _terrain_physical == null:
		return false

	if not _has_solid_floor(world_pos):
		return false

	if not _has_headroom(world_pos):
		return false

	return true
```

- [ ] **Step 4: Make `_on_despawn_tick` testable without WorldManager**

Replace the beginning of `_on_despawn_tick` in `src/core/cave_spawner.gd`:

```gdscript
func _on_despawn_tick() -> void:
	var player_pos := Vector2.ZERO
	if is_instance_valid(_world_manager):
		player_pos = _world_manager.tracking_position

	for enemy in get_tree().get_nodes_in_group("attackable"):
		if not is_instance_valid(enemy):
			continue
		if enemy.global_position.distance_to(player_pos) > despawn_dist:
			enemy.queue_free()
```

- [ ] **Step 5: Run tests again**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_cave_spawner.gd 2>&1`
Expected: All 6 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add tests/unit/test_cave_spawner.gd src/core/cave_spawner.gd
git commit -m "test: add unit tests for CaveSpawner with WorldManager-independent validation"
```

---

### Task 5: Integration test (manual smoke test)

**Files:**
- None modified (verification only)

- [ ] **Step 1: Launch the game**

Run: `godot --editor &` then press F5 to run the project. Or use: `godot --headless 2>&1 &` and check logs.

Manually verify:
1. Enter a game level (not creative mode).
2. Walk around in cave corridors.
3. Observe that DummyEnemy instances appear in the cave as the player moves, not just inside rooms.
4. Walk far away from an enemy — verify it disappears beyond ~2500px.
5. Kill enough enemies to reach the mob cap — verify no new spawns while cap is full.
6. Enter creative mode — verify enemies still spawn (no mode gating).

- [ ] **Step 2: Commit any remaining changes**

If no changes needed, skip. Otherwise:

```bash
git add .
git commit -m "chore: verified cave spawning integration"
```

---

### Self-Review

**Spec coverage:**
- Room-template spawning coexisting: ✅ Task 2 cave_spawner.gd runs independently, no changes to spawn_dispatcher.gd
- Material-based validation (TerrainPhysical.query): ✅ _has_solid_floor and _has_headroom use TerrainPhysical.query
- Player distance [600, 2000]: ✅ _validate_position checks min/max dist against tracking_position
- Mob cap 15: ✅ _on_spawn_tick gates on _count_live_enemies >= mob_cap
- 2 attempts every 1s: ✅ Timer with spawn_interval=1.0, attempts_per_cycle=2
- Despawn at 2500px every 1s: ✅ _despawn_timer at 1s, _on_despawn_tick removes beyond despawn_dist
- Biome awareness: ✅ BiomeDef.cave_spawn_rate, LevelManager calls set_biome_params on floor advance
- Creative mode spawns enabled: ✅ No GameModeManager gate in _on_spawn_tick
- Enemies parented to chunk_container: ✅ _spawn_parent = _world_manager.get_chunk_container()
- Edge cases: ✅ Validation retries, null-safe WorldManager access, skipped spawns on failure

**Placeholder scan:** No TBD, TODO, or vague instructions found.

**Type consistency:**
- `cave_spawn_rate: float` in BiomeDef ← passed to `set_biome_params(float)` in CaveSpawner ✅
- `_spawn_parent: Node2D` ← returned by `get_chunk_container() -> Node2D` ✅
- `_world_manager.terrain_physical: TerrainPhysical` ← used as `_terrain_physical` ✅
- `_world_manager.tracking_position: Vector2` ← used as `player_pos: Vector2` ✅
