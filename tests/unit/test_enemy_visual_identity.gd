extends GdUnitTestSuite


func test_soft_dot_texture_is_radial_fill() -> void:
	var tex := EnemyVfxShared.soft_dot_texture(8)
	assert_int(tex.fill).is_equal(GradientTexture2D.FILL_RADIAL)
	assert_int(tex.width).is_equal(8)
	assert_int(tex.height).is_equal(8)


func test_fade_gradient_interpolates_hot_to_fade() -> void:
	var hot := Color(1.0, 0.5, 0.2, 1.0)
	var fade := Color(1.0, 0.5, 0.2, 0.0)
	var tex := EnemyVfxShared.fade_gradient(hot, fade)
	assert_that(tex.gradient.get_color(0)).is_equal(hot)
	assert_that(tex.gradient.get_color(1)).is_equal(fade)


func test_flicker_interval_idle_is_slow() -> void:
	var a: EnemyAnimator = auto_free(EnemyAnimator.new())
	assert_float(a._flicker_interval(false, 0.0)).is_equal(EnemyAnimator.IDLE_INTERVAL)


func test_flicker_interval_moving_fast_is_quick() -> void:
	var a: EnemyAnimator = auto_free(EnemyAnimator.new())
	assert_float(a._flicker_interval(true, 1.0)).is_equal(EnemyAnimator.MIN_MOVING_INTERVAL)


func test_flicker_interval_moving_scales_with_speed() -> void:
	var a: EnemyAnimator = auto_free(EnemyAnimator.new())
	var slow := a._flicker_interval(true, 0.2)
	var fast := a._flicker_interval(true, 0.8)
	assert_float(fast).is_less(slow)


func test_set_hold_breathe_forces_frame_and_blocks_tick() -> void:
	var a: EnemyAnimator = auto_free(EnemyAnimator.new())
	a.texture_normal = PlaceholderTexture2D.new()
	a.texture_breathe = PlaceholderTexture2D.new()
	a.set_hold(EnemyAnimator.Hold.BREATHE)
	assert_bool(a._showing_breathe).is_true()
	a.tick(1.0, true, 1.0)
	assert_bool(a._showing_breathe).is_true()


func test_set_hold_normal_forces_frame() -> void:
	var a: EnemyAnimator = auto_free(EnemyAnimator.new())
	a.texture_normal = PlaceholderTexture2D.new()
	a.texture_breathe = PlaceholderTexture2D.new()
	a.set_hold(EnemyAnimator.Hold.BREATHE)
	a.set_hold(EnemyAnimator.Hold.NORMAL)
	assert_bool(a._showing_breathe).is_false()


func test_tick_toggles_frame_after_interval() -> void:
	var a: EnemyAnimator = auto_free(EnemyAnimator.new())
	a.texture_normal = PlaceholderTexture2D.new()
	a.texture_breathe = PlaceholderTexture2D.new()
	a.tick(EnemyAnimator.IDLE_INTERVAL + 0.01, false, 0.0)
	assert_bool(a._showing_breathe).is_true()


func test_set_textures_assigns_both_fields() -> void:
	var a: EnemyAnimator = auto_free(EnemyAnimator.new())
	var n := PlaceholderTexture2D.new()
	var b := PlaceholderTexture2D.new()
	a.set_textures(n, b)
	assert_object(a.texture_normal).is_equal(n)
	assert_object(a.texture_breathe).is_equal(b)


class MockAnimatorEnemy extends Enemy:
	func _execute_attack() -> void:
		pass


func test_enemy_ticks_animator_when_present() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	e.add_child(sprite)
	var animator := EnemyAnimator.new()
	animator.name = "EnemyAnimator"
	animator.texture_normal = PlaceholderTexture2D.new()
	animator.texture_breathe = PlaceholderTexture2D.new()
	e.add_child(animator)
	add_child(e)
	await get_tree().process_frame
	e.speed = 60.0
	e.velocity = Vector2.ZERO
	e._physics_process(EnemyAnimator.IDLE_INTERVAL + 0.01)
	assert_object(sprite.texture).is_equal(animator.texture_breathe)


func test_enemy_without_animator_does_not_error() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	add_child(e)
	await get_tree().process_frame
	e._physics_process(0.5)


func test_melee_enemy_scene_uses_grunt_sprites() -> void:
	var scene: PackedScene = load("res://scenes/enemies/melee_enemy.tscn")
	var e: Node = auto_free(scene.instantiate())
	var sprite: Sprite2D = e.get_node("Sprite2D")
	var animator: EnemyAnimator = e.get_node("EnemyAnimator")
	assert_str(sprite.texture.resource_path).contains("caves_grunt1")
	assert_str(animator.texture_normal.resource_path).contains("caves_grunt1")
	assert_str(animator.texture_breathe.resource_path).contains("caves_grunt2")


func test_lunge_enemy_scene_uses_brute_sprites() -> void:
	var scene: PackedScene = load("res://scenes/enemies/lunge_enemy.tscn")
	var e: Node = auto_free(scene.instantiate())
	var sprite: Sprite2D = e.get_node("Sprite2D")
	var animator: EnemyAnimator = e.get_node("EnemyAnimator")
	assert_str(sprite.texture.resource_path).contains("caves_brute1")
	assert_str(animator.texture_breathe.resource_path).contains("caves_brute2")


