class_name InteractableShrine
extends Area2D

## Base for diegetic risk/reward interactables. PickupContext highlights it and shows
## its info card; pressing interact fires _on_interact(player) exactly once, then the
## shrine is consumed. Subclasses override _on_interact.

const DETECTION_RADIUS: float = 20.0

@export var title: String = ""
@export_multiline var body: String = ""

var consumed: bool = false


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	var shape := CircleShape2D.new()
	shape.radius = DETECTION_RADIUS
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)


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
	card.populate(null, title, lines, [])


func interact(player: Node) -> void:
	if consumed:
		return
	consumed = true
	_on_interact(player)


func _on_interact(_player) -> void:
	pass
