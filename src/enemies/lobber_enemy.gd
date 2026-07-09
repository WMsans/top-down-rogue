class_name LobberEnemy
extends RangedEnemy

const SPEED_MULT: float = 0.9
const LOBBER_ATTACK_RANGE: float = 200.0
const LOBBER_WINDUP: float = 0.5
const REPOSITION_MIN_DIST: float = 60.0
const REPOSITION_MAX_DIST: float = 120.0
const REPOSITION_ARRIVE_DIST: float = 12.0

var _reposition_target: Vector2 = Vector2.ZERO
var _has_reposition_target: bool = false


func _ready() -> void:
	if weapon_resource == null:
		weapon_resource = WeaponRegistry.get_weapon_by_id("flame_lobber")
	super._ready()
	speed = _speed_base * SPEED_MULT
	_speed_base = speed
	_attack_range = LOBBER_ATTACK_RANGE
	windup_duration = LOBBER_WINDUP


func _select_sprite_textures() -> Array:
	return [LOBBER_NORMAL, LOBBER_BREATHE]


func _change_state(new_state: int) -> void:
	if new_state == State.COOLDOWN and _state == State.ATTACK:
		_pick_reposition_target()
	super._change_state(new_state)


func _pick_reposition_target() -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		_has_reposition_target = false
		return
	var away := global_position - _player_ref.global_position
	away = _safe_normalized(away) if away.length_squared() > 0.0001 else Vector2.RIGHT.rotated(randf() * TAU)
	var dist := randf_range(REPOSITION_MIN_DIST, REPOSITION_MAX_DIST)
	_reposition_target = global_position + away * dist
	_has_reposition_target = true


func _process_chase(delta: float) -> void:
	if _has_reposition_target:
		var to_target := _reposition_target - global_position
		if to_target.length() <= REPOSITION_ARRIVE_DIST:
			_has_reposition_target = false
		else:
			var move_dir := _apply_separation(_safe_normalized(to_target))
			velocity = move_dir * _get_effective_speed()
			return
	super._process_chase(delta)
