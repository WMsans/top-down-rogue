class_name ProjectileBehavior
extends RefCounted

func on_spawn(_proj) -> void:
	pass

func on_process(_proj, _delta: float) -> void:
	pass

func on_enemy_hit(_proj, _target) -> bool:
	return false

func on_terrain_hit(_proj) -> bool:
	return false

func on_enemy_projectile_overlap(_proj, _enemy_proj) -> void:
	pass
