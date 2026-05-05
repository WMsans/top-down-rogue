extends GdUnitTestSuite

func test_projectile_moves_in_direction() -> void:
	var p := auto_free(Projectile.new())
	p.direction = Vector2.RIGHT
	p.speed = 100.0
	p.lifetime = 10.0
	p.global_position = Vector2.ZERO
	p._process(0.1)
	assert_that(p.global_position.x).is_greater(5.0)

func test_projectile_expires() -> void:
	var p := auto_free(Projectile.new())
	p.lifetime = 0.05
	p._process(0.1)
	assert_that(is_instance_valid(p)).is_false()

func test_enemy_projectile_hits_player() -> void:
	var p := auto_free(Projectile.new())
	p.is_enemy_projectile = true
	p.damage = 10.0
	p.direction = Vector2.RIGHT
	var player := Node2D.new()
	player.add_to_group("player", true)
	p._handle_hit(player)
	assert_that(is_instance_valid(p)).is_false()

func test_projectile_ignores_self() -> void:
	var p := auto_free(Projectile.new())
	p.is_enemy_projectile = false
	p.damage = 10.0
	p.source_node = p
	var target := auto_free(Enemy.new())
	p._handle_hit(target)
	assert_that(is_instance_valid(p)).is_true()

func test_projectile_hits_attackable() -> void:
	var p := auto_free(Projectile.new())
	p.is_enemy_projectile = false
	p.damage = 10.0
	p.source_node = null
	var target := auto_free(Enemy.new())
	p._handle_hit(target)
	assert_that(is_instance_valid(p)).is_false()
