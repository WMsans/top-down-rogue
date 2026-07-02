extends GdUnitTestSuite

class _Stub extends Modifier:
	var cats: String = "trigger"
	func _init() -> void:
		category = "trigger"
	func on_hit_target(_w, _u, _t) -> void:
		pass

func test_add_modifier_records_slot_index() -> void:
	var w := Weapon.new()
	var a := _Stub.new()
	var b := _Stub.new()
	w.add_modifier(0, a)
	w.add_modifier(2, b)
	assert_int(a.slot_index).is_equal(0)
	assert_int(b.slot_index).is_equal(2)

func test_sibling_helpers() -> void:
	var w := Weapon.new()
	var a := _Stub.new()
	var b := _Stub.new()
	var c := _Stub.new()
	w.add_modifier(0, a); w.add_modifier(1, b); w.add_modifier(2, c)
	assert_object(w.get_first_modifier()).is_same(a)
	assert_object(w.get_left_modifier(1)).is_same(a)
	assert_object(w.get_right_modifier(1)).is_same(c)
	assert_object(w.get_left_modifier(0)).is_null()
	assert_object(w.get_right_modifier(2)).is_null()

func test_first_modifier_skips_nulls() -> void:
	var w := Weapon.new()
	var c := _Stub.new()
	w.add_modifier(2, c)
	assert_object(w.get_first_modifier()).is_same(c)

func test_disabled_flag_defaults_false_and_settable() -> void:
	var m := _Stub.new()
	assert_bool(m.is_disabled).is_false()
	m.is_disabled = true
	assert_bool(m.is_disabled).is_true()


class _Counter extends Modifier:
	var hits: int = 0
	func _init() -> void:
		category = "trigger"
	func on_hit_target(_w, _u, _t) -> void:
		hits += 1


class _Retrigger extends Modifier:
	var calls: int = 0
	func _init() -> void:
		category = "trigger"
		is_retrigger_modifier = true
	func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
		calls += 1
		var first: Modifier = weapon.get_first_modifier()
		weapon.retrigger_modifier(first, "on_hit_target", [user, target])


class _ChainRetrigger extends Modifier:
	func _init() -> void:
		category = "trigger"
		is_retrigger_modifier = true
	func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
		var first: Modifier = weapon.get_first_modifier()
		weapon.retrigger_modifier(first, "on_hit_target", [user, target])


func test_retrigger_fires_target_once() -> void:
	var w := Weapon.new()
	var c := _Counter.new()
	var r := _Retrigger.new()
	w.add_modifier(0, c); w.add_modifier(1, r)
	var t := Node.new()
	w.resolve_hit(null, t, 5.0, false)
	assert_int(c.hits).is_equal(2)

func test_retrigger_skips_retrigger_modifier() -> void:
	var w := Weapon.new()
	var r1 := _Retrigger.new()
	var r2 := _Retrigger.new()
	w.add_modifier(0, r1); w.add_modifier(1, r2)
	var t := Node.new()
	w.resolve_hit(null, t, 5.0, false)
	assert_int(r1.calls).is_equal(1)
	assert_int(r2.calls).is_equal(1)

func test_retrigger_depth_guard_stops_at_two() -> void:
	var w := Weapon.new()
	var c := _Counter.new()
	var chainA := _ChainRetrigger.new()
	var chainB := _ChainRetrigger.new()
	w.add_modifier(0, c); w.add_modifier(1, chainA); w.add_modifier(2, chainB)
	var t := Node.new()
	w.resolve_hit(null, t, 5.0, false)
	assert_int(c.hits).is_equal(3)


func test_disabled_modifier_skipped_in_all_hooks() -> void:
	var w := Weapon.new()
	var c := _Counter.new()
	c.is_disabled = true
	w.add_modifier(0, c)
	var t := Node.new()
	w.notify_attack(null, {"direction": Vector2.RIGHT, "origin": Vector2.ZERO, "charged": false, "charge_ratio": 0.0})
	w.resolve_hit(null, t, 5.0, false)
	assert_int(c.hits).is_equal(0)


func test_disabled_modifier_excluded_from_effective_stats() -> void:
	var w := Weapon.new()
	w.damage = 10.0
	var m := DataModifier.new({
		"id": "x", "name": "X", "description": "", "rarity": "Common",
		"category": "stat", "trigger": "passive", "condition": "", "effect": "stat_add",
		"element": "damage", "magnitude": "5", "magnitude2": "0", "suppresses_base_use": "No",
	})
	m.is_disabled = true
	w.add_modifier(0, m)
	assert_float(w.get_effective_stats()["damage"]).is_equal(10.0)
	m.is_disabled = false
	w.invalidate_effective_stats()
	assert_float(w.get_effective_stats()["damage"]).is_equal(15.0)
