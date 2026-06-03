extends GdUnitTestSuite

const TerrainCollider := preload("res://src/physics/terrain_collider.gd")
const SIZE := 256


func _solid_chunk() -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(SIZE * SIZE)
	data.fill(13)  # any collidable material id
	return data


func _world_bounds(data: PackedByteArray, off: Vector2i) -> Rect2:
	var body := StaticBody2D.new()
	var cs := TerrainCollider.build_collision(data, SIZE, body, off)
	body.free()
	assert_that(cs).is_not_null()
	var segs := (cs.shape as ConcavePolygonShape2D).segments
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for p in segs:
		mn = mn.min(p + Vector2(off))
		mx = mx.max(p + Vector2(off))
	return Rect2(mn, mx - mn)


# A fully-solid chunk must produce collision spanning the whole chunk, not inset
# by a marching-squares cell. Otherwise the wall surface sits inside the rendered
# tile and a gap opens at every chunk border.
func test_solid_chunk_reaches_chunk_edges() -> void:
	var b := _world_bounds(_solid_chunk(), Vector2i.ZERO)
	assert_float(b.position.x).is_equal_approx(0.0, 0.01)
	assert_float(b.position.y).is_equal_approx(0.0, 0.01)
	assert_float(b.size.x).is_equal_approx(float(SIZE), 0.01)
	assert_float(b.size.y).is_equal_approx(float(SIZE), 0.01)


# Two solid chunks sharing a border must tile with no collision seam between them.
func test_adjacent_solid_chunks_have_no_seam() -> void:
	var solid := _solid_chunk()
	var a := _world_bounds(solid, Vector2i(0, 0))
	var right := _world_bounds(solid, Vector2i(SIZE, 0))
	var below := _world_bounds(solid, Vector2i(0, SIZE))
	# Horizontal seam: A's right edge meets B's left edge exactly.
	assert_float(right.position.x - (a.position.x + a.size.x)).is_equal_approx(0.0, 0.01)
	# Vertical seam: A's bottom edge meets C's top edge exactly.
	assert_float(below.position.y - (a.position.y + a.size.y)).is_equal_approx(0.0, 0.01)
