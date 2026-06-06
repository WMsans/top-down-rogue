# Enemy Navigation (Flow-Field Pursuit + Grid Clamp) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give enemies cheap wall-respecting movement and flow-field routing around walls toward the player, without re-enabling per-enemy terrain physics.

**Architecture:** A coarse CPU `PassabilityGrid` (per-chunk tiles, refreshed on dirty chunks) feeds a shared, double-buffered, time-sliced `FlowField` built outward from the player. A `NavField` glue object owned by `WorldManager` ties them together and is ticked each frame. Enemies sample the field to route around walls when line-of-sight is blocked and use an O(1) axis-slide clamp against the grid in place of physics collision.

**Tech Stack:** Godot 4.6, GDScript, gdUnit4 test framework. Design spec: `docs/superpowers/specs/2026-06-05-enemy-navigation-design.md`.

---

## Conventions for every test step

Run a single test file with the gdUnit4 CLI runner:

```bash
export GODOT_BIN=/usr/bin/godot
./addons/gdUnit4/runtest.sh -a tests/unit/<file>.gd
```

A passing suite prints a summary with `0 failed`/`0 errors`. A failing/missing test prints the failure or a parse error.

## File Structure

- Create `src/core/nav/passability_grid.gd` — coarse solid/open lookup from material bytes (`PassabilityGrid`, `RefCounted`).
- Create `src/core/nav/flow_field.gd` — double-buffered, time-sliced BFS field (`FlowField`, `RefCounted`).
- Create `src/core/nav/nav_field.gd` — glue: owns the grid + field, drains dirty chunks via `read_region`, exposes `sample_direction`/`is_solid_world` (`NavField`, `RefCounted`).
- Modify `src/core/world_manager.gd` — create/own `nav_field`, mark it dirty, tick it.
- Modify `src/enemies/enemy.gd` — sight-to-acquire + sticky leash pursuit, field fallback when LOS blocked, axis-slide clamp replacing `move_and_slide`.
- Modify `scenes/enemies/enemy.tscn` — drop enemy terrain `collision_mask` to 0.
- Create `tests/unit/test_passability_grid.gd`, `tests/unit/test_flow_field.gd`, `tests/unit/test_nav_field.gd`, `tests/unit/test_enemy_pursuit.gd`.

---

## Task 1: PassabilityGrid

**Files:**
- Create: `src/core/nav/passability_grid.gd`
- Test: `tests/unit/test_passability_grid.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_passability_grid.gd`:

```gdscript
extends GdUnitTestSuite

const PassabilityGrid = preload("res://src/core/nav/passability_grid.gd")

# Build a 256x256 material region (1 byte/pixel) that is all `air` except a
# square block of `solid` in the top-left local area [x0,x1) x [y0,y1).
func _region_with_block(air: int, solid: int, x0: int, y0: int, x1: int, y1: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(256 * 256)
	bytes.fill(air)
	for y in range(y0, y1):
		for x in range(x0, x1):
			bytes[y * 256 + x] = solid
	return bytes

# solid_lut: index = material id, value 1 means "has collider".
func _lut(solid_ids: Array) -> PackedByteArray:
	var lut := PackedByteArray()
	lut.resize(8)
	lut.fill(0)
	for id in solid_ids:
		lut[id] = 1
	return lut

func test_open_when_no_tiles() -> void:
	var g = PassabilityGrid.new(8, 256, _lut([2]))
	assert_bool(g.is_solid_world(Vector2(4, 4))).is_false()

func test_classifies_solid_block() -> void:
	# air id 0, solid id 2. Block covers pixels [0,16) x [0,16) of chunk (0,0).
	var g = PassabilityGrid.new(8, 256, _lut([2]))
	g.update_chunk(Vector2i(0, 0), _region_with_block(0, 2, 0, 0, 16, 16))
	# A pixel inside the block -> solid cell.
	assert_bool(g.is_solid_world(Vector2(4, 4))).is_true()
	# A pixel well outside the block -> open.
	assert_bool(g.is_solid_world(Vector2(100, 100))).is_false()

func test_any_solid_pixel_marks_whole_cell() -> void:
	# A single solid pixel at (9,9) sits in cell (1,1) (8px cells); that cell is solid.
	var g = PassabilityGrid.new(8, 256, _lut([2]))
	g.update_chunk(Vector2i(0, 0), _region_with_block(0, 2, 9, 9, 10, 10))
	assert_bool(g.is_solid_world(Vector2(8, 8))).is_true()   # cell (1,1)
	assert_bool(g.is_solid_world(Vector2(0, 0))).is_false()  # cell (0,0)

func test_negative_chunk_coords() -> void:
	var g = PassabilityGrid.new(8, 256, _lut([2]))
	g.update_chunk(Vector2i(-1, -1), _region_with_block(0, 2, 248, 248, 256, 256))
	# World pixel (-4,-4) lives in chunk (-1,-1) local (252,252) -> inside block.
	assert_bool(g.is_solid_world(Vector2(-4, -4))).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_passability_grid.gd`
