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


func _on_chunks_generated(new_coords: Array[Vector2i]) -> void:
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
	if _world_manager == null or material_id <= 0:
		return
	_world_manager.place_material(world_pos, float(radius_cells), material_id)
