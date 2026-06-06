class_name NavField
extends RefCounted

const CELL := 8
const CHUNK := 256
const REGION_RADIUS_CELLS := 48
const TILE_BUDGET := 2
const FLOW_BUDGET := 160
const MOVE_THRESHOLD_CELLS := 8
const MAX_LIVE_AGE := 3.0

var _world_manager
var grid: PassabilityGrid
var flow: FlowField
var _dirty: Dictionary = {}

func _init(world_manager) -> void:
	_world_manager = world_manager
	grid = PassabilityGrid.new(CELL, CHUNK, _build_solid_lut())
	flow = FlowField.new(CELL, REGION_RADIUS_CELLS, FLOW_BUDGET, MOVE_THRESHOLD_CELLS, MAX_LIVE_AGE)

func _build_solid_lut() -> PackedByteArray:
	var n: int = MaterialRegistry.materials.size()
	var lut := PackedByteArray()
	lut.resize(n)
	for i in n:
		lut[i] = 1 if MaterialRegistry.has_collider(i) else 0
	return lut

func mark_dirty(chunk_coord: Vector2i) -> void:
	_dirty[chunk_coord] = true

func update(player_world_pos: Vector2, delta: float) -> void:
	_drain_tiles()
	flow.update(grid, player_world_pos, delta)

func _drain_tiles() -> void:
	var done := 0
	for coord in _dirty.keys():
		if done >= TILE_BUDGET:
			break
		var origin: Vector2i = coord * CHUNK
		var bytes: PackedByteArray = _world_manager.read_region(Rect2i(origin, Vector2i(CHUNK, CHUNK)))
		grid.update_chunk(coord, bytes)
		_dirty.erase(coord)
		done += 1

func sample_direction(world_pos: Vector2) -> Vector2:
	return flow.sample_direction(world_pos)

func is_solid_world(world_pos: Vector2) -> bool:
	return grid.is_solid_world(world_pos)
