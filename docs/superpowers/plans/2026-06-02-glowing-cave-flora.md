# Glowing Cave Flora Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fill cave chunks with bioluminescent flora — decorative sprites that each emit a soft, shadow-less, flickering `PointLight2D` — so the dark cave level reads as dimly but genuinely lit.

**Architecture:** Upgrade the existing per-chunk decoration scatter (`floor_chunk.gd`) from a flat `Array[Texture2D]` into a reusable, light-aware `DecorDef` resource model. Decorations are placed only on open floor (`MAT_AIR`) cells, sampled from each chunk's material texture. Flora lights reuse a single shared radial gradient texture and a shared `FlickerLight` script (extracted from the lantern). The system is biome-agnostic; only the caves biome is populated here.

**Tech Stack:** Godot 4 (GDScript), gdUnit4 test framework, `PointLight2D` 2D lighting, `RenderingDevice.read_region` GPU texture readback.

**Spec:** `docs/superpowers/specs/2026-06-02-glowing-cave-flora-design.md`

**Test command (used throughout):**
```bash
cd /home/jeremy/Development/Godot/top-down-rogue && timeout 120 godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a <test-path> 2>&1 | tail -n 8
```
A passing run ends with a `Statistics:` line showing `0 errors | 0 failures`.

**Key facts for the implementer:**
- `MaterialRegistry` is an autoload singleton; `MaterialRegistry.MAT_AIR` is the air material id (value `0`). Use the constant, never the literal.
- `world_manager.read_region(rect: Rect2i) -> PackedByteArray` returns **one byte per pixel** (the material id), row-major, `width*height` bytes. Missing/unloaded pixels are filled with `255`.
- A chunk is `256x256` pixels (`CHUNK_SIZE`), tiled in `16px` cells (`TILE_SIZE`) → a `16x16` grid of 256 cells.
- `floor_chunk.gd`'s `populate()` is called from exactly one place: `floor_container.gd:25`.

---

### Task 1: `DecorDef` resource

**Files:**
- Create: `src/core/decor_def.gd`
- Test: `tests/unit/test_decor_def.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_decor_def.gd`:

```gdscript
extends GdUnitTestSuite

const _DecorDef = preload("res://src/core/decor_def.gd")

func test_decor_def_defaults() -> void:
	var d := _DecorDef.new()
	assert_that(d.texture).is_null()
	assert_that(d.weight).is_equal(1.0)
	assert_that(d.emits_light).is_true()
	assert_that(d.light_energy).is_equal(1.0)
	assert_that(d.light_radius).is_equal(56.0)
	assert_that(d.flicker_amplitude).is_equal(0.08)

func test_decor_def_is_resource() -> void:
	var d := _DecorDef.new()
	assert_that(d is Resource).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /home/jeremy/Development/Godot/top-down-rogue && timeout 120 godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/unit/test_decor_def.gd 2>&1 | tail -n 8
```
Expected: FAIL — `res://src/core/decor_def.gd` does not exist (load error).

- [ ] **Step 3: Write minimal implementation**

Create `src/core/decor_def.gd`:

```gdscript
class_name DecorDef
extends Resource

## One decoration variant for a biome's floor scatter.
## A glowing decoration carries its own PointLight2D config; set
## emits_light = false for an ordinary (non-glowing) decoration.

@export var texture: Texture2D
@export var weight: float = 1.0                              ## relative pick weight within a biome
@export var emits_light: bool = true
@export var light_color: Color = Color(0.5, 0.9, 1.0, 1.0)   ## soft cyan/teal
@export var light_energy: float = 1.0
@export var light_radius: float = 56.0                       ## px; maps to PointLight2D.texture_scale
@export var flicker_amplitude: float = 0.08                  ## 0 = steady glow
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd /home/jeremy/Development/Godot/top-down-rogue && timeout 120 godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/unit/test_decor_def.gd 2>&1 | tail -n 8
```
Expected: PASS — `2 test cases | 0 errors | 0 failures`.

