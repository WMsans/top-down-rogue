class_name SniperPenetrationBehavior
extends ProjectileBehavior

@export var pierces: int = 2

func on_terrain_hit(proj) -> bool:
	if pierces <= 0:
		return false
	pierces -= 1
	if proj != null and proj.has_method("_carve_terrain"):
		proj._carve_terrain()
	return true