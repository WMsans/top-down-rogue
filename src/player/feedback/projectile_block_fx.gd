class_name ProjectileBlockFX
extends RefCounted

const SCENE: PackedScene = preload("res://scenes/fx/projectile_block.tscn")


static func play(pos: Vector2, dir: Vector2) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	var fx := SCENE.instantiate() as Node2D
	fx.global_position = pos
	if dir.length_squared() > 0.0001:
		fx.rotation = dir.angle()
	tree.current_scene.add_child(fx)
	var sparks := fx.get_node_or_null("Sparks") as GPUParticles2D
	if sparks:
		sparks.restart()
		sparks.emitting = true
	var flash := fx.get_node_or_null("Flash") as Sprite2D
	if flash:
		var tw := flash.create_tween()
		tw.tween_property(flash, "scale", Vector2.ONE, 0.03)
		tw.tween_property(flash, "modulate:a", 0.0, 0.08)
	var timer := fx.get_node_or_null("LifetimeTimer") as Timer
	if timer:
		timer.timeout.connect(fx.queue_free)
