extends Node

const ENEMY_SCENE := preload("res://scenes/dummy_enemy.tscn")
const CHEST_SCENE := preload("res://scenes/chest.tscn")
const SHOP_SCENE  := preload("res://scenes/economy/shop_ui.tscn")
const PORTAL_SCENE := preload("res://scenes/portal.tscn")

const CHUNK_SIZE := 256

var _spawned_sectors: Dictionary = {}  # Vector2i → true
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
	_spawned_sectors.clear()
	_world_manager.chunks_generated.connect(_on_chunks_generated)


func clear() -> void:
	_spawned_sectors.clear()


func _on_chunks_generated(new_coords: Array[Vector2i]) -> void:
	var grid: SectorGrid = LevelManager.get_grid()
	if grid == null:
		return

	for chunk_coord in new_coords:
		var chunk_world_min := chunk_coord * CHUNK_SIZE
		var chunk_world_max := chunk_world_min + Vector2i(CHUNK_SIZE - 1, CHUNK_SIZE - 1)
		var sectors_seen: Dictionary = {}

		for corner in [
			chunk_world_min,
			chunk_world_max,
			Vector2i(chunk_world_max.x, chunk_world_min.y),
			Vector2i(chunk_world_min.x, chunk_world_max.y),
		]:
			var sector := grid.world_to_sector(Vector2(corner))
			if sectors_seen.has(sector):
				continue
			sectors_seen[sector] = true

			var sector_center := grid.sector_to_world_center(sector)
			# Only spawn if sector center is inside this chunk (avoids cross-chunk dupes)
			if sector_center.x < chunk_world_min.x or sector_center.x > chunk_world_max.x:
				continue
			if sector_center.y < chunk_world_min.y or sector_center.y > chunk_world_max.y:
				continue
			if _spawned_sectors.has(sector):
				continue

			var slot := grid.resolve_sector(sector)
			if slot.is_empty:
				_spawned_sectors[sector] = true
				continue

			_spawned_sectors[sector] = true
			_spawn_for_slot(grid, slot, sector, sector_center)


func _spawn_for_slot(grid: SectorGrid, slot, sector: Vector2i, world_center: Vector2i) -> void:
	var tmpl: RoomTemplate = grid.get_template_for_slot(slot)
	if tmpl == null:
		return
	var idx := BiomeRegistry.get_template_index(tmpl)
	if idx < 0:
		return
	var markers: Array = BiomeRegistry.template_pack.collect_markers(slot.template_size, idx)
	var size_f: int = slot.template_size
	var floor_num: int = LevelManager.floor_number
	var dist: int = grid.chebyshev_distance(sector, Vector2i.ZERO)

	for m in markers:
		var local_pos: Vector2i = m["pos"]
		var marker_type: int = m["type"]
		var rotated := _apply_rotation(local_pos, slot.rotation, size_f)
		var world_pos := Vector2(
			world_center.x - size_f / 2 + rotated.x,
			world_center.y - size_f / 2 + rotated.y,
		)
		_spawn_entity(marker_type, world_pos, dist, floor_num, slot.is_boss)


static func _apply_rotation(local: Vector2i, rotation_deg: int, size: int) -> Vector2i:
	var steps: int = rotation_deg / 90
	match steps:
		0: return local
		1: return Vector2i(local.y, size - 1 - local.x)
		2: return Vector2i(size - 1 - local.x, size - 1 - local.y)
		3: return Vector2i(size - 1 - local.y, local.x)
	return local


func _spawn_entity(marker: int, world_pos: Vector2, sector_dist: int, floor_num: int, is_boss_room: bool) -> void:
	match marker:
		1: _spawn_enemy(world_pos, sector_dist, floor_num, false, false)
		2: _spawn_enemy(world_pos, sector_dist, floor_num, false, true)  # elite
		3: _spawn_chest(world_pos, false)
		4: _spawn_shop(world_pos)
		5: _spawn_chest(world_pos, true)  # secret loot
		6: _spawn_enemy(world_pos, sector_dist, floor_num, true, false)  # boss
		7: pass  # PORTAL_ANCHOR — handled at boss death


func _spawn_enemy(world_pos: Vector2, sector_dist: int, floor_num: int, is_boss: bool, is_elite: bool) -> void:
	var enemy := ENEMY_SCENE.instantiate()

	var tier_index: int = clampi(int(floor(float(sector_dist) / float(SectorGrid.BOSS_RING_DISTANCE) * 2.0)), 0, 2)
	if "enemy_tier" in enemy:
		enemy.enemy_tier = tier_index

	var health_mult := 1.0 + (floor_num - 1) * 0.25
	var damage_mult := 1.0 + (floor_num - 1) * 0.15
	var speed_mult  := 1.0 + (floor_num - 1) * 0.10

	if "max_health" in enemy:
		enemy.max_health = int(float(enemy.max_health) * health_mult * (2.0 if is_elite else 1.0) * (5.0 if is_boss else 1.0))
	if "speed" in enemy:
		enemy.speed = enemy.speed * speed_mult * (1.5 if is_boss else 1.0)
	if "damage" in enemy:
		enemy.damage = int(float(enemy.damage) * damage_mult)

	if is_boss:
		enemy.modulate = LevelManager.current_biome.tint
		if enemy.has_signal("died"):
			enemy.died.connect(_on_boss_died.bind(world_pos))

	enemy.global_position = world_pos
	_spawn_parent.add_child(enemy)


func _spawn_chest(world_pos: Vector2, is_secret_loot: bool) -> void:
	var chest := CHEST_SCENE.instantiate()
	chest.global_position = world_pos
	if is_secret_loot and "rare_drop" in chest:
		chest.rare_drop = true
	_spawn_parent.add_child(chest)


func _spawn_shop(world_pos: Vector2) -> void:
	var shop := SHOP_SCENE.instantiate()
	_spawn_parent.get_parent().add_child(shop)


func _on_boss_died(arena_center: Vector2) -> void:
	var portal := PORTAL_SCENE.instantiate()
	portal.global_position = arena_center
	_spawn_parent.add_child(portal)
