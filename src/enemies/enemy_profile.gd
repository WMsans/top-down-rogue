class_name EnemyProfile
extends RefCounted

## Behavior knobs for one enemy tier. Difficulty comes from behavior, never
## stats: these scale telegraphs, cadence, aim and volley size, not hits.

var telegraph_mult: float = 1.0
var cadence_mult: float = 1.0
var reaction_time: float = 0.2
var chain_attacks: int = 2
var volley_bonus: int = 1
var lead_factor: float = 0.5
var lunge_redirect: bool = false


## Elites take the next tier's timing and aim (HARD stays HARD) and always
## redirect their lunge; everything else keeps the base tier's value.
static func for_tier(tier: int, elite: bool = false) -> EnemyProfile:
	var p := EnemyProfile.new()
	p._fill(tier)
	if elite:
		var step := EnemyProfile.new()
		step._fill(mini(tier + 1, DropTable.EnemyTier.HARD))
		p.telegraph_mult = step.telegraph_mult
		p.cadence_mult = step.cadence_mult
		p.lead_factor = step.lead_factor
		p.lunge_redirect = true
	return p


func _fill(tier: int) -> void:
	match tier:
		DropTable.EnemyTier.EASY:
			telegraph_mult = 1.25
			cadence_mult = 1.2
			reaction_time = 0.35
			chain_attacks = 1
			volley_bonus = 0
			lead_factor = 0.0
			lunge_redirect = false
		DropTable.EnemyTier.HARD:
			telegraph_mult = 0.75
			cadence_mult = 0.7
			reaction_time = 0.1
			chain_attacks = 2
			volley_bonus = 2
			lead_factor = 0.9
			lunge_redirect = true
		_:
			pass  # NORMAL: the field defaults above