- [ ] **Step 5: Commit**

```bash
cd /home/jeremy/Development/Godot/top-down-rogue && git add src/core/decor_def.gd tests/unit/test_decor_def.gd && git commit -m "feat: add DecorDef resource for light-aware decorations"
```

---

### Task 2: `FlickerLight` shared script + lantern refactor

**Files:**
- Create: `src/core/flicker_light.gd`
- Test: `tests/unit/test_flicker_light.gd`
- Modify: `src/props/lantern.gd` (replace its inline flicker)
- Modify: `scenes/props/lantern.tscn` (attach `FlickerLight` to the `Light` node)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_flicker_light.gd`:

```gdscript
extends GdUnitTestSuite

const _FlickerLight = preload("res://src/core/flicker_light.gd")

func test_is_point_light() -> void:
	var f := _FlickerLight.new()
	assert_that(f is PointLight2D).is_true()

func test_ready_captures_base_energy() -> void:
	var f := _FlickerLight.new()
	f.energy = 1.2
	f.amplitude = 0.1
	add_child(f)            # triggers _ready
	assert_that(f.base_energy).is_equal(1.2)

func test_flicker_stays_within_amplitude_bounds() -> void:
	var f := _FlickerLight.new()
	f.energy = 1.0
	f.amplitude = 0.1
	add_child(f)
	# Advance the flicker manually a few ticks; energy must stay within base +/- amplitude.
	for i in range(20):
		f._process(0.05)
		assert_that(f.energy >= 0.9 - 0.0001 and f.energy <= 1.1 + 0.0001).is_true()

func test_zero_amplitude_holds_steady_energy() -> void:
	var f := _FlickerLight.new()
	f.energy = 2.0
	f.amplitude = 0.0
	add_child(f)
	f._process(0.05)
	assert_that(f.energy).is_equal(2.0)
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /home/jeremy/Development/Godot/top-down-rogue && timeout 120 godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/unit/test_flicker_light.gd 2>&1 | tail -n 8
```
Expected: FAIL — `res://src/core/flicker_light.gd` does not exist.

- [ ] **Step 3: Write the FlickerLight script**

Create `src/core/flicker_light.gd`:

```gdscript
class_name FlickerLight
extends PointLight2D

## A PointLight2D that gently flickers its energy.
## base_energy is captured from `energy` on _ready unless set explicitly.

var base_energy: float = 1.0
var amplitude: float = 0.08
var _phase: float = 0.0

func _ready() -> void:
	base_energy = energy
	_phase = randf() * TAU

func _process(delta: float) -> void:
	if amplitude <= 0.0:
		energy = base_energy
		set_process(false)
		return
	_phase += delta * 8.0
	var jitter: float = sin(_phase) * 0.6 + sin(_phase * 2.3) * 0.4
	energy = base_energy + jitter * amplitude
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd /home/jeremy/Development/Godot/top-down-rogue && timeout 120 godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/unit/test_flicker_light.gd 2>&1 | tail -n 8
```
Expected: PASS — `4 test cases | 0 errors | 0 failures`.

Note: `test_ready_captures_base_energy` sets `amplitude` before `add_child`, so `_process` does not zero `base_energy` before the assertion (gdUnit asserts run before the next idle frame). The capture happens in `_ready`.

- [ ] **Step 5: Refactor lantern.gd to delegate to FlickerLight**

Replace the entire contents of `src/props/lantern.gd` with:

```gdscript
extends Node2D

## Thin adapter: maps the metas set by FeatureLanternCluster onto the
## FlickerLight that drives the lantern's glow. Flicker math lives in FlickerLight.

@onready var _light: FlickerLight = $Light as FlickerLight

func _ready() -> void:
	if _light == null:
		return
	if has_meta("flicker_base_energy"):
		_light.base_energy = get_meta("flicker_base_energy")
		_light.energy = _light.base_energy
	if has_meta("flicker_amplitude"):
		_light.amplitude = get_meta("flicker_amplitude")
```

