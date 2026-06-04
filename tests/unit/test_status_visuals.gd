extends GdUnitTestSuite

const StatusVisualsScript = preload("res://src/status/status_visuals.gd")
const StatusComponentScript = preload("res://src/status/status_component.gd")


func _sprite_children(node: Node) -> int:
	var n := 0
	for c in node.get_children():
		if c is Sprite2D:
			n += 1
	return n


func test_one_icon_per_active_status() -> void:
	var status: StatusComponent = auto_free(StatusComponentScript.new())
	status.add_stain("on_fire", 2.0)
	status.add_stain("wet", 2.0)
	status.add_stain("oiled", 0.2)  # below threshold -> no icon
	var sv = auto_free(StatusVisualsScript.new())
	sv.setup(status, Vector2.ZERO)
	assert_int(_sprite_children(sv)).is_equal(2)


func test_icon_removed_when_status_lapses() -> void:
	var status: StatusComponent = auto_free(StatusComponentScript.new())
	status.add_stain("on_fire", 2.0)
	var sv = auto_free(StatusVisualsScript.new())
	sv.setup(status, Vector2.ZERO)
	assert_int(_sprite_children(sv)).is_equal(1)
	status.clear("on_fire")  # emits changed -> refresh
	assert_int(_sprite_children(sv)).is_equal(0)


func test_alpha_is_min_at_threshold() -> void:
	var status: StatusComponent = auto_free(StatusComponentScript.new())
	status.add_stain("on_fire", 1.0)  # exactly threshold
	var sv = auto_free(StatusVisualsScript.new())
	sv.setup(status, Vector2.ZERO)
	var icon: Sprite2D = null
	for c in sv.get_children():
		if c is Sprite2D:
			icon = c
	assert_object(icon).is_not_null()
	assert_float(icon.modulate.a).is_equal_approx(StatusRegistry.ICON_MIN_ALPHA, 0.01)
