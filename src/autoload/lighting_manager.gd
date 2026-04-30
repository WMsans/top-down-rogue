@tool
extends Node

@export var enabled: bool = true
@export var tick_interval: int = 4
@export var intensity_k: float = 1.0
@export var blur_radius_cells: int = 5
@export var ambient: Color = Color(0.05, 0.05, 0.05)

const CELL_SIZE: int = 4
const CHUNK_SIZE: int = 256
const TILE_SIZE: int = CHUNK_SIZE / CELL_SIZE

var rd: RenderingDevice
var _frame_counter: int = 0

var emission_shader: RID
var emission_pipeline: RID
var compose_shader: RID
var compose_pipeline: RID
var blur_shader: RID
var blur_pipeline: RID

var main_grid_2d: Texture2DRD

# Vector2i chunk_coord -> RID emission_tile_tex (RGBA16F, TILE_SIZE x TILE_SIZE)
var emission_tiles: Dictionary = {}

var main_grid_tex: RID
var scratch_grid_tex: RID
var loaded_aabb: Rect2i = Rect2i()
var grid_size: Vector2i = Vector2i.ZERO

const MAX_GRID_CELLS: int = 1024 * 1024


func _ready() -> void:
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		push_error("LightingManager: no RenderingDevice; disabling")
		enabled = false
		return
	_init_pipelines()


func _init_pipelines() -> void:
	var emission_file := load("res://shaders/compute/emission_reduce.glsl") as RDShaderFile
	emission_shader = rd.shader_create_from_spirv(emission_file.get_spirv())
	emission_pipeline = rd.compute_pipeline_create(emission_shader)

	var compose_file := load("res://shaders/compute/light_compose.glsl") as RDShaderFile
	compose_shader = rd.shader_create_from_spirv(compose_file.get_spirv())
	compose_pipeline = rd.compute_pipeline_create(compose_shader)

	var blur_file := load("res://shaders/compute/light_blur.glsl") as RDShaderFile
	blur_shader = rd.shader_create_from_spirv(blur_file.get_spirv())
	blur_pipeline = rd.compute_pipeline_create(blur_shader)


func _exit_tree() -> void:
	if rd == null:
		return
	_free_grid_textures()
	for tex in emission_tiles.values():
		if tex.is_valid():
			rd.free_rid(tex)
	emission_tiles.clear()
	if emission_pipeline.is_valid():
		rd.free_rid(emission_pipeline)
	if emission_shader.is_valid():
		rd.free_rid(emission_shader)
	if compose_pipeline.is_valid():
		rd.free_rid(compose_pipeline)
	if compose_shader.is_valid():
		rd.free_rid(compose_shader)
	if blur_pipeline.is_valid():
		rd.free_rid(blur_pipeline)
	if blur_shader.is_valid():
		rd.free_rid(blur_shader)


func _compute_loaded_aabb() -> Rect2i:
	if emission_tiles.is_empty():
		return Rect2i()
	var any_set := false
	var min_c := Vector2i.ZERO
	var max_c := Vector2i.ZERO
	for coord_v in emission_tiles.keys():
		var coord: Vector2i = coord_v
		if not any_set:
			min_c = coord
			max_c = coord
			any_set = true
		else:
			min_c.x = min(min_c.x, coord.x)
			min_c.y = min(min_c.y, coord.y)
			max_c.x = max(max_c.x, coord.x)
			max_c.y = max(max_c.y, coord.y)
	return Rect2i(min_c, max_c - min_c + Vector2i.ONE)


func _ensure_grid_textures() -> bool:
	var aabb := _compute_loaded_aabb()
	if aabb.size == Vector2i.ZERO:
		return false
	if aabb == loaded_aabb and main_grid_tex.is_valid():
		return true
	_free_grid_textures()
	loaded_aabb = aabb
	grid_size = Vector2i(aabb.size.x * TILE_SIZE, aabb.size.y * TILE_SIZE)
	if grid_size.x * grid_size.y > MAX_GRID_CELLS:
		push_warning("LightingManager: grid size %s exceeds cap; skipping" % grid_size)
		grid_size = Vector2i.ZERO
		loaded_aabb = Rect2i()
		return false
	var tf := RDTextureFormat.new()
	tf.width = grid_size.x
	tf.height = grid_size.y
	tf.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	tf.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	)
	main_grid_tex = rd.texture_create(tf, RDTextureView.new())
	scratch_grid_tex = rd.texture_create(tf, RDTextureView.new())
	return true


func _free_grid_textures() -> void:
	if main_grid_tex.is_valid():
		rd.free_rid(main_grid_tex)
		main_grid_tex = RID()
	if scratch_grid_tex.is_valid():
		rd.free_rid(scratch_grid_tex)
		scratch_grid_tex = RID()


func _process(_delta: float) -> void:
	if not enabled:
		return
	_frame_counter += 1
	if _frame_counter < tick_interval:
		return
	_frame_counter = 0
	_tick()


func _tick() -> void:
	if rd == null:
		return
	if not _ensure_grid_textures():
		return
	_dispatch_emission_reduce()
	_dispatch_compose()
	_dispatch_blur()
	_publish_grid_globals()


