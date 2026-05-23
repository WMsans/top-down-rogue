# Floor Background Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render a biome-driven tiled floor with sparse decorations beneath the existing terrain chunks, so the world no longer shows Godot's default background.

**Architecture:** A new `FloorContainer` sibling of `ChunkContainer` owns one `FloorChunk` per loaded terrain chunk coord. Each `FloorChunk` is a Node2D with a 256×256 tiled `Sprite2D` for the floor and a handful of 16×16 `Sprite2D` children for decorations, placed deterministically via seeded RNG. `BiomeDef` gains `floor_texture`, `decor_textures`, and `decor_chance` fields, so each biome's `.tres` drives the visuals. Chunk lifecycle is wired through two `WorldManager` signals: existing `chunks_generated`, plus a new `chunk_unloaded` we emit from `ChunkManager.unload_chunk`.

**Tech Stack:** Godot 4 (GDScript), GdUnit4 for tests, existing compute-shader terrain pipeline (untouched).

**Spec:** `docs/superpowers/specs/2026-05-23-floor-background-design.md`

---

## File map

- `src/core/biome_def.gd` — add 3 fields.
- `src/core/world_manager.gd` — declare `chunk_unloaded` signal, instantiate `FloorContainer` in `_ready()`.
- `src/core/chunk_manager.gd` — emit `chunk_unloaded(coord)` from `unload_chunk()`.
- `src/terrain/floor_chunk.gd` — new file, the per-chunk visual node.
- `src/terrain/floor_container.gd` — new file, owns the coord → FloorChunk dict.
- `tests/unit/test_floor_chunk.gd` — new GdUnit4 test suite.
- `tests/unit/test_biome_def.gd` — extend with new-field defaults.
- `assets/biomes/{caves,frozen,magma,mines,vault}.tres` — populate new fields by hand in editor (Task 8).

---

## Task 1: Extend BiomeDef with floor + decor fields

**Files:**
- Modify: `src/core/biome_def.gd`
- Test: `tests/unit/test_biome_def.gd`

- [ ] **Step 1: Add failing tests for the new defaults**

Append to `tests/unit/test_biome_def.gd`:

```gdscript
func test_biome_def_floor_defaults() -> void:
	var b := _BiomeDef.new()
	assert_that(b.floor_texture).is_null()
	assert_that(b.decor_textures).is_equal([] as Array[Texture2D])
	assert_that(b.decor_chance).is_equal(0.02)
```

- [ ] **Step 2: Run tests, verify failure**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_biome_def.gd`
Expected: FAIL — `Invalid access to property 'floor_texture'` (or similar).

- [ ] **Step 3: Add the three exported fields to BiomeDef**

In `src/core/biome_def.gd`, after the existing `@export` lines (e.g. after `@export var tint: Color = Color.WHITE`):

```gdscript
@export var floor_texture: Texture2D = null
@export var decor_textures: Array[Texture2D] = []
@export var decor_chance: float = 0.02
```

- [ ] **Step 4: Run tests, verify pass**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_biome_def.gd`
Expected: PASS for all `test_biome_def_*` cases.

- [ ] **Step 5: Commit**

```bash
git add src/core/biome_def.gd tests/unit/test_biome_def.gd
git commit -m "feat(biome): add floor_texture, decor_textures, decor_chance fields"
```

---

## Task 2: Add `chunk_unloaded` signal to WorldManager and emit it

**Files:**
- Modify: `src/core/world_manager.gd:23` (signal declarations area)
- Modify: `src/core/chunk_manager.gd:128-135` (top of `unload_chunk`)

No test for this task — it's a one-line signal addition exercised by Task 5's integration. Signals without consumers can't be unit-tested meaningfully in isolation.

- [ ] **Step 1: Declare the new signal**

In `src/core/world_manager.gd`, right after the existing `signal chunks_generated(new_coords: Array[Vector2i])` line:

```gdscript
signal chunk_unloaded(coord: Vector2i)
```

- [ ] **Step 2: Emit it from `ChunkManager.unload_chunk`**

In `src/core/chunk_manager.gd`, in `unload_chunk(coord: Vector2i)`, immediately after the line that fetches `chunk: Chunk = chunks[coord]` and before any freeing:

