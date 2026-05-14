extends Node2D

func _ready() -> void:
	add_to_group("attackable")

func try_parry(_attacker: Node, _hit_pos: Vector2, _hit_dir: Vector2) -> bool:
	return true

func on_hit_impact(_pos: Vector2, _dir: Vector2, _dmg: int) -> void:
	pass
