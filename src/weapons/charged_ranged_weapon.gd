class_name ChargedRangedWeapon
extends RangedWeapon

@export var charge_time_full: float = 0.7
@export var charge_damage_mult: float = 2.0

var _charge_time: float = 0.0
var _charging: bool = false
var _current_user: Node = null


func get_charge_ratio() -> float:
	return clampf(_charge_time / charge_time_full, 0.0, 1.0)


func is_chargeable() -> bool:
	return true


func is_charging() -> bool:
	return _charging


func on_press(user: Node) -> void:
	if not is_ready():
		return
	_current_user = user
	_charging = true
	_charge_time = 0.0


func on_release(user: Node) -> void:
	if not _charging:
		return
	_charging = false
	_current_user = user
	if get_charge_ratio() >= 1.0:
		_fire_charged(user)


func _fire_charged(user: Node) -> void:
	for m in modifiers:
		if m != null:
			m.on_use(self, user)
	_emit_shot(user, _get_facing_direction(user))
	_cooldown_timer = get_effective_stats()["cooldown"]


func _tick_impl(delta: float) -> void:
	super._tick_impl(delta)
	if _charging:
		_charge_time = minf(_charge_time + delta, charge_time_full)
