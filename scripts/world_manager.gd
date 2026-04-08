@tool
extends Node2D

const CHUNK_SIZE := 256
const WORKGROUP_SIZE := 8
const NUM_WORKGROUPS := CHUNK_SIZE / WORKGROUP_SIZE  # 32

const COLLISION_UPDATE_INTERVAL := 0.3
const MAX_COLLISION_SEGMENTS := 4096
const MAX_INJECTIONS_PER_CHUNK := 32
# Header: int count + 12 bytes padding (std430 16-byte alignment).
# Each InjectionAABB is 32 bytes (ivec2 min + ivec2 max + ivec2 vel + 2x i32 pad).
const INJECTION_BUFFER_SIZE := 16 + 32 * MAX_INJECTIONS_PER_CHUNK

var rd: RenderingDevice
var chunks: Dictionary = {}  # Vector2i -> Chunk

var gen_shader: RID
var gen_pipeline: RID
var sim_shader: RID
var sim_pipeline: RID
var collider_shader: RID
var collider_pipeline: RID
var collider_storage_buffer: RID
var dummy_texture: RID

var render_shader: Shader
var _gen_uniform_sets_to_free: Array[RID] = []
var material_textures: Texture2DArray

@onready var chunk_container: Node2D = $ChunkContainer
var collision_container: Node2D

## The position used for chunk loading/unloading. Set by the player controller.
var tracking_position: Vector2 = Vector2.ZERO
## Reference to the shadow grid for dirty notifications. Set by the player controller.
var shadow_grid: Node = null


func _ready() -> void:
	rd = RenderingServer.get_rendering_device()
	_init_shaders()
	_init_dummy_texture()
	_init_collider_storage_buffer()
	render_shader = preload("res://shaders/render_chunk.gdshader")
	_init_material_textures()
	
	collision_container = Node2D.new()
	collision_container.name = "CollisionContainer"
	add_child(collision_container)


func _init_material_textures() -> void:
	var images: Array[Image] = []
	for m in MaterialRegistry.materials:
		if m.texture_path.is_empty():
			var ref_img: Image
			if images.size() > 0:
				ref_img = images[0]
			else:
				ref_img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
				ref_img.fill(Color.TRANSPARENT)
			images.append(TextureArrayBuilder.create_placeholder_image(ref_img.get_size(), Color.TRANSPARENT))
		else:
			images.append(Image.load_from_file(m.texture_path))
	material_textures = TextureArrayBuilder.build_from_images(images)


func _exit_tree() -> void:
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		_free_chunk_resources(chunk)
	chunks.clear()
	if dummy_texture.is_valid():
		rd.free_rid(dummy_texture)
	if collider_storage_buffer.is_valid():
		rd.free_rid(collider_storage_buffer)
	if gen_pipeline.is_valid():
		rd.free_rid(gen_pipeline)
	if gen_shader.is_valid():
		rd.free_rid(gen_shader)
	if sim_pipeline.is_valid():
		rd.free_rid(sim_pipeline)
	if sim_shader.is_valid():
		rd.free_rid(sim_shader)
	if collider_pipeline.is_valid():
		rd.free_rid(collider_pipeline)
	if collider_shader.is_valid():
		rd.free_rid(collider_shader)


func _init_shaders() -> void:
	var gen_file: RDShaderFile = load("res://shaders/generation.glsl")
	var gen_spirv := gen_file.get_spirv()
	gen_shader = rd.shader_create_from_spirv(gen_spirv)
	gen_pipeline = rd.compute_pipeline_create(gen_shader)

	var sim_file: RDShaderFile = load("res://shaders/simulation.glsl")
	var sim_spirv := sim_file.get_spirv()
	sim_shader = rd.shader_create_from_spirv(sim_spirv)
	sim_pipeline = rd.compute_pipeline_create(sim_shader)

	var collider_file: RDShaderFile = load("res://shaders/collider.glsl")
	var collider_spirv := collider_file.get_spirv()
	collider_shader = rd.shader_create_from_spirv(collider_spirv)
	collider_pipeline = rd.compute_pipeline_create(collider_shader)


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


func _init_collider_storage_buffer() -> void:
	var max_segments := 4096
	var max_vertices := max_segments * 4
	var buffer_size := 4 + max_vertices * 4
	collider_storage_buffer = rd.storage_buffer_create(buffer_size)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_chunks()
	_run_simulation()
	_rebuild_dirty_collisions()


