# Coalesced + Double-Buffered Light SSBO Readback — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the ~4.21 ms `rd.buffer_get_data` stall in `_update_lights` by coalescing all chunks' light-pack outputs into a single double-buffered SSBO, so each frame issues at most one GPU→CPU readback against a buffer the GPU has already finished with.

**Architecture:** Replace per-`Chunk` `light_output_buffer` with two shared SSBOs in `ComputeDevice`. The light-pack compute shader takes a new `slice_idx` push constant and writes into `output[slice_idx * 16 + cell_idx]`. Each frame, dispatches go to `light_output_buffers[write_idx]`; the CPU reads `light_output_buffers[1 - write_idx]` once and decodes per-chunk slices using a manifest recorded at dispatch time. After the read, the write index flips. First frame is guarded the same way `terrain_probe_first_frame` guards its read.

**Tech Stack:** Godot 4 GDScript, `RenderingDevice` compute, GLSL compute shader.

**Source spec:** `docs/superpowers/specs/2026-05-20-coalesced-light-readback-design.md`

---

## File Inventory

- **Modify:** `src/core/compute_device.gd` — new constants, shared SSBO allocation, new dispatch/read APIs, slice decode helper.
- **Modify:** `shaders/compute/light_pack.glsl` — add `slice_idx` push constant; write to slice offset.
- **Modify:** `src/core/chunk.gd` — remove `light_output_buffer`, replace `light_pack_uniform_set: RID` with `light_pack_uniform_sets: Array[RID]` (size 2).
- **Modify:** `src/core/chunk_manager.gd` — drop per-chunk light buffer allocation/free, build two uniform sets per chunk (one per buffer index).
- **Modify:** `src/core/world_manager.gd` — rewrite `_update_lights`, remove `_light_readback_counter`, reset/teardown updates.
- **Modify (test):** `tests/unit/test_light_decode_hazard.gd` — keep coverage for the slice decoder.

---

## Testing Approach

This is a GPU pipeline refactor with one CPU-decodable helper. Unit-testable surface: the slice decoder (extending `test_light_decode_hazard.gd`). Pipeline correctness and the perf win are verified by running the editor and checking the profiler — there is no headless GPU harness in this repo.

After each integration task, run:

```bash
# Run the unit suite (must stay green)
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit
```

For the final perf check, the user runs the editor with the profiler open and confirms `ComputeDevice.read...` drops below 0.5 ms and frame time clears 16 ms with margin. This is called out as a step the user must perform (Task 7).

---

## Task 1: Add coalesced-buffer constants and storage in `ComputeDevice`

**Files:**
- Modify: `src/core/compute_device.gd` (constants block at top, fields, new init function)

- [ ] **Step 1: Add constants and fields**

In `src/core/compute_device.gd`, just after the existing light-related constants (around line 39, after `const LIGHT_CELLS_Y := 4`), add:

```gdscript
const LIGHT_MAX_ACTIVE_CHUNKS := 32
const LIGHT_SHARED_BUFFER_SIZE := LIGHT_MAX_ACTIVE_CHUNKS * LIGHT_OUTPUT_SIZE  # 32 * 192 = 6144 bytes
```

Then, just after `var light_pack_pipeline: RID` (around line 17), add new fields:

```gdscript
var light_output_buffers: Array[RID] = [RID(), RID()]
var light_write_index: int = 0
var light_first_frame: bool = true
# Manifest per buffer: flat PackedInt32Array of [chunk_x, chunk_y, slice_idx, ...]
var light_dispatch_manifests: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
```

- [ ] **Step 2: Add init function for the shared buffers**

Add this new function in `src/core/compute_device.gd` after `init_dummy_texture()` (around line 100):

```gdscript
func init_light_shared_buffers() -> void:
	var zero := PackedByteArray()
	zero.resize(LIGHT_SHARED_BUFFER_SIZE)
	zero.fill(0)
	for i in range(2):
		light_output_buffers[i] = rd.storage_buffer_create(LIGHT_SHARED_BUFFER_SIZE)
		rd.buffer_update(light_output_buffers[i], 0, LIGHT_SHARED_BUFFER_SIZE, zero)
	light_write_index = 0
	light_first_frame = true
	light_dispatch_manifests[0] = PackedInt32Array()
	light_dispatch_manifests[1] = PackedInt32Array()
```

