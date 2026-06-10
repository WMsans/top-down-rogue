class_name RangedWeapon
extends Weapon

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")

@export var projectile_speed: float = 120.0
@export var projectile_lifetime: float = 3.0
@export var spread_angle: float = 0.0
@export var projectile_count: int = 1
@export var weapon_texture: Texture2D:
	set(value):
		weapon_texture = value
		icon_texture = value
@export var projectile_texture: Texture2D


func _init() -> void:
	cooldown = 1.0
	damage = 3.0
	modifier_slot_count = 3
	modifiers.resize(modifier_slot_count)
	rarity = DropTable.ItemTier.UNCOMMON


func has_visual() -> bool:
	return weapon_texture != null


func setup_visual(container: Node2D, sprite: Sprite2D) -> void:
	super.setup_visual(container, sprite)
	if weapon_texture:
		_sprite.texture = weapon_texture
		_sprite.offset = Vector2.ZERO


func update_visual(_delta: float, user: Node) -> void:
	if visual == null:
		return
	var dir := _get_facing_direction(user)
	visual.position = Vector2.ZERO
	visual.rotation = dir.angle() + PI * 5.0 / 4.0
	_sprite.position = Vector2.ZERO
	_sprite.rotation = 0.0
	_sprite.scale = Vector2.ONE


func _use_impl(user: Node) -> void:
	var direction := _get_facing_direction(user)
	var base_angle := direction.angle()
	var half_spread := deg_to_rad(spread_angle) / 2.0

	for i in range(projectile_count):
		var angle_offset: float = 0.0
		if projectile_count > 1:
			angle_offset = lerpf(-half_spread, half_spread, float(i) / float(projectile_count - 1))
		var proj_dir := Vector2(cos(base_angle + angle_offset), sin(base_angle + angle_offset))
		_spawn_projectile(user, proj_dir)
	notify_attack(user, {
		"direction": direction,
		"origin": user.global_position,
		"charged": false,
		"charge_ratio": 0.0,
	})


func _spawn_projectile(user: Node, direction: Vector2) -> void:
	var proj := PROJECTILE_SCENE.instantiate()
	proj.global_position = user.global_position
	proj.damage = damage
	proj.crit_chance = get_effective_crit_chance()
	proj.crit_multiplier = crit_multiplier
	proj.crit_status = crit_status
	proj.speed = projectile_speed
	proj.lifetime = projectile_lifetime
	proj.direction = direction.normalized()
	proj.source_node = user
	if projectile_texture:
		var proj_sprite := proj.get_node_or_null("Sprite2D")
		if proj_sprite:
			proj_sprite.texture = projectile_texture
	proj.is_enemy_projectile = user.is_in_group("attackable") or user.is_in_group("cave_spawned")
	var world := user.get_tree().get_first_node_in_group("world_manager")
	if world:
		world.get_chunk_container().add_child(proj)
	else:
		user.get_parent().add_child(proj)


func _get_facing_direction(user: Node) -> Vector2:
	if user.has_method("get_facing_direction"):
		return user.get_facing_direction()
	if "velocity" in user:
		var vel = user.get("velocity")
		if vel is Vector2 and vel.length_squared() > 0.01:
			return vel.normalized()
	return Vector2.DOWN
