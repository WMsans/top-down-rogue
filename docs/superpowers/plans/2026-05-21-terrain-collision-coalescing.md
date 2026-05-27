# Terrain Collision Coalescing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the 28ms terrain-collision spike by coalescing GPU dispatch + readback into a single per-frame round-trip, deferring readback by one frame, adding dirty-flag tracking, and amortizing occluder polygon construction.

**Architecture:** Mirror the existing light pipeline (commits 245a8bd..0ae913c). One shared SSBO with N slots, persistent per-chunk uniform sets, one `compute_list_begin/end` per frame, dispatch N / read N+1. Dirty set drives selection so steady-state cost is ~0ms. Occluder construction runs at ≤1 chunk/frame.

**Tech Stack:** Godot 4, GDScript, GLSL compute shader, RenderingDevice low-level API, GdUnit4.

**Spec:** `docs/superpowers/specs/2026-05-21-terrain-collision-coalescing-design.md`

---

## File Structure

- `src/core/chunk.gd` — add `collider_uniform_set: RID` field.
- `src/core/compute_device.gd` — replace `collider_storage_buffer` with coalesced buffer; add `dispatch_collider_pack`, `read_collider_buffer_coalesced`, `decode_collider_slice`.
- `src/core/chunk_manager.gd` — build/free `collider_uniform_set` in chunk lifecycle.
- `shaders/compute/collider.glsl` — add push constant `slot_index`, offset writes into slot.
- `src/core/terrain_collision_helper.gd` — rewrite: dirty set, async pipeline, queues.
- `src/core/world_manager.gd` — frame flow + `mark_terrain_dirty` forwarder.
- `src/core/terrain_modifier.gd` — call `mark_terrain_dirty` after each `rd.texture_update`.
- `tests/unit/test_terrain_collision_helper.gd` — new unit tests for helper logic with a fake compute device.

---

## Constants (used throughout)

```gdscript
# In ComputeDevice
const COLLIDER_MAX_DISPATCH_PER_FRAME := 4
const COLLIDER_MAX_SEGMENTS_PER_SLOT := 4096   # matches current shader MAX_SEGMENTS
const COLLIDER_SLOT_STRIDE_BYTES := 4 + COLLIDER_MAX_SEGMENTS_PER_SLOT * 4 * 4  # header + segments
const COLLIDER_COALESCED_BUFFER_SIZE := COLLIDER_MAX_DISPATCH_PER_FRAME * COLLIDER_SLOT_STRIDE_BYTES
```

Slot N starts at byte offset `N * COLLIDER_SLOT_STRIDE_BYTES`. Each slot: `u32 segment_count` then `u32[MAX_SEGMENTS_PER_SLOT * 4]` of packed `(x1,y1,x2,y2)`.

---

## Task 1: Add coalesced collider buffer + constants to ComputeDevice

**Files:**
- Modify: `src/core/compute_device.gd` (replace `init_collider_storage_buffer`, add constants, update cleanup)

- [ ] **Step 1: Add constants near top of compute_device.gd**

Locate the existing `LIGHT_*` constants block (near the top). Add immediately below:

```gdscript
const COLLIDER_MAX_DISPATCH_PER_FRAME := 4
const COLLIDER_MAX_SEGMENTS_PER_SLOT := 4096
const COLLIDER_SLOT_STRIDE_BYTES := 4 + COLLIDER_MAX_SEGMENTS_PER_SLOT * 4 * 4
const COLLIDER_COALESCED_BUFFER_SIZE := COLLIDER_MAX_DISPATCH_PER_FRAME * COLLIDER_SLOT_STRIDE_BYTES
```

- [ ] **Step 2: Add double-buffered state vars near light state**

Find `var light_write_index := 0` (around line 110-117). Add immediately below:

```gdscript
var collider_output_buffers: Array[RID] = [RID(), RID()]
var collider_write_index: int = 0
var collider_first_frame: bool = true
# Manifest entries are [coord.x, coord.y, slot_index] triples; one per dispatched chunk.
var collider_dispatch_manifests: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
```

- [ ] **Step 3: Replace `init_collider_storage_buffer` body**

Replace the existing body (currently lines ~123-127):

