extends GdUnitTestSuite

const _FloorChunk = preload("res://src/terrain/floor_chunk.gd")
const _BiomeDef = preload("res://src/core/biome_def.gd")
const _ForestDef = preload("res://src/core/forest_def.gd")
const _ForestPropDef = preload("res://src/core/forest_prop_def.gd")
const _DecorDef = preload("res://src/core/decor_def.gd")

const CHUNK_SIZE := 256

# World-manager stub exposing an entity layer; get_chunk_container and
# chunks_generated satisfy the dispatcher autoloads that adopt the group.
class StubWM extends Node:
	var entity_layer: Node2D = null
	var nav_field = null

	signal chunks_generated(new_coords: Array[Vector2i])

	func get_chunk_container() -> Node2D:
		return null

func _make_texture(width: int, height: int) -> ImageTexture:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)

func _prop_def(kind: String, role: String, family: String, radius: float) -> _ForestPropDef:
	var d: _ForestPropDef = _ForestPropDef.new()
	d.kind = kind
	d.role = role
	d.family = family
	d.trunk_radius = radius
	d.texture = _make_texture(16, 16)
	return d

func _flora_def(emits_light: bool) -> _DecorDef:
	var d: _DecorDef = _DecorDef.new()
	d.texture = _make_texture(16, 16)
	d.emits_light = emits_light
	return d

# Full forest fixture: 6 trees (bright/dark/odd x pine/dead, radius 6), one rock
# (radius 10) and one flora in each flora array. Threshold -1.0 puts every cell
# inside a forest patch.
func _make_forest(flora_emits: bool = true) -> _ForestDef:
	var f: _ForestDef = _ForestDef.new()
	var trees: Array[ForestPropDef] = []
	for role in ["bright", "dark", "odd"]:
		for family in ["pine", "dead"]:
			trees.append(_prop_def("tree", role, family, 6.0))
	f.tree_defs = trees
	var rocks: Array[ForestPropDef] = [_prop_def("rock", "any", "", 10.0)]
	f.rock_defs = rocks
	var flora: Array[DecorDef] = [_flora_def(flora_emits)]
	f.root_flora = flora
	f.sprinkle_flora = flora.duplicate()
	f.patch_threshold = -1.0
	return f

func _make_biome(forest: _ForestDef) -> _BiomeDef:
	var b: _BiomeDef = _BiomeDef.new()
	b.floor_texture = _make_texture(16, 16)
	b.forest = forest
	return b

func _all_air_bytes() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(CHUNK_SIZE * CHUNK_SIZE)
	b.fill(MaterialRegistry.MAT_AIR)
	return b

func _all_solid_bytes() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(CHUNK_SIZE * CHUNK_SIZE)
	b.fill(MaterialRegistry.MAT_AIR + 1)   # any non-air material id
	return b

# Solid everywhere except an air disc of radius 110 centred at (128, 128): the
# same open-room fixture the planner tests use. Props hug the wall ring of the
# disc; an all-air chunk has no wall anywhere and deliberately gets no props
# (the planner keeps infinite open floors clear so passages are never sealed).
func _room_bytes() -> PackedByteArray:
	var b := _all_solid_bytes()
	for y in range(CHUNK_SIZE):
		for x in range(CHUNK_SIZE):
			if Vector2(x - 128.0, y - 128.0).length() <= 110.0:
				b[y * CHUNK_SIZE + x] = MaterialRegistry.MAT_AIR
	return b

func _floor_sprite(chunk: _FloorChunk) -> Sprite2D:
	return chunk.get_node_or_null("FloorSprite") as Sprite2D

func _decor_sprites(chunk: _FloorChunk) -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	for child in chunk.get_children():
		# "DecorLights" (the baked PointLight2D) also starts with "Decor".
		if child is Sprite2D and child.name.begins_with("Decor"):
			out.append(child as Sprite2D)
	return out

func _prop_nodes(chunk: _FloorChunk) -> Array[ForestProp]:
	var out: Array[ForestProp] = []
	for child in chunk.get_children():
		if child is ForestProp:
			out.append(child as ForestProp)
	return out

func _planned_props(coord: Vector2i, forest: _ForestDef, world_seed: int,
		material_bytes: PackedByteArray) -> Array:
	var out: Array = []
	for e in ForestPlanner.plan(coord, forest, world_seed, material_bytes):
		if e["kind"] == "prop":
			out.append(e)
	return out

