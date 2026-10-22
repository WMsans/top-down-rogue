class_name MeleeEnemy
extends Enemy

@export var weapon_resource: MeleeWeapon = null


func _ready() -> void:
	if not carries_weapon:
		weapon = null
		_attack_range = 28.0
		speed = 60.0
		_speed_base = speed
		cooldown_duration = 0.8
	elif weapon_resource:
		weapon = weapon_resource.duplicate()
		_attack_range = weapon.weapon_reach
		cooldown_duration = weapon_resource.cooldown
		speed = 60.0
	else:
		weapon = MeleeWeapon.new()
		_attack_range = 28.0
		speed = 60.0
		_speed_base = speed
		cooldown_duration = weapon.cooldown
	super._ready()
	_setup_drop_table()


func _setup_drop_table() -> void:
	drop_table = DropTable.from_enemy_tier(enemy_tier)


func _execute_attack() -> void:
	if weapon and _player_ref and is_instance_valid(_player_ref):
		weapon.use(self)


const AIM_LOCK_TIME: float = 0.1
const CHAIN_WINDUP: float = 0.2
const CHAIN_REACH_BONUS: float = 16.0
const CHAIN_STEP: float = 16.0

var _aim_locked: bool = false
var _aim_lock_dir: Vector2 = Vector2.DOWN
var _swings_done: int = 0
var _chain_pending: bool = false


## The swing follows the player through the windup and only commits in the
## last AIM_LOCK_TIME, so dodging is about timing, not leaving early.
func _process_windup(delta: float) -> void:
	if not _aim_locked and _state_timer <= AIM_LOCK_TIME:
		_aim_lock_dir = super.get_facing_direction()
		_aim_locked = true
	super._process_windup(delta)


func get_facing_direction() -> Vector2:
	if _aim_locked:
		return _aim_lock_dir
	return super.get_facing_direction()


func _change_state(new_state: int) -> void:
	if new_state != State.ATTACK:
		_aim_locked = false
	super._change_state(new_state)
	if new_state == State.WINDUP:
		if _chain_pending:
			_chain_pending = false
			_state_timer = CHAIN_WINDUP * _get_profile().telegraph_mult
		else:
			_swings_done = 0


func _state_after_attack() -> int:
	_swings_done += 1
	if _can_chain():
		_chain_pending = true
		_step_toward_player(CHAIN_STEP)
		if weapon:
			weapon.reset_cooldown()
		return State.WINDUP
	return State.RECOVER


func _can_chain() -> bool:
	if _swings_done >= _get_profile().chain_attacks:
		return false
	if _player_ref == null or not is_instance_valid(_player_ref):
		return false
	return global_position.distance_to(_player_ref.global_position) <= _attack_range + CHAIN_REACH_BONUS


# Wall-safe step: crowd pushes are clamped per axis and capped below one nav cell.
func _step_toward_player(distance: float) -> void:
	var dir := _safe_normalized(_player_ref.global_position - global_position)
	var remaining := distance
	while remaining > 0.0:
		var s := minf(remaining, CROWD_PUSH_CAP)
		_apply_crowd_push(dir * s)
		remaining -= s
