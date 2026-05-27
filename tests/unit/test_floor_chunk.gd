extends GdUnitTestSuite

const _FloorChunk = preload("res://src/terrain/floor_chunk.gd")
const _BiomeDef = preload("res://src/core/biome_def.gd")

const CHUNK_SIZE := 256

func _make_texture(width: int, height: int) -> ImageTexture:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)

func _make_biome(decor_chance: float, decor_count: int) -> _BiomeDef:
	var b := _BiomeDef.new()
	b.floor_texture = _make_texture(16, 16)
	b.decor_chance = decor_chance
	var decors: Array[Texture2D] = []
	for i in range(decor_count):
		decors.append(_make_texture(16, 16))
	b.decor_textures = decors
	return b

func _floor_sprite(chunk: _FloorChunk) -> Sprite2D:
	return chunk.get_node_or_null("FloorSprite") as Sprite2D

func test_populate_creates_floor_sprite_at_chunk_size() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(0.0, 0), 12345)

	var sprite := _floor_sprite(chunk)
	assert_that(sprite).is_not_null()
	assert_that(sprite.texture).is_not_null()
	assert_that(sprite.region_enabled).is_true()
	assert_that(sprite.region_rect.size).is_equal(Vector2(CHUNK_SIZE, CHUNK_SIZE))

func test_populate_skips_when_floor_texture_missing() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	var biome := _BiomeDef.new()  # no floor_texture
	chunk.populate(Vector2i(0, 0), biome, 12345)

	assert_that(_floor_sprite(chunk)).is_null()

func _decor_sprites(chunk: _FloorChunk) -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	for child in chunk.get_children():
		if child.name.begins_with("Decor"):
			out.append(child as Sprite2D)
	return out

func test_decor_chance_zero_creates_no_decor() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(0.0, 3), 42)
	assert_that(_decor_sprites(chunk).size()).is_equal(0)

func test_decor_chance_one_creates_full_grid() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(1.0, 3), 42)
	# 256x256 chunk / 16px tiles = 16x16 = 256 cells
	assert_that(_decor_sprites(chunk).size()).is_equal(256)

func test_decor_placement_is_deterministic_for_same_seed_and_coord() -> void:
	var biome := _make_biome(0.5, 3)
	var a := _FloorChunk.new()
	var b := _FloorChunk.new()
	add_child(a)
	add_child(b)
	a.populate(Vector2i(3, -2), biome, 999)
	b.populate(Vector2i(3, -2), biome, 999)

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
	a.populate(Vector2i(0, 0), biome, 7)
	b.populate(Vector2i(1, 0), biome, 7)

	var ad := _decor_sprites(a)
	var bd := _decor_sprites(b)
	# Same seed + different coords should very rarely produce identical placements.
	var identical := ad.size() == bd.size()
	if identical:
		for i in range(ad.size()):
			if ad[i].position != bd[i].position:
				identical = false
				break
	assert_that(identical).is_false()

func test_empty_decor_textures_skips_decor_pass() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(1.0, 0), 42)
	assert_that(_decor_sprites(chunk).size()).is_equal(0)
