class_name SplitBehavior
extends ProjectileBehavior

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")

var shard_count: int = 4
var damage_factor: float = 0.5
var spread_deg: float = 60.0
var shard_speed: float = 140.0
var shard_lifetime: float = 0.6
var shard_collisionless_time: float = 0.3
var spawn_offset: float = 12.0
var shard_hit_status: String = ""


func on_enemy_hit(proj, _target) -> bool:
	_split(proj, false)
	return false  # let the projectile die normally


func on_terrain_hit(proj) -> bool:
	_split(proj, true)
	return false  # let the projectile carve + die normally


func _split(proj, reverse_dir: bool = false) -> void:
	var parent: Node = proj.get_parent()
	if parent == null:
		return
	var base_angle: float = proj.direction.angle()
	if reverse_dir:
		base_angle += PI
	var half: float = deg_to_rad(spread_deg) / 2.0
	for i in range(shard_count):
		var t: float = 0.0 if shard_count == 1 else float(i) / float(shard_count - 1)
		var angle: float = base_angle + lerpf(-half, half, t)
		var shard: Projectile = PROJECTILE_SCENE.instantiate()
		shard.direction = Vector2(cos(angle), sin(angle))
		shard.damage = proj.damage * damage_factor
		shard.speed = shard_speed
		shard.lifetime = shard_lifetime
		shard.is_enemy_projectile = proj.is_enemy_projectile
		shard.source_node = proj.source_node
		shard.collisionless_time = shard_collisionless_time
		if shard_hit_status != "":
			shard.hit_status = shard_hit_status
		shard.global_position = proj.global_position + shard.direction * spawn_offset
		var src_sprite = proj.get_node_or_null("Sprite2D")
		var shard_sprite = shard.get_node_or_null("Sprite2D")
		if src_sprite != null and shard_sprite != null:
			shard_sprite.texture = src_sprite.texture
		parent.add_child(shard)
