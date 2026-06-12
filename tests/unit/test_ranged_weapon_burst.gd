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