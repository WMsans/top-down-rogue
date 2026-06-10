class_name ComputeDevice
extends RefCounted

const CHUNK_SIZE := 256
const WORKGROUP_SIZE := 8
const NUM_WORKGROUPS := CHUNK_SIZE / WORKGROUP_SIZE

var world_manager = null
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
var light_output_buffers: Array[RID] = [RID(), RID()]
var light_write_index: int = 0
var light_first_frame: bool = true
# Manifest per buffer: flat PackedInt32Array of [chunk_x, chunk_y, slice_idx, ...]
var light_dispatch_manifests: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
var collider_output_buffers: Array[RID] = [RID(), RID()]
var collider_write_index: int = 0
var collider_first_frame: bool = true
# Manifest entries are [coord.x, coord.y, slot_index] triples; one per dispatched chunk.
var collider_dispatch_manifests: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
var passability_output_buffers: Array[RID] = [RID(), RID()]
var solidity_flag_buffer: RID = RID()
var solidity_dispatch_manifest: PackedInt32Array = PackedInt32Array()
var dummy_texture: RID
var render_shader: Shader
var material_textures: Texture2DArray

var gen_stamp_buffer: RID
var gen_stamp_uniform_set: RID
var gen_biome_buffer: RID
var gen_biome_uniform_set: RID
var gen_template_uniform_set: RID
var gen_template_array_rids: Dictionary = {}  # int size_class → RID
var gen_cavern_buffer: RID
var gen_cavern_uniform_set: RID

const STAMP_BUFFER_SIZE := 16 + 128 * 16   # 16-byte header + 128 vec4s
const BIOME_BUFFER_SIZE := 32 + 4 * 16     # 32-byte header + 4 pool vec4s
const CAVERN_BUFFER_SIZE := 16 + 64 * 2 * 16   # header (4 ints) + 64 caverns x 2 vec4s

const LIGHT_CELL_COUNT := 16
const LIGHT_CELL_BYTES := 12
const LIGHT_OUTPUT_SIZE := LIGHT_CELL_COUNT * LIGHT_CELL_BYTES  # 192
const LIGHT_CELLS_X := 4
const LIGHT_CELLS_Y := 4

const LIGHT_MAX_ACTIVE_CHUNKS := 32
const LIGHT_SHARED_BUFFER_SIZE := LIGHT_MAX_ACTIVE_CHUNKS * LIGHT_OUTPUT_SIZE  # 32 * 192 = 6144 bytes

const COLLIDER_MAX_DISPATCH_PER_FRAME := 4
const COLLIDER_MAX_SEGMENTS_PER_SLOT := 4096
const COLLIDER_SLOT_STRIDE_BYTES := 4 + COLLIDER_MAX_SEGMENTS_PER_SLOT * 4 * 4
const COLLIDER_COALESCED_BUFFER_SIZE := COLLIDER_MAX_DISPATCH_PER_FRAME * COLLIDER_SLOT_STRIDE_BYTES

const PASSABILITY_CELLS_PER_SIDE := 32          # 256px chunk / 8px cell
const PASSABILITY_SLOT_U32 := 1024              # 32 * 32, one uint per cell
const PASSABILITY_SLOT_BYTES := 4096            # 1024 * 4
const PASSABILITY_BUFFER_SIZE := COLLIDER_MAX_DISPATCH_PER_FRAME * PASSABILITY_SLOT_BYTES  # 16 KB

const SIM_MAX_CHUNKS := 64
const SIM_FLAG_SLOT_BYTES := 4
const SIM_FLAG_BUFFER_SIZE := SIM_MAX_CHUNKS * SIM_FLAG_SLOT_BYTES

const PROBE_BUDGET := 256
const PROBE_INPUT_BUFFER_SIZE := PROBE_BUDGET * 8
const PROBE_OUTPUT_BUFFER_SIZE := PROBE_BUDGET * 4

var terrain_probe_shader: RID
var terrain_probe_pipeline: RID
var terrain_probe_input_buffers: Array[RID] = [RID(), RID()]
var terrain_probe_output_buffers: Array[RID] = [RID(), RID()]
var terrain_probe_write_index: int = 0
var terrain_probe_first_frame: bool = true

const MELEE_HIT_RING := 3
const MELEE_HIT_CAPACITY := 64
const MELEE_HIT_HEADER_BYTES := 16
const MELEE_HIT_ENTRY_BYTES := 16
const MELEE_HIT_BUFFER_SIZE := MELEE_HIT_HEADER_BYTES + MELEE_HIT_CAPACITY * MELEE_HIT_ENTRY_BYTES