- [ ] **Step 6: Attach FlickerLight to the lantern scene's Light node**

Edit `scenes/props/lantern.tscn`. Add a script ext_resource near the other `[ext_resource]` lines:

```
[ext_resource type="Script" path="res://src/core/flicker_light.gd" id="3_flicker"]
```

Then add a `script` line to the existing `Light` node so the block reads:

```
[node name="Light" type="PointLight2D" parent="." unique_id=543209445]
color = Color(1, 0.85, 0.6, 1)
energy = 1.2
texture = SubResource("GradientTexture2D_sxhwi")
texture_scale = 4.0
script = ExtResource("3_flicker")
```

- [ ] **Step 7: Run the lantern feature test to confirm no regression**

Run:
```bash
cd /home/jeremy/Development/Godot/top-down-rogue && timeout 120 godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/unit/test_feature_lantern_cluster.gd 2>&1 | tail -n 8
```
Expected: PASS — `2 test cases | 0 errors | 0 failures`. (`FeatureLanternCluster` casts the `Light` node as `PointLight2D`; `FlickerLight` is a `PointLight2D`, so the cast and property assignments still work.)

- [ ] **Step 8: Commit**

```bash
cd /home/jeremy/Development/Godot/top-down-rogue && git add src/core/flicker_light.gd tests/unit/test_flicker_light.gd src/props/lantern.gd scenes/props/lantern.tscn && git commit -m "refactor: extract shared FlickerLight, reuse in lantern"
```

---

### Task 3: BiomeDef `decor_defs` swap + FloorChunk light-aware floor-only scatter

This task swaps `BiomeDef.decor_textures` → `decor_defs` and rewrites `floor_chunk.gd` to (a) place only on `MAT_AIR` cells using passed-in material bytes, (b) weighted-pick a `DecorDef`, and (c) attach a `FlickerLight` per glowing decor. Both changes land in one commit because `floor_chunk` is the sole consumer of `decor_textures` — removing the field without updating the consumer would break the parse. `populate`'s new `material_bytes` parameter defaults to empty so the unchanged `floor_container.gd` caller still compiles (it simply produces no decor until Task 4).

**Files:**
- Modify: `src/core/biome_def.gd:18-19`
- Modify: `src/terrain/floor_chunk.gd` (whole decoration path)
- Modify: `tests/unit/test_biome_def.gd:35-39` (`test_biome_def_floor_defaults`)
- Rewrite: `tests/unit/test_floor_chunk.gd`

- [ ] **Step 1: Update the BiomeDef defaults test**

In `tests/unit/test_biome_def.gd`, replace the `test_biome_def_floor_defaults` function with:

```gdscript
func test_biome_def_floor_defaults() -> void:
	var b := _BiomeDef.new()
	assert_that(b.floor_texture).is_null()
	assert_that(b.decor_defs).is_equal([] as Array[DecorDef])
	assert_that(b.decor_chance).is_equal(0.02)
```

- [ ] **Step 2: Rewrite the floor_chunk test suite**

Replace the entire contents of `tests/unit/test_floor_chunk.gd` with:

