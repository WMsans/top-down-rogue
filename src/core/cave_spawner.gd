extends Node

const CHUNK_SIZE := 256
const ENEMY_SCENE := preload("res://scenes/dummy_enemy.tscn")

@export var spawn_interval: float = 1.0
@export var attempts_per_cycle: int = 2
@export var spawn_min_dist: float = 0.0
@export var spawn_max_dist: float = 2000.0
@export var despawn_dist: float = 2500.0
@export var mob_cap: int = 70
@export var spawn_rate: float = 1.0

const BASE_SPAWN_CHANCE: float = 0.5
const MAX_VALIDATION_RETRIES: int = 3

const DBG_INTERVAL: int = 30
var _dbg_tick: int = 0
var _dbg_entry: int = 0
var _dbg_mob_capped: int = 0
var _dbg_deps_missing: int = 0
var _dbg_no_surface: int = 0
var _dbg_no_chunks: int = 0
var _dbg_reject_dist: int = 0
var _dbg_reject_rand: int = 0
var _dbg_reject_solid: int = 0
var _dbg_reject_headroom: int = 0
var _dbg_spawned: int = 0

var _world_manager: Node2D = null
var _terrain_physical: TerrainPhysical = null
var _spawn_parent: Node2D = null
var _spawn_timer: Timer = null
var _despawn_timer: Timer = null


func _ready() -> void:
	print("[cave_spawner] INIT rate=%.2f interval=%.2f attempts=%d min_dist=%.0f max_dist=%.0f cap=%d" % [
		spawn_rate, spawn_interval, attempts_per_cycle, spawn_min_dist, spawn_max_dist, mob_cap,
	])
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
	print("[cave_spawner] DEPS wm=%s tp=%s parent=%s" % [
		"OK" if is_instance_valid(_world_manager) else "MISSING",
		"OK" if is_instance_valid(_terrain_physical) else "MISSING",
		"OK" if _spawn_parent != null else "MISSING",
	])


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
	return get_tree().get_nodes_in_group("attackable").filter(func(n): return is_instance_valid(n)).size()


func _on_spawn_tick() -> void:
	_dbg_entry += 1

	if _count_live_enemies() >= mob_cap:
		_dbg_mob_capped += 1
		_dbg_print()
		return

	if not is_instance_valid(_world_manager) or not is_instance_valid(_terrain_physical) or _spawn_parent == null:
		_resolve_dependencies()
	if not is_instance_valid(_world_manager) or not is_instance_valid(_terrain_physical) or _spawn_parent == null:
		_dbg_deps_missing += 1
		_dbg_print()
		return

	var surface := get_node_or_null("/root/TerrainSurface")
	if surface == null:
		_dbg_no_surface += 1
		_dbg_print()
		return

	var chunk_coords: Array = surface.get_active_chunk_coords()
	if chunk_coords.is_empty():
		_dbg_no_chunks += 1
		_dbg_print()
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
				_spawn_enemy(world_pos)
				_dbg_spawned += 1
				attempts += 1
				break

	_dbg_print()


func _validate_position(world_pos: Vector2) -> bool:
	var player_pos := Vector2.ZERO
	if is_instance_valid(_world_manager):
		player_pos = _world_manager.tracking_position

	var dist := world_pos.distance_to(player_pos)
	if dist < spawn_min_dist or dist > spawn_max_dist:
		_dbg_reject_dist += 1
		return false

	if randf() > spawn_rate * BASE_SPAWN_CHANCE:
		_dbg_reject_rand += 1
		return false

	if _terrain_physical == null:
		return true

	if not _has_solid_floor(world_pos):
		_dbg_reject_solid += 1
		return false

	if not _has_headroom(world_pos):
		_dbg_reject_headroom += 1
		return false

	return true


func _has_solid_floor(world_pos: Vector2) -> bool:
	if _terrain_physical == null:
		return false

	var down_offsets := [Vector2.ZERO, Vector2(0, 16), Vector2(0, 32)]
	var any_probed := false
	for offset in down_offsets:
		var pos : Vector2  = world_pos + offset
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
		var pos : Vector2 = world_pos + offset
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
	var enemy := ENEMY_SCENE.instantiate()
	enemy.global_position = world_pos
	_spawn_parent.add_child(enemy)


func _dbg_print() -> void:
	_dbg_tick += 1
	if _dbg_tick % DBG_INTERVAL != 0:
		return
	var live := _count_live_enemies()
	print("[cave_spawner] tick=%d entries=%d live=%d cap=%d spawned=%d | capped=%d deps=%d nosurf=%d nochunks=%d | reject: dist=%d rand=%d solid=%d headroom=%d" % [
		_dbg_tick, _dbg_entry, live, mob_cap, _dbg_spawned,
		_dbg_mob_capped, _dbg_deps_missing, _dbg_no_surface, _dbg_no_chunks,
		_dbg_reject_dist, _dbg_reject_rand, _dbg_reject_solid, _dbg_reject_headroom,
	])

func _on_despawn_tick() -> void:
	var player_pos := Vector2.ZERO
	if is_instance_valid(_world_manager):
		player_pos = _world_manager.tracking_position

	for enemy in get_tree().get_nodes_in_group("attackable"):
		if not is_instance_valid(enemy):
			continue
		if enemy.global_position.distance_to(player_pos) > despawn_dist:
			enemy.queue_free()
