class_name AiDebugOverlay
extends Node2D

## World-space view of the encounter director for tuning enemy AI:
## token holders (red ring), ring slots (yellow dots), firing spots (cyan
## crosses), predicted aim points (blue line + circle).

const TOKEN_COLOR := Color(1.0, 0.2, 0.2, 0.9)
const SLOT_COLOR := Color(1.0, 0.9, 0.2, 0.9)
const SPOT_COLOR := Color(0.2, 1.0, 1.0, 0.9)
const AIM_COLOR := Color(0.3, 0.6, 1.0, 0.6)

var director = null


func _ready() -> void:
	top_level = true
	z_index = 4096


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if director == null:
		return
	for e in director.get_token_holders():
		draw_arc(e.global_position, 12.0, 0.0, TAU, 24, TOKEN_COLOR, 1.5)
	for slot in director.get_ring_slots():
		if slot != Vector2.INF:
			draw_circle(slot, 2.5, SLOT_COLOR)
	for spot in director.get_taken_spots(null):
		draw_line(spot + Vector2(-4, -4), spot + Vector2(4, 4), SPOT_COLOR, 1.5)
		draw_line(spot + Vector2(-4, 4), spot + Vector2(4, -4), SPOT_COLOR, 1.5)
	for e in get_tree().get_nodes_in_group("attackable"):
		if not ("_debug_aim_point" in e) or e._debug_aim_point == Vector2.INF:
			continue
		draw_line(e.global_position, e._debug_aim_point, AIM_COLOR, 1.0)
		draw_arc(e._debug_aim_point, 3.0, 0.0, TAU, 12, AIM_COLOR, 1.0)
