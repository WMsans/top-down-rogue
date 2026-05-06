class_name Projectile
extends Area2D

@export var damage: float = 0.0
@export var speed: float = 200.0
@export var lifetime: float = 3.0
@export var is_enemy_projectile: bool = false
var direction: Vector2 = Vector2.RIGHT
var source_node: Node2D = null

var _age: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	global_position += direction * speed * delta
	var sprite := get_node_or_null("Sprite2D")
	if sprite:
		sprite.rotation = direction.angle() + PI * 3.0 / 4.0


func _on_body_entered(body: Node) -> void:
	_handle_hit(body)


func _on_area_entered(area: Area2D) -> void:
	_handle_hit(area)


func _handle_hit(target: Node) -> void:
	if is_enemy_projectile:
		if target.is_in_group("player"):
			if target.has_method("on_hit_impact"):
				target.on_hit_impact(global_position, direction, int(damage))
			queue_free()
	else:
		if target.is_in_group("attackable"):
			if target != source_node and target.has_method("on_hit_impact"):
				target.on_hit_impact(global_position, direction, int(damage))
				queue_free()
