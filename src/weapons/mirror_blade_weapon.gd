class_name MirrorBladeWeapon
extends MeleeWeapon

func _init() -> void:
	super._init()
	weapon_reach = 30.0
	arc_angle = deg_to_rad(100.0)

func _destroy_projectiles_in_arc(user: Node, origin: Vector2, direction: Vector2) -> void:
	if user == null:
		return
	var dir_angle: float = direction.angle()
	var half_arc_angle: float = arc_angle / 2.0
	var reflected: int = 0
	for node in user.get_tree().get_nodes_in_group("projectile"):
		if reflected >= 8:
			return
		if not (node is Projectile):
			continue
		var p: Projectile = node
		if not p.is_enemy_projectile:
			continue
		var to_target: Vector2 = p.global_position - origin
		var dist: float = to_target.length()
		if dist > weapon_reach or dist <= 0.001:
			continue
		if absf(angle_difference(dir_angle, to_target.angle())) > half_arc_angle:
			continue
		_reflect(p, origin)
		reflected += 1

func _reflect(p: Projectile, origin: Vector2) -> void:
	p.is_enemy_projectile = false
	var outward: Vector2 = (p.global_position - origin)
	p.direction = outward.normalized() if outward.length() > 0.001 else -p.direction
	p.source_weapon = self
	p.source_node = null
	var sprite := p.get_node_or_null("Sprite2D")
	if sprite:
		sprite.rotation = p.direction.angle() + PI * 3.0 / 4.0
	ProjectileBlockFX.play(p.global_position, -p.direction)