```gdscript
func init_collider_storage_buffer() -> void:
	var zero := PackedByteArray()
	zero.resize(COLLIDER_COALESCED_BUFFER_SIZE)
	zero.fill(0)
	for i in range(2):
		collider_output_buffers[i] = rd.storage_buffer_create(COLLIDER_COALESCED_BUFFER_SIZE)
		rd.buffer_update(collider_output_buffers[i], 0, COLLIDER_COALESCED_BUFFER_SIZE, zero)
	collider_write_index = 0
	collider_first_frame = true
	collider_dispatch_manifests[0] = PackedInt32Array()
	collider_dispatch_manifests[1] = PackedInt32Array()
	# Legacy single buffer retained for any in-flight CPU fallback path; keep as zero RID.
	collider_storage_buffer = RID()
```

- [ ] **Step 4: Update cleanup**

Find the cleanup block (around line 407 `if collider_storage_buffer.is_valid():`). Replace with:

```gdscript
if collider_storage_buffer.is_valid():
	rd.free_rid(collider_storage_buffer)
	collider_storage_buffer = RID()
for i in range(2):
	if collider_output_buffers[i].is_valid():
		rd.free_rid(collider_output_buffers[i])
		collider_output_buffers[i] = RID()
```

- [ ] **Step 5: Run editor to confirm boot**

Run: `godot --headless --quit-after 3 --path /Users/jeremyzhao/Development/godot/top-down-rogue 2>&1 | tail -30`
Expected: no errors related to compute_device or collider buffer init.

- [ ] **Step 6: Commit**

```bash
git add src/core/compute_device.gd
git commit -m "perf(collision): add coalesced double-buffered collider SSBOs"
```

---

## Task 2: Add `collider_uniform_set` field to Chunk

**Files:**
- Modify: `src/core/chunk.gd`

- [ ] **Step 1: Add field**

Add after `var light_pack_uniform_sets: Array[RID] = [RID(), RID()]`:

```gdscript
# Two persistent uniform sets — one per write-buffer parity, binding rd_texture + collider_output_buffer.
var collider_uniform_sets: Array[RID] = [RID(), RID()]
```

- [ ] **Step 2: Commit**

```bash
git add src/core/chunk.gd
git commit -m "perf(collision): add persistent collider uniform set field to Chunk"
```

---

## Task 3: Build & free `collider_uniform_sets` in ChunkManager

**Files:**
- Modify: `src/core/chunk_manager.gd`

- [ ] **Step 1: Add `build_collider_uniform_sets` method**

Add after the existing `build_light_pack_uniform_set` method (search for `func build_light_pack_uniform_set`):

```gdscript
func build_collider_uniform_sets(chunk: Chunk) -> void:
	var compute: ComputeDevice = world_manager.compute_device
	for i in range(2):
		if chunk.collider_uniform_sets[i].is_valid():
			world_manager.rd.free_rid(chunk.collider_uniform_sets[i])
			chunk.collider_uniform_sets[i] = RID()
		if not compute.collider_output_buffers[i].is_valid():
			continue
		var uniforms: Array[RDUniform] = []
		var u0 := RDUniform.new()
		u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u0.binding = 0
		u0.add_id(chunk.rd_texture)
		uniforms.append(u0)
		var u1 := RDUniform.new()
		u1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u1.binding = 1
		u1.add_id(compute.collider_output_buffers[i])
		uniforms.append(u1)
		chunk.collider_uniform_sets[i] = world_manager.rd.uniform_set_create(uniforms, compute.collider_shader, 0)
```

- [ ] **Step 2: Call it in `load_chunk`**

In `load_chunk`, find the line `build_light_pack_uniform_set(chunk)` (around line 124). Add immediately below:

```gdscript
	build_collider_uniform_sets(chunk)
```

- [ ] **Step 3: Free in `free_chunk_uniform_sets`**

In `free_chunk_uniform_sets` (around line 133-140), add inside the function body, after the existing `light_pack_uniform_sets` cleanup loop:

```gdscript
	for i in range(2):
		if chunk.collider_uniform_sets[i].is_valid():
			world_manager.rd.free_rid(chunk.collider_uniform_sets[i])
			chunk.collider_uniform_sets[i] = RID()
```

- [ ] **Step 4: Boot check**

Run: `godot --headless --quit-after 3 --path /Users/jeremyzhao/Development/godot/top-down-rogue 2>&1 | tail -30`
Expected: no errors. Chunk creation logs should be clean.

