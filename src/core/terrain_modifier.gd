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


func place_blood(world_pos: Vector2, radius: float, outward_speed: float, bias_dir: Vector2 = Vector2.ZERO) -> void:
	var center_x := int(floor(world_pos.x))
	var center_y := int(floor(world_pos.y))
	var r := int(ceil(radius))
	var r_sq := float(r * r)
	var bias_len := bias_dir.length()
	var bias := Vector2.ZERO
	if bias_len > 0.0001:
		bias = bias_dir / bias_len
	var affected: Dictionary = {}
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var d_sq := float(dx * dx + dy * dy)
			if d_sq > r_sq:
				continue
			# Irregular splat: keep probability falls off near the edge and gets a
			# bias toward the hit direction so splatter trails the wound.
			var t : float = 1.0 - sqrt(d_sq) / max(1.0, float(r))
			var keep := 0.35 + 0.65 * t
			if bias != Vector2.ZERO and (dx != 0 or dy != 0):
				var cell_dir := Vector2(float(dx), float(dy)).normalized()
				keep += 0.35 * cell_dir.dot(bias)
			if randf() > keep:
				continue
			var wx := center_x + dx
			var wy := center_y + dy
			var chunk_coord := Vector2i(floori(float(wx) / CHUNK_SIZE), floori(float(wy) / CHUNK_SIZE))
			if not world_manager.chunks.has(chunk_coord):
				continue
			var local := Vector2i(posmod(wx, CHUNK_SIZE), posmod(wy, CHUNK_SIZE))
			if not affected.has(chunk_coord):
				affected[chunk_coord] = []
			affected[chunk_coord].append([local, Vector2(float(dx), float(dy))])
	for chunk_coord in affected:
		var chunk: Chunk = world_manager.chunks[chunk_coord]
		var data: PackedByteArray = world_manager.rd.texture_get_data(chunk.rd_texture, 0)
		var modified := false
		for entry in affected[chunk_coord]:
			var pixel_pos: Vector2i = entry[0]
			var dir: Vector2 = entry[1]
			var idx := (pixel_pos.y * CHUNK_SIZE + pixel_pos.x) * 4
			if data[idx] != MaterialRegistry.MAT_AIR:
				continue
			data[idx] = MaterialRegistry.MAT_BLOOD
			data[idx + 1] = clampi(180 + randi_range(-30, 60), 1, 255)
			data[idx + 2] = 0
			var dir_normalized := dir
			if dir.length_squared() > 0.0001:
				dir_normalized = dir.normalized()
			elif bias != Vector2.ZERO:
				dir_normalized = bias
			var jitter_angle := randf_range(-0.6, 0.6)
			dir_normalized = dir_normalized.rotated(jitter_angle)
			var speed := outward_speed * randf_range(0.6, 1.4)
			if bias != Vector2.ZERO:
				dir_normalized = (dir_normalized + bias * 0.6).normalized()
			var vel := (dir_normalized * speed) / 60.0
			var vx := clampi(int(round(vel.x)) + 8, 0, 15)
			var vy := clampi(int(round(vel.y)) + 8, 0, 15)
			data[idx + 3] = (vx << 4) | vy
			modified = true
		if modified:
			world_manager.rd.texture_update(chunk.rd_texture, 0, data)

	if terrain_physical:
		var affected_rect := Rect2i(center_x - r, center_y - r, r * 2 + 1, r * 2 + 1)
		terrain_physical.invalidate_rect(affected_rect)


func place_material(world_pos: Vector2, radius: float, material_id: int) -> void:
	place_material_blob(world_pos, radius, material_id, 0, 0.0)


# Place a material blob with optional noisy edges. When edge_jitter > 0, the
# disc's effective radius varies per-angle using a cheap layered-sine noise seeded
# by `noise_seed`, producing rough natural shapes instead of perfect circles.
func place_material_blob(world_pos: Vector2, radius: float, material_id: int, noise_seed: int = 0, edge_jitter: float = 0.0) -> void:
	var center_x := int(floor(world_pos.x))
	var center_y := int(floor(world_pos.y))
	var max_radius: float = radius * (1.0 + max(edge_jitter, 0.0))
	var r := int(ceil(max_radius))
	var seed_a: float = float(noise_seed) * 0.0137
	var seed_b: float = float(noise_seed) * 0.0291 + 1.7
	var seed_c: float = float(noise_seed) * 0.0073 + 4.3
	var affected: Dictionary = {}
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var d_sq: int = dx * dx + dy * dy
			if d_sq == 0:
				pass
			var local_radius: float = radius
			if edge_jitter > 0.0 and d_sq > 0:
				var angle: float = atan2(float(dy), float(dx))
				var n: float = sin(angle * 3.0 + seed_a) * 0.5 \
						+ sin(angle * 7.0 + seed_b) * 0.3 \
						+ cos(angle * 13.0 + seed_c) * 0.2
				local_radius = radius * (1.0 + n * edge_jitter)
			if float(d_sq) > local_radius * local_radius:
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
	var initial_temp := 0
	if material_id == MaterialRegistry.MAT_EXPLODE_WAVE:
		initial_temp = 100  # WAVE_DEFAULT_POWER — mirror of shaders/include/sim/common.glslinc
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
			data[idx + 2] = initial_temp
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
	materials: Array[int],
	damage: float = -1.0
) -> Array:
	var origin_int := Vector2i(int(origin.x), int(origin.y))
	var r_int := int(ceil(radius))
	var half_arc := arc_angle / 2.0
	var dir_angle := direction.angle()
	var start_angle := dir_angle - half_arc
	var end_angle := dir_angle + half_arc
	var inner_r := radius * (1.0 - edge_fraction)
	var inner_r_sq := int(inner_r) * int(inner_r)
	var r_sq := r_int * r_int
	var apply_hardness := damage >= 0.0
	var safe_damage := maxf(damage, 0.1)
	var impact_list: Array = []

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
				affected[chunk_coord].append([local, Vector2(float(dx), float(dy)).normalized(), false, dist_sq])
			else:
				affected[chunk_coord].append([local, Vector2.ZERO, true, dist_sq])

	if affected.is_empty():
		return impact_list

	for chunk_coord in affected:
		var chunk: Chunk = world_manager.chunks[chunk_coord]
		var data: PackedByteArray = world_manager.rd.texture_get_data(chunk.rd_texture, 0)
		var modified := false
		for entry in affected[chunk_coord]:
			var pixel_pos: Vector2i = entry[0]
			var push_dir: Vector2 = entry[1]
			var do_clear: bool = entry[2]
			var dist_sq: int = entry[3]
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
				if apply_hardness:
					var hardness: float = MaterialRegistry.get_hardness(material)
					var scale: float = clampf(safe_damage / (safe_damage + hardness), 0.1, 1.0)
					var effective_radius: float = radius * scale
					if dist_sq > int(effective_radius) * int(effective_radius):
						continue
					var world_wx: int = chunk_coord.x * CHUNK_SIZE + pixel_pos.x
					var world_wy: int = chunk_coord.y * CHUNK_SIZE + pixel_pos.y
					impact_list.append({
						"world_pos": Vector2(world_wx, world_wy),
						"material_id": material,
						"scale": scale,
					})
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

	return impact_list
