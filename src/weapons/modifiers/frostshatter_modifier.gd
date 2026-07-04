class_name FrostshatterModifier
extends DetonatorModifier

const SHATTER_RADIUS := 60.0
const SHATTER_BURST := 10.0


func _init() -> void:
	super()
	name = "Frostshatter"
	description = "Consume Frozen to burst for stacks×8 and shatter nearby foes."
	consumed_status = "frozen"
	burst_per_stack = 8.0


func _on_detonate(weapon: Weapon, user: Node, target: Node, stacks: float) -> void:
	if target == null or not (target is Node2D):
		return
	var tree := target.get_tree()
	if tree == null:
		return
	var near: Array = CombatUtil.nearest_attackables(tree, (target as Node2D).global_position, [target], 6, SHATTER_RADIUS)
	for foe in near:
		weapon._apply_burst(user, foe, SHATTER_BURST)