var melee_arc_shader: RID
var melee_arc_pipeline: RID
var melee_hit_buffers: Array[RID] = [RID(), RID(), RID()]
var melee_hit_write_index: int = 0


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


func init_collider_storage_buffer() -> void:
	var zero := PackedByteArray()
	zero.resize(COLLIDER_COALESCED_BUFFER_SIZE)
	zero.fill(0)
	for i in range(2):
		collider_output_buffers[i] = rd.storage_buffer_create(COLLIDER_COALESCED_BUFFER_SIZE)
		rd.buffer_update(collider_output_buffers[i], 0, COLLIDER_COALESCED_BUFFER_SIZE, zero)
	collider_write_index = 0
	collider_first_frame = true
	collider_dispatch_manifests[0] = PackedInt32Array()
	collider_dispatch_manifests[1] = PackedInt32Array()
	# Legacy single buffer retained for any in-flight CPU fallback path; keep as zero RID.
	collider_storage_buffer = RID()


func init_solidity_flag_buffer() -> void:
	var zero := PackedByteArray()
	zero.resize(SIM_FLAG_BUFFER_SIZE)
	zero.fill(0)
	solidity_flag_buffer = rd.storage_buffer_create(SIM_FLAG_BUFFER_SIZE)
	rd.buffer_update(solidity_flag_buffer, 0, SIM_FLAG_BUFFER_SIZE, zero)
	solidity_dispatch_manifest = PackedInt32Array()


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


func init_gen_cavern_buffer() -> void:
	var zero := PackedByteArray()
	zero.resize(CAVERN_BUFFER_SIZE)
	zero.fill(0)
	gen_cavern_buffer = rd.storage_buffer_create(CAVERN_BUFFER_SIZE, zero)

	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = 0
	u.add_id(gen_cavern_buffer)
	gen_cavern_uniform_set = rd.uniform_set_create([u], gen_shader, 4)


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
	var zero_out := PackedByteArray()
	zero_out.resize(PROBE_OUTPUT_BUFFER_SIZE)
	zero_out.fill(0)
	for i in range(2):
		terrain_probe_input_buffers[i] = rd.storage_buffer_create(PROBE_INPUT_BUFFER_SIZE, zero_in)
		terrain_probe_output_buffers[i] = rd.storage_buffer_create(PROBE_OUTPUT_BUFFER_SIZE, zero_out)


func init_melee_arc() -> void:
	var f: RDShaderFile = load("res://shaders/compute/melee_arc.glsl")
	melee_arc_shader = rd.shader_create_from_spirv(f.get_spirv())
	melee_arc_pipeline = rd.compute_pipeline_create(melee_arc_shader)
	var zero := PackedByteArray()
	zero.resize(MELEE_HIT_BUFFER_SIZE)
	zero.fill(0)
	for i in range(MELEE_HIT_RING):
		melee_hit_buffers[i] = rd.storage_buffer_create(MELEE_HIT_BUFFER_SIZE, zero)


# template_arrays: Dictionary[int size_class → Texture2DArray]
func bind_template_arrays(template_arrays: Dictionary) -> void:
	if gen_template_uniform_set.is_valid():
		rd.free_rid(gen_template_uniform_set)
		gen_template_uniform_set = RID()
	for rid in gen_template_array_rids.values():
		if rid.is_valid():
			rd.free_rid(rid)
	gen_template_array_rids.clear()

	var uniforms: Array[RDUniform] = []
	var binding_for_size := {16: 0, 32: 1, 64: 2, 128: 3, 256: 4}

	for size_class in [16, 32, 64, 128, 256]:
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u.binding = binding_for_size[size_class]
		var tex_rid := _texture_array_to_rid(template_arrays.get(size_class, null), size_class)
		gen_template_array_rids[size_class] = tex_rid
		var sampler_state := RDSamplerState.new()
		sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		var sampler := rd.sampler_create(sampler_state)
		u.add_id(sampler)
		u.add_id(tex_rid)
		uniforms.append(u)

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


