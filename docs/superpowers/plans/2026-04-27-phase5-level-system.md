# Phase 5: Level System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Noita-style level system: per-floor biomes, PNG room templates with spawn markers, per-material pool noise, sector-based deterministic placement, and floor-advance via portal.

**Architecture:** A CPU-side `SectorGrid` deterministically picks a `RoomTemplate` per sector. The current `BiomeDef` (selected by floor) supplies noise params, a material palette, pool definitions, and the template list. Generation runs five GPU stages (`wood_fill → biome_cave → biome_pools → pixel_scene_stamp → secret_ring`). After generation, `SpawnDispatcher` reads each placed template's PNG G-channel from a CPU cache and spawns enemies/chests/shops/bosses at the marker pixel positions.

**Tech Stack:** Godot 4.6, GDScript, GLSL compute shaders, GdUnit4 (extends `GdUnitTestSuite`).

---

## File Map

### Created

| File | Responsibility |
|------|---------------|
| `src/core/pool_def.gd` | Resource: `(material_id, noise_scale, noise_threshold)` |
| `src/core/room_template.gd` | Resource: PNG path + flags |
| `src/core/biome_def.gd` | Resource: noise + materials + templates |
| `src/core/sector_grid.gd` | Pure class: sector math + deterministic template selection |
| `src/core/template_pack.gd` | Loads PNGs into `Texture2DArray` per size class; caches `Image` for marker readback |
| `src/autoload/biome_registry.gd` | Autoload — owns `BiomeDef[]`; `get_biome(floor)` |
| `src/autoload/level_manager.gd` | Autoload — floor state, sector grid, advance_floor |
| `src/core/spawn_dispatcher.gd` | Reads marker pixels, spawns entities, dedupes by sector |
| `src/portal.gd` | Area2D interactable that calls `LevelManager.advance_floor()` |
| `scenes/portal.tscn` | Portal scene |
| `tools/generate_room_templates.gd` | Entry point — runs generators, writes PNGs |
| `tools/room_generators/blob_room.gd` | Irregular blob template generator |
| `tools/room_generators/arena.gd` | Rectangular arena generator |
| `tools/room_generators/corridor.gd` | Long-thin corridor generator |
| `tools/room_generators/secret_vault.gd` | Small treasure chamber generator |
| `tools/room_generators/shop_chamber.gd` | Shop chamber generator |
| `assets/rooms/<biome>/*.png` | Generated templates (~25 files) |
| `assets/biomes/caves.tres` … | 5 BiomeDef resources |
| `shaders/include/biome_cave_stage.glslinc` | Biome-driven cave noise stage |
| `shaders/include/biome_pools_stage.glslinc` | Per-material pool noise stage |
| `shaders/include/pixel_scene_stamp.glslinc` | Stamps PNGs into chunk via Texture2DArray |
| `shaders/include/secret_ring_stage.glslinc` | Annular wall around secret rooms |
| `tests/unit/test_sector_grid.gd` | Determinism + math |
| `tests/unit/test_template_pack.gd` | Marker readback correctness |
| `tests/unit/test_biome_def.gd` | Resource defaults |

### Modified

| File | Change |
|------|--------|
| `src/autoload/material_registry.gd` | Add DIRT, COAL, ICE, WATER (static-solid) |
| `src/core/world_manager.gd` | New `chunks_generated` signal; new `reset()`; pass biome+stamps to dispatch |
| `src/core/compute_device.gd` | Stamp storage buffer, biome storage buffer, template Texture2DArray bindings |
| `shaders/compute/generation.glsl` | Replace cave include with new chain |
| `project.godot` | Register `BiomeRegistry`, `LevelManager` autoloads |

---

## Task 1: Add new materials (DIRT, COAL, ICE, WATER)

**Files:**
- Modify: `src/autoload/material_registry.gd`

- [ ] **Step 1: Add the four materials**

In `_init_materials()` after the LAVA block, append:

```gdscript
    var mat_dirt := MaterialDef.new(
        "DIRT", "",
        false, 0, 0,
        true, true,
        Color(0.45, 0.32, 0.18, 1.0)
    )
    mat_dirt.id = materials.size()
    materials.append(mat_dirt)
    MAT_DIRT = mat_dirt.id

    var mat_coal := MaterialDef.new(
        "COAL", "",
        true, 220, 200,
        true, true,
        Color(0.12, 0.12, 0.14, 1.0)
    )
    mat_coal.id = materials.size()
    materials.append(mat_coal)
    MAT_COAL = mat_coal.id

    var mat_ice := MaterialDef.new(
        "ICE", "",
        false, 0, 0,
        true, true,
        Color(0.7, 0.85, 0.95, 1.0)
    )
    mat_ice.id = materials.size()
    materials.append(mat_ice)
    MAT_ICE = mat_ice.id

    var mat_water := MaterialDef.new(
        "WATER", "",
        false, 0, 0,
        true, true,
        Color(0.2, 0.45, 0.75, 1.0)
    )
    mat_water.id = materials.size()
    materials.append(mat_water)
    MAT_WATER = mat_water.id
```

Add the four `MAT_*` declarations near the top with the others:

```gdscript
var MAT_DIRT: int
var MAT_COAL: int
var MAT_ICE: int
var MAT_WATER: int
```

- [ ] **Step 2: Verify materials load in editor**

Open the project in Godot. Verify no autoload errors in the editor. Open any scene that uses terrain — verify game launches without complaints.

- [ ] **Step 3: Regenerate the materials shader include**

