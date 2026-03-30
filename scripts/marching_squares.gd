class_name MarchingSquares
extends RefCounted

## Takes a 2D grid of booleans and returns polygon contours.
## grid_width/grid_height are the dimensions of the boolean grid.
## cell_size is the world-space size of each grid cell (used to scale output vertices).
## offset is the world-space position of the grid's top-left corner.

static func generate_polygons(grid: Array[bool], grid_width: int, grid_height: int, cell_size: float, offset: Vector2) -> Array[PackedVector2Array]:
	# Build edge segments from marching squares cases
	var segments: Array[Vector2] = [] # pairs of points: [start0, end0, start1, end1, ...]

	for y in range(grid_height - 1):
		for x in range(grid_width - 1):
			var tl := grid[y * grid_width + x]
			var tr := grid[y * grid_width + (x + 1)]
			var bl := grid[(y + 1) * grid_width + x]
			var br := grid[(y + 1) * grid_width + (x + 1)]

			var case_index := 0
			if tl: case_index |= 8
			if tr: case_index |= 4
			if br: case_index |= 2
			if bl: case_index |= 1

			var cx := float(x) * cell_size + offset.x
			var cy := float(y) * cell_size + offset.y

			var top := Vector2(cx + cell_size * 0.5, cy)
			var bottom := Vector2(cx + cell_size * 0.5, cy + cell_size)
			var left := Vector2(cx, cy + cell_size * 0.5)
			var right := Vector2(cx + cell_size, cy + cell_size * 0.5)

			match case_index:
				0, 15:
					pass # all air or all solid — no boundary
				1:
					segments.append_array([left, bottom])
				2:
					segments.append_array([bottom, right])
				3:
					segments.append_array([left, right])
				4:
					segments.append_array([right, top])
				5:
					# Saddle case: tl=0 tr=1 br=0 bl=1
					segments.append_array([left, top])
					segments.append_array([right, bottom])
				6:
					segments.append_array([bottom, top])
				7:
					segments.append_array([left, top])
				8:
					segments.append_array([top, left])
				9:
					segments.append_array([top, bottom])
				10:
					# Saddle case: tl=1 tr=0 br=1 bl=0
					segments.append_array([top, right])
					segments.append_array([bottom, left])
				11:
					segments.append_array([top, right])
				12:
					segments.append_array([right, left])
				13:
					segments.append_array([right, bottom])
				14:
					segments.append_array([bottom, left])

	return _chain_segments_into_polygons(segments)


static func _chain_segments_into_polygons(segments: Array[Vector2]) -> Array[PackedVector2Array]:
	if segments.is_empty():
		return []

	# Build adjacency: map each point to the segments that start/end there
	# segments are stored as pairs: [start0, end0, start1, end1, ...]
	var segment_count := segments.size() / 2
	var used := PackedByteArray()
	used.resize(segment_count)
	used.fill(0)

	var result: Array[PackedVector2Array] = []
	var epsilon := 0.01

	for i in range(segment_count):
		if used[i]:
			continue

		# Start a new chain from this segment
		var chain: PackedVector2Array = []
		chain.append(segments[i * 2])
		chain.append(segments[i * 2 + 1])
		used[i] = 1

		# Try to extend the chain by finding segments whose start matches our chain's end
		var changed := true
		while changed:
			changed = false
			var chain_end := chain[chain.size() - 1]
			for j in range(segment_count):
				if used[j]:
					continue
				var s_start := segments[j * 2]
				var s_end := segments[j * 2 + 1]
				if chain_end.distance_to(s_start) < epsilon:
					chain.append(s_end)
					used[j] = 1
					changed = true
					break
				elif chain_end.distance_to(s_end) < epsilon:
					chain.append(s_start)
					used[j] = 1
					changed = true
					break

		if chain.size() >= 3:
			result.append(chain)

	return result
