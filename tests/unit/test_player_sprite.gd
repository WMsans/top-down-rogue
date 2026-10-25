extends GdUnitTestSuite


func test_sprite_frames_have_all_animations() -> void:
	var frames: SpriteFrames = load("res://textures/Player/player_sprite_frames.tres")
	for a in ["idle", "run"]:
		for d in ["front_left", "back_left", "front_right", "back_right"]:
			assert_bool(frames.has_animation(StringName("%s_%s" % [a, d]))).is_true()
	assert_int(frames.get_frame_count(&"idle_back_right")).is_equal(20)
	assert_int(frames.get_frame_count(&"run_front_left")).is_equal(18)
	assert_int(frames.get_frame_count(&"run_back_left")).is_equal(16)
	assert_float(frames.get_animation_speed(&"run_front_right")).is_equal(15.0)


func test_anim_name() -> void:
	assert_str(PlayerController.anim_name(Vector2.DOWN, false, false)).is_equal("idle_front_right")
	assert_str(PlayerController.anim_name(Vector2.UP, true, true)).is_equal("run_back_left")
	assert_str(PlayerController.anim_name(Vector2(-1, 0), true, false)).is_equal("idle_front_left")


func test_scene_uses_sprite() -> void:
	var p: Node = auto_free(load("res://scenes/player.tscn").instantiate())
	assert_object(p.get_node_or_null("ColorRect")).is_null()
	var s: AnimatedSprite2D = p.get_node("Sprite")
	assert_vector(s.position).is_equal(Vector2(0, 6))
	assert_vector(s.offset).is_equal(Vector2(0, -15))


func test_inventory_finds_sprite() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	var sprite := AnimatedSprite2D.new()
	sprite.name = "Sprite"
	parent.add_child(sprite)
	var inv := PlayerInventory.new()
	parent.add_child(inv)
	inv._ready()
	assert_object(inv._sprite).is_same(sprite)
