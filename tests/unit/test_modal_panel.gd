extends GdUnitTestSuite

const UILayout = preload("res://src/ui/ui_layout.gd")
const ModalPanelScene = preload("res://scenes/ui/components/modal_panel.tscn")

var _root: Control

func before_test() -> void:
	_root = ModalPanelScene.instantiate()
	add_child(_root)
	await get_tree().process_frame

func after_test() -> void:
	_root.queue_free()

func test_default_width_is_md() -> void:
	var panel: PanelContainer = _root.get_node("CenterContainer/Root")
	assert_that(panel.custom_minimum_size.x).is_equal(float(UILayout.MODAL_MD))

func test_set_width_updates_min_size() -> void:
	_root.width = UILayout.ModalWidth.LG
	# `width` is exported with a setter that updates immediately.
	var panel: PanelContainer = _root.get_node("CenterContainer/Root")
	assert_that(panel.custom_minimum_size.x).is_equal(float(UILayout.MODAL_LG))

func test_set_title_updates_label() -> void:
	_root.title = "HELLO"
	var label: Label = _root.get_node("CenterContainer/Root/Margin/VBox/TitleBar/TitleLabel")
	assert_that(label.text).is_equal("HELLO")

func test_close_button_hidden_when_disabled() -> void:
	_root.show_close_button = false
	var close: Button = _root.get_node("CenterContainer/Root/Margin/VBox/TitleBar/CloseButton")
	assert_that(close.visible).is_false()

func test_close_requested_emitted_on_close_button() -> void:
	var fired := [false]
	_root.close_requested.connect(func(): fired[0] = true)
	var close: Button = _root.get_node("CenterContainer/Root/Margin/VBox/TitleBar/CloseButton")
	close.pressed.emit()
	assert_that(fired[0]).is_true()

func test_footer_hidden_when_empty() -> void:
	await get_tree().process_frame
	var footer: HBoxContainer = _root.get_node("CenterContainer/Root/Margin/VBox/Footer")
	var sep: HSeparator = _root.get_node("CenterContainer/Root/Margin/VBox/FooterSeparator")
	assert_that(footer.visible).is_false()
	assert_that(sep.visible).is_false()
