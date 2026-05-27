@tool
class_name SecretVaultGenerator

# Small chamber with secret_loot marker. Outer ring is left transparent —
# secret_ring stage in the shader adds the wall after pixel_scene stamps.
static func generate(size: int, gen_seed: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var center := Vector2(size / 2.0, size / 2.0)
	var radius := size * 0.40

	for y in range(size):
		for x in range(size):
			var dx := x - center.x
			var dy := y - center.y
			var dist := sqrt(dx * dx + dy * dy)
			if dist < radius:
				img.set_pixel(x, y, Color8(0, 0, 0, 255))

	# SECRET_LOOT marker (G=5) at center
	img.set_pixel(int(center.x), int(center.y), Color8(0, 5, 0, 255))

	return img
