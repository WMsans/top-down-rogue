extends Node

const MELEE_ENEMY_SCENE := preload("res://scenes/enemies/melee_enemy.tscn")
const RANGED_ENEMY_SCENE := preload("res://scenes/enemies/ranged_enemy.tscn")
const BOSS_ENEMY_SCENE := preload("res://scenes/enemies/boss_enemy.tscn")
const CHEST_SCENE := preload("res://scenes/chest.tscn")
const SHOP_STALL_SCENE := preload("res://scenes/economy/shop_stall.tscn")
const PORTAL_SCENE := preload("res://scenes/portal.tscn")
const LANTERN_SCENE := preload("res://scenes/props/lantern.tscn")
const SHOP_FLOOR_TEXTURE := preload("res://textures/Guidance/wooden_planks.png")

# Wood wall thickness around the sealed shop room (matches ShopChamberGenerator).
const SHOP_WALL_THICKNESS := 6

const CHUNK_SIZE := 256
const NUDGE_CELL: int = 8       # search step, one passability cell
const NUDGE_MAX_RINGS: int = 3  # outward search radius ~= 24px

const GAUNTLET_EXTRA_PER_RING := 0.34
const GAUNTLET_EXTRA_CAP := 4

const REINFORCE_INTERVAL := 12.0
const REINFORCE_SPAWN_DIST := 360.0

var _spawned_sectors: Dictionary = {}
var _world_manager: Node = null
var _spawn_parent: Node = null
var _reinforce_timer: float = 0.0


static func gauntlet_extra_count(sector_dist: int) -> int:
	return clampi(int(floor(float(sector_dist) * GAUNTLET_EXTRA_PER_RING)), 0, GAUNTLET_EXTRA_CAP)


func _process(delta: float) -> void:
	if _world_manager == null or not is_instance_valid(_world_manager):
		var wm := get_tree().get_first_node_in_group("world_manager")
		if wm == null:
			return
		_world_manager = wm
		_spawn_parent = _world_manager.get_chunk_container()
		_spawned_sectors.clear()
		_world_manager.chunks_generated.connect(_on_chunks_generated)
		return
	_tick_reinforcement(delta)


func clear() -> void:
	_spawned_sectors.clear()


func _tick_reinforcement(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player):
		return
	_reinforce_timer += delta
	if _reinforce_timer < REINFORCE_INTERVAL:
		return
	_reinforce_timer = 0.0
	var angle := randf() * TAU
	var spawn_pos: Vector2 = player.global_position + Vector2.from_angle(angle) * REINFORCE_SPAWN_DIST
	var resolved: Variant = _resolve_clear_position(spawn_pos)
	if resolved == null:
		return
	var grid: SectorGrid = LevelManager.get_grid()
	var sector_dist: int = 1
	if grid != null:
		sector_dist = grid.chebyshev_distance(grid.world_to_sector(spawn_pos), Vector2i.ZERO)
	_spawn_enemy(resolved, sector_dist, LevelManager.floor_number, false, false)


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
			if sector_center.x < chunk_world_min.x or sector_center.x > chunk_world_max.x:
				continue
			if sector_center.y < chunk_world_min.y or sector_center.y > chunk_world_max.y:
				continue
			if _spawned_sectors.has(sector):
				continue

			var slot := grid.resolve_sector(sector)
			if slot.is_boss:
				_spawned_sectors[sector] = true
				continue
			if slot.is_claimed:
				_spawned_sectors[sector] = true
				continue
			if slot.is_empty:
				_spawned_sectors[sector] = true
				continue

			_spawned_sectors[sector] = true
			_spawn_for_slot(grid, slot, sector, sector_center)


func _spawn_for_slot(grid: SectorGrid, slot, sector: Vector2i, world_center: Vector2i) -> void:
	var tmpl: RoomTemplate = grid.get_template_for_slot(slot)
	if tmpl == null:
		return
	if tmpl.cavern_carve:
		return
	var idx := BiomeRegistry.get_template_index(tmpl)
	if idx < 0:
		return
	var markers: Array = BiomeRegistry.template_pack.collect_markers(slot.template_size, idx)
	var size_f: int = slot.template_size
	var floor_num: int = LevelManager.floor_number
	var dist: int = grid.chebyshev_distance(sector, Vector2i.ZERO)
	var has_shop := false

	for m in markers:
		var local_pos: Vector2i = m["pos"]
		var marker_type: int = m["type"]
		if marker_type == 4:
			has_shop = true
		var rotated := _apply_rotation(local_pos, slot.rotation, size_f)
		var world_pos := Vector2(
			world_center.x - size_f / 2 + rotated.x,
			world_center.y - size_f / 2 + rotated.y,
		)
		_spawn_entity(marker_type, world_pos, dist, floor_num, slot.is_boss)

	if has_shop:
		_spawn_shop_floor(world_center, size_f)


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
		1:
			_spawn_enemy_validated(world_pos, sector_dist, floor_num, false, false)
			for _i in range(gauntlet_extra_count(sector_dist)):
				var jitter := Vector2(randf_range(-16, 16), randf_range(-16, 16))
				_spawn_enemy_validated(world_pos + jitter, sector_dist, floor_num, false, false)
		2: _spawn_enemy_validated(world_pos, sector_dist, floor_num, false, true)
		3: _spawn_chest(world_pos, false)
		4: _spawn_shop(world_pos)
		5: _spawn_chest(world_pos, true)
		6: _spawn_enemy(world_pos, sector_dist, floor_num, true, false)
		7: pass
		8: _spawn_lantern(world_pos)


