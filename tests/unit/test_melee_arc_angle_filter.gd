extends GdUnitTestSuite

func test_target_in_front_within_reach_passes() -> void:
	assert_bool(MeleeWeapon._is_inside_arc(Vector2.ZERO, Vector2(10, 0), 0.0, PI / 4, 16.0)).is_true()

func test_target_outside_reach_fails() -> void:
	assert_bool(MeleeWeapon._is_inside_arc(Vector2.ZERO, Vector2(20, 0), 0.0, PI / 4, 16.0)).is_false()

func test_target_behind_fails() -> void:
	assert_bool(MeleeWeapon._is_inside_arc(Vector2.ZERO, Vector2(-10, 0), 0.0, PI / 4, 16.0)).is_false()

func test_target_at_arc_edge_passes() -> void:
	var t := Vector2.from_angle(deg_to_rad(44.0)) * 10.0
	assert_bool(MeleeWeapon._is_inside_arc(Vector2.ZERO, t, 0.0, deg_to_rad(45.0), 16.0)).is_true()

func test_zero_distance_fails() -> void:
	assert_bool(MeleeWeapon._is_inside_arc(Vector2.ZERO, Vector2.ZERO, 0.0, PI / 4, 16.0)).is_false()
