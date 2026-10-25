extends GdUnitTestSuite

func test_on_hit_impact_delegates_to_inventory() -> void:
	# The controller stays out of the tree (its _ready needs the game scene),
	# so the parts on_hit_impact touches are wired up by hand.
	var controller: PlayerController = auto_free(PlayerController.new())
	controller._sprite = auto_free(AnimatedSprite2D.new())
	var inventory: PlayerInventory = auto_free(PlayerInventory.new())
	inventory.name = "PlayerInventory"
	controller.add_child(inventory)
	inventory._ready()  # fills health and armor
	controller.on_hit_impact(Vector2.ZERO, Vector2.RIGHT)
	assert_that(inventory.get_armor()).is_equal(2)


func test_squash_keeps_positive_scale() -> void:
	var controller: PlayerController = auto_free(PlayerController.new())
	controller._sprite = auto_free(AnimatedSprite2D.new())
	controller._facing_left = true
	controller._play_squash()
	controller._squash_tween.custom_step(0.03)  # mid-squash; tweens don't auto-run out of tree
	assert_float(controller._sprite.scale.x).is_greater(0.0)
	controller._squash_tween.custom_step(1.0)
	assert_vector(controller._sprite.scale).is_equal(Vector2.ONE)