- [ ] **Step 5: Commit**

```bash
git add src/core/chunk_manager.gd
git commit -m "perf(collision): persistent collider uniform sets per chunk"
```

---

## Task 4: Update collider.glsl for slot-indexed writes

**Files:**
- Modify: `shaders/compute/collider.glsl`

- [ ] **Step 1: Replace the SegmentBuffer layout and add push constant**

Replace lines 8-12 (the `layout(std430, ...)` block) with:

```glsl
layout(std430, binding = 1) buffer SegmentBuffer {
	uint data[];
} segment_buffer;

layout(push_constant, std430) uniform Params {
	uint slot_index;
	uint _pad0;
	uint _pad1;
	uint _pad2;
} pc;
```

Note: the count is now part of `data[]` at `slot_base`, indexed via offset arithmetic. This is necessary because `atomicAdd` requires the counter to live inside the same SSBO array.

- [ ] **Step 2: Add slot-base helper constants near MAX_SEGMENTS**

After the existing `const uint MAX_SEGMENTS = 4096u;` line, add:

```glsl
// Slot layout: 1 u32 header (segment count) + MAX_SEGMENTS * 4 u32 of segment data.
// data[] is shared across slots; each slot starts at slot_base.
const uint SLOT_STRIDE_U32 = 1u + MAX_SEGMENTS * 4u;
```

- [ ] **Step 3: Replace the atomicAdd write block at the bottom of main()**

Find the block:

```glsl
	for (uint s = 0u; s < num_segments; s++) {
		uint idx = atomicAdd(segment_buffer.count, 4u);
		if (idx + 4u > MAX_SEGMENTS * 4u) {
			return;
		}
		segment_buffer.data[idx + 0] = segments[s * 4 + 0];
		segment_buffer.data[idx + 1] = segments[s * 4 + 1];
		segment_buffer.data[idx + 2] = segments[s * 4 + 2];
		segment_buffer.data[idx + 3] = segments[s * 4 + 3];
	}
```

Replace with:

```glsl
	uint slot_base = pc.slot_index * SLOT_STRIDE_U32;
	uint segments_base = slot_base + 1u;
	uint cap_u32 = MAX_SEGMENTS * 4u;

	for (uint s = 0u; s < num_segments; s++) {
		uint segment_idx = atomicAdd(segment_buffer.data[slot_base], 1u);
		uint write_off = segment_idx * 4u;
		if (write_off + 4u > cap_u32) {
			return;
		}
		segment_buffer.data[segments_base + write_off + 0u] = segments[s * 4 + 0];
		segment_buffer.data[segments_base + write_off + 1u] = segments[s * 4 + 1];
		segment_buffer.data[segments_base + write_off + 2u] = segments[s * 4 + 2];
		segment_buffer.data[segments_base + write_off + 3u] = segments[s * 4 + 3];
	}
```

- [ ] **Step 4: Boot to compile the shader**

Run: `godot --headless --quit-after 3 --path /Users/jeremyzhao/Development/godot/top-down-rogue 2>&1 | grep -iE "error|shader" | head -20`
Expected: no compile errors for `collider.glsl`.

- [ ] **Step 5: Commit**

```bash
git add shaders/compute/collider.glsl
git commit -m "perf(collision): slot-indexed writes in collider compute shader"
```

---

## Task 5: Add `dispatch_collider_pack` to ComputeDevice

**Files:**
- Modify: `src/core/compute_device.gd`

- [ ] **Step 1: Add method after `dispatch_light_pack`**

Add this new method after the existing `dispatch_light_pack` function:

