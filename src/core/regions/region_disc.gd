class_name RegionDisc
extends ArenaRegion

@export var center: Vector2 = Vector2.ZERO
@export var radius: float = 100.0

func sample(rng: RandomNumberGenerator) -> Vector2:
	var theta: float = rng.randf() * TAU
	var r: float = sqrt(rng.randf()) * radius
	return center + Vector2(cos(theta), sin(theta)) * r
