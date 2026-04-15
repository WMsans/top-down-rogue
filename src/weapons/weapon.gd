class_name Weapon
extends RefCounted

var name: String = "Weapon"
var cooldown: float = 0.5
var damage: float = 0.0
var icon_texture: Texture2D = null
var visual: Node2D = null
var _sprite: Sprite2D = null


func use(_user: Node) -> void:
	push_error("Weapon.use() must be overridden")


func tick(_delta: float) -> void:
	pass


func is_ready() -> bool:
	return true


func has_visual() -> bool:
	return false


func setup_visual(container: Node2D, sprite: Sprite2D) -> void:
	visual = container
	_sprite = sprite


func update_visual(_delta: float, _user: Node) -> void:
	pass


func get_base_stats() -> Dictionary:
	return {
		"name": name,
		"cooldown": cooldown,
		"damage": damage
	}