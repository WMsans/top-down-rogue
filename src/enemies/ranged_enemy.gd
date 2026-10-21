class_name RangedEnemy
extends Enemy

@export var weapon_resource: RangedWeapon = null

@export var preferred_distance: float = 120.0
@export var strafe_speed: float = 40.0
@export var back_away_acceleration: float = 200.0

const SPOT_REFRESH: float = 1.5
const REPOSITION_MIN: float = 0.6
const REPOSITION_MAX: float = 1.2

var _strafe_direction: float = 1.0
var _strafe_re_roll: float = 0.0
var _has_spot: bool = false
var _spot_timer: float = 0.0
var _alert_broadcast: bool = false
var _rng := RandomNumberGenerator.new()


func token_cost() -> float:
	return 0.5


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
		_speed_base = speed
		cooldown_duration = weapon.cooldown
	detection_radius = 250.0
	windup_duration = 0.4
	_rng.randomize()
	super._ready()
	_apply_volley_bonus()
	_setup_drop_table()


## Fans get wider, single-shot weapons get longer bursts.
func _apply_volley_bonus() -> void:
	var rw := weapon as RangedWeapon
	if rw == null:
		return
	var bonus := _get_profile().volley_bonus
	if bonus <= 0:
		return
	if rw.projectile_count > 1:
		rw.projectile_count += bonus
	else:
		rw.burst_count += bonus


func get_facing_direction() -> Vector2:
	var rw := weapon as RangedWeapon
	return _dir_to_predicted(rw.projectile_speed if rw != null else 0.0)


## Soul Knight loop: walk to a firing spot, stop, volley, then move again.
func _process_chase(delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref) or not _player_in_range:
		_aggroed = false
		_change_state(State.WANDER)
		return
	var sees := _can_see_player()
	if sees:
		_aggroed = true
		# The claim already set _aggroed, so the alert has its own one-shot flag.
		if not _alert_broadcast:
			_alert_broadcast = true
			_broadcast_alert()

	_spot_timer -= delta
	if not _has_spot or _spot_timer <= 0.0 or not sees:
		if _pick_spot_and_move():
			return
		if not sees:
			_change_state(State.WANDER)
			return

	var to_player := _player_ref.global_position - global_position
	var dist := to_player.length()
	if dist < 1.0:
		velocity = Vector2.ZERO
		return

	_strafe_re_roll -= delta
	if _strafe_re_roll <= 0.0:
		_strafe_direction = 1.0 if randf() > 0.5 else -1.0
		_strafe_re_roll = 1.5
	var perpendicular := Vector2(-to_player.y, to_player.x).normalized()
	velocity = _apply_separation(perpendicular * _strafe_direction) * strafe_speed

	if dist <= _attack_range and _try_take_token():
		_change_state(State.WINDUP)


# Returns true when it started a REPOSITION. With no valid spot it keeps the
# current position (strafing) until the next refresh.
func _pick_spot_and_move() -> bool:
	_spot_timer = SPOT_REFRESH
	_has_spot = true
	var dir = _get_director()
	var taken: Array = dir.get_taken_spots(self) if dir != null else []
	var solid: Callable = dir.solid_check if dir != null else Callable()
	var spot := FiringSpotPicker.pick(global_position, _player_ref.global_position, taken, solid,
			_has_line_of_sight, _rng)
	if spot == Vector2.INF:
		return false
	if dir != null:
		dir.claim_spot(self, spot)
		# A claimed spot means the enemy joined the fight, so it counts as
		# pursuing: the claim survives the director's prune and it can be
		# granted a token.
		_aggroed = true
	_begin_reposition(spot, _rng.randf_range(REPOSITION_MIN, REPOSITION_MAX))
	return true


func _state_after_attack() -> int:
	_has_spot = false
	return State.RECOVER


func _setup_drop_table() -> void:
	drop_table = DropTable.from_enemy_tier(enemy_tier)


func _execute_attack() -> void:
	if weapon and _player_ref and is_instance_valid(_player_ref):
		weapon.use(self)
