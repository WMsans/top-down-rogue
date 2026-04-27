class_name Drop
extends RigidBody2D

@export var linear_damp_value: float = 5.0

@onready var _sprite: Sprite2D = $Sprite2D

enum PickupType { GOLD, WEAPON, MODIFIER }

func get_pickup_type() -> int:
	return PickupType.WEAPON

func get_pickup_payload():
	return null

func should_auto_pickup() -> bool:
	return false

func _ready() -> void:
	gravity_scale = 0.0
	linear_damp = linear_damp_value
	mass = 1.0


func interact(player: Node) -> void:
	_pickup(player)


func _pickup(_player: Node) -> void:
	queue_free()


func set_highlighted(enabled: bool) -> void:
	if _sprite and _sprite.material is ShaderMaterial:
		(_sprite.material as ShaderMaterial).set_shader_parameter("outline_width", 1.0 if enabled else 0.0)