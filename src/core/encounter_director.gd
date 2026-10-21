class_name EncounterDirector
extends RefCounted

const HORDE_SOFT_CAP := 14
const CONTAGION_RADIUS := 48.0
const SPEED_CAP_FRACTION := 0.95
const TETHER_DISTANCE := 80.0
const RAMP_BAND := 120.0

const BASE_TOKENS := 4.0
const DEEP_TOKENS := 6.0
const ELITE_TOKEN_BONUS := 1.0
const TOKEN_TIMEOUT := 3.0
const AIM_CONE_HALF_ANGLE := PI / 4.0
# The live player facing flips too often to steer a group; sample it slowly.
const FACING_POLL_INTERVAL := 2.0

var _active: Array = []
# enemy -> {"cost": float, "age": float, "attacking": bool}
var _tokens: Dictionary = {}
var _requests: Array = []
var _player_pos: Vector2 = Vector2.ZERO
var _player_facing: Vector2 = Vector2.RIGHT
var _facing_timer: float = 0.0


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


func update(player_pos: Vector2, attackable: Array, delta: float = 0.0, player_facing: Vector2 = Vector2.ZERO) -> void:
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

	_player_pos = player_pos
	_poll_facing(delta, player_facing)
	_tick_tokens(delta)
	_grant_requests()


func unregister(enemy) -> void:
	_active.erase(enemy)
	release_token(enemy)


func request_token(enemy) -> bool:
	if _tokens.has(enemy):
		return true
	if not _requests.has(enemy):
		_requests.append(enemy)
	return false


func release_token(enemy) -> void:
	_tokens.erase(enemy)
	_requests.erase(enemy)


func has_token(enemy) -> bool:
	return _tokens.has(enemy)


## An attacking holder is exempt from the timeout; the timeout only reclaims
## tokens from enemies that never got their attack off (stuck on terrain).
func mark_attacking(enemy) -> void:
	if _tokens.has(enemy):
		_tokens[enemy]["attacking"] = true


func max_tokens() -> float:
	var deep := false
	var elites := 0
	for e in _active:
		if not is_instance_valid(e):
			continue
		if "enemy_tier" in e and e.enemy_tier >= DropTable.EnemyTier.NORMAL:
			deep = true
		if "is_elite" in e and e.is_elite:
			elites += 1
	return (DEEP_TOKENS if deep else BASE_TOKENS) + ELITE_TOKEN_BONUS * elites


func used_tokens() -> float:
	var total := 0.0
	for e in _tokens:
		total += _tokens[e]["cost"]
	return total


func get_player_facing() -> Vector2:
	return _player_facing


func get_token_holders() -> Array:
	return _tokens.keys().filter(func(e): return is_instance_valid(e))


func _poll_facing(delta: float, player_facing: Vector2) -> void:
	_facing_timer -= delta
	if _facing_timer > 0.0:
		return
	_facing_timer = FACING_POLL_INTERVAL
	if player_facing.length_squared() > 0.0001:
		_player_facing = player_facing.normalized()


func _tick_tokens(delta: float) -> void:
	for e in _tokens.keys():
		if not is_instance_valid(e) or not e.is_pursuing():
			_tokens.erase(e)
			continue
		var t: Dictionary = _tokens[e]
		if t["attacking"]:
			continue
		t["age"] += delta
		if t["age"] >= TOKEN_TIMEOUT:
			_tokens.erase(e)


func _grant_requests() -> void:
	var pending: Array = []
	for e in _requests:
		if is_instance_valid(e) and _active.has(e) and e.has_method("is_pursuing") and e.is_pursuing() and not _tokens.has(e):
			pending.append(e)
	_requests.clear()
	pending.sort_custom(_request_before)
	var cap := max_tokens()
	var used := used_tokens()
	for e in pending:
		var cost := _token_cost(e)
		if used + cost > cap + 0.0001:
			continue
		_tokens[e] = {"cost": cost, "age": 0.0, "attacking": false}
		used += cost


func _request_before(a, b) -> bool:
	var a_cone := _in_aim_cone(a.global_position)
	var b_cone := _in_aim_cone(b.global_position)
	if a_cone != b_cone:
		return not a_cone
	return a.global_position.distance_squared_to(_player_pos) < b.global_position.distance_squared_to(_player_pos)


func _in_aim_cone(pos: Vector2) -> bool:
	var to := pos - _player_pos
	if to.length_squared() < 0.01:
		return true
	return absf(_player_facing.angle_to(to)) <= AIM_CONE_HALF_ANGLE


static func _token_cost(enemy) -> float:
	return enemy.token_cost() if enemy.has_method("token_cost") else 1.0
