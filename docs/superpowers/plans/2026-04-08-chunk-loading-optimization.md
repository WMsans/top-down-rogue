# Chunk Loading Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate chunk loading lag by implementing object pooling, asynchronous generation, and predictive loading.

**Architecture:** Three-pronged approach: ChunkPool reuses GPU resources for revisited chunks, ChunkQueue spreads generation across frames, PredictiveLoader pre-loads chunks based on player movement.

**Tech Stack:** GDScript, Godot RenderingDevice API, Compute Shaders

---

## File Structure

**Create:**
- `scripts/chunk_pool.gd` - Manages pool of reusable chunk resources
- `scripts/chunk_queue.gd` - Processes chunk generation/updates across frames
- `scripts/predictive_loader.gd` - Predicts player movement, pre-loads chunks

**Modify:**
- `scripts/chunk.gd` - Add reset method for pooling
- `scripts/world_manager.gd` - Integrate pool, queue, predictive loader

---

## Task 1: Create ChunkPool Class

**Files:**
- Create: `scripts/chunk_pool.gd`

- [ ] **Step 1: Create ChunkPool class skeleton**

```gdscript
class_name ChunkPool
extends RefCounted

var inactive_chunks: Dictionary = {}  # Vector2i -> Chunk
var max_pool_size: int
var rd: RenderingDevice
var gen_shader: RID
var gen_pipeline: RID
var render_shader: Shader
var material_textures: Texture2DArray
var collider_container: Node2D

func _init(
	rd_param: RenderingDevice,
	gen_shader_param: RID,
	gen_pipeline_param: RID,
	render_shader_param: Shader,
	material_textures_param: Texture2DArray,
	collider_container_param: Node2D,
	max_pool_size_param: int = 64
):
	rd = rd_param
	gen_shader = gen_shader_param
	gen_pipeline = gen_pipeline_param
	render_shader = render_shader_param
	material_textures = material_textures_param
	collider_container = collider_container_param
	max_pool_size = max_pool_size_param
```

- [ ] **Step 2: Add get_chunk method to ChunkPool**

```gdscript
func get_chunk(coord: Vector2i) -> Chunk:
	if inactive_chunks.has(coord):
		var chunk: Chunk = inactive_chunks[coord]
		inactive_chunks.erase(coord)
		chunk.coord = coord
		_reset_chunk(chunk)
		return chunk
	return _create_new_chunk(coord)
```

- [ ] **Step 3: Add return_chunk method to ChunkPool**

```gdscript
func return_chunk(coord: Vector2i, chunk: Chunk) -> void:
	if inactive_chunks.size() >= max_pool_size:
		_free_chunk(chunk)
		return
	chunk.mesh_instance.visible = false
	chunk.wall_mesh_instance.visible = false
	inactive_chunks[coord] = chunk
```

- [ ] **Step 4: Add helper methods to ChunkPool**

