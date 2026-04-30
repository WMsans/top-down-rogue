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


func _ready() -> void:
	rd = RenderingServer.get_rendering_device()


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


func register_chunk(_chunk) -> void:
	pass


func unregister_chunk(_chunk) -> void:
	pass
