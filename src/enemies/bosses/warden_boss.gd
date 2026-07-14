class_name WardenBoss
extends BossEnemy

class BouncingStaff extends RangedWeapon:
	func _make_behaviors() -> Array:
		var arr := super._make_behaviors()
		arr.append(BounceBehavior.new())
		return arr

const RICOCHET_TELEGRAPH := 0.6
const MAGNET_RADIUS := 220.0
const BRUTE_SCENE := preload("res://scenes/enemies/brute_enemy.tscn")
const GOLD_DROP_SCENE := preload("res://scenes/gold_drop.tscn")


func _ready() -> void:
	boss_name = "Golden Warden"
	var base := WeaponRegistry.get_weapon_by_id("boss_staff")
	if base:
		var staff := BouncingStaff.new()
		staff.projectile_speed = base.projectile_speed
		staff.projectile_lifetime = base.projectile_lifetime
		staff.spread_angle = base.spread_angle
		staff.projectile_count = base.projectile_count
		staff.burst_count = base.burst_count
		staff.burst_interval = base.burst_interval
		staff.hit_status = base.hit_status
		staff.cooldown = base.cooldown
		staff.damage = base.damage
		staff.rarity = base.rarity
		staff.modifier_slot_count = base.modifier_slot_count
		staff.name = base.name
		weapon_resource = staff
	else:
		weapon_resource = null
	super._ready()


func _pattern_count(_phase: int) -> int:
	return 2


func _on_phase_enter(phase: int) -> void:
	match phase:
		1: attack_interval = 1.4
		2: attack_interval = 1.6
		3: attack_interval = 2.0


func _execute_pattern(phase: int, index: int) -> void:
	match phase:
		1: _ricochet_pattern(index)
		2: _magnet_pattern(index)
		3: _adds_pattern(index)


func _ricochet_pattern(index: int) -> void:
	_fire_ricochet(1 if index == 0 else 2)


func _fire_ricochet(count: int) -> void:
	if weapon == null:
		return
	_spawn_telegraph_shockwave(global_position, 8.0, RICOCHET_TELEGRAPH)
	await get_tree().create_timer(RICOCHET_TELEGRAPH, false).timeout
	if not is_instance_valid(self) or not (_player_ref and is_instance_valid(_player_ref)):
		return
	var clone := (weapon as RangedWeapon).duplicate()
	clone.projectile_count = count
	if count == 2:
		clone.spread_angle = 60.0
	clone.use(self)


func _magnet_pattern(index: int) -> void:
	if index == 0:
		_spawn_telegraph_converging(global_position, MAGNET_RADIUS, 0.4, Color(1.0, 0.85, 0.2))
		_magnet_active = true
	else:
		_magnet_active = false
		_spawn_telegraph_shockwave(global_position, MAGNET_RADIUS, 0.4)
		_repulse_pulse()


var _magnet_active: bool = false


func _tick_phase(delta: float) -> void:
	if current_phase != 2 or not _magnet_active:
		return
	if _player_ref == null or not is_instance_valid(_player_ref):
		return
	var to := global_position - _player_ref.global_position
	var d := to.length()
	if d < MAGNET_RADIUS and d > 1.0:
		var ramp := 1.0 - d / MAGNET_RADIUS
		_apply_player_force(to.normalized(), 60.0 * ramp * delta * 60.0)


func _repulse_pulse() -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return
	var dir := (_player_ref.global_position - global_position).normalized()
	_apply_player_force(dir, 280.0)


func _apply_player_force(dir: Vector2, magnitude: float) -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not (p is CharacterBody2D):
		return
	(p as CharacterBody2D).velocity += dir * magnitude


func _adds_pattern(index: int) -> void:
	if index == 0:
		_summon_elite()
	else:
		_gold_rain()


func _summon_elite() -> void:
	var corner := Vector2(global_position.x + 120, global_position.y + 120)
	_spawn_telegraph_shockwave(corner, 24.0, 0.5)
	_spawn_minion(BRUTE_SCENE, corner, true)


func _gold_rain() -> void:
	for i in 3:
		var base := _player_ref.global_position if (_player_ref and is_instance_valid(_player_ref)) else global_position
		var target := base + Vector2(randf_range(-60, 60), randf_range(-60, 60))
		_spawn_telegraph_shockwave(target, 16.0, 0.8)
		_spawn_prop(GOLD_DROP_SCENE, target)


func _spawn_telegraph_shockwave(center: Vector2, radius: float, duration: float) -> void:
	BossTelegraph.shockwave_ring(get_parent(), center, radius, duration)

func _spawn_telegraph_converging(target: Vector2, radius: float, duration: float, tint: Color) -> void:
	BossTelegraph.converging_particles(get_parent(), target, radius, duration, tint)
