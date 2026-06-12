extends GdUnitTestSuite

const RangedWeaponScript = preload("res://src/weapons/ranged_weapon.gd")

class _FakeShooter extends Node2D:
	var facing := Vector2.RIGHT
	func get_facing_direction() -> Vector2:
		return facing

func _shooter(facing: Vector2) -> _FakeShooter:
	var s: _FakeShooter = auto_free(_FakeShooter.new())
	add_child(s)
	s.facing = facing
	return s

func test_single_shot_emits_one_along_facing() -> void:
	var w := RangedWeaponScript.new()
	var dirs: Array = []
	w.shot_sink = func(d): dirs.append(d)
	w.use(_shooter(Vector2.RIGHT))
	assert_int(dirs.size()).is_equal(1)
	assert_float(dirs[0].angle()).is_equal_approx(0.0, 0.01)

func test_spread_emits_count_shots_at_edges() -> void:
	var w := RangedWeaponScript.new()
	w.projectile_count = 3
	w.spread_angle = 90.0
	var dirs: Array = []
	w.shot_sink = func(d): dirs.append(d)
	w.use(_shooter(Vector2.RIGHT))
	assert_int(dirs.size()).is_equal(3)
	assert_float(dirs[0].angle()).is_equal_approx(deg_to_rad(-45.0), 0.01)
	assert_float(dirs[2].angle()).is_equal_approx(deg_to_rad(45.0), 0.01)

func test_single_shot_weapon_is_not_bursting() -> void:
	var w := RangedWeaponScript.new()
	w.shot_sink = func(_d): pass
	w.use(_shooter(Vector2.RIGHT))
	assert_bool(w.is_bursting()).is_false()

func test_burst_fires_count_shots_over_time() -> void:
	var w := RangedWeaponScript.new()
	w.burst_count = 3
	w.burst_interval = 0.1
	var dirs: Array = []
	w.shot_sink = func(d): dirs.append(d)
	w.use(_shooter(Vector2.RIGHT))
	assert_int(dirs.size()).is_equal(1)
	assert_bool(w.is_bursting()).is_true()
	w.tick(0.1)
	assert_int(dirs.size()).is_equal(2)
	w.tick(0.1)
	assert_int(dirs.size()).is_equal(3)
	assert_bool(w.is_bursting()).is_false()
	w.tick(0.1)
	assert_int(dirs.size()).is_equal(3)

func test_reaim_changes_later_shot_directions() -> void:
	var w := RangedWeaponScript.new()
	w.burst_count = 2
	w.burst_interval = 0.1
	w.reaim_each_shot = true
	var shooter := _shooter(Vector2.RIGHT)
	var dirs: Array = []
	w.shot_sink = func(d): dirs.append(d)
	w.use(shooter)
	shooter.facing = Vector2.UP
	w.tick(0.1)
	assert_float(dirs[0].angle()).is_equal_approx(0.0, 0.01)
	assert_float(dirs[1].angle()).is_equal_approx(Vector2.UP.angle(), 0.01)

func test_no_reaim_keeps_initial_direction() -> void:
	var w := RangedWeaponScript.new()
	w.burst_count = 2
	w.burst_interval = 0.1
	w.reaim_each_shot = false
	var shooter := _shooter(Vector2.RIGHT)
	var dirs: Array = []
	w.shot_sink = func(d): dirs.append(d)
	w.use(shooter)
	shooter.facing = Vector2.UP
	w.tick(0.1)
	assert_float(dirs[1].angle()).is_equal_approx(0.0, 0.01)

func test_burst_ends_if_user_freed() -> void:
	var w := RangedWeaponScript.new()
	w.burst_count = 3
	w.burst_interval = 0.1
	var shooter := _FakeShooter.new()
	add_child(shooter)
	w.shot_sink = func(_d): pass
	w.use(shooter)
	shooter.free()
	w.tick(0.1)
	assert_bool(w.is_bursting()).is_false()