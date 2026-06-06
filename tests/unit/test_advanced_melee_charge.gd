extends GdUnitTestSuite

const AdvancedScript = preload("res://src/weapons/advanced_melee_weapon.gd")

# Subclass that records the moves dispatched, so we can assert charge selection
# without touching physics or animation.
class ProbeWeapon extends AdvancedMeleeWeapon:
	var played: Array = []
	func _setup_moves() -> void:
		charge_time_full = 0.5
		tap_threshold = 0.1
		charged_flurry_max = 2
		light_moves = [_slash()]
		charged_moves = [_spin()]
	func _play_move(move, _user) -> void:
		played.append(move)

func _make() -> ProbeWeapon:
	var w := ProbeWeapon.new()
	w.weapon_reach = 30.0
	w.arc_angle = PI / 2.0
	return w

func test_charge_ratio_accrues_and_clamps() -> void:
	var w := _make()
	w.on_press(null)
	w._tick_impl(0.25)
	assert_float(w.get_charge_ratio()).is_equal_approx(0.5, 0.01)
	w._tick_impl(1.0)
	assert_float(w.get_charge_ratio()).is_equal_approx(1.0, 0.01)

func test_quick_tap_plays_light() -> void:
	var w := _make()
	w.on_press(null)
	w._tick_impl(0.05)            # below tap_threshold
	w.on_release(null)
	assert_int(w.played.size()).is_equal(1)
	assert_int(w.played[0].shape).is_equal(AdvancedMeleeWeapon.MoveShape.SLASH)

func test_full_charge_plays_charged_flurry_scaled() -> void:
	var w := _make()
	w.on_press(null)
	w._tick_impl(1.0)             # full charge => ratio 1 => count 2
	w.on_release(null)
	# Flurry plays the first move immediately; the rest drain on tick.
	assert_int(w.played.size()).is_equal(1)
	assert_int(w.played[0].shape).is_equal(AdvancedMeleeWeapon.MoveShape.SPIN)
	w._tick_impl(1.0)             # drain the second spin
	assert_int(w.played.size()).is_equal(2)

func test_half_charge_plays_light() -> void:
	var w := _make()
	w.on_press(null)
	w._tick_impl(0.2)             # ratio 0.4 => below full => light slash
	w.on_release(null)
	assert_int(w.played.size()).is_equal(1)
	assert_int(w.played[0].shape).is_equal(AdvancedMeleeWeapon.MoveShape.SLASH)


func test_is_chargeable_true_when_charged_moves_exist() -> void:
	var w := _make()
	assert_bool(w.is_chargeable()).is_true()


func test_is_charging_tracks_press_and_release() -> void:
	var w := _make()
	assert_bool(w.is_charging()).is_false()
	w.on_press(null)
	assert_bool(w.is_charging()).is_true()
	w.on_release(null)
	assert_bool(w.is_charging()).is_false()
