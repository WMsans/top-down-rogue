# Glowing Light Sources Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Godot PointLight2D nodes driven by a compute shader pass that aggregates glowing pixels (MATERIAL_GLOW > 1.0) per chunk into up to 16 lights per chunk, updated on a 5-frame distributed rotation.

**Architecture:** New compute shader (`light_pack.glsl`) scans each chunk's 256x256 texture in a 4x4 grid (64x64 cells each), accumulating glowing pixel counts and positions. Results written to a 128-byte SSBO per chunk. New `ChunkLights` component manages 16 PointLight2D nodes per chunk with smooth lerp interpolation. Dispatch at 12Hz, readback distributed across 5 frames.

**Tech Stack:** Godot 4.6 RenderingDevice, GLSL compute shaders, PointLight2D

---

### Task 1: Write the compute shader `light_pack.glsl`

**Files:**
- Create: `shaders/compute/light_pack.glsl`

- [ ] **Step 1: Create the compute shader**

Write `shaders/compute/light_pack.glsl`:

```glsl
#[compute]
#version 450

#include "res://shaders/generated/materials.glslinc"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba8, set = 0, binding = 0) readonly uniform image2D chunk_tex;

layout(push_constant, std430) uniform PushConstants {
	ivec2 chunk_coord;
	int _pad0;
	int _pad1;
} pc;

const uint CELL_SIZE = 64u;
const uint CELLS_X = 4u;
const uint CELLS_Y = 4u;

struct LightCell {
	uint packed_count_glow;   // bits [15:0] = pixel_count, bits [31:16] = avg_glow_raw (glow × 1000)
	uint packed_pos;          // bits [15:0] = avg_x, bits [31:16] = avg_y
};

layout(set = 0, binding = 1, std430) buffer LightOutput {
	LightCell cells[];
} output_data;

shared uint s_counts[64];
shared uint s_sum_x[64];
shared uint s_sum_y[64];
shared uint s_sum_glow[64];

int get_material(vec4 pixel) {
	return int(pixel.r * 255.0 + 0.5);
}

void main() {
	uint thread_idx = gl_LocalInvocationIndex;
	uint cell_x = gl_WorkGroupID.x;
	uint cell_y = gl_WorkGroupID.y;
	uint cell_idx = cell_y * CELLS_X + cell_x;

	uint local_count = 0u;
	uint local_sum_x = 0u;
	uint local_sum_y = 0u;
	uint local_sum_glow = 0u;

	uint base_x = cell_x * CELL_SIZE;
	uint base_y = cell_y * CELL_SIZE;

	for (uint dy = 0u; dy < 8u; dy++) {
		for (uint dx = 0u; dx < 8u; dx++) {
			uint px = base_x + gl_LocalInvocationID.x * 8u + dx;
			uint py = base_y + gl_LocalInvocationID.y * 8u + dy;

			vec4 pixel = imageLoad(chunk_tex, ivec2(px, py));
			int mat = get_material(pixel);

			if (mat >= 0 && mat < MAT_COUNT && MATERIAL_GLOW[mat] > 1.0) {
				local_count += 1u;
				local_sum_x += px;
				local_sum_y += py;
				local_sum_glow += uint(MATERIAL_GLOW[mat] * 1000.0 + 0.5);
			}
		}
	}

	s_counts[thread_idx] = local_count;
	s_sum_x[thread_idx] = local_sum_x;
	s_sum_y[thread_idx] = local_sum_y;
	s_sum_glow[thread_idx] = local_sum_glow;

	barrier();

	for (uint stride = 32u; stride > 0u; stride >>= 1) {
		if (thread_idx < stride) {
			s_counts[thread_idx] += s_counts[thread_idx + stride];
			s_sum_x[thread_idx] += s_sum_x[thread_idx + stride];
			s_sum_y[thread_idx] += s_sum_y[thread_idx + stride];
			s_sum_glow[thread_idx] += s_sum_glow[thread_idx + stride];
		}
		barrier();
	}

	if (thread_idx == 0u) {
		uint count = s_counts[0];
		if (count < 4u) {
			output_data.cells[cell_idx].packed_count_glow = 0u;
			output_data.cells[cell_idx].packed_pos = 0u;
		} else {
			uint avg_x = s_sum_x[0] / count;
			uint avg_y = s_sum_y[0] / count;
			uint avg_glow_raw = s_sum_glow[0] / count;
			output_data.cells[cell_idx].packed_count_glow = (avg_glow_raw << 16) | (count & 0xFFFFu);
			output_data.cells[cell_idx].packed_pos = (avg_y << 16) | (avg_x & 0xFFFFu);
		}
	}
}
```

