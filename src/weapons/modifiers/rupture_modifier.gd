class_name RuptureModifier
extends Modifier

const BLEED_HITS_TO_BURST := 5
const BURST_MULT := 5.0
var _bleed_hits: int = 0


func _init() -> void:
	category = "trigger"
	name = "Rupture"
	description = "Bleeding accumulates; at 5 stacks the target bursts for 5× a hit."


func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
	if is_disabled:
		return
	var sc = target.get_node_or_null("StatusComponent") if target != null else null
	if sc == null or sc.get_stain("bloody") <= 0.0:
		return
	_bleed_hits += 1
	if _bleed_hits >= BLEED_HITS_TO_BURST:
		_bleed_hits = 0
		weapon._apply_burst(user, target, weapon.damage * BURST_MULT)
