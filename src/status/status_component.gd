class_name StatusComponent
extends Node

# Per-entity status holder. Attached as a child named "StatusComponent" to the
# player and every enemy. Holds "stain" amounts, decays them, runs reactions,
# applies effects (burn DoT, movement block/slow), and tops up stains from the
# terrain the owner stands on. Owner must implement apply_status_damage(int).

signal changed

const _EPSILON := 0.01

var _stains: Dictionary = {}      # id -> float amount
var _burn_accum: float = 0.0
var _owner_node: Node = null
var _terrain_physical: Node = null


func _ready() -> void:
	_owner_node = get_parent()
	var wm: Node = get_tree().get_first_node_in_group("world_manager")
	if wm != null:
		_terrain_physical = wm.get_node_or_null("TerrainPhysical")


# --- Stain access ---

func add_stain(id: String, amount: float) -> void:
	if amount == 0.0:
		return
	_stains[id] = maxf(0.0, get_stain(id) + amount)
	changed.emit()


func reduce_stain(id: String, amount: float) -> void:
	# Silent (no signal): used by reactions/decay which run every frame.
	if not _stains.has(id):
		return
	var v: float = _stains[id] - amount
	if v <= _EPSILON:
		_stains.erase(id)
	else:
		_stains[id] = v


func get_stain(id: String) -> float:
	return _stains.get(id, 0.0)


func has_status(id: String) -> bool:
	return get_stain(id) >= StatusRegistry.get_threshold(id)


func get_active_ids() -> Array:
	var result: Array = []
	for id in _stains.keys():
		if has_status(id):
			result.append(id)
	return result


func clear(id: String) -> void:
	if _stains.erase(id):
		changed.emit()


# --- Movement ---

func get_move_speed_multiplier() -> float:
	var mult: float = 1.0
	for id in _stains.keys():
		if not has_status(id):
			continue
		if StatusRegistry.blocks_movement(id):
			return 0.0
		mult = minf(mult, StatusRegistry.get_slow_multiplier(id))
	return mult


func is_movement_blocked() -> bool:
	return is_zero_approx(get_move_speed_multiplier())


# --- Per-frame update ---

func tick(delta: float) -> void:
	_decay(delta)
	StatusRegistry.apply_reactions(self, delta)
	_apply_effects(delta)
	changed.emit()


func _physics_process(delta: float) -> void:
	_poll_terrain(delta)
	tick(delta)


func _decay(delta: float) -> void:
	for id in _stains.keys():
		reduce_stain(id, StatusRegistry.get_decay_rate(id) * delta)


func _apply_effects(delta: float) -> void:
	if has_status("on_fire"):
		_burn_accum += StatusRegistry.get_burn_dps("on_fire") * delta
		var whole: int = int(_burn_accum)
		if whole >= 1:
			_burn_accum -= float(whole)
			if _owner_node != null and _owner_node.has_method("apply_status_damage"):
				_owner_node.apply_status_damage(whole)


func _poll_terrain(delta: float) -> void:
	if _terrain_physical == null or _owner_node == null:
		return
	if not (_owner_node is Node2D):
		return
	var cell = _terrain_physical.query((_owner_node as Node2D).global_position)
	if cell == null:
		return
	var id: String = StatusRegistry.stain_for_material(cell.material_id)
	if id != "":
		add_stain(id, StatusRegistry.TERRAIN_STAIN_RATE * delta)
