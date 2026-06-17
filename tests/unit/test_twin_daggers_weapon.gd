extends GdUnitTestSuite

const TwinDaggers = preload("res://src/weapons/twin_daggers_weapon.gd")

class Probe extends TwinDaggers:
	var played: Array = []
	func _play_move(move, _user) -> void:
		played.append(move)

func test_one_attack_dispatches_two_passes() -> void:
	var w := Probe.new()
	w._use_impl(null)
	assert_int(w.played.size()).is_equal(1)
	w._tick_impl(1.0)
	assert_int(w.played.size()).is_equal(2)

func test_uses_auto_flurry_with_two_light_moves() -> void:
	var w := TwinDaggers.new()
	w._ensure_moves()
	assert_int(w.combo_mode).is_equal(AdvancedMeleeWeapon.ComboMode.AUTO_FLURRY)
	assert_int(w.light_moves.size()).is_equal(2)