```gdscript
func unload_chunk(coord: Vector2i) -> void:
	var chunks: Dictionary = world_manager.chunks
	var chunk: Chunk = chunks[coord]
	world_manager.chunk_unloaded.emit(coord)
	if world_manager._collision_helper != null:
		world_manager._collision_helper.on_chunk_unloaded(coord)
	# ... (rest unchanged)
```

- [ ] **Step 3: Smoke-run the game headlessly to confirm no script errors**

Run: `godot --headless --path . --quit-after 2 scenes/game.tscn`
Expected: exits cleanly (return code 0), no parse errors in stdout/stderr.

- [ ] **Step 4: Commit**

```bash
git add src/core/world_manager.gd src/core/chunk_manager.gd
git commit -m "feat(world): emit chunk_unloaded signal on chunk teardown"
```

---

## Task 3: Create `FloorChunk` — floor sprite only (no decorations yet)

**Files:**
- Create: `src/terrain/floor_chunk.gd`
- Test: `tests/unit/test_floor_chunk.gd`

- [ ] **Step 1: Write failing tests for floor-only behavior**

Create `tests/unit/test_floor_chunk.gd`:

```gdscript
extends GdUnitTestSuite

const _FloorChunk = preload("res://src/terrain/floor_chunk.gd")
const _BiomeDef = preload("res://src/core/biome_def.gd")

const CHUNK_SIZE := 256

func _make_texture(width: int, height: int) -> ImageTexture:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)

func _make_biome(decor_chance: float, decor_count: int) -> _BiomeDef:
	var b := _BiomeDef.new()
	b.floor_texture = _make_texture(16, 16)
	b.decor_chance = decor_chance
	var decors: Array[Texture2D] = []
	for i in range(decor_count):
		decors.append(_make_texture(16, 16))
	b.decor_textures = decors
	return b

func _floor_sprite(chunk: _FloorChunk) -> Sprite2D:
	return chunk.get_node_or_null("FloorSprite") as Sprite2D

func test_populate_creates_floor_sprite_at_chunk_size() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(0.0, 0), 12345)

	var sprite := _floor_sprite(chunk)
	assert_that(sprite).is_not_null()
	assert_that(sprite.texture).is_not_null()
	assert_that(sprite.region_enabled).is_true()
	assert_that(sprite.region_rect.size).is_equal(Vector2(CHUNK_SIZE, CHUNK_SIZE))

func test_populate_skips_when_floor_texture_missing() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	var biome := _BiomeDef.new()  # no floor_texture
	chunk.populate(Vector2i(0, 0), biome, 12345)

	assert_that(_floor_sprite(chunk)).is_null()
```

- [ ] **Step 2: Run tests, verify failure**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_floor_chunk.gd`
Expected: FAIL — file `src/terrain/floor_chunk.gd` does not exist.

- [ ] **Step 3: Implement `FloorChunk` (floor sprite only)**

Create `src/terrain/floor_chunk.gd`:

```gdscript
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
	# Tiling: region_enabled + a region larger than the source, with the
	# Sprite2D's texture_repeat enabled so the texture tiles within the region.
	var sprite := Sprite2D.new()
	sprite.name = "FloorSprite"
	sprite.texture = tex
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, CHUNK_SIZE, CHUNK_SIZE)
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(sprite)
```

- [ ] **Step 4: Run tests, verify pass**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_floor_chunk.gd`
Expected: both tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/terrain/floor_chunk.gd tests/unit/test_floor_chunk.gd
git commit -m "feat(terrain): add FloorChunk with tiled floor sprite"
```

---

## Task 4: Add decoration placement to `FloorChunk`

**Files:**
- Modify: `src/terrain/floor_chunk.gd`
- Test: `tests/unit/test_floor_chunk.gd`

- [ ] **Step 1: Add failing tests for decoration behavior**

Append to `tests/unit/test_floor_chunk.gd`:

```gdscript
func _decor_sprites(chunk: _FloorChunk) -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	for child in chunk.get_children():
		if child.name.begins_with("Decor"):
			out.append(child as Sprite2D)
	return out

func test_decor_chance_zero_creates_no_decor() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(0.0, 3), 42)
	assert_that(_decor_sprites(chunk).size()).is_equal(0)

func test_decor_chance_one_creates_full_grid() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(1.0, 3), 42)
	# 256x256 chunk / 16px tiles = 16x16 = 256 cells
	assert_that(_decor_sprites(chunk).size()).is_equal(256)

