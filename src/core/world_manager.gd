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
const _FloorContainer = preload("res://src/terrain/floor_container.gd")
var floor_container: Node2D
var collision_container: Node2D
var lights_container: Node2D

var tracking_position: Vector2 = Vector2.ZERO
var shadow_grid: Node = null

var _gen_uniform_sets_to_free: Array[RID] = []

var _light_dispatch_cursor := 0                  # stable round-robin cursor for >cap visible chunks
signal chunks_generated(new_coords: Array[Vector2i])
signal chunk_unloaded(coord: Vector2i)

var swarm_grid: RefCounted = preload("res://src/core/swarm_grid.gd").new(32.0)
var encounter_director: EncounterDirector = EncounterDirector.new()
var nav_field  # NavField

# Max new chunks to create+generate per frame; the rest stay "desired but not
# loaded" and are picked up on following frames, spreading the populate/decor/
# light-bake cost instead of spiking it in one frame.
const MAX_NEW_CHUNKS_PER_FRAME := 2

func _ready() -> void:
	add_to_group("world_manager")

	floor_container = _FloorContainer.new()
	floor_container.name = "FloorContainer"
	floor_container.z_index = -10
	add_child(floor_container)
	floor_container.bind(self)

	rd = RenderingServer.get_rendering_device()

	compute_device = ComputeDevice.new()
	compute_device.world_manager = self
	compute_device.init_shaders()
	compute_device.init_dummy_texture()
	compute_device.init_collider_storage_buffer()
	compute_device.init_solidity_flag_buffer()
	compute_device.render_shader = preload("res://shaders/visual/render_chunk.gdshader")
	compute_device.init_material_textures()
	compute_device.init_gen_stamp_buffer()
	compute_device.init_gen_cavern_buffer()
	compute_device.init_gen_biome_buffer()
	compute_device.init_terrain_probe()
	compute_device.init_melee_arc()
	compute_device.init_light_shared_buffers()
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

	TerrainSurface.register_adapter(self)
	nav_field = preload("res://src/core/nav/nav_field.gd").new(self)

func mark_terrain_dirty(coord: Vector2i) -> void:
	# Nav grid is now fed by the collider dispatch's passability output (via
	# TerrainCollisionHelper), so only the collision helper is marked here.
	if _collision_helper != null:
		_collision_helper.mark_dirty(coord)


func _exit_tree() -> void:
	chunk_manager.clear_all_chunks()
	compute_device.free_resources()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var attackable := get_tree().get_nodes_in_group("attackable")
	swarm_grid.rebuild(attackable)
	encounter_director.melee_token_count = EncounterDirector.tokens_for_floor(2, LevelManager.floor_number)
	encounter_director.ranged_token_count = EncounterDirector.tokens_for_floor(2, LevelManager.floor_number)
	encounter_director.update(tracking_position, attackable)
	_update_chunks()
	for coord in compute_device.read_solidity_flags(chunks):
		mark_terrain_dirty(coord)
	_run_simulation()
	_collision_helper.rebuild_dirty(chunks, delta)
	if nav_field != null:
		nav_field.update(tracking_position, delta)
	_run_terrain_probes()
	_update_lights()
	_drain_terrain_impacts()
	terrain_physical.set_center(Vector2i(tracking_position))


