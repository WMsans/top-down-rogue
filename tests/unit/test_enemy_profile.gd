extends GdUnitTestSuite


func test_easy_profile() -> void:
	var p := EnemyProfile.for_tier(DropTable.EnemyTier.EASY)
	assert_float(p.telegraph_mult).is_equal(1.25)
	assert_float(p.cadence_mult).is_equal(1.2)
	assert_float(p.reaction_time).is_equal(0.35)
	assert_int(p.chain_attacks).is_equal(1)
	assert_int(p.volley_bonus).is_equal(0)
	assert_float(p.lead_factor).is_equal(0.0)
	assert_bool(p.lunge_redirect).is_false()


func test_normal_profile() -> void:
	var p := EnemyProfile.for_tier(DropTable.EnemyTier.NORMAL)
	assert_float(p.telegraph_mult).is_equal(1.0)
	assert_float(p.cadence_mult).is_equal(1.0)
	assert_float(p.reaction_time).is_equal(0.2)
	assert_int(p.chain_attacks).is_equal(2)
	assert_int(p.volley_bonus).is_equal(1)
	assert_float(p.lead_factor).is_equal(0.5)
	assert_bool(p.lunge_redirect).is_false()


func test_hard_profile() -> void:
	var p := EnemyProfile.for_tier(DropTable.EnemyTier.HARD)
	assert_float(p.telegraph_mult).is_equal(0.75)
	assert_float(p.cadence_mult).is_equal(0.7)
	assert_float(p.reaction_time).is_equal(0.1)
	assert_int(p.chain_attacks).is_equal(2)
	assert_int(p.volley_bonus).is_equal(2)
	assert_float(p.lead_factor).is_equal(0.9)
	assert_bool(p.lunge_redirect).is_true()


func test_elite_steps_up_timing_and_lead_only() -> void:
	var p := EnemyProfile.for_tier(DropTable.EnemyTier.EASY, true)
	# Stepped to NORMAL for these three...
	assert_float(p.telegraph_mult).is_equal(1.0)
	assert_float(p.cadence_mult).is_equal(1.0)
	assert_float(p.lead_factor).is_equal(0.5)
	# ...always gets the redirect...
	assert_bool(p.lunge_redirect).is_true()
	# ...and keeps EASY for the rest.
	assert_float(p.reaction_time).is_equal(0.35)
	assert_int(p.chain_attacks).is_equal(1)
	assert_int(p.volley_bonus).is_equal(0)


func test_hard_elite_stays_hard() -> void:
	var p := EnemyProfile.for_tier(DropTable.EnemyTier.HARD, true)
	assert_float(p.telegraph_mult).is_equal(0.75)
	assert_float(p.cadence_mult).is_equal(0.7)
	assert_float(p.lead_factor).is_equal(0.9)


func test_unknown_tier_falls_back_to_normal() -> void:
	var p := EnemyProfile.for_tier(99)
	assert_float(p.telegraph_mult).is_equal(1.0)
	assert_int(p.chain_attacks).is_equal(2)