func test_populate_creates_floor_sprite_at_chunk_size() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(null), 12345, _all_air_bytes())
	var sprite := _floor_sprite(chunk)
	assert_that(sprite).is_not_null()
	assert_that(sprite.region_enabled).is_true()
	assert_that(sprite.region_rect.size).is_equal(Vector2(CHUNK_SIZE, CHUNK_SIZE))

func test_populate_skips_when_floor_texture_missing() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	var biome := _BiomeDef.new()  # no floor_texture
	biome.forest = _make_forest()
	chunk.populate(Vector2i(0, 0), biome, 12345, _all_air_bytes())
	assert_that(_floor_sprite(chunk)).is_null()

func test_null_forest_creates_no_flora_or_props() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(null), 42, _room_bytes())
	assert_that(_decor_sprites(chunk).size()).is_equal(0)
	assert_that(_prop_nodes(chunk).size()).is_equal(0)

func test_nothing_placed_on_all_solid_bytes() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(_make_forest()), 42, _all_solid_bytes())
	assert_that(_decor_sprites(chunk).size()).is_equal(0)
	assert_that(_prop_nodes(chunk).size()).is_equal(0)

func test_empty_material_bytes_skips_forest_pass() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(_make_forest()), 42, PackedByteArray())
	assert_that(_decor_sprites(chunk).size()).is_equal(0)
	assert_that(_prop_nodes(chunk).size()).is_equal(0)

func test_populate_spawns_forest_props() -> void:
	var forest := _make_forest()
	var coord := Vector2i(0, 0)
	var world_seed := 4242
	var bytes := _room_bytes()
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(coord, _make_biome(forest), world_seed, bytes)
	var props := _prop_nodes(chunk)
	assert_that(props.size()).is_greater(0)
	var planned := _planned_props(coord, forest, world_seed, bytes)
	assert_that(props.size()).is_equal(planned.size())
	for i in range(props.size()):
		assert_that(props[i].position).is_equal(planned[i]["pos"])

func test_destroyed_prop_not_respawned() -> void:
	var forest := _make_forest(false)
	var coord := Vector2i(0, 0)
	var world_seed := 5150  # unique id space so the static registry cannot leak across tests
	var bytes := _room_bytes()
	var chunk_a := _FloorChunk.new()
	add_child(chunk_a)
	chunk_a.populate(coord, _make_biome(forest), world_seed, bytes)
	var props_a := _prop_nodes(chunk_a)
	assert_that(props_a.size()).is_greater(1)
	var first := props_a[0]
	var dead_id: String = first._prop_id
	first.take_dig_hit(first.global_position, Vector2.RIGHT, 0.0)
	assert_that(ForestProp.is_destroyed(dead_id)).is_true()

	var chunk_b := _FloorChunk.new()
	add_child(chunk_b)
	chunk_b.populate(coord, _make_biome(forest), world_seed, bytes)
	var props_b := _prop_nodes(chunk_b)
	assert_that(props_b.size()).is_equal(props_a.size() - 1)
	for p in props_b:
		assert_that(p._prop_id).is_not_equal(dead_id)

func test_flora_feeds_baked_light() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(_make_forest(true)), 4343, _room_bytes())
	assert_that(_decor_sprites(chunk).size()).is_greater(0)
	var lights := 0
	for child in chunk.get_children():
		if child is PointLight2D:
			lights += 1
	assert_that(lights).is_equal(1)
	assert_that(chunk.get_node_or_null("DecorLights")).is_not_null()

func test_non_glowing_flora_has_no_decor_lights() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(_make_forest(false)), 4444, _room_bytes())
	assert_that(_decor_sprites(chunk).size()).is_greater(0)
	assert_that(chunk.get_node_or_null("DecorLights")).is_null()

# Flora sprites are bottom-centred at the placement point: with centered = true
# the offset must be NEGATIVE half the texture height so the sprite's bottom
# edge sits on pos (same anchoring as ForestProp.setup).
func test_flora_sprites_bottom_centred_at_placement_point() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(_make_forest(false)), 4545, _room_bytes())
	var decors := _decor_sprites(chunk)
	assert_that(decors.size()).is_greater(0)
	for sprite in decors:
		assert_that(sprite.centered).is_true()
		assert_that(sprite.offset.y).is_equal(-float(sprite.texture.get_height()) / 2.0)

