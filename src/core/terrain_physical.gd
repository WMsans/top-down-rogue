class_name TerrainPhysical
extends Node

const CHUNK_SIZE := 256
const TTL_FRAMES := 8

## Last known probe results: Vector2i(world_x, world_y) -> {mat_id: int, frame: int}
var _result_cache: Dictionary = {}

## Cells queued for the next probe dispatch (set semantics): Vector2i -> true
var _pending_probes: Dictionary = {}

## Frame counter, advanced once per apply_probe_results call.
var _current_frame: int = 0

## Grid center in world coords (kept for API compatibility).
var _grid_center: Vector2i = Vector2i.ZERO
var _grid_size: int = 128
var _half_grid: int = 64

## Reference to WorldManager (provides .chunks for binning).
var world_manager: Node2D = null


func query(world_pos: Vector2) -> TerrainCell:
	var cell_pos := Vector2i(int(floor(world_pos.x)), int(floor(world_pos.y)))
	_pending_probes[cell_pos] = true
	if _result_cache.has(cell_pos):
		var entry: Dictionary = _result_cache[cell_pos]
		if _current_frame - int(entry["frame"]) <= TTL_FRAMES:
			return _cell_from_material(int(entry["mat_id"]))
	return TerrainCell.new()


func invalidate_rect(rect: Rect2i) -> void:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			_result_cache.erase(Vector2i(x, y))


func set_center(world_center: Vector2i) -> void:
	_grid_center = world_center


## Drain up to PROBE_BUDGET pending probes, bin by containing chunk.
## Returns Array of {chunk_coord, world_coords, start, count}.
## Probes whose chunk is not loaded are discarded (caller will re-query as needed).
func prepare_probe_batch(probe_budget: int = 64) -> Array:
	if _pending_probes.is_empty():
		return []

	var loaded_chunks: Dictionary = {}
	if world_manager != null and "chunks" in world_manager:
		loaded_chunks = world_manager.chunks

	# Drain into a deterministic order, capped by budget.
	var drained: Array[Vector2i] = []
	var leftover: Dictionary = {}
	var taken: int = 0
	for key in _pending_probes.keys():
		if taken < probe_budget:
			drained.append(key)
			taken += 1
		else:
			leftover[key] = true
	_pending_probes = leftover

	# Bin by chunk; drop coords in unloaded chunks.
	var bins: Dictionary = {}  # Vector2i chunk_coord -> Array[Vector2i] world_coords
	for wc in drained:
		var chunk_coord := Vector2i(
			int(floor(float(wc.x) / CHUNK_SIZE)),
			int(floor(float(wc.y) / CHUNK_SIZE))
		)
		if not loaded_chunks.has(chunk_coord):
			continue
		if not bins.has(chunk_coord):
			bins[chunk_coord] = []
		bins[chunk_coord].append(wc)

	# Assign contiguous start offsets.
	var batch: Array = []
	var cursor: int = 0
	for chunk_coord in bins.keys():
		var coords: Array = bins[chunk_coord]
		batch.append({
			"chunk_coord": chunk_coord,
			"world_coords": coords,
			"start": cursor,
			"count": coords.size(),
		})
		cursor += coords.size()
	return batch


## Pack the world coords of a batch into the SSBO input buffer layout
## (ivec2 per probe, contiguous by start offset). Returns a fixed-size
## PackedByteArray sized to PROBE_BUDGET * 8.
func pack_probe_input(batch: Array, probe_budget: int = 64) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(probe_budget * 8)
	buf.fill(0)
	for entry in batch:
		var start: int = int(entry["start"])
		var coords: Array = entry["world_coords"]
		var chunk_coord: Vector2i = entry["chunk_coord"]
		var origin := chunk_coord * CHUNK_SIZE
		for i in range(coords.size()):
			var wc: Vector2i = coords[i]
			var lx: int = wc.x - origin.x
			var ly: int = wc.y - origin.y
			var off: int = (start + i) * 8
			buf.encode_s32(off, lx)
			buf.encode_s32(off + 4, ly)
	return buf


func apply_probe_results(batch: Array, raw_bytes: PackedByteArray) -> void:
	for entry in batch:
		var start: int = int(entry["start"])
		var coords: Array = entry["world_coords"]
		for i in range(coords.size()):
			var byte_off: int = (start + i) * 4
			if byte_off + 4 > raw_bytes.size():
				break
			var mat_id: int = int(raw_bytes.decode_u32(byte_off))
			_result_cache[coords[i]] = {"mat_id": mat_id, "frame": _current_frame}
	_current_frame += 1


func _cell_from_material(mat_id: int) -> TerrainCell:
	var is_solid := MaterialRegistry.has_collider(mat_id)
	var is_fluid := MaterialRegistry.is_fluid(mat_id)
	var dmg := MaterialRegistry.get_damage(mat_id)
	return TerrainCell.new(mat_id, is_solid, is_fluid, dmg)
