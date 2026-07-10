class_name BloodAltar
extends InteractableShrine

## Risk/reward: pay a slice of current HP for a rich (HARD-tier) chest.
## Balance: costs 25% of current health (min 5); yields one HARD-tier chest.

const HP_COST_FRACTION := 0.25
const MIN_HP_COST := 5

const _ICON := preload("res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/32x32/potion_02a.png")


func _init() -> void:
	title = "Blood Altar"
	body = "Offer blood for power. Interact to pay 25% of your health for a rich chest."
	icon = _ICON


func _on_interact(player) -> void:
	var inv := _inventory(player)
	if inv == null:
		return
	var current: int = inv.get_health() if inv.has_method("get_health") else 0
	var cost: int = maxi(MIN_HP_COST, int(float(current) * HP_COST_FRACTION))
	if inv.has_method("take_status_damage"):
		inv.take_status_damage(cost)
	_spawn_chest_here(DropTable.EnemyTier.HARD)
