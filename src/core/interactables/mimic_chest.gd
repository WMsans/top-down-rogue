class_name MimicChest
extends InteractableShrine

## Risk/reward: looks like a chest. Usually real loot, sometimes a mimic ambush.
## Balance: 60% -> HARD-tier chest; 40% -> 6-enemy ambush, no loot.

const REAL_CHANCE := 0.6
const AMBUSH_COUNT := 6
const AMBUSH_SPREAD := 40.0

const _ICON := preload("res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/32x32/gift_01a.png")


func _init() -> void:
	title = "Mimic?"
	body = "Too good to be true? Interact to open — it may bite back."
	icon = _ICON


func _on_interact(_player) -> void:
	if randf() < REAL_CHANCE:
		_spawn_chest_here(DropTable.EnemyTier.HARD)
	else:
		_spawn_melee(AMBUSH_COUNT, AMBUSH_SPREAD, false)