func dispatch_melee_arc(chunks: Dictionary, affected_chunk_coords: Array[Vector2i],
		origin: Vector2, direction: Vector2,
		radius: float, inner_radius: float, arc_half_angle: float,
		push_speed: float, damage: float, target_mask: int) -> Array[RID]:
	if affected_chunk_coords.is_empty():
		return []

	var zero_header := PackedByteArray()
	zero_header.resize(MELEE_HIT_HEADER_BYTES)
	zero_header.fill(0)
	rd.buffer_update(melee_hit_buffers[melee_hit_write_index], 0, MELEE_HIT_HEADER_BYTES, zero_header)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, melee_arc_pipeline)

	var created: Array[RID] = []
	for coord in affected_chunk_coords:
		var chunk: Chunk = chunks.get(coord, null)
		if chunk == null or not chunk.rd_texture.is_valid():
			continue

		var u_tex := RDUniform.new()
		u_tex.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_tex.binding = 0
		u_tex.add_id(chunk.rd_texture)

		var u_hits := RDUniform.new()
		u_hits.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u_hits.binding = 1
		u_hits.add_id(melee_hit_buffers[melee_hit_write_index])

		var us := rd.uniform_set_create([u_tex, u_hits], melee_arc_shader, 0)
		created.append(us)
		rd.compute_list_bind_uniform_set(compute_list, us, 0)

		var origin_chunk := coord * CHUNK_SIZE
		var push := PackedByteArray()
		push.resize(64)
		push.fill(0)
		push.encode_s32(0, origin_chunk.x)
		push.encode_s32(4, origin_chunk.y)
		push.encode_float(8, origin.x)
		push.encode_float(12, origin.y)
		push.encode_float(16, direction.x)
		push.encode_float(20, direction.y)
		push.encode_float(24, radius)
		push.encode_float(28, inner_radius)
		push.encode_float(32, arc_half_angle)
		push.encode_float(36, push_speed)
		push.encode_float(40, damage)
		push.encode_u32(44, target_mask)
		push.encode_u32(48, MELEE_HIT_CAPACITY)
		rd.compute_list_set_push_constant(compute_list, push, push.size())

		rd.compute_list_dispatch(compute_list, NUM_WORKGROUPS, NUM_WORKGROUPS, 1)

	rd.compute_list_end()

	if world_manager:
		for coord in affected_chunk_coords:
			world_manager.mark_terrain_dirty(coord)

	return created


func drain_melee_hits() -> Array:
	var read_index := (melee_hit_write_index + 1) % MELEE_HIT_RING
	var raw := rd.buffer_get_data(melee_hit_buffers[read_index], 0, MELEE_HIT_BUFFER_SIZE)
	if raw.size() < MELEE_HIT_HEADER_BYTES:
		return []
	var count: int = int(raw.decode_u32(0))
	var capped: int = min(count, MELEE_HIT_CAPACITY)
	var result: Array = []
	for i in range(capped):
		var off := MELEE_HIT_HEADER_BYTES + i * MELEE_HIT_ENTRY_BYTES
		result.append({
			"world_pos": Vector2(float(raw.decode_s32(off)), float(raw.decode_s32(off + 4))),
			"material_id": int(raw.decode_u32(off + 8)),
			"scale": raw.decode_float(off + 12),
		})
	# Clear the count so this buffer isn't replayed when the ring wraps back to it.
	if count > 0:
		var zero_header := PackedByteArray()
		zero_header.resize(MELEE_HIT_HEADER_BYTES)
		zero_header.fill(0)
		rd.buffer_update(melee_hit_buffers[read_index], 0, MELEE_HIT_HEADER_BYTES, zero_header)
	melee_hit_write_index = (melee_hit_write_index + 1) % MELEE_HIT_RING
	return result


