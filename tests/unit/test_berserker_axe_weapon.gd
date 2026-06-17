extends GdUnitTestSuite

const BerserkerAxe = preload("res://src/weapons/berserker_axe_weapon.gd")

class _Inv extends Node:
	var frac: float = 1.0
	func _init() -> void:
		name = "PlayerInventory"
	func get_health_fraction() -> float:
		return frac

func _user_with_hp(frac: float) -> Node2D:
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	var inv: _Inv = _Inv.new()
	inv.frac = frac
	user.add_child(inv)
	return user

func test_full_hp_no_ramp() -> void:
	var w: BerserkerAxe = BerserkerAxe.new()
	var user: Node2D = _user_with_hp(1.0)
	assert_float(w._native_modify_hit_damage(user, null, 10.0)).is_equal_approx(10.0, 0.01)

func test_near_death_max_ramp() -> void:
	var w: BerserkerAxe = BerserkerAxe.new()
	var user: Node2D = _user_with_hp(0.0)
	assert_float(w._native_modify_hit_damage(user, null, 10.0)).is_equal_approx(10.0 * BerserkerAxe.MAX_RAMP, 0.01)

func test_missing_inventory_defaults_to_no_ramp() -> void:
	var w: BerserkerAxe = BerserkerAxe.new()
	var bare: Node2D = auto_free(Node2D.new())
	add_child(bare)
	assert_float(w._native_modify_hit_damage(bare, null, 10.0)).is_equal_approx(10.0, 0.01)
