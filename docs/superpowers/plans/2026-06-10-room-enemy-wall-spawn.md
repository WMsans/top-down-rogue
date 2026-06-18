# Room Enemy Wall-Spawn Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop room-template enemies from spawning inside solid terrain by validating each enemy marker against the actual terrain material and nudging it to nearby open space (or skipping it when boxed in).

**Architecture:** Extract the existing "is this footprint all-air?" check from `cave_spawner` into a shared `SpawnValidation` static helper. `spawn_dispatcher` uses that helper inside a new spiral search (`_resolve_clear_position`) to relocate enemy markers (types 1 and 2) before spawning. Boss markers (6) and all non-enemy markers are unchanged.

**Tech Stack:** Godot 4 / GDScript, gdUnit4 for unit tests. Tests run with `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a <test-file>`.

**Spec:** `docs/superpowers/specs/2026-06-10-room-enemy-wall-spawn-design.md`

---

## File Structure

- **Create:** `src/core/spawn_validation.gd` — `SpawnValidation` static helper, single responsibility: read a square footprint and report whether every cell is `MAT_AIR`.
- **Create:** `tests/unit/test_spawn_validation.gd` — unit tests for `footprint_clear`.
- **Modify:** `src/core/cave_spawner.gd` — `_is_clear_of_walls` delegates to the shared helper (behavior unchanged).
- **Modify:** `src/core/spawn_dispatcher.gd` — add `_resolve_clear_position` + `_spawn_enemy_validated`; route enemy markers through validation.
- **Modify:** `tests/unit/test_spawn_dispatcher.gd` (new file) — unit tests for the spiral relocation.

A note on `MaterialRegistry.MAT_AIR`: it is an autoload property resolved at startup. gdUnit4 runs project autoloads, so tests reference `MaterialRegistry.MAT_AIR` directly and derive a guaranteed-different "solid" byte as `(MaterialRegistry.MAT_AIR + 1) % 256`.

---

## Task 1: Shared `SpawnValidation.footprint_clear` helper

**Files:**
- Create: `src/core/spawn_validation.gd`
- Test: `tests/unit/test_spawn_validation.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_spawn_validation.gd`:

```gdscript
extends GdUnitTestSuite

const _SpawnValidation = preload("res://src/core/spawn_validation.gd")

# Stub world_manager: read_region fills the requested rect from a solid-cell set.
# Air cells use MAT_AIR; solid cells use a guaranteed-different byte.
class StubWM extends RefCounted:
	var solid_cells: Dictionary = {}      # Vector2i -> true
	var force_wrong_size: bool = false
	var force_oob_byte: int = -1          # if >=0, fill entire region with this byte

	func read_region(rect: Rect2i) -> PackedByteArray:
		var air := MaterialRegistry.MAT_AIR
		var solid := (air + 1) % 256
		var data := PackedByteArray()
		var count := rect.size.x * rect.size.y
		if force_wrong_size:
			data.resize(count - 1)
			data.fill(air)
			return data
		data.resize(count)
		for y in range(rect.size.y):
			for x in range(rect.size.x):
				var cell := Vector2i(rect.position.x + x, rect.position.y + y)
				var idx := y * rect.size.x + x
				if force_oob_byte >= 0:
					data[idx] = force_oob_byte
				elif solid_cells.has(cell):
					data[idx] = solid
				else:
					data[idx] = air
		return data


func test_all_air_is_clear() -> void:
	var wm := StubWM.new()
	assert_bool(_SpawnValidation.footprint_clear(wm, Vector2(100, 100))).is_true()


func test_single_solid_cell_in_footprint_is_not_clear() -> void:
	var wm := StubWM.new()
	wm.solid_cells[Vector2i(100, 100)] = true   # dead-center of the footprint
	assert_bool(_SpawnValidation.footprint_clear(wm, Vector2(100, 100))).is_false()


func test_out_of_chunk_byte_is_not_clear() -> void:
	var wm := StubWM.new()
	wm.force_oob_byte = 255                       # 255 marks cells outside any chunk
	assert_bool(_SpawnValidation.footprint_clear(wm, Vector2(100, 100))).is_false()


func test_wrong_size_read_is_not_clear() -> void:
	var wm := StubWM.new()
	wm.force_wrong_size = true
	assert_bool(_SpawnValidation.footprint_clear(wm, Vector2(100, 100))).is_false()


func test_null_world_manager_is_not_clear() -> void:
	assert_bool(_SpawnValidation.footprint_clear(null, Vector2(100, 100))).is_false()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_spawn_validation.gd`
