class_name PassabilityGrid
extends RefCounted

# Coarse "is this cell solid?" lookup, backed by cached per-chunk tiles.
# A cell is solid if ANY pixel in its block uses a material flagged solid in the
# LUT. That conservative rule inflates walls by ~one enemy radius (8px), keeping
# bodies out of walls like agent-radius inflation in a navmesh.

var _cell: int
var _chunk: int
var _cells_per_chunk: int
var _solid_lut: PackedByteArray
var _tiles: Dictionary = {}  # Vector2i chunk coord -> PackedByteArray (cells_per_chunk^2, 1=solid)

func _init(cell_size: int = 8, chunk_size: int = 256, solid_lut: PackedByteArray = PackedByteArray()) -> void:
	_cell = cell_size
	_chunk = chunk_size
	_cells_per_chunk = chunk_size / cell_size
	_solid_lut = solid_lut

func update_chunk(chunk_coord: Vector2i, material_bytes: PackedByteArray) -> void:
	var tile := PackedByteArray()
	tile.resize(_cells_per_chunk * _cells_per_chunk)
	tile.fill(0)
	for cy in _cells_per_chunk:
		for cx in _cells_per_chunk:
			var solid := false
			var py0 := cy * _cell
			var px0 := cx * _cell
			for py in range(py0, py0 + _cell):
				var row := py * _chunk
				for px in range(px0, px0 + _cell):
					var mat: int = material_bytes[row + px]
					if mat >= 0 and mat < _solid_lut.size() and _solid_lut[mat] == 1:
						solid = true
						break
				if solid:
					break
			tile[cy * _cells_per_chunk + cx] = 1 if solid else 0
	_tiles[chunk_coord] = tile

func set_tile(chunk_coord: Vector2i, tile: PackedByteArray) -> void:
	_tiles[chunk_coord] = tile

func drop_chunk(chunk_coord: Vector2i) -> void:
	_tiles.erase(chunk_coord)

func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / _cell), floori(world_pos.y / _cell))

func is_solid_cell(cell: Vector2i) -> bool:
	var chunk := Vector2i(
		floori(float(cell.x) / _cells_per_chunk),
		floori(float(cell.y) / _cells_per_chunk)
	)
	var tile = _tiles.get(chunk, null)
	if tile == null:
		return false
	var lx: int = cell.x - chunk.x * _cells_per_chunk
	var ly: int = cell.y - chunk.y * _cells_per_chunk
	return tile[ly * _cells_per_chunk + lx] == 1

func is_solid_world(world_pos: Vector2) -> bool:
	return is_solid_cell(world_to_cell(world_pos))
