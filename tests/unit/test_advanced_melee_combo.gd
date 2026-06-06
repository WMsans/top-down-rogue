extends GdUnitTestSuite

class TapChainProbe extends AdvancedMeleeWeapon:
	var played: Array = []
	func _setup_moves() -> void:
		combo_mode = ComboMode.TAP_CHAIN
		combo_reset_time = 0.5
		light_moves = [_slash(0.0), _slash(0.0), _thrust()]
	func _play_move(move, _user) -> void:
		played.append(move.shape)

class FlurryProbe extends AdvancedMeleeWeapon:
	var played: Array = []
	func _setup_moves() -> void:
		combo_mode = ComboMode.AUTO_FLURRY
		flurry_step_time = 0.1
		light_moves = [_thrust(), _thrust(), _thrust()]
	func _play_move(move, _user) -> void:
		played.append(move.shape)

func _tap_probe() -> TapChainProbe:
	var w := TapChainProbe.new()
	w.weapon_reach = 30.0
	w.arc_angle = PI / 2.0
	w.cooldown = 0.0
	return w

func test_tap_chain_advances_then_wraps() -> void:
	var w := _tap_probe()
	w.on_press(null)   # step 0 slash
	w.on_press(null)   # step 1 slash
	w.on_press(null)   # step 2 thrust -> wraps to 0
	w.on_press(null)   # step 0 slash again
	assert_array(w.played).is_equal([
		AdvancedMeleeWeapon.MoveShape.SLASH,
		AdvancedMeleeWeapon.MoveShape.SLASH,
		AdvancedMeleeWeapon.MoveShape.THRUST,
		AdvancedMeleeWeapon.MoveShape.SLASH,
	])

func test_tap_chain_resets_after_window() -> void:
	var w := _tap_probe()
	w.on_press(null)            # step 0
	w._tick_impl(0.6)           # window (0.5) elapses -> index resets to 0
	w.on_press(null)            # step 0 again, not step 1
	assert_array(w.played).is_equal([
		AdvancedMeleeWeapon.MoveShape.SLASH,
		AdvancedMeleeWeapon.MoveShape.SLASH,
	])

func test_auto_flurry_plays_all_and_locks_input() -> void:
	var w := FlurryProbe.new()
	w.weapon_reach = 30.0
	w.arc_angle = PI / 2.0
	w.cooldown = 0.0
	w.on_press(null)            # starts flurry, plays move 1 immediately
	assert_int(w.played.size()).is_equal(1)
	w.on_press(null)            # ignored: flurry active
	assert_int(w.played.size()).is_equal(1)
	w._tick_impl(0.1)           # move 2
	w._tick_impl(0.1)           # move 3
	assert_int(w.played.size()).is_equal(3)
	w._tick_impl(0.1)           # queue drained -> flurry ends
	assert_bool(w._flurry_active).is_false()
