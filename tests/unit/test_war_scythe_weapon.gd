extends GdUnitTestSuite

const WarScythe = preload("res://src/weapons/war_scythe_weapon.gd")

class _Target extends Area2D:
	var hits: Array = []
	var health: float = 100.0
	func _init() -> void:
		add_to_group("attackable")
		set_collision_layer_value(8, true)
		var col := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 4.0
		col.shape = shape
		add_child(col)
	func on_hit_impact(_p: Vector2, _d: Vector2, dmg: int) -> void:
		hits.append(dmg)

func test_arc_is_300_degrees() -> void:
	var w := WarScythe.new()
	assert_float(rad_to_deg(w.arc_angle)).is_equal_approx(300.0, 0.5)

func test_hits_rear_flank_but_not_directly_behind() -> void:
	var parent: Area2D = auto_free(Area2D.new())
	add_child(parent)
	var user := Node2D.new()
	parent.add_child(user)
	user.global_position = Vector2.ZERO
	# Facing +x. Rear-flank target at 150-ish deg (within 300 arc).
	var flank := _Target.new()
	parent.add_child(flank)
	flank.global_position = Vector2(-8.66, 5.0)   # ~150 deg, dist 10
	# Directly-behind target at 180 deg (in the ~60 deg blind spot).
	var behind := _Target.new()
	parent.add_child(behind)
	behind.global_position = Vector2(-10.0, 0.0)
	var w := WarScythe.new()
	w.crit_chance = 0.0
	await get_tree().physics_frame
	w._hit_attackables(user, Vector2.ZERO, Vector2.RIGHT, w.weapon_reach, w.arc_angle, 1.0, false, true)
	assert_int(flank.hits.size()).is_equal(1)
	assert_int(behind.hits.size()).is_equal(0)