```gdscript
func _reset_chunk(chunk: Chunk) -> void:
	chunk.mesh_instance.visible = true
	chunk.wall_mesh_instance.visible = true
	chunk.collision_dirty = true
	chunk.last_collision_time = 0.0
	_zero_texture(chunk.rd_texture)

func _zero_texture(texture_rid: RID) -> void:
	var zero_data := PackedByteArray()
	zero_data.resize(256 * 256 * 4)
	zero_data.fill(0)
	rd.texture_update(texture_rid, 0, zero_data)

func _create_new_chunk(coord: Vector2i) -> Chunk:
	var chunk := Chunk.new()
	chunk.coord = coord
	
	var tf := RDTextureFormat.new()
	tf.width = 256
	tf.height = 256
	tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tf.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	chunk.rd_texture = rd.texture_create(tf, RDTextureView.new())
	
	chunk.injection_buffer = rd.storage_buffer_create(16 + 32 * 32)
	var zero_data := PackedByteArray()
	zero_data.resize(16 + 32 * 32)
	zero_data.fill(0)
	rd.buffer_update(chunk.injection_buffer, 0, zero_data.size(), zero_data)
	
	chunk.texture_2d_rd = Texture2DRD.new()
	chunk.texture_2d_rd.texture_rd_rid = chunk.rd_texture
	
	var quad := QuadMesh.new()
	quad.size = Vector2(256, 256)
	
	chunk.mesh_instance = MeshInstance2D.new()
	chunk.mesh_instance.mesh = quad
	chunk.mesh_instance.position = Vector2(coord) * 256 + Vector2(128, 128)
	
	var mat := ShaderMaterial.new()
	mat.shader = render_shader
	mat.set_shader_parameter("chunk_data", chunk.texture_2d_rd)
	mat.set_shader_parameter("material_textures", material_textures)
	mat.set_shader_parameter("wall_height", 16)
	mat.set_shader_parameter("layer_mode", 1)
	chunk.mesh_instance.material = mat
	
	var wall_quad := QuadMesh.new()
	wall_quad.size = Vector2(256, 256)
	
	chunk.wall_mesh_instance = MeshInstance2D.new()
	chunk.wall_mesh_instance.mesh = wall_quad
	chunk.wall_mesh_instance.position = chunk.mesh_instance.position
	chunk.wall_mesh_instance.z_index = 1
	
	var wall_mat := ShaderMaterial.new()
	wall_mat.shader = render_shader
	wall_mat.set_shader_parameter("chunk_data", chunk.texture_2d_rd)
	wall_mat.set_shader_parameter("material_textures", material_textures)
	wall_mat.set_shader_parameter("wall_height", 16)
	wall_mat.set_shader_parameter("layer_mode", 0)
	chunk.wall_mesh_instance.material = wall_mat
	
	chunk.static_body = StaticBody2D.new()
	chunk.static_body.collision_layer = 1
	chunk.static_body.collision_mask = 0
	
	return chunk

func _free_chunk(chunk: Chunk) -> void:
	if chunk.mesh_instance and is_instance_valid(chunk.mesh_instance):
		chunk.mesh_instance.queue_free()
	if chunk.wall_mesh_instance and is_instance_valid(chunk.wall_mesh_instance):
		chunk.wall_mesh_instance.queue_free()
	if chunk.static_body and is_instance_valid(chunk.static_body):
		chunk.static_body.queue_free()
	if chunk.injection_buffer.is_valid():
		rd.free_rid(chunk.injection_buffer)
	if chunk.sim_uniform_set.is_valid():
		rd.free_rid(chunk.sim_uniform_set)
	if chunk.rd_texture.is_valid():
		rd.free_rid(chunk.rd_texture)

func clear() -> void:
	for coord in inactive_chunks:
		_free_chunk(inactive_chunks[coord])
	inactive_chunks.clear()
```

- [ ] **Step 5: Create the .uid file for ChunkPool**

```json
{"path":"res://scripts/chunk_pool.gd","class_name":"ChunkPool","language":"GDScript","uid":"uid://chunkpool001"}
```

- [ ] **Step 6: Commit ChunkPool implementation**

```bash
git add scripts/chunk_pool.gd scripts/chunk_pool.gd.uid
git commit -m "feat: add ChunkPool class for resource reuse"
```

---

## Task 2: Create ChunkQueue Class

**Files:**
- Create: `scripts/chunk_queue.gd`

- [ ] **Step 1: Create ChunkQueue class with queue structures**

