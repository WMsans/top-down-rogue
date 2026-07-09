class_name SkirmisherEnemy
extends MeleeEnemy

const HP_MULT: float = 0.6
const SPEED_MULT: float = 1.4
const DAMAGE_MULT: float = 0.7
const FLANK_COMMIT_RANGE_MULT: float = 1.8
const FLANK_ANGLE_MIN: float = 0.785398
const FLANK_ANGLE_MAX: float = 1.047198

var _flank_sign: float = 1.0
var _flank_angle: float = 0.0


func _ready() -> void:
	super._ready()
	max_health = int(float(max_health) * HP_MULT)
	health = max_health
	speed = _speed_base * SPEED_MULT
	_speed_base = speed
	if weapon:
		weapon.damage *= DAMAGE_MULT
	_flank_sign = 1.0 if randf() > 0.5 else -1.0
	_flank_angle = randf_range(FLANK_ANGLE_MIN, FLANK_ANGLE_MAX)
	wander_move_time_min = 0.4
	wander_move_time_max = 1.0
	wander_pause_time_min = 0.2
	wander_pause_time_max = 0.6


func _process_chase(_delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		_aggroed = false
		_change_state(State.WANDER)
		return

	var to_player := _player_ref.global_position - global_position
	var dist := to_player.length()
	var sees := _can_see_player()

	if sees:
		_aggroed = true
	elif not _aggroed:
		_change_state(State.WANDER)
		return

	if dist < 1.0:
		velocity = Vector2.ZERO
		return

	if sees and dist <= _attack_range:
		velocity = Vector2.ZERO
		_change_state(State.WINDUP)
		return

	var move_dir: Vector2
	if sees:
		if dist <= _attack_range * FLANK_COMMIT_RANGE_MULT:
			move_dir = _safe_normalized(to_player)
		else:
			move_dir = _safe_normalized(to_player).rotated(_flank_angle * _flank_sign)
	else:
		var fd := _nav_field_dir()
		move_dir = fd if fd != Vector2.ZERO else _safe_normalized(to_player)

	move_dir = _apply_separation(move_dir)
	velocity = move_dir * _get_effective_speed()
