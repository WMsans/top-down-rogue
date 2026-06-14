extends GdUnitTestSuite

# Verifies _move_with_clamp keeps the enemy body out of solid terrain even at
# knockback speeds (no embedding, no tunneling through thin walls), and that
# enemies register as fluid interactors.

class StubNavField:
	# Solid everywhere at world x >= wall_x. wall_x defaults far away (open).
	var wall_x: float = 1.0e9
	# Optional thin solid band [band_min, band_max) on the x axis.
	var band_min: float = 1.0e9
	var band_max: float = 1.0e9
	func is_solid_world(pos: Vector2) -> bool:
		if pos.x >= wall_x:
			return true
		return pos.x >= band_min and pos.x < band_max

class StubWorldManager extends Node:
	var nav_field: StubNavField = StubNavField.new()


func _make_enemy(nav: StubNavField) -> Enemy:
	var e: Enemy = auto_free(Enemy.new())
	var wm: StubWorldManager = auto_free(StubWorldManager.new())
	wm.nav_field = nav
	e._world_manager = wm
	e._body_radius = 8.0
	return e


func test_knockback_stops_at_wall_edge() -> void:
	var nav := StubNavField.new()
	nav.wall_x = 100.0
	var e := _make_enemy(nav)
	e.global_position = Vector2.ZERO
	# Fast rightward knockback that would overshoot the wall in one frame.
	e.velocity = Vector2(180.0, 0.0)
	e._move_with_clamp(1.0)
	# Leading edge (centre + body_radius) must not enter the solid cell.
	assert_that(e.global_position.x + e._body_radius).is_less_equal(100.0)


func test_no_tunneling_through_thin_wall() -> void:
	var nav := StubNavField.new()
	# One-cell-thick solid band; without sub-stepping a fast step jumps past it.
	nav.band_min = 50.0
	nav.band_max = 58.0
	var e := _make_enemy(nav)
	e.global_position = Vector2.ZERO
	e.velocity = Vector2(600.0, 0.0)
	e._move_with_clamp(1.0)
	# Must remain on the near side of the band, not teleported past it.
	assert_that(e.global_position.x + e._body_radius).is_less_equal(50.0)


func test_blocked_axis_does_not_halt_perpendicular_motion() -> void:
	var nav := StubNavField.new()
	nav.wall_x = 50.0
	var e := _make_enemy(nav)
	e.global_position = Vector2.ZERO
	# Moving into the wall (x) while also sliding along it (y).
	e.velocity = Vector2(180.0, 120.0)
	e._move_with_clamp(1.0)
	assert_that(e.global_position.x + e._body_radius).is_less_equal(50.0)
	assert_that(e.global_position.y).is_greater(0.0)


func test_open_motion_is_unobstructed() -> void:
	var nav := StubNavField.new()  # no wall
	var e := _make_enemy(nav)
	e.global_position = Vector2.ZERO
	e.velocity = Vector2(60.0, 0.0)
	e._move_with_clamp(0.5)
	assert_float(e.global_position.x).is_equal_approx(30.0, 0.001)


func test_enemy_joins_gas_interactors_group() -> void:
	var e: Enemy = auto_free(Enemy.new())
	add_child(e)  # triggers _ready
	assert_bool(e.is_in_group("gas_interactors")).is_true()
