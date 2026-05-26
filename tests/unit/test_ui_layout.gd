extends GdUnitTestSuite

const UILayout = preload("res://src/ui/ui_layout.gd")

func test_spacing_scale_values() -> void:
	assert_that(UILayout.XS).is_equal(4)
	assert_that(UILayout.S).is_equal(8)
	assert_that(UILayout.M).is_equal(16)
	assert_that(UILayout.L).is_equal(24)
	assert_that(UILayout.XL).is_equal(32)

func test_modal_widths() -> void:
	assert_that(UILayout.MODAL_SM).is_equal(320)
	assert_that(UILayout.MODAL_MD).is_equal(480)
	assert_that(UILayout.MODAL_LG).is_equal(640)

func test_modal_width_for_enum() -> void:
	assert_that(UILayout.modal_width_for(UILayout.ModalWidth.SM)).is_equal(320)
	assert_that(UILayout.modal_width_for(UILayout.ModalWidth.MD)).is_equal(480)
	assert_that(UILayout.modal_width_for(UILayout.ModalWidth.LG)).is_equal(640)

func test_button_and_panel_constants() -> void:
	assert_that(UILayout.PANEL_PAD_X).is_equal(24)
	assert_that(UILayout.PANEL_PAD_Y).is_equal(24)
	assert_that(UILayout.HUD_GUTTER).is_equal(16)
	assert_that(UILayout.BUTTON_MIN_HEIGHT).is_equal(40)
	assert_that(UILayout.BUTTON_COMPACT_MIN_WIDTH).is_equal(96)
	assert_that(UILayout.BUTTON_ICON_SIZE).is_equal(32)
	assert_that(UILayout.TITLE_BAR_HEIGHT).is_equal(48)
	assert_that(UILayout.SEPARATOR_PAD).is_equal(8)
