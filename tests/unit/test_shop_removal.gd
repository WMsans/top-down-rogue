extends GdUnitTestSuite

const SHOP_REMOVAL := preload("res://scenes/economy/shop_removal.tscn")

func _make_player(gold: int, accepted: bool, with_modifier: bool) -> Node2D:
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
	if with_modifier:
		var w := Weapon.new()
		w.modifiers.resize(3)
		w.modifiers[0] = Modifier.new()
		inv.equip_weapon(0, w)
	return player


func _make_removal() -> ShopRemoval:
	var removal: ShopRemoval = SHOP_REMOVAL.instantiate()
	add_child(removal)
	auto_free(removal)
	return removal


func test_removal_charges_base_and_escalates() -> void:
	var player := _make_player(500, true, true)
	var removal := _make_removal()
	removal.interact(player)
	assert_int(player.get_node("PlayerInventory").gold).is_equal(420)
	removal.interact(player)
	assert_int(player.get_node("PlayerInventory").gold).is_equal(300)


func test_removal_noop_without_equipped_modifier() -> void:
	var player := _make_player(500, true, false)
	var removal := _make_removal()
	removal.interact(player)
	assert_int(player.get_node("PlayerInventory").gold).is_equal(500)


func test_removal_noop_when_too_poor() -> void:
	var player := _make_player(10, true, true)
	var removal := _make_removal()
	removal.interact(player)
	assert_int(player.get_node("PlayerInventory").gold).is_equal(10)
