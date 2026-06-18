extends GdUnitTestSuite

const SniperPenetration = preload("res://src/weapons/sniper_penetration_behavior.gd")

func test_penetration_keeps_alive_while_budget_remains() -> void:
	var b = SniperPenetration.new()
	b.pierces = 2
	var proj: Projectile = auto_free(Projectile.new())
	assert_bool(b.on_terrain_hit(proj)).is_true()
	assert_bool(b.on_terrain_hit(proj)).is_true()
	assert_bool(b.on_terrain_hit(proj)).is_false()

func test_enemy_projectile_with_keep_behavior_survives_terrain() -> void:
	var b = SniperPenetration.new()
	b.pierces = 1
	var proj: Projectile = auto_free(Projectile.new())
	proj.is_enemy_projectile = true
	proj.behaviors = [b]
	proj.solidity_oracle = func(_p): return false
	add_child(proj)
	var wall: StaticBody2D = auto_free(StaticBody2D.new())
	add_child(wall)
	proj._handle_hit(wall)
	assert_bool(is_instance_valid(proj)).is_true()