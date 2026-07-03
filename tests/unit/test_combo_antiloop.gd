extends GdUnitTestSuite

class _HitCounter extends Modifier:
	var on_hit_calls: int = 0
	func _init() -> void:
		category = "trigger"
	func on_hit_target(_w, _u, _t) -> void:
		on_hit_calls += 1

func test_mirror_slot_plus_echo_no_loop() -> void:
	var w := Weapon.new()
	var c := _HitCounter.new()
	var mirror := MirrorSlotModifier.new()
	var echo := EchoStrikeModifier.new()
	w.add_modifier(0, c); w.add_modifier(1, mirror); w.add_modifier(2, echo)
	var t := Node.new()
	w.resolve_hit(null, t, 5.0, false)
	assert_bool(c.on_hit_calls <= 6).is_true()


func test_catalyst_bond_plus_retrigger_no_cycle() -> void:
	var w := Weapon.new()
	var c := _HitCounter.new()
	var bond := CatalystBondModifier.new()
	var echo := EchoStrikeModifier.new()
	w.add_modifier(0, c); w.add_modifier(1, bond); w.add_modifier(2, echo)
	var t := Node.new()
	w.resolve_hit(null, t, 5.0, false)
	assert_bool(c.on_hit_calls <= 5).is_true()


func test_keystone_focus_survives_outer_retrigger_modifier() -> void:
	var w := Weapon.new()
	var outer := _HitCounter.new()
	outer.is_retrigger_modifier = true
	var ks := KeystoneModifier.new()
	w.add_modifier(0, outer); w.add_modifier(1, ks)
	var t := Node.new()
	w.resolve_hit(null, t, 5.0, false)
	assert_int(outer.on_hit_calls).is_equal(0)
