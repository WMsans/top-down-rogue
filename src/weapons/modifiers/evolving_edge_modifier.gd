class_name EvolvingEdgeModifier
extends Modifier

const BASE_BONUS := 2.0
const HITS_TO_DOUBLE := 15
var _hits: int = 0


func _init() -> void:
	category = "trigger"
	name = "Evolving Edge"
	description = "After 15 hits, this modifier's own bonus doubles (run)."


func on_hit_target(_weapon: Weapon, _user: Node, _target: Node) -> void:
	if is_disabled:
		return
	_hits += 1


func get_stat_add(stat: String) -> float:
	if stat != "damage":
		return 0.0
	return BASE_BONUS * (2.0 if _hits >= HITS_TO_DOUBLE else 1.0)
