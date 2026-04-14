@tool
extends Node2D

var rd: RenderingDevice
var chunks: Dictionary = {}
var compute_device: ComputeDevice
var chunk_manager: ChunkManager
var collision_manager: CollisionManager
var terrain_modifier: TerrainModifier
var terrain_reader: TerrainReader

@onready var chunk_container: Node2D = $ChunkContainer
var collision_container: Node2D

var tracking_position: Vector2 = Vector2.ZERO
var shadow_grid: Node = null

var _gen_uniform_sets_to_free: Array[RID] = []


func _ready() -> void:
	rd = RenderingServer.get_rendering_device()

	compute_device = ComputeDevice.new()
	compute_device.init_shaders()
	compute_device.init_dummy_texture()
	compute_device.init_collider_storage_buffer()
	compute_device.render_shader = preload("res://shaders/visual/render_chunk.gdshader")
	compute_device.init_material_textures()

	chunk_manager = ChunkManager.new(self)
	collision_manager = CollisionManager.new(self)
	terrain_modifier = TerrainModifier.new(self)
	terrain_reader = TerrainReader.new(self)

	collision_container = Node2D.new()
	collision_container.name = "CollisionContainer"
	add_child(collision_container)


func _exit_tree() -> void:
	chunk_manager.clear_all_chunks()
	compute_device.free_resources()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_chunks()
	_run_simulation()
	collision_manager.rebuild_dirty_collisions(chunks, delta)


func _update_chunks() -> void:
	for us in _gen_uniform_sets_to_free:
		rd.free_rid(us)
	_gen_uniform_sets_to_free.clear()

	var desired := chunk_manager.get_desired_chunks(tracking_position)
	var desired_set: Dictionary = {}
	for coord in desired:
		desired_set[coord] = true

	var to_remove: Array[Vector2i] = []
	for coord in chunks:
		if not desired_set.has(coord):
			to_remove.append(coord)
	for coord in to_remove:
		chunk_manager.unload_chunk(coord)

	var new_chunks: Array[Vector2i] = []
	for coord in desired:
		if not chunks.has(coord):
			chunk_manager.create_chunk(coord)
			new_chunks.append(coord)

	if not new_chunks.is_empty():
		_gen_uniform_sets_to_free = compute_device.dispatch_generation(chunks, new_chunks, 0)

	if not new_chunks.is_empty() or not to_remove.is_empty():
		chunk_manager.rebuild_sim_uniform_sets(new_chunks, to_remove)
		chunk_manager.update_render_neighbors(new_chunks, to_remove)


func _run_simulation() -> void:
	if chunks.is_empty():
		return

	var tree := get_tree()
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		if not chunk.injection_buffer.is_valid():
			continue
		var payload := GasInjector.build_payload(tree, coord)
		rd.buffer_update(chunk.injection_buffer, 0, payload.size(), payload)

	compute_device.dispatch_simulation(chunks, shadow_grid)


func place_gas(world_pos: Vector2, radius: float, density: int, velocity: Vector2i = Vector2i.ZERO) -> void:
	terrain_modifier.place_gas(world_pos, radius, density, velocity)


func place_lava(world_pos: Vector2, radius: float) -> void:
	terrain_modifier.place_lava(world_pos, radius)


func disperse_materials_in_arc(origin: Vector2, direction: Vector2, radius: float, arc_angle: float, push_speed: float, materials: Array[int]) -> void:
	terrain_modifier.disperse_materials_in_arc(origin, direction, radius, arc_angle, push_speed, materials)


func clear_and_push_materials_in_arc(origin: Vector2, direction: Vector2, radius: float, arc_angle: float, push_speed: float, edge_fraction: float, materials: Array[int]) -> void:
	terrain_modifier.clear_and_push_materials_in_arc(origin, direction, radius, arc_angle, push_speed, edge_fraction, materials)


func place_fire(world_pos: Vector2, radius: float) -> void:
	terrain_modifier.place_fire(world_pos, radius)


func get_active_chunk_coords() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coord in chunks:
		result.append(coord)
	return result


func generate_chunks_at(coords: Array[Vector2i], seed_val: int) -> void:
	chunk_manager.generate_chunks_at(coords, seed_val)


func clear_all_chunks() -> void:
	chunk_manager.clear_all_chunks()


func get_chunk_container() -> Node2D:
	return chunk_container


func read_region(region: Rect2i) -> PackedByteArray:
	return terrain_reader.read_region(region)


func find_spawn_position(search_origin: Vector2i, body_size: Vector2i) -> Vector2i:
	return terrain_reader.find_spawn_position(search_origin, body_size)