func test_decor_placement_is_deterministic_for_same_seed_and_coord() -> void:
	var biome := _make_biome(0.5, 3)
	var a := _FloorChunk.new()
	var b := _FloorChunk.new()
	add_child(a)
	add_child(b)
	a.populate(Vector2i(3, -2), biome, 999)
	b.populate(Vector2i(3, -2), biome, 999)

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
	a.populate(Vector2i(0, 0), biome, 7)
	b.populate(Vector2i(1, 0), biome, 7)

	var ad := _decor_sprites(a)
	var bd := _decor_sprites(b)
	# Same seed + different coords should very rarely produce identical placements.
	var identical := ad.size() == bd.size()
	if identical:
		for i in range(ad.size()):
			if ad[i].position != bd[i].position:
				identical = false
				break
	assert_that(identical).is_false()

func test_empty_decor_textures_skips_decor_pass() -> void:
	var chunk := _FloorChunk.new()
	add_child(chunk)
	chunk.populate(Vector2i(0, 0), _make_biome(1.0, 0), 42)
	assert_that(_decor_sprites(chunk).size()).is_equal(0)
```

- [ ] **Step 2: Run tests, verify failure**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_floor_chunk.gd`
Expected: the 5 new tests FAIL (no decor logic yet); the 2 from Task 3 still PASS.

- [ ] **Step 3: Implement decoration placement**

In `src/terrain/floor_chunk.gd`, modify `populate()` to call a new `_add_decorations()` after `_add_floor_sprite`:

```gdscript
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
	# Combine seed and coord into a single deterministic 64-bit seed.
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
	# Mix world_seed with coord using a simple deterministic hash.
	var h: int = world_seed
	h = (h * 73856093) ^ coord.x
	h = (h * 19349663) ^ coord.y
	return h
```

- [ ] **Step 4: Run tests, verify pass**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_floor_chunk.gd`
Expected: all 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/terrain/floor_chunk.gd tests/unit/test_floor_chunk.gd
git commit -m "feat(terrain): add deterministic decoration placement to FloorChunk"
```

---

## Task 5: Create `FloorContainer`

**Files:**
- Create: `src/terrain/floor_container.gd`

No GdUnit test for this task — it's a thin coordinator over signals from a live `WorldManager`. We verify it via the manual smoke test in Task 7.

- [ ] **Step 1: Implement `FloorContainer`**

Create `src/terrain/floor_container.gd`:

```gdscript
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
		fc.populate(coord, biome, world_seed)
		_chunks[coord] = fc

func _on_chunk_unloaded(coord: Vector2i) -> void:
	if not _chunks.has(coord):
		return
	var fc: Node = _chunks[coord]
	_chunks.erase(coord)
	if is_instance_valid(fc):
		fc.queue_free()
```

- [ ] **Step 2: Parse-check by booting the project headlessly**

Run: `godot --headless --path . --check-only src/terrain/floor_container.gd`
Expected: no errors (file parses).

- [ ] **Step 3: Commit**

```bash
git add src/terrain/floor_container.gd
git commit -m "feat(terrain): add FloorContainer to manage per-chunk floors"
```

---

## Task 6: Wire `FloorContainer` into `WorldManager`

**Files:**
- Modify: `src/core/world_manager.gd`

- [ ] **Step 1: Instantiate `FloorContainer` in `_ready()`**

In `src/core/world_manager.gd`, locate the existing `chunk_container` setup (line ~38 in the scene file; the field `@onready var chunk_container: Node2D = $ChunkContainer` near the top of the script). Inside `_ready()`, after `add_to_group("world_manager")` and before `compute_device` setup, add the floor container so it draws *under* terrain:

```gdscript
var floor_container: FloorContainer

func _ready() -> void:
	add_to_group("world_manager")

	floor_container = FloorContainer.new()
	floor_container.name = "FloorContainer"
	floor_container.z_index = -10
	add_child(floor_container)
	floor_container.bind(self)

	rd = RenderingServer.get_rendering_device()
	# ... (rest of _ready unchanged)
```

Also make sure `chunk_container` has a higher z-index than -10. Since `ChunkContainer` is in the .tscn with default z_index 0, this already holds. No scene file edit required.

- [ ] **Step 2: Boot the project headlessly to confirm no script errors**

Run: `godot --headless --path . --quit-after 3 scenes/game.tscn`
Expected: exits cleanly (return code 0). Look for "FloorContainer" appearing in scene tree dump if any debug logging is on; otherwise just verify no errors.

