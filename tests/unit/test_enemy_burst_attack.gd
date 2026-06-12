extends GdUnitTestSuite

class _MockBurstWeapon extends RangedWeapon:
	var bursting: bool = false
	func is_bursting() -> bool:
		return bursting
	func _use_impl(_user: Node) -> void:
		pass

func test_melee_attack_not_in_progress() -> void:
	var m: MeleeEnemy = auto_free(MeleeEnemy.new())
	add_child(m)
	assert_bool(m._attack_in_progress()).is_false()

func test_ranged_attack_in_progress_tracks_weapon_burst() -> void:
	var e: RangedEnemy = auto_free(RangedEnemy.new())
	add_child(e)
	var w := _MockBurstWeapon.new()
	e.weapon = w
	w.bursting = true
	assert_bool(e._attack_in_progress()).is_true()
	w.bursting = false
	assert_bool(e._attack_in_progress()).is_false()

func test_attack_state_holds_until_burst_done() -> void:
	var e: RangedEnemy = auto_free(RangedEnemy.new())
	add_child(e)
	var w := _MockBurstWeapon.new()
	e.weapon = w
	w.bursting = true
	e._change_state(Enemy.State.ATTACK)
	e._process_attack(0.0)
	assert_int(e._state).is_equal(Enemy.State.ATTACK)
	w.bursting = false
	e._process_attack(0.0)
	assert_int(e._state).is_equal(Enemy.State.COOLDOWN)