class_name CollisionManager
extends RefCounted

const CHUNK_SIZE := 256
const COLLISION_REBUILD_INTERVAL := 0.2
const COLLISIONS_PER_FRAME := 4

var world_manager: Node2D
var _collision_rebuild_timer: float = 0.0
var _collision_rebuild_index: int = 0


func _init(manager: Node2D) -> void:
	world_manager = manager


func rebuild_dirty_collisions(chunks: Dictionary, delta: float) -> void:
	if chunks.is_empty():
		return

	_collision_rebuild_timer += delta
	if _collision_rebuild_timer < COLLISION_REBUILD_INTERVAL:
		return
	_collision_rebuild_timer = 0.0

	var chunk_coords: Array[Vector2i] = []
	for coord in chunks:
		chunk_coords.append(coord)

	var count := mini(COLLISIONS_PER_FRAME, chunk_coords.size())
	for i in range(count):
		var idx := (_collision_rebuild_index + i) % chunk_coords.size()
		var coord: Vector2i = chunk_coords[idx]
		var chunk: Chunk = chunks[coord]
		var success := rebuild_chunk_collision_gpu(chunk)
		if not success:
			rebuild_chunk_collision_cpu(chunk)

	_collision_rebuild_index = (_collision_rebuild_index + count) % max(1, chunk_coords.size())


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
	if chunk.static_body.get_child_count() > 0:
		for child in chunk.static_body.get_children():
			child.queue_free()

	var collision_shape := TerrainCollider.build_collision(material_data, CHUNK_SIZE, chunk.static_body, world_offset)
	if collision_shape != null:
		chunk.static_body.add_child(collision_shape)


func parse_segment_buffer(data: PackedByteArray, max_offset: int) -> PackedVector2Array:
	var segments := PackedVector2Array()
	var offset := 0
	while offset + 16 <= data.size() and offset < max_offset:
		var x1 := float(data.decode_u32(offset))
		var y1 := float(data.decode_u32(offset + 4))
		var x2 := float(data.decode_u32(offset + 8))
		var y2 := float(data.decode_u32(offset + 12))
		if x1 == 0.0 and y1 == 0.0 and x2 == 0.0 and y2 == 0.0:
			break
		segments.append(Vector2(x1, y1))
		segments.append(Vector2(x2, y2))
		offset += 16
	return segments


func rebuild_chunk_collision_gpu(chunk: Chunk) -> bool:
	var compute: ComputeDevice = world_manager.compute_device
	var buffer_data := PackedByteArray()
	buffer_data.resize(4)
	buffer_data.encode_u32(0, 0)
	world_manager.rd.buffer_update(compute.collider_storage_buffer, 0, buffer_data.size(), buffer_data)

	var uniforms: Array[RDUniform] = []

	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(chunk.rd_texture)
	uniforms.append(u0)

	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u1.binding = 1
	u1.add_id(compute.collider_storage_buffer)
	uniforms.append(u1)

	var uniform_set: RID = world_manager.rd.uniform_set_create(uniforms, compute.collider_shader, 0)

	var compute_list: int = world_manager.rd.compute_list_begin()
	world_manager.rd.compute_list_bind_compute_pipeline(compute_list, compute.collider_pipeline)
	world_manager.rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	world_manager.rd.compute_list_dispatch(compute_list, 16, 16, 1)
	world_manager.rd.compute_list_end()

	world_manager.rd.free_rid(uniform_set)

	var result_data: PackedByteArray = world_manager.rd.buffer_get_data(compute.collider_storage_buffer)
	if result_data.size() < 4:
		return false

	var segment_count: int = result_data.decode_u32(0)
	if segment_count == 0:
		if chunk.static_body.get_child_count() > 0:
			for child in chunk.static_body.get_children():
				child.queue_free()
		return true

	var segments := parse_segment_buffer(result_data.slice(4), segment_count * 4)

	var world_offset := chunk.coord * CHUNK_SIZE
	if chunk.static_body.get_child_count() > 0:
		for child in chunk.static_body.get_children():
			child.queue_free()

	if segments.size() >= 4:
		var collision_shape := TerrainCollider.build_from_segments(
			segments, chunk.static_body, world_offset
		)
		if collision_shape != null:
			chunk.static_body.add_child(collision_shape)

		for occluder in chunk.occluder_instances:
			if is_instance_valid(occluder):
				occluder.queue_free()
		chunk.occluder_instances.clear()

		var occluder_polygons := TerrainCollider.create_occluder_polygons(segments)
		var chunk_pos := Vector2(chunk.coord.x * CHUNK_SIZE, chunk.coord.y * CHUNK_SIZE)
		for poly in occluder_polygons:
			var occ := LightOccluder2D.new()
			occ.position = chunk_pos
			occ.occluder = poly
			world_manager.collision_container.add_child(occ)
			chunk.occluder_instances.append(occ)

	return true
