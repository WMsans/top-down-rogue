class_name ReturnBehavior
extends ProjectileBehavior

var out_time: float = 0.5
var return_catch_radius: float = 14.0
var _elapsed: float = 0.0
var _returning: bool = false
var _source: Node2D = null


func on_spawn(proj) -> void:
	_elapsed = 0.0
	_returning = false
	if proj.source_node is Node2D:
		_source = proj.source_node


func on_process(proj, delta: float) -> void:
	_elapsed += delta
	if not _returning:
		if _elapsed >= out_time:
			_returning = true
		return
	if _source == null or not is_instance_valid(_source):
		return
	var to_src: Vector2 = _source.global_position - proj.global_position
	if to_src.length() <= return_catch_radius:
		proj.queue_free()
		return
	proj.direction = to_src.normalized()


func on_enemy_hit(_proj, _target) -> bool:
	return true
