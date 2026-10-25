extends GdUnitTestSuite

const _WorldManager = preload("res://src/core/world_manager.gd")


func test_game_scene_has_y_sorted_entities_with_player() -> void:
	var root: Node = load("res://scenes/game.tscn").instantiate()
	var wm := root.get_node("GameViewport/SubViewport/WorldManager")
	var e := wm.get_node_or_null("Entities") as Node2D
	assert_object(e).is_not_null()
	assert_bool(e.y_sort_enabled).is_true()
	assert_object(e.get_node_or_null("Player")).is_not_null()
	# Drawn after the chunk meshes so the floor-AO quad never covers actors.
	assert_int(e.get_index()).is_greater(wm.get_node("ChunkContainer").get_index())
	root.free()


func test_reset_keeps_player() -> void:
	var layer: Node2D = auto_free(Node2D.new())
	var player := Node2D.new()
	player.add_to_group("player")
	layer.add_child(player)
	layer.add_child(Node2D.new())
	layer.add_child(Node2D.new())
	_WorldManager.clear_entities(layer)
	await await_idle_frame()
	assert_int(layer.get_child_count()).is_equal(1)
	assert_object(layer.get_child(0)).is_same(player)


# The Player lives under WorldManager/Entities, so it finds the world manager
# as an ancestor, not a sibling (chunk streaming follows tracking_position).
func test_player_finds_world_manager_from_entities() -> void:
	var root: Node = load("res://scenes/game.tscn").instantiate()
	var wm := root.get_node("GameViewport/SubViewport/WorldManager")
	var player := wm.get_node("Entities/Player")
	assert_object(player._world_manager()).is_same(wm)
	root.free()


func test_floor_container_clear_frees_chunks() -> void:
	var fc: FloorContainer = auto_free(FloorContainer.new())
	add_child(fc)
	var chunk := Node2D.new()
	fc.add_child(chunk)
	fc._chunks[Vector2i(1, 2)] = chunk
	fc.clear()
	await await_idle_frame()
	assert_int(fc.get_child_count()).is_equal(0)
	assert_bool(fc._chunks.is_empty()).is_true()
