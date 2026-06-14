class_name LungeEnemy
extends MeleeEnemy

@export var lunge_range: float = 120.0
@export var dash_speed: float = 420.0
@export var dash_duration: float = 0.22
@export var contact_radius: float = 18.0
@export var recovery_duration: float = 1.0

var _lock_dir: Vector2 = Vector2.DOWN
var _dash_timer: float = 0.0
var _dash_hit: bool = false
var _dash_done: bool = false  # set when a dash finishes; blocks restart after a HURT interrupt


func _ready() -> void:
	super._ready()
	_attack_range = lunge_range
	windup_duration = 0.45
	cooldown_duration = recovery_duration


func _begin_dash() -> void:
	_lock_dir = get_facing_direction()
	_dash_timer = dash_duration
	_dash_hit = false


func _moves_during_attack() -> bool:
	return _state == State.ATTACK and not _dash_done
