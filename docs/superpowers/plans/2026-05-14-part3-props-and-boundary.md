# Part 3: Props & World Boundary — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fill cave chunks with material and entity props (lava/oil/water/gas pools, ice & sand powders, explosive boxes, oil barrels, wooden pillars), introduce destruction debris that turns destroyed solids into powder, and bound the infinite world with a wardstone warning ring + indestructible void wall.

**Architecture:** Companion `chunk_flags_tex` scratch buffer carries a `NO_PROPS` mask; a new GPU stage `stage_biome_props` scatters material props post-walkability; a GDScript `PropDispatcher` scatters entity props on `chunks_generated`. Powder is a static "pile-on-floor" sim with melee/explode-wave dispersal and per-material heat reactions. Destruction is branchless via a 256-entry per-material `DESTRUCTION_TABLE` baked into `materials.glslinc`. World boundary is a generation-stage override at sector Chebyshev distance >10.

**Tech Stack:** Godot 4, GDScript, GLSL compute shaders, GdUnit4. Depends on Part 1 (walkability alpha-scratch and `stage_walkability_enforce`) and Part 2 (MAT_OIL, MAT_EXPLODE_WAVE, perimeter accent materials).

**Dependency:** Parts 1 and 2 must be merged.

---

## File Structure

**New:**
- `shaders/include/biome_props_stage.glslinc` — material prop scatter
- `shaders/include/world_boundary_stage.glslinc` — wardstone ring + void zone fill
- `shaders/include/powder_stage.glslinc` — powder idle + dispersal + heat reactions
- `src/core/prop_dispatcher.gd` — post-gen entity scatter
- `src/core/prop_def.gd` — biome material-prop resource type
- `src/core/entity_prop_def.gd` — biome entity-prop resource type
- `scenes/props/wooden_pillar.tscn`, `src/drops/wooden_pillar.gd` — new pillar prop
- `tests/unit/test_world_boundary.gd`, `tests/unit/test_prop_density.gd`, `tests/unit/test_destruction_debris.gd`, `tests/unit/test_powder_dispersal.gd`

**Modified:**
- `src/autoload/material_registry.gd` — register `MAT_ICE_POWDER`, `MAT_SAND_DUST`, `MAT_WARDSTONE`, `MAT_VOID_STONE`; add `destruction_distribution: Dictionary` and `indestructible: bool` fields to `MaterialDef`
- `tools/generate_material_glsl.gd` — emit `DESTRUCTION_TABLE[MAT_COUNT][256]` and `INDESTRUCTIBLE[MAT_COUNT]`
- `src/core/biome_def.gd` — add `prop_pools: Array[PropDef]`, `entity_prop_pool: Array[EntityPropDef]`
- `assets/biomes/*.tres` — populate prop pools per the spec mapping
- `shaders/compute/generation*.glsl` — wire boundary stage (first), props stage (after walkability_enforce); bind `chunk_flags_tex`
- `shaders/compute/<sim shader>` — add `stage_powder`
- `shaders/include/walkability_enforce_stage.glslinc` — also write NO_PROPS into chunk_flags_tex for pocket cells
- `shaders/include/pixel_scene_stamp.glslinc` — write NO_PROPS for stamp footprint cells
- `src/core/terrain_modifier.gd` — destruction lookup via DESTRUCTION_TABLE; honor INDESTRUCTIBLE
- `gdextension/src/compute_device.*` — allocate `chunk_flags_tex` per chunk
- `src/core/world_manager.gd` — `read_region` optionally returns flag bytes

---

## Task 1: Allocate `chunk_flags_tex` companion buffer

**Files:**
- Modify: `gdextension/src/compute_device.cpp` (or equivalent)
- Modify: `shaders/compute/generation*.glsl`

