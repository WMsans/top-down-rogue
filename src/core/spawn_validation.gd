class_name SpawnValidation
extends RefCounted

# Shared spawn-position validation. A position is "clear" when every cell in a
# square footprint centered on it is MAT_AIR. Reads actual chunk material via
# world_manager.read_region (same source as player-spawn validation), not the
# async terrain_physical probe cache. Cells outside any active chunk read as 255
# and count as NOT clear, so callers never spawn into unloaded terrain.

const DEFAULT_HALF: int = 6   # 13x13 footprint ~= enemy body; matches cave_spawner

static func footprint_clear(world_manager, world_pos: Vector2, half: int = DEFAULT_HALF) -> bool:
	if world_manager == null or not is_instance_valid(world_manager):
		return false
	var origin := Vector2i(int(floor(world_pos.x)) - half, int(floor(world_pos.y)) - half)
	var side := half * 2 + 1
	var data: PackedByteArray = world_manager.read_region(Rect2i(origin, Vector2i(side, side)))
	if data.size() != side * side:
		return false
	var air := MaterialRegistry.MAT_AIR
	for i in range(data.size()):
		if data[i] != air:
			return false
	return true
