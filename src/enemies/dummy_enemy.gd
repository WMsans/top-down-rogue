class_name DummyEnemy
extends Enemy


func _ready() -> void:
	super._ready()
	_assign_default_weapon()
	_setup_drop_table()
	_set_base_modulate(Color(0.2, 0.8, 0.2))


func _assign_default_weapon() -> void:
	weapon = MeleeWeapon.new()
	weapon.cooldown = 0.5
	weapon.damage = 3.0
	_attack_range = 28.0
	speed = 60.0
	max_health = 15
	health = max_health
	_speed_base = speed


func _setup_drop_table() -> void:
	drop_table = DropTable.from_enemy_tier(enemy_tier)


func _execute_attack() -> void:
	if weapon and _player_ref and is_instance_valid(_player_ref):
		weapon.use(self)