Expected: FAIL/parse error — `passability_grid.gd` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `src/core/nav/passability_grid.gd`:

```gdscript
class_name PassabilityGrid
extends RefCounted

# Coarse "is this cell solid?" lookup, backed by cached per-chunk tiles.
# A cell is solid if ANY pixel in its block uses a material flagged solid in the
# LUT. That conservative rule inflates walls by ~one enemy radius (8px), keeping
# bodies out of walls like agent-radius inflation in a navmesh.

var _cell: int
var _chunk: int
var _cells_per_chunk: int
var _solid_lut: PackedByteArray
var _tiles: Dictionary = {}  # Vector2i chunk coord -> PackedByteArray (cells_per_chunk^2, 1=solid)

func _init(cell_size: int = 8, chunk_size: int = 256, solid_lut: PackedByteArray = PackedByteArray()) -> void:
	_cell = cell_size
	_chunk = chunk_size
	_cells_per_chunk = chunk_size / cell_size
	_solid_lut = solid_lut

func update_chunk(chunk_coord: Vector2i, material_bytes: PackedByteArray) -> void:
	var tile := PackedByteArray()
	tile.resize(_cells_per_chunk * _cells_per_chunk)
	tile.fill(0)
	for cy in _cells_per_chunk:
		for cx in _cells_per_chunk:
			var solid := false
			var py0 := cy * _cell
			var px0 := cx * _cell
			for py in range(py0, py0 + _cell):
				var row := py * _chunk
				for px in range(px0, px0 + _cell):
					var mat: int = material_bytes[row + px]
					if mat >= 0 and mat < _solid_lut.size() and _solid_lut[mat] == 1:
						solid = true
						break
				if solid:
					break
			tile[cy * _cells_per_chunk + cx] = 1 if solid else 0
	_tiles[chunk_coord] = tile

func drop_chunk(chunk_coord: Vector2i) -> void:
	_tiles.erase(chunk_coord)

func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / _cell), floori(world_pos.y / _cell))

func is_solid_cell(cell: Vector2i) -> bool:
	var chunk := Vector2i(
		floori(float(cell.x) / _cells_per_chunk),
		floori(float(cell.y) / _cells_per_chunk)
	)
	var tile = _tiles.get(chunk, null)
	if tile == null:
		return false
	var lx: int = cell.x - chunk.x * _cells_per_chunk
	var ly: int = cell.y - chunk.y * _cells_per_chunk
	return tile[ly * _cells_per_chunk + lx] == 1

func is_solid_world(world_pos: Vector2) -> bool:
	return is_solid_cell(world_to_cell(world_pos))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_passability_grid.gd`
Expected: PASS (0 failed).

- [ ] **Step 5: Commit**

```bash
git add src/core/nav/passability_grid.gd tests/unit/test_passability_grid.gd
git commit -m "feat: PassabilityGrid coarse solid/open lookup from material tiles"
```

---

## Task 2: FlowField (double-buffered, time-sliced BFS)

**Files:**
- Create: `src/core/nav/flow_field.gd`
- Test: `tests/unit/test_flow_field.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_flow_field.gd`:

```gdscript
extends GdUnitTestSuite

const FlowField = preload("res://src/core/nav/flow_field.gd")

# Minimal grid stub matching the interface FlowField needs: is_solid_cell(cell).
class StubGrid:
	var solids: Dictionary = {}  # Vector2i -> true
	func set_solid(cell: Vector2i) -> void:
		solids[cell] = true
	func is_solid_cell(cell: Vector2i) -> bool:
		return solids.has(cell)

func _run_to_completion(field, grid) -> void:
	while field.is_building():
		field.step(grid)

func _dirs_equal(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not a[i].is_equal_approx(b[i]):
			return false
	return true

func test_center_has_no_flow() -> void:
	var grid := StubGrid.new()
	var f = FlowField.new(8, 6, 100000, 8, 999.0)
	f.begin_build(Vector2i(0, 0))
	_run_to_completion(f, grid)
	# Player cell -> zero flow (already at target).
	assert_vector(f.sample_direction(Vector2(0, 0))).is_equal(Vector2.ZERO)

func test_adjacent_points_toward_player() -> void:
	var grid := StubGrid.new()
	var f = FlowField.new(8, 6, 100000, 8, 999.0)
	f.begin_build(Vector2i(0, 0))
	_run_to_completion(f, grid)
	# Cell (1,0) is one cell right of the player; flow should push back toward -x.
	var dir := f.sample_direction(Vector2(8, 0))  # world pos in cell (1,0)
	assert_float(dir.x).is_less(0.0)

func test_routes_around_wall() -> void:
	# Vertical wall at x=2 for y in [-6..2], open gap at y in [3..6].
	var grid := StubGrid.new()
	for y in range(-6, 3):
		grid.set_solid(Vector2i(2, y))
	var f = FlowField.new(8, 6, 100000, 8, 999.0)
	f.begin_build(Vector2i(0, 0))
	_run_to_completion(f, grid)
	# The wall cell itself has no flow.
	assert_vector(f.sample_direction(Vector2(2 * 8, 0))).is_equal(Vector2.ZERO)
	# A cell on the far side of the wall is still reachable (routed around the gap).
	var far := f.sample_direction(Vector2(4 * 8, 0))  # cell (4,0)
	assert_bool(far != Vector2.ZERO).is_true()

func test_incremental_equals_one_shot() -> void:
	var grid := StubGrid.new()
	for y in range(-6, 3):
		grid.set_solid(Vector2i(2, y))
	# Tiny budget -> many steps.
	var f_inc = FlowField.new(8, 6, 5, 8, 999.0)
	f_inc.begin_build(Vector2i(0, 0))
	_run_to_completion(f_inc, grid)
	# Huge budget -> one step.
	var f_one = FlowField.new(8, 6, 100000, 8, 999.0)
	f_one.begin_build(Vector2i(0, 0))
	f_one.step(grid)
	assert_bool(f_one.is_building()).is_false()
	assert_bool(_dirs_equal(f_inc.live_dir(), f_one.live_dir())).is_true()

func test_idle_skip_and_rebuild_on_move() -> void:
	var grid := StubGrid.new()
	var f = FlowField.new(8, 6, 100000, 8, 3.0)
	f.update(grid, Vector2(0, 0), 0.0)          # first build (origin cell 0,0)
	assert_bool(f.is_building()).is_false()
	assert_bool(f.has_live()).is_true()
	f.update(grid, Vector2(0, 0), 0.1)          # stationary, fresh -> no rebuild
	assert_vector(f.live_origin_cell()).is_equal(Vector2i(0, 0))
	f.update(grid, Vector2(8 * 9, 0), 0.0)      # moved 9 cells (>=8) -> rebuild
	assert_vector(f.live_origin_cell()).is_equal(Vector2i(9, 0))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_flow_field.gd`
Expected: FAIL/parse error — `flow_field.gd` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `src/core/nav/flow_field.gd`:

