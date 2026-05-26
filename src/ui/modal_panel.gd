class_name ModalPanel
extends Control

## Reusable modal composition: backdrop + centred panel with title bar,
## body, and footer. Host scenes set `title`, `width`, and add children
## to `get_body()` / `get_footer()`.

const UILayout = preload("res://src/ui/ui_layout.gd")

signal close_requested

@export var width: UILayout.ModalWidth = UILayout.ModalWidth.MD:
	set(value):
		width = value
		_refresh_width()

@export var title: String = "":
	set(value):
		title = value
		_refresh_title()

@export var show_close_button: bool = true:
	set(value):
		show_close_button = value
		_refresh_close_button()

@export var has_backdrop: bool = true:
	set(value):
		has_backdrop = value
		_refresh_backdrop()

@export var close_on_backdrop_click: bool = true

@onready var _backdrop: ColorRect = $Backdrop
@onready var _root: PanelContainer = $CenterContainer/Root
@onready var _title_label: Label = $CenterContainer/Root/Margin/VBox/TitleBar/TitleLabel
@onready var _close_button: Button = $CenterContainer/Root/Margin/VBox/TitleBar/CloseButton
@onready var _header_separator: HSeparator = $CenterContainer/Root/Margin/VBox/HeaderSeparator
@onready var _body: VBoxContainer = $CenterContainer/Root/Margin/VBox/Body
@onready var _footer: HBoxContainer = $CenterContainer/Root/Margin/VBox/Footer
@onready var _footer_separator: HSeparator = $CenterContainer/Root/Margin/VBox/FooterSeparator

func _ready() -> void:
	_close_button.pressed.connect(_on_close_pressed)
	_backdrop.gui_input.connect(_on_backdrop_gui_input)
	_body.child_entered_tree.connect(_on_children_changed)
	_body.child_exiting_tree.connect(_on_children_changed)
	_footer.child_entered_tree.connect(_on_children_changed)
	_footer.child_exiting_tree.connect(_on_children_changed)
	_refresh_width()
	_refresh_title()
	_refresh_close_button()
	_refresh_backdrop()
	_refresh_section_visibility()

func get_body() -> VBoxContainer:
	return _body

func get_footer() -> HBoxContainer:
	return _footer

func _refresh_width() -> void:
	if _root == null:
		return
	_root.custom_minimum_size.x = UILayout.modal_width_for(width)

func _refresh_title() -> void:
	if _title_label == null:
		return
	_title_label.text = title

func _refresh_close_button() -> void:
	if _close_button == null:
		return
	_close_button.visible = show_close_button

func _refresh_backdrop() -> void:
	if _backdrop == null:
		return
	_backdrop.visible = has_backdrop

func _refresh_section_visibility() -> void:
	if _body == null:
		return
	var has_body := _body.get_child_count() > 0
	var has_footer := _footer.get_child_count() > 0
	_header_separator.visible = has_body
	_footer_separator.visible = has_footer
	_footer.visible = has_footer

func _on_children_changed(_node: Node) -> void:
	call_deferred("_refresh_section_visibility")

func _on_close_pressed() -> void:
	close_requested.emit()

func _on_backdrop_gui_input(event: InputEvent) -> void:
	if not close_on_backdrop_click:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_requested.emit()
