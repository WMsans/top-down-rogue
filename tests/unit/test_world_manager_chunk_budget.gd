extends GdUnitTestSuite

# world_manager.gd has no class_name, so preload the script and call the static
# selector directly — no WorldManager instance (which needs a RenderingDevice).
const WorldManagerScript = preload("res://src/core/world_manager.gd")

func test_select_new_chunks_caps_per_frame() -> void:
	var desired := [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
	]
	var loaded := {}  # nothing loaded yet
	var picked := WorldManagerScript._select_new_chunks(desired, loaded, 2)
	assert_int(picked.size()).is_equal(2)
	assert_array(picked).is_equal([Vector2i(0, 0), Vector2i(1, 0)])

func test_select_new_chunks_skips_already_loaded() -> void:
	var desired := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var loaded := {Vector2i(0, 0): true}  # first one already loaded
	var picked := WorldManagerScript._select_new_chunks(desired, loaded, 2)
	assert_array(picked).is_equal([Vector2i(1, 0), Vector2i(2, 0)])

func test_select_new_chunks_returns_all_when_under_cap() -> void:
	var desired := [Vector2i(0, 0), Vector2i(1, 0)]
	var picked := WorldManagerScript._select_new_chunks(desired, {}, 5)
	assert_int(picked.size()).is_equal(2)
