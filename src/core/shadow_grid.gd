class_name ShadowGrid
extends Node

## Size of the shadow grid in pixels (square). Configurable, default 128.
@export var grid_size: int = 128

## Distance from grid center before re-centering triggers a sync.
const RECENTER_THRESHOLD := 32

## Emitted when grid data is updated (after readback apply or force sync).
signal data_updated

var _data: PackedByteArray
## World position of the grid's top-left corner.
var _anchor: Vector2i = Vector2i.ZERO
## World position of the grid center at last sync.
var _last_sync_center: Vector2i = Vector2i.ZERO

## Reference to WorldManager — set by the player controller during setup.
var world_manager: Node2D

## Sync scheduling state
var _sync_pending: bool = false
var _readback_pending: bool = false
var _pending_data: PackedByteArray
var _frames_since_last_sync: int = 0
var _dirty: bool = false
const MIN_SYNC_INTERVAL := 3  # Minimum frames between syncs


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
	return _data[idx] != MaterialRegistry.MAT_AIR


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
	## print("=== ShadowGrid.apply_data ===")
	## print("  data size: %d" % data.size())
	_data = data
	data_updated.emit()
	## print("  Emitted data_updated signal")


## Returns the world-space Rect2i that this grid currently covers.
func get_world_rect() -> Rect2i:
	return Rect2i(_anchor, Vector2i(grid_size, grid_size))


## Called each physics frame by the player controller.
## Handles async two-phase readback: request on frame N, apply on frame N+1.
func update_sync(player_world_pos: Vector2i) -> void:
	_frames_since_last_sync += 1

	# Phase 2: apply pending readback data from previous frame
	if _readback_pending:
		apply_data(_pending_data)
		_pending_data = PackedByteArray()
		_readback_pending = false
		_frames_since_last_sync = 0

	# Phase 1: check if we need to request a new readback
	var should_sync: bool = _dirty or needs_recenter(player_world_pos)
	if should_sync and _frames_since_last_sync >= MIN_SYNC_INTERVAL and not _sync_pending:
		set_center(player_world_pos)
		_request_readback()


func _request_readback() -> void:
	if world_manager == null:
		return
	_sync_pending = true
	# Perform the GPU readback (synchronous call, but only happens every few frames)
	_pending_data = world_manager.read_region(get_world_rect())
	_sync_pending = false
	_readback_pending = true
	_dirty = false


## Called by WorldManager when terrain changes in a chunk that overlaps this grid.
func mark_dirty() -> void:
	_dirty = true


## Force an immediate sync (used for initial spawn).
func force_sync(center: Vector2i) -> void:
	## print("=== ShadowGrid.force_sync ===")
	## print("  center: %s" % center)
	if world_manager == null:
		print("  ERROR: world_manager is null!")
		return
	set_center(center)
	var data: PackedByteArray = world_manager.read_region(get_world_rect())
	# print("  Read region data size: %d" % data.size())
	_data = data
	_frames_since_last_sync = 0
	_dirty = false
	data_updated.emit()
	# print("  Emitted data_updated signal")
