extends GdUnitTestSuite

const _SectorGrid = preload("res://src/core/sector_grid.gd")

func test_tiers_span_zero_to_two_across_central_area() -> void:
	# Distances 0..WALL_INNER_SECTORS map onto tiers 0,1,2 in order, clamped.
	assert_that(_SectorGrid.enemy_tier_for_distance(0)).is_equal(0)
	assert_that(_SectorGrid.enemy_tier_for_distance(2)).is_equal(0)
	assert_that(_SectorGrid.enemy_tier_for_distance(3)).is_equal(1)
	assert_that(_SectorGrid.enemy_tier_for_distance(5)).is_equal(1)
	assert_that(_SectorGrid.enemy_tier_for_distance(6)).is_equal(2)
	assert_that(_SectorGrid.enemy_tier_for_distance(8)).is_equal(2)

func test_tier_is_clamped() -> void:
	assert_that(_SectorGrid.enemy_tier_for_distance(-1)).is_equal(0)
	assert_that(_SectorGrid.enemy_tier_for_distance(99)).is_equal(2)
