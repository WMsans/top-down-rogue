class_name StatusComponent
extends Node

# Per-entity status holder. Attached as a child named "StatusComponent" to the
# player and every enemy. Holds "stain" amounts, decays them, runs reactions,
# applies effects (burn DoT, movement block/slow), and tops up stains from the
# terrain the owner stands on. Owner must implement apply_status_damage(int).

signal changed
signal burn_tick  # emitted each time a whole point of burn damage lands

const _EPSILON := 0.01

# Body footprint half-extents (px) sampled as a grid when polling terrain, so the
# owner picks up stains from any source cell its body overlaps (not just its
# centre). See _HISTORY_FRAMES for how the latent probe is handled while moving.
const _FOOTPRINT_HALF := Vector2(4.0, 6.0)
const _SAMPLE_STEPS := 2
# The terrain probe is several frames latent: a cell queried this frame reads back
# AIR and only returns its real material once a later frame's GPU read-back lands.
# A standing owner re-samples the same cells until they warm, so it accumulates
# stain; a moving owner steps onto a fresh (cold) cell every frame and, sampling
# only its current footprint, would never read terrain back. We also re-sample the
# footprints of the last few frames' positions — those cells were primed then and
# are warm now — so terrain just walked over still applies. Must exceed the probe
# read-back latency in frames for a moving owner to ever get a warm hit.
const _HISTORY_FRAMES := 3
# Terrain polling is the dominant per-entity cost. Run it every POLL_INTERVAL
# render frames (not physics steps), spread across entities by a per-instance
# phase, accumulating delta so stain rates are unchanged. See the design doc
# 2026-06-05-status-performance-spiral-design.md.
const POLL_INTERVAL := 4

var _stains: Dictionary = {}      # id -> float amount
var _burn_accum: float = 0.0
var _owner_node: Node = null
var _terrain_physical: Node = null
var _origin_history: Array[Vector2] = []  # recent poll positions, oldest first
var _frame_counter: int = 0
var _poll_phase: int = 0           # which frame-in-interval this component polls on
var _accum_poll_delta: float = 0.0  # delta accumulated since the last terrain poll


func _ready() -> void:
	_owner_node = get_parent()
	var wm: Node = get_tree().get_first_node_in_group("world_manager")
	if wm != null:
		_terrain_physical = wm.get_node_or_null("TerrainPhysical")
	_poll_phase = int(get_instance_id() % POLL_INTERVAL)


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


func get_blended_tint() -> Color:
	var ids: Array = get_active_ids()
	if ids.is_empty():
		return Color.WHITE
	var c: Color = Color.WHITE
	for id in ids:
		c = c.lerp(StatusRegistry.get_tint(id), 0.5)
	return c


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


func _process(delta: float) -> void:
	update(delta)


# Per-frame entry. tick() (decay/reactions/burn) runs every frame; the heavy
# terrain poll runs once per POLL_INTERVAL frames and is handed the accumulated
# delta so accumulation totals match an every-frame poll.
func update(delta: float) -> void:
	_accum_poll_delta += delta
	_frame_counter += 1
	if (_frame_counter % POLL_INTERVAL) == _poll_phase:
		_poll_terrain(_accum_poll_delta)
		_accum_poll_delta = 0.0
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
			burn_tick.emit()
			if _owner_node != null and _owner_node.has_method("apply_status_damage"):
				_owner_node.apply_status_damage(whole)


func _poll_terrain(delta: float) -> void:
	if _terrain_physical == null or _owner_node == null:
		return
	if not (_owner_node is Node2D):
		return
	var origin: Vector2 = (_owner_node as Node2D).global_position
	# Look ahead along movement so the cells we're about to enter get primed.
	var look_ahead := Vector2.ZERO
	if "velocity" in _owner_node:
		look_ahead = (_owner_node.velocity as Vector2) * delta

	# Sample the footprint at the current position (primes cells, reads any already
	# warm), one step ahead (primes the approach), and at recent positions (warm now
	# from earlier frames). Dedupe sample origins by cell so a stationary owner
	# collapses to a single footprint and the probe budget isn't wasted.
	var origins: Array[Vector2] = []
	var seen_cells := {}
	for past in _origin_history:
		_add_sample_origin(origins, seen_cells, past)
	_add_sample_origin(origins, seen_cells, origin)
	_add_sample_origin(origins, seen_cells, origin + look_ahead)

	# Collect each distinct stain once so the rate is independent of sample count.
	var ids := {}
	for so in origins:
		for iy in _SAMPLE_STEPS:
			var fy: float = lerpf(-_FOOTPRINT_HALF.y, _FOOTPRINT_HALF.y, float(iy) / (_SAMPLE_STEPS - 1))
			for ix in _SAMPLE_STEPS:
				var fx: float = lerpf(-_FOOTPRINT_HALF.x, _FOOTPRINT_HALF.x, float(ix) / (_SAMPLE_STEPS - 1))
				var cell = _terrain_physical.query(so + Vector2(fx, fy))
				if cell == null:
					continue
				var id: String = StatusRegistry.stain_for_material(cell.material_id)
				if id != "":
					ids[id] = true

	# Remember this position so the next few frames can re-sample its (now warm) cells.
	_origin_history.append(origin)
	while _origin_history.size() > _HISTORY_FRAMES:
		_origin_history.pop_front()

	for id in ids:
		add_stain(id, StatusRegistry.TERRAIN_STAIN_RATE * delta)


func _add_sample_origin(origins: Array[Vector2], seen_cells: Dictionary, pos: Vector2) -> void:
	var key := Vector2i(floori(pos.x), floori(pos.y))
	if seen_cells.has(key):
		return
	seen_cells[key] = true
	origins.append(pos)
