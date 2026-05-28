extends Node

var impact_data: Dictionary = {}


func _ready() -> void:
	impact_data = {
		MaterialRegistry.MAT_DIRT: {
			"particle_color": Color(0.45, 0.32, 0.18),
			"particle_count": 6,
		},
		MaterialRegistry.MAT_WOOD: {
			"particle_color": Color(0.55, 0.42, 0.25),
			"particle_count": 8,
		},
		MaterialRegistry.MAT_COAL: {
			"particle_color": Color(0.12, 0.12, 0.14),
			"particle_count": 8,
		},
		MaterialRegistry.MAT_ICE: {
			"particle_color": Color(0.7, 0.85, 0.95),
			"particle_count": 10,
		},
		MaterialRegistry.MAT_STONE: {
			"particle_color": Color(0.5, 0.5, 0.5),
			"particle_count": 6,
		},
	}


var _PARTICLE_POLY := PackedVector2Array([
	Vector2(-1.5, -1.5), Vector2(1.5, -1.5), Vector2(1.5, 1.5), Vector2(-1.5, 1.5)
])


func play_impact(world_pos: Vector2, material_id: int, intensity: float, parent: Node2D) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var data: Dictionary = impact_data.get(material_id, {})
	if data.is_empty():
		return
	var color: Color = data.get("particle_color", Color(0.5, 0.5, 0.5))
	var count: int = maxi(1, int(data.get("particle_count", 6) * intensity))
	# One parallel tween per impact instead of one per particle — avoids
	# allocating N Tween objects when bursting many impacts in a frame.
	var tween := create_tween().set_parallel(true)
	for _i in range(count):
		# Node2D (not Control) so the particle lives in the world's canvas
		# transform and is moved by the Camera2D, instead of screen space.
		var particle := Polygon2D.new()
		particle.polygon = _PARTICLE_POLY
		particle.color = color
		particle.z_index = 100
		particle.global_position = world_pos + Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
		parent.add_child(particle)
		var dir := Vector2.from_angle(randf() * TAU)
		var target_pos := particle.global_position + dir * randf_range(12.0, 28.0)
		var dur := randf_range(0.2, 0.45)
		tween.tween_property(particle, "global_position", target_pos, dur).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tween.tween_property(particle, "modulate:a", 0.0, dur)
		tween.tween_callback(particle.queue_free).set_delay(dur)
