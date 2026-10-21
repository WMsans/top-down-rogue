extends GdUnitTestSuite

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")


func _hud() -> CanvasLayer:
	var hud: CanvasLayer = auto_free(HUD_SCENE.instantiate())
	add_child(hud)
	return hud


func _lit(container: HBoxContainer) -> int:
	var n := 0
	for c in container.get_children():
		if c.modulate.a > 0.5:
			n += 1
	return n


func test_hearts_show_current_and_max() -> void:
	var hud := _hud()
	hud._on_health_changed(2, 3)
	var hearts: HBoxContainer = hud.get_node("%Hearts")
	assert_int(hearts.get_child_count()).is_equal(3)
	assert_int(_lit(hearts)).is_equal(2)


func test_shields_show_current_and_max() -> void:
	var hud := _hud()
	hud._on_armor_changed(1, 3)
	var shields: HBoxContainer = hud.get_node("%Shields")
	assert_int(shields.get_child_count()).is_equal(3)
	assert_int(_lit(shields)).is_equal(1)


func test_shields_follow_max_armor() -> void:
	var hud := _hud()
	hud._on_armor_changed(1, 1)
	assert_int(hud.get_node("%Shields").get_child_count()).is_equal(1)
	hud._on_armor_changed(3, 4)
	assert_int(hud.get_node("%Shields").get_child_count()).is_equal(4)
