extends GdUnitTestSuite


func test_offer_weapon_accepts_and_calls_callback() -> void:
	var delivery := WeaponDelivery.new()
	delivery._test_mode = true
	delivery._test_response_accepted = true
	delivery._test_response_slot = 1

	var captured_accepted := false
	var captured_slot := -1
	var callback := func(accepted: bool, slot: int) -> void:
		captured_accepted = accepted
		captured_slot = slot

	var spec := WeaponOfferSpec.new()
	spec.type = WeaponOfferSpec.OfferType.WEAPON
	spec.weapon = Weapon.new()

	delivery.offer(spec, callback)
	assert_that(captured_accepted).is_true()
	assert_that(captured_slot).is_equal(1)


func test_offer_weapon_rejects_and_calls_callback() -> void:
	var delivery := WeaponDelivery.new()
	delivery._test_mode = true
	delivery._test_response_accepted = false

	var captured_accepted := true
	var callback := func(accepted: bool, _slot: int) -> void:
		captured_accepted = accepted

	var spec := WeaponOfferSpec.new()
	spec.type = WeaponOfferSpec.OfferType.WEAPON
	spec.weapon = Weapon.new()

	delivery.offer(spec, callback)
	assert_that(captured_accepted).is_false()


func test_offer_modifier_rejected_when_no_slots() -> void:
	var delivery := WeaponDelivery.new()
	delivery._test_mode = true
	var captured_accepted := true
	var callback := func(accepted: bool, _slot: int) -> void:
		captured_accepted = accepted

	var spec := WeaponOfferSpec.new()
	spec.type = WeaponOfferSpec.OfferType.MODIFIER
	spec.modifier = Modifier.new()

	delivery.offer(spec, callback)
	assert_that(captured_accepted).is_false()
