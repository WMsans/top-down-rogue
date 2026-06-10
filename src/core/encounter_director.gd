class_name EncounterDirector
extends RefCounted

const HORDE_SOFT_CAP := 14
const CONTAGION_RADIUS := 48.0
const SPEED_CAP_FRACTION := 0.95
const TETHER_DISTANCE := 80.0
const RAMP_BAND := 120.0

var melee_token_count: int = 2
var ranged_token_count: int = 2

var _active: Array = []
var _melee_claims: Dictionary = {}
var _ranged_claims: Dictionary = {}
var _slots: Dictionary = {}


func is_active(enemy) -> bool:
	return _active.has(enemy)


func try_claim_attack(enemy, is_ranged: bool) -> bool:
	if not is_active(enemy):
		return false
	var claims: Dictionary = _ranged_claims if is_ranged else _melee_claims
	if claims.has(enemy):
		return true
	var budget: int = ranged_token_count if is_ranged else melee_token_count
	if claims.size() >= budget:
		return false
	claims[enemy] = true
	return true


func release_attack(enemy) -> void:
	_melee_claims.erase(enemy)
	_ranged_claims.erase(enemy)


static func tokens_for_floor(base: int, floor_number: int) -> int:
	return base + clampi((floor_number - 1) / 3, 0, 1)
