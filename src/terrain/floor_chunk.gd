class_name FloorChunk
extends Node2D

const CHUNK_SIZE := 256
const TILE_SIZE := 16

var _warned_missing_texture := false

func populate(coord: Vector2i, biome: BiomeDef, world_seed: int) -> void:
	for child in get_children():
		child.queue_free()

	if biome == null or biome.floor_texture == null:
		if not _warned_missing_texture:
			push_warning("FloorChunk: biome has no floor_texture; skipping floor render")
			_warned_missing_texture = true
		return

	_add_floor_sprite(biome.floor_texture)
	_add_decorations(coord, biome, world_seed)

func _add_decorations(coord: Vector2i, biome: BiomeDef, world_seed: int) -> void:
	if biome.decor_textures.is_empty() or biome.decor_chance <= 0.0:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = _hash_seed(world_seed, coord)

	var cells_per_side := CHUNK_SIZE / TILE_SIZE  # 16
	var idx := 0
	for cy in range(cells_per_side):
		for cx in range(cells_per_side):
			if rng.randf() < biome.decor_chance:
				var pick := rng.randi() % biome.decor_textures.size()
				var sprite := Sprite2D.new()
				sprite.name = "Decor%d" % idx
				sprite.texture = biome.decor_textures[pick]
				sprite.centered = false
				sprite.position = Vector2(cx * TILE_SIZE, cy * TILE_SIZE)
				add_child(sprite)
				idx += 1

static func _hash_seed(world_seed: int, coord: Vector2i) -> int:
	var h: int = world_seed
	h = (h * 73856093) ^ coord.x
	h = (h * 19349663) ^ coord.y
	return h

func _add_floor_sprite(tex: Texture2D) -> void:
	var sprite := Sprite2D.new()
	sprite.name = "FloorSprite"
	sprite.texture = tex
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, CHUNK_SIZE, CHUNK_SIZE)
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(sprite)
