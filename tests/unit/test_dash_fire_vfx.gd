extends GdUnitTestSuite


func _make_vfx() -> DashFireVfx:
	var v: DashFireVfx = auto_free(DashFireVfx.new())
	add_child(v)
	return v


func test_start_faces_direction_and_offsets_forward() -> void:
	var v := _make_vfx()
	v.start(Vector2.RIGHT)
	assert_float(v.rotation).is_equal_approx(0.0, 0.01)
	assert_float(v.position.x).is_equal_approx(v.offset_distance, 0.01)
	assert_float(v.position.y).is_equal_approx(0.0, 0.01)


func test_start_sets_emitting_true() -> void:
	var v := _make_vfx()
	v.start(Vector2.RIGHT)
	var particles: GPUParticles2D = v.get_node("Particles")
	assert_bool(particles.emitting).is_true()


func test_stop_sets_emitting_false() -> void:
	var v := _make_vfx()
	v.start(Vector2.RIGHT)
	v.stop()
	var particles: GPUParticles2D = v.get_node("Particles")
	assert_bool(particles.emitting).is_false()


func test_start_rotates_to_upward_direction() -> void:
	var v := _make_vfx()
	v.start(Vector2.UP)
	assert_float(v.rotation).is_equal_approx(Vector2.UP.angle(), 0.01)


func test_flame_fill_layer_exists() -> void:
	var v := _make_vfx()
	var flame_fill: CPUParticles2D = v.get_node("FlameFill")
	assert_object(flame_fill).is_not_null()
	assert_int(flame_fill.emission_shape).is_equal(CPUParticles2D.EMISSION_SHAPE_POINTS)


func test_flame_fill_emission_points_are_populated() -> void:
	var v := _make_vfx()
	var flame_fill: CPUParticles2D = v.get_node("FlameFill")
	assert_int(flame_fill.emission_points.size()).is_greater(0)


func test_flame_fill_emission_points_stay_within_bullet_bounds() -> void:
	var v := _make_vfx()
	var flame_fill: CPUParticles2D = v.get_node("FlameFill")
	for pt in flame_fill.emission_points:
		assert_float(absf(pt.x)).is_less_equal(v.body_length * 0.5 + 0.01)
		assert_float(absf(pt.y)).is_less_equal(v.body_width * 0.5 + 0.01)


func test_start_sets_flame_fill_emitting_true() -> void:
	var v := _make_vfx()
	v.start(Vector2.RIGHT)
	var flame_fill: CPUParticles2D = v.get_node("FlameFill")
	assert_bool(flame_fill.emitting).is_true()


func test_stop_sets_flame_fill_emitting_false() -> void:
	var v := _make_vfx()
	v.start(Vector2.RIGHT)
	v.stop()
	var flame_fill: CPUParticles2D = v.get_node("FlameFill")
	assert_bool(flame_fill.emitting).is_false()
