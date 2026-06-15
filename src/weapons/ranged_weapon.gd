class_name RangedWeapon
extends Weapon

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")

@export var projectile_speed: float = 120.0
@export var projectile_lifetime: float = 3.0
@export var spread_angle: float = 0.0
@export var projectile_count: int = 1
@export var burst_count: int = 1
@export var burst_interval: float = 0.12
@export var reaim_each_shot: bool = false
@export var weapon_texture: Texture2D = preload("res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/16x16/bow_01a.png"):
	set(value):
		weapon_texture = value
		icon_texture = value
@export var projectile_texture: Texture2D = preload("res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/16x16/arrow_01a.png")

var shot_sink: Callable = Callable()
var _shots_left: int = 0
var _burst_timer: float = 0.0
var _burst_dir: Vector2 = Vector2.RIGHT
var _burst_user: Node = null


func _init() -> void:
	cooldown = 1.0
	damage = 3.0
	modifier_slot_count = 3
	modifiers.resize(modifier_slot_count)
	rarity = DropTable.ItemTier.UNCOMMON
	icon_texture = weapon_texture
	_configure()


func _configure() -> void:
	pass


func _make_behaviors() -> Array:
	return []


func _seed_effective_stats() -> Dictionary:
	var s := super._seed_effective_stats()
	return s


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
	_burst_user = user
	_burst_dir = _get_facing_direction(user)
	_shots_left = maxi(0, burst_count - 1)
	_burst_timer = burst_interval
	_emit_shot(user, _burst_dir)


func _tick_impl(delta: float) -> void:
	if _shots_left <= 0:
		return
	if not is_instance_valid(_burst_user):
		_shots_left = 0
		return
	_burst_timer -= delta
	if _burst_timer <= 0.0:
		_burst_timer += burst_interval
		_burst_dir = _get_facing_direction(_burst_user) if reaim_each_shot else _burst_dir
		_emit_shot(_burst_user, _burst_dir)
		_shots_left -= 1


func is_bursting() -> bool:
	return _shots_left > 0


func _emit_shot(user: Node, base_dir: Vector2) -> void:
	var base_angle := base_dir.angle()
	var half_spread := deg_to_rad(spread_angle) / 2.0
	for i in range(projectile_count):
		var angle_offset: float = 0.0
		if projectile_count > 1:
			angle_offset = lerpf(-half_spread, half_spread, float(i) / float(projectile_count - 1))
		var proj_dir := Vector2(cos(base_angle + angle_offset), sin(base_angle + angle_offset))
		_spawn_projectile(user, proj_dir)
	notify_attack(user, {
		"direction": base_dir,
		"origin": user.global_position,
		"charged": false,
		"charge_ratio": 0.0,
	})


func _spawn_projectile(user: Node, direction: Vector2) -> void:
	if shot_sink.is_valid():
		shot_sink.call(direction.normalized())
		return
	var proj := PROJECTILE_SCENE.instantiate()
	proj.behaviors = _make_behaviors()
	proj.global_position = user.global_position
	proj.damage = get_effective_stats()["damage"]
	proj.crit_chance = get_effective_crit_chance()
	proj.crit_multiplier = crit_multiplier
	proj.crit_status = crit_status
	proj.speed = projectile_speed
	proj.lifetime = projectile_lifetime
	proj.direction = direction.normalized()
	proj.source_node = user
	proj.source_weapon = self
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
