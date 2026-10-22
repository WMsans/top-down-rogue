extends GdUnitTestSuite

class _StatusTarget extends Node2D:
	var hits: Array = []
	func _init() -> void:
		add_to_group("attackable")
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)
	func on_hit_impact(_p: Vector2, _d: Vector2) -> void:
		hits.append(1)


class _HpTarget extends Node2D:
	var hits_remaining: int = 2
	var impacts: Array = []
	func _init(_hp: float = 100.0) -> void:
		add_to_group("attackable")
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)
	func on_hit_impact(_p: Vector2, _d: Vector2) -> void:
		hits_remaining -= 1
		impacts.append(1)


class _HitCounter extends Modifier:
	var on_hit_calls: int = 0
	func _init() -> void:
		category = "trigger"
	func on_hit_target(_w, _u, _t) -> void:
		on_hit_calls += 1


class _ChainRetrigger extends Modifier:
	func _init() -> void:
		category = "trigger"
		is_retrigger_modifier = true
	func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
		var first: Modifier = weapon.get_first_modifier()
		weapon.retrigger_modifier(first, "on_hit_target", [user, target])


class _LocalChain extends Modifier:
	func _init() -> void:
		category = "trigger"
		is_retrigger_modifier = true
	func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
		var first: Modifier = weapon.get_first_modifier()
		weapon.retrigger_modifier(first, "on_hit_target", [user, target])


func test_flagship_echo_strike_retiggers_the_first_modifier_once() -> void:
	var user := _StatusTarget.new()
	add_child(user)
	user.global_position = Vector2.ZERO
	var w := Weapon.new()
	var counter := _HitCounter.new()
	var echo := EchoStrikeModifier.new()
	w.add_modifier(0, counter); w.add_modifier(1, echo)
	var t := _HpTarget.new(1000.0)
	add_child(t)
	t.global_position = Vector2(30, 0)
	w.resolve_hit(user, t)
	# the echo retriggers the first modifier, but the swing itself is one hit
	assert_int(counter.on_hit_calls).is_equal(2)
	assert_int(t.impacts.size()).is_equal(1)


func test_depth_guard_prevents_infinite_retrigger_chain() -> void:
	var w := Weapon.new()
	var c := _HitCounter.new()
	var r1 := _ChainRetrigger.new()
	var r2 := _LocalChain.new()
	w.add_modifier(0, c); w.add_modifier(1, r1); w.add_modifier(2, r2)
	var t := Node.new()
	w.resolve_hit(null, t)
	assert_bool(c.on_hit_calls <= 5).is_true()
