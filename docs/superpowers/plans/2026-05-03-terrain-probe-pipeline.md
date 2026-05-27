# Terrain Probe Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the empty `_grid` cache in `TerrainPhysical` with a tiny GPU probe SSBO + readback path so `query()` returns real material data, fixing both the natural-enemy-spawn bug and the lava-damage bug at ~256 B readback per frame instead of 256 KB chunk readback.

**Architecture:** Add a small compute shader that gathers up to 64 individual cells per frame from active chunk textures into a 256 B output SSBO. `TerrainPhysical.query()` keeps its current signature; internally it returns the most recent cached result and queues the coord for the next probe batch. `WorldManager._process` runs one dispatch + one tiny `buffer_get_data` per frame after the simulation step.

**Tech Stack:** Godot 4.x `RenderingDevice` compute, GLSL 450 compute shader, GdUnit test suite.

**Spec:** `docs/superpowers/specs/2026-05-03-terrain-probe-pipeline-design.md`.

---

## File Map

- **Create:** `shaders/compute/terrain_probe.glsl` — gather shader.
- **Modify:** `src/core/compute_device.gd` — new RIDs, `init_terrain_probe`, `dispatch_terrain_probe`, `read_terrain_probe`, free in `free_resources`.
- **Modify:** `src/core/terrain_physical.gd` — replace `_grid` with `_result_cache` + `_pending_probes`, rewrite `query`, add `prepare_probe_batch`, `apply_probe_results`. Keep `invalidate_rect` and `set_center`.
- **Modify:** `src/core/world_manager.gd` — call `compute_device.init_terrain_probe()` in `_ready`, add `_run_terrain_probes()` step in `_process` between collision rebuild and `_update_lights`.
- **Modify:** `tests/unit/test_terrain_physical.gd` — replace tests that touch `_grid` with tests for the new state, add tests for `prepare_probe_batch` and `apply_probe_results`.

Constants land in `ComputeDevice.PROBE_BUDGET = 64` and `TerrainPhysical.TTL_FRAMES = 8`.

---

## Task 1: Probe shader

**Files:**
- Create: `shaders/compute/terrain_probe.glsl`

- [ ] **Step 1: Write the shader**

Create `shaders/compute/terrain_probe.glsl`:

```glsl
#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 1, local_size_z = 1) in;

layout(rgba8, set = 0, binding = 0) readonly uniform image2D chunk_tex;

layout(set = 0, binding = 1, std430) readonly buffer ProbeInput {
	ivec2 local_coords[];
} probe_input;

layout(set = 0, binding = 2, std430) buffer ProbeOutput {
	uint mat_ids[];
} probe_output;

layout(push_constant, std430) uniform PushConstants {
	uint probe_start;
	uint probe_count;
} pc;

void main() {
	uint gid = gl_GlobalInvocationID.x;
	if (gid >= pc.probe_count) {
		return;
	}
	uint slot = pc.probe_start + gid;
	ivec2 c = probe_input.local_coords[slot];
	vec4 px = imageLoad(chunk_tex, c);
	probe_output.mat_ids[slot] = uint(px.r * 255.0 + 0.5);
}
```

- [ ] **Step 2: Verify the shader compiles**

Run: `cd /home/jeremy/Development/gdworkflow/sandbox/top-down-rogue && godot --headless --quit 2>&1 | grep -iE "error|terrain_probe" | head -20`

Expected: no compile errors mentioning `terrain_probe.glsl`. (Godot imports new `.glsl` files on first run; the `.import` companion is generated automatically.)

- [ ] **Step 3: Commit**

```bash
git add shaders/compute/terrain_probe.glsl shaders/compute/terrain_probe.glsl.import
git commit -m "feat: add terrain_probe compute shader for sparse cell readback"
```

---

## Task 2: ComputeDevice — buffers, init, free

**Files:**
- Modify: `src/core/compute_device.gd`

- [ ] **Step 1: Add fields and constant**

In `src/core/compute_device.gd`, near the top after the existing `light_*` fields, add:

```gdscript
const PROBE_BUDGET := 64
const PROBE_INPUT_BUFFER_SIZE := PROBE_BUDGET * 8     # 64 × ivec2 (2×4 bytes) = 512
const PROBE_OUTPUT_BUFFER_SIZE := PROBE_BUDGET * 4    # 64 × uint  (4 bytes) = 256

var terrain_probe_shader: RID
var terrain_probe_pipeline: RID
var terrain_probe_input_buffer: RID
var terrain_probe_output_buffer: RID
```

