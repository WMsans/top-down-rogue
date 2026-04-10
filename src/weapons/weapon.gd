class_name Weapon
extends RefCounted

var name: String = "Weapon"


func use(_user: Node) -> void:
	push_error("Weapon.use() must be overridden")


func tick(_delta: float) -> void:
	pass


func is_ready() -> bool:
	return true