class_name ArenaFeature
extends Resource

## Base class. Concrete subclasses below.
## `region` is the spatial distribution; `apply(ctx)` is called by the dispatcher
## once per feature. Subclasses spawn entities or stamp material via ctx.
##
## ctx is a CompositionContext (see composition_dispatcher.gd):
##   - anchor_world_pos: Vector2 (arena center in world coords)
##   - rng: RandomNumberGenerator
##   - dispatcher: CompositionDispatcher (for entity spawning + material writes)
##   - mask_air: Callable(world_pos) -> bool (checks current carve mask)
@export var region: ArenaRegion

const _AR = preload("res://src/core/arena_region.gd")


func apply(_ctx) -> void:
	pass


# --- Concrete features ---

class FeatureBossSpawn extends ArenaFeature:
	@export var boss_scene: PackedScene
	@export var floor_scaling: bool = true

	func apply(ctx) -> void:
		# Boss is always at the exact arena center (inner-disc air guaranteed).
		ctx.dispatcher.spawn_boss(ctx.anchor_world_pos, boss_scene)


class FeatureEnemyPack extends ArenaFeature:
	@export var enemy_scene: PackedScene
	@export var count: int = 4
	@export var is_elite: bool = false

	func apply(ctx) -> void:
		for i in count:
			var pos := _sample_air(ctx)
			if pos == null:
				continue
			ctx.dispatcher.spawn_enemy(pos, enemy_scene, is_elite)

	func _sample_air(ctx):
		if region == null:
			return null
		for retry in 8:
			var local: Vector2 = region.sample(ctx.rng)
			var world: Vector2 = ctx.anchor_world_pos + local
			if ctx.mask_air.call(world):
				return world
		return null


class FeaturePillarCluster extends ArenaFeature:
	@export var count: int = 6
	@export var pillar_radius_cells: int = 10
	@export var spacing_min: float = 64.0

	func apply(ctx) -> void:
		var placed: Array[Vector2] = []
		for i in count:
			var pos := _try_place(ctx, placed)
			if pos == null:
				continue
			placed.append(pos)
			ctx.dispatcher.stamp_material_disc(pos, pillar_radius_cells, ctx.background_material)

	func _try_place(ctx, placed: Array[Vector2]):
		if region == null:
			return null
		for retry in 8:
			var local: Vector2 = region.sample(ctx.rng)
			var world: Vector2 = ctx.anchor_world_pos + local
			if not ctx.mask_air.call(world):
				continue
			var too_close := false
			for p in placed:
				if p.distance_to(world) < spacing_min:
					too_close = true
					break
			if too_close:
				continue
			return world
		return null


class FeaturePoolPatch extends ArenaFeature:
	@export var material_id: int = 0           # resolved against MaterialRegistry
	@export var count: int = 1
	@export var size_min_cells: int = 6
	@export var size_max_cells: int = 14

	func apply(ctx) -> void:
		if material_id <= 0:
			return  # deferred/uninitialized — skip silently
		for i in count:
			var pos := _sample_air(ctx)
			if pos == null:
				continue
			var radius: int = ctx.rng.randi_range(size_min_cells, size_max_cells)
			ctx.dispatcher.stamp_material_disc(pos, radius, material_id)

	func _sample_air(ctx):
		if region == null:
			return null
		for retry in 8:
			var local: Vector2 = region.sample(ctx.rng)
			var world: Vector2 = ctx.anchor_world_pos + local
			if ctx.mask_air.call(world):
				return world
		return null


class FeatureBarrelCluster extends ArenaFeature:
	@export var barrel_scene: PackedScene  # null = deferred, no-op
	@export var count: int = 3

	func apply(ctx) -> void:
		if barrel_scene == null:
			return
		for i in count:
			var pos := _sample_air(ctx)
			if pos == null:
				continue
			ctx.dispatcher.spawn_prop(pos, barrel_scene)

	func _sample_air(ctx):
		if region == null:
			return null
		for retry in 8:
			var local: Vector2 = region.sample(ctx.rng)
			var world: Vector2 = ctx.anchor_world_pos + local
			if ctx.mask_air.call(world):
				return world
		return null


class FeatureVent extends ArenaFeature:
	@export var vent_scene: PackedScene  # null = deferred, no-op
	@export var count: int = 1

	func apply(ctx) -> void:
		if vent_scene == null:
			return
		for i in count:
			var pos := _sample_air(ctx)
			if pos == null:
				continue
			ctx.dispatcher.spawn_prop(pos, vent_scene)

	func _sample_air(ctx):
		if region == null:
			return null
		for retry in 8:
			var local: Vector2 = region.sample(ctx.rng)
			var world: Vector2 = ctx.anchor_world_pos + local
			if ctx.mask_air.call(world):
				return world
		return null


class FeatureChestSpawn extends ArenaFeature:
	@export var rare: bool = false

	func apply(ctx) -> void:
		# Always at exact arena center.
		ctx.dispatcher.spawn_chest(ctx.anchor_world_pos, rare)
