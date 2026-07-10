extends GdUnitTestSuite

const _Shrine = preload("res://src/core/interactables/interactable_shrine.gd")

class _SpyShrine extends "res://src/core/interactables/interactable_shrine.gd":
	var interacts: int = 0
	func _on_interact(_player) -> void:
		interacts += 1

func test_interact_invokes_hook_once_then_consumes() -> void:
	var shrine := _SpyShrine.new()
	auto_free(shrine)
	shrine.interact(null)
	shrine.interact(null)   # second call ignored — already consumed
	assert_int(shrine.interacts).is_equal(1)
	assert_bool(shrine.consumed).is_true()

func test_shrine_is_not_auto_pickup() -> void:
	var shrine := _Shrine.new()
	auto_free(shrine)
	assert_bool(shrine.should_auto_pickup()).is_false()

func test_shrine_builds_collision_shape_on_ready() -> void:
	var shrine := _Shrine.new()
	add_child(shrine)
	assert_int(shrine.collision_layer).is_equal(2)
	shrine.queue_free()
