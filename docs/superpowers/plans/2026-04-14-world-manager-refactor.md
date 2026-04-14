# WorldManager Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decompose the monolithic `world_manager.gd` (1063 lines) into 6 focused classes for maintainability and easier feature addition.

**Architecture:** WorldManager becomes a thin coordinator holding shared state (`rd`, `chunks`, scene nodes). Five subsystem classes handle their own domain: ComputeDevice (GPU init/dispatch), ChunkManager (lifecycle), CollisionManager (collisions), TerrainModifier (pixel ops), TerrainReader (read queries). Subsystems receive a reference to WorldManager and access shared state through it.

**Tech Stack:** GDScript 4, Godot 4.6, RenderingDevice compute API

---

## File Structure

| File | Responsibility |
|---|---|
| `src/core/world_manager.gd` | Thin coordinator: `unset _process`, delegates to subsystems, exposes public API |
| `src/core/compute_device.gd` | New class. Shader/pipeline init, storage buffers, dummy texture, compute dispatch helpers |
| `src/core/chunk_manager.gd` | New class. Chunk create/unload/free, desired-chunk calculation, render neighbor updates, sim uniform sets |
| `src/core/collision_manager.gd` | New class. GPU/CPU collision rebuild, timed rotation, segment parsing, occluder creation |
| `src/core/terrain_modifier.gd` | New class. place_gas, place_lava, place_fire, disperse_materials_in_arc, clear_and_push_materials_in_arc |
| `src/core/terrain_reader.gd` | New class. read_region, find_spawn_position, _pocket_fits |
| `src/core/chunk.gd` | Unchanged |

All external callers (player_controller, input_handler, melee_weapon, shadow_grid, collision_overlay, chunk_grid_overlay, world_preview) continue using the same WorldManager public API — no caller changes needed.

---

## Subsystem Interfaces

### ComputeDevice
```gdscript
class_name ComputeDevice
extends RefCounted

var rd: RenderingDevice
var gen_shader: RID
var gen_pipeline: RID
var sim_shader: RID
var sim_pipeline: RID
var collider_shader: RID
var collider_pipeline: RID
var collider_storage_buffer: RID
var dummy_texture: RID
var render_shader: Shader
var material_textures: Texture2DArray

func _init() -> void                    # gets RenderingDevice
func init_shaders() -> void             # loads compute shaders, creates pipelines
func init_dummy_texture() -> void       # creates 256x256 zero texture
func init_collider_storage_buffer() -> void  # creates 4 + max_vertices*4 buffer
func init_material_textures() -> void   # builds Texture2DArray from MaterialRegistry
func free_resources() -> void           # frees all RIDs
func dispatch_generation(chunks: Dictionary, new_coords: Array[Vector2i], seed_val: int) -> Array[RID]
func dispatch_simulation(chunks: Dictionary, shadow_grid: Node) -> void
```

### ChunkManager
```gdscript
class_name ChunkManager
extends RefCounted

var world_manager: Node2D  # back-reference for rd, scene tree, containers

func get_desired_chunks(tracking_position: Vector2) -> Array[Vector2i]
func create_chunk(coord: Vector2i) -> void
func unload_chunk(coord: Vector2i) -> void
func free_chunk_resources(chunk: Chunk) -> void
func update_chunks(desired: Array[Vector2i]) -> void
func rebuild_sim_uniform_sets(loaded: Array[Vector2i], unloaded: Array[Vector2i]) -> void
func build_sim_uniform_set(chunk: Chunk) -> void
func update_render_neighbors(loaded: Array[Vector2i], unloaded: Array[Vector2i]) -> void
func clear_all_chunks(chunks: Dictionary) -> void
func generate_chunks_at(coords: Array[Vector2i], seed_val: int, chunks: Dictionary) -> Array[Vector2i]
```

### CollisionManager
```gdscript
class_name CollisionManager
extends RefCounted

var world_manager: Node2D
var _collision_rebuild_timer: float = 0.0
var _collision_rebuild_index: int = 0

func rebuild_dirty_collisions(chunks: Dictionary, delta: float) -> void
func rebuild_chunk_collision_gpu(chunk: Chunk) -> bool
func rebuild_chunk_collision_cpu(chunk: Chunk) -> void
func parse_segment_buffer(data: PackedByteArray, max_offset: int) -> PackedVector2Array
```

### TerrainModifier
```gdscript
class_name TerrainModifier
extends RefCounted

var world_manager: Node2D

func place_gas(world_pos: Vector2, radius: float, density: int, velocity: Vector2i) -> void
func place_lava(world_pos: Vector2, radius: float) -> void
func place_fire(world_pos: Vector2, radius: float) -> void
func disperse_materials_in_arc(origin: Vector2, direction: Vector2, radius: float, arc_angle: float, push_speed: float, materials: Array[int]) -> void
func clear_and_push_materials_in_arc(origin: Vector2, direction: Vector2, radius: float, arc_angle: float, push_speed: float, edge_fraction: float, materials: Array[int]) -> void
```

