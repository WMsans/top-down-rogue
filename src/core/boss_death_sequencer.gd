class_name BossDeathSequencer
extends Node

var _spawn_parent: Node = null
var _portal_scene: PackedScene = null
var _fast: bool = false
var _tween_factory: Callable = Callable()
var camera_fx: Node = null
var shake_callback: Callable = Callable()


func configure(spawn_parent: Node, portal_scene: PackedScene, _drop_scene: PackedScene, fast: bool = false) -> void:
	_spawn_parent = spawn_parent
	_portal_scene = portal_scene
	_fast = fast


func play(boss: BossEnemy, arena_center: Vector2, edge_color: Color, drop_scene: PackedScene) -> void:
	var sprite := boss.get_node_or_null("Sprite2D") as Sprite2D
	if camera_fx and camera_fx.has_method("hit_stop"):
		camera_fx.hit_stop(0.05)
	if shake_callback.is_valid():
		shake_callback.call(3.0, 0.4)
	if sprite:
		var pts := _sample_silhouette_points(sprite, 32)
		for p in pts:
			_spawn_fragment(p, arena_center, edge_color)
	if sprite:
		var dur := 0.3 if _fast else 1.4
		var tween := FX.dissolve(sprite, dur, edge_color)
		if tween and not _fast:
			await tween.finished
		elif _fast:
			(sprite.material as ShaderMaterial).set_shader_parameter("progress", 1.0)
	if _portal_scene and _spawn_parent:
		var portal := _portal_scene.instantiate()
		portal.global_position = arena_center
		_spawn_parent.add_child(portal)
	if drop_scene and _spawn_parent and boss.weapon:
		var drop := drop_scene.instantiate()
		drop.global_position = boss.global_position
		_spawn_parent.add_child(drop)
		var target := boss.global_position + (arena_center - boss.global_position).normalized() * 60
		var t := drop.create_tween()
		t.tween_property(drop, "global_position", target, 0.5).set_trans(Tween.TRANS_SINE)
	if sprite and not _fast:
		FX.clear(sprite)
	boss.queue_free()


func _spawn_fragment(world_pos: Vector2, portal_pos: Vector2, tint: Color) -> void:
	if _spawn_parent == null:
		return
	var frag := Sprite2D.new()
	frag.texture = EnemyVfxShared.soft_dot_texture(8)
	frag.modulate = tint
	frag.global_position = world_pos
	frag.z_index = 6
	_spawn_parent.add_child(frag)
	var t := frag.create_tween()
	t.set_parallel(true)
	t.tween_property(frag, "global_position", portal_pos, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property(frag, "scale", Vector2.ZERO, 1.0).set_trans(Tween.TRANS_SINE)
	t.tween_property(frag, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_LINEAR)
	t.chain().tween_callback(frag.queue_free)


func _sample_silhouette_points(sprite: Sprite2D, count: int) -> Array[Vector2]:
	var tex := sprite.texture
	if tex == null:
		return []
	var img: Image = tex.get_image() if tex.has_method("get_image") else (tex as ImageTexture).get_image()
	var size := img.get_size()
	var half := Vector2(size) * 0.5
	var origin := sprite.global_position
	var accepted: Array[Vector2] = []
	var attempts := 0
	var max_attempts := count * 8
	while accepted.size() < count and attempts < max_attempts:
		attempts += 1
		var lx := randi() % size.x
		var ly := randi() % size.y
		var pix := img.get_pixel(lx, ly)
		if pix.a > 0.1:
			var world := origin + Vector2(lx - half.x, ly - half.y)
			accepted.append(world)
	return accepted
