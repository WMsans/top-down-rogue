extends Node

const CHUNK_SIZE := 256

const MELEE_ENEMY_SCENE := preload("res://scenes/enemies/melee_enemy.tscn")
const RANGED_ENEMY_SCENE := preload("res://scenes/enemies/ranged_enemy.tscn")

const RUSTY_SWORD := preload("res://resources/weapons/rusty_sword.tres")
const BONE_DAGGER := preload("res://resources/weapons/bone_dagger.tres")
const THROWING_KNIFE := preload("res://resources/weapons/throwing_knife.tres")
const FIRE_ORB := preload("res://resources/weapons/fire_orb.tres")
const BROAD_AXE := preload("res://resources/weapons/broad_axe.tres")
const FLAME_BLADE := preload("res://resources/weapons/flame_blade.tres")
const SPREAD_SHOT := preload("res://resources/weapons/spread_shot.tres")

@export var spawn_interval: float = 1.0
@export var attempts_per_cycle: int = 2
@export var spawn_min_dist: float = 0.0
@export var spawn_max_dist: float = 2000.0
@export var despawn_dist: float = 2500.0
@export var mob_cap: int = 99
@export var spawn_rate: float = 1.0
@export var group_size_min: int = 3
@export var group_size_max: int = 5
@export var group_spread: float = 32.0
@export var elite_chance: float = 0.15

const BASE_SPAWN_CHANCE: float = 0.5
const MAX_VALIDATION_RETRIES: int = 3

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
		return MELEE_ENEMY_SCENE
	return RANGED_ENEMY_SCENE


func _pick_melee_weapon() -> MeleeWeapon:
	if randf() < 0.5:
		return RUSTY_SWORD
	return BONE_DAGGER


func _pick_ranged_weapon() -> RangedWeapon:
	if randf() < 0.7:
		return THROWING_KNIFE
	return FIRE_ORB


func _pick_elite_melee_weapon() -> MeleeWeapon:
	if randf() < 0.5:
		return BROAD_AXE
	return FLAME_BLADE


func _on_spawn_tick() -> void:
	if _count_live_enemies() >= mob_cap:
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
				var size := randi_range(group_size_min, group_size_max)
				if _count_live_enemies() + size > mob_cap:
					size = mob_cap - _count_live_enemies()
					if size <= 0:
						return
				_spawn_group(world_pos, size)
				attempts += 1
				break


func _validate_position(world_pos: Vector2) -> bool:
	var player_pos := Vector2.ZERO
	if is_instance_valid(_world_manager):
		player_pos = _world_manager.tracking_position

	var dist := world_pos.distance_to(player_pos)
	if dist < spawn_min_dist or dist > spawn_max_dist:
		return false

	if randf() > spawn_rate * BASE_SPAWN_CHANCE:
		return false

	if _terrain_physical == null:
		return true

	if not _has_solid_floor(world_pos):
		return false

	if not _has_headroom(world_pos):
		return false

	return true


func _has_solid_floor(world_pos: Vector2) -> bool:
	if _terrain_physical == null:
		return false
	var down_offsets := [Vector2.ZERO, Vector2(0, 16), Vector2(0, 32)]
	var any_probed := false
	for offset in down_offsets:
		var pos: Vector2 = world_pos + offset
		if not _terrain_physical.has_cache(pos):
			continue
		any_probed = true
		if _terrain_physical.query(pos).is_solid:
			return true
	if not any_probed:
		return true
	return false


func _has_headroom(world_pos: Vector2) -> bool:
	if _terrain_physical == null:
		return false
	var up_offsets := [Vector2(0, -8), Vector2(0, -24)]
	var any_probed := false
	for offset in up_offsets:
		var pos: Vector2 = world_pos + offset
		if not _terrain_physical.has_cache(pos):
			continue
		any_probed = true
		if _terrain_physical.query(pos).is_solid:
			return false
	if not any_probed:
		return true
	return true


func _spawn_enemy(world_pos: Vector2) -> void:
	if _spawn_parent == null:
		return
	var scene := _pick_enemy_scene()
	var enemy := scene.instantiate()

	var is_elite_roll := randf() < elite_chance
	if is_elite_roll:
		enemy.is_elite = true
		enemy.elite_ability = randi() % 4 + 1

	if scene == MELEE_ENEMY_SCENE:
		if is_elite_roll:
			enemy.weapon_resource = _pick_elite_melee_weapon()
		else:
			enemy.weapon_resource = _pick_melee_weapon()
	else:
		enemy.weapon_resource = _pick_ranged_weapon()

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
		if _terrain_physical != null and not _has_headroom(pos):
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
