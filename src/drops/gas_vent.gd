class_name GasVent
extends StaticBody2D

@export var emission_interval: float = 3.0
@export var gas_radius: float = 2.0
@export var gas_density: int = 100

var _timer: float = 0.0


func _ready() -> void:
	add_to_group("destructible_prop")
	_timer = randf() * emission_interval


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = emission_interval
		_emit_gas()


func _emit_gas() -> void:
	var wm := get_tree().get_first_node_in_group("world_manager")
	if wm and wm.has_method("place_gas"):
		wm.place_gas(global_position, gas_radius, gas_density, Vector2i.ZERO)
