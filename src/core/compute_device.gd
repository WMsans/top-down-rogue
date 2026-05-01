class_name ComputeDevice
extends RefCounted

const CHUNK_SIZE := 256
const WORKGROUP_SIZE := 8
const NUM_WORKGROUPS := CHUNK_SIZE / WORKGROUP_SIZE

var rd: RenderingDevice
var sim_shader: RID
var sim_pipeline: RID
var dummy_texture: RID
var render_shader: Shader
var material_textures: Texture2DArray


func _init() -> void:
	rd = RenderingServer.get_rendering_device()


func init_shaders() -> void:
	var sim_file: RDShaderFile = load("res://shaders/compute/simulation.glsl")
	var sim_spirv := sim_file.get_spirv()
	sim_shader = rd.shader_create_from_spirv(sim_spirv)
	sim_pipeline = rd.compute_pipeline_create(sim_shader)


func init_dummy_texture() -> void:
	var tf := RDTextureFormat.new()
	tf.width = CHUNK_SIZE
	tf.height = CHUNK_SIZE
	tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	var data := PackedByteArray()
	data.resize(CHUNK_SIZE * CHUNK_SIZE * 4)
	data.fill(0)
	dummy_texture = rd.texture_create(tf, RDTextureView.new(), [data])


func init_material_textures() -> void:
	var images: Array[Image] = []
	for m in MaterialTable.materials:
		if m.texture_path.is_empty():
			var ref_size: Vector2i = Vector2i(16, 16)
			if images.size() > 0:
				ref_size = images[0].get_size()
			var fill_color := Color.TRANSPARENT
			if m.tint_color.a > 0.0:
				fill_color = m.tint_color.linear_to_srgb()
				fill_color.a = 1.0
			images.append(TextureArrayBuilder.create_placeholder_image(ref_size, fill_color))
		else:
			images.append(Image.load_from_file(m.texture_path))
	material_textures = TextureArrayBuilder.build_from_images(images)


func free_resources() -> void:
	if dummy_texture.is_valid():
		rd.free_rid(dummy_texture)
	if sim_pipeline.is_valid():
		rd.free_rid(sim_pipeline)
	if sim_shader.is_valid():
		rd.free_rid(sim_shader)


func dispatch_simulation(chunks: Dictionary, shadow_grid: Node) -> void:
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

	rd.compute_list_bind_compute_pipeline(compute_list, sim_pipeline)
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		if not chunk.sim_uniform_set.is_valid():
			continue
		rd.compute_list_bind_uniform_set(compute_list, chunk.sim_uniform_set, 0)
		rd.compute_list_set_push_constant(compute_list, push_even, push_even.size())
		rd.compute_list_dispatch(compute_list, NUM_WORKGROUPS, NUM_WORKGROUPS, 1)

	rd.compute_list_add_barrier(compute_list)

	rd.compute_list_bind_compute_pipeline(compute_list, sim_pipeline)
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		if not chunk.sim_uniform_set.is_valid():
			continue
		rd.compute_list_bind_uniform_set(compute_list, chunk.sim_uniform_set, 0)
		rd.compute_list_set_push_constant(compute_list, push_odd, push_odd.size())
		rd.compute_list_dispatch(compute_list, NUM_WORKGROUPS, NUM_WORKGROUPS, 1)

	rd.compute_list_end()

	if shadow_grid:
		var grid_rect: Rect2i = shadow_grid.get_world_rect()
		for coord in chunks:
			var chunk_rect := Rect2i(coord * CHUNK_SIZE, Vector2i(CHUNK_SIZE, CHUNK_SIZE))
			if grid_rect.intersects(chunk_rect):
				shadow_grid.mark_dirty()
				break
