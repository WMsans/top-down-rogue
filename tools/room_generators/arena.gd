@tool
class_name ArenaGenerator

# Rectangular arena with thin wall border and clustered enemies.
# is_boss=true → single boss marker (G=6) in center, boss flag for caller to set on RoomTemplate.
static func generate(size: int, enemy_count: int, is_boss: bool, gen_seed: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var rng := RandomNumberGenerator.new()
	rng.seed = gen_seed

	var inset := 3
	# Carve interior to AIR (mask=255, R=0)
	for y in range(inset, size - inset):
		for x in range(inset, size - inset):
			img.set_pixel(x, y, Color8(0, 0, 0, 255))

	# Border ring of biome native (R=255 = native sentinel)
	for y in range(inset - 1, size - inset + 1):
		for x in range(inset - 1, size - inset + 1):
			var on_edge := (
				x == inset - 1 or x == size - inset
				or y == inset - 1 or y == size - inset
			)
			if on_edge:
				img.set_pixel(x, y, Color8(255, 0, 0, 255))

	if is_boss:
		var cx := size / 2
		var cy := size / 2
		img.set_pixel(cx, cy, Color8(0, 6, 0, 255))
		return img

	# Cluster enemies near center
	var placed := 0
	var attempts := 0
	while placed < enemy_count and attempts < enemy_count * 20:
		attempts += 1
		var px := rng.randi_range(inset + 2, size - inset - 3)
		var py := rng.randi_range(inset + 2, size - inset - 3)
		var current := img.get_pixel(px, py)
		if int(current.a8) == 255 and int(current.r8) == 0 and int(current.g8) == 0:
			img.set_pixel(px, py, Color8(0, 1, 0, 255))
			placed += 1

	return img
