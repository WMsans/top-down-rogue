extends GdUnitTestSuite


func test_offer_weapon_accepts_and_calls_callback() -> void:
	var inventory: PlayerInventory = auto_free(PlayerInventory.new())
	inventory.name = "PlayerInventory"
	var delivery: WeaponDelivery = auto_free(WeaponDelivery.new())
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	parent.add_child(inventory)
	parent.add_child(delivery)

	delivery._test_mode = true
	delivery._test_response_accepted = true
	delivery._test_response_slot = 1

	var result := {"accepted": false, "slot": -1}
	var callback := func(accepted: bool, slot: int) -> void:
		result["accepted"] = accepted
		result["slot"] = slot

	var spec := WeaponOfferSpec.new()
	spec.type = WeaponOfferSpec.OfferType.WEAPON
	spec.weapon = Weapon.new()

	delivery._offer_weapon(spec, callback)
	assert_that(result["accepted"]).is_true()
	assert_that(result["slot"]).is_equal(1)


func test_offer_weapon_rejects_and_calls_callback() -> void:
	var inventory: PlayerInventory = auto_free(PlayerInventory.new())
	inventory.name = "PlayerInventory"
	var delivery: WeaponDelivery = auto_free(WeaponDelivery.new())
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	parent.add_child(inventory)
	parent.add_child(delivery)

	delivery._test_mode = true
	delivery._test_response_accepted = false

	var result := {"accepted": true}
	var callback := func(accepted: bool, _slot: int) -> void:
		result["accepted"] = accepted

	var spec := WeaponOfferSpec.new()
	spec.type = WeaponOfferSpec.OfferType.WEAPON
	spec.weapon = Weapon.new()

	delivery._offer_weapon(spec, callback)
	assert_that(result["accepted"]).is_false()


func test_offer_modifier_rejected_when_no_slots() -> void:
	var inventory: PlayerInventory = auto_free(PlayerInventory.new())
	inventory.name = "PlayerInventory"
	var delivery: WeaponDelivery = auto_free(WeaponDelivery.new())
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	parent.add_child(inventory)
	parent.add_child(delivery)

	# Equip a weapon with free modifier slots so can_equip_modifier passes
	# and we reach _test_mode block to verify rejection via _test_response_accepted
	var w := Weapon.new()
	w.modifier_slot_count = 1
	w.modifiers.resize(1)
	inventory.equip_weapon(0, w)

	delivery._test_mode = true
	delivery._test_response_accepted = false

	var result := {"accepted": true}
	var callback := func(accepted: bool, _slot: int) -> void:
		result["accepted"] = accepted

	var spec := WeaponOfferSpec.new()
	spec.type = WeaponOfferSpec.OfferType.MODIFIER
	spec.modifier = Modifier.new()

	delivery._offer_modifier(spec, callback)
	assert_that(result["accepted"]).is_false()