# --- Chunk lifecycle ---

func _get_desired_chunks() -> Array[Vector2i]:
	var vp_size := get_viewport().get_visible_rect().size
	# Use zoom from any Camera2D in the tree, default to 8x
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

			var push_data := PackedByteArray()
			push_data.resize(16)
			push_data.encode_s32(0, coord.x)
			push_data.encode_s32(4, coord.y)
			push_data.encode_u32(8, 0)
			push_data.encode_u32(12, 0)
			rd.compute_list_set_push_constant(compute_list, push_data, push_data.size())

			rd.compute_list_dispatch(compute_list, NUM_WORKGROUPS, NUM_WORKGROUPS, 1)
		rd.compute_list_end()

	# Rebuild simulation uniform sets for affected chunks
	if not new_chunks.is_empty() or not to_remove.is_empty():
		_rebuild_sim_uniform_sets(new_chunks, to_remove)
		_update_render_neighbors(new_chunks, to_remove)


func _create_chunk(coord: Vector2i) -> void:
	var chunk := Chunk.new()
	chunk.coord = coord

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

	chunk.injection_buffer = rd.storage_buffer_create(INJECTION_BUFFER_SIZE)
	# Zero-initialize (count = 0, no bodies) so the first dispatch is a no-op loop.
	var zero_data := PackedByteArray()
	zero_data.resize(INJECTION_BUFFER_SIZE)
	zero_data.fill(0)
	rd.buffer_update(chunk.injection_buffer, 0, zero_data.size(), zero_data)

	chunk.texture_2d_rd = Texture2DRD.new()
	chunk.texture_2d_rd.texture_rd_rid = chunk.rd_texture

	chunk.mesh_instance = MeshInstance2D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(CHUNK_SIZE, CHUNK_SIZE)
	chunk.mesh_instance.mesh = quad
	chunk.mesh_instance.position = Vector2(coord) * CHUNK_SIZE + Vector2(CHUNK_SIZE / 2.0, CHUNK_SIZE / 2.0)

	var mat := ShaderMaterial.new()
	mat.shader = render_shader
	mat.set_shader_parameter("chunk_data", chunk.texture_2d_rd)
	mat.set_shader_parameter("material_textures", material_textures)
	mat.set_shader_parameter("wall_height", 16)
	mat.set_shader_parameter("layer_mode", 1)
	chunk.mesh_instance.material = mat

	chunk_container.add_child(chunk.mesh_instance)

	# Wall top mesh (renders in front of player)
	chunk.wall_mesh_instance = MeshInstance2D.new()
	var wall_quad := QuadMesh.new()
	wall_quad.size = Vector2(CHUNK_SIZE, CHUNK_SIZE)
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

	chunk_container.add_child(chunk.wall_mesh_instance)

	chunk.static_body = StaticBody2D.new()
	chunk.static_body.collision_layer = 1
	chunk.static_body.collision_mask = 0
	collision_container.add_child(chunk.static_body)
	chunk.collision_dirty = true

	chunks[coord] = chunk


func _unload_chunk(coord: Vector2i) -> void:
	var chunk: Chunk = chunks[coord]
	_free_chunk_resources(chunk)
	chunks.erase(coord)


func _free_chunk_resources(chunk: Chunk) -> void:
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
			var n: Vector2i = coord + offset
			if chunks.has(n):
				to_rebuild[n] = true
	for coord in unloaded:
		for offset in NEIGHBOR_OFFSETS:
			var n: Vector2i = coord + offset
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
		var n_coord: Vector2i = chunk.coord + NEIGHBOR_OFFSETS[i]
		var tex := dummy_texture
		if chunks.has(n_coord):
			tex = chunks[n_coord].rd_texture
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u.binding = i + 1
		u.add_id(tex)
		uniforms.append(u)

	# Binding 5: rigidbody injection SSBO (per chunk)
	var u5 := RDUniform.new()
	u5.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u5.binding = 5
	u5.add_id(chunk.injection_buffer)
	uniforms.append(u5)

	chunk.sim_uniform_set = rd.uniform_set_create(uniforms, sim_shader, 0)


