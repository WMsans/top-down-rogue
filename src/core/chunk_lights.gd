class_name ChunkLights
extends Node2D

## A single chunk-spanning PointLight2D whose texture is composited from soft
## radial splats — one circle stamped at each glowing cell's centroid, using the
## per-cell glow data light_pack.glsl aggregates.
##
## Previously each chunk spawned 16 separate PointLight2Ds. In dense glow, far more
## than ~16 of them overlapped a single canvas item (the player, a floor quad),
## blowing past Godot's per-canvas-item 2D light cap — so the renderer dropped a
## churning subset each frame and the lights flickered as the player moved. One
## light per chunk keeps every item under the cap; compositing radial splats (rather
## than bilinearly stretching a 4x4 energy grid, which yields ugly diamonds) keeps
## the soft circular look of the original lights.

const CHUNK_SIZE := 256.0
const CELLS := 4
const CELL_COUNT := CELLS * CELLS
const MARGIN := 64.0                               # world px the light overhangs the chunk (cross-chunk bleed)
const LIGHT_WORLD := CHUNK_SIZE + 2.0 * MARGIN     # 384
const TEX := 64                                    # light-texture resolution
const PX_PER_TEXEL := LIGHT_WORLD / float(TEX)     # 6.0 world px per texel
const KR := 12                                     # splat radius in texels (~72px world)
const KSIZE := KR * 2 + 1
const SMOOTH_SPEED := 30.0
const ENERGY := 2.0                                # overall brightness multiplier (tunable)
const GLOW_COLOR := Color(1.0, 0.5, 0.15)          # warm lava-orange

static var _kernel: PackedFloat32Array

var chunk_coord: Vector2i
var light: PointLight2D
var _texture: ImageTexture
var _accum: PackedFloat32Array
var _bytes: PackedByteArray
var target_energies: PackedFloat32Array
var target_positions: Array[Vector2]
var current_energies: PackedFloat32Array
var _dirty: bool = true


static func _get_kernel() -> PackedFloat32Array:
	if not _kernel.is_empty():
		return _kernel
	var k := PackedFloat32Array()
	k.resize(KSIZE * KSIZE)
	for ky in range(KSIZE):
		for kx in range(KSIZE):
			var dx := float(kx - KR)
			var dy := float(ky - KR)
			var t := sqrt(dx * dx + dy * dy) / float(KR)
			var f := clampf(1.0 - t, 0.0, 1.0)
			k[ky * KSIZE + kx] = f * f  # quadratic falloff -> soft round edge
	_kernel = k
	return k


func _init(coord: Vector2i) -> void:
	chunk_coord = coord
	name = "Lights"
	z_index = 2

	target_energies.resize(CELL_COUNT)
	current_energies.resize(CELL_COUNT)
	target_positions.resize(CELL_COUNT)
	_accum.resize(TEX * TEX)
	_bytes.resize(TEX * TEX * 4)

	var img := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	_texture = ImageTexture.create_from_image(img)

	light = PointLight2D.new()
	light.shadow_enabled = false
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.color = Color.WHITE  # color is baked into the texture
	light.energy = ENERGY
	light.texture = _texture
	light.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	light.texture_scale = PX_PER_TEXEL
	# Texture is centered on the node; center the light over the chunk.
	light.position = Vector2(CHUNK_SIZE, CHUNK_SIZE) * 0.5
	light.visible = false
	add_child(light)


## Feeds the per-cell glow data decoded from the light_pack SSBO. Energies are
## smoothed toward these targets in _process so new/extinguished glow fades.
func apply_light_data(cell_data: Array) -> void:
	var n := mini(cell_data.size(), CELL_COUNT)
	for i in range(n):
		var entry := cell_data[i] as Dictionary
		var e := float(entry.get("energy", 0.0))
		var p: Vector2 = entry.get("position", Vector2.ZERO)
		# Only flag a rebuild when the data actually moved; static terrain glow is
		# re-reported every ~5 frames and must not keep rebuilding the texture.
		if absf(e - target_energies[i]) > 0.002 or not p.is_equal_approx(target_positions[i]):
			_dirty = true
		target_energies[i] = e
		target_positions[i] = p


func _process(delta: float) -> void:
	var t := 1.0 - exp(-SMOOTH_SPEED * delta)
	var settled := true
	for i in range(CELL_COUNT):
		current_energies[i] = lerpf(current_energies[i], target_energies[i], t)
		if absf(current_energies[i] - target_energies[i]) > 0.002:
			settled = false
	if settled and not _dirty:
		return
	_dirty = not settled
	_rebuild()


func _rebuild() -> void:
	var kernel := _get_kernel()
	for i in range(_accum.size()):
		_accum[i] = 0.0

	var any_glow := false
	for i in range(CELL_COUNT):
		var e := current_energies[i]
		if e <= 0.004:
			continue
		any_glow = true
		var p: Vector2 = target_positions[i]
		var cx := int(floor((p.x + MARGIN) / PX_PER_TEXEL))
		var cy := int(floor((p.y + MARGIN) / PX_PER_TEXEL))
		for ky in range(KSIZE):
			var ty := cy - KR + ky
			if ty < 0 or ty >= TEX:
				continue
			var row := ty * TEX
			var krow := ky * KSIZE
			for kx in range(KSIZE):
				var tx := cx - KR + kx
				if tx < 0 or tx >= TEX:
					continue
				_accum[row + tx] += kernel[krow + kx] * e

	light.visible = any_glow
	if not any_glow:
		return

	for idx in range(TEX * TEX):
		var v := clampf(_accum[idx], 0.0, 1.0)
		var o := idx * 4
		_bytes[o] = int(GLOW_COLOR.r * v * 255.0)
		_bytes[o + 1] = int(GLOW_COLOR.g * v * 255.0)
		_bytes[o + 2] = int(GLOW_COLOR.b * v * 255.0)
		_bytes[o + 3] = 255
	_texture.update(Image.create_from_data(TEX, TEX, false, Image.FORMAT_RGBA8, _bytes))
