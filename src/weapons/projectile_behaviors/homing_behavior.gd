class_name HomingBehavior
extends ProjectileBehavior

var turn_rate_rad: float = PI * 2.0


func on_process(proj, delta: float) -> void:
	var target := _nearest_target(proj)
	if target == null:
		return
	var desired: Vector2 = target.global_position - proj.global_position
	if desired == Vector2.ZERO:
		return
	var cur_angle: float = proj.direction.angle()
	var diff: float = angle_difference(cur_angle, desired.angle())
	var max_step: float = turn_rate_rad * delta
	var new_angle: float = cur_angle + clampf(diff, -max_step, max_step)
	proj.direction = Vector2(cos(new_angle), sin(new_angle))


func _nearest_target(proj) -> Node2D:
	var tree: SceneTree = proj.get_tree()
	if tree == null:
		return null
	var group: String = "player" if proj.is_enemy_projectile else "attackable"
	var best: Node2D = null
	var best_d2: float = INF
	for n in tree.get_nodes_in_group(group):
		if n == proj.source_node or not is_instance_valid(n) or not (n is Node2D):
			continue
		var d2: float = proj.global_position.distance_squared_to((n as Node2D).global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = n
	return best
