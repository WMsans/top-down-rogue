class_name DummyEnemy
extends Enemy

const GOLD_DROP_SCENE := preload("res://scenes/gold_drop.tscn")
const WEAPON_DROP_SCENE := preload("res://scenes/weapon_drop.tscn")
const TestWeaponScript := preload("res://src/weapons/test_weapon.gd")
const MeleeWeaponScript := preload("res://src/weapons/melee_weapon.gd")
const LavaEmitterModifierScript := preload("res://src/weapons/lava_emitter_modifier.gd")

var _player: Node = null


func _ready() -> void:
	super._ready()
	_sprite_modulate_green()
	_setup_drop_table()
	_player = get_tree().get_first_node_in_group("player")


func _sprite_modulate_green() -> void:
	var sprite := get_node_or_null("Sprite2D")
	if sprite:
		sprite.modulate = Color(0.2, 0.8, 0.2)


func _setup_drop_table() -> void:
	drop_table = DropTable.new()
	var weapon_drop_entry := DropTable.DropEntry.new(WEAPON_DROP_SCENE, 1.0, 1, 1)
	drop_table.add_entry(weapon_drop_entry)
	var gold_entry := DropTable.DropEntry.new(GOLD_DROP_SCENE, 1.0, 2, 5, 5)
	drop_table.add_entry(gold_entry)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var dir := _player.global_position - global_position
	if dir.length() < 4.0:
		return
	global_position += dir.normalized() * speed * delta


func _on_hit() -> void:
	var sprite := get_node_or_null("Sprite2D")
	if sprite == null:
		return
	sprite.modulate = Color.WHITE
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(0.2, 0.8, 0.2), 0.15)
