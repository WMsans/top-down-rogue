class_name NecrosisModifier
extends DetonatorModifier


func _init() -> void:
	super()
	name = "Necrosis"
	description = "Consume Poison stacks for an instant burst of ×2 that damage."
	consumed_status = "poisoned"
	burst_per_stack = 2.0
