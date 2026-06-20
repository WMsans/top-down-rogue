extends Control

const MinimapModel = preload("res://src/ui/minimap/minimap_model.gd")

var model
var player_world: Vector2 = Vector2.ZERO
var view_extent: Vector2 = Vector2(896, 896)
var player_facing: Vector2 = Vector2.DOWN

const COL_BOSS := Color(0.85, 0.20, 0.20)
const COL_SHOP := Color(0.95, 0.80, 0.20)
const COL_ELITE := Color(0.70, 0.30, 0.95)
const COL_PLAYER := Color(0.90, 0.95, 1.0)


func _poi_color(t: int) -> Color:
	match t:
		MinimapModel.POI_BOSS: return COL_BOSS
		MinimapModel.POI_SHOP: return COL_SHOP
		MinimapModel.POI_ELITE: return COL_ELITE
	return Color.WHITE


func _world_to_widget(rel: Vector2) -> Vector2:
	var half := size * 0.5
	return half + Vector2(rel.x / view_extent.x, rel.y / view_extent.y) * half


func _clamp_to_edge(rel: Vector2) -> Vector2:
	var sx := view_extent.x / max(abs(rel.x), 0.001)
	var sy := view_extent.y / max(abs(rel.y), 0.001)
	var s: float = min(sx, sy) * 0.92
	return _world_to_widget(rel * s)


func _draw_arrow(pos: Vector2, angle: float, col: Color, length: float = 6.0) -> void:
	var dir := Vector2.RIGHT.rotated(angle)
	var perp := dir.orthogonal()
	var tip := pos + dir * length
	var a := pos - dir * length * 0.5 + perp * length * 0.6
	var b := pos - dir * length * 0.5 - perp * length * 0.6
	draw_colored_polygon(PackedVector2Array([tip, a, b]), col)


func _draw() -> void:
	if model == null:
		return
	for poi in model.get_pois():
		var wp: Vector2 = poi["world_pos"]
		var rel := wp - player_world
		var inside: bool = abs(rel.x) <= view_extent.x and abs(rel.y) <= view_extent.y
		var col := _poi_color(poi["type"])
		if inside:
			if poi["always_visible"] or model.is_revealed_world(wp):
				draw_circle(_world_to_widget(rel), 3.0, col)
		elif poi["always_visible"]:
			_draw_arrow(_clamp_to_edge(rel), rel.angle(), col, 7.0)
	_draw_arrow(size * 0.5, player_facing.angle(), COL_PLAYER, 6.0)
