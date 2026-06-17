extends GdUnitTestSuite

const MirrorBlade = preload("res://src/weapons/mirror_blade_weapon.gd")

func test_enemy_projectile_in_arc_is_reflected_not_freed() -> void:
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	user.global_position = Vector2.ZERO
	var proj: Projectile = Projectile.new()
	proj.is_enemy_projectile = true
	proj.direction = Vector2.LEFT
	add_child(proj)
	proj.global_position = Vector2(10, 0)
	var w: MirrorBlade = MirrorBlade.new()
	await get_tree().physics_frame
	w._destroy_projectiles_in_arc(user, Vector2.ZERO, Vector2.RIGHT)
	assert_bool(is_instance_valid(proj)).is_true()
	assert_bool(proj.is_enemy_projectile).is_false()
	assert_float(proj.direction.x).is_greater(0.0)
	assert_object(proj.source_weapon).is_same(w)
	proj.queue_free()
