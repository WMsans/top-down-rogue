class_name WeaponManager
extends Node

const TestWeaponScript := preload("res://src/weapons/test_weapon.gd")
const MeleeWeaponScript := preload("res://src/weapons/melee_weapon.gd")
const LavaEmitterModifierScript := preload("res://src/weapons/lava_emitter_modifier.gd")

signal weapon_activated(slot_index: int)

var _inventory: PlayerInventory
var _player: Node = null
var _visual: Node2D = null
var _sprite: Sprite2D = null
var _active_weapon: Weapon = null


func _ready() -> void:
	_player = get_parent()
	_inventory = _player.get_node_or_null("PlayerInventory")
	if _inventory:
		var test_weapon := TestWeaponScript.new()
		test_weapon.add_modifier(0, LavaEmitterModifierScript.new())
		_inventory.equip_weapon(0, test_weapon)
		_inventory.equip_weapon(1, MeleeWeaponScript.new())
	_setup_visual.call_deferred()


func _setup_visual() -> void:
	_visual = Node2D.new()
	_visual.name = "WeaponVisual"
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite2D"
	_visual.add_child(_sprite)
	_player.add_child(_visual)
	_visual.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var slot := -1
		match event.keycode:
			KEY_Z: slot = 0
			KEY_X: slot = 1
			KEY_C: slot = 2
		if _inventory == null:
			return
		var weapon = _inventory.get_weapon(slot)
		if slot >= 0 and slot < PlayerInventory.MAX_WEAPON_SLOTS and weapon != null:
			if weapon.is_ready():
				_activate_weapon(weapon)
				weapon.use(_player)
				_inventory.active_weapon_slot = slot
				weapon_activated.emit(slot)


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


func _physics_process(delta: float) -> void:
	if _inventory == null:
		return
	for i in range(PlayerInventory.MAX_WEAPON_SLOTS):
		var weapon = _inventory.get_weapon(i)
		if weapon != null:
			weapon.tick(delta)
