# Noita-Like Pixel Terrain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a GPU-accelerated cellular automata pixel simulation with infinite chunked terrain, fire propagation, and debug overlays in Godot 4.6.

**Architecture:** Centralized WorldManager owns a RenderingDevice and manages chunk lifecycle. Each 256x256 chunk is an RGBA8 GPU texture shared between compute shaders (simulation/generation) and a canvas_item rendering shader via Texture2DRD. Checkerboard CA update pattern avoids race conditions with single-buffered textures.

**Tech Stack:** Godot 4.6, GDScript, GLSL 450 compute shaders, RenderingDevice API, Texture2DRD

---

## File Structure

```
project.godot                     — update: set main scene
scripts/
  camera_controller.gd            — create: WASD camera movement
  input_handler.gd                — create: mouse click fire placement
  debug_manager.gd                — create: F3 toggle debug overlays
  chunk_grid_overlay.gd           — create: draw chunk boundary lines
  chunk.gd                        — create: RefCounted chunk data (RID, mesh, uniforms)
  world_manager.gd                — create: RD init, chunk lifecycle, simulation dispatch
shaders/
  generation.glsl                 — create: compute shader, fill chunk with wood
  simulation.glsl                 — create: compute shader, CA fire rules
  render_chunk.gdshader           — create: canvas_item shader, material -> color
scenes/
  main.tscn                       — create: full scene tree
```

---

### Task 1: Project Scaffolding — All Files + Camera

Create every file needed for the project. Camera controller and shaders are fully implemented. Other scripts are stubs. Main scene wires everything together.

**Files:**
- Modify: `project.godot`
- Create: `scripts/camera_controller.gd`
- Create: `scripts/input_handler.gd` (stub)
- Create: `scripts/debug_manager.gd` (stub)
- Create: `scripts/chunk_grid_overlay.gd` (stub)
- Create: `scripts/chunk.gd`
- Create: `shaders/generation.glsl`
- Create: `shaders/simulation.glsl`
- Create: `shaders/render_chunk.gdshader`
- Create: `scenes/main.tscn`

- [ ] **Step 1: Update project.godot to set main scene**

Add `run/main_scene` to the `[application]` section of `project.godot`:

```ini
[application]

config/name="TopDownRogue"
config/features=PackedStringArray("4.6", "Forward Plus")
config/icon="res://icon.svg"
run/main_scene="res://scenes/main.tscn"
```

- [ ] **Step 2: Create camera_controller.gd**

Write `scripts/camera_controller.gd`:

```gdscript
extends Camera2D

@export var move_speed: float = 400.0

func _process(delta: float) -> void:
	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		input.x -= 1
	if Input.is_key_pressed(KEY_D):
		input.x += 1
	if Input.is_key_pressed(KEY_W):
		input.y -= 1
	if Input.is_key_pressed(KEY_S):
		input.y += 1
	if input != Vector2.ZERO:
		position += input.normalized() * move_speed * delta
```

- [ ] **Step 3: Create stub scripts**

Write `scripts/input_handler.gd`:

```gdscript
extends Node
```

Write `scripts/debug_manager.gd`:

```gdscript
extends Node2D
```

Write `scripts/chunk_grid_overlay.gd`:

```gdscript
extends Node2D
```

- [ ] **Step 4: Create chunk.gd**

Write `scripts/chunk.gd`:

```gdscript
class_name Chunk
extends RefCounted

var coord: Vector2i
var rd_texture: RID
var texture_2d_rd: Texture2DRD
var mesh_instance: MeshInstance2D
var sim_uniform_set: RID
```

- [ ] **Step 5: Create generation.glsl**

Write `shaders/generation.glsl`:

```glsl
#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba8, set = 0, binding = 0) uniform image2D chunk_tex;

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	if (pos.x >= 256 || pos.y >= 256) return;

	// Wood: material=1, health=255, temperature=0, reserved=0
	vec4 pixel = vec4(1.0 / 255.0, 1.0, 0.0, 0.0);
	imageStore(chunk_tex, pos, pixel);
}
```

