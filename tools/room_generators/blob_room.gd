@tool
class_name BlobRoomGenerator

# Generates an irregular blob carved into the biome's background material,
# optional pool material patch, and scattered enemy markers.
#
# Args:
#   size: int — square size (16/32/64/128)
#   pool_material: int — material id for floor pool, or -1 for none
#   enemy_count: int — number of enemy markers to scatter
#   gen_seed: int — RNG seed
#
# Returns: Image (RGBA8) ready to save as PNG
static func generate(size: int, pool_material: int, enemy_count: int, gen_seed: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))  # transparent (skip mask = 0)

	var rng := RandomNumberGenerator.new()
	rng.seed = gen_seed

	var center := Vector2(size / 2.0, size / 2.0)
	var base_radius := size * 0.40

	# Carve blob: distance + perlin-ish bumpiness via sine sum
	for y in range(size):
		for x in range(size):
			var dx := x - center.x
			var dy := y - center.y
			var dist := sqrt(dx * dx + dy * dy)
			var theta := atan2(dy, dx)
			var bump := sin(theta * 3.0 + rng.randf_range(0.0, 0.3)) * 4.0
			bump += sin(theta * 5.0 + rng.randf_range(0.0, 0.3)) * 2.0
			var r := base_radius + bump
			if dist < r:
				# AIR (R=0), mask = 255 → write
				img.set_pixel(x, y, Color8(0, 0, 0, 255))

	# Pool patch in lower half
	if pool_material >= 0:
		var pool_center := Vector2(size / 2.0, size * 0.65)
		var pool_radius := size * 0.18
		for y in range(size):
			for x in range(size):
				var dx2 := x - pool_center.x
				var dy2 := y - pool_center.y
				var d2 := sqrt(dx2 * dx2 + dy2 * dy2)
				if d2 < pool_radius:
					img.set_pixel(x, y, Color8(pool_material, 0, 0, 255))

	# Scatter enemy markers (G=1) on AIR pixels
	var placed := 0
	var attempts := 0
	while placed < enemy_count and attempts < enemy_count * 20:
		attempts += 1
		var px := rng.randi_range(2, size - 3)
		var py := rng.randi_range(2, size - 3)
		var current := img.get_pixel(px, py)
		# Only place on AIR (R=0) pixels with mask=255
		if int(current.a8) == 255 and int(current.r8) == 0:
			img.set_pixel(px, py, Color8(0, 1, 0, 255))
			placed += 1

	return img
