class_name LightningArcFX
extends Node2D

const SEGMENTS := 7
const JITTER := 6.0
const LIFETIME := 0.15

var _points: PackedVector2Array = PackedVector2Array()
var _end: Vector2 = Vector2.ZERO
var _tint: Color = Color(0.9, 0.95, 1.0)


static func play(host: Node, from: Vector2, to: Vector2, tint: Color) -> void:
	if host == null:
		return
	var fx := LightningArcFX.new()
	host.add_child(fx)
	fx.global_position = from
	fx._setup(to - from, tint)


func _setup(delta: Vector2, tint: Color) -> void:
	_tint = tint
	_end = delta
	_build_points(delta)
	queue_redraw()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, LIFETIME)
	tw.tween_callback(queue_free)


func _build_points(delta: Vector2) -> void:
	_points = PackedVector2Array()
	var perp := Vector2(-delta.y, delta.x).normalized()
	for i in range(SEGMENTS + 1):
		var t := float(i) / float(SEGMENTS)
		var base := delta * t
		var off := 0.0
		if i != 0 and i != SEGMENTS:
			off = randf_range(-JITTER, JITTER)
		_points.append(base + perp * off)


func _draw() -> void:
	if _points.size() >= 2:
		draw_polyline(_points, Color(_tint.r, _tint.g, _tint.b, 0.35), 3.0)
		draw_polyline(_points, _tint, 1.0)
	draw_circle(_end, 3.0, _tint)
	for i in range(4):
		var a := PI * 0.5 * float(i) + PI * 0.25
		draw_line(_end, _end + Vector2(cos(a), sin(a)) * 6.0, _tint, 1.0)