## Update render shader neighbor textures for wall face continuity across chunks.
## The wall face scan goes +px.y (north in world), so each chunk needs its
## northern neighbor's texture: chunk_coord + (0, -1).
func _update_render_neighbors(loaded: Array[Vector2i], unloaded: Array[Vector2i]) -> void:
	# Chunks that need their neighbor updated: newly loaded chunks and
	# chunks directly south of loaded/unloaded chunks (they gain/lose a neighbor).
	var to_update: Dictionary = {}
	for coord in loaded:
		to_update[coord] = true
		var south: Vector2i = coord + Vector2i(0, 1)
		if chunks.has(south):
			to_update[south] = true
	for coord in unloaded:
		var south: Vector2i = coord + Vector2i(0, 1)
		if chunks.has(south):
			to_update[south] = true

	for coord in to_update:
		if not chunks.has(coord):
			continue
		var chunk: Chunk = chunks[coord]
		var north_coord: Vector2i = coord + Vector2i(0, -1)
		var mat: ShaderMaterial = chunk.mesh_instance.material as ShaderMaterial
		if chunks.has(north_coord):
			mat.set_shader_parameter("neighbor_data", chunks[north_coord].texture_2d_rd)
			mat.set_shader_parameter("has_neighbor", true)
		else:
			mat.set_shader_parameter("has_neighbor", false)


# --- Simulation dispatch ---

func _run_simulation() -> void:
	if chunks.is_empty():
		return

	var push_even := PackedByteArray()
	push_even.resize(16)
	push_even.encode_s32(0, 0)
	push_even.encode_s32(4, randi())

	var push_odd := PackedByteArray()
	push_odd.resize(16)
	push_odd.encode_s32(0, 1)
	push_odd.encode_s32(4, randi())

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

	# Notify shadow grid if any simulated chunk overlaps its bounds
	if shadow_grid:
		var grid_rect: Rect2i = shadow_grid.get_world_rect()
		for coord in chunks:
			var chunk_rect := Rect2i(coord * CHUNK_SIZE, Vector2i(CHUNK_SIZE, CHUNK_SIZE))
			if grid_rect.intersects(chunk_rect):
				shadow_grid.mark_dirty()
				break


func _rebuild_dirty_collisions() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		if not chunk.collision_dirty:
			continue
		if now - chunk.last_collision_time < COLLISION_UPDATE_INTERVAL:
			continue
		
		var success := _rebuild_chunk_collision_gpu(chunk)
		if not success:
			_rebuild_chunk_collision_cpu(chunk)
		else:
			chunk.collision_dirty = _check_chunk_burning(chunk)
		
		chunk.last_collision_time = now


func _rebuild_chunk_collision_cpu(chunk: Chunk) -> void:
	var chunk_data := rd.texture_get_data(chunk.rd_texture, 0)
	var material_data := PackedByteArray()
	material_data.resize(CHUNK_SIZE * CHUNK_SIZE)
	var has_burning := false
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			var src_idx := (y * CHUNK_SIZE + x) * 4
			var mat := chunk_data[src_idx]
			var temp := chunk_data[src_idx + 2]
			material_data[y * CHUNK_SIZE + x] = mat
			if MaterialRegistry.is_flammable(mat) and temp > MaterialRegistry.get_ignition_temp(mat):
				has_burning = true
	chunk.collision_dirty = has_burning

	var world_offset := chunk.coord * CHUNK_SIZE
	if chunk.static_body.get_child_count() > 0:
		for child in chunk.static_body.get_children():
			child.queue_free()

	var collision_shape := TerrainCollider.build_collision(material_data, CHUNK_SIZE, chunk.static_body, world_offset)
	if collision_shape != null:
		chunk.static_body.add_child(collision_shape)


func _parse_segment_buffer(data: PackedByteArray, max_offset: int) -> PackedVector2Array:
	var segments := PackedVector2Array()
	var offset := 0
	while offset + 16 <= data.size() and offset < max_offset:
		var x1 := float(data.decode_u32(offset))
		var y1 := float(data.decode_u32(offset + 4))
		var x2 := float(data.decode_u32(offset + 8))
		var y2 := float(data.decode_u32(offset + 12))
		if x1 == 0.0 and y1 == 0.0 and x2 == 0.0 and y2 == 0.0:
			break
		segments.append(Vector2(x1, y1))
		segments.append(Vector2(x2, y2))
		offset += 16
	return segments