```gdscript
extends GdUnitTestSuite

const _FloorChunk = preload("res://src/terrain/floor_chunk.gd")
const _BiomeDef = preload("res://src/core/biome_def.gd")
const _DecorDef = preload("res://src/core/decor_def.gd")

const CHUNK_SIZE := 256

func _make_texture(width: int, height: int) -> ImageTexture:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)

func _make_decor(emits_light: bool) -> _DecorDef:
	var d := _DecorDef.new()
	d.texture = _make_texture(16, 16)
	d.emits_light = emits_light
	return d

func _make_biome(decor_chance: float, decor_count: int, emits_light: bool = true) -> _BiomeDef:
	var b := _BiomeDef.new()
	b.floor_texture = _make_texture(16, 16)
	b.decor_chance = decor_chance
	var defs: Array[DecorDef] = []
	for i in range(decor_count):
		defs.append(_make_decor(emits_light))
	b.decor_defs = defs
	return b

func _all_air_bytes() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(CHUNK_SIZE * CHUNK_SIZE)
	b.fill(MaterialRegistry.MAT_AIR)
	return b

func _all_solid_bytes() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(CHUNK_SIZE * CHUNK_SIZE)
	b.fill(MaterialRegistry.MAT_AIR + 1)   # any non-air material id
	return b

func _floor_sprite(chunk: _FloorChunk) -> Sprite2D:
	return chunk.get_node_or_null("FloorSprite") as Sprite2D

func _decor_sprites(chunk: _FloorChunk) -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	for child in chunk.get_children():
		if child.name.begins_with("Decor"):
			out.append(child as Sprite2D)
	return out

func test_populate_creates_floor_sprite_at_chunk_size() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(0.0, 0), 12345, _all_air_bytes())
	var sprite := _floor_sprite(chunk)
	assert_that(sprite).is_not_null()
	assert_that(sprite.region_enabled).is_true()
	assert_that(sprite.region_rect.size).is_equal(Vector2(CHUNK_SIZE, CHUNK_SIZE))

func test_populate_skips_when_floor_texture_missing() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	var biome := _BiomeDef.new()  # no floor_texture
	chunk.populate(Vector2i(0, 0), biome, 12345, _all_air_bytes())
	assert_that(_floor_sprite(chunk)).is_null()

func test_decor_chance_zero_creates_no_decor() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(0.0, 3), 42, _all_air_bytes())
	assert_that(_decor_sprites(chunk).size()).is_equal(0)

func test_decor_chance_one_fills_all_air_cells() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(1.0, 3), 42, _all_air_bytes())
	# 256x256 chunk / 16px tiles = 16x16 = 256 cells, all air -> all decorated.
	assert_that(_decor_sprites(chunk).size()).is_equal(256)

func test_decor_never_placed_on_solid_cells() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(1.0, 3), 42, _all_solid_bytes())
	assert_that(_decor_sprites(chunk).size()).is_equal(0)

func test_empty_material_bytes_skips_decor() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(1.0, 3), 42, PackedByteArray())
	assert_that(_decor_sprites(chunk).size()).is_equal(0)

func test_empty_decor_defs_skips_decor_pass() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(1.0, 0), 42, _all_air_bytes())
	assert_that(_decor_sprites(chunk).size()).is_equal(0)

func test_glowing_decor_gets_flicker_light_child() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(1.0, 1, true), 42, _all_air_bytes())
	var sprites := _decor_sprites(chunk)
	assert_that(sprites.size()).is_equal(256)
	var light := sprites[0].get_node_or_null("Light") as FlickerLight
	assert_that(light).is_not_null()
	assert_that(light.shadow_enabled).is_false()
	assert_that(light.blend_mode).is_equal(Light2D.BLEND_MODE_ADD)

func test_non_glowing_decor_has_no_light_child() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(1.0, 1, false), 42, _all_air_bytes())
	var sprites := _decor_sprites(chunk)
	assert_that(sprites[0].get_node_or_null("Light")).is_null()

func test_decor_placement_is_deterministic_for_same_seed_and_coord() -> void:
	var biome := _make_biome(0.5, 3)
	var a := _FloorChunk.new()
	var b := _FloorChunk.new()
	add_child(a)
	add_child(b)
	a.populate(Vector2i(3, -2), biome, 999, _all_air_bytes())
	b.populate(Vector2i(3, -2), biome, 999, _all_air_bytes())
	var ad := _decor_sprites(a)
	var bd := _decor_sprites(b)
	assert_that(ad.size()).is_equal(bd.size())
	for i in range(ad.size()):
		assert_that(ad[i].position).is_equal(bd[i].position)
		assert_that(ad[i].texture).is_same(bd[i].texture)

func test_decor_placement_differs_across_coords() -> void:
	var biome := _make_biome(0.5, 3)
	var a := _FloorChunk.new()
	var b := _FloorChunk.new()
	add_child(a)
	add_child(b)
	a.populate(Vector2i(0, 0), biome, 7, _all_air_bytes())
	b.populate(Vector2i(1, 0), biome, 7, _all_air_bytes())
	var ad := _decor_sprites(a)
	var bd := _decor_sprites(b)
	var identical := ad.size() == bd.size()
	if identical:
		for i in range(ad.size()):
			if ad[i].position != bd[i].position:
				identical = false
				break
	assert_that(identical).is_false()
```

