extends GdUnitTestSuite

func _weapon() -> ChargedRangedWeapon:
	var w := ChargedRangedWeapon.new()
	w.charge_time_full = 0.5
	w.cooldown = 1.0
	return w

func test_partial_charge_release_fires_nothing() -> void:
	var shots: Array = []
	var w := _weapon()
	w.shot_sink = func(_dir): shots.append(1)
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	w.on_press(user)
	w.tick(0.2)  # below charge_time_full
	w.on_release(user)
	assert_int(shots.size()).is_equal(0)

func test_full_charge_release_fires_once() -> void:
	var shots: Array = []
	var w := _weapon()
	w.shot_sink = func(_dir): shots.append(1)
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	w.on_press(user)
	w.tick(0.6)  # >= charge_time_full
	assert_float(w.get_charge_ratio()).is_equal_approx(1.0, 0.001)
	assert_bool(w.is_charging()).is_true()
	w.on_release(user)
	assert_int(shots.size()).is_equal(1)
	assert_bool(w.is_charging()).is_false()

func test_is_chargeable_true() -> void:
	assert_bool(_weapon().is_chargeable()).is_true()
