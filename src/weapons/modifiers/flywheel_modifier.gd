class_name FlywheelModifier
extends Modifier

const CHARGE_TO_DUMP := 5
const DUMP_EXTRA := 3
var _charge: int = 0


func _init() -> void:
	category = "trigger"
	is_retrigger_modifier = true
	name = "Flywheel"
	description = "Untriggered modifiers charge; at 5, fire ×3 then empty."


func on_attack(_weapon: Weapon, _user: Node, _ctx: Dictionary) -> void:
	if is_disabled:
		return
	_charge += 1


func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
	if is_disabled:
		return
	if _charge < CHARGE_TO_DUMP:
		return
	_charge = 0
	for m in weapon._iter_active_modifiers():
		if m == self or m.is_retrigger_modifier:
			continue
		for _i in range(DUMP_EXTRA):
			m.on_hit_target(weapon, user, target)
