class_name ChainBehavior
extends ProjectileBehavior

const LIGHTNING_DURATION := 0.4
const TINT := Color(0.9, 0.95, 1.0)

var jumps: int = 3
var range_px: float = 160.0


func on_enemy_hit(proj, target) -> bool:
	var tree: SceneTree = proj.get_tree()
	if tree == null:
		return false
	var host: Node = _resolve_host(proj)
	var visited: Array = [proj.source_node, target]
	var from: Node2D = target as Node2D
	for _i in range(jumps):
		if from == null:
			break
		var nxt_list := CombatUtil.nearest_attackables(tree, from.global_position, visited, 1, range_px)
		if nxt_list.is_empty():
			break
		var nxt: Node2D = nxt_list[0]
		if proj.source_weapon != null:
			var is_crit: bool = randf() < clampf(proj.crit_chance, 0.0, 1.0)
			proj.source_weapon.resolve_hit(proj.source_node, nxt, proj.damage, is_crit)
		var sc = nxt.get_node_or_null("StatusComponent")
		if sc != null:
			sc.add_timed_status("lightning", LIGHTNING_DURATION)
		if host != null:
			LightningArcFX.play(host, from.global_position, nxt.global_position, TINT)
		visited.append(nxt)
		from = nxt
	return false  # bolt spent after delivering the chain


func _resolve_host(proj) -> Node:
	var tree: SceneTree = proj.get_tree()
	if tree != null:
		var wm := tree.get_first_node_in_group("world_manager")
		if wm != null and wm.has_method("get_chunk_container"):
			var c = wm.get_chunk_container()
			if c != null:
				return c
	return proj.get_parent()
