class_name LungeEnemy
extends MeleeEnemy

@export var lunge_range: float = 120.0
@export var dash_speed: float = 420.0
@export var dash_duration: float = 0.22
@export var contact_radius: float = 18.0
@export var recovery_duration: float = 1.0
@export var dash_damage: float = 5.0

var _lock_dir: Vector2 = Vector2.DOWN
var _dash_timer: float = 0.0
var _dash_hit: bool = false
var _dash_done: bool = false

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
		_set_animator_hold(EnemyAnimator.Hold.BREATHE)
	elif new_state == State.ATTACK:
		_set_animator_hold(EnemyAnimator.Hold.NORMAL)
	elif new_state != State.HURT:
		_set_animator_hold(EnemyAnimator.Hold.NONE)
	super._change_state(new_state)


func _set_animator_hold(mode: int) -> void:
	var animator := get_node_or_null("EnemyAnimator")
	if animator:
		animator.set_hold(mode)


func _play_windup_telegraph() -> void:
	_play_hit_flash()
	_play_squash()


func _begin_dash() -> void:
	_lock_dir = get_facing_direction()
	_dash_timer = dash_duration
	_dash_hit = false
	_fire_vfx.start(_lock_dir)


func _moves_during_attack() -> bool:
	return _state == State.ATTACK and not _dash_done


func _process_attack(delta: float) -> void:
	if not _attack_started:
		_attack_started = true
		if _dash_done:
			_change_state(State.COOLDOWN)
			return
		_begin_dash()
	_tick_dash(delta)


func _tick_dash(delta: float) -> void:
	velocity = _lock_dir * dash_speed
	_check_body_contact()
	_dash_timer -= delta
	if _dash_timer <= 0.0:
		_dash_done = true
		velocity = Vector2.ZERO
		_fire_vfx.stop()
		_change_state(State.COOLDOWN)


func _check_body_contact() -> void:
	if _dash_hit:
		return
	if _player_ref == null or not is_instance_valid(_player_ref):
		return
	if global_position.distance_to(_player_ref.global_position) > contact_radius:
		return
	_dash_hit = true
	if _player_ref.has_method("on_hit_impact"):
		var dmg: int = int(dash_damage * damage_scale)
		_player_ref.on_hit_impact(global_position, _lock_dir, dmg)
