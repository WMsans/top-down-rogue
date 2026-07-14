class_name DrillBoss
extends BossEnemy

const BORE_TELEGRAPH := 0.6
const MINE_SCENE := preload("res://scenes/props/mine.tscn")
const PILLAR_RADIUS := 6.0


var _test_player_pos: Vector2 = Vector2(-9999, -9999)


func _ready() -> void:
	boss_name = "Drill Construct"
	weapon_resource = null
	super._ready()


func _set_player_pos_for_test(p: Vector2) -> void:
	_test_player_pos = p


func _player_pos() -> Vector2:
	if _test_player_pos != Vector2(-9999, -9999):
		return _test_player_pos
	if _player_ref and is_instance_valid(_player_ref):
		return _player_ref.global_position
	return global_position


func _pattern_count(_phase: int) -> int:
	return 2


func _on_phase_enter(phase: int) -> void:
	match phase:
		1: attack_interval = 1.8
		2: attack_interval = 1.6
		3: attack_interval = 1.4


func _execute_pattern(phase: int, index: int) -> void:
	match phase:
		1: _bore_pattern(index)
		2: _mine_pattern(index)
		3: _wall_pattern(index)


func _bore_pattern(index: int) -> void:
	var target := _player_pos()
	if index == 0:
		_do_straight_bore(target)
	else:
		_do_double_bore(target)


func _do_straight_bore(target: Vector2) -> void:
	_spawn_telegraph_ground_crack(global_position, target, BORE_TELEGRAPH)
	get_tree().create_timer(BORE_TELEGRAPH, false).timeout.connect(func():
		if not is_instance_valid(self): return
		_begin_charge(target, 0.7, 900.0))


func _do_double_bore(target: Vector2) -> void:
	var dir := (target - global_position).normalized()
	var a1 := dir.rotated(deg_to_rad(30.0)) * 200 + global_position
	var a2 := dir.rotated(deg_to_rad(-30.0)) * 200 + global_position
	_spawn_telegraph_ground_crack(global_position, a1, BORE_TELEGRAPH)
	get_tree().create_timer(BORE_TELEGRAPH, false).timeout.connect(func():
		if not is_instance_valid(self): return
		_begin_charge(a1, 0.35, 900.0))
	get_tree().create_timer(BORE_TELEGRAPH + 0.4, false).timeout.connect(func():
		if not is_instance_valid(self): return
		_begin_charge(a2, 0.35, 900.0))


func _begin_charge(target: Vector2, duration: float, accel: float) -> void:
	_charge_active = true
	_charge_target = target
	_charge_accel = accel
	_charge_remaining = duration
	_lock_navigation(true)


var _charge_active: bool = false
var _charge_target: Vector2 = Vector2.ZERO
var _charge_accel: float = 900.0
var _charge_remaining: float = 0.0


func _tick_phase(delta: float) -> void:
	if _charge_active:
		_charge_remaining -= delta
		_steer_toward(_charge_target, _charge_accel, delta)
		if _charge_remaining <= 0.0:
			_charge_active = false
			_lock_navigation(false)


func _mine_pattern(index: int) -> void:
	if index == 0:
		for i in 4:
			var off := Vector2(randf_range(-90, 90), randf_range(-90, 90))
			_spawn_prop(MINE_SCENE, global_position + off)
	else:
		for gx in 4:
			for gy in 4:
				var pos := global_position + Vector2((gx - 1.5) * 40, (gy - 1.5) * 40)
				_spawn_prop(MINE_SCENE, pos)


func _wall_pattern(index: int) -> void:
	if index == 0:
		for i in 6:
			var off := Vector2(randf_range(-100, 100), randf_range(-100, 100))
			_stamp_material(global_position + off, PILLAR_RADIUS, MaterialRegistry.MAT_STONE)
	else:
		var dir := (_player_pos() - global_position).normalized()
		var perp := dir.rotated(deg_to_rad(90))
		for i in 5:
			var t := float(i) / 5.0 * 160.0
			_stamp_material(global_position + dir * t + perp * 30, PILLAR_RADIUS, MaterialRegistry.MAT_STONE)
			_stamp_material(global_position + dir * t - perp * 30, PILLAR_RADIUS, MaterialRegistry.MAT_STONE)
		_begin_charge(_player_pos(), 0.6, 900.0)


func _spawn_telegraph_ground_crack(start: Vector2, end: Vector2, duration: float) -> void:
	BossTelegraph.ground_crack_line(get_parent(), start, end, duration)
