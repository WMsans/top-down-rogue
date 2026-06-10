class_name NavField
extends RefCounted

const CELL := 8
const CHUNK := 256
const REGION_RADIUS_CELLS := 48
const FLOW_BUDGET := 160
const MOVE_THRESHOLD_CELLS := 8
const MAX_LIVE_AGE := 3.0

var grid: PassabilityGrid
var flow: FlowField

# world_manager is accepted for call-site compatibility but no longer used:
# the GPU collider pass feeds grid tiles via TerrainCollisionHelper.
func _init(_world_manager = null) -> void:
	grid = PassabilityGrid.new(CELL, CHUNK, _build_solid_lut())
	flow = FlowField.new(CELL, REGION_RADIUS_CELLS, FLOW_BUDGET, MOVE_THRESHOLD_CELLS, MAX_LIVE_AGE)

func _build_solid_lut() -> PackedByteArray:
	var n: int = MaterialRegistry.materials.size()
	var lut := PackedByteArray()
	lut.resize(n)
	for i in n:
		lut[i] = 1 if MaterialRegistry.has_collider(i) else 0
	return lut

func update(player_world_pos: Vector2, delta: float) -> void:
	flow.update(grid, player_world_pos, delta)

func sample_direction(world_pos: Vector2) -> Vector2:
	return flow.sample_direction(world_pos)

func is_solid_world(world_pos: Vector2) -> bool:
	return grid.is_solid_world(world_pos)
