class_name ArenaRegion
extends Resource

## Base class for arena feature regions. Concrete subclasses below.
## `sample(rng)` returns a Vector2 offset relative to the arena center.
func sample(_rng: RandomNumberGenerator) -> Vector2:
	return Vector2.ZERO


class RegionPoint extends ArenaRegion:
	@export var offset: Vector2 = Vector2.ZERO

	func sample(_rng: RandomNumberGenerator) -> Vector2:
		return offset


class RegionDisc extends ArenaRegion:
	@export var center: Vector2 = Vector2.ZERO
	@export var radius: float = 100.0

	func sample(rng: RandomNumberGenerator) -> Vector2:
		var theta: float = rng.randf() * TAU
		var r: float = sqrt(rng.randf()) * radius
		return center + Vector2(cos(theta), sin(theta)) * r


class RegionRing extends ArenaRegion:
	@export var center: Vector2 = Vector2.ZERO
	@export var r_min: float = 100.0
	@export var r_max: float = 200.0

	func sample(rng: RandomNumberGenerator) -> Vector2:
		var theta: float = rng.randf() * TAU
		# Uniform-area sample in annulus.
		var u: float = rng.randf()
		var r: float = sqrt(u * (r_max * r_max - r_min * r_min) + r_min * r_min)
		return center + Vector2(cos(theta), sin(theta)) * r


class RegionArc extends ArenaRegion:
	@export var center: Vector2 = Vector2.ZERO
	@export var angle: float = 0.0       # midline angle (radians)
	@export var span: float = PI / 2.0   # full angular width
	@export var r_min: float = 100.0
	@export var r_max: float = 200.0

	func sample(rng: RandomNumberGenerator) -> Vector2:
		var theta: float = angle + (rng.randf() - 0.5) * span
		var u: float = rng.randf()
		var r: float = sqrt(u * (r_max * r_max - r_min * r_min) + r_min * r_min)
		return center + Vector2(cos(theta), sin(theta)) * r