In Godot editor, run `tools/generate_material_glsl.gd` (or however the existing material GLSL generator is invoked — there's an existing convention). Check `shaders/generated/materials.glslinc` was updated to include the 4 new materials.

- [ ] **Step 4: Commit**

```bash
git add src/autoload/material_registry.gd shaders/generated/materials.glslinc
git commit -m "feat: add DIRT, COAL, ICE, WATER static-solid materials"
```

---

## Task 2: Resource classes (PoolDef, RoomTemplate, BiomeDef)

**Files:**
- Create: `src/core/pool_def.gd`
- Create: `src/core/room_template.gd`
- Create: `src/core/biome_def.gd`
- Create: `tests/unit/test_biome_def.gd`

- [ ] **Step 1: Write the failing test for BiomeDef defaults**

Create `tests/unit/test_biome_def.gd`:

```gdscript
extends GdUnitTestSuite

const _BiomeDef = preload("res://src/core/biome_def.gd")
const _PoolDef = preload("res://src/core/pool_def.gd")
const _RoomTemplate = preload("res://src/core/room_template.gd")

func test_biome_def_has_defaults() -> void:
    var b := _BiomeDef.new()
    assert_that(b.cave_noise_scale).is_equal(0.008)
    assert_that(b.cave_threshold).is_equal(0.42)
    assert_that(b.octaves).is_equal(5)
    assert_that(b.secret_ring_thickness).is_equal(3)

func test_pool_def_construction() -> void:
    var p := _PoolDef.new()
    p.material_id = 7
    p.noise_scale = 0.005
    p.noise_threshold = 0.6
    assert_that(p.material_id).is_equal(7)

func test_room_template_defaults() -> void:
    var rt := _RoomTemplate.new()
    assert_that(rt.weight).is_equal(1.0)
    assert_that(rt.size_class).is_equal(64)
    assert_that(rt.is_secret).is_false()
    assert_that(rt.is_boss).is_false()
    assert_that(rt.rotatable).is_true()
```

- [ ] **Step 2: Run tests to verify they fail**

Run the GdUnit4 test for `tests/unit/test_biome_def.gd`. Expected: errors about missing class files.

- [ ] **Step 3: Implement PoolDef**

Create `src/core/pool_def.gd`:

```gdscript
class_name PoolDef
extends Resource

@export var material_id: int = 0
@export var noise_scale: float = 0.005
@export var noise_threshold: float = 0.6
@export var seed_offset: int = 0
```

- [ ] **Step 4: Implement RoomTemplate**

Create `src/core/room_template.gd`:

```gdscript
class_name RoomTemplate
extends Resource

@export var png_path: String = ""
@export var weight: float = 1.0
@export var size_class: int = 64
@export var is_secret: bool = false
@export var is_boss: bool = false
@export var rotatable: bool = true
```

- [ ] **Step 5: Implement BiomeDef**

Create `src/core/biome_def.gd`:

```gdscript
class_name BiomeDef
extends Resource

@export var display_name: String = ""
@export var cave_noise_scale: float = 0.008
@export var cave_threshold: float = 0.42
@export var ridge_weight: float = 0.3
@export var ridge_scale: float = 0.012
@export var octaves: int = 5
@export var background_material: int = 2  # STONE
@export var pool_materials: Array[PoolDef] = []
@export var room_templates: Array[RoomTemplate] = []
@export var boss_templates: Array[RoomTemplate] = []
@export var secret_ring_thickness: int = 3
@export var tint: Color = Color.WHITE
```

- [ ] **Step 6: Run tests and verify they pass**

Run the GdUnit4 test for `tests/unit/test_biome_def.gd`. Expected: all 3 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add src/core/pool_def.gd src/core/room_template.gd src/core/biome_def.gd tests/unit/test_biome_def.gd
git commit -m "feat: add BiomeDef, RoomTemplate, PoolDef resources"
```

---

## Task 3: Room generator — blob_room

**Files:**
- Create: `tools/room_generators/blob_room.gd`

This generator (and the four others) is a `@tool` script that returns an `Image`. The orchestration script (Task 6) calls these and writes PNGs.

- [ ] **Step 1: Implement blob_room**

Create `tools/room_generators/blob_room.gd`:

```gdscript
@tool
class_name BlobRoomGenerator

# Generates an irregular blob carved into the biome's background material,
# optional pool material patch, and scattered enemy markers.
#
# Args:
#   size: int — square size (16/32/64/128)
#   pool_material: int — material id for floor pool, or -1 for none
#   enemy_count: int — number of enemy markers to scatter
#   gen_seed: int — RNG seed
#
# Returns: Image (RGBA8) ready to save as PNG
static func generate(size: int, pool_material: int, enemy_count: int, gen_seed: int) -> Image:
    var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
    img.fill(Color(0, 0, 0, 0))  # transparent (skip mask = 0)

    var rng := RandomNumberGenerator.new()
    rng.seed = gen_seed

    var center := Vector2(size / 2.0, size / 2.0)
    var base_radius := size * 0.40

    # Carve blob: distance + perlin-ish bumpiness via sine sum
    for y in range(size):
        for x in range(size):
            var dx := x - center.x
            var dy := y - center.y
            var dist := sqrt(dx * dx + dy * dy)
            var theta := atan2(dy, dx)
            var bump := sin(theta * 3.0 + rng.randf_range(0.0, 0.3)) * 4.0
            bump += sin(theta * 5.0 + rng.randf_range(0.0, 0.3)) * 2.0
            var r := base_radius + bump
            if dist < r:
                # AIR (R=0), mask = 255 → write
                img.set_pixel(x, y, Color8(0, 0, 0, 255))

    # Pool patch in lower half
    if pool_material >= 0:
        var pool_center := Vector2(size / 2.0, size * 0.65)
        var pool_radius := size * 0.18
        for y in range(size):
            for x in range(size):
                var dx2 := x - pool_center.x
                var dy2 := y - pool_center.y
                var d2 := sqrt(dx2 * dx2 + dy2 * dy2)
                if d2 < pool_radius:
                    img.set_pixel(x, y, Color8(pool_material, 0, 0, 255))

    # Scatter enemy markers (G=1) on AIR pixels
    var placed := 0
    var attempts := 0
    while placed < enemy_count and attempts < enemy_count * 20:
        attempts += 1
        var px := rng.randi_range(2, size - 3)
        var py := rng.randi_range(2, size - 3)
        var current := img.get_pixel(px, py)
        # Only place on AIR (R=0) pixels with mask=255
        if int(current.a8) == 255 and int(current.r8) == 0:
            img.set_pixel(px, py, Color8(0, 1, 0, 255))
            placed += 1

    return img
```

- [ ] **Step 2: Quick visual smoke check (optional)**

In Godot editor, run a script that calls `BlobRoomGenerator.generate(64, -1, 3, 42)` and saves the image to `/tmp/blob.png`. Open it in an image viewer — should look like an irregular blob with 3 G=1 pixels (visible as faint green).

- [ ] **Step 3: Commit**

```bash
git add tools/room_generators/blob_room.gd
git commit -m "feat: add blob_room template generator"
```

---

## Task 4: Room generators — arena, corridor

**Files:**
- Create: `tools/room_generators/arena.gd`
- Create: `tools/room_generators/corridor.gd`

- [ ] **Step 1: Implement arena**

Create `tools/room_generators/arena.gd`:

```gdscript
@tool
class_name ArenaGenerator

# Rectangular arena with thin wall border and clustered enemies.
# is_boss=true → single boss marker (G=6) in center, boss flag for caller to set on RoomTemplate.
static func generate(size: int, enemy_count: int, is_boss: bool, gen_seed: int) -> Image:
    var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
    img.fill(Color(0, 0, 0, 0))

    var rng := RandomNumberGenerator.new()
    rng.seed = gen_seed

    var inset := 3
    # Carve interior to AIR (mask=255, R=0)
    for y in range(inset, size - inset):
        for x in range(inset, size - inset):
            img.set_pixel(x, y, Color8(0, 0, 0, 255))

    # Border ring of biome native (R=255 = native sentinel)
    for y in range(inset - 1, size - inset + 1):
        for x in range(inset - 1, size - inset + 1):
            var on_edge := (
                x == inset - 1 or x == size - inset
                or y == inset - 1 or y == size - inset
            )
            if on_edge:
                img.set_pixel(x, y, Color8(255, 0, 0, 255))

    if is_boss:
        var cx := size / 2
        var cy := size / 2
        img.set_pixel(cx, cy, Color8(0, 6, 0, 255))
        return img

    # Cluster enemies near center
    var placed := 0
    var attempts := 0
    while placed < enemy_count and attempts < enemy_count * 20:
        attempts += 1
        var px := rng.randi_range(inset + 2, size - inset - 3)
        var py := rng.randi_range(inset + 2, size - inset - 3)
        var current := img.get_pixel(px, py)
        if int(current.a8) == 255 and int(current.r8) == 0 and int(current.g8) == 0:
            img.set_pixel(px, py, Color8(0, 1, 0, 255))
            placed += 1

    return img
```

- [ ] **Step 2: Implement corridor**

Create `tools/room_generators/corridor.gd`:

```gdscript
@tool
class_name CorridorGenerator

# Long thin corridor. Length axis = X. Width is fixed; length defines size_class via caller.
# has_chest=true places a chest marker (G=3) at the far end.
static func generate(length: int, width: int, has_chest: bool, gen_seed: int) -> Image:
    # Output square size = max(length, width); pad with transparent
    var size: int = max(length, width)
    var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
    img.fill(Color(0, 0, 0, 0))

    var rng := RandomNumberGenerator.new()
    rng.seed = gen_seed

    var y_start: int = (size - width) / 2
    var x_start: int = (size - length) / 2

    for y in range(y_start, y_start + width):
        for x in range(x_start, x_start + length):
            img.set_pixel(x, y, Color8(0, 0, 0, 255))

    # End-caps with native border on both ends
    for y in range(y_start - 1, y_start + width + 1):
        if y >= 0 and y < size:
            if x_start - 1 >= 0:
                img.set_pixel(x_start - 1, y, Color8(255, 0, 0, 255))
            if x_start + length < size:
                img.set_pixel(x_start + length, y, Color8(255, 0, 0, 255))

    if has_chest:
        var cy := y_start + width / 2
        var cx := x_start + length - 2
        img.set_pixel(cx, cy, Color8(0, 3, 0, 255))

    # Sparse enemies along corridor
    var placed := 0
    var enemy_count := max(1, length / 24)
    var attempts := 0
    while placed < enemy_count and attempts < 40:
        attempts += 1
        var px := rng.randi_range(x_start + 2, x_start + length - 3)
        var py := y_start + width / 2
        var current := img.get_pixel(px, py)
        if int(current.a8) == 255 and int(current.r8) == 0 and int(current.g8) == 0:
            img.set_pixel(px, py, Color8(0, 1, 0, 255))
            placed += 1

    return img
```

- [ ] **Step 3: Commit**

```bash
git add tools/room_generators/arena.gd tools/room_generators/corridor.gd
git commit -m "feat: add arena and corridor template generators"
```

---

## Task 5: Room generators — secret_vault, shop_chamber

**Files:**
- Create: `tools/room_generators/secret_vault.gd`
- Create: `tools/room_generators/shop_chamber.gd`

- [ ] **Step 1: Implement secret_vault**

Create `tools/room_generators/secret_vault.gd`:

```gdscript
@tool
class_name SecretVaultGenerator

# Small chamber with secret_loot marker. Outer ring is left transparent —
# secret_ring stage in the shader adds the wall after pixel_scene stamps.
static func generate(size: int, gen_seed: int) -> Image:
    var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
    img.fill(Color(0, 0, 0, 0))

    var center := Vector2(size / 2.0, size / 2.0)
    var radius := size * 0.40

    for y in range(size):
        for x in range(size):
            var dx := x - center.x
            var dy := y - center.y
            var dist := sqrt(dx * dx + dy * dy)
            if dist < radius:
                img.set_pixel(x, y, Color8(0, 0, 0, 255))

    # SECRET_LOOT marker (G=5) at center
    img.set_pixel(int(center.x), int(center.y), Color8(0, 5, 0, 255))

    return img
```

- [ ] **Step 2: Implement shop_chamber**

Create `tools/room_generators/shop_chamber.gd`:

```gdscript
@tool
class_name ShopChamberGenerator

# Small room with central shop marker (G=4).
static func generate(size: int, gen_seed: int) -> Image:
    var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
    img.fill(Color(0, 0, 0, 0))

    var inset := 2
    for y in range(inset, size - inset):
        for x in range(inset, size - inset):
            img.set_pixel(x, y, Color8(0, 0, 0, 255))

    # Border of biome native
    for y in range(inset - 1, size - inset + 1):
        for x in range(inset - 1, size - inset + 1):
            var on_edge := (
                x == inset - 1 or x == size - inset
                or y == inset - 1 or y == size - inset
            )
            if on_edge:
                img.set_pixel(x, y, Color8(255, 0, 0, 255))

    var cx := size / 2
    var cy := size / 2
    img.set_pixel(cx, cy, Color8(0, 4, 0, 255))

    return img
```

- [ ] **Step 3: Commit**

```bash
git add tools/room_generators/secret_vault.gd tools/room_generators/shop_chamber.gd
git commit -m "feat: add secret_vault and shop_chamber template generators"
```

---

## Task 6: Generator entry point + bootstrap PNGs

**Files:**
- Create: `tools/generate_room_templates.gd`
- Create: `assets/rooms/` directory tree

- [ ] **Step 1: Implement orchestration script**

Create `tools/generate_room_templates.gd`:

```gdscript
@tool
extends SceneTree

# Entry script. Run via:
#   godot --headless --script tools/generate_room_templates.gd
#
# Writes PNGs to assets/rooms/<biome>/. Creates directories if missing.

const OUT_DIR := "res://assets/rooms"

# Material IDs (must match MaterialRegistry order; cannot import the autoload
# from a SceneTree script, so values are duplicated here)
const MAT_LAVA := 4
const MAT_DIRT := 5
const MAT_COAL := 6
const MAT_ICE := 7
const MAT_WATER := 8

const _Blob = preload("res://tools/room_generators/blob_room.gd")
const _Arena = preload("res://tools/room_generators/arena.gd")
const _Corridor = preload("res://tools/room_generators/corridor.gd")
const _SecretVault = preload("res://tools/room_generators/secret_vault.gd")
const _ShopChamber = preload("res://tools/room_generators/shop_chamber.gd")

func _init() -> void:
    _ensure_dirs()
    _generate_caves()
    _generate_mines()
    _generate_magma()
    _generate_frozen()
    _generate_vault()
    print("[generate_room_templates] done")
    quit()

func _ensure_dirs() -> void:
    for biome in ["caves", "mines", "magma", "frozen", "vault"]:
        DirAccess.make_dir_recursive_absolute("res://assets/rooms/" + biome)

func _save(img: Image, biome: String, name: String) -> void:
    var path := "%s/%s/%s.png" % [OUT_DIR, biome, name]
    var abs := ProjectSettings.globalize_path(path)
    img.save_png(abs)
    print("  wrote ", path)

# --- per-biome bootstraps ---

func _generate_caves() -> void:
    _save(_Blob.generate(64, MAT_DIRT, 3, 1001), "caves", "blob_a")
    _save(_Blob.generate(64, -1, 4, 1002), "caves", "blob_b")
    _save(_Corridor.generate(96, 32, true, 1003), "caves", "corridor_a")
    _save(_SecretVault.generate(32, 1004), "caves", "secret_a")
    _save(_Arena.generate(128, 0, true, 1005), "caves", "boss_arena")

func _generate_mines() -> void:
    _save(_Corridor.generate(96, 32, false, 2001), "mines", "corridor_a")
    _save(_Corridor.generate(96, 32, true, 2002), "mines", "corridor_b")
    _save(_Arena.generate(64, 5, false, 2003), "mines", "arena_a")
    _save(_SecretVault.generate(32, 2004), "mines", "secret_a")
    _save(_Arena.generate(128, 0, true, 2005), "mines", "boss_arena")

func _generate_magma() -> void:
    _save(_Blob.generate(64, MAT_LAVA, 3, 3001), "magma", "blob_lava_a")
    _save(_Blob.generate(64, MAT_LAVA, 4, 3002), "magma", "blob_lava_b")
    _save(_Arena.generate(64, 4, false, 3003), "magma", "arena_a")
    _save(_Arena.generate(128, 0, true, 3005), "magma", "boss_arena")

func _generate_frozen() -> void:
    _save(_Blob.generate(64, MAT_WATER, 3, 4001), "frozen", "blob_water_a")
    _save(_Blob.generate(64, MAT_WATER, 4, 4002), "frozen", "blob_water_b")
    _save(_Corridor.generate(96, 32, true, 4003), "frozen", "corridor_a")
    _save(_Arena.generate(128, 0, true, 4005), "frozen", "boss_arena")

func _generate_vault() -> void:
    _save(_Arena.generate(64, 5, false, 5001), "vault", "arena_a")
    _save(_Arena.generate(64, 5, false, 5002), "vault", "arena_b")
    _save(_ShopChamber.generate(32, 5003), "vault", "shop_a")
    _save(_Arena.generate(128, 0, true, 5005), "vault", "boss_arena")
```

- [ ] **Step 2: Run the generator**

```bash
cd /Users/jeremyzhao/Development/godot/top-down-rogue
godot --headless --script tools/generate_room_templates.gd
```

Expected: 22 PNG files written under `assets/rooms/<biome>/`.

If the `godot` command is unavailable or fails headless, instead create a temporary scene with a script that calls `_init()` manually from inside the editor.

- [ ] **Step 3: Verify output**

```bash
find assets/rooms -name '*.png' | wc -l
```

Expected: 22 (5+5+4+4+4).

- [ ] **Step 4: Commit**

```bash
git add tools/generate_room_templates.gd assets/rooms/
git commit -m "feat: bootstrap 22 generated room template PNGs"
```

---

## Task 7: Author the 5 BiomeDef .tres files

**Files:**
- Create: `assets/biomes/caves.tres`
- Create: `assets/biomes/mines.tres`
- Create: `assets/biomes/magma.tres`
- Create: `assets/biomes/frozen.tres`
- Create: `assets/biomes/vault.tres`

These are authored by hand in the Godot editor (Inspector). Use the spec's biome table for parameters.

- [ ] **Step 1: Create the directory**

In Godot FileSystem panel, create folder `assets/biomes/`.

- [ ] **Step 2: Author caves.tres**

Right-click `assets/biomes/` → New Resource → `BiomeDef`. Save as `caves.tres`. Set fields in Inspector:

- `display_name`: "Caves"
- `cave_noise_scale`: 0.008
- `cave_threshold`: 0.42
- `ridge_weight`: 0.3
- `ridge_scale`: 0.012
- `octaves`: 5
- `background_material`: 2 (STONE — the int id)
- `pool_materials`: add 1 PoolDef → material_id=5 (DIRT), noise_scale=0.005, noise_threshold=0.7, seed_offset=11
- `room_templates`: add 4 RoomTemplate entries:
  - blob_a: png_path=`res://assets/rooms/caves/blob_a.png`, weight=2.0, size_class=64
  - blob_b: same path pattern, weight=2.0, size_class=64
  - corridor_a: weight=1.5, size_class=128 (corridors live in size 128 array — see TemplatePack note below)
  - secret_a: weight=1.0, size_class=32, is_secret=true
- `boss_templates`: add 1 RoomTemplate → boss_arena.png, size_class=128, is_boss=true, rotatable=false
- `secret_ring_thickness`: 3
- `tint`: Color(1, 1, 1, 1)

**Note on size classes:** `Texture2DArray` requires all images in an array to be the same size. Group templates into 4 arrays: 16, 32, 64, 128. Corridors are 96×32 padded to 128×128 (see corridor generator). Boss arenas are 128×128. Set `size_class` to whichever array bucket the PNG fits into.

- [ ] **Step 3: Author mines.tres**

- `display_name`: "Mines"
- `cave_noise_scale`: 0.010 (tighter than caves)
- `cave_threshold`: 0.45
- `ridge_weight`: 0.4
- `octaves`: 5
- `background_material`: 2 (STONE)
- `pool_materials`: 2 entries
  - COAL: material_id=6, noise_scale=0.006, noise_threshold=0.65, seed_offset=21
  - WOOD: material_id=1, noise_scale=0.020, noise_threshold=0.85, seed_offset=22
- `room_templates`: corridor_a, corridor_b (size 128), arena_a (size 64), secret_a (size 32, is_secret=true)
- `boss_templates`: boss_arena (size 128)
- `tint`: Color(0.9, 0.85, 0.75, 1)

- [ ] **Step 4: Author magma.tres**

- `display_name`: "Magma Caverns"
- `cave_noise_scale`: 0.012
- `cave_threshold`: 0.50 (sparser caves — more rock)
- `ridge_weight`: 0.5
- `octaves`: 5
- `background_material`: 2 (STONE)
- `pool_materials`: 2 entries
  - LAVA: material_id=4, noise_scale=0.004, noise_threshold=0.72, seed_offset=31
  - GAS: material_id=3, noise_scale=0.015, noise_threshold=0.85, seed_offset=32
- `room_templates`: blob_lava_a, blob_lava_b (size 64), arena_a (size 64)
- `boss_templates`: boss_arena (size 128)
- `tint`: Color(1, 0.7, 0.5, 1)

- [ ] **Step 5: Author frozen.tres**

- `display_name`: "Frozen Depths"
- `cave_noise_scale`: 0.009
- `cave_threshold`: 0.40
- `ridge_weight`: 0.2
- `octaves`: 4
- `background_material`: 7 (ICE)
- `pool_materials`: 1 entry
  - WATER: material_id=8, noise_scale=0.007, noise_threshold=0.62, seed_offset=41
- `room_templates`: blob_water_a, blob_water_b (size 64), corridor_a (size 128)
- `boss_templates`: boss_arena (size 128)
- `tint`: Color(0.7, 0.85, 1, 1)

- [ ] **Step 6: Author vault.tres**

- `display_name`: "Vault"
- `cave_noise_scale`: 0.014 (denser — more wall, less open)
- `cave_threshold`: 0.55
- `ridge_weight`: 0.5
- `octaves`: 5
- `background_material`: 1 (WOOD)
- `pool_materials`: 1 entry
  - STONE: material_id=2, noise_scale=0.012, noise_threshold=0.72, seed_offset=51
- `room_templates`: arena_a, arena_b (size 64), shop_a (size 32)
- `boss_templates`: boss_arena (size 128)
- `tint`: Color(1, 0.95, 0.85, 1)

- [ ] **Step 7: Commit**

```bash
git add assets/biomes/
git commit -m "feat: author 5 BiomeDef resources (Caves, Mines, Magma, Frozen, Vault)"
```

---

## Task 8: SectorGrid (with tests)

**Files:**
- Create: `src/core/sector_grid.gd`
- Create: `tests/unit/test_sector_grid.gd`

- [ ] **Step 1: Write failing tests**

Create `tests/unit/test_sector_grid.gd`:

```gdscript
extends GdUnitTestSuite

const _SectorGrid = preload("res://src/core/sector_grid.gd")
const _BiomeDef = preload("res://src/core/biome_def.gd")
const _RoomTemplate = preload("res://src/core/room_template.gd")

func _make_biome() -> _BiomeDef:
    var b := _BiomeDef.new()
    var rt := _RoomTemplate.new()
    rt.png_path = "rt0"
    rt.weight = 1.0
    var rt2 := _RoomTemplate.new()
    rt2.png_path = "rt1"
    rt2.weight = 2.0
    b.room_templates = [rt, rt2]
    var boss := _RoomTemplate.new()
    boss.png_path = "boss"
    boss.is_boss = true
    boss.rotatable = false
    b.boss_templates = [boss]
    return b

func test_world_to_sector_origin() -> void:
    var grid := _SectorGrid.new(12345, _make_biome())
    assert_that(grid.world_to_sector(Vector2.ZERO)).is_equal(Vector2i.ZERO)

func test_world_to_sector_positive() -> void:
    var grid := _SectorGrid.new(12345, _make_biome())
    assert_that(grid.world_to_sector(Vector2(384, 0))).is_equal(Vector2i(1, 0))

func test_world_to_sector_negative() -> void:
    var grid := _SectorGrid.new(12345, _make_biome())
    assert_that(grid.world_to_sector(Vector2(-1, -1))).is_equal(Vector2i(-1, -1))

func test_sector_to_world_center() -> void:
    var grid := _SectorGrid.new(12345, _make_biome())
    assert_that(grid.sector_to_world_center(Vector2i.ZERO)).is_equal(Vector2i(192, 192))

func test_chebyshev_symmetric() -> void:
    var grid := _SectorGrid.new(12345, _make_biome())
    var a := Vector2i(2, -3)
    var b := Vector2i(-1, 5)
    assert_that(grid.chebyshev_distance(a, b)).is_equal(grid.chebyshev_distance(b, a))

func test_boss_ring_returns_boss_slot() -> void:
    var grid := _SectorGrid.new(12345, _make_biome())
    var slot := grid.resolve_sector(Vector2i(10, 0))
    assert_that(slot.is_boss).is_true()

func test_outside_boss_ring_is_empty() -> void:
    var grid := _SectorGrid.new(12345, _make_biome())
    var slot := grid.resolve_sector(Vector2i(11, 0))
    assert_that(slot.is_empty).is_true()

func test_inside_ring_not_boss() -> void:
    var grid := _SectorGrid.new(12345, _make_biome())
    var slot := grid.resolve_sector(Vector2i(5, 0))
    assert_that(slot.is_boss).is_false()

func test_resolve_sector_deterministic() -> void:
    var b := _make_biome()
    var g1 := _SectorGrid.new(99999, b)
    var g2 := _SectorGrid.new(99999, b)
    var coord := Vector2i(3, -2)
    var s1 := g1.resolve_sector(coord)
    var s2 := g2.resolve_sector(coord)
    assert_that(s1.template_index).is_equal(s2.template_index)
    assert_that(s1.rotation).is_equal(s2.rotation)
    assert_that(s1.is_empty).is_equal(s2.is_empty)

func test_resolve_sector_seed_changes() -> void:
    var b := _make_biome()
    var g1 := _SectorGrid.new(1, b)
    var g2 := _SectorGrid.new(2, b)
    var diff := 0
    for x in range(-5, 5):
        for y in range(-5, 5):
            var c := Vector2i(x, y)
            if g1.chebyshev_distance(c, Vector2i.ZERO) >= _SectorGrid.BOSS_RING_DISTANCE:
                continue
            var s1 := g1.resolve_sector(c)
            var s2 := g2.resolve_sector(c)
            if s1.template_index != s2.template_index or s1.is_empty != s2.is_empty:
                diff += 1
    assert_that(diff > 30).is_true()

func test_rotation_is_zero_for_non_rotatable() -> void:
    var grid := _SectorGrid.new(12345, _make_biome())
    var slot := grid.resolve_sector(Vector2i(10, 0))  # boss, rotatable=false
    assert_that(slot.rotation).is_equal(0)
```

- [ ] **Step 2: Run tests to verify failure**

Expected: missing class errors.

- [ ] **Step 3: Implement SectorGrid**

Create `src/core/sector_grid.gd`:

```gdscript
class_name SectorGrid

const SECTOR_SIZE_PX := 384
const BOSS_RING_DISTANCE := 10
const EMPTY_WEIGHT := 1.5  # weight added against sum of template weights

class RoomSlot:
    var is_empty: bool = false
    var is_boss: bool = false
    var template_index: int = -1
    var rotation: int = 0  # 0/90/180/270
    var template_size: int = 0

var _seed: int
var _biome: BiomeDef


func _init(world_seed: int, biome: BiomeDef) -> void:
    _seed = world_seed
    _biome = biome


func world_to_sector(world_pos: Vector2) -> Vector2i:
    return Vector2i(
        floori(world_pos.x / SECTOR_SIZE_PX),
        floori(world_pos.y / SECTOR_SIZE_PX)
    )


func sector_to_world_center(coord: Vector2i) -> Vector2i:
    return Vector2i(
        coord.x * SECTOR_SIZE_PX + SECTOR_SIZE_PX / 2,
        coord.y * SECTOR_SIZE_PX + SECTOR_SIZE_PX / 2
    )


func chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
    return max(abs(a.x - b.x), abs(a.y - b.y))


func resolve_sector(coord: Vector2i) -> RoomSlot:
    var slot := RoomSlot.new()
    var dist := chebyshev_distance(coord, Vector2i.ZERO)

    if dist > BOSS_RING_DISTANCE:
        slot.is_empty = true
        return slot

    var rng := RandomNumberGenerator.new()
    rng.seed = hash(_seed ^ (coord.x * 73856093) ^ (coord.y * 19349663))

    if dist == BOSS_RING_DISTANCE:
        if _biome.boss_templates.is_empty():
            slot.is_empty = true
            return slot
        slot.is_boss = true
        slot.template_index = rng.randi() % _biome.boss_templates.size()
        var boss_tmpl: RoomTemplate = _biome.boss_templates[slot.template_index]
        slot.rotation = (rng.randi() % 4) * 90 if boss_tmpl.rotatable else 0
        slot.template_size = boss_tmpl.size_class
        return slot

    # Regular pick: weighted choice with EMPTY weight
    if _biome.room_templates.is_empty():
        slot.is_empty = true
        return slot

    var total := EMPTY_WEIGHT
    for tmpl in _biome.room_templates:
        total += (tmpl as RoomTemplate).weight

    var roll := rng.randf() * total
    if roll < EMPTY_WEIGHT:
        slot.is_empty = true
        return slot

    var cumulative := EMPTY_WEIGHT
    for i in range(_biome.room_templates.size()):
        cumulative += (_biome.room_templates[i] as RoomTemplate).weight
        if roll < cumulative:
            slot.template_index = i
            var tmpl: RoomTemplate = _biome.room_templates[i]
            slot.rotation = (rng.randi() % 4) * 90 if tmpl.rotatable else 0
            slot.template_size = tmpl.size_class
            return slot

    slot.is_empty = true
    return slot


func get_template_for_slot(slot: RoomSlot) -> RoomTemplate:
    if slot.is_empty:
        return null
    if slot.is_boss:
        return _biome.boss_templates[slot.template_index]
    return _biome.room_templates[slot.template_index]
```

- [ ] **Step 4: Run tests and verify pass**

Run GdUnit4 tests for `tests/unit/test_sector_grid.gd`. Expected: all 11 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/sector_grid.gd tests/unit/test_sector_grid.gd
git commit -m "feat: add SectorGrid with deterministic template selection"
```

---

## Task 9: TemplatePack (with tests)

**Files:**
- Create: `src/core/template_pack.gd`
- Create: `tests/unit/test_template_pack.gd`

- [ ] **Step 1: Write failing tests**

Create `tests/unit/test_template_pack.gd`:

```gdscript
extends GdUnitTestSuite

const _TemplatePack = preload("res://src/core/template_pack.gd")
const _RoomTemplate = preload("res://src/core/room_template.gd")

func _make_template(path: String, size: int) -> _RoomTemplate:
    var rt := _RoomTemplate.new()
    rt.png_path = path
    rt.size_class = size
    return rt

func test_register_returns_index() -> void:
    var pack := _TemplatePack.new()
    var rt := _make_template("res://assets/rooms/caves/blob_a.png", 64)
    var idx := pack.register(rt)
    assert_that(idx).is_equal(0)

func test_register_two_same_size_class() -> void:
    var pack := _TemplatePack.new()
    var a := _make_template("res://assets/rooms/caves/blob_a.png", 64)
    var b := _make_template("res://assets/rooms/caves/blob_b.png", 64)
    assert_that(pack.register(a)).is_equal(0)
    assert_that(pack.register(b)).is_equal(1)

func test_register_different_size_classes_keep_independent_indices() -> void:
    var pack := _TemplatePack.new()
    var a := _make_template("res://assets/rooms/caves/blob_a.png", 64)
    var b := _make_template("res://assets/rooms/caves/secret_a.png", 32)
    assert_that(pack.register(a)).is_equal(0)
    assert_that(pack.register(b)).is_equal(0)

func test_get_image_returns_loaded_image() -> void:
    var pack := _TemplatePack.new()
    var a := _make_template("res://assets/rooms/caves/blob_a.png", 64)
    var idx := pack.register(a)
    pack.build_arrays()
    var img := pack.get_image(64, idx)
    assert_that(img).is_not_null()
    assert_that(img.get_width()).is_equal(64)

func test_marker_pixels_returns_g_channel_positions() -> void:
    # blob_a was generated with 3 enemy markers (G=1)
    var pack := _TemplatePack.new()
    pack.register(_make_template("res://assets/rooms/caves/blob_a.png", 64))
    pack.build_arrays()
    var markers := pack.collect_markers(64, 0)
    var enemy_count := 0
    for m in markers:
        if m["type"] == 1:
            enemy_count += 1
    assert_that(enemy_count).is_equal(3)
```

- [ ] **Step 2: Run tests to verify failure**

Expected: missing class.

- [ ] **Step 3: Implement TemplatePack**

Create `src/core/template_pack.gd`:

```gdscript
class_name TemplatePack
extends RefCounted

# Per size_class, a list of (template, image)
var _by_size: Dictionary = {}        # int → Array[Dictionary]{template, image}
var _arrays: Dictionary = {}         # int → Texture2DArray


func register(tmpl: RoomTemplate) -> int:
    if not _by_size.has(tmpl.size_class):
        _by_size[tmpl.size_class] = []
    var bucket: Array = _by_size[tmpl.size_class]
    var idx := bucket.size()
    bucket.append({"template": tmpl, "image": null})
    return idx


func build_arrays() -> void:
    for size_class in _by_size.keys():
        var bucket: Array = _by_size[size_class]
        var images: Array[Image] = []
        for entry in bucket:
            var tmpl: RoomTemplate = entry["template"]
            var img := Image.load_from_file(tmpl.png_path)
            if img == null:
                push_error("TemplatePack: failed to load %s" % tmpl.png_path)
                continue
            # Pad/resize to size_class if needed
            if img.get_width() != size_class or img.get_height() != size_class:
                var padded := Image.create(size_class, size_class, false, Image.FORMAT_RGBA8)
                padded.fill(Color(0, 0, 0, 0))
                var ox := (size_class - img.get_width()) / 2
                var oy := (size_class - img.get_height()) / 2
                padded.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i(ox, oy))
                img = padded
            entry["image"] = img
            images.append(img)
        if not images.is_empty():
            _arrays[size_class] = TextureArrayBuilder.build_from_images(images)