### TerrainReader
```gdscript
class_name TerrainReader
extends RefCounted

var world_manager: Node2D

func read_region(region: Rect2i) -> PackedByteArray
func find_spawn_position(search_origin: Vector2i, body_size: Vector2i) -> Vector2i
func _pocket_fits(data: PackedByteArray, region_w: int, region_h: int, top_left: Vector2i, size: Vector2i) -> bool
```

---

### Task 1: Create TerrainReader

**Files:**
- Create: `src/core/terrain_reader.gd`

Extract `read_region`, `find_spawn_position`, and `_pocket_fits` from world_manager.gd into a new TerrainReader class. It needs access to `rd` (RenderingDevice) and `chunks` dict from WorldManager via back-reference. CHUNK_SIZE constant is duplicated as a local const.

- [ ] **Step 1: Create `src/core/terrain_reader.gd`**

```gdscript
class_name TerrainReader
extends RefCounted

const CHUNK_SIZE := 256

var world_manager: Node2D


func _init(manager: Node2D) -> void:
	world_manager = manager


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
			if not world_manager.chunks.has(chunk_coord):
				continue

			var chunk: Chunk = world_manager.chunks[chunk_coord]
			var chunk_data := world_manager.rd.texture_get_data(chunk.rd_texture, 0)

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


func find_spawn_position(search_origin: Vector2i, body_size: Vector2i) -> Vector2i:
	var max_radius := CHUNK_SIZE * 4
	var search_rect := Rect2i(
		search_origin - Vector2i(max_radius, max_radius),
		Vector2i(max_radius * 2, max_radius * 2)
	)
	var region_data := read_region(search_rect)
	var region_w: int = search_rect.size.x
	var region_h: int = search_rect.size.y

	var center := Vector2i(max_radius, max_radius)
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

	push_warning("ShadowGrid: No valid spawn pocket found, falling back to search_origin")
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
```

---

### Task 2: Create TerrainModifier

**Files:**
- Create: `src/core/terrain_modifier.gd`

Extract `place_gas`, `place_lava`, `place_fire`, `disperse_materials_in_arc`, `clear_and_push_materials_in_arc` from world_manager.gd.

- [ ] **Step 1: Create `src/core/terrain_modifier.gd`**

