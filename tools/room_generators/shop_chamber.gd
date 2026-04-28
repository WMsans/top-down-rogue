@tool
class_name ShopChamberGenerator

# Small room with central shop marker (G=4).
static func generate(size: int, gen_seed: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var inset := 2
	for y in range(inset, size - inset):
		for x in range(inset, size - inset):
			img.set_pixel(x, y, Color8(0, 0, 0, 255))

	# Border of biome native
	for y in range(inset - 1, size - inset + 1):
		for x in range(inset - 1, size - inset + 1):
			var on_edge := (
				x == inset - 1 or x == size - inset
				or y == inset - 1 or y == size - inset
			)
			if on_edge:
				img.set_pixel(x, y, Color8(255, 0, 0, 255))

	var cx := size / 2
	var cy := size / 2
	img.set_pixel(cx, cy, Color8(0, 4, 0, 255))

	return img