- [ ] **Step 2: Add `init_terrain_probe`**

Append to `compute_device.gd`:

```gdscript
func init_terrain_probe() -> void:
	var f: RDShaderFile = load("res://shaders/compute/terrain_probe.glsl")
	terrain_probe_shader = rd.shader_create_from_spirv(f.get_spirv())
	terrain_probe_pipeline = rd.compute_pipeline_create(terrain_probe_shader)

	var zero_in := PackedByteArray()
	zero_in.resize(PROBE_INPUT_BUFFER_SIZE)
	zero_in.fill(0)
	terrain_probe_input_buffer = rd.storage_buffer_create(PROBE_INPUT_BUFFER_SIZE, zero_in)

	var zero_out := PackedByteArray()
	zero_out.resize(PROBE_OUTPUT_BUFFER_SIZE)
	zero_out.fill(0)
	terrain_probe_output_buffer = rd.storage_buffer_create(PROBE_OUTPUT_BUFFER_SIZE, zero_out)
```

- [ ] **Step 3: Free new RIDs in `free_resources`**

In `free_resources()`, before the final closing brace of the function, add:

```gdscript
	if terrain_probe_input_buffer.is_valid():
		rd.free_rid(terrain_probe_input_buffer)
	if terrain_probe_output_buffer.is_valid():
		rd.free_rid(terrain_probe_output_buffer)
	if terrain_probe_pipeline.is_valid():
		rd.free_rid(terrain_probe_pipeline)
	if terrain_probe_shader.is_valid():
		rd.free_rid(terrain_probe_shader)
```

- [ ] **Step 4: Verify Godot still loads the project**

Run: `cd /home/jeremy/Development/gdworkflow/sandbox/top-down-rogue && godot --headless --quit 2>&1 | tail -20`

Expected: no parse errors mentioning `compute_device.gd`.

- [ ] **Step 5: Commit**

```bash
git add src/core/compute_device.gd
git commit -m "feat: add terrain probe SSBOs and pipeline init in ComputeDevice"
```

---

## Task 3: ComputeDevice — dispatch and readback

**Files:**
- Modify: `src/core/compute_device.gd`

- [ ] **Step 1: Add `dispatch_terrain_probe` and `read_terrain_probe`**

Append to `compute_device.gd`:

```gdscript
## Dispatch the probe shader once per chunk that has probes.
##
## `batch` is an Array of Dictionaries with keys:
##   chunk_coord: Vector2i
##   start: int               (offset into the global probe range)
##   count: int               (number of probes for this chunk)
## `packed_input` is the full PROBE_BUDGET-sized PackedByteArray
## containing ivec2 local coords for every probe in the batch
## (entries past total_count may be zero).
func dispatch_terrain_probe(chunks: Dictionary, batch: Array, packed_input: PackedByteArray) -> void:
	if batch.is_empty():
		return

	rd.buffer_update(terrain_probe_input_buffer, 0, PROBE_INPUT_BUFFER_SIZE, packed_input)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, terrain_probe_pipeline)

	var created_uniform_sets: Array[RID] = []
	for entry in batch:
		var chunk_coord: Vector2i = entry["chunk_coord"]
		var chunk: Chunk = chunks.get(chunk_coord, null)
		if chunk == null or not chunk.rd_texture.is_valid():
			continue
		var start: int = entry["start"]
		var count: int = entry["count"]
		if count <= 0:
			continue

		var u_tex := RDUniform.new()
		u_tex.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_tex.binding = 0
		u_tex.add_id(chunk.rd_texture)

		var u_in := RDUniform.new()
		u_in.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u_in.binding = 1
		u_in.add_id(terrain_probe_input_buffer)

		var u_out := RDUniform.new()
		u_out.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u_out.binding = 2
		u_out.add_id(terrain_probe_output_buffer)

		var us := rd.uniform_set_create([u_tex, u_in, u_out], terrain_probe_shader, 0)
		created_uniform_sets.append(us)

		rd.compute_list_bind_uniform_set(compute_list, us, 0)

		var push := PackedByteArray()
		push.resize(8)
		push.encode_u32(0, start)
		push.encode_u32(4, count)
		rd.compute_list_set_push_constant(compute_list, push, push.size())

		var groups: int = int(ceil(float(count) / 8.0))
		rd.compute_list_dispatch(compute_list, groups, 1, 1)

	rd.compute_list_end()

	for us in created_uniform_sets:
		rd.free_rid(us)


func read_terrain_probe(byte_count: int) -> PackedByteArray:
	if byte_count <= 0:
		return PackedByteArray()
	return rd.buffer_get_data(terrain_probe_output_buffer, 0, byte_count)
```

