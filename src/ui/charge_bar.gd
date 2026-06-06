class_name ChargeBar
extends Node2D

const BAR_WIDTH := 18.0
const BAR_HEIGHT := 3.0
const ANCHOR := Vector2(0.0, -9.0)
const BG_COLOR := Color(0.08, 0.08, 0.08, 0.85)
const FILL_COLOR := Color(0.95, 0.7, 0.2, 1.0)
const FULL_COLOR := Color(1.0, 0.88, 0.35, 1.0)
const JITTER_PX := 1.0
const Z := 79

var _ratio: float = 0.0


func _ready() -> void:
	z_index = Z
	z_as_relative = false
	position = ANCHOR
	visible = false


func set_active(on: bool) -> void:
	visible = on
	if not on:
		position = ANCHOR


func set_ratio(r: float) -> void:
	_ratio = clampf(r, 0.0, 1.0)
	if _ratio >= 1.0:
		position = ANCHOR + Vector2(
			randf_range(-JITTER_PX, JITTER_PX),
			randf_range(-JITTER_PX, JITTER_PX))
	else:
		position = ANCHOR
	queue_redraw()


func _draw() -> void:
	var origin := Vector2(-BAR_WIDTH * 0.5, -BAR_HEIGHT * 0.5)
	draw_rect(Rect2(origin, Vector2(BAR_WIDTH, BAR_HEIGHT)), BG_COLOR)
	var fill_w := BAR_WIDTH * _ratio
	var color := FULL_COLOR if _ratio >= 1.0 else FILL_COLOR
	draw_rect(Rect2(origin, Vector2(fill_w, BAR_HEIGHT)), color)
