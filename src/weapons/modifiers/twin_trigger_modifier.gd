class_name TwinTriggerModifier
extends Modifier

var _swings: int = 0


func _init() -> void:
	category = "trigger"
	is_retrigger_modifier = true
	name = "Twin Trigger"
	description = "Every 3rd swing, all modifiers trigger twice."


func on_attack(weapon: Weapon, user: Node, ctx: Dictionary) -> void:
	if is_disabled:
		return
	_swings += 1
	if _swings % 3 == 0:
		_extra_pass(weapon, "on_attack", [user, ctx])


func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
	if is_disabled:
		return
	if _swings % 3 == 0:
		_extra_pass(weapon, "on_hit_target", [user, target])


func _extra_pass(weapon: Weapon, hook: String, args: Array) -> void:
	for m in weapon._iter_active_modifiers():
		if m == self or m.is_retrigger_modifier:
			continue
		match hook:
			"on_attack":
				m.on_attack(weapon, args[0], args[1])
			"on_hit_target":
				m.on_hit_target(weapon, args[0], args[1])
