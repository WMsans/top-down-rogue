extends GdUnitTestSuite

const _RoomSign = preload("res://src/core/interactables/room_sign.gd")

func test_sign_is_not_auto_pickup() -> void:
	var sign_node := _RoomSign.new()
	auto_free(sign_node)
	assert_bool(sign_node.should_auto_pickup()).is_false()

func test_sign_has_no_interact() -> void:
	var sign_node := _RoomSign.new()
	auto_free(sign_node)
	assert_bool(sign_node.has_method("interact")).is_false()

func test_sign_exposes_pickup_contract() -> void:
	var sign_node := _RoomSign.new()
	auto_free(sign_node)
	assert_bool(sign_node.has_method("get_pickup_type")).is_true()
	assert_bool(sign_node.has_method("populate_info_card")).is_true()

func test_sign_builds_collision_shape_on_ready() -> void:
	var sign_node := _RoomSign.new()
	add_child(sign_node)          # triggers _ready
	assert_int(sign_node.collision_layer).is_equal(2)
	var shapes := sign_node.get_children().filter(func(n): return n is CollisionShape2D)
	assert_int(shapes.size()).is_equal(1)
	sign_node.queue_free()