```gdscript
func dispatch_collider_pack(chunks: Dictionary, coords: Array) -> void:
	var manifest := PackedInt32Array()

	if coords.is_empty():
		collider_dispatch_manifests[collider_write_index] = manifest
		return

	# Zero all slot headers in the write buffer (one u32 per slot).
	var header_clear := PackedByteArray()
	header_clear.resize(4)
	header_clear.encode_u32(0, 0)
	for slot in range(COLLIDER_MAX_DISPATCH_PER_FRAME):
		var slot_offset := slot * COLLIDER_SLOT_STRIDE_BYTES
		rd.buffer_update(collider_output_buffers[collider_write_index], slot_offset, 4, header_clear)

	var push_data := PackedByteArray()
	push_data.resize(16)
	push_data.fill(0)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, collider_pipeline)

	var slot_idx := 0
	for coord in coords:
		if slot_idx >= COLLIDER_MAX_DISPATCH_PER_FRAME:
			push_warning("collider_pack: dispatch list exceeds COLLIDER_MAX_DISPATCH_PER_FRAME, dropping extras")
			break
		var chunk: Chunk = chunks.get(coord, null)
		if chunk == null:
			continue
		var us: RID = chunk.collider_uniform_sets[collider_write_index]
		if not us.is_valid():
			continue

		rd.compute_list_bind_uniform_set(compute_list, us, 0)
		push_data.encode_u32(0, slot_idx)
		rd.compute_list_set_push_constant(compute_list, push_data, push_data.size())
		rd.compute_list_dispatch(compute_list, 16, 16, 1)

		manifest.append(coord.x)
		manifest.append(coord.y)
		manifest.append(slot_idx)
		slot_idx += 1

	rd.compute_list_end()

	collider_dispatch_manifests[collider_write_index] = manifest
```

- [ ] **Step 2: Commit**

```bash
git add src/core/compute_device.gd
git commit -m "perf(collision): coalesced dispatch_collider_pack"
```

---

## Task 6: Add `read_collider_buffer_coalesced` + decoder to ComputeDevice

**Files:**
- Modify: `src/core/compute_device.gd`

- [ ] **Step 1: Add read + decode methods after `dispatch_collider_pack`**

```gdscript
# Returns Dictionary[Vector2i, PackedVector2Array] of segments per dispatched chunk.
# Returns empty dict on first frame (no prior dispatch to read).
func read_collider_buffer_coalesced() -> Dictionary:
	if collider_first_frame:
		collider_first_frame = false
		collider_write_index = 1 - collider_write_index
		return {}

	var read_index := 1 - collider_write_index
	var manifest: PackedInt32Array = collider_dispatch_manifests[read_index]
	if manifest.is_empty():
		collider_write_index = 1 - collider_write_index
		return {}

	var entry_count := manifest.size() / 3
	var bytes_needed := entry_count * COLLIDER_SLOT_STRIDE_BYTES
	if entry_count == COLLIDER_MAX_DISPATCH_PER_FRAME:
		bytes_needed = COLLIDER_COALESCED_BUFFER_SIZE
	var data: PackedByteArray = rd.buffer_get_data(collider_output_buffers[read_index], 0, bytes_needed)

	collider_write_index = 1 - collider_write_index

	var result: Dictionary = {}
	for i in range(entry_count):
		var cx := manifest[i * 3]
		var cy := manifest[i * 3 + 1]
		var slot := manifest[i * 3 + 2]
		var coord := Vector2i(cx, cy)
		result[coord] = decode_collider_slice(data, slot)
	return result


# Decodes one slot into a PackedVector2Array of (x1,y1,x2,y2) segments flattened.
func decode_collider_slice(data: PackedByteArray, slot: int) -> PackedVector2Array:
	var segments := PackedVector2Array()
	var slot_offset := slot * COLLIDER_SLOT_STRIDE_BYTES
	if slot_offset + 4 > data.size():
		return segments
	var count: int = data.decode_u32(slot_offset)
	if count == 0:
		return segments
	count = mini(count, COLLIDER_MAX_SEGMENTS_PER_SLOT)
	var seg_base := slot_offset + 4
	for i in range(count):
		var off := seg_base + i * 16
		if off + 16 > data.size():
			break
		var x1 := float(data.decode_u32(off))
		var y1 := float(data.decode_u32(off + 4))
		var x2 := float(data.decode_u32(off + 8))
		var y2 := float(data.decode_u32(off + 12))
		segments.append(Vector2(x1, y1))
		segments.append(Vector2(x2, y2))
	return segments
```

- [ ] **Step 2: Commit**

```bash
git add src/core/compute_device.gd
git commit -m "perf(collision): read_collider_buffer_coalesced + slice decoder"
```

---

## Task 7: Write failing unit test for `TerrainCollisionHelper` dirty tracking

**Files:**
- Create: `tests/unit/test_terrain_collision_helper.gd`

- [ ] **Step 1: Create the test file with a fake compute device**

