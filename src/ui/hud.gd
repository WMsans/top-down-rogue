extends CanvasLayer

## Single HUD: TL = hearts + shields + gold (one framed cluster), TR = weapon
## (matching framed cluster). Replaces health_ui.gd + weapon_button.gd.

const PIP_SIZE := Vector2(12, 12)
const HEART_COLOR := Color(0.9, 0.2, 0.2)
const SHIELD_COLOR := Color(0.35, 0.65, 1.0)
const PIP_EMPTY_ALPHA := 0.2
const PIP_POP_TIME := 0.18
const PIP_POP_SCALE := 1.6

@onready var _hearts: HBoxContainer = %Hearts
@onready var _shields: HBoxContainer = %Shields
@onready var _gold_label: Label = %GoldLabel
@onready var _weapon_icon: TextureButton = %WeaponIconButton
@onready var _weapon_fallback: ColorRect = %WeaponFallback
@onready var _weapon_tooltip: PanelContainer = %WeaponTooltip
@onready var _weapon_tooltip_name: Label = %WeaponTooltipName
@onready var _weapon_tooltip_cd: Label = %WeaponTooltipCooldown
@onready var _weapon_tooltip_dig: Label = %WeaponTooltipDig

var _inventory: PlayerInventory
var _weapon_manager: WeaponManager
var _current_weapon: Weapon
var _flash_tween: Tween = null
var _bounce_tween: Tween = null
var _outline_panel: Panel = null
var _lit_pip_counts: Dictionary = {}  # container instance id -> lit pip count

func _ready() -> void:
	_weapon_icon.pressed.connect(_on_weapon_button_pressed)
	_weapon_icon.mouse_entered.connect(_on_weapon_mouse_entered)
	_weapon_icon.mouse_exited.connect(_on_weapon_mouse_exited)
	_weapon_tooltip.visible = false
	_weapon_fallback.visible = false

	var player := get_tree().get_first_node_in_group("player")
	if player:
		_inventory = player.get_node_or_null("PlayerInventory")
		if _inventory:
			_inventory.health_changed.connect(_on_health_changed)
			_inventory.armor_changed.connect(_on_armor_changed)
			_inventory.player_died.connect(_on_died)
			_inventory.gold_changed.connect(_on_gold_changed)
			_on_health_changed(_inventory.get_health(), _inventory.get_max_health())
			_on_armor_changed(_inventory.get_armor(), _inventory.get_max_armor())
			_on_gold_changed(_inventory.gold)
		_weapon_manager = player.get_node_or_null("WeaponManager")
		if _weapon_manager:
			_weapon_manager.weapon_activated.connect(_on_weapon_activated)
			_update_weapon_display(_inventory.active_weapon_slot if _inventory else 0)
	_outline_panel = _create_outline_panel()

func set_health(current: int, max_value: int) -> void:
	_on_health_changed(current, max_value)

func set_gold(amount: int) -> void:
	_gold_label.text = str(amount)

func set_weapon_icon(texture: Texture2D) -> void:
	if texture == null:
		_weapon_icon.texture_normal = null
		_weapon_fallback.visible = true
	else:
		_weapon_icon.texture_normal = texture
		_weapon_fallback.visible = false

func set_weapon_tooltip(name: String, cooldown: float, dig_power: float) -> void:
	_weapon_tooltip_name.text = name
	_weapon_tooltip_cd.text = "Cooldown: %.1fs" % cooldown
	_weapon_tooltip_dig.text = "Dig: %.1f" % dig_power

func show_weapon_tooltip(show: bool) -> void:
	_weapon_tooltip.visible = show

func flash_slots_full() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_outline_panel.visible = true
	if _bounce_tween != null and _bounce_tween.is_valid():
		_bounce_tween.kill()
		UiAnimations.reset_scale(_weapon_icon)
	_bounce_tween = UiAnimations.jitter_bounce(_weapon_icon)
	_flash_tween = create_tween()
	_flash_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_flash_tween.tween_interval(0.8)
	_flash_tween.tween_callback(func() -> void: _outline_panel.visible = false)

