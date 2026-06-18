class_name FloorChunk
extends Node2D

const CHUNK_SIZE := 256
const TILE_SIZE := 16

# Baked decor-light parameters. Every glowing decor in a chunk is composited into
# a single PointLight2D (one CPU ImageTexture), keeping every canvas item far
# under Godot's ~16-lights-per-item cap. The texture overhangs the chunk by
# _MARGIN so edge decor bleeds into neighbors; a decor's light_radius is clamped
# to _MARGIN (default 56 < 64) to avoid clipping at the chunk boundary.
const _MARGIN := 64.0
const _LIGHT_WORLD := CHUNK_SIZE + 2.0 * _MARGIN          # 384
const _LIGHT_TEX := 96                                    # texture resolution
const _PX_PER_TEXEL := _LIGHT_WORLD / float(_LIGHT_TEX)   # 4.0 world px / texel
const _DECOR_ENERGY := 1.0                                # global brightness multiplier (tunable)

var _warned_missing_texture := false
var _decor_light: PointLight2D

func populate(coord: Vector2i, biome: BiomeDef, world_seed: int, material_bytes: PackedByteArray = PackedByteArray()) -> void:
	_decor_light = null
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

	# Collected light contributions, baked into one PointLight2D after placement.
	var splats: Array = []

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
			var pos := Vector2(cx * TILE_SIZE, cy * TILE_SIZE)
			_spawn_decor(def, idx, pos)
			if def.emits_light:
				# Anchor at the sprite origin to match the old per-decor light.
				splats.append({
					"center": pos,
					"color": def.light_color,
					"energy": def.light_energy,
					"radius": def.light_radius,
				})
			idx += 1

	_bake_decor_lights(splats)


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


## Composites every glowing decor in the chunk into one additive PointLight2D.
## Each contribution is a soft linear-falloff radial splat (matching the look of
## the old per-decor GradientTexture2D light) accumulated in RGB so per-decor
## light_color is preserved. Built once; no per-frame work.
func _bake_decor_lights(splats: Array) -> void:
	if splats.is_empty():
		return

	var n := _LIGHT_TEX * _LIGHT_TEX
	var acc_r := PackedFloat32Array()
	var acc_g := PackedFloat32Array()
	var acc_b := PackedFloat32Array()
	acc_r.resize(n)
	acc_g.resize(n)
	acc_b.resize(n)

	for s in splats:
		var center: Vector2 = s["center"]
		var color: Color = s["color"]
		var energy: float = s["energy"]
		var radius: float = clampf(s["radius"], 1.0, _MARGIN)
		# Fractional texel index where the splat center lands (inverse of the
		# light's centered placement below).
		var cx := (center.x + _MARGIN) / _PX_PER_TEXEL
		var cy := (center.y + _MARGIN) / _PX_PER_TEXEL
		var kr := radius / _PX_PER_TEXEL          # splat radius in texels
		var kri := int(ceil(kr))
		var tx0 := maxi(0, int(floor(cx)) - kri)
		var tx1 := mini(_LIGHT_TEX - 1, int(floor(cx)) + kri)
		var ty0 := maxi(0, int(floor(cy)) - kri)
		var ty1 := mini(_LIGHT_TEX - 1, int(floor(cy)) + kri)
		for ty in range(ty0, ty1 + 1):
			for tx in range(tx0, tx1 + 1):
				var dx := float(tx) + 0.5 - cx
				var dy := float(ty) + 0.5 - cy
				var t := sqrt(dx * dx + dy * dy) / kr
				var f := clampf(1.0 - t, 0.0, 1.0)   # linear falloff
				if f <= 0.0:
					continue
				var w := f * energy
				var o := ty * _LIGHT_TEX + tx
				acc_r[o] += w * color.r
				acc_g[o] += w * color.g
				acc_b[o] += w * color.b

	var bytes := PackedByteArray()
	bytes.resize(n * 4)
	for i in range(n):
		var o := i * 4
		bytes[o] = int(clampf(acc_r[i], 0.0, 1.0) * 255.0)
		bytes[o + 1] = int(clampf(acc_g[i], 0.0, 1.0) * 255.0)
		bytes[o + 2] = int(clampf(acc_b[i], 0.0, 1.0) * 255.0)
		bytes[o + 3] = 255

	var img := Image.create_from_data(_LIGHT_TEX, _LIGHT_TEX, false, Image.FORMAT_RGBA8, bytes)
	var light := PointLight2D.new()
	light.name = "DecorLights"
	light.texture = ImageTexture.create_from_image(img)
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.shadow_enabled = false
	light.color = Color.WHITE        # colors are baked into the texture
	light.energy = _DECOR_ENERGY
	light.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	light.texture_scale = _PX_PER_TEXEL
	# Texture is centered on the node; center the light over the chunk.
	light.position = Vector2(CHUNK_SIZE, CHUNK_SIZE) * 0.5
	light.visible = GameRuleManager.are_lights_enabled()
	add_child(light)
	_decor_light = light
	GameRuleManager.lights_toggled.connect(_on_lights_toggled)

func _on_lights_toggled(enabled: bool) -> void:
	if _decor_light:
		_decor_light.visible = enabled


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
