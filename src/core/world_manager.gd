@tool
extends Node2D

var rd: RenderingDevice
var chunks: Dictionary = {}
var compute_device: ComputeDevice
var chunk_manager: ChunkManager
var terrain_physical: TerrainPhysical
var _collision_helper: RefCounted
var terrain_modifier: TerrainModifier

@onready var chunk_container: Node2D = $ChunkContainer
var collision_container: Node2D
var lights_container: Node2D

var tracking_position: Vector2 = Vector2.ZERO
var shadow_grid: Node = null

var _gen_uniform_sets_to_free: Array[RID] = []

var _light_frame_counter := 0
var _light_dispatch_buckets: Array[Array] = []   # 5 slots, each = Array[Vector2i]
var _light_readback_counter := 0

signal chunks_generated(new_coords: Array[Vector2i])

func _ready() -> void:
	add_to_group("world_manager")
	rd = RenderingServer.get_rendering_device()

	compute_device = ComputeDevice.new()
	compute_device.init_shaders()
	compute_device.init_dummy_texture()
	compute_device.init_collider_storage_buffer()
	compute_device.render_shader = preload("res://shaders/visual/render_chunk.gdshader")
	compute_device.init_material_textures()
	compute_device.init_gen_stamp_buffer()
	compute_device.init_gen_biome_buffer()
	# Bind biome buffer + template arrays from current biome
	compute_device.upload_biome_buffer(LevelManager.current_biome)
	compute_device.bind_template_arrays(BiomeRegistry.get_template_arrays())

	chunk_manager = ChunkManager.new(self)
	terrain_physical = TerrainPhysical.new()
	terrain_physical.name = "TerrainPhysical"
	terrain_physical.world_manager = self
	add_child(terrain_physical)

	_collision_helper = TerrainCollisionHelper.new()
	_collision_helper.world_manager = self

	terrain_modifier = TerrainModifier.new(self)
	terrain_modifier.terrain_physical = terrain_physical

	collision_container = Node2D.new()
	collision_container.name = "CollisionContainer"
	add_child(collision_container)

	lights_container = Node2D.new()
	lights_container.name = "LightsContainer"
	add_child(lights_container)

	_light_dispatch_buckets.resize(5)
	for i in range(5):
		_light_dispatch_buckets[i] = []

	TerrainSurface.register_adapter(self)


func _exit_tree() -> void:
	chunk_manager.clear_all_chunks()
	compute_device.free_resources()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_chunks()
	_run_simulation()
	_collision_helper.rebuild_dirty(chunks, delta)
	_update_lights()
	terrain_physical.set_center(Vector2i(tracking_position))


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
		var stamp_bytes := LevelManager.build_stamp_bytes(new_chunks)
		_gen_uniform_sets_to_free = compute_device.dispatch_generation(
			chunks, new_chunks, LevelManager.world_seed, stamp_bytes
		)
		chunks_generated.emit(new_chunks)

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


func place_material(world_pos: Vector2, radius: float, material_id: int) -> void:
	terrain_modifier.place_material(world_pos, radius, material_id)


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


const CHUNK_SIZE := 256


func read_region(region: Rect2i) -> PackedByteArray:
	var width: int = region.size.x
	var height: int = region.size.y
	var result := PackedByteArray()
	result.resize(width * height)
	result.fill(255)

	var min_chunk := Vector2i(
		floori(float(region.position.x) / CHUNK_SIZE),
		floori(float(region.position.y) / CHUNK_SIZE)
	)
	var max_chunk := Vector2i(
		floori(float(region.end.x - 1) / CHUNK_SIZE),
		floori(float(region.end.y - 1) / CHUNK_SIZE)
	)

	for cx in range(min_chunk.x, max_chunk.x + 1):
		for cy in range(min_chunk.y, max_chunk.y + 1):
			var chunk_coord := Vector2i(cx, cy)
			if not chunks.has(chunk_coord):
				continue

			var chunk: Chunk = chunks[chunk_coord]
			var chunk_data: PackedByteArray = rd.texture_get_data(chunk.rd_texture, 0)

			var chunk_origin := chunk_coord * CHUNK_SIZE

			var chunk_rect := Rect2i(chunk_origin, Vector2i(CHUNK_SIZE, CHUNK_SIZE))
			var overlap := region.intersection(chunk_rect)

			for y in range(overlap.position.y, overlap.end.y):
				for x in range(overlap.position.x, overlap.end.x):
					var local_x: int = x - chunk_origin.x
					var local_y: int = y - chunk_origin.y
					var chunk_idx: int = (local_y * CHUNK_SIZE + local_x) * 4
					var material: int = chunk_data[chunk_idx]

					var result_x: int = x - region.position.x
					var result_y: int = y - region.position.y
					result[result_y * width + result_x] = material

	return result


