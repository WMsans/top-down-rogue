@tool
extends Node2D

const CHUNK_SIZE := 256
const WORKGROUP_SIZE := 8
const NUM_WORKGROUPS := CHUNK_SIZE / WORKGROUP_SIZE  # 32

const MAT_AIR := 0
const MAT_WOOD := 1
const MAT_STONE := 2
const MAX_TEMPERATURE := 255

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
var material_textures: Texture2DArray

@onready var chunk_container: Node2D = $ChunkContainer
@onready var camera: Camera2D = get_parent().get_node("Camera2D")


func _ready() -> void:
	rd = RenderingServer.get_rendering_device()
	_init_shaders()
	_init_dummy_texture()
	render_shader = preload("res://shaders/render_chunk.gdshader")
	_init_material_textures()


func _init_material_textures() -> void:
	var plank_img := Image.load_from_file("res://textures/PixelTextures/plank.png")
	var stone_img := Image.load_from_file("res://textures/PixelTextures/stone.png")
	var placeholder := TextureArrayBuilder.create_placeholder_image(plank_img.get_size(), Color.TRANSPARENT)

	var images: Array[Image] = [placeholder, plank_img, stone_img]
	material_textures = TextureArrayBuilder.build_from_images(images)


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
	if Engine.is_editor_hint():
		return
	_update_chunks()
	_run_simulation()


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
	mat.set_shader_parameter("material_textures", material_textures)
	mat.set_shader_parameter("wall_height", 16)
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

	chunk.sim_uniform_set = rd.uniform_set_create(uniforms, sim_shader, 0)


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
			var material := data[idx]
			if material != MAT_WOOD:
				continue
			data[idx + 2] = MAX_TEMPERATURE
		rd.texture_update(chunk.rd_texture, 0, data)


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