- [ ] **Step 2: Verify Godot still loads the project**

Run: `cd /home/jeremy/Development/gdworkflow/sandbox/top-down-rogue && godot --headless --quit 2>&1 | tail -20`

Expected: no parse errors.

- [ ] **Step 3: Commit**

```bash
git add src/core/compute_device.gd
git commit -m "feat: add terrain probe dispatch and readback methods"
```

---

## Task 4: TerrainPhysical — rewrite state and query (TDD)

**Files:**
- Modify: `src/core/terrain_physical.gd`
- Modify: `tests/unit/test_terrain_physical.gd`

- [ ] **Step 1: Rewrite the existing test file**

Replace the entire contents of `tests/unit/test_terrain_physical.gd` with:

```gdscript
extends GdUnitTestSuite


func test_query_empty_cache_returns_default_cell() -> void:
	var tp := TerrainPhysical.new()
	var cell := tp.query(Vector2(50, 60))
	assert_that(cell.material_id).is_equal(0)
	assert_that(cell.is_solid).is_false()
	assert_that(cell.damage).is_equal(0.0)


func test_query_queues_pending_probe() -> void:
	var tp := TerrainPhysical.new()
	tp.query(Vector2(12.7, -3.2))
	assert_that(tp._pending_probes.has(Vector2i(12, -4))).is_true()


func test_apply_probe_results_populates_cache() -> void:
	var tp := TerrainPhysical.new()
	# Queue one probe via query (returns default).
	tp.query(Vector2(10, 20))

	var batch: Array = [{
		"chunk_coord": Vector2i(0, 0),
		"world_coords": [Vector2i(10, 20)],
		"start": 0,
		"count": 1,
	}]
	var raw := PackedByteArray()
	raw.resize(4)
	raw.encode_u32(0, MaterialRegistry.STONE)
	tp.apply_probe_results(batch, raw)

	var cell := tp.query(Vector2(10, 20))
	assert_that(cell.material_id).is_equal(MaterialRegistry.STONE)


func test_ttl_expiry_returns_default() -> void:
	var tp := TerrainPhysical.new()
	tp.query(Vector2(5, 5))
	var batch: Array = [{
		"chunk_coord": Vector2i(0, 0),
		"world_coords": [Vector2i(5, 5)],
		"start": 0,
		"count": 1,
	}]
	var raw := PackedByteArray()
	raw.resize(4)
	raw.encode_u32(0, MaterialRegistry.STONE)
	tp.apply_probe_results(batch, raw)

	# Advance frame counter past TTL by applying empty batches.
	for i in range(TerrainPhysical.TTL_FRAMES + 1):
		tp.apply_probe_results([], PackedByteArray())

	var cell := tp.query(Vector2(5, 5))
	assert_that(cell.material_id).is_equal(0)


func test_invalidate_clears_cache_entry() -> void:
	var tp := TerrainPhysical.new()
	tp.query(Vector2(15, 25))
	var batch: Array = [{
		"chunk_coord": Vector2i(0, 0),
		"world_coords": [Vector2i(15, 25)],
		"start": 0,
		"count": 1,
	}]
	var raw := PackedByteArray()
	raw.resize(4)
	raw.encode_u32(0, MaterialRegistry.STONE)
	tp.apply_probe_results(batch, raw)

	tp.invalidate_rect(Rect2i(10, 20, 10, 10))

	var cell := tp.query(Vector2(15, 25))
	assert_that(cell.material_id).is_equal(0)


func test_set_center_updates_grid_center() -> void:
	var tp := TerrainPhysical.new()
	tp.set_center(Vector2i(500, 500))
	assert_that(tp._grid_center).is_equal(Vector2i(500, 500))


func test_prepare_probe_batch_bins_by_chunk() -> void:
	var tp := TerrainPhysical.new()
	# Stub world_manager with a chunks dict containing two chunk coords.
	var fake_wm := Node2D.new()
	fake_wm.set("chunks", {Vector2i(0, 0): true, Vector2i(1, 0): true})
	tp.world_manager = fake_wm

	tp.query(Vector2(5, 5))      # chunk (0,0) local (5,5)
	tp.query(Vector2(260, 10))   # chunk (1,0) local (4,10)
	tp.query(Vector2(7, 8))      # chunk (0,0) local (7,8)

	var batch := tp.prepare_probe_batch()

	# Two chunks present in batch.
	assert_that(batch.size()).is_equal(2)

	var total: int = 0
	for entry in batch:
		total += int(entry["count"])
	assert_that(total).is_equal(3)

	# Starts are contiguous.
	var sorted_starts: Array = []
	for entry in batch:
		sorted_starts.append(int(entry["start"]))
	sorted_starts.sort()
	assert_that(sorted_starts[0]).is_equal(0)
	assert_that(sorted_starts[1]).is_equal(int(batch[0]["count"]) if int(batch[0]["start"]) == 0 else int(batch[1]["count"]))

	fake_wm.free()


func test_prepare_probe_batch_drops_unloaded_chunks() -> void:
	var tp := TerrainPhysical.new()
	var fake_wm := Node2D.new()
	fake_wm.set("chunks", {Vector2i(0, 0): true})  # chunk (1,0) NOT loaded
	tp.world_manager = fake_wm

	tp.query(Vector2(5, 5))      # in loaded chunk
	tp.query(Vector2(260, 10))   # in unloaded chunk

	var batch := tp.prepare_probe_batch()
	assert_that(batch.size()).is_equal(1)
	assert_that(batch[0]["chunk_coord"]).is_equal(Vector2i(0, 0))
	assert_that(int(batch[0]["count"])).is_equal(1)
	# Pending set is fully drained (unloaded probes are discarded, not retained).
	assert_that(tp._pending_probes.is_empty()).is_true()

	fake_wm.free()
```

