class_name KeystoneModifier
extends Modifier

const DAMAGE_MULT := 2.0


func _init() -> void:
	category = "trigger"
	name = "Keystone"
	description = "Slot 2 modifier +100%; slots 1 and 3 disabled (focus build)."


func is_keystone() -> bool:
	return true


func get_stat_mult(stat: String) -> float:
	return 1.0