```gdscript
class_name ChunkQueue
extends RefCounted

var pending_generation: Array = []  # Array[Dictionary] with {coord, priority}
var pending_texture_reset: Array = []# Array[Dictionary] with {coord, chunk}
var max_generation_per_frame: int = 2
var max_texture_updates_per_frame: int = 4

func add_generation(coord: Vector2i, priority: float) -> void:
	for item in pending_generation:
		if item.coord == coord:
			item.priority = min(item.priority, priority)
			return
	pending_generation.append({"coord": coord, "priority": priority})

func add_texture_reset(coord: Vector2i, chunk: Chunk) -> void:
	for item in pending_texture_reset:
		if item.coord == coord:
			return
	pending_texture_reset.append({"coord": coord, "chunk": chunk})

func has_pending(coord: Vector2i) -> bool:
	for item in pending_generation:
		if item.coord == coord:
			return true
	for item in pending_texture_reset:
		if item.coord == coord:
			return true
	return false
```

- [ ] **Step 2: Add process_next_frame method to ChunkQueue**

```gdscript
func process_next_frame(
	rd: RenderingDevice,
	gen_pipeline: RID,
	gen_shader: RID,
	chunks: Dictionary,
	dummy_texture: RID,
	sim_shader: RID,
	collider_storage_buffer: RID,
	on_chunk_ready: Callable
) -> Dictionary:
	var processed := {"generated": [], "reset": []}
	
	# Sort pending generation by priority (lower distance = higher priority)
	pending_generation.sort_custom(func(a, b): return a.priority < b.priority)
	
	# Process texture resets first (faster)
	var reset_count := 0
	while reset_count < max_texture_updates_per_frame and not pending_texture_reset.is_empty():
		var item: Dictionary = pending_texture_reset.pop_front()
		var coord: Vector2i = item.coord
		var chunk: Chunk = item.chunk
		if not chunks.has(coord) or chunks[coord] != chunk:
			continue
		var zero_data := PackedByteArray()
		zero_data.resize(256 * 256 * 4)
		zero_data.fill(0)
		rd.texture_update(chunk.rd_texture, 0, zero_data)
		processed.reset.append(coord)
		reset_count += 1
	
	# Process generation dispatches
	var gen_count := 0
	while gen_count < max_generation_per_frame and not pending_generation.is_empty():
		var item: Dictionary = pending_generation.pop_front()
		var coord: Vector2i = item.coord
		if not chunks.has(coord):
			continue
		_dispatch_generation(rd, gen_pipeline, gen_shader, chunks[coord])
		if on_chunk_ready.is_valid():
			on_chunk_ready.call(coord)
		processed.generated.append(coord)
		gen_count += 1
	
	return processed

func _dispatch_generation(rd: RenderingDevice, gen_pipeline: RID, gen_shader: RID, chunk: Chunk) -> void:
	var gen_uniform := RDUniform.new()
	gen_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	gen_uniform.binding = 0
	gen_uniform.add_id(chunk.rd_texture)
	var uniform_set := rd.uniform_set_create([gen_uniform], gen_shader, 0)
	
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, gen_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	
	var push_data := PackedByteArray()
	push_data.resize(16)
	push_data.encode_s32(0, chunk.coord.x)
	push_data.encode_s32(4, chunk.coord.y)
	push_data.encode_u32(8, 0)
	push_data.encode_u32(12, 0)
	rd.compute_list_set_push_constant(compute_list, push_data, push_data.size())
	
	rd.compute_list_dispatch(compute_list, 32, 32, 1)
	rd.compute_list_end()
	
	rd.free_rid(uniform_set)
```

- [ ] **Step 3: Create the .uid file for ChunkQueue**

```json
{"path":"res://scripts/chunk_queue.gd","class_name":"ChunkQueue","language":"GDScript","uid":"uid://chunkqueue001"}
```

- [ ] **Step 4: Commit ChunkQueue implementation**

```bash
git add scripts/chunk_queue.gd scripts/chunk_queue.gd.uid
git commit -m "feat: add ChunkQueue class for async chunk processing"
```

---

## Task 3: Create PredictiveLoader Class

**Files:**
- Create: `scripts/predictive_loader.gd`

- [ ] **Step 1: Create PredictiveLoader class skeleton**

