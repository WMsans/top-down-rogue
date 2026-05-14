class_name DummyEnemy
extends Enemy


func _ready() -> void:
	super._ready()
	_setup_drop_table()
	_set_base_modulate(Color(0.6, 0.6, 0.6))
	speed = 0.0
	_speed_base = 0.0
	max_health = 30
	health = max_health


func _setup_drop_table() -> void:
	drop_table = DropTable.from_enemy_tier(enemy_tier)


func _execute_attack() -> void:
	pass
