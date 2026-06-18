# tests/unit/test_player_health_fraction.gd
extends GdUnitTestSuite


func test_full_health_is_one() -> void:
	var inv: PlayerInventory = auto_free(PlayerInventory.new())
	inv.max_health = 100
	add_child(inv)  # _ready sets _current_health = max_health
	assert_float(inv.get_health_fraction()).is_equal_approx(1.0, 0.001)


func test_fraction_scales_with_current_health() -> void:
	var inv: PlayerInventory = auto_free(PlayerInventory.new())
	inv.max_health = 100
	add_child(inv)
	inv.take_status_damage(75)
	assert_float(inv.get_health_fraction()).is_equal_approx(0.25, 0.02)
