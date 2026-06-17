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

func test_arc_railgun_is_charged_and_pierces() -> void:
	var w := ArcRailgunWeapon.new()
	assert_bool(w is ChargedRangedWeapon).is_true()
	assert_bool(w.is_chargeable()).is_true()
	var b: Array = w._make_behaviors()
	assert_int(b.size()).is_equal(1)
	assert_bool(b[0] is PenetrateBehavior).is_true()

func test_arc_railgun_only_fires_at_full_charge() -> void:
	var shots: Array = []
	var w := ArcRailgunWeapon.new()
	w.charge_time_full = 0.5
	w.shot_sink = func(_dir): shots.append(1)
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	w.on_press(user)
	w.tick(0.1)
	w.on_release(user)   # partial -> nothing
	assert_int(shots.size()).is_equal(0)
	w.on_press(user)
	w.tick(0.6)
	w.on_release(user)   # full -> one rail
	assert_int(shots.size()).is_equal(1)
