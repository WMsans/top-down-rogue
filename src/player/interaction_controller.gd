class_name InteractionController
extends Node

var _player: CharacterBody2D = null
var _nearby_interactables: Array[Interactable] = []
var _highlighted_interactable: Interactable = null
var _detection_area: Area2D = null


func _ready() -> void:
	_player = get_parent() as CharacterBody2D
	_detection_area = Area2D.new()
	_detection_area.name = "DetectionArea"
	
	var shape := CircleShape2D.new()
	shape.radius = 32.0
	var collision_shape := CollisionShape2D.new()
	collision_shape.shape = shape
	_detection_area.add_child(collision_shape)
	_detection_area.collision_mask = 2
	_detection_area.monitoring = true
	
	add_child(_detection_area)
	
	_detection_area.body_entered.connect(_on_body_entered)
	_detection_area.body_exited.connect(_on_body_exited)


func _process(_delta: float) -> void:
	var closest := _find_closest_interactable()
	if _highlighted_interactable != closest:
		if _highlighted_interactable:
			_highlighted_interactable.set_highlighted(false)
		_highlighted_interactable = closest
		if _highlighted_interactable:
			_highlighted_interactable.set_highlighted(true)


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event.is_action_pressed("interact") and _highlighted_interactable:
		_highlighted_interactable.interact(_player)
		get_viewport().set_input_as_handled()


func _on_body_entered(body: Node2D) -> void:
	var interactable := _find_interactable(body)
	if interactable:
		_nearby_interactables.append(interactable)


func _on_body_exited(body: Node2D) -> void:
	var interactable := _find_interactable(body)
	if interactable:
		_nearby_interactables.erase(interactable)
		if _highlighted_interactable == interactable:
			_highlighted_interactable.set_highlighted(false)
			_highlighted_interactable = null


func _find_interactable(node: Node) -> Interactable:
	for child in node.get_children():
		if child is Interactable:
			return child
	return null


func _find_closest_interactable() -> Interactable:
	var closest: Interactable = null
	var closest_dist: float = INF
	var player_pos: Vector2 = _player.global_position
	for interactable in _nearby_interactables:
		if not is_instance_valid(interactable):
			_nearby_interactables.erase(interactable)
			continue
		var dist: float = interactable.get_parent().global_position.distance_to(player_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = interactable
	return closest