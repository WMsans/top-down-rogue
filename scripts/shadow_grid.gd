class_name ShadowGrid
extends Node

## Size of the shadow grid in pixels (square). Configurable, default 128.
@export var grid_size: int = 128

## Distance from grid center before re-centering triggers a sync.
const RECENTER_THRESHOLD := 32

## Material constants (must match world_manager.gd / shaders)
const MAT_AIR := 0

var _data: PackedByteArray
## World position of the grid's top-left corner.
var _anchor: Vector2i = Vector2i.ZERO
## World position of the grid center at last sync.
var _last_sync_center: Vector2i = Vector2i.ZERO


func _ready() -> void:
	_data = PackedByteArray()
	_data.resize(grid_size * grid_size)
	# Fill with solid (conservative default — treat unknown as impassable)
	_data.fill(255)


## Convert world coordinates to grid index. Returns -1 if out of bounds.
func _world_to_index(world_x: int, world_y: int) -> int:
	var lx: int = world_x - _anchor.x
	var ly: int = world_y - _anchor.y
	if lx < 0 or lx >= grid_size or ly < 0 or ly >= grid_size:
		return -1
	return ly * grid_size + lx


## Returns true if the pixel at (world_x, world_y) is solid (not air).
## Out-of-bounds queries return true (conservative).
func is_solid(world_x: int, world_y: int) -> bool:
	var idx := _world_to_index(world_x, world_y)
	if idx == -1:
		return true
	return _data[idx] != MAT_AIR


## Returns the material type byte at (world_x, world_y).
## Out-of-bounds queries return 255 (solid).
func get_material(world_x: int, world_y: int) -> int:
	var idx := _world_to_index(world_x, world_y)
	if idx == -1:
		return 255
	return _data[idx]


## Check if the grid should be re-centered around a new player position.
func needs_recenter(player_world_pos: Vector2i) -> bool:
	var dx: int = absi(player_world_pos.x - _last_sync_center.x)
	var dy: int = absi(player_world_pos.y - _last_sync_center.y)
	return dx > RECENTER_THRESHOLD or dy > RECENTER_THRESHOLD


## Update the anchor so the grid is centered on the given world position.
func set_center(center: Vector2i) -> void:
	_anchor = Vector2i(center.x - grid_size / 2, center.y - grid_size / 2)
	_last_sync_center = center


## Replace the grid data with new readback data. Called after GPU readback completes.
func apply_data(data: PackedByteArray) -> void:
	_data = data


## Returns the world-space Rect2i that this grid currently covers.
func get_world_rect() -> Rect2i:
	return Rect2i(_anchor, Vector2i(grid_size, grid_size))
