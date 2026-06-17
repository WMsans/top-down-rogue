class_name CombatUtil
extends RefCounted

static func radial_knockback(source: Node, radius: float, strength: float) -> void:
	if source == null or not (source is Node2D):
		return
	var tree := source.get_tree()
	if tree == null:
		return
	var origin: Vector2 = (source as Node2D).global_position
	var r2: float = radius * radius
	for n in tree.get_nodes_in_group("attackable"):
		if n == source or not is_instance_valid(n) or not (n is Node2D):
			continue
		if not n.has_method("apply_knockback"):
			continue
		var to_n: Vector2 = (n as Node2D).global_position - origin
		if to_n.length_squared() > r2:
			continue
		var dir: Vector2 = to_n.normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.DOWN
		n.apply_knockback(dir, strength)
