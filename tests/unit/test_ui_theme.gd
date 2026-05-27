extends GdUnitTestSuite

func test_default_accent_is_caves_orange() -> void:
	var ui: Node = load("res://src/ui/ui_theme.gd").new()
	ui._build_theme()
	assert_that(ui.accent).is_equal(Color(0.851, 0.467, 0.259, 1))

func test_set_accent_updates_button_hover_color() -> void:
	var ui: Node = load("res://src/ui/ui_theme.gd").new()
	ui._build_theme()
	var new_accent := Color(0.431, 0.776, 0.910, 1)
	ui.set_accent(new_accent)
	var hover_color: Color = ui.get_theme().get_color("font_hover_color", "Button")
	assert_that(hover_color).is_equal(new_accent)

func test_set_accent_updates_title_label_color() -> void:
	var ui: Node = load("res://src/ui/ui_theme.gd").new()
	ui._build_theme()
	var new_accent := Color(1.0, 0.314, 0.188, 1)
	ui.set_accent(new_accent)
	var title_color: Color = ui.get_theme().get_color("font_color", "TitleLabel")
	assert_that(title_color).is_equal(new_accent)

func test_set_accent_emits_palette_changed() -> void:
	var ui: Node = load("res://src/ui/ui_theme.gd").new()
	ui._build_theme()
	var monitor := monitor_signals(ui)
	ui.set_accent(Color.MAGENTA)
	await assert_signal(monitor).is_emitted("palette_changed")

func test_theme_uses_16px_body_font_size() -> void:
	var ui: Node = load("res://src/ui/ui_theme.gd").new()
	ui._build_theme()
	var t: Theme = ui.get_theme()
	assert_that(t.default_font_size).is_equal(16)
	assert_that(t.get_font_size("font_size", "Button")).is_equal(16)

func test_panel_stylebox_has_zero_corner_radius() -> void:
	var ui: Node = load("res://src/ui/ui_theme.gd").new()
	ui._build_theme()
	var sb: StyleBoxFlat = ui.get_theme().get_stylebox("panel", "PanelContainer")
	assert_that(sb.corner_radius_top_left).is_equal(0)
	assert_that(sb.corner_radius_top_right).is_equal(0)
	assert_that(sb.corner_radius_bottom_left).is_equal(0)
	assert_that(sb.corner_radius_bottom_right).is_equal(0)
	assert_that(sb.border_width_top).is_equal(2)
	assert_that(sb.border_width_bottom).is_equal(2)
	assert_that(sb.border_width_left).is_equal(2)
	assert_that(sb.border_width_right).is_equal(2)

