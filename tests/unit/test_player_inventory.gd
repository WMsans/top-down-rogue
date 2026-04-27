# tests/unit/test_player_inventory.gd
extends GdUnitTestSuite


func test_add_gold_increases_gold() -> void:
	var inv := PlayerInventory.new()
	inv.add_gold(10)
	assert_that(inv.gold).is_equal(10)


func test_spend_gold_succeeds_with_sufficient_gold() -> void:
	var inv := PlayerInventory.new()
	inv.add_gold(20)
	assert_that(inv.spend_gold(5)).is_true()
	assert_that(inv.gold).is_equal(15)


func test_spend_gold_fails_with_insufficient_gold() -> void:
	var inv := PlayerInventory.new()
	inv.add_gold(3)
	assert_that(inv.spend_gold(10)).is_false()
	assert_that(inv.gold).is_equal(3)


func test_take_damage_reduces_health() -> void:
	var inv := PlayerInventory.new()
	inv.take_damage(30)
	assert_that(inv.get_health()).is_equal(inv.max_health - 30)


func test_take_damage_does_not_go_below_zero() -> void:
	var inv := PlayerInventory.new()
	inv.take_damage(9999)
	assert_that(inv.get_health()).is_equal(0)
	assert_that(inv.is_dead()).is_true()


func test_invincibility_prevents_double_damage() -> void:
	var inv := PlayerInventory.new()
	inv.take_damage(10)
	inv.take_damage(10)  # blocked by invincibility
	assert_that(inv.get_health()).is_equal(inv.max_health - 10)


func test_heal_restores_health() -> void:
	var inv := PlayerInventory.new()
	var half := inv.max_health / 2
	inv.take_damage(half)
	inv.heal(20)
	assert_that(inv.get_health()).is_equal(inv.max_health - half + 20)


func test_equip_weapon_sets_slot() -> void:
	var inv := PlayerInventory.new()
	var weapon := Weapon.new()
	inv.equip_weapon(0, weapon)
	assert_that(inv.get_weapon(0)).is_equal(weapon)


func test_has_empty_weapon_slot() -> void:
	var inv := PlayerInventory.new()
	assert_that(inv.has_empty_weapon_slot()).is_true()
	inv.equip_weapon(0, Weapon.new())
	inv.equip_weapon(1, Weapon.new())
	inv.equip_weapon(2, Weapon.new())
	assert_that(inv.has_empty_weapon_slot()).is_false()