func get_array(size_class: int) -> Texture2DArray:
    return _arrays.get(size_class, null)


func get_image(size_class: int, index: int) -> Image:
    if not _by_size.has(size_class):
        return null
    var bucket: Array = _by_size[size_class]
    if index < 0 or index >= bucket.size():
        return null
    return bucket[index]["image"]


# Returns Array of {pos: Vector2i (local), type: int}
func collect_markers(size_class: int, index: int) -> Array:
    var result: Array = []
    var img := get_image(size_class, index)
    if img == null:
        return result
    for y in range(img.get_height()):
        for x in range(img.get_width()):
            var c := img.get_pixel(x, y)
            if int(c.a8) != 255:
                continue
            var marker := int(c.g8)
            if marker > 0:
                result.append({"pos": Vector2i(x, y), "type": marker})
    return result


func get_size_classes() -> Array:
    return _by_size.keys()


func template_count(size_class: int) -> int:
    if not _by_size.has(size_class):
        return 0
    return (_by_size[size_class] as Array).size()
```

- [ ] **Step 4: Run tests and verify pass**

Expected: all 5 tests PASS. (Tests depend on PNGs from Task 6 existing.)

- [ ] **Step 5: Commit**

```bash
git add src/core/template_pack.gd tests/unit/test_template_pack.gd
git commit -m "feat: add TemplatePack for PNG → Texture2DArray + marker readback"
```

---

## Task 10: Shader stage — biome_cave

**Files:**
- Create: `shaders/include/biome_cave_stage.glslinc`

This stage replaces the existing `simplex_cave_stage` with biome-driven parameters. The biome buffer is bound at `set=2, binding=0`.

- [ ] **Step 1: Implement the stage**

Create `shaders/include/biome_cave_stage.glslinc`:

```glsl
// Biome-driven cave noise stage. Replaces simplex_cave_stage.
// Reads cave parameters from BiomeBuffer at set=2, binding=0.

