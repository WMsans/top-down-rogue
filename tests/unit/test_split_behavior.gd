extends GdUnitTestSuite

# Split shards have no source_weapon, so they take the projectile's legacy hit
# path. They must still carry the hit status of the projectile they came from.

func test_split_shards_inherit_the_projectile_hit_status() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var p: Projectile = Projectile.new()
	p.hit_status = "on_fire"
	p.behaviors = [SplitBehavior.new()]
	parent.add_child(p)
	var sb: SplitBehavior = p.behaviors[0]
	sb.on_enemy_hit(p, null)
	var shards := 0
	for c in parent.get_children():
		if c is Projectile and c != p:
			shards += 1
			assert_str((c as Projectile).hit_status).is_equal("on_fire")
	assert_int(shards).is_equal(4)


func test_split_shards_keep_their_own_hit_status() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var p: Projectile = Projectile.new()
	p.hit_status = "on_fire"
	var sb := SplitBehavior.new()
	sb.shard_hit_status = "chilly"
	p.behaviors = [sb]
	parent.add_child(p)
	sb.on_enemy_hit(p, null)
	for c in parent.get_children():
		if c is Projectile and c != p:
			assert_str((c as Projectile).hit_status).is_equal("chilly")
