class_name ExplosiveBarrel
extends StaticBody2D

@export var explosion_power: int = 120
@export var max_health: int = 1

var health: int


func _ready() -> void:
	health = max_health
	add_to_group("destructible_prop")


func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		_detonate()


func _detonate() -> void:
	var wm := get_tree().get_first_node_in_group("world_manager")
	if wm and wm.has_method("place_material_with_temp"):
		wm.place_material_with_temp(global_position, 1.0, MaterialRegistry.MAT_EXPLODE_WAVE, explosion_power)
	queue_free()
