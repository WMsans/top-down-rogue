class_name ComputeDevice
extends RefCounted

const CHUNK_SIZE := 256
const WORKGROUP_SIZE := 8
const NUM_WORKGROUPS := CHUNK_SIZE / WORKGROUP_SIZE

var rd: RenderingDevice
var gen_shader: RID
var gen_pipeline: RID
var sim_shader: RID
var sim_pipeline: RID
var collider_shader: RID
var collider_pipeline: RID
var collider_storage_buffer: RID
var light_pack_shader: RID
var light_pack_pipeline: RID
var dummy_texture: RID
var render_shader: Shader
var material_textures: Texture2DArray

var gen_stamp_buffer: RID
var gen_stamp_uniform_set: RID
var gen_biome_buffer: RID
var gen_biome_uniform_set: RID
var gen_template_uniform_set: RID
var gen_template_array_rids: Dictionary = {}  # int size_class → RID

const STAMP_BUFFER_SIZE := 16 + 128 * 16   # 16-byte header + 128 vec4s
const BIOME_BUFFER_SIZE := 32 + 4 * 16     # 32-byte header + 4 pool vec4s

const LIGHT_CELL_COUNT := 16
const LIGHT_CELL_BYTES := 8
const LIGHT_OUTPUT_SIZE := LIGHT_CELL_COUNT * LIGHT_CELL_BYTES  # 128
const LIGHT_CELLS_X := 4
const LIGHT_CELLS_Y := 4

const PROBE_BUDGET := 64
const PROBE_INPUT_BUFFER_SIZE := PROBE_BUDGET * 8
const PROBE_OUTPUT_BUFFER_SIZE := PROBE_BUDGET * 4

var terrain_probe_shader: RID
var terrain_probe_pipeline: RID
var terrain_probe_input_buffer: RID
var terrain_probe_output_buffer: RID


func _init() -> void:
	rd = RenderingServer.get_rendering_device()


func init_shaders() -> void:
	var gen_file: RDShaderFile = load("res://shaders/compute/generation.glsl")
	var gen_spirv := gen_file.get_spirv()
	gen_shader = rd.shader_create_from_spirv(gen_spirv)
	gen_pipeline = rd.compute_pipeline_create(gen_shader)

	var sim_file: RDShaderFile = load("res://shaders/compute/simulation.glsl")
	var sim_spirv := sim_file.get_spirv()
	sim_shader = rd.shader_create_from_spirv(sim_spirv)
	sim_pipeline = rd.compute_pipeline_create(sim_shader)

	var collider_file: RDShaderFile = load("res://shaders/compute/collider.glsl")
	var collider_spirv := collider_file.get_spirv()
	collider_shader = rd.shader_create_from_spirv(collider_spirv)
	collider_pipeline = rd.compute_pipeline_create(collider_shader)

	var light_pack_file: RDShaderFile = load("res://shaders/compute/light_pack.glsl")
	var light_pack_spirv := light_pack_file.get_spirv()
	light_pack_shader = rd.shader_create_from_spirv(light_pack_spirv)
	light_pack_pipeline = rd.compute_pipeline_create(light_pack_shader)


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


func init_collider_storage_buffer() -> void:
	var max_segments := 4096
	var max_vertices := max_segments * 4
	var buffer_size := 4 + max_vertices * 4
	collider_storage_buffer = rd.storage_buffer_create(buffer_size)


func init_material_textures() -> void:
	var images: Array[Image] = []
	for m in MaterialRegistry.materials:
		if m.texture_path.is_empty():
			var ref_size: Vector2i = Vector2i(16, 16)
			if images.size() > 0:
				ref_size = images[0].get_size()
			# Encode in sRGB; the shader applies srgb_to_linear when sampling.
			var fill_color := Color.TRANSPARENT
			if m.tint_color.a > 0.0:
				fill_color = m.tint_color.linear_to_srgb()
				fill_color.a = 1.0
			images.append(TextureArrayBuilder.create_placeholder_image(ref_size, fill_color))
		else:
			images.append(Image.load_from_file(m.texture_path))
	material_textures = TextureArrayBuilder.build_from_images(images)


func init_gen_stamp_buffer() -> void:
	var zero := PackedByteArray()
	zero.resize(STAMP_BUFFER_SIZE)
	zero.fill(0)
	gen_stamp_buffer = rd.storage_buffer_create(STAMP_BUFFER_SIZE, zero)

	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = 0
	u.add_id(gen_stamp_buffer)
	gen_stamp_uniform_set = rd.uniform_set_create([u], gen_shader, 1)


func init_gen_biome_buffer() -> void:
	var zero := PackedByteArray()
	zero.resize(BIOME_BUFFER_SIZE)
	zero.fill(0)
	gen_biome_buffer = rd.storage_buffer_create(BIOME_BUFFER_SIZE, zero)

	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = 0
	u.add_id(gen_biome_buffer)
	gen_biome_uniform_set = rd.uniform_set_create([u], gen_shader, 2)


