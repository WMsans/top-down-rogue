class_name CombustionModifier
extends DetonatorModifier


func _init() -> void:
	super()
	name = "Combustion"
	description = "Consume On-Fire for an instant burst equal to the remaining burn ×3."
	consumed_status = "on_fire"
	burst_per_stack = 3.0
