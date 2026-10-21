extends GdUnitTestSuite

class _Target extends Node2D:
	var hits_remaining: int = 2
	var hits: Array = []
	func _init() -> void:
		add_to_group("attackable")
	func on_hit_impact(_p: Vector2, _d: Vector2, dmg: int) -> void:
		hits.append(dmg)
		hits_remaining -= 1

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
	w.resolve_hit(null, t, 3.0)
	assert_int(w.dmg_calls).is_equal(1)
	assert_int(t.hits[0]).is_equal(6)

func test_native_on_kill_fires_once_on_lethal_hit() -> void:
	var w: _NativeWeapon = _NativeWeapon.new()
	var t := _target()
	t.hits_remaining = 1
	w.resolve_hit(null, t, 3.0)
	assert_int(w.killed).is_equal(1)

func test_native_on_kill_does_not_fire_on_nonlethal_hit() -> void:
	var w: _NativeWeapon = _NativeWeapon.new()
	var t := _target()
	t.hits_remaining = 2
	w.resolve_hit(null, t, 3.0)
	assert_int(w.killed).is_equal(0)
