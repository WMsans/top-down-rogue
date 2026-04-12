class_name TerrainCollider

## Cell size for marching squares (in pixels). Larger = fewer polygons but less detail.
const CELL_SIZE := 2

## Douglas-Peucker simplification tolerance (in pixels).
const DP_EPSILON := 0.8

## Distance to inset occluder polygons (in pixels). Matches near_air() radius.
const OCCLUDER_INSET := 3.0


## Build collision shape from material data and attach to a StaticBody2D.
## Returns the created CollisionShape2D, or null if no segments generated.
static func build_collision(data: PackedByteArray, size: int, static_body: StaticBody2D, world_offset: Vector2i) -> CollisionShape2D:
	var samples_w: int = size / CELL_SIZE + 1
	var samples_h: int = size / CELL_SIZE + 1
	var samples := PackedByteArray()
	samples.resize(samples_w * samples_h)

	for sy in samples_h:
		for sx in samples_w:
			if sx == 0 or sx == samples_w - 1 or sy == 0 or sy == samples_h - 1:
				samples[sy * samples_w + sx] = 0
				continue
			var gx: int = mini(sx * CELL_SIZE, size - 1)
			var gy: int = mini(sy * CELL_SIZE, size - 1)
			samples[sy * samples_w + sx] = 1 if data[gy * size + gx] != 0 else 0

	var cells_w: int = samples_w - 1
	var cells_h: int = samples_h - 1
	var adj: Dictionary = {}

	for cy in cells_h:
		for cx in cells_w:
			var tl: int = samples[cy * samples_w + cx]
			var tr: int = samples[cy * samples_w + cx + 1]
			var br: int = samples[(cy + 1) * samples_w + cx + 1]
			var bl: int = samples[(cy + 1) * samples_w + cx]
			var case_idx: int = (tl << 3) | (tr << 2) | (br << 1) | bl

			for seg in _get_segments(case_idx):
				var p1: Vector2i = _edge_point(cx, cy, seg[0])
				var p2: Vector2i = _edge_point(cx, cy, seg[1])
				if not adj.has(p1):
					adj[p1] = []
				if not adj.has(p2):
					adj[p2] = []
				adj[p1].append(p2)
				adj[p2].append(p1)

	var visited: Dictionary = {}
	var all_segments := PackedVector2Array()

	for start_point: Vector2i in adj:
		if visited.has(start_point):
			continue
		var neighbors: Array = adj[start_point]
		if neighbors.size() == 0:
			continue

		var poly_points := PackedVector2Array()
		var current: Vector2i = start_point
		var prev: Vector2i = Vector2i(-999999, -999999)
		var closed := false

		while true:
			visited[current] = true
			poly_points.append(Vector2(current.x, current.y))

			var cur_neighbors: Array = adj[current]
			var next: Vector2i = Vector2i(-999999, -999999)
			for n: Vector2i in cur_neighbors:
				if n == prev:
					continue
				if n == start_point and poly_points.size() >= 3:
					next = start_point
					break
				if not visited.has(n):
					next = n
					break

			if next == start_point:
				closed = true
				break
			if next == Vector2i(-999999, -999999):
				break

			prev = current
			current = next

		if poly_points.size() >= 3 and closed:
			poly_points = _simplify_closed_polygon(poly_points, DP_EPSILON)
			for i in poly_points.size():
				all_segments.append(poly_points[i])
				all_segments.append(poly_points[(i + 1) % poly_points.size()])

	if all_segments.size() >= 4:
		var shape := ConcavePolygonShape2D.new()
		shape.segments = all_segments
		var collision_shape := CollisionShape2D.new()
		collision_shape.shape = shape
		static_body.position = Vector2(world_offset.x, world_offset.y)
		return collision_shape
	return null


static func _get_segments(case_idx: int) -> Array:
	match case_idx:
		1: return [[3, 2]]
		2: return [[2, 1]]
		3: return [[3, 1]]
		4: return [[1, 0]]
		5: return [[0, 1], [3, 2]]
		6: return [[2, 0]]
		7: return [[3, 0]]
		8: return [[0, 3]]
		9: return [[0, 2]]
		10: return [[0, 3], [1, 2]]
		11: return [[0, 1]]
		12: return [[1, 3]]
		13: return [[1, 2]]
		14: return [[2, 3]]
		_: return []


static func _edge_point(cx: int, cy: int, edge: int) -> Vector2i:
	var half: int = CELL_SIZE / 2
	match edge:
		0: return Vector2i(cx * CELL_SIZE + half, cy * CELL_SIZE)
		1: return Vector2i((cx + 1) * CELL_SIZE, cy * CELL_SIZE + half)
		2: return Vector2i(cx * CELL_SIZE + half, (cy + 1) * CELL_SIZE)
		3: return Vector2i(cx * CELL_SIZE, cy * CELL_SIZE + half)
	return Vector2i.ZERO


