extends GdUnitTestSuite

func _make_user() -> Node2D:
	var n: Node2D = auto_free(Node2D.new())
	add_child(n)
	return n

func _setup_weapon(w: MeleeWeapon) -> void:
	var container: Node2D = auto_free(Node2D.new())
	container.name = "WeaponVisual"
	var sprite: Sprite2D = auto_free(Sprite2D.new())
	sprite.name = "Sprite2D"
	container.add_child(sprite)
	w.setup_visual(container, sprite)

func test_enemy_projectile_in_arc_is_destroyed_during_swing() -> void:
	var w: MeleeWeapon = auto_free(MeleeWeapon.new())
	_setup_weapon(w)
	var user: Node2D = _make_user()
	user.global_position = Vector2.ZERO
	# Spawn an enemy projectile directly in front (DOWN is default facing)
	var p: Projectile = auto_free(Projectile.new())
	p.is_enemy_projectile = true
	p.direction = Vector2.LEFT
	add_child(p)
	p.global_position = Vector2(0, 10)  # in front of DOWN-facing user, within reach

	w.use(user)
	w.update_visual(0.02, user)  # one swing tick within active phase
	await get_tree().process_frame
	assert_that(is_instance_valid(p)).is_false()

func test_player_projectile_is_ignored() -> void:
	var w: MeleeWeapon = auto_free(MeleeWeapon.new())
	_setup_weapon(w)
	var user: Node2D = _make_user()
	user.global_position = Vector2.ZERO
	var p: Projectile = auto_free(Projectile.new())
	p.is_enemy_projectile = false
	p.direction = Vector2.LEFT
	add_child(p)
	p.global_position = Vector2(0, 10)

	w.use(user)
	w.update_visual(0.02, user)
	assert_that(is_instance_valid(p)).is_true()

func test_projectile_outside_arc_survives() -> void:
	var w: MeleeWeapon = auto_free(MeleeWeapon.new())
	_setup_weapon(w)
	var user: Node2D = _make_user()
	user.global_position = Vector2.ZERO
	var p: Projectile = auto_free(Projectile.new())
	p.is_enemy_projectile = true
	p.direction = Vector2.LEFT
	add_child(p)
	# User default-facing is DOWN; (-30, 0) is ~90° from DOWN, outside PI/4 half-arc
	p.global_position = Vector2(-30, 0)

	w.use(user)
	w.update_visual(0.02, user)
	assert_that(is_instance_valid(p)).is_true()
