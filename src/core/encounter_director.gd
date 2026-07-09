class_name EncounterDirector
extends RefCounted

const HORDE_SOFT_CAP := 14
const CONTAGION_RADIUS := 48.0
const SPEED_CAP_FRACTION := 0.95
const TETHER_DISTANCE := 80.0
const RAMP_BAND := 120.0

const KILL_STREAK_MIN := -2
const KILL_STREAK_MAX := 4
const KILL_STREAK_GAIN := 2
const KILL_STREAK_LOSS := 1

var kill_streak: int = 0
var _active: Array = []


func is_active(enemy) -> bool:
	return _active.has(enemy)


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


func unregister(enemy) -> void:
	_active.erase(enemy)


func register_kill() -> void:
	kill_streak = clampi(kill_streak + KILL_STREAK_GAIN, KILL_STREAK_MIN, KILL_STREAK_MAX)


func register_player_hit() -> void:
	kill_streak = clampi(kill_streak - KILL_STREAK_LOSS, KILL_STREAK_MIN, KILL_STREAK_MAX)
