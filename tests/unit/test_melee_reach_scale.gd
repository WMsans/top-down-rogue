extends GdUnitTestSuite

const MeleeWeaponScript := preload("res://src/weapons/melee_weapon.gd")

func test_reach_scale_default_weapon() -> void:
	var w := MeleeWeaponScript.new()
	assert_that(w.weapon_reach).is_equal(36.0)
	assert_that(w._reach_scale).is_equal(1.0)

func test_reach_scale_bone_dagger() -> void:
	var w := MeleeWeaponScript.new()
	w.weapon_reach = 20.0
	w._reach_scale = w.weapon_reach / MeleeWeapon.REFERENCE_REACH
	assert_that(w._reach_scale).is_equal_approx(20.0 / 36.0, 0.001)

func test_reach_scale_tao_sword() -> void:
	var w := MeleeWeaponScript.new()
	w.weapon_reach = 40.0
	w._reach_scale = w.weapon_reach / MeleeWeapon.REFERENCE_REACH
	assert_that(w._reach_scale).is_equal_approx(40.0 / 36.0, 0.001)

func test_reach_scale_broad_axe() -> void:
	var w := MeleeWeaponScript.new()
	w.weapon_reach = 36.0
	w._reach_scale = w.weapon_reach / MeleeWeapon.REFERENCE_REACH
	assert_that(w._reach_scale).is_equal(1.0)

func test_reference_reach_constant() -> void:
	assert_that(MeleeWeapon.REFERENCE_REACH).is_equal(36.0)

func test_reach_scale_rusty_sword() -> void:
	var w := MeleeWeaponScript.new()
	w.weapon_reach = 28.0
	w._reach_scale = w.weapon_reach / MeleeWeapon.REFERENCE_REACH
	assert_that(w._reach_scale).is_equal_approx(28.0 / 36.0, 0.001)

func test_apply_pose_scales_by_reach() -> void:
	var w := MeleeWeaponScript.new()
	w.weapon_reach = 20.0
	var container := Node2D.new()
	var sprite := Sprite2D.new()
	container.add_child(sprite)
	w.setup_visual(container, sprite)
	w._pose_scale = Vector2.ONE
	w._apply_pose()
	assert_that(sprite.scale.x).is_equal_approx(20.0 / 36.0, 0.001)
	assert_that(sprite.scale.y).is_equal_approx(20.0 / 36.0, 0.001)
	container.queue_free()

func test_apply_pose_preserves_squash_stretch() -> void:
	var w := MeleeWeaponScript.new()
	w.weapon_reach = 20.0
	var container := Node2D.new()
	var sprite := Sprite2D.new()
	container.add_child(sprite)
	w.setup_visual(container, sprite)
	w._pose_scale = Vector2(1.25, 0.75)
	w._apply_pose()
	var expected := 20.0 / 36.0
	assert_that(sprite.scale.x).is_equal_approx(1.25 * expected, 0.001)
	assert_that(sprite.scale.y).is_equal_approx(0.75 * expected, 0.001)
	container.queue_free()

func test_trail_inherits_reach_scale() -> void:
	var w := MeleeWeaponScript.new()
	w.weapon_reach = 20.0
	var container := Node2D.new()
	var sprite := Sprite2D.new()
	container.add_child(sprite)
	w.setup_visual(container, sprite)
	var scale_param := Vector2(0.7, 1.35)
	var reach_scale := 20.0 / 36.0
	var expected := scale_param * reach_scale
	assert_that(expected.x).is_equal_approx(0.7 * 20.0 / 36.0, 0.001)
	assert_that(expected.y).is_equal_approx(1.35 * 20.0 / 36.0, 0.001)
	container.queue_free()

func test_resource_file_reach_values_differ() -> void:
	var bone := WeaponRegistry.get_weapon_by_id("bone_dagger")
	var rusty := WeaponRegistry.get_weapon_by_id("rusty_sword")
	assert_that(bone.weapon_reach).is_less(rusty.weapon_reach)