```gdscript
class_name FlowField
extends RefCounted

# Shared, double-buffered, time-sliced BFS field of directions pointing toward
# the player. Enemies sample the LIVE buffer; a WORK buffer is filled a fixed
# budget of cells per frame, then swapped in when complete. Cost is flat per
# frame (no periodic stall).

var _cell: int
var _radius: int        # field half-size in cells
var _budget: int        # cells expanded per step()
var _move_thresh: int   # rebuild when player drifts this many cells
var _max_age: float     # rebuild when live field older than this (seconds)
var _D: int             # side length = 2*radius+1

# Live buffer (sampled by enemies)
var _has_live: bool = false
var _live_origin: Vector2i = Vector2i.ZERO
var _live_dir: PackedVector2Array = PackedVector2Array()
var _live_age: float = 0.0

# Work buffer (built incrementally)
var _building: bool = false
var _work_origin: Vector2i = Vector2i.ZERO
var _work_dir: PackedVector2Array = PackedVector2Array()
var _work_dist: PackedInt32Array = PackedInt32Array()
var _frontier: PackedInt32Array = PackedInt32Array()
var _head: int = 0

func _init(cell_size: int, radius_cells: int, cell_budget: int, move_thresh_cells: int, max_age_sec: float) -> void:
	_cell = cell_size
	_radius = radius_cells
	_budget = cell_budget
	_move_thresh = move_thresh_cells
	_max_age = max_age_sec
	_D = radius_cells * 2 + 1

func is_building() -> bool:
	return _building

func has_live() -> bool:
	return _has_live

func live_dir() -> PackedVector2Array:
	return _live_dir

func live_origin_cell() -> Vector2i:
	return _live_origin

func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / _cell), floori(world_pos.y / _cell))

func begin_build(origin_cell: Vector2i) -> void:
	_work_origin = origin_cell
	_work_dir = PackedVector2Array()
	_work_dir.resize(_D * _D)
	_work_dir.fill(Vector2.ZERO)
	_work_dist = PackedInt32Array()
	_work_dist.resize(_D * _D)
	_work_dist.fill(-1)
	_frontier = PackedInt32Array()
	_head = 0
	var center := _radius * _D + _radius
	_work_dist[center] = 0
	_frontier.append(center)
	_building = true

func step(grid) -> void:
	if not _building:
		return
	var processed := 0
	while _head < _frontier.size() and processed < _budget:
		var idx: int = _frontier[_head]
		_head += 1
		processed += 1
		var lx: int = idx % _D
		var ly: int = idx / _D
		var d: int = _work_dist[idx]
		for oy in [-1, 0, 1]:
			for ox in [-1, 0, 1]:
				if ox == 0 and oy == 0:
					continue
				var nx: int = lx + ox
				var ny: int = ly + oy
				if nx < 0 or ny < 0 or nx >= _D or ny >= _D:
					continue
				var nidx: int = ny * _D + nx
				if _work_dist[nidx] != -1:
					continue
				var wcell := Vector2i(_work_origin.x + (nx - _radius), _work_origin.y + (ny - _radius))
				if grid.is_solid_cell(wcell):
					_work_dist[nidx] = -2  # solid: visited, never enqueued, no flow
					continue
				_work_dist[nidx] = d + 1
				# Direction points from the neighbor back toward the current cell,
				# which is one step closer to the player.
				_work_dir[nidx] = Vector2(lx - nx, ly - ny).normalized()
				_frontier.append(nidx)
	if _head >= _frontier.size():
		_finish_build()

func _finish_build() -> void:
	_live_dir = _work_dir
	_live_origin = _work_origin
	_has_live = true
	_live_age = 0.0
	_building = false

func update(grid, player_world_pos: Vector2, delta: float) -> void:
	if _has_live:
		_live_age += delta
	if _building:
		step(grid)
		return
	var pcell := world_to_cell(player_world_pos)
	var need := false
	if not _has_live:
		need = true
	elif _live_age >= _max_age:
		need = true
	elif absi(pcell.x - _live_origin.x) + absi(pcell.y - _live_origin.y) >= _move_thresh:
		need = true
	if need:
		begin_build(pcell)
		step(grid)

func sample_direction(world_pos: Vector2) -> Vector2:
	if not _has_live:
		return Vector2.ZERO
	var cell := world_to_cell(world_pos)
	var lx: int = cell.x - _live_origin.x + _radius
	var ly: int = cell.y - _live_origin.y + _radius
	if lx < 0 or ly < 0 or lx >= _D or ly >= _D:
		return Vector2.ZERO
	return _live_dir[ly * _D + lx]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_flow_field.gd`
