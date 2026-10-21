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

const RING_REFRESH := 0.5
const RING_ROTATE_STEP := TAU / 16.0
const RING_ROTATE_TRIES := 8

var _active: Array = []
# enemy -> {"cost": float, "age": float, "attacking": bool}
var _tokens: Dictionary = {}
var _requests: Array = []
var _player_pos: Vector2 = Vector2.ZERO
var _player_facing: Vector2 = Vector2.RIGHT
var _facing_timer: float = 0.0

## func(world_pos: Vector2) -> bool; set by WorldManager from its nav field.
var solid_check: Callable = Callable()
# enemy -> {"radius": float, "angle": float}; angle INF when no open slot
var _ring: Dictionary = {}
var _ring_dirty: bool = true
var _ring_timer: float = 0.0

# enemy -> Vector2 firing spot
var _spots: Dictionary = {}


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


static func alert(origin: Vector2, radius: float, candidates: Array, source) -> void:
	var r2 := radius * radius
	for e in candidates:
		if e == source or not is_instance_valid(e):
			continue
		if not e.has_method("receive_alert"):
			continue
		if origin.distance_squared_to(e.global_position) <= r2:
			e.receive_alert()


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
	_tick_ring(delta)
	_tick_spots()
	_grant_requests()


func unregister(enemy) -> void:
	_active.erase(enemy)
	release_token(enemy)
	leave_ring(enemy)
	release_spot(enemy)


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


func join_ring(enemy, radius: float) -> void:
	if _ring.has(enemy):
		_ring[enemy]["radius"] = radius
		return
	_ring[enemy] = {"radius": radius, "angle": INF}
	_ring_dirty = true


func leave_ring(enemy) -> void:
	if _ring.erase(enemy):
		_ring_dirty = true


func get_slot(enemy) -> Vector2:
	if not _ring.has(enemy):
		return Vector2.INF
	if _ring_dirty:
		_assign_slots()
	return _slot_pos(_ring[enemy])


## A firing spot is a position a ranged enemy has claimed to shoot from.
func claim_spot(enemy, pos: Vector2) -> void:
	_spots[enemy] = pos


func release_spot(enemy) -> void:
	_spots.erase(enemy)


## Firing spots claimed by everyone except `except`.
func get_taken_spots(except) -> Array:
	var out: Array = []
	for e in _spots:
		if e != except and is_instance_valid(e):
			out.append(_spots[e])
	return out


func get_ring_slots() -> Array:
	if _ring_dirty:
		_assign_slots()
	var out: Array = []
	for e in _ring:
		out.append(_slot_pos(_ring[e]))
	return out


## Slots are angles, so they track the player instead of freezing in world space.
func _slot_pos(slot: Dictionary) -> Vector2:
	if slot["angle"] == INF:
		return Vector2.INF
	return _player_pos + Vector2.from_angle(slot["angle"]) * slot["radius"]


## Spread members evenly by angle around the player. With three or more, the
## slot pattern is anchored behind the player's (sampled) facing so someone
## always flanks. Each member takes the free slot nearest its current angle.
func _assign_slots() -> void:
	_ring_dirty = false
	var members: Array = _ring.keys().filter(func(e): return is_instance_valid(e))
	var n := members.size()
	if n == 0:
		return
	var step := TAU / n
	var start: float
	if n >= 3:
		start = (-_player_facing).angle()
	else:
		start = (members[0].global_position - _player_pos).angle()
	var taken := {}
	members.sort_custom(_angle_before)
	for e in members:
		var mine: float = (e.global_position - _player_pos).angle()
		var best := -1
		var best_d := INF
		for i in range(n):
			if taken.has(i):
				continue
			var d := absf(wrapf(start + step * i - mine, -PI, PI))
			if d < best_d:
				best_d = d
				best = i
		taken[best] = true
		_ring[e]["angle"] = _open_angle(start + step * best, _ring[e]["radius"])


func _angle_before(a, b) -> bool:
	return (a.global_position - _player_pos).angle() < (b.global_position - _player_pos).angle()


func _open_angle(angle: float, radius: float) -> float:
	for k in range(RING_ROTATE_TRIES):
		var offset := RING_ROTATE_STEP * ceilf(k / 2.0) * (1.0 if k % 2 == 1 else -1.0)
		var pos := _player_pos + Vector2.from_angle(angle + offset) * radius
		if not solid_check.is_valid() or not solid_check.call(pos):
			return angle + offset
	return INF


func get_token_holders() -> Array:
	return _tokens.keys().filter(func(e): return is_instance_valid(e))


func _poll_facing(delta: float, player_facing: Vector2) -> void:
	_facing_timer -= delta
	if _facing_timer > 0.0:
		return
	_facing_timer = FACING_POLL_INTERVAL
	if player_facing.length_squared() > 0.0001:
		_player_facing = player_facing.normalized()


func _tick_ring(delta: float) -> void:
	for e in _ring.keys():
		if not is_instance_valid(e) or not e.is_pursuing():
			_ring.erase(e)
			_ring_dirty = true
	_ring_timer -= delta
	if _ring_timer <= 0.0:
		_ring_timer = RING_REFRESH
		_ring_dirty = true


func _tick_spots() -> void:
	for e in _spots.keys():
		if not is_instance_valid(e) or not e.is_pursuing():
			_spots.erase(e)


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
