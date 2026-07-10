class_name InteractableShrine
extends Area2D

## Base for diegetic risk/reward interactables. PickupContext highlights it and shows
## its info card; pressing interact fires _on_interact(player) exactly once, then the
## shrine is consumed. Subclasses override _on_interact and set title/body/icon.

const DETECTION_RADIUS: float = 20.0
const CHEST_SCENE := preload("res://scenes/chest.tscn")
const MELEE_SCENE := preload("res://scenes/enemies/melee_enemy.tscn")

@export var title: String = ""
@export_multiline var body: String = ""
@export var icon: Texture2D = null

var consumed: bool = false


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	var shape := CircleShape2D.new()
	shape.radius = DETECTION_RADIUS
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)
	if icon != null:
		var spr := Sprite2D.new()
		spr.texture = icon
		add_child(spr)


func get_pickup_type() -> int:
	return Drop.PickupType.PORTAL


func should_auto_pickup() -> bool:
	return false


func set_highlighted(enabled: bool) -> void:
	modulate = Color(1.3, 1.3, 1.0) if enabled else Color.WHITE


func populate_info_card(card: Card) -> void:
	var lines: Array[String] = []
	for line in body.split("\n", false):
		lines.append(line)
	card.populate(icon, title, lines, [])


func interact(player: Node) -> void:
	if consumed:
		return
	consumed = true
	_on_interact(player)


func _on_interact(_player) -> void:
	pass


# --- Shared helpers for subclasses ---

func _inventory(player: Node) -> Node:
	if player == null:
		return null
	return player.get_node_or_null("PlayerInventory")


func _spawn_chest_here(tier: int) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var chest := CHEST_SCENE.instantiate()
	if "tier" in chest:
		chest.tier = tier
	parent.add_child(chest)
	chest.global_position = global_position


func _spawn_melee(count: int, spread: float, elite: bool) -> Array:
	var out: Array = []
	var parent := get_parent()
	if parent == null:
		return out
	for _i in count:
		var e := MELEE_SCENE.instantiate()
		if elite and "is_elite" in e:
			e.is_elite = true
		var off := Vector2(randf_range(-spread, spread), randf_range(-spread, spread))
		parent.add_child(e)
		e.global_position = global_position + off
		e.add_to_group("cave_spawned")
		out.append(e)
	return out
