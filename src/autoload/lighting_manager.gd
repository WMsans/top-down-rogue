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

# Vector2i chunk_coord -> RID emission_tile_tex (RGBA16F, TILE_SIZE x TILE_SIZE)
var emission_tiles: Dictionary = {}


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


func _exit_tree() -> void:
	if rd == null:
		return
	for tex in emission_tiles.values():
		if tex.is_valid():
			rd.free_rid(tex)
	emission_tiles.clear()
	if emission_pipeline.is_valid():
		rd.free_rid(emission_pipeline)
	if emission_shader.is_valid():
		rd.free_rid(emission_shader)


func _process(_delta: float) -> void:
	if not enabled:
		return
	_frame_counter += 1
	if _frame_counter < tick_interval:
		return
	_frame_counter = 0
	_tick()


func _tick() -> void:
	pass


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
