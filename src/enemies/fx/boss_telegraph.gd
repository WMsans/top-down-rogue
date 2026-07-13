class_name BossTelegraph
extends RefCounted

# Purely-visual telegraph primitives for boss attacks. Each factory returns a
# Node2D the caller parents to the world layer; the node auto-queue_free()s at
# `duration` end. z_index 6 keeps them above gameplay sprites but below UI.
# Caller must pass a parent that is already in the scene tree.

const TELEGRAPH_Z := 6


static func ground_crack_line(parent: Node, start: Vector2, end: Vector2, duration: float) -> Node2D:
	var root := _make_root()
	root.global_position = start
	var line := Line2D.new()
	line.points = PackedVector2Array([Vector2.ZERO, end - start])
	line.width = 3.0
	line.default_color = Color(1.0, 0.85, 0.3, 0.8)
	line.z_index = TELEGRAPH_Z
	line.z_as_relative = false
	root.add_child(line)
	parent.add_child(root)
	var fade := root.create_tween()
	fade.tween_property(line, "default_color:a", 0.0, duration).set_trans(Tween.TRANS_LINEAR)
	_schedule_free(root, duration)
	return root


static func expanding_circle(parent: Node, center: Vector2, max_radius: float, duration: float) -> Node2D:
	var root := _make_root()
	root.global_position = center
	var p := _particles_outward(max_radius, duration, Color(1.0, 0.4, 0.3, 0.9))
	root.add_child(p)
	parent.add_child(root)
	_schedule_free(root, duration)
	return root


static func column_rise(parent: Node, base: Vector2, height: float, duration: float) -> Node2D:
	var root := _make_root()
	root.global_position = base
	var line := Line2D.new()
	line.points = PackedVector2Array([Vector2.ZERO, Vector2(0, -height)])
	line.width = 6.0
	line.default_color = Color(0.8, 0.8, 0.9, 0.8)
	line.z_index = TELEGRAPH_Z
	line.z_as_relative = false
	line.scale = Vector2(1.0, 0.0)
	root.add_child(line)
	parent.add_child(root)
	var grow := root.create_tween()
	grow.tween_property(line, "scale:y", 1.0, duration).set_trans(Tween.TRANS_CUBIC)
	_schedule_free(root, duration)
	return root


static func shockwave_ring(parent: Node, center: Vector2, max_radius: float, duration: float) -> Node2D:
	var root := _make_root()
	root.global_position = center
	var ring := Line2D.new()
	ring.points = _ring_points(max_radius, 24)
	ring.width = 4.0
	ring.default_color = Color(1.0, 1.0, 1.0, 0.9)
	ring.z_index = TELEGRAPH_Z
	ring.z_as_relative = false
	ring.scale = Vector2.ZERO
	root.add_child(ring)
	parent.add_child(root)
	var expand := root.create_tween()
	expand.tween_property(ring, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_LINEAR)
	var fade := root.create_tween()
	fade.tween_property(ring, "default_color:a", 0.0, duration).set_trans(Tween.TRANS_LINEAR)
	_schedule_free(root, duration)
	return root


static func converging_particles(parent: Node, target: Vector2, source_radius: float, duration: float, tint: Color) -> Node2D:
	var root := _make_root()
	root.global_position = target
	var p := GPUParticles2D.new()
	p.name = "Particles"
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 16
	p.lifetime = duration
	p.texture = EnemyVfxShared.soft_dot_texture()
	p.z_index = TELEGRAPH_Z
	p.z_as_relative = false
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.ZERO
	m.spread = 180.0
	m.gravity = Vector3.ZERO
	# Negative radial velocity → particles fly inward toward the target.
	m.initial_velocity_min = -source_radius / duration
	m.initial_velocity_max = -source_radius / duration
	m.scale_min = 0.4
	m.scale_max = 1.0
	m.color = tint
	m.color_ramp = EnemyVfxShared.fade_gradient(tint, Color(tint.r, tint.g, tint.b, 0.0))
	p.process_material = m
	root.add_child(p)
	parent.add_child(root)
	_schedule_free(root, duration)
	return root


# --- internals ---

static func _make_root() -> Node2D:
	var n := Node2D.new()
	n.z_index = TELEGRAPH_Z
	n.z_as_relative = false
	return n


static func _particles_outward(max_radius: float, duration: float, tint: Color) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = "ExpandingCircle"
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 24
	p.lifetime = duration
	p.texture = EnemyVfxShared.soft_dot_texture()
	p.z_index = TELEGRAPH_Z
	p.z_as_relative = false
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0.0, 0.0, 0.0)
	m.spread = 180.0
	m.gravity = Vector3.ZERO
	m.initial_velocity_min = 0.0
	m.initial_velocity_max = max_radius / duration
	m.scale_min = 0.5
	m.scale_max = 1.2
	m.color = tint
	m.color_ramp = EnemyVfxShared.fade_gradient(tint, Color(tint.r, tint.g, tint.b, 0.0))
	p.process_material = m
	return p


static func _ring_points(radius: float, segments: int) -> PackedVector2Array:
	var pts: Array[Vector2] = []
	for i in segments + 1:
		var a := float(i) / float(segments) * TAU
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return PackedVector2Array(pts)


static func _schedule_free(node: Node, delay: float) -> void:
	node.get_tree().create_timer(delay, false).timeout.connect(node.queue_free)