- [ ] **Step 6: Create simulation.glsl**

Write `shaders/simulation.glsl`:

```glsl
#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba8, set = 0, binding = 0) uniform image2D chunk_tex;
layout(rgba8, set = 0, binding = 1) readonly uniform image2D neighbor_top;
layout(rgba8, set = 0, binding = 2) readonly uniform image2D neighbor_bottom;
layout(rgba8, set = 0, binding = 3) readonly uniform image2D neighbor_left;
layout(rgba8, set = 0, binding = 4) readonly uniform image2D neighbor_right;

layout(push_constant, std430) uniform PushConstants {
	int phase;
	int _pad1;
	int _pad2;
	int _pad3;
} pc;

const int CHUNK_SIZE = 256;
const int MAT_AIR = 0;
const int MAT_WOOD = 1;
const int MAT_FIRE = 2;
const int IGNITION_TEMP = 180;
const int FIRE_TEMP = 255;
const int HEAT_DISSIPATION = 2;
const int HEAT_SPREAD = 10;

int get_material(vec4 p) { return int(round(p.r * 255.0)); }
int get_health(vec4 p) { return int(round(p.g * 255.0)); }
int get_temperature(vec4 p) { return int(round(p.b * 255.0)); }

vec4 make_pixel(int mat, int hp, int temp) {
	return vec4(float(mat) / 255.0, float(hp) / 255.0, float(temp) / 255.0, 0.0);
}

vec4 read_neighbor(ivec2 pos) {
	if (pos.x >= 0 && pos.x < CHUNK_SIZE && pos.y >= 0 && pos.y < CHUNK_SIZE) {
		return imageLoad(chunk_tex, pos);
	}
	if (pos.y < 0) {
		return imageLoad(neighbor_top, ivec2(pos.x, CHUNK_SIZE + pos.y));
	}
	if (pos.y >= CHUNK_SIZE) {
		return imageLoad(neighbor_bottom, ivec2(pos.x, pos.y - CHUNK_SIZE));
	}
	if (pos.x < 0) {
		return imageLoad(neighbor_left, ivec2(CHUNK_SIZE + pos.x, pos.y));
	}
	if (pos.x >= CHUNK_SIZE) {
		return imageLoad(neighbor_right, ivec2(pos.x - CHUNK_SIZE, pos.y));
	}
	return vec4(0.0);
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	if (pos.x >= CHUNK_SIZE || pos.y >= CHUNK_SIZE) return;

	// Checkerboard: skip if not this phase
	if ((pos.x + pos.y) % 2 != pc.phase) return;

	vec4 pixel = imageLoad(chunk_tex, pos);
	int material = get_material(pixel);
	int health = get_health(pixel);
	int temperature = get_temperature(pixel);

	// Read cardinal neighbors
	vec4 n_up = read_neighbor(pos + ivec2(0, -1));
	vec4 n_down = read_neighbor(pos + ivec2(0, 1));
	vec4 n_left = read_neighbor(pos + ivec2(-1, 0));
	vec4 n_right = read_neighbor(pos + ivec2(1, 0));

	int fire_neighbors = 0;
	if (get_material(n_up) == MAT_FIRE) fire_neighbors++;
	if (get_material(n_down) == MAT_FIRE) fire_neighbors++;
	if (get_material(n_left) == MAT_FIRE) fire_neighbors++;
	if (get_material(n_right) == MAT_FIRE) fire_neighbors++;

	if (material == MAT_AIR) {
		temperature = max(0, temperature - HEAT_DISSIPATION);
	} else if (material == MAT_WOOD) {
		temperature = min(255, temperature + fire_neighbors * HEAT_SPREAD);
		temperature = max(0, temperature - HEAT_DISSIPATION);
		if (temperature > IGNITION_TEMP) {
			material = MAT_FIRE;
			health = 255;
			temperature = FIRE_TEMP;
		}
	} else if (material == MAT_FIRE) {
		temperature = FIRE_TEMP;
		health = health - 1;
		if (health <= 0) {
			material = MAT_AIR;
			health = 0;
			temperature = FIRE_TEMP;
		}
	}

	imageStore(chunk_tex, pos, make_pixel(material, health, temperature));
}
```