- [ ] **Step 2: Commit**

```bash
git add shaders/compute/light_pack.glsl
git commit -m "feat: add light_pack compute shader for glowing pixel aggregation"
```

---

### Task 2: Add light_pack pipeline setup in ComputeDevice

**Files:**
- Modify: `src/core/compute_device.gd`

- [ ] **Step 1: Add light_pack shader and pipeline fields**

In `src/core/compute_device.gd`, add after the existing shader/pipeline fields (after line 14):

```gdscript
var light_pack_shader: RID
var light_pack_pipeline: RID
```

Add after line 49 (after `collider_pipeline = ...` in `init_shaders`):

```gdscript
	var light_pack_file: RDShaderFile = load("res://shaders/compute/light_pack.glsl")
	var light_pack_spirv := light_pack_file.get_spirv()
	light_pack_shader = rd.shader_create_from_spirv(light_pack_spirv)
	light_pack_pipeline = rd.compute_pipeline_create(light_pack_shader)
```

- [ ] **Step 2: Add cleanup for light_pack resources**

In `free_resources()`, add after the collider cleanup (after line 231):

```gdscript
	if light_pack_pipeline.is_valid():
		rd.free_rid(light_pack_pipeline)
	if light_pack_shader.is_valid():
		rd.free_rid(light_pack_shader)
```

- [ ] **Step 3: Commit**

```bash
git add src/core/compute_device.gd
git commit -m "feat: add light_pack pipeline init and cleanup to ComputeDevice"
```

---

### Task 3: Add light_pack buffer and uniform set to Chunk

**Files:**
- Modify: `src/core/chunk.gd`
- Modify: `src/core/chunk_manager.gd`

- [ ] **Step 1: Add fields to Chunk**

In `src/core/chunk.gd`, add after line 12:

```gdscript
var light_output_buffer: RID
var light_pack_uniform_set: RID
var chunk_lights  # ChunkLights (Node2D)
```

- [ ] **Step 2: Create light_pack buffers in chunk creation**

In `src/core/chunk_manager.gd`, add after line 69 (after `rd.buffer_update(chunk.injection_buffer, ...)` in `create_chunk`):

```gdscript
	var light_output_size := 128  # 16 cells × 8 bytes (2 uints)
	chunk.light_output_buffer = world_manager.rd.storage_buffer_create(light_output_size)
```

- [ ] **Step 3: Build light_pack uniform set**

Add a new method to `chunk_manager.gd` after `build_sim_uniform_set` (after line 193):

```gdscript
func build_light_pack_uniform_set(chunk: Chunk) -> void:
	var compute: ComputeDevice = world_manager.compute_device

	if chunk.light_pack_uniform_set.is_valid():
		world_manager.rd.free_rid(chunk.light_pack_uniform_set)

	var uniforms: Array[RDUniform] = []

	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(chunk.rd_texture)
	uniforms.append(u0)

	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u1.binding = 1
	u1.add_id(chunk.light_output_buffer)
	uniforms.append(u1)

	chunk.light_pack_uniform_set = world_manager.rd.uniform_set_create(uniforms, compute.light_pack_shader, 0)
```

- [ ] **Step 4: Call build_light_pack_uniform_set in chunk creation**

In `create_chunk`, after the `chunks[coord] = chunk` line (line 114), add:

```gdscript
	build_light_pack_uniform_set(chunk)
```

- [ ] **Step 5: Clean up light_pack resources in chunk unload**

In `free_chunk_resources`, add after line 138 (after freeing `rd_texture`):