- [ ] **Step 3: Commit**

```bash
git add src/core/world_manager.gd
git commit -m "feat(world): instantiate FloorContainer beneath ChunkContainer"
```

---

## Task 7: Manual visual smoke test (no biome data yet)

This task has no code changes — it confirms wiring before we populate biome resources.

- [ ] **Step 1: Run the game**

Launch the Godot editor and play `scenes/game.tscn`, or run:
```bash
godot --path . scenes/game.tscn
```

- [ ] **Step 2: Observe**

Because no biome has `floor_texture` set yet, the world should look **identical to before this work**: terrain chunks render normally, areas outside chunks still show Godot default background. A one-time warning `FloorChunk: biome has no floor_texture; skipping floor render` should appear in the console.

- [ ] **Step 3: Verify scene tree**

Open the remote debugger ("Remote" tab in editor while running) and confirm:
- `WorldManager` has a `FloorContainer` child.
- As you walk around, `FloorChunk_X_Y` nodes appear and disappear under `FloorContainer` matching the active chunks.

If both hold, wiring is good. No commit (no changes).

---

## Task 8: Author per-biome floor and decoration textures

This task is done in the Godot editor. There is no automated test — the success criterion is the manual visual check in Task 9.

For each of the five biomes (`assets/biomes/caves.tres`, `frozen.tres`, `magma.tres`, `mines.tres`, `vault.tres`):

- [ ] **Step 1: Pick a 16×16 floor region from `Floor.png`**

Open `textures/Assets/DawnLike/Objects/Floor.png` in the editor for reference. For each biome, create a new `AtlasTexture` resource (right-click in FileSystem → New Resource → AtlasTexture):
- `atlas` = `res://textures/Assets/DawnLike/Objects/Floor.png`
- `region` = a `Rect2(x, y, 16, 16)` over a fitting floor tile.

Suggested mappings (adjust to taste; each tile in Floor.png is 16×16, with the sheet organized in 3-tile-wide blocks per floor type — pick the center tile of a block for the "plain" variant):
- `caves` → a stone/dirt tile.
- `frozen` → an ice/snow tile.
- `magma` → a cracked red/orange tile.
- `mines` → a brick tile.
- `vault` → a polished stone tile.

Save each AtlasTexture as `assets/biomes/floor_<biome>.tres` (e.g. `assets/biomes/floor_caves.tres`).

- [ ] **Step 2: Assign each `floor_texture` field**

Open each biome `.tres` in the inspector and set `floor_texture` to the matching AtlasTexture file from Step 1.

- [ ] **Step 3: Author 3–6 decoration AtlasTextures per biome from `Ground1.png`**

For each biome, pick decoration tiles that thematically match. Save them as `assets/biomes/decor_<biome>_<n>.tres`. Add them to the biome's `decor_textures` array in the inspector. Leave `decor_chance` at its default `0.02` for now.

- [ ] **Step 4: Commit all biome resource changes together**

```bash
git add assets/biomes/
git commit -m "feat(biome): populate floor_texture and decor_textures for all biomes"
```

---

## Task 9: Final visual verification

No code changes. Verify the feature works end-to-end.

- [ ] **Step 1: Launch the game**

```bash
godot --path . scenes/game.tscn
```

- [ ] **Step 2: Verify floor appears in the starting biome**

Walk around. The floor texture should be visible under terrain wherever a chunk is loaded. There should be no Godot-grey background visible within the active chunk radius. Sparse decorations should appear (~5 per chunk on average).

- [ ] **Step 3: Verify floor swaps cleanly on floor change**

Trigger a descent (use whatever debug command or portal exists in the project). Confirm:
- All old `FloorChunk` nodes are freed.
- New chunks spawn with the new biome's floor texture and decor pool.
- No leftover floor sprites from the previous biome.

- [ ] **Step 4: Verify chunk unload**

Walk far enough that chunks unload behind you. Confirm `FloorChunk` nodes for those coords disappear from the scene tree (Remote tab).

If all four checks pass, the feature is complete. If any fail, file a follow-up task and do not mark the plan done.

---

## Done criteria

- All 7 unit tests pass (`tests/unit/test_floor_chunk.gd` + extended `test_biome_def.gd`).
- All 5 biomes have `floor_texture` and at least one `decor_textures` entry set.
- Manual visual checks in Task 9 all pass.
- No regressions in existing tests:
  Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/`
  Expected: full suite green.
