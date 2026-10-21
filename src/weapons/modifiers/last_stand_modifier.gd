class_name LastStandModifier
extends Modifier

const BOOST_MULT := 1.6


func _init() -> void:
	category = "trigger"
	name = "Last Stand"
	description = "After taking a hit, your next swing has a 1/2 chance to release a knockback shockwave."
