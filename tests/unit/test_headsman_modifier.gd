extends GdUnitTestSuite

# Headsman refunds 50% of the remaining cooldown on a kill (modifiers.csv).

func test_headsman_refunds_half_the_remaining_cooldown() -> void:
	var w: Weapon = Weapon.new()
	w.cooldown = 2.0
	w.use(null)                      # 2.0s of cooldown pending
	HeadsmanModifier.new().on_kill(w, null, null)
	w.tick(0.99)
	assert_bool(w.is_ready()).is_false()   # not an instant swing
	w.tick(0.02)
	assert_bool(w.is_ready()).is_true()    # ready halfway through the wait


func test_headsman_does_nothing_without_a_kill() -> void:
	var w: Weapon = Weapon.new()
	w.cooldown = 2.0
	w.use(null)
	w.tick(0.5)
	assert_bool(w.is_ready()).is_false()
