extends GdUnitTestSuite

const Whirlwind = preload("res://src/weapons/whirlwind_blade_weapon.gd")

class Probe extends Whirlwind:
	var played: Array = []
	func _play_move(move, _user) -> void:
		played.append(move)

func test_tap_plays_normal_slash() -> void:
	var w := Probe.new()
	w.on_press(null)
	w._tick_impl(0.05)          # below tap threshold
	w.on_release(null)
	assert_int(w.played.size()).is_equal(1)
	assert_int(w.played[0].shape).is_equal(AdvancedMeleeWeapon.MoveShape.SLASH)

func test_full_charge_plays_360_spin() -> void:
	var w := Probe.new()
	w.on_press(null)
	w._tick_impl(2.0)           # full charge
	w.on_release(null)
	assert_int(w.played.size()).is_equal(1)
	assert_int(w.played[0].shape).is_equal(AdvancedMeleeWeapon.MoveShape.SPIN)
	assert_float(w.played[0].arc).is_equal_approx(TAU, 0.001)