- [ ] **Step 3: Wire the init into `WorldManager._ready`**

In `src/core/world_manager.gd`, inside `_ready()`, just after the existing line `compute_device.init_terrain_probe()` (around line 40), add:

```gdscript
	compute_device.init_light_shared_buffers()
```

- [ ] **Step 4: Free the buffers in `free_resources` (if present)**

Search `src/core/compute_device.gd` for `func free_resources`. If it exists, add to it:

```gdscript
	for i in range(2):
		if light_output_buffers[i].is_valid():
			rd.free_rid(light_output_buffers[i])
			light_output_buffers[i] = RID()
```

If `free_resources` does not exist, skip this step — the existing teardown will leak only on engine exit, which matches the current terrain-probe pattern.

- [ ] **Step 5: Verify the project still loads**

Run:

```bash
godot --headless --path . --quit-after 2
```

Expected: exits cleanly with no errors mentioning `light_output_buffers` or `LIGHT_SHARED_BUFFER_SIZE`. (Existing per-chunk `light_output_buffer` is still in use — that's intentional, removed in Task 5.)

- [ ] **Step 6: Commit**

```bash
git add src/core/compute_device.gd src/core/world_manager.gd
git commit -m "perf(lights): allocate coalesced double-buffered light SSBOs"
```

---

## Task 2: Update `light_pack.glsl` to write into a slice

**Files:**
- Modify: `shaders/compute/light_pack.glsl`

- [ ] **Step 1: Add `slice_idx` to the push constant**

In `shaders/compute/light_pack.glsl`, replace the `PushConstants` block:

```glsl
layout(push_constant, std430) uniform PushConstants {
	ivec2 chunk_coord;
	uint slice_idx;
	uint _pad0;
} pc;
```

(Total still 16 bytes: `ivec2` = 8, `uint` = 4, `uint` = 4.)

- [ ] **Step 2: Write to the slice offset**

Still in `light_pack.glsl`, inside `main()` at the `if (thread_idx == 0u)` block, replace every `output_data.cells[cell_idx]` with `output_data.cells[pc.slice_idx * 16u + cell_idx]`. After the change, that block reads:

```glsl
	if (thread_idx == 0u) {
		if (cell_idx >= CELLS_X * CELLS_Y) return;
		uint count = s_counts[0];
		uint out_idx = pc.slice_idx * 16u + cell_idx;
		if (count < 4u) {
			output_data.cells[out_idx].packed_count_glow = 0u;
			output_data.cells[out_idx].packed_pos = 0u;
		} else {
			uint avg_x = s_sum_x[0] / count;
			uint avg_y = s_sum_y[0] / count;
			uint avg_glow_raw = s_sum_glow[0] / count;
			output_data.cells[out_idx].packed_count_glow = (avg_glow_raw << 16) | (count & 0xFFFFu);
			output_data.cells[out_idx].packed_pos = (avg_y << 16) | (avg_x & 0xFFFFu);
		}
		output_data.cells[out_idx].hazard_mask = s_hazard[0];
	}
```

- [ ] **Step 3: Verify the shader compiles**

Run:

```bash
godot --headless --path . --quit-after 2
```

Expected: no shader compile errors in the console for `light_pack.glsl`. (Runtime behavior will be wrong until Task 4 supplies `slice_idx`, but the next task pairs the dispatch update.)

- [ ] **Step 4: Commit**

```bash
git add shaders/compute/light_pack.glsl
git commit -m "perf(lights): light_pack shader writes to coalesced slice"
```

---

## Task 3: Per-chunk uniform sets bind shared buffers (one per index)

**Files:**
- Modify: `src/core/chunk.gd`
- Modify: `src/core/chunk_manager.gd`

- [ ] **Step 1: Replace `light_pack_uniform_set` with an array in `Chunk`**

In `src/core/chunk.gd`, replace lines 14–15:

```gdscript
var light_output_buffer: RID
var light_pack_uniform_set: RID
```

with:

```gdscript
var light_pack_uniform_sets: Array[RID] = [RID(), RID()]
```

(`light_output_buffer` is intentionally removed; it's no longer used.)

- [ ] **Step 2: Update `build_light_pack_uniform_set` to build two sets bound to the shared buffers**

In `src/core/chunk_manager.gd`, replace the entire `build_light_pack_uniform_set` function (currently around lines 239–259):

```gdscript
func build_light_pack_uniform_set(chunk: Chunk) -> void:
	var compute: ComputeDevice = world_manager.compute_device

	for i in range(2):
		if chunk.light_pack_uniform_sets[i].is_valid():
			world_manager.rd.free_rid(chunk.light_pack_uniform_sets[i])
			chunk.light_pack_uniform_sets[i] = RID()

	for i in range(2):
		var u0 := RDUniform.new()
		u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u0.binding = 0
		u0.add_id(chunk.rd_texture)

		var u1 := RDUniform.new()
		u1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u1.binding = 1
		u1.add_id(compute.light_output_buffers[i])

		var uniforms: Array[RDUniform] = [u0, u1]
		chunk.light_pack_uniform_sets[i] = world_manager.rd.uniform_set_create(uniforms, compute.light_pack_shader, 0)
```

- [ ] **Step 3: Stop allocating per-chunk `light_output_buffer` in `create_chunk`**

In `src/core/chunk_manager.gd`, delete lines 74–79 (the block that creates and zeroes `chunk.light_output_buffer`):

```gdscript
	var light_output_size := compute.LIGHT_OUTPUT_SIZE
	chunk.light_output_buffer = world_manager.rd.storage_buffer_create(light_output_size)
	var light_zero := PackedByteArray()
	light_zero.resize(light_output_size)
	light_zero.fill(0)
	world_manager.rd.buffer_update(chunk.light_output_buffer, 0, light_output_size, light_zero)
```

- [ ] **Step 4: Update `free_chunk_uniform_sets` and `free_chunk_body`**

In `src/core/chunk_manager.gd`, replace the `light_pack_uniform_set` cleanup in `free_chunk_uniform_sets` (lines 144–146):

```gdscript
	for i in range(2):
		if chunk.light_pack_uniform_sets[i].is_valid():
			world_manager.rd.free_rid(chunk.light_pack_uniform_sets[i])
			chunk.light_pack_uniform_sets[i] = RID()
```

And delete the `light_output_buffer` block in `free_chunk_body` (lines 172–174):

```gdscript
	if chunk.light_output_buffer.is_valid():
		world_manager.rd.free_rid(chunk.light_output_buffer)
		chunk.light_output_buffer = RID()
```

- [ ] **Step 5: Verify no other references**

Run:

```bash
grep -rn "light_output_buffer\b" src/ shaders/ tests/
```

Expected: zero matches (the GLSL file uses `output_data`, not the GDScript field name). If you see matches, fix them — they will produce runtime errors when the project loads.

- [ ] **Step 6: Verify the project still loads**

Run:

```bash
godot --headless --path . --quit-after 2
```

Expected: clean exit, no parse errors about `light_output_buffer` or `light_pack_uniform_set`. The dispatch path still references the old single uniform set — that's fixed in Task 4 immediately after, so do not delay the commit.

- [ ] **Step 7: Commit**

```bash
git add src/core/chunk.gd src/core/chunk_manager.gd
git commit -m "perf(lights): per-chunk uniform sets bind shared light SSBOs"
```

---

## Task 4: Coalesced dispatch + readback + slice decode in `ComputeDevice`

**Files:**
- Modify: `src/core/compute_device.gd`

- [ ] **Step 1: Rewrite `dispatch_light_pack` to use slice indices and the active shared buffer**

In `src/core/compute_device.gd`, replace the entire `dispatch_light_pack` function (currently lines 550–574):

```gdscript
func dispatch_light_pack(chunks: Dictionary, bucket_coords: Array) -> void:
	# Clear the manifest for the buffer we're about to write.
	var manifest: PackedInt32Array = PackedInt32Array()

	if bucket_coords.is_empty():
		light_dispatch_manifests[light_write_index] = manifest
		return

	var push_data := PackedByteArray()
	push_data.resize(16)
	push_data.fill(0)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, light_pack_pipeline)

	var slice_idx := 0
	for coord in bucket_coords:
		if slice_idx >= LIGHT_MAX_ACTIVE_CHUNKS:
			push_warning("light_pack: bucket exceeds LIGHT_MAX_ACTIVE_CHUNKS, dropping extras")
			break
		var chunk: Chunk = chunks.get(coord, null)
		if chunk == null:
			continue
		var us: RID = chunk.light_pack_uniform_sets[light_write_index]
		if not us.is_valid():
			continue

		rd.compute_list_bind_uniform_set(compute_list, us, 0)

		push_data.encode_s32(0, coord.x)
		push_data.encode_s32(4, coord.y)
		push_data.encode_u32(8, slice_idx)
		push_data.encode_u32(12, 0)
		rd.compute_list_set_push_constant(compute_list, push_data, push_data.size())

		rd.compute_list_dispatch(compute_list, LIGHT_CELLS_X, LIGHT_CELLS_Y, 1)

		manifest.append(coord.x)
		manifest.append(coord.y)
		manifest.append(slice_idx)
		slice_idx += 1

	rd.compute_list_end()

	light_dispatch_manifests[light_write_index] = manifest
```

- [ ] **Step 2: Replace `read_light_buffer` with `read_light_buffer_coalesced`**

In `src/core/compute_device.gd`, delete the existing `read_light_buffer` function (lines 577–580) and add:

```gdscript
## Reads the prior frame's coalesced light SSBO and returns the bytes plus the manifest
## describing which (chunk_coord, slice_idx) tuples are present.
## Returns an empty dictionary on the first frame, before any dispatch has completed.
## After a successful read, flips light_write_index so the next dispatch targets the
## buffer just consumed.
func read_light_buffer_coalesced() -> Dictionary:
	if light_first_frame:
		light_first_frame = false
		light_write_index = 1 - light_write_index
		return {}

	var read_index := 1 - light_write_index
	var manifest: PackedInt32Array = light_dispatch_manifests[read_index]
	if manifest.is_empty():
		light_write_index = 1 - light_write_index
		return {}

	var slice_count := manifest.size() / 3
	var byte_count := slice_count * LIGHT_OUTPUT_SIZE
	var bytes := rd.buffer_get_data(light_output_buffers[read_index], 0, byte_count)

	light_write_index = 1 - light_write_index

	return {
		"bytes": bytes,
		"manifest": manifest,
	}
```

- [ ] **Step 3: Add `decode_light_ssbo_slice` next to `decode_light_ssbo`**

In `src/core/compute_device.gd`, just after `decode_light_ssbo` (around line 618), add:

```gdscript
## Decodes a single 16-cell slice out of a coalesced light SSBO byte buffer.
func decode_light_ssbo_slice(data: PackedByteArray, slice_idx: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var slice_off := slice_idx * LIGHT_OUTPUT_SIZE
	if data.size() < slice_off + LIGHT_OUTPUT_SIZE:
		return result
	result.resize(LIGHT_CELL_COUNT)

	for cell_idx in range(LIGHT_CELL_COUNT):
		var off := slice_off + cell_idx * LIGHT_CELL_BYTES
		var packed_count_glow := data.decode_u32(off)
		var packed_pos := data.decode_u32(off + 4)
		var hazard_mask := data.decode_u32(off + 8)

		var pixel_count := packed_count_glow & 0xFFFF
		var avg_glow_raw := (packed_count_glow >> 16) & 0xFFFF
		var avg_x := packed_pos & 0xFFFF
		var avg_y := (packed_pos >> 16) & 0xFFFF

		var energy := 0.0
		var pos := Vector2.ZERO

		if pixel_count >= 4:
			var avg_glow := float(avg_glow_raw) / 1000.0
			var coverage := clampf(float(pixel_count) / 32.0, 0.0, 1.0)
			energy = coverage * (avg_glow / 20.0)
			pos = Vector2(float(avg_x), float(avg_y))

		result[cell_idx] = {
			"position": pos,
			"energy": energy,
			"color": Color(1.0, 0.5, 0.15, 1.0),
			"hazard": int(hazard_mask),
		}

	return result
```

- [ ] **Step 4: Add a unit test for the slice decoder**

In `tests/unit/test_light_decode_hazard.gd`, append a new test:

```gdscript
func _make_coalesced_buffer(hazards_per_slice: Array) -> PackedByteArray:
	var slice_count := hazards_per_slice.size()
	var buf := PackedByteArray()
	buf.resize(slice_count * LIGHT_OUTPUT_SIZE)
	buf.fill(0)
	for s in range(slice_count):
		var slice_off := s * LIGHT_OUTPUT_SIZE
		var hazards: Array = hazards_per_slice[s]
		for i in range(LIGHT_CELL_COUNT):
			var off := slice_off + i * LIGHT_CELL_BYTES
			buf.encode_u32(off + 8, hazards[i])
	return buf

func test_slice_decoder_extracts_hazard_mask_for_slice() -> void:
	var device := ComputeDevice.new()
	var slice0: Array = []
	var slice1: Array = []
	slice0.resize(LIGHT_CELL_COUNT)
	slice1.resize(LIGHT_CELL_COUNT)
	for i in range(LIGHT_CELL_COUNT):
		slice0[i] = 0
		slice1[i] = 0
	slice0[3] = MaterialRegistry.HAZARD_LAVA
	slice1[7] = MaterialRegistry.HAZARD_FIRE
	var data := _make_coalesced_buffer([slice0, slice1])

	var decoded0 := device.decode_light_ssbo_slice(data, 0)
	var decoded1 := device.decode_light_ssbo_slice(data, 1)
	assert_that(decoded0.size()).is_equal(LIGHT_CELL_COUNT)
	assert_that(decoded1.size()).is_equal(LIGHT_CELL_COUNT)
	assert_that(int(decoded0[3]["hazard"])).is_equal(MaterialRegistry.HAZARD_LAVA)
	assert_that(int(decoded1[7]["hazard"])).is_equal(MaterialRegistry.HAZARD_FIRE)
	assert_that(int(decoded0[7]["hazard"])).is_equal(0)
```

- [ ] **Step 5: Run the unit suite**

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_light_decode_hazard.gd
```

Expected: all tests in `test_light_decode_hazard.gd` pass, including the new `test_slice_decoder_extracts_hazard_mask_for_slice`. The existing `test_decoder_extracts_hazard_mask` must still pass — `decode_light_ssbo` was not modified.

- [ ] **Step 6: Commit**

```bash
git add src/core/compute_device.gd tests/unit/test_light_decode_hazard.gd
git commit -m "perf(lights): coalesced dispatch/read APIs + slice decoder"
```

---

## Task 5: Rewrite `_update_lights` in `WorldManager`

**Files:**
- Modify: `src/core/world_manager.gd`

- [ ] **Step 1: Remove the obsolete readback counter field**

In `src/core/world_manager.gd`, delete line 23:

```gdscript
var _light_readback_counter := 0
```

- [ ] **Step 2: Replace the `_update_lights` body**

Replace the entire `_update_lights` function (currently lines 355–406) with:

```gdscript
func _update_lights() -> void:
	if chunks.is_empty():
		return

	# --- Readback: consume the prior frame's coalesced output ---
	var readback: Dictionary = compute_device.read_light_buffer_coalesced()
	if not readback.is_empty():
		var bytes: PackedByteArray = readback["bytes"]
		var manifest: PackedInt32Array = readback["manifest"]
		var slice_count := manifest.size() / 3
		for s in range(slice_count):
			var coord := Vector2i(manifest[s * 3], manifest[s * 3 + 1])
			var slice_idx: int = manifest[s * 3 + 2]
			var chunk: Chunk = chunks.get(coord, null)
			if not chunk or not chunk.chunk_lights:
				continue
			var decoded := compute_device.decode_light_ssbo_slice(bytes, slice_idx)
			if decoded.is_empty():
				continue
			chunk.chunk_lights.apply_light_data(decoded)
			for j in range(min(decoded.size(), 16)):
				chunk.hazard_cells[j] = int(decoded[j].get("hazard", 0))

	# --- Dispatch: 1/5 of visible chunks each frame ---
	_light_frame_counter = (_light_frame_counter + 1) % 5

	var active_coords: Array[Vector2i] = []
	for coord in chunks:
		active_coords.append(coord)

	var bucket_idx := _light_frame_counter
	_light_dispatch_buckets[bucket_idx].clear()

	var bucket_size := maxi(1, ceili(float(active_coords.size()) / 5.0))
	var start := bucket_idx * bucket_size
	if start < active_coords.size():
		var end := mini(start + bucket_size, active_coords.size())
		for i in range(start, end):
			_light_dispatch_buckets[bucket_idx].append(active_coords[i])

	compute_device.dispatch_light_pack(chunks, _light_dispatch_buckets[bucket_idx])
```

Order matters: read BEFORE dispatch within a frame. The read consumes buffer `(1 - write_index)`, then flips `write_index`, so the dispatch that follows writes into the buffer we just drained.

- [ ] **Step 3: Update `reset()` to clear the new state**

In `src/core/world_manager.gd`, find `reset()` (around line 414). It contains both:

```gdscript
	_light_frame_counter = 0
	_light_readback_counter = 0
```

Delete the `_light_readback_counter = 0` line (the field no longer exists after Step 1). Then, immediately after `_light_frame_counter = 0`, add:

```gdscript
	compute_device.light_first_frame = true
	compute_device.light_write_index = 0
	compute_device.light_dispatch_manifests[0] = PackedInt32Array()
	compute_device.light_dispatch_manifests[1] = PackedInt32Array()
```

- [ ] **Step 4: Verify the project still loads and runs the unit suite**

```bash
godot --headless --path . --quit-after 2
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit
```

Expected: both commands exit cleanly; all unit tests still pass.

- [ ] **Step 5: Commit**

```bash
git add src/core/world_manager.gd
git commit -m "perf(lights): coalesced single readback per frame in _update_lights"
```

---

## Task 6: Smoke-test in editor

**Files:** (none — runtime verification only)

- [ ] **Step 1: Launch the editor / a playable scene**

Open the project in the Godot editor and run the main scene the user normally uses for FPS testing (the one that produced the 17.21 ms baseline). Confirm visually:

- Lights (Light2Ds) appear and fade around glowing materials (lava, fire) as before.
- Enemies still take damage when standing on lava (the hazard-mask pre-filter still works).
- No console errors mentioning `light_pack`, `light_output`, `slice_idx`, or uniform set creation failures.

- [ ] **Step 2: Report back any anomalies**

If any visual or gameplay regression appears, stop and investigate before proceeding to Task 7. Likely suspects:
- Stale buffer reads on first frame (check `light_first_frame` guard).
- Slice offset mismatch between dispatch (Task 4) and shader (Task 2) — both must use `slice_idx * 16`.
- Uniform set not rebuilt when chunks load/unload — check that `build_light_pack_uniform_set` is called from `create_chunk` (it already is, line 131 of `chunk_manager.gd`).

---

## Task 7: Profile and verify the perf goal

**Files:** (none — runtime verification only)

- [ ] **Step 1: Capture profiler reading**

In the editor profiler, in the same scene as the baseline (12 active light chunks, 101 enemies if reproducible):

- `ComputeDevice.read...` (or its successor entry — should now be a single `read_light_buffer_coalesced` call per frame): expect **< 0.5 ms**.
- `_update_lights`: expect **< 1.0 ms** total.
- Frame Time: expect **< 16.66 ms** with margin (target: 13–15 ms range).

- [ ] **Step 2: If the goal is not met**

If `ComputeDevice.read...` is still > 1 ms per frame, the readback is still effectively stalling — investigate:
- Confirm the read is hitting the inactive buffer index (`1 - light_write_index`), not the one that was just written this frame.
- Confirm the dispatch happens AFTER the read within `_update_lights` (the order in Task 5 Step 2 is mandatory).
- As a fallback knob: reduce dispatch to 1/N where N > 5, accepting longer hazard refresh latency.

If the goal is met, proceed.

- [ ] **Step 3: Final commit (release notes)**

Only after the user confirms the perf goal is met:

```bash
git commit --allow-empty -m "perf(lights): verified 60+ FPS in editor after coalesced readback"
```