- [ ] **Step 2: Run tests — expect failure**

Run: `cd /home/jeremy/Development/gdworkflow/sandbox/top-down-rogue && godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_terrain_physical.gd 2>&1 | tail -40`

Expected: failures referencing `_pending_probes`, `apply_probe_results`, `prepare_probe_batch`, `TTL_FRAMES` not yet existing.

- [ ] **Step 3: Rewrite `src/core/terrain_physical.gd`**

Replace the entire contents of `src/core/terrain_physical.gd` with:

```gdscript
class_name TerrainPhysical
extends Node

const CHUNK_SIZE := 256
const TTL_FRAMES := 8

## Last known probe results: Vector2i(world_x, world_y) -> {mat_id: int, frame: int}
var _result_cache: Dictionary = {}

## Cells queued for the next probe dispatch (set semantics): Vector2i -> true
var _pending_probes: Dictionary = {}

## Frame counter, advanced once per apply_probe_results call.
var _current_frame: int = 0

## Grid center in world coords (kept for API compatibility).
var _grid_center: Vector2i = Vector2i.ZERO
var _grid_size: int = 128
var _half_grid: int = 64

## Reference to WorldManager (provides .chunks for binning).
var world_manager: Node2D = null


func query(world_pos: Vector2) -> TerrainCell:
	var cell_pos := Vector2i(int(floor(world_pos.x)), int(floor(world_pos.y)))
	_pending_probes[cell_pos] = true
	if _result_cache.has(cell_pos):
		var entry: Dictionary = _result_cache[cell_pos]
		if _current_frame - int(entry["frame"]) <= TTL_FRAMES:
			return _cell_from_material(int(entry["mat_id"]))
	return TerrainCell.new()


func invalidate_rect(rect: Rect2i) -> void:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			_result_cache.erase(Vector2i(x, y))


func set_center(world_center: Vector2i) -> void:
	_grid_center = world_center


## Drain up to PROBE_BUDGET pending probes, bin by containing chunk.
## Returns Array of {chunk_coord, world_coords, start, count}.
## Probes whose chunk is not loaded are discarded (caller will re-query as needed).
func prepare_probe_batch(probe_budget: int = 64) -> Array:
	if _pending_probes.is_empty():
		return []

	var loaded_chunks: Dictionary = {}
	if world_manager != null and "chunks" in world_manager:
		loaded_chunks = world_manager.chunks

	# Drain into a deterministic order, capped by budget.
	var drained: Array[Vector2i] = []
	var leftover: Dictionary = {}
	var taken: int = 0
	for key in _pending_probes.keys():
		if taken < probe_budget:
			drained.append(key)
			taken += 1
		else:
			leftover[key] = true
	_pending_probes = leftover

	# Bin by chunk; drop coords in unloaded chunks.
	var bins: Dictionary = {}  # Vector2i chunk_coord -> Array[Vector2i] world_coords
	for wc in drained:
		var chunk_coord := Vector2i(
			int(floor(float(wc.x) / CHUNK_SIZE)),
			int(floor(float(wc.y) / CHUNK_SIZE))
		)
		if not loaded_chunks.has(chunk_coord):
			continue
		if not bins.has(chunk_coord):
			bins[chunk_coord] = []
		bins[chunk_coord].append(wc)

	# Assign contiguous start offsets.
	var batch: Array = []
	var cursor: int = 0
	for chunk_coord in bins.keys():
		var coords: Array = bins[chunk_coord]
		batch.append({
			"chunk_coord": chunk_coord,
			"world_coords": coords,
			"start": cursor,
			"count": coords.size(),
		})
		cursor += coords.size()
	return batch


## Pack the world coords of a batch into the SSBO input buffer layout
## (ivec2 per probe, contiguous by start offset). Returns a fixed-size
## PackedByteArray sized to PROBE_BUDGET * 8.
func pack_probe_input(batch: Array, probe_budget: int = 64) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(probe_budget * 8)
	buf.fill(0)
	for entry in batch:
		var start: int = int(entry["start"])
		var coords: Array = entry["world_coords"]
		var chunk_coord: Vector2i = entry["chunk_coord"]
		var origin := chunk_coord * CHUNK_SIZE
		for i in range(coords.size()):
			var wc: Vector2i = coords[i]
			var lx: int = wc.x - origin.x
			var ly: int = wc.y - origin.y
			var off: int = (start + i) * 8
			buf.encode_s32(off, lx)
			buf.encode_s32(off + 4, ly)
	return buf


func apply_probe_results(batch: Array, raw_bytes: PackedByteArray) -> void:
	for entry in batch:
		var start: int = int(entry["start"])
		var coords: Array = entry["world_coords"]
		for i in range(coords.size()):
			var byte_off: int = (start + i) * 4
			if byte_off + 4 > raw_bytes.size():
				break
			var mat_id: int = int(raw_bytes.decode_u32(byte_off))
			_result_cache[coords[i]] = {"mat_id": mat_id, "frame": _current_frame}
	_current_frame += 1


func _cell_from_material(mat_id: int) -> TerrainCell:
	var is_solid := MaterialRegistry.has_collider(mat_id)
	var is_fluid := MaterialRegistry.is_fluid(mat_id)
	var dmg := MaterialRegistry.get_damage(mat_id)
	return TerrainCell.new(mat_id, is_solid, is_fluid, dmg)
```

