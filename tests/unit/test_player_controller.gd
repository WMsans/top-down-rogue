extends GdUnitTestSuite

func test_on_hit_impact_delegates_to_inventory() -> void:
	# The controller stays out of the tree (its _ready needs the game scene),
	# so the parts on_hit_impact touches are wired up by hand.
	var controller: PlayerController = auto_free(PlayerController.new())
	controller._color_rect = auto_free(ColorRect.new())
	var inventory: PlayerInventory = auto_free(PlayerInventory.new())
	inventory.name = "PlayerInventory"
	controller.add_child(inventory)
	inventory._ready()  # fills health and armor
	controller.on_hit_impact(Vector2.ZERO, Vector2.RIGHT)
	assert_that(inventory.get_armor()).is_equal(2)
