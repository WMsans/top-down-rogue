extends GdUnitTestSuite

func test_on_hit_impact_delegates_to_inventory() -> void:
	var controller: PlayerController = auto_free(PlayerController.new())
	controller._color_rect = auto_free(ColorRect.new())
	var inventory: PlayerInventory = auto_free(PlayerInventory.new())
	inventory.name = "PlayerInventory"
	controller.add_child(inventory)
	inventory._current_health = inventory.max_health
	controller.on_hit_impact(Vector2.ZERO, Vector2.RIGHT, 10)
	assert_that(inventory.get_health()).is_equal(90)
