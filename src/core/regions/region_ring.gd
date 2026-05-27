class_name RegionRing
extends ArenaRegion

@export var center: Vector2 = Vector2.ZERO
@export var r_min: float = 100.0
@export var r_max: float = 200.0

func sample(rng: RandomNumberGenerator) -> Vector2:
	var theta: float = rng.randf() * TAU
	var u: float = rng.randf()
	var r: float = sqrt(u * (r_max * r_max - r_min * r_min) + r_min * r_min)
	return center + Vector2(cos(theta), sin(theta)) * r