func free_resources() -> void:
	if gen_stamp_uniform_set.is_valid():
		rd.free_rid(gen_stamp_uniform_set)
		gen_stamp_uniform_set = RID()
	if gen_biome_uniform_set.is_valid():
		rd.free_rid(gen_biome_uniform_set)
		gen_biome_uniform_set = RID()
	if gen_template_uniform_set.is_valid():
		rd.free_rid(gen_template_uniform_set)
		gen_template_uniform_set = RID()
	for rid in gen_template_array_rids.values():
		if rid.is_valid():
			rd.free_rid(rid)
	gen_template_array_rids.clear()
	if gen_stamp_buffer.is_valid():
		rd.free_rid(gen_stamp_buffer)
		gen_stamp_buffer = RID()
	if gen_cavern_buffer.is_valid():
		rd.free_rid(gen_cavern_buffer)
		gen_cavern_buffer = RID()
	if gen_cavern_uniform_set.is_valid():
		rd.free_rid(gen_cavern_uniform_set)
		gen_cavern_uniform_set = RID()
	if gen_biome_buffer.is_valid():
		rd.free_rid(gen_biome_buffer)
		gen_biome_buffer = RID()
	if dummy_texture.is_valid():
		rd.free_rid(dummy_texture)
		dummy_texture = RID()
	if collider_storage_buffer.is_valid():
		rd.free_rid(collider_storage_buffer)
		collider_storage_buffer = RID()
	for i in range(2):
		if collider_output_buffers[i].is_valid():
			rd.free_rid(collider_output_buffers[i])
			collider_output_buffers[i] = RID()
	if solidity_flag_buffer.is_valid():
		rd.free_rid(solidity_flag_buffer)
		solidity_flag_buffer = RID()
	if gen_pipeline.is_valid():
		rd.free_rid(gen_pipeline)
		gen_pipeline = RID()
	if gen_shader.is_valid():
		rd.free_rid(gen_shader)
		gen_shader = RID()
	if sim_pipeline.is_valid():
		rd.free_rid(sim_pipeline)
		sim_pipeline = RID()
	if sim_shader.is_valid():
		rd.free_rid(sim_shader)
		sim_shader = RID()
	if collider_pipeline.is_valid():
		rd.free_rid(collider_pipeline)
		collider_pipeline = RID()
	if collider_shader.is_valid():
		rd.free_rid(collider_shader)
		collider_shader = RID()
	if light_pack_pipeline.is_valid():
		rd.free_rid(light_pack_pipeline)
		light_pack_pipeline = RID()
	if light_pack_shader.is_valid():
		rd.free_rid(light_pack_shader)
		light_pack_shader = RID()
	for i in range(MELEE_HIT_RING):
		if melee_hit_buffers[i].is_valid():
			rd.free_rid(melee_hit_buffers[i])
			melee_hit_buffers[i] = RID()
	if melee_arc_pipeline.is_valid():
		rd.free_rid(melee_arc_pipeline)
		melee_arc_pipeline = RID()
	if melee_arc_shader.is_valid():
		rd.free_rid(melee_arc_shader)
		melee_arc_shader = RID()
	for i in range(2):
		if terrain_probe_input_buffers[i].is_valid():
			rd.free_rid(terrain_probe_input_buffers[i])
			terrain_probe_input_buffers[i] = RID()
		if terrain_probe_output_buffers[i].is_valid():
			rd.free_rid(terrain_probe_output_buffers[i])
			terrain_probe_output_buffers[i] = RID()
	for i in range(2):
		if light_output_buffers[i].is_valid():
			rd.free_rid(light_output_buffers[i])
			light_output_buffers[i] = RID()
	if terrain_probe_pipeline.is_valid():
		rd.free_rid(terrain_probe_pipeline)
		terrain_probe_pipeline = RID()
	if terrain_probe_shader.is_valid():
		rd.free_rid(terrain_probe_shader)
		terrain_probe_shader = RID()


func dispatch_generation(
	chunks: Dictionary,
	new_coords: Array[Vector2i],
	seed_val: int,
	stamp_bytes: PackedByteArray = PackedByteArray(),
	cavern_bytes: PackedByteArray = PackedByteArray()
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

	var cav_upload := cavern_bytes
	if cav_upload.size() < CAVERN_BUFFER_SIZE:
		cav_upload = cavern_bytes.duplicate()
		cav_upload.resize(CAVERN_BUFFER_SIZE)
	rd.buffer_update(gen_cavern_buffer, 0, CAVERN_BUFFER_SIZE, cav_upload)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, gen_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, gen_stamp_uniform_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, gen_biome_uniform_set, 2)
	if gen_template_uniform_set.is_valid():
		rd.compute_list_bind_uniform_set(compute_list, gen_template_uniform_set, 3)
	if gen_cavern_uniform_set.is_valid():
		rd.compute_list_bind_uniform_set(compute_list, gen_cavern_uniform_set, 4)

	for coord in new_coords:
		var chunk: Chunk = chunks[coord]
		var gen_uniform := RDUniform.new()
		gen_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		gen_uniform.binding = 0
		gen_uniform.add_id(chunk.rd_texture)
		var uniform_set := rd.uniform_set_create([gen_uniform], gen_shader, 0)
		created_uniform_sets.append(uniform_set)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)

		var flag_uniform := RDUniform.new()
		flag_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		flag_uniform.binding = 0
		flag_uniform.add_id(chunk.rd_flag_texture)
		var flag_uniform_set := rd.uniform_set_create([flag_uniform], gen_shader, 5)
		created_uniform_sets.append(flag_uniform_set)
		rd.compute_list_bind_uniform_set(compute_list, flag_uniform_set, 5)

		var push_data := PackedByteArray()
		push_data.resize(16)
		push_data.encode_s32(0, coord.x)
		push_data.encode_s32(4, coord.y)
		push_data.encode_u32(8, seed_val)
		push_data.encode_u32(12, 0)
		rd.compute_list_set_push_constant(compute_list, push_data, push_data.size())

		rd.compute_list_dispatch(compute_list, NUM_WORKGROUPS, NUM_WORKGROUPS, 1)
	rd.compute_list_end()

	if world_manager:
		for coord in new_coords:
			world_manager.mark_terrain_dirty(coord)

	return created_uniform_sets


