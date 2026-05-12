class_name NailClashFX
extends RefCounted

const SCENE: PackedScene = preload("res://scenes/fx/nail_clash.tscn")

const HITSTOP_DURATION: float = 0.12
const FLASH_SCALE_DURATION: float = 0.06
const FLASH_FADE_DURATION: float = 0.18
const RING_DURATION: float = 0.20
const SHAKE_AMPLITUDE: float = 6.0
const SHAKE_DURATION: float = 0.18


static func play(pos: Vector2, normal: Vector2) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return

	var fx := SCENE.instantiate() as Node2D
	fx.global_position = pos
	tree.current_scene.add_child(fx)

	var sparks := fx.get_node_or_null("Sparks") as GPUParticles2D
	if sparks:
		sparks.restart()

	var flash := fx.get_node_or_null("Flash") as Sprite2D
	if flash:
		var tw := flash.create_tween()
		tw.tween_property(flash, "scale", Vector2(1.6, 1.6), FLASH_SCALE_DURATION)
		tw.tween_property(flash, "modulate:a", 0.0, FLASH_FADE_DURATION)

	var ring := fx.get_node_or_null("Ring") as ColorRect
	if ring and ring.material is ShaderMaterial:
		var mat: ShaderMaterial = ring.material
		mat.set_shader_parameter("radius", 0.0)
		mat.set_shader_parameter("alpha", 1.0)
		var rtw := ring.create_tween().set_parallel(true)
		rtw.tween_method(func(v: float) -> void: mat.set_shader_parameter("radius", v), 0.0, 1.0, RING_DURATION)
		rtw.tween_method(func(v: float) -> void: mat.set_shader_parameter("alpha", v), 1.0, 0.0, RING_DURATION)

	var timer := fx.get_node_or_null("LifetimeTimer") as Timer
	if timer:
		timer.timeout.connect(fx.queue_free)

	_apply_hitstop(tree)
	_apply_shake(tree)


static func _apply_hitstop(tree: SceneTree) -> void:
	Engine.time_scale = 0.0
	var t := tree.create_timer(HITSTOP_DURATION, true, false, true)
	t.timeout.connect(func() -> void: Engine.time_scale = 1.0)


static func _apply_shake(tree: SceneTree) -> void:
	var cam := tree.get_first_node_in_group("camera")
	if cam == null:
		return
	if not (cam is Camera2D):
		return
	var camera: Camera2D = cam
	var base_offset: Vector2 = camera.offset
	var elapsed: float = 0.0
	var tw := camera.create_tween()
	var steps := 6
	for i in range(steps):
		var remaining := 1.0 - float(i) / float(steps)
		var amp := SHAKE_AMPLITUDE * remaining
		var off := base_offset + Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
		tw.tween_property(camera, "offset", off, SHAKE_DURATION / float(steps))
	tw.tween_property(camera, "offset", base_offset, 0.03)
