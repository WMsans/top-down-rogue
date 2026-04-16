class_name Drop
extends RigidBody2D

@export var linear_damp_value: float = 5.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _interactable: Interactable = $Interactable


func _ready() -> void:
	gravity_scale = 0.0
	linear_damp = linear_damp_value
	mass = 1.0


func interact(player: Node) -> void:
	_pickup(player)


func _pickup(_player: Node) -> void:
	queue_free()


func set_highlighted(enabled: bool) -> void:
	if _interactable:
		_interactable.set_highlighted(enabled)