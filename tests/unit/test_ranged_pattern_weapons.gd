extends GdUnitTestSuite

class _FakeShooter extends Node2D:
	var facing := Vector2.RIGHT
	func get_facing_direction() -> Vector2:
		return facing

func _shooter(facing: Vector2) -> _FakeShooter:
	var s: _FakeShooter = auto_free(_FakeShooter.new())
	add_child(s)
	s.facing = facing
	return s

func test_aimed_burst_defaults() -> void:
	var w := AimedBurstWeapon.new()
	assert_int(w.burst_count).is_equal(3)
	assert_bool(w.reaim_each_shot).is_true()
	assert_int(w.projectile_count).is_equal(1)

func test_aimed_burst_fires_three_aimed_shots() -> void:
	var w := AimedBurstWeapon.new()
	w.burst_interval = 0.1
	var dirs: Array = []
	w.shot_sink = func(d): dirs.append(d)
	w.use(_shooter(Vector2.RIGHT))
	w.tick(0.1)
	w.tick(0.1)
	assert_int(dirs.size()).is_equal(3)
	for d in dirs:
		assert_float(d.angle()).is_equal_approx(0.0, 0.01)

func test_split_defaults() -> void:
	var w := SplitShotWeapon.new()
	assert_int(w.projectile_count).is_equal(2)
	assert_bool(w.reaim_each_shot).is_true()

func test_split_emits_two_diverging_with_gap() -> void:
	var w := SplitShotWeapon.new()
	w.spread_angle = 30.0
	var dirs: Array = []
	w.shot_sink = func(d): dirs.append(d)
	w.use(_shooter(Vector2.RIGHT))
	assert_int(dirs.size()).is_equal(2)
	assert_float(dirs[0].angle()).is_equal_approx(deg_to_rad(-15.0), 0.01)
	assert_float(dirs[1].angle()).is_equal_approx(deg_to_rad(15.0), 0.01)
	for d in dirs:
		assert_bool(abs(d.angle()) < 0.01).is_false()

func test_fan_emits_center_plus_two_spread() -> void:
	var w := FanWeapon.new()
	w.spread_angle = 40.0
	var dirs: Array = []
	w.shot_sink = func(d): dirs.append(d)
	w.use(_shooter(Vector2.RIGHT))
	assert_int(dirs.size()).is_equal(3)
	assert_float(dirs[0].angle()).is_equal_approx(deg_to_rad(-20.0), 0.01)
	assert_float(dirs[1].angle()).is_equal_approx(0.0, 0.01)
	assert_float(dirs[2].angle()).is_equal_approx(deg_to_rad(20.0), 0.01)