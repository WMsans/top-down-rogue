extends CanvasLayer

const PIXEL_FONT := preload("res://textures/DawnLike/GUI/SDS_8x8.ttf")
const CARD_MIN_SIZE := Vector2(160, 200)
const ICON_SIZE := Vector2(96, 96)

@onready var _overlay: ColorRect = %Overlay
@onready var _cards_container: HBoxContainer = %CardsContainer
@onready var _title_label: Label = %TitleLabel

var _weapon_manager: WeaponManager = null
var _selected_slot: int = -1
var _pickup_mode: bool = false
var _pickup_weapon: Weapon = null
var _pickup_callback: Callable


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_theme()
	visible = false
	_overlay.gui_input.connect(_on_overlay_input)


func open(weapon_manager: WeaponManager) -> void:
	_weapon_manager = weapon_manager
	_selected_slot = -1
	_build_cards()
	SceneManager.set_paused(true)
	visible = true


func open_for_pickup(weapon_manager: WeaponManager, new_weapon: Weapon, callback: Callable) -> void:
	_pickup_mode = true
	_pickup_weapon = new_weapon
	_pickup_callback = callback
	_weapon_manager = weapon_manager
	_selected_slot = -1
	_build_cards()
	_title_label.text = "Replace a slot:"
	SceneManager.set_paused(true)
	visible = true


func close() -> void:
	visible = false
	_weapon_manager = null
	_pickup_mode = false
	_pickup_weapon = null
	_pickup_callback = Callable()
	_selected_slot = -1
	_clear_cards()
	SceneManager.set_paused(false)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func _build_cards() -> void:
	_clear_cards()
	for i in range(3):
		var weapon: Weapon = null
		if i < _weapon_manager.weapons.size():
			weapon = _weapon_manager.weapons[i]
		var card := _create_card(weapon, i)
		_cards_container.add_child(card)


func _clear_cards() -> void:
	for child in _cards_container.get_children():
		child.queue_free()


func _create_card(weapon: Weapon, slot_index: int) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_MIN_SIZE
	card.gui_input.connect(_on_card_input.bind(slot_index))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	if weapon == null:
		var label := Label.new()
		label.text = "EMPTY"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(label)
	else:
		_add_icon(vbox, weapon)
		var name_label := Label.new()
		name_label.text = weapon.name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(name_label)

		var stats := weapon.get_base_stats()
		var cooldown_label := Label.new()
		cooldown_label.text = "Cooldown: %.1fs" % stats["cooldown"]
		cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(cooldown_label)

		var damage_label := Label.new()
		damage_label.text = "Damage: %.0f" % stats["damage"]
		damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(damage_label)

	return card


func _add_icon(parent: VBoxContainer, weapon: Weapon) -> void:
	if weapon.icon_texture != null:
		var icon := TextureRect.new()
		icon.texture = weapon.icon_texture
		icon.custom_minimum_size = ICON_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		parent.add_child(icon)
	else:
		var fallback := ColorRect.new()
		fallback.custom_minimum_size = ICON_SIZE
		fallback.color = Color(0.3, 0.3, 0.3, 1)
		parent.add_child(fallback)
		var q_label := Label.new()
		q_label.text = "?"
		q_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q_label.anchors_preset = Control.PRESET_FULL_RECT
		fallback.add_child(q_label)


func _on_card_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _pickup_mode:
			_pickup_callback.call(slot_index)
			close()
		else:
			if _selected_slot == -1:
				_selected_slot = slot_index
				_highlight_slot(slot_index)
			else:
				if _selected_slot != slot_index:
					_swap_weapons(_selected_slot, slot_index)
				_selected_slot = -1
				_build_cards()


func _highlight_slot(slot_index: int) -> void:
	var cards := _cards_container.get_children()
	if slot_index < cards.size():
		var card: Control = cards[slot_index]
		card.modulate = Color(1.0, 1.0, 0.7, 1.0)


func _swap_weapons(slot_a: int, slot_b: int) -> void:
	if _weapon_manager != null:
		_weapon_manager.swap_weapons(slot_a, slot_b)


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			close()


func _apply_theme() -> void:
	var t := Theme.new()
	t.default_font = PIXEL_FONT
	t.set_font_size("font_size", "Label", 16)
	t.set_color("font_color", "Label", Color(0.976, 0.988, 0.953))
	_title_label.theme = t