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
	var particles: CPUParticles2D = v.get_node("Particles")
	assert_bool(particles.emitting).is_true()


func test_stop_sets_emitting_false() -> void:
	var v := _make_vfx()
	v.start(Vector2.RIGHT)
	v.stop()
	var particles: CPUParticles2D = v.get_node("Particles")
	assert_bool(particles.emitting).is_false()


func test_start_rotates_to_upward_direction() -> void:
	var v := _make_vfx()
	v.start(Vector2.UP)
	assert_float(v.rotation).is_equal_approx(Vector2.UP.angle(), 0.01)
