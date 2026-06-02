class_name FloorContainer
extends Node2D

const _FloorChunk = preload("res://src/terrain/floor_chunk.gd")
const CHUNK_SIZE := 256

var _chunks: Dictionary = {}  # Vector2i -> FloorChunk
var _world_manager: Node2D = null

func bind(world_manager: Node2D) -> void:
	_world_manager = world_manager
	world_manager.chunks_generated.connect(_on_chunks_generated)
	world_manager.chunk_unloaded.connect(_on_chunk_unloaded)

func _on_chunks_generated(new_coords: Array[Vector2i]) -> void:
	var biome: BiomeDef = LevelManager.current_biome
	var world_seed: int = LevelManager.world_seed
	for coord in new_coords:
		if _chunks.has(coord):
			continue
		var fc := _FloorChunk.new()
		fc.name = "FloorChunk_%d_%d" % [coord.x, coord.y]
		fc.position = Vector2(coord.x * CHUNK_SIZE, coord.y * CHUNK_SIZE)
		add_child(fc)
		var rect := Rect2i(coord.x * CHUNK_SIZE, coord.y * CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE)
		var material_bytes: PackedByteArray = _world_manager.read_region(rect)
		fc.populate(coord, biome, world_seed, material_bytes)
		_chunks[coord] = fc

func _on_chunk_unloaded(coord: Vector2i) -> void:
	if not _chunks.has(coord):
		return
	var fc: Node = _chunks[coord]
	_chunks.erase(coord)
	if is_instance_valid(fc):
		fc.queue_free()
