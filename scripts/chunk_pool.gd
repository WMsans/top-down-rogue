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


func get_chunk(coord: Vector2i) -> Chunk:
	if inactive_chunks.has(coord):
		var chunk: Chunk = inactive_chunks[coord]
		inactive_chunks.erase(coord)
		chunk.coord = coord
		_reset_chunk(chunk)
		return chunk
	return _create_new_chunk(coord)


func return_chunk(coord: Vector2i, chunk: Chunk) -> void:
	if inactive_chunks.size() >= max_pool_size:
		_free_chunk(chunk)
		return
	chunk.mesh_instance.visible = false
	chunk.wall_mesh_instance.visible = false
	inactive_chunks[coord] = chunk


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