- [ ] **Step 4: Run tests — expect pass**

Run: `cd /home/jeremy/Development/gdworkflow/sandbox/top-down-rogue && godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_terrain_physical.gd 2>&1 | tail -40`

Expected: all `test_*` cases pass.

- [ ] **Step 5: Commit**

```bash
git add src/core/terrain_physical.gd tests/unit/test_terrain_physical.gd
git commit -m "feat: rewrite TerrainPhysical with probe-batch cache"
```

---

## Task 5: WorldManager — wire init and per-frame dispatch

**Files:**
- Modify: `src/core/world_manager.gd`

- [ ] **Step 1: Initialize the probe pipeline in `_ready`**

In `_ready()`, after the existing `compute_device.init_*` calls (right after `compute_device.init_gen_biome_buffer()`), add:

```gdscript
	compute_device.init_terrain_probe()
```

- [ ] **Step 2: Add `_run_terrain_probes` method**

Append to `world_manager.gd`:

```gdscript
func _run_terrain_probes() -> void:
	if chunks.is_empty():
		return
	var batch := terrain_physical.prepare_probe_batch(ComputeDevice.PROBE_BUDGET)
	if batch.is_empty():
		return

	var total_count: int = 0
	for entry in batch:
		total_count += int(entry["count"])
	if total_count <= 0:
		return

	var packed_input := terrain_physical.pack_probe_input(batch, ComputeDevice.PROBE_BUDGET)
	compute_device.dispatch_terrain_probe(chunks, batch, packed_input)
	var raw := compute_device.read_terrain_probe(total_count * 4)
	terrain_physical.apply_probe_results(batch, raw)
```

