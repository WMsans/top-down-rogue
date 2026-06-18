class_name WeaponManager
extends Node

const TestWeaponScript := preload("res://src/weapons/test_weapon.gd")
const MeleeWeaponScript := preload("res://src/weapons/melee_weapon.gd")
const LavaEmitterModifierScript := preload("res://src/weapons/modifiers/lava_emitter_modifier.gd")
const ChargeBarScript := preload("res://src/ui/charge_bar.gd")

signal weapon_activated(slot_index: int)

var _inventory: PlayerInventory
var _player: Node = null
var _visual: Node2D = null
var _sprite: Sprite2D = null
var _active_weapon: Weapon = null
var _pressed_slot: int = -1
var _charge_bar: ChargeBar = null


func _ready() -> void:
	_player = get_parent()
	_setup_visual.call_deferred()
	_setup_weapons.call_deferred()


func _setup_weapons() -> void:
	_inventory = _player.get_node_or_null("PlayerInventory")
	if _inventory:
		var test_weapon := TestWeaponScript.new()
		test_weapon.add_modifier(0, LavaEmitterModifierScript.new())
		_inventory.equip_weapon(0, test_weapon)
		_inventory.equip_weapon(1, MeleeWeaponScript.new())


func _setup_visual() -> void:
	_visual = Node2D.new()
	_visual.name = "WeaponVisual"
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite2D"
	_visual.add_child(_sprite)
	_player.add_child(_visual)
	_visual.visible = false

	_charge_bar = ChargeBarScript.new()
	_charge_bar.name = "ChargeBar"
	_player.add_child(_charge_bar)


func _input(event: InputEvent) -> void:
	if ConsoleManager.is_open():
		return
	if not (event is InputEventKey) or event.echo:
		return
	var slot := _slot_for_keycode(event.keycode)
	if slot < 0 or _inventory == null:
		return
	if event.pressed:
		var status := _player.get_node_or_null("StatusComponent")
		if status != null and not status.can_attack():
			return
		var weapon = _inventory.get_weapon(slot)
		if slot < PlayerInventory.MAX_WEAPON_SLOTS and weapon != null:
			_activate_weapon(weapon)
			_inventory.active_weapon_slot = slot
			_pressed_slot = slot
			weapon.on_press(_player)
			weapon_activated.emit(slot)
	else:
		# Route the release to whatever weapon received the press for this slot.
		if slot == _pressed_slot:
			var weapon = _inventory.get_weapon(slot)
			if weapon != null:
				weapon.on_release(_player)
			_pressed_slot = -1


func _slot_for_keycode(keycode: int) -> int:
	match keycode:
		KEY_Z: return 0
		KEY_X: return 1
		KEY_C: return 2
	return -1


func _activate_weapon(weapon: Weapon) -> void:
	if weapon.has_visual():
		weapon.setup_visual(_visual, _sprite)
		_visual.visible = true
	else:
		_visual.visible = false
	_active_weapon = weapon


func _process(delta: float) -> void:
	if _active_weapon != null and _active_weapon.has_visual():
		_active_weapon.update_visual(delta, _player)
	_update_charge_bar()


func _update_charge_bar() -> void:
	if _charge_bar == null:
		return
	if _active_weapon != null and _active_weapon.is_charging():
		_charge_bar.set_active(true)
		_charge_bar.set_ratio(_active_weapon.get_charge_ratio())
	else:
		_charge_bar.set_active(false)


func _physics_process(delta: float) -> void:
	if _inventory == null:
		return
	for i in range(PlayerInventory.MAX_WEAPON_SLOTS):
		var weapon = _inventory.get_weapon(i)
		if weapon != null:
			weapon.tick(delta)
