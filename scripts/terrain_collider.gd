extends StaticBody2D

const READBACK_SIZE := 64
const GRID_SIZE := 16
const CELL_SIZE := 4.0  # READBACK_SIZE / GRID_SIZE = 4 pixels per cell
const REBUILD_THRESHOLD := 8.0  # pixels

var _last_rebuild_center := Vector2.INF
var _world_manager: Node2D


func _ready() -> void:
	# TerrainCollider is child of Player, which is child of Main
	# WorldManager is sibling of Player under Main
	_world_manager = get_node("/root/Main/WorldManager")
	top_level = true  # Don't inherit Player's transform — polygons are in world space


func _physics_process(_delta: float) -> void:
	var player_pos := get_parent().global_position  # Player's position

	if player_pos.distance_to(_last_rebuild_center) < REBUILD_THRESHOLD:
		return

	_rebuild_collision(player_pos)
	_last_rebuild_center = player_pos


func _rebuild_collision(center: Vector2) -> void:
	# Clear existing collision polygons
	for child in get_children():
		child.queue_free()

	# Read terrain region from WorldManager
	var region_data := _world_manager.read_terrain_region(center, READBACK_SIZE)
	if region_data.is_empty():
		return

	# Downsample to binary grid
	var grid := _downsample_to_grid(region_data)

	# Run marching squares
	var half_readback := READBACK_SIZE * 0.5
	var grid_offset := center - Vector2(half_readback, half_readback)
	var polygons := MarchingSquares.generate_polygons(grid, GRID_SIZE, GRID_SIZE, CELL_SIZE, grid_offset)

	# Create CollisionPolygon2D for each polygon
	for poly in polygons:
		if poly.size() < 3:
			continue
		var col := CollisionPolygon2D.new()
		col.polygon = poly
		add_child(col)


func _downsample_to_grid(region_data: PackedByteArray) -> Array[bool]:
	# region_data is READBACK_SIZE * READBACK_SIZE * 4 bytes (RGBA per pixel)
	# Downsample: each CELL_SIZE x CELL_SIZE block becomes one grid cell
	# A cell is solid if ANY pixel in the block has material != 0 (R channel != 0)
	var grid: Array[bool] = []
	grid.resize(GRID_SIZE * GRID_SIZE)
	grid.fill(false)

	var cell_px := int(CELL_SIZE)

	for gy in range(GRID_SIZE):
		for gx in range(GRID_SIZE):
			var solid := false
			for ly in range(cell_px):
				if solid:
					break
				for lx in range(cell_px):
					var px := gx * cell_px + lx
					var py := gy * cell_px + ly
					var idx := (py * READBACK_SIZE + px) * 4
					if region_data[idx] != 0:  # R channel = material, 0 = air
						solid = true
						break
			grid[gy * GRID_SIZE + gx] = solid

	return grid
