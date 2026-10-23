class_name ForestPlanner
extends RefCounted

## Deterministic forest patch placement for one chunk; pure logic, spawns no
## nodes. plan() returns entries FloorChunk (Task 5) turns into ForestProp and
## decor nodes:
##   {"kind": "prop" | "flora", "def": ForestPropDef | DecorDef,
##    "pos": Vector2 (chunk-local; trunk base for props), "index": int}
## Identical inputs always produce an identical array, so `index` is a stable
## prop identity across reloads.

const CELL := 8                    # coarse placement grid, px per cell
const EDGE_MARGIN := 16.0          # props stay this far from a chunk border
const PASS_GAP := 16.0             # air ring kept around every trunk
const HUG_MAX := 56.0              # props only place where the wall is this close
const MAIN_NEAR := Vector2(24, 40)     # dark tree distance band from the anchor
const MAIN_FAR := Vector2(64, 112)     # odd tree distance band from the anchor
const SECONDARY_MIN_DIST := 96.0   # secondary groups start this far out
const ROOT_RING := Vector2(6, 28)  # root flora radius band around a prop
const KEEP_OUT_MARGIN := 32.0      # sector_keep_out slack around template rooms

const _CHUNK_SIZE := 256
const _UNREACHABLE_WALL := 1000000  # wall_dist sentinel for cells with no wall in-chunk
# wall_dist is quantised to whole cells while prop centres sit at cell
# centres, so the nearest solid pixel can be up to CELL/2 closer than
# wall_dist claims. Radius filters add this slack so the trunk's
# r + PASS_GAP air disc is never-touch-solid for real.
const _WALL_SLACK := CELL * 0.5