func dispatch_simulation(chunks: Dictionary, shadow_grid: Node) -> void:
	if chunks.is_empty():
		return

	var zero := PackedByteArray()
	zero.resize(SIM_FLAG_BUFFER_SIZE)
	zero.fill(0)
	rd.buffer_update(solidity_flag_buffer, 0, SIM_FLAG_BUFFER_SIZE, zero)

	var flag_manifest := PackedInt32Array()
	var slot_of: Dictionary = {}
	var next_slot := 0
	for coord in chunks:
		if next_slot >= SIM_MAX_CHUNKS:
			push_warning("dispatch_simulation: loaded chunks exceed SIM_MAX_CHUNKS; solidity flags dropped for extras")
			break
		slot_of[coord] = next_slot
		flag_manifest.append(coord.x)
		flag_manifest.append(coord.y)
		flag_manifest.append(next_slot)
		next_slot += 1
	solidity_dispatch_manifest = flag_manifest

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
		push_even.encode_s32(8, slot_of.get(coord, 0))
		rd.compute_list_bind_uniform_set(compute_list, chunk.sim_uniform_set, 0)
		rd.compute_list_set_push_constant(compute_list, push_even, push_even.size())
		rd.compute_list_dispatch(compute_list, NUM_WORKGROUPS, NUM_WORKGROUPS, 1)

	rd.compute_list_add_barrier(compute_list)

	rd.compute_list_bind_compute_pipeline(compute_list, sim_pipeline)
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		if not chunk.sim_uniform_set.is_valid():
			continue
		push_odd.encode_s32(8, slot_of.get(coord, 0))
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


func dispatch_collider_pack(chunks: Dictionary, coords: Array) -> void:
	var manifest := PackedInt32Array()

	if coords.is_empty():
		collider_dispatch_manifests[collider_write_index] = manifest
		return

	# Zero all slot headers in the write buffer (one u32 per slot).
	var header_clear := PackedByteArray()
	header_clear.resize(4)
	header_clear.encode_u32(0, 0)
	for slot in range(COLLIDER_MAX_DISPATCH_PER_FRAME):
		var slot_offset := slot * COLLIDER_SLOT_STRIDE_BYTES
		rd.buffer_update(collider_output_buffers[collider_write_index], slot_offset, 4, header_clear)

	var push_data := PackedByteArray()
	push_data.resize(16)
	push_data.fill(0)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, collider_pipeline)

	var slot_idx := 0
	for coord in coords:
		if slot_idx >= COLLIDER_MAX_DISPATCH_PER_FRAME:
			push_warning("collider_pack: dispatch list exceeds COLLIDER_MAX_DISPATCH_PER_FRAME, dropping extras")
			break
		var chunk: Chunk = chunks.get(coord, null)
		if chunk == null:
			continue
		var us: RID = chunk.collider_uniform_sets[collider_write_index]
		if not us.is_valid():
			continue

		rd.compute_list_bind_uniform_set(compute_list, us, 0)
		push_data.encode_u32(0, slot_idx)
		rd.compute_list_set_push_constant(compute_list, push_data, push_data.size())
		rd.compute_list_dispatch(compute_list, 16, 16, 1)

		manifest.append(coord.x)
		manifest.append(coord.y)
		manifest.append(slot_idx)
		slot_idx += 1

	rd.compute_list_end()

	collider_dispatch_manifests[collider_write_index] = manifest


