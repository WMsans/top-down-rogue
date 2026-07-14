class_name BossEnemy
extends Enemy

signal phase_changed(phase: int)
signal boss_ready

@export var boss_name: String = "Boss"
@export var phase_count: int = 3
@export var weapon_resource: Weapon = null
@export var attack_interval: float = 1.2
@export var hazard_interval: float = 5.0

var current_phase: int = 1
var encounter_active: bool = true

var _pattern_index: int = 0
var _nav_locked: bool = false
var _boss_attack_range: float = 200.0


func _ready() -> void:
	if weapon_resource:
		weapon = weapon_resource.duplicate()
		_boss_attack_range = 200.0
	else:
		weapon = null
		_boss_attack_range = 0.0
	speed = 40.0
	max_health = 200
	health = max_health
	_speed_base = speed
	detection_radius = 400.0
	scale = Vector2(2.0, 2.0)
	super._ready()
	_setup_drop_table()
	boss_ready.emit()


func _setup_drop_table() -> void:
	drop_table = DropTable.from_enemy_tier(enemy_tier, true, true, true)
	drop_table.add_entry(DropTable.DropEntry.modifier_pool(1.0, DropTable.ItemTier.RARE, 1, 1))
	drop_table.add_entry(DropTable.DropEntry.gold(1.0, 5, 8, 10))


# Boss combat flows through the Enemy AI state machine: when the AI transitions
# to the ATTACK state it calls _execute_attack(). The base dispatches into the
# phase/pattern machinery. encounter_active = false (controller, during intro)
# suppresses attacks and movement so the boss stands still.
func _execute_attack() -> void:
	if not encounter_active:
		return
	var idx := _pick_pattern(current_phase)
	_execute_pattern(current_phase, idx)


func _process(delta: float) -> void:
	if not encounter_active and _state != State.DEATH:
		# Idle: no AI, no phase ticking, no attacks during intro.
		return
	if _nav_locked:
		_call_enemy_process_minimal(delta)
	else:
		super._process(delta)
	if _state != State.DEATH:
		_tick_phase(delta)


# Minimal Enemy-tick path used while navigation is locked (subclass steering).
# Runs knockback + death/hurt state timers so charges don't desync the Enemy
# base machinery; chase/wander/windup/attack/cooldown are skipped because the
# subclass owns velocity directly.
func _call_enemy_process_minimal(delta: float) -> void:
	if _state == State.DEATH:
		_process_death(delta)
		return
	_tick_knockback(delta)
	if _state == State.HURT:
		_process_hurt(delta)


func _pick_pattern(phase: int) -> int:
	var count := _pattern_count(phase)
	if count <= 1:
		_pattern_index = 0
		return 0
	var idx := _pattern_index % count
	_pattern_index = (_pattern_index + 1) % count
	return idx


func _pattern_count(_phase: int) -> int:
	return 1


func _execute_pattern(_phase: int, _index: int) -> void:
	_do_attack()


func _do_attack() -> void:
	if weapon != null and _player_ref != null and is_instance_valid(_player_ref):
		var d := global_position.distance_to(_player_ref.global_position)
		if d <= _boss_attack_range:
			weapon.use(self)


func _tick_phase(_delta: float) -> void:
	# Override per subclass for per-frame phase behavior (magnet, trail, hazards).
	pass


func _on_phase_enter(_phase: int) -> void:
	# Override per subclass; called once after current_phase is set.
	pass


func hit(damage: int) -> void:
	super.hit(damage)
	if _state != State.DEATH:
		_check_phase_transition()


func _check_phase_transition() -> void:
	while current_phase < phase_count and health <= _phase_threshold(current_phase + 1):
		current_phase += 1
		_transition_phase()
		_on_phase_enter(current_phase)
		phase_changed.emit(current_phase)


func _phase_threshold(p: int) -> int:
	return int(float(max_health) * float(phase_count - p + 1) / float(phase_count))


# Base no-op. Subclasses configure phase-specific state via _on_phase_enter.
func _transition_phase() -> void:
	pass


func set_encounter_active(active: bool) -> void:
	encounter_active = active


func _apply_floor_scaling(floor_num: int) -> void:
	var hp_mult := 1.0 + (floor_num - 1) * 0.20
	var sp_mult := 1.0 + (floor_num - 1) * 0.10
	var dmg_mult := 1.0 + (floor_num - 1) * 0.15
	max_health = int(round(float(max_health) * hp_mult))
	health = max_health
	speed *= sp_mult
	_speed_base = speed
	if weapon_resource:
		weapon_resource.damage *= dmg_mult
	if weapon:
		weapon.damage *= dmg_mult
	if has_signal("health_changed"):
		health_changed.emit(health, max_health)


# --- Movement hooks for charge subclasses ---

# Sets velocity toward `target`; the Enemy _physics_process performs the actual
# collision-stepped movement. Subclasses call _lock_navigation(true) first so
# super._process does not overwrite velocity with chase logic.
func _steer_toward(target: Vector2, accel: float, delta: float) -> void:
	var to := target - global_position
	if to.length_squared() > 1.0:
		var desired := to.normalized() * speed
		velocity = velocity.lerp(desired, clampf(accel * delta, 0.0, 1.0))


func _lock_navigation(locked: bool) -> void:
	_nav_locked = locked


# --- Facade: subclasses call these instead of touching singletons ---

func _stamp_material(pos: Vector2, radius: float, mat_id: int) -> void:
	CompositionDispatcher.stamp_material_blob(pos, radius, mat_id, 0, 0.0)


func _stamp_material_ring(pos: Vector2, inner: float, outer: float, mat_id: int) -> void:
	CompositionDispatcher.stamp_material_ring(pos, inner, outer, mat_id)


func _apply_status(target: Node, status_id: String, amount: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var sc = target.get_node_or_null("StatusComponent")
	if sc and sc.has_method("add_stain"):
		sc.add_stain(status_id, amount)


func _spawn_minion(scene: PackedScene, world_pos: Vector2, is_elite: bool) -> void:
	CompositionDispatcher.spawn_enemy(world_pos, scene, is_elite)


func _spawn_prop(scene: PackedScene, world_pos: Vector2) -> void:
	CompositionDispatcher.spawn_prop(world_pos, scene)


func _roll_weapon_modifier() -> void:
	pass


func _spawn_drops() -> void:
	if drop_table:
		drop_table.resolve(global_position, get_parent(), 1.0)
	if weapon:
		_spawn_weapon_drop()