- [ ] **Step 7: Create render_chunk.gdshader**

Write `shaders/render_chunk.gdshader`:

```gdshader
shader_type canvas_item;

uniform sampler2D chunk_data : filter_nearest;

void fragment() {
	vec4 data = texture(chunk_data, UV);
	int material = int(round(data.r * 255.0));
	float health = data.g;
	float temperature = data.b;

	if (material == 0) {
		// Air
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	} else if (material == 1) {
		// Wood — tint toward red with temperature
		vec3 wood_color = vec3(0.55, 0.35, 0.17);
		vec3 hot_color = vec3(0.8, 0.2, 0.1);
		COLOR = vec4(mix(wood_color, hot_color, temperature), 1.0);
	} else if (material == 2) {
		// Fire — orange to red based on health
		vec3 fire_bright = vec3(1.0, 0.6, 0.1);
		vec3 fire_dim = vec3(0.8, 0.1, 0.0);
		COLOR = vec4(mix(fire_dim, fire_bright, health), 1.0);
	} else {
		COLOR = vec4(1.0, 0.0, 1.0, 1.0);
	}
}
```

- [ ] **Step 8: Create main.tscn**

Create directory `scenes/` and write `scenes/main.tscn`:

```
[gd_scene load_steps=6 format=3]

[ext_resource type="Script" path="res://scripts/world_manager.gd" id="1"]
[ext_resource type="Script" path="res://scripts/camera_controller.gd" id="2"]
[ext_resource type="Script" path="res://scripts/input_handler.gd" id="3"]
[ext_resource type="Script" path="res://scripts/debug_manager.gd" id="4"]
[ext_resource type="Script" path="res://scripts/chunk_grid_overlay.gd" id="5"]

[node name="Main" type="Node2D"]

[node name="WorldManager" type="Node2D" parent="."]
script = ExtResource("1")

[node name="ChunkContainer" type="Node2D" parent="WorldManager"]

[node name="Camera2D" type="Camera2D" parent="."]
zoom = Vector2(2, 2)
script = ExtResource("2")

[node name="InputHandler" type="Node" parent="."]
script = ExtResource("3")

[node name="DebugManager" type="Node2D" parent="."]
visible = false
script = ExtResource("4")

[node name="ChunkGridOverlay" type="Node2D" parent="DebugManager"]
script = ExtResource("5")
```

- [ ] **Step 9: Verify camera works**

Run the project in Godot. Expected: empty gray scene, WASD moves the camera. No errors in console.

- [ ] **Step 10: Commit**

```bash
git add scripts/ shaders/ scenes/ project.godot
git commit -m "feat: scaffold project with camera, shaders, and scene tree"
```

---

### Task 2: WorldManager — Chunk Rendering

Implement the RenderingDevice initialization, chunk lifecycle (load/unload based on camera), generation dispatch, and rendering setup. After this task, you should see a brown wood world.

**Files:**
- Modify: `scripts/world_manager.gd`

- [ ] **Step 1: Write world_manager.gd with full chunk rendering**

Replace `scripts/world_manager.gd` with:

```gdscript
extends Node2D

const CHUNK_SIZE := 256
const WORKGROUP_SIZE := 8
const NUM_WORKGROUPS := CHUNK_SIZE / WORKGROUP_SIZE  # 32

var rd: RenderingDevice
var chunks: Dictionary = {}  # Vector2i -> Chunk

# Shader resources
var gen_shader: RID
var gen_pipeline: RID
var sim_shader: RID
var sim_pipeline: RID
var dummy_texture: RID  # 256x256 air texture for missing neighbors

var render_shader: Shader
var _gen_uniform_sets_to_free: Array[RID] = []

@onready var chunk_container: Node2D = $ChunkContainer
@onready var camera: Camera2D = get_parent().get_node("Camera2D")


func _ready() -> void:
	rd = RenderingServer.get_rendering_device()
	_init_shaders()
	_init_dummy_texture()
	render_shader = preload("res://shaders/render_chunk.gdshader")


func _exit_tree() -> void:
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		_free_chunk_resources(chunk)
	chunks.clear()
	if dummy_texture.is_valid():
		rd.free_rid(dummy_texture)
	if gen_pipeline.is_valid():
		rd.free_rid(gen_pipeline)
	if gen_shader.is_valid():
		rd.free_rid(gen_shader)
	if sim_pipeline.is_valid():
		rd.free_rid(sim_pipeline)
	if sim_shader.is_valid():
		rd.free_rid(sim_shader)


func _init_shaders() -> void:
	var gen_file: RDShaderFile = load("res://shaders/generation.glsl")
	var gen_spirv := gen_file.get_spirv()
	gen_shader = rd.shader_create_from_spirv(gen_spirv)
	gen_pipeline = rd.compute_pipeline_create(gen_shader)

	var sim_file: RDShaderFile = load("res://shaders/simulation.glsl")
	var sim_spirv := sim_file.get_spirv()
	sim_shader = rd.shader_create_from_spirv(sim_spirv)
	sim_pipeline = rd.compute_pipeline_create(sim_shader)


func _init_dummy_texture() -> void:
	var tf := RDTextureFormat.new()
	tf.width = CHUNK_SIZE
	tf.height = CHUNK_SIZE
	tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	var data := PackedByteArray()
	data.resize(CHUNK_SIZE * CHUNK_SIZE * 4)
	data.fill(0)
	dummy_texture = rd.texture_create(tf, RDTextureView.new(), [data])


func _process(_delta: float) -> void:
	_update_chunks()


# --- Chunk lifecycle ---

func _get_desired_chunks() -> Array[Vector2i]:
	var vp_size := get_viewport().get_visible_rect().size
	var cam_pos := camera.global_position
	var cam_zoom := camera.zoom
	var half_view := vp_size / (2.0 * cam_zoom)

	var min_chunk := Vector2i(
		floori((cam_pos.x - half_view.x) / CHUNK_SIZE) - 1,
		floori((cam_pos.y - half_view.y) / CHUNK_SIZE) - 1
	)
	var max_chunk := Vector2i(
		floori((cam_pos.x + half_view.x) / CHUNK_SIZE) + 1,
		floori((cam_pos.y + half_view.y) / CHUNK_SIZE) + 1
	)

	var result: Array[Vector2i] = []
	for x in range(min_chunk.x, max_chunk.x + 1):
		for y in range(min_chunk.y, max_chunk.y + 1):
			result.append(Vector2i(x, y))
	return result


func _update_chunks() -> void:
	# Free previous frame's generation uniform sets (GPU is done with them)
	for us in _gen_uniform_sets_to_free:
		rd.free_rid(us)
	_gen_uniform_sets_to_free.clear()

	var desired := _get_desired_chunks()
	var desired_set: Dictionary = {}
	for coord in desired:
		desired_set[coord] = true

	# Unload stale chunks
	var to_remove: Array[Vector2i] = []
	for coord in chunks:
		if not desired_set.has(coord):
			to_remove.append(coord)
	for coord in to_remove:
		_unload_chunk(coord)

	# Load new chunks
	var new_chunks: Array[Vector2i] = []
	for coord in desired:
		if not chunks.has(coord):
			_create_chunk(coord)
			new_chunks.append(coord)

	# Batch-generate all new chunks
	if not new_chunks.is_empty():
		var compute_list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, gen_pipeline)
		for coord in new_chunks:
			var chunk: Chunk = chunks[coord]
			var gen_uniform := RDUniform.new()
			gen_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			gen_uniform.binding = 0
			gen_uniform.add_id(chunk.rd_texture)
			var uniform_set := rd.uniform_set_create([gen_uniform], gen_shader, 0)
			_gen_uniform_sets_to_free.append(uniform_set)
			rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
			rd.compute_list_dispatch(compute_list, NUM_WORKGROUPS, NUM_WORKGROUPS, 1)
		rd.compute_list_end()

	# Rebuild simulation uniform sets for affected chunks
	if not new_chunks.is_empty() or not to_remove.is_empty():
		_rebuild_sim_uniform_sets(new_chunks, to_remove)


func _create_chunk(coord: Vector2i) -> void:
	var chunk := Chunk.new()
	chunk.coord = coord

	# Create RD texture
	var tf := RDTextureFormat.new()
	tf.width = CHUNK_SIZE
	tf.height = CHUNK_SIZE
	tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tf.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	chunk.rd_texture = rd.texture_create(tf, RDTextureView.new())

	# Create Texture2DRD for rendering
	chunk.texture_2d_rd = Texture2DRD.new()
	chunk.texture_2d_rd.texture_rd_rid = chunk.rd_texture

	# Create MeshInstance2D with QuadMesh
	chunk.mesh_instance = MeshInstance2D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(CHUNK_SIZE, CHUNK_SIZE)
	chunk.mesh_instance.mesh = quad
	chunk.mesh_instance.position = Vector2(coord) * CHUNK_SIZE + Vector2(CHUNK_SIZE / 2.0, CHUNK_SIZE / 2.0)

	var mat := ShaderMaterial.new()
	mat.shader = render_shader
	mat.set_shader_parameter("chunk_data", chunk.texture_2d_rd)
	chunk.mesh_instance.material = mat

	chunk_container.add_child(chunk.mesh_instance)
	chunks[coord] = chunk


func _unload_chunk(coord: Vector2i) -> void:
	var chunk: Chunk = chunks[coord]
	_free_chunk_resources(chunk)
	chunks.erase(coord)


func _free_chunk_resources(chunk: Chunk) -> void:
	if chunk.mesh_instance and is_instance_valid(chunk.mesh_instance):
		chunk.mesh_instance.queue_free()
	if chunk.sim_uniform_set.is_valid():
		rd.free_rid(chunk.sim_uniform_set)
	if chunk.rd_texture.is_valid():
		rd.free_rid(chunk.rd_texture)


# --- Simulation uniform sets ---

const NEIGHBOR_OFFSETS = [
	Vector2i(0, -1),  # top
	Vector2i(0, 1),   # bottom
	Vector2i(-1, 0),  # left
	Vector2i(1, 0),   # right
]


func _rebuild_sim_uniform_sets(loaded: Array[Vector2i], unloaded: Array[Vector2i]) -> void:
	var to_rebuild: Dictionary = {}
	for coord in loaded:
		to_rebuild[coord] = true
		for offset in NEIGHBOR_OFFSETS:
			var n := coord + offset
			if chunks.has(n):
				to_rebuild[n] = true
	for coord in unloaded:
		for offset in NEIGHBOR_OFFSETS:
			var n := coord + offset
			if chunks.has(n):
				to_rebuild[n] = true
	for coord in to_rebuild:
		if chunks.has(coord):
			_build_sim_uniform_set(chunks[coord])


func _build_sim_uniform_set(chunk: Chunk) -> void:
	if chunk.sim_uniform_set.is_valid():
		rd.free_rid(chunk.sim_uniform_set)

	var uniforms: Array[RDUniform] = []

	# Binding 0: own texture (read/write)
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(chunk.rd_texture)
	uniforms.append(u0)

	# Bindings 1-4: neighbor textures (top, bottom, left, right)
	for i in range(4):
		var n_coord := chunk.coord + NEIGHBOR_OFFSETS[i]
		var tex := dummy_texture
		if chunks.has(n_coord):
			tex = chunks[n_coord].rd_texture
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u.binding = i + 1
		u.add_id(tex)
		uniforms.append(u)

	chunk.sim_uniform_set = rd.uniform_set_create(uniforms, sim_shader, 0)


# --- Fire placement (called by InputHandler) ---

func place_fire(world_pos: Vector2, radius: float) -> void:
	var center_x := int(floor(world_pos.x))
	var center_y := int(floor(world_pos.y))
	var r := int(ceil(radius))

	# Group affected pixels by chunk
	var affected: Dictionary = {}  # Vector2i -> Array[Vector2i]
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var wx := center_x + dx
			var wy := center_y + dy
			var chunk_coord := Vector2i(floori(float(wx) / CHUNK_SIZE), floori(float(wy) / CHUNK_SIZE))
			if not chunks.has(chunk_coord):
				continue
			var local := Vector2i(posmod(wx, CHUNK_SIZE), posmod(wy, CHUNK_SIZE))
			if not affected.has(chunk_coord):
				affected[chunk_coord] = []
			affected[chunk_coord].append(local)

	for chunk_coord in affected:
		var chunk: Chunk = chunks[chunk_coord]
		var data := rd.texture_get_data(chunk.rd_texture, 0)
		for pixel_pos: Vector2i in affected[chunk_coord]:
			var idx := (pixel_pos.y * CHUNK_SIZE + pixel_pos.x) * 4
			data[idx] = 2      # material = fire
			data[idx + 1] = 255  # health = 255
			data[idx + 2] = 255  # temperature = 255
			data[idx + 3] = 0    # reserved
		rd.texture_update(chunk.rd_texture, 0, data)


# --- Public API for debug overlay ---

func get_active_chunk_coords() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coord in chunks:
		result.append(coord)
	return result
```

