class_name SwarmGrid
extends RefCounted

# Per-frame spatial hash of enemy positions used for O(n) crowd separation.
# Rebuilt once per frame by WorldManager; enemies query only their 3x3 cell
# neighbourhood instead of iterating the whole "attackable" group.
#
# cell_size must be >= the largest enemy separation_radius so a 3x3 query around
# a position covers every node within that radius. Enemy.separation_radius
# defaults to 16; 32 leaves headroom for elites/larger bodies.

var _cell_size: float
var _cells: Dictionary = {}  # Vector2i -> Array[Node2D]


func _init(cell_size: float = 32.0) -> void:
	_cell_size = maxf(1.0, cell_size)


func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / _cell_size), floori(pos.y / _cell_size))


func rebuild(nodes: Array) -> void:
	_cells.clear()
	for n in nodes:
		if not is_instance_valid(n) or not (n is Node2D):
			continue
		var key := _cell_of((n as Node2D).global_position)
		if not _cells.has(key):
			_cells[key] = []
		_cells[key].append(n)


func query_neighbors(pos: Vector2) -> Array:
	var result: Array = []
	var base := _cell_of(pos)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var key := base + Vector2i(dx, dy)
			if _cells.has(key):
				result.append_array(_cells[key])
	return result