Expected: PASS (0 failed). All five cases pass, including `test_incremental_equals_one_shot` (time-sliced output equals one-shot BFS).

- [ ] **Step 5: Commit**

```bash
git add src/core/nav/flow_field.gd tests/unit/test_flow_field.gd
git commit -m "feat: FlowField double-buffered time-sliced BFS toward player"
```

---

## Task 3: NavField glue + WorldManager wiring

**Files:**
- Create: `src/core/nav/nav_field.gd`
- Modify: `src/core/world_manager.gd` (member at line ~27, `_ready` end ~82, `mark_terrain_dirty` ~84-86, `_process` ~94-104)
- Test: `tests/unit/test_nav_field.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_nav_field.gd`:

```gdscript
extends GdUnitTestSuite

const NavField = preload("res://src/core/nav/nav_field.gd")

# Stub world manager exposing read_region, the only WorldManager method NavField
# calls. Returns a fixed 256x256 material region.
class StubWM extends Node:
	var region: PackedByteArray
	func read_region(_rect: Rect2i) -> PackedByteArray:
		return region

func _region_all(mat: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(256 * 256)
	b.fill(mat)
	return b

func test_dirty_chunk_becomes_solid_after_update() -> void:
	var wm := auto_free(StubWM.new())
	add_child(wm)
	# Fill chunk (0,0) entirely with a colliding material (stone).
	wm.region = _region_all(MaterialRegistry.MAT_STONE)
	var nav = NavField.new(wm)
	nav.mark_dirty(Vector2i(0, 0))
	nav.update(Vector2(0, 0), 0.0)   # drains the tile via read_region
	assert_bool(nav.is_solid_world(Vector2(4, 4))).is_true()

func test_air_chunk_is_open() -> void:
	var wm := auto_free(StubWM.new())
	add_child(wm)
	wm.region = _region_all(MaterialRegistry.MAT_AIR)
	var nav = NavField.new(wm)
	nav.mark_dirty(Vector2i(0, 0))
	nav.update(Vector2(0, 0), 0.0)
	assert_bool(nav.is_solid_world(Vector2(4, 4))).is_false()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_nav_field.gd`
Expected: FAIL/parse error — `nav_field.gd` does not exist.

- [ ] **Step 3a: Write NavField**

Create `src/core/nav/nav_field.gd`:

```gdscript
class_name NavField
extends RefCounted

# Glue that owns the passability grid + flow field, refreshes grid tiles for
# dirty chunks via WorldManager.read_region, and ticks the field each frame.

const CELL := 8
const CHUNK := 256
const REGION_RADIUS_CELLS := 48     # field half-size: 48*8 = 384px around player
const TILE_BUDGET := 2              # dirty chunk tiles rebuilt per update
const FLOW_BUDGET := 160            # cells expanded per field step
const MOVE_THRESHOLD_CELLS := 8     # rebuild field when player drifts >= this
const MAX_LIVE_AGE := 3.0           # rebuild field when older than this (sec)

var _world_manager
var grid: PassabilityGrid
var flow: FlowField
var _dirty: Dictionary = {}         # Vector2i chunk coord -> true

func _init(world_manager) -> void:
	_world_manager = world_manager
	grid = PassabilityGrid.new(CELL, CHUNK, _build_solid_lut())
	flow = FlowField.new(CELL, REGION_RADIUS_CELLS, FLOW_BUDGET, MOVE_THRESHOLD_CELLS, MAX_LIVE_AGE)

func _build_solid_lut() -> PackedByteArray:
	var n: int = MaterialRegistry.materials.size()
	var lut := PackedByteArray()
	lut.resize(n)
	for i in n:
		lut[i] = 1 if MaterialRegistry.has_collider(i) else 0
	return lut

func mark_dirty(chunk_coord: Vector2i) -> void:
	_dirty[chunk_coord] = true

func update(player_world_pos: Vector2, delta: float) -> void:
	_drain_tiles()
	flow.update(grid, player_world_pos, delta)

func _drain_tiles() -> void:
	var done := 0
	for coord in _dirty.keys():
		if done >= TILE_BUDGET:
			break
		var origin: Vector2i = coord * CHUNK
		var bytes: PackedByteArray = _world_manager.read_region(Rect2i(origin, Vector2i(CHUNK, CHUNK)))
		grid.update_chunk(coord, bytes)
		_dirty.erase(coord)
		done += 1

func sample_direction(world_pos: Vector2) -> Vector2:
	return flow.sample_direction(world_pos)

func is_solid_world(world_pos: Vector2) -> bool:
	return grid.is_solid_world(world_pos)
```

