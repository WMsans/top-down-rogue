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


func test_split_spawns_shards_on_enemy_hit_then_dies() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var p: Projectile = Projectile.new()  # NOT auto_free: it should queue_free itself
	p.is_enemy_projectile = false
	p.damage = 10.0
	var b := SplitBehavior.new()
	b.shard_count = 4
	p.behaviors = [b]
	parent.add_child(p)
	var target: Enemy = auto_free(Enemy.new())
	p._handle_hit(target)
	await get_tree().process_frame  # let queue_free settle
	# 4 shards added under the same parent; original removed.
	var shards := 0
	for c in parent.get_children():
		if c is Projectile:
			shards += 1
	assert_that(shards).is_equal(4)

func test_split_shards_have_no_behaviors_and_reduced_damage() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var p: Projectile = Projectile.new()
	p.is_enemy_projectile = false
	p.damage = 10.0
	var b := SplitBehavior.new()
	b.shard_count = 3
	b.damage_factor = 0.5
	p.behaviors = [b]
	parent.add_child(p)
	p._handle_hit(auto_free(Enemy.new()))
	await get_tree().process_frame
	for c in parent.get_children():
		if c is Projectile:
			assert_that(c.behaviors.is_empty()).is_true()
			assert_that(c.damage).is_equal(5.0)


func test_bounce_flips_blocked_x_axis() -> void:
	var p: Projectile = auto_free(Projectile.new())
	p.global_position = Vector2.ZERO
	p.direction = Vector2.RIGHT
	# Wall ahead on +X only.
	p.solidity_oracle = func(pos: Vector2) -> bool: return pos.x > 0.0
	var b := BounceBehavior.new()
	b.max_bounces = 3
	var keep := b.on_terrain_hit(p)
	assert_that(keep).is_true()
	assert_that(p.direction.x).is_less(0.0)
	assert_that(b.max_bounces).is_equal(2)

func test_bounce_dies_when_exhausted() -> void:
	var p: Projectile = auto_free(Projectile.new())
	p.direction = Vector2.RIGHT
	p.solidity_oracle = func(_pos: Vector2) -> bool: return true
	var b := BounceBehavior.new()
	b.max_bounces = 0
	assert_that(b.on_terrain_hit(p)).is_false()


func test_penetrate_passes_through_enemies() -> void:
	var p: Projectile = auto_free(Projectile.new())
	p.is_enemy_projectile = false
	p.damage = 5.0
	p.behaviors = [PenetrateBehavior.new()]
	p._handle_hit(auto_free(Enemy.new()))
	assert_that(is_instance_valid(p)).is_true()
	p._handle_hit(auto_free(Enemy.new()))
	assert_that(is_instance_valid(p)).is_true()

func test_penetrate_dies_on_wall() -> void:
	var b := PenetrateBehavior.new()
	var p: Projectile = auto_free(Projectile.new())
	assert_that(b.on_terrain_hit(p)).is_false()
