class_name SectorGrid

const SECTOR_SIZE_PX := 384
# Three interspersed concentric square boss rings (Chebyshev sectors), inner -> outer.
const BOSS_RING_DISTANCES := [8, 10, 12]
const BOSS_WORLD_EDGE := 12          # dist > this is empty void (world edge)
const BOSS_RING_ANCHOR_COUNT := 8    # anchors per ring
# Per-ring phase (fraction of anchor spacing) so anchors interleave in angle.
const BOSS_RING_PHASES := [0.0, 1.0 / 3.0, 2.0 / 3.0]
const BOSS_CLAIM_RADIUS := 3
const ELITE_CLAIM_RADIUS := 1
const EMPTY_WEIGHT := 1.5

class RoomSlot:
	var is_empty: bool = false
	var is_boss: bool = false
	var is_claimed: bool = false
	var template_index: int = -1
	var rotation: int = 0
	var template_size: int = 0
	var composition: Resource = null
	var template_override: RoomTemplate = null

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


# Index of a sector walking the perimeter of the square ring of radius d: 0 .. 8d-1.
static func _ring_index(coord: Vector2i, d: int) -> int:
	if coord.x == d:  return coord.y + d
	if coord.y == d:  return 2 * d + (d - coord.x)
	if coord.x == -d: return 4 * d + (d - coord.y)
	return 6 * d + (coord.x + d)


static func is_boss_anchor(coord: Vector2i) -> bool:
	var d: int = max(abs(coord.x), abs(coord.y))
	var k := BOSS_RING_DISTANCES.find(d)
	if k == -1:
		return false  # not on any boss ring
	var perim := 8 * d
	var r := _ring_index(coord, d)
	var phase: float = BOSS_RING_PHASES[k]
	for j in range(BOSS_RING_ANCHOR_COUNT):
		var t := int(round((float(j) + phase) * float(perim) / float(BOSS_RING_ANCHOR_COUNT))) % perim
		if t == r:
			return true
	return false


func _find_claiming_anchor(coord: Vector2i) -> Vector2i:
	for dx in range(-BOSS_CLAIM_RADIUS, BOSS_CLAIM_RADIUS + 1):
		for dy in range(-BOSS_CLAIM_RADIUS, BOSS_CLAIM_RADIUS + 1):
			var candidate := coord + Vector2i(dx, dy)
			if is_boss_anchor(candidate):
				return candidate
	return Vector2i.MAX


func resolve_sector(coord: Vector2i) -> RoomSlot:
	var slot := RoomSlot.new()

	if _biome != null and _biome.fixed_anchors.has(coord):
		var tmpl: RoomTemplate = _biome.fixed_anchors[coord]
		slot.template_override = tmpl
		slot.template_size = tmpl.size_class
		if tmpl.cavern_carve:
			slot.composition = tmpl.composition
		return slot

	var dist := chebyshev_distance(coord, Vector2i.ZERO)

	if dist > BOSS_WORLD_EDGE:
		slot.is_empty = true
		return slot

	if is_boss_anchor(coord):
		if _biome.boss_compositions.is_empty():
			slot.is_empty = true
			return slot
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(_seed ^ (coord.x * 73856093) ^ (coord.y * 19349663))
		slot.is_boss = true
		slot.template_index = rng.randi() % _biome.boss_compositions.size()
		slot.composition = _biome.boss_compositions[slot.template_index]
		return slot

	var anchor := _find_claiming_anchor(coord)
	if anchor != Vector2i.MAX:
		slot.is_empty = true
		slot.is_claimed = true
		return slot

	if _biome.room_templates.is_empty():
		slot.is_empty = true
		return slot

	var rng2 := RandomNumberGenerator.new()
	rng2.seed = hash(_seed ^ (coord.x * 73856093) ^ (coord.y * 19349663))
	var total := EMPTY_WEIGHT
	for tmpl in _biome.room_templates:
		total += (tmpl as RoomTemplate).weight
	var roll := rng2.randf() * total
	if roll < EMPTY_WEIGHT:
		slot.is_empty = true
		return slot
	var cumulative := EMPTY_WEIGHT
	for i in range(_biome.room_templates.size()):
		cumulative += (_biome.room_templates[i] as RoomTemplate).weight
		if roll < cumulative:
			slot.template_index = i
			var tmpl: RoomTemplate = _biome.room_templates[i]
			slot.rotation = (rng2.randi() % 4) * 90 if tmpl.rotatable else 0
			slot.template_size = tmpl.size_class
			if tmpl.cavern_carve:
				slot.composition = tmpl.composition
			return slot

	slot.is_empty = true
	return slot


func get_template_for_slot(slot: RoomSlot) -> RoomTemplate:
	if slot.is_empty or slot.is_boss:
		return null
	if slot.template_override != null:
		return slot.template_override
	return _biome.room_templates[slot.template_index]