```gdscript
class_name PredictiveLoader
extends RefCounted

var position_history: Array = []  # Array[Vector2]
var history_size: int = 10
var chunks_ahead: int = 1

func update(player_pos: Vector2) -> void:
	position_history.append(player_pos)
	if position_history.size() > history_size:
		position_history.pop_front()
```

- [ ] **Step 2: Add prediction method to PredictiveLoader**

```gdscript
func get_predicted_chunks(current_view: Array[Vector2i], player_pos: Vector2) -> Array[Vector2i]:
	if position_history.size() < 3:
		return []
	
	var velocity := _calculate_velocity()
	if velocity.length() < 10.0:
		return []player not moving fast enough
	
	var predicted_coords: Array[Vector2i] = []
	var direction := velocity.normalized()
	
	for i in range(1, chunks_ahead + 1):
		var future_pos := player_pos + direction * (256.0 * float(i))
		var chunk_coord := Vector2i(
			floori(future_pos.x / 256.0),
			floori(future_pos.y / 256.0)
		)
		var is_new := true
		for existing in current_view:
			if existing == chunk_coord:
				is_new = false
				break
		if is_new:
			predicted_coords.append(chunk_coord)
	
	return predicted_coords

func _calculate_velocity() -> Vector2:
	if position_history.size() < 2:
		return Vector2.ZERO
	
	var recent := position_history.slice(-min(5, position_history.size()))
	if recent.size() < 2:
		return Vector2.ZERO
	
	var total_velocity := Vector2.ZERO
	for i in range(1, recent.size()):
		total_velocity += recent[i] - recent[i - 1]
	
	return total_velocity / float(recent.size() - 1)
```

- [ ] **Step 3: Create the .uid file for PredictiveLoader**

```json
{"path":"res://scripts/predictive_loader.gd","class_name":"PredictiveLoader","language":"GDScript","uid":"uid://predictiveloader001"}
```

- [ ] **Step 4: Commit PredictiveLoader implementation**

```bash
git add scripts/predictive_loader.gd scripts/predictive_loader.gd.uid
git commit -m "feat: add PredictiveLoader for movement-based pre-loading"
```

---

## Task 4: Modify Chunk Class

**Files:**
- Modify: `scripts/chunk.gd`

- [ ] **Step 1: Read current Chunk implementation**

Read `scripts/chunk.gd` to see current state.

- [ ] **Step 2: Add recycled flag to Chunk class**

```gdscript
class_name Chunk
extends RefCounted

var coord: Vector2i
var rd_texture: RID
var texture_2d_rd: Texture2DRD
var mesh_instance: MeshInstance2D
var wall_mesh_instance: MeshInstance2D
var sim_uniform_set: RID
var injection_buffer: RID
var static_body: StaticBody2D
var collision_dirty: bool = true
var last_collision_time: float = 0.0
var is_recycled: bool = false
```

- [ ] **Step 3: Commit Chunk modification**

```bash
git add scripts/chunk.gd
git commit -m "feat: add is_recycled flag to Chunk class"
```

---

## Task 5: Integrate into WorldManager

**Files:**
- Modify: `scripts/world_manager.gd`

- [ ] **Step 1: Read current WorldManager implementation**

Read `scripts/world_manager.gd` lines 1-50 to see current state.

- [ ] **Step 2: Add pool, queue, and predictive loader instances to WorldManager**

Find the section with variable declarations after line 15, add:

```gdscript
var chunk_pool: ChunkPool
var chunk_queue: ChunkQueue
var predictive_loader: PredictiveLoader
```

- [ ] **Step 3: Initialize pool, queue, and loader in _ready**

Find the `_ready` function (around line 40), after `_init_material_textures()`:

```gdscript
func _ready() -> void:
	rd = RenderingServer.get_rendering_device()
	_init_shaders()
	_init_dummy_texture()
	_init_collider_storage_buffer()
	render_shader = preload("res://shaders/render_chunk.gdshader")
	_init_material_textures()
	
	# Create collision container before pool initialization
	collision_container = Node2D.new()
	collision_container.name = "CollisionContainer"
	add_child(collision_container)
	
	# Initialize pool and queue
	chunk_pool = ChunkPool.new(
		rd,
		gen_shader,
		gen_pipeline,
		render_shader,
		material_textures,
		collision_container,
		64
	)
	chunk_queue = ChunkQueue.new()
	predictive_loader = PredictiveLoader.new()
```

