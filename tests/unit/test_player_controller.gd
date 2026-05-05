extends GdUnitTestSuite

func test_on_hit_impact_delegates_to_inventory() -> void:
	var controller := PlayerController.new()
	var inventory := PlayerInventory.new()
	inventory.name = "PlayerInventory"
	controller.add_child(inventory)
	controller.on_hit_impact(Vector2.ZERO, Vector2.RIGHT, 10)
	assert_that(inventory.get_health()).is_equal(90)
