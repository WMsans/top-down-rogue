class_name CombustionModifier
extends DetonatorModifier


func _init() -> void:
	super()
	name = "Combustion"
	description = "Hitting a burning foe consumes On-Fire and grants +30% reach for 1s."
	consumed_status = "on_fire"