func init_terrain_probe() -> void:
	var f: RDShaderFile = load("res://shaders/compute/terrain_probe.glsl")
	terrain_probe_shader = rd.shader_create_from_spirv(f.get_spirv())
	terrain_probe_pipeline = rd.compute_pipeline_create(terrain_probe_shader)

	var zero_in := PackedByteArray()
	zero_in.resize(PROBE_INPUT_BUFFER_SIZE)
	zero_in.fill(0)
	terrain_probe_input_buffer = rd.storage_buffer_create(PROBE_INPUT_BUFFER_SIZE, zero_in)

	var zero_out := PackedByteArray()
	zero_out.resize(PROBE_OUTPUT_BUFFER_SIZE)
	zero_out.fill(0)
	terrain_probe_output_buffer = rd.storage_buffer_create(PROBE_OUTPUT_BUFFER_SIZE, zero_out)


# template_arrays: Dictionary[int size_class → Texture2DArray]
func bind_template_arrays(template_arrays: Dictionary) -> void:
	# Free previous RIDs if any
	for rid in gen_template_array_rids.values():
		if rid.is_valid():
			rd.free_rid(rid)
	gen_template_array_rids.clear()

	var uniforms: Array[RDUniform] = []
	var binding_for_size := {16: 0, 32: 1, 64: 2, 128: 3}

	for size_class in [16, 32, 64, 128]:
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u.binding = binding_for_size[size_class]
		var tex_rid := _texture_array_to_rid(template_arrays.get(size_class, null), size_class)
		gen_template_array_rids[size_class] = tex_rid
		# Need a sampler RID — use linear/nearest with no filter
		var sampler_state := RDSamplerState.new()
		sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		var sampler := rd.sampler_create(sampler_state)
		u.add_id(sampler)
		u.add_id(tex_rid)
		uniforms.append(u)

	if gen_template_uniform_set.is_valid():
		rd.free_rid(gen_template_uniform_set)
	gen_template_uniform_set = rd.uniform_set_create(uniforms, gen_shader, 3)


func _texture_array_to_rid(tex_array: Texture2DArray, size_class: int) -> RID:
	if tex_array == null:
		# Create a minimal placeholder array (1 layer)
		var tf := RDTextureFormat.new()
		tf.width = size_class
		tf.height = size_class
		tf.array_layers = 1
		tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
		tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
		tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		var blank := PackedByteArray()
		blank.resize(size_class * size_class * 4)
		blank.fill(0)
		return rd.texture_create(tf, RDTextureView.new(), [blank])

	var tf := RDTextureFormat.new()
	tf.width = size_class
	tf.height = size_class
	tf.array_layers = tex_array.get_layers()
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT

	var data: Array = []
	for i in range(tex_array.get_layers()):
		var img := tex_array.get_layer_data(i)
		data.append(img.get_data())
	return rd.texture_create(tf, RDTextureView.new(), data)


func upload_biome_buffer(biome: BiomeDef) -> void:
	var buf := PackedByteArray()
	buf.resize(BIOME_BUFFER_SIZE)
	buf.fill(0)
	buf.encode_float(0,  biome.cave_noise_scale)
	buf.encode_float(4,  biome.cave_threshold)
	buf.encode_float(8,  biome.ridge_weight)
	buf.encode_float(12, biome.ridge_scale)
	buf.encode_s32(16, biome.octaves)
	buf.encode_s32(20, biome.background_material)
	buf.encode_s32(24, biome.secret_ring_thickness)
	buf.encode_s32(28, 0)  # _pad
	var pool_count: int = min(biome.pool_materials.size(), 4)
	for i in range(pool_count):
		var p: PoolDef = biome.pool_materials[i]
		var off := 32 + i * 16
		buf.encode_float(off + 0,  float(p.material_id))
		buf.encode_float(off + 4,  p.noise_scale)
		buf.encode_float(off + 8,  p.noise_threshold)
		buf.encode_float(off + 12, float(p.seed_offset))
	rd.buffer_update(gen_biome_buffer, 0, BIOME_BUFFER_SIZE, buf)


func free_resources() -> void:
	if gen_stamp_buffer.is_valid():
		rd.free_rid(gen_stamp_buffer)
	if gen_biome_buffer.is_valid():
		rd.free_rid(gen_biome_buffer)
	if gen_stamp_uniform_set.is_valid():
		rd.free_rid(gen_stamp_uniform_set)
	if gen_biome_uniform_set.is_valid():
		rd.free_rid(gen_biome_uniform_set)
	if gen_template_uniform_set.is_valid():
		rd.free_rid(gen_template_uniform_set)
	for rid in gen_template_array_rids.values():
		if rid.is_valid():
			rd.free_rid(rid)
	gen_template_array_rids.clear()
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
	if light_pack_pipeline.is_valid():
		rd.free_rid(light_pack_pipeline)
	if light_pack_shader.is_valid():
		rd.free_rid(light_pack_shader)
	if terrain_probe_input_buffer.is_valid():
		rd.free_rid(terrain_probe_input_buffer)
	if terrain_probe_output_buffer.is_valid():
		rd.free_rid(terrain_probe_output_buffer)
	if terrain_probe_pipeline.is_valid():
		rd.free_rid(terrain_probe_pipeline)
	if terrain_probe_shader.is_valid():
		rd.free_rid(terrain_probe_shader)


