class_name TrialGauntlet
extends InteractableShrine

## Risk/reward: summon a hard elite wave; clear it for a relic (HARD-tier) chest.
## Balance: 5 elite melee; reward chest spawns when the last one dies.

const ELITE_COUNT := 5
const WAVE_SPREAD := 56.0

const _ICON := preload("res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/32x32/sword_01a.png")

var _alive := 0
var _rewarded := false


func _init() -> void:
	title = "Trial Gauntlet"
	body = "Prove yourself. Interact to summon a trial — survive for a relic chest."
	icon = _ICON


func _on_interact(_player) -> void:
	var mob := _spawn_melee(ELITE_COUNT, WAVE_SPREAD, true)
	_alive = mob.size()
	for e in mob:
		if e is Node:
			(e as Node).tree_exited.connect(_on_enemy_gone)
	if _alive <= 0:
		_grant_reward()


func _on_enemy_gone() -> void:
	_alive -= 1
	if _alive <= 0:
		_grant_reward()


func _grant_reward() -> void:
	if _rewarded:
		return
	_rewarded = true
	_spawn_chest_here(DropTable.EnemyTier.HARD)
