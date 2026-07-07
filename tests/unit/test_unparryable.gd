extends GdUnitTestSuite

class TestParryTarget extends Area2D:
	var hit_received: bool = false
	var _should_parry: bool = true

	func _init() -> void:
		collision_layer = 1 << 7
		var shape := CircleShape2D.new()
		shape.radius = 20.0
		var cs := CollisionShape2D.new()
		cs.shape = shape
		add_child(cs)

	func try_parry(_attacker: Node, _hit_pos: Vector2, _hit_dir: Vector2) -> bool:
		return _should_parry

	func on_hit_impact(_impact_point: Vector2, _hit_dir: Vector2, _damage: int) -> void:
		hit_received = true


func test_parry_skips_damage() -> void:
	var target: TestParryTarget = auto_free(TestParryTarget.new())
	target._should_parry = true
	add_child(target)
	await get_tree().process_frame

	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	await get_tree().process_frame
	target.global_position = user.global_position + Vector2(0, 10)

	var w := MeleeWeapon.new()
	w.weapon_reach = 36.0
	w.damage = 10.0
	w._hit_attackables(user, user.global_position, Vector2.DOWN, w.weapon_reach, w.arc_angle, 1.0, false, false)

	assert_that(target.hit_received).is_false()


func test_unparryable_applies_damage() -> void:
	var target: TestParryTarget = auto_free(TestParryTarget.new())
	target._should_parry = false
	add_child(target)
	await get_tree().process_frame

	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	await get_tree().process_frame
	target.global_position = user.global_position + Vector2(0, 10)

	var w := MeleeWeapon.new()
	w.weapon_reach = 36.0
	w.damage = 10.0
	w._hit_attackables(user, user.global_position, Vector2.DOWN, w.weapon_reach, w.arc_angle, 1.0, false, false)

	assert_that(target.hit_received).is_true()
