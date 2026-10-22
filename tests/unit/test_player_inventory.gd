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


func _inv() -> PlayerInventory:
	var inv: PlayerInventory = auto_free(PlayerInventory.new())
	add_child(inv)  # _ready fills health and armor
	return inv


func test_starts_with_three_hp_and_three_armor() -> void:
	var inv := _inv()
	assert_int(inv.get_health()).is_equal(3)
	assert_int(inv.get_armor()).is_equal(3)


func test_hit_takes_armor_first() -> void:
	var inv := _inv()
	inv.take_hit()
	assert_int(inv.get_armor()).is_equal(2)
	assert_int(inv.get_health()).is_equal(3)


func test_hit_takes_hp_when_armor_empty() -> void:
	var inv := _inv()
	for i in range(3):
		inv.take_status_tick()
	inv.take_hit()
	assert_int(inv.get_armor()).is_equal(0)
	assert_int(inv.get_health()).is_equal(2)


func test_invincibility_blocks_second_hit() -> void:
	var inv := _inv()
	inv.take_hit()
	inv.take_hit()
	assert_int(inv.get_armor()).is_equal(2)


func test_status_tick_ignores_invincibility() -> void:
	var inv := _inv()
	inv.take_hit()
	inv.take_status_tick()
	assert_int(inv.get_armor()).is_equal(1)


func test_dies_after_six_points() -> void:
	var inv := _inv()
	var monitor = monitor_signals(inv)
	for i in range(6):
		inv.take_status_tick()
	assert_int(inv.get_health()).is_equal(0)
	assert_bool(inv.is_dead()).is_true()
	await assert_signal(monitor).is_emitted("player_died")


func test_creative_mode_refills_instead_of_dying() -> void:
	var inv := _inv()
	GameModeManager.set_mode(GameModeManager.Mode.CREATIVE)
	for i in range(6):
		inv.take_status_tick()
	GameModeManager.set_mode(GameModeManager.Mode.SURVIVAL)
	assert_bool(inv.is_dead()).is_false()
	assert_int(inv.get_health()).is_equal(3)
	assert_int(inv.get_armor()).is_equal(3)


func test_armor_regen_waits_for_delay() -> void:
	var inv := _inv()
	inv.take_status_tick()
	inv._physics_process(2.9)
	assert_int(inv.get_armor()).is_equal(2)
	inv._physics_process(0.1)
	assert_int(inv.get_armor()).is_equal(3)


func test_armor_regen_one_point_per_interval() -> void:
	var inv := _inv()
	for i in range(3):
		inv.take_status_tick()
	inv._physics_process(3.0)
	assert_int(inv.get_armor()).is_equal(1)
	inv._physics_process(0.99)
	assert_int(inv.get_armor()).is_equal(1)
	inv._physics_process(0.01)
	assert_int(inv.get_armor()).is_equal(2)


func test_large_delta_grants_multiple_armor() -> void:
	var inv := _inv()
	for i in range(3):
		inv.take_status_tick()
	inv._physics_process(5.0)  # points at 3.0, 4.0, 5.0
	assert_int(inv.get_armor()).is_equal(3)


func test_any_point_loss_resets_regen_delay() -> void:
	var inv := _inv()
	inv.take_status_tick()
	inv._physics_process(2.5)
	inv.take_status_tick()
	inv._physics_process(2.9)
	assert_int(inv.get_armor()).is_equal(1)
	inv._physics_process(0.1)
	assert_int(inv.get_armor()).is_equal(2)


func test_hp_never_regenerates() -> void:
	var inv := _inv()
	for i in range(4):
		inv.take_status_tick()
	inv._physics_process(20.0)
	assert_int(inv.get_health()).is_equal(2)
	assert_int(inv.get_armor()).is_equal(3)


func test_skip_armor_regen_delay() -> void:
	var inv := _inv()
	inv.take_status_tick()
	inv.skip_armor_regen_delay()
	inv._physics_process(0.01)
	assert_int(inv.get_armor()).is_equal(3)


func test_set_max_armor_clamps_current() -> void:
	var inv := _inv()
	inv.set_max_armor(1)
	assert_int(inv.get_max_armor()).is_equal(1)
	assert_int(inv.get_armor()).is_equal(1)


func test_heal_restores_hp_clamped() -> void:
	var inv := _inv()
	for i in range(5):
		inv.take_status_tick()
	inv.heal(5)
	assert_int(inv.get_health()).is_equal(3)


func test_point_loss_emits_damaged_one() -> void:
	var inv := _inv()
	var monitor = monitor_signals(inv)
	inv.take_status_tick()
	await assert_signal(monitor).is_emitted("damaged", [1])
	await assert_signal(monitor).is_emitted("armor_changed", [2, 3])


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
