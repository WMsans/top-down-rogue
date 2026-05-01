class_name TerrainPhysical
extends Node

## CPU-side cache: Vector2i(world_x, world_y) -> int (material_id)
var _grid: Dictionary = {}

## Grid center in world coords
var _grid_center: Vector2i = Vector2i.ZERO
var _grid_size: int = 128
var _half_grid: int = 64

## Dirty sectors waiting for collision rebuild
var _dirty_sectors: Array[Rect2i] = []

## Reference to WorldManager for GPU readback
var world_manager: Node2D = null

## Collision segments per chunk (for debug/collision queries)
var _segments_per_chunk: Dictionary = {}  # Vector2i -> Array[Vector2]


func query(world_pos: Vector2) -> TerrainCell:
	var cell_pos := Vector2i(int(floor(world_pos.x)), int(floor(world_pos.y)))
	if _grid.has(cell_pos):
		var mat_id: int = _grid[cell_pos]
		return _cell_from_material(mat_id)
	return TerrainCell.new()


func invalidate_rect(rect: Rect2i) -> void:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			_grid.erase(Vector2i(x, y))
	_dirty_sectors.append(rect)


func set_center(world_center: Vector2i) -> void:
	_grid_center = world_center


func _cell_from_material(mat_id: int) -> TerrainCell:
	var is_solid := MaterialTable.has_collider(mat_id)
	var is_fluid := MaterialTable.is_fluid(mat_id)
	var dmg := MaterialTable.get_damage(mat_id)
	var cell := TerrainCell.new()
	cell.init_args(mat_id, is_solid, is_fluid, dmg)
	return cell
