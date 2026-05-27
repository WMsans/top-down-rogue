extends GdUnitTestSuite

const UILayout = preload("res://src/ui/ui_layout.gd")

func test_default_button_min_height_is_button_min_height() -> void:
	var t := UiTheme.get_theme()
	var sb: StyleBox = t.get_stylebox("normal", "Button")
	assert_that(sb).is_not_null()

func test_compact_button_variation_registered() -> void:
	var t := UiTheme.get_theme()
	assert_that(str(t.get_type_variation_base("CompactButton"))).is_equal("Button")

func test_icon_button_variation_registered() -> void:
	var t := UiTheme.get_theme()
	assert_that(str(t.get_type_variation_base("IconButton"))).is_equal("Button")

func test_separator_separation_constant() -> void:
	var t := UiTheme.get_theme()
	assert_that(t.get_constant("separation", "HSeparator")).is_equal(UILayout.SEPARATOR_PAD)
