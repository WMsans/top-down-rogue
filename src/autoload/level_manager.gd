extends Node

signal floor_changed(floor_number: int)
signal boss_arena_entered(world_center: Vector2i)

const STAMP_BUFFER_SIZE := 16 + 128 * 16

var floor_number: int = 1
var world_seed: int = 0
var current_biome: BiomeDef
var _grid: SectorGrid
var _spawn_dispatcher: Node
var _cave_spawner: Node


func _ready() -> void:
	world_seed = randi()
	current_biome = BiomeRegistry.get_biome(floor_number)
	_grid = SectorGrid.new(world_seed, current_biome)
	var SpawnDispatcher = load("res://src/core/spawn_dispatcher.gd")
	_spawn_dispatcher = SpawnDispatcher.new()
	_spawn_dispatcher.name = "SpawnDispatcher"
	add_child(_spawn_dispatcher)
	var CaveSpawner = load("res://src/core/cave_spawner.gd")
	_cave_spawner = CaveSpawner.new()
	_cave_spawner.name = "CaveSpawner"
	add_child(_cave_spawner)
	_cave_spawner.set_biome_params(current_biome.cave_spawn_rate)


func get_grid() -> SectorGrid:
	return _grid


func get_biome() -> BiomeDef:
	return current_biome


func advance_floor() -> void:
	floor_number += 1
	world_seed = randi()
	current_biome = BiomeRegistry.get_biome(floor_number)
	_grid = SectorGrid.new(world_seed, current_biome)
	if _spawn_dispatcher and _spawn_dispatcher.has_method("clear"):
		_spawn_dispatcher.clear()
	if _cave_spawner and _cave_spawner.has_method("set_biome_params"):
		_cave_spawner.set_biome_params(current_biome.cave_spawn_rate)
	var wm := get_tree().get_first_node_in_group("world_manager")
	if wm and wm.has_method("reset"):
		wm.reset()
	floor_changed.emit(floor_number)


func build_stamp_bytes(chunk_coords: Array[Vector2i]) -> PackedByteArray:
	var seen_sectors: Dictionary = {}
	var stamps: Array = []

	for chunk_coord in chunk_coords:
		var chunk_world_min := chunk_coord * 256
		var chunk_world_max := chunk_world_min + Vector2i(255, 255)
		for corner in [
			chunk_world_min,
			chunk_world_max,
			Vector2i(chunk_world_max.x, chunk_world_min.y),
			Vector2i(chunk_world_min.x, chunk_world_max.y),
		]:
			var sector := _grid.world_to_sector(Vector2(corner))
			if seen_sectors.has(sector):
				continue
			seen_sectors[sector] = true

			var slot := _grid.resolve_sector(sector)
			if slot.is_empty:
				continue

			var tmpl := _grid.get_template_for_slot(slot)
			if tmpl == null:
				continue

			var center := _grid.sector_to_world_center(sector)
			var idx := BiomeRegistry.get_template_index(tmpl)
			if idx < 0:
				continue

			var rot_steps := slot.rotation / 90
			var flags := 0
			if tmpl.is_secret:
				flags |= 1
			var meta := (slot.template_size & 0xFF) | ((rot_steps & 0xFF) << 8) | ((flags & 0xFF) << 16)

			stamps.append({
				"cx": float(center.x),
				"cy": float(center.y),
				"idx": float(idx),
				"meta": float(meta),
			})
			if stamps.size() >= 128:
				break
		if stamps.size() >= 128:
			break

	return _encode_stamps(stamps)


func _encode_stamps(stamps: Array) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(STAMP_BUFFER_SIZE)
	buf.fill(0)
	buf.encode_s32(0, stamps.size())
	for i in range(stamps.size()):
		var s: Dictionary = stamps[i]
		var off := 16 + i * 16
		buf.encode_float(off + 0,  s["cx"])
		buf.encode_float(off + 4,  s["cy"])
		buf.encode_float(off + 8,  s["idx"])
		buf.encode_float(off + 12, s["meta"])
	return buf
