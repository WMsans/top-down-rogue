class_name Chest
extends StaticBody2D

const CHEST_CLOSED_TEXTURE := preload("res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/32x32/gift_01a.png")
const CHEST_OPEN_TEXTURE := preload("res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/32x32/giftopen_01a.png")
const CHOICE_COUNT := 3

@export var tier: int = DropTable.ItemTier.COMMON

var _weapons: Array[Weapon] = []
var _opened: bool = false
var _looted: bool = false
var _chest_ui: CanvasLayer = null

@onready var _sprite: Sprite2D = $Sprite2D


func get_pickup_type() -> int:
	return Drop.PickupType.CHEST


func get_pickup_payload():
	return null


func should_auto_pickup() -> bool:
	return false


func _ready() -> void:
	collision_layer = 3
	collision_mask = 1
	_sprite.texture = CHEST_CLOSED_TEXTURE


func interact(_player: Node) -> void:
	if _opened or _looted:
		return
	_opened = true
	_sprite.texture = CHEST_OPEN_TEXTURE
	set_collision_layer_value(1, false)
	set_collision_layer_value(2, false)
	_generate_weapons()
	_open_chest_ui()


func set_highlighted(enabled: bool) -> void:
	if _looted:
		return
	if _sprite and _sprite.material is ShaderMaterial:
		(_sprite.material as ShaderMaterial).set_shader_parameter("outline_width", 1.0 if enabled else 0.0)


func _generate_weapons() -> void:
	_weapons.clear()
	var seen_scripts: Dictionary = {}
	for i in CHOICE_COUNT:
		var weapon: Weapon = null
		for _attempt in range(5):
			var candidate: Weapon = WeaponRegistry.get_random_weapon(tier)
			if candidate == null:
				continue
			var script_key = candidate.get_script()
			if script_key == null:
				script_key = candidate
			if not seen_scripts.has(script_key):
				seen_scripts[script_key] = true
				weapon = candidate
				break
		if weapon == null:
			weapon = WeaponRegistry.get_random_weapon(tier)
		if weapon != null:
			_weapons.append(weapon)


func _open_chest_ui() -> void:
	if _weapons.is_empty():
		_close_chest()
		return
	var root := get_tree().current_scene
	if root == null:
		_close_chest()
		return
	var ui := _get_or_create_chest_ui(root)
	if ui == null:
		_close_chest()
		return
	ui.open_with_weapons(_weapons, _on_weapon_chosen)


func _close_chest() -> void:
	_opened = false
	_sprite.texture = CHEST_CLOSED_TEXTURE
	set_collision_layer_value(1, true)
	set_collision_layer_value(2, true)


func _mark_looted() -> void:
	_looted = true
	_opened = true
	_sprite.texture = CHEST_OPEN_TEXTURE
	set_collision_layer_value(1, true)
	set_collision_layer_value(2, false)
	set_highlighted(false)


func _get_or_create_chest_ui(root: Node) -> CanvasLayer:
	if _chest_ui and is_instance_valid(_chest_ui):
		return _chest_ui
	var existing := root.get_node_or_null("ChestUI")
	if existing:
		_chest_ui = existing as CanvasLayer
		return _chest_ui
	var scene: PackedScene = preload("res://scenes/ui/chest_ui.tscn")
	var instance := scene.instantiate()
	root.add_child(instance)
	_chest_ui = instance as CanvasLayer
	return _chest_ui


func _on_weapon_chosen(weapon: Weapon) -> void:
	if weapon == null:
		_close_chest()
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		_mark_looted()
		return
	var delivery: WeaponDelivery = player.get_node_or_null("WeaponDelivery")
	if delivery == null:
		_mark_looted()
		return
	var spec := WeaponOfferSpec.new()
	spec.type = WeaponOfferSpec.OfferType.WEAPON
	spec.weapon = weapon
	delivery.offer(spec, _on_delivery_result)


func _on_delivery_result(_accepted: bool, _slot: int) -> void:
	_mark_looted()