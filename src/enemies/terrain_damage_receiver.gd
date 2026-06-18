class_name TerrainDamageReceiver
extends Node

const BODY_RADIUS := 8.0
const SAMPLE_POINTS_X := 3
const SAMPLE_POINTS_Y := 3

var _terrain_physical: Node


func _ready() -> void:
	var wm := get_tree().get_first_node_in_group("world_manager")
	if wm:
		_terrain_physical = wm.get_node_or_null("TerrainPhysical")


func _physics_process(_delta: float) -> void:
	# Lava/fire damage is now handled as the On Fire status via StatusComponent.
	pass
