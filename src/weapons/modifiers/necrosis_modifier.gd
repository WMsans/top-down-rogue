class_name NecrosisModifier
extends DetonatorModifier


func _init() -> void:
	super()
	name = "Necrosis"
	description = "Hitting a poisoned foe consumes Poison and grants +30% swing speed for 1s."
	consumed_status = "poisoned"
	burst_per_stack = 2.0
