extends Node

const ENEMY_SCENE := preload("res://scenes/dummy_enemy.tscn")

@export var spawn_interval: float = 1.0
@export var attempts_per_cycle: int = 2
@export var spawn_min_dist: float = 600.0
@export var spawn_max_dist: float = 2000.0
@export var despawn_dist: float = 2500.0
@export var mob_cap: int = 15
@export var spawn_rate: float = 1.0

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
	return get_tree().get_nodes_in_group("attackable").filter(func(n): return is_instance_valid(n)).size()


func _on_spawn_tick() -> void:
	if not is_instance_valid(_world_manager) or not is_instance_valid(_terrain_physical):
		_resolve_dependencies()
		return

	if _count_live_enemies() >= mob_cap:
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

		var world_base := Vector2(chunk_coord * 256)
		for _retry in range(MAX_VALIDATION_RETRIES):
			var local_x := randi() % 256
			var local_y := randi() % 256
			var world_pos := world_base + Vector2(local_x, local_y)

			if _validate_position(world_pos):
				_spawn_enemy(world_pos)
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
		return false

	if not _has_solid_floor(world_pos):
		return false

	if not _has_headroom(world_pos):
		return false

	return true


func _has_solid_floor(world_pos: Vector2) -> bool:
	if _terrain_physical == null:
		return false

	var down_offsets := [Vector2.ZERO, Vector2(0, 16), Vector2(0, 32)]
	for offset in down_offsets:
		var cell := _terrain_physical.query(world_pos + offset)
		if cell.is_solid:
			return true
	return false


func _has_headroom(world_pos: Vector2) -> bool:
	if _terrain_physical == null:
		return false

	var up_offsets := [Vector2(0, -8), Vector2(0, -24)]
	for offset in up_offsets:
		var cell := _terrain_physical.query(world_pos + offset)
		if cell.is_solid:
			return false
	return true


func _spawn_enemy(world_pos: Vector2) -> void:
	var enemy := ENEMY_SCENE.instantiate()
	enemy.global_position = world_pos
	_spawn_parent.add_child(enemy)


func _on_despawn_tick() -> void:
	var player_pos := Vector2.ZERO
	if is_instance_valid(_world_manager):
		player_pos = _world_manager.tracking_position

	for enemy in get_tree().get_nodes_in_group("attackable"):
		if not is_instance_valid(enemy):
			continue
		if enemy.global_position.distance_to(player_pos) > despawn_dist:
			enemy.queue_free()
