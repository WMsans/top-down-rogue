class_name CaveSpawner
extends Node

const CHUNK_SIZE := 256

const MELEE_ENEMY_SCENE := preload("res://scenes/enemies/melee_enemy.tscn")
const RANGED_ENEMY_SCENE := preload("res://scenes/enemies/ranged_enemy.tscn")

@export var spawn_interval: float = 1.0
@export var attempts_per_cycle: int = 2
@export var spawn_min_dist: float = 600.0
@export var spawn_max_dist: float = 2000.0
@export var despawn_dist: float = 2500.0
@export var mob_cap: int = 50
@export var spawn_rate: float = 1.0
@export var group_size_min: int = 3
@export var group_size_max: int = 5
@export var group_spread: float = 32.0
@export var elite_chance: float = 0.15

const BASE_SPAWN_CHANCE: float = 0.5
const MAX_VALIDATION_RETRIES: int = 3

const NEAR_ORIGIN_MULT: float = 0.45

var _current_density_mult: float = 1.0


static func origin_density_mult(sector_dist: int) -> float:
	var t := clampf(float(sector_dist) / float(SectorGrid.WALL_INNER_SECTORS), 0.0, 1.0)
	return lerpf(NEAR_ORIGIN_MULT, 1.0, t)


func _player_origin_dist() -> int:
	var grid: SectorGrid = LevelManager.get_grid()
	if grid == null or not is_instance_valid(_world_manager):
		return SectorGrid.WALL_INNER_SECTORS
	var sector := grid.world_to_sector(_world_manager.tracking_position)
	return grid.chebyshev_distance(sector, Vector2i.ZERO)

var _world_manager: Node2D = null
var _terrain_physical: TerrainPhysical = null
var _spawn_parent: Node2D = null
var _spawn_timer: Timer = null
var _despawn_timer: Timer = null


func _ready() -> void:
	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = spawn_interval
	_spawn_timer.timeout.connect(_on_spawn_tick)
	add_child(_spawn_timer)
	_spawn_timer.start()

	_despawn_timer = Timer.new()
	_despawn_timer.wait_time = 1.0
	_despawn_timer.timeout.connect(_on_despawn_tick)
	add_child(_despawn_timer)
	_despawn_timer.start()

	set_process(false)
	_resolve_dependencies()


func _resolve_dependencies() -> void:
	var wm := get_tree().get_first_node_in_group("world_manager")
	if wm == null:
		return
	_world_manager = wm
	_spawn_parent = _world_manager.get_chunk_container()
	_terrain_physical = _world_manager.terrain_physical


func set_biome_params(new_spawn_rate: float) -> void:
	spawn_rate = new_spawn_rate


func clear() -> void:
	pass


func _count_live_enemies() -> int:
	return get_tree().get_nodes_in_group("cave_spawned").filter(func(n): return is_instance_valid(n)).size()


func _pick_enemy_scene() -> PackedScene:
	if randf() < 0.8:
		var archetype := SpawnDispatcher._weighted_pick(SpawnDispatcher.MELEE_ARCHETYPE_WEIGHTS)
		return SpawnDispatcher.MELEE_ARCHETYPE_SCENES[archetype]
	var archetype := SpawnDispatcher._weighted_pick(SpawnDispatcher.RANGED_ARCHETYPE_WEIGHTS)
	return SpawnDispatcher.RANGED_ARCHETYPE_SCENES[archetype]


func _archetype_for_scene(scene: PackedScene) -> String:
	for archetype in SpawnDispatcher.MELEE_ARCHETYPE_SCENES:
		if SpawnDispatcher.MELEE_ARCHETYPE_SCENES[archetype] == scene:
			return archetype
	for archetype in SpawnDispatcher.RANGED_ARCHETYPE_SCENES:
		if SpawnDispatcher.RANGED_ARCHETYPE_SCENES[archetype] == scene:
			return archetype
	return "grunt"


func _pick_pooled_weapon(archetype: String, is_melee: bool) -> Weapon:
	var pool: Array[Dictionary] = EnemyWeaponPools.build_melee_pool(archetype) if is_melee else EnemyWeaponPools.build_ranged_pool(archetype)
	var floor_num: int = LevelManager.floor_number
	var sector_tier := DropTable.EnemyTier.NORMAL
	var grid: SectorGrid = LevelManager.get_grid()
	if grid != null and _world_manager != null and is_instance_valid(_world_manager):
		var sector := grid.world_to_sector(_world_manager.tracking_position)
		var dist := grid.chebyshev_distance(sector, Vector2i.ZERO)
		sector_tier = SectorGrid.enemy_tier_for_distance(dist)
	var kill_streak := 0
	if _world_manager != null and is_instance_valid(_world_manager):
		var dir = _world_manager.get("encounter_director")
		if dir != null and "kill_streak" in dir:
			kill_streak = dir.kill_streak
	var id := EnemyWeaponPools.pick_weapon_id(pool, floor_num, kill_streak, sector_tier)
	if id == "":
		return WeaponRegistry.get_weapon_by_id("rusty_sword") if is_melee else WeaponRegistry.get_weapon_by_id("throwing_knife")
	return WeaponRegistry.get_weapon_by_id(id)


