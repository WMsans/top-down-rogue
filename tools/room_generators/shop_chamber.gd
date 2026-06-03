@tool
class_name ShopChamberGenerator

# Sealed shop room: thick wood wall ring (R=MAT_WOOD), AIR interior,
# a single shop marker (G=4) at the center. Biome-independent (wood, not native).
const MAT_WOOD := 1
const WALL_THICKNESS := 6

static func generate(size: int, _gen_seed: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Interior: AIR (R=0), mask=255
	for y in range(size):
		for x in range(size):
			img.set_pixel(x, y, Color8(0, 0, 0, 255))

	# Sealed wood wall ring, WALL_THICKNESS cells thick on every edge
	for y in range(size):
		for x in range(size):
			var on_wall := (
				x < WALL_THICKNESS or x >= size - WALL_THICKNESS
				or y < WALL_THICKNESS or y >= size - WALL_THICKNESS
			)
			if on_wall:
				img.set_pixel(x, y, Color8(MAT_WOOD, 0, 0, 255))

	# Shop marker (G=4) at center, on an AIR cell (R=0)
	img.set_pixel(size / 2, size / 2, Color8(0, 4, 0, 255))

	return img
