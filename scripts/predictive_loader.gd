class_name PredictiveLoader
extends RefCounted

var position_history: Array = []
var history_size: int = 10
var chunks_ahead: int = 1

func update(player_pos: Vector2) -> void:
	position_history.append(player_pos)
	if position_history.size() > history_size:
		position_history.pop_front()

func get_predicted_chunks(current_view: Array[Vector2i], player_pos: Vector2) -> Array[Vector2i]:
	if position_history.size() < 3:
		return []
	
	var velocity := _calculate_velocity()
	if velocity.length() < 10.0:
		return []
	
	var predicted_coords: Array[Vector2i] = []
	var direction := velocity.normalized()
	
	for i in range(1, chunks_ahead + 1):
		var future_pos := player_pos + direction * (256.0 * float(i))
		var chunk_coord := Vector2i(
			floori(future_pos.x / 256.0),
			floori(future_pos.y / 256.0)
		)
		var is_new := true
		for existing in current_view:
			if existing == chunk_coord:
				is_new = false
				break
		if is_new:
			predicted_coords.append(chunk_coord)
	
	return predicted_coords

func _calculate_velocity() -> Vector2:
	if position_history.size() < 2:
		return Vector2.ZERO
	
	var recent := position_history.slice(-min(5, position_history.size()))
	if recent.size() < 2:
		return Vector2.ZERO
	
	var total_velocity := Vector2.ZERO
	for i in range(1, recent.size()):
		total_velocity += recent[i] - recent[i - 1]
	
	return total_velocity / float(recent.size() - 1)