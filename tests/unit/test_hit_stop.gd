extends GdUnitTestSuite

# Regression: hit-stop used Engine.time_scale = 0.0, which makes the physics
# server step with dt = 0. Godot's contact solver divides by the step, so
# overlapping RigidBody2Ds (stacked weapon drops from kills) went NaN and the
# physics frame time ballooned to hundreds of ms for the rest of the run.

const DROP_SCENE := preload("res://scenes/drop.tscn")


func after_test() -> void:
	Engine.time_scale = 1.0


func _spawn_overlapping_drops(count: int) -> Array[RigidBody2D]:
	var drops: Array[RigidBody2D] = []
	for i in count:
		var d: RigidBody2D = auto_free(DROP_SCENE.instantiate())
		d.position = Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
		add_child(d)
		drops.append(d)
	return drops


func _count_non_finite(drops: Array[RigidBody2D]) -> int:
	var n := 0
	for d in drops:
		var p := d.global_position
		if not (is_finite(p.x) and is_finite(p.y)):
			n += 1
	return n


func test_hit_reaction_hit_stop_never_zeroes_time_scale() -> void:
	HitReaction._do_hit_stop(true)
	assert_float(Engine.time_scale).is_greater(0.0)
	assert_float(Engine.time_scale).is_less(1.0)


func test_nail_clash_hit_stop_never_zeroes_time_scale() -> void:
	NailClashFX._apply_hitstop(get_tree())
	assert_float(Engine.time_scale).is_greater(0.0)
	assert_float(Engine.time_scale).is_less(1.0)


func test_overlapping_drops_stay_finite_through_hit_stop() -> void:
	var drops := _spawn_overlapping_drops(12)
	await get_tree().physics_frame
	HitReaction._do_hit_stop(true)
	for i in 20:
		await get_tree().physics_frame
	assert_int(_count_non_finite(drops)).is_equal(0)