static func _simplify_closed_polygon(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	var n: int = points.size()
	if n <= 4:
		return points

	var mid: int = n / 2
	var chain1 := PackedVector2Array()
	for i in range(0, mid + 1):
		chain1.append(points[i])
	var chain2 := PackedVector2Array()
	for i in range(mid, n):
		chain2.append(points[i])
	chain2.append(points[0])

	chain1 = _douglas_peucker(chain1, epsilon)
	chain2 = _douglas_peucker(chain2, epsilon)

	var result := PackedVector2Array()
	for i in chain1.size():
		result.append(chain1[i])
	for i in range(1, chain2.size() - 1):
		result.append(chain2[i])
	return result


static func _douglas_peucker(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	if points.size() <= 2:
		return points

	var max_dist: float = 0.0
	var max_idx: int = 0
	var first: Vector2 = points[0]
	var last: Vector2 = points[points.size() - 1]

	for i in range(1, points.size() - 1):
		var dist: float = _point_to_segment_distance(points[i], first, last)
		if dist > max_dist:
			max_dist = dist
			max_idx = i

	if max_dist > epsilon:
		var left := _douglas_peucker(points.slice(0, max_idx + 1), epsilon)
		var right := _douglas_peucker(points.slice(max_idx), epsilon)
		var result := PackedVector2Array()
		for i in range(left.size() - 1):
			result.append(left[i])
		for i in right.size():
			result.append(right[i])
		return result
	else:
		var result := PackedVector2Array()
		result.append(first)
		result.append(last)
		return result


static func _point_to_segment_distance(point: Vector2, seg_start: Vector2, seg_end: Vector2) -> float:
	var line: Vector2 = seg_end - seg_start
	var len_sq: float = line.length_squared()
	if len_sq < 0.0001:
		return point.distance_to(seg_start)
	var t: float = clampf((point - seg_start).dot(line) / len_sq, 0.0, 1.0)
	var projection: Vector2 = seg_start + line * t
	return point.distance_to(projection)


## Shrink a closed polygon by offsetting vertices inward along their normals.
## Points must form a closed loop (first and last are implicit neighbors).
## Returns a new polygon with inset vertices, or empty if degenerate.
static func shrink_polygon(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	if points.size() < 3:
		return PackedVector2Array()
	
	# Calculate signed area to determine winding direction
	# Positive = counter-clockwise, negative = clockwise
	var signed_area := 0.0
	for i in points.size():
		var j := (i + 1) % points.size()
		signed_area += points[i].x * points[j].y - points[j].x * points[i].y
	signed_area *= 0.5
	
	# Inward direction multiplier: +1 for CCW (positive area), -1 for CW (negative area)
	var inward_mult := 1.0 if signed_area > 0 else -1.0
	
	var result := PackedVector2Array()
	result.resize(points.size())
	
	for i in points.size():
		var prev_idx := (i - 1 + points.size()) % points.size()
		var next_idx := (i + 1) % points.size()
		
		# Edge from prev to current, and current to next
		var edge1 := points[i] - points[prev_idx]
		var edge2 := points[next_idx] - points[i]
		
		# Perpendiculars (rotate90counter-clockwise)
		var perp1 := Vector2(-edge1.y, edge1.x)
		var perp2 := Vector2(-edge2.y, edge2.x)
		
		# Normalize and average for vertex normal
		var normal := (perp1.normalized() + perp2.normalized()).normalized()
		# Apply inward offset
		result[i] = points[i] + normal * distance * inward_mult
	
	return result


## Build collision shape from pre-computed segment vertices.
## Segments must contain an even number of vertices (pairs of endpoints).
## Returns the created CollisionShape2D, or null if insufficient segments.
static func build_from_segments(
	segments: PackedVector2Array,
	static_body: StaticBody2D,
	world_offset: Vector2i
) -> CollisionShape2D:
	if segments.size() % 2 != 0:
		return null
	if segments.size() < 4:
		return null

	var shape := ConcavePolygonShape2D.new()
	shape.segments = segments
	var collision_shape := CollisionShape2D.new()
	collision_shape.shape = shape
	static_body.position = Vector2(world_offset.x, world_offset.y)
	return collision_shape


## Build ordered polygon chains from segment pairs and return an array of OccluderPolygon2D.
## Segments is a flat array of endpoint pairs: [A, B, C, D, ...] where (A,B), (C,D) are segments.
## Returns an empty array if no valid polygons can be reconstructed.
static func create_occluder_polygons(segments: PackedVector2Array) -> Array[OccluderPolygon2D]:
	if segments.size() < 4:
		return []

	# Build adjacency from segment pairs
	var adj: Dictionary = {}  # Vector2 -> Array[Vector2]
	for i in range(0, segments.size(), 2):
		var p1 := segments[i]
		var p2 := segments[i + 1]
		if not adj.has(p1):
			adj[p1] = []
		if not adj.has(p2):
			adj[p2] = []
		adj[p1].append(p2)
		adj[p2].append(p1)

	# Trace closed loops
	var visited: Dictionary = {}
	var result: Array[OccluderPolygon2D] = []

	for start: Vector2 in adj:
		if visited.has(start):
			continue
		var neighbors: Array = adj[start]
		if neighbors.size() == 0:
			continue

		var chain := PackedVector2Array()
		var current: Vector2 = start
		var prev := Vector2(-1e9, -1e9)
		var closed := false

		while true:
			visited[current] = true
			chain.append(current)

			var cur_neighbors: Array = adj[current]
			var next := Vector2(-1e9, -1e9)
			for n: Vector2 in cur_neighbors:
				if n == prev:
					continue
				if n == start and chain.size() >= 3:
					next = start
					break
				if not visited.has(n):
					next = n
					break

			if next == start:
				closed = true
				break
			if next == Vector2(-1e9, -1e9):
				break

			prev = current
			current = next

		if chain.size() >= 3 and closed:
			var shrunk := shrink_polygon(chain, OCCLUDER_INSET)
			if shrunk.size() >= 3:
				var polygon := OccluderPolygon2D.new()
				polygon.polygon = shrunk
				result.append(polygon)

	return result