- [ ] **Step 3b: Run the NavField test (passes before WorldManager wiring)**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_nav_field.gd`
Expected: PASS (0 failed).

- [ ] **Step 3c: Wire NavField into WorldManager**

In `src/core/world_manager.gd`, add the member next to `swarm_grid` (line ~27):

```gdscript
var nav_field  # NavField
```

At the end of `_ready()` (after `TerrainSurface.register_adapter(self)`), create it:

```gdscript
	nav_field = preload("res://src/core/nav/nav_field.gd").new(self)
```

In `mark_terrain_dirty(coord)` (currently lines 84-86), also notify the nav field:

```gdscript
func mark_terrain_dirty(coord: Vector2i) -> void:
	if _collision_helper != null:
		_collision_helper.mark_dirty(coord)
	if nav_field != null:
		nav_field.mark_dirty(coord)
```

In `_process(delta)`, after `_collision_helper.rebuild_dirty(chunks, delta)` (line 100), tick the field:

```gdscript
	if nav_field != null:
		nav_field.update(tracking_position, delta)
```

- [ ] **Step 4: Run the existing world manager test to confirm no regression**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_world_manager_chunk_budget.gd`
Expected: PASS (0 failed). (This test exercises `_select_new_chunks`, unaffected by the wiring; it confirms the file still parses and loads.)

- [ ] **Step 5: Commit**

```bash
git add src/core/nav/nav_field.gd tests/unit/test_nav_field.gd src/core/world_manager.gd
git commit -m "feat: NavField glue; WorldManager owns and ticks the nav field"
```

---

## Task 4: Enemy pursuit + wall clamp

**Files:**
- Modify: `src/enemies/enemy.gd` — vars (~48-66), `_physics_process` (line 200), `_process_chase` (lines 241-263), `_can_see_player` (lines 390-398), add helpers.
- Modify: `scenes/enemies/enemy.tscn` — `collision_mask` 1 → 0.
- Test: `tests/unit/test_enemy_pursuit.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_enemy_pursuit.gd`:

