class_name Enemy
extends CharacterBody2D

signal died
signal health_changed(current: int, maximum: int)

@export var max_health: int = 20
@export var speed: float = 0.0

var health: int
var drop_table: DropTable = null
var _hit_flash_tween: Tween = null


func _ready() -> void:
	health = max_health


func hit(damage: int) -> void:
	if damage <= 0:
		return
	health -= damage
	health_changed.emit(health, max_health)
	_on_hit()
	if health <= 0:
		die()


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