static func plan(
		coord: Vector2i,
		forest: ForestDef,
		world_seed: int,
		material_bytes: PackedByteArray,
		keep_out: Callable = Callable()) -> Array:
	var entries: Array = []
	if forest == null or material_bytes.size() < _CHUNK_SIZE * _CHUNK_SIZE:
		return entries

	var rng := RandomNumberGenerator.new()
	rng.seed = FloorChunk._hash_seed(world_seed, coord)
	var origin := Vector2(coord.x * _CHUNK_SIZE, coord.y * _CHUNK_SIZE)

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = world_seed
	noise.frequency = forest.patch_frequency

	# Coarse grid: keep open, in-patch cells and bucket them by what they can host.
	var grid_cells := _CHUNK_SIZE / CELL
	var wall_dist := _coarse_wall_dist(material_bytes)
	var prop_cells: Array = []    # patch cells eligible for props
	var edge_rock_cells: Array = []
	var clearing: Dictionary = {}  # in-patch open cell with the largest wall_dist
	for cy in range(grid_cells):
		for cx in range(grid_cells):
			var idx := cy * grid_cells + cx
			if wall_dist[idx] <= 0:
				continue  # closed cell
			var pos := Vector2(cx * CELL + CELL * 0.5, cy * CELL + CELL * 0.5)
			var world := origin + pos
			if noise.get_noise_2d(world.x, world.y) <= forest.patch_threshold:
				continue  # outside a forest patch
			var cell := {"pos": pos, "wall": wall_dist[idx]}
			if clearing.is_empty() or cell["wall"] > clearing["wall"]:
				clearing = cell
			if cell["wall"] <= HUG_MAX \
					and pos.x >= EDGE_MARGIN and pos.y >= EDGE_MARGIN \
					and pos.x <= _CHUNK_SIZE - EDGE_MARGIN \
					and pos.y <= _CHUNK_SIZE - EDGE_MARGIN \
					and not _kept_out(keep_out, world):
				prop_cells.append(cell)
			if cell["wall"] == CELL:
				edge_rock_cells.append(cell)

	var placed: Array = []  # accepted props as {"pos": Vector2, "radius": float}

	# Main group: anchor tree, then dark and odd trees at set bands from it.
	var anchor_pos := Vector2.INF
	var anchor_family := ""
	if not prop_cells.is_empty():
		var bright_pool := _role_pool(forest.tree_defs, "bright")
		var anchor_cells: Array = prop_cells
		if not bright_pool.is_empty():
			var min_r := INF
			for d in bright_pool:
				min_r = minf(min_r, d.trunk_radius)
			anchor_cells = []
			for cell in prop_cells:
				if cell["wall"] >= min_r + PASS_GAP + _WALL_SLACK:
					anchor_cells.append(cell)
		if not anchor_cells.is_empty():
			var anchor: Dictionary = anchor_cells[rng.randi() % anchor_cells.size()]
			anchor_pos = anchor["pos"]
			var main := _place_prop(entries, placed, bright_pool, [anchor], rng)
			if not main.is_empty():
				anchor_family = main["def"].family
			var dark := _place_prop(entries, placed,
					_role_pool(forest.tree_defs, "dark"), prop_cells, rng,
					anchor_pos, MAIN_NEAR.x, MAIN_NEAR.y)
			if anchor_family == "" and not dark.is_empty():
				# bright failed at the anchor; the dark pick defines the group family
				anchor_family = dark["def"].family
			_place_prop(entries, placed,
					_role_pool(forest.tree_defs, "odd"), prop_cells, rng,
					anchor_pos, MAIN_FAR.x, MAIN_FAR.y)

	# Secondary groups: distinct-family clusters at least SECONDARY_MIN_DIST out.
	if anchor_pos != Vector2.INF:
		for _g in range(forest.secondary_groups):
			var far_cells: Array = []
			for cell in prop_cells:
				if cell["pos"].distance_to(anchor_pos) >= SECONDARY_MIN_DIST:
					far_cells.append(cell)
			var families: PackedStringArray = []
			for def in forest.tree_defs:
				if def.family != anchor_family and not def.family.is_empty() \
						and not families.has(def.family):
					families.append(def.family)
			if far_cells.is_empty() or families.is_empty():
				continue
			var family: String = families[rng.randi() % families.size()]
			var fam_pool: Array = []
			for def in forest.tree_defs:
				if def.family == family:
					fam_pool.append(def)
			var spot: Dictionary = _place_prop(entries, placed, fam_pool, far_cells, rng)
			if not spot.is_empty() and rng.randi() % 2 == 1:
				_place_prop(entries, placed, fam_pool, prop_cells, rng,
						spot["pos"], 20.0, 36.0)

	# Rocks: hug the wall harder than trees (closest eligible candidate to a wall).
	for _attempt in range(forest.rock_attempts):
		_place_rock(entries, placed, forest.rock_defs, prop_cells, rng)

	# Edge rocks: flora laid against the wall, on in-patch cells touching it.
	if not forest.edge_rocks.is_empty():
		var wall_hugs := edge_rock_cells.duplicate()
		_shuffle(wall_hugs, rng)
		for i in range(mini(forest.edge_rock_count, wall_hugs.size())):
			_add_flora(entries, forest.edge_rocks, wall_hugs[i]["pos"], rng)

	# Root flora: glowing plants clustered at each prop base, plus one lone
	# accent in the clearing (the in-patch cell farthest from any wall).
	# Only real props (kind == "prop") get clusters; the edge-rock flora
	# appended just above are decoration, not hosts.
	var props_placed: Array = []
	for e in entries:
		if e["kind"] == "prop":
			props_placed.append(e)
	if not forest.root_flora.is_empty():
		for p in props_placed:
			for _i in range(forest.flora_per_tree):
				for _try in range(8):
					var angle := rng.randf() * TAU
					var ring_r := rng.randf_range(ROOT_RING.x, ROOT_RING.y)
					var flora_pos: Vector2 = p["pos"] + Vector2.from_angle(angle) * ring_r
					if _pixel_is_air(material_bytes, flora_pos):
						_add_flora(entries, forest.root_flora, flora_pos, rng)
						break
		if not clearing.is_empty():
			_add_flora(entries, forest.root_flora, clearing["pos"], rng)

	# Sprinkle: lone flora from the sprinkle set on air cells outside patches.
	if not forest.sprinkle_flora.is_empty() and forest.sprinkle_chance > 0.0:
		var tiles := _CHUNK_SIZE / 16
		for ty in range(tiles):
			for tx in range(tiles):
				var local := Vector2(tx * 16 + 8, ty * 16 + 8)
				var world := origin + local
				if noise.get_noise_2d(world.x, world.y) > forest.patch_threshold:
					continue  # inside a forest patch
				if not _pixel_is_air(material_bytes, local):
					continue
				if rng.randf() >= forest.sprinkle_chance:
					continue
				_add_flora(entries, forest.sprinkle_flora, local, rng)

	return entries


# Veto for props near reserved sector features: boss/claimed/composition/
# override slots, and template rooms (shops, chests, the guidance anchor).
static func sector_keep_out(grid: SectorGrid, world_pos: Vector2) -> bool:
	var sector := grid.world_to_sector(world_pos)
	var slot := grid.resolve_sector(sector)
	if slot.is_boss or slot.is_claimed or slot.composition != null \
			or slot.template_override != null:
		return true
	var tmpl := grid.get_template_for_slot(slot)
	if tmpl != null:
		var center := Vector2(grid.sector_to_world_center(sector))
		var reach := tmpl.size_class / 2.0 + KEEP_OUT_MARGIN
		if maxf(absf(world_pos.x - center.x), absf(world_pos.y - center.y)) <= reach:
			return true
	return false


# Distance from each open 8px cell to the nearest closed (partly solid) cell,
# 8-connected BFS in cells, multiplied by CELL for pixels. Closed cells get 0;
# open cells with no wall in this chunk get a sentinel larger than any filter.
static func _coarse_wall_dist(material_bytes: PackedByteArray) -> PackedInt32Array:
	var grid_cells := _CHUNK_SIZE / CELL
	var dist := PackedInt32Array()
	dist.resize(grid_cells * grid_cells)
	dist.fill(-1)
	var queue: Array[int] = []
	for cy in range(grid_cells):
		for cx in range(grid_cells):
			var closed := false
			for py in range(cy * CELL, cy * CELL + CELL):
				for px in range(cx * CELL, cx * CELL + CELL):
					if material_bytes[py * _CHUNK_SIZE + px] != MaterialRegistry.MAT_AIR:
						closed = true
						break
				if closed:
					break
			if closed:
				var i := cy * grid_cells + cx
				dist[i] = 0
				queue.append(i)
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		var cx := cur % grid_cells
		var cy := cur / grid_cells
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := cx + dx
				var ny := cy + dy
				if dx == 0 and dy == 0 or nx < 0 or ny < 0 \
						or nx >= grid_cells or ny >= grid_cells:
					continue  # cells outside the chunk count as open, never sources
				var ni := ny * grid_cells + nx
				if dist[ni] == -1:
					dist[ni] = dist[cur] + 1
					queue.append(ni)
	for i in range(dist.size()):
		dist[i] = _UNREACHABLE_WALL if dist[i] == -1 else dist[i] * CELL
	return dist


