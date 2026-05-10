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


func play_impact(world_pos: Vector2, material_id: int, intensity: float) -> void:
	var data: Dictionary = impact_data.get(material_id, {})
	if data.is_empty():
		return
	var color: Color = data.get("particle_color", Color(0.5, 0.5, 0.5))
	var count: int = maxi(1, int(data.get("particle_count", 6) * intensity))
	for _i in range(count):
		var particle := ColorRect.new()
		particle.color = color
		particle.size = Vector2(2, 2)
		particle.position = world_pos + Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
		particle.z_index = 100
		add_child(particle)
		var tween := create_tween()
		var target_pos := particle.position + Vector2(randf_range(-20.0, 20.0), randf_range(-20.0, 20.0))
		tween.tween_property(particle, "position", target_pos, randf_range(0.15, 0.35))
		tween.parallel().tween_property(particle, "modulate:a", 0.0, randf_range(0.15, 0.35))
		tween.tween_callback(particle.queue_free)
