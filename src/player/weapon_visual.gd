class_name WeaponVisual
extends Node2D

const WEAPON_TEXTURE := preload("res://textures/weapon.png")
const PIVOT_DISTANCE: float = 15.0

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_sprite.texture = WEAPON_TEXTURE
	var tex_size: Vector2 = WEAPON_TEXTURE.get_size()
	_sprite.offset = Vector2(tex_size.x / 2.0, -tex_size.y / 4.0)


func _process(_delta: float) -> void:
	var player := _get_player()
	if player == null:
		return
	
	var facing: Vector2 = player.get_facing_direction()
	var angle: float = facing.angle()
	
	position = Vector2(cos(angle), sin(angle)) * PIVOT_DISTANCE
	rotation = angle + PI / 2.0


func _get_player() -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	if parent.has_method("get_facing_direction"):
		return parent
	return null