# Places one prop from `pool` on an eligible cell; when `from`/`dist_min`/
# `dist_max` are given the cell must sit inside that distance band of `from`.
# Tries pool members by weighted draw until one has an eligible cell.
# Returns the placed entry, or {} when the slot is skipped.
static func _place_prop(
		entries: Array,
		placed: Array,
		pool: Array,
		cells: Array,
		rng: RandomNumberGenerator,
		from: Vector2 = Vector2.INF,
		dist_min: float = 0.0,
		dist_max: float = INF) -> Dictionary:
	var ordered := pool.duplicate()
	while not ordered.is_empty():
		var def: ForestPropDef = _weighted_pick(ordered, rng)
		ordered.erase(def)
		var eligible: Array = []
		for cell in cells:
			if from != Vector2.INF:
				var d: float = cell["pos"].distance_to(from)
				if d < dist_min or d > dist_max:
					continue
			if cell["wall"] < def.trunk_radius + PASS_GAP + _WALL_SLACK:
				continue
			if not _spacing_ok(cell["pos"], def.trunk_radius, placed):
				continue
			eligible.append(cell)
		if eligible.is_empty():
			continue
		return _add_prop(entries, placed, def, eligible[rng.randi() % eligible.size()]["pos"])
	return {}


# Rocks prefer the eligible cell closest to a wall (smallest wall_dist).
static func _place_rock(
		entries: Array,
		placed: Array,
		pool: Array,
		cells: Array,
		rng: RandomNumberGenerator) -> Dictionary:
	var ordered := pool.duplicate()
	while not ordered.is_empty():
		var def: ForestPropDef = _weighted_pick(ordered, rng)
		ordered.erase(def)
		var best: Variant = null
		for cell in cells:
			if cell["wall"] < def.trunk_radius + PASS_GAP + _WALL_SLACK:
				continue
			if not _spacing_ok(cell["pos"], def.trunk_radius, placed):
				continue
			if best == null or cell["wall"] < best["wall"]:
				best = cell
		if best != null:
			return _add_prop(entries, placed, def, best["pos"])
	return {}


static func _add_prop(
		entries: Array, placed: Array, def: ForestPropDef, pos: Vector2) -> Dictionary:
	var entry := {"kind": "prop", "def": def, "pos": pos, "index": entries.size()}
	entries.append(entry)
	placed.append({"pos": pos, "radius": def.trunk_radius})
	return entry


static func _add_flora(
		entries: Array, defs: Array, pos: Vector2, rng: RandomNumberGenerator) -> void:
	var def: Variant = _weighted_pick(defs, rng)
	entries.append({"kind": "flora", "def": def, "pos": pos, "index": entries.size()})


# Defs carrying `role`; a role with no defs falls back to the role-"any" ones.
static func _role_pool(defs: Array[ForestPropDef], role: String) -> Array:
	var out: Array = []
	var fallback: Array = []
	for d in defs:
		if d.role == role:
			out.append(d)
		elif d.role == "any":
			fallback.append(d)
	return out if not out.is_empty() else fallback


static func _spacing_ok(pos: Vector2, radius: float, placed: Array) -> bool:
	for p in placed:
		var need: float = radius + p["radius"] + PASS_GAP
		if pos.distance_to(p["pos"]) < need:
			return false
	return true


static func _weighted_pick(defs: Array, rng: RandomNumberGenerator) -> Variant:
	var total := 0.0
	for d in defs:
		total += maxf(d.weight, 0.0)
	if total <= 0.0:
		return defs[0]
	var roll := rng.randf() * total
	for d in defs:
		roll -= maxf(d.weight, 0.0)
		if roll < 0.0:
			return d
	return defs[defs.size() - 1]


# Deterministic Fisher-Yates; Array.shuffle() would use the global RNG.
static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp


static func _kept_out(keep_out: Callable, world: Vector2) -> bool:
	if keep_out.is_valid():
		return bool(keep_out.call(world))
	return false


static func _pixel_is_air(material_bytes: PackedByteArray, local: Vector2) -> bool:
	var x := int(floor(local.x))
	var y := int(floor(local.y))
	if x < 0 or y < 0 or x >= _CHUNK_SIZE or y >= _CHUNK_SIZE:
		return false
	return material_bytes[y * _CHUNK_SIZE + x] == MaterialRegistry.MAT_AIR
