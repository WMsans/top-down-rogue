class_name DummyEnemy
extends Enemy

var _player: Node = null


func _ready() -> void:
	super._ready()
	_sprite_modulate_green()
	_setup_drop_table()
	_player = get_tree().get_first_node_in_group("player")


func _sprite_modulate_green() -> void:
	_set_base_modulate(Color(0.2, 0.8, 0.2))


func _setup_drop_table() -> void:
	drop_table = DropTable.from_enemy_tier(enemy_tier)


func _process(delta: float) -> void:
	global_position += _knockback_velocity * delta
	_tick_knockback(delta)
	if _player == null or not is_instance_valid(_player):
		return
	var dir: Vector2 = _player.global_position - global_position
	if dir.length() < 4.0:
		return
	global_position += dir.normalized() * speed * delta


func _on_hit() -> void:
	super._on_hit()