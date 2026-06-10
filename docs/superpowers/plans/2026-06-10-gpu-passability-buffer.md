# GPU Passability Buffer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate NavField's per-dirty-chunk 262 KB GPU readback and 65,536-pixel GDScript downsample by having the existing collider compute pass emit a 32×32 solidity grid that the collision helper feeds straight into the nav grid.

**Architecture:** The `collider.glsl` dispatch already runs over every dirty chunk at 128×128 invocations. We add a second storage buffer; the invocation owning each 8px cell samples its 8×8 pixel block and writes a solid/open byte. `TerrainCollisionHelper`, which already reads the coalesced collider buffer, decodes the passability tile and calls `NavField.grid.set_tile()`. NavField then drops its dirty-tracking, `read_region` call, and CPU downsample from the live loop.

**Tech Stack:** Godot 4 (GDScript), GLSL compute shaders via `RenderingDevice`, gdUnit4 for unit tests.

**Spec:** `docs/superpowers/specs/2026-06-10-gpu-passability-buffer-design.md`

---

## File Structure

- **Create** `tests/unit/test_passability_set_tile.gd` — unit test for `PassabilityGrid.set_tile`.
- **Create** `tests/unit/test_passability_decode.gd` — unit test for `ComputeDevice.decode_passability_slice`.
- **Modify** `src/core/nav/passability_grid.gd` — add `set_tile`.
- **Modify** `src/core/compute_device.gd` — passability buffer constants/decls, `decode_passability_slice`, init/free, dual readback in `read_collider_buffer_coalesced`.
- **Modify** `shaders/compute/collider.glsl` — binding 2 + passability write block.
- **Modify** `src/core/chunk_manager.gd` — bind passability buffer in collider uniform set; drop nav tile on chunk unload.
- **Modify** `src/core/terrain_collision_helper.gd` — consume new readback shape, feed nav grid.
- **Modify** `src/core/nav/nav_field.gd` — remove dirty/drain/read_region; slim `update`.
- **Modify** `src/core/world_manager.gd` — stop marking nav dirty.
- **Modify** `tests/unit/test_nav_field.gd` — rewrite for the GPU-tile path.
- **Modify** `tests/unit/test_terrain_collision_helper.gd` — update fakes for the new readback shape.

## Test runner

gdUnit4 CLI. Each unit test runs headless:

```bash
GODOT_BIN=$(command -v godot) addons/gdUnit4/runtest.sh -a tests/unit/<file>.gd
```

If `godot` is not on `PATH`, set `GODOT_BIN` to the Godot 4 binary explicitly. GPU-path tasks (Tasks 3–4) can't be unit-tested without a `RenderingDevice`; they use a manual launch instead.

---

## Task 1: `PassabilityGrid.set_tile`

Store a pre-downsampled 32×32 solidity tile directly, bypassing the CPU downsample.

**Files:**
- Create: `tests/unit/test_passability_set_tile.gd`
- Modify: `src/core/nav/passability_grid.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_passability_set_tile.gd`:

```gdscript
extends GdUnitTestSuite

const PassabilityGrid = preload("res://src/core/nav/passability_grid.gd")

# 32x32 cells per 256px chunk at 8px cells. value 1 = solid.
func _tile(solid_cells: Array) -> PackedByteArray:
	var t := PackedByteArray()
	t.resize(32 * 32)
	t.fill(0)
	for c: Vector2i in solid_cells:
		t[c.y * 32 + c.x] = 1
	return t

func test_set_tile_marks_cell_solid() -> void:
	var g = PassabilityGrid.new(8, 256, PackedByteArray())
	g.set_tile(Vector2i(0, 0), _tile([Vector2i(1, 1)]))
	assert_bool(g.is_solid_world(Vector2(8, 8))).is_true()    # cell (1,1)
	assert_bool(g.is_solid_world(Vector2(0, 0))).is_false()   # cell (0,0)

func test_set_tile_negative_chunk() -> void:
	var g = PassabilityGrid.new(8, 256, PackedByteArray())
	# chunk (-1,-1) local cell (31,31) -> world px (-8,-8)
	g.set_tile(Vector2i(-1, -1), _tile([Vector2i(31, 31)]))
	assert_bool(g.is_solid_world(Vector2(-8, -8))).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=$(command -v godot) addons/gdUnit4/runtest.sh -a tests/unit/test_passability_set_tile.gd`
