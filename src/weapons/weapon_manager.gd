class_name WeaponManager
extends Node

const TestWeaponScript := preload("res://src/weapons/test_weapon.gd")
const MeleeWeaponScript := preload("res://src/weapons/melee_weapon.gd")

var weapons: Array[Weapon] = []
var _player: Node = null
var _visual: Node2D = null
var _sprite: Sprite2D = null
var _active_weapon: Weapon = null


func _ready() -> void:
	_player = get_parent()
	weapons.resize(3)
	weapons[0] = TestWeaponScript.new()
	weapons[1] = MeleeWeaponScript.new()

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
		if slot >= 0 and slot < weapons.size() and weapons[slot] != null:
			var weapon := weapons[slot]
			_activate_weapon(weapon)
			weapon.use(_player)


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
	for weapon in weapons:
		if weapon != null:
			weapon.tick(delta)
