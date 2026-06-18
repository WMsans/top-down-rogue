extends CanvasLayer

## Single HUD: TL = health + gold (one framed cluster), TR = weapon
## (matching framed cluster). Replaces health_ui.gd + weapon_button.gd.

@onready var _health_bar_fill: ColorRect = %BarFill
@onready var _health_label: RichTextLabel = %HealthLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _weapon_icon: TextureButton = %WeaponIconButton
@onready var _weapon_fallback: ColorRect = %WeaponFallback
@onready var _weapon_tooltip: PanelContainer = %WeaponTooltip
@onready var _weapon_tooltip_name: Label = %WeaponTooltipName
@onready var _weapon_tooltip_cd: Label = %WeaponTooltipCooldown
@onready var _weapon_tooltip_dmg: Label = %WeaponTooltipDamage

var _inventory: PlayerInventory
var _weapon_manager: WeaponManager
var _current_weapon: Weapon
var _flash_tween: Tween = null
var _bounce_tween: Tween = null
var _outline_panel: Panel = null

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
			_inventory.player_died.connect(_on_died)
			_inventory.gold_changed.connect(_on_gold_changed)
			_on_health_changed(_inventory.get_health(), _inventory.get_max_health())
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

func set_weapon_tooltip(name: String, cooldown: float, damage: int) -> void:
	_weapon_tooltip_name.text = name
	_weapon_tooltip_cd.text = "Cooldown: %.1fs" % cooldown
	_weapon_tooltip_dmg.text = "Damage: %d" % damage

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
	var ratio := clampf(float(current) / float(maximum), 0.0, 1.0) if maximum > 0 else 0.0
	_health_bar_fill.anchor_right = ratio
	_health_label.text = "%d / %d" % [current, maximum]

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
		_weapon_tooltip_dmg.text = "Damage: %.0f" % stats["damage"]
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


