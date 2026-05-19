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
	if _terrain_physical == null:
		return
	var enemy := get_parent()
	if not enemy.has_method("hit"):
		return
	if enemy.get("health") <= 0:
		return

	var total_damage := 0
	var pos: Vector2 = enemy.position

	for ix in range(SAMPLE_POINTS_X):
		for iy in range(SAMPLE_POINTS_Y):
			var sample_x := int(round(pos.x - BODY_RADIUS + float(ix) * BODY_RADIUS * 2.0 / float(SAMPLE_POINTS_X - 1)))
			var sample_y := int(round(pos.y - BODY_RADIUS + float(iy) * BODY_RADIUS * 2.0 / float(SAMPLE_POINTS_Y - 1)))
			var cell: TerrainCell = _terrain_physical.query(Vector2(sample_x, sample_y))
			total_damage = max(total_damage, int(cell.damage))

	if total_damage > 0:
		enemy.hit(total_damage)
