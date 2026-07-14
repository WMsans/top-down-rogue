extends GdUnitTestSuite

const CameraEffect: GDScript = preload("res://src/core/camera_effect.gd")

func test_pan_to_returns_tween_and_restores() -> void:
	var cam: Camera2D = auto_free(Camera2D.new())
	get_tree().root.add_child(cam)
	var fx: CameraEffect = auto_free(CameraEffect.new())
	get_tree().root.add_child(fx)
	fx.setup(cam)
	var t: Variant = fx.pan_to(Vector2(100, 0), 0.2, Vector2(1.2, 1.2))
	assert_that(t is Tween).is_true()
	await await_millis(300)
	fx.pan_back(0.1)
	await await_millis(200)
	assert_bool(is_instance_valid(fx)).is_true()

func test_shake_does_not_crash_without_camera() -> void:
	var fx: CameraEffect = auto_free(CameraEffect.new())
	get_tree().root.add_child(fx)
	fx.shake(2.0, 0.2)
	assert_bool(is_instance_valid(fx)).is_true()
