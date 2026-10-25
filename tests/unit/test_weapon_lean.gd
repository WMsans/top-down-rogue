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
