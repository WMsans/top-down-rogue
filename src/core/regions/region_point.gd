class_name RegionPoint
extends ArenaRegion

@export var offset: Vector2 = Vector2.ZERO

func sample(_rng: RandomNumberGenerator) -> Vector2:
	return offset
