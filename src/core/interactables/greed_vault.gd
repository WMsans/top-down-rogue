class_name GreedVault
extends InteractableShrine

## Risk/reward: grab the hoard now, but the alarm summons waves of defenders.
## Balance: instant HARD-tier chest; 3 waves of 4 melee, 1.5s apart (first immediate).

const WAVES := 3
const PER_WAVE := 4
const WAVE_INTERVAL := 1.5
const WAVE_SPREAD := 48.0

const _ICON := preload("res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/32x32/coin_01a.png")

var _waves_left := 0
var _wave_timer: Timer = null


func _init() -> void:
	title = "Greed Vault"
	body = "Take it and run. Interact to loot — but the alarm summons defenders."
	icon = _ICON


func _on_interact(_player) -> void:
	_spawn_chest_here(DropTable.EnemyTier.HARD)
	_waves_left = WAVES
	_wave_timer = Timer.new()
	_wave_timer.wait_time = WAVE_INTERVAL
	_wave_timer.timeout.connect(_on_wave)
	add_child(_wave_timer)
	_wave_timer.start()
	_on_wave()  # first wave immediately


func _on_wave() -> void:
	if _waves_left <= 0:
		if _wave_timer != null:
			_wave_timer.stop()
		return
	_waves_left -= 1
	_spawn_melee(PER_WAVE, WAVE_SPREAD, false)
