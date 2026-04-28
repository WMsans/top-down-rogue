@tool
class_name CorridorGenerator

# Long thin corridor. Length axis = X. Width is fixed; length defines size_class via caller.
# has_chest=true places a chest marker (G=3) at the far end.
static func generate(length: int, width: int, has_chest: bool, gen_seed: int) -> Image:
	# Output square size = max(length, width); pad with transparent
	var size: int = max(length, width)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var rng := RandomNumberGenerator.new()
	rng.seed = gen_seed

	var y_start: int = (size - width) / 2
	var x_start: int = (size - length) / 2

	for y in range(y_start, y_start + width):
		for x in range(x_start, x_start + length):
			img.set_pixel(x, y, Color8(0, 0, 0, 255))

	# End-caps with native border on both ends
	for y in range(y_start - 1, y_start + width + 1):
		if y >= 0 and y < size:
			if x_start - 1 >= 0:
				img.set_pixel(x_start - 1, y, Color8(255, 0, 0, 255))
			if x_start + length < size:
				img.set_pixel(x_start + length, y, Color8(255, 0, 0, 255))

	if has_chest:
		var cy := y_start + width / 2
		var cx := x_start + length - 2
		img.set_pixel(cx, cy, Color8(0, 3, 0, 255))

	# Sparse enemies along corridor
	var placed := 0
	var enemy_count := max(1, length / 24)
	var attempts := 0
	while placed < enemy_count and attempts < 40:
		attempts += 1
		var px := rng.randi_range(x_start + 2, x_start + length - 3)
		var py := y_start + width / 2
		var current := img.get_pixel(px, py)
		if int(current.a8) == 255 and int(current.r8) == 0 and int(current.g8) == 0:
			img.set_pixel(px, py, Color8(0, 1, 0, 255))
			placed += 1

	return img
