extends GdUnitTestSuite

const AiDebugCommand := preload("res://src/console/commands/ai_debug_command.gd")

class FakeWorld extends Node2D:
	var encounter_director := EncounterDirector.new()


func test_toggles_overlay() -> void:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	var args: Array[String] = []
	var ctx := {"world_manager": world}
	assert_str(AiDebugCommand._ai_debug(args, ctx)).is_equal("AI debug overlay on")
	var overlay := world.get_node_or_null("AiDebugOverlay")
	assert_object(overlay).is_not_null()
	assert_object(overlay.director).is_same(world.encounter_director)
	assert_str(AiDebugCommand._ai_debug(args, ctx)).is_equal("AI debug overlay off")


func test_errors_without_world() -> void:
	var args: Array[String] = []
	assert_str(AiDebugCommand._ai_debug(args, {"world_manager": null})).starts_with("error:")
