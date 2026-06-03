extends GdUnitTestSuite

const SHOP_WEAPON_DROP := preload("res://scenes/economy/shop_weapon_drop.tscn")

func _make_player(gold: int, accepted: bool) -> Node2D:
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
	return player

func _make_drop(price: int) -> ShopWeaponDrop:
	var drop: ShopWeaponDrop = SHOP_WEAPON_DROP.instantiate()
	var w := Weapon.new()
	w.rarity = DropTable.ItemTier.COMMON
	w.modifiers.resize(3)
	drop.weapon = w
	drop.price = price
	add_child(drop)
	return drop

func test_affordable_pickup_charges_once_and_frees() -> void:
	var player := _make_player(500, true)
	var drop := _make_drop(120)
	drop._pickup(player)
	assert_int(player.get_node("PlayerInventory").gold).is_equal(380)
	assert_bool(drop.is_queued_for_deletion()).is_true()

func test_unaffordable_pickup_charges_nothing_and_stays() -> void:
	var player := _make_player(50, true)
	var drop := _make_drop(120)
	drop._pickup(player)
	assert_int(player.get_node("PlayerInventory").gold).is_equal(50)
	assert_bool(drop.is_queued_for_deletion()).is_false()
	auto_free(drop)

func test_rejected_delivery_charges_nothing() -> void:
	var player := _make_player(500, false)
	var drop := _make_drop(120)
	drop._pickup(player)
	assert_int(player.get_node("PlayerInventory").gold).is_equal(500)
	assert_bool(drop.is_queued_for_deletion()).is_false()
	auto_free(drop)
