extends GdUnitTestSuite

const BossDeathSequencer = preload("res://src/core/boss_death_sequencer.gd")


func test_sample_silhouette_rejects_transparent() -> void:
	var tex : Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	tex.fill(Color(0, 0, 0, 0))
	for x in range(6, 10):
		for y in range(6, 10):
			tex.set_pixel(x, y, Color(1, 1, 1, 1))
	var sprite : Sprite2D = auto_free(Sprite2D.new())
	sprite.texture = ImageTexture.create_from_image(tex)
	sprite.global_position = Vector2(100, 100)
	var seq : BossDeathSequencer = auto_free(BossDeathSequencer.new())
	var pts : Array[Vector2] = seq._sample_silhouette_points(sprite, 20)
	assert_int(pts.size()).is_greater_equal(1)
	var sq_min : Vector2 = Vector2(100 - 8 + 6, 100 - 8 + 6)
	var sq_max : Vector2 = Vector2(100 - 8 + 10, 100 - 8 + 10)
	for p in pts:
		assert_bool(p.x >= min(sq_min.x, sq_max.x) and p.x <= max(sq_min.x, sq_max.x)).is_true()
