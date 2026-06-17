extends GdUnitTestSuite

class _Target extends Node2D:
	var health: float = 10.0
	func _init() -> void:
		add_to_group("attackable")
	func on_hit_impact(_p: Vector2, _d: Vector2, dmg: int) -> void:
		health -= dmg

class _NativeWeapon extends Weapon:
	var killed: int = 0
	var dmg_calls: int = 0
	func _native_modify_hit_damage(_u: Node, _t: Node, dmg: float) -> float:
		dmg_calls += 1
		return dmg * 2.0
	func _native_on_kill(_u: Node, _t: Node) -> void:
		killed += 1

func _target() -> _Target:
	var t := _Target.new()
	add_child(t)
	return auto_free(t)

func test_native_modify_hit_damage_folds_into_resolve_hit() -> void:
	var w: _NativeWeapon = _NativeWeapon.new()
	var t := _target()
	w.resolve_hit(null, t, 3.0, false)
	assert_int(w.dmg_calls).is_equal(1)
	assert_float(t.health).is_equal_approx(4.0, 0.001)

func test_native_on_kill_fires_once_on_lethal_hit() -> void:
	var w: _NativeWeapon = _NativeWeapon.new()
	var t := _target()
	t.health = 4.0
	w.resolve_hit(null, t, 3.0, false)
	assert_int(w.killed).is_equal(1)

func test_native_on_kill_does_not_fire_on_nonlethal_hit() -> void:
	var w: _NativeWeapon = _NativeWeapon.new()
	var t := _target()
	t.health = 100.0
	w.resolve_hit(null, t, 3.0, false)
	assert_int(w.killed).is_equal(0)