layout(set = 2, binding = 0, std430) readonly buffer BiomeBuffer {
    float cave_scale;
    float cave_threshold;
    float ridge_weight;
    float ridge_scale;
    int   octaves;
    int   background_material;
    int   secret_ring_thickness;
    int   _pad0;
    // pools[i]: x = material_id (as float), y = noise_scale, z = noise_threshold, w = seed_offset
    vec4 pools[4];
} biome;

void stage_biome_cave(Context ctx) {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= 256 || pos.y >= 256) return;

    vec2 world_pos = vec2(ctx.chunk_coord * 256) + vec2(pos);

    float cave_noise = simplex_fbm(world_pos * biome.cave_scale, ctx.world_seed, biome.octaves);
    float ridge_noise = simplex_ridge(world_pos * biome.ridge_scale, hash_combine(ctx.world_seed, 1000u), 4);
    float combined = cave_noise * (1.0 - biome.ridge_weight) + ridge_noise * biome.ridge_weight;

    if (combined > biome.cave_threshold) {
        // AIR
        imageStore(chunk_tex, pos, vec4(0.0));
    } else {
        // Background material
        float r = float(biome.background_material) / 255.0;
        imageStore(chunk_tex, pos, vec4(r, 0.0, 0.0, 0.0));
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add shaders/include/biome_cave_stage.glslinc
git commit -m "feat: add biome-driven cave stage shader"
```

---

## Task 11: Shader stage — biome_pools

**Files:**
- Create: `shaders/include/biome_pools_stage.glslinc`

- [ ] **Step 1: Implement the stage**

Create `shaders/include/biome_pools_stage.glslinc`:

```glsl
// Per-material pool noise. Overwrites solid pixels (non-AIR) with pool material
// where each pool's noise field exceeds its threshold.
//
// Reads BiomeBuffer (defined in biome_cave_stage.glslinc).

void stage_biome_pools(Context ctx) {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= 256 || pos.y >= 256) return;

    vec4 current = imageLoad(chunk_tex, pos);
    int mat_id = int(round(current.r * 255.0));
    if (mat_id == 0) return;  // skip AIR

    vec2 world_pos = vec2(ctx.chunk_coord * 256) + vec2(pos);

    for (int i = 0; i < 4; i++) {
        vec4 p = biome.pools[i];
        int pool_mat = int(round(p.x));
        if (pool_mat <= 0) continue;
        float scale = p.y;
        float thr = p.z;
        uint pseed = hash_combine(ctx.world_seed, uint(int(round(p.w))));
        float n = simplex_fbm(world_pos * scale, pseed, 2);
        if (n > thr) {
            imageStore(chunk_tex, pos, vec4(float(pool_mat) / 255.0, 0.0, 0.0, 0.0));
            return;  // first pool wins
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add shaders/include/biome_pools_stage.glslinc
git commit -m "feat: add biome material pool noise stage"
```

---

## Task 12: Shader stage — pixel_scene_stamp

**Files:**
- Create: `shaders/include/pixel_scene_stamp.glslinc`

- [ ] **Step 1: Implement the stage**

Create `shaders/include/pixel_scene_stamp.glslinc`:

```glsl
// Stamps PNG room templates into the chunk texture.
// Stamp buffer at set=1 binding=0; texture arrays at set=3 (one per size class).

layout(set = 1, binding = 0, std430) readonly buffer StampBuffer {
    int count;
    int _pad[3];
    // Each stamp packed as two vec4s:
    //  s0: world_center.xy, template_index (z), packed_meta (w)
    //  packed_meta encoding (as int, fits in float exactly up to 2^24):
    //    bits  0..7  = size_class (16/32/64/128 → use as-is)
    //    bits  8..15 = rotation_steps (0/1/2/3 = 0/90/180/270 deg)
    //    bits 16..23 = flags (bit0 = is_secret)
    vec4 stamps[128];
} stamp_buf;

layout(set = 3, binding = 0) uniform sampler2DArray template_array_16;
layout(set = 3, binding = 1) uniform sampler2DArray template_array_32;
layout(set = 3, binding = 2) uniform sampler2DArray template_array_64;
layout(set = 3, binding = 3) uniform sampler2DArray template_array_128;

vec4 sample_template(int size_class, int idx, vec2 uv) {
    if (size_class == 16)  return texture(template_array_16,  vec3(uv, float(idx)));
    if (size_class == 32)  return texture(template_array_32,  vec3(uv, float(idx)));
    if (size_class == 64)  return texture(template_array_64,  vec3(uv, float(idx)));
    return texture(template_array_128, vec3(uv, float(idx)));
}

vec2 rotate_local(vec2 local, int rot_steps, float size) {
    // rot_steps: 0=0°, 1=90°, 2=180°, 3=270° (CCW)
    if (rot_steps == 0) return local;
    if (rot_steps == 1) return vec2(local.y, size - 1.0 - local.x);
    if (rot_steps == 2) return vec2(size - 1.0 - local.x, size - 1.0 - local.y);
    return vec2(size - 1.0 - local.y, local.x);
}

void stage_pixel_scene_stamp(Context ctx) {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= 256 || pos.y >= 256) return;

    vec2 world_pos = vec2(ctx.chunk_coord * 256) + vec2(pos);

    for (int i = 0; i < stamp_buf.count; i++) {
        vec4 s = stamp_buf.stamps[i];
        vec2 center = s.xy;
        int idx = int(round(s.z));
        int meta = int(round(s.w));
        int size_class = meta & 0xFF;
        int rot_steps = (meta >> 8) & 0xFF;

        float half_size = float(size_class) * 0.5;
        vec2 delta = world_pos - center;
        if (abs(delta.x) >= half_size || abs(delta.y) >= half_size) continue;

        vec2 local = delta + vec2(half_size);  // [0, size)
        vec2 src = rotate_local(local, rot_steps, float(size_class));
        vec2 uv = (src + vec2(0.5)) / float(size_class);
        vec4 t = sample_template(size_class, idx, uv);

        if (t.a < 0.5) continue;  // skip mask

        int r = int(round(t.r * 255.0));
        int mat = (r == 255) ? biome.background_material : r;
        imageStore(chunk_tex, pos, vec4(float(mat) / 255.0, 0.0, 0.0, 0.0));
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add shaders/include/pixel_scene_stamp.glslinc
git commit -m "feat: add pixel_scene_stamp shader stage"
```

---

## Task 13: Shader stage — secret_ring

**Files:**
- Create: `shaders/include/secret_ring_stage.glslinc`

- [ ] **Step 1: Implement the stage**

Create `shaders/include/secret_ring_stage.glslinc`:

```glsl
// For each stamp flagged is_secret, draws an annular wall of biome.background_material
// at radius [size*0.45 .. size*0.45 + thickness] from stamp center. Runs after
// pixel_scene_stamp so it overwrites AIR at the ring band.

void stage_secret_ring(Context ctx) {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= 256 || pos.y >= 256) return;

    vec2 world_pos = vec2(ctx.chunk_coord * 256) + vec2(pos);

    for (int i = 0; i < stamp_buf.count; i++) {
        vec4 s = stamp_buf.stamps[i];
        int meta = int(round(s.w));
        int flags = (meta >> 16) & 0xFF;
        if ((flags & 1) == 0) continue;  // not secret

        int size_class = meta & 0xFF;
        float inner = float(size_class) * 0.45;
        float outer = inner + float(biome.secret_ring_thickness);

        vec2 delta = world_pos - s.xy;
        float d = length(delta);
        if (d >= inner && d < outer) {
            float r = float(biome.background_material) / 255.0;
            imageStore(chunk_tex, pos, vec4(r, 0.0, 0.0, 0.0));
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add shaders/include/secret_ring_stage.glslinc
git commit -m "feat: add secret_ring shader stage"
```

---

## Task 14: Update generation.glsl pipeline

**Files:**
- Modify: `shaders/compute/generation.glsl`

- [ ] **Step 1: Replace generation.glsl with new stage chain**

Replace the entire contents of `shaders/compute/generation.glsl` with:

```glsl
#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(push_constant) uniform PushConstants {
    ivec2 chunk_coord;
    uint world_seed;
    uint padding;
} push_ctx;

layout(rgba8, set = 0, binding = 0) uniform image2D chunk_tex;

#include "res://shaders/generated/materials.glslinc"
#include "res://shaders/include/simplex_2d.glslinc"
#include "res://shaders/include/wood_fill_stage.glslinc"
#include "res://shaders/include/simplex_cave_utils.glslinc"
#include "res://shaders/include/biome_cave_stage.glslinc"
#include "res://shaders/include/biome_pools_stage.glslinc"
#include "res://shaders/include/pixel_scene_stamp.glslinc"
#include "res://shaders/include/secret_ring_stage.glslinc"

void main() {
    Context ctx;
    ctx.chunk_coord = push_ctx.chunk_coord;
    ctx.world_seed = push_ctx.world_seed;

    stage_wood_fill(ctx);
    stage_biome_cave(ctx);
    stage_biome_pools(ctx);
    stage_pixel_scene_stamp(ctx);
    stage_secret_ring(ctx);
}
```

- [ ] **Step 2: Compile-check**

In Godot editor, reload the project. The shader will recompile on the next launch. If compilation fails, the error will appear in the Output panel — fix any GLSL issues before continuing.

- [ ] **Step 3: Commit**

```bash
git add shaders/compute/generation.glsl
git commit -m "feat: rewire generation.glsl with biome+stamp+secret stages"
```

---

## Task 15: ComputeDevice extensions (stamp + biome buffers, template arrays)

**Files:**
- Modify: `src/core/compute_device.gd`

- [ ] **Step 1: Add new fields**

In `src/core/compute_device.gd`, after `var material_textures: Texture2DArray`, add:

```gdscript
var gen_stamp_buffer: RID
var gen_stamp_uniform_set: RID
var gen_biome_buffer: RID
var gen_biome_uniform_set: RID
var gen_template_uniform_set: RID
var gen_template_array_rids: Dictionary = {}  # int size_class → RID

const STAMP_BUFFER_SIZE := 16 + 128 * 16   # 16-byte header + 128 vec4s
const BIOME_BUFFER_SIZE := 32 + 4 * 16     # 32-byte header + 4 pool vec4s
```

- [ ] **Step 2: Add init methods**

After `init_material_textures()`:

```gdscript
func init_gen_stamp_buffer() -> void:
    var zero := PackedByteArray()
    zero.resize(STAMP_BUFFER_SIZE)
    zero.fill(0)
    gen_stamp_buffer = rd.storage_buffer_create(STAMP_BUFFER_SIZE, zero)

    var u := RDUniform.new()
    u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    u.binding = 0
    u.add_id(gen_stamp_buffer)
    gen_stamp_uniform_set = rd.uniform_set_create([u], gen_shader, 1)


func init_gen_biome_buffer() -> void:
    var zero := PackedByteArray()
    zero.resize(BIOME_BUFFER_SIZE)
    zero.fill(0)
    gen_biome_buffer = rd.storage_buffer_create(BIOME_BUFFER_SIZE, zero)

    var u := RDUniform.new()
    u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    u.binding = 0
    u.add_id(gen_biome_buffer)
    gen_biome_uniform_set = rd.uniform_set_create([u], gen_shader, 2)


# template_arrays: Dictionary[int size_class → Texture2DArray]
func bind_template_arrays(template_arrays: Dictionary) -> void:
    # Free previous RIDs if any
    for rid in gen_template_array_rids.values():
        if rid.is_valid():
            rd.free_rid(rid)
    gen_template_array_rids.clear()

    var uniforms: Array[RDUniform] = []
    var binding_for_size := {16: 0, 32: 1, 64: 2, 128: 3}

    for size_class in [16, 32, 64, 128]:
        var u := RDUniform.new()
        u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
        u.binding = binding_for_size[size_class]
        var tex_rid := _texture_array_to_rid(template_arrays.get(size_class, null), size_class)
        gen_template_array_rids[size_class] = tex_rid
        # Need a sampler RID — use linear/nearest with no filter
        var sampler_state := RDSamplerState.new()
        sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
        sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
        sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
        sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
        var sampler := rd.sampler_create(sampler_state)
        u.add_id(sampler)
        u.add_id(tex_rid)
        uniforms.append(u)

    if gen_template_uniform_set.is_valid():
        rd.free_rid(gen_template_uniform_set)
    gen_template_uniform_set = rd.uniform_set_create(uniforms, gen_shader, 3)


func _texture_array_to_rid(tex_array: Texture2DArray, size_class: int) -> RID:
    if tex_array == null:
        # Create a minimal placeholder array (1 layer)
        var tf := RDTextureFormat.new()
        tf.width = size_class
        tf.height = size_class
        tf.array_layers = 1
        tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
        tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
        tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
        var blank := PackedByteArray()
        blank.resize(size_class * size_class * 4)
        blank.fill(0)
        return rd.texture_create(tf, RDTextureView.new(), [blank])

    var tf := RDTextureFormat.new()
    tf.width = size_class
    tf.height = size_class
    tf.array_layers = tex_array.get_layers()
    tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
    tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
    tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT

    var data: Array = []
    for i in range(tex_array.get_layers()):
        var img := tex_array.get_layer_data(i)
        data.append(img.get_data())
    return rd.texture_create(tf, RDTextureView.new(), data)


func upload_biome_buffer(biome: BiomeDef) -> void:
    var buf := PackedByteArray()
    buf.resize(BIOME_BUFFER_SIZE)
    buf.fill(0)
    buf.encode_float(0,  biome.cave_noise_scale)
    buf.encode_float(4,  biome.cave_threshold)
    buf.encode_float(8,  biome.ridge_weight)
    buf.encode_float(12, biome.ridge_scale)
    buf.encode_s32(16, biome.octaves)
    buf.encode_s32(20, biome.background_material)
    buf.encode_s32(24, biome.secret_ring_thickness)
    buf.encode_s32(28, 0)  # _pad
    var pool_count: int = min(biome.pool_materials.size(), 4)
    for i in range(pool_count):
        var p: PoolDef = biome.pool_materials[i]
        var off := 32 + i * 16
        buf.encode_float(off + 0,  float(p.material_id))
        buf.encode_float(off + 4,  p.noise_scale)
        buf.encode_float(off + 8,  p.noise_threshold)
        buf.encode_float(off + 12, float(p.seed_offset))
    rd.buffer_update(gen_biome_buffer, 0, BIOME_BUFFER_SIZE, buf)
```

- [ ] **Step 3: Update dispatch_generation signature and body**

Replace the existing `dispatch_generation` method:

```gdscript
func dispatch_generation(
    chunks: Dictionary,
    new_coords: Array[Vector2i],
    seed_val: int,
    stamp_bytes: PackedByteArray = PackedByteArray()
) -> Array[RID]:
    var created_uniform_sets: Array[RID] = []
    if new_coords.is_empty():
        return created_uniform_sets

    # Upload stamp buffer (or zero header if none)
    var upload := stamp_bytes
    if upload.size() < STAMP_BUFFER_SIZE:
        upload = stamp_bytes.duplicate()
        upload.resize(STAMP_BUFFER_SIZE)
    rd.buffer_update(gen_stamp_buffer, 0, STAMP_BUFFER_SIZE, upload)

    var compute_list := rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(compute_list, gen_pipeline)
    rd.compute_list_bind_uniform_set(compute_list, gen_stamp_uniform_set, 1)
    rd.compute_list_bind_uniform_set(compute_list, gen_biome_uniform_set, 2)
    if gen_template_uniform_set.is_valid():
        rd.compute_list_bind_uniform_set(compute_list, gen_template_uniform_set, 3)

    for coord in new_coords:
        var chunk: Chunk = chunks[coord]
        var gen_uniform := RDUniform.new()
        gen_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
        gen_uniform.binding = 0
        gen_uniform.add_id(chunk.rd_texture)
        var uniform_set := rd.uniform_set_create([gen_uniform], gen_shader, 0)
        created_uniform_sets.append(uniform_set)
        rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)

        var push_data := PackedByteArray()
        push_data.resize(16)
        push_data.encode_s32(0, coord.x)
        push_data.encode_s32(4, coord.y)
        push_data.encode_u32(8, seed_val)
        push_data.encode_u32(12, 0)
        rd.compute_list_set_push_constant(compute_list, push_data, push_data.size())

        rd.compute_list_dispatch(compute_list, NUM_WORKGROUPS, NUM_WORKGROUPS, 1)
    rd.compute_list_end()

    return created_uniform_sets
```

- [ ] **Step 4: Update free_resources**

In `free_resources()`, before existing pipeline frees, add:

```gdscript
    if gen_stamp_buffer.is_valid():
        rd.free_rid(gen_stamp_buffer)
    if gen_biome_buffer.is_valid():
        rd.free_rid(gen_biome_buffer)
    if gen_stamp_uniform_set.is_valid():
        rd.free_rid(gen_stamp_uniform_set)
    if gen_biome_uniform_set.is_valid():
        rd.free_rid(gen_biome_uniform_set)
    if gen_template_uniform_set.is_valid():
        rd.free_rid(gen_template_uniform_set)
    for rid in gen_template_array_rids.values():
        if rid.is_valid():
            rd.free_rid(rid)
    gen_template_array_rids.clear()
```

- [ ] **Step 5: Commit**

```bash
git add src/core/compute_device.gd
git commit -m "feat: add stamp/biome buffers and template arrays to ComputeDevice"
```

---

## Task 16: BiomeRegistry autoload

**Files:**
- Create: `src/autoload/biome_registry.gd`
- Modify: `project.godot`

- [ ] **Step 1: Implement BiomeRegistry**

Create `src/autoload/biome_registry.gd`:

```gdscript
extends Node

const BIOME_PATHS := [
    "res://assets/biomes/caves.tres",
    "res://assets/biomes/mines.tres",
    "res://assets/biomes/magma.tres",
    "res://assets/biomes/frozen.tres",
    "res://assets/biomes/vault.tres",
]

var biomes: Array[BiomeDef] = []
var template_pack: TemplatePack
var _template_index_for_template: Dictionary = {}  # RoomTemplate → int index in size class


func _ready() -> void:
    template_pack = TemplatePack.new()
    for path in BIOME_PATHS:
        var b: BiomeDef = load(path)
        if b == null:
            push_error("BiomeRegistry: failed to load %s" % path)
            continue
        biomes.append(b)
        for tmpl in b.room_templates:
            _register(tmpl as RoomTemplate)
        for tmpl in b.boss_templates:
            _register(tmpl as RoomTemplate)
    template_pack.build_arrays()


func _register(tmpl: RoomTemplate) -> void:
    if _template_index_for_template.has(tmpl):
        return
    var idx := template_pack.register(tmpl)
    _template_index_for_template[tmpl] = idx


func get_biome(floor_number: int) -> BiomeDef:
    if biomes.is_empty():
        push_error("BiomeRegistry: no biomes loaded")
        return null
    var i: int = (floor_number - 1) % biomes.size()
    return biomes[i]


func get_template_index(tmpl: RoomTemplate) -> int:
    return _template_index_for_template.get(tmpl, -1)


func get_template_arrays() -> Dictionary:
    var d: Dictionary = {}
    for sc in template_pack.get_size_classes():
        d[sc] = template_pack.get_array(sc)
    return d
```

- [ ] **Step 2: Register autoload**

Edit `project.godot`. In the `[autoload]` section, after `MaterialRegistry`, add:

```ini
BiomeRegistry="*res://src/autoload/biome_registry.gd"
```

- [ ] **Step 3: Verify launch**

Open the project in Godot. Verify no autoload errors. The 5 biomes should load and 22 templates should pack into arrays. Add a temporary `print("loaded %d biomes" % biomes.size())` at end of `_ready()` if you want confirmation; remove after verifying.

- [ ] **Step 4: Commit**

```bash
git add src/autoload/biome_registry.gd project.godot
git commit -m "feat: add BiomeRegistry autoload that loads biomes and packs templates"
```

---

## Task 17: LevelManager autoload

**Files:**
- Create: `src/autoload/level_manager.gd`
- Modify: `project.godot`

- [ ] **Step 1: Implement LevelManager**

Create `src/autoload/level_manager.gd`:

```gdscript
extends Node

signal floor_changed(floor_number: int)
signal boss_arena_entered(world_center: Vector2i)

const STAMP_BUFFER_SIZE := 16 + 128 * 16

var floor_number: int = 1
var world_seed: int = 0
var current_biome: BiomeDef
var _grid: SectorGrid
var _spawn_dispatcher: Node  # SpawnDispatcher; assigned in _ready


func _ready() -> void:
    world_seed = randi()
    current_biome = BiomeRegistry.get_biome(floor_number)
    _grid = SectorGrid.new(world_seed, current_biome)
    var SpawnDispatcher = load("res://src/core/spawn_dispatcher.gd")
    _spawn_dispatcher = SpawnDispatcher.new()
    _spawn_dispatcher.name = "SpawnDispatcher"
    add_child(_spawn_dispatcher)


func get_grid() -> SectorGrid:
    return _grid


func get_biome() -> BiomeDef:
    return current_biome


func advance_floor() -> void:
    floor_number += 1
    world_seed = randi()
    current_biome = BiomeRegistry.get_biome(floor_number)
    _grid = SectorGrid.new(world_seed, current_biome)
    if _spawn_dispatcher and _spawn_dispatcher.has_method("clear"):
        _spawn_dispatcher.clear()
    var wm := get_tree().get_first_node_in_group("world_manager")
    if wm and wm.has_method("reset"):
        wm.reset()
    floor_changed.emit(floor_number)


func build_stamp_bytes(chunk_coords: Array[Vector2i]) -> PackedByteArray:
    var seen_sectors: Dictionary = {}
    var stamps: Array = []  # Array[Dictionary]

    for chunk_coord in chunk_coords:
        var chunk_world_min := chunk_coord * 256
        var chunk_world_max := chunk_world_min + Vector2i(255, 255)
        for corner in [
            chunk_world_min,
            chunk_world_max,
            Vector2i(chunk_world_max.x, chunk_world_min.y),
            Vector2i(chunk_world_min.x, chunk_world_max.y),
        ]:
            var sector := _grid.world_to_sector(Vector2(corner))
            if seen_sectors.has(sector):
                continue
            seen_sectors[sector] = true

            var slot := _grid.resolve_sector(sector)
            if slot.is_empty:
                continue

            var tmpl := _grid.get_template_for_slot(slot)
            if tmpl == null:
                continue

            var center := _grid.sector_to_world_center(sector)
            var idx := BiomeRegistry.get_template_index(tmpl)
            if idx < 0:
                continue

            var rot_steps := slot.rotation / 90
            var flags := 0
            if tmpl.is_secret:
                flags |= 1
            var meta := (slot.template_size & 0xFF) | ((rot_steps & 0xFF) << 8) | ((flags & 0xFF) << 16)

            stamps.append({
                "cx": float(center.x),
                "cy": float(center.y),
                "idx": float(idx),
                "meta": float(meta),
            })
            if stamps.size() >= 128:
                break
        if stamps.size() >= 128:
            break

    return _encode_stamps(stamps)


func _encode_stamps(stamps: Array) -> PackedByteArray:
    var buf := PackedByteArray()
    buf.resize(STAMP_BUFFER_SIZE)
    buf.fill(0)
    buf.encode_s32(0, stamps.size())
    for i in range(stamps.size()):
        var s: Dictionary = stamps[i]
        var off := 16 + i * 16
        buf.encode_float(off + 0,  s["cx"])
        buf.encode_float(off + 4,  s["cy"])
        buf.encode_float(off + 8,  s["idx"])
        buf.encode_float(off + 12, s["meta"])
    return buf
```

- [ ] **Step 2: Register autoload**

Edit `project.godot`. In `[autoload]`, after `BiomeRegistry`:

```ini
LevelManager="*res://src/autoload/level_manager.gd"
```

- [ ] **Step 3: Commit (will fail to load until SpawnDispatcher exists in next tasks; that's fine, we wire it up next)**

```bash
git add src/autoload/level_manager.gd project.godot
git commit -m "feat: add LevelManager autoload with stamp builder and floor advance"
```

If the editor errors on the SpawnDispatcher load failure, note it and proceed — Task 19 fixes it.

---

## Task 18: WorldManager integration (signal, biome upload, reset)

**Files:**
- Modify: `src/core/world_manager.gd`

- [ ] **Step 1: Add group registration and chunks_generated signal**

In `src/core/world_manager.gd`, at the top of `_ready()`, add:

```gdscript
    add_to_group("world_manager")
```

After `var _gen_uniform_sets_to_free: Array[RID] = []`, add:

```gdscript
signal chunks_generated(new_coords: Array[Vector2i])
```

- [ ] **Step 2: Initialize stamp + biome buffers**

In `_ready()`, after `compute_device.init_material_textures()`, add:

```gdscript
    compute_device.init_gen_stamp_buffer()
    compute_device.init_gen_biome_buffer()
    # Bind biome buffer + template arrays from current biome
    compute_device.upload_biome_buffer(LevelManager.current_biome)
    compute_device.bind_template_arrays(BiomeRegistry.get_template_arrays())
```

- [ ] **Step 3: Pass stamps + seed to dispatch**

In `_update_chunks()`, replace:

```gdscript
    if not new_chunks.is_empty():
        _gen_uniform_sets_to_free = compute_device.dispatch_generation(chunks, new_chunks, 0)
```

with:

```gdscript
    if not new_chunks.is_empty():
        var stamp_bytes := LevelManager.build_stamp_bytes(new_chunks)
        _gen_uniform_sets_to_free = compute_device.dispatch_generation(
            chunks, new_chunks, LevelManager.world_seed, stamp_bytes
        )
        chunks_generated.emit(new_chunks)
```

- [ ] **Step 4: Add reset() method**

At the bottom of `world_manager.gd`:

```gdscript
func reset() -> void:
    chunk_manager.clear_all_chunks()
    # Despawn all entities under chunk_container
    for child in chunk_container.get_children():
        if child is Chunk:
            continue  # chunk_manager handles these
        child.queue_free()
    tracking_position = Vector2.ZERO
    # Re-bind biome data for the new floor
    compute_device.upload_biome_buffer(LevelManager.current_biome)
    compute_device.bind_template_arrays(BiomeRegistry.get_template_arrays())
```

- [ ] **Step 5: Commit**

```bash
git add src/core/world_manager.gd
git commit -m "feat: wire LevelManager + BiomeRegistry into WorldManager dispatch"
```

---

## Task 19: SpawnDispatcher

**Files:**
- Create: `src/core/spawn_dispatcher.gd`

- [ ] **Step 1: Implement SpawnDispatcher**

Create `src/core/spawn_dispatcher.gd`:

```gdscript
extends Node

const ENEMY_SCENE := preload("res://scenes/dummy_enemy.tscn")
const CHEST_SCENE := preload("res://scenes/chest.tscn")
const SHOP_SCENE  := preload("res://scenes/economy/shop_ui.tscn")
const PORTAL_SCENE := preload("res://scenes/portal.tscn")

const CHUNK_SIZE := 256

var _spawned_sectors: Dictionary = {}  # Vector2i → true
var _world_manager: Node = null
var _spawn_parent: Node = null


func _ready() -> void:
    call_deferred("_late_connect")


func _late_connect() -> void:
    _world_manager = get_tree().get_first_node_in_group("world_manager")
    if _world_manager == null:
        push_error("SpawnDispatcher: world_manager not found")
        return
    _spawn_parent = _world_manager.get_chunk_container()
    _world_manager.chunks_generated.connect(_on_chunks_generated)


func clear() -> void:
    _spawned_sectors.clear()


func _on_chunks_generated(new_coords: Array[Vector2i]) -> void:
    var grid: SectorGrid = LevelManager.get_grid()
    if grid == null:
        return

    for chunk_coord in new_coords:
        var chunk_world_min := chunk_coord * CHUNK_SIZE
        var chunk_world_max := chunk_world_min + Vector2i(CHUNK_SIZE - 1, CHUNK_SIZE - 1)
        var sectors_seen: Dictionary = {}

        for corner in [
            chunk_world_min,
            chunk_world_max,
            Vector2i(chunk_world_max.x, chunk_world_min.y),
            Vector2i(chunk_world_min.x, chunk_world_max.y),
        ]:
            var sector := grid.world_to_sector(Vector2(corner))
            if sectors_seen.has(sector):
                continue
            sectors_seen[sector] = true

            var sector_center := grid.sector_to_world_center(sector)
            # Only spawn if sector center is inside this chunk (avoids cross-chunk dupes)
            if sector_center.x < chunk_world_min.x or sector_center.x > chunk_world_max.x:
                continue
            if sector_center.y < chunk_world_min.y or sector_center.y > chunk_world_max.y:
                continue
            if _spawned_sectors.has(sector):
                continue

            var slot := grid.resolve_sector(sector)
            if slot.is_empty:
                _spawned_sectors[sector] = true
                continue

            _spawned_sectors[sector] = true
            _spawn_for_slot(grid, slot, sector, sector_center)


func _spawn_for_slot(grid: SectorGrid, slot, sector: Vector2i, world_center: Vector2i) -> void:
    var tmpl: RoomTemplate = grid.get_template_for_slot(slot)
    if tmpl == null:
        return
    var idx := BiomeRegistry.get_template_index(tmpl)
    if idx < 0:
        return
    var markers: Array = BiomeRegistry.template_pack.collect_markers(slot.template_size, idx)
    var size_f: int = slot.template_size
    var floor_num: int = LevelManager.floor_number
    var dist: int = grid.chebyshev_distance(sector, Vector2i.ZERO)

    for m in markers:
        var local_pos: Vector2i = m["pos"]
        var marker_type: int = m["type"]
        var rotated := _apply_rotation(local_pos, slot.rotation, size_f)
        var world_pos := Vector2(
            world_center.x - size_f / 2 + rotated.x,
            world_center.y - size_f / 2 + rotated.y,
        )
        _spawn_entity(marker_type, world_pos, dist, floor_num, slot.is_boss)


static func _apply_rotation(local: Vector2i, rotation_deg: int, size: int) -> Vector2i:
    var steps: int = rotation_deg / 90
    match steps:
        0: return local
        1: return Vector2i(local.y, size - 1 - local.x)
        2: return Vector2i(size - 1 - local.x, size - 1 - local.y)
        3: return Vector2i(size - 1 - local.y, local.x)
    return local


func _spawn_entity(marker: int, world_pos: Vector2, sector_dist: int, floor_num: int, is_boss_room: bool) -> void:
    match marker:
        1: _spawn_enemy(world_pos, sector_dist, floor_num, false, false)
        2: _spawn_enemy(world_pos, sector_dist, floor_num, false, true)  # elite
        3: _spawn_chest(world_pos, false)
        4: _spawn_shop(world_pos)
        5: _spawn_chest(world_pos, true)  # secret loot
        6: _spawn_enemy(world_pos, sector_dist, floor_num, true, false)  # boss
        7: pass  # PORTAL_ANCHOR — handled at boss death (see _on_boss_died)


func _spawn_enemy(world_pos: Vector2, sector_dist: int, floor_num: int, is_boss: bool, is_elite: bool) -> void:
    var enemy := ENEMY_SCENE.instantiate()

    var tier_index: int = clampi(int(floor(float(sector_dist) / float(SectorGrid.BOSS_RING_DISTANCE) * 2.0)), 0, 2)
    if "enemy_tier" in enemy:
        enemy.enemy_tier = tier_index

    var health_mult := 1.0 + (floor_num - 1) * 0.25
    var damage_mult := 1.0 + (floor_num - 1) * 0.15
    var speed_mult  := 1.0 + (floor_num - 1) * 0.10

    if "max_health" in enemy:
        enemy.max_health = int(float(enemy.max_health) * health_mult * (2.0 if is_elite else 1.0) * (5.0 if is_boss else 1.0))
    if "speed" in enemy:
        enemy.speed = enemy.speed * speed_mult * (1.5 if is_boss else 1.0)
    if "damage" in enemy:
        enemy.damage = int(float(enemy.damage) * damage_mult)

    if is_boss:
        enemy.modulate = LevelManager.current_biome.tint
        if enemy.has_signal("died"):
            enemy.died.connect(_on_boss_died.bind(world_pos))

    enemy.global_position = world_pos
    _spawn_parent.add_child(enemy)


func _spawn_chest(world_pos: Vector2, is_secret_loot: bool) -> void:
    var chest := CHEST_SCENE.instantiate()
    chest.global_position = world_pos
    if is_secret_loot and "rare_drop" in chest:
        chest.rare_drop = true
    _spawn_parent.add_child(chest)


func _spawn_shop(world_pos: Vector2) -> void:
    var shop := SHOP_SCENE.instantiate()
    # Shops are CanvasLayer-based; attach to scene root rather than chunk_container
    _spawn_parent.get_parent().add_child(shop)


func _on_boss_died(arena_center: Vector2) -> void:
    var portal := PORTAL_SCENE.instantiate()
    portal.global_position = arena_center
    _spawn_parent.add_child(portal)
```

- [ ] **Step 2: Verify load — LevelManager autoload now resolves**

Open Godot editor. The earlier load-failure for `SpawnDispatcher` should clear since the file now exists.

- [ ] **Step 3: Commit**

```bash
git add src/core/spawn_dispatcher.gd
git commit -m "feat: add SpawnDispatcher for marker-based entity placement"
```

---

## Task 20: Portal scene + script

**Files:**
- Create: `src/portal.gd`
- Create: `scenes/portal.tscn`

- [ ] **Step 1: Implement Portal script**

Create `src/portal.gd`:

```gdscript
class_name Portal
extends Area2D

const PROMPT_TEXT := "Press [E] to enter portal"

var _player_inside: bool = false
@onready var _prompt_label: Label = $PromptLabel


func _ready() -> void:
    body_entered.connect(_on_body_entered)
    body_exited.connect(_on_body_exited)
    if _prompt_label:
        _prompt_label.text = PROMPT_TEXT
        _prompt_label.visible = false


func _process(_delta: float) -> void:
    if _player_inside and Input.is_action_just_pressed("interact"):
        LevelManager.advance_floor()
        queue_free()


func _on_body_entered(body: Node2D) -> void:
    if body.is_in_group("player"):
        _player_inside = true
        if _prompt_label:
            _prompt_label.visible = true


func _on_body_exited(body: Node2D) -> void:
    if body.is_in_group("player"):
        _player_inside = false
        if _prompt_label:
            _prompt_label.visible = false
```

- [ ] **Step 2: Create the Portal scene in editor**

In Godot editor:
1. New Scene → root node `Area2D`, named `Portal`
2. Attach script `res://src/portal.gd`
3. Add child `CollisionShape2D` with `CircleShape2D`, radius 16
4. Add child `ColorRect`, size (32, 32), position (-16, -16), color `Color(0.4, 0.0, 0.8, 0.85)` (purple placeholder)
5. Add child `Label`, name `PromptLabel`, position (-60, -32), size (120, 16), text empty (script sets it)
6. Save as `res://scenes/portal.tscn`

- [ ] **Step 3: Commit**

```bash
git add src/portal.gd scenes/portal.tscn
git commit -m "feat: add Portal interactable scene and script"
```

---

## Task 21: End-to-end smoke test

This task has no code — it's manual verification that the system works end-to-end.

- [ ] **Step 1: Launch the game**

Run the game from Godot editor. The world should generate. Move the player around.

**Expected:** Caves biome (floor 1). You should see:
- Stone walls with dirt pool clusters
- Discrete room shapes (blobs, corridors, secret circles)
- Enemies clustered inside rooms
- A purple portal does NOT yet appear (no boss yet — boss is at chebyshev distance 10)

- [ ] **Step 2: Check shop spawning**

Walk through the world. Shops spawn rarely in caves (only in vault biome by default). For caves, you should encounter chests and enemy clusters primarily.

- [ ] **Step 3: Check secret rooms**

Look for thin circular walls. Swing through to find a chest inside.

- [ ] **Step 4: Cheat to boss arena**

Open the cheat console (existing system). Use the existing teleport command to jump to coordinates `(3840, 0)` (10 sectors × 384px). Verify a boss arena is visible — large open area with a single boss enemy with biome tint.

If no cheat console exists for teleport, manually walk in one direction for ~3840px.

- [ ] **Step 5: Defeat boss → portal spawns**

Kill the boss. Verify a portal spawns at the boss's position.

- [ ] **Step 6: Enter portal → next floor**

Press E on the portal. Verify:
- World resets (chunks unload, entities despawn)
- Player respawns at world origin
- Terrain regenerates with the Mines biome (different palette — coal pools instead of dirt)
- `floor_changed` signal fires (no HUD this phase, but future hooks work)

- [ ] **Step 7: Walk through floors 2-5**

Repeat boss + portal flow for each floor. Verify each biome looks distinct:
- Mines: coal seams in stone, wood planks scattered
- Magma: lava pools, gas pockets, sparser caves
- Frozen: ice walls (instead of stone), water pockets
- Vault: dense wood, stone accents, more rooms

- [ ] **Step 8: Floor 6 = Caves loops**

After Vault, advance once more. Should loop back to Caves with no errors.

- [ ] **Step 9: Run all unit tests**

In Godot editor, run GdUnit4 tests. Expected:
- `tests/unit/test_sector_grid.gd` — 11 PASS
- `tests/unit/test_template_pack.gd` — 5 PASS
- `tests/unit/test_biome_def.gd` — 3 PASS

- [ ] **Step 10: Final commit**

```bash
git add .
git commit -m "feat: Phase 5 level system end-to-end (Noita-style biomes + templates)"
```

---

## Self-Review Checklist

**Spec coverage:**
- [x] Cave generation algorithm — biome_cave_stage (Task 10)
- [x] Room placement (shops, secrets, boss arenas) — SectorGrid + SpawnDispatcher + templates (Tasks 8, 19)
- [x] Enemy population — SpawnDispatcher marker readback (Task 19)
- [x] Secret areas with thin walls — secret_ring_stage + secret_vault generator (Tasks 5, 13)
- [x] Portal system — Portal scene + advance_floor (Tasks 20, 17)
- [x] Difficulty scaling — tier gating + per-floor stat multipliers (Task 19)
- [x] Floor tracking — `floor_number` + `floor_changed` signal (Task 17)
- [x] Material pools — biome_pools_stage (Task 11)
- [x] PNG-based room templates — generators + TemplatePack (Tasks 3-7, 9)
- [x] Per-floor biome stratification — BiomeRegistry + advance_floor swap (Tasks 16, 17)
- [x] Floor counter HUD — **out of scope per design discussion** (no task)

**No placeholders:** Every step contains complete code or specific commands.

**Type consistency:**
- `BiomeDef.pool_materials: Array[PoolDef]` consistent across registry, shader upload, and resources
- `RoomTemplate` properties (png_path, weight, size_class, is_secret, is_boss, rotatable) consistent across generators, BiomeDef, SectorGrid, SpawnDispatcher
- `SectorGrid.RoomSlot` (template_index, rotation, template_size, is_empty, is_boss) consistent between resolve_sector callers
- Stamp encoding (cx, cy, idx, packed_meta) consistent between `LevelManager._encode_stamps`, `compute_device.dispatch_generation`, and `pixel_scene_stamp.glslinc`
- Marker types (1=enemy, 2=elite, 3=chest, 4=shop, 5=secret_loot, 6=boss, 7=portal_anchor) consistent across generators and SpawnDispatcher
- Material IDs (DIRT=5, COAL=6, ICE=7, WATER=8) consistent between MaterialRegistry init order and generator script constants
