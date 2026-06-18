class_name ChainSparkModifier
extends Modifier

const RANGE := 160.0
const DAMAGE := 6
const LIGHTNING_DURATION := 0.4
const STUN_CHANCE := 0.25
const STUN_DURATION := 0.3
const TINT := Color(0.9, 0.95, 1.0)

var chain_count: int = 3


func _init() -> void:
	name = "Chain Spark"
	description = "Critical hits arc lightning to nearby enemies, with a chance to stun."
	icon_texture = preload("res://textures/wall.png")


func on_crit(_weapon: Weapon, user: Node, _target: Node) -> void:
	if user == null or not (user is Node2D):
		return
	var host := _resolve_host(user)
	var origin: Vector2 = (user as Node2D).global_position
	for n in _nearest_targets(user, chain_count, RANGE):
		var pos: Vector2 = (n as Node2D).global_position
		if n.has_method("on_hit_impact"):
			n.on_hit_impact(pos, (pos - origin).normalized(), DAMAGE)
		var sc = n.get_node_or_null("StatusComponent")
		if sc != null:
			sc.add_timed_status("lightning", LIGHTNING_DURATION)
			if randf() < STUN_CHANCE:
				sc.add_timed_status("stun", STUN_DURATION)
		LightningArcFX.play(host, origin, pos, TINT)


func _nearest_targets(user: Node, count: int, range_px: float) -> Array:
	var tree := user.get_tree()
	if tree == null:
		return []
	var origin: Vector2 = (user as Node2D).global_position
	var r2: float = range_px * range_px
	var candidates: Array = []
	for n in tree.get_nodes_in_group("attackable"):
		if n == user or not is_instance_valid(n) or not (n is Node2D):
			continue
		var d: float = origin.distance_squared_to((n as Node2D).global_position)
		if d <= r2:
			candidates.append({ "node": n, "d": d })
	candidates.sort_custom(func(a, b): return a["d"] < b["d"])
	var out: Array = []
	for i in range(mini(count, candidates.size())):
		out.append(candidates[i]["node"])
	return out


func _resolve_host(user: Node) -> Node:
	var tree := user.get_tree()
	if tree != null:
		var wm := tree.get_first_node_in_group("world_manager")
		if wm != null and wm.has_method("get_chunk_container"):
			var c = wm.get_chunk_container()
			if c != null:
				return c
	return user.get_parent()
