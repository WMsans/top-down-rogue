extends GdUnitTestSuite

const _CHUNK_BYTES := FloorChunk.CHUNK_SIZE * FloorChunk.CHUNK_SIZE
const CHUNK_SIZE := 256


func _dummy_texture() -> Texture2D:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _flora(emits_light: bool) -> DecorDef:
	var def := DecorDef.new()
	def.texture = _dummy_texture()
	def.emits_light = emits_light
	def.weight = 1.0
	def.light_color = Color(1.0, 0.5, 0.2)
	def.light_energy = 1.0
	def.light_radius = 56.0
	return def


# Threshold -1.0 puts every cell inside a forest patch; the glowing root_flora
# clusters around the props the planner places against the disc wall below.
func _make_forest(emits_light: bool) -> ForestDef:
	var forest := ForestDef.new()
	var trees: Array[ForestPropDef] = []
	for role in ["bright", "dark", "odd"]:
		var def := ForestPropDef.new()
		def.role = role
		def.family = "pine"
		def.trunk_radius = 6.0
		def.texture = _dummy_texture()
		trees.append(def)
	forest.tree_defs = trees
	var root_flora: Array[DecorDef] = [_flora(emits_light)]
	forest.root_flora = root_flora
	forest.patch_threshold = -1.0
	return forest


func _make_biome(emits_light: bool) -> BiomeDef:
	var biome := BiomeDef.new()
	biome.floor_texture = _dummy_texture()
	biome.forest = _make_forest(emits_light)
	return biome


# Solid everywhere except an air disc of radius 110 centred at (128, 128): the
# open-room fixture the planner places flora in. An all-air chunk has no walls
# to hug and only receives the single clearing accent flora.
func _room_bytes() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(_CHUNK_BYTES)
	bytes.fill(1)  # any non-air id; MaterialRegistry.MAT_AIR is 0
	for y in range(CHUNK_SIZE):
		for x in range(CHUNK_SIZE):
			if Vector2(x - 128.0, y - 128.0).length() <= 110.0:
				bytes[y * CHUNK_SIZE + x] = MaterialRegistry.MAT_AIR
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


func test_glowing_forest_bakes_single_light() -> void:
	var chunk := FloorChunk.new()
	add_child(chunk)
	auto_free(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(true), 12345, _room_bytes())

	assert_int(_count_point_lights(chunk)).is_equal(1)
	var light := chunk.get_node_or_null("DecorLights") as PointLight2D
	assert_object(light).is_not_null()
	assert_bool(_has_lit_pixel(light.texture.get_image())).is_true()


func test_non_emitting_forest_has_no_light() -> void:
	var chunk := FloorChunk.new()
	add_child(chunk)
	auto_free(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(false), 12345, _room_bytes())

	assert_object(chunk.get_node_or_null("DecorLights")).is_null()
	assert_int(_count_point_lights(chunk)).is_equal(0)


func test_same_seed_bakes_identical_texture() -> void:
	var biome := _make_biome(true)
	var bytes := _room_bytes()

	var chunk_a := FloorChunk.new()
	add_child(chunk_a)
	auto_free(chunk_a)
	chunk_a.populate(Vector2i(3, 7), biome, 997, bytes)

	var chunk_b := FloorChunk.new()
	add_child(chunk_b)
	auto_free(chunk_b)
	chunk_b.populate(Vector2i(3, 7), biome, 997, bytes)

	var img_a := (chunk_a.get_node("DecorLights") as PointLight2D).texture.get_image()
	var img_b := (chunk_b.get_node("DecorLights") as PointLight2D).texture.get_image()
	assert_bool(img_a.get_data() == img_b.get_data()).is_true()
