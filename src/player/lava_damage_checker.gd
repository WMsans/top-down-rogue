class_name LavaDamageChecker
extends Node

const BODY_WIDTH := 8
const BODY_HEIGHT := 12
const SAMPLE_POINTS_X := 3
const SAMPLE_POINTS_Y := 3

var _health_component: HealthComponent
var _shadow_grid: ShadowGrid


func _ready() -> void:
	var player := get_parent()
	_health_component = player.get_node("HealthComponent")


func _physics_process(_delta: float) -> void:
	if _health_component.is_dead():
		return
	if _shadow_grid == null:
		_shadow_grid = get_parent().shadow_grid
		if _shadow_grid == null:
			return

	var total_damage := 0
	var pos: Vector2 = get_parent().position
	var half_w := BODY_WIDTH / 2.0
	var half_h := BODY_HEIGHT / 2.0

	for ix in range(SAMPLE_POINTS_X):
		for iy in range(SAMPLE_POINTS_Y):
			var sample_x := int(round(pos.x - half_w + float(ix) * BODY_WIDTH / float(SAMPLE_POINTS_X - 1)))
			var sample_y := int(round(pos.y - half_h + float(iy) * BODY_HEIGHT / float(SAMPLE_POINTS_Y - 1)))
			var material_id := _shadow_grid.get_material(sample_x, sample_y)
			total_damage += MaterialRegistry.get_damage(material_id)

	if total_damage > 0:
		_health_component.take_damage(total_damage)
