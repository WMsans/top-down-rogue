extends GdUnitTestSuite

const _SectorGrid = preload("res://src/core/sector_grid.gd")
const _BiomeDef = preload("res://src/core/biome_def.gd")
const _ArenaComposition = preload("res://src/core/arena_composition.gd")

# ArenaComposition.nominal_radius — the carved boss-arena radius in px.
const NOMINAL_RADIUS := 960.0
# Outer ring distance; scan/march bound. Equals SectorGrid.BOSS_WORLD_EDGE post-Task-2.
const EDGE := 12

func _biome() -> Resource:
	var b := _BiomeDef.new()
	var comp := _ArenaComposition.new()
	comp.arena_kind = &"boss"
	b.boss_compositions = [comp]
	return b

func _anchor_world_positions(grid) -> Array:
	var pts: Array = []
	for x in range(-EDGE, EDGE + 1):
		for y in range(-EDGE, EDGE + 1):
			if _SectorGrid.is_boss_anchor(Vector2i(x, y)):
				pts.append(Vector2(grid.sector_to_world_center(Vector2i(x, y))))
	return pts

func test_every_radial_direction_crosses_a_boss_arena() -> void:
	var grid := _SectorGrid.new(0, _biome())
	var anchors := _anchor_world_positions(grid)
	assert_that(anchors.size() > 0).is_true()
	var src := Vector2(grid.sector_to_world_center(Vector2i.ZERO))
	# Far enough to reach the corner of the d=12 square (12*384*sqrt2 ~= 6519).
	var edge_dist := float(EDGE) * _SectorGrid.SECTOR_SIZE_PX * 1.5
	var rays := 3600
	var uncovered := 0
	for i in range(rays):
		var a := TAU * float(i) / float(rays)
		var dir := Vector2(cos(a), sin(a))
		var covered := false
		for p in anchors:
			var q: Vector2 = p - src
			var proj := q.dot(dir)
			if proj < 0.0 or proj > edge_dist:
				continue  # behind the ray or past the world edge
			var perp := absf(q.x * dir.y - q.y * dir.x)  # dist anchor->ray line
			if perp < NOMINAL_RADIUS:
				covered = true
				break
		if not covered:
			uncovered += 1
	assert_that(uncovered).is_equal(0)
