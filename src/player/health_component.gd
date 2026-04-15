class_name HealthComponent
extends Node

signal health_changed(current: int, maximum: int)
signal died

@export var max_health: int = 100
@export var invincibility_duration: float = 1.0

const BLINK_INTERVAL := 0.08

var _current_health: int
var _invincible_timer: float = 0.0
var _is_dead: bool = false
var _is_invincible: bool = false
var _blink_timer: float = 0.0
var _color_rect: ColorRect


func _ready() -> void:
	_current_health = max_health
	_color_rect = get_parent().get_node("ColorRect")


func take_damage(amount: int) -> void:
	if _is_dead or _is_invincible:
		return
	_current_health = maxi(_current_health - amount, 0)
	_is_invincible = true
	_invincible_timer = invincibility_duration
	health_changed.emit(_current_health, max_health)
	if _current_health <= 0:
		_is_dead = true
		_color_rect.visible = true
		died.emit()


func heal(amount: int) -> void:
	if _is_dead:
		return
	_current_health = mini(_current_health + amount, max_health)
	health_changed.emit(_current_health, max_health)


func is_dead() -> bool:
	return _is_dead


func _physics_process(delta: float) -> void:
	if _is_invincible:
		_invincible_timer -= delta
		if _invincible_timer <= 0.0:
			_is_invincible = false
			_invincible_timer = 0.0
			if not _is_dead:
				_color_rect.visible = true


func _process(_delta: float) -> void:
	if _is_invincible and not _is_dead:
		_blink_timer += _delta
		if _blink_timer >= BLINK_INTERVAL:
			_blink_timer -= BLINK_INTERVAL
			_color_rect.visible = not _color_rect.visible
