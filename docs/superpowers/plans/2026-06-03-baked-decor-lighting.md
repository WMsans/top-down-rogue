# Baked Per-Chunk Decor Lighting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace per-decor `PointLight2D`s with a single baked light texture per `FloorChunk`, eliminating the first-level light flicker caused by Godot's ~16-lights-per-canvas-item cap.

**Architecture:** All glowing decor in a chunk is composited on the CPU into one additive `PointLight2D` whose texture is built once in `populate()` from soft linear-falloff radial splats (RGB-accumulated to preserve per-decor color). Mirrors the proven `src/core/chunk_lights.gd` pattern but fully static — no `_process`, no GPU readback. Decor lighting becomes steady (flicker dropped). All changes live in one source file plus one new test file.

**Tech Stack:** Godot 4.6, GDScript, gdUnit4 test framework.

Spec: `docs/superpowers/specs/2026-06-03-baked-decor-lighting-design.md`

---

## File Structure

- **Modify:** `src/terrain/floor_chunk.gd` — stop spawning a `FlickerLight` per decor; collect each glowing decor's contribution during placement and bake them into one `PointLight2D` named `DecorLights`. Remove the now-unused `_shared_light_gradient` / `_LIGHT_TEXTURE_HALF` / `_light_gradient` helpers.
- **Create:** `tests/unit/test_floor_chunk_decor_lights.gd` — gdUnit4 suite verifying consolidation, the no-light case, and determinism.
- **Untouched:** `src/core/flicker_light.gd` stays (still used by `scenes/props/lantern.tscn`, a placed prop). `src/core/chunk_lights.gd` (terrain glow) is unrelated and unchanged.

**Test runner (used in every task):**

```bash
GODOT_BIN=godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_floor_chunk_decor_lights.gd
```

(If `godot` is not on `PATH`, set `GODOT_BIN` to the Godot 4.6 binary. The runner runs headless.)

---

## Task 1: Bake all decor lights in a chunk into one `PointLight2D`

**Files:**
- Create: `tests/unit/test_floor_chunk_decor_lights.gd`
- Modify: `src/terrain/floor_chunk.gd` (full rewrite)

- [ ] **Step 1: Write the failing test (consolidation)**

Create `tests/unit/test_floor_chunk_decor_lights.gd` with the shared helpers and the first test:

```gdscript
extends GdUnitTestSuite

const _CHUNK_BYTES := FloorChunk.CHUNK_SIZE * FloorChunk.CHUNK_SIZE


func _dummy_texture() -> Texture2D:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _make_biome(emits_light: bool) -> BiomeDef:
	var biome := BiomeDef.new()
	biome.floor_texture = _dummy_texture()
	biome.decor_chance = 1.0
	var def := DecorDef.new()
	def.texture = _dummy_texture()
	def.emits_light = emits_light
	def.weight = 1.0
	def.light_color = Color(1.0, 0.5, 0.2)
	def.light_energy = 1.0
	def.light_radius = 56.0
	var defs: Array[DecorDef] = [def]
	biome.decor_defs = defs
	return biome


func _air_bytes() -> PackedByteArray:
	# Zero-filled == MaterialRegistry.MAT_AIR (id 0), so every cell is placeable.
	var bytes := PackedByteArray()
	bytes.resize(_CHUNK_BYTES)
	return bytes


func _count_point_lights(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is PointLight2D:
			count += 1
		count += _count_point_lights(child)
	return count


func _has_lit_pixel(img: Image) -> bool:
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c.r + c.g + c.b > 0.0:
				return true
	return false


func test_dense_decor_bakes_single_light() -> void:
	var chunk := FloorChunk.new()
	add_child(chunk)
	auto_free(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(true), 12345, _air_bytes())

	assert_int(_count_point_lights(chunk)).is_equal(1)
	var light := chunk.get_node_or_null("DecorLights") as PointLight2D
	assert_object(light).is_not_null()
	assert_bool(_has_lit_pixel(light.texture.get_image())).is_true()
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
GODOT_BIN=godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_floor_chunk_decor_lights.gd
```

Expected: `test_dense_decor_bakes_single_light` FAILS. With the current code, a full chunk of air + `decor_chance = 1.0` spawns ~256 separate `FlickerLight`s (so `_count_point_lights` is ~256, not 1) and there is no node named `DecorLights`.

- [ ] **Step 3: Rewrite `src/terrain/floor_chunk.gd`**

Replace the entire file with:

```gdscript
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
	add_child(light)


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
```

This removes `FlickerLight` spawning from `_spawn_decor`, deletes the unused `_shared_light_gradient` / `_LIGHT_TEXTURE_HALF` / `_light_gradient` members, and adds `_bake_decor_lights`.

