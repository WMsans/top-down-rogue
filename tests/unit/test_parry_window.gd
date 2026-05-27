extends GdUnitTestSuite

func _make_user() -> Node2D:
	var n: Node2D = auto_free(Node2D.new())
	add_child(n)
	return n


func _setup_weapon(w: MeleeWeapon) -> void:
	var container: Node2D = auto_free(Node2D.new())
	var sprite: Sprite2D = auto_free(Sprite2D.new())
	container.add_child(sprite)
	w.setup_visual(container, sprite)


func test_parry_active_only_during_window() -> void:
	var w: MeleeWeapon = auto_free(MeleeWeapon.new())
	_setup_weapon(w)
	w.parry_window = 0.1
	var user: Node2D = _make_user()
	assert_that(w.is_parry_active()).is_false()
	assert_that(w.is_swing_active()).is_false()
	w.use(user)
	assert_that(w.is_parry_active()).is_true()
	assert_that(w.is_swing_active()).is_true()
	# Advance past parry window but still inside swing
	for i in range(3):
		w.update_visual(0.04, user)  # 0.12s elapsed
	assert_that(w.is_parry_active()).is_false()
	assert_that(w.is_swing_active()).is_true()

func test_swing_inactive_during_return_phase() -> void:
	var w: MeleeWeapon = auto_free(MeleeWeapon.new())
	_setup_weapon(w)
	var user: Node2D = _make_user()
	w.use(user)
	# PREP 0.06 + ACTION 0.09 + HOLD 0.025 = 0.175 — advance past that
	for i in range(6):
		w.update_visual(0.04, user)  # 0.24s elapsed → in RETURN
	assert_that(w.is_swing_active()).is_false()
