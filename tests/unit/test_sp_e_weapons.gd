extends GdUnitTestSuite

func test_heavy_crossbow_pierces_enemies() -> void:
	var w := HeavyCrossbowWeapon.new()
	var b: Array = w._make_behaviors()
	assert_int(b.size()).is_equal(1)
	assert_bool(b[0] is PenetrateBehavior).is_true()
	# PenetrateBehavior keeps the projectile alive through an enemy.
	var p: Projectile = auto_free(Projectile.new())
	p.is_enemy_projectile = false
	p.damage = 5.0
	p.behaviors = [b[0]]
	p._handle_hit(auto_free(Enemy.new()))
	assert_bool(is_instance_valid(p)).is_true()

func test_chakram_returns() -> void:
	var b: Array = ChakramLauncherWeapon.new()._make_behaviors()
	assert_int(b.size()).is_equal(1)
	assert_bool(b[0] is ReturnBehavior).is_true()

func test_seeker_homes() -> void:
	var b: Array = SeekerLauncherWeapon.new()._make_behaviors()
	assert_int(b.size()).is_equal(1)
	assert_bool(b[0] is HomingBehavior).is_true()
