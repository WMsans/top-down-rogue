class_name DetonatorModifier
extends Modifier

var consumed_status: String = ""
var burst_per_stack: float = 0.0


func _init() -> void:
	category = "trigger"


func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
	if is_disabled:
		return
	var sc = target.get_node_or_null("StatusComponent") if target != null else null
	if sc == null:
		return
	var stacks: float = sc.get_stain(consumed_status)
	if stacks < StatusRegistry.get_threshold(consumed_status):
		return
	var burst: float = stacks * burst_per_stack
	sc.clear(consumed_status)
	weapon._apply_burst(user, target, burst)
	_on_detonate(weapon, user, target, stacks)


func _on_detonate(_weapon: Weapon, _user: Node, _target: Node, _stacks: float) -> void:
	pass
