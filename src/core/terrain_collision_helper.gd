class_name TerrainCollisionHelper
extends RefCounted

const CHUNK_SIZE := 256
const MAX_DISPATCH_PER_FRAME := 4

var world_manager  # WorldManager (Node2D)

var _dirty_chunks: Dictionary = {}             # Vector2i -> true
var _in_flight: Array = []                     # Array[Vector2i] dispatched last frame
var _pending_collision_builds: Array = []      # Array[Vector2i] ready to build shapes
var _pending_occluder_builds: Array = []       # Array[Vector2i] ready to build occluders
var _pending_segments: Dictionary = {}         # Vector2i -> PackedVector2Array
var _dispatch_cursor: int = 0


func mark_dirty(coord: Vector2i) -> void:
	_dirty_chunks[coord] = true


func on_chunk_unloaded(coord: Vector2i) -> void:
	_dirty_chunks.erase(coord)
	_in_flight.erase(coord)
	_pending_collision_builds.erase(coord)
	_pending_occluder_builds.erase(coord)
	_pending_segments.erase(coord)


func rebuild_dirty(chunks: Dictionary, _delta: float) -> void:
	# 1. Consume prior frame's readback.
	_consume_readback(chunks)

	# 2. Amortize: drain one occluder build per frame.
	_drain_one_occluder(chunks)

	# 3. Drain all pending collision shape builds.
	_drain_collision_builds(chunks)

	# 4. Dispatch up to MAX_DISPATCH_PER_FRAME newly-selected dirty chunks.
	_dispatch_next_batch(chunks)


func _consume_readback(chunks: Dictionary) -> void:
	var compute = world_manager.compute_device
	var readback: Dictionary = compute.read_collider_buffer_coalesced()
	_in_flight.clear()
	for coord in readback:
		if not chunks.has(coord):
			continue
		var segments: PackedVector2Array = readback[coord]
		_pending_segments[coord] = segments
		_pending_collision_builds.append(coord)
		_pending_occluder_builds.append(coord)


func _dispatch_next_batch(chunks: Dictionary) -> void:
	if _dirty_chunks.is_empty():
		world_manager.compute_device.dispatch_collider_pack(chunks, [])
		return

	var coords: Array = []
	var keys: Array = _dirty_chunks.keys()
	# Stable selection: take up to MAX in iteration order, skipping unloaded chunks.
	for k in keys:
		if coords.size() >= MAX_DISPATCH_PER_FRAME:
			break
		if not chunks.has(k):
			_dirty_chunks.erase(k)
			continue
		coords.append(k)

	for c in coords:
		_dirty_chunks.erase(c)

	world_manager.compute_device.dispatch_collider_pack(chunks, coords)
	_in_flight = coords


func _drain_collision_builds(chunks: Dictionary) -> void:
	for coord in _pending_collision_builds:
		if not chunks.has(coord):
			_pending_segments.erase(coord)
			continue
		var chunk: Chunk = chunks[coord]
		var segments: PackedVector2Array = _pending_segments.get(coord, PackedVector2Array())
		_build_collision_shape(chunk, segments)
	_pending_collision_builds.clear()


func _drain_one_occluder(chunks: Dictionary) -> void:
	while not _pending_occluder_builds.is_empty():
		var coord: Vector2i = _pending_occluder_builds[0]
		_pending_occluder_builds.remove_at(0)
		if not chunks.has(coord):
			continue
		var chunk: Chunk = chunks[coord]
		var segments: PackedVector2Array = _pending_segments.get(coord, PackedVector2Array())
		_build_occluders(chunk, segments)
		# Clear segments only after both queues consumed.
		if not _pending_collision_builds.has(coord):
			_pending_segments.erase(coord)
		return  # Only one per frame.


func _build_collision_shape(chunk: Chunk, segments: PackedVector2Array) -> void:
	# Clear old collision children.
	for child in chunk.static_body.get_children():
		child.queue_free()

	if segments.size() < 4:
		return

	var world_offset := chunk.coord * CHUNK_SIZE
	var collision_shape := TerrainCollider.build_from_segments(segments, chunk.static_body, world_offset)
	if collision_shape != null:
		chunk.static_body.add_child(collision_shape)


func _build_occluders(chunk: Chunk, segments: PackedVector2Array) -> void:
	for occluder in chunk.occluder_instances:
		if is_instance_valid(occluder):
			occluder.queue_free()
	chunk.occluder_instances.clear()

	if segments.size() < 4:
		return

	var polygons := TerrainCollider.create_occluder_polygons(segments)
	var chunk_pos := Vector2(chunk.coord.x * CHUNK_SIZE, chunk.coord.y * CHUNK_SIZE)
	for poly in polygons:
		var occ := LightOccluder2D.new()
		occ.position = chunk_pos
		occ.occluder = poly
		world_manager.collision_container.add_child(occ)
		chunk.occluder_instances.append(occ)


# CPU fallback retained for explicit invocation (e.g. by manual repair tools).
func rebuild_chunk_collision_cpu(chunk: Chunk) -> void:
	var chunk_data: PackedByteArray = world_manager.rd.texture_get_data(chunk.rd_texture, 0)
	var material_data := PackedByteArray()
	material_data.resize(CHUNK_SIZE * CHUNK_SIZE)
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			var src_idx := (y * CHUNK_SIZE + x) * 4
			var mat: int = chunk_data[src_idx]
			material_data[y * CHUNK_SIZE + x] = mat if MaterialRegistry.has_collider(mat) else 0

	var world_offset := chunk.coord * CHUNK_SIZE
	for child in chunk.static_body.get_children():
		child.queue_free()

	var collision_shape := TerrainCollider.build_collision(material_data, CHUNK_SIZE, chunk.static_body, world_offset)
	if collision_shape != null:
		chunk.static_body.add_child(collision_shape)
