class_name ModifierProjectile
extends RefCounted

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
const DEFAULT_TEXTURE := preload("res://textures/wall.png")
const DEFAULT_SPEED := 140.0
const DEFAULT_LIFETIME := 1.5

static func spawn_one(user: Node, origin: Vector2, direction: Vector2, damage: float,
		opts: Dictionary = {}) -> Projectile:
	var parent := _resolve_parent(user)
	if parent == null:
		return null
	var proj: Projectile = PROJECTILE_SCENE.instantiate()
	proj.direction = direction.normalized()
	proj.damage = damage
	proj.speed = opts.get("speed", DEFAULT_SPEED)
	proj.lifetime = opts.get("lifetime", DEFAULT_LIFETIME)
	proj.hit_status = opts.get("hit_status", "")
	proj.source_node = user
	proj.is_enemy_projectile = user.is_in_group("attackable") or user.is_in_group("cave_spawned")
	if opts.has("behaviors"):
		proj.behaviors = opts["behaviors"]
	var sprite: Sprite2D = proj.get_node_or_null("Sprite2D")
	if sprite != null:
		sprite.texture = opts.get("texture", DEFAULT_TEXTURE)
		if opts.has("tint"):
			sprite.modulate = opts["tint"]
	parent.add_child(proj)
	proj.global_position = origin
	return proj

static func spawn_fan(user: Node, origin: Vector2, base_dir: Vector2, damage: float,
		count: int, spread_deg: float, opts: Dictionary = {}) -> void:
	var base_angle := base_dir.angle()
	var half := deg_to_rad(spread_deg) / 2.0
	for i in range(count):
		var t: float = 0.0 if count <= 1 else float(i) / float(count - 1)
		var angle := base_angle + lerpf(-half, half, t)
		var dir := Vector2(cos(angle), sin(angle))
		var per_opts := opts.duplicate()
		if opts.has("make_behaviors"):
			per_opts["behaviors"] = opts["make_behaviors"].call()
		spawn_one(user, origin, dir, damage, per_opts)

static func _resolve_parent(user: Node) -> Node:
	if user == null:
		return null
	var tree := user.get_tree()
	if tree != null:
		var wm := tree.get_first_node_in_group("world_manager")
		if wm != null and wm.has_method("get_chunk_container"):
			var container = wm.get_chunk_container()
			if container != null:
				return container
	return user.get_parent()
