extends Node

const CHUNK_SIZE := 256
const ArenaComposition = preload("res://src/core/arena_composition.gd")
const ArenaFeature = preload("res://src/core/arena_feature.gd")

class CompositionContext:
	var anchor_world_pos: Vector2
	var rng: RandomNumberGenerator
	var dispatcher: Node
	var mask_air: Callable
	var background_material: int = 2

var _dispatched_anchors: Dictionary = {}  # sector_coord → true
var _world_manager: Node = null
var _spawn_parent: Node = null
# Replayable material stamps issued by features. Each entry:
#   {"pos": Vector2, "radius": float, "mat": int, "seed": int, "jitter": float}
# Stamps that hit unloaded chunks at issue time are re-applied when those chunks
# later generate, so cross-chunk pillar/pool parts aren't truncated.
var _stamps: Array = []


func _process(_delta: float) -> void:
	if _world_manager != null and is_instance_valid(_world_manager):
		return
	var wm := get_tree().get_first_node_in_group("world_manager")
	if wm == null:
		return
	_world_manager = wm
	_spawn_parent = _world_manager.get_chunk_container()
	_dispatched_anchors.clear()
	_world_manager.chunks_generated.connect(_on_chunks_generated)


func clear() -> void:
	_dispatched_anchors.clear()
	_stamps.clear()


func _on_chunks_generated(new_coords: Array[Vector2i]) -> void:
	# Replay any prior stamps whose AABB intersects a newly loaded chunk so
	# cross-chunk pillar/pool parts get filled in.
	_replay_stamps_for_chunks(new_coords)
	var grid: SectorGrid = LevelManager.get_grid()
	if grid == null:
		return
	for chunk_coord in new_coords:
		var chunk_world := chunk_coord * CHUNK_SIZE
		var min_s := grid.world_to_sector(Vector2(chunk_world.x - 1120, chunk_world.y - 1120))
		var max_s := grid.world_to_sector(Vector2(chunk_world.x + CHUNK_SIZE + 1120, chunk_world.y + CHUNK_SIZE + 1120))
		for sx in range(min_s.x, max_s.x + 1):
			for sy in range(min_s.y, max_s.y + 1):
				var sector := Vector2i(sx, sy)
				if _dispatched_anchors.has(sector):
					continue
				var slot := grid.resolve_sector(sector)
				if slot.composition == null:
					continue
				var anchor_chunk_coord := Vector2i(
					floori(grid.sector_to_world_center(sector).x / float(CHUNK_SIZE)),
					floori(grid.sector_to_world_center(sector).y / float(CHUNK_SIZE)),
				)
				if anchor_chunk_coord != chunk_coord:
					continue
				_dispatched_anchors[sector] = true
				_evaluate_composition(grid, sector, slot)


func _evaluate_composition(grid: SectorGrid, sector: Vector2i, slot) -> void:
	var comp: ArenaComposition = slot.composition
	if comp == null:
		return
	var anchor_world := Vector2(grid.sector_to_world_center(sector))
	var biome: BiomeDef = LevelManager.current_biome
	var background_mat: int = biome.background_material if biome else 2
	for i in comp.features.size():
		var f: ArenaFeature = comp.features[i]
		if f == null:
			continue
		var ctx := CompositionContext.new()
		ctx.anchor_world_pos = anchor_world
		ctx.rng = RandomNumberGenerator.new()
		ctx.rng.seed = hash(LevelManager.world_seed ^ sector.x * 73856093 ^ sector.y * 19349663 ^ i)
		ctx.dispatcher = self
		ctx.background_material = background_mat
		ctx.mask_air = func(world_pos: Vector2) -> bool:
			return _is_air(world_pos)
		f.apply(ctx)


func _is_air(world_pos: Vector2) -> bool:
	var ipos := Vector2i(floori(world_pos.x), floori(world_pos.y))
	var data: PackedByteArray = _world_manager.read_region(Rect2i(ipos, Vector2i(1, 1)))
	if data.size() == 0:
		return false
	return data[0] == MaterialRegistry.MAT_AIR


# --- Dispatcher API consumed by ArenaFeature subclasses ---

func spawn_boss(world_pos: Vector2, boss_scene: PackedScene) -> void:
	if boss_scene == null:
		return
	var inst := boss_scene.instantiate()
	inst.global_position = world_pos
	if inst.has_signal("died"):
		inst.died.connect(_on_boss_died.bind(world_pos))
	_spawn_parent.add_child(inst)

func _on_boss_died(arena_center: Vector2) -> void:
	const PORTAL_SCENE = preload("res://scenes/portal.tscn")
	var portal := PORTAL_SCENE.instantiate()
	portal.global_position = arena_center
	_spawn_parent.add_child(portal)

func spawn_enemy(world_pos: Vector2, enemy_scene: PackedScene, is_elite: bool) -> void:
	if enemy_scene == null:
		return
	var inst := enemy_scene.instantiate()
	if is_elite and "is_elite" in inst:
		inst.is_elite = true
	inst.global_position = world_pos
	_spawn_parent.add_child(inst)

func spawn_prop(world_pos: Vector2, prop_scene: PackedScene) -> void:
	if prop_scene == null:
		return
	var inst := prop_scene.instantiate()
	inst.global_position = world_pos
	_spawn_parent.add_child(inst)

func spawn_chest(world_pos: Vector2, rare: bool) -> void:
	const CHEST_SCENE = preload("res://scenes/chest.tscn")
	var chest := CHEST_SCENE.instantiate()
	chest.global_position = world_pos
	if rare and "rare_drop" in chest:
		chest.rare_drop = true
	_spawn_parent.add_child(chest)

func stamp_material_disc(world_pos: Vector2, radius_cells: int, material_id: int) -> void:
	stamp_material_blob(world_pos, float(radius_cells), material_id, 0, 0.0)


func stamp_material_blob(world_pos: Vector2, radius: float, material_id: int, noise_seed: int, edge_jitter: float) -> void:
	if _world_manager == null or material_id <= 0:
		return
	_stamps.append({
		"pos": world_pos,
		"radius": radius,
		"mat": material_id,
		"seed": noise_seed,
		"jitter": edge_jitter,
	})
	_world_manager.place_material_blob(world_pos, radius, material_id, noise_seed, edge_jitter)


func _replay_stamps_for_chunks(new_coords: Array[Vector2i]) -> void:
	if _world_manager == null or _stamps.is_empty() or new_coords.is_empty():
		return
	var new_chunks := {}
	for c in new_coords:
		new_chunks[c] = true
	for stamp in _stamps:
		var radius: float = stamp["radius"] * (1.0 + max(float(stamp["jitter"]), 0.0))
		var min_x := int(floor(stamp["pos"].x - radius))
		var max_x := int(ceil(stamp["pos"].x + radius))
		var min_y := int(floor(stamp["pos"].y - radius))
		var max_y := int(ceil(stamp["pos"].y + radius))
		var cmin_x := floori(float(min_x) / CHUNK_SIZE)
		var cmax_x := floori(float(max_x) / CHUNK_SIZE)
		var cmin_y := floori(float(min_y) / CHUNK_SIZE)
		var cmax_y := floori(float(max_y) / CHUNK_SIZE)
		var intersects := false
		for cx in range(cmin_x, cmax_x + 1):
			for cy in range(cmin_y, cmax_y + 1):
				if new_chunks.has(Vector2i(cx, cy)):
					intersects = true
					break
			if intersects:
				break
		if intersects:
			_world_manager.place_material_blob(stamp["pos"], stamp["radius"], stamp["mat"], stamp["seed"], stamp["jitter"])