func _on_health_changed(current: int, maximum: int) -> void:
	set_pips(_hearts, current, maximum, HEART_COLOR)


func _on_armor_changed(current: int, maximum: int) -> void:
	set_pips(_shields, current, maximum, SHIELD_COLOR)


# One square per point of `maximum`; the first `current` are lit, the rest dimmed.
func set_pips(container: HBoxContainer, current: int, maximum: int, color: Color) -> void:
	while container.get_child_count() < maximum:
		var pip := ColorRect.new()
		pip.custom_minimum_size = PIP_SIZE
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(pip)
	while container.get_child_count() > maximum:
		var last: Node = container.get_child(container.get_child_count() - 1)
		container.remove_child(last)
		last.queue_free()
	for i in range(container.get_child_count()):
		var pip: ColorRect = container.get_child(i)
		pip.color = color
		pip.modulate.a = 1.0 if i < current else PIP_EMPTY_ALPHA
	var lit: int = mini(current, maximum)
	var key: int = container.get_instance_id()
	var was_lit: int = _lit_pip_counts.get(key, -1)
	_lit_pip_counts[key] = lit
	# -1 means the row was empty until now: that is a fill, not a refill.
	if was_lit >= 0 and lit > was_lit:
		_pop_pip(container.get_child(lit - 1))


# Short pop on a newly lit pip: armour regen is silent otherwise, so a
# refilling shield would otherwise be invisible. Scale only - the alpha of a
# pip says whether it is lit.
func _pop_pip(pip: Node) -> void:
	if pip == null or not (pip is Control):
		return
	var c := pip as Control
	c.pivot_offset = PIP_SIZE * 0.5
	c.scale = Vector2.ONE * PIP_POP_SCALE
	var tween := c.create_tween()
	tween.tween_property(c, "scale", Vector2.ONE, PIP_POP_TIME)

func _on_died() -> void:
	if _inventory:
		_on_health_changed(0, _inventory.get_max_health())

func _on_gold_changed(amount: int) -> void:
	_gold_label.text = str(amount)

func _on_weapon_activated(slot_index: int) -> void:
	_update_weapon_display(slot_index)

func _update_weapon_display(slot_index: int) -> void:
	if not _inventory:
		return
	if slot_index < 0 or slot_index >= PlayerInventory.MAX_WEAPON_SLOTS:
		return
	var weapon: Weapon = _inventory.get_weapon(slot_index)
	if weapon == null:
		return
	_current_weapon = weapon
	if weapon.icon_texture != null:
		_weapon_icon.texture_normal = weapon.icon_texture
		_weapon_fallback.visible = false
	else:
		_weapon_icon.texture_normal = null
		_weapon_fallback.visible = true

func _on_weapon_button_pressed() -> void:
	if _weapon_manager != null:
		var popup := get_tree().root.find_child("WeaponPopup", true, false)
		if popup and popup.has_method("open"):
			popup.open(_weapon_manager)

func _on_weapon_mouse_entered() -> void:
	if _current_weapon != null:
		var stats := _current_weapon.get_base_stats()
		_weapon_tooltip_name.text = str(stats["name"])
		_weapon_tooltip_cd.text = "Cooldown: %.1fs" % stats["cooldown"]
		_weapon_tooltip_dig.text = "Dig: %.1f" % stats["dig_power"]
		_weapon_tooltip.visible = true

func _on_weapon_mouse_exited() -> void:
	_weapon_tooltip.visible = false

func _create_outline_panel() -> Panel:
	var p := Panel.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(1.0, 0.2, 0.2, 1.0)
	style.draw_center = false
	p.add_theme_stylebox_override("panel", style)
	_weapon_icon.add_child(p)
	return p