func _on_spawn_tick() -> void:
	_current_density_mult = origin_density_mult(_player_origin_dist())
	var effective_cap := int(mob_cap * _current_density_mult)

	if _count_live_enemies() >= effective_cap:
		return

	if not is_instance_valid(_world_manager) or not is_instance_valid(_terrain_physical) or _spawn_parent == null:
		_resolve_dependencies()
	if not is_instance_valid(_world_manager) or not is_instance_valid(_terrain_physical) or _spawn_parent == null:
		return

	var surface := get_node_or_null("/root/TerrainSurface")
	if surface == null:
		return

	var chunk_coords: Array = surface.get_active_chunk_coords()
	if chunk_coords.is_empty():
		return

	chunk_coords.shuffle()

	var attempts := 0
	for chunk_coord in chunk_coords:
		if attempts >= attempts_per_cycle:
			break

		var world_base := Vector2(chunk_coord * CHUNK_SIZE)
		for _retry in range(MAX_VALIDATION_RETRIES):
			var local_x := randi() % CHUNK_SIZE
			var local_y := randi() % CHUNK_SIZE
			var world_pos := world_base + Vector2(local_x, local_y)

			if _validate_position(world_pos):
				var gmin := maxi(1, int(group_size_min * _current_density_mult))
				var gmax := maxi(gmin, int(group_size_max * _current_density_mult))
				var size := randi_range(gmin, gmax)
				if _count_live_enemies() + size > effective_cap:
					size = effective_cap - _count_live_enemies()
					if size <= 0:
						return
				_spawn_group(world_pos, size)
				attempts += 1
				break


const SPAWN_CLEAR_HALF: int = 6


func _validate_position(world_pos: Vector2) -> bool:
	var player_pos := Vector2.ZERO
	if is_instance_valid(_world_manager):
		player_pos = _world_manager.tracking_position

	var dist := world_pos.distance_to(player_pos)
	if dist < spawn_min_dist or dist > spawn_max_dist:
		return false

	if randf() > spawn_rate * BASE_SPAWN_CHANCE * _current_density_mult:
		return false

	if not _is_clear_of_walls(world_pos):
		return false

	if _is_in_no_spawn_arena(world_pos):
		return false

	return true


func _is_in_no_spawn_arena(world_pos: Vector2) -> bool:
	var grid: SectorGrid = LevelManager.get_grid()
	if grid == null:
		return false
	var sector := grid.world_to_sector(world_pos)
	var slot := grid.resolve_sector(sector)
	var comp: ArenaComposition = slot.composition as ArenaComposition
	if comp != null and comp.arena_kind == &"guidance":
		return true
	# Sealed rooms (e.g. the shop) opt out of cave spawning via no_spawn.
	var tmpl := grid.get_template_for_slot(slot)
	return tmpl != null and tmpl.no_spawn


# Ensure the spawn position's footprint contains only air. Delegates to the
# shared SpawnValidation helper so the room path (spawn_dispatcher) and the
# cave path cannot drift apart.
func _is_clear_of_walls(world_pos: Vector2) -> bool:
	return SpawnValidation.footprint_clear(_world_manager, world_pos, SPAWN_CLEAR_HALF)


func _spawn_enemy(world_pos: Vector2) -> void:
	if _spawn_parent == null:
		return
	var scene := _pick_enemy_scene()
	var enemy := scene.instantiate()
	var archetype := _archetype_for_scene(scene)
	var is_melee: bool = SpawnDispatcher.MELEE_ARCHETYPE_SCENES.has(archetype)

	var is_elite_roll := randf() < elite_chance
	if is_elite_roll:
		enemy.is_elite = true
		enemy.elite_ability = randi() % 4 + 1

	enemy.weapon_resource = _pick_pooled_weapon(archetype, is_melee)

	enemy.global_position = world_pos
	enemy.add_to_group("cave_spawned")
	_spawn_parent.add_child(enemy)


func _spawn_group(center: Vector2, count: int) -> void:
	var placed := 0
	var max_retries := count * 3
	var retries := 0
	while placed < count and retries < max_retries:
		var offset := Vector2(
			randf_range(-group_spread, group_spread),
			randf_range(-group_spread, group_spread),
		)
		var pos := center + offset
		retries += 1
		if not _is_clear_of_walls(pos):
			continue
		_spawn_enemy(pos)
		placed += 1


func _on_despawn_tick() -> void:
	var player_pos := Vector2.ZERO
	if is_instance_valid(_world_manager):
		player_pos = _world_manager.tracking_position

	for enemy in get_tree().get_nodes_in_group("cave_spawned"):
		if not is_instance_valid(enemy):
			continue
		if enemy.global_position.distance_to(player_pos) > despawn_dist:
			enemy.queue_free()