# Pure selection of which desired chunks to create this frame: skip already-loaded
# coords, take at most `cap` in desired order. Static + side-effect-free for testing.
static func _select_new_chunks(desired: Array, loaded: Dictionary, cap: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for coord in desired:
		if loaded.has(coord):
			continue
		if out.size() >= cap:
			break
		out.append(coord)
	return out

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

	var new_chunks: Array[Vector2i] = _select_new_chunks(desired, chunks, MAX_NEW_CHUNKS_PER_FRAME)
	for coord in new_chunks:
		chunk_manager.create_chunk(coord)

	if not new_chunks.is_empty():
		var stamp_bytes := LevelManager.build_stamp_bytes(new_chunks)
		var cavern_bytes := chunk_manager._build_cavern_bytes(new_chunks)
		_gen_uniform_sets_to_free = compute_device.dispatch_generation(
			chunks, new_chunks, LevelManager.world_seed, stamp_bytes, cavern_bytes
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


func _run_terrain_probes() -> void:
	if chunks.is_empty():
		return

	# First: read last frame's results from the GPU (no stall — GPU is one frame ahead).
	var prev_batch: Array = terrain_physical._last_batch
	var prev_total_count: int = terrain_physical._last_total_count
	if prev_total_count > 0:
		var raw := compute_device.read_terrain_probe(prev_total_count * 4)
		terrain_physical.apply_probe_results(prev_batch, raw)
	else:
		# First frame: advance past the initial empty buffer so the ring is aligned.
		compute_device.read_terrain_probe(0)

	# Then: drain current pending and dispatch to be read next frame.
	var batch := terrain_physical.prepare_probe_batch(ComputeDevice.PROBE_BUDGET)
	if batch.is_empty():
		terrain_physical.record_dispatched_batch([], 0)
		return

	var total_count: int = 0
	for entry in batch:
		total_count += int(entry["count"])
	if total_count <= 0:
		terrain_physical.record_dispatched_batch([], 0)
		return

	var packed_input := terrain_physical.pack_probe_input(batch, ComputeDevice.PROBE_BUDGET)
	var probe_uniform_sets := compute_device.dispatch_terrain_probe(chunks, batch, packed_input)
	terrain_physical.record_dispatched_batch(batch, total_count)

	for us in probe_uniform_sets:
		if us.is_valid():
			compute_device.rd.free_rid(us)


func place_gas(world_pos: Vector2, radius: float, density: int, velocity: Vector2i = Vector2i.ZERO) -> void:
	terrain_modifier.place_gas(world_pos, radius, density, velocity)


func place_lava(world_pos: Vector2, radius: float) -> void:
	terrain_modifier.place_lava(world_pos, radius)


func place_blood(world_pos: Vector2, radius: float, outward_speed: float, bias_dir: Vector2 = Vector2.ZERO) -> void:
	terrain_modifier.place_blood(world_pos, radius, outward_speed, bias_dir)


func disperse_materials_in_arc(origin: Vector2, direction: Vector2, radius: float, arc_angle: float, push_speed: float, materials: Array[int]) -> void:
	terrain_modifier.disperse_materials_in_arc(origin, direction, radius, arc_angle, push_speed, materials)


func clear_and_push_materials_in_arc(origin: Vector2, direction: Vector2, radius: float, arc_angle: float, push_speed: float, edge_fraction: float, materials: Array[int], damage: float = -1.0) -> void:
	terrain_modifier.clear_and_push_materials_in_arc(origin, direction, radius, arc_angle, push_speed, edge_fraction, materials, damage)


func place_material(world_pos: Vector2, radius: float, material_id: int) -> void:
	terrain_modifier.place_material(world_pos, radius, material_id)


func place_material_blob(world_pos: Vector2, radius: float, material_id: int, noise_seed: int = 0, edge_jitter: float = 0.0, only_chunks: Dictionary = {}) -> void:
	terrain_modifier.place_material_blob(world_pos, radius, material_id, noise_seed, edge_jitter, only_chunks)


func place_material_ring(world_pos: Vector2, inner_radius: float, outer_radius: float, material_id: int, only_chunks: Dictionary = {}) -> void:
	terrain_modifier.place_material_ring(world_pos, inner_radius, outer_radius, material_id, only_chunks)


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


func read_flag_region(region: Rect2i) -> PackedByteArray:
	var width: int = region.size.x
	var height: int = region.size.y
	var result := PackedByteArray()
	result.resize(width * height)
	result.fill(0)

	var min_chunk := Vector2i(floori(float(region.position.x) / CHUNK_SIZE), floori(float(region.position.y) / CHUNK_SIZE))
	var max_chunk := Vector2i(floori(float(region.end.x - 1) / CHUNK_SIZE), floori(float(region.end.y - 1) / CHUNK_SIZE))

	for cx in range(min_chunk.x, max_chunk.x + 1):
		for cy in range(min_chunk.y, max_chunk.y + 1):
			var chunk_coord := Vector2i(cx, cy)
			if not chunks.has(chunk_coord):
				continue
			var chunk: Chunk = chunks[chunk_coord]
			if not chunk.rd_flag_texture.is_valid():
				continue
			var chunk_data: PackedByteArray = rd.texture_get_data(chunk.rd_flag_texture, 0)
			var chunk_origin := chunk_coord * CHUNK_SIZE
			var chunk_rect := Rect2i(chunk_origin, Vector2i(CHUNK_SIZE, CHUNK_SIZE))
			var overlap := region.intersection(chunk_rect)
			for y in range(overlap.position.y, overlap.end.y):
				for x in range(overlap.position.x, overlap.end.x):
					var local_x: int = x - chunk_origin.x
					var local_y: int = y - chunk_origin.y
					var src_idx: int = local_y * CHUNK_SIZE + local_x
					var dst_x: int = x - region.position.x
					var dst_y: int = y - region.position.y
					result[dst_y * width + dst_x] = chunk_data[src_idx]
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

	# --- Readback: consume the prior frame's coalesced output ---
	var readback: Dictionary = compute_device.read_light_buffer_coalesced()
	if not readback.is_empty():
		var bytes: PackedByteArray = readback["bytes"]
		var manifest: PackedInt32Array = readback["manifest"]
		var slice_count := manifest.size() / 3
		for s in range(slice_count):
			var coord := Vector2i(manifest[s * 3], manifest[s * 3 + 1])
			var slice_idx: int = manifest[s * 3 + 2]
			var chunk: Chunk = chunks.get(coord, null)
			if not chunk or not chunk.chunk_lights:
				continue
			var decoded := compute_device.decode_light_ssbo_slice(bytes, slice_idx)
			if decoded.is_empty():
				continue
			chunk.chunk_lights.apply_light_data(decoded)
			for j in range(min(decoded.size(), 16)):
				chunk.hazard_cells[j] = int(decoded[j].get("hazard", 0))

	# --- Dispatch: refresh every visible chunk each frame. ---
	# Previously this dispatched only 1/5 of chunks per frame, bucketed by each chunk's
	# index in the per-frame-rebuilt `active_coords` array. Under movement, chunks
	# load/unload so the array reorders and its size changes, shifting every chunk's
	# index and the bucket size each frame — a chunk near the player could miss its
	# bucket window for dozens of frames, the 1-5 s movement-only light latency.
	# Dispatch is cheap (a few tiny compute jobs + the single coalesced readback), so
	# refresh all active chunks every frame: low latency, independent of movement.
	var active_coords: Array[Vector2i] = []
	for coord in chunks:
		active_coords.append(coord)

	var dispatch_coords := active_coords
	if active_coords.size() > ComputeDevice.LIGHT_MAX_ACTIVE_CHUNKS:
		dispatch_coords = _select_light_dispatch_window(active_coords)

	compute_device.dispatch_light_pack(chunks, dispatch_coords)


## When more chunks are visible than the coalesced light buffer can hold in one
## frame, walk them in a stable sorted order with a persistent cursor so every chunk
## is still covered within ceil(N / cap) frames — regardless of load/unload churn.
func _select_light_dispatch_window(active_coords: Array[Vector2i]) -> Array[Vector2i]:
	var cap: int = ComputeDevice.LIGHT_MAX_ACTIVE_CHUNKS
	var sorted := active_coords.duplicate()
	sorted.sort()
	var n := sorted.size()
	if _light_dispatch_cursor >= n:
		_light_dispatch_cursor = 0
	var window: Array[Vector2i] = []
	for i in range(cap):
		window.append(sorted[(_light_dispatch_cursor + i) % n])
	_light_dispatch_cursor = (_light_dispatch_cursor + cap) % n
	return window

const MAX_IMPACTS_PER_FRAME := 16

func _drain_terrain_impacts() -> void:
	var hits: Array = compute_device.drain_melee_hits()
	# Cap impacts per frame; bursts of 60+ swamped the main thread with
	# tween/node allocations. Excess hits are dropped (visual only).
	var to_play: int = mini(hits.size(), MAX_IMPACTS_PER_FRAME)
	for i in range(to_play):
		var hit = hits[i]
		TerrainImpact.play_impact(hit["world_pos"], hit["material_id"], hit["scale"], chunk_container)


func reset() -> void:
	chunk_manager.clear_all_chunks()
	for us in _gen_uniform_sets_to_free:
		rd.free_rid(us)
	_gen_uniform_sets_to_free.clear()
	for child in chunk_container.get_children():
		child.queue_free()
	for child in lights_container.get_children():
		child.queue_free()
	_light_dispatch_cursor = 0
	compute_device.light_first_frame = true
	compute_device.light_write_index = 0
	compute_device.light_dispatch_manifests[0] = PackedInt32Array()
	compute_device.light_dispatch_manifests[1] = PackedInt32Array()
	tracking_position = Vector2.ZERO
	compute_device.upload_biome_buffer(LevelManager.current_biome)
	compute_device.bind_template_arrays(BiomeRegistry.get_template_arrays())
