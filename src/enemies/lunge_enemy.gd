class_name LungeEnemy
extends MeleeEnemy

@export var lunge_range: float = 120.0
@export var dash_speed: float = 420.0
@export var dash_duration: float = 0.22
@export var contact_radius: float = 18.0
@export var recovery_duration: float = 1.0

const REDIRECT_MAX_ANGLE: float = PI / 6.0

var _lock_dir: Vector2 = Vector2.DOWN
var _dash_timer: float = 0.0
var _dash_hit: bool = false
var _dash_done: bool = false
var _redirected: bool = false

const DASH_FIRE_VFX_SCENE: PackedScene = preload("res://scenes/fx/dash_fire_vfx.tscn")

var _fire_vfx: DashFireVfx = null


func _init() -> void:
	carries_weapon = false


func _ready() -> void:
	super._ready()
	_attack_range = lunge_range
	windup_duration = 0.45
	cooldown_duration = recovery_duration
	scale = Vector2(1.6, 1.6)
	_fire_vfx = DASH_FIRE_VFX_SCENE.instantiate()
	add_child(_fire_vfx)


func _change_state(new_state: int) -> void:
	if new_state == State.WINDUP:
		_dash_done = false
		_play_windup_telegraph()
	super._change_state(new_state)


func _play_windup_telegraph() -> void:
	_play_hit_flash()
	_play_squash()


func _begin_dash() -> void:
	var target := global_position
	if _player_ref and is_instance_valid(_player_ref):
		var dist := global_position.distance_to(_player_ref.global_position)
		target = _predict_player_pos(dist / dash_speed)
	_lock_dir = _safe_normalized(target - global_position)
	if _lock_dir == Vector2.ZERO:
		_lock_dir = Vector2.DOWN
	_dash_timer = dash_duration
	_dash_hit = false
	_redirected = false
	_fire_vfx.start(_lock_dir)


func _moves_during_attack() -> bool:
	return _state == State.ATTACK and not _dash_done


func _process_attack(delta: float) -> void:
	if not _attack_started:
		_attack_started = true
		if _dash_done:
			_change_state(State.RECOVER)
			return
		_begin_dash()
	_tick_dash(delta)


func _tick_dash(delta: float) -> void:
	if not _redirected and _get_profile().lunge_redirect and _dash_timer <= dash_duration * 0.5:
		_redirected = true
		_lock_dir = _steer_toward_player(_lock_dir)
	velocity = _lock_dir * dash_speed
	_check_body_contact()
	_dash_timer -= delta
	if _dash_timer <= 0.0:
		_dash_done = true
		velocity = Vector2.ZERO
		_fire_vfx.stop()
		_change_state(State.RECOVER)


## One mid-dash correction toward the player's current position, capped so a
## sidestep still beats it.
func _steer_toward_player(dir: Vector2) -> Vector2:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return dir
	var to := _player_ref.global_position - global_position
	if to.length_squared() < 0.01:
		return dir
	var turn := clampf(dir.angle_to(to), -REDIRECT_MAX_ANGLE, REDIRECT_MAX_ANGLE)
	return dir.rotated(turn)


func _on_attack_cancelled() -> void:
	_dash_done = true
	velocity = Vector2.ZERO
	if _fire_vfx:
		_fire_vfx.stop()


func _check_body_contact() -> void:
	if _dash_hit:
		return
	if _player_ref == null or not is_instance_valid(_player_ref):
		return
	if global_position.distance_to(_player_ref.global_position) > contact_radius:
		return
	_dash_hit = true
	if _player_ref.has_method("on_hit_impact"):
		_player_ref.on_hit_impact(global_position, _lock_dir)
