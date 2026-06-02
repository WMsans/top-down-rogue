class_name FloorChunk
extends Node2D

const CHUNK_SIZE := 256
const TILE_SIZE := 16
const _LIGHT_TEXTURE_HALF := 64.0   # half-extent (px) of the shared light gradient at scale 1.0

static var _light_gradient: GradientTexture2D

var _warned_missing_texture := false

func populate(coord: Vector2i, biome: BiomeDef, world_seed: int, material_bytes: PackedByteArray = PackedByteArray()) -> void:
	for child in get_children():
		child.queue_free()

	if biome == null or biome.floor_texture == null:
		if not _warned_missing_texture:
			push_warning("FloorChunk: biome has no floor_texture; skipping floor render")
			_warned_missing_texture = true
		return

	_add_floor_sprite(biome.floor_texture)
	_add_decorations(coord, biome, world_seed, material_bytes)

func _add_decorations(coord: Vector2i, biome: BiomeDef, world_seed: int, material_bytes: PackedByteArray) -> void:
	if biome.decor_defs.is_empty() or biome.decor_chance <= 0.0:
		return
	# Floor-only placement requires a full chunk's worth of material bytes.
	if material_bytes.size() < CHUNK_SIZE * CHUNK_SIZE:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = _hash_seed(world_seed, coord)

	var total_weight := 0.0
	for def in biome.decor_defs:
		total_weight += max(def.weight, 0.0)
	if total_weight <= 0.0:
		return

	var cells_per_side := CHUNK_SIZE / TILE_SIZE  # 16
	var idx := 0
	for cy in range(cells_per_side):
		for cx in range(cells_per_side):
			if rng.randf() >= biome.decor_chance:
				continue
			# Classify the cell by its center pixel; skip non-air (solid) cells.
			var px := cx * TILE_SIZE + TILE_SIZE / 2
			var py := cy * TILE_SIZE + TILE_SIZE / 2
			if material_bytes[py * CHUNK_SIZE + px] != MaterialRegistry.MAT_AIR:
				continue
			var def := _weighted_pick(biome.decor_defs, total_weight, rng)
			if def == null or def.texture == null:
				continue
			_spawn_decor(def, idx, Vector2(cx * TILE_SIZE, cy * TILE_SIZE))
			idx += 1

func _weighted_pick(defs: Array[DecorDef], total_weight: float, rng: RandomNumberGenerator) -> DecorDef:
	var roll := rng.randf() * total_weight
	for def in defs:
		roll -= max(def.weight, 0.0)
		if roll <= 0.0:
			return def
	return defs[defs.size() - 1]

func _spawn_decor(def: DecorDef, idx: int, pos: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.name = "Decor%d" % idx
	sprite.texture = def.texture
	sprite.centered = false
	sprite.position = pos
	add_child(sprite)

	if def.emits_light:
		var light := FlickerLight.new()
		light.name = "Light"
		light.texture = _shared_light_gradient()
		light.blend_mode = Light2D.BLEND_MODE_ADD
		light.shadow_enabled = false
		light.color = def.light_color
		light.energy = def.light_energy
		light.texture_scale = def.light_radius / _LIGHT_TEXTURE_HALF
		light.amplitude = def.flicker_amplitude
		sprite.add_child(light)

static func _shared_light_gradient() -> GradientTexture2D:
	if _light_gradient == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(0, 0, 0, 1))   # ADD blend: black edge contributes nothing
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = int(_LIGHT_TEXTURE_HALF * 2.0)   # 128 -> half-extent 64 at scale 1.0
		tex.height = int(_LIGHT_TEXTURE_HALF * 2.0)
		_light_gradient = tex
	return _light_gradient

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