Expected: FAIL — `Invalid call. Nonexistent function 'set_tile'`.

- [ ] **Step 3: Add `set_tile`**

In `src/core/nav/passability_grid.gd`, after `update_chunk` (ends at line 40), add:

```gdscript
func set_tile(chunk_coord: Vector2i, tile: PackedByteArray) -> void:
	# tile is a pre-downsampled _cells_per_chunk^2 grid (1 = solid), the same
	# format update_chunk produces — used by the GPU passability path.
	_tiles[chunk_coord] = tile
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=$(command -v godot) addons/gdUnit4/runtest.sh -a tests/unit/test_passability_set_tile.gd`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/core/nav/passability_grid.gd tests/unit/test_passability_set_tile.gd
git commit -m "feat: PassabilityGrid.set_tile for pre-downsampled GPU tiles"
```

---

## Task 2: Passability buffer constants + `decode_passability_slice`

Declare the buffer/constants and a pure-CPU decoder (mirrors `decode_solidity_flags`).

**Files:**
- Modify: `src/core/compute_device.gd`
- Create: `tests/unit/test_passability_decode.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_passability_decode.gd`:

```gdscript
extends GdUnitTestSuite

const PASS_SLOT_U32 := 1024
const PASS_SLOT_BYTES := 4096

func _buffer(slot_count: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(slot_count * PASS_SLOT_BYTES)
	b.fill(0)
	return b

func test_decodes_solid_cell_in_slot() -> void:
	var device := ComputeDevice.new()
	var data := _buffer(3)
	# slot 2, cell index 33 (cell (1,1)) marked solid
	data.encode_u32(2 * PASS_SLOT_BYTES + 33 * 4, 1)
	var tile := device.decode_passability_slice(data, 2)
	assert_that(tile.size()).is_equal(PASS_SLOT_U32)
	assert_that(tile[33]).is_equal(1)
	assert_that(tile[0]).is_equal(0)

func test_slot_beyond_buffer_returns_zero_tile() -> void:
	var device := ComputeDevice.new()
	var data := _buffer(1)
	var tile := device.decode_passability_slice(data, 5)
	assert_that(tile.size()).is_equal(PASS_SLOT_U32)
	assert_that(tile[0]).is_equal(0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=$(command -v godot) addons/gdUnit4/runtest.sh -a tests/unit/test_passability_decode.gd`
Expected: FAIL — `Nonexistent function 'decode_passability_slice'`.

- [ ] **Step 3: Add constants and buffer declaration**

In `src/core/compute_device.gd`, immediately after the collider constants block (currently ends at line 60, `const COLLIDER_COALESCED_BUFFER_SIZE := ...`), add:

```gdscript
const PASSABILITY_CELLS_PER_SIDE := 32          # 256px chunk / 8px cell
const PASSABILITY_SLOT_U32 := 1024              # 32 * 32, one uint per cell
const PASSABILITY_SLOT_BYTES := 4096            # 1024 * 4
const PASSABILITY_BUFFER_SIZE := COLLIDER_MAX_DISPATCH_PER_FRAME * PASSABILITY_SLOT_BYTES  # 16 KB
```

In the variable-declaration block, immediately after `var collider_dispatch_manifests: ...` (line 28), add:

```gdscript
# Passability grid output, written by the same collider dispatch. Shares the
# collider write-index / manifest / double-buffer; one 32x32 byte-grid per slot.
var passability_output_buffers: Array[RID] = [RID(), RID()]
```

- [ ] **Step 4: Add `decode_passability_slice`**

In `src/core/compute_device.gd`, immediately after `decode_collider_slice` (ends at line 797), add:

```gdscript
static func decode_passability_slice(data: PackedByteArray, slot: int) -> PackedByteArray:
	var tile := PackedByteArray()
	tile.resize(PASSABILITY_SLOT_U32)
	tile.fill(0)
	var slot_offset := slot * PASSABILITY_SLOT_BYTES
	if slot_offset + PASSABILITY_SLOT_BYTES > data.size():
		return tile
	for i in range(PASSABILITY_SLOT_U32):
		tile[i] = 1 if data.decode_u32(slot_offset + i * 4) != 0 else 0
	return tile
```

- [ ] **Step 5: Run test to verify it passes**

Run: `GODOT_BIN=$(command -v godot) addons/gdUnit4/runtest.sh -a tests/unit/test_passability_decode.gd`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add src/core/compute_device.gd tests/unit/test_passability_decode.gd
git commit -m "feat: passability buffer constants + decode_passability_slice"
```

---

## Task 3: Passability buffer lifecycle (create + free)

Allocate and free the double-buffered passability storage alongside the collider buffers.

**Files:**
- Modify: `src/core/compute_device.gd`

- [ ] **Step 1: Create + zero the buffers in init**

In `src/core/compute_device.gd`, `init_collider_storage_buffer()` currently ends at line 152 with `collider_storage_buffer = RID()`. Append, inside the same function:

```gdscript
	# Passability output buffers ride the same dispatch/double-buffer.
	var pzero := PackedByteArray()
	pzero.resize(PASSABILITY_BUFFER_SIZE)
	pzero.fill(0)
	for i in range(2):
		passability_output_buffers[i] = rd.storage_buffer_create(PASSABILITY_BUFFER_SIZE)
		rd.buffer_update(passability_output_buffers[i], 0, PASSABILITY_BUFFER_SIZE, pzero)
```

- [ ] **Step 2: Free the buffers in `free_resources`**

In `free_resources()`, immediately after the `collider_output_buffers` free loop (currently ends at line 458 `collider_output_buffers[i] = RID()`), add:

```gdscript
	for i in range(2):
		if passability_output_buffers[i].is_valid():
			rd.free_rid(passability_output_buffers[i])
			passability_output_buffers[i] = RID()
```

- [ ] **Step 3: Verify the project still launches (no automated test — GPU path)**

Run: `godot --path . --quit-after 120 2>&1 | grep -iE "error|passability|script" | head`
Expected: no script/parse errors mentioning `compute_device.gd` or `passability`. The buffer is allocated but not yet bound or written — harmless. (If using the Godot editor's MCP `run_project`, launch then stop, and check `get_debug_output` for the same.)

- [ ] **Step 4: Commit**

```bash
git add src/core/compute_device.gd
git commit -m "feat: allocate + free GPU passability output buffers"
```

---

## Task 4: Shader writes passability grid + uniform set binds it

The shader and the uniform-set binding **must land together** — a `binding = 2` in the shader with no bound buffer (or vice versa) makes the dispatch fail.

**Files:**
- Modify: `shaders/compute/collider.glsl`
- Modify: `src/core/chunk_manager.gd:285-304` (`build_collider_uniform_sets`)

- [ ] **Step 1: Add the passability binding + constants to the shader**

In `shaders/compute/collider.glsl`, after the `segment_buffer` block (ends at line 11), add:

```glsl
layout(std430, binding = 2) buffer PassabilityBuffer {
	uint data[];
} passability_buffer;
```

After `const uint MAX_SEGMENTS = 4096u;` (line 23), add:

```glsl
const uint PASS_CELL = 8u;
const uint PASS_CELLS_PER_SIDE = 32u;   // CHUNK_SIZE / PASS_CELL
const uint PASS_SLOT_U32 = 1024u;       // 32 * 32, one uint per 8px cell
```

- [ ] **Step 2: Write the passability cell in `main()`**

In `shaders/compute/collider.glsl`, `gx`/`gy` are computed at lines 53–54 (`uint gx = cell_x * CELL_SIZE;` / `uint gy = cell_y * CELL_SIZE;`). Immediately after line 54, **before** the corner sampling at line 56, insert:

```glsl
	// Passability grid: the invocation owning each 8px cell (every 4th 2px cell
	// on each axis) samples its full 8x8 pixel block and writes 1 if ANY pixel
	// is solid. Raw solidity with NO border-air forcing, so a wall touching the
	// chunk edge reads solid and enemies don't path into it.
	if ((cell_x & 3u) == 0u && (cell_y & 3u) == 0u) {
		uint pass_solid = 0u;
		for (uint ppy = 0u; ppy < PASS_CELL; ppy++) {
			for (uint ppx = 0u; ppx < PASS_CELL; ppx++) {
				uint pmat = uint(round(imageLoad(terrain_texture, ivec2(gx + ppx, gy + ppy)).r * 255.0));
				if (pmat != 0u && HAS_COLLIDER[pmat]) { pass_solid = 1u; break; }
			}
			if (pass_solid == 1u) break;
		}
		uint pcell = (cell_y / 4u) * PASS_CELLS_PER_SIDE + (cell_x / 4u);
		passability_buffer.data[pc.slot_index * PASS_SLOT_U32 + pcell] = pass_solid;
	}
```

(`gx = cell_x * 2`; for designated `cell_x` divisible by 4, `gx` is divisible by 8 and `gx + 7 <= 255`, so the loop stays in-bounds.)

- [ ] **Step 3: Bind the passability buffer in the collider uniform set**

In `src/core/chunk_manager.gd`, `build_collider_uniform_sets`, the validity guard at line 291 reads:

```gdscript
		if not compute.collider_output_buffers[i].is_valid():
			continue
```

Replace it with:

```gdscript
		if not compute.collider_output_buffers[i].is_valid() or not compute.passability_output_buffers[i].is_valid():
			continue
```

Then, immediately after the `u1` block appends the segment buffer (line 303 `uniforms.append(u1)`), add:

```gdscript
		var u2 := RDUniform.new()
		u2.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u2.binding = 2
		u2.add_id(compute.passability_output_buffers[i])
		uniforms.append(u2)
```

- [ ] **Step 4: Verify the shader compiles and the dispatch runs (manual — GPU path)**

Run: `godot --path . --quit-after 180 2>&1 | grep -iE "error|shader|uniform|collider" | head`
Expected: no shader-compile or `uniform_set_create` errors. The collider should still build wall collision (player can't walk through walls). If a uniform-mismatch error appears, the shader binding and the uniform set are out of sync — re-check Steps 1–3.

- [ ] **Step 5: Commit**

```bash
git add shaders/compute/collider.glsl src/core/chunk_manager.gd
git commit -m "feat: collider pass emits 32x32 passability grid to bound buffer"
```

---

## Task 5: Coalesced readback returns both buffers; helper feeds nav grid

Change `read_collider_buffer_coalesced` to read both buffers in one call and return `{"segments", "passability"}`; update the only two consumers (the helper and its test fake).

**Files:**
- Modify: `src/core/compute_device.gd:747-774` (`read_collider_buffer_coalesced`)
- Modify: `src/core/terrain_collision_helper.gd:48-69` (`_consume_readback`)
- Modify: `tests/unit/test_terrain_collision_helper.gd`

- [ ] **Step 1: Update the helper's test fakes to the new shape**

In `tests/unit/test_terrain_collision_helper.gd`, replace the `FakeComputeDevice` class (lines 5–13) with:

```gdscript
	class FakeComputeDevice extends RefCounted:
		var dispatched_coords: Array = []
		var pending_readback: Dictionary = {"segments": {}, "passability": {}}
		func dispatch_collider_pack(_chunks: Dictionary, coords: Array) -> void:
			dispatched_coords = coords.duplicate()
		func read_collider_buffer_coalesced() -> Dictionary:
			var out := pending_readback.duplicate()
			pending_readback = {"segments": {}, "passability": {}}
			return out
```

And add a `nav_field` field to `FakeWorldManager` (currently lines 15–20) so `_consume_readback`'s `world_manager.nav_field` access resolves. Replace the class with:

```gdscript
	class FakeWorldManager extends RefCounted:
		var compute_device
		var chunks: Dictionary = {}
		var dirty_marks: Array = []
		var nav_field = null
		func mark_terrain_dirty(coord: Vector2i) -> void:
			dirty_marks.append(coord)
```

- [ ] **Step 2: Run the helper test to confirm it fails against old code**

Run: `GODOT_BIN=$(command -v godot) addons/gdUnit4/runtest.sh -a tests/unit/test_terrain_collision_helper.gd`
Expected: FAIL — old `_consume_readback` does `for coord in readback:` and iterates the dict's string keys (`"segments"`, `"passability"`), so `chunks.has(coord)` is comparing a String, breaking `test_dispatch_drains_dirty_up_to_cap` / readback handling. (If it happens to pass, Step 4 still corrects the logic.)

- [ ] **Step 3: Rewrite `read_collider_buffer_coalesced`**

In `src/core/compute_device.gd`, replace the whole function (lines 747–774) with:

```gdscript
func read_collider_buffer_coalesced() -> Dictionary:
	var empty := {"segments": {}, "passability": {}}
	if collider_first_frame:
		collider_first_frame = false
		collider_write_index = 1 - collider_write_index
		return empty

	var read_index := 1 - collider_write_index
	var manifest: PackedInt32Array = collider_dispatch_manifests[read_index]
	if manifest.is_empty():
		collider_write_index = 1 - collider_write_index
		return empty

	var entry_count := manifest.size() / 3

	var bytes_needed := entry_count * COLLIDER_SLOT_STRIDE_BYTES
	if entry_count == COLLIDER_MAX_DISPATCH_PER_FRAME:
		bytes_needed = COLLIDER_COALESCED_BUFFER_SIZE
	var data: PackedByteArray = rd.buffer_get_data(collider_output_buffers[read_index], 0, bytes_needed)

	var pass_bytes_needed := entry_count * PASSABILITY_SLOT_BYTES
	if entry_count == COLLIDER_MAX_DISPATCH_PER_FRAME:
		pass_bytes_needed = PASSABILITY_BUFFER_SIZE
	var pass_data: PackedByteArray = rd.buffer_get_data(passability_output_buffers[read_index], 0, pass_bytes_needed)

	collider_write_index = 1 - collider_write_index

	var segments: Dictionary = {}
	var passability: Dictionary = {}
	for i in range(entry_count):
		var slot := manifest[i * 3 + 2]
		var coord := Vector2i(manifest[i * 3], manifest[i * 3 + 1])
		segments[coord] = decode_collider_slice(data, slot)
		passability[coord] = decode_passability_slice(pass_data, slot)
	return {"segments": segments, "passability": passability}
```

- [ ] **Step 4: Rewrite `_consume_readback`**

In `src/core/terrain_collision_helper.gd`, replace the whole function (lines 48–69) with:

```gdscript
func _consume_readback(chunks: Dictionary) -> void:
	var compute = world_manager.compute_device
	var readback: Dictionary = compute.read_collider_buffer_coalesced()
	var segments_map: Dictionary = readback["segments"]
	var passability_map: Dictionary = readback["passability"]
	_in_flight.clear()

	# Feed every dispatched chunk's passability tile into the nav grid,
	# independent of the seg-hash skip below: an all-solid chunk emits no
	# segments but still has a meaningful passability grid.
	if world_manager.nav_field != null:
		for coord in passability_map:
			if chunks.has(coord):
				world_manager.nav_field.grid.set_tile(coord, passability_map[coord])

	for coord in segments_map:
		if not chunks.has(coord):
			continue
		var segments: PackedVector2Array = segments_map[coord]
		# Byte-identical segments => shape + occluders unchanged; skip rebuild.
		var seg_hash: int = hash(segments)
		var is_first_build: bool = not _last_seg_hash.has(coord)
		if _last_seg_hash.get(coord, -1) == seg_hash:
			continue
		_last_seg_hash[coord] = seg_hash
		_pending_segments[coord] = segments
		_pending_collision_builds.append(coord)
		_pending_occluder_builds.append(coord)
		if is_first_build:
			_fresh_pending[coord] = true
```

- [ ] **Step 5: Run the helper test to verify it passes**

Run: `GODOT_BIN=$(command -v godot) addons/gdUnit4/runtest.sh -a tests/unit/test_terrain_collision_helper.gd`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add src/core/compute_device.gd src/core/terrain_collision_helper.gd tests/unit/test_terrain_collision_helper.gd
git commit -m "feat: coalesced readback returns segments+passability; helper feeds nav grid"
```

---

## Task 6: Slim NavField + drop the old read path

Remove the dirty-tracking / `read_region` / CPU downsample from the live nav loop, now that the GPU path feeds `grid.set_tile`. Drop nav tiles on chunk unload.

**Files:**
- Modify: `tests/unit/test_nav_field.gd`
- Modify: `src/core/nav/nav_field.gd`
- Modify: `src/core/world_manager.gd:87-91` (`mark_terrain_dirty`)
- Modify: `src/core/chunk_manager.gd:137-139` (`unload_chunk`)

- [ ] **Step 1: Rewrite the NavField test for the GPU-tile path**

Replace the entire contents of `tests/unit/test_nav_field.gd` with:

```gdscript
extends GdUnitTestSuite

const NavField = preload("res://src/core/nav/nav_field.gd")

# 32x32 cells per chunk at 8px cells. value 1 = solid.
func _tile(solid_cells: Array) -> PackedByteArray:
	var t := PackedByteArray()
	t.resize(32 * 32)
	t.fill(0)
	for c: Vector2i in solid_cells:
		t[c.y * 32 + c.x] = 1
	return t

func test_grid_tile_marks_world_solid() -> void:
	var nav = NavField.new()
	nav.grid.set_tile(Vector2i(0, 0), _tile([Vector2i(0, 0)]))
	assert_bool(nav.is_solid_world(Vector2(4, 4))).is_true()

func test_open_when_no_tile() -> void:
	var nav = NavField.new()
	assert_bool(nav.is_solid_world(Vector2(4, 4))).is_false()

func test_update_does_not_crash_with_no_tiles() -> void:
	var nav = NavField.new()
	nav.update(Vector2(0, 0), 0.0)
	assert_bool(nav.is_solid_world(Vector2(4, 4))).is_false()
```

- [ ] **Step 2: Run the NavField test to confirm it fails against old code**

Run: `GODOT_BIN=$(command -v godot) addons/gdUnit4/runtest.sh -a tests/unit/test_nav_field.gd`
Expected: FAIL — `NavField.new()` with no argument errors against the current required `_init(world_manager)`.

- [ ] **Step 3: Slim NavField**

Replace the entire contents of `src/core/nav/nav_field.gd` with:

```gdscript
class_name NavField
extends RefCounted

const CELL := 8
const CHUNK := 256
const REGION_RADIUS_CELLS := 48
const FLOW_BUDGET := 160
const MOVE_THRESHOLD_CELLS := 8
const MAX_LIVE_AGE := 3.0

var grid: PassabilityGrid
var flow: FlowField

# world_manager is accepted for call-site compatibility but no longer used:
# the GPU collider pass feeds grid tiles via TerrainCollisionHelper.
func _init(_world_manager = null) -> void:
	grid = PassabilityGrid.new(CELL, CHUNK, _build_solid_lut())
	flow = FlowField.new(CELL, REGION_RADIUS_CELLS, FLOW_BUDGET, MOVE_THRESHOLD_CELLS, MAX_LIVE_AGE)

func _build_solid_lut() -> PackedByteArray:
	var n: int = MaterialRegistry.materials.size()
	var lut := PackedByteArray()
	lut.resize(n)
	for i in n:
		lut[i] = 1 if MaterialRegistry.has_collider(i) else 0
	return lut

func update(player_world_pos: Vector2, delta: float) -> void:
	flow.update(grid, player_world_pos, delta)

func sample_direction(world_pos: Vector2) -> Vector2:
	return flow.sample_direction(world_pos)

func is_solid_world(world_pos: Vector2) -> bool:
	return grid.is_solid_world(world_pos)
```

- [ ] **Step 4: Run the NavField test to verify it passes**

Run: `GODOT_BIN=$(command -v godot) addons/gdUnit4/runtest.sh -a tests/unit/test_nav_field.gd`
Expected: PASS (3 tests).

- [ ] **Step 5: Stop marking nav dirty in `world_manager`**

In `src/core/world_manager.gd`, replace `mark_terrain_dirty` (lines 87–91):

```gdscript
func mark_terrain_dirty(coord: Vector2i) -> void:
	if _collision_helper != null:
		_collision_helper.mark_dirty(coord)
	if nav_field != null:
		nav_field.mark_dirty(coord)
```

with:

```gdscript
func mark_terrain_dirty(coord: Vector2i) -> void:
	# Nav grid is now fed by the collider dispatch's passability output (via
	# TerrainCollisionHelper), so only the collision helper is marked here.
	if _collision_helper != null:
		_collision_helper.mark_dirty(coord)
```

- [ ] **Step 6: Drop the nav tile on chunk unload**

In `src/core/chunk_manager.gd`, `unload_chunk`, after the collision-helper purge (lines 138–139):

```gdscript
	if world_manager._collision_helper != null:
		world_manager._collision_helper.on_chunk_unloaded(coord)
```

add:

```gdscript
	if world_manager.nav_field != null:
		world_manager.nav_field.grid.drop_chunk(coord)
```

- [ ] **Step 7: Verify in-engine that enemies still path (manual — GPU path)**

Run the project (`godot --path .` or MCP `run_project`), spawn into a level, and confirm enemies move toward the player and route around walls rather than stopping at or clipping into terrain. Check the debug output for errors:

Run: `godot --path . --quit-after 240 2>&1 | grep -iE "error|nav_field|read_region" | head`
Expected: no errors; no remaining `read_region` references in the nav path (grep in Step 8 of Task 7 confirms).

- [ ] **Step 8: Commit**

```bash
git add src/core/nav/nav_field.gd src/core/world_manager.gd src/core/chunk_manager.gd tests/unit/test_nav_field.gd
git commit -m "feat: NavField consumes GPU passability tiles; drop read_region path"
```

---

## Task 7: Full verification

Confirm the whole suite is green and the old path is gone.

**Files:** none (verification only).

- [ ] **Step 1: Run the full unit suite**

Run: `GODOT_BIN=$(command -v godot) addons/gdUnit4/runtest.sh -a tests/unit`
Expected: all suites PASS, including `test_passability_set_tile`, `test_passability_decode`, `test_nav_field`, `test_terrain_collision_helper`, `test_passability_grid`, `test_solidity_flags_decode`, `test_terrain_collider_seam`.

- [ ] **Step 2: Confirm the nav path no longer reads back full chunks**

Run: `grep -n "read_region\|_drain_tiles\|mark_dirty" src/core/nav/nav_field.gd`
Expected: no matches (the file no longer references any of them).

Run: `grep -rn "nav_field.mark_dirty" src/`
Expected: no matches.

- [ ] **Step 3: Confirm passability is wired end-to-end**

Run: `grep -n "passability_output_buffers\|decode_passability_slice\|PASSABILITY" src/core/compute_device.gd && grep -n "binding = 2" src/core/chunk_manager.gd && grep -n "passability_buffer" shaders/compute/collider.glsl && grep -n "set_tile" src/core/terrain_collision_helper.gd`
Expected: matches in every file — buffer/decoder in `compute_device`, binding in `chunk_manager`, write in the shader, and the `set_tile` feed in the helper.

- [ ] **Step 4: Final manual smoke (GPU path)**

Run the project, play for ~30 seconds, carve terrain near enemies, and confirm: walls still block the player, enemies path around freshly-carved and freshly-filled terrain, and no errors print. This exercises the GPU passability grid reacting to live terrain edits.

- [ ] **Step 5: Update the todo checkboxes**

In `docs/design_docs/implementation_todo.md`, mark both Sub-project 2 rows done — change `|  | P1 | High | GPU 32×32 solidity grid |` and `|  | P1 | Medium | NavField consumes GPU grid |` to `| x |` in the leading Done column (lines 190–191).

- [ ] **Step 6: Commit**

```bash
git add docs/design_docs/implementation_todo.md
git commit -m "docs: mark Phase 8 sub-project 2 (GPU passability buffer) done"
```

---

## Self-Review Notes

**Spec coverage:** §1 buffer layout → Tasks 2–3. §2 shader → Task 4. §3 uniform set → Task 4. §4 readback/decode → Tasks 2, 5. §5 helper consumption → Task 5. §6 NavField → Task 6. §7 `set_tile` + retained `update_chunk` → Task 1 (retains `update_chunk` untouched). §8 wiring (stop marking nav dirty, drop_chunk on unload) → Task 6. Testing/success-criteria → Tasks 1, 2, 7.

**Type consistency:** `set_tile(Vector2i, PackedByteArray)`, `decode_passability_slice(PackedByteArray, int) -> PackedByteArray`, and the `{"segments", "passability"}` readback dict are used identically across Tasks 1, 2, 5, 6. Shader constants (`PASS_CELL`, `PASS_CELLS_PER_SIDE`, `PASS_SLOT_U32`) and GDScript constants (`PASSABILITY_*`) are distinct namespaces but numerically aligned (8 / 32 / 1024 / 4096).

**Retained on purpose:** `PassabilityGrid.update_chunk` and `test_passability_grid.gd` (CPU reference/fallback) are left untouched per spec §7 — not dead-code-removed in this plan.
