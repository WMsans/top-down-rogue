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
