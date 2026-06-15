extends GdUnitTestSuite

class _Target extends Area2D:
	var health: float = 100.0
	var hits: Array = []
	func _init() -> void:
		add_to_group("attackable")
		set_collision_layer_value(8, true)
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)
		var col := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 4.0
		col.shape = shape
		add_child(col)
	func on_hit_impact(_p: Vector2, _d: Vector2, dmg: int) -> void:
		hits.append(dmg)
		health -= dmg

class _EdgeMod extends Modifier:
	func on_hit_target(_w: Weapon, _u: Node, t: Node) -> void:
		t.get_node("StatusComponent").add_stain("on_fire", 2.0)

func test_melee_swing_routes_through_resolve_hit_and_applies_edge() -> void:
	var parent: Area2D = auto_free(Area2D.new())
	add_child(parent)
	var user := Node2D.new()
	parent.add_child(user)
	user.global_position = Vector2.ZERO
	var target := _Target.new()
	parent.add_child(target)
	target.global_position = Vector2(10, 0)
	var w := MeleeWeapon.new()
	w.weapon_reach = 30.0
	w.arc_angle = PI
	w.damage = 5.0
	w.crit_chance = 0.0
	w.modifiers = [_EdgeMod.new(), null, null]
	await get_tree().physics_frame
	w._hit_attackables(user, Vector2.ZERO, Vector2.RIGHT, 30.0, PI, 1.0, false, true)
	assert_int(target.hits.size()).is_equal(1)
	assert_that(target.get_node("StatusComponent").get_stain("on_fire")).is_greater(0.0)
