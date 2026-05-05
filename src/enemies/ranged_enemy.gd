class_name RangedEnemy
extends Enemy

@export var weapon_resource: RangedWeapon = null

@export var preferred_distance: float = 120.0
@export var strafe_speed: float = 40.0
@export var back_away_acceleration: float = 200.0

var _strafe_direction: float = 1.0
var _strafe_re_roll: float = 0.0


func _ready() -> void:
	if weapon_resource:
		weapon = weapon_resource.duplicate()
		_attack_range = preferred_distance * 1.5
		cooldown_duration = weapon_resource.cooldown
	else:
		weapon = RangedWeapon.new()
		_attack_range = 180.0
		speed = 50.0
		max_health = 12
		_speed_base = speed
		cooldown_duration = weapon.cooldown
	detection_radius = 250.0
	windup_duration = 0.4
	min_attack_settle_time = 0.5
	super._ready()
	_setup_drop_table()


func _setup_drop_table() -> void:
	drop_table = DropTable.from_enemy_tier(enemy_tier)


func _process_chase(delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		_change_state(State.IDLE)
		return
	if not _player_in_range:
		_change_state(State.IDLE)
		return

	var to_player := _player_ref.global_position - global_position
	var dist := to_player.length()
	if dist < 1.0:
		return

	var move_dir := to_player.normalized()

	if dist < preferred_distance - 20.0:
		move_dir = -to_player.normalized()
		global_position += move_dir * speed * delta
	elif dist > preferred_distance + 20.0:
		global_position += move_dir * speed * delta
	else:
		_strafe_re_roll -= delta
		if _strafe_re_roll <= 0.0:
			_strafe_direction = 1.0 if randf() > 0.5 else -1.0
			_strafe_re_roll = 1.5
		var perpendicular := Vector2(-to_player.y, to_player.x).normalized()
		global_position += perpendicular * _strafe_direction * strafe_speed * delta

	move_dir = _apply_separation(move_dir)

	if dist <= _attack_range and _settle_timer >= min_attack_settle_time:
		_change_state(State.WINDUP)


func _execute_attack() -> void:
	if weapon and _player_ref and is_instance_valid(_player_ref):
		weapon.use(self)
