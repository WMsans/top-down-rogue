class_name AdvancedMeleeWeapon
extends MeleeWeapon

enum MoveShape { SLASH, THRUST, SPIN }
enum ComboMode { TAP_CHAIN, AUTO_FLURRY }

class Move extends RefCounted:
	var shape: int = MoveShape.SLASH
	var reach: float = 36.0
	var arc: float = PI / 2.0
	var damage_mult: float = 1.0
	var dash_distance: float = 0.0
	var force_crit: bool = false
	var ignore_parry: bool = false
	var swing_dir: float = 0.0   # 0 = alternate; +1/-1 = forced swing direction

@export var charge_time_full: float = 0.6
@export var tap_threshold: float = 0.12
@export var combo_mode: int = ComboMode.TAP_CHAIN
@export var combo_reset_time: float = 0.5
@export var charged_flurry_max: int = 1
@export var flurry_step_time: float = 0.16

var light_moves: Array = []
var charged_moves: Array = []

var _moves_built: bool = false
var _charging: bool = false
var _charge_time: float = 0.0
var _combo_index: int = 0
var _combo_reset_timer: float = 0.0
var _flurry_queue: Array = []
var _flurry_timer: float = 0.0
var _flurry_active: bool = false
var _active_move: Move = null
var _move_phase_time: float = 0.0
var _spin_from_angle: float = 0.0


# ---- Move construction (lazy: runs after .tres stats are applied) ----

func _ensure_moves() -> void:
	if _moves_built:
		return
	_moves_built = true
	_setup_moves()


func _setup_moves() -> void:
	# Subclasses override to populate light_moves / charged_moves.
	light_moves = [_slash()]


func _slash(dir: float = 0.0, dmg_mult: float = 1.0) -> Move:
	var m := Move.new()
	m.shape = MoveShape.SLASH
	m.reach = weapon_reach
	m.arc = arc_angle
	m.swing_dir = dir
	m.damage_mult = dmg_mult
	return m


func _thrust(force_crit: bool = false, ignore_parry: bool = false, dash: float = 0.0) -> Move:
	var m := Move.new()
	m.shape = MoveShape.THRUST
	m.reach = weapon_reach * 1.25
	m.arc = deg_to_rad(20.0)
	m.force_crit = force_crit
	m.ignore_parry = ignore_parry
	m.dash_distance = dash
	return m


func _spin(dmg_mult: float = 1.0, dash: float = 0.0) -> Move:
	var m := Move.new()
	m.shape = MoveShape.SPIN
	m.reach = weapon_reach
	m.arc = TAU
	m.damage_mult = dmg_mult
	m.dash_distance = dash
	return m


# ---- Charge controller ----

func get_charge_ratio() -> float:
	return clampf(_charge_time / charge_time_full, 0.0, 1.0)


func on_press(user: Node) -> void:
	_ensure_moves()
	if _flurry_active:
		return
	if not is_ready():
		return
	if charged_moves.is_empty():
		use(user)            # non-charge weapons: light combo / single move via _use_impl
		return
	_current_user = user
	_charging = true
	_charge_time = 0.0


func on_release(user: Node) -> void:
	if not _charging:
		return
	_charging = false
	_current_user = user
	if _charge_time < tap_threshold:
		use(user)            # tap: reuse base wrapper (modifiers + cooldown + _use_impl)
	else:
		_fire_charged(user, get_charge_ratio())


func _fire_charged(user: Node, ratio: float) -> void:
	for modifier in modifiers:
		if modifier != null:
			modifier.on_use(self, user)
	_do_charged_attack(user, ratio)
	_cooldown_timer = cooldown


# ---- Attack dispatch ----

func _use_impl(user: Node) -> void:
	_ensure_moves()
	_current_user = user
	if _flurry_active:
		return
	_do_light_attack(user)


func _do_light_attack(user: Node) -> void:
	if combo_mode == ComboMode.AUTO_FLURRY:
		_start_flurry(light_moves.duplicate(), user)
		return
	if light_moves.is_empty():
		return
	var move = light_moves[_combo_index]
	_play_move(move, user)
	_combo_index += 1
	if _combo_index >= light_moves.size():
		_combo_index = 0
	_combo_reset_timer = combo_reset_time


func _do_charged_attack(user: Node, ratio: float) -> void:
	if charged_moves.is_empty():
		return
	if charged_flurry_max > 1:
		var count := clampi(1 + int(round(ratio * float(charged_flurry_max - 1))), 1, charged_flurry_max)
		var seq: Array = []
		for i in range(count):
			seq.append_array(charged_moves)
		_start_flurry(seq, user)
	elif charged_moves.size() == 1:
		_play_move(charged_moves[0], user)
	else:
		_start_flurry(charged_moves.duplicate(), user)


# ---- Flurry engine ----

func _start_flurry(moves: Array, user: Node) -> void:
	_flurry_queue = moves
	_flurry_active = true
	_flurry_timer = 0.0
	_advance_flurry(user)


