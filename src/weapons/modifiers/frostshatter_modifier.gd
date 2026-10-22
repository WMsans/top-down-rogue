class_name FrostshatterModifier
extends DetonatorModifier


func _init() -> void:
	super()
	name = "Frostshatter"
	description = "Hitting a frozen foe consumes Frozen and grants +30% move speed for 1s."
	consumed_status = "frozen"
