class_name NailClashFX
extends RefCounted

const SCENE: PackedScene = preload("res://scenes/fx/nail_clash.tscn")

const HITSTOP_DURATION: float = 0.06
const FLASH_DURATION: float = 0.14
const SLASH_DURATION: float = 0.12
const RING_DURATION: float = 0.20
const RING2_DELAY: float = 0.04
const RING2_DURATION: float = 0.24
const SHAKE_AMPLITUDE: float = 1.5
const SHAKE_DURATION: float = 0.10
const FX_SCALE: float = 0.55


static func play(pos: Vector2, normal: Vector2, tint: Color = Color(1, 1, 1, 1)) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var host: Node = _find_world_host(tree)
	if host == null:
		return

	var fx := SCENE.instantiate() as Node2D
	host.add_child(fx)
	fx.global_position = pos
	var ang := normal.angle() if normal.length_squared() > 0.0001 else 0.0
	fx.rotation = ang
	fx.scale = Vector2(FX_SCALE, FX_SCALE)

	var spark_tint := Color(tint.r, tint.g, tint.b, 0.7)
	var sparks := fx.get_node_or_null("Sparks") as GPUParticles2D
	if sparks:
		sparks.self_modulate = spark_tint
		sparks.restart()
	var sf := fx.get_node_or_null("StreaksFwd") as GPUParticles2D
	if sf:
		sf.self_modulate = spark_tint
		sf.restart()
	var sb := fx.get_node_or_null("StreaksBack") as GPUParticles2D
	if sb:
		sb.self_modulate = spark_tint
		sb.restart()

	_play_flash(fx.get_node_or_null("Flash") as ColorRect, tint)
	_play_slash(fx.get_node_or_null("Slash") as ColorRect, tint)
	_play_ring(fx.get_node_or_null("Ring") as ColorRect, 0.0, RING_DURATION, 1.0, tint)
	_play_ring(fx.get_node_or_null("Ring2") as ColorRect, RING2_DELAY, RING2_DURATION, 1.0, tint)

	var timer := fx.get_node_or_null("LifetimeTimer") as Timer
	if timer:
		timer.timeout.connect(fx.queue_free)

	_apply_hitstop(tree)
	_apply_shake(tree)


static func _find_world_host(tree: SceneTree) -> Node:
	var cam := tree.get_first_node_in_group("camera")
	if cam is Node2D:
		var n: Node = (cam as Node).get_parent()
		while n != null and not (n is Viewport):
			if n is Node2D:
				return n
			n = n.get_parent()
		if n is Viewport:
			return n
	var player := tree.get_first_node_in_group("player")
	if player is Node2D:
		return (player as Node).get_parent()
	return tree.current_scene


static func _play_flash(rect: ColorRect, tint: Color) -> void:
	if rect == null or not (rect.material is ShaderMaterial):
		return
	var mat: ShaderMaterial = rect.material
	var hot := Color(maxf(tint.r, 1.1), maxf(tint.g, 1.1), maxf(tint.b, 1.1), 0.7)
	mat.set_shader_parameter("core_color", hot)
	mat.set_shader_parameter("halo_color", Color(tint.r, tint.g, tint.b, tint.a * 0.6))
	mat.set_shader_parameter("intensity", 0.55)
	rect.scale = Vector2(0.35, 0.35)
	var tw := rect.create_tween().set_parallel(true)
	tw.tween_property(rect, "scale", Vector2(1.0, 1.0), FLASH_DURATION)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("intensity", v), 0.55, 0.0, FLASH_DURATION)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


static func _play_slash(rect: ColorRect, tint: Color) -> void:
	if rect == null or not (rect.material is ShaderMaterial):
		return
	var mat: ShaderMaterial = rect.material
	mat.set_shader_parameter("streak_color", Color(tint.r, tint.g, tint.b, tint.a * 0.6))
	mat.set_shader_parameter("intensity", 0.5)
	mat.set_shader_parameter("thickness", 0.025)
	rect.scale = Vector2(0.2, 0.2)
	var tw := rect.create_tween().set_parallel(true)
	tw.tween_property(rect, "scale", Vector2(0.9, 0.9), SLASH_DURATION)\
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("thickness", v), 0.025, 0.003, SLASH_DURATION)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("intensity", v), 0.5, 0.0, SLASH_DURATION)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


static func _play_ring(rect: ColorRect, delay: float, duration: float, scale_mul: float, tint: Color) -> void:
	if rect == null or not (rect.material is ShaderMaterial):
		return
	var mat: ShaderMaterial = rect.material
	mat.set_shader_parameter("ring_color", Color(tint.r, tint.g, tint.b, tint.a * 0.55))
	mat.set_shader_parameter("radius", 0.0)
	mat.set_shader_parameter("alpha", 0.55)
	rect.scale = Vector2(scale_mul, scale_mul)
	var tw := rect.create_tween().set_parallel(true)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("radius", v), 0.0, 1.0, duration)\
		.set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("alpha", v), 0.55, 0.0, duration)\
		.set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(rect, "scale", Vector2(scale_mul * 1.5, scale_mul * 1.5), duration)\
		.set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


static func _apply_hitstop(tree: SceneTree) -> void:
	Engine.time_scale = 0.0
	var t := tree.create_timer(HITSTOP_DURATION, true, false, true)
	t.timeout.connect(func() -> void: Engine.time_scale = 1.0)


static func _apply_shake(tree: SceneTree) -> void:
	var cam := tree.get_first_node_in_group("camera")
	if not (cam is Camera2D):
		return
	var camera: Camera2D = cam
	var base_offset: Vector2 = camera.offset
	var tw := camera.create_tween()
	var steps := 8
	for i in range(steps):
		var remaining := 1.0 - float(i) / float(steps)
		var amp := SHAKE_AMPLITUDE * remaining
		var off := base_offset + Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
		tw.tween_property(camera, "offset", off, SHAKE_DURATION / float(steps))
	tw.tween_property(camera, "offset", base_offset, 0.04)
