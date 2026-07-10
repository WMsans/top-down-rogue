class_name RoomSign
extends Area2D

## A readable in-world sign. Standing near it shows the room's risk/reward in the
## shared WeaponInfoPopup (via PickupContext). Informational only — no interact().

const DETECTION_RADIUS: float = 20.0

@export var title: String = ""
@export_multiline var body: String = ""


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
