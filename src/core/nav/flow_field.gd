class_name FlowField
extends RefCounted

# Shared, double-buffered, time-sliced BFS field of directions pointing toward
# the player. Enemies sample the LIVE buffer; a WORK buffer is filled a fixed
# budget of cells per frame, then swapped in when complete. Cost is flat per
# frame (no periodic stall).

var _cell: int
var _radius: int        # field half-size in cells
var _budget: int        # cells expanded per step()
var _move_thresh: int   # rebuild when player drifts this many cells
var _max_age: float     # rebuild when live field older than this (seconds)
var _D: int             # side length = 2*radius+1

# Live buffer (sampled by enemies)
var _has_live: bool = false
var _live_origin: Vector2i = Vector2i.ZERO
var _live_dir: PackedVector2Array = PackedVector2Array()
var _live_age: float = 0.0

# Work buffer (built incrementally)
var _building: bool = false
var _work_origin: Vector2i = Vector2i.ZERO
var _work_dir: PackedVector2Array = PackedVector2Array()
var _work_dist: PackedInt32Array = PackedInt32Array()
var _frontier: PackedInt32Array = PackedInt32Array()
var _head: int = 0

func _init(cell_size: int, radius_cells: int, cell_budget: int, move_thresh_cells: int, max_age_sec: float) -> void:
	_cell = cell_size
	_radius = radius_cells
	_budget = cell_budget
	_move_thresh = move_thresh_cells
	_max_age = max_age_sec
	_D = radius_cells * 2 + 1

func is_building() -> bool:
	return _building

func has_live() -> bool:
	return _has_live

func live_dir() -> PackedVector2Array:
	return _live_dir

func live_origin_cell() -> Vector2i:
	return _live_origin

func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / _cell), floori(world_pos.y / _cell))

func begin_build(origin_cell: Vector2i) -> void:
	_work_origin = origin_cell
	_work_dir = PackedVector2Array()
	_work_dir.resize(_D * _D)
	_work_dir.fill(Vector2.ZERO)
	_work_dist = PackedInt32Array()
	_work_dist.resize(_D * _D)
	_work_dist.fill(-1)
	_frontier = PackedInt32Array()
	_head = 0
	var center := _radius * _D + _radius
	_work_dist[center] = 0
	_frontier.append(center)
	_building = true

func step(grid) -> void:
	if not _building:
		return
	var processed := 0
	while _head < _frontier.size() and processed < _budget:
		var idx: int = _frontier[_head]
		_head += 1
		processed += 1
		var lx: int = idx % _D
		var ly: int = idx / _D
		var d: int = _work_dist[idx]
		for oy in [-1, 0, 1]:
			for ox in [-1, 0, 1]:
				if ox == 0 and oy == 0:
					continue
				var nx: int = lx + ox
				var ny: int = ly + oy
				if nx < 0 or ny < 0 or nx >= _D or ny >= _D:
					continue
				var nidx: int = ny * _D + nx
				if _work_dist[nidx] != -1:
					continue
				var wcell := Vector2i(_work_origin.x + (nx - _radius), _work_origin.y + (ny - _radius))
				if grid.is_solid_cell(wcell):
					_work_dist[nidx] = -2  # solid: visited, never enqueued, no flow
					continue
				_work_dist[nidx] = d + 1
				# Direction points from the neighbor back toward the current cell,
				# which is one step closer to the player.
				_work_dir[nidx] = Vector2(lx - nx, ly - ny).normalized()
				_frontier.append(nidx)
	if _head >= _frontier.size():
		_finish_build()

func _finish_build() -> void:
	_live_dir = _work_dir
	_live_origin = _work_origin
	_has_live = true
	_live_age = 0.0
	_building = false

func update(grid, player_world_pos: Vector2, delta: float) -> void:
	if _has_live:
		_live_age += delta
	if _building:
		step(grid)
		return
	var pcell := world_to_cell(player_world_pos)
	var need := false
	if not _has_live:
		need = true
	elif _live_age >= _max_age:
		need = true
	elif absi(pcell.x - _live_origin.x) + absi(pcell.y - _live_origin.y) >= _move_thresh:
		need = true
	if need:
		begin_build(pcell)
		step(grid)

func sample_direction(world_pos: Vector2) -> Vector2:
	if not _has_live:
		return Vector2.ZERO
	var cell := world_to_cell(world_pos)
	var lx: int = cell.x - _live_origin.x + _radius
	var ly: int = cell.y - _live_origin.y + _radius
	if lx < 0 or ly < 0 or lx >= _D or ly >= _D:
		return Vector2.ZERO
	return _live_dir[ly * _D + lx]
