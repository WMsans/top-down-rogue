extends CanvasLayer

const PIXEL_FONT := preload("res://textures/Assets/DawnLike/GUI/SDS_8x8.ttf")
const MODIFIER_ICON_SIZE := Vector2(32, 32)

@export var weapon_popup: NodePath

@onready var _icon_button: TextureButton = %IconButton
@onready var _tooltip: PanelContainer = %Tooltip
@onready var _tooltip_name: Label = %TooltipName
@onready var _tooltip_cooldown: Label = %TooltipCooldown
@onready var _tooltip_damage: Label = %TooltipDamage
@onready var _fallback_icon: ColorRect = %FallbackIcon

var _weapon_manager: WeaponManager = null
var _current_weapon: Weapon = null


func _ready() -> void:
	_apply_theme()
	_tooltip.visible = false
	_fallback_icon.visible = false
	_icon_button.texture_normal = null
	_icon_button.pressed.connect(_on_button_pressed)
	_icon_button.mouse_entered.connect(_on_mouse_entered)
	_icon_button.mouse_exited.connect(_on_mouse_exited)
	_find_weapon_manager()
	if _weapon_manager != null:
		_weapon_manager.weapon_activated.connect(_on_weapon_activated)
		_update_display(_weapon_manager.active_slot)


func _find_weapon_manager() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		_weapon_manager = player.get_node("WeaponManager")


func _on_weapon_activated(slot_index: int) -> void:
	_update_display(slot_index)


func _update_display(slot_index: int) -> void:
	if _weapon_manager == null:
		return
	if slot_index < 0 or slot_index >= _weapon_manager.weapons.size():
		return
	var weapon: Weapon = _weapon_manager.weapons[slot_index]
	if weapon == null:
		return
	_current_weapon = weapon
	if weapon.icon_texture != null:
		_icon_button.texture_normal = weapon.icon_texture
		_icon_button.visible = true
		_fallback_icon.visible = false
	else:
		_icon_button.visible = false
		_fallback_icon.visible = true
	_tooltip.visible = false


func _on_button_pressed() -> void:
	if _weapon_manager != null:
		var popup := get_node_or_null(weapon_popup)
		if popup and popup.has_method("open"):
			popup.open(_weapon_manager)


func _on_mouse_entered() -> void:
	if _current_weapon != null:
		_update_tooltip()
		_tooltip.visible = true


func _on_mouse_exited() -> void:
	_tooltip.visible = false


func _update_tooltip() -> void:
	if _current_weapon == null:
		return
	var stats := _current_weapon.get_base_stats()
	_tooltip_name.text = str(stats["name"])
	_tooltip_cooldown.text = "Cooldown: %.1fs" % stats["cooldown"]
	_tooltip_damage.text = "Damage: %.0f" % stats["damage"]
	_clear_modifier_icons()
	_add_modifier_icons()


func _clear_modifier_icons() -> void:
	var row := _tooltip.get_node_or_null("VBoxContainer/ModifierRow")
	if row != null:
		for child in row.get_children():
			child.queue_free()


func _add_modifier_icons() -> void:
	var vbox := _tooltip.get_node("VBoxContainer")
	var row := vbox.get_node_or_null("ModifierRow")
	if row == null:
		row = HBoxContainer.new()
		row.name = "ModifierRow"
		row.add_theme_constant_override("separation", 2)
		vbox.add_child(row)
	for i in range(_current_weapon.modifier_slot_count):
		var modifier: Modifier = _current_weapon.get_modifier_at(i)
		if modifier != null:
			var icon := TextureRect.new()
			icon.custom_minimum_size = MODIFIER_ICON_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			if modifier.icon_texture != null:
				icon.texture = modifier.icon_texture
			row.add_child(icon)
		else:
			var empty := ColorRect.new()
			empty.custom_minimum_size = MODIFIER_ICON_SIZE
			empty.color = Color(0.2, 0.2, 0.2, 1)
			row.add_child(empty)


func _apply_theme() -> void:
	var t := Theme.new()
	t.default_font = PIXEL_FONT
	t.set_font_size("font_size", "Label", 16)
	t.set_color("font_color", "Label", Color(0.976, 0.988, 0.953))
	_tooltip_name.theme = t
	_tooltip_cooldown.theme = t
	_tooltip_damage.theme = t