- [ ] **Step 3: Run tests to verify they fail**

Run:
```bash
cd /home/jeremy/Development/Godot/top-down-rogue && timeout 120 godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/unit/test_floor_chunk.gd 2>&1 | tail -n 8
```
Expected: FAIL/ERROR — `floor_chunk.gd` still reads `biome.decor_textures` and `populate` takes only 3 args, so the new tests error or fail.

- [ ] **Step 4: Swap the BiomeDef field**

In `src/core/biome_def.gd`, replace line 18:

```gdscript
@export var decor_textures: Array[Texture2D] = []
```

with:

```gdscript
@export var decor_defs: Array[DecorDef] = []
```

(Leave line 19, `@export var decor_chance: float = 0.02`, unchanged.)

- [ ] **Step 5: Rewrite the floor_chunk decoration path**

Replace the entire contents of `src/terrain/floor_chunk.gd` with:

```gdscript
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
```

- [ ] **Step 6: Run the floor_chunk and biome_def tests to verify they pass**

Run:
```bash
cd /home/jeremy/Development/Godot/top-down-rogue && timeout 120 godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/unit/test_floor_chunk.gd 2>&1 | tail -n 8 && timeout 120 godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/unit/test_biome_def.gd 2>&1 | tail -n 8
```
Expected: BOTH PASS — `test_floor_chunk.gd` shows `12 test cases | 0 errors | 0 failures`; `test_biome_def.gd` shows `4 test cases | 0 errors | 0 failures`.

- [ ] **Step 7: Commit**

```bash
cd /home/jeremy/Development/Godot/top-down-rogue && git add src/core/biome_def.gd src/terrain/floor_chunk.gd tests/unit/test_floor_chunk.gd tests/unit/test_biome_def.gd && git commit -m "feat: light-aware floor-only decor scatter via DecorDef"
```

---

### Task 4: FloorContainer reads chunk material region and passes it through

**Files:**
- Modify: `src/terrain/floor_container.gd:23-26`

`FloorContainer` already holds `_world_manager`. Read each new chunk's material region once and pass the bytes into `populate`.

- [ ] **Step 1: Wire the material readback into populate**

In `src/terrain/floor_container.gd`, inside `_on_chunks_generated`, replace this block:

```gdscript
		var fc := _FloorChunk.new()
		fc.name = "FloorChunk_%d_%d" % [coord.x, coord.y]
		fc.position = Vector2(coord.x * CHUNK_SIZE, coord.y * CHUNK_SIZE)
		add_child(fc)
		fc.populate(coord, biome, world_seed)
		_chunks[coord] = fc
```

with:

```gdscript
		var fc := _FloorChunk.new()
		fc.name = "FloorChunk_%d_%d" % [coord.x, coord.y]
		fc.position = Vector2(coord.x * CHUNK_SIZE, coord.y * CHUNK_SIZE)
		add_child(fc)
		var rect := Rect2i(coord.x * CHUNK_SIZE, coord.y * CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE)
		var material_bytes: PackedByteArray = _world_manager.read_region(rect)
		fc.populate(coord, biome, world_seed, material_bytes)
		_chunks[coord] = fc
```

- [ ] **Step 2: Verify the project parses (no syntax/type errors)**

Run:
```bash
cd /home/jeremy/Development/Godot/top-down-rogue && timeout 60 godot --headless --check-only --script src/terrain/floor_container.gd 2>&1 | tail -n 5
```
Expected: no parse errors printed (empty output or only unrelated warnings).

- [ ] **Step 3: Commit**