- [ ] **Step 4: Modify _exit_tree to clear pool**

Find the `_exit_tree` function (around line 69), add before `chunks.clear()`:

```gdscript
func _exit_tree() -> void:
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		_free_chunk_resources(chunk)
	chunks.clear()
	
	if chunk_pool:
		chunk_pool.clear()
	
	# ... rest of cleanup
```

- [ ] **Step 5: Modify _get_desired_chunks to include predictive chunks**

Find the `_get_desired_chunks` function (around line 138), modify to:

```gdscript
func _get_desired_chunks() -> Array[Vector2i]:
	var vp_size := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	var cam_zoom := cam.zoom if cam else Vector2(8, 8)
	var half_view := vp_size / (2.0 * cam_zoom)
	
	var min_chunk := Vector2i(
		floori((tracking_position.x - half_view.x) / CHUNK_SIZE) - 1,
		floori((tracking_position.y - half_view.y) / CHUNK_SIZE) - 1
	)
	var max_chunk := Vector2i(
		floori((tracking_position.x + half_view.x) / CHUNK_SIZE) + 1,
		floori((tracking_position.y + half_view.y) / CHUNK_SIZE) + 1
	)
	
	var result: Array[Vector2i] = []
	for x in range(min_chunk.x, max_chunk.x + 1):
		for y in range(min_chunk.y, max_chunk.y + 1):
			result.append(Vector2i(x, y))
	
	# Add predictive chunks
	var predicted := predictive_loader.get_predicted_chunks(result, tracking_position)
	for coord in predicted:
		if not result.has(coord):
			result.append(coord)
	
	return result
```

- [ ] **Step 6: Modify _update_chunks to use pool and queue**

Find the `_update_chunks` function (around line 161), modify to:

```gdscript
func _update_chunks() -> void:
	# Free previous frame's generation uniform sets
	for us in _gen_uniform_sets_to_free:
		rd.free_rid(us)
	_gen_uniform_sets_to_free.clear()
	
	# Process queue first (async processing)
	var processed := chunk_queue.process_next_frame(
		rd,
		gen_pipeline,
		gen_shader,
		chunks,
		dummy_texture,
		sim_shader,
		collider_storage_buffer,
		_rebuild_after_generation
	)
	
	# Update predictive loader position
	predictive_loader.update(tracking_position)
	
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
	
	# Queue new chunks
	var new_chunks: Array[Vector2i] = []
	for coord in desired:
		if not chunks.has(coord):
			_load_chunk(coord)
			new_chunks.append(coord)
		elif not chunk_queue.has_pending(coord):
			# Chunk exists and not pending, check if needs rebuild
			var chunk: Chunk = chunks[coord]
			if chunk.is_recycled:
				chunk_queue.add_texture_reset(coord, chunk)
	
	# Rebuild simulation uniform sets for newly loaded chunks
	if not new_chunks.is_empty() or not to_remove.is_empty():
		_rebuild_sim_uniform_sets(new_chunks, to_remove)
		_update_render_neighbors(new_chunks, to_remove)
```

- [ ] **Step 7: Modify _create_chunk to use pool**

Find the `_create_chunk` function (around line 218), replace the entire function:

