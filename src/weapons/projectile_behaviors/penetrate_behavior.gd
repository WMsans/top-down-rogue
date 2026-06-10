class_name PenetrateBehavior
extends ProjectileBehavior

func on_enemy_hit(_proj, _target) -> bool:
	return true


func on_terrain_hit(_proj) -> bool:
	return false
