class_name TerrainCell
extends Resource

var material_id: int = 0
var is_solid: bool = false
var is_fluid: bool = false
var damage: float = 0.0

func _init(p_material_id: int = 0, p_is_solid: bool = false, p_is_fluid: bool = false, p_damage: float = 0.0) -> void:
	material_id = p_material_id
	is_solid = p_is_solid
	is_fluid = p_is_fluid
	damage = p_damage
