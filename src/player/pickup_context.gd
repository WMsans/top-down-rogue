class_name PickupContext
extends Node

const DETECTION_RADIUS: float = 12.0

var _player: CharacterBody2D
var _detection_area: Area2D
var _nearby_pickups: Array[Node2D] = []
var _highlighted: Node2D = null


func _ready() -> void:
	_player = get_parent() as CharacterBody2D
	_detection_area = Area2D.new()
	_detection_area.name = "DetectionArea"
	var shape := CircleShape2D.new()
	shape.radius = DETECTION_RADIUS
	var collision_shape := CollisionShape2D.new()
	collision_shape.shape = shape
	_detection_area.add_child(collision_shape)
	_detection_area.collision_mask = 2
	_detection_area.monitoring = true
	_detection_area.body_entered.connect(_on_body_entered)
	_detection_area.body_exited.connect(_on_body_exited)
	_player.add_child.call_deferred(_detection_area)


func _process(_delta: float) -> void:
	var closest := _find_closest_pickup()
	if _highlighted != closest:
		if _highlighted and is_instance_valid(_highlighted) and _highlighted.has_method("set_highlighted"):
			_highlighted.set_highlighted(false)
		_highlighted = closest
		if _highlighted and _highlighted.has_method("set_highlighted"):
			_highlighted.set_highlighted(true)


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event.is_action_pressed("interact") and _highlighted:
		if _highlighted.has_method("interact"):
			_highlighted.interact(_player)
		get_viewport().set_input_as_handled()


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("get_pickup_type") and body.has_method("should_auto_pickup"):
		if body.should_auto_pickup():
			return
		if not _nearby_pickups.has(body):
			_nearby_pickups.append(body)


func _on_body_exited(body: Node2D) -> void:
	_nearby_pickups.erase(body)
	if _highlighted == body:
		if _highlighted and is_instance_valid(_highlighted) and _highlighted.has_method("set_highlighted"):
			_highlighted.set_highlighted(false)
		_highlighted = null


func _find_closest_pickup() -> Node2D:
	var closest: Node2D = null
	var closest_dist: float = INF
	var player_pos: Vector2 = _player.global_position
	for pickup in _nearby_pickups:
		if not is_instance_valid(pickup):
			_nearby_pickups.erase(pickup)
			continue
		var dist: float = pickup.global_position.distance_to(player_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = pickup
	return closest