```gdscript
class_name TerrainModifier
extends RefCounted

const CHUNK_SIZE := 256

var world_manager: Node2D


func _init(manager: Node2D) -> void:
	world_manager = manager


func place_gas(world_pos: Vector2, radius: float, density: int, velocity: Vector2i = Vector2i.ZERO) -> void:
	var center_x := int(floor(world_pos.x))
	var center_y := int(floor(world_pos.y))
	var r := int(ceil(radius))
	var affected: Dictionary = {}
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var wx := center_x + dx
			var wy := center_y + dy
			var chunk_coord := Vector2i(floori(float(wx) / CHUNK_SIZE), floori(float(wy) / CHUNK_SIZE))
			if not world_manager.chunks.has(chunk_coord):
				continue
			var local := Vector2i(posmod(wx, CHUNK_SIZE), posmod(wy, CHUNK_SIZE))
			if not affected.has(chunk_coord):
				affected[chunk_coord] = []
			affected[chunk_coord].append(local)
	var clamped_density: int = clampi(density, 0, 255)
	var vx := clampi(velocity.x + 8, 0, 15)
	var vy := clampi(velocity.y + 8, 0, 15)
	var packed_velocity: int = (vx << 4) | vy
	for chunk_coord in affected:
		var chunk: Chunk = world_manager.chunks[chunk_coord]
		var data := world_manager.rd.texture_get_data(chunk.rd_texture, 0)
		var modified := false
		for pixel_pos: Vector2i in affected[chunk_coord]:
			var idx := (pixel_pos.y * CHUNK_SIZE + pixel_pos.x) * 4
			if data[idx] != MaterialRegistry.MAT_AIR:
				continue
			data[idx] = MaterialRegistry.MAT_GAS
			data[idx + 1] = clamped_density
			data[idx + 2] = 0
			data[idx + 3] = packed_velocity
			modified = true
		if modified:
			world_manager.rd.texture_update(chunk.rd_texture, 0, data)


func place_lava(world_pos: Vector2, radius: float) -> void:
	var center_x := int(floor(world_pos.x))
	var center_y := int(floor(world_pos.y))
	var r := int(ceil(radius))
	var affected: Dictionary = {}
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var wx := center_x + dx
			var wy := center_y + dy
			var chunk_coord := Vector2i(floori(float(wx) / CHUNK_SIZE), floori(float(wy) / CHUNK_SIZE))
			if not world_manager.chunks.has(chunk_coord):
				continue
			var local := Vector2i(posmod(wx, CHUNK_SIZE), posmod(wy, CHUNK_SIZE))
			if not affected.has(chunk_coord):
				affected[chunk_coord] = []
			affected[chunk_coord].append(local)
	for chunk_coord in affected:
		var chunk: Chunk = world_manager.chunks[chunk_coord]
		var data := world_manager.rd.texture_get_data(chunk.rd_texture, 0)
		var modified := false
		for pixel_pos: Vector2i in affected[chunk_coord]:
			var idx := (pixel_pos.y * CHUNK_SIZE + pixel_pos.x) * 4
			if data[idx] != MaterialRegistry.MAT_AIR:
				continue
			data[idx] = MaterialRegistry.MAT_LAVA
			data[idx + 1] = 200
			data[idx + 2] = 255
			data[idx + 3] = 136
			modified = true
		if modified:
			world_manager.rd.texture_update(chunk.rd_texture, 0, data)


func place_fire(world_pos: Vector2, radius: float) -> void:
	var center_x := int(floor(world_pos.x))
	var center_y := int(floor(world_pos.y))
	var r := int(ceil(radius))

	var affected: Dictionary = {}
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var wx := center_x + dx
			var wy := center_y + dy
			var chunk_coord := Vector2i(floori(float(wx) / CHUNK_SIZE), floori(float(wy) / CHUNK_SIZE))
			if not world_manager.chunks.has(chunk_coord):
				continue
			var local := Vector2i(posmod(wx, CHUNK_SIZE), posmod(wy, CHUNK_SIZE))
			if not affected.has(chunk_coord):
				affected[chunk_coord] = []
			affected[chunk_coord].append(local)

	for chunk_coord in affected:
		var chunk: Chunk = world_manager.chunks[chunk_coord]
		var data := world_manager.rd.texture_get_data(chunk.rd_texture, 0)
		var modified := false
		for pixel_pos: Vector2i in affected[chunk_coord]:
			var idx := (pixel_pos.y * CHUNK_SIZE + pixel_pos.x) * 4
			var material := data[idx]
			if not MaterialRegistry.is_flammable(material):
				continue
			data[idx + 2] = 255
			modified = true
		if modified:
			world_manager.rd.texture_update(chunk.rd_texture, 0, data)


func disperse_materials_in_arc(
	origin: Vector2,
	direction: Vector2,
	radius: float,
	arc_angle: float,
	push_speed: float,
	materials: Array[int]
) -> void:
	var origin_int := Vector2i(int(origin.x), int(origin.y))
	var r_int := int(ceil(radius))
	var half_arc := arc_angle / 2.0
	var dir_angle := direction.angle()
	var start_angle := dir_angle - half_arc
	var end_angle := dir_angle + half_arc

	var affected: Dictionary = {}

	for dx in range(-r_int, r_int + 1):
		for dy in range(-r_int, r_int + 1):
			var dist_sq := dx * dx + dy * dy
			if dist_sq > r_int * r_int:
				continue

			var pixel_angle := atan2(float(dy), float(dx))
			var delta_start := pixel_angle - start_angle
			while delta_start > PI:
				delta_start -= TAU
			while delta_start < -PI:
				delta_start += TAU
			var delta_end := pixel_angle - end_angle
			while delta_end > PI:
				delta_end -= TAU
			while delta_end < -PI:
				delta_end += TAU

			if delta_start < 0.0 or delta_end > 0.0:
				continue

			var wx := origin_int.x + dx
			var wy := origin_int.y + dy
			var chunk_coord := Vector2i(floori(float(wx) / CHUNK_SIZE), floori(float(wy) / CHUNK_SIZE))
			if not world_manager.chunks.has(chunk_coord):
				continue
			var local := Vector2i(posmod(wx, CHUNK_SIZE), posmod(wy, CHUNK_SIZE))
			if not affected.has(chunk_coord):
				affected[chunk_coord] = []
			affected[chunk_coord].append([local, Vector2(float(dx), float(dy)).normalized()])

	if affected.is_empty():
		return

	for chunk_coord in affected:
		var chunk: Chunk = world_manager.chunks[chunk_coord]
		var data := world_manager.rd.texture_get_data(chunk.rd_texture, 0)
		var modified := false
		for entry in affected[chunk_coord]:
			var pixel_pos: Vector2i = entry[0]
			var push_dir: Vector2 = entry[1]
			var idx := (pixel_pos.y * CHUNK_SIZE + pixel_pos.x) * 4
			var material := data[idx]

			var is_target := false
			for mat_id in materials:
				if material == mat_id:
					is_target = true
					break
			if not is_target:
				continue

			var push_vx := int(round(push_dir.x * push_speed / 60.0))
			var push_vy := int(round(push_dir.y * push_speed / 60.0))
			var vx_encoded := clampi(push_vx + 8, 0, 15)
			var vy_encoded := clampi(push_vy + 8, 0, 15)
			var packed_velocity: int = (vx_encoded << 4) | vy_encoded

			data[idx + 3] = packed_velocity
			modified = true

		if modified:
			world_manager.rd.texture_update(chunk.rd_texture, 0, data)


func clear_and_push_materials_in_arc(
	origin: Vector2,
	direction: Vector2,
	radius: float,
	arc_angle: float,
	push_speed: float,
	edge_fraction: float,
	materials: Array[int]
) -> void:
	var origin_int := Vector2i(int(origin.x), int(origin.y))
	var r_int := int(ceil(radius))
	var half_arc := arc_angle / 2.0
	var dir_angle := direction.angle()
	var start_angle := dir_angle - half_arc
	var end_angle := dir_angle + half_arc
	var inner_r := radius * (1.0 - edge_fraction)
	var inner_r_sq := int(inner_r) * int(inner_r)
	var r_sq := r_int * r_int

	var affected: Dictionary = {}

	for dx in range(-r_int, r_int + 1):
		for dy in range(-r_int, r_int + 1):
			var dist_sq := dx * dx + dy * dy
			if dist_sq > r_sq:
				continue

			var pixel_angle := atan2(float(dy), float(dx))
			var delta_start := pixel_angle - start_angle
			while delta_start > PI:
				delta_start -= TAU
			while delta_start < -PI:
				delta_start += TAU
			var delta_end := pixel_angle - end_angle
			while delta_end > PI:
				delta_end -= TAU
			while delta_end < -PI:
				delta_end += TAU

			if delta_start < 0.0 or delta_end > 0.0:
				continue

			var wx := origin_int.x + dx
			var wy := origin_int.y + dy
			var chunk_coord := Vector2i(floori(float(wx) / CHUNK_SIZE), floori(float(wy) / CHUNK_SIZE))
			if not world_manager.chunks.has(chunk_coord):
				continue
			var local := Vector2i(posmod(wx, CHUNK_SIZE), posmod(wy, CHUNK_SIZE))
			if not affected.has(chunk_coord):
				affected[chunk_coord] = []

			if dist_sq >= inner_r_sq:
				affected[chunk_coord].append([local, Vector2(float(dx), float(dy)).normalized(), false])
			else:
				affected[chunk_coord].append([local, Vector2.ZERO, true])

	if affected.is_empty():
		return

	for chunk_coord in affected:
		var chunk: Chunk = world_manager.chunks[chunk_coord]
		var data := world_manager.rd.texture_get_data(chunk.rd_texture, 0)
		var modified := false
		for entry in affected[chunk_coord]:
			var pixel_pos: Vector2i = entry[0]
			var push_dir: Vector2 = entry[1]
			var do_clear: bool = entry[2]
			var idx := (pixel_pos.y * CHUNK_SIZE + pixel_pos.x) * 4
			var material := data[idx]

			var is_target := false
			for mat_id in materials:
				if material == mat_id:
					is_target = true
					break
			if not is_target:
				continue

			if do_clear:
				data[idx] = MaterialRegistry.MAT_AIR
				data[idx + 1] = 0
				data[idx + 2] = 0
				data[idx + 3] = 136
			else:
				var push_vx := int(round(push_dir.x * push_speed / 60.0))
				var push_vy := int(round(push_dir.y * push_speed / 60.0))
				var vx_encoded := clampi(push_vx + 8, 0, 15)
				var vy_encoded := clampi(push_vy + 8, 0, 15)
				data[idx + 3] = (vx_encoded << 4) | vy_encoded
			modified = true

		if modified:
			world_manager.rd.texture_update(chunk.rd_texture, 0, data)
```

