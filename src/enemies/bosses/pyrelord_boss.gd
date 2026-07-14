class_name PyrelordBoss
extends BossEnemy

const RING_TELEGRAPH := 1.2
const SPIT_TELEGRAPH := 0.8
const ORB_TELEGRAPH := 0.3

var _center: Vector2 = Vector2.ZERO
var _trail_timer: float = 0.0
var _last_pattern_index: int = 0


func _ready() -> void:
	boss_name = "Pyrelord"
	var w := WeaponRegistry.get_weapon_by_id("fire_orb")
	weapon_resource = w.duplicate() if w else null
	super._ready()
	_center = global_position


func _set_center_for_test(c: Vector2) -> void:
	_center = c


func _pattern_count(_phase: int) -> int:
	return 2


func _on_phase_enter(phase: int) -> void:
	match phase:
		1: attack_interval = 1.2
		2:
			attack_interval = 1.0
			_trail_timer = 0.25
		3: attack_interval = 1.4


func _execute_pattern(phase: int, index: int) -> void:
	match phase:
		1: _orb_pattern(index)
		2: _lava_pattern(index)
		3: _ring_pattern(index)


func _orb_pattern(index: int) -> void:
	if index == 0:
		_fire_pattern(1, 0.0)
	else:
		_fire_pattern(3, 30.0)


func _fire_pattern(projectile_count: int, spread: float) -> void:
	_spawn_telegraph_expanding(global_position, 16.0, ORB_TELEGRAPH)
	if weapon == null:
		return
	var clone := (weapon as RangedWeapon).duplicate()
	clone.projectile_count = projectile_count
	clone.spread_angle = spread
	await get_tree().create_timer(ORB_TELEGRAPH, false).timeout
	if is_instance_valid(self) and _player_ref and is_instance_valid(_player_ref):
		clone.use(self)


func _lava_pattern(index: int) -> void:
	_last_pattern_index = index
	if index == 0:
		return
	for i in 3:
		var base := _player_ref.global_position if (_player_ref and is_instance_valid(_player_ref)) else global_position
		var pos := base + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		_spawn_telegraph_expanding(pos, 20.0, SPIT_TELEGRAPH)
		get_tree().create_timer(SPIT_TELEGRAPH, false).timeout.connect(func(): if is_instance_valid(self): _stamp_material(pos, 5.0, MaterialRegistry.MAT_LAVA))


func _ring_pattern(index: int) -> void:
	if index == 0:
		_spawn_telegraph_expanding(_center, 120.0, RING_TELEGRAPH)
		get_tree().create_timer(RING_TELEGRAPH, false).timeout.connect(func():
			if not is_instance_valid(self): return
			_stamp_material_ring(_center, 80.0, 110.0, MaterialRegistry.MAT_LAVA))
	else:
		_spawn_telegraph_expanding(_center, 160.0, RING_TELEGRAPH)
		get_tree().create_timer(RING_TELEGRAPH, false).timeout.connect(func():
			if not is_instance_valid(self): return
			_stamp_material_ring(_center, 40.0, 160.0, MaterialRegistry.MAT_LAVA))


func _tick_phase(delta: float) -> void:
	if current_phase == 2:
		_trail_timer -= delta
		if _trail_timer <= 0.0:
			_trail_timer = 0.25
			_stamp_material(global_position, 4.0, MaterialRegistry.MAT_LAVA)


func _spawn_telegraph_expanding(center: Vector2, radius: float, duration: float) -> void:
	BossTelegraph.expanding_circle(get_parent(), center, radius, duration)
