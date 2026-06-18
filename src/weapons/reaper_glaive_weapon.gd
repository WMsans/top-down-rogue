class_name ReaperGlaiveWeapon
extends MeleeWeapon

const REAP_HEAL := 2

func _init() -> void:
	super._init()
	weapon_reach = 44.0
	arc_angle = deg_to_rad(100.0)

func _native_on_kill(user: Node, _target: Node) -> void:
	if user == null:
		return
	var inv = user.get_node_or_null("PlayerInventory")
	if inv != null and inv.has_method("heal"):
		inv.heal(REAP_HEAL)
