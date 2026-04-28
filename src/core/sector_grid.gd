class_name SectorGrid

const SECTOR_SIZE_PX := 384
const BOSS_RING_DISTANCE := 10
const EMPTY_WEIGHT := 1.5  # weight added against sum of template weights

class RoomSlot:
	var is_empty: bool = false
	var is_boss: bool = false
	var template_index: int = -1
	var rotation: int = 0  # 0/90/180/270
	var template_size: int = 0

var _seed: int
var _biome: BiomeDef


func _init(world_seed: int, biome: BiomeDef) -> void:
	_seed = world_seed
	_biome = biome


func world_to_sector(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / SECTOR_SIZE_PX),
		floori(world_pos.y / SECTOR_SIZE_PX)
	)


func sector_to_world_center(coord: Vector2i) -> Vector2i:
	return Vector2i(
		coord.x * SECTOR_SIZE_PX + SECTOR_SIZE_PX / 2,
		coord.y * SECTOR_SIZE_PX + SECTOR_SIZE_PX / 2
	)


func chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return max(abs(a.x - b.x), abs(a.y - b.y))


func resolve_sector(coord: Vector2i) -> RoomSlot:
	var slot := RoomSlot.new()
	var dist := chebyshev_distance(coord, Vector2i.ZERO)

	if dist > BOSS_RING_DISTANCE:
		slot.is_empty = true
		return slot

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_seed ^ (coord.x * 73856093) ^ (coord.y * 19349663))

	if dist == BOSS_RING_DISTANCE:
		if _biome.boss_templates.is_empty():
			slot.is_empty = true
			return slot
		slot.is_boss = true
		slot.template_index = rng.randi() % _biome.boss_templates.size()
		var boss_tmpl: RoomTemplate = _biome.boss_templates[slot.template_index]
		slot.rotation = (rng.randi() % 4) * 90 if boss_tmpl.rotatable else 0
		slot.template_size = boss_tmpl.size_class
		return slot

	# Regular pick: weighted choice with EMPTY weight
	if _biome.room_templates.is_empty():
		slot.is_empty = true
		return slot

	var total := EMPTY_WEIGHT
	for tmpl in _biome.room_templates:
		total += (tmpl as RoomTemplate).weight

	var roll := rng.randf() * total
	if roll < EMPTY_WEIGHT:
		slot.is_empty = true
		return slot

	var cumulative := EMPTY_WEIGHT
	for i in range(_biome.room_templates.size()):
		cumulative += (_biome.room_templates[i] as RoomTemplate).weight
		if roll < cumulative:
			slot.template_index = i
			var tmpl: RoomTemplate = _biome.room_templates[i]
			slot.rotation = (rng.randi() % 4) * 90 if tmpl.rotatable else 0
			slot.template_size = tmpl.size_class
			return slot

	slot.is_empty = true
	return slot


func get_template_for_slot(slot: RoomSlot) -> RoomTemplate:
	if slot.is_empty:
		return null
	if slot.is_boss:
		return _biome.boss_templates[slot.template_index]
	return _biome.room_templates[slot.template_index]
