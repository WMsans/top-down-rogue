extends GdUnitTestSuite

# Pure placement tests for ForestPlanner: chunk-local coordinates only,
# no node spawning (that is Task 5), no GPU.

const _ForestDefScript := preload("res://src/core/forest_def.gd")
const _ForestPlannerScript := preload("res://src/terrain/forest_planner.gd")
const _ForestPropDefScript := preload("res://src/core/forest_prop_def.gd")
const _DecorDefScript := preload("res://src/core/decor_def.gd")

const CHUNK_SIZE := 256
const EPS := 0.001


func _make_texture() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)


func _prop(kind: String, role: String, family: String, radius: float) -> ForestPropDef:
	var d: ForestPropDef = _ForestPropDefScript.new()
	d.kind = kind
	d.role = role
	d.family = family
	d.trunk_radius = radius
	d.texture = _make_texture()
	return d


func _flora() -> DecorDef:
	var d: DecorDef = _DecorDefScript.new()
	d.texture = _make_texture()
	return d


func _solid() -> int:
	return MaterialRegistry.MAT_AIR + 1  # any non-air material id


func _all_solid_bytes() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(CHUNK_SIZE * CHUNK_SIZE)
	b.fill(_solid())
	return b


# Solid everywhere except an air disc of radius 110 centred at (128, 128).
func _room_bytes() -> PackedByteArray:
	var b := _all_solid_bytes()
	for y in range(CHUNK_SIZE):
		for x in range(CHUNK_SIZE):
			if Vector2(x - 128.0, y - 128.0).length() <= 110.0:
				b[y * CHUNK_SIZE + x] = MaterialRegistry.MAT_AIR
	return b


# Solid except a horizontal 24px-tall air band.
func _corridor_bytes() -> PackedByteArray:
	var b := _all_solid_bytes()
	for y in range(112, 136):
		for x in range(CHUNK_SIZE):
			b[y * CHUNK_SIZE + x] = MaterialRegistry.MAT_AIR
	return b


# Solid except a horizontal air band of `height` px centred on y = 132.
# height 40 (rows 112..151) leaves cell rows 14-18 open: the centre row 16
# reports wall_dist = 24 (Chebyshev 3 from the closed rows 13/19) while its
# cell centre (y = 132) is truly only 20px from the nearest solid row —
# exercising the up to CELL/2 overestimate of wall_dist.
func _band_bytes(height: int) -> PackedByteArray:
	var b := _all_solid_bytes()
	for y in range(132 - height / 2, 132 + height / 2):
		for x in range(CHUNK_SIZE):
			b[y * CHUNK_SIZE + x] = MaterialRegistry.MAT_AIR
	return b


# 6 tree defs (bright/dark/odd x pine/dead, radius 6), one rock def (radius 10),
# one flora def per flora array. Flora arrays hold distinct instances so tests
# can tell which array a placement came from.
func _forest(threshold: float) -> _ForestDefScript:
	var f: _ForestDefScript = _ForestDefScript.new()
	var trees: Array[ForestPropDef] = []
	trees.append(_prop("tree", "bright", "pine", 6.0))
	trees.append(_prop("tree", "bright", "dead", 6.0))
	trees.append(_prop("tree", "dark", "pine", 6.0))
	trees.append(_prop("tree", "dark", "dead", 6.0))
	trees.append(_prop("tree", "odd", "pine", 6.0))
	trees.append(_prop("tree", "odd", "dead", 6.0))
	f.tree_defs = trees
	var rocks: Array[ForestPropDef] = []
	rocks.append(_prop("rock", "any", "", 10.0))
	f.rock_defs = rocks
	var root_flora: Array[DecorDef] = []
	root_flora.append(_flora())
	f.root_flora = root_flora
	var edge_rocks: Array[DecorDef] = []
	edge_rocks.append(_flora())
	f.edge_rocks = edge_rocks
	var sprinkle_flora: Array[DecorDef] = []
	sprinkle_flora.append(_flora())
	f.sprinkle_flora = sprinkle_flora
	f.patch_threshold = threshold
	return f


