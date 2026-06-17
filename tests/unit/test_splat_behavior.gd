extends GdUnitTestSuite

func _proj() -> Projectile:
	var p: Projectile = auto_free(Projectile.new())
	p.global_position = Vector2(7, 3)
	return p

func test_splats_lava_on_terrain_hit() -> void:
	var calls: Array = []
	var b := SplatBehavior.new()
	b.material = "lava"
	b.radius = 6.0
	b.place_sink = func(mat, pos, rad, _dens): calls.append([mat, pos, rad])
	var keep := b.on_terrain_hit(_proj())
	assert_bool(keep).is_false()
	assert_int(calls.size()).is_equal(1)
	assert_str(calls[0][0]).is_equal("lava")
	assert_vector(calls[0][1]).is_equal(Vector2(7, 3))

func test_splats_on_enemy_hit() -> void:
	var calls: Array = []
	var b := SplatBehavior.new()
	b.material = "gas"
	b.place_sink = func(mat, _pos, _rad, _dens): calls.append(mat)
	var keep := b.on_enemy_hit(_proj(), null)
	assert_bool(keep).is_false()
	assert_int(calls.size()).is_equal(1)
	assert_str(calls[0]).is_equal("gas")

func test_splats_on_expire() -> void:
	var calls: Array = []
	var b := SplatBehavior.new()
	b.place_sink = func(_m, _p, _r, _d): calls.append(1)
	b.on_expire(_proj())
	assert_int(calls.size()).is_equal(1)

func test_done_guard_prevents_double_splat() -> void:
	var calls: Array = []
	var b := SplatBehavior.new()
	b.place_sink = func(_m, _p, _r, _d): calls.append(1)
	var p := _proj()
	b.on_enemy_hit(p, null)
	b.on_expire(p)  # must NOT splat again
	assert_int(calls.size()).is_equal(1)
