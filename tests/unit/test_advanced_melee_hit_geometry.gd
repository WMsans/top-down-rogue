extends GdUnitTestSuite

# A full-circle arc (spin) must include targets behind the origin.
func test_full_circle_arc_includes_behind() -> void:
	assert_bool(MeleeWeapon._is_inside_arc(Vector2.ZERO, Vector2(-10, 0), 0.0, PI, 16.0)).is_true()

# A narrow thrust arc must reject a flank target.
func test_narrow_arc_rejects_flank() -> void:
	var flank := Vector2.from_angle(deg_to_rad(60.0)) * 10.0
	assert_bool(MeleeWeapon._is_inside_arc(Vector2.ZERO, flank, 0.0, deg_to_rad(12.0), 16.0)).is_false()

# A narrow thrust arc accepts a directly-forward target within reach.
func test_narrow_arc_accepts_forward() -> void:
	assert_bool(MeleeWeapon._is_inside_arc(Vector2.ZERO, Vector2(14, 0), 0.0, deg_to_rad(12.0), 16.0)).is_true()
