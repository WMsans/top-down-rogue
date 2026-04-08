class_name ChunkQueue
extends RefCounted

var pending_generation: Array = []  # Array[Dictionary] with {coord, priority}
var pending_generation_keys: Dictionary = {}  # O(1) lookup for deduplication
var pending_texture_reset: Array = []  # Array[Dictionary] with {coord, chunk}
var pending_texture_reset_keys: Dictionary = {}  # O(1) lookup for deduplication
var max_generation_per_frame: int = 2
var max_texture_updates_per_frame: int = 4

func add_generation(coord: Vector2i, priority: float) -> void:
	if pending_generation_keys.has(coord):
		for item in pending_generation:
			if item.coord == coord:
				item.priority = min(item.priority, priority)
				return
	pending_generation.append({"coord": coord, "priority": priority})
	pending_generation_keys[coord] = true

func add_texture_reset(coord: Vector2i, chunk: Chunk) -> void:
	if pending_texture_reset_keys.has(coord):
		return
	pending_texture_reset.append({"coord": coord, "chunk": chunk})
	pending_texture_reset_keys[coord] = true

func has_pending(coord: Vector2i) -> bool:
	return pending_generation_keys.has(coord) or pending_texture_reset_keys.has(coord)

func process_next_frame(
	rd: RenderingDevice,
	gen_pipeline: RID,
	gen_shader: RID,
	chunks: Dictionary,
	on_chunk_ready: Callable
) -> Dictionary:
	var processed := {"generated": [], "reset": []}
	
	pending_generation.sort_custom(func(a, b): return a.priority < b.priority)
	
	var reset_count := 0
	while reset_count < max_texture_updates_per_frame and not pending_texture_reset.is_empty():
		var item: Dictionary = pending_texture_reset.pop_front()
		var coord: Vector2i = item.coord
		var chunk: Chunk = item.chunk
		pending_texture_reset_keys.erase(coord)
		if not chunks.has(coord) or chunks[coord] != chunk:
			continue
		var zero_data := PackedByteArray()
		zero_data.resize(256 * 256 * 4)
		zero_data.fill(0)
		rd.texture_update(chunk.rd_texture, 0, zero_data)
		processed.reset.append(coord)
		reset_count += 1
	
	var gen_count := 0
	while gen_count < max_generation_per_frame and not pending_generation.is_empty():
		var item: Dictionary = pending_generation.pop_front()
		var coord: Vector2i = item.coord
		pending_generation_keys.erase(coord)
		if not chunks.has(coord):
			continue
		_dispatch_generation(rd, gen_pipeline, gen_shader, chunks[coord])
		if on_chunk_ready.is_valid():
			on_chunk_ready.call(coord)
		processed.generated.append(coord)
		gen_count += 1
	
	return processed

func _dispatch_generation(rd: RenderingDevice, gen_pipeline: RID, gen_shader: RID, chunk: Chunk) -> void:
	var gen_uniform := RDUniform.new()
	gen_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	gen_uniform.binding = 0
	gen_uniform.add_id(chunk.rd_texture)
	var uniform_set := rd.uniform_set_create([gen_uniform], gen_shader, 0)
	
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, gen_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	
	var push_data := PackedByteArray()
	push_data.resize(16)
	push_data.encode_s32(0, chunk.coord.x)
	push_data.encode_s32(4, chunk.coord.y)
	push_data.encode_u32(8, 0)
	push_data.encode_u32(12, 0)
	rd.compute_list_set_push_constant(compute_list, push_data, push_data.size())
	
	rd.compute_list_dispatch(compute_list, 32, 32, 1)
	rd.compute_list_end()
	
	rd.free_rid(uniform_set)