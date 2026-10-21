# tests/unit/test_player_health_fraction.gd
extends GdUnitTestSuite


func test_full_health_is_one() -> void:
	var inv: PlayerInventory = auto_free(PlayerInventory.new())
	add_child(inv)
	assert_float(inv.get_health_fraction()).is_equal_approx(1.0, 0.001)


func test_fraction_ignores_armor() -> void:
	var inv: PlayerInventory = auto_free(PlayerInventory.new())
	add_child(inv)
	inv.take_status_tick()  # armor 3 -> 2, HP untouched
	assert_float(inv.get_health_fraction()).is_equal_approx(1.0, 0.001)


func test_fraction_scales_with_hp() -> void:
	var inv: PlayerInventory = auto_free(PlayerInventory.new())
	add_child(inv)
	for i in range(4):
		inv.take_status_tick()  # 3 armor, then 1 HP
	assert_float(inv.get_health_fraction()).is_equal_approx(2.0 / 3.0, 0.01)
