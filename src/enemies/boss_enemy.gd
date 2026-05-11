class_name BossEnemy
extends Enemy

@export var boss_name: String = "Boss"
@export var phase_count: int = 3
@export var weapon_resource: RangedWeapon = null
@export var hazard_interval: float = 5.0
@export var hazard_count: int = 3
@export var hazard_duration: float = 10.0
@export var hazard_damage: float = 5.0

var current_phase: int = 1
var _original_weapon: RangedWeapon = null
var _hazard_timer: float = 0.0


func _ready() -> void:
	if weapon_resource:
		weapon = weapon_resource.duplicate()
		_original_weapon = weapon_resource.duplicate()
		_attack_range = 200.0
		cooldown_duration = weapon.cooldown
	else:
		weapon = RangedWeapon.new()
		weapon.damage = 6.0
		weapon.cooldown = 0.8
		weapon.projectile_speed = 120.0
		_original_weapon = RangedWeapon.new()
		_attack_range = 200.0
		cooldown_duration = weapon.cooldown
	speed = 40.0
	max_health = 200
	_speed_base = speed
	detection_radius = 400.0
	scale = Vector2(2.0, 2.0)
	super._ready()
	_setup_drop_table()
	_hazard_timer = hazard_interval


func _setup_drop_table() -> void:
	drop_table = DropTable.from_enemy_tier(enemy_tier, true, true, true)
	drop_table.add_entry(DropTable.DropEntry.modifier_pool(1.0, DropTable.ItemTier.RARE, 1, 1))


func _process(delta: float) -> void:
	super._process(delta)
	if current_phase == 3 and _state != State.DEATH:
		_hazard_timer -= delta
		if _hazard_timer <= 0.0:
			_hazard_timer = hazard_interval
			_spawn_hazards()


func hit(damage: int) -> void:
	super.hit(damage)
	if _state != State.DEATH:
		_check_phase_transition()


func _check_phase_transition() -> void:
	while current_phase < phase_count and health <= _phase_threshold(current_phase + 1):
		current_phase += 1
		_transition_phase()


func _phase_threshold(p: int) -> int:
	return int(float(max_health) * float(phase_count - p + 1) / float(phase_count))


func _transition_phase() -> void:
	match current_phase:
		2:
			if weapon and weapon is RangedWeapon:
				(weapon as RangedWeapon).projectile_count = 3
				(weapon as RangedWeapon).spread_angle = 30.0
		3:
			_hazard_timer = hazard_interval


func _execute_attack() -> void:
	if weapon and _player_ref and is_instance_valid(_player_ref):
		weapon.use(self)


func _spawn_hazards() -> void:
	for i in range(hazard_count):
		var offset := Vector2(randf_range(-80, 80), randf_range(-80, 80))
		var pos := global_position + offset
		TerrainSurface.place_lava(pos, 4.0)
