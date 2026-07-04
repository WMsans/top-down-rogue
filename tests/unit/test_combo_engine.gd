extends GdUnitTestSuite

class _HitCounter extends Modifier:
	var on_hit_calls: int = 0
	var dmg_seen: float = 0.0
	func _init() -> void:
		category = "trigger"
	func on_hit_target(_w, _u, _t) -> void:
		on_hit_calls += 1
	func modify_hit_damage(_w, _u, _t, dmg: float) -> float:
		dmg_seen = dmg
		return dmg


class _ChainRetrigger extends Modifier:
	func _init() -> void:
		category = "trigger"
		is_retrigger_modifier = true
	func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
		var first: Modifier = weapon.get_first_modifier()
		weapon.retrigger_modifier(first, "on_hit_target", [user, target])


func test_echo_strike_retriggers_first_slot_once() -> void:
	var w := Weapon.new()
	var first := _HitCounter.new()
	var echo := EchoStrikeModifier.new()
	w.add_modifier(0, first); w.add_modifier(1, echo)
	var t := Node.new()
	w.resolve_hit(null, t, 10.0, false)
	assert_int(first.on_hit_calls).is_equal(2)


func test_echo_strike_no_op_when_first_is_self() -> void:
	var w := Weapon.new()
	var echo := EchoStrikeModifier.new()
	w.add_modifier(0, echo)
	var t := Node.new()
	w.resolve_hit(null, t, 10.0, false)
	assert_bool(true).is_true()


func test_overclock_retriggers_left_then_disables_five_seconds() -> void:
	var w := Weapon.new()
	var left := _HitCounter.new()
	var oc := OverclockModifier.new()
	w.add_modifier(0, left); w.add_modifier(1, oc)
	var t := Node.new()
	w.resolve_hit(null, t, 10.0, false)
	assert_int(left.on_hit_calls).is_equal(2)
	assert_bool(left.is_disabled).is_true()
	w.resolve_hit(null, t, 10.0, false)
	assert_int(left.on_hit_calls).is_equal(2)
	w.tick(5.01)
	assert_bool(left.is_disabled).is_false()
	w.resolve_hit(null, t, 10.0, false)
	assert_int(left.on_hit_calls).is_equal(4)


func test_mirror_slot_delegates_to_left() -> void:
	var w := Weapon.new()
	var left := _HitCounter.new()
	var mirror := MirrorSlotModifier.new()
	w.add_modifier(0, left); w.add_modifier(1, mirror)
	var t := Node.new()
	w.resolve_hit(null, t, 10.0, false)
	assert_int(left.on_hit_calls).is_equal(2)


func test_mirror_slot_copying_mirror_is_noop() -> void:
	var w := Weapon.new()
	var m1 := MirrorSlotModifier.new()
	var m2 := MirrorSlotModifier.new()
	w.add_modifier(0, m1); w.add_modifier(1, m2)
	var t := Node.new()
	w.resolve_hit(null, t, 10.0, false)
	assert_bool(true).is_true()


func test_catalyst_bond_links_slots_zero_and_two() -> void:
	var w := Weapon.new()
	var s0 := _HitCounter.new()
	var bond := CatalystBondModifier.new()
	var s2 := _HitCounter.new()
	w.add_modifier(0, s0); w.add_modifier(1, bond); w.add_modifier(2, s2)
	var t := Node.new()
	w.resolve_hit(null, t, 10.0, false)
	assert_int(s0.on_hit_calls).is_equal(2)
	assert_int(s2.on_hit_calls).is_equal(2)


func test_keystone_disables_outer_slots_and_doubles_damage() -> void:
	var w := Weapon.new()
	w.damage = 10.0
	var s0 := _HitCounter.new()
	var ks := KeystoneModifier.new()
	var s2 := _HitCounter.new()
	w.add_modifier(0, s0); w.add_modifier(1, ks); w.add_modifier(2, s2)
	var t := Node.new()
	w.resolve_hit(null, t, 10.0, false)
	assert_int(s0.on_hit_calls).is_equal(0)
	assert_int(s2.on_hit_calls).is_equal(0)
	assert_float(w.get_effective_stats()["damage"]).is_equal(20.0)


func test_keystone_without_keystone_is_normal() -> void:
	var w := Weapon.new()
	w.damage = 10.0
	var s0 := _HitCounter.new()
	w.add_modifier(0, s0)
	assert_float(w.get_effective_stats()["damage"]).is_equal(10.0)


func test_twin_trigger_doubles_all_on_third_swing() -> void:
	var w := Weapon.new()
	var a := _HitCounter.new()
	var tt := TwinTriggerModifier.new()
	var b := _HitCounter.new()
	w.add_modifier(0, a); w.add_modifier(1, tt); w.add_modifier(2, b)
	var ctx := {"direction": Vector2.RIGHT, "origin": Vector2.ZERO, "charged": false, "charge_ratio": 0.0}
	var t := Node.new()
	w.notify_attack(null, ctx); w.resolve_hit(null, t, 5.0, false)
	assert_int(a.on_hit_calls).is_equal(1)
	assert_int(b.on_hit_calls).is_equal(1)
	w.notify_attack(null, ctx); w.resolve_hit(null, t, 5.0, false)
	assert_int(a.on_hit_calls).is_equal(2)
	assert_int(b.on_hit_calls).is_equal(2)
	w.notify_attack(null, ctx); w.resolve_hit(null, t, 5.0, false)
	assert_int(a.on_hit_calls).is_equal(4)
	assert_int(b.on_hit_calls).is_equal(4)


func test_flywheel_dumps_three_extra_at_five_swings() -> void:
	var w := Weapon.new()
	var a := _HitCounter.new()
	var fw := FlywheelModifier.new()
	var b := _HitCounter.new()
	w.add_modifier(0, a); w.add_modifier(1, fw); w.add_modifier(2, b)
	var ctx := {"direction": Vector2.RIGHT, "origin": Vector2.ZERO, "charged": false, "charge_ratio": 0.0}
	var t := Node.new()
	for i in range(4):
		w.notify_attack(null, ctx); w.resolve_hit(null, t, 5.0, false)
	assert_int(a.on_hit_calls).is_equal(4)
	assert_int(b.on_hit_calls).is_equal(4)
	w.notify_attack(null, ctx); w.resolve_hit(null, t, 5.0, false)
	assert_int(a.on_hit_calls).is_equal(8)
	assert_int(b.on_hit_calls).is_equal(8)
	w.notify_attack(null, ctx); w.resolve_hit(null, t, 5.0, false)
	assert_int(a.on_hit_calls).is_equal(9)
	assert_int(b.on_hit_calls).is_equal(9)
