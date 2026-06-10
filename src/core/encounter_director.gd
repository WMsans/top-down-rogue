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


static func catch_up_speed(base_speed: float, dist_to_player: float, player_speed: float) -> float:
	var cap := player_speed * SPEED_CAP_FRACTION
	if dist_to_player <= TETHER_DISTANCE:
		return minf(base_speed, cap)
	var t := clampf((dist_to_player - TETHER_DISTANCE) / RAMP_BAND, 0.0, 1.0)
	var target := maxf(base_speed, cap)
	return minf(lerpf(base_speed, target, t), cap)


static func should_aggro_from_neighbors(me: Node2D, neighbors: Array) -> bool:
	var my_pos := me.global_position
	for n in neighbors:
		if n == me or not is_instance_valid(n):
			continue
		if not n.has_method("is_pursuing") or not n.is_pursuing():
			continue
		if my_pos.distance_to(n.global_position) <= CONTAGION_RADIUS:
			return true
	return false
