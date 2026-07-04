# src/ui/chest_ui.gd
class_name ChestUI
extends CanvasLayer

const CARD_MIN_SIZE := Vector2(160, 240)
const ICON_SIZE := Vector2(72, 72)
const CARD_SCENE := preload("res://scenes/ui/card.tscn")

var _weapons: Array[Weapon] = []
var _callback: Callable
var _chosen: bool = false
var _is_closing: bool = false
var _card_slots: Array[Control] = []

@onready var _card_container: HBoxContainer = %CardContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	%ShopPanel.close_requested.connect(close)
	visible = false


func open_with_weapons(weapons: Array[Weapon], callback: Callable) -> void:
	_weapons = weapons
	_callback = callback
	_chosen = false
	_is_closing = false
	%ShopPanel.title = "Choose a Weapon"
	_build_cards()
	SceneManager.set_paused(true)
	visible = true
	_play_entrance_animation()


func close() -> void:
	if _is_closing:
		return
	_is_closing = true
	await _play_exit_animation()
	_clear_cards()
	visible = false
	SceneManager.set_paused(false)
	if not _chosen and _callback.is_valid():
		_callback.call(null)


func _play_entrance_animation() -> void:
	%ShopPanel.modulate.a = 0.0
	%ShopPanel.pivot_offset = %ShopPanel.size * 0.5
	%ShopPanel.scale = Vector2(0.92, 0.92)

	var panel_tween := create_tween()
	panel_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	panel_tween.set_parallel(true)
	panel_tween.tween_property(%ShopPanel, "modulate:a", 1.0, 0.22)
	panel_tween.tween_property(%ShopPanel, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_stagger_cards_in()


func _stagger_cards_in() -> void:
	for i in _card_slots.size():
		var slot := _card_slots[i]
		slot.modulate.a = 0.0
		slot.position.y += 24
		var tween := create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_interval(0.12 + i * 0.08)
		tween.parallel().tween_property(slot, "modulate:a", 1.0, 0.28)
		tween.parallel().tween_property(slot, "position:y", slot.position.y - 24, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _play_exit_animation() -> void:
	var panel_tween := create_tween()
	panel_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	panel_tween.set_parallel(true)
	panel_tween.tween_property(%ShopPanel, "modulate:a", 0.0, 0.18)
	panel_tween.tween_property(%ShopPanel, "scale", Vector2(0.94, 0.94), 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await panel_tween.finished


func _build_cards() -> void:
	_clear_cards()
	for i in _weapons.size():
		var weapon: Weapon = _weapons[i]
		var slot := VBoxContainer.new()
		slot.alignment = BoxContainer.ALIGNMENT_CENTER
		slot.add_theme_constant_override("separation", 4)
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var card := _create_weapon_card(weapon, i)
		slot.add_child(card)
		card.ready.connect(func():
			var stats: Array[String] = []
			var base_stats := weapon.get_base_stats()
			stats.append("Cooldown: %.1fs" % base_stats["cooldown"])
			stats.append("Damage: %.0f" % base_stats["damage"])
			card.populate(weapon.icon_texture, weapon.name, stats)
			card.set_rarity(weapon.rarity)
			card.set_icon_tooltip_text(weapon.name, weapon.description)
		, CONNECT_ONE_SHOT)
		_card_container.add_child(slot)
		_card_slots.append(slot)


func _clear_cards() -> void:
	for child in _card_container.get_children():
		child.queue_free()
	_card_slots.clear()


func _create_weapon_card(weapon: Weapon, index: int) -> Control:
	var card: Card = CARD_SCENE.instantiate()
	card.card_size = CARD_MIN_SIZE
	card.icon_size = ICON_SIZE
	card.card_clicked.connect(func(): _select_weapon(index))
	return card


func _select_weapon(index: int) -> void:
	if _is_closing:
		return
	if index < 0 or index >= _weapons.size():
		return
	_chosen = true
	_is_closing = true
	var weapon: Weapon = _weapons[index]
	await _play_exit_animation()
	_clear_cards()
	visible = false
	SceneManager.set_paused(false)
	if _callback.is_valid():
		_callback.call(weapon)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
