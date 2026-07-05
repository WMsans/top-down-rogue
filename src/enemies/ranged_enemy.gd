class_name RangedEnemy
extends Enemy

@export var weapon_resource: RangedWeapon = null

@export var preferred_distance: float = 120.0
@export var strafe_speed: float = 40.0
@export var back_away_acceleration: float = 200.0

const ARCHER_NORMAL: Texture2D = preload("res://textures/Enemies/caves/archer/caves_archer1.png")
const ARCHER_BREATHE: Texture2D = preload("res://textures/Enemies/caves/archer/caves_archer2.png")
const LOBBER_NORMAL: Texture2D = preload("res://textures/Enemies/caves/lobber/caves_lobber1.png")
const LOBBER_BREATHE: Texture2D = preload("res://textures/Enemies/caves/lobber/caves_lobber2.png")

var _strafe_direction: float = 1.0
var _strafe_re_roll: float = 0.0


func _attack_in_progress() -> bool:
	return weapon != null and weapon.is_bursting()


func _ready() -> void:
	if weapon_resource:
		weapon = weapon_resource.duplicate()
		_attack_range = preferred_distance * 1.5
		cooldown_duration = weapon_resource.cooldown
		speed = 50.0
	else:
		weapon = RangedWeapon.new()
		_attack_range = 180.0
		speed = 50.0
		max_health = 12
		_speed_base = speed
		cooldown_duration = weapon.cooldown
	detection_radius = 250.0
	windup_duration = 0.4
	super._ready()
	_setup_drop_table()
	_apply_sprite_variant()


func _setup_drop_table() -> void:
	drop_table = DropTable.from_enemy_tier(enemy_tier)


func _process_chase(delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		_change_state(State.WANDER)
		return
	if not _player_in_range:
		_change_state(State.WANDER)
		return
	if not _can_see_player():
		_change_state(State.WANDER)
		return

	var to_player := _player_ref.global_position - global_position
	var dist := to_player.length()
	if dist < 1.0:
		velocity = Vector2.ZERO
		return

	var move_dir: Vector2

	if dist < preferred_distance - 20.0:
		move_dir = -to_player.normalized()
		velocity = move_dir * _get_effective_speed()
	elif dist > preferred_distance + 20.0:
		move_dir = to_player.normalized()
		velocity = move_dir * _get_effective_speed()
	else:
		_strafe_re_roll -= delta
		if _strafe_re_roll <= 0.0:
			_strafe_direction = 1.0 if randf() > 0.5 else -1.0
			_strafe_re_roll = 1.5
		var perpendicular := Vector2(-to_player.y, to_player.x).normalized()
		velocity = perpendicular * _strafe_direction * strafe_speed

	velocity = _apply_separation(velocity)

	if dist <= _attack_range:
		_change_state(State.WINDUP)
		return


func _execute_attack() -> void:
	if weapon and _player_ref and is_instance_valid(_player_ref):
		weapon.use(self)


func _select_sprite_textures() -> Array:
	if weapon_resource is SplitShotWeapon or weapon_resource is FanWeapon:
		return [LOBBER_NORMAL, LOBBER_BREATHE]
	return [ARCHER_NORMAL, ARCHER_BREATHE]


func _apply_sprite_variant() -> void:
	var textures := _select_sprite_textures()
	var sprite := get_node_or_null("Sprite2D")
	if sprite:
		sprite.texture = textures[0]
	var animator := get_node_or_null("EnemyAnimator")
	if animator:
		animator.set_textures(textures[0], textures[1])
		animator._timer = EnemyAnimator.IDLE_INTERVAL
