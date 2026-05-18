class_name ArenaRegion
extends Resource

## Base class for arena feature regions. Concrete subclasses live in src/core/regions/.
## `sample(rng)` returns a Vector2 offset relative to the arena center.
func sample(_rng: RandomNumberGenerator) -> Vector2:
	return Vector2.ZERO