```gdscript
extends GdUnitTestSuite

const TerrainCollisionHelper := preload("res://src/core/terrain_collision_helper.gd")

class FakeComputeDevice extends RefCounted:
	var dispatched_coords: Array = []
	var pending_readback: Dictionary = {}
	func dispatch_collider_pack(_chunks: Dictionary, coords: Array) -> void:
		dispatched_coords = coords.duplicate()
	func read_collider_buffer_coalesced() -> Dictionary:
		var out := pending_readback.duplicate()
		pending_readback = {}
		return out

class FakeWorldManager extends RefCounted:
	var compute_device
	var chunks: Dictionary = {}
	var dirty_marks: Array = []
	func mark_terrain_dirty(coord: Vector2i) -> void:
		dirty_marks.append(coord)


func _make_helper() -> TerrainCollisionHelper:
	var wm := FakeWorldManager.new()
	wm.compute_device = FakeComputeDevice.new()
	var h := TerrainCollisionHelper.new()
	h.world_manager = wm
	return h


func test_empty_dirty_set_does_nothing() -> void:
	var h := _make_helper()
	h.rebuild_dirty({}, 0.016)
	assert_that(h.world_manager.compute_device.dispatched_coords).is_empty()


func test_mark_dirty_adds_to_set() -> void:
	var h := _make_helper()
	h.mark_dirty(Vector2i(1, 2))
	h.mark_dirty(Vector2i(1, 2))  # duplicate is idempotent
	h.mark_dirty(Vector2i(3, 4))
	assert_that(h._dirty_chunks.size()).is_equal(2)


func test_dispatch_drains_dirty_up_to_cap() -> void:
	var h := _make_helper()
	for x in range(6):
		h.mark_dirty(Vector2i(x, 0))
		h.world_manager.chunks[Vector2i(x, 0)] = "dummy"
	h.rebuild_dirty(h.world_manager.chunks, 0.016)
	# MAX_DISPATCH_PER_FRAME = 4
	assert_that(h.world_manager.compute_device.dispatched_coords.size()).is_equal(4)
	assert_that(h._dirty_chunks.size()).is_equal(2)


func test_on_chunk_unloaded_purges_state() -> void:
	var h := _make_helper()
	var c := Vector2i(7, 7)
	h.mark_dirty(c)
	h._in_flight = [c]
	h._pending_collision_builds = [c]
	h._pending_occluder_builds = [c]
	h._pending_segments[c] = PackedVector2Array()
	h.on_chunk_unloaded(c)
	assert_that(h._dirty_chunks.has(c)).is_false()
	assert_that(h._in_flight.has(c)).is_false()
	assert_that(h._pending_collision_builds.has(c)).is_false()
	assert_that(h._pending_occluder_builds.has(c)).is_false()
	assert_that(h._pending_segments.has(c)).is_false()
```

