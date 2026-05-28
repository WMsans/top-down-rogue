class_name FeatureLanternCluster
extends ArenaFeature

@export var lanterns: Array[LanternSpec] = []

func apply(ctx) -> void:
	for spec in lanterns:
		if spec == null or spec.prop_scene == null:
			continue
		var inst: Node2D = spec.prop_scene.instantiate()
		var light := inst.get_node_or_null("Light") as PointLight2D
		if light != null:
			light.color = spec.light_color
			light.energy = spec.light_energy
			light.texture_scale = max(spec.light_radius / 64.0, 0.1)
			inst.set_meta("flicker_base_energy", spec.light_energy)
			inst.set_meta("flicker_amplitude", spec.flicker_amplitude)
		ctx.dispatcher.spawn_node(inst, ctx.anchor_world_pos + spec.offset)
