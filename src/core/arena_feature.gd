class_name ArenaFeature
extends Resource

## Base class. Concrete subclasses live in src/core/features/.
## `region` is the spatial distribution; `apply(ctx)` is called by the dispatcher
## once per feature. Subclasses spawn entities or stamp material via ctx.
##
## ctx is a CompositionContext (see composition_dispatcher.gd):
##   - anchor_world_pos: Vector2 (arena center in world coords)
##   - rng: RandomNumberGenerator
##   - dispatcher: CompositionDispatcher (for entity spawning + material writes)
##   - mask_air: Callable(world_pos) -> bool (checks current carve mask)
@export var region: ArenaRegion


func apply(_ctx) -> void:
	pass
