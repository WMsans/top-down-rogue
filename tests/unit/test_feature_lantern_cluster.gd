extends GdUnitTestSuite

const _Feature = preload("res://src/core/features/feature_lantern_cluster.gd")
const _Spec = preload("res://src/core/features/lantern_spec.gd")
const _Dispatcher = preload("res://src/core/composition_dispatcher.gd")
const _LanternScene = preload("res://scenes/props/lantern.tscn")

func _make_ctx(dispatcher: Node, anchor: Vector2) -> _Dispatcher.CompositionContext:
	var ctx := _Dispatcher.CompositionContext.new()
	ctx.anchor_world_pos = anchor
	ctx.rng = RandomNumberGenerator.new()
	ctx.dispatcher = dispatcher
	ctx.mask_air = func(_p: Vector2) -> bool: return true
	return ctx

func test_lantern_cluster_spawns_one_per_spec_at_offsets() -> void:
	var dispatcher = _Dispatcher.new()
	add_child(dispatcher)
	var parent := Node2D.new()
	add_child(parent)
	dispatcher._spawn_parent = parent

	var s1 := _Spec.new()
	s1.offset = Vector2(-200, -200)
	s1.prop_scene = _LanternScene
	s1.light_color = Color(1, 0.8, 0.5, 1)
	s1.light_energy = 1.5
	s1.light_radius = 400.0
	s1.flicker_amplitude = 0.1

	var s2 := _Spec.new()
	s2.offset = Vector2(200, 200)
	s2.prop_scene = _LanternScene
	s2.light_color = Color(1, 0.8, 0.5, 1)
	s2.light_energy = 1.5
	s2.light_radius = 400.0
	s2.flicker_amplitude = 0.1

	var feature := _Feature.new()
	feature.lanterns = [s1, s2]
	feature.apply(_make_ctx(dispatcher, Vector2(100, 100)))

	assert_that(parent.get_child_count()).is_equal(2)
	var first := parent.get_child(0) as Node2D
	var second := parent.get_child(1) as Node2D
	assert_that(first.global_position).is_equal(Vector2(-100, -100))
	assert_that(second.global_position).is_equal(Vector2(300, 300))

func test_lantern_cluster_empty_array_spawns_nothing() -> void:
	var dispatcher = _Dispatcher.new()
	add_child(dispatcher)
	var parent := Node2D.new()
	add_child(parent)
	dispatcher._spawn_parent = parent

	var feature := _Feature.new()
	feature.lanterns = []
	feature.apply(_make_ctx(dispatcher, Vector2.ZERO))

	assert_that(parent.get_child_count()).is_equal(0)