---

### Task 3: Create CollisionManager

**Files:**
- Create: `src/core/collision_manager.gd`

Extract collision rebuilding logic: `_rebuild_dirty_collisions`, `_rebuild_chunk_collision_cpu`, `_rebuild_chunk_collision_gpu`, `_parse_segment_buffer`.

- [ ] **Step 1: Create `src/core/collision_manager.gd`**

```gdscript
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
	var chunk_data := world_manager.rd.texture_get_data(chunk.rd_texture, 0)
	var material_data := PackedByteArray()
	material_data.resize(CHUNK_SIZE * CHUNK_SIZE)
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			var src_idx := (y * CHUNK_SIZE + x) * 4
			var mat := chunk_data[src_idx]
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
	var compute := world_manager.compute_device
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

	var uniform_set := world_manager.rd.uniform_set_create(uniforms, compute.collider_shader, 0)

	var compute_list := world_manager.rd.compute_list_begin()
	world_manager.rd.compute_list_bind_compute_pipeline(compute_list, compute.collider_pipeline)
	world_manager.rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	world_manager.rd.compute_list_dispatch(compute_list, 16, 16, 1)
	world_manager.rd.compute_list_end()

	world_manager.rd.free_rid(uniform_set)

	var result_data := world_manager.rd.buffer_get_data(compute.collider_storage_buffer)
	if result_data.size() < 4:
		return false

	var segment_count := result_data.decode_u32(0)
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
```

