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

func _add_floor_sprite(tex: Texture2D) -> void:
	var sprite := Sprite2D.new()
	sprite.name = "FloorSprite"
	sprite.texture = tex
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, CHUNK_SIZE, CHUNK_SIZE)
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(sprite)
