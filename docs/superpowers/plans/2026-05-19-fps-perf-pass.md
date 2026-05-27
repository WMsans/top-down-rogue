# FPS Performance Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reach sustained 60 FPS in the editor with the current 588-enemy stress scene by eliminating GPU sync stalls and gating per-enemy terrain queries on a coarse hazard map.

**Architecture:** Three coordinated changes — (1) per-sub-cell hazard bitmask piggy-backed onto the existing 4×4 light extraction pipeline, (2) double-buffered terrain probe SSBOs with a bounded FIFO of pending queries and interned `TerrainCell` instances, (3) melee split where enemy hits use `PhysicsServer2D.intersect_shape` and terrain modification is a fire-and-forget compute dispatch with a 3-frame-lagged ring-buffer hit list for impact FX.

**Tech Stack:** Godot 4 (GDScript), RenderingDevice compute, GLSL 450, GdUnit4 tests.

**Spec:** `docs/superpowers/specs/2026-05-19-fps-perf-pass-design.md`

---

## File Structure

**Created:**
- `shaders/compute/melee_arc.glsl` — fire-and-forget terrain modification shader for melee swings.
- `tests/unit/test_material_hazard_bits.gd` — hazard bit mapping.
- `tests/unit/test_terrain_cell_intern.gd` — interned `TerrainCell` identity.
- `tests/unit/test_terrain_physical_hazard.gd` — `hazard_at` lookup.
- `tests/unit/test_terrain_physical_pending_cap.gd` — bounded FIFO behavior.
- `tests/unit/test_light_decode_hazard.gd` — decoder reads hazard field.
- `tests/unit/test_melee_arc_angle_filter.gd` — extracted arc-angle helper.

**Modified:**
- `src/autoload/material_registry.gd` — hazard bit mapping, `TerrainCell` interning.
- `tools/generate_material_glsl.gd` — emit `HAZARD_BIT[]` array into the glslinc.
- `shaders/generated/materials.glslinc` — regenerated, includes hazard bit table.
- `shaders/compute/light_pack.glsl` — add per-cell hazard reduction.
- `src/core/compute_device.gd` — extend light SSBO layout, double-buffer terrain probe SSBOs, melee arc pipeline, hit list ring.
- `src/core/chunk.gd` — new `hazard_cells: PackedInt32Array`.
- `src/core/terrain_physical.gd` — `hazard_at`, bounded FIFO, deferred apply via stored batch, use interned cells.
- `src/core/world_manager.gd` — read hazard from decoded light data, double-buffer probe orchestration, impact FX drainer.
- `src/core/terrain_modifier.gd` — `clear_and_push_materials_in_arc` becomes a dispatch (no return value).
- `src/enemies/terrain_damage_receiver.gd` — hazard gate before query.
- `src/player/lava_damage_checker.gd` — hazard gate before query.
- `src/weapons/melee_weapon.gd` — drop the impact return value, switch enemy hit detection to `intersect_shape`.
- `project.godot` — register `attackable_hit` physics layer.
- Enemy and player scene files — add `attackable_hit` layer bit to their CollisionShape2D.

---

## Task 1: Hazard bit mapping in MaterialRegistry

**Files:**
- Modify: `src/autoload/material_registry.gd`
- Test: `tests/unit/test_material_hazard_bits.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_material_hazard_bits.gd`:

```gdscript
extends GdUnitTestSuite

func test_hazard_bits() -> void:
	var registry := MaterialRegistry.new()
	registry._init_materials()
	assert_that(registry.get_hazard_bit(registry.MAT_LAVA)).is_equal(0)
	assert_that(registry.get_hazard_bit(registry.MAT_EXPLODE_WAVE)).is_equal(1)
	assert_that(registry.get_hazard_bit(registry.MAT_OIL)).is_equal(2)
	assert_that(registry.get_hazard_bit(registry.MAT_BLOOD)).is_equal(3)

func test_non_hazard_returns_minus_one() -> void:
	var registry := MaterialRegistry.new()
	registry._init_materials()
	assert_that(registry.get_hazard_bit(registry.MAT_AIR)).is_equal(-1)
	assert_that(registry.get_hazard_bit(registry.MAT_DIRT)).is_equal(-1)
	assert_that(registry.get_hazard_bit(registry.MAT_STONE)).is_equal(-1)
	assert_that(registry.get_hazard_bit(-1)).is_equal(-1)
	assert_that(registry.get_hazard_bit(999)).is_equal(-1)

func test_hazard_mask_constants() -> void:
	assert_that(MaterialRegistry.HAZARD_LAVA).is_equal(1)
	assert_that(MaterialRegistry.HAZARD_FIRE).is_equal(2)
	assert_that(MaterialRegistry.HAZARD_OIL).is_equal(4)
	assert_that(MaterialRegistry.HAZARD_BLOOD).is_equal(8)
```

- [ ] **Step 2: Run test to verify it fails**

```
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_material_hazard_bits.gd
```
Expected: FAIL — `get_hazard_bit` does not exist; `HAZARD_LAVA` does not exist.

- [ ] **Step 3: Implement hazard bit mapping**

In `src/autoload/material_registry.gd`, add near the top of the class (after the existing `MAT_*` declarations):

```gdscript
const HAZARD_LAVA := 1
const HAZARD_FIRE := 2  # MAT_EXPLODE_WAVE acts as the fire/heat hazard
const HAZARD_OIL := 4
const HAZARD_BLOOD := 8
```

Add the method (anywhere after `_init_materials`):

```gdscript
func get_hazard_bit(material_id: int) -> int:
	if material_id == MAT_LAVA:
		return 0
	if material_id == MAT_EXPLODE_WAVE:
		return 1
	if material_id == MAT_OIL:
		return 2
	if material_id == MAT_BLOOD:
		return 3
	return -1
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/autoload/material_registry.gd tests/unit/test_material_hazard_bits.gd
git commit -m "feat(material): add hazard bit mapping for sub-cell gating"
```

---

## Task 2: Emit HAZARD_BIT array into generated GLSL

**Files:**
- Modify: `tools/generate_material_glsl.gd`
- Modify (regenerated): `shaders/generated/materials.glslinc`

- [ ] **Step 1: Inspect current generator**

```
godot --headless --path . -s tools/generate_material_glsl.gd
```
Note current output keys: `MAT_*` constants, `IS_FLUID[]`, `MATERIAL_GLOW[]`. We need to add `HAZARD_BIT[]` (int per material id, −1 if non-hazardous).

- [ ] **Step 2: Modify the generator**

In `tools/generate_material_glsl.gd`, locate the block that writes `IS_FLUID`. After it, write a parallel `HAZARD_BIT` table. The exact form depends on the existing generator code; add a function such as:

```gdscript
func _write_hazard_bits(file: FileAccess, registry) -> void:
	file.store_line("const int HAZARD_BIT[%d] = int[%d](" % [registry.materials.size(), registry.materials.size()])
	for i in range(registry.materials.size()):
		var bit := registry.get_hazard_bit(i)
		var sep := "," if i < registry.materials.size() - 1 else ""
		file.store_line("    %d%s" % [bit, sep])
	file.store_line(");")
	file.store_line("")
```

Call it after the `IS_FLUID` writer.

- [ ] **Step 3: Regenerate the glslinc**

```
godot --headless --path . -s tools/generate_material_glsl.gd
```

Verify `shaders/generated/materials.glslinc` now contains:

