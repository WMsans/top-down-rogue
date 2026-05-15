class_name OilBarrel
extends StaticBody2D

@export var max_health: int = 2
@export var oil_radius: float = 3.0
@export var explosion_power: int = 60

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
	if wm:
		if wm.has_method("place_material"):
			wm.place_material(global_position, oil_radius, MaterialRegistry.MAT_OIL)
		if wm.has_method("place_material_with_temp"):
			wm.place_material_with_temp(global_position, 1.0, MaterialRegistry.MAT_EXPLODE_WAVE, explosion_power)
	queue_free()
