extends GdUnitTestSuite

func test_base_behavior_hooks_are_noops() -> void:
	var b: ProjectileBehavior = ProjectileBehavior.new()
	var proj: Projectile = auto_free(Projectile.new())
	assert_that(b.on_enemy_hit(proj, null)).is_false()
	assert_that(b.on_terrain_hit(proj)).is_false()
	b.on_spawn(proj)
	b.on_process(proj, 0.1)
	b.on_enemy_projectile_overlap(proj, null)


# A test behavior that records calls and votes keep-alive on demand.
class _RecordingBehavior extends ProjectileBehavior:
	var keep_enemy: bool = false
	var keep_terrain: bool = false
	var spawned: int = 0
	var processed: int = 0
	var enemy_hits: int = 0
	var overlaps: Array = []
	func on_spawn(_proj) -> void: spawned += 1
	func on_process(_proj, _delta: float) -> void: processed += 1
	func on_enemy_hit(_proj, _target) -> bool:
		enemy_hits += 1
		return keep_enemy
	func on_terrain_hit(_proj) -> bool:
		return keep_terrain
	func on_enemy_projectile_overlap(_proj, enemy_proj) -> void:
		overlaps.append(enemy_proj)

func test_on_spawn_called_on_ready() -> void:
	var b := _RecordingBehavior.new()
	var p: Projectile = auto_free(Projectile.new())
	p.behaviors = [b]
	add_child(p)
	assert_that(b.spawned).is_equal(1)

func test_on_process_called_each_frame() -> void:
	var b := _RecordingBehavior.new()
	var p: Projectile = auto_free(Projectile.new())
	p.behaviors = [b]
	p.lifetime = 10.0
	p._process(0.1)
	assert_that(b.processed).is_equal(1)

func test_behavior_keep_alive_on_enemy_hit() -> void:
	var b := _RecordingBehavior.new()
	b.keep_enemy = true
	var p: Projectile = auto_free(Projectile.new())
	p.behaviors = [b]
	p.is_enemy_projectile = false
	p.damage = 5.0
	var target: Enemy = auto_free(Enemy.new())
	add_child(target)
	p._handle_hit(target)
	assert_that(b.enemy_hits).is_equal(1)
	assert_that(is_instance_valid(p)).is_true()

func test_no_behavior_still_dies_on_enemy_hit() -> void:
	var p: Projectile = auto_free(Projectile.new())
	p.is_enemy_projectile = false
	p.damage = 5.0
	var target: Enemy = auto_free(Enemy.new())
	add_child(target)
	p._handle_hit(target)
	await get_tree().process_frame
	assert_that(is_instance_valid(p)).is_false()

func test_is_solid_at_uses_injected_oracle() -> void:
	var p: Projectile = auto_free(Projectile.new())
	p.solidity_oracle = func(pos: Vector2) -> bool: return pos.x > 0.0
	assert_that(p.is_solid_at(Vector2(5, 0))).is_true()
	assert_that(p.is_solid_at(Vector2(-5, 0))).is_false()