func dispatch_generation(
	chunks: Dictionary,
	new_coords: Array[Vector2i],
	seed_val: int,
	stamp_bytes: PackedByteArray = PackedByteArray()
) -> Array[RID]:
	var created_uniform_sets: Array[RID] = []
	if new_coords.is_empty():
		return created_uniform_sets

	# Upload stamp buffer (or zero header if none)
	var upload := stamp_bytes
	if upload.size() < STAMP_BUFFER_SIZE:
		upload = stamp_bytes.duplicate()
		upload.resize(STAMP_BUFFER_SIZE)
	rd.buffer_update(gen_stamp_buffer, 0, STAMP_BUFFER_SIZE, upload)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, gen_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, gen_stamp_uniform_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, gen_biome_uniform_set, 2)
	if gen_template_uniform_set.is_valid():
		rd.compute_list_bind_uniform_set(compute_list, gen_template_uniform_set, 3)

	for coord in new_coords:
		var chunk: Chunk = chunks[coord]
		var gen_uniform := RDUniform.new()
		gen_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		gen_uniform.binding = 0
		gen_uniform.add_id(chunk.rd_texture)
		var uniform_set := rd.uniform_set_create([gen_uniform], gen_shader, 0)
		created_uniform_sets.append(uniform_set)
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

	return created_uniform_sets


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


func dispatch_light_pack(chunks: Dictionary, bucket_coords: Array) -> void:
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

		rd.compute_list_dispatch(compute_list, LIGHT_CELLS_X, LIGHT_CELLS_Y, 1)

	rd.compute_list_end()


func read_light_buffer(chunk: Chunk) -> PackedByteArray:
	if not chunk.light_output_buffer.is_valid():
		return PackedByteArray()
	return rd.buffer_get_data(chunk.light_output_buffer, 0, LIGHT_OUTPUT_SIZE)


## Decodes a 128-byte SSBO into an array of 16 dictionaries with position, energy, and color.
## Always returns 16 entries — cells with no glowing pixels get energy=0 and will fade out.
func decode_light_ssbo(data: PackedByteArray) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if data.size() < LIGHT_OUTPUT_SIZE:
		return result
	result.resize(LIGHT_CELL_COUNT)

	for cell_idx in range(LIGHT_CELL_COUNT):
		var off := cell_idx * LIGHT_CELL_BYTES
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


func dispatch_terrain_probe(chunks: Dictionary, batch: Array, packed_input: PackedByteArray) -> Array[RID]:
	if batch.is_empty():
		return []

	rd.buffer_update(terrain_probe_input_buffer, 0, PROBE_INPUT_BUFFER_SIZE, packed_input)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, terrain_probe_pipeline)

	var created_uniform_sets: Array[RID] = []
	for entry in batch:
		var chunk_coord: Vector2i = entry["chunk_coord"]
		var chunk: Chunk = chunks.get(chunk_coord, null)
		if chunk == null or not chunk.rd_texture.is_valid():
			continue
		var start: int = entry["start"]
		var count: int = entry["count"]
		if count <= 0:
			continue

		var u_tex := RDUniform.new()
		u_tex.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_tex.binding = 0
		u_tex.add_id(chunk.rd_texture)

		var u_in := RDUniform.new()
		u_in.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u_in.binding = 1
		u_in.add_id(terrain_probe_input_buffer)

		var u_out := RDUniform.new()
		u_out.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u_out.binding = 2
		u_out.add_id(terrain_probe_output_buffer)

		var us := rd.uniform_set_create([u_tex, u_in, u_out], terrain_probe_shader, 0)
		created_uniform_sets.append(us)

		rd.compute_list_bind_uniform_set(compute_list, us, 0)

		var push := PackedByteArray()
		push.resize(16)
		push.fill(0)
		push.encode_u32(0, start)
		push.encode_u32(4, count)
		rd.compute_list_set_push_constant(compute_list, push, push.size())

		var groups: int = int(ceil(float(count) / 8.0))
		rd.compute_list_dispatch(compute_list, groups, 1, 1)

	rd.compute_list_end()

	return created_uniform_sets


func read_terrain_probe(byte_count: int) -> PackedByteArray:
	if byte_count <= 0:
		return PackedByteArray()
	return rd.buffer_get_data(terrain_probe_output_buffer, 0, byte_count)