Expected: FAIL — cannot load `res://src/core/spawn_validation.gd` (file does not exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `src/core/spawn_validation.gd`:

```gdscript
class_name SpawnValidation
extends RefCounted

# Shared spawn-position validation. A position is "clear" when every cell in a
# square footprint centered on it is MAT_AIR. Reads actual chunk material via
# world_manager.read_region (same source as player-spawn validation), not the
# async terrain_physical probe cache. Cells outside any active chunk read as 255
# and count as NOT clear, so callers never spawn into unloaded terrain.

const DEFAULT_HALF: int = 6   # 13x13 footprint ~= enemy body; matches cave_spawner

static func footprint_clear(world_manager, world_pos: Vector2, half: int = DEFAULT_HALF) -> bool:
	if world_manager == null or not is_instance_valid(world_manager):
		return false
	var origin := Vector2i(int(floor(world_pos.x)) - half, int(floor(world_pos.y)) - half)
	var side := half * 2 + 1
	var data: PackedByteArray = world_manager.read_region(Rect2i(origin, Vector2i(side, side)))
	if data.size() != side * side:
		return false
	var air := MaterialRegistry.MAT_AIR
	for i in range(data.size()):
		if data[i] != air:
			return false
	return true
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_spawn_validation.gd`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add src/core/spawn_validation.gd tests/unit/test_spawn_validation.gd
git commit -m "feat: shared SpawnValidation.footprint_clear helper"
```

---

## Task 2: Delegate `cave_spawner._is_clear_of_walls` to the shared helper

This is a refactor — behavior must stay identical. `cave_spawner` keeps its own `SPAWN_CLEAR_HALF` constant and passes it through.

**Files:**
- Modify: `src/core/cave_spawner.gd:175-190` (the `_is_clear_of_walls` body)

- [ ] **Step 1: Replace the method body**

In `src/core/cave_spawner.gd`, replace the entire `_is_clear_of_walls` function (currently `src/core/cave_spawner.gd:175-190`, including its leading comment block at `:171-174`) with:

```gdscript
# Ensure the spawn position's footprint contains only air. Delegates to the
# shared SpawnValidation helper so the room path (spawn_dispatcher) and the
# cave path cannot drift apart.
func _is_clear_of_walls(world_pos: Vector2) -> bool:
	return SpawnValidation.footprint_clear(_world_manager, world_pos, SPAWN_CLEAR_HALF)
```

Leave `const SPAWN_CLEAR_HALF: int = 6` (`src/core/cave_spawner.gd:133`) exactly as-is.

- [ ] **Step 2: Run the existing cave_spawner tests to verify no regression**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_cave_spawner.gd`
Expected: PASS — all existing tests still green (validation behavior is unchanged).

- [ ] **Step 3: Commit**

```bash
git add src/core/cave_spawner.gd
git commit -m "refactor: cave_spawner reuses SpawnValidation.footprint_clear"
```

---

## Task 3: Spiral relocation `_resolve_clear_position` in `spawn_dispatcher`

**Files:**
- Modify: `src/core/spawn_dispatcher.gd` (add constants + method near `_spawn_enemy`)
- Test: `tests/unit/test_spawn_dispatcher.gd` (new)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_spawn_dispatcher.gd`:

```gdscript
extends GdUnitTestSuite

const _SpawnDispatcher = preload("res://src/core/spawn_dispatcher.gd")

# Same stub shape as test_spawn_validation: read_region answers from a solid set.
class StubWM extends RefCounted:
	var solid_cells: Dictionary = {}   # Vector2i -> true

	func read_region(rect: Rect2i) -> PackedByteArray:
		var air := MaterialRegistry.MAT_AIR
		var solid := (air + 1) % 256
		var data := PackedByteArray()
		data.resize(rect.size.x * rect.size.y)
		for y in range(rect.size.y):
			for x in range(rect.size.x):
				var cell := Vector2i(rect.position.x + x, rect.position.y + y)
				data[y * rect.size.x + x] = solid if solid_cells.has(cell) else air
		return data


func _make_dispatcher(wm) -> Node:
	var d = _SpawnDispatcher.new()
	d._world_manager = wm
	return d


func test_clear_position_returned_unchanged() -> void:
	var wm := StubWM.new()                       # all air
	var d := _make_dispatcher(wm)
	var pos := Vector2(200, 200)
	assert_vector(d._resolve_clear_position(pos)).is_equal(pos)
	d.free()


func test_blocked_marker_nudges_to_nearby_air() -> void:
	var wm := StubWM.new()
	# Wall band to the LEFT of center: x in [center-6 .. center-2] across the
	# vertical span. This intersects the center footprint (x from center-6) but
	# not a footprint shifted +8 on x (x from center+2), leaving open space to
	# the right within one ring.
	for dx in range(-6, -1):
		for dy in range(-10, 11):
			wm.solid_cells[Vector2i(200 + dx, 200 + dy)] = true
	var d := _make_dispatcher(wm)
	var result = d._resolve_clear_position(Vector2(200, 200))
	assert_that(result).is_not_null()
	# The chosen spot must itself be clear and within the search radius.
	assert_bool(SpawnValidation.footprint_clear(wm, result)).is_true()
	assert_float((result as Vector2).distance_to(Vector2(200, 200))) \
		.is_less_equal(float(d.NUDGE_MAX_RINGS * d.NUDGE_CELL) * 1.5)
	d.free()


func test_fully_enclosed_marker_returns_null() -> void:
	var wm := StubWM.new()
	# Solidify everything within the search radius + footprint reach.
	var reach := 6 + (3 * 8) + 2
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			wm.solid_cells[Vector2i(200 + dx, 200 + dy)] = true
	var d := _make_dispatcher(wm)
	assert_that(d._resolve_clear_position(Vector2(200, 200))).is_null()
	d.free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_spawn_dispatcher.gd`
Expected: FAIL — `_resolve_clear_position` / `NUDGE_MAX_RINGS` / `NUDGE_CELL` do not exist yet.

- [ ] **Step 3: Add constants and the spiral method**

In `src/core/spawn_dispatcher.gd`, add these constants next to the existing `const CHUNK_SIZE := 256` (`src/core/spawn_dispatcher.gd:15`):

```gdscript
const NUDGE_CELL: int = 8       # search step, one passability cell
const NUDGE_MAX_RINGS: int = 3  # outward search radius ~= 24px
```

Then add this method directly above `func _spawn_enemy(` (`src/core/spawn_dispatcher.gd:135`):

```gdscript
# Returns world_pos unchanged when its footprint is clear; otherwise the nearest
# clear position within NUDGE_MAX_RINGS rings; otherwise null (caller skips).
func _resolve_clear_position(world_pos: Vector2) -> Variant:
	if SpawnValidation.footprint_clear(_world_manager, world_pos):
		return world_pos
	for ring in range(1, NUDGE_MAX_RINGS + 1):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if abs(dx) != ring and abs(dy) != ring:
					continue  # interior cells were covered by smaller rings
				var cand := world_pos + Vector2(dx * NUDGE_CELL, dy * NUDGE_CELL)
				if SpawnValidation.footprint_clear(_world_manager, cand):
					return cand
	return null
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_spawn_dispatcher.gd`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/core/spawn_dispatcher.gd tests/unit/test_spawn_dispatcher.gd
git commit -m "feat: spawn_dispatcher spiral relocation for blocked markers"
```

---

## Task 4: Route enemy markers through validation

Wire markers 1 (normal) and 2 (elite) through the new relocation. Boss (6) and all non-enemy markers stay on their existing direct path.

**Files:**
- Modify: `src/core/spawn_dispatcher.gd:123-133` (`_spawn_entity`)
- Modify: `src/core/spawn_dispatcher.gd` (add `_spawn_enemy_validated` above `_spawn_enemy`)

- [ ] **Step 1: Add the validated wrapper**

In `src/core/spawn_dispatcher.gd`, add this method directly above `func _spawn_enemy(` (and above the `_resolve_clear_position` added in Task 3 is fine too — order is not significant):

```gdscript
# Enemy spawn that first relocates the marker out of any wall. Skips the spawn
# entirely when no clear spot exists within the search radius.
func _spawn_enemy_validated(world_pos: Vector2, sector_dist: int, floor_num: int, is_boss: bool, is_elite: bool) -> void:
	var resolved: Variant = _resolve_clear_position(world_pos)
	if resolved == null:
		return
	_spawn_enemy(resolved, sector_dist, floor_num, is_boss, is_elite)
```

- [ ] **Step 2: Re-route markers 1 and 2 in `_spawn_entity`**

In `src/core/spawn_dispatcher.gd`, change the `match marker` block in `_spawn_entity` (`src/core/spawn_dispatcher.gd:124-132`). Replace only the marker `1` and marker `2` lines:

Before:
```gdscript
		1: _spawn_enemy(world_pos, sector_dist, floor_num, false, false)
		2: _spawn_enemy(world_pos, sector_dist, floor_num, false, true)
```

After:
```gdscript
		1: _spawn_enemy_validated(world_pos, sector_dist, floor_num, false, false)
		2: _spawn_enemy_validated(world_pos, sector_dist, floor_num, false, true)
```

Leave marker `6` (`_spawn_enemy(world_pos, sector_dist, floor_num, true, false)`) and every other case unchanged.

- [ ] **Step 3: Run the full unit suite to confirm nothing broke**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit`
Expected: PASS — including `test_spawn_validation.gd`, `test_spawn_dispatcher.gd`, and `test_cave_spawner.gd`.

- [ ] **Step 4: Commit**

```bash
git add src/core/spawn_dispatcher.gd
git commit -m "fix: room enemy markers nudged out of walls, boss spawns unchanged"
```

---

## Manual verification (after all tasks)

Unit tests cover the helper and the spiral. The end-to-end wiring (markers → relocation → spawn) is best confirmed in-engine:

1. Launch the project and enter a floor with template rooms.
2. Watch enemy spawns at room entry — none should appear embedded in wall pixels.
3. Confirm boss arenas still spawn the boss at its authored center (unchanged).

If an automated integration check is desired later, it would need a loaded world + real `read_region`, which is out of scope for these unit-level tests.

---

## Self-Review Notes

- **Spec coverage:** shared helper (Task 1) ↔ spec §3; cave_spawner delegation (Task 2) ↔ spec §3; spiral nudge-else-skip (Task 3) ↔ spec §2; enemy-only routing with boss excluded (Task 4) ↔ spec Scope. Edge cases (air fast-path, adjacent-air nudge, boxed-in skip, out-of-chunk) covered by Task 1 + Task 3 tests.
- **Naming consistency:** `footprint_clear`, `_resolve_clear_position`, `_spawn_enemy_validated`, `NUDGE_CELL`, `NUDGE_MAX_RINGS`, `DEFAULT_HALF`, `SPAWN_CLEAR_HALF` are used identically across every task and test.
- **No placeholders:** every code and test step is complete.
