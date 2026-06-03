extends GdUnitTestSuite

const SHOP_MODIFIER_DROP := preload("res://scenes/economy/shop_modifier_drop.tscn")

func _make_player(gold: int, accepted: bool, with_weapon: bool) -> Node2D:
	var player := Node2D.new()
	player.add_to_group("player")
	var inv := PlayerInventory.new()
	inv.name = "PlayerInventory"
	player.add_child(inv)
	var delivery := WeaponDelivery.new()
	delivery.name = "WeaponDelivery"
	delivery._test_mode = true
	delivery._test_response_accepted = accepted
	delivery._test_response_slot = 0
	player.add_child(delivery)
	add_child(player)
	auto_free(player)
	inv.gold = gold
	if with_weapon:
		var w := Weapon.new()
		w.modifiers.resize(3)
		inv.equip_weapon(0, w)
	return player

func _make_drop(price: int) -> ShopModifierDrop:
	var drop: ShopModifierDrop = SHOP_MODIFIER_DROP.instantiate()
	drop.modifier = Modifier.new()
	drop.price = price
	add_child(drop)
	return drop

func test_affordable_pickup_charges_once_and_frees() -> void:
	var player := _make_player(200, true, true)
	var drop := _make_drop(30)
	drop._pickup(player)
	assert_int(player.get_node("PlayerInventory").gold).is_equal(170)
	assert_bool(drop.is_queued_for_deletion()).is_true()

func test_unaffordable_pickup_charges_nothing_and_stays() -> void:
	var player := _make_player(10, true, true)
	var drop := _make_drop(30)
	drop._pickup(player)
	assert_int(player.get_node("PlayerInventory").gold).is_equal(10)
	assert_bool(drop.is_queued_for_deletion()).is_false()
	auto_free(drop)
