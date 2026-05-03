class_name ChunkManager
extends RefCounted

const CHUNK_SIZE := 256
const WORKGROUP_SIZE := 8
const NUM_WORKGROUPS := CHUNK_SIZE / WORKGROUP_SIZE
const MAX_INJECTIONS_PER_CHUNK := 32
const INJECTION_BUFFER_SIZE := 16 + 32 * MAX_INJECTIONS_PER_CHUNK

const NEIGHBOR_OFFSETS = [
	Vector2i(0, -1),
	Vector2i(0, 1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
]

var world_manager: Node2D


func _init(manager: Node2D) -> void:
	world_manager = manager


func get_desired_chunks(tracking_position: Vector2) -> Array[Vector2i]:
	var vp_size := world_manager.get_viewport().get_visible_rect().size
	var cam := world_manager.get_viewport().get_camera_2d()
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


func create_chunk(coord: Vector2i) -> void:
	var compute: ComputeDevice = world_manager.compute_device
	var chunks: Dictionary = world_manager.chunks

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
	chunk.rd_texture = world_manager.rd.texture_create(tf, RDTextureView.new())

	chunk.injection_buffer = world_manager.rd.storage_buffer_create(INJECTION_BUFFER_SIZE)
	var zero_data := PackedByteArray()
	zero_data.resize(INJECTION_BUFFER_SIZE)
	zero_data.fill(0)
	world_manager.rd.buffer_update(chunk.injection_buffer, 0, zero_data.size(), zero_data)

	var light_output_size := 128  # 16 cells × 8 bytes (2 uints)
	chunk.light_output_buffer = world_manager.rd.storage_buffer_create(light_output_size)

	chunk.texture_2d_rd = Texture2DRD.new()
	chunk.texture_2d_rd.texture_rd_rid = chunk.rd_texture

	chunk.mesh_instance = MeshInstance2D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(CHUNK_SIZE, CHUNK_SIZE)
	chunk.mesh_instance.mesh = quad
	chunk.mesh_instance.position = Vector2(coord) * CHUNK_SIZE + Vector2(CHUNK_SIZE / 2.0, CHUNK_SIZE / 2.0)

	var mat := ShaderMaterial.new()
	mat.shader = compute.render_shader
	mat.set_shader_parameter("chunk_data", chunk.texture_2d_rd)
	mat.set_shader_parameter("material_textures", compute.material_textures)
	mat.set_shader_parameter("wall_height", 16)
	mat.set_shader_parameter("layer_mode", 1)
	chunk.mesh_instance.material = mat

	world_manager.chunk_container.add_child(chunk.mesh_instance)

	chunk.wall_mesh_instance = MeshInstance2D.new()
	var wall_quad := QuadMesh.new()
	wall_quad.size = Vector2(CHUNK_SIZE, CHUNK_SIZE)
	chunk.wall_mesh_instance.mesh = wall_quad
	chunk.wall_mesh_instance.position = chunk.mesh_instance.position
	chunk.wall_mesh_instance.z_index = 1

	var wall_mat := ShaderMaterial.new()
	wall_mat.shader = compute.render_shader
	wall_mat.set_shader_parameter("chunk_data", chunk.texture_2d_rd)
	wall_mat.set_shader_parameter("material_textures", compute.material_textures)
	wall_mat.set_shader_parameter("wall_height", 16)
	wall_mat.set_shader_parameter("layer_mode", 0)
	chunk.wall_mesh_instance.material = wall_mat

	world_manager.chunk_container.add_child(chunk.wall_mesh_instance)

	chunk.static_body = StaticBody2D.new()
	chunk.static_body.collision_layer = 1
	chunk.static_body.collision_mask = 0
	world_manager.collision_container.add_child(chunk.static_body)

	chunk.occluder_instances = []

	chunks[coord] = chunk

	build_light_pack_uniform_set(chunk)


func unload_chunk(coord: Vector2i) -> void:
	var chunk: Chunk = world_manager.chunks[coord]
	free_chunk_resources(chunk)
	world_manager.chunks.erase(coord)


func free_chunk_resources(chunk: Chunk) -> void:
	if chunk.mesh_instance and is_instance_valid(chunk.mesh_instance):
		chunk.mesh_instance.queue_free()
	if chunk.wall_mesh_instance and is_instance_valid(chunk.wall_mesh_instance):
		chunk.wall_mesh_instance.queue_free()
	if chunk.static_body and is_instance_valid(chunk.static_body):
		chunk.static_body.queue_free()
	for occluder in chunk.occluder_instances:
		if is_instance_valid(occluder):
			occluder.queue_free()
	chunk.occluder_instances.clear()
	if chunk.injection_buffer.is_valid():
		world_manager.rd.free_rid(chunk.injection_buffer)
	if chunk.sim_uniform_set.is_valid():
		world_manager.rd.free_rid(chunk.sim_uniform_set)
	if chunk.rd_texture.is_valid():
		world_manager.rd.free_rid(chunk.rd_texture)
	if chunk.light_output_buffer.is_valid():
		world_manager.rd.free_rid(chunk.light_output_buffer)
	if chunk.light_pack_uniform_set.is_valid():
		world_manager.rd.free_rid(chunk.light_pack_uniform_set)


func rebuild_sim_uniform_sets(loaded: Array[Vector2i], unloaded: Array[Vector2i]) -> void:
	var chunks: Dictionary = world_manager.chunks
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
			build_sim_uniform_set(chunks[coord])


func build_sim_uniform_set(chunk: Chunk) -> void:
	var compute: ComputeDevice = world_manager.compute_device
	var chunks: Dictionary = world_manager.chunks

	if chunk.sim_uniform_set.is_valid():
		world_manager.rd.free_rid(chunk.sim_uniform_set)

	var uniforms: Array[RDUniform] = []

	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(chunk.rd_texture)
	uniforms.append(u0)

	for i in range(4):
		var n_coord: Vector2i = chunk.coord + NEIGHBOR_OFFSETS[i]
		var tex: RID = compute.dummy_texture
		if chunks.has(n_coord):
			tex = chunks[n_coord].rd_texture
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u.binding = i + 1
		u.add_id(tex)
		uniforms.append(u)

	var u5 := RDUniform.new()
	u5.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u5.binding = 5
	u5.add_id(chunk.injection_buffer)
	uniforms.append(u5)

	chunk.sim_uniform_set = world_manager.rd.uniform_set_create(uniforms, compute.sim_shader, 0)


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


func update_render_neighbors(loaded: Array[Vector2i], unloaded: Array[Vector2i]) -> void:
	var chunks: Dictionary = world_manager.chunks
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


func clear_all_chunks() -> void:
	var chunks: Dictionary = world_manager.chunks
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		free_chunk_resources(chunk)
	chunks.clear()


func generate_chunks_at(coords: Array[Vector2i], seed_val: int) -> Array[Vector2i]:
	var chunks: Dictionary = world_manager.chunks

	for us in world_manager._gen_uniform_sets_to_free:
		world_manager.rd.free_rid(us)
	world_manager._gen_uniform_sets_to_free.clear()

	var new_chunks: Array[Vector2i] = []
	for coord in coords:
		if not chunks.has(coord):
			create_chunk(coord)
			new_chunks.append(coord)

	if new_chunks.is_empty():
		return new_chunks

	world_manager._gen_uniform_sets_to_free = world_manager.compute_device.dispatch_generation(chunks, new_chunks, seed_val)

	rebuild_sim_uniform_sets(new_chunks, [])
	update_render_neighbors(new_chunks, [])

	return new_chunks
