extends GdUnitTestSuite

func test_register_overlay_applies_current_accent() -> void:
	var rect := NinePatchRect.new()
	add_child(rect)
	UiTheme.set_accent(Color(1, 0, 0, 1))
	UiTheme.register_overlay(rect)
	assert_that(rect.modulate).is_equal(Color(1, 0, 0, 1))
	rect.queue_free()

func test_accent_change_updates_registered_overlay() -> void:
	var rect := NinePatchRect.new()
	add_child(rect)
	UiTheme.register_overlay(rect)
	UiTheme.set_accent(Color(0, 1, 0, 1))
	assert_that(rect.modulate).is_equal(Color(0, 1, 0, 1))
	rect.queue_free()

func test_freed_overlay_does_not_break_apply() -> void:
	var rect := NinePatchRect.new()
	add_child(rect)
	UiTheme.register_overlay(rect)
	rect.queue_free()
	await get_tree().process_frame
	# Should not error.
	UiTheme.set_accent(Color(0, 0, 1, 1))
	assert_that(true).is_true()
