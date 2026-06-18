class_name SniperEnemy
extends RangedEnemy

@export var lock_time: float = 0.3

var _aim_locked: bool = false
var _lock_dir: Vector2 = Vector2.DOWN
var _aim_line: Line2D = null


func _ready() -> void:
	if weapon_resource == null:
		weapon_resource = SniperWeapon.new()
	super._ready()
	windup_duration = 1.2
	cooldown_duration = weapon.cooldown if weapon else 2.5
	_aim_line = Line2D.new()
	_aim_line.width = 1.5
	_aim_line.default_color = Color(1.0, 0.7, 0.2, 0.5)
	_aim_line.visible = false
	add_child(_aim_line)


func _process_windup(delta: float) -> void:
	if not _aim_locked and _state_timer <= lock_time:
		_lock_aim()
	_update_aim_line()
	super._process_windup(delta)


func _lock_aim() -> void:
	_lock_dir = _to_player_dir()
	_aim_locked = true
	if _aim_line:
		_aim_line.default_color = Color(1.0, 0.2, 0.2, 0.9)


func _update_aim_line() -> void:
	if _aim_line == null:
		return
	var dir := _lock_dir if _aim_locked else _to_player_dir()
	_aim_line.visible = true
	_aim_line.points = PackedVector2Array([Vector2.ZERO, dir * 600.0])


func _to_player_dir() -> Vector2:
	if _player_ref and is_instance_valid(_player_ref):
		var d := _player_ref.global_position - global_position
		if d.length() > 0.01:
			return d.normalized()
	return Vector2.DOWN


func get_facing_direction() -> Vector2:
	if _aim_locked:
		return _lock_dir
	return _to_player_dir()


func _change_state(new_state: int) -> void:
	if new_state != State.WINDUP and new_state != State.ATTACK:
		_aim_locked = false
		if _aim_line:
			_aim_line.visible = false
			_aim_line.default_color = Color(1.0, 0.7, 0.2, 0.5)
	super._change_state(new_state)