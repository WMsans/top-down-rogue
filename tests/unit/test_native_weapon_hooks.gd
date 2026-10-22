extends GdUnitTestSuite

class _Target extends Node2D:
	var hits_remaining: int = 2
	var hit_count: int = 0
	func _init() -> void:
		add_to_group("attackable")
	func on_hit_impact(_p: Vector2, _d: Vector2) -> void:
		hit_count += 1
		hits_remaining -= 1

class _NativeWeapon extends Weapon:
	var killed: int = 0
	func _native_on_kill(_u: Node, _t: Node) -> void:
		killed += 1

func _target() -> _Target:
	var t := _Target.new()
	add_child(t)
	return auto_free(t)

func test_native_on_kill_fires_once_on_lethal_hit() -> void:
	var w: _NativeWeapon = _NativeWeapon.new()
	var t := _target()
	t.hits_remaining = 1
	w.resolve_hit(null, t)
	assert_int(w.killed).is_equal(1)

func test_native_on_kill_does_not_fire_on_nonlethal_hit() -> void:
	var w: _NativeWeapon = _NativeWeapon.new()
	var t := _target()
	t.hits_remaining = 2
	w.resolve_hit(null, t)
	assert_int(w.killed).is_equal(0)