func test_placement_is_deterministic_for_same_seed_and_coord() -> void:
	var biome := _make_biome(_make_forest())
	var bytes := _room_bytes()
	var a := _FloorChunk.new()
	var b := _FloorChunk.new()
	add_child(a)
	add_child(b)
	a.populate(Vector2i(3, -2), biome, 999, bytes)
	b.populate(Vector2i(3, -2), biome, 999, bytes)
	var ad := _decor_sprites(a)
	var bd := _decor_sprites(b)
	assert_that(ad.size()).is_equal(bd.size())
	for i in range(ad.size()):
		assert_that(ad[i].position).is_equal(bd[i].position)
		assert_that(ad[i].texture).is_same(bd[i].texture)
	var ap := _prop_nodes(a)
	var bp := _prop_nodes(b)
	assert_that(ap.size()).is_equal(bp.size())
	for i in range(ap.size()):
		assert_that(ap[i].position).is_equal(bp[i].position)

func test_placement_differs_across_coords() -> void:
	var biome := _make_biome(_make_forest())
	var bytes := _room_bytes()
	var a := _FloorChunk.new()
	var b := _FloorChunk.new()
	add_child(a)
	add_child(b)
	a.populate(Vector2i(0, 0), biome, 7, bytes)
	b.populate(Vector2i(1, 0), biome, 7, bytes)
	var ap := _prop_nodes(a)
	var bp := _prop_nodes(b)
	var identical := ap.size() == bp.size()
	if identical:
		for i in range(ap.size()):
			if ap[i].position != bp[i].position:
				identical = false
				break
	assert_that(identical).is_false()


func _wm_with_layer() -> StubWM:
	var wm: StubWM = auto_free(StubWM.new())
	wm.entity_layer = Node2D.new()
	wm.entity_layer.y_sort_enabled = true
	wm.add_child(wm.entity_layer)
	wm.add_to_group("world_manager")
	add_child(wm)
	return wm


func _raised_decor(layer: Node) -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	for child in layer.get_children():
		if child is Sprite2D and child.name.begins_with("Decor"):
			out.append(child as Sprite2D)
	return out


func test_front_flora_moves_to_entity_layer_darkened() -> void:
	var wm := _wm_with_layer()
	var forest := _make_forest(false)
	var world_seed := 4646
	var bytes := _room_bytes()
	# Expected darkness per flora position, from the planner's own layout.
	var props: Array = []
	var floras: Array = []
	for e in ForestPlanner.plan(Vector2i(0, 0), forest, world_seed, bytes):
		(props if e["kind"] == "prop" else floras).append(e)
	var expected: Dictionary = {}  # Vector2 -> darkness
	for f in floras:
		var hit := false
		var d := 0.0
		for p in props:
			var off: Vector2 = f["pos"] - p["pos"]
			if ForestProp.is_in_front(p["def"], off, 16.0):
				hit = true
				d = maxf(d, ForestProp.shadow_darkness(p["def"], off))
		if hit:
			expected[f["pos"]] = d
	assert_int(expected.size()).is_greater(0)

	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(forest), world_seed, bytes)
	var raised := _raised_decor(wm.entity_layer)
	assert_int(raised.size()).is_equal(expected.size())
	for sprite in raised:
		assert_bool(expected.has(sprite.global_position)).is_true()
		var d: float = expected[sprite.global_position]
		assert_float(sprite.modulate.r).is_equal_approx(1.0 - d, 0.001)
	for sprite in _decor_sprites(chunk):
		assert_that(sprite.modulate).is_equal(Color.WHITE)
	chunk.free()
	wm.remove_from_group("world_manager")


func test_chunk_free_clears_raised_flora() -> void:
	var wm := _wm_with_layer()
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(_make_forest(false)), 4646, _room_bytes())
	assert_int(_raised_decor(wm.entity_layer).size()).is_greater(0)
	chunk.free()
	await await_idle_frame()
	assert_int(_raised_decor(wm.entity_layer).size()).is_equal(0)
	wm.remove_from_group("world_manager")
