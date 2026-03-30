class_name TerrainCollider
extends StaticBody2D

## Cell size for marching squares (in pixels). Larger = fewer polygons but less detail.
const CELL_SIZE := 2

## Douglas-Peucker simplification tolerance (in pixels).
const DP_EPSILON := 0.8

var _collision_shape: CollisionShape2D


## Rebuild collision segments from raw shadow grid data.
## Uses ConcavePolygonShape2D (line segments) to form wall boundaries.
func rebuild(data: PackedByteArray, anchor: Vector2i, grid_size: int) -> void:
	# Position this StaticBody2D at the anchor point so collision shapes
	# can be in local coordinates (relative to this node's position)
	position = Vector2(anchor.x, anchor.y)
	
	print("=== TerrainCollider.rebuild ===")
	print("  anchor: %s" % anchor)
	print("  grid_size: %d" % grid_size)
	print("  data size: %d" % data.size())
	print("  data sample (first 10 bytes): %s" % [data.slice(0, 10)])
	
	# Build sample grid at CELL_SIZE intervals
	var samples_w: int = grid_size / CELL_SIZE + 1
	var samples_h: int = grid_size / CELL_SIZE + 1
	var samples := PackedByteArray()
	samples.resize(samples_w * samples_h)

	for sy in samples_h:
		for sx in samples_w:
			# Force boundary ring to air so all marching-squares contours close
			if sx == 0 or sx == samples_w - 1 or sy == 0 or sy == samples_h - 1:
				samples[sy * samples_w + sx] = 0
				continue
			var gx: int = mini(sx * CELL_SIZE, grid_size - 1)
			var gy: int = mini(sy * CELL_SIZE, grid_size - 1)
			samples[sy * samples_w + sx] = 1 if data[gy * grid_size + gx] != 0 else 0

	# Marching squares: generate edge segments and build adjacency graph.
	# Each node has degree exactly 2, forming disjoint closed loops.
	var cells_w: int = samples_w - 1
	var cells_h: int = samples_h - 1
	var adj: Dictionary = {}  # Vector2i → Array[Vector2i]

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

	# Trace closed polylines from adjacency graph, simplify, then convert to segments
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

		# Only emit segments for closed loops — open chains would create
		# long connecting lines from the last point back to the first.
		if poly_points.size() >= 3 and closed:
			poly_points = _simplify_closed_polygon(poly_points, DP_EPSILON)
			# Convert closed polyline to segment pairs for ConcavePolygonShape2D
			for i in poly_points.size():
				all_segments.append(poly_points[i])
				all_segments.append(poly_points[(i + 1) % poly_points.size()])

	# Create or update the single ConcavePolygonShape2D
	print("  Total segments generated: %d (total points: %d)" % [all_segments.size() / 2, all_segments.size()])
	
	if all_segments.size() >= 4:
		var shape := ConcavePolygonShape2D.new()
		shape.segments = all_segments
		if _collision_shape == null:
			_collision_shape = CollisionShape2D.new()
			add_child(_collision_shape)
			print("  Created new CollisionShape2D node")
		_collision_shape.shape = shape
		print("  Collision shape created: %d segments" % (all_segments.size() / 2))
		print("  Shape segments count: %d" % (shape.segments.size() / 2))
		print("  TerrainCollider position: %s" % position)
		print("  TerrainCollider global_position: %s" % global_position)
		print("  TerrainCollider collision_layer: %d" % collision_layer)
		print("  TerrainCollider collision_mask: %d" % collision_mask)
		print("  First few segment points: %s" % [all_segments.slice(0, 6)])
		print("  First 2 segments world coords: (%s, %s), (%s, %s)" % [all_segments[0] + position, all_segments[1] + position, all_segments[2] + position, all_segments[3] + position])
	elif _collision_shape != null:
		_collision_shape.shape = null
		print("  No segments, cleared collision shape")
	else:
		print("  WARNING: No segments generated at all!")


## Marching squares segment lookup.
## Returns array of [edge_a, edge_b] pairs. Edges: 0=top, 1=right, 2=bottom, 3=left.
func _get_segments(case_idx: int) -> Array:
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


## Edge midpoint position in local grid coordinates.
func _edge_point(cx: int, cy: int, edge: int) -> Vector2i:
	var half: int = CELL_SIZE / 2
	match edge:
		0: return Vector2i(cx * CELL_SIZE + half, cy * CELL_SIZE)
		1: return Vector2i((cx + 1) * CELL_SIZE, cy * CELL_SIZE + half)
		2: return Vector2i(cx * CELL_SIZE + half, (cy + 1) * CELL_SIZE)
		3: return Vector2i(cx * CELL_SIZE, cy * CELL_SIZE + half)
	return Vector2i.ZERO


## Simplify a closed polygon using Douglas-Peucker.
## Splits at two opposing vertices, simplifies each half, recombines.
func _simplify_closed_polygon(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
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


## Standard Douglas-Peucker simplification for an open polyline.
func _douglas_peucker(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
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


## Distance from a point to a line segment.
func _point_to_segment_distance(point: Vector2, seg_start: Vector2, seg_end: Vector2) -> float:
	var line: Vector2 = seg_end - seg_start
	var len_sq: float = line.length_squared()
	if len_sq < 0.0001:
		return point.distance_to(seg_start)
	var t: float = clampf((point - seg_start).dot(line) / len_sq, 0.0, 1.0)
	var projection: Vector2 = seg_start + line * t
	return point.distance_to(projection)