```gdscript
extends GdUnitTestSuite

# Mock enemy with controllable line-of-sight, matching the MockEnemy pattern in
# test_enemy_state_machine.gd.
class MockEnemy extends Enemy:
	var can_see: bool = true
	func _can_see_player() -> bool:
		return can_see

# Stub nav field: fixed sample direction, and solid when x >= solid_x.
class StubFlow:
	var dir: Vector2 = Vector2.ZERO
	var solid_x: float = 1.0e9
	func sample_direction(_p: Vector2) -> Vector2:
		return dir
	func is_solid_world(p: Vector2) -> bool:
		return p.x >= solid_x

# Stub world manager Node holding a nav_field and a null swarm_grid (so
# _apply_separation passes the direction through unchanged).
class StubWM extends Node:
	var nav_field
	var swarm_grid = null

func _make_enemy() -> MockEnemy:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	return e

func _make_player(e: MockEnemy, pos: Vector2) -> void:
	e._player_ref = Node2D.new()
	add_child(e._player_ref)
	e._player_ref.global_position = pos

func test_follows_field_when_los_blocked() -> void:
	var e := _make_enemy()
	e._state = Enemy.State.CHASE
	e._aggroed = true
	e.can_see = false
	_make_player(e, Vector2(50, 0))          # within leash, but unseen
	var flow := StubFlow.new()
	flow.dir = Vector2(0, 1)                  # field says go down (around a wall)
	var wm := auto_free(StubWM.new())
	wm.nav_field = flow
	add_child(wm)
	e._world_manager = wm
	e._process_chase(0.1)
	assert_bool(e.velocity.y > 0.0).is_true()
	assert_float(absf(e.velocity.x)).is_less(1.0)

func test_direct_steer_when_seen() -> void:
	var e := _make_enemy()
	e._state = Enemy.State.CHASE
	e.can_see = true
	_make_player(e, Vector2(100, 0))          # straight to the right
	e._world_manager = null                    # field unused when seen
	e._process_chase(0.1)
	assert_bool(e.velocity.x > 0.0).is_true()
	assert_float(absf(e.velocity.y)).is_less(1.0)

func test_deaggro_past_leash() -> void:
	var e := _make_enemy()
	e._state = Enemy.State.CHASE
	e._aggroed = true
	e.can_see = false
	e.leash_radius = 280.0
	_make_player(e, Vector2(400, 0))          # beyond leash
	e._process_chase(0.1)
	assert_that(e._state).is_equal(Enemy.State.WANDER)
	assert_bool(e._aggroed).is_false()

func test_unseen_and_unaggroed_reverts() -> void:
	# Sight-to-acquire: a target never seen and currently blocked does not commit.
	var e := _make_enemy()
	e._state = Enemy.State.CHASE
	e._aggroed = false
	e.can_see = false
	_make_player(e, Vector2(50, 0))           # within leash but unseen, not aggroed
	e._process_chase(0.1)
	assert_that(e._state).is_equal(Enemy.State.WANDER)

func test_clamp_blocks_into_wall_allows_slide() -> void:
	var e := _make_enemy()
	e.global_position = Vector2(0, 0)
	e.velocity = Vector2(100, 100)            # heads into +x wall, +y open
	var flow := StubFlow.new()
	flow.solid_x = 8.0                         # anything x >= 8 is solid
	var wm := auto_free(StubWM.new())
	wm.nav_field = flow
	add_child(wm)
	e._world_manager = wm
	e._move_with_clamp(0.1)                    # target (10,10): x blocked, y allowed
	assert_float(e.global_position.x).is_equal(0.0)
	assert_float(e.global_position.y).is_equal(10.0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_enemy_pursuit.gd`
Expected: FAIL — `leash_radius`, `_aggroed`, `_move_with_clamp`, and the new `_process_chase` behavior do not exist yet.

- [ ] **Step 3a: Add the pursuit state fields**

In `src/enemies/enemy.gd`, add to the `@export` block (after line 21, `min_attack_settle_time`):

```gdscript
@export var leash_radius: float = 280.0
```

Add to the state var block (after line 56, `_player_in_range`):

```gdscript
var _aggroed: bool = false
```

- [ ] **Step 3b: Guard `_can_see_player` for headless / out-of-tree use**

Replace the body of `_can_see_player()` (lines 390-398) so a missing world cannot crash:

```gdscript
func _can_see_player() -> bool:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return false
	if not is_inside_tree():
		return false
	var world := get_world_2d()
	if world == null:
		return false
	var space_state := world.direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, _player_ref.global_position)
	query.collision_mask = 1
	query.exclude = [self, _player_ref]
	var result := space_state.intersect_ray(query)
	return result.is_empty()
```

- [ ] **Step 3c: Rewrite `_process_chase` with sight-to-acquire + sticky leash + field fallback**

Replace `_process_chase` (lines 241-263) with:

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
		# Sight-to-acquire: never seen the player and currently blocked — don't commit.
		_change_state(State.WANDER)
		return

	# Sticky pursuit: give up only once the player escapes the leash radius.
	if dist > leash_radius:
		_aggroed = false
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

	move_dir = _apply_separation(move_dir)
	velocity = move_dir * _get_effective_speed()

	if sees and dist <= _attack_range and _settle_timer >= min_attack_settle_time:
		velocity = Vector2.ZERO
		_change_state(State.WINDUP)
```

- [ ] **Step 3d: Add nav-field helpers and the clamp**

Add these methods to `src/enemies/enemy.gd` (e.g. just after `_apply_separation`, around line 342):

```gdscript
func _nav_field_dir() -> Vector2:
	if _world_manager == null or not is_instance_valid(_world_manager):
		return Vector2.ZERO
	var nf = _world_manager.get("nav_field")
	if nf == null:
		return Vector2.ZERO
	return nf.sample_direction(global_position)


