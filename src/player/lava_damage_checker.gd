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
	if _terrain_physical == null:
		return
	var player := get_parent()
	var health_component := player.get_node_or_null("HealthComponent")
	if health_component and health_component.is_dead():
		return

	var total_damage := 0
	var pos: Vector2 = player.position
	var half_w := BODY_WIDTH / 2.0
	var half_h := BODY_HEIGHT / 2.0

	for ix in range(SAMPLE_POINTS_X):
		for iy in range(SAMPLE_POINTS_Y):
			var sample_x := int(round(pos.x - half_w + float(ix) * BODY_WIDTH / float(SAMPLE_POINTS_X - 1)))
			var sample_y := int(round(pos.y - half_h + float(iy) * BODY_HEIGHT / float(SAMPLE_POINTS_Y - 1)))
			var cell: TerrainCell = _terrain_physical.query(Vector2(sample_x, sample_y))
			total_damage += int(cell.damage)

	if total_damage > 0 and health_component:
		health_component.take_damage(total_damage)
