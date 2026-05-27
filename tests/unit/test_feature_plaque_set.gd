extends GdUnitTestSuite

const _Feature = preload("res://src/core/features/feature_plaque_set.gd")
const _Spec = preload("res://src/core/features/plaque_spec.gd")
const _Dispatcher = preload("res://src/core/composition_dispatcher.gd")

func _make_ctx(dispatcher: Node, anchor: Vector2) -> _Dispatcher.CompositionContext:
	var ctx := _Dispatcher.CompositionContext.new()
	ctx.anchor_world_pos = anchor
	ctx.rng = RandomNumberGenerator.new()
	ctx.dispatcher = dispatcher
	ctx.mask_air = func(_p: Vector2) -> bool: return true
	return ctx

func test_plaque_set_spawns_sprite_per_spec() -> void:
	var dispatcher = _Dispatcher.new()
	add_child(dispatcher)
	var parent := Node2D.new()
	add_child(parent)
	dispatcher._spawn_parent = parent

	var s1 := _Spec.new()
	s1.offset = Vector2(0, -300)
	s1.texture = PlaceholderTexture2D.new()
	s1.size = Vector2(64, 64)

	var s2 := _Spec.new()
	s2.offset = Vector2(-300, 0)
	s2.texture = PlaceholderTexture2D.new()
	s2.size = Vector2(64, 64)

	var feature := _Feature.new()
	feature.plaques = [s1, s2]
	feature.apply(_make_ctx(dispatcher, Vector2(50, 50)))

	assert_that(parent.get_child_count()).is_equal(2)
	var first := parent.get_child(0) as Sprite2D
	var second := parent.get_child(1) as Sprite2D
	assert_that(first.global_position).is_equal(Vector2(50, -250))
	assert_that(second.global_position).is_equal(Vector2(-250, 50))
	assert_that(first.texture).is_not_null()
	assert_that(second.texture).is_not_null()

func test_plaque_set_skips_spec_with_null_texture() -> void:
	var dispatcher = _Dispatcher.new()
	add_child(dispatcher)
	var parent := Node2D.new()
	add_child(parent)
	dispatcher._spawn_parent = parent

	var s := _Spec.new()
	s.offset = Vector2.ZERO
	s.texture = null
	s.size = Vector2(64, 64)

	var feature := _Feature.new()
	feature.plaques = [s]
	feature.apply(_make_ctx(dispatcher, Vector2.ZERO))

	assert_that(parent.get_child_count()).is_equal(0)
