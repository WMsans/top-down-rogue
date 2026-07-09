class_name ArcherEnemy
extends RangedEnemy

const KITE_DISTANCE_MULT: float = 1.3
const KITE_SPEED_MULT: float = 1.2

func _ready() -> void:
	if weapon_resource == null:
		weapon_resource = WeaponRegistry.get_weapon_by_id("throwing_knife")
	super._ready()


func _select_sprite_textures() -> Array:
	return [ARCHER_NORMAL, ARCHER_BREATHE]


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

	var kite_distance := preferred_distance * KITE_DISTANCE_MULT
	var move_dir: Vector2
	if dist < kite_distance - 20.0:
		move_dir = -to_player.normalized()
		velocity = move_dir * _get_effective_speed() * KITE_SPEED_MULT
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