func find_spawn_position(search_origin: Vector2i, body_size: Vector2i, max_radius: float = 800.0) -> Vector2i:
	var max_r: float = max(max_radius, float(body_size.x) + float(body_size.y))
	var max_ri := int(max_r)
	var search_rect := Rect2i(
		search_origin - Vector2i(max_ri, max_ri),
		Vector2i(max_ri * 2, max_ri * 2)
	)
	var region_data := read_region(search_rect)
	var region_w: int = search_rect.size.x
	var region_h: int = search_rect.size.y

	var center := Vector2i(max_ri, max_ri)
	var dir := Vector2i(1, 0)
	var pos := center
	var steps_in_leg := 1
	var steps_taken := 0
	var legs_completed := 0

	for _i in range(region_w * region_h):
		if _pocket_fits(region_data, region_w, region_h, pos, body_size):
			return search_rect.position + pos

		pos += dir
		steps_taken += 1
		if steps_taken >= steps_in_leg:
			steps_taken = 0
			legs_completed += 1
			dir = Vector2i(-dir.y, dir.x)
			if legs_completed % 2 == 0:
				steps_in_leg += 1

	push_warning("No valid spawn pocket found, falling back to search_origin")
	return search_origin


func _pocket_fits(data: PackedByteArray, region_w: int, region_h: int, top_left: Vector2i, size: Vector2i) -> bool:
	if top_left.x < 0 or top_left.y < 0:
		return false
	if top_left.x + size.x > region_w or top_left.y + size.y > region_h:
		return false
	for y in range(top_left.y, top_left.y + size.y):
		for x in range(top_left.x, top_left.x + size.x):
			if data[y * region_w + x] != MaterialRegistry.MAT_AIR:
				return false
	return true


func _update_lights() -> void:
	if chunks.is_empty():
		return

	_light_frame_counter = (_light_frame_counter + 1) % 5

	# Convert chunk coord keys to array for bucketing
	var active_coords: Array[Vector2i] = []
	for coord in chunks:
		active_coords.append(coord)

	# --- Dispatch: 1/5 of visible chunks each frame ---
	var bucket_idx := _light_frame_counter
	_light_dispatch_buckets[bucket_idx].clear()

	var bucket_size := maxi(1, active_coords.size() / 5)
	var start := bucket_idx * bucket_size
	if start < active_coords.size():
		var end := mini(start + bucket_size, active_coords.size())
		for i in range(start, end):
			_light_dispatch_buckets[bucket_idx].append(active_coords[i])

	compute_device.dispatch_light_pack(chunks, _light_dispatch_buckets[bucket_idx])

	# --- Readback: drain from 4 older buckets (1/4 of each) ---
	_light_readback_counter = (_light_readback_counter + 1) % 4

	for age in range(1, 5):
		var read_bucket := (_light_frame_counter + 5 - age) % 5
		var pending: Array = _light_dispatch_buckets[read_bucket]
		if pending.is_empty():
			continue

		var slice_size := maxi(1, pending.size() / 4)
		var slice_start := _light_readback_counter * slice_size
		if slice_start < pending.size():
			var slice_end := mini(slice_start + slice_size, pending.size())
			for i in range(slice_start, slice_end):
				var coord: Vector2i = pending[i]
				var chunk: Chunk = chunks.get(coord, null)
				if not chunk or not chunk.chunk_lights:
					continue

				var data := compute_device.read_light_buffer(chunk)
				if data.size() == 0:
					continue

				var decoded := compute_device.decode_light_ssbo(data)
				chunk.chunk_lights.apply_light_data(decoded)

func reset() -> void:
	chunk_manager.clear_all_chunks()
	for us in _gen_uniform_sets_to_free:
		rd.free_rid(us)
	_gen_uniform_sets_to_free.clear()
	for child in chunk_container.get_children():
		child.queue_free()
	for child in lights_container.get_children():
		child.queue_free()
	_light_dispatch_buckets.clear()
	_light_dispatch_buckets.resize(5)
	for i in range(5):
		_light_dispatch_buckets[i] = []
	_light_frame_counter = 0
	_light_readback_counter = 0
	tracking_position = Vector2.ZERO
	compute_device.upload_biome_buffer(LevelManager.current_biome)
	compute_device.bind_template_arrays(BiomeRegistry.get_template_arrays())
