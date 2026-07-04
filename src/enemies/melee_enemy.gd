class_name MeleeEnemy
extends Enemy

@export var weapon_resource: MeleeWeapon = null


func _ready() -> void:
	if not carries_weapon:
		weapon = null
		_attack_range = 28.0
		speed = 60.0
		max_health = 15
		_speed_base = speed
		cooldown_duration = 0.8
	elif weapon_resource:
		weapon = weapon_resource.duplicate()
		_attack_range = weapon.weapon_reach
		cooldown_duration = weapon_resource.cooldown
		speed = 60.0
	else:
		weapon = MeleeWeapon.new()
		_attack_range = 28.0
		speed = 60.0
		max_health = 15
		_speed_base = speed
		cooldown_duration = weapon.cooldown
	super._ready()
	_setup_drop_table()


func _setup_drop_table() -> void:
	drop_table = DropTable.from_enemy_tier(enemy_tier)


func _execute_attack() -> void:
	if weapon and _player_ref and is_instance_valid(_player_ref):
		weapon.use(self)
