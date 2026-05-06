class_name FogOfWar
extends Node

const RAYCAST_MASK := 1        # terrain collision layer
const LIGHT_EDGE_BUFFER := 1.2 # check lights out to 1.2× range for smooth fade
const SMOOTH_SPEED := 10.0     # alpha interpolation speed
const BUCKET_SIZE := 256.0     # spatial bucket cell size (matches chunk)
const CHECK_EVERY := 2         # throttle full evaluation to every N frames
const CACHE_THRESHOLD := 4.0   # skip raycast if entity moved < this px since last check

## {instance_id: {position: Vector2, target_alpha: float}}
var _visibility_cache: Dictionary = {}
var _chunk_lights_nodes: Array[WeakRef] = []
var _player_lights: Array[Dictionary] = []   # [{node: WeakRef, range: float}]
var _entities: Array[WeakRef] = []
var _frame_counter: int = 0
var _terrain_container: Node2D


func _ready() -> void:
	add_to_group("fog_of_war")
	var wm := get_tree().get_first_node_in_group("world_manager")
	if wm:
		_terrain_container = wm.get_node_or_null("CollisionContainer")


func register(entity: Node2D) -> void:
	for ref in _entities:
		var e := ref.get_ref()
		if e == entity:
			return
	_entities.append(weakref(entity))


func unregister(entity: Node2D) -> void:
	for i in range(_entities.size() - 1, -1, -1):
		var e := _entities[i].get_ref()
		if e == null or e == entity:
			_entities.remove_at(i)
			if e == entity:
				_visibility_cache.erase(entity.get_instance_id())
				return


func register_player_light(light: Node2D, p_range: float) -> void:
	for entry in _player_lights:
		var existing: Node2D = entry.node.get_ref()
		if existing == light:
			entry.range = p_range
			return
	_player_lights.append({node = weakref(light), range = p_range})


func register_chunk_lights(p_lights: Node2D) -> void:
	for ref in _chunk_lights_nodes:
		var existing := ref.get_ref()
		if existing == p_lights:
			return
	_chunk_lights_nodes.append(weakref(p_lights))


func unregister_chunk_lights(p_lights: Node2D) -> void:
	for i in range(_chunk_lights_nodes.size() - 1, -1, -1):
		var node := _chunk_lights_nodes[i].get_ref()
		if node == null or node == p_lights:
			_chunk_lights_nodes.remove_at(i)


func _process(delta: float) -> void:
	_frame_counter += 1
	if _frame_counter % CHECK_EVERY != 0:
		_apply_smoothing(delta)
		return

	_evaluate_visibility(delta)


func _evaluate_visibility(delta: float) -> void:
	var active_lights := _collect_active_lights()
	var buckets := _bucket_lights(active_lights)

	var to_remove: Array[int] = []
	for i in range(_entities.size()):
		var ref: WeakRef = _entities[i]
		var entity: Node2D = ref.get_ref()
		if entity == null or not is_instance_valid(entity):
			to_remove.append(i)
			continue

		var target := _compute_visibility(entity, buckets)
		_visibility_cache[entity.get_instance_id()] = {
			position = entity.global_position,
			target_alpha = target,
		}

	for i in range(to_remove.size() - 1, -1, -1):
		_entities.remove_at(to_remove[i])

	_apply_smoothing(delta)


func _apply_smoothing(delta: float) -> void:
	var t := clampf(SMOOTH_SPEED * delta, 0.0, 1.0)
	for ref in _entities:
		var entity: Node2D = ref.get_ref()
		if entity == null or not is_instance_valid(entity):
			continue
		var cache := _visibility_cache.get(entity.get_instance_id(), {})
		var target: float = cache.get("target_alpha", 0.0)
		entity.modulate.a = lerpf(entity.modulate.a, target, t)


func _collect_active_lights() -> Array[Dictionary]:
	var lights: Array[Dictionary] = []

	# player lights
	for entry in _player_lights:
		var light: Node2D = entry.node.get_ref()
		if light == null or not is_instance_valid(light):
			continue
		lights.append({
			position = light.global_position,
			range = entry.range,
		})

	# chunk lights
	for ref in _chunk_lights_nodes:
		var cl: ChunkLights = ref.get_ref()
		if cl == null or not is_instance_valid(cl):
			continue
		var active := cl.get_active_lights()
		for d in active:
			lights.append(d)

	return lights


func _bucket_lights(lights: Array[Dictionary]) -> Dictionary:
	var buckets := {}
	for light in lights:
		var pos: Vector2 = light.position
		var rng: float = light.range * LIGHT_EDGE_BUFFER
		if rng <= 0.0:
			continue
		var min_cell := Vector2i(floori((pos.x - rng) / BUCKET_SIZE), floori((pos.y - rng) / BUCKET_SIZE))
		var max_cell := Vector2i(floori((pos.x + rng) / BUCKET_SIZE), floori((pos.y + rng) / BUCKET_SIZE))
		for cx in range(min_cell.x, max_cell.x + 1):
			for cy in range(min_cell.y, max_cell.y + 1):
				var cell := Vector2i(cx, cy)
				if not buckets.has(cell):
					buckets[cell] = []
				buckets[cell].append(light)
	return buckets


func _compute_visibility(entity: Node2D, buckets: Dictionary) -> float:
	var epos := entity.global_position

	var cache := _visibility_cache.get(entity.get_instance_id(), {})
	var cached_pos: Vector2 = cache.get("position", Vector2.INF)
	if cache.has("target_alpha") and epos.distance_squared_to(cached_pos) < CACHE_THRESHOLD * CACHE_THRESHOLD:
		return cache.target_alpha

	var max_visibility := 0.0
	var cell := Vector2i(floori(epos.x / BUCKET_SIZE), floori(epos.y / BUCKET_SIZE))

	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var key := Vector2i(cell.x + dx, cell.y + dy)
			var cell_lights: Array = buckets.get(key, [])
			for light in cell_lights:
				var lpos: Vector2 = light.position
				var lrange: float = light.range
				var dist := epos.distance_to(lpos)
				if dist > lrange * LIGHT_EDGE_BUFFER:
					continue
				if not _raycast_clear(epos, lpos, entity):
					continue
				var vis := clampf(1.0 - dist / lrange, 0.0, 1.0)
				if vis > max_visibility:
					max_visibility = vis
					if max_visibility >= 1.0:
						return 1.0

	return max_visibility


func _raycast_clear(from: Vector2, to: Vector2, entity: Node2D) -> bool:
	var world := get_world_2d()
	if world == null:
		return true  # not in tree yet, assume visible
	var space_state := world.direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = RAYCAST_MASK
	if entity is CollisionObject2D:
		query.exclude = [entity.get_rid()]

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return true

	var collider: Node = result.collider
	return not _is_terrain_body(collider)


func _is_terrain_body(collider: Node) -> bool:
	if _terrain_container == null:
		return false
	var node: Node = collider
	while node != null:
		if node == _terrain_container:
			return true
		node = node.get_parent()
	return false
