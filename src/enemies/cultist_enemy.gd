class_name CultistEnemy
extends MeleeEnemy

const HP_MULT: float = 0.8
const DAMAGE_MULT: float = 0.6

@export var heal_radius: float = 100.0
@export var heal_cooldown: float = 6.0
@export var heal_fraction: float = 0.2

var _heal_timer: float = 0.0
var _callout_label: Label = null


func _ready() -> void:
	super._ready()
	max_health = int(float(max_health) * HP_MULT)
	health = max_health
	if weapon:
		weapon.damage *= DAMAGE_MULT
	wander_enabled = false

	_callout_label = Label.new()
	_callout_label.name = "CalloutLabel"
	_callout_label.text = "Caw cawww"
	_callout_label.position = Vector2(-24, -30)
	_callout_label.add_theme_font_size_override("font_size", 12)
	_callout_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_callout_label.scale = Vector2.ZERO
	_callout_label.z_index = 10
	_callout_label.z_as_relative = false
	add_child(_callout_label)


func _process_idle(delta: float) -> void:
	if _player_ref and is_instance_valid(_player_ref) and _player_in_range:
		_change_state(State.CHASE)
		return

	_heal_timer -= delta
	if _heal_timer <= 0.0:
		var ally := _find_wounded_ally()
		if ally != null:
			_heal_ally(ally)
			_heal_timer = heal_cooldown
			return

	velocity = Vector2.ZERO


func _find_wounded_ally() -> Node:
	if _world_manager == null or not is_instance_valid(_world_manager):
		return null
	var grid = _world_manager.swarm_grid
	if grid == null:
		return null
	var best: Node = null
	var best_dist := heal_radius
	for candidate in grid.query_neighbors(global_position):
		if candidate == self or not is_instance_valid(candidate):
			continue
		if not ("health" in candidate) or not ("max_health" in candidate):
			continue
		if candidate.health >= candidate.max_health:
			continue
		var dist: float = global_position.distance_to(candidate.global_position)
		if dist <= best_dist:
			best = candidate
			best_dist = dist
	return best


func _heal_ally(ally: Node) -> void:
	var heal_amount: int = int(float(ally.max_health) * heal_fraction)
	ally.health = mini(ally.max_health, ally.health + heal_amount)
	if ally.has_signal("health_changed"):
		ally.health_changed.emit(ally.health, ally.max_health)
	_show_callout()


func _show_callout() -> void:
	if _callout_label == null:
		return
	var tween := create_tween()
	tween.tween_property(_callout_label, "scale", Vector2.ONE, 0.1)
	tween.tween_interval(1.0)
	tween.tween_property(_callout_label, "scale", Vector2.ZERO, 0.2)
