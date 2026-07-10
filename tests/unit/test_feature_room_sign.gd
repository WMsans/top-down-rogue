extends GdUnitTestSuite

const _Feature = preload("res://src/core/features/feature_room_sign.gd")

class _FakeCtx:
	var anchor_world_pos: Vector2 = Vector2(100, 200)
	var dispatcher

class _FakeDispatcher:
	var spawned: Node = null
	var spawned_pos: Vector2 = Vector2.ZERO
	func spawn_node(node, world_pos: Vector2) -> void:
		spawned = node
		spawned_pos = world_pos

func test_feature_places_sign_with_text_at_offset() -> void:
	var feat := _Feature.new()
	feat.title = "Treasure"
	feat.body = "A safe chest."
	feat.offset = Vector2(0, -8)
	var ctx := _FakeCtx.new()
	var disp := _FakeDispatcher.new()
	ctx.dispatcher = disp
	feat.apply(ctx)
	assert_object(disp.spawned).is_not_null()
	var placed := disp.spawned as RoomSign
	assert_str(placed.title).is_equal("Treasure")
	assert_vector(disp.spawned_pos).is_equal(Vector2(100, 192))
	placed.free()