- [ ] **Step 3: Call it from `_process`**

In `_process(delta)`, insert the call between the collision rebuild and the lights update. The block currently reads:

```gdscript
	_update_chunks()
	_run_simulation()
	_collision_helper.rebuild_dirty(chunks, delta)
	_update_lights()
	terrain_physical.set_center(Vector2i(tracking_position))
```

Change it to:

```gdscript
	_update_chunks()
	_run_simulation()
	_collision_helper.rebuild_dirty(chunks, delta)
	_run_terrain_probes()
	_update_lights()
	terrain_physical.set_center(Vector2i(tracking_position))
```

- [ ] **Step 4: Verify Godot still loads the project**

Run: `cd /home/jeremy/Development/gdworkflow/sandbox/top-down-rogue && godot --headless --quit 2>&1 | tail -20`

Expected: no parse errors.

- [ ] **Step 5: Commit**

```bash
git add src/core/world_manager.gd
git commit -m "feat: dispatch terrain probes per frame in WorldManager"
```

---

## Task 6: Integration check — run existing suites

**Files:** none modified.

- [ ] **Step 1: Run the full unit test suite**

Run: `cd /home/jeremy/Development/gdworkflow/sandbox/top-down-rogue && godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit 2>&1 | tail -60`

Expected: all suites pass. Of particular interest:
- `tests/unit/test_terrain_physical.gd` — the rewrite from Task 4.
- `tests/unit/test_cave_spawner.gd` — must still pass; the spawner queries `TerrainPhysical` and the test stubs that interface, so behaviour should be unchanged.

If `test_cave_spawner.gd` references `_grid` directly, switch it to use the new `apply_probe_results` path (mirror the helper batches built in `test_terrain_physical.gd`). If it only goes through `query()`, no change is needed.

- [ ] **Step 2: Commit any test updates**

If you had to adjust tests:

```bash
git add tests/unit/test_cave_spawner.gd
git commit -m "test: update cave spawner test for new TerrainPhysical cache"
```

If no test changes were needed, skip this step.

---

## Task 7: Manual smoke test

**Files:** none modified.

- [ ] **Step 1: Launch the game and verify both bug fixes**

Run: `cd /home/jeremy/Development/gdworkflow/sandbox/top-down-rogue && godot --path . 2>&1 | tail -30`

Expected manual checks (with the game running):
1. **Lava damage:** position the player into lava terrain → HP decreases over the next ~1 s. Previously it would not decrease at all.
2. **Natural enemy spawning:** explore caves outside any room for ~10 s; new enemies should appear at distances within `[spawn_min_dist, spawn_max_dist]` around the player. Previously none would spawn outside rooms.

If either check fails, capture console output and revisit Tasks 4–5.

- [ ] **Step 2: No commit needed** (manual verification only).

---

## Self-Review Notes

- **Spec coverage:**
  - Probe shader (Task 1) ✔
  - `ComputeDevice` buffers/init/free (Task 2) ✔
  - `ComputeDevice` dispatch + readback (Task 3) ✔
  - `TerrainPhysical` rewrite incl. `query`, `prepare_probe_batch`, `apply_probe_results`, `invalidate_rect`, TTL, edge case for unloaded chunks (Task 4 + tests) ✔
  - `WorldManager` `_ready` init + `_process` step ordering (Task 5) ✔
  - Integration & manual smoke (Tasks 6, 7) ✔
- **Type consistency:** the batch dictionary shape (`chunk_coord`, `world_coords`, `start`, `count`) is the same in `prepare_probe_batch`, `pack_probe_input`, `apply_probe_results`, and `dispatch_terrain_probe`. The shader push constant `(probe_start, probe_count)` matches the GDScript encoding `encode_u32(0, start); encode_u32(4, count)`.
- **No placeholders:** every step has either concrete code, an exact command, or a manual check with explicit pass/fail criteria.
