extends GdUnitTestSuite

const _Feature = preload("res://src/core/features/feature_floor_overlay.gd")
const _Dispatcher = preload("res://src/core/composition_dispatcher.gd")

func _make_ctx(dispatcher: Node, anchor: Vector2) -> _Dispatcher.CompositionContext:
	var ctx := _Dispatcher.CompositionContext.new()
	ctx.anchor_world_pos = anchor
	ctx.rng = RandomNumberGenerator.new()
	ctx.dispatcher = dispatcher
	ctx.mask_air = func(_p: Vector2) -> bool: return true
	return ctx

func test_floor_overlay_spawns_sprite_at_offset() -> void:
	var dispatcher = _Dispatcher.new()
	add_child(dispatcher)
	var parent := Node2D.new()
	add_child(parent)
	dispatcher._spawn_parent = parent

	var feature := _Feature.new()
	feature.texture = PlaceholderTexture2D.new()
	feature.radius = 120.0
	feature.offset = Vector2(0, 0)
	feature.z_index_value = -5

	feature.apply(_make_ctx(dispatcher, Vector2(200, 300)))

	assert_that(parent.get_child_count()).is_equal(1)
	var poly := parent.get_child(0) as Polygon2D
	assert_that(poly).is_not_null()
	assert_that(poly.global_position).is_equal(Vector2(200, 300))
	assert_that(poly.z_index).is_equal(-5)
	assert_that(poly.texture).is_not_null()