func _publish_grid_globals() -> void:
	if main_grid_2d == null:
		main_grid_2d = Texture2DRD.new()
	main_grid_2d.texture_rd_rid = main_grid_tex
	RenderingServer.global_shader_parameter_set("light_grid_tex", main_grid_2d)

	var origin_px := Vector2(loaded_aabb.position) * float(CHUNK_SIZE)
	var size_px := Vector2(loaded_aabb.size) * float(CHUNK_SIZE)
	RenderingServer.global_shader_parameter_set(
		"light_grid_world_rect",
		Vector4(origin_px.x, origin_px.y, size_px.x, size_px.y),
	)
	RenderingServer.global_shader_parameter_set("light_intensity_k", intensity_k)
	RenderingServer.global_shader_parameter_set(
		"light_ambient", Vector3(ambient.r, ambient.g, ambient.b)
	)


func _dispatch_blur() -> void:
	if not main_grid_tex.is_valid():
		return
	var groups_x := (grid_size.x + 7) / 8
	var groups_y := (grid_size.y + 7) / 8

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, blur_pipeline)
	var created_sets: Array[RID] = []

	# Horizontal: main -> scratch
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(main_grid_tex)
	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u1.binding = 1
	u1.add_id(scratch_grid_tex)
	var s0 := rd.uniform_set_create([u0, u1], blur_shader, 0)
	created_sets.append(s0)

	var pc_h := PackedByteArray()
	pc_h.resize(16)
	pc_h.encode_s32(0, grid_size.x)
	pc_h.encode_s32(4, grid_size.y)
	pc_h.encode_s32(8, 1)
	pc_h.encode_s32(12, 0)
	rd.compute_list_bind_uniform_set(compute_list, s0, 0)
	rd.compute_list_set_push_constant(compute_list, pc_h, pc_h.size())
	rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)

	rd.compute_list_add_barrier(compute_list)

	# Vertical: scratch -> main
	var u2 := RDUniform.new()
	u2.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u2.binding = 0
	u2.add_id(scratch_grid_tex)
	var u3 := RDUniform.new()
	u3.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u3.binding = 1
	u3.add_id(main_grid_tex)
	var s1 := rd.uniform_set_create([u2, u3], blur_shader, 0)
	created_sets.append(s1)

	var pc_v := PackedByteArray()
	pc_v.resize(16)
	pc_v.encode_s32(0, grid_size.x)
	pc_v.encode_s32(4, grid_size.y)
	pc_v.encode_s32(8, 0)
	pc_v.encode_s32(12, 1)
	rd.compute_list_bind_uniform_set(compute_list, s1, 0)
	rd.compute_list_set_push_constant(compute_list, pc_v, pc_v.size())
	rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)

	rd.compute_list_end()
	for s in created_sets:
		rd.free_rid(s)


func _dispatch_compose() -> void:
	if not main_grid_tex.is_valid():
		return
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, compose_pipeline)
	var groups := TILE_SIZE / 8
	var created_sets: Array[RID] = []

	for coord_v in emission_tiles.keys():
		var coord: Vector2i = coord_v
		var tile_rid: RID = emission_tiles[coord]
		var dst := (coord - loaded_aabb.position) * TILE_SIZE

		var u_src := RDUniform.new()
		u_src.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_src.binding = 0
		u_src.add_id(tile_rid)

		var u_dst := RDUniform.new()
		u_dst.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_dst.binding = 1
		u_dst.add_id(main_grid_tex)

		var set_rid := rd.uniform_set_create([u_src, u_dst], compose_shader, 0)
		created_sets.append(set_rid)

		var pc := PackedByteArray()
		pc.resize(16)
		pc.encode_s32(0, dst.x)
		pc.encode_s32(4, dst.y)

		rd.compute_list_bind_uniform_set(compute_list, set_rid, 0)
		rd.compute_list_set_push_constant(compute_list, pc, pc.size())
		rd.compute_list_dispatch(compute_list, groups, groups, 1)

	rd.compute_list_end()
	for s in created_sets:
		rd.free_rid(s)


func _get_chunks() -> Dictionary:
	var world_manager = get_node_or_null("/root/Main")
	if world_manager == null:
		return {}
	if not "chunks" in world_manager:
		return {}
	return world_manager.chunks


func _dispatch_emission_reduce() -> void:
	var chunks := _get_chunks()
	if chunks.is_empty():
		return

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, emission_pipeline)
	var groups := TILE_SIZE / 8

	var created_sets: Array[RID] = []

	for coord in chunks:
		var chunk = chunks[coord]
		var tile_var = emission_tiles.get(coord, null)
		if tile_var == null:
			continue
		var tile_rid: RID = tile_var

		var u_chunk := RDUniform.new()
		u_chunk.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_chunk.binding = 0
		u_chunk.add_id(chunk.rd_texture)

		var u_tile := RDUniform.new()
		u_tile.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_tile.binding = 1
		u_tile.add_id(tile_rid)

		var set_rid := rd.uniform_set_create([u_chunk, u_tile], emission_shader, 0)
		created_sets.append(set_rid)
		rd.compute_list_bind_uniform_set(compute_list, set_rid, 0)
		rd.compute_list_dispatch(compute_list, groups, groups, 1)

	rd.compute_list_end()
	for s in created_sets:
		rd.free_rid(s)


func register_chunk(chunk) -> void:
	if rd == null or not enabled:
		return
	if emission_tiles.has(chunk.coord):
		return
	var tf := RDTextureFormat.new()
	tf.width = TILE_SIZE
	tf.height = TILE_SIZE
	tf.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	tf.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	emission_tiles[chunk.coord] = rd.texture_create(tf, RDTextureView.new())


func unregister_chunk(chunk) -> void:
	if rd == null:
		return
	var tex_var = emission_tiles.get(chunk.coord, null)
	if tex_var == null:
		return
	var tex: RID = tex_var
	if tex.is_valid():
		rd.free_rid(tex)
	emission_tiles.erase(chunk.coord)
