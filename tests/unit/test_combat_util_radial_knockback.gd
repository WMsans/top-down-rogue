extends GdUnitTestSuite

const CombatUtilScript = preload("res://src/weapons/combat_util.gd")

class _Foe extends Node2D:
	var last_dir: Vector2 = Vector2.ZERO
	var last_strength: float = -1.0
	func _init() -> void:
		add_to_group("attackable")
	func apply_knockback(direction: Vector2, strength: float) -> void:
		last_dir = direction
		last_strength = strength


func test_knocks_back_targets_inside_radius_away_from_source() -> void:
	var src: Node2D = auto_free(Node2D.new())
	add_child(src)
	src.global_position = Vector2.ZERO
	var near := _Foe.new()
	src.add_child(near)
	near.global_position = Vector2(10, 0)
	var far := _Foe.new()
	src.add_child(far)
	far.global_position = Vector2(500, 0)
	CombatUtilScript.radial_knockback(src, 50.0, 120.0)
	assert_float(near.last_strength).is_equal_approx(120.0, 0.001)
	assert_float(near.last_dir.x).is_greater(0.0)   # pushed away from source (+x)
	assert_float(far.last_strength).is_equal(-1.0)   # outside radius, untouched
