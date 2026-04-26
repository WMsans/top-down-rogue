class_name Enemy
extends CharacterBody2D

signal died
signal health_changed(current: int, maximum: int)

@export var max_health: int = 20
@export var speed: float = 0.0

const KNOCKBACK_SPEED: float = 180.0
const KNOCKBACK_DECAY: float = 12.0
const FLASH_COLOR: Color = Color(3.0, 3.0, 3.0)
const FLASH_DECAY: float = 0.12
const SQUASH_SCALE: Vector2 = Vector2(1.4, 0.7)
const SQUASH_DURATION: float = 0.18

var health: int
var drop_table: DropTable = null
var _knockback_velocity: Vector2 = Vector2.ZERO
var _base_modulate: Color = Color.WHITE
var _flash_tween: Tween = null
var _squash_tween: Tween = null


func _ready() -> void:
	add_to_group("attackable")
	health = max_health


func hit(damage: int) -> void:
	if damage <= 0:
		return
	health -= damage
	health_changed.emit(health, max_health)
	_on_hit()
	if health <= 0:
		die()


func on_hit_impact(_impact_point: Vector2, hit_dir: Vector2, damage: int) -> void:
	if hit_dir.length_squared() > 0.0001:
		_knockback_velocity += hit_dir.normalized() * KNOCKBACK_SPEED
	var lethal: bool = damage >= health
	ScreenShakeManager.shake(ScreenShakeManager.SHAKE_AMOUNT, ScreenShakeManager.SHAKE_DURATION, hit_dir)
	var stop_duration: float = HitStopManager.HIT_STOP_BASE
	if lethal:
		stop_duration += HitStopManager.HIT_STOP_KILL_BONUS
	HitStopManager.stop(stop_duration)
	hit(damage)


func _tick_knockback(delta: float) -> void:
	if _knockback_velocity.length_squared() < 1.0:
		_knockback_velocity = Vector2.ZERO
		return
	_knockback_velocity *= exp(-KNOCKBACK_DECAY * delta)


func die() -> void:
	died.emit()
	if drop_table:
		drop_table.resolve(global_position, get_parent())
	_on_death()
	queue_free()


func _set_base_modulate(c: Color) -> void:
	_base_modulate = c
	var sprite := get_node_or_null("Sprite2D")
	if sprite:
		sprite.modulate = c


func _play_hit_flash() -> void:
	var sprite := get_node_or_null("Sprite2D")
	if sprite == null:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	sprite.modulate = FLASH_COLOR
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", _base_modulate, FLASH_DECAY)


func _play_squash() -> void:
	var sprite := get_node_or_null("Sprite2D")
	if sprite == null:
		return
	if _squash_tween and _squash_tween.is_valid():
		_squash_tween.kill()
	sprite.scale = SQUASH_SCALE
	_squash_tween = create_tween()
	_squash_tween.set_trans(Tween.TRANS_ELASTIC)
	_squash_tween.set_ease(Tween.EASE_OUT)
	_squash_tween.tween_property(sprite, "scale", Vector2.ONE, SQUASH_DURATION)


func _on_hit() -> void:
	_play_hit_flash()
	_play_squash()


func _on_death() -> void:
	pass