func _advance_flurry(user: Node) -> void:
	if _flurry_queue.is_empty():
		_flurry_active = false
		return
	var move = _flurry_queue.pop_front()
	_play_move(move, user)
	_flurry_timer = flurry_step_time


# ---- Per-frame timers ----

func _tick_impl(delta: float) -> void:
	if _charging:
		_charge_time = minf(_charge_time + delta, charge_time_full)
		_on_charge_tick(_current_user, delta, get_charge_ratio())
	if _flurry_active:
		_flurry_timer -= delta
		if _flurry_timer <= 0.0:
			_advance_flurry(_current_user)
	if _combo_reset_timer > 0.0:
		_combo_reset_timer -= delta
		if _combo_reset_timer <= 0.0:
			_combo_index = 0


# ---- Move runner (hits + animations) ----

func _play_move(move: Move, user: Node) -> void:
	if user == null:
		return
	var pos: Vector2 = user.global_position
	var direction := _get_facing_direction(user)
	_apply_move_hit(move, user, pos, direction)
	if move.dash_distance > 0.0 and user.has_method("request_dash"):
		user.request_dash(direction, move.dash_distance * 6.0)
	_start_move_anim(move, direction)


func _apply_move_hit(move: Move, user: Node, pos: Vector2, direction: Vector2) -> void:
	_carve_and_push(pos, direction, move.reach, move.arc, damage * move.damage_mult)
	_hit_attackables(user, pos, direction, move.reach, move.arc, move.damage_mult, move.force_crit, move.ignore_parry)


func _start_move_anim(move: Move, direction: Vector2) -> void:
	_active_move = move
	_move_phase_time = 0.0
	match move.shape:
		MoveShape.SLASH:
			if move.swing_dir != 0.0:
				_swing_toggle = -move.swing_dir      # _start_swing negates, so pre-invert to force up/down
			_start_swing(direction)                  # inherited cosmetic swing
			_active_move = null                      # slash uses the parent state machine
		MoveShape.THRUST, MoveShape.SPIN:
			_facing_angle = direction.angle()
			if absf(direction.x) > 0.01:
				_facing_sign = signf(direction.x)
			_spin_from_angle = _facing_angle
			_is_swinging = true                      # block idle pose; we drive it below


func update_visual(delta: float, user: Node) -> void:
	# Bespoke thrust/spin run here; everything else defers to MeleeWeapon's swing.
	if _active_move != null and (_active_move.shape == MoveShape.THRUST or _active_move.shape == MoveShape.SPIN):
		_process_special_move(delta, user)
		return
	super.update_visual(delta, user)


func _process_special_move(delta: float, user: Node) -> void:
	if visual == null:
		return
	_current_user = user
	var dir := _get_facing_direction(user)
	_facing_angle = dir.angle()
	_move_phase_time += delta
	var facing := _facing_unit()
	match _active_move.shape:
		MoveShape.THRUST:
			_animate_thrust(facing)
		MoveShape.SPIN:
			_animate_spin()


func _animate_thrust(facing: Vector2) -> void:
	# Fast stab out then snap back over ~0.18s.
	var dur := 0.18
	var t := clampf(_move_phase_time / dur, 0.0, 1.0)
	var out := sin(t * PI)                                   # 0 -> 1 -> 0
	var lunge := weapon_reach * 0.6
	_pose_pos = _rest_pos() + facing * (rest_forward + lunge * out)
	_pose_rot = _blade_to_sprite_rot(_facing_angle)
	_pose_scale = Vector2(1.0 + 0.25 * out, 1.0 - 0.15 * out)
	_apply_pose()
	if _active_move != null and t >= 1.0:
		_end_special_move()


func _animate_spin() -> void:
	# One full blade revolution around the player over ~0.3s, with a body lean.
	var dur := 0.3
	var t := clampf(_move_phase_time / dur, 0.0, 1.0)
	var eased := _ease_out_cubic(t)
	var blade := _spin_from_angle + TAU * eased
	_pose_pos = _rest_pos() + Vector2(cos(blade), sin(blade)) * (weapon_reach * 0.35)
	_pose_rot = _blade_to_sprite_rot(blade)
	_pose_scale = Vector2(1.1, 0.95)
	_apply_pose()
	if t >= 1.0:
		_end_special_move()


func _end_special_move() -> void:
	_active_move = null
	_is_swinging = false
	_process_idle()


# ---- Seam for subclasses ----

func _on_charge_tick(_user, _delta: float, _ratio: float) -> void:
	pass


func _process_idle() -> void:
	super._process_idle()
	if _charging and _sprite != null:
		var r := get_charge_ratio()
		_sprite.modulate = Color(1.0, 1.0, 1.0).lerp(Color(2.0, 1.6, 0.6), r)
	elif _sprite != null:
		_sprite.modulate = Color(1.0, 1.0, 1.0)
