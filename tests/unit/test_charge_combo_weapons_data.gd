extends GdUnitTestSuite

func _w(id: String) -> AdvancedMeleeWeapon:
	var w = WeaponRegistry.get_weapon_by_id(id)
	w._ensure_moves()
	return w

func test_all_load_as_advanced() -> void:
	for id in ["willowblade", "executioner", "blood_blade", "void_sword",
			"dragon_fang", "grand_knight_sword", "deep_dark_blade",
			"phantom_blade", "qinggang_sword"]:
		var w = WeaponRegistry.get_weapon_by_id(id)
		assert_that(w is AdvancedMeleeWeapon).override_failure_message(
			"'%s' is not AdvancedMeleeWeapon" % id).is_true()

func test_dragon_fang_is_three_thrust_flurry() -> void:
	var w := _w("dragon_fang")
	assert_int(w.combo_mode).is_equal(AdvancedMeleeWeapon.ComboMode.AUTO_FLURRY)
	assert_int(w.light_moves.size()).is_equal(3)
	for m in w.light_moves:
		assert_int(m.shape).is_equal(AdvancedMeleeWeapon.MoveShape.THRUST)

func test_grand_knight_is_slash_slash_thrust() -> void:
	var w := _w("grand_knight_sword")
	assert_int(w.combo_mode).is_equal(AdvancedMeleeWeapon.ComboMode.TAP_CHAIN)
	var shapes := []
	for m in w.light_moves:
		shapes.append(m.shape)
	assert_array(shapes).is_equal([
		AdvancedMeleeWeapon.MoveShape.SLASH,
		AdvancedMeleeWeapon.MoveShape.SLASH,
		AdvancedMeleeWeapon.MoveShape.THRUST,
	])

func test_willowblade_charged_thrust_is_force_crit() -> void:
	var w := _w("willowblade")
	assert_int(w.charged_moves.size()).is_equal(1)
	assert_int(w.charged_moves[0].shape).is_equal(AdvancedMeleeWeapon.MoveShape.THRUST)
	assert_bool(w.charged_moves[0].force_crit).is_true()

func test_executioner_charged_spin_scales() -> void:
	var w := _w("executioner")
	assert_int(w.charged_flurry_max).is_equal(2)
	assert_int(w.charged_moves[0].shape).is_equal(AdvancedMeleeWeapon.MoveShape.SPIN)

func test_blood_blade_charged_slash_has_dash() -> void:
	var w := _w("blood_blade")
	assert_float(w.charged_moves[0].dash_distance).is_greater(0.0)

func test_phantom_thrust_ignores_parry() -> void:
	var w := _w("phantom_blade")
	var thrust = w.light_moves[1]
	assert_int(thrust.shape).is_equal(AdvancedMeleeWeapon.MoveShape.THRUST)
	assert_bool(thrust.ignore_parry).is_true()

func test_deep_dark_is_spin_then_thrust() -> void:
	var w := _w("deep_dark_blade")
	assert_int(w.light_moves[0].shape).is_equal(AdvancedMeleeWeapon.MoveShape.SPIN)
	assert_int(w.light_moves[1].shape).is_equal(AdvancedMeleeWeapon.MoveShape.THRUST)

func test_qinggang_alternates_swing_dir() -> void:
	var w := _w("qinggang_sword")
	assert_float(w.light_moves[0].swing_dir).is_equal(1.0)
	assert_float(w.light_moves[1].swing_dir).is_equal(-1.0)
