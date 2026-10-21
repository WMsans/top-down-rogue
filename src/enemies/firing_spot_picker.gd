class_name FiringSpotPicker
extends RefCounted

## Picks where a ranged enemy stands to shoot: inside a distance band around
## the player, in line of sight, spaced from other shooters, on open ground.
## Candidates fan out from the enemy's current side so it doesn't cross the
## player to get there.

const MIN_DIST := 100.0
const MAX_DIST := 150.0
const SPACING := 40.0
const CANDIDATES := 8
const ARC_SPREAD := PI


static func pick(origin: Vector2, player_pos: Vector2, taken: Array, solid_check: Callable,
		los_check: Callable, rng: RandomNumberGenerator) -> Vector2:
	var side: float
	if origin.distance_squared_to(player_pos) > 0.01:
		side = (origin - player_pos).angle()
	else:
		side = rng.randf() * TAU
	var step := ARC_SPREAD / CANDIDATES
	for i in range(CANDIDATES):
		var k := ceilf(i / 2.0)
		var sgn := 1.0 if i % 2 == 1 else -1.0
		var angle := side + sgn * k * step + rng.randf_range(-0.1, 0.1)
		var spot := player_pos + Vector2.from_angle(angle) * rng.randf_range(MIN_DIST, MAX_DIST)
		if solid_check.is_valid() and solid_check.call(spot):
			continue
		if _too_close(spot, taken):
			continue
		# Raycasts are the expensive check; run them last.
		if los_check.is_valid() and not los_check.call(spot, player_pos):
			continue
		return spot
	return Vector2.INF


static func _too_close(spot: Vector2, taken: Array) -> bool:
	for t in taken:
		if spot.distance_to(t) < SPACING:
			return true
	return false
