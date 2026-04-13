class_name Weapon
extends RefCounted

var name: String = "Weapon"
var visual_scene: PackedScene = null
var visual: Node2D = null


func use(_user: Node) -> void:
	push_error("Weapon.use() must be overridden")


func tick(_delta: float) -> void:
	pass


func is_ready() -> bool:
	return true


func trigger_visual(direction: Vector2) -> void:
	if visual:
		_do_visual(direction)


func _do_visual(_direction: Vector2) -> void:
	pass