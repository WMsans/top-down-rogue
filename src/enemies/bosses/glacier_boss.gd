class_name GlacierBoss
extends BossEnemy

const SHARD_TELEGRAPH := 0.3
const NOVA_TELEGRAPH := 0.8
const PILLAR_RADIUS := 6.0
const RING_RADIUS := 70.0

var _test_player_pos: Vector2 = Vector2(-9999, -9999)


func _ready() -> void:
	boss_name = "Glacier Titan"
	var w := WeaponRegistry.get_weapon_by_id("boss_staff")
	weapon_resource = w.duplicate() if w else null
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
		1: attack_interval = 1.0
		2: attack_interval = 1.4
		3: attack_interval = 1.6


func _execute_pattern(phase: int, index: int) -> void:
	match phase:
		1: _shard_pattern(index)
		2: _chill_pattern(index)
		3: _pillar_pattern(index)


func _shard_pattern(index: int) -> void:
	if index == 0:
		_fire_shards(1, 1)
	else:
		_fire_shards(3, 3)


func _fire_shards(count: int, burst: int) -> void:
	_spawn_telegraph_expanding(global_position, 14.0, SHARD_TELEGRAPH)
	if weapon == null:
		return
	var clone := (weapon as RangedWeapon).duplicate()
	clone.projectile_count = count
	clone.burst_count = burst
	clone.burst_interval = 0.08
	await get_tree().create_timer(SHARD_TELEGRAPH, false).timeout
	if is_instance_valid(self) and _player_ref and is_instance_valid(_player_ref):
		clone.use(self)


func _chill_pattern(index: int) -> void:
	if index == 0:
		var pos := _player_pos()
		_spawn_telegraph_expanding(pos, 24.0, NOVA_TELEGRAPH)
		get_tree().create_timer(NOVA_TELEGRAPH, false).timeout.connect(func():
			if is_instance_valid(self): _stamp_material(pos, PILLAR_RADIUS, MaterialRegistry.MAT_ICE))
	else:
		_spawn_telegraph_expanding(global_position, RING_RADIUS, NOVA_TELEGRAPH)
		get_tree().create_timer(NOVA_TELEGRAPH, false).timeout.connect(func():
			if is_instance_valid(self): _stamp_material_ring(global_position, RING_RADIUS - 16.0, RING_RADIUS, MaterialRegistry.MAT_ICE))


func _pillar_pattern(index: int) -> void:
	if index == 0:
		var target := _player_pos()
		var dir := (target - global_position)
		var steps := 5
		for i in steps:
			var t := float(i + 1) / float(steps + 1)
			var pos := global_position.lerp(target, t)
			_spawn_telegraph_column(pos, 24.0, 0.5)
			var ip := pos
			get_tree().create_timer(0.5, false).timeout.connect(func():
				if is_instance_valid(self): _stamp_material(ip, PILLAR_RADIUS, MaterialRegistry.MAT_ICE))
	else:
		var center := _player_pos()
		var gap := randi() % 8
		for i in 8:
			if i == gap:
				continue
			var a := float(i) / 8.0 * TAU
			var pos := center + Vector2(cos(a), sin(a)) * RING_RADIUS
			_stamp_material(pos, PILLAR_RADIUS, MaterialRegistry.MAT_ICE)


func _spawn_telegraph_expanding(center: Vector2, radius: float, duration: float) -> void:
	BossTelegraph.expanding_circle(get_parent(), center, radius, duration)

func _spawn_telegraph_column(base: Vector2, height: float, duration: float) -> void:
	BossTelegraph.column_rise(get_parent(), base, height, duration)