```gdscript
func _load_chunk(coord: Vector2i) -> void:
	var chunk := chunk_pool.get_chunk(coord)
	chunk.is_recycled = chunk_pool.inactive_chunks.has(coord)
	chunks[coord] = chunk
	
	chunk_container.add_child(chunk.mesh_instance)
	chunk_container.add_child(chunk.wall_mesh_instance)
	collision_container.add_child(chunk.static_body)
	
	# Queue for generation or texture reset
	var player_chunk := Vector2i(
		floori(tracking_position.x / float(CHUNK_SIZE)),
		floori(tracking_position.y / float(CHUNK_SIZE))
	)
	var distance := (Vector2(coord) - Vector2(player_chunk)).length()
	
	if chunk.is_recycled:
		chunk_queue.add_texture_reset(coord, chunk)
	else:
		chunk_queue.add_generation(coord, distance)
```

- [ ] **Step 8: Modify _unload_chunk to return to pool**

Find the `_unload_chunk` function (around line 287), replace:

```gdscript
func _unload_chunk(coord: Vector2i) -> void:
	var chunk: Chunk = chunks[coord]
	chunk_container.remove_child(chunk.mesh_instance)
	chunk_container.remove_child(chunk.wall_mesh_instance)
	collision_container.remove_child(chunk.static_body)
	chunks.erase(coord)
	
	# Remove from scene tree but keep in pool
	chunk.is_recycled = true
	chunk_pool.return_chunk(coord, chunk)
```

- [ ] **Step 9: Add callback for chunk generation completion**

Add new function after `_unload_chunk`:

```gdscript
func _rebuild_after_generation(coord: Vector2i) -> void:
	if not chunks.has(coord):
		return
	var chunk: Chunk = chunks[coord]
	var loaded: Array[Vector2i] = [coord]
	_rebuild_sim_uniform_sets(loaded, [])
	_update_render_neighbors(loaded, [])
```

- [ ] **Step 10: Update _free_chunk_resources to handle recycled chunks**

Find `_free_chunk_resources` function (around line 293), verify it still works correctly or note that pool handles freeing.

Actually, we need to keep this for `_exit_tree` cleanup. The pool handles runtime unloading, but exit_tree needs to free everything.

- [ ] **Step 11: Commit WorldManager integration**

```bash
git add scripts/world_manager.gd
git commit -m "feat: integrate pool, queue, and predictive loader into WorldManager"
```

---

## Task 6: Update clear_all_chunks

**Files:**
- Modify: `scripts/world_manager.gd`

- [ ] **Step 1: Modify clear_all_chunks to use pool**

Find `clear_all_chunks` function (around line 717), modify to:

```gdscript
func clear_all_chunks() -> void:
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		_free_chunk_resources(chunk)
	chunks.clear()
	chunk_pool.clear()
	for us in _gen_uniform_sets_to_free:
		rd.free_rid(us)
	_gen_uniform_sets_to_free.clear()
```

- [ ] **Step 2: Commit clear_all_chunks update**

```bash
git add scripts/world_manager.gd
git commit -m "fix: clear pool when clearing all chunks"
```

---

## Task 7: Test and Profile

**Files:**
- None (testing task)

- [ ] **Step 1: Run the game and observe chunk loading**

Start the game and move around to trigger chunk loading. Observe if lag is reduced.

- [ ] **Step 2: Profile with Godot profiler**

Enable Godot profiler, move around, and check:
- Frame time spikes during chunk loading
- GPU memory usage with pool enabled
- Time spent in `_update_chunks`

- [ ] **Step 3: Test rapid back-and-forth movement**

Move rapidly back and forth across chunk boundaries to test pool effectiveness.

- [ ] **Step 4: Test sustained forward movement**

Move in one direction to test predictive loading effectiveness.

- [ ] **Step 5: Document performance improvements**

Note before/after frame times and stutter reduction in the commit message.

---

## Summary

This plan implements three optimization strategies:

1. **ChunkPool** reuses GPU resources when returning to previously visited areas
2. **ChunkQueue** spreads generation across frames to avoid single-frame stutter
3. **PredictiveLoader** pre-loads chunks based on player movement direction

Expected outcome: Near-instant chunk loading for pooled chunks, smooth 2-3 frame load for new chunks, no single frame exceeding 20ms.