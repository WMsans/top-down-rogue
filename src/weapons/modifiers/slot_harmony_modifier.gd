class_name SlotHarmonyModifier
extends Modifier

const HARMONY_MULT := 1.2


func _init() -> void:
	category = "trigger"
	name = "Slot Harmony"
	description = "+20% damage while all 3 slots are different categories."


func _all_different(weapon: Weapon) -> bool:
	var cats: Array = []
	for i in range(weapon.modifier_slot_count):
		var m: Modifier = weapon.get_modifier_at(i)
		if m == null:
			return false
		var c: String = m.category if "category" in m else ""
		if c == "" or cats.has(c):
			return false
		cats.append(c)
	return cats.size() == weapon.modifier_slot_count
