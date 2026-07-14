class_name Mine
extends Area2D

@export var blast_radius: float = 48.0
@export var blast_damage: int = 12
@export var arm_delay: float = 1.0
@export var timeout: float = 8.0

var _armed: bool = false
var _arming: bool = false
var _arm_remaining: float = 0.0
var _timeout_remaining: float = 0.0


func _ready() -> void:
	monitoring = true
	collision_layer = 0
	collision_mask = 1  # player / bodies
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func arm(delay: float = -1.0) -> void:
	_arming = true
	_arm_remaining = delay if delay >= 0.0 else arm_delay


func _skip_arm_for_test() -> void:
	_armed = true


func begin_timeout() -> void:
	_timeout_remaining = timeout


func is_armed() -> bool:
	return _armed


func _process(delta: float) -> void:
	if _arming and not _armed:
		_arm_remaining -= delta
		if _arm_remaining <= 0.0:
			_arming = false
			_armed = true
			begin_timeout()
	if _armed and _timeout_remaining > 0.0:
		_timeout_remaining -= delta
		if _timeout_remaining <= 0.0:
			_explode()


func _on_body_entered(_body: Node) -> void:
	if _armed:
		_explode()


func _explode() -> void:
	if not is_inside_tree():
		return
	var space := get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = blast_radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = 1
	var hits := space.intersect_shape(query)
	for hit in hits:
		var c = hit.collider
		if c and c.has_method("hit"):
			c.hit(blast_damage)
	queue_free()