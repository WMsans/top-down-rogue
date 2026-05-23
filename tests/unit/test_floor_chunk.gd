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