R8 storage texture parallel to `chunk_tex`. Bound at set 0 binding 4 (binding 3 was claimed by Part 1's `chunk_max_radius_buf`).

- [ ] **Step 1: Allocate per chunk** following the pattern from Part 1's `jfa_a/jfa_b`:

```cpp
chunk.flags_tex = create_storage_texture(256, 256, RD::DATA_FORMAT_R8_UINT);
// In uniform set:
add_image_binding(uniform_set, /*binding=*/4, chunk.flags_tex);
// In chunk free:
free_rid(chunk.flags_tex);
```

- [ ] **Step 2: Add binding in gen shaders.**

```glsl
layout(r8ui, set = 0, binding = 4) uniform uimage2D chunk_flags_tex;
```

- [ ] **Step 3: Initialize to 0 at start of each gen run.** Add an early pass (pass = -1 or part of the existing pass-0 base) that writes 0 to every cell of `chunk_flags_tex`.

Simplest: at the start of `main()` in generation_simplex_cave.glsl, if `gen_pass_idx == 0`:

```glsl
if (push_ctx.gen_pass_idx == 0) {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x < 256 && pos.y < 256) {
        imageStore(chunk_flags_tex, pos, uvec4(0));
    }
    // ... rest of base-pass stages ...
}
```

- [ ] **Step 4: Verify game runs without errors.**

- [ ] **Step 5: Commit.**

```bash
git add -A
git commit -m "feat(gen): allocate chunk_flags_tex companion scratch buffer"
```

---

## Task 2: NO_PROPS bit writers — walkability_enforce

**Files:**
- Modify: `shaders/include/walkability_enforce_stage.glslinc`

Within Part 1's enforce stages, every cell inside the centroid's 150×150 region gets `NO_PROPS` (bit 0) set in `chunk_flags_tex`.

- [ ] **Step 1: Add a helper.**

```glsl
void set_no_props(ivec2 pos) {
    uvec4 cur = imageLoad(chunk_flags_tex, pos);
    cur.r |= 1u;
    imageStore(chunk_flags_tex, pos, cur);
}
```

- [ ] **Step 2: Wire into the strip-pools and dilate stages.** Inside each, after computing the cell is within the pocket bounds (the existing range checks), call `set_no_props(pos)`:

```glsl
// At the start of stage_walkability_strip_pools, after computing range/centroid checks:
if (max(abs(pos.x - cx), abs(pos.y - cy)) <= 75) {
    set_no_props(pos);
}
```

(Apply to both strip-pools and the per-iteration dilate functions.)

- [ ] **Step 3: Commit.**

```bash
git add shaders/include/walkability_enforce_stage.glslinc
git commit -m "feat(gen): walkability enforce flags guaranteed-pocket cells NO_PROPS"
```

---

## Task 3: NO_PROPS bit writers — pixel_scene_stamp

**Files:**
- Modify: `shaders/include/pixel_scene_stamp.glslinc`

Every cell inside a stamp's bounding rect (regardless of whether the stamp wrote material or left air) gets NO_PROPS set.

- [ ] **Step 1: At the start of the per-cell stamp body**, if any stamp's bounding rect contains `pos`, set `NO_PROPS`. Reuse the existing per-stamp loop; after determining a stamp covers the cell:

```glsl
// Inside the existing loop where the stamp meta is read:
uvec4 fcur = imageLoad(chunk_flags_tex, pos);
fcur.r |= 1u;
imageStore(chunk_flags_tex, pos, fcur);
```

- [ ] **Step 2: Commit.**

```bash
git add shaders/include/pixel_scene_stamp.glslinc
git commit -m "feat(gen): pixel stamp flags footprint cells NO_PROPS"
```

---

## Task 4: Register powders, wardstone, void_stone

**Files:**
- Modify: `src/autoload/material_registry.gd`

- [ ] **Step 1: Declare vars and register.**

```gdscript
var MAT_ICE_POWDER: int
var MAT_SAND_DUST: int
var MAT_WARDSTONE: int
var MAT_VOID_STONE: int

# In _init_materials(), after Part 2's additions:

var mat_ice_powder := MaterialDef.new(
    "ICE_POWDER", "",
    false, 0, 30,   # 30-tick melt timer
    false, false,   # non-solid, no wall extension (entities pass through)
    Color(0.78, 0.90, 0.98, 1.0),
    false, 0, 1.0, 0.0,
    false   # not indestructible
)
mat_ice_powder.id = materials.size()
materials.append(mat_ice_powder)
MAT_ICE_POWDER = mat_ice_powder.id

var mat_sand_dust := MaterialDef.new(
    "SAND_DUST", "",
    false, 0, 0,
    false, false,
    Color(0.74, 0.65, 0.46, 1.0),
    false, 0, 1.0, 0.0,
    false
)
mat_sand_dust.id = materials.size()
materials.append(mat_sand_dust)
MAT_SAND_DUST = mat_sand_dust.id

var mat_wardstone := MaterialDef.new(
    "WARDSTONE", "",
    false, 0, 0,
    true, true,
    Color(0.55, 0.45, 0.85, 1.0),
    false, 0, 30.0, 100.0,
    true   # indestructible
)
mat_wardstone.id = materials.size()
materials.append(mat_wardstone)
MAT_WARDSTONE = mat_wardstone.id

var mat_void := MaterialDef.new(
    "VOID_STONE", "",
    false, 0, 0,
    true, true,
    Color(0.02, 0.02, 0.04, 1.0),
    false, 0, 1.0, 1000.0,
    true
)
mat_void.id = materials.size()
materials.append(mat_void)
MAT_VOID_STONE = mat_void.id
```

- [ ] **Step 2: Add a `destruction_distribution: Dictionary` field to `MaterialDef`** — default `{MAT_AIR: 1.0}`:

```gdscript
class MaterialDef:
    var destruction_distribution: Dictionary = {0: 1.0}  # default to 100% AIR
    # add p_destruction_distribution: Dictionary = {0: 1.0} to _init params

    func _init(... p_destruction_distribution: Dictionary = {0: 1.0} ...):
        destruction_distribution = p_destruction_distribution
```

- [ ] **Step 3: Populate distributions** for the relevant materials, after all materials are registered:

```gdscript
# At the end of _init_materials():
materials[MAT_STONE].destruction_distribution = {MAT_SAND_DUST: 0.4, MAT_AIR: 0.6}
materials[MAT_DIRT].destruction_distribution  = {MAT_SAND_DUST: 0.4, MAT_AIR: 0.6}
materials[MAT_COAL].destruction_distribution  = {MAT_SAND_DUST: 0.3, MAT_AIR: 0.7}
materials[MAT_ICE].destruction_distribution   = {MAT_ICE_POWDER: 0.5, MAT_AIR: 0.5}
materials[MAT_STONE_BRICKS].destruction_distribution    = {MAT_SAND_DUST: 0.3, MAT_AIR: 0.7}
materials[MAT_OBSIDIAN].destruction_distribution        = {MAT_SAND_DUST: 0.3, MAT_AIR: 0.7}
materials[MAT_PACKED_ICE].destruction_distribution      = {MAT_ICE_POWDER: 0.5, MAT_AIR: 0.5}
materials[MAT_STONE_CRACKED].destruction_distribution   = materials[MAT_STONE].destruction_distribution.duplicate()
materials[MAT_MAGMA_STONE_CRACKED].destruction_distribution = {MAT_SAND_DUST: 0.3, MAT_AIR: 0.7}
materials[MAT_FROZEN_ROCK_CRACKED].destruction_distribution = {MAT_ICE_POWDER: 0.4, MAT_AIR: 0.6}
# Wood/metal/perimeter-metal/wardstone/void left at default {MAT_AIR: 1.0} (clean break, or indestructible -> never invoked).
```

- [ ] **Step 4: Regenerate materials.glslinc.**

```bash
godot --headless --script res://tools/generate_material_glsl.gd
```

- [ ] **Step 5: Verify** `MAT_COUNT` is now 26 and the new materials appear in the generated GLSL.

- [ ] **Step 6: Commit.**

```bash
git add src/autoload/material_registry.gd shaders/generated/materials.glslinc
git commit -m "feat(materials): register powders, wardstone, void_stone, destruction distributions"
```

---

## Task 5: Emit `DESTRUCTION_TABLE` and `INDESTRUCTIBLE` constants

**Files:**
- Modify: `tools/generate_material_glsl.gd`

Generate per-material 256-entry int arrays plus an indestructible bool array.

- [ ] **Step 1: Locate the existing emit logic.**

```bash
grep -n "MATERIAL_TINT\|IGNITION_TEMP\|MAT_COUNT" tools/generate_material_glsl.gd
```

- [ ] **Step 2: Add the new emit blocks.**

```gdscript
# After existing const emits, before EOF:
out.append("const int DESTRUCTION_TABLE[%d][256] = int[][](" % materials.size())
for i in range(materials.size()):
    var mat: MaterialRegistry.MaterialDef = materials[i]
    var table: PackedInt32Array = _build_destruction_table(mat.destruction_distribution)
    var row := "    int[256](" + ",".join(table.map(func(v): return str(v))) + ")"
    if i < materials.size() - 1:
        row += ","
    out.append(row)
out.append(");")

out.append("const bool INDESTRUCTIBLE[%d] = bool[%d](" % [materials.size(), materials.size()])
for i in range(materials.size()):
    var mat: MaterialRegistry.MaterialDef = materials[i]
    var s := "true" if mat.indestructible else "false"
    if i < materials.size() - 1:
        s += ","
    out.append("    " + s)
out.append(");")

# Helper:
func _build_destruction_table(dist: Dictionary) -> PackedInt32Array:
    var table := PackedInt32Array()
    table.resize(256)
    var idx := 0
    for mat_id in dist.keys():
        var prob: float = dist[mat_id]
        var count := int(round(prob * 256.0))
        for _i in range(count):
            if idx >= 256: break
            table[idx] = int(mat_id)
            idx += 1
    # Fill any remainder with MAT_AIR (idx 0).
    while idx < 256:
        table[idx] = 0
        idx += 1
    return table
```

- [ ] **Step 3: Run, inspect output.**

```bash
godot --headless --script res://tools/generate_material_glsl.gd
grep -A2 "DESTRUCTION_TABLE\[" shaders/generated/materials.glslinc | head -20
```

- [ ] **Step 4: Commit.**

```bash
git add tools/generate_material_glsl.gd shaders/generated/materials.glslinc
git commit -m "feat(materials): emit DESTRUCTION_TABLE and INDESTRUCTIBLE in materials.glslinc"
```

---

## Task 6: Branchless destruction lookup in terrain_modifier

**Files:**
- Modify: `src/core/terrain_modifier.gd`

Replace every site where a destroyed cell becomes `MAT_AIR` with the table lookup. Honor `INDESTRUCTIBLE`.

- [ ] **Step 1: Find destruction sites.**

```bash
grep -n "MAT_AIR\|destroy\|health.*0" src/core/terrain_modifier.gd
```

- [ ] **Step 2: Add the helper at the top of terrain_modifier.gd:**

```gdscript
func _resolve_destruction(mat_id: int, world_pos: Vector2i) -> int:
    if MaterialRegistry.materials[mat_id].indestructible:
        return mat_id
    var hash_byte := (hash(world_pos) & 0xFF) as int
    var table: PackedInt32Array = MaterialRegistry.materials[mat_id].destruction_table_cache
    return table[hash_byte]
```

For this to work, materials need a precomputed `destruction_table_cache: PackedInt32Array` mirror of what the GLSL emit does. Add it as a method on `MaterialRegistry`:

```gdscript
# In material_registry.gd, after _init_materials():
for mat in materials:
    mat.destruction_table_cache = _build_destruction_table_for(mat.destruction_distribution)

func _build_destruction_table_for(dist: Dictionary) -> PackedInt32Array:
    # Same logic as generate_material_glsl.gd's _build_destruction_table.
    var table := PackedInt32Array(); table.resize(256)
    var idx := 0
    for mat_id in dist.keys():
        var count := int(round(float(dist[mat_id]) * 256.0))
        for _i in range(count):
            if idx >= 256: break
            table[idx] = int(mat_id); idx += 1
    while idx < 256: table[idx] = 0; idx += 1
    return table
```

- [ ] **Step 3: Replace each `MAT_AIR` destruction write** with `_resolve_destruction(mat_id, world_pos)`.

- [ ] **Step 4: Also update GPU-side destruction paths** if the sim shader has them. Check `shaders/include/sim/` for cells transitioning to AIR on health==0:

```bash
grep -rn "MAT_AIR\|make_pixel(0" shaders/include/sim/
```

Replace with `DESTRUCTION_TABLE[mat][hash_byte]` lookup. Use `simple_hash(pos)` or similar utility — check `simplex_2d.glslinc` or `cave_utils.glslinc` for an existing hash function.

- [ ] **Step 5: Commit.**

```bash
git add -A
git commit -m "feat(destruction): branchless DESTRUCTION_TABLE lookup at all destroy sites"
```

---

## Task 7: Test — destruction debris distribution

**Files:**
- Create: `tests/unit/test_destruction_debris.gd`

- [ ] **Step 1: Write the test.**

```gdscript
# tests/unit/test_destruction_debris.gd
extends GdUnitTestSuite

func test_stone_yields_40pct_sand_dust() -> void:
    var counts := {MaterialRegistry.MAT_SAND_DUST: 0, MaterialRegistry.MAT_AIR: 0}
    var table: PackedInt32Array = MaterialRegistry.materials[MaterialRegistry.MAT_STONE].destruction_table_cache
    for byte in range(256):
        var result := table[byte]
        if not counts.has(result): counts[result] = 0
        counts[result] += 1
    var sand_frac := float(counts[MaterialRegistry.MAT_SAND_DUST]) / 256.0
    assert_that(sand_frac).is_between(0.38, 0.42)

func test_wardstone_destruction_returns_self() -> void:
    # Indestructible: simulate the resolve_destruction path
    var wm: Node = preload("res://scenes/world_manager.tscn").instantiate()
    add_child(wm)
    var tm: TerrainModifier = wm.terrain_modifier
    var result := tm._resolve_destruction(MaterialRegistry.MAT_WARDSTONE, Vector2i(0, 0))
    assert_that(result).is_equal(MaterialRegistry.MAT_WARDSTONE)
    wm.queue_free()
```

- [ ] **Step 2: Run, expect PASS.**

- [ ] **Step 3: Commit.**

```bash
git add tests/unit/test_destruction_debris.gd
git commit -m "test(destruction): table distributions and indestructibility"
```

---

## Task 8: Powder sim stage

**Files:**
- Create: `shaders/include/powder_stage.glslinc`
- Modify: sim shader main

Static piles. Per cell:
- If not powder: ignore.
- If neighbor has `temperature >= 100` and powder is ice → decrement health, cool neighbor by 20, convert to water at health==0.
- No autonomous motion. Dispersal is handled by the existing arc functions; explode wave handling in `stage_explode_wave` already accounts for pushing.

- [ ] **Step 1: Create the stage.**

```glsl
// shaders/include/powder_stage.glslinc

void stage_powder(ivec2 pos) {
    vec4 cur = imageLoad(chunk_tex, pos);
    int mat = int(round(cur.r * 255.0));
    if (mat != MAT_ICE_POWDER && mat != MAT_SAND_DUST) return;

    if (mat == MAT_ICE_POWDER) {
        // Check 4-neighbors for high temp.
        int max_neighbor_temp = 0;
        ivec2 hot_neighbor = ivec2(-1, -1);
        for (int d = 0; d < 4; d++) {
            ivec2 n = pos;
            if (d == 0) n.x -= 1;
            else if (d == 1) n.x += 1;
            else if (d == 2) n.y -= 1;
            else n.y += 1;
            if (n.x < 0 || n.x >= 256 || n.y < 0 || n.y >= 256) continue;
            vec4 ncur = imageLoad(chunk_tex, n);
            int nt = int(round(ncur.b * 255.0));
            if (nt > max_neighbor_temp) {
                max_neighbor_temp = nt;
                hot_neighbor = n;
            }
        }
        if (max_neighbor_temp >= 100) {
            int health = int(round(cur.g * 255.0));
            health -= 1;
            // Cool the hot neighbor by 20.
            if (hot_neighbor.x >= 0) {
                vec4 ncur = imageLoad(chunk_tex, hot_neighbor);
                int nt = int(round(ncur.b * 255.0));
                nt = max(0, nt - 20);
                ncur.b = float(nt) / 255.0;
                imageStore(chunk_tex, hot_neighbor, ncur);
            }
            if (health <= 0) {
                imageStore(chunk_tex, pos, make_pixel(MAT_WATER, 0, 0));
            } else {
                cur.g = float(health) / 255.0;
                imageStore(chunk_tex, pos, cur);
            }
        }
    }
    // MAT_SAND_DUST is fully inert; no per-tick work.
}
```

- [ ] **Step 2: Add `stage_powder(pos)` call in sim shader main**, alongside other sim stages.

- [ ] **Step 3: Update melee swing dispersal** to include powder material IDs. Locate the call sites of `clear_and_push_materials_in_arc` and `disperse_materials_in_arc` in weapon code; add powder IDs to the materials array:

```gdscript
# Example update in weapon code:
var dispersible: Array[int] = [
    MaterialRegistry.MAT_GAS,
    MaterialRegistry.MAT_ICE_POWDER,
    MaterialRegistry.MAT_SAND_DUST,
]
wm.disperse_materials_in_arc(origin, direction, radius, arc, push_speed, dispersible)
```

- [ ] **Step 4: Commit.**

```bash
git add -A
git commit -m "feat(sim): powder stage + dispersal integration"
```

---

## Task 9: Test — powder dispersal and melt

**Files:**
- Create: `tests/unit/test_powder_dispersal.gd`

- [ ] **Step 1: Write the test.**

```gdscript
# tests/unit/test_powder_dispersal.gd
extends GdUnitTestSuite

func test_ice_powder_melts_near_lava() -> void:
    var wm: Node2D = preload("res://scenes/world_manager.tscn").instantiate()
    add_child(wm)
    wm.tracking_position = Vector2.ZERO
    await get_tree().process_frame; await get_tree().process_frame

    var origin := Vector2i(40, 40)
    for y in range(5):
        for x in range(5):
            wm.terrain_modifier.place_material(Vector2(origin.x + x, origin.y + y), 0.5, MaterialRegistry.MAT_ICE_POWDER)
    wm.terrain_modifier.place_lava(Vector2(origin.x - 1, origin.y), 0.5)

    for _i in range(200):
        await get_tree().process_frame

    var rect := Rect2i(origin - Vector2i(1, 1), Vector2i(7, 7))
    var data := wm.read_region(rect)
    var ice_remaining := 0
    var water_count := 0
    for i in range(data.size()):
        if data[i] == MaterialRegistry.MAT_ICE_POWDER: ice_remaining += 1
        if data[i] == MaterialRegistry.MAT_WATER: water_count += 1
    assert_that(ice_remaining).is_less_equal(5)
    assert_that(water_count).is_greater(0)
    wm.queue_free()

func test_sand_dust_static_until_swing() -> void:
    var wm: Node2D = preload("res://scenes/world_manager.tscn").instantiate()
    add_child(wm)
    wm.tracking_position = Vector2.ZERO
    await get_tree().process_frame; await get_tree().process_frame

    var center := Vector2(60, 60)
    for y in range(4):
        for x in range(4):
            wm.terrain_modifier.place_material(center + Vector2(x, y), 0.5, MaterialRegistry.MAT_SAND_DUST)

    var before := wm.read_region(Rect2i(58, 58, 8, 8)).duplicate()
    for _i in range(60):
        await get_tree().process_frame
    var after := wm.read_region(Rect2i(58, 58, 8, 8))
    assert_that(after).is_equal(before)  # static, no drift

    # Now disperse via arc.
    wm.disperse_materials_in_arc(center + Vector2(2, 2), Vector2.RIGHT, 8.0, 1.5, 50.0, [MaterialRegistry.MAT_SAND_DUST])
    await get_tree().process_frame
    var post_swing := wm.read_region(Rect2i(58, 58, 8, 8))
    assert_that(post_swing).is_not_equal(before)
    wm.queue_free()
```

- [ ] **Step 2: Run, expect PASS.**

- [ ] **Step 3: Commit.**

```bash
git add tests/unit/test_powder_dispersal.gd
git commit -m "test(sim): powder melt and dispersal behavior"
```

---

## Task 10: PropDef / EntityPropDef resources

**Files:**
- Create: `src/core/prop_def.gd`, `src/core/entity_prop_def.gd`

- [ ] **Step 1: Create `prop_def.gd`.**

```gdscript
# src/core/prop_def.gd
class_name PropDef
extends Resource

@export var material_id: int = 0
@export var noise_scale: float = 0.02
@export var noise_threshold: float = 0.85
@export var seed_offset: int = 0
```

- [ ] **Step 2: Create `entity_prop_def.gd`.**

```gdscript
# src/core/entity_prop_def.gd
class_name EntityPropDef
extends Resource

@export var scene: PackedScene
@export var poisson_mean: float = 0.5  # average count per chunk
@export var footprint_size: int = 8    # validation probe size in px
```

- [ ] **Step 3: Add fields to BiomeDef.**

```gdscript
# src/core/biome_def.gd
@export var prop_pools: Array[PropDef] = []
@export var entity_prop_pool: Array[EntityPropDef] = []
```

- [ ] **Step 4: Commit.**

```bash
git add src/core/prop_def.gd src/core/entity_prop_def.gd src/core/biome_def.gd
git commit -m "feat(biomes): PropDef / EntityPropDef resources"
```

---

## Task 11: Populate biome prop pools

**Files:**
- Modify: `assets/biomes/*.tres`

Per the spec mapping table:

| Prop | caves | mines | magma | frozen | vault |
|---|---|---|---|---|---|
| Lava pool | — | — | 4% | — | — |
| Oil pool | — | 2% | — | — | 1% |
| Water pond | 2% | 1% | — | — | — |
| Gas pool | 1% | 3% | 1% | — | 2% |
| Ice powder | — | — | — | 4% | — |
| Sand/dust | 1% | — | — | — | — |
| Wooden pillar | — | 2/chunk | — | — | — |
| Explosive box | 0.5 | 1 | 0.5 | 0.5 | 1 |
| Oil barrel | 0.3 | 1 | 0.3 | — | 0.5 |

Convert percentages to noise thresholds empirically: a single octave simplex with scale=0.05 at threshold T produces approximately `1 - T` coverage. So 4% coverage → threshold 0.96; 2% → 0.98; 1% → 0.99; 3% → 0.97.

- [ ] **Step 1: For each biome .tres**, open in editor and:
  - Set `prop_pools` per the table — each entry is a `PropDef` with the right material and threshold.
  - Set `entity_prop_pool` per the table — each entry is an `EntityPropDef` with the prop scene and `poisson_mean`.

- [ ] **Step 2: Commit per biome.**

```bash
git add assets/biomes/<biome>.tres
git commit -m "feat(biomes): populate prop_pools for <biome>"
```

---

## Task 12: Wooden pillar scene

**Files:**
- Create: `scenes/props/wooden_pillar.tscn`, `src/drops/wooden_pillar.gd`

- [ ] **Step 1: Author scene.** StaticBody2D with 12×12 sprite, collision, script.

```gdscript
# src/drops/wooden_pillar.gd
class_name WoodenPillar
extends StaticBody2D

@export var max_health: int = 3
var health: int

func _ready() -> void:
    health = max_health
    add_to_group("destructible_prop")

func take_damage(amount: int) -> void:
    health -= amount
    if health <= 0:
        queue_free()
```

- [ ] **Step 2: Commit.**

```bash
git add scenes/props/wooden_pillar.tscn src/drops/wooden_pillar.gd
git commit -m "feat(props): wooden pillar scene"
```

---

## Task 13: Material props stage

**Files:**
- Create: `shaders/include/biome_props_stage.glslinc`
- Modify: gen shaders main and dispatch loop

Runs after `stage_walkability_enforce` finishes (i.e. after the JFA refresh post-dilate). Iterates each prop in `biome.prop_pools` (a new array bound alongside `biome.pools`), evaluates noise, stamps material if eligible.

- [ ] **Step 1: Extend the biome buffer** to carry `prop_pools` (e.g. 6 entries: `vec4 prop_pools[6]`, same packing as existing pools). Update `compute_device.upload_biome_buffer` to populate them from `biome.prop_pools`.

- [ ] **Step 2: Create the stage.**

```glsl
// shaders/include/biome_props_stage.glslinc

void stage_biome_props(ivec2 pos, Context ctx) {
    vec4 cur = imageLoad(chunk_tex, pos);
    int mat = int(round(cur.r * 255.0));
    if (mat != MAT_AIR) return;
    uvec4 flag = imageLoad(chunk_flags_tex, pos);
    if ((flag.r & 1u) != 0u) return;  // NO_PROPS

    vec2 world_pos = vec2(ctx.chunk_coord * 256) + vec2(pos);
    for (int i = 0; i < 6; i++) {
        vec4 p = biome.prop_pools[i];
        int prop_mat = int(round(p.x));
        if (prop_mat <= 0) continue;
        float scale = p.y;
        float thr = p.z;
        uint pseed = hash_combine(ctx.world_seed, uint(int(round(p.w)) + 7000));
        float n = simplex_fbm(world_pos * scale, pseed, 2);
        if (n > thr) {
            imageStore(chunk_tex, pos, make_pixel(prop_mat, 60, 0));
            return;
        }
    }
}
```

- [ ] **Step 3: Add a pass index for the props stage** in generation_simplex_cave.glsl, dispatched after all walkability passes complete (pass 322, just before the alpha-clear). Update Part 1's pass numbering: shift alpha-clear to pass 323, add props as pass 322.

```glsl
} else if (pass == 322) {
    stage_biome_props(pos, ctx);
} else if (pass == 323) {
    // (formerly 322) clear scratch alpha
    vec4 cur = imageLoad(chunk_tex, pos);
    cur.a = 0.0;
    imageStore(chunk_tex, pos, cur);
}
```

- [ ] **Step 4: Update compute_device dispatch loop** to run pass 322 and 323.

- [ ] **Step 5: Hand-test:** generate a few levels in each biome, confirm props appear at roughly expected density and never inside set-pieces or walkable pockets.

- [ ] **Step 6: Commit.**

```bash
git add -A
git commit -m "feat(gen): stage_biome_props scatters material props honoring NO_PROPS"
```

---

## Task 14: PropDispatcher — entity props

**Files:**
- Create: `src/core/prop_dispatcher.gd`
- Modify: scene tree to add `PropDispatcher` autoload or under WorldManager

- [ ] **Step 1: Write the dispatcher.**

```gdscript
# src/core/prop_dispatcher.gd
extends Node

const CHUNK_SIZE := 256

var _world_manager: Node = null
var _spawn_parent: Node = null

func _process(_delta: float) -> void:
    if _world_manager and is_instance_valid(_world_manager):
        return
    var wm := get_tree().get_first_node_in_group("world_manager")
    if wm == null: return
    _world_manager = wm
    _spawn_parent = wm.get_chunk_container()
    wm.chunks_generated.connect(_on_chunks_generated)

func _on_chunks_generated(new_coords: Array[Vector2i]) -> void:
    var biome: BiomeDef = LevelManager.current_biome
    if biome == null: return
    for chunk_coord in new_coords:
        for prop in biome.entity_prop_pool:
            var count := _sample_poisson(prop.poisson_mean)
            for _i in range(count):
                _try_place(prop, chunk_coord)

func _sample_poisson(mean: float) -> int:
    var L := exp(-mean)
    var k := 0
    var p := 1.0
    while true:
        k += 1
        p *= randf()
        if p <= L: break
    return k - 1

func _try_place(prop: EntityPropDef, chunk_coord: Vector2i) -> void:
    for _try in range(8):
        var lx := randi() % CHUNK_SIZE
        var ly := randi() % CHUNK_SIZE
        var world_pos := Vector2(chunk_coord.x * CHUNK_SIZE + lx, chunk_coord.y * CHUNK_SIZE + ly)
        if not _validate(world_pos, prop.footprint_size):
            continue
        var inst = prop.scene.instantiate()
        inst.global_position = world_pos
        _spawn_parent.add_child(inst)
        return

func _validate(world_pos: Vector2, size: int) -> bool:
    var half := size / 2
    var rect := Rect2i(Vector2i(world_pos) - Vector2i(half, half), Vector2i(size, size))
    var data := _world_manager.read_region(rect)
    if data.size() != size * size: return false
    for i in range(data.size()):
        if data[i] != MaterialRegistry.MAT_AIR: return false
    # Read flags too — requires read_region to also fetch flag bytes (Task 16).
    var flags := _world_manager.read_region_flags(rect)
    if flags.size() != size * size: return false
    for i in range(flags.size()):
        if (flags[i] & 1) != 0: return false
    return true
```

- [ ] **Step 2: Register as autoload** (Project Settings → AutoLoad → add `PropDispatcher` pointing to `prop_dispatcher.gd`).

- [ ] **Step 3: Commit (read_region_flags wiring next).**

```bash
git add src/core/prop_dispatcher.gd project.godot
git commit -m "feat(props): entity prop dispatcher hooks chunks_generated"
```

---

## Task 15: WorldManager.read_region_flags

**Files:**
- Modify: `src/core/world_manager.gd`

Mirror of `read_region` but reads from `chunk_flags_tex` instead of `chunk_tex`. Needs GDExtension support since the texture lives on GPU; pattern mirrors how `read_region` works for the material channel.

- [ ] **Step 1: Add the method.**

```gdscript
func read_region_flags(region: Rect2i) -> PackedByteArray:
    var width: int = region.size.x
    var height: int = region.size.y
    var result := PackedByteArray()
    result.resize(width * height)
    result.fill(0)

    var min_chunk := Vector2i(floori(float(region.position.x) / CHUNK_SIZE), floori(float(region.position.y) / CHUNK_SIZE))
    var max_chunk := Vector2i(floori(float(region.end.x - 1) / CHUNK_SIZE), floori(float(region.end.y - 1) / CHUNK_SIZE))

    for cx in range(min_chunk.x, max_chunk.x + 1):
        for cy in range(min_chunk.y, max_chunk.y + 1):
            var chunk_coord := Vector2i(cx, cy)
            if not chunks.has(chunk_coord): continue
            var chunk: Chunk = chunks[chunk_coord]
            var flag_data: PackedByteArray = rd.texture_get_data(chunk.flags_tex, 0)
            var chunk_origin := chunk_coord * CHUNK_SIZE
            var chunk_rect := Rect2i(chunk_origin, Vector2i(CHUNK_SIZE, CHUNK_SIZE))
            var overlap := region.intersection(chunk_rect)
            for y in range(overlap.position.y, overlap.end.y):
                for x in range(overlap.position.x, overlap.end.x):
                    var local_x: int = x - chunk_origin.x
                    var local_y: int = y - chunk_origin.y
                    var src_idx: int = local_y * CHUNK_SIZE + local_x  # R8 single byte per cell
                    result[(y - region.position.y) * width + (x - region.position.x)] = flag_data[src_idx]
    return result
```

For this to work, the `Chunk` struct (probably in the GDExtension side) must expose `flags_tex` as an RID accessible from GDScript. If not, add an accessor.

- [ ] **Step 2: Commit.**

```bash
git add src/core/world_manager.gd
git commit -m "feat(world): read_region_flags for chunk_flags_tex"
```

---

## Task 16: Test — prop density and conflict-mask correctness

**Files:**
- Create: `tests/unit/test_prop_density.gd`

- [ ] **Step 1: Write the test.**

```gdscript
# tests/unit/test_prop_density.gd
extends GdUnitTestSuite

const CHUNK_SIZE := 256

func test_props_respect_no_props_mask() -> void:
    var biome_idx := 1  # mines (has wooden pillars)
    LevelManager.current_biome = BiomeRegistry.biomes[biome_idx]
    LevelManager.world_seed = 42
    var wm: Node2D = preload("res://scenes/world_manager.tscn").instantiate()
    add_child(wm)
    wm.tracking_position = Vector2(CHUNK_SIZE * 3, CHUNK_SIZE * 3)
    for _i in range(40):
        await get_tree().process_frame

    for cx in range(2, 5):
        for cy in range(2, 5):
            var coord := Vector2i(cx, cy)
            if not wm.chunks.has(coord): continue
            var rect := Rect2i(coord * CHUNK_SIZE, Vector2i(CHUNK_SIZE, CHUNK_SIZE))
            var mats := wm.read_region(rect)
            var flags := wm.read_region_flags(rect)
            for i in range(mats.size()):
                var m := mats[i]
                if m == MaterialRegistry.MAT_AIR: continue
                if m == MaterialRegistry.MAT_STONE: continue
                # Otherwise it's a prop (oil/water/gas/etc). Assert NO_PROPS is NOT set.
                # (If it's set, the props stage was supposed to skip this cell.)
                if [MaterialRegistry.MAT_OIL, MaterialRegistry.MAT_WATER, MaterialRegistry.MAT_GAS, MaterialRegistry.MAT_LAVA, MaterialRegistry.MAT_ICE_POWDER, MaterialRegistry.MAT_SAND_DUST].has(m):
                    assert_that((flags[i] & 1)).is_equal(0)
    wm.queue_free()
```

- [ ] **Step 2: Run, expect PASS.**

- [ ] **Step 3: Commit.**

```bash
git add tests/unit/test_prop_density.gd
git commit -m "test(props): NO_PROPS mask is respected"
```

---

## Task 17: World boundary stage

**Files:**
- Create: `shaders/include/world_boundary_stage.glslinc`
- Modify: gen shaders main + dispatch loop

Runs first (gen pass index 0, before existing stages). Compute chunk's centroid sector; branch on distance:

- dist ≤ 10: do nothing (normal gen proceeds in later passes)
- 10 < dist < 11: fill cells at distance ≈ 10.5 with wardstone
- dist ≥ 11: fill entire chunk with void_stone, set a chunk_is_void flag

Chunk-level `chunk_is_void` shared via a 1-int SSBO that gets read in early-out checks in subsequent stages.

- [ ] **Step 1: Add the SSBO binding.**

```glsl
layout(std430, set = 0, binding = 5) buffer ChunkBoundaryState {
    int chunk_is_void;
} boundary;
```

Allocate as 4 bytes per chunk in compute_device.

- [ ] **Step 2: Create the stage.**

```glsl
// shaders/include/world_boundary_stage.glslinc

const int SECTOR_SIZE_PX = 384;
const int BOSS_RING_DIST = 10;

void stage_world_boundary(ivec2 pos, Context ctx) {
    // World-space coords of this cell.
    ivec2 world_pos = ctx.chunk_coord * 256 + pos;

    // Sector grid is centered at origin.
    ivec2 sector = ivec2(int(floor(float(world_pos.x) / float(SECTOR_SIZE_PX))),
                         int(floor(float(world_pos.y) / float(SECTOR_SIZE_PX))));
    int cheby = max(abs(sector.x), abs(sector.y));

    if (cheby >= 11) {
        imageStore(chunk_tex, pos, make_pixel(MAT_VOID_STONE, 255, 0));
        // First thread sets the flag.
        if (pos.x == 0 && pos.y == 0) {
            atomicMax(boundary.chunk_is_void, 1);
        }
        return;
    }

    if (cheby == 10) {
        // Wardstone band — cells whose sector-fractional distance lands near 0.5.
        // Compute fractional sector position; cells near the outer edge of sector 10 (toward sector 11) get wardstone.
        ivec2 sector_local = world_pos - sector * SECTOR_SIZE_PX;
        int dx_to_outer = (sector.x >= 0) ? (SECTOR_SIZE_PX - 1 - sector_local.x) : sector_local.x;
        int dy_to_outer = (sector.y >= 0) ? (SECTOR_SIZE_PX - 1 - sector_local.y) : sector_local.y;
        int outer_dist = max(0, min(dx_to_outer, dy_to_outer));
        if (outer_dist < 32) {
            imageStore(chunk_tex, pos, make_pixel(MAT_WARDSTONE, 255, 0));
        }
    }
}
```

- [ ] **Step 3: Wire as first stage in pass 0.** In generation_simplex_cave.glsl main:

```glsl
if (push_ctx.gen_pass_idx == 0) {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= 256 || pos.y >= 256) return;
    imageStore(chunk_flags_tex, pos, uvec4(0));
    Context ctx;
    ctx.chunk_coord = push_ctx.chunk_coord;
    ctx.world_seed = push_ctx.world_seed;

    stage_world_boundary(pos, ctx);
    if (boundary.chunk_is_void != 0) return;  // early-out for void chunks

    stage_stone_fill(ctx);
    stage_simplex_cave(ctx);
    // (pools, stamps, etc. — preserve WARDSTONE cells by checking mat != MAT_WARDSTONE before overwriting)
    return;
}
```

- [ ] **Step 4: Clear the boundary buffer before each chunk gen** in compute_device:

```cpp
int zero = 0;
rd->buffer_update(chunk.boundary_buf, 0, sizeof(int), &zero);
```

- [ ] **Step 5: Protect wardstone in subsequent stages** — add a guard at the start of each stamp/pool/prop stage:

```glsl
vec4 cur = imageLoad(chunk_tex, pos);
if (int(round(cur.r * 255.0)) == MAT_WARDSTONE) return;
```

- [ ] **Step 6: Hand-test:** walk to sector boundary in-game, confirm wardstone ring is visible and impassable, and beyond it the world is solid void-stone.

- [ ] **Step 7: Commit.**

```bash
git add -A
git commit -m "feat(gen): world boundary - wardstone ring + void-stone fill"
```

---

## Task 18: Indestructibility guard in terrain_modifier

**Files:**
- Modify: `src/core/terrain_modifier.gd`

Already added in Task 6, but verify it covers wardstone and void_stone. Add a regression test.

- [ ] **Step 1: Confirm `_resolve_destruction` returns the material itself when `indestructible` is true.** (Verified by Task 7 test, but extend it now to also check VOID_STONE.)

- [ ] **Step 2: Add a hand-test:** apply explode wave to a wardstone cell in-game, confirm no change.

- [ ] **Step 3: Commit if any changes made.**

---

## Task 19: Test — world boundary

**Files:**
- Create: `tests/unit/test_world_boundary.gd`

- [ ] **Step 1: Write the test.**

```gdscript
# tests/unit/test_world_boundary.gd
extends GdUnitTestSuite

const SECTOR_SIZE := 384
const CHUNK_SIZE := 256

func test_void_beyond_distance_11() -> void:
    var wm: Node2D = preload("res://scenes/world_manager.tscn").instantiate()
    add_child(wm)
    # Track at sector (12, 12) which is in the void zone.
    wm.tracking_position = Vector2(SECTOR_SIZE * 12, SECTOR_SIZE * 12)
    for _i in range(40):
        await get_tree().process_frame

    var probe_pos := Vector2i(SECTOR_SIZE * 12, SECTOR_SIZE * 12)
    var data := wm.read_region(Rect2i(probe_pos, Vector2i(16, 16)))
    for v in data:
        assert_that(v).is_equal(MaterialRegistry.MAT_VOID_STONE)
    wm.queue_free()

func test_wardstone_ring_present_at_boundary() -> void:
    var wm: Node2D = preload("res://scenes/world_manager.tscn").instantiate()
    add_child(wm)
    wm.tracking_position = Vector2(SECTOR_SIZE * 10, 0)
    for _i in range(40):
        await get_tree().process_frame

    # Probe a thin column straddling the wardstone band at the outer edge of sector 10.
    var found_wardstone := false
    var probe_x := SECTOR_SIZE * 11 - 8  # 8 px inside the outer edge of sector 10
    for y in range(0, SECTOR_SIZE, 4):
        var cell := wm.read_region(Rect2i(probe_x, y, 1, 1))
        if cell[0] == MaterialRegistry.MAT_WARDSTONE:
            found_wardstone = true
            break
    assert_that(found_wardstone).is_true()
    wm.queue_free()
```

- [ ] **Step 2: Run, expect PASS.**

- [ ] **Step 3: Commit.**

```bash
git add tests/unit/test_world_boundary.gd
git commit -m "test(gen): world boundary - wardstone ring + void zone"
```

---

## Task 20: Final hand-playtest pass

Walk through every biome from a fresh run; confirm:

- [ ] Props are scattered visibly through caves (lava pools in magma, oil pools in mines, etc.)
- [ ] Wooden pillars dot the mines biome at ~2/chunk
- [ ] Explosive barrels are placeable, ignitable, and produce a clean expanding ring
- [ ] Oil barrels leak oil on damage, ignite on lava contact
- [ ] Carving through stone leaves visible sand-dust trails (~40%)
- [ ] Carving through frozen rock leaves ice-powder that melts near torches/lava
- [ ] At the world boundary, wardstone ring is unmistakable and uncrossable
- [ ] No props clip into boss arenas, elite chest rooms, or guaranteed walkable pockets
- [ ] All previous tests (`test_walkability_*`, `test_oil_chain`, `test_explode_wave_shell`, `test_powder_dispersal`, `test_prop_density`, `test_destruction_debris`, `test_world_boundary`) still pass

- [ ] **Step 1: Run the full test suite.**

```bash
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/
```

- [ ] **Step 2: Final commit if any tweaks were needed.**

---

## Done Criteria

- [ ] All new unit tests pass
- [ ] World boundary is impassable; players can't walk past sector ring 11
- [ ] Carving leaves debris trails; ice melts into water; oil chains via fire and explode waves
- [ ] Props scatter in cave chunks at expected density, never in protected regions
- [ ] Per-chunk gen time delta < 5 ms over Part 1's baseline
