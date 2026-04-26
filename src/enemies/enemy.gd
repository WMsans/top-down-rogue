class_name Enemy
extends CharacterBody2D

signal died
signal health_changed(current: int, maximum: int)

@export var max_health: int = 20
@export var speed: float = 0.0

const KNOCKBACK_SPEED: float = 180.0
const KNOCKBACK_DECAY: float = 12.0

var health: int
var drop_table: DropTable = null
var _hit_flash_tween: Tween = null
var _knockback_velocity: Vector2 = Vector2.ZERO


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


func _on_hit() -> void:
	pass


func _on_death() -> void:
	pass