func read_collider_buffer_coalesced() -> Dictionary:
	if collider_first_frame:
		collider_first_frame = false
		collider_write_index = 1 - collider_write_index
		return {}

	var read_index := 1 - collider_write_index
	var manifest: PackedInt32Array = collider_dispatch_manifests[read_index]
	if manifest.is_empty():
		collider_write_index = 1 - collider_write_index
		return {}

	var entry_count := manifest.size() / 3
	var bytes_needed := entry_count * COLLIDER_SLOT_STRIDE_BYTES
	if entry_count == COLLIDER_MAX_DISPATCH_PER_FRAME:
		bytes_needed = COLLIDER_COALESCED_BUFFER_SIZE
	var data: PackedByteArray = rd.buffer_get_data(collider_output_buffers[read_index], 0, bytes_needed)

	collider_write_index = 1 - collider_write_index

	var result: Dictionary = {}
	for i in range(entry_count):
		var cx := manifest[i * 3]
		var cy := manifest[i * 3 + 1]
		var slot := manifest[i * 3 + 2]
		var coord := Vector2i(cx, cy)
		result[coord] = decode_collider_slice(data, slot)
	return result


func decode_collider_slice(data: PackedByteArray, slot: int) -> PackedVector2Array:
	var segments := PackedVector2Array()
	var slot_offset := slot * COLLIDER_SLOT_STRIDE_BYTES
	if slot_offset + 4 > data.size():
		return segments
	var count: int = data.decode_u32(slot_offset)
	if count == 0:
		return segments
	count = mini(count, COLLIDER_MAX_SEGMENTS_PER_SLOT)
	var seg_base := slot_offset + 4
	for i in range(count):
		var off := seg_base + i * 16
		if off + 16 > data.size():
			break
		var x1 := float(data.decode_u32(off))
		var y1 := float(data.decode_u32(off + 4))
		var x2 := float(data.decode_u32(off + 8))
		var y2 := float(data.decode_u32(off + 12))
		segments.append(Vector2(x1, y1))
		segments.append(Vector2(x2, y2))
	return segments


static func decode_passability_slice(data: PackedByteArray, slot: int) -> PackedByteArray:
	var tile := PackedByteArray()
	tile.resize(PASSABILITY_SLOT_U32)
	tile.fill(0)
	var slot_offset := slot * PASSABILITY_SLOT_BYTES
	if slot_offset + PASSABILITY_SLOT_BYTES > data.size():
		return tile
	for i in range(PASSABILITY_SLOT_U32):
		tile[i] = 1 if data.decode_u32(slot_offset + i * 4) != 0 else 0
	return tile


static func decode_solidity_flags(data: PackedByteArray, manifest: PackedInt32Array, loaded: Dictionary) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	var entry_count := manifest.size() / 3
	for i in range(entry_count):
		var slot: int = manifest[i * 3 + 2]
		var off := slot * SIM_FLAG_SLOT_BYTES
		if off + 4 > data.size():
			continue
		if data.decode_u32(off) == 0:
			continue
		var coord := Vector2i(manifest[i * 3], manifest[i * 3 + 1])
		if not loaded.has(coord):
			continue
		changed.append(coord)
	return changed


func read_solidity_flags(chunks: Dictionary) -> Array[Vector2i]:
	if solidity_dispatch_manifest.is_empty():
		return []
	var data := rd.buffer_get_data(solidity_flag_buffer, 0, SIM_FLAG_BUFFER_SIZE)
	return decode_solidity_flags(data, solidity_dispatch_manifest, chunks)


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


## Decodes the light SSBO into an array of 16 dictionaries with position, energy, color, and hazard.
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
			energy = coverage * (avg_glow / 20.0)  # MAX_GLOW = 20.0
			pos = Vector2(float(avg_x), float(avg_y))

		result[cell_idx] = {
			"position": pos,
			"energy": energy,
			"color": Color(1.0, 0.5, 0.15, 1.0),
			"hazard": int(hazard_mask),
		}

	return result


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


func dispatch_terrain_probe(chunks: Dictionary, batch: Array, packed_input: PackedByteArray) -> Array[RID]:
	if batch.is_empty():
		return []

	rd.buffer_update(terrain_probe_input_buffers[terrain_probe_write_index], 0, PROBE_INPUT_BUFFER_SIZE, packed_input)

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
		u_in.add_id(terrain_probe_input_buffers[terrain_probe_write_index])

		var u_out := RDUniform.new()
		u_out.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u_out.binding = 2
		u_out.add_id(terrain_probe_output_buffers[terrain_probe_write_index])

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
	if terrain_probe_first_frame:
		terrain_probe_first_frame = false
		return PackedByteArray()
	if byte_count <= 0:
		return PackedByteArray()
	var read_index := terrain_probe_write_index
	var result := rd.buffer_get_data(terrain_probe_output_buffers[read_index], 0, byte_count)
	terrain_probe_write_index = 1 - terrain_probe_write_index
	return result
