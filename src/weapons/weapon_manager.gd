class_name WeaponManager
extends Node

const TestWeaponScript := preload("res://src/weapons/test_weapon.gd")
const MeleeWeaponScript := preload("res://src/weapons/melee_weapon.gd")

var weapons: Array[Weapon] = []
var _player: Node = null


func _ready() -> void:
	_player = get_parent()
	weapons.resize(3)
	weapons[0] = TestWeaponScript.new()
	weapons[1] = MeleeWeaponScript.new()
	
	_setup_weapon_visuals.call_deferred()


func _setup_weapon_visuals() -> void:
	for weapon in weapons:
		if weapon != null and weapon.visual_scene != null:
			var visual_instance := weapon.visual_scene.instantiate()
			_player.add_child(visual_instance)
			weapon.visual = visual_instance


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var slot := -1
		match event.keycode:
			KEY_Z: slot = 0
			KEY_X: slot = 1
			KEY_C: slot = 2
		if slot >= 0 and slot < weapons.size() and weapons[slot] != null:
			weapons[slot].use(_player)


func _physics_process(delta: float) -> void:
	for weapon in weapons:
		if weapon != null and weapon.has_method("tick"):
			weapon.tick(delta)