func _check_chunk_burning(chunk: Chunk) -> bool:
	var chunk_data := rd.texture_get_data(chunk.rd_texture, 0)
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			var src_idx := (y * CHUNK_SIZE + x) * 4
			var mat := chunk_data[src_idx]
			var temp := chunk_data[src_idx + 2]
			if MaterialRegistry.is_flammable(mat) and temp > MaterialRegistry.get_ignition_temp(mat):
				return true
	return false


func _rebuild_chunk_collision_gpu(chunk: Chunk) -> bool:
	var buffer_data := PackedByteArray()
	buffer_data.resize(4)
	buffer_data.encode_u32(0, 0)
	rd.buffer_update(collider_storage_buffer, 0, buffer_data.size(), buffer_data)

	var uniforms: Array[RDUniform] = []

	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(chunk.rd_texture)
	uniforms.append(u0)

	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u1.binding = 1
	u1.add_id(collider_storage_buffer)
	uniforms.append(u1)

	var uniform_set := rd.uniform_set_create(uniforms, collider_shader, 0)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, collider_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, 16, 16, 1)
	rd.compute_list_end()

	rd.free_rid(uniform_set)

	var result_data := rd.buffer_get_data(collider_storage_buffer)
	if result_data.size() < 4:
		return false

	var segment_count := result_data.decode_u32(0)
	if segment_count == 0:
		return true

	var segments := _parse_segment_buffer(result_data.slice(4), segment_count * 4)

	var world_offset := chunk.coord * CHUNK_SIZE
	if chunk.static_body.get_child_count() > 0:
		for child in chunk.static_body.get_children():
			child.queue_free()

	if segments.size() >= 4:
		var collision_shape := TerrainCollider.build_from_segments(
			segments, chunk.static_body, world_offset
		)
		if collision_shape != null:
			chunk.static_body.add_child(collision_shape)

	return true


## Debug: spawn a circular blob of gas at world_pos with given density.
func place_gas(world_pos: Vector2, radius: float, density: int) -> void:
	var center_x := int(floor(world_pos.x))
	var center_y := int(floor(world_pos.y))
	var r := int(ceil(radius))
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
	var clamped_density: int = clampi(density, 0, 255)
	for chunk_coord in affected:
		var chunk: Chunk = chunks[chunk_coord]
		var data := rd.texture_get_data(chunk.rd_texture, 0)
		var modified := false
		for pixel_pos: Vector2i in affected[chunk_coord]:
			var idx := (pixel_pos.y * CHUNK_SIZE + pixel_pos.x) * 4
			if data[idx] != MaterialRegistry.MAT_AIR:
				continue
			data[idx] = MaterialRegistry.MAT_GAS
			data[idx + 1] = clamped_density
			data[idx + 2] = 0
			data[idx + 3] = (8 << 4) | 8  # packed velocity (0, 0)
			modified = true
		if modified:
			rd.texture_update(chunk.rd_texture, 0, data)


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
		var modified := false
		for pixel_pos: Vector2i in affected[chunk_coord]:
			var idx := (pixel_pos.y * CHUNK_SIZE + pixel_pos.x) * 4
			var material := data[idx]
			if not MaterialRegistry.is_flammable(material):
				continue
			data[idx + 2] = 255
			modified = true
		if modified:
			rd.texture_update(chunk.rd_texture, 0, data)
			chunk.collision_dirty = true


# --- Public API for debug overlay ---

func get_active_chunk_coords() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coord in chunks:
		result.append(coord)
	return result


func generate_chunks_at(coords: Array[Vector2i], seed_val: int) -> void:
	for us in _gen_uniform_sets_to_free:
		rd.free_rid(us)
	_gen_uniform_sets_to_free.clear()

	var new_chunks: Array[Vector2i] = []
	for coord in coords:
		if not chunks.has(coord):
			_create_chunk(coord)
			new_chunks.append(coord)

	if new_chunks.is_empty():
		return

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

		var push_data := PackedByteArray()
		push_data.resize(16)
		push_data.encode_s32(0, coord.x)
		push_data.encode_s32(4, coord.y)
		push_data.encode_u32(8, seed_val)
		push_data.encode_u32(12, 0)
		rd.compute_list_set_push_constant(compute_list, push_data, push_data.size())

		rd.compute_list_dispatch(compute_list, NUM_WORKGROUPS, NUM_WORKGROUPS, 1)
	rd.compute_list_end()

	_rebuild_sim_uniform_sets(new_chunks, [])
	_update_render_neighbors(new_chunks, [])


