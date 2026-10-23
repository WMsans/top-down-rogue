@tool
class_name ShopChamberGenerator

# Open shop clearing: an irregular rounded AIR pocket with no walls. Pixels
# outside it stay transparent (A=0) so the native cave flows right up to the
# stall. A single shop marker (G=4) sits at the center.
const RADIUS_X := 0.48          # fraction of size; leaves a thin rim of native cave
const RADIUS_Y := 0.44
const SQUARENESS := 4.0         # superellipse exponent: 2 = ellipse, higher = boxier
const BUMP := 3.0               # px of wobble on the edge so it reads as cave

static func generate(size: int, gen_seed: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))  # transparent (skip mask = 0)

	var rng := RandomNumberGenerator.new()
	rng.seed = gen_seed
	var phase_a := rng.randf_range(0.0, TAU)
	var phase_b := rng.randf_range(0.0, TAU)

	var center := Vector2(size / 2.0, size / 2.0)
	var rx := size * RADIUS_X
	var ry := size * RADIUS_Y

	for y in range(size):
		for x in range(size):
			var dx := x - center.x
			var dy := y - center.y
			var theta := atan2(dy, dx)
			var bump := sin(theta * 5.0 + phase_a) * BUMP * 0.6 + sin(theta * 9.0 + phase_b) * BUMP * 0.4
			var nx := absf(dx) / (rx + bump)
			var ny := absf(dy) / (ry + bump)
			if pow(nx, SQUARENESS) + pow(ny, SQUARENESS) < 1.0:
				img.set_pixel(x, y, Color8(0, 0, 0, 255))

	# Shop marker (G=4) at center, on an AIR cell (R=0)
	img.set_pixel(size / 2, size / 2, Color8(0, 4, 0, 255))

	# Lantern marker (G=8) beside the counter, left of the merchant
	img.set_pixel(size / 2 - 34, size / 2 - 24, Color8(0, 8, 0, 255))

	return img
