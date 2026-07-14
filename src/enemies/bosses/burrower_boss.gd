class_name BurrowerBoss
extends BossEnemy

const CHARGE_TELEGRAPH := 0.4
const SWEEP_TELEGRAPH := 0.5
const PIT_TELEGRAPH := 1.0
const PIT_RADIUS := 5.0
const DUST_RADIUS := 6.0

var _hazard_timer: float = 0.0


func _ready() -> void:
	boss_name = "Burrower"
	weapon_resource = null
	super._ready()


func _pattern_count(_phase: int) -> int:
	return 2


func _on_phase_enter(phase: int) -> void:
	match phase:
		1: attack_interval = 1.6
		2: attack_interval = 1.4
		3:
			attack_interval = 1.0
			_hazard_timer = hazard_interval


func _execute_pattern(phase: int, index: int) -> void:
	match phase:
		1: _charge_pattern(index)
		2: _dust_pattern(index)
		3: _pit_pattern(index)


func _charge_pattern(index: int) -> void:
	if index == 0:
		_do_directed_charge()
	else:
		_do_sweep_charge()


func _do_directed_charge() -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return
	var target := _player_ref.global_position
	_spawn_telegraph_ground_crack(global_position, target, CHARGE_TELEGRAPH)
	_begin_charge(target, 0.6, 800.0)


func _do_sweep_charge() -> void:
	var center := global_position
	_spawn_telegraph_expanding(center, 120.0, SWEEP_TELEGRAPH)
	_sequence_charge(center, 0.8)


func _begin_charge(target: Vector2, duration: float, accel: float) -> void:
	_charge_active = true
	_charge_target = target
	_charge_accel = accel
	_charge_remaining = duration
	_lock_navigation(true)


var _charge_active: bool = false
var _charge_target: Vector2 = Vector2.ZERO
var _charge_accel: float = 600.0
var _charge_remaining: float = 0.0


func _tick_phase(delta: float) -> void:
	if _charge_active:
		_charge_remaining -= delta
		_steer_toward(_charge_target, _charge_accel, delta)
		if _charge_remaining <= 0.0:
			_charge_active = false
			_lock_navigation(false)
			if current_phase == 2 and _last_pattern_index == 0:
				_do_dust_burst_after_charge()
	if current_phase == 3:
		_hazard_timer -= delta
		if _hazard_timer <= 0.0:
			_hazard_timer = hazard_interval
			_pit_or_tremor()


var _last_pattern_index: int = 0


func _dust_pattern(index: int) -> void:
	_last_pattern_index = index
	if index == 0:
		_do_directed_charge()
	else:
		for i in 3:
			var off := Vector2(randf_range(-80, 80), randf_range(-80, 80))
			var pos := _player_ref.global_position + off if (_player_ref and is_instance_valid(_player_ref)) else global_position + off
			_spawn_telegraph_expanding(pos, 24.0, 0.6)
			_stamp_material(pos, DUST_RADIUS, MaterialRegistry.MAT_DUST)


func _do_dust_burst_after_charge() -> void:
	_stamp_material(global_position, DUST_RADIUS, MaterialRegistry.MAT_DUST)
	_stamp_material(_charge_target, DUST_RADIUS, MaterialRegistry.MAT_DUST)


func _pit_or_tremor() -> void:
	var idx := _pattern_index
	if idx == 0:
		var pos := global_position + Vector2(randf_range(-120, 120), randf_range(-120, 120))
		_spawn_telegraph_expanding(pos, 40.0, PIT_TELEGRAPH)
		if is_inside_tree():
			get_tree().create_timer(PIT_TELEGRAPH, false).timeout.connect(func(): _stamp_material(pos, PIT_RADIUS, MaterialRegistry.MAT_AIR))
		else:
			_stamp_material(pos, PIT_RADIUS, MaterialRegistry.MAT_AIR)
	else:
		if is_inside_tree():
			get_tree().call_group("boss_encounter", "shake", 2.0)
		for i in 8:
			var a := float(i) / 8.0 * TAU
			_stamp_material(global_position + Vector2(cos(a), sin(a)) * 60.0, DUST_RADIUS, MaterialRegistry.MAT_DUST)


func _pit_pattern(index: int) -> void:
	_last_pattern_index = index
	pass


func _spawn_telegraph_ground_crack(start: Vector2, end: Vector2, duration: float) -> void:
	BossTelegraph.ground_crack_line(get_parent(), start, end, duration)

func _spawn_telegraph_expanding(center: Vector2, radius: float, duration: float) -> void:
	BossTelegraph.expanding_circle(get_parent(), center, radius, duration)


func _sequence_charge(center: Vector2, duration: float) -> void:
	_charge_active = true
	_charge_target = center + Vector2(120, 0)
	_charge_accel = 700.0
	_charge_remaining = duration
	_lock_navigation(true)
