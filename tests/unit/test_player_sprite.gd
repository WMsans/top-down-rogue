extends GdUnitTestSuite


func test_sprite_frames_have_all_animations() -> void:
	var frames: SpriteFrames = load("res://textures/Player/player_sprite_frames.tres")
	for a in ["idle", "run"]:
		for d in ["front_left", "back_left", "front_right", "back_right"]:
			assert_bool(frames.has_animation(StringName("%s_%s" % [a, d]))).is_true()
	assert_int(frames.get_frame_count(&"idle_back_left")).is_equal(20)
	assert_int(frames.get_frame_count(&"run_front_right")).is_equal(18)
	assert_int(frames.get_frame_count(&"run_back_right")).is_equal(16)
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


func test_lean_target_right_is_mostly_skew() -> void:
	var t := PlayerController.lean_target(Vector2.RIGHT, false)
	assert_float(t.skew).is_greater(0.2)
	assert_float(t.scale.y).is_between(1.0, 1.1)


func test_lean_target_left_skews_negative() -> void:
	assert_float(PlayerController.lean_target(Vector2.LEFT, false).skew).is_less(-0.2)


func test_lean_target_up_is_mostly_stretch() -> void:
	var t := PlayerController.lean_target(Vector2.UP, true)
	assert_float(t.scale.y).is_greater(1.2)
	assert_float(t.scale.x).is_less(1.0)
	assert_float(t.skew).is_between(-0.15, -0.01)  # small, toward facing (left)


func test_lean_target_down_facing_right_skews_right() -> void:
	var t := PlayerController.lean_target(Vector2.DOWN, false)
	assert_float(t.scale.y).is_greater(1.2)
	assert_float(t.skew).is_between(0.01, 0.15)


func test_lean_target_zero_is_rest() -> void:
	var t := PlayerController.lean_target(Vector2.ZERO, false)
	assert_float(t.skew).is_equal(0.0)
	assert_vector(t.scale).is_equal(Vector2.ONE)


func test_squash_kills_lean() -> void:
	var controller: PlayerController = auto_free(PlayerController.new())
	controller._sprite = auto_free(AnimatedSprite2D.new())
	controller.play_attack_lean(Vector2.RIGHT)
	controller._lean_tween.custom_step(0.03)  # mid-lean
	controller._play_squash()
	assert_bool(controller._lean_tween == null or not controller._lean_tween.is_valid()).is_true()
	controller._squash_tween.custom_step(1.0)
	assert_float(controller._sprite.skew).is_equal(0.0)
	assert_vector(controller._sprite.scale).is_equal(Vector2.ONE)



# Wired by hand like test_player_controller.gd: the controller's _ready needs the game scene.
func _wired_controller() -> PlayerController:
	var c: PlayerController = auto_free(PlayerController.new())
	c._sprite = AnimatedSprite2D.new()
	c._sprite.sprite_frames = load("res://textures/Player/player_sprite_frames.tres")
	c.add_child(c._sprite)
	var inv := PlayerInventory.new()
	inv.name = "PlayerInventory"
	c.add_child(inv)
	var status := StatusComponent.new()
	status.name = "StatusComponent"
	c.add_child(status)
	return c


func test_moving_player_plays_run() -> void:
	var c := _wired_controller()
	c._update_animation(Vector2.RIGHT)
	assert_str(c._sprite.animation).is_equal("run_front_right")


func test_stunned_player_holding_direction_plays_idle() -> void:
	var c := _wired_controller()
	(c.get_node("StatusComponent") as StatusComponent).add_timed_status("stun", 5.0)
	c._update_animation(Vector2.RIGHT)
	assert_str(c._sprite.animation).starts_with("idle_")


func test_dead_player_plays_idle() -> void:
	var c := _wired_controller()
	(c.get_node("PlayerInventory") as PlayerInventory)._is_dead = true
	c._update_animation(Vector2.RIGHT)
	assert_str(c._sprite.animation).starts_with("idle_")