- [ ] **Step 2: Verify chunk rendering**

Run the project in Godot. Expected:
- The entire viewport fills with a uniform brown color (wood pixels)
- WASD moves the camera; new chunks load seamlessly at the edges
- No errors or warnings in the console
- Performance is smooth (no stutter on chunk load)

- [ ] **Step 3: Commit**

```bash
git add scripts/world_manager.gd
git commit -m "feat: implement WorldManager with chunk lifecycle and generation rendering"
```

---

### Task 3: WorldManager — Simulation Dispatch

Add the cellular automata simulation loop to WorldManager. After this task, the simulation runs every frame but with no visible change (all wood, no fire source).

**Files:**
- Modify: `scripts/world_manager.gd`

- [ ] **Step 1: Add simulation dispatch to _process**

In `scripts/world_manager.gd`, modify `_process` to call the simulation:

```gdscript
func _process(_delta: float) -> void:
	_update_chunks()
	_run_simulation()
```

Then add the `_run_simulation` method at the end of the file (before the `get_active_chunk_coords` method):

```gdscript
# --- Simulation dispatch ---

func _run_simulation() -> void:
	if chunks.is_empty():
		return

	var push_even := PackedByteArray()
	push_even.resize(16)
	push_even.encode_s32(0, 0)

	var push_odd := PackedByteArray()
	push_odd.resize(16)
	push_odd.encode_s32(0, 1)

	var compute_list := rd.compute_list_begin()

	# Even pass
	rd.compute_list_bind_compute_pipeline(compute_list, sim_pipeline)
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		if not chunk.sim_uniform_set.is_valid():
			continue
		rd.compute_list_bind_uniform_set(compute_list, chunk.sim_uniform_set, 0)
		rd.compute_list_set_push_constant(compute_list, push_even, push_even.size())
		rd.compute_list_dispatch(compute_list, NUM_WORKGROUPS, NUM_WORKGROUPS, 1)

	rd.compute_list_add_barrier(compute_list)

	# Odd pass
	rd.compute_list_bind_compute_pipeline(compute_list, sim_pipeline)
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		if not chunk.sim_uniform_set.is_valid():
			continue
		rd.compute_list_bind_uniform_set(compute_list, chunk.sim_uniform_set, 0)
		rd.compute_list_set_push_constant(compute_list, push_odd, push_odd.size())
		rd.compute_list_dispatch(compute_list, NUM_WORKGROUPS, NUM_WORKGROUPS, 1)

	rd.compute_list_end()
```

