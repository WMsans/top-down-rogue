class_name MageEnemy
extends RangedEnemy

const HP_MULT: float = 0.9
const SPEED_MULT: float = 0.6
const MAGE_ATTACK_RANGE: float = 220.0
const MAGE_WINDUP: float = 0.8

const MAGE_NORMAL: Texture2D = preload("res://textures/Enemies/caves/mage/caves_mage1.png")
const MAGE_BREATHE: Texture2D = preload("res://textures/Enemies/caves/mage/caves_mage2.png")


func _ready() -> void:
	if weapon_resource == null:
		weapon_resource = WeaponRegistry.get_weapon_by_id("seeker_launcher")
	super._ready()
	max_health = int(float(max_health) * HP_MULT)
	health = max_health
	speed = _speed_base * SPEED_MULT
	_speed_base = speed
	_attack_range = MAGE_ATTACK_RANGE
	windup_duration = MAGE_WINDUP


func _select_sprite_textures() -> Array:
	return [MAGE_NORMAL, MAGE_BREATHE]


func _process_chase(_delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		_change_state(State.WANDER)
		return
	if not _player_in_range or not _can_see_player():
		_change_state(State.WANDER)
		return

	var to_player := _player_ref.global_position - global_position
	var dist := to_player.length()
	if dist <= _attack_range:
		velocity = Vector2.ZERO
		_change_state(State.WINDUP)
		return

	var move_dir := _safe_normalized(to_player)
	move_dir = _apply_separation(move_dir)
	velocity = move_dir * _get_effective_speed()