---

### Task 4: Create ComputeDevice

**Files:**
- Create: `src/core/compute_device.gd`

Extract GPU initialization and compute dispatch helpers.

- [ ] **Step 1: Create `src/core/compute_device.gd`**

```gdscript
class_name ComputeDevice
extends RefCounted

const CHUNK_SIZE := 256
const WORKGROUP_SIZE := 8
const NUM_WORKGROUPS := CHUNK_SIZE / WORKGROUP_SIZE

var rd: RenderingDevice
var gen_shader: RID
var gen_pipeline: RID
var sim_shader: RID
var sim_pipeline: RID
var collider_shader: RID
var collider_pipeline: RID
var collider_storage_buffer: RID
var dummy_texture: RID
var render_shader: Shader
var material_textures: Texture2DArray


func _init() -> void:
	rd = RenderingServer.get_rendering_device()


func init_shaders() -> void:
	var gen_file: RDShaderFile = load("res://shaders/compute/generation.glsl")
	var gen_spirv := gen_file.get_spirv()
	gen_shader = rd.shader_create_from_spirv(gen_spirv)
	gen_pipeline = rd.compute_pipeline_create(gen_shader)

	var sim_file: RDShaderFile = load("res://shaders/compute/simulation.glsl")
	var sim_spirv := sim_file.get_spirv()
	sim_shader = rd.shader_create_from_spirv(sim_spirv)
	sim_pipeline = rd.compute_pipeline_create(sim_shader)

	var collider_file: RDShaderFile = load("res://shaders/compute/collider.glsl")
	var collider_spirv := collider_file.get_spirv()
	collider_shader = rd.shader_create_from_spirv(collider_spirv)
	collider_pipeline = rd.compute_pipeline_create(collider_shader)


func init_dummy_texture() -> void:
	var tf := RDTextureFormat.new()
	tf.width = CHUNK_SIZE
	tf.height = CHUNK_SIZE
	tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	var data := PackedByteArray()
	data.resize(CHUNK_SIZE * CHUNK_SIZE * 4)
	data.fill(0)
	dummy_texture = rd.texture_create(tf, RDTextureView.new(), [data])


func init_collider_storage_buffer() -> void:
	var max_segments := 4096
	var max_vertices := max_segments * 4
	var buffer_size := 4 + max_vertices * 4
	collider_storage_buffer = rd.storage_buffer_create(buffer_size)


func init_material_textures() -> void:
	var images: Array[Image] = []
	for m in MaterialRegistry.materials:
		if m.texture_path.is_empty():
			var ref_img: Image
			if images.size() > 0:
				ref_img = images[0]
			else:
				ref_img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
				ref_img.fill(Color.TRANSPARENT)
			images.append(TextureArrayBuilder.create_placeholder_image(ref_img.get_size(), Color.TRANSPARENT))
		else:
			images.append(Image.load_from_file(m.texture_path))
	material_textures = TextureArrayBuilder.build_from_images(images)


func free_resources() -> void:
	if dummy_texture.is_valid():
		rd.free_rid(dummy_texture)
	if collider_storage_buffer.is_valid():
		rd.free_rid(collider_storage_buffer)
	if gen_pipeline.is_valid():
		rd.free_rid(gen_pipeline)
	if gen_shader.is_valid():
		rd.free_rid(gen_shader)
	if sim_pipeline.is_valid():
		rd.free_rid(sim_pipeline)
	if sim_shader.is_valid():
		rd.free_rid(sim_shader)
	if collider_pipeline.is_valid():
		rd.free_rid(collider_pipeline)
	if collider_shader.is_valid():
		rd.free_rid(collider_shader)


func dispatch_generation(chunks: Dictionary, new_coords: Array[Vector2i], seed_val: int) -> Array[RID]:
	var created_uniform_sets: Array[RID] = []
	if new_coords.is_empty():
		return created_uniform_sets

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, gen_pipeline)
	for coord in new_coords:
		var chunk: Chunk = chunks[coord]
		var gen_uniform := RDUniform.new()
		gen_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		gen_uniform.binding = 0
		gen_uniform.add_id(chunk.rd_texture)
		var uniform_set := rd.uniform_set_create([gen_uniform], gen_shader, 0)
		created_uniform_sets.append(uniform_set)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)

		var push_data := PackedByteArray()
		push_data.resize(16)
		push_data.encode_s32(0, coord.x)
		push_data.encode_s32(4, coord.y)
		push_data.encode_u32(8, seed_val)
		push_data.encode_u32(12, 0)
		rd.compute_list_set_push_constant(compute_list, push_data, push_data.size())

		rd.compute_list_dispatch(compute_list, NUM_WORKGROUPS, NUM_WORKGROUPS, 1)
	rd.compute_list_end()

	return created_uniform_sets


func dispatch_simulation(chunks: Dictionary, shadow_grid: Node) -> void:
	if chunks.is_empty():
		return

	var push_even := PackedByteArray()
	push_even.resize(16)
	push_even.encode_s32(0, 0)
	push_even.encode_s32(4, randi())

	var push_odd := PackedByteArray()
	push_odd.resize(16)
	push_odd.encode_s32(0, 1)
	push_odd.encode_s32(4, randi())

	var compute_list := rd.compute_list_begin()

	rd.compute_list_bind_compute_pipeline(compute_list, sim_pipeline)
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		if not chunk.sim_uniform_set.is_valid():
			continue
		rd.compute_list_bind_uniform_set(compute_list, chunk.sim_uniform_set, 0)
		rd.compute_list_set_push_constant(compute_list, push_even, push_even.size())
		rd.compute_list_dispatch(compute_list, NUM_WORKGROUPS, NUM_WORKGROUPS, 1)

	rd.compute_list_add_barrier(compute_list)

	rd.compute_list_bind_compute_pipeline(compute_list, sim_pipeline)
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		if not chunk.sim_uniform_set.is_valid():
			continue
		rd.compute_list_bind_uniform_set(compute_list, chunk.sim_uniform_set, 0)
		rd.compute_list_set_push_constant(compute_list, push_odd, push_odd.size())
		rd.compute_list_dispatch(compute_list, NUM_WORKGROUPS, NUM_WORKGROUPS, 1)

	rd.compute_list_end()

	if shadow_grid:
		var grid_rect: Rect2i = shadow_grid.get_world_rect()
		for coord in chunks:
			var chunk_rect := Rect2i(coord * CHUNK_SIZE, Vector2i(CHUNK_SIZE, CHUNK_SIZE))
			if grid_rect.intersects(chunk_rect):
				shadow_grid.mark_dirty()
				break
```