- [ ] **Step 2: Run the test — expect failure (method/fields don't exist yet)**

Run: `godot --headless --path /Users/jeremyzhao/Development/godot/top-down-rogue -s addons/gdUnit4/bin/GdUnitCmdTool.gd -- -a tests/unit/test_terrain_collision_helper.gd 2>&1 | tail -40`
Expected: FAIL — `mark_dirty`, `_dirty_chunks`, `on_chunk_unloaded`, etc. don't exist yet.

- [ ] **Step 3: Commit test (red)**

```bash
git add tests/unit/test_terrain_collision_helper.gd
git commit -m "test(collision): failing tests for helper dirty tracking"
```

---

## Task 8: Rewrite `TerrainCollisionHelper`

**Files:**
- Modify: `src/core/terrain_collision_helper.gd` (full rewrite, keep CPU fallback)

- [ ] **Step 1: Replace file contents**

```gdscript
class_name TerrainCollisionHelper
extends RefCounted

const CHUNK_SIZE := 256
const MAX_DISPATCH_PER_FRAME := 4

var world_manager  # WorldManager (Node2D)

var _dirty_chunks: Dictionary = {}             # Vector2i -> true
var _in_flight: Array = []                     # Array[Vector2i] dispatched last frame
var _pending_collision_builds: Array = []      # Array[Vector2i] ready to build shapes
var _pending_occluder_builds: Array = []       # Array[Vector2i] ready to build occluders
var _pending_segments: Dictionary = {}         # Vector2i -> PackedVector2Array
var _dispatch_cursor: int = 0


func mark_dirty(coord: Vector2i) -> void:
	_dirty_chunks[coord] = true


func on_chunk_unloaded(coord: Vector2i) -> void:
	_dirty_chunks.erase(coord)
	_in_flight.erase(coord)
	_pending_collision_builds.erase(coord)
	_pending_occluder_builds.erase(coord)
	_pending_segments.erase(coord)


func rebuild_dirty(chunks: Dictionary, _delta: float) -> void:
	# 1. Consume prior frame's readback.
	_consume_readback(chunks)

	# 2. Amortize: drain one occluder build per frame.
	_drain_one_occluder(chunks)

	# 3. Drain all pending collision shape builds.
	_drain_collision_builds(chunks)

	# 4. Dispatch up to MAX_DISPATCH_PER_FRAME newly-selected dirty chunks.
	_dispatch_next_batch(chunks)


func _consume_readback(chunks: Dictionary) -> void:
	var compute = world_manager.compute_device
	var readback: Dictionary = compute.read_collider_buffer_coalesced()
	_in_flight.clear()
	for coord in readback:
		if not chunks.has(coord):
			continue
		var segments: PackedVector2Array = readback[coord]
		_pending_segments[coord] = segments
		_pending_collision_builds.append(coord)
		_pending_occluder_builds.append(coord)


func _dispatch_next_batch(chunks: Dictionary) -> void:
	if _dirty_chunks.is_empty():
		world_manager.compute_device.dispatch_collider_pack(chunks, [])
		return

	var coords: Array = []
	var keys: Array = _dirty_chunks.keys()
	# Stable selection: take up to MAX in iteration order, skipping unloaded chunks.
	for k in keys:
		if coords.size() >= MAX_DISPATCH_PER_FRAME:
			break
		if not chunks.has(k):
			_dirty_chunks.erase(k)
			continue
		coords.append(k)

	for c in coords:
		_dirty_chunks.erase(c)

	world_manager.compute_device.dispatch_collider_pack(chunks, coords)
	_in_flight = coords


func _drain_collision_builds(chunks: Dictionary) -> void:
	for coord in _pending_collision_builds:
		if not chunks.has(coord):
			_pending_segments.erase(coord)
			continue
		var chunk: Chunk = chunks[coord]
		var segments: PackedVector2Array = _pending_segments.get(coord, PackedVector2Array())
		_build_collision_shape(chunk, segments)
	_pending_collision_builds.clear()


func _drain_one_occluder(chunks: Dictionary) -> void:
	while not _pending_occluder_builds.is_empty():
		var coord: Vector2i = _pending_occluder_builds[0]
		_pending_occluder_builds.remove_at(0)
		if not chunks.has(coord):
			continue
		var chunk: Chunk = chunks[coord]
		var segments: PackedVector2Array = _pending_segments.get(coord, PackedVector2Array())
		_build_occluders(chunk, segments)
		# Clear segments only after both queues consumed.
		if not _pending_collision_builds.has(coord):
			_pending_segments.erase(coord)
		return  # Only one per frame.


func _build_collision_shape(chunk: Chunk, segments: PackedVector2Array) -> void:
	# Clear old collision children.
	for child in chunk.static_body.get_children():
		child.queue_free()

	if segments.size() < 4:
		return

	var world_offset := chunk.coord * CHUNK_SIZE
	var collision_shape := TerrainCollider.build_from_segments(segments, chunk.static_body, world_offset)
	if collision_shape != null:
		chunk.static_body.add_child(collision_shape)


func _build_occluders(chunk: Chunk, segments: PackedVector2Array) -> void:
	for occluder in chunk.occluder_instances:
		if is_instance_valid(occluder):
			occluder.queue_free()
	chunk.occluder_instances.clear()

	if segments.size() < 4:
		return

	var polygons := TerrainCollider.create_occluder_polygons(segments)
	var chunk_pos := Vector2(chunk.coord.x * CHUNK_SIZE, chunk.coord.y * CHUNK_SIZE)
	for poly in polygons:
		var occ := LightOccluder2D.new()
		occ.position = chunk_pos
		occ.occluder = poly
		world_manager.collision_container.add_child(occ)
		chunk.occluder_instances.append(occ)


# CPU fallback retained for explicit invocation (e.g. by manual repair tools).
func rebuild_chunk_collision_cpu(chunk: Chunk) -> void:
	var chunk_data: PackedByteArray = world_manager.rd.texture_get_data(chunk.rd_texture, 0)
	var material_data := PackedByteArray()
	material_data.resize(CHUNK_SIZE * CHUNK_SIZE)
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			var src_idx := (y * CHUNK_SIZE + x) * 4
			var mat: int = chunk_data[src_idx]
			material_data[y * CHUNK_SIZE + x] = mat if MaterialRegistry.has_collider(mat) else 0

	var world_offset := chunk.coord * CHUNK_SIZE
	for child in chunk.static_body.get_children():
		child.queue_free()

	var collision_shape := TerrainCollider.build_collision(material_data, CHUNK_SIZE, chunk.static_body, world_offset)
	if collision_shape != null:
		chunk.static_body.add_child(collision_shape)
```

- [ ] **Step 2: Run unit tests — expect PASS**

Run: `godot --headless --path /Users/jeremyzhao/Development/godot/top-down-rogue -s addons/gdUnit4/bin/GdUnitCmdTool.gd -- -a tests/unit/test_terrain_collision_helper.gd 2>&1 | tail -40`
Expected: all 4 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add src/core/terrain_collision_helper.gd
git commit -m "perf(collision): rewrite helper with dirty tracking, async readback, amortized occluders"
```

---

## Task 9: Wire `mark_terrain_dirty` into WorldManager and call from helper init

**Files:**
- Modify: `src/core/world_manager.gd`

- [ ] **Step 1: Add forwarder method**

In world_manager.gd, add this method anywhere appropriate (e.g. near the existing helper setup at line ~50):

```gdscript
func mark_terrain_dirty(coord: Vector2i) -> void:
	if _collision_helper != null:
		_collision_helper.mark_dirty(coord)
```

- [ ] **Step 2: Verify rebuild_dirty call site is unchanged**

The existing call `_collision_helper.rebuild_dirty(chunks, delta)` (~line 82) still works — the signature is unchanged.

- [ ] **Step 3: Boot check**

Run: `godot --headless --quit-after 3 --path /Users/jeremyzhao/Development/godot/top-down-rogue 2>&1 | tail -20`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add src/core/world_manager.gd
git commit -m "perf(collision): mark_terrain_dirty forwarder on WorldManager"
```

---

## Task 10: Mark dirty after terrain texture writes in TerrainModifier

**Files:**
- Modify: `src/core/terrain_modifier.gd`

- [ ] **Step 1: Find every `rd.texture_update(chunk.rd_texture, 0, data)` site**

There are ~5+ sites at lines 50, 89, 158, 221, 260, 346 (approximate — grep to confirm). For each one, insert immediately after the line:

```gdscript
			world_manager.mark_terrain_dirty(chunk.coord)
```

Match the indentation of the surrounding block (one level inside the `if`/loop).

- [ ] **Step 2: Confirm all sites covered**

Run: `grep -n "rd.texture_update.*chunk.rd_texture" src/core/terrain_modifier.gd`
For each line returned, the next line should now be `world_manager.mark_terrain_dirty(chunk.coord)`.

- [ ] **Step 3: Boot check**

Run: `godot --headless --quit-after 3 --path /Users/jeremyzhao/Development/godot/top-down-rogue 2>&1 | tail -20`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add src/core/terrain_modifier.gd
git commit -m "perf(collision): mark chunks dirty after terrain texture writes"
```

---

## Task 11: Mark dirty on chunk generation in ChunkManager

**Files:**
- Modify: `src/core/chunk_manager.gd`

- [ ] **Step 1: Find chunk generation completion site**

Look for where a chunk's initial terrain data is populated (search for `world_manager.rd.texture_update` or similar within `chunk_manager.gd`, or the post-generation hook in `load_chunk`).

If chunk generation is performed by `ComputeDevice` dispatches (e.g. `generate_chunk`), mark dirty after the dispatch completes — at the end of `load_chunk`, add:

```gdscript
	world_manager.mark_terrain_dirty(coord)
```

If multi-step generation runs over several frames, mark dirty at each completion step.

- [ ] **Step 2: Boot check & confirm collision builds on a fresh chunk**

Run the game briefly (3 seconds headless) and verify chunks get collision built:

Run: `godot --headless --quit-after 5 --path /Users/jeremyzhao/Development/godot/top-down-rogue 2>&1 | tail -20`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add src/core/chunk_manager.gd
git commit -m "perf(collision): mark chunk dirty after initial generation"
```

---

## Task 12: Mark dirty after compute-shader terrain writes

**Files:**
- Modify: `src/core/compute_device.gd`

- [ ] **Step 1: Identify GPU terrain-write dispatches**

Search for compute dispatches that write into `chunk.rd_texture`:

Run: `grep -n "chunk.rd_texture\|add_id(chunk.rd_texture)" src/core/compute_device.gd`

The relevant sites (per the spec exploration) are around lines 317 and 733 — these bind `rd_texture` as a write target. For each dispatch that potentially writes terrain:

After the `rd.compute_list_end()` of the dispatch, iterate the dispatched chunks list and call:

```gdscript
	for coord in dispatched_coords:
		world_manager.mark_terrain_dirty(coord)
```

(Use whatever variable in scope holds the dispatched coords — typically `chunks` keys or an explicit list passed in.)

- [ ] **Step 2: Verify world_manager is reachable**

ComputeDevice already references `world_manager` elsewhere (check by grepping `world_manager` in `compute_device.gd`). If not in scope, pass it via the existing helper or signal.

- [ ] **Step 3: Boot + run check**

Run: `godot --headless --quit-after 5 --path /Users/jeremyzhao/Development/godot/top-down-rogue 2>&1 | tail -20`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add src/core/compute_device.gd
git commit -m "perf(collision): mark dirty after GPU terrain writes"
```

---

## Task 13: Wire `on_chunk_unloaded` from ChunkManager

**Files:**
- Modify: `src/core/chunk_manager.gd`

- [ ] **Step 1: Call helper purge before freeing chunk resources**

In `unload_chunk` (around line 127), before the call to `free_chunk_resources(chunk)`, add:

```gdscript
	if world_manager._collision_helper != null:
		world_manager._collision_helper.on_chunk_unloaded(coord)
```

- [ ] **Step 2: Boot + stream check**

Run: `godot --headless --quit-after 8 --path /Users/jeremyzhao/Development/godot/top-down-rogue 2>&1 | tail -30`
Expected: no errors after chunk unload events.

- [ ] **Step 3: Commit**

```bash
git add src/core/chunk_manager.gd
git commit -m "perf(collision): purge helper state on chunk unload"
```

---

## Task 14: Manual perf verification

**Files:** none (manual run)

- [ ] **Step 1: Launch editor and reproduce the original profile scene**

Run: `godot --path /Users/jeremyzhao/Development/godot/top-down-rogue` (open editor manually if interactive verification needed).

Load the same scene used in the bug report screenshot. Open the Debugger → Profiler panel. Start profiling.

- [ ] **Step 2: Verify hotspot reduction**

Check the script function profiler:

- `TerrainCollisionHelper.rebuild_dirty` should drop out of the top 5.
- `rebuild_chunk_collision_gpu` should no longer appear (method removed).
- Steady-state frame time should be ≤16.6ms.
- During terrain modification bursts (digging/destruction), frame time should stay ≤20ms.

- [ ] **Step 3: Record results**

If frame time meets target, mark this task complete. If not, capture the new profile and open an investigation — likely candidates: occluder polygon construction still too heavy (consider further amortization), or another non-collision hotspot is now dominant.

- [ ] **Step 4: Commit any tuning changes**

If `MAX_DISPATCH_PER_FRAME` was tuned, commit:

```bash
git add src/core/compute_device.gd
git commit -m "perf(collision): tune dispatch cap to N"
```

---

## Notes for the implementer

- **Don't skip Task 4 (shader change).** Without slot-indexed writes, all dispatches race on the same `count` field and you get garbage segment counts.
- **Don't skip dirty marking (Tasks 10–12).** If you skip these, the helper will work but never rebuild collision after the first frame, breaking the game.
- **The old `rebuild_chunk_collision_gpu` and `parse_segment_buffer` methods are gone after Task 8.** Anything that called them externally would break — grep for callers before assuming nothing references them.
- **`collider_storage_buffer` is retained as a zero RID** in Task 1 step 3 to avoid breaking any other code that referenced it. Once Task 8 lands, grep for remaining references and remove them in a follow-up cleanup if desired (not required by this plan).
