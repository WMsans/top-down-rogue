class_name TerrainModifier
extends RefCounted

const CHUNK_SIZE := 256

var world_manager: Node2D
var terrain_physical: Node


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
		var data: PackedByteArray = world_manager.rd.texture_get_data(chunk.rd_texture, 0)
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

	if terrain_physical:
		var affected_rect := Rect2i(center_x - r, center_y - r, r * 2 + 1, r * 2 + 1)
		terrain_physical.invalidate_rect(affected_rect)


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
		var data: PackedByteArray = world_manager.rd.texture_get_data(chunk.rd_texture, 0)
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

	if terrain_physical:
		var affected_rect := Rect2i(center_x - r, center_y - r, r * 2 + 1, r * 2 + 1)
		terrain_physical.invalidate_rect(affected_rect)


func place_material(world_pos: Vector2, radius: float, material_id: int) -> void:
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
		var data: PackedByteArray = world_manager.rd.texture_get_data(chunk.rd_texture, 0)
		var modified := false
		for pixel_pos: Vector2i in affected[chunk_coord]:
			var idx := (pixel_pos.y * CHUNK_SIZE + pixel_pos.x) * 4
			if data[idx] != MaterialRegistry.MAT_AIR:
				continue
			data[idx] = material_id
			data[idx + 1] = 255
			data[idx + 2] = 0
			data[idx + 3] = 136
			modified = true
		if modified:
			world_manager.rd.texture_update(chunk.rd_texture, 0, data)

	if terrain_physical:
		var affected_rect := Rect2i(center_x - r, center_y - r, r * 2 + 1, r * 2 + 1)
		terrain_physical.invalidate_rect(affected_rect)


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
		var data: PackedByteArray = world_manager.rd.texture_get_data(chunk.rd_texture, 0)
		var modified := false
		for pixel_pos: Vector2i in affected[chunk_coord]:
			var idx := (pixel_pos.y * CHUNK_SIZE + pixel_pos.x) * 4
			var material: int = data[idx]
			if not MaterialRegistry.is_flammable(material):
				continue
			data[idx + 2] = 255
			modified = true
		if modified:
			world_manager.rd.texture_update(chunk.rd_texture, 0, data)

	if terrain_physical:
		var affected_rect := Rect2i(center_x - r, center_y - r, r * 2 + 1, r * 2 + 1)
		terrain_physical.invalidate_rect(affected_rect)


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
		var data: PackedByteArray = world_manager.rd.texture_get_data(chunk.rd_texture, 0)
		var modified := false
		for entry in affected[chunk_coord]:
			var pixel_pos: Vector2i = entry[0]
			var push_dir: Vector2 = entry[1]
			var idx := (pixel_pos.y * CHUNK_SIZE + pixel_pos.x) * 4
			var material: int = data[idx]

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

	if terrain_physical:
		var affected_rect := Rect2i(origin_int.x - r_int, origin_int.y - r_int, r_int * 2 + 1, r_int * 2 + 1)
		terrain_physical.invalidate_rect(affected_rect)


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
		var data: PackedByteArray = world_manager.rd.texture_get_data(chunk.rd_texture, 0)
		var modified := false
		for entry in affected[chunk_coord]:
			var pixel_pos: Vector2i = entry[0]
			var push_dir: Vector2 = entry[1]
			var do_clear: bool = entry[2]
			var idx := (pixel_pos.y * CHUNK_SIZE + pixel_pos.x) * 4
			var material: int = data[idx]

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

	if terrain_physical:
		var affected_rect := Rect2i(origin_int.x - r_int, origin_int.y - r_int, r_int * 2 + 1, r_int * 2 + 1)
		terrain_physical.invalidate_rect(affected_rect)
