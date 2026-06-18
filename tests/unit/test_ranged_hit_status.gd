extends GdUnitTestSuite

func test_spawn_sets_hit_status_on_projectile() -> void:
	var w := RangedWeapon.new()
	w.hit_status = "freeze"
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)  # user.get_parent() == this suite (no world_manager in test)
	w._spawn_projectile(user, Vector2.RIGHT)
	await get_tree().process_frame
	var found: Projectile = null
	for c in get_children():
		if c is Projectile:
			found = c
	assert_object(found).is_not_null()
	if found != null:
		assert_str(found.hit_status).is_equal("freeze")
		found.queue_free()

func test_default_hit_status_blank() -> void:
	var w := RangedWeapon.new()
	assert_str(w.hit_status).is_equal("")