func _is_blocked(pos: Vector2) -> bool:
	if _world_manager == null or not is_instance_valid(_world_manager):
		return false
	var nf = _world_manager.get("nav_field")
	if nf == null:
		return false
	return nf.is_solid_world(pos)


func _move_with_clamp(delta: float) -> void:
	var target := global_position + velocity * delta
	if _is_blocked(Vector2(target.x, global_position.y)):
		target.x = global_position.x
	if _is_blocked(Vector2(global_position.x, target.y)):
		target.y = global_position.y
	global_position = target
```

- [ ] **Step 3e: Replace physics movement with the clamp**

In `_physics_process` (line 199-200), replace:

```gdscript
	if _state == State.WANDER or _state == State.CHASE or _state == State.HURT:
		move_and_slide()
```

with:

```gdscript
	if _state == State.WANDER or _state == State.CHASE or _state == State.HURT:
		_move_with_clamp(delta)
```

- [ ] **Step 3f: Drop enemy terrain collision mask in the scene**

In `scenes/enemies/enemy.tscn`, change the `Enemy` node's `collision_mask` from `1` to `0` (terrain physics for enemies is now handled by the grid clamp, not the physics engine):

```
[node name="Enemy" type="CharacterBody2D" unique_id=693161229]
collision_layer = 132
collision_mask = 0
script = ExtResource("1")
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_enemy_pursuit.gd`
Expected: PASS (0 failed).

Then confirm the existing enemy suites still pass:

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_enemy_state_machine.gd`
Expected: PASS (0 failed). (`test_transitions_to_chase_when_player_in_range` still enters CHASE via `_process_idle`; `test_transitions_to_wander_when_player_leaves` still reverts — now because the enemy is unseen and not aggroed.)

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_enemy_aggression.gd`
Expected: PASS (0 failed).

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_melee_enemy.gd`
Expected: PASS (0 failed).

- [ ] **Step 5: Commit**

```bash
git add src/enemies/enemy.gd scenes/enemies/enemy.tscn tests/unit/test_enemy_pursuit.gd
git commit -m "feat: enemies route around walls via flow field + grid-clamp wall collision"
```

---

## Task 5: Full suite verification

**Files:** none (verification only)

- [ ] **Step 1: Run the entire unit test directory**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit`
Expected: PASS — 0 failed, 0 errors across all suites.

- [ ] **Step 2: Manual in-editor smoke check (record result)**

Launch the game, spawn enemies near a wall, and confirm:
- Enemies no longer pass through walls (they slide along them).
- An enemy that sees the player, then loses line-of-sight behind a wall, keeps pursuing and rounds the corner instead of reverting to wander immediately.
- No periodic frame hitch every few seconds (the field build is spread per-frame).

Note the observed result in the PR/commit description. If any check fails, file the discrepancy rather than asserting success.

- [ ] **Step 3: Commit any fixups**

```bash
git add -A
git commit -m "test: enemy navigation full-suite verification"
```

---

## Self-Review Notes

- **Spec coverage:** PassabilityGrid (Task 1), FlowField double-buffered/time-sliced/idle-skip (Task 2), NavField + WorldManager tick + dirty wiring (Task 3), sight-to-acquire + sticky leash + LOS-direct/field-fallback + axis-slide clamp + `collision_mask=0` (Task 4). Incremental-equals-one-shot test present (Task 2). Non-goals (hazards, ghost variants, wander pathfinding, threading) are intentionally untouched.
- **Type consistency:** `is_solid_cell`/`is_solid_world`/`world_to_cell` (PassabilityGrid) match FlowField's `grid.is_solid_cell` call and enemy/NavField's `is_solid_world`. `sample_direction`, `is_building`, `step`, `begin_build`, `update`, `live_dir`, `live_origin_cell`, `has_live` (FlowField) match their test and NavField call sites. `nav_field`, `mark_dirty`, `update`, `sample_direction`, `is_solid_world` (NavField) match WorldManager and enemy call sites. Enemy adds `leash_radius`, `_aggroed`, `_nav_field_dir`, `_is_blocked`, `_move_with_clamp`.
- **No placeholders:** every code step shows complete code; every test step shows the exact run command and expected outcome.
```