```gdscript
	if chunk.light_output_buffer.is_valid():
		world_manager.rd.free_rid(chunk.light_output_buffer)
	if chunk.light_pack_uniform_set.is_valid():
		world_manager.rd.free_rid(chunk.light_pack_uniform_set)
```

- [ ] **Step 6: Commit**

```bash
git add src/core/chunk.gd src/core/chunk_manager.gd
git commit -m "feat: add light_pack buffers and uniform sets per chunk"
```

---

### Task 4: Create ChunkLights component

**Files:**
- Create: `src/core/chunk_lights.gd`

- [ ] **Step 1: Write ChunkLights**

Write `src/core/chunk_lights.gd`:

```gdscript
class_name ChunkLights
extends Node2D

const CHUNK_SIZE := 256.0
const CELLS_X := 4
const CELLS_Y := 4
const MAX_LIGHTS := 16
const DEFAULT_LIGHT_RANGE := 64.0
const MAX_GLOW := 20.0
const SMOOTH_SPEED := 30.0
const MIN_PIXELS := 4
const DEFAULT_TEXTURE_SIZE := 512.0  # PointLight2D default texture radius

var target_positions: Array[Vector2]
var target_energies: Array[float]
var current_positions: Array[Vector2]
var current_energies: Array[float]
var lights: Array[PointLight2D]
var chunk_coord: Vector2i

func _init(coord: Vector2i) -> void:
	chunk_coord = coord
	name = "Lights"
	z_index = 2

	var light_texture := _create_unit_radius_texture()

	target_positions.resize(MAX_LIGHTS)
	target_energies.resize(MAX_LIGHTS)
	current_positions.resize(MAX_LIGHTS)
	current_energies.resize(MAX_LIGHTS)
	lights.resize(MAX_LIGHTS)

	for i in range(MAX_LIGHTS):
		target_positions[i] = Vector2.ZERO
		target_energies[i] = 0.0
		current_positions[i] = Vector2.ZERO
		current_energies[i] = 0.0

		var light := PointLight2D.new()
		light.visible = false
		light.shadow_enabled = false
		light.blend_mode = Light2D.BLEND_MODE_ADD
		light.texture = light_texture
		light.texture_scale = DEFAULT_LIGHT_RANGE / DEFAULT_TEXTURE_SIZE
		light.color = Color(1.0, 0.5, 0.15, 1.0)  # warm lava-orange default
		add_child(light)
		lights[i] = light


func _create_unit_radius_texture() -> Texture2D:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(float(size - 1) * 0.5, float(size - 1) * 0.5)
	var radius := float(size) * 0.5 - 1.0
	for y in range(size):
		for x in range(size):
			var dist := Vector2(float(x), float(y)).distance_to(center) / radius
			var a := clampf(1.0 - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


func apply_light_data(cell_data: Array) -> void:
	for i in range(MAX_LIGHTS):
		var entry := cell_data[i] as Dictionary
		target_positions[i] = entry.get("position", Vector2.ZERO)
		target_energies[i] = entry.get("energy", 0.0)
		lights[i].color = entry.get("color", Color(1.0, 0.5, 0.15, 1.0))


func _process(delta: float) -> void:
	var t := 1.0 - exp(-SMOOTH_SPEED * delta)
	for i in range(MAX_LIGHTS):
		current_positions[i] = current_positions[i].lerp(target_positions[i], t)
		current_energies[i] = lerpf(current_energies[i], target_energies[i], t)

		if current_energies[i] < 0.005:
			lights[i].visible = false
		else:
			lights[i].visible = true
			lights[i].position = current_positions[i]
			lights[i].energy = current_energies[i]
```

- [ ] **Step 2: Commit**

```bash
git add src/core/chunk_lights.gd
git commit -m "feat: add ChunkLights component with smooth PointLight2D interpolation"
```

---

### Task 5: Wire ChunkLights into chunk lifecycle

**Files:**
- Modify: `src/core/world_manager.gd`
- Modify: `src/core/chunk_manager.gd`

- [ ] **Step 1: Add lights_container to WorldManager**

In `src/core/world_manager.gd`, add after line 13 (after `var collision_container: Node2D`):

```gdscript
var lights_container: Node2D
```

