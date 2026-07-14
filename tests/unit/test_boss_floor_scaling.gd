extends GdUnitTestSuite

class ScalableBoss extends BossEnemy:
	func _ready() -> void:
		pass


func test_scaling_floor_3_applies_multipliers() -> void:
	var b : ScalableBoss = auto_free(ScalableBoss.new())
	b.max_health = 100
	b.speed = 50.0
	var w_resource := RangedWeapon.new()
	w_resource.damage = 10.0
	var w_instance := RangedWeapon.new()
	w_instance.damage = 10.0
	b.weapon_resource = w_resource
	b.weapon = w_instance
	b._apply_floor_scaling(3)
	# 100 * (1 + 2*0.20) = 140
	assert_int(b.max_health).is_equal(140)
	# 50 * (1 + 2*0.10) = 60
	assert_float(b.speed).is_equal_approx(60.0, 0.001)
	# 10 * (1 + 2*0.15) = 13
	assert_float(w_instance.damage).is_equal_approx(13.0, 0.001)


func test_scaling_floor_1_is_noop() -> void:
	var b : ScalableBoss = auto_free(ScalableBoss.new())
	b.max_health = 100
	b.speed = 50.0
	b._apply_floor_scaling(1)
	assert_int(b.max_health).is_equal(100)
	assert_float(b.speed).is_equal_approx(50.0, 0.001)