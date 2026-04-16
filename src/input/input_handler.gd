extends Node

const FIRE_RADIUS := 5.0
const GAS_RADIUS := 6.0
const GAS_DENSITY := 200
const WEAPON_DROP_SCENE := preload("res://scenes/weapon_drop.tscn")
const TestWeaponScript := preload("res://src/weapons/test_weapon.gd")
const MeleeWeaponScript := preload("res://src/weapons/melee_weapon.gd")

var _weapon_scripts: Array[GDScript] = []

@onready var world_manager: Node2D = get_parent().get_node("WorldManager")

func _ready() -> void:
	_weapon_scripts = [TestWeaponScript, MeleeWeaponScript]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var viewport := get_viewport()
		var camera := viewport.get_camera_2d()
		if camera == null:
			return
		var screen_pos := viewport.get_mouse_position()
		var view_size := viewport.get_visible_rect().size
		var world_pos := (screen_pos - view_size * 0.5) / camera.zoom + camera.global_position
		if event.button_index == MOUSE_BUTTON_LEFT:
			_spawn_weapon_drop(world_pos)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			world_manager.place_lava(world_pos, 5.0)


func _spawn_weapon_drop(pos: Vector2) -> void:
	var drop: WeaponDrop = WEAPON_DROP_SCENE.instantiate()
	var weapon_script: GDScript = _weapon_scripts[randi() % _weapon_scripts.size()]
	drop.weapon = weapon_script.new()
	get_parent().add_child(drop)
	drop.global_position = pos