- [ ] **Step 2: Verify simulation runs without errors**

Run the project in Godot. Expected:
- Same brown wood world as before (no fire = no visible change)
- No errors, warnings, or GPU validation errors in console
- Performance remains smooth (simulation dispatch is lightweight with no state changes)

- [ ] **Step 3: Commit**

```bash
git add scripts/world_manager.gd
git commit -m "feat: add CA simulation dispatch with checkerboard pattern"
```

---

### Task 4: Input Handler — Fire Placement

Implement mouse click to place a circle of fire pixels. After this task, clicking places fire that spreads through the wood.

**Files:**
- Modify: `scripts/input_handler.gd`

- [ ] **Step 1: Implement input_handler.gd**

Replace `scripts/input_handler.gd` with:

```gdscript
extends Node

const FIRE_RADIUS := 5.0

@onready var world_manager: Node2D = get_parent().get_node("WorldManager")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var world_pos := get_viewport().get_canvas_transform().affine_inverse() * Vector2(event.position)
			world_manager.place_fire(world_pos, FIRE_RADIUS)
```

- [ ] **Step 2: Verify fire placement and propagation**

Run the project in Godot. Expected:
- Click anywhere on the brown wood to place a small circle of fire
- Fire pixels appear as bright orange/red
- Fire spreads outward to adjacent wood pixels over time
- Wood near fire tints red from heat before igniting
- Fire eventually burns out, leaving transparent (air) pixels
- Fire propagates across chunk boundaries (if you place fire near a chunk edge)

