class_name DetonatorModifier
extends Modifier

# Inert until Plan 3. The old "consume the status, then burst a hit" shape
# spent a real hit, which the hit-count model no longer allows; Plan 3
# replaces it with "clear the status and buff the player" (needs the
# PlayerBuffs infrastructure from Plan 2).

var consumed_status: String = ""


func _init() -> void:
	category = "trigger"
