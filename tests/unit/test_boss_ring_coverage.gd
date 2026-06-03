extends GdUnitTestSuite

const _SectorGrid = preload("res://src/core/sector_grid.gd")

# Walk the d=8 square perimeter (the inner wall face) clockwise and collect the
# anchor positions along it, so we can measure spacing between chamber openings.
func _perimeter_anchor_steps() -> Array:
	var d := _SectorGrid.WALL_INNER_SECTORS
	var ring: Array = []
	# Top edge L->R, right edge T->B, bottom edge R->L, left edge B->T (no corner dupes).
	for x in range(-d, d):        ring.append(Vector2i(x, -d))
	for y in range(-d, d):        ring.append(Vector2i(d, y))
	for x in range(d, -d, -1):    ring.append(Vector2i(x, d))
	for y in range(d, -d, -1):    ring.append(Vector2i(-d, y))
	var steps: Array = []
	for i in range(ring.size()):
		if _SectorGrid.is_boss_anchor(ring[i]):
			steps.append(i)
	return steps

func test_anchor_count_matches_constant() -> void:
	assert_that(_perimeter_anchor_steps().size()).is_equal(_SectorGrid.BOSS_RING_ANCHOR_COUNT)

func test_no_long_blank_wall_between_chambers() -> void:
	var steps := _perimeter_anchor_steps()
	assert_that(steps.size() > 0).is_true()
	var perim := 8 * _SectorGrid.WALL_INNER_SECTORS  # 64 sectors around the d=8 ring
	var max_gap := 0
	for i in range(steps.size()):
		var a: int = steps[i]
		var b: int = steps[(i + 1) % steps.size()]
		var gap: int = b - a if (i + 1) < steps.size() else (b + perim - a)
		max_gap = max(max_gap, gap)
	# 12 anchors over 64 perimeter sectors => avg ~5.3; no gap may exceed 8 sectors
	# (~3072px of wall) so the player always meets the next chamber quickly.
	assert_that(max_gap).is_less_equal(8)

func test_all_anchors_on_wall_face() -> void:
	for x in range(-_SectorGrid.WALL_INNER_SECTORS, _SectorGrid.WALL_INNER_SECTORS + 1):
		for y in range(-_SectorGrid.WALL_INNER_SECTORS, _SectorGrid.WALL_INNER_SECTORS + 1):
			if _SectorGrid.is_boss_anchor(Vector2i(x, y)):
				assert_that(max(abs(x), abs(y))).is_equal(_SectorGrid.WALL_INNER_SECTORS)
