class_name EncounterDirector
extends RefCounted

const HORDE_SOFT_CAP := 14
const CONTAGION_RADIUS := 48.0
const SPEED_CAP_FRACTION := 0.95
const TETHER_DISTANCE := 80.0
const RAMP_BAND := 120.0
const AGGRO_MIN := -2
const AGGRO_MAX := 4
const KILL_GAIN := 2
const HIT_LOSS := 1

var melee_token_count: int = 2
var ranged_token_count: int = 2
var aggression_delta: int = 0

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
	var budget: int = effective_ranged_tokens() if is_ranged else effective_melee_tokens()
	if claims.size() >= budget:
		return false
	claims[enemy] = true
	return true


func release_attack(enemy) -> void:
	_melee_claims.erase(enemy)
	_ranged_claims.erase(enemy)


func effective_melee_tokens() -> int:
	return maxi(1, melee_token_count + aggression_delta)


func effective_ranged_tokens() -> int:
	return maxi(1, ranged_token_count + aggression_delta)


func register_kill() -> void:
	aggression_delta = clampi(aggression_delta + KILL_GAIN, AGGRO_MIN, AGGRO_MAX)


func register_player_hit() -> void:
	aggression_delta = clampi(aggression_delta - HIT_LOSS, AGGRO_MIN, AGGRO_MAX)


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


func update(player_pos: Vector2, attackable: Array) -> void:
	var still: Array = []
	for e in _active:
		if is_instance_valid(e) and e.has_method("is_pursuing") and e.is_pursuing():
			still.append(e)
		else:
			_drop_bookkeeping(e)
	_active = still

	for e in attackable:
		if _active.size() >= HORDE_SOFT_CAP:
			break
		if not is_instance_valid(e):
			continue
		if not e.has_method("is_pursuing") or not e.is_pursuing():
			continue
		if not _active.has(e):
			_active.append(e)

	_assign_slots(player_pos)


func unregister(enemy) -> void:
	_active.erase(enemy)
	_drop_bookkeeping(enemy)


func _drop_bookkeeping(enemy) -> void:
	_melee_claims.erase(enemy)
	_ranged_claims.erase(enemy)
	_slots.erase(enemy)


var _player_pos: Vector2 = Vector2.ZERO


func _assign_slots(player_pos: Vector2) -> void:
	_player_pos = player_pos
	_slots.clear()
	var n := _active.size()
	if n == 0:
		return
	var ordered := _active.duplicate()
	ordered.sort_custom(func(x, y):
		return (x.global_position - player_pos).angle() < (y.global_position - player_pos).angle())
	var start: float = (ordered[0].global_position - player_pos).angle()
	for i in range(n):
		_slots[ordered[i]] = start + TAU * float(i) / float(n)


func get_slot_angle(enemy) -> float:
	if _slots.has(enemy):
		return _slots[enemy]
	if is_instance_valid(enemy):
		return (enemy.global_position - _player_pos).angle()
	return 0.0