- [ ] **Step 4: Run the test to verify it passes**

```bash
GODOT_BIN=godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_floor_chunk_decor_lights.gd
```

Expected: `test_dense_decor_bakes_single_light` PASSES (exactly one `PointLight2D` named `DecorLights`, with a non-empty baked texture).

- [ ] **Step 5: Commit**

```bash
git add src/terrain/floor_chunk.gd tests/unit/test_floor_chunk_decor_lights.gd
git commit -m "feat: bake per-chunk decor lighting into one PointLight2D"
```

---

## Task 2: Regression tests — no-light case and determinism

**Files:**
- Modify: `tests/unit/test_floor_chunk_decor_lights.gd`

- [ ] **Step 1: Add the two tests**

Append to `tests/unit/test_floor_chunk_decor_lights.gd`:

```gdscript
func test_non_emitting_decor_has_no_light() -> void:
	var chunk := FloorChunk.new()
	add_child(chunk)
	auto_free(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(false), 12345, _air_bytes())

	assert_object(chunk.get_node_or_null("DecorLights")).is_null()
	assert_int(_count_point_lights(chunk)).is_equal(0)


func test_same_seed_bakes_identical_texture() -> void:
	var biome := _make_biome(true)
	var bytes := _air_bytes()

	var chunk_a := FloorChunk.new()
	add_child(chunk_a)
	auto_free(chunk_a)
	chunk_a.populate(Vector2i(3, 7), biome, 999, bytes)

	var chunk_b := FloorChunk.new()
	add_child(chunk_b)
	auto_free(chunk_b)
	chunk_b.populate(Vector2i(3, 7), biome, 999, bytes)

	var img_a := (chunk_a.get_node("DecorLights") as PointLight2D).texture.get_image()
	var img_b := (chunk_b.get_node("DecorLights") as PointLight2D).texture.get_image()
	assert_bool(img_a.get_data() == img_b.get_data()).is_true()
```

- [ ] **Step 2: Run the suite**

```bash
GODOT_BIN=godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_floor_chunk_decor_lights.gd
```

Expected: all three tests PASS. `test_non_emitting_decor_has_no_light` confirms no light node is created when decor doesn't emit; `test_same_seed_bakes_identical_texture` confirms the bake is deterministic for a fixed seed/coord.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_floor_chunk_decor_lights.gd
git commit -m "test: cover no-light and determinism for baked decor lighting"
```

---

## Task 3: Full suite + manual in-engine verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full unit-test suite to check nothing regressed**

```bash
GODOT_BIN=godot ./addons/gdUnit4/runtest.sh -a tests/unit
```

Expected: the whole `tests/unit` suite passes (no other suite depends on per-decor `FlickerLight` behavior).

- [ ] **Step 2: Manual visual check**

Launch the game and load the first level (the dense-decor biome). Walk the player around the lit decor.

Expected:
- No light flicker as the player/camera moves (the original bug is gone).
- Decor glow color and softness look consistent with before the change (warm radial pools around each glowing decoration).
- Light bleeds smoothly across chunk boundaries with no hard seams.

If glow looks too dim or bright overall, tune `_DECOR_ENERGY` in `src/terrain/floor_chunk.gd`. If a hard edge appears at chunk borders, a decor's `light_radius` exceeds `_MARGIN` (64) — lower the radius or raise `_MARGIN` and `_LIGHT_WORLD`/`_LIGHT_TEX` accordingly.

- [ ] **Step 3: Commit any tuning**

```bash
git add src/terrain/floor_chunk.gd
git commit -m "fix: tune baked decor light energy"
```

(Skip if no tuning was needed.)

---

## Self-Review Notes

- **Spec coverage:** consolidation to one light (Task 1), colored linear-falloff splats with `_MARGIN` bleed and clamping (Task 1 `_bake_decor_lights`), `FlickerLight` removed from decor but kept for the lantern prop (Task 1 leaves `flicker_light.gd` untouched), no-`_process` static bake (Task 1), and all three spec tests (Tasks 1–2) plus the manual flicker check (Task 3).
- **Naming consistency:** the baked node is named `DecorLights` in the implementation and every test/assertion. Constants `_MARGIN`, `_LIGHT_TEX`, `_PX_PER_TEXEL`, `_DECOR_ENERGY` are used consistently.
- **Geometry check:** `_LIGHT_WORLD = 256 + 2·64 = 384`; `_PX_PER_TEXEL = 384/96 = 4`; splat texel center `cx = (worldx + 64)/4` is the exact inverse of placing a 96-texel texture at scale 4 centered over the chunk, so `dx = (tx+0.5) − cx = 0` at the splat center.
