extends Node

const HIT_STOP_BASE: float = 0.06
const HIT_STOP_KILL_BONUS: float = 0.04

var _active_timer: SceneTreeTimer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func stop(duration: float) -> void:
	if duration <= 0.0:
		return
	Engine.time_scale = 0.0
	_active_timer = get_tree().create_timer(duration, true, false, true)
	var my_timer := _active_timer
	await my_timer.timeout
	if _active_timer == my_timer:
		Engine.time_scale = 1.0
		_active_timer = null