In `_ready()`, add after line 51 (after `add_child(collision_container)`):

```gdscript
	lights_container = Node2D.new()
	lights_container.name = "LightsContainer"
	add_child(lights_container)
```

- [ ] **Step 2: Create ChunkLights in chunk creation**

In `src/core/chunk_manager.gd` `create_chunk`, add after line 112 (after `chunk.occluder_instances = []`):

```gdscript
	var lights_node := ChunkLights.new(coord)
	lights_node.position = Vector2(coord) * CHUNK_SIZE
	world_manager.lights_container.add_child(lights_node)
	chunk.chunk_lights = lights_node
```

- [ ] **Step 3: Clean up ChunkLights in chunk unload**

In `src/core/chunk_manager.gd` `free_chunk_resources`, add after line 128 (after `chunk.static_body.queue_free()`):

```gdscript
	if chunk.chunk_lights and is_instance_valid(chunk.chunk_lights):
		chunk.chunk_lights.queue_free()
```

- [ ] **Step 4: Commit**

```bash
git add src/core/world_manager.gd src/core/chunk_manager.gd
git commit -m "feat: wire ChunkLights into chunk create/destroy lifecycle"
```

---

### Task 6: Add light dispatch and distributed readback to ComputeDevice

**Files:**
- Modify: `src/core/compute_device.gd`

- [ ] **Step 1: Add light pack dispatch method**

Add to `compute_device.gd` before the last line:

```gdscript
func dispatch_light_pack(chunks: Dictionary, bucket_coords: Array[Vector2i]) -> void:
	if bucket_coords.is_empty():
		return

	var push_data := PackedByteArray()
	push_data.resize(16)
	push_data.fill(0)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, light_pack_pipeline)

	for coord in bucket_coords:
		var chunk: Chunk = chunks.get(coord, null)
		if not chunk or not chunk.light_pack_uniform_set.is_valid():
			continue

		rd.compute_list_bind_uniform_set(compute_list, chunk.light_pack_uniform_set, 0)

		push_data.encode_s32(0, coord.x)
		push_data.encode_s32(4, coord.y)
		rd.compute_list_set_push_constant(compute_list, push_data, push_data.size())

		rd.compute_list_dispatch(compute_list, 4, 4, 1)  # 4x4 grid of workgroups

	rd.compute_list_end()
```


- [ ] **Step 2: Add readback method**

Add after the dispatch method:

```gdscript
func read_light_buffer(chunk: Chunk) -> PackedByteArray:
	if not chunk.light_output_buffer.is_valid():
		return PackedByteArray()
	return rd.buffer_get_data(chunk.light_output_buffer, 0, 128)
```


- [ ] **Step 3: Add SSBO decode method**

Add after the readback method:

```gdscript
## Decodes a 128-byte SSBO into an array of 16 dictionaries with position, energy, and color.
## Always returns 16 entries — cells with no glowing pixels get energy=0 and will fade out.
func decode_light_ssbo(data: PackedByteArray) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.resize(16)

	for cell_idx in range(16):
		var off := cell_idx * 8
		var packed_count_glow := data.decode_u32(off)
		var packed_pos := data.decode_u32(off + 4)

		var pixel_count := packed_count_glow & 0xFFFF
		var avg_glow_raw := (packed_count_glow >> 16) & 0xFFFF
		var avg_x := packed_pos & 0xFFFF
		var avg_y := (packed_pos >> 16) & 0xFFFF

		var energy := 0.0
		var pos := Vector2.ZERO

		if pixel_count >= 4:
			var avg_glow := float(avg_glow_raw) / 1000.0
			var coverage := clampf(float(pixel_count) / 32.0, 0.0, 1.0)
			energy = coverage * (avg_glow / 20.0)  # MAX_GLOW = 20.0
			pos = Vector2(float(avg_x), float(avg_y))

		result[cell_idx] = {
			"position": pos,
			"energy": energy,
			"color": Color(1.0, 0.5, 0.15, 1.0)
		}

	return result
```


- [ ] **Step 4: Commit**

```bash
git add src/core/compute_device.gd
git commit -m "feat: add light_pack dispatch, readback, and SSBO decode to ComputeDevice"
```