```bash
cd /home/jeremy/Development/Godot/top-down-rogue && git add src/terrain/floor_container.gd && git commit -m "feat: read chunk material region for floor-only decor placement"
```

---

### Task 5: Populate the caves biome with glowing flora

**Files:**
- Modify: `assets/biomes/caves.tres`
- Test: `tests/unit/test_caves_biome_decor.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_caves_biome_decor.gd`:

```gdscript
extends GdUnitTestSuite

func test_caves_biome_has_three_glowing_flora() -> void:
	var biome: BiomeDef = load("res://assets/biomes/caves.tres")
	assert_that(biome).is_not_null()
	assert_that(biome.decor_defs.size()).is_equal(3)
	for def in biome.decor_defs:
		assert_that(def.texture).is_not_null()
		assert_that(def.emits_light).is_true()
	assert_that(biome.decor_chance > 0.0).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /home/jeremy/Development/Godot/top-down-rogue && timeout 120 godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/unit/test_caves_biome_decor.gd 2>&1 | tail -n 8
```
Expected: FAIL — `decor_defs.size()` is 0 (caves has no decor yet).

- [ ] **Step 3: Add the DecorDef script + flora textures as ext_resources**

In `assets/biomes/caves.tres`, add these lines alongside the existing `[ext_resource]` block (any unused `id` strings are fine; these do not collide with existing ids):

```
[ext_resource type="Script" path="res://src/core/decor_def.gd" id="20_decordef"]
[ext_resource type="Texture2D" path="res://textures/Environments/Decors/grass1.png" id="21_grass1"]
[ext_resource type="Texture2D" path="res://textures/Environments/Decors/grass2.png" id="22_grass2"]
[ext_resource type="Texture2D" path="res://textures/Environments/Decors/small_tree.png" id="23_tree"]
```

- [ ] **Step 4: Add the three DecorDef sub-resources**

In `assets/biomes/caves.tres`, add these `[sub_resource]` blocks alongside the other `[sub_resource]` blocks (before the final `[resource]` section):

```
[sub_resource type="Resource" id="Resource_decor_grass1"]
script = ExtResource("20_decordef")
texture = ExtResource("21_grass1")
weight = 3.0
emits_light = true
light_color = Color(0.5, 0.9, 1.0, 1)
light_energy = 1.0
light_radius = 52.0
flicker_amplitude = 0.08

[sub_resource type="Resource" id="Resource_decor_grass2"]
script = ExtResource("20_decordef")
texture = ExtResource("22_grass2")
weight = 3.0
emits_light = true
light_color = Color(0.45, 1.0, 0.8, 1)
light_energy = 1.0
light_radius = 52.0
flicker_amplitude = 0.08

[sub_resource type="Resource" id="Resource_decor_tree"]
script = ExtResource("20_decordef")
texture = ExtResource("23_tree")
weight = 1.0
emits_light = true
light_color = Color(0.55, 0.95, 0.7, 1)
light_energy = 1.2
light_radius = 64.0
flicker_amplitude = 0.06
```

- [ ] **Step 5: Reference the DecorDefs and raise decor_chance on the resource**

In the final `[resource]` section of `assets/biomes/caves.tres`, add these two lines (place them next to `floor_texture = ...`):

```
decor_defs = [SubResource("Resource_decor_grass1"), SubResource("Resource_decor_grass2"), SubResource("Resource_decor_tree")]
decor_chance = 0.05
```

(`decor_chance = 0.05` over 256 cells, after floor-only filtering on a partly-solid cave chunk, lands roughly 6–10 lit flora per chunk — the "meaningfully lit" target. It is a tuning knob; adjust by eye in Task 6.)

- [ ] **Step 6: Run the caves biome test to verify it passes**

Run:
```bash
cd /home/jeremy/Development/Godot/top-down-rogue && timeout 120 godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/unit/test_caves_biome_decor.gd 2>&1 | tail -n 8
```
Expected: PASS — `1 test cases | 0 errors | 0 failures`.

