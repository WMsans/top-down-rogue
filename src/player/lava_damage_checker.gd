class_name LavaDamageChecker
extends Node

const BODY_WIDTH := 8
const BODY_HEIGHT := 12
const SAMPLE_POINTS_X := 3
const SAMPLE_POINTS_Y := 3

var _terrain_physical: Node


func _ready() -> void:
	var player := get_parent()
	var wm := player.get_parent().get_node_or_null("WorldManager")
	if wm:
		_terrain_physical = wm.get_node_or_null("TerrainPhysical")


func _physics_process(_delta: float) -> void:
	# Lava/fire damage is now handled as the On Fire status via StatusComponent.
	# This checker is retained as a no-op for any future non-fire terrain hazards.
	pass