---

### Task 7: Wire light update loop into WorldManager

**Files:**
- Modify: `src/core/world_manager.gd`

- [ ] **Step 1: Add state variables**

Add to `src/core/world_manager.gd`, after line 18 (after `var _gen_uniform_sets_to_free: Array[RID] = []`):

```gdscript
var _light_frame_counter := 0
var _light_dispatch_buckets: Array[Array] = []   # 5 slots, each = Array[Vector2i]
var _light_readback_counter := 0
```

- [ ] **Step 2: Initialize buckets**

In `_ready()`, add after line 52 (after `lights_container = ...`):

```gdscript
	_light_dispatch_buckets.resize(5)
	for i in range(5):
		_light_dispatch_buckets[i] = []
```

- [ ] **Step 3: Add light update method**

Add before the last line of `world_manager.gd`:

```gdscript
func _update_lights() -> void:
	if chunks.is_empty():
		return

	_light_frame_counter = (_light_frame_counter + 1) % 5

	# Convert chunk coord keys to array for bucketing
	var active_coords: Array[Vector2i] = []
	for coord in chunks:
		active_coords.append(coord)

	# --- Dispatch: 1/5 of visible chunks each frame ---
	var bucket_idx := _light_frame_counter
	_light_dispatch_buckets[bucket_idx].clear()

	var bucket_size := maxi(1, active_coords.size() / 5)
	var start := bucket_idx * bucket_size
	if start < active_coords.size():
		var end := mini(start + bucket_size, active_coords.size())
		for i in range(start, end):
			_light_dispatch_buckets[bucket_idx].append(active_coords[i])

	compute_device.dispatch_light_pack(chunks, _light_dispatch_buckets[bucket_idx])

	# --- Readback: drain from 4 older buckets (1/4 of each) ---
	_light_readback_counter = (_light_readback_counter + 1) % 4

	for age in range(1, 5):
		var read_bucket := (_light_frame_counter + 5 - age) % 5
		var pending: Array = _light_dispatch_buckets[read_bucket]
		if pending.is_empty():
			continue

		var slice_size := maxi(1, pending.size() / 4)
		var slice_start := _light_readback_counter * slice_size
		if slice_start < pending.size():
			var slice_end := mini(slice_start + slice_size, pending.size())
			for i in range(slice_start, slice_end):
				var coord: Vector2i = pending[i]
				var chunk: Chunk = chunks.get(coord, null)
				if not chunk or not chunk.chunk_lights:
					continue

				var data := compute_device.read_light_buffer(chunk)
				if data.size() == 0:
					continue

				var decoded := compute_device.decode_light_ssbo(data)
				chunk.chunk_lights.apply_light_data(decoded)
```

- [ ] **Step 4: Call _update_lights in _process**

In `_process`, add after line 67 (`_collision_helper.rebuild_dirty(chunks, delta)`):

```gdscript
	_update_lights()
```

- [ ] **Step 5: Clear buckets on reset**

In `reset()`, add after line 264 (after `for child in chunk_container.get_children():` block):

```gdscript
	for child in lights_container.get_children():
		child.queue_free()
	_light_dispatch_buckets.clear()
	_light_dispatch_buckets.resize(5)
	for i in range(5):
		_light_dispatch_buckets[i] = []
	_light_frame_counter = 0
	_light_readback_counter = 0
```

- [ ] **Step 6: Commit**

```bash
git add src/core/world_manager.gd
git commit -m "feat: wire 5-frame distributed light dispatch and readback loop"
```

---

### Task 8: Verification

**Files:** None (manual verification)

- [ ] **Step 1: Run the project and verify visually**

Run the project. Place lava using the cheat console (`place_lava`) or trigger lava generation. Verify:
1. Lava areas emit orange PointLight2D illumination on surrounding terrain
2. Lights smoothly interpolate between updates (no popping)
3. Lights are culled for chunks outside the camera view
4. Performance is acceptable (no frame drops)

- [ ] **Step 2: Check for errors**

Watch the Godot debugger output for any RenderingDevice errors related to:
- Invalid uniform sets
- Buffer size mismatches
- Pipeline binding errors

