extends GdUnitTestSuite

const BossHudScene := preload("res://scenes/ui/boss_hud.tscn")

func test_setup_records_phase_count() -> void:
	var hud: BossHud = auto_free(BossHudScene.instantiate())
	get_tree().root.add_child(hud)
	hud.setup("Burrower", 300, 3, [300, 200, 100])
	assert_int(hud.get_public_phase()).is_equal(1)

func test_set_phase_lights_pip() -> void:
	var hud: BossHud = auto_free(BossHudScene.instantiate())
	get_tree().root.add_child(hud)
	hud.setup("Boss", 100, 3, [100, 66, 33])
	hud.set_phase(2)
	assert_int(hud.get_public_phase()).is_equal(2)
	var pips := hud.get_node("Pips").get_children()
	assert_int(pips.size()).is_equal(3)
	assert_that(pips[0].self_modulate).is_equal(Color(0.3, 0.3, 0.3, 0.5))
	assert_that(pips[1].self_modulate).is_equal(Color.WHITE)
	assert_that(pips[2].self_modulate).is_equal(Color(0.3, 0.3, 0.3, 0.5))

func test_update_health_clamps_bar() -> void:
	var hud: BossHud = auto_free(BossHudScene.instantiate())
	get_tree().root.add_child(hud)
	hud.setup("Boss", 100, 3, [100, 66, 33])
	hud.update_health(50)
	var bar: ProgressBar = hud.get_node("Bar")
	assert_float(bar.value).is_equal(50.0)
	hud.update_health(-5)
	assert_float(bar.value).is_equal(0.0)