# Returns world_pos unchanged when its footprint is clear; otherwise the nearest
# clear position within NUDGE_MAX_RINGS rings; otherwise null (caller skips).
func _resolve_clear_position(world_pos: Vector2) -> Variant:
	if SpawnValidation.footprint_clear(_world_manager, world_pos):
		return world_pos
	for ring in range(1, NUDGE_MAX_RINGS + 1):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if abs(dx) != ring and abs(dy) != ring:
					continue  # interior cells were covered by smaller rings
				var cand := world_pos + Vector2(dx * NUDGE_CELL, dy * NUDGE_CELL)
				if SpawnValidation.footprint_clear(_world_manager, cand):
					return cand
	return null


func _spawn_enemy_validated(world_pos: Vector2, sector_dist: int, floor_num: int, is_boss: bool, is_elite: bool) -> void:
	var resolved: Variant = _resolve_clear_position(world_pos)
	if resolved == null:
		return
	_spawn_enemy(resolved, sector_dist, floor_num, is_boss, is_elite)


func _spawn_enemy(world_pos: Vector2, sector_dist: int, floor_num: int, is_boss: bool, is_elite: bool) -> void:
	var enemy: Enemy
	if is_boss:
		enemy = BOSS_ENEMY_SCENE.instantiate()
		enemy.weapon_resource = WeaponRegistry.get_weapon_by_id("boss_staff")
	else:
		if is_elite:
			enemy = MELEE_ENEMY_SCENE.instantiate()
			enemy.is_elite = true
			enemy.elite_ability = randi() % 4 + 1
			enemy.weapon_resource = _pick_melee_weapon()
		else:
			if randf() < 0.8:
				enemy = MELEE_ENEMY_SCENE.instantiate()
				enemy.weapon_resource = _pick_melee_weapon()
			else:
				enemy = RANGED_ENEMY_SCENE.instantiate()
				enemy.weapon_resource = _pick_ranged_weapon()

	var tier_index: int = SectorGrid.enemy_tier_for_distance(sector_dist)
	if "enemy_tier" in enemy:
		enemy.enemy_tier = tier_index

	var health_mult := 1.0 + (floor_num - 1) * 0.25
	var damage_mult := 1.0 + (floor_num - 1) * 0.15
	var speed_mult  := 1.0 + (floor_num - 1) * 0.10

	enemy.max_health = int(float(enemy.max_health) * health_mult * (2.0 if is_elite else 1.0) * (5.0 if is_boss else 1.0))
	enemy.speed = enemy.speed * speed_mult * (1.5 if is_boss else 1.0)

	if is_boss:
		if "weapon_resource" in enemy and enemy.weapon_resource:
			enemy.weapon_resource.damage *= damage_mult

	if is_boss:
		enemy.modulate = LevelManager.current_biome.tint
		if enemy.has_signal("died"):
			enemy.died.connect(_on_boss_died.bind(world_pos))

	enemy.global_position = world_pos
	_spawn_parent.add_child(enemy)


func _pick_melee_weapon() -> Weapon:
	if randf() < 0.5:
		return WeaponRegistry.get_weapon_by_id("rusty_sword")
	return WeaponRegistry.get_weapon_by_id("bone_dagger")


func _pick_ranged_weapon() -> Weapon:
	if randf() < 0.7:
		return WeaponRegistry.get_weapon_by_id("throwing_knife")
	return WeaponRegistry.get_weapon_by_id("fire_orb")


func _spawn_chest(world_pos: Vector2, is_secret_loot: bool) -> void:
	var chest := CHEST_SCENE.instantiate()
	chest.global_position = world_pos
	chest.tier = DropTable.EnemyTier.HARD if is_secret_loot else DropTable.EnemyTier.NORMAL
	_spawn_parent.add_child(chest)


func _spawn_shop(world_pos: Vector2) -> void:
	var stall := SHOP_STALL_SCENE.instantiate()
	stall.global_position = world_pos
	_spawn_parent.add_child(stall)


# Lays a wooden-plank floor over the sealed shop interior, mirroring the
# guidance room's floor overlay. The room is square, so the floor is a square
# inset by the wall thickness rather than the circular guidance disc.
func _spawn_shop_floor(world_center: Vector2i, room_size: int) -> void:
	var half := float(room_size) / 2.0 - float(SHOP_WALL_THICKNESS)
	var poly := Polygon2D.new()
	poly.name = "ShopFloor"
	poly.texture = SHOP_FLOOR_TEXTURE
	poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	poly.z_index = -5
	poly.polygon = PackedVector2Array([
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half),
	])
	poly.global_position = Vector2(world_center)
	_spawn_parent.add_child(poly)


func _spawn_lantern(world_pos: Vector2) -> void:
	var lantern := LANTERN_SCENE.instantiate()
	lantern.global_position = world_pos
	_spawn_parent.add_child(lantern)


func _on_boss_died(arena_center: Vector2) -> void:
	var portal := PORTAL_SCENE.instantiate()
	portal.global_position = arena_center
	_spawn_parent.add_child(portal)
