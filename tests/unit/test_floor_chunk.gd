extends GdUnitTestSuite

const _FloorChunk = preload("res://src/terrain/floor_chunk.gd")
const _BiomeDef = preload("res://src/core/biome_def.gd")
const _DecorDef = preload("res://src/core/decor_def.gd")

const CHUNK_SIZE := 256

func _make_texture(width: int, height: int) -> ImageTexture:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)

func _make_decor(emits_light: bool) -> _DecorDef:
	var d := _DecorDef.new()
	d.texture = _make_texture(16, 16)
	d.emits_light = emits_light
	return d

func _make_biome(decor_chance: float, decor_count: int, emits_light: bool = true) -> _BiomeDef:
	var b := _BiomeDef.new()
	b.floor_texture = _make_texture(16, 16)
	b.decor_chance = decor_chance
	var defs: Array[DecorDef] = []
	for i in range(decor_count):
		defs.append(_make_decor(emits_light))
	b.decor_defs = defs
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

func _floor_sprite(chunk: _FloorChunk) -> Sprite2D:
	return chunk.get_node_or_null("FloorSprite") as Sprite2D

func _decor_sprites(chunk: _FloorChunk) -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	for child in chunk.get_children():
		if child.name.begins_with("Decor"):
			out.append(child as Sprite2D)
	return out

func test_populate_creates_floor_sprite_at_chunk_size() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(0.0, 0), 12345, _all_air_bytes())
	var sprite := _floor_sprite(chunk)
	assert_that(sprite).is_not_null()
	assert_that(sprite.region_enabled).is_true()
	assert_that(sprite.region_rect.size).is_equal(Vector2(CHUNK_SIZE, CHUNK_SIZE))

func test_populate_skips_when_floor_texture_missing() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	var biome := _BiomeDef.new()  # no floor_texture
	chunk.populate(Vector2i(0, 0), biome, 12345, _all_air_bytes())
	assert_that(_floor_sprite(chunk)).is_null()

func test_decor_chance_zero_creates_no_decor() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(0.0, 3), 42, _all_air_bytes())
	assert_that(_decor_sprites(chunk).size()).is_equal(0)

func test_decor_chance_one_fills_all_air_cells() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(1.0, 3), 42, _all_air_bytes())
	# 256х256 chunk / 16px tiles = 16x16 = 256 cells, all air -> all decorated.
	assert_that(_decor_sprites(chunk).size()).is_equal(256)

func test_decor_never_placed_on_solid_cells() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(1.0, 3), 42, _all_solid_bytes())
	assert_that(_decor_sprites(chunk).size()).is_equal(0)

func test_empty_material_bytes_skips_decor() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(1.0, 3), 42, PackedByteArray())
	assert_that(_decor_sprites(chunk).size()).is_equal(0)

func test_empty_decor_defs_skips_decor_pass() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(1.0, 0), 42, _all_air_bytes())
	assert_that(_decor_sprites(chunk).size()).is_equal(0)

func test_glowing_decor_bakes_decor_lights_node() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(1.0, 1, true), 42, _all_air_bytes())
	var sprites := _decor_sprites(chunk)
	assert_that(sprites.size()).is_equal(256)
	# With baked lighting, each decor sprite no longer carries a FlickerLight child.
	assert_that(sprites[0].get_node_or_null("Light")).is_null()
	var decor_light := chunk.get_node_or_null("DecorLights") as PointLight2D
	assert_that(decor_light).is_not_null()
	assert_that(decor_light.shadow_enabled).is_false()
	assert_that(decor_light.blend_mode).is_equal(Light2D.BLEND_MODE_ADD)

func test_non_glowing_decor_has_no_decor_lights() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(1.0, 1, false), 42, _all_air_bytes())
	var sprites := _decor_sprites(chunk)
	assert_that(sprites[0].get_node_or_null("Light")).is_null()
	assert_that(chunk.get_node_or_null("DecorLights")).is_null()

func test_decor_placement_is_deterministic_for_same_seed_and_coord() -> void:
	var biome := _make_biome(0.5, 3)
	var a := _FloorChunk.new()
	var b := _FloorChunk.new()
	add_child(a)
	add_child(b)
	a.populate(Vector2i(3, -2), biome, 999, _all_air_bytes())
	b.populate(Vector2i(3, -2), biome, 999, _all_air_bytes())
	var ad := _decor_sprites(a)
	var bd := _decor_sprites(b)
	assert_that(ad.size()).is_equal(bd.size())
	for i in range(ad.size()):
		assert_that(ad[i].position).is_equal(bd[i].position)
		assert_that(ad[i].texture).is_same(bd[i].texture)

func test_decor_placement_differs_across_coords() -> void:
	var biome := _make_biome(0.5, 3)
	var a := _FloorChunk.new()
	var b := _FloorChunk.new()
	add_child(a)
	add_child(b)
	a.populate(Vector2i(0, 0), biome, 7, _all_air_bytes())
	b.populate(Vector2i(1, 0), biome, 7, _all_air_bytes())
	var ad := _decor_sprites(a)
	var bd := _decor_sprites(b)
	var identical := ad.size() == bd.size()
	if identical:
		for i in range(ad.size()):
			if ad[i].position != bd[i].position:
				identical = false
				break
	assert_that(identical).is_false()