```
const int HAZARD_BIT[12] = int[12](
    -1,  // AIR
    -1,  // WOOD
    -1,  // STONE
    -1,  // GAS
    0,   // LAVA
    -1,  // DIRT
    -1,  // COAL
    -1,  // ICE
    -1,  // WATER
    3,   // BLOOD
    2,   // OIL
    1    // EXPLODE_WAVE
);
```

(Comments optional — generator may or may not emit them.)

- [ ] **Step 4: Commit**

```bash
git add tools/generate_material_glsl.gd shaders/generated/materials.glslinc
git commit -m "feat(materials): generate HAZARD_BIT array into glslinc"
```

---

## Task 3: Light shader emits hazard bitmask per cell

**Files:**
- Modify: `shaders/compute/light_pack.glsl`
- Modify: `src/core/compute_device.gd` (constants)

- [ ] **Step 1: Update LightCell layout to include hazard field**

In `src/core/compute_device.gd`, change:

```gdscript
const LIGHT_CELL_BYTES := 8
```

to:

```gdscript
const LIGHT_CELL_BYTES := 12
```

`LIGHT_OUTPUT_SIZE` (`= LIGHT_CELL_COUNT * LIGHT_CELL_BYTES`) auto-updates to 192.

- [ ] **Step 2: Update the shader struct and reduction**

Edit `shaders/compute/light_pack.glsl`:

Change the struct:

```glsl
struct LightCell {
    uint packed_count_glow;
    uint packed_pos;
    uint hazard_mask;
};
```

Add a shared accumulator after the existing `s_sum_glow`:

```glsl
shared uint s_hazard[64];
```

Inside the per-pixel loop, after `int mat = get_material(pixel);`, accumulate hazards:

```glsl
if (mat >= 0 && mat < MAT_COUNT) {
    int hbit = HAZARD_BIT[mat];
    if (hbit >= 0) {
        local_hazard |= (1u << uint(hbit));
    }
}
```

(declare `uint local_hazard = 0u;` next to the other locals.)

Write it into shared memory:

```glsl
s_hazard[thread_idx] = local_hazard;
```

In the reduction loop, OR-reduce hazard alongside the sums:

```glsl
for (uint stride = 32u; stride > 0u; stride >>= 1) {
    if (thread_idx < stride) {
        s_counts[thread_idx]   += s_counts[thread_idx + stride];
        s_sum_x[thread_idx]    += s_sum_x[thread_idx + stride];
        s_sum_y[thread_idx]    += s_sum_y[thread_idx + stride];
        s_sum_glow[thread_idx] += s_sum_glow[thread_idx + stride];
        s_hazard[thread_idx]   |= s_hazard[thread_idx + stride];
    }
    barrier();
}
```

In the `thread_idx == 0` write block, always write the hazard mask (regardless of the count < 4 branch):

```glsl
if (thread_idx == 0u) {
    if (cell_idx >= CELLS_X * CELLS_Y) return;
    uint count = s_counts[0];
    if (count < 4u) {
        output_data.cells[cell_idx].packed_count_glow = 0u;
        output_data.cells[cell_idx].packed_pos = 0u;
    } else {
        uint avg_x = s_sum_x[0] / count;
        uint avg_y = s_sum_y[0] / count;
        uint avg_glow_raw = s_sum_glow[0] / count;
        output_data.cells[cell_idx].packed_count_glow = (avg_glow_raw << 16) | (count & 0xFFFFu);
        output_data.cells[cell_idx].packed_pos = (avg_y << 16) | (avg_x & 0xFFFFu);
    }
    output_data.cells[cell_idx].hazard_mask = s_hazard[0];
}
```

- [ ] **Step 3: Commit**

```bash
git add shaders/compute/light_pack.glsl src/core/compute_device.gd
git commit -m "feat(light): emit per-cell hazard bitmask alongside light data"
```

---

## Task 4: Decoder returns hazard, default for legacy callers

**Files:**
- Modify: `src/core/compute_device.gd` (`decode_light_ssbo`)
- Test: `tests/unit/test_light_decode_hazard.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_light_decode_hazard.gd`:

```gdscript
extends GdUnitTestSuite

const LIGHT_CELL_COUNT := 16
const LIGHT_CELL_BYTES := 12
const LIGHT_OUTPUT_SIZE := LIGHT_CELL_COUNT * LIGHT_CELL_BYTES

func _make_buffer(hazard_per_cell: Array[int]) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(LIGHT_OUTPUT_SIZE)
	buf.fill(0)
	for i in range(LIGHT_CELL_COUNT):
		var off := i * LIGHT_CELL_BYTES
		buf.encode_u32(off + 8, hazard_per_cell[i])
	return buf

func test_decoder_extracts_hazard_mask() -> void:
	var device := ComputeDevice.new()
	var hazards: Array[int] = []
	hazards.resize(LIGHT_CELL_COUNT)
	for i in range(LIGHT_CELL_COUNT):
		hazards[i] = 0
	hazards[0] = MaterialRegistry.HAZARD_LAVA
	hazards[5] = MaterialRegistry.HAZARD_FIRE | MaterialRegistry.HAZARD_OIL
	var data := _make_buffer(hazards)
	var decoded := device.decode_light_ssbo(data)
	assert_that(decoded.size()).is_equal(LIGHT_CELL_COUNT)
	assert_that(int(decoded[0]["hazard"])).is_equal(MaterialRegistry.HAZARD_LAVA)
	assert_that(int(decoded[5]["hazard"])).is_equal(MaterialRegistry.HAZARD_FIRE | MaterialRegistry.HAZARD_OIL)
	assert_that(int(decoded[1]["hazard"])).is_equal(0)
```

- [ ] **Step 2: Run test to verify it fails**

```
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_light_decode_hazard.gd
```
Expected: FAIL (`hazard` key missing).

- [ ] **Step 3: Implement decoder update**

In `src/core/compute_device.gd`, modify `decode_light_ssbo` to read the hazard mask:

```gdscript
func decode_light_ssbo(data: PackedByteArray) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if data.size() < LIGHT_OUTPUT_SIZE:
		return result
	result.resize(LIGHT_CELL_COUNT)

	for cell_idx in range(LIGHT_CELL_COUNT):
		var off := cell_idx * LIGHT_CELL_BYTES
		var packed_count_glow := data.decode_u32(off)
		var packed_pos := data.decode_u32(off + 4)
		var hazard_mask := data.decode_u32(off + 8)

		var pixel_count := packed_count_glow & 0xFFFF
		var avg_glow_raw := (packed_count_glow >> 16) & 0xFFFF
		var avg_x := packed_pos & 0xFFFF
		var avg_y := (packed_pos >> 16) & 0xFFFF

		var energy := 0.0
		var pos := Vector2.ZERO

		if pixel_count >= 4:
			var avg_glow := float(avg_glow_raw) / 1000.0
			var coverage := clampf(float(pixel_count) / 32.0, 0.0, 1.0)
			energy = coverage * (avg_glow / 20.0)
			pos = Vector2(float(avg_x), float(avg_y))

		result[cell_idx] = {
			"position": pos,
			"energy": energy,
			"color": Color(1.0, 0.5, 0.15, 1.0),
			"hazard": int(hazard_mask),
		}

	return result
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/compute_device.gd tests/unit/test_light_decode_hazard.gd
git commit -m "feat(light): decode hazard mask from light SSBO"
```

---

## Task 5: Chunk stores hazard_cells, WorldManager writes it

**Files:**
- Modify: `src/core/chunk.gd`
- Modify: `src/core/world_manager.gd` (`_update_lights`)