- [ ] **Step 3: Commit**

```bash
git add scripts/input_handler.gd
git commit -m "feat: add mouse click fire placement with radius"
```

---

### Task 5: Debug Manager — Chunk Grid Overlay

Implement the F3 debug overlay that draws chunk boundary lines.

**Files:**
- Modify: `scripts/debug_manager.gd`
- Modify: `scripts/chunk_grid_overlay.gd`

- [ ] **Step 1: Implement debug_manager.gd**

Replace `scripts/debug_manager.gd` with:

```gdscript
extends Node2D

func _ready() -> void:
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		visible = !visible
```

- [ ] **Step 2: Implement chunk_grid_overlay.gd**

Replace `scripts/chunk_grid_overlay.gd` with:

```gdscript
extends Node2D

const CHUNK_SIZE := 256
const LINE_COLOR := Color(0.0, 1.0, 0.0, 0.4)
const LINE_WIDTH := 1.0

@onready var world_manager: Node2D = get_parent().get_parent().get_node("WorldManager")

func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()

func _draw() -> void:
	var coords := world_manager.get_active_chunk_coords()
	for coord in coords:
		var rect := Rect2(
			Vector2(coord) * CHUNK_SIZE,
			Vector2(CHUNK_SIZE, CHUNK_SIZE)
		)
		draw_rect(rect, LINE_COLOR, false, LINE_WIDTH)
```

- [ ] **Step 3: Verify debug overlay**

Run the project in Godot. Expected:
- Press F3: green wireframe rectangles appear around each loaded chunk
- Press F3 again: overlay disappears
- Moving with WASD shows chunks loading/unloading, grid follows
- Overlay does not interfere with mouse click fire placement

- [ ] **Step 4: Commit**

```bash
git add scripts/debug_manager.gd scripts/chunk_grid_overlay.gd
git commit -m "feat: add F3 debug overlay with chunk grid"
```