- [ ] **Step 7: Commit**

```bash
cd /home/jeremy/Development/Godot/top-down-rogue && git add assets/biomes/caves.tres tests/unit/test_caves_biome_decor.gd && git commit -m "feat: populate caves biome with glowing bioluminescent flora"
```

---

### Task 6: Full-suite regression + visual verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full unit-test suite**

Run:
```bash
cd /home/jeremy/Development/Godot/top-down-rogue && timeout 300 godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/unit 2>&1 | tail -n 12
```
Expected: `Overall Summary:` reports `0 errors | 0 failures`. If any suite fails, fix it before continuing (the likely culprits are the migrated `test_floor_chunk.gd` / `test_biome_def.gd` or a stray `decor_textures` reference — grep with `git grep decor_textures` and convert any remaining usage).

- [ ] **Step 2: Confirm no lingering `decor_textures` references**

Run:
```bash
cd /home/jeremy/Development/Godot/top-down-rogue && git grep -n "decor_textures" -- 'src' 'tests' 'assets' || echo "clean"
```
Expected: prints `clean` (no matches).

- [ ] **Step 3: Launch the game and verify the cave is lit**

Run (close the window after observing, or let the timeout end it):
```bash
cd /home/jeremy/Development/Godot/top-down-rogue && timeout 25 godot 2>&1 | tail -n 15
```
Expected: the game boots into the cave (floor 1) with no script errors in the log. Visually confirm: glowing bioluminescent flora are scattered across open cave floor (not buried in rock), each casts a soft cyan/teal glow that gently flickers, and the cave reads as dimly-but-genuinely lit rather than pitch black. If too dark or too bright, tune `decor_chance` (density) and `light_energy` / `light_radius` in `assets/biomes/caves.tres`, then re-run this step. Re-commit `caves.tres` if you change the tuning.

---

## Self-Review

**Spec coverage:**
- DecorDef resource (spec §1) → Task 1. ✓
- BiomeDef `decor_defs` replaces `decor_textures` (spec §2) → Task 3 Step 4. ✓
- Shared FlickerLight extracted from lantern (spec §3) → Task 2. ✓
- Floor-only placement via `read_region` (spec §4) → Task 4 + the `MAT_AIR` center-pixel test in Task 3 Step 5. ✓
- floor_chunk weighted pick + sprite + shadow-less ADD light + shared gradient (spec §5) → Task 3 Step 5. ✓
- Caves config: three flora DecorDefs, cyan/teal/green, tuned `decor_chance` (spec §6) → Task 5. ✓
- Lifecycle (children freed on repopulate/unload) → preserved in Task 3 `populate` (`queue_free` loop) and unchanged `floor_container` unload path; no new teardown needed. ✓
- Edge cases: empty defs, solid cell, empty/undersized bytes, `emits_light=false`, `flicker_amplitude=0` → covered by Task 3 tests + FlickerLight test. ✓
- Performance (no shadows, shared gradient, one readback/chunk) → encoded in Task 3 Step 5 and Task 4. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code; every command shows expected output. ✓

**Type consistency:** `DecorDef` fields (`texture`, `weight`, `emits_light`, `light_color`, `light_energy`, `light_radius`, `flicker_amplitude`) are identical across Task 1, Task 3 tests, and Task 5 `.tres`. `FlickerLight` exposes `base_energy` and `amplitude`, set consistently in Task 2 (lantern), Task 3 (`_spawn_decor`), and asserted in tests. `populate(coord, biome, world_seed, material_bytes)` signature matches between Task 3 (definition), Task 3 tests (4-arg calls), and Task 4 (caller). `_shared_light_gradient` / `_LIGHT_TEXTURE_HALF` naming is consistent within Task 3. ✓

**Decoupling note:** Task 3's `material_bytes` default (`PackedByteArray()`) lets the still-unmodified `floor_container.gd` compile and run (producing no decor) after Task 3's commit, so every commit leaves a green tree; Task 4 then switches decor on.
