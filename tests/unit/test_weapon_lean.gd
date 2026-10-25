extends GdUnitTestSuite


class LeanSpy extends Node2D:
	var dirs: Array = []

	func get_facing_direction() -> Vector2:
		return Vector2.LEFT

	func play_attack_lean(direction: Vector2) -> void:
		dirs.append(direction)


func test_use_calls_lean_with_facing() -> void:
	var w := TestWeapon.new()
	var spy: LeanSpy = auto_free(LeanSpy.new())
	w.use(spy)
	assert_array(spy.dirs).contains_exactly([Vector2.LEFT])


func test_use_on_cooldown_does_not_lean() -> void:
	var w := TestWeapon.new()
	var spy: LeanSpy = auto_free(LeanSpy.new())
	w.use(spy)
	w.use(spy)
	assert_array(spy.dirs).has_size(1)


func test_use_with_null_user_does_not_crash() -> void:
	var w := Weapon.new()  # base _use_impl is a no-op; TestWeapon itself needs a user
	w.use(null)
	assert_bool(w.is_ready()).is_false()


func test_charged_ranged_release_leans() -> void:
	var w := ChargedRangedWeapon.new()
	w.charge_time_full = 0.5
	w.shot_sink = func(_dir): pass
	var spy: LeanSpy = auto_free(LeanSpy.new())
	add_child(spy)
	w.on_press(spy)
	w.tick(0.6)
	w.on_release(spy)
	assert_array(spy.dirs).contains_exactly([Vector2.LEFT])


class ProbeMelee extends AdvancedMeleeWeapon:
	func _setup_moves() -> void:
		charge_time_full = 0.5
		tap_threshold = 0.1
		charged_flurry_max = 2
		light_moves = [_slash()]
		charged_moves = [_spin()]
	func _play_move(_move, _user) -> void:
		pass


func test_advanced_melee_charged_release_leans() -> void:
	var w := ProbeMelee.new()
	var spy: LeanSpy = auto_free(LeanSpy.new())
	w.on_press(spy)
	w._tick_impl(1.0)
	w.on_release(spy)
	assert_array(spy.dirs).contains_exactly([Vector2.LEFT])