- [ ] **Step 1: Add hazard_cells to Chunk**

Open `src/core/chunk.gd`. After the existing fields (near `chunk_lights`), add:

```gdscript
## Per sub-cell hazard bitmask (16 entries, LIGHT_CELLS_X * LIGHT_CELLS_Y).
## Updated each frame by WorldManager._update_lights.
var hazard_cells: PackedInt32Array = PackedInt32Array()
```

In the `_init` (or equivalent constructor / `_ready`) of `Chunk`, initialize:

```gdscript
hazard_cells.resize(16)
hazard_cells.fill(0)
```

(Place this alongside other one-time init in Chunk — if the file's init is `func _init():`, add it there; otherwise wherever fields are first populated.)

- [ ] **Step 2: WorldManager writes hazard cells from decoded data**

In `src/core/world_manager.gd`, find `_update_lights`. Around line 380–388 the code applies decoded light data to `chunk.chunk_lights`. Right after `chunk.chunk_lights.apply_light_data(decoded)` (or equivalent), add:

```gdscript
for i in range(min(decoded.size(), 16)):
    chunk.hazard_cells[i] = int(decoded[i].get("hazard", 0))
```

(Match the exact location: this should run for every chunk for which `decoded` was produced.)

- [ ] **Step 3: Commit**

```bash
git add src/core/chunk.gd src/core/world_manager.gd
git commit -m "feat(chunk): store per-cell hazard mask updated by light pipeline"
```

---

## Task 6: TerrainPhysical.hazard_at lookup

**Files:**
- Modify: `src/core/terrain_physical.gd`
- Test: `tests/unit/test_terrain_physical_hazard.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_terrain_physical_hazard.gd`:

```gdscript
extends GdUnitTestSuite

class FakeChunk:
	var hazard_cells: PackedInt32Array = PackedInt32Array()
	func _init() -> void:
		hazard_cells.resize(16)
		hazard_cells.fill(0)

class FakeWorldManager extends Node2D:
	var chunks: Dictionary = {}

func test_hazard_at_returns_false_for_unloaded_chunk() -> void:
	var tp := TerrainPhysical.new()
	var wm := FakeWorldManager.new()
	tp.world_manager = wm
	add_child(wm)
	assert_bool(tp.hazard_at(Vector2(10, 10), MaterialRegistry.HAZARD_LAVA)).is_false()
	wm.queue_free()

func test_hazard_at_returns_true_when_mask_matches() -> void:
	var tp := TerrainPhysical.new()
	var wm := FakeWorldManager.new()
	tp.world_manager = wm
	add_child(wm)
	var chunk := FakeChunk.new()
	# cell (0,0) of chunk (0,0). Sub-cell size 64; pixel (10,10) is in sub-cell index 0.
	chunk.hazard_cells[0] = MaterialRegistry.HAZARD_LAVA
	wm.chunks[Vector2i(0, 0)] = chunk
	assert_bool(tp.hazard_at(Vector2(10, 10), MaterialRegistry.HAZARD_LAVA)).is_true()
	assert_bool(tp.hazard_at(Vector2(10, 10), MaterialRegistry.HAZARD_FIRE)).is_false()
	wm.queue_free()

func test_hazard_at_maps_to_correct_sub_cell() -> void:
	var tp := TerrainPhysical.new()
	var wm := FakeWorldManager.new()
	tp.world_manager = wm
	add_child(wm)
	var chunk := FakeChunk.new()
	# Sub-cell at local (3,2) = idx 2*4+3 = 11. Pixel (3*64+10, 2*64+10) = (202, 138).
	chunk.hazard_cells[11] = MaterialRegistry.HAZARD_OIL
	wm.chunks[Vector2i(0, 0)] = chunk
	assert_bool(tp.hazard_at(Vector2(202, 138), MaterialRegistry.HAZARD_OIL)).is_true()
	assert_bool(tp.hazard_at(Vector2(10, 10), MaterialRegistry.HAZARD_OIL)).is_false()
	wm.queue_free()
```

- [ ] **Step 2: Run test to verify it fails**

```
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_terrain_physical_hazard.gd
```
Expected: FAIL — `hazard_at` does not exist.

- [ ] **Step 3: Implement hazard_at**

In `src/core/terrain_physical.gd`, add near the top:

```gdscript
const SUB_CELL_SIZE := 64  # CHUNK_SIZE / 4
const SUB_CELLS_PER_ROW := 4
```

Add the method:

```gdscript
func hazard_at(world_pos: Vector2, mask: int) -> bool:
	if world_manager == null or not ("chunks" in world_manager):
		return false
	var chunk_coord := Vector2i(
		floori(world_pos.x / float(CHUNK_SIZE)),
		floori(world_pos.y / float(CHUNK_SIZE)),
	)
	var chunk = world_manager.chunks.get(chunk_coord, null)
	if chunk == null or not ("hazard_cells" in chunk):
		return false
	var cells: PackedInt32Array = chunk.hazard_cells
	if cells.size() < SUB_CELLS_PER_ROW * SUB_CELLS_PER_ROW:
		return false
	var local_x := int(posmod(int(floor(world_pos.x)), CHUNK_SIZE))
	var local_y := int(posmod(int(floor(world_pos.y)), CHUNK_SIZE))
	var sx := local_x / SUB_CELL_SIZE
	var sy := local_y / SUB_CELL_SIZE
	var idx := sy * SUB_CELLS_PER_ROW + sx
	return (cells[idx] & mask) != 0
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/terrain_physical.gd tests/unit/test_terrain_physical_hazard.gd
git commit -m "feat(terrain): hazard_at sub-cell lookup"
```

---

## Task 7: Gate enemy and player damage checks on hazard_at

**Files:**
- Modify: `src/enemies/terrain_damage_receiver.gd`
- Modify: `src/player/lava_damage_checker.gd`

- [ ] **Step 1: Add hazard gate to TerrainDamageReceiver**

Edit `src/enemies/terrain_damage_receiver.gd`. After the early-out for dead enemies (`if enemy.get("health") <= 0: return`), insert:

```gdscript
var hazard_mask := MaterialRegistry.HAZARD_LAVA | MaterialRegistry.HAZARD_FIRE
if not _terrain_physical.hazard_at(enemy.position, hazard_mask):
    return
```

- [ ] **Step 2: Add hazard gate to LavaDamageChecker**

Edit `src/player/lava_damage_checker.gd`. After the dead-player early-out (`if inventory and inventory.is_dead(): return`), insert:

```gdscript
var hazard_mask := MaterialRegistry.HAZARD_LAVA | MaterialRegistry.HAZARD_FIRE
if not _terrain_physical.hazard_at(player.position, hazard_mask):
    return
```

- [ ] **Step 3: Manual smoke test**

Run the editor on the current scene. Stand on lava — confirm player still takes damage. Stand near but not on lava — confirm no spurious damage. Move an enemy onto lava in editor scene (or wait for AI) — confirm enemy still dies.

- [ ] **Step 4: Commit**

```bash
git add src/enemies/terrain_damage_receiver.gd src/player/lava_damage_checker.gd
git commit -m "perf: gate terrain damage checks on hazard sub-cell mask"
```

---

## Task 8: TerrainCell interning

**Files:**
- Modify: `src/autoload/material_registry.gd`
- Modify: `src/core/terrain_physical.gd`
- Test: `tests/unit/test_terrain_cell_intern.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_terrain_cell_intern.gd`:

```gdscript
extends GdUnitTestSuite

func test_get_cell_returns_same_instance_for_same_id() -> void:
	var registry := MaterialRegistry.new()
	registry._init_materials()
	var a := registry.get_cell(registry.MAT_DIRT)
	var b := registry.get_cell(registry.MAT_DIRT)
	assert_that(a).is_same(b)

func test_get_cell_distinct_per_id() -> void:
	var registry := MaterialRegistry.new()
	registry._init_materials()
	var dirt := registry.get_cell(registry.MAT_DIRT)
	var stone := registry.get_cell(registry.MAT_STONE)
	assert_that(dirt).is_not_same(stone)

func test_get_cell_reflects_material_props() -> void:
	var registry := MaterialRegistry.new()
	registry._init_materials()
	var lava := registry.get_cell(registry.MAT_LAVA)
	assert_that(lava.material_id).is_equal(registry.MAT_LAVA)
	assert_that(lava.is_fluid).is_true()
	assert_int(lava.damage).is_greater(0)
```

- [ ] **Step 2: Run test to verify it fails**

```
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_terrain_cell_intern.gd
```
Expected: FAIL — `get_cell` does not exist.

- [ ] **Step 3: Implement interning in MaterialRegistry**

In `src/autoload/material_registry.gd`, add field:

```gdscript
var _cell_cache: Dictionary = {}
```

Add method:

```gdscript
func get_cell(material_id: int) -> TerrainCell:
	if _cell_cache.has(material_id):
		return _cell_cache[material_id]
	var cell := TerrainCell.new(
		material_id,
		has_collider(material_id),
		is_fluid(material_id),
		get_damage(material_id),
	)
	_cell_cache[material_id] = cell
	return cell
```

- [ ] **Step 4: Use interned cells in TerrainPhysical**

In `src/core/terrain_physical.gd`, change `_cell_from_material`:

```gdscript
func _cell_from_material(mat_id: int) -> TerrainCell:
	return MaterialRegistry.get_cell(mat_id)
```

(The `query()` callsite already calls `_cell_from_material`. Likewise, the empty-cell default at the end of `query()` — change `return TerrainCell.new()` to `return MaterialRegistry.get_cell(MaterialRegistry.MAT_AIR)`.)

- [ ] **Step 5: Run test to verify it passes**

Same command as Step 2. Expected: PASS. Also run the existing suite to confirm no regression:

```
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/
```

- [ ] **Step 6: Commit**

```bash
git add src/autoload/material_registry.gd src/core/terrain_physical.gd tests/unit/test_terrain_cell_intern.gd
git commit -m "perf(terrain): intern TerrainCell per material id"
```

---

## Task 9: Bounded pending-probe FIFO

**Files:**
- Modify: `src/core/terrain_physical.gd`
- Test: `tests/unit/test_terrain_physical_pending_cap.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_terrain_physical_pending_cap.gd`:

```gdscript
extends GdUnitTestSuite

func test_pending_caps_at_max_pending() -> void:
	var tp := TerrainPhysical.new()
	tp.MAX_PENDING = 8  # shrink for test purposes
	for i in range(20):
		tp.query(Vector2(float(i), 0.0))
	assert_int(tp._pending_probes.size()).is_less_equal(8)

func test_pending_drops_oldest_on_overflow() -> void:
	var tp := TerrainPhysical.new()
	tp.MAX_PENDING = 4
	tp.query(Vector2(0, 0))
	tp.query(Vector2(1, 0))
	tp.query(Vector2(2, 0))
	tp.query(Vector2(3, 0))
	tp.query(Vector2(4, 0))  # should evict (0,0)
	assert_bool(tp._pending_probes.has(Vector2i(0, 0))).is_false()
	assert_bool(tp._pending_probes.has(Vector2i(4, 0))).is_true()

func test_duplicate_query_does_not_grow_pending() -> void:
	var tp := TerrainPhysical.new()
	tp.MAX_PENDING = 4
	for _i in range(10):
		tp.query(Vector2(5, 5))
	assert_int(tp._pending_probes.size()).is_equal(1)
```

- [ ] **Step 2: Run test to verify it fails**

```
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_terrain_physical_pending_cap.gd
```
Expected: FAIL — `MAX_PENDING` does not exist; pending grows unbounded.

- [ ] **Step 3: Implement bounded FIFO in TerrainPhysical**

In `src/core/terrain_physical.gd`, add a tunable (above the var declarations):

```gdscript
var MAX_PENDING: int = 1024  # 4 * PROBE_BUDGET; var (not const) so tests can shrink it.
```

Replace `query()`:

```gdscript
func query(world_pos: Vector2) -> TerrainCell:
	var cell_pos := Vector2i(int(floor(world_pos.x)), int(floor(world_pos.y)))
	if not _pending_probes.has(cell_pos):
		if _pending_probes.size() >= MAX_PENDING:
			# Drop oldest insertion-order key.
			var oldest = _pending_probes.keys()[0]
			_pending_probes.erase(oldest)
		_pending_probes[cell_pos] = true
	if _result_cache.has(cell_pos):
		var entry: Dictionary = _result_cache[cell_pos]
		if _current_frame - int(entry["frame"]) <= TTL_FRAMES:
			return _cell_from_material(int(entry["mat_id"]))
	return MaterialRegistry.get_cell(MaterialRegistry.MAT_AIR)
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/terrain_physical.gd tests/unit/test_terrain_physical_pending_cap.gd
git commit -m "perf(terrain): cap pending probes with FIFO eviction"
```

---

## Task 10: Double-buffered terrain probe SSBOs

**Files:**
- Modify: `src/core/compute_device.gd`
- Modify: `src/core/terrain_physical.gd`
- Modify: `src/core/world_manager.gd` (`_run_terrain_probes`)

- [ ] **Step 1: Raise PROBE_BUDGET and duplicate SSBOs in ComputeDevice**

In `src/core/compute_device.gd`, change:

```gdscript
const PROBE_BUDGET := 64
```
to:
```gdscript
const PROBE_BUDGET := 256
```

Replace single buffer fields:

```gdscript
var terrain_probe_input_buffer: RID
var terrain_probe_output_buffer: RID
```

with:

```gdscript
var terrain_probe_input_buffers: Array[RID] = [RID(), RID()]
var terrain_probe_output_buffers: Array[RID] = [RID(), RID()]
var terrain_probe_write_index: int = 0
var terrain_probe_first_frame: bool = true
```

Update `init_terrain_probe`:

```gdscript
func init_terrain_probe() -> void:
	var f: RDShaderFile = load("res://shaders/compute/terrain_probe.glsl")
	terrain_probe_shader = rd.shader_create_from_spirv(f.get_spirv())
	terrain_probe_pipeline = rd.compute_pipeline_create(terrain_probe_shader)

	var zero_in := PackedByteArray()
	zero_in.resize(PROBE_INPUT_BUFFER_SIZE)
	zero_in.fill(0)
	var zero_out := PackedByteArray()
	zero_out.resize(PROBE_OUTPUT_BUFFER_SIZE)
	zero_out.fill(0)
	for i in range(2):
		terrain_probe_input_buffers[i] = rd.storage_buffer_create(PROBE_INPUT_BUFFER_SIZE, zero_in)
		terrain_probe_output_buffers[i] = rd.storage_buffer_create(PROBE_OUTPUT_BUFFER_SIZE, zero_out)
```

Update `free_resources` (around lines 310–315):

```gdscript
for i in range(2):
	if terrain_probe_input_buffers[i].is_valid():
		rd.free_rid(terrain_probe_input_buffers[i])
		terrain_probe_input_buffers[i] = RID()
	if terrain_probe_output_buffers[i].is_valid():
		rd.free_rid(terrain_probe_output_buffers[i])
		terrain_probe_output_buffers[i] = RID()
```

- [ ] **Step 2: Update dispatch/read to use the write-index pair**

Modify `dispatch_terrain_probe` to use `terrain_probe_input_buffers[terrain_probe_write_index]` and `terrain_probe_output_buffers[terrain_probe_write_index]`. Replace the body of the function (keeping its signature) so every reference to `terrain_probe_input_buffer` becomes `terrain_probe_input_buffers[terrain_probe_write_index]` and likewise for output. The uniform set creation lines:

```gdscript
u_in.add_id(terrain_probe_input_buffers[terrain_probe_write_index])
...
u_out.add_id(terrain_probe_output_buffers[terrain_probe_write_index])
```

And the buffer update:

```gdscript
rd.buffer_update(terrain_probe_input_buffers[terrain_probe_write_index], 0, PROBE_INPUT_BUFFER_SIZE, packed_input)
```

`dispatch_terrain_probe` does **not** flip the index.

Replace `read_terrain_probe`:

```gdscript
func read_terrain_probe(byte_count: int) -> PackedByteArray:
	if byte_count <= 0:
		return PackedByteArray()
	if terrain_probe_first_frame:
		terrain_probe_first_frame = false
		terrain_probe_write_index = 1 - terrain_probe_write_index
		return PackedByteArray()
	var read_index := 1 - terrain_probe_write_index
	var result := rd.buffer_get_data(terrain_probe_output_buffers[read_index], 0, byte_count)
	terrain_probe_write_index = 1 - terrain_probe_write_index
	return result
```

- [ ] **Step 3: TerrainPhysical remembers the last dispatched batch**

In `src/core/terrain_physical.gd`, add field:

```gdscript
var _last_batch: Array = []
var _last_total_count: int = 0
```

Add a small helper for `world_manager.gd` to call after dispatch:

```gdscript
func record_dispatched_batch(batch: Array, total_count: int) -> void:
	_last_batch = batch
	_last_total_count = total_count
```

Keep `apply_probe_results(batch, raw_bytes)` as-is (it already takes a batch arg).

- [ ] **Step 4: Update WorldManager._run_terrain_probes for double-buffered pipeline**

Replace `_run_terrain_probes` body in `src/core/world_manager.gd`:

```gdscript
func _run_terrain_probes() -> void:
	if chunks.is_empty():
		return

	# First: read last frame's results from the GPU (no stall — GPU is one frame ahead).
	var prev_batch: Array = terrain_physical._last_batch
	var prev_total_count: int = terrain_physical._last_total_count
	if prev_total_count > 0:
		var raw := compute_device.read_terrain_probe(prev_total_count * 4)
		terrain_physical.apply_probe_results(prev_batch, raw)
	else:
		# Still need to advance ring index on first-frame; harmless on subsequent empty frames.
		compute_device.read_terrain_probe(0)

	# Then: drain current pending and dispatch to be read next frame.
	var batch := terrain_physical.prepare_probe_batch(ComputeDevice.PROBE_BUDGET)
	if batch.is_empty():
		terrain_physical.record_dispatched_batch([], 0)
		return

	var total_count: int = 0
	for entry in batch:
		total_count += int(entry["count"])
	if total_count <= 0:
		terrain_physical.record_dispatched_batch([], 0)
		return

	var packed_input := terrain_physical.pack_probe_input(batch, ComputeDevice.PROBE_BUDGET)
	var probe_uniform_sets := compute_device.dispatch_terrain_probe(chunks, batch, packed_input)
	terrain_physical.record_dispatched_batch(batch, total_count)

	for us in probe_uniform_sets:
		if us.is_valid():
			compute_device.rd.free_rid(us)
```

(Note: `read_terrain_probe(0)` short-circuits and just flips the ring index on first frame. Confirm Step 2's `byte_count <= 0` early-out returns empty without crashing.)

- [ ] **Step 5: Smoke test**

```
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/
```
Expected: all green (no test directly exercises the GPU path, but no regression in CPU-side suites).

Run editor and confirm lava still damages player after 1 frame of contact (it does — TTL_FRAMES default is 8).

- [ ] **Step 6: Commit**

```bash
git add src/core/compute_device.gd src/core/terrain_physical.gd src/core/world_manager.gd
git commit -m "perf(terrain): double-buffer probe SSBOs to remove sync stall, raise budget to 256"
```

---

## Task 11: Register attackable_hit physics layer

**Files:**
- Modify: `project.godot`
- Modify: enemy and player scene files (`*.tscn`) that should be hit-testable.

- [ ] **Step 1: Add the named layer**

Open `project.godot` and find the `[layer_names]` section (or create it if missing). Add:

```
2d_physics/layer_8="attackable_hit"
```

(Use layer 8 unless it's already taken — in which case use the first free slot ≥ 5, and remember the bit index for Step 3.)

- [ ] **Step 2: Add a constant in melee_weapon for the bit**

In `src/weapons/melee_weapon.gd`, add near other constants:

```gdscript
const ATTACKABLE_HIT_LAYER := 1 << 7  # layer 8, zero-indexed bit 7
```

(Adjust to the layer chosen in Step 1.)

- [ ] **Step 3: Audit all `attackable`-group nodes for a CollisionShape2D**

```bash
grep -rln "groups=.*attackable" scenes/ src/ --include="*.tscn"
```

For each scene returned, open it and:
- Confirm the root (or a child) has a `CollisionShape2D` with non-zero `shape`.
- On the body / area owning that shape, OR the `attackable_hit` bit into its `collision_layer` (in the inspector or via the tscn line `collision_layer = <bitmask>`).

If a scene lacks a `CollisionShape2D`, add a minimal one (`CircleShape2D` radius matching the enemy footprint).

- [ ] **Step 4: Smoke test**

Run the editor. Use the player to swing at one enemy — confirm it takes damage exactly as before (this test is still on the group-iteration path; the next task swaps it to intersect_shape).

- [ ] **Step 5: Commit**

```bash
git add project.godot src/weapons/melee_weapon.gd scenes/ src/
git commit -m "feat(physics): register attackable_hit layer on enemies and player"
```

---

## Task 12: Switch melee enemy hits to PhysicsServer2D.intersect_shape

**Files:**
- Modify: `src/weapons/melee_weapon.gd`
- Test: `tests/unit/test_melee_arc_angle_filter.gd`

- [ ] **Step 1: Extract the arc-angle filter as a pure function (testable)**

In `src/weapons/melee_weapon.gd`, add a static helper:

```gdscript
static func _is_inside_arc(origin: Vector2, target: Vector2, dir_angle: float, half_arc_angle: float, reach: float) -> bool:
	var to_target := target - origin
	var dist := to_target.length()
	if dist > reach or dist <= 0.001:
		return false
	return absf(angle_difference(dir_angle, to_target.angle())) <= half_arc_angle
```

- [ ] **Step 2: Write the failing test**

Create `tests/unit/test_melee_arc_angle_filter.gd`:

```gdscript
extends GdUnitTestSuite

func test_target_in_front_within_reach_passes() -> void:
	assert_bool(MeleeWeapon._is_inside_arc(Vector2.ZERO, Vector2(10, 0), 0.0, PI / 4, 16.0)).is_true()

func test_target_outside_reach_fails() -> void:
	assert_bool(MeleeWeapon._is_inside_arc(Vector2.ZERO, Vector2(20, 0), 0.0, PI / 4, 16.0)).is_false()

func test_target_behind_fails() -> void:
	assert_bool(MeleeWeapon._is_inside_arc(Vector2.ZERO, Vector2(-10, 0), 0.0, PI / 4, 16.0)).is_false()

func test_target_at_arc_edge_passes() -> void:
	# 45 degree arc, target at +44 degrees within reach.
	var t := Vector2.from_angle(deg_to_rad(44.0)) * 10.0
	assert_bool(MeleeWeapon._is_inside_arc(Vector2.ZERO, t, 0.0, deg_to_rad(45.0), 16.0)).is_true()

func test_zero_distance_fails() -> void:
	assert_bool(MeleeWeapon._is_inside_arc(Vector2.ZERO, Vector2.ZERO, 0.0, PI / 4, 16.0)).is_false()
```

- [ ] **Step 3: Run test to verify it passes (helper is already in place)**

```
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_melee_arc_angle_filter.gd
```
Expected: PASS (since helper exists from Step 1). If FAIL, fix helper to match.

- [ ] **Step 4: Replace _hit_attackables_in_arc to use intersect_shape**

Replace the function body in `src/weapons/melee_weapon.gd`:

```gdscript
func _hit_attackables_in_arc(user: Node, origin: Vector2, direction: Vector2) -> void:
	var dmg: int = int(damage)
	if dmg <= 0:
		return
	var dir_angle: float = direction.angle()
	var half_arc_angle: float = arc_angle / 2.0

	var space_state := user.get_world_2d().direct_space_state
	var circle := CircleShape2D.new()
	circle.radius = weapon_reach
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = circle
	params.transform = Transform2D(0.0, origin)
	params.collision_mask = ATTACKABLE_HIT_LAYER
	params.collide_with_areas = true
	params.collide_with_bodies = true

	var hits: Array = space_state.intersect_shape(params, 32)
	for hit in hits:
		var node: Node = hit.get("collider", null)
		if node == null or node == user:
			continue
		if not (node is Node2D):
			continue
		if not node.has_method("on_hit_impact"):
			continue
		var node2d := node as Node2D
		if not _is_inside_arc(origin, node2d.global_position, dir_angle, half_arc_angle, weapon_reach):
			continue
		var hit_dir: Vector2 = (node2d.global_position - origin).normalized()
		if node.has_method("try_parry"):
			if node.try_parry(user, node2d.global_position, hit_dir):
				var tint: Color = trail_color if "trail_color" in self else Color(1, 1, 1, 1)
				NailClashFX.play(node2d.global_position, -hit_dir, tint)
				continue
		node.on_hit_impact(node2d.global_position, hit_dir, dmg)
```

- [ ] **Step 5: Smoke test in editor**

Run the scene. Attack one enemy: takes damage. Attack with multiple enemies in range: all take damage. Attack with an enemy just outside the cone: untouched. Compare to behavior before the change.

- [ ] **Step 6: Commit**

```bash
git add src/weapons/melee_weapon.gd tests/unit/test_melee_arc_angle_filter.gd
git commit -m "perf(melee): hit-test enemies via intersect_shape instead of group scan"
```

---

## Task 13: Melee arc compute shader (terrain modification on GPU)

**Files:**
- Create: `shaders/compute/melee_arc.glsl`
- Modify: `src/core/compute_device.gd` (init/dispatch + ring SSBOs)

- [ ] **Step 1: Write the shader**

Create `shaders/compute/melee_arc.glsl`:

```glsl
#[compute]
#version 450

#include "res://shaders/generated/materials.glslinc"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba8, set = 0, binding = 0) uniform image2D chunk_tex;

struct HitEntry {
    int world_x;
    int world_y;
    uint mat_id;
    float scale;
};

layout(set = 0, binding = 1, std430) buffer HitList {
    uint count;
    uint _pad[3];
    HitEntry entries[];
} hit_list;

layout(push_constant, std430) uniform PushConstants {
    ivec2 chunk_origin;        // world position of chunk's (0,0) pixel
    vec2 origin;               // swing center, in world coords
    vec2 direction;            // unit vector
    float radius;
    float inner_radius;
    float arc_half_angle;
    float push_speed;          // unused for clear pass; kept for shader uniformity
    float damage;              // 0.0 => fluid push only, no impact emission
    uint target_mask_low;      // bit i set if material id i is a target (ids 0..31)
    uint hit_capacity;
    uint _pad0;
} pc;

bool is_target(uint mat_id) {
    if (mat_id >= 32u) return false;
    return (pc.target_mask_low & (1u << mat_id)) != 0u;
}

float hardness_for(uint mat_id) {
    // Mirror MaterialRegistry.get_hardness; for materials without hardness, return 0.
    // The CPU is the authority but we replicate the scaling so the GPU clear matches.
    // For now: dirt=0.5, wood=2, coal=3, ice=4, stone=5.
    if (mat_id == uint(MAT_DIRT)) return 0.5;
    if (mat_id == uint(MAT_WOOD)) return 2.0;
    if (mat_id == uint(MAT_COAL)) return 3.0;
    if (mat_id == uint(MAT_ICE)) return 4.0;
    if (mat_id == uint(MAT_STONE)) return 5.0;
    return 0.0;
}

void main() {
    ivec2 local = ivec2(gl_GlobalInvocationID.xy);
    if (local.x < 0 || local.x >= 256 || local.y < 0 || local.y >= 256) return;

    vec2 world_pos = vec2(pc.chunk_origin) + vec2(local);
    vec2 to_pixel = world_pos - pc.origin;
    float dist_sq = dot(to_pixel, to_pixel);
    float r_sq = pc.radius * pc.radius;
    if (dist_sq > r_sq) return;

    float pixel_angle = atan(to_pixel.y, to_pixel.x);
    float dir_angle = atan(pc.direction.y, pc.direction.x);
    float delta = pixel_angle - dir_angle;
    delta = atan(sin(delta), cos(delta)); // normalize to [-PI, PI]
    if (abs(delta) > pc.arc_half_angle) return;

    vec4 pix = imageLoad(chunk_tex, local);
    uint mat = uint(pix.r * 255.0 + 0.5);
    if (!is_target(mat)) return;

    bool do_clear = dist_sq < pc.inner_radius * pc.inner_radius;
    bool is_solid_pass = pc.damage >= 0.0;

    if (!do_clear) {
        // Outer ring: fluid push is intentionally not implemented in this pass.
        // (See plan "Deferred" note — needs a velocity image binding.)
        return;
    }

    if (is_solid_pass) {
        float hardness = hardness_for(mat);
        float scale_clamped = clamp(pc.damage / (pc.damage + hardness), 0.1, 1.0);
        float effective_r = pc.radius * scale_clamped;
        if (dist_sq > effective_r * effective_r) return;

        imageStore(chunk_tex, local, vec4(0.0, 0.0, 0.0, 0.0));

        uint idx = atomicAdd(hit_list.count, 1u);
        if (idx < pc.hit_capacity) {
            hit_list.entries[idx].world_x = int(world_pos.x);
            hit_list.entries[idx].world_y = int(world_pos.y);
            hit_list.entries[idx].mat_id = mat;
            hit_list.entries[idx].scale = scale_clamped;
        }
    } else {
        // Fluid pass: clear in inner ring, no impact emission (matches CPU behavior
        // where fluids in inner ring were cleared with do_clear=true and no impact
        // was recorded for them).
        imageStore(chunk_tex, local, vec4(0.0, 0.0, 0.0, 0.0));
    }
}
```

- [ ] **Step 2: Add SSBO ring + pipeline + init in ComputeDevice**

In `src/core/compute_device.gd`, add fields:

```gdscript
const MELEE_HIT_RING := 3
const MELEE_HIT_CAPACITY := 64
const MELEE_HIT_HEADER_BYTES := 16  # 4 uints (count + 3 pad)
const MELEE_HIT_ENTRY_BYTES := 16   # ivec2 + uint + float
const MELEE_HIT_BUFFER_SIZE := MELEE_HIT_HEADER_BYTES + MELEE_HIT_CAPACITY * MELEE_HIT_ENTRY_BYTES

var melee_arc_shader: RID
var melee_arc_pipeline: RID
var melee_hit_buffers: Array[RID] = [RID(), RID(), RID()]
var melee_hit_write_index: int = 0
```

Add init function called from `_ready` after `init_terrain_probe`:

```gdscript
func init_melee_arc() -> void:
	var f: RDShaderFile = load("res://shaders/compute/melee_arc.glsl")
	melee_arc_shader = rd.shader_create_from_spirv(f.get_spirv())
	melee_arc_pipeline = rd.compute_pipeline_create(melee_arc_shader)
	var zero := PackedByteArray()
	zero.resize(MELEE_HIT_BUFFER_SIZE)
	zero.fill(0)
	for i in range(MELEE_HIT_RING):
		melee_hit_buffers[i] = rd.storage_buffer_create(MELEE_HIT_BUFFER_SIZE, zero)
```

Wire the call in `_ready` (search for `init_terrain_probe()`; add a sibling call right after).

In `free_resources`, add:

```gdscript
for i in range(MELEE_HIT_RING):
	if melee_hit_buffers[i].is_valid():
		rd.free_rid(melee_hit_buffers[i])
		melee_hit_buffers[i] = RID()
if melee_arc_pipeline.is_valid():
	rd.free_rid(melee_arc_pipeline)
	melee_arc_pipeline = RID()
if melee_arc_shader.is_valid():
	rd.free_rid(melee_arc_shader)
	melee_arc_shader = RID()
```

- [ ] **Step 3: Add dispatch and drain methods**

In `src/core/compute_device.gd`, add:

```gdscript
func dispatch_melee_arc(chunks: Dictionary, affected_chunk_coords: Array[Vector2i],
		origin: Vector2, direction: Vector2,
		radius: float, inner_radius: float, arc_half_angle: float,
		push_speed: float, damage: float, target_mask: int) -> Array[RID]:
	if affected_chunk_coords.is_empty():
		return []

	# Zero the write buffer's count header so atomicAdd starts from 0.
	var zero_header := PackedByteArray()
	zero_header.resize(MELEE_HIT_HEADER_BYTES)
	zero_header.fill(0)
	rd.buffer_update(melee_hit_buffers[melee_hit_write_index], 0, MELEE_HIT_HEADER_BYTES, zero_header)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, melee_arc_pipeline)

	var created: Array[RID] = []
	for coord in affected_chunk_coords:
		var chunk: Chunk = chunks.get(coord, null)
		if chunk == null or not chunk.rd_texture.is_valid():
			continue

		var u_tex := RDUniform.new()
		u_tex.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_tex.binding = 0
		u_tex.add_id(chunk.rd_texture)

		var u_hits := RDUniform.new()
		u_hits.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u_hits.binding = 1
		u_hits.add_id(melee_hit_buffers[melee_hit_write_index])

		var us := rd.uniform_set_create([u_tex, u_hits], melee_arc_shader, 0)
		created.append(us)
		rd.compute_list_bind_uniform_set(compute_list, us, 0)

		var origin_chunk := coord * CHUNK_SIZE
		var push := PackedByteArray()
		push.resize(64)
		push.fill(0)
		push.encode_s32(0, origin_chunk.x)
		push.encode_s32(4, origin_chunk.y)
		push.encode_float(8, origin.x)
		push.encode_float(12, origin.y)
		push.encode_float(16, direction.x)
		push.encode_float(20, direction.y)
		push.encode_float(24, radius)
		push.encode_float(28, inner_radius)
		push.encode_float(32, arc_half_angle)
		push.encode_float(36, push_speed)
		push.encode_float(40, damage)
		push.encode_u32(44, target_mask)
		push.encode_u32(48, MELEE_HIT_CAPACITY)
		rd.compute_list_set_push_constant(compute_list, push, push.size())

		rd.compute_list_dispatch(compute_list, 32, 32, 1)  # 256 / 8 = 32 workgroups per axis

	rd.compute_list_end()
	return created


func drain_melee_hits() -> Array:
	# Read the buffer that's 3 frames behind the write index.
	var read_index := (melee_hit_write_index + 1) % MELEE_HIT_RING
	var raw := rd.buffer_get_data(melee_hit_buffers[read_index], 0, MELEE_HIT_BUFFER_SIZE)
	if raw.size() < MELEE_HIT_HEADER_BYTES:
		return []
	var count: int = int(raw.decode_u32(0))
	var capped: int = min(count, MELEE_HIT_CAPACITY)
	var result: Array = []
	for i in range(capped):
		var off := MELEE_HIT_HEADER_BYTES + i * MELEE_HIT_ENTRY_BYTES
		result.append({
			"world_pos": Vector2(float(raw.decode_s32(off)), float(raw.decode_s32(off + 4))),
			"material_id": int(raw.decode_u32(off + 8)),
			"scale": raw.decode_float(off + 12),
		})
	# Advance write index for next dispatch.
	melee_hit_write_index = (melee_hit_write_index + 1) % MELEE_HIT_RING
	return result
```

- [ ] **Step 4: Commit**

```bash
git add shaders/compute/melee_arc.glsl src/core/compute_device.gd
git commit -m "feat(melee): GPU compute pipeline for arc terrain modification + hit list ring"
```

---

## Task 14: Route TerrainModifier.clear_and_push_materials_in_arc through the dispatch

**Files:**
- Modify: `src/core/terrain_modifier.gd`
- Modify: `src/core/world_manager.gd` (return type of wrapper)
- Modify: `src/weapons/melee_weapon.gd` (caller)

- [ ] **Step 1: Replace the CPU loop with a dispatch**

In `src/core/terrain_modifier.gd`, replace `clear_and_push_materials_in_arc` (lines 353 onward through the function end). New version:

```gdscript
func clear_and_push_materials_in_arc(
	origin: Vector2,
	direction: Vector2,
	radius: float,
	arc_angle: float,
	push_speed: float,
	edge_fraction: float,
	materials: Array[int],
	damage: float = -1.0
) -> void:
	if world_manager.chunks.is_empty():
		return

	var r_int := int(ceil(radius))
	var origin_int := Vector2i(int(origin.x), int(origin.y))
	var min_world := origin_int - Vector2i(r_int, r_int)
	var max_world := origin_int + Vector2i(r_int, r_int)
	var min_chunk := Vector2i(floori(float(min_world.x) / CHUNK_SIZE), floori(float(min_world.y) / CHUNK_SIZE))
	var max_chunk := Vector2i(floori(float(max_world.x) / CHUNK_SIZE), floori(float(max_world.y) / CHUNK_SIZE))

	var affected: Array[Vector2i] = []
	for cx in range(min_chunk.x, max_chunk.x + 1):
		for cy in range(min_chunk.y, max_chunk.y + 1):
			var coord := Vector2i(cx, cy)
			if world_manager.chunks.has(coord):
				affected.append(coord)
	if affected.is_empty():
		return

	var inner_r := radius * (1.0 - edge_fraction)
	var half_arc := arc_angle / 2.0

	var target_mask: int = 0
	for mat_id in materials:
		if mat_id >= 0 and mat_id < 32:
			target_mask |= (1 << mat_id)

	# Pass damage as-is, including the negative sentinel that signals the fluid pass.
	var uniform_sets := world_manager.compute_device.dispatch_melee_arc(
		world_manager.chunks, affected, origin, direction,
		radius, inner_r, half_arc, push_speed, damage, target_mask
	)
	for us in uniform_sets:
		if us.is_valid():
			world_manager.compute_device.rd.free_rid(us)

	# Invalidate the probe cache for the affected region so queries pick up new state next frame.
	var modified_rect := Rect2i(min_world, max_world - min_world + Vector2i.ONE)
	world_manager.terrain_physical.invalidate_rect(modified_rect)
```

- [ ] **Step 2: Update WorldManager wrapper signature**

In `src/core/world_manager.gd` find the wrapper around line 178:

```gdscript
func clear_and_push_materials_in_arc(origin: Vector2, direction: Vector2, radius: float, arc_angle: float, push_speed: float, edge_fraction: float, materials: Array[int], damage: float = -1.0) -> Array:
	return terrain_modifier.clear_and_push_materials_in_arc(origin, direction, radius, arc_angle, push_speed, edge_fraction, materials, damage)
```

Change to:

```gdscript
func clear_and_push_materials_in_arc(origin: Vector2, direction: Vector2, radius: float, arc_angle: float, push_speed: float, edge_fraction: float, materials: Array[int], damage: float = -1.0) -> void:
	terrain_modifier.clear_and_push_materials_in_arc(origin, direction, radius, arc_angle, push_speed, edge_fraction, materials, damage)
```

- [ ] **Step 3: Update MeleeWeapon caller**

In `src/weapons/melee_weapon.gd`, change the lines around 107 and 116:

```gdscript
TerrainSurface.clear_and_push_materials_in_arc(pos, direction, weapon_reach, arc_angle, push_speed, 0.25, fluids)
...
var impacts: Array = TerrainSurface.clear_and_push_materials_in_arc(pos, direction, weapon_reach, arc_angle, 0.0, 0.0, solids, damage)
for impact in impacts:
	TerrainImpact.play_impact(impact["world_pos"], impact["material_id"], impact["scale"])
_hit_attackables_in_arc(user, pos, direction)
```

Become:

```gdscript
TerrainSurface.clear_and_push_materials_in_arc(pos, direction, weapon_reach, arc_angle, push_speed, 0.25, fluids)
...
TerrainSurface.clear_and_push_materials_in_arc(pos, direction, weapon_reach, arc_angle, 0.0, 0.0, solids, damage)
_hit_attackables_in_arc(user, pos, direction)
```

- [ ] **Step 4: Search for other callers**

```bash
grep -rn "clear_and_push_materials_in_arc" src/ --include="*.gd"
```

Inspect each result; any other consumer of the returned `impacts` array must be updated to not depend on it (or moved to use the deferred drainer in the next task).

- [ ] **Step 5: Smoke test**

Run editor. Attack a wall — confirm pixels disappear after roughly one frame. Spark FX will be missing until Task 15.

- [ ] **Step 6: Commit**

```bash
git add src/core/terrain_modifier.gd src/core/world_manager.gd src/weapons/melee_weapon.gd
git commit -m "perf(terrain): fire-and-forget GPU dispatch for melee terrain mods"
```

---

## Task 15: Deferred impact FX drainer

**Files:**
- Modify: `src/core/world_manager.gd`

- [ ] **Step 1: Add drainer call in _process**

In `src/core/world_manager.gd`, find `_process` (look for the existing call to `_update_lights()` around line 84). Right after `_update_lights()`, add:

```gdscript
_drain_terrain_impacts()
```

- [ ] **Step 2: Implement _drain_terrain_impacts**

Add the function in `src/core/world_manager.gd`:

```gdscript
func _drain_terrain_impacts() -> void:
	var hits: Array = compute_device.drain_melee_hits()
	for hit in hits:
		TerrainImpact.play_impact(hit["world_pos"], hit["material_id"], hit["scale"])
```

- [ ] **Step 3: Smoke test**

Run editor. Attack a wall — confirm sparks appear (about 3 frames after the swing, imperceptible).

- [ ] **Step 4: Commit**

```bash
git add src/core/world_manager.gd
git commit -m "feat(terrain): drain melee hit list ring for deferred impact FX"
```

---

## Task 16: Validate frame budget

**Files:** none (verification only).

- [ ] **Step 1: Reproduce the stress scene**

Open the same scene used for the profile screenshot (588 enemies, active lava/fire). Enable the editor profiler with `Profile Functions` on.

- [ ] **Step 2: Capture frame time**

Let the scene run for ~10 seconds with the player moving and occasionally attacking. Pause the profiler.

- [ ] **Step 3: Verify each before/after target**

| Subsystem | Target |
|---|---|
| `_run_terrain_probes` | < 2 ms |
| `TerrainDamageReceiver._physics_process` (total) | < 2 ms |
| `_hit_attackables_in_arc` (per swing) | < 1 ms |
| `clear_and_push_materials_in_arc` (per swing, both calls) | < 2 ms |
| Frame Time | < 16.6 ms |

If any line exceeds its target, capture a new profile screenshot, attach it to the worktree, and stop — do not declare the plan complete. Investigate the specific hotspot before continuing.

- [ ] **Step 4: Run the full unit test suite**

```
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/
```
Expected: all green.

- [ ] **Step 5: Commit a note recording the result**

If targets are met, no commit needed (no code change). If you added a profile screenshot, commit it under `docs/superpowers/specs/` alongside the design doc:

```bash
git add docs/superpowers/specs/2026-05-19-fps-perf-pass-after.png
git commit -m "docs(perf): record post-pass profile capture"
```

---

## Deferred follow-ups (not in this plan)

- **GPU fluid push velocity.** The CPU implementation of
  `clear_and_push_materials_in_arc` set a per-pixel push direction
  in the outer ring for fluid materials. The GPU shader in Task 13
  clears fluids in the inner ring but does **not** apply push
  velocity to the outer ring (no velocity image binding exists
  yet). The visible difference is that swinging through a pool of
  lava no longer kicks droplets outward — the lava is still
  carved. If this matters, add a velocity image binding to the
  shader and atomically `imageStore` push direction encoded into
  the chunk's velocity texture.
- **`place_blood` cost** (6.46 ms × 6 calls) and other per-event
  spikes flagged in the spec. Per-event, not per-frame; revisit
  only if 60 FPS regresses under heavy hit waves.

---

## Summary of expected outcome

| Subsystem | Before | After (target) |
|---|---|---|
| `_run_terrain_probes` | 66.82 ms | < 2 ms |
| TerrainDamageReceiver (588×) | 9.99 ms | < 2 ms |
| `_hit_attackables_in_arc` per swing | 6.90 ms | < 1 ms |
| `clear_and_push_materials_in_arc` ×2 per swing | 24.48 ms | < 2 ms (dispatch only) |
| Total `_process` budget | 88 ms | < 16.6 ms |
