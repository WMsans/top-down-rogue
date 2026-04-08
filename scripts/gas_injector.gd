class_name GasInjector
extends RefCounted

const MAX_INJECTIONS_PER_CHUNK := 32
const MIN_SPEED_SQ := 0.25
# Velocity-to-cell-per-frame scale. A body moving 60 px/s -> 1 cell/frame at 60 fps.
const VELOCITY_SCALE := 1.0 / 60.0

const CHUNK_SIZE := 256
const HEADER_BYTES := 16
const BODY_BYTES := 32
const BUFFER_BYTES := HEADER_BYTES + BODY_BYTES * MAX_INJECTIONS_PER_CHUNK


## Returns per-frame injection bytes for the chunk at `coord`.
## `scene` is used to look up nodes in the `gas_interactors` group.
static func build_payload(scene: SceneTree, coord: Vector2i) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(BUFFER_BYTES)
	out.fill(0)

	var chunk_world_rect := Rect2(
		Vector2(coord) * CHUNK_SIZE,
		Vector2(CHUNK_SIZE, CHUNK_SIZE)
	)

	var count := 0
	for node in scene.get_nodes_in_group("gas_interactors"):
		if count >= MAX_INJECTIONS_PER_CHUNK:
			break
		if not node is Node2D:
			continue

		var linvel := _get_node_velocity(node)
		if linvel.length_squared() < MIN_SPEED_SQ:
			continue

		var aabb_world := _world_aabb_of(node)
		if not chunk_world_rect.intersects(aabb_world):
			continue

		# Convert to chunk-local *inclusive min / exclusive max* integer cell coords.
		var min_local := Vector2i(
			floori(aabb_world.position.x - chunk_world_rect.position.x),
			floori(aabb_world.position.y - chunk_world_rect.position.y)
		)
		var max_local := Vector2i(
			ceili(aabb_world.end.x - chunk_world_rect.position.x),
			ceili(aabb_world.end.y - chunk_world_rect.position.y)
		)
		min_local = min_local.clamp(Vector2i.ZERO, Vector2i(CHUNK_SIZE, CHUNK_SIZE))
		max_local = max_local.clamp(Vector2i.ZERO, Vector2i(CHUNK_SIZE, CHUNK_SIZE))
		if max_local.x <= min_local.x or max_local.y <= min_local.y:
			continue

		var vx := clampi(int(round(linvel.x * VELOCITY_SCALE)), -8, 7)
		var vy := clampi(int(round(linvel.y * VELOCITY_SCALE)), -8, 7)
		if vx == 0 and vy == 0:
			continue

		var offset := HEADER_BYTES + count * BODY_BYTES
		out.encode_s32(offset + 0,  min_local.x)
		out.encode_s32(offset + 4,  min_local.y)
		out.encode_s32(offset + 8,  max_local.x)
		out.encode_s32(offset + 12, max_local.y)
		out.encode_s32(offset + 16, vx)
		out.encode_s32(offset + 20, vy)
		# offset +24, +28 are pad bytes, already zero.
		count += 1

	out.encode_s32(0, count)
	return out


static func _get_node_velocity(node: Node2D) -> Vector2:
	if node is CharacterBody2D:
		return (node as CharacterBody2D).velocity
	if node is RigidBody2D:
		return (node as RigidBody2D).linear_velocity
	# Any Node2D exposing a `velocity` property.
	if "velocity" in node:
		var v = node.get("velocity")
		if v is Vector2:
			return v
	return Vector2.ZERO


static func _world_aabb_of(node: Node2D) -> Rect2:
	# Try CollisionObject2D.get_shape_owners for a proper AABB.
	if node is CollisionObject2D:
		var co := node as CollisionObject2D
		var rect := Rect2()
		var first := true
		for owner_id in co.get_shape_owners():
			var owner_id_int: int = owner_id
			var transform: Transform2D = co.shape_owner_get_transform(owner_id_int)
			for i in range(co.shape_owner_get_shape_count(owner_id_int)):
				var shape: Shape2D = co.shape_owner_get_shape(owner_id_int, i)
				var shape_rect := _shape_aabb(shape, transform)
				if first:
					rect = shape_rect
					first = false
				else:
					rect = rect.merge(shape_rect)
		if not first:
			rect.position += node.global_position
			return rect
	# Fallback: treat the node as a 1-pixel point at its position.
	return Rect2(node.global_position - Vector2(0.5, 0.5), Vector2(1, 1))


static func _shape_aabb(shape: Shape2D, xform: Transform2D) -> Rect2:
	if shape is RectangleShape2D:
		var half: Vector2 = (shape as RectangleShape2D).size * 0.5
		var local := Rect2(-half, half * 2.0)
		return xform * local
	if shape is CircleShape2D:
		var r: float = (shape as CircleShape2D).radius
		var local := Rect2(Vector2(-r, -r), Vector2(r * 2.0, r * 2.0))
		return xform * local
	if shape is CapsuleShape2D:
		var cs := shape as CapsuleShape2D
		var h := cs.height * 0.5 + cs.radius
		var local := Rect2(Vector2(-cs.radius, -h), Vector2(cs.radius * 2.0, h * 2.0))
		return xform * local
	# Fallback: small box centered on origin.
	return xform * Rect2(Vector2(-1, -1), Vector2(2, 2))