func _props(entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		if e["kind"] == "prop":
			out.append(e)
	return out


func _flora_entries(entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		if e["kind"] == "flora":
			out.append(e)
	return out


func test_props_never_touch_solid() -> void:
	var bytes := _room_bytes()
	var entries := _ForestPlannerScript.plan(Vector2i(0, 0), _forest(-1.0), 42, bytes)
	var props := _props(entries)
	assert_int(props.size()).is_greater(0)
	assert_that(_solid_violation(bytes, props)).is_equal("")


# "" when every prop keeps the trunk_radius + PASS_GAP disc around its
# centre entirely on MAT_AIR pixels; otherwise a violation description.
func _solid_violation(bytes: PackedByteArray, props: Array) -> String:
	for p in props:
		var pos: Vector2 = p["pos"]
		var reach: float = p["def"].trunk_radius + _ForestPlannerScript.PASS_GAP
		var x0 := int(floor(pos.x - reach))
		var x1 := int(ceil(pos.x + reach))
		var y0 := int(floor(pos.y - reach))
		var y1 := int(ceil(pos.y + reach))
		for y in range(maxi(y0, 0), mini(y1 + 1, CHUNK_SIZE)):
			for x in range(maxi(x0, 0), mini(x1 + 1, CHUNK_SIZE)):
				if Vector2(x, y).distance_squared_to(pos) <= reach * reach \
						and bytes[y * CHUNK_SIZE + x] != MaterialRegistry.MAT_AIR:
					return "prop at %s has solid pixel (%d,%d) within trunk_radius+PASS_GAP" % [pos, x, y]
	return ""


# wall_dist is 8 * Chebyshev cell distance, but prop centres sit at cell
# centres, so the nearest solid pixel can be up to CELL/2 closer than
# wall_dist claims. A radius-6 tree on the 40px band's centre row passed the
# bare wall >= 6 + 16 filter (wall_dist = 24) while its 22px trunk disc
# reaches the solid row only 20px away. With the CELL/2 margin requirement
# (wall >= r + PASS_GAP + CELL/2) no band cell qualifies and nothing places.
func test_wall_dist_quantization_band_gets_no_props() -> void:
	var bytes := _band_bytes(40)
	var entries := _ForestPlannerScript.plan(Vector2i(0, 0), _forest(-1.0), 42, bytes)
	var props := _props(entries)
	assert_that(_solid_violation(bytes, props)).is_equal("")
	assert_int(props.size()).is_equal(0)


func test_props_respect_spacing() -> void:
	var entries := _ForestPlannerScript.plan(Vector2i(0, 0), _forest(-1.0), 42, _room_bytes())
	var props := _props(entries)
	var violation := ""
	for i in range(props.size()):
		for j in range(i + 1, props.size()):
			var need: float = props[i]["def"].trunk_radius + props[j]["def"].trunk_radius \
					+ _ForestPlannerScript.PASS_GAP
			var dist: float = (props[i]["pos"] as Vector2).distance_to(props[j]["pos"])
			if dist < need - EPS:
				violation = "props %d and %d are %.3f apart, need >= %.3f" % [i, j, dist, need]
	assert_that(violation).is_equal("")


func test_narrow_corridor_gets_no_props() -> void:
	var entries := _ForestPlannerScript.plan(Vector2i(0, 0), _forest(-1.0), 42, _corridor_bytes())
	assert_int(_props(entries).size()).is_equal(0)


func test_all_solid_gets_nothing() -> void:
	var entries := _ForestPlannerScript.plan(Vector2i(0, 0), _forest(-1.0), 42, _all_solid_bytes())
	assert_int(entries.size()).is_equal(0)


func test_main_group_roles_and_distances() -> void:
	var entries := _ForestPlannerScript.plan(Vector2i(0, 0), _forest(-1.0), 42, _room_bytes())
	var props := _props(entries)
	assert_int(props.size()).is_greater_equal(3)
	assert_that(props[0]["def"].role).is_equal("bright")
	assert_that(props[1]["def"].role).is_equal("dark")
	assert_that(props[2]["def"].role).is_equal("odd")
	var near: Vector2 = _ForestPlannerScript.MAIN_NEAR
	var far: Vector2 = _ForestPlannerScript.MAIN_FAR
	var d01: float = (props[0]["pos"] as Vector2).distance_to(props[1]["pos"])
	var d02: float = (props[0]["pos"] as Vector2).distance_to(props[2]["pos"])
	assert_bool(d01 >= near.x - EPS and d01 <= near.y + EPS) \
		.override_failure_message("dark tree %.3f from anchor, expected in [%s]" % [d01, near]) \
		.is_true()
	assert_bool(d02 >= far.x - EPS and d02 <= far.y + EPS) \
		.override_failure_message("odd tree %.3f from anchor, expected in [%s]" % [d02, far]) \
		.is_true()


func test_props_keep_edge_margin() -> void:
	var entries := _ForestPlannerScript.plan(Vector2i(0, 0), _forest(-1.0), 42, _room_bytes())
	var margin: float = _ForestPlannerScript.EDGE_MARGIN
	var violation := ""
	for p in _props(entries):
		var pos: Vector2 = p["pos"]
		if pos.x < margin - EPS or pos.y < margin - EPS \
				or pos.x > CHUNK_SIZE - margin + EPS or pos.y > CHUNK_SIZE - margin + EPS:
			violation = "prop at %s is closer than EDGE_MARGIN=%s to a chunk border" % [pos, margin]
	assert_that(violation).is_equal("")


func test_keep_out_blocks_props_not_flora() -> void:
	var keep_out := func(_world_pos: Vector2) -> bool:
		return true
	var entries := _ForestPlannerScript.plan(
		Vector2i(0, 0), _forest(-1.0), 42, _room_bytes(), keep_out)
	assert_int(_props(entries).size()).is_equal(0)
	assert_int(_flora_entries(entries).size()).is_greater(0)


# Root flora attaches to props only (brief step 7, "for each prop"), never to
# the edge-rock flora entries appended just before it. The narrow corridor
# places zero props but does place edge-rock flora, so exactly one root_flora
# entry may survive: the lone clearing accent.
func test_root_flora_only_attaches_to_props() -> void:
	var forest := _forest(-1.0)
	var entries := _ForestPlannerScript.plan(Vector2i(0, 0), forest, 42, _corridor_bytes())
	assert_int(_props(entries).size()).is_equal(0)
	var edge_count := 0
	var root_count := 0
	for e in _flora_entries(entries):
		if forest.edge_rocks.has(e["def"]):
			edge_count += 1
		elif forest.root_flora.has(e["def"]):
			root_count += 1
	assert_int(edge_count).is_greater(0)  # without edge rocks the case is vacuous
	assert_int(root_count).is_equal(1)
	# Room case: at most flora_per_tree root clusters per prop, plus the accent.
	var room := _forest(-1.0)
	var room_entries := _ForestPlannerScript.plan(Vector2i(0, 0), room, 42, _room_bytes())
	var room_props := _props(room_entries)
	assert_int(room_props.size()).is_greater(0)
	var room_roots := 0
	for e in _flora_entries(room_entries):
		if room.root_flora.has(e["def"]):
			room_roots += 1
	assert_bool(room_roots <= room_props.size() * room.flora_per_tree + 1) \
		.override_failure_message(
			"%d root flora for %d props (flora_per_tree=%d): clusters attached to non-prop entries"
			% [room_roots, room_props.size(), room.flora_per_tree]) \
		.is_true()


func test_outside_patch_only_sprinkle() -> void:
	var forest := _forest(1.0)  # simplex noise never exceeds 1.0 -> no patches
	forest.sprinkle_chance = 1.0
	var entries := _ForestPlannerScript.plan(Vector2i(0, 0), forest, 42, _room_bytes())
	assert_int(_props(entries).size()).is_equal(0)
	var flora := _flora_entries(entries)
	assert_int(flora.size()).is_greater(0)
	var violation := ""
	for e in flora:
		if not forest.sprinkle_flora.has(e["def"]):
			violation = "flora entry came from a non-sprinkle def: %s" % e["def"]
	assert_that(violation).is_equal("")


func _signature(entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		out.append([e["kind"], e["pos"], e["index"]])
	return out


func test_deterministic() -> void:
	var bytes := _room_bytes()
	var a := _signature(_ForestPlannerScript.plan(Vector2i(0, 0), _forest(-1.0), 999, bytes))
	var b := _signature(_ForestPlannerScript.plan(Vector2i(0, 0), _forest(-1.0), 999, bytes))
	assert_int(a.size()).is_equal(b.size())
	var same := true
	for i in range(a.size()):
		if a[i] != b[i]:
			same = false
	assert_that(same).is_true()
	var c := _signature(_ForestPlannerScript.plan(Vector2i(0, 0), _forest(-1.0), 1000, bytes))
	var different := a.size() != c.size()
	if not different:
		different = not same
		if not different:
			for i in range(a.size()):
				if a[i] != c[i]:
					different = true
	assert_that(different).is_true()


func test_sector_keep_out_guidance_anchor() -> void:
	var grid := SectorGrid.new(123, load("res://assets/biomes/caves.tres"))
	var center := Vector2(grid.sector_to_world_center(Vector2i.ZERO))
	assert_that(_ForestPlannerScript.sector_keep_out(grid, center)).is_true()
