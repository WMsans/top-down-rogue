extends GdUnitTestSuite

class _HitCounter extends Modifier:
	var on_hit_calls: int = 0
	func _init() -> void:
		category = "trigger"
	func on_hit_target(_w, _u, _t) -> void:
		on_hit_calls += 1


class _HpTarget extends Node2D:
	var health: float
	var max_health: float
	func _init(h: float = 100.0) -> void:
		health = h
		max_health = h
		add_to_group("attackable")
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)


func test_pendulum_alternates_left_right() -> void:
	var w := Weapon.new()
	var left := _HitCounter.new()
	var pend := PendulumModifier.new()
	var right := _HitCounter.new()
	w.add_modifier(0, left); w.add_modifier(1, pend); w.add_modifier(2, right)
	var ctx := {"direction": Vector2.RIGHT, "origin": Vector2.ZERO, "charged": false, "charge_ratio": 0.0}
	var t := Node.new()
	w.notify_attack(null, ctx); w.resolve_hit(null, t)
	assert_int(left.on_hit_calls).is_equal(2)
	assert_int(right.on_hit_calls).is_equal(1)
	w.notify_attack(null, ctx); w.resolve_hit(null, t)
	assert_int(left.on_hit_calls).is_equal(3)
	assert_int(right.on_hit_calls).is_equal(3)


func test_headsman_refunds_half_the_swing_cooldown_on_kill() -> void:
	var w := Weapon.new()
	w.cooldown = 0.5
	w._cooldown_timer = 0.5
	var m := HeadsmanModifier.new()
	w.add_modifier(0, m)
	var t := _HpTarget.new(100.0)
	add_child(t)
	m.on_kill(w, null, t)
	assert_float(w._cooldown_timer).is_equal(0.25)



