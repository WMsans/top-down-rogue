class_name RegionArc
extends ArenaRegion

@export var center: Vector2 = Vector2.ZERO
@export var angle: float = 0.0
@export var span: float = PI / 2.0
@export var r_min: float = 100.0
@export var r_max: float = 200.0

func sample(rng: RandomNumberGenerator) -> Vector2:
	var theta: float = angle + (rng.randf() - 0.5) * span
	var u: float = rng.randf()
	var r: float = sqrt(u * (r_max * r_max - r_min * r_min) + r_min * r_min)
	return center + Vector2(cos(theta), sin(theta)) * r
