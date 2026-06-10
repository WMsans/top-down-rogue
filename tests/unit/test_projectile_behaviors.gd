extends GdUnitTestSuite

func test_base_behavior_hooks_are_noops() -> void:
	var b: ProjectileBehavior = ProjectileBehavior.new()
	var proj: Projectile = auto_free(Projectile.new())
	assert_that(b.on_enemy_hit(proj, null)).is_false()
	assert_that(b.on_terrain_hit(proj)).is_false()
	b.on_spawn(proj)
	b.on_process(proj, 0.1)
	b.on_enemy_projectile_overlap(proj, null)