func test_sniper_enemy_scene_uses_mage_sprites() -> void:
	var scene: PackedScene = load("res://scenes/enemies/sniper_enemy.tscn")
	var e: Node = auto_free(scene.instantiate())
	var sprite: Sprite2D = e.get_node("Sprite2D")
	var animator: EnemyAnimator = e.get_node("EnemyAnimator")
	assert_str(sprite.texture.resource_path).contains("caves_mage1")
	assert_str(animator.texture_breathe.resource_path).contains("caves_mage2")


func test_ranged_enemy_defaults_to_archer_sprite() -> void:
	var scene: PackedScene = load("res://scenes/enemies/ranged_enemy.tscn")
	var e: RangedEnemy = auto_free(scene.instantiate())
	add_child(e)
	await get_tree().process_frame
	var sprite: Sprite2D = e.get_node("Sprite2D")
	assert_str(sprite.texture.resource_path).contains("caves_archer1")


func test_ranged_enemy_with_aimed_burst_uses_archer_sprite() -> void:
	var scene: PackedScene = load("res://scenes/enemies/ranged_enemy.tscn")
	var e: RangedEnemy = auto_free(scene.instantiate())
	e.weapon_resource = AimedBurstWeapon.new()
	add_child(e)
	await get_tree().process_frame
	var sprite: Sprite2D = e.get_node("Sprite2D")
	assert_str(sprite.texture.resource_path).contains("caves_archer1")


func test_ranged_enemy_with_splitshot_uses_lobber_sprite() -> void:
	var scene: PackedScene = load("res://scenes/enemies/ranged_enemy.tscn")
	var e: RangedEnemy = auto_free(scene.instantiate())
	e.weapon_resource = SplitShotWeapon.new()
	add_child(e)
	await get_tree().process_frame
	var sprite: Sprite2D = e.get_node("Sprite2D")
	var animator: EnemyAnimator = e.get_node("EnemyAnimator")
	assert_str(sprite.texture.resource_path).contains("caves_lobber1")
	assert_str(animator.texture_breathe.resource_path).contains("caves_lobber2")


func test_ranged_enemy_with_fan_uses_lobber_sprite() -> void:
	var scene: PackedScene = load("res://scenes/enemies/ranged_enemy.tscn")
	var e: RangedEnemy = auto_free(scene.instantiate())
	e.weapon_resource = FanWeapon.new()
	add_child(e)
	await get_tree().process_frame
	var sprite: Sprite2D = e.get_node("Sprite2D")
	assert_str(sprite.texture.resource_path).contains("caves_lobber1")


func test_enemy_has_hurt_vfx_child() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	add_child(e)
	await get_tree().process_frame
	assert_object(e._hurt_vfx).is_not_null()
	assert_bool(e._hurt_vfx is HurtSparkVfx).is_true()


func test_on_hit_bursts_hurt_vfx() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	e.health = 100
	add_child(e)
	await get_tree().process_frame
	e.hit(5)
	var particles: GPUParticles2D = e._hurt_vfx.get_node("Particles")
	assert_bool(particles.emitting).is_true()


func test_base_enemy_does_not_use_footstep_vfx() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	assert_bool(e._uses_footstep_vfx()).is_false()


func test_melee_enemy_uses_footstep_vfx() -> void:
	var e: MeleeEnemy = auto_free(MeleeEnemy.new())
	assert_bool(e._uses_footstep_vfx()).is_true()


func test_lunge_enemy_does_not_use_footstep_vfx() -> void:
	var e: LungeEnemy = auto_free(LungeEnemy.new())
	assert_bool(e._uses_footstep_vfx()).is_false()


func test_chasing_melee_enemy_puffs_footstep_dust() -> void:
	var scene: PackedScene = load("res://scenes/enemies/melee_enemy.tscn")
	var e: MeleeEnemy = auto_free(scene.instantiate())
	add_child(e)
	await get_tree().process_frame
	e._state = Enemy.State.CHASE
	e.velocity = Vector2(60, 0)
	e._physics_process(FootstepDustVfx.FOOTSTEP_INTERVAL + 0.01)
	var particles: GPUParticles2D = e._footstep_vfx.get_node("Particles")
	assert_bool(particles.emitting).is_true()


func test_base_enemy_uses_windup_telegraph_vfx() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	assert_bool(e._uses_windup_telegraph_vfx()).is_true()


func test_lunge_enemy_does_not_use_windup_telegraph_vfx() -> void:
	var e: LungeEnemy = auto_free(LungeEnemy.new())
	assert_bool(e._uses_windup_telegraph_vfx()).is_false()


func test_windup_plays_telegraph_vfx_for_melee() -> void:
	var scene: PackedScene = load("res://scenes/enemies/melee_enemy.tscn")
	var e: MeleeEnemy = auto_free(scene.instantiate())
	add_child(e)
	await get_tree().process_frame
	e._change_state(Enemy.State.WINDUP)
	var particles: GPUParticles2D = e._windup_vfx.get_node("Particles")
	assert_bool(particles.emitting).is_true()


func test_windup_does_not_play_telegraph_vfx_for_lunge() -> void:
	var scene: PackedScene = load("res://scenes/enemies/lunge_enemy.tscn")
	var e: LungeEnemy = auto_free(scene.instantiate())
	add_child(e)
	await get_tree().process_frame
	e._change_state(Enemy.State.WINDUP)
	var particles: GPUParticles2D = e._windup_vfx.get_node("Particles")
	assert_bool(particles.emitting).is_false()