func clear_all_chunks() -> void:
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		_free_chunk_resources(chunk)
	chunks.clear()
	for us in _gen_uniform_sets_to_free:
		rd.free_rid(us)
	_gen_uniform_sets_to_free.clear()


func get_chunk_container() -> Node2D:
	return chunk_container


## Read material bytes for a rectangular world region from GPU chunk textures.
## Returns a PackedByteArray of width*height bytes (one byte per pixel, material type).
## Pixels in unloaded chunks are returned as 255 (solid).
func read_region(region: Rect2i) -> PackedByteArray:
	var width: int = region.size.x
	var height: int = region.size.y
	var result := PackedByteArray()
	result.resize(width * height)
	result.fill(255)  # Default: solid for unloaded areas

	# Determine which chunks overlap this region
	var min_chunk := Vector2i(
		floori(float(region.position.x) / CHUNK_SIZE),
		floori(float(region.position.y) / CHUNK_SIZE)
	)
	var max_chunk := Vector2i(
		floori(float(region.end.x - 1) / CHUNK_SIZE),
		floori(float(region.end.y - 1) / CHUNK_SIZE)
	)

	for cx in range(min_chunk.x, max_chunk.x + 1):
		for cy in range(min_chunk.y, max_chunk.y + 1):
			var chunk_coord := Vector2i(cx, cy)
			if not chunks.has(chunk_coord):
				continue

			var chunk: Chunk = chunks[chunk_coord]
			var chunk_data := rd.texture_get_data(chunk.rd_texture, 0)

			# World-space origin of this chunk
			var chunk_origin := chunk_coord * CHUNK_SIZE

			# Overlap between the requested region and this chunk
			var chunk_rect := Rect2i(chunk_origin, Vector2i(CHUNK_SIZE, CHUNK_SIZE))
			var overlap := region.intersection(chunk_rect)

			for y in range(overlap.position.y, overlap.end.y):
				for x in range(overlap.position.x, overlap.end.x):
					var local_x: int = x - chunk_origin.x
					var local_y: int = y - chunk_origin.y
					var chunk_idx: int = (local_y * CHUNK_SIZE + local_x) * 4  # RGBA8
					var material: int = chunk_data[chunk_idx]  # R channel = material type

					var result_x: int = x - region.position.x
					var result_y: int = y - region.position.y
					result[result_y * width + result_x] = material

	return result


## Find a spawn position by spiraling outward from search_origin.
## Looks for a contiguous air pocket that fits body_size.
## Returns the top-left corner of the pocket in world coordinates.
## Falls back to search_origin if no pocket found within max_radius.
func find_spawn_position(search_origin: Vector2i, body_size: Vector2i) -> Vector2i:
	var max_radius := CHUNK_SIZE * 4  # Search up to 4 chunks away
	var search_rect := Rect2i(
		search_origin - Vector2i(max_radius, max_radius),
		Vector2i(max_radius * 2, max_radius * 2)
	)
	var region_data := read_region(search_rect)
	var region_w: int = search_rect.size.x
	var region_h: int = search_rect.size.y

	# Spiral outward from center of the search region
	var center := Vector2i(max_radius, max_radius)
	var dir := Vector2i(1, 0)
	var pos := center
	var steps_in_leg := 1
	var steps_taken := 0
	var legs_completed := 0

	for _i in range(region_w * region_h):
		# Check if body_size fits at this position (all air)
		if _pocket_fits(region_data, region_w, region_h, pos, body_size):
			return search_rect.position + pos

		# Spiral step
		pos += dir
		steps_taken += 1
		if steps_taken >= steps_in_leg:
			steps_taken = 0
			legs_completed += 1
			# Rotate direction: right -> down -> left -> up
			dir = Vector2i(-dir.y, dir.x)
			if legs_completed % 2 == 0:
				steps_in_leg += 1

	push_warning("ShadowGrid: No valid spawn pocket found, falling back to search_origin")
	return search_origin


func _pocket_fits(data: PackedByteArray, region_w: int, region_h: int, top_left: Vector2i, size: Vector2i) -> bool:
	if top_left.x < 0 or top_left.y < 0:
		return false
	if top_left.x + size.x > region_w or top_left.y + size.y > region_h:
		return false
	for y in range(top_left.y, top_left.y + size.y):
		for x in range(top_left.x, top_left.x + size.x):
			if data[y * region_w + x] != MaterialRegistry.MAT_AIR:
				return false
	return true
