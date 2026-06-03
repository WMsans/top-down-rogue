extends GdUnitTestSuite

const _CHUNK_BYTES := FloorChunk.CHUNK_SIZE * FloorChunk.CHUNK_SIZE


func _dummy_texture() -> Texture2D:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _make_biome(emits_light: bool) -> BiomeDef:
	var biome := BiomeDef.new()
	biome.floor_texture = _dummy_texture()
	biome.decor_chance = 1.0
	var def := DecorDef.new()
	def.texture = _dummy_texture()
	def.emits_light = emits_light
	def.weight = 1.0
	def.light_color = Color(1.0, 0.5, 0.2)
	def.light_energy = 1.0
	def.light_radius = 56.0
	var defs: Array[DecorDef] = [def]
	biome.decor_defs = defs
	return biome


func _air_bytes() -> PackedByteArray:
	# Zero-filled == MaterialRegistry.MAT_AIR (id 0), so every cell is placeable.
	var bytes := PackedByteArray()
	bytes.resize(_CHUNK_BYTES)
	return bytes


func _count_point_lights(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is PointLight2D:
			count += 1
		count += _count_point_lights(child)
	return count


func _has_lit_pixel(img: Image) -> bool:
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c.r + c.g + c.b > 0.0:
				return true
	return false


func test_dense_decor_bakes_single_light() -> void:
	var chunk := FloorChunk.new()
	add_child(chunk)
	auto_free(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(true), 12345, _air_bytes())

	assert_int(_count_point_lights(chunk)).is_equal(1)
	var light := chunk.get_node_or_null("DecorLights") as PointLight2D
	assert_object(light).is_not_null()
	assert_bool(_has_lit_pixel(light.texture.get_image())).is_true()


func test_non_emitting_decor_has_no_light() -> void:
	var chunk := FloorChunk.new()
	add_child(chunk)
	auto_free(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(false), 12345, _air_bytes())

	assert_object(chunk.get_node_or_null("DecorLights")).is_null()
	assert_int(_count_point_lights(chunk)).is_equal(0)


func test_same_seed_bakes_identical_texture() -> void:
	var biome := _make_biome(true)
	var bytes := _air_bytes()

	var chunk_a := FloorChunk.new()
	add_child(chunk_a)
	auto_free(chunk_a)
	chunk_a.populate(Vector2i(3, 7), biome, 999, bytes)

	var chunk_b := FloorChunk.new()
	add_child(chunk_b)
	auto_free(chunk_b)
	chunk_b.populate(Vector2i(3, 7), biome, 999, bytes)

	var img_a := (chunk_a.get_node("DecorLights") as PointLight2D).texture.get_image()
	var img_b := (chunk_b.get_node("DecorLights") as PointLight2D).texture.get_image()
	assert_bool(img_a.get_data() == img_b.get_data()).is_true()
