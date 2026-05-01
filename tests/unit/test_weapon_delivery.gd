extends GdUnitTestSuite


func _make_delivery() -> WeaponDelivery:
	var delivery: WeaponDelivery = auto_free(WeaponDelivery.new())
	var inv: PlayerInventory = auto_free(PlayerInventory.new())
	add_child(inv)
	delivery._inventory = inv
	delivery._test_mode = true
	return delivery


func test_offer_weapon_accepts_and_calls_callback() -> void:
	var delivery := _make_delivery()
	delivery._test_response_accepted = true
	delivery._test_response_slot = 1

	var captured := {"accepted": false, "slot": -1}
	var callback := func(accepted: bool, slot: int) -> void:
		captured.accepted = accepted
		captured.slot = slot

	var spec := WeaponOfferSpec.new()
	spec.type = WeaponOfferSpec.OfferType.WEAPON
	spec.weapon = Weapon.new()

	delivery.offer(spec, callback)
	assert_that(captured.accepted).is_true()
	assert_that(captured.slot).is_equal(1)


func test_offer_weapon_rejects_and_calls_callback() -> void:
	var delivery := _make_delivery()
	delivery._test_response_accepted = false

	var captured := {"accepted": true}
	var callback := func(accepted: bool, _slot: int) -> void:
		captured.accepted = accepted

	var spec := WeaponOfferSpec.new()
	spec.type = WeaponOfferSpec.OfferType.WEAPON
	spec.weapon = Weapon.new()

	delivery.offer(spec, callback)
	assert_that(captured.accepted).is_false()


func test_offer_modifier_rejected_when_no_slots() -> void:
	var delivery := _make_delivery()
	var captured := {"accepted": true}
	var callback := func(accepted: bool, _slot: int) -> void:
		captured.accepted = accepted

	var spec := WeaponOfferSpec.new()
	spec.type = WeaponOfferSpec.OfferType.MODIFIER
	spec.modifier = Modifier.new()

	delivery.offer(spec, callback)
	assert_that(captured.accepted).is_false()
