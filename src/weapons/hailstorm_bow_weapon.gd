class_name HailstormBowWeapon
extends RangedWeapon

@export var volley_count: int = 12
@export var volley_spread_deg: float = 120.0
@export var speed_jitter: float = 40.0

func _configure() -> void:
	damage = 2.5
	cooldown = 1.4
	projectile_count = 1   # base spread path unused; _emit_shot overridden
	spread_angle = 0.0
	projectile_speed = 150.0
	projectile_lifetime = 1.2

func _emit_shot(user: Node, base_dir: Vector2) -> void:
	var base_angle: float = base_dir.angle()
	var half: float = deg_to_rad(volley_spread_deg) / 2.0
	var base_speed: float = projectile_speed
	for i in range(volley_count):
		var jitter: float = randf_range(-half, half)
		var ang: float = base_angle + jitter
		var dir := Vector2(cos(ang), sin(ang))
		projectile_speed = base_speed + randf_range(-speed_jitter, speed_jitter)
		_spawn_projectile(user, dir)
	projectile_speed = base_speed
	notify_attack(user, {
		"direction": base_dir,
		"origin": user.global_position,
		"charged": false,
		"charge_ratio": 0.0,
	})