Note: `dispatch_simulation` still needs injection buffer uploads before dispatch. That happens in `_process` in the current code. The WorldManager coordinator will handle that before calling dispatch.

---

### Task 5: Create ChunkManager

**Files:**
- Create: `src/core/chunk_manager.gd`

Extract chunk lifecycle: create, unload, free resources, desired chunk calculation, sim uniform set building, render neighbor updates.

- [ ] **Step 1: Create `src/core/chunk_manager.gd`**

```gdscript
class_name ChunkManager
extends RefCounted

const CHUNK_SIZE := 256
const WORKGROUP_SIZE := 8
const NUM_WORKGROUPS := CHUNK_SIZE / WORKGROUP_SIZE
const MAX_INJECTIONS_PER_CHUNK := 32
const INJECTION_BUFFER_SIZE := 16 + 32 * MAX_INJECTIONS_PER_CHUNK

const NEIGHBOR_OFFSETS = [
	Vector2i(0, -1),
	Vector2i(0, 1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
]

var world_manager: Node2D


func _init(manager: Node2D) -> void:
	world_manager = manager


func get_desired_chunks(tracking_position: Vector2) -> Array[Vector2i]:
	var vp_size := world_manager.get_viewport().get_visible_rect().size
	var cam := world_manager.get_viewport().get_camera_2d()
	var cam_zoom := cam.zoom if cam else Vector2(8, 8)
	var half_view := vp_size / (2.0 * cam_zoom)

	var min_chunk := Vector2i(
		floori((tracking_position.x - half_view.x) / CHUNK_SIZE) - 1,
		floori((tracking_position.y - half_view.y) / CHUNK_SIZE) - 1
	)
	var max_chunk := Vector2i(
		floori((tracking_position.x + half_view.x) / CHUNK_SIZE) + 1,
		floori((tracking_position.y + half_view.y) / CHUNK_SIZE) + 1
	)

	var result: Array[Vector2i] = []
	for x in range(min_chunk.x, max_chunk.x + 1):
		for y in range(min_chunk.y, max_chunk.y + 1):
			result.append(Vector2i(x, y))
	return result


func create_chunk(coord: Vector2i) -> void:
	var compute := world_manager.compute_device
	var chunks: Dictionary = world_manager.chunks

	var chunk := Chunk.new()
	chunk.coord = coord

	var tf := RDTextureFormat.new()
	tf.width = CHUNK_SIZE
	tf.height = CHUNK_SIZE
	tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tf.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	chunk.rd_texture = world_manager.rd.texture_create(tf, RDTextureView.new())

	chunk.injection_buffer = world_manager.rd.storage_buffer_create(INJECTION_BUFFER_SIZE)
	var zero_data := PackedByteArray()
	zero_data.resize(INJECTION_BUFFER_SIZE)
	zero_data.fill(0)
	world_manager.rd.buffer_update(chunk.injection_buffer, 0, zero_data.size(), zero_data)

	chunk.texture_2d_rd = Texture2DRD.new()
	chunk.texture_2d_rd.texture_rd_rid = chunk.rd_texture

	chunk.mesh_instance = MeshInstance2D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(CHUNK_SIZE, CHUNK_SIZE)
	chunk.mesh_instance.mesh = quad
	chunk.mesh_instance.position = Vector2(coord) * CHUNK_SIZE + Vector2(CHUNK_SIZE / 2.0, CHUNK_SIZE / 2.0)

	var mat := ShaderMaterial.new()
	mat.shader = compute.render_shader
	mat.set_shader_parameter("chunk_data", chunk.texture_2d_rd)
	mat.set_shader_parameter("material_textures", compute.material_textures)
	mat.set_shader_parameter("wall_height", 16)
	mat.set_shader_parameter("layer_mode", 1)
	chunk.mesh_instance.material = mat

	world_manager.chunk_container.add_child(chunk.mesh_instance)

	chunk.wall_mesh_instance = MeshInstance2D.new()
	var wall_quad := QuadMesh.new()
	wall_quad.size = Vector2(CHUNK_SIZE, CHUNK_SIZE)
	chunk.wall_mesh_instance.mesh = wall_quad
	chunk.wall_mesh_instance.position = chunk.mesh_instance.position
	chunk.wall_mesh_instance.z_index = 1

	var wall_mat := ShaderMaterial.new()
	wall_mat.shader = compute.render_shader
	wall_mat.set_shader_parameter("chunk_data", chunk.texture_2d_rd)
	wall_mat.set_shader_parameter("material_textures", compute.material_textures)
	wall_mat.set_shader_parameter("wall_height", 16)
	wall_mat.set_shader_parameter("layer_mode", 0)
	chunk.wall_mesh_instance.material = wall_mat

	world_manager.chunk_container.add_child(chunk.wall_mesh_instance)

	chunk.static_body = StaticBody2D.new()
	chunk.static_body.collision_layer = 1
	chunk.static_body.collision_mask = 0
	world_manager.collision_container.add_child(chunk.static_body)

	chunk.occluder_instances = []

	chunks[coord] = chunk


func unload_chunk(coord: Vector2i) -> void:
	var chunk: Chunk = world_manager.chunks[coord]
	free_chunk_resources(chunk)
	world_manager.chunks.erase(coord)


func free_chunk_resources(chunk: Chunk) -> void:
	if chunk.mesh_instance and is_instance_valid(chunk.mesh_instance):
		chunk.mesh_instance.queue_free()
	if chunk.wall_mesh_instance and is_instance_valid(chunk.wall_mesh_instance):
		chunk.wall_mesh_instance.queue_free()
	if chunk.static_body and is_instance_valid(chunk.static_body):
		chunk.static_body.queue_free()
	for occluder in chunk.occluder_instances:
		if is_instance_valid(occluder):
			occluder.queue_free()
	chunk.occluder_instances.clear()
	if chunk.injection_buffer.is_valid():
		world_manager.rd.free_rid(chunk.injection_buffer)
	if chunk.sim_uniform_set.is_valid():
		world_manager.rd.free_rid(chunk.sim_uniform_set)
	if chunk.rd_texture.is_valid():
		world_manager.rd.free_rid(chunk.rd_texture)


func rebuild_sim_uniform_sets(loaded: Array[Vector2i], unloaded: Array[Vector2i]) -> void:
	var chunks: Dictionary = world_manager.chunks
	var to_rebuild: Dictionary = {}
	for coord in loaded:
		to_rebuild[coord] = true
		for offset in NEIGHBOR_OFFSETS:
			var n: Vector2i = coord + offset
			if chunks.has(n):
				to_rebuild[n] = true
	for coord in unloaded:
		for offset in NEIGHBOR_OFFSETS:
			var n: Vector2i = coord + offset
			if chunks.has(n):
				to_rebuild[n] = true
	for coord in to_rebuild:
		if chunks.has(coord):
			build_sim_uniform_set(chunks[coord])


func build_sim_uniform_set(chunk: Chunk) -> void:
	var compute := world_manager.compute_device
	var chunks: Dictionary = world_manager.chunks

	if chunk.sim_uniform_set.is_valid():
		world_manager.rd.free_rid(chunk.sim_uniform_set)

	var uniforms: Array[RDUniform] = []

	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(chunk.rd_texture)
	uniforms.append(u0)

	for i in range(4):
		var n_coord: Vector2i = chunk.coord + NEIGHBOR_OFFSETS[i]
		var tex := compute.dummy_texture
		if chunks.has(n_coord):
			tex = chunks[n_coord].rd_texture
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u.binding = i + 1
		u.add_id(tex)
		uniforms.append(u)

	var u5 := RDUniform.new()
	u5.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u5.binding = 5
	u5.add_id(chunk.injection_buffer)
	uniforms.append(u5)

	chunk.sim_uniform_set = world_manager.rd.uniform_set_create(uniforms, compute.sim_shader, 0)


func update_render_neighbors(loaded: Array[Vector2i], unloaded: Array[Vector2i]) -> void:
	var chunks: Dictionary = world_manager.chunks
	var to_update: Dictionary = {}
	for coord in loaded:
		to_update[coord] = true
		var south: Vector2i = coord + Vector2i(0, 1)
		if chunks.has(south):
			to_update[south] = true
	for coord in unloaded:
		var south: Vector2i = coord + Vector2i(0, 1)
		if chunks.has(south):
			to_update[south] = true

	for coord in to_update:
		if not chunks.has(coord):
			continue
		var chunk: Chunk = chunks[coord]
		var north_coord: Vector2i = coord + Vector2i(0, -1)
		var mat: ShaderMaterial = chunk.mesh_instance.material as ShaderMaterial
		if chunks.has(north_coord):
			mat.set_shader_parameter("neighbor_data", chunks[north_coord].texture_2d_rd)
			mat.set_shader_parameter("has_neighbor", true)
		else:
			mat.set_shader_parameter("has_neighbor", false)


func clear_all_chunks() -> void:
	var chunks: Dictionary = world_manager.chunks
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		free_chunk_resources(chunk)
	chunks.clear()


func generate_chunks_at(coords: Array[Vector2i], seed_val: int) -> Array[Vector2i]:
	var chunks: Dictionary = world_manager.chunks

	for us in world_manager._gen_uniform_sets_to_free:
		world_manager.rd.free_rid(us)
	world_manager._gen_uniform_sets_to_free.clear()

	var new_chunks: Array[Vector2i] = []
	for coord in coords:
		if not chunks.has(coord):
			create_chunk(coord)
			new_chunks.append(coord)

	if new_chunks.is_empty():
		return new_chunks

	world_manager._gen_uniform_sets_to_free = world_manager.compute_device.dispatch_generation(chunks, new_chunks, seed_val)

	rebuild_sim_uniform_sets(new_chunks, [])
	update_render_neighbors(new_chunks, [])

	return new_chunks
```

