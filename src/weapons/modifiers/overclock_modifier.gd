class_name OverclockModifier
extends Modifier

const DISABLE_TIME := 5.0
var _timer: float = 0.0


func _init() -> void:
	category = "trigger"
	is_retrigger_modifier = true
	name = "Overclock"
	description = "Retrigger the modifier to your left, then disable it for 5 seconds."


func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
	if is_disabled:
		return
	var left: Modifier = weapon.get_left_modifier(slot_index)
	if left != null and left != self and not left.is_retrigger_modifier:
		weapon.retrigger_modifier(left, "on_hit_target", [user, target])
		left.is_disabled = true
		_timer = DISABLE_TIME


func on_tick(_weapon: Weapon, delta: float) -> void:
	if _timer > 0.0:
		_timer -= delta
		if _timer <= 0.0:
			var w: Weapon = _weapon
			var left: Modifier = w.get_left_modifier(slot_index)
			if left != null:
				left.is_disabled = false
