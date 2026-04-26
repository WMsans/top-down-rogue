extends Node

const FIRE_RADIUS := 5.0
const GAS_RADIUS := 6.0
const GAS_DENSITY := 200
const WEAPON_DROP_SCENE := preload("res://scenes/weapon_drop.tscn")
const MODIFIER_DROP_SCENE := preload("res://scenes/modifier_drop.tscn")
const TestWeaponScript := preload("res://src/weapons/test_weapon.gd")
const MeleeWeaponScript := preload("res://src/weapons/melee_weapon.gd")
const LavaEmitterModifierScript := preload("res://src/weapons/lava_emitter_modifier.gd")
const GOLD_DROP_SCENE := preload("res://scenes/gold_drop.tscn")
const DUMMY_ENEMY_SCENE := preload("res://scenes/dummy_enemy.tscn")
const SHOP_UI_SCENE := preload("res://scenes/economy/shop_ui.tscn")
const ShopOfferScript := preload("res://src/economy/shop_offer.gd")

var _weapon_scripts: Array[GDScript] = []
var _modifier_scripts: Array[GDScript] = []

@onready var world_manager: Node2D = get_parent().get_node("WorldManager")

func _ready() -> void:
	_weapon_scripts = [TestWeaponScript, MeleeWeaponScript]
	_modifier_scripts = [LavaEmitterModifierScript]


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
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_spawn_dummy_enemy(world_pos)


func _spawn_weapon_drop(pos: Vector2) -> void:
	var drop: WeaponDrop = WEAPON_DROP_SCENE.instantiate()
	var weapon_script: GDScript = _weapon_scripts[randi() % _weapon_scripts.size()]
	drop.weapon = weapon_script.new()
	get_parent().add_child(drop)
	drop.global_position = pos


func _spawn_modifier_drop(pos: Vector2) -> void:
	var drop: ModifierDrop = MODIFIER_DROP_SCENE.instantiate()
	var modifier_script: GDScript = _modifier_scripts[randi() % _modifier_scripts.size()]
	drop.modifier = modifier_script.new()
	get_parent().add_child(drop)
	drop.global_position = pos


func _spawn_dummy_enemy(pos: Vector2) -> void:
	var enemy: CharacterBody2D = DUMMY_ENEMY_SCENE.instantiate()
	get_parent().add_child(enemy)
	enemy.global_position = pos


func _spawn_gold_drop(pos: Vector2) -> void:
	var drop: GoldDrop = GOLD_DROP_SCENE.instantiate()
	drop.set_amount(10)
	get_parent().add_child(drop)
	drop.global_position = pos


func _open_test_shop() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		return
	var shop: ShopUI = SHOP_UI_SCENE.instantiate()
	get_parent().add_child(shop)
	var offerings: Array[ShopOffer] = [
		ShopOfferScript.new(LavaEmitterModifierScript.new(), 50),
	]
	shop.open(offerings)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_G:
			var viewport := get_viewport()
			var camera := viewport.get_camera_2d()
			if camera == null:
				return
			var screen_pos := viewport.get_mouse_position()
			var view_size := viewport.get_visible_rect().size
			var world_pos := (screen_pos - view_size * 0.5) / camera.zoom + camera.global_position
			_spawn_gold_drop(world_pos)
		KEY_H:
			var viewport := get_viewport()
			var camera := viewport.get_camera_2d()
			if camera == null:
				return
			var screen_pos := viewport.get_mouse_position()
			var view_size := viewport.get_visible_rect().size
			var world_pos := (screen_pos - view_size * 0.5) / camera.zoom + camera.global_position
			_spawn_dummy_enemy(world_pos)
		KEY_U:
			_open_test_shop()