---

### Task 6: Rewrite WorldManager as thin coordinator

**Files:**
- Modify: `src/core/world_manager.gd`

Replace the entire file. WorldManager now holds shared state and delegates to subsystems. All public API methods are preserved as passthroughs so external callers need zero changes.

- [ ] **Step 1: Rewrite `src/core/world_manager.gd`**

```gdscript
@tool
extends Node2D

const CHUNK_SIZE := 256
const MAX_INJECTIONS_PER_CHUNK := 32
const INJECTION_BUFFER_SIZE := 16 + 32 * MAX_INJECTIONS_PER_CHUNK

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
```

---

### Task 7: Verify and test

**Files:**
- All files unchanged, just run and verify

Since this is a Godot project without an automated test suite, verification involves:
1. Checking that the project parses without errors
2. Running the game and verifying basic functionality

- [ ] **Step 1: Verify all files exist and have no obvious syntax issues**

Check that all 6 files exist:
- `src/core/world_manager.gd`
- `src/core/compute_device.gd`
- `src/core/chunk_manager.gd`
- `src/core/collision_manager.gd`
- `src/core/terrain_modifier.gd`
- `src/core/terrain_reader.gd`

Check the main.tscn references the world_manager.gd script correctly (path unchanged, so no scene changes needed).

- [ ] **Step 2: Run the project and verify basic functionality**

Launch the Godot project and verify:
- Chunks load and render correctly
- Player spawns at a valid position
- Collision works
- Gas placement (left-click) works
- Lava placement (right-click) works
- Shadow/lighting updates correctly
- Debug overlays still work