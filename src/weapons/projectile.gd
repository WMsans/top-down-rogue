class_name Projectile
extends Area2D

@export var damage: float = 0.0
@export var speed: float = 120.0
@export var lifetime: float = 3.0
@export var is_enemy_projectile: bool = false
var direction: Vector2 = Vector2.RIGHT
var source_node: Node2D = null

var _age: float = 0.0


func _ready() -> void:
	add_to_group("projectile")
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
		elif target is StaticBody2D:
			_carve_terrain()
			queue_free()
	else:
		if target.is_in_group("attackable"):
			if target != source_node and target.has_method("on_hit_impact"):
				target.on_hit_impact(global_position, direction, int(damage))
				queue_free()
		elif target is StaticBody2D:
			_carve_terrain()
			queue_free()


func _carve_terrain() -> void:
	var solids: Array[int] = [
		MaterialRegistry.MAT_DIRT,
		MaterialRegistry.MAT_WOOD,
		MaterialRegistry.MAT_STONE,
		MaterialRegistry.MAT_COAL,
		MaterialRegistry.MAT_ICE,
	]
	var impacts: Array = TerrainSurface.clear_and_push_materials_in_arc(
		global_position, direction, 3.0, TAU, 0.0, 0.0, solids, damage
	)
	for impact in impacts:
		TerrainImpact.play_impact(impact["world_pos"], impact["material_id"], impact["scale"])
