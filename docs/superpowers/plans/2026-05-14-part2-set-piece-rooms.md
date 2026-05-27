# Part 2: Set-Piece Rooms — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace lame boss/elite-chest/secret set-pieces with distinct, recognizable encounters. Boss arenas become 512-px crenellated landmarks; elite chest rooms become open chambers in the regular template pool; secret chests embed in solid terrain with a cracked-wall hint. Introduces `MAT_OIL` and `MAT_EXPLODE_WAVE`.

**Architecture:** Material registry extension (10 new materials), oil flow + temperature-driven burning piggybacking on the existing liquid sim, a brand-new `stage_explode_wave` for the radial-shell wave, expanded spawn markers (8–13) in `spawn_dispatcher`, new scenes for barrel/box/vent entities, and per-biome authored PNGs.

**Tech Stack:** Godot 4, GDScript, GLSL compute shaders, image-editor for PNG authoring, GdUnit4.

**Dependency:** Part 1 must be merged. Part 2 builds on the alpha-scratch pattern but does not extend it.

---

## File Structure

**New:**
- `shaders/include/explode_wave_stage.glslinc` — wave radial-shell sim
- `shaders/include/sim/oil.glslinc` — oil flow + burning behavior (mirrors `lava.glslinc`)
- `assets/rooms/<biome>/boss_arena_a.png` … `_d.png` (20 PNGs at 512×512)
- `assets/rooms/<biome>/elite_chest_a.png` … `_c.png` (15 PNGs at 256×256)
- `assets/rooms/<biome>/secret_a.png` (5 PNGs re-authored)
- `scenes/props/explosive_barrel.tscn`
- `scenes/props/oil_barrel.tscn`
- `scenes/props/gas_vent.tscn`
- `src/drops/explosive_barrel.gd`, `src/drops/oil_barrel.gd`, `src/drops/gas_vent.gd`
- `tests/unit/test_oil_chain.gd`, `tests/unit/test_explode_wave_shell.gd`

**Modified:**
- `src/autoload/material_registry.gd` — register 10 new materials
- `tools/generate_material_glsl.gd` — regenerate `shaders/generated/materials.glslinc`
- `src/core/room_template.gd` — add `is_elite_chest: bool`
- `src/core/biome_def.gd` — add `cracked_material: int`, `perimeter_material: int`, `elite_chest_templates` (optional, see Task 15)
- `assets/biomes/*.tres` — wire new fields and templates
- `src/core/sector_grid.gd` — no algorithmic change; uses the larger boss-template array
- `src/core/spawn_dispatcher.gd` — handle markers 8–13
- `shaders/include/secret_ring_stage.glslinc` — DELETED
- `shaders/include/pixel_scene_stamp.glslinc` — secret-stamp solid-validation
- `shaders/compute/<sim shader>` — add `stage_explode_wave` and oil handling

---

## Task 1: Register new materials in the registry

**Files:**
- Modify: `src/autoload/material_registry.gd`

Add 10 new materials in `_init_materials()`. Each follows the pattern of existing entries.

- [ ] **Step 1: Add `indestructible: bool = false` parameter to `MaterialDef._init()`** (default false; old call sites unchanged).

```gdscript
class MaterialDef:
    var indestructible: bool = false
    # ... existing fields ...

    func _init(
        # ... existing params ...
        p_indestructible: bool = false
    ):
        # ... existing assignments ...
        indestructible = p_indestructible
```

- [ ] **Step 2: Append new material registrations** at the end of `_init_materials()`:

```gdscript
# OIL — fluid; non-flammable in base state (ignites by direct contact only)
var mat_oil := MaterialDef.new(
    "OIL", "",
    false, 0, 60,   # not auto-ignitable; burn_health=60 = 60-tick burn lifetime
    false, false,
    Color(0.10, 0.06, 0.04, 1.0),
    true,           # fluid
    0, 1.0, 0.0
)
mat_oil.id = materials.size()
materials.append(mat_oil)
MAT_OIL = mat_oil.id

# EXPLODE_WAVE — custom sim, transient
var mat_explode := MaterialDef.new(
    "EXPLODE_WAVE", "",
    false, 0, 0,
    false, false,
    Color(1.0, 0.95, 0.5, 1.0),
    false,
    0, 30.0, 0.0
)
mat_explode.id = materials.size()
materials.append(mat_explode)
MAT_EXPLODE_WAVE = mat_explode.id

# Per-biome perimeter accents (5)
var perim_specs := [
    {"name": "STONE_BRICKS", "tint": Color(0.55, 0.55, 0.58, 1.0)},
    {"name": "WOOD_BEAM",    "tint": Color(0.45, 0.30, 0.18, 1.0)},
    {"name": "OBSIDIAN",     "tint": Color(0.10, 0.08, 0.15, 1.0)},
    {"name": "PACKED_ICE",   "tint": Color(0.78, 0.90, 0.98, 1.0)},
    {"name": "ENGRAVED_METAL", "tint": Color(0.65, 0.62, 0.45, 1.0)},
]
for spec in perim_specs:
    var m := MaterialDef.new(
        spec.name, "",
        false, 0, 0,
        true, true,           # solid, wall-extension
        spec.tint,
        false, 0, 1.0, 5.0
    )
    m.id = materials.size()
    materials.append(m)
    set("MAT_" + spec.name, m.id)

# Per-biome cracked variants (5)
var cracked_specs := [
    {"name": "STONE_CRACKED",    "tint": Color(0.50, 0.50, 0.52, 1.0)},
    {"name": "MINE_STONE_CRACKED", "tint": Color(0.42, 0.36, 0.28, 1.0)},
    {"name": "MAGMA_STONE_CRACKED", "tint": Color(0.40, 0.20, 0.15, 1.0)},
    {"name": "FROZEN_ROCK_CRACKED", "tint": Color(0.62, 0.78, 0.88, 1.0)},
    {"name": "VAULT_METAL_CRACKED", "tint": Color(0.60, 0.58, 0.42, 1.0)},
]
for spec in cracked_specs:
    var m := MaterialDef.new(
        spec.name, "",
        false, 0, 0,
        true, true,
        spec.tint,
        false, 0, 1.0, 4.0
    )
    m.id = materials.size()
    materials.append(m)
    set("MAT_" + spec.name, m.id)
```

- [ ] **Step 3: Declare the new MAT_ vars at the top of the registry file** alongside existing ones (otherwise `set()` will create them dynamically but they won't be statically reachable):

```gdscript
var MAT_OIL: int
var MAT_EXPLODE_WAVE: int
var MAT_STONE_BRICKS: int
var MAT_WOOD_BEAM: int
var MAT_OBSIDIAN: int
var MAT_PACKED_ICE: int
var MAT_ENGRAVED_METAL: int
var MAT_STONE_CRACKED: int
var MAT_MINE_STONE_CRACKED: int
var MAT_MAGMA_STONE_CRACKED: int
var MAT_FROZEN_ROCK_CRACKED: int
var MAT_VAULT_METAL_CRACKED: int
```

- [ ] **Step 4: Run the material-glsl regen tool.**

```bash
godot --headless --script res://tools/generate_material_glsl.gd
```

- [ ] **Step 5: Open the project, confirm the registry loads without errors, and `MAT_COUNT` in `shaders/generated/materials.glslinc` jumped from 10 to 22.**

- [ ] **Step 6: Commit.**

```bash
git add src/autoload/material_registry.gd shaders/generated/materials.glslinc
git commit -m "feat(materials): register oil, explode_wave, perimeter and cracked variants"
```

---

## Task 2: Oil fluid sim

**Files:**
- Create: `shaders/include/sim/oil.glslinc`
- Modify: `shaders/compute/simulation.glsl` (or whichever shader includes the per-cell sim main)

Mirror `lava.glslinc`'s structure (`get_density_*`, `unpack_velocity_*`, `pack_*`, `simulate_*`). Key differences for oil:

- `is_solid_for_oil(mat)` should treat lava as solid (oil floats on lava? per design oil pools against lava — treat lava as solid). Treat water as solid too (water and oil don't mix in this game).
- **No heat diffusion from neighbors.** Oil's temperature only rises via direct contact with `MAT_LAVA`, `MAT_FIRE`, or being entered by `MAT_EXPLODE_WAVE`. Per-tick: scan 4-neighbors; if any is MAT_LAVA or MAT_FIRE, set temperature to max(current, 220).
- **Burning behavior:** if `temperature >= 200`, decrement health by 1 per tick. Spawn `MAT_FIRE` in adjacent AIR cells. When `health == 0`, replace cell with `MAT_EXPLODE_WAVE` packing temperature=30.

- [ ] **Step 1: Create `shaders/include/sim/oil.glslinc`** by copying `lava.glslinc` as a starting template and editing material refs from `MAT_LAVA` → `MAT_OIL`. Replace the temperature-mixing block with:

```glsl
// Oil temperature update: no diffusion, only direct ignition contact.
int new_temp = temperature;
if (n_mat_up == MAT_LAVA || n_mat_up == MAT_FIRE)    new_temp = max(new_temp, 220);
if (n_mat_down == MAT_LAVA || n_mat_down == MAT_FIRE) new_temp = max(new_temp, 220);
if (n_mat_left == MAT_LAVA || n_mat_left == MAT_FIRE) new_temp = max(new_temp, 220);
if (n_mat_right == MAT_LAVA || n_mat_right == MAT_FIRE) new_temp = max(new_temp, 220);

// Burning behavior.
int new_health = (material == MAT_OIL) ? int(round(pixel.g * 255.0)) : 60;  // re-use G for health while burning
if (new_temp >= 200) {
    new_health -= 1;
    // Emit fire in adjacent air cells (using existing helper if one exists; else write directly).
    if (n_mat_up == MAT_AIR)    imageStore(chunk_tex, pos + ivec2(0, -1), make_pixel(MAT_FIRE, 200, 0));
    if (n_mat_down == MAT_AIR)  imageStore(chunk_tex, pos + ivec2(0, 1),  make_pixel(MAT_FIRE, 200, 0));
    if (n_mat_left == MAT_AIR)  imageStore(chunk_tex, pos + ivec2(-1, 0), make_pixel(MAT_FIRE, 200, 0));
    if (n_mat_right == MAT_AIR) imageStore(chunk_tex, pos + ivec2(1, 0),  make_pixel(MAT_FIRE, 200, 0));
}
if (new_health <= 0) {
    imageStore(chunk_tex, pos, make_pixel(MAT_EXPLODE_WAVE, 0, 30));
    return;
}
```

- [ ] **Step 2: Include `oil.glslinc` in the sim shader and call `simulate_oil` in the main sim entry-point.** The pattern matches `simulate_lava`'s call site.

- [ ] **Step 3: Hand-test:** place an oil pool in-game (use console command if available, otherwise modify a test scene). Confirm oil flows like lava but in dark amber color, and ignites on lava contact, leaving a fire trail.

- [ ] **Step 4: Commit.**

```bash
git add shaders/include/sim/oil.glslinc shaders/compute/
git commit -m "feat(sim): oil fluid + temperature-driven burning"
```

---

## Task 3: Explode wave radial-shell sim

**Files:**
- Create: `shaders/include/explode_wave_stage.glslinc`
- Modify: sim shader main

The wave's "shell" semantics: each frame, each `MAT_EXPLODE_WAVE` cell either (a) propagates to its 8 air neighbors with power decremented by 4, or (b) reverts to MAT_AIR. The cell itself doesn't persist beyond 1 tick.

Implementation challenge: we need to avoid double-writes when two wave cells try to propagate into the same neighbor. Use a two-phase approach within the sim tick: phase 1 = "claim" neighbor cells via atomic; phase 2 = "decay self" if claimed-power matches.

Simpler: each AIR cell pulls from its 8 wave neighbors, picks the max-power one minus 4, and becomes a wave cell with that power. Each wave cell on the same tick becomes AIR. Then damage/temperature effects apply based on its old power.

- [ ] **Step 1: Write the stage.**

```glsl
// shaders/include/explode_wave_stage.glslinc
//
// Radial-shell expansion. Each tick:
//   AIR cells with at least one MAT_EXPLODE_WAVE neighbor become wave cells
//   with power = max(neighbor_power) - DECAY. Wave cells revert to AIR.
//   Adjacent flammables get temperature += old_power.
//   Adjacent terrain takes (power) damage.

const int EXPLODE_WAVE_DECAY = 4;

void stage_explode_wave(ivec2 pos) {
    vec4 cur = imageLoad(chunk_tex, pos);
    int mat = int(round(cur.r * 255.0));

    if (mat == MAT_EXPLODE_WAVE) {
        int power = int(round(cur.b * 255.0));
        // Apply per-cell effects on the cells in our own footprint:
        //   - heat adjacent flammables
        for (int d = 0; d < 4; d++) {
            ivec2 n = pos;
            if (d == 0) n.x -= 1;
            else if (d == 1) n.x += 1;
            else if (d == 2) n.y -= 1;
            else n.y += 1;
            if (n.x < 0 || n.x >= 256 || n.y < 0 || n.y >= 256) continue;
            vec4 ncur = imageLoad(chunk_tex, n);
            int nmat = int(round(ncur.r * 255.0));
            if (IS_FLAMMABLE[nmat] || nmat == MAT_OIL) {
                int ntemp = int(round(ncur.b * 255.0));
                ntemp = min(255, ntemp + power);
                ncur.b = float(ntemp) / 255.0;
                imageStore(chunk_tex, n, ncur);
            }
            // Damage terrain (subtract power from health).
            int nhealth = int(round(ncur.g * 255.0));
            if (HAS_COLLIDER[nmat]) {
                nhealth = max(0, nhealth - power);
                ncur.g = float(nhealth) / 255.0;
                imageStore(chunk_tex, n, ncur);
            }
        }
        // Self decays to AIR.
        imageStore(chunk_tex, pos, make_pixel(MAT_AIR, 0, 0));
        return;
    }

    if (mat != MAT_AIR) return;

    // AIR: pull max-power wave from 8 neighbors.
    int best_power = 0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            ivec2 n = pos + ivec2(dx, dy);
            if (n.x < 0 || n.x >= 256 || n.y < 0 || n.y >= 256) continue;
            vec4 ncur = imageLoad(chunk_tex, n);
            int nmat = int(round(ncur.r * 255.0));
            if (nmat != MAT_EXPLODE_WAVE) continue;
            int np = int(round(ncur.b * 255.0));
            if (np > best_power) best_power = np;
        }
    }
    int new_power = best_power - EXPLODE_WAVE_DECAY;
    if (new_power > 0) {
        imageStore(chunk_tex, pos, make_pixel(MAT_EXPLODE_WAVE, 0, new_power));
    }
}
```

- [ ] **Step 2: Include and call in sim shader main**, before liquid stages (so waves resolve into AIR before fluids advect).

- [ ] **Step 3: Add entity-damage application.** When a wave cell exists at the player or an enemy's position, the entity takes damage equal to the wave's power. The cleanest hook is in the entity's `_process` (or whatever runs per physics frame): probe the world_manager for the cell at the entity's position, and if it's MAT_EXPLODE_WAVE, apply damage.

```gdscript
# Add to src/player/player.gd and src/enemies/enemy.gd in _physics_process:
var cell := WorldManager.read_cell(global_position)
if cell.material == MaterialRegistry.MAT_EXPLODE_WAVE:
    take_damage(cell.temperature)  # power packed in temperature byte
```

If `WorldManager.read_cell` doesn't exist, add it (a single-cell variant of `read_region`).

- [ ] **Step 4: Commit.**

```bash
git add -A
git commit -m "feat(sim): explode wave radial-shell expansion + entity damage"
```

---

## Task 4: Test — oil chain ignition

**Files:**
- Create: `tests/unit/test_oil_chain.gd`

- [ ] **Step 1: Write the test.**

```gdscript
# tests/unit/test_oil_chain.gd
extends GdUnitTestSuite

const CHUNK_SIZE := 256

func test_oil_ignites_from_lava_contact() -> void:
    var wm: Node2D = preload("res://scenes/world_manager.tscn").instantiate()
    add_child(wm)
    wm.tracking_position = Vector2.ZERO
    await get_tree().process_frame
    await get_tree().process_frame  # chunks ready

    # Place a 5x5 oil patch with one lava cell adjacent at (10, 10).
    var origin := Vector2i(50, 50)
    for y in range(5):
        for x in range(5):
            wm.terrain_modifier.place_material(Vector2(origin.x + x, origin.y + y), 0.5, MaterialRegistry.MAT_OIL)
    wm.terrain_modifier.place_lava(Vector2(origin.x - 1, origin.y), 0.5)

    # Step sim ~200 frames.
    for _i in range(200):
        await get_tree().process_frame

    # Check: all 25 oil cells should have either burned through to MAT_EXPLODE_WAVE or be MAT_AIR (post-wave).
    var rect := Rect2i(origin - Vector2i(1, 1), Vector2i(7, 7))
    var data := wm.read_region(rect)
    var oil_remaining := 0
    for y in range(rect.size.y):
        for x in range(rect.size.x):
            if data[y * rect.size.x + x] == MaterialRegistry.MAT_OIL:
                oil_remaining += 1
    assert_that(oil_remaining).is_less_equal(2)  # allow a couple stragglers due to flow
    wm.queue_free()
```

- [ ] **Step 2: Run, expect PASS.**

- [ ] **Step 3: Commit.**

```bash
git add tests/unit/test_oil_chain.gd
git commit -m "test(sim): oil chain ignition from lava contact"
```

---

## Task 5: Test — explode wave radial shell

**Files:**
- Create: `tests/unit/test_explode_wave_shell.gd`

- [ ] **Step 1: Write the test.**

```gdscript
# tests/unit/test_explode_wave_shell.gd
extends GdUnitTestSuite

func test_wave_forms_ring_not_disk() -> void:
    var wm: Node2D = preload("res://scenes/world_manager.tscn").instantiate()
    add_child(wm)
    wm.tracking_position = Vector2.ZERO
    await get_tree().process_frame
    await get_tree().process_frame

    var center := Vector2i(100, 100)
    # Seed a single wave cell with power 120.
    wm.terrain_modifier.place_material_with_temp(Vector2(center), 0.5, MaterialRegistry.MAT_EXPLODE_WAVE, 120)

    # After N ticks, wave should form a ring at Chebyshev radius N from center.
    for N in [3, 6, 10]:
        for _i in range(N):
            await get_tree().process_frame
        var rect := Rect2i(center - Vector2i(N + 2, N + 2), Vector2i(2 * N + 5, 2 * N + 5))
        var data := wm.read_region(rect)
        var wave_count := 0
        var center_air_count := 0
        for y in range(rect.size.y):
            for x in range(rect.size.x):
                var wx := rect.position.x + x
                var wy := rect.position.y + y
                var cheby := max(abs(wx - center.x), abs(wy - center.y))
                var mat := data[y * rect.size.x + x]
                if mat == MaterialRegistry.MAT_EXPLODE_WAVE:
                    wave_count += 1
                    # Wave cells should be at radius ~N
                    assert_that(cheby).is_between(N - 1, N + 1)
                if cheby < N - 1 and mat == MaterialRegistry.MAT_AIR:
                    center_air_count += 1
        assert_that(wave_count).is_greater(0)
        assert_that(center_air_count).is_greater(0)  # interior of the ring is AIR
    wm.queue_free()
```

You may need a small helper `terrain_modifier.place_material_with_temp` that writes a cell with a specified temperature byte. If it doesn't exist, add it in this task.

- [ ] **Step 2: Run, expect PASS.**

- [ ] **Step 3: Commit.**

```bash
git add tests/unit/test_explode_wave_shell.gd src/core/terrain_modifier.gd
git commit -m "test(sim): explode wave forms expanding ring shell"
```

---

## Task 6: Spawn-dispatcher new markers

**Files:**
- Modify: `src/core/spawn_dispatcher.gd:_spawn_entity`

Add cases for markers 8 (explosive barrel), 9 (oil barrel), 10 (gas vent), 11 (lava pool seed), 12 (oil pool seed), 13 (water pool seed). Markers 8–10 instance scenes; 11–13 are stamped as material cells via `terrain_modifier`.

- [ ] **Step 1: Add scene preloads at top of file.**

```gdscript
const EXPLOSIVE_BARREL_SCENE := preload("res://scenes/props/explosive_barrel.tscn")
const OIL_BARREL_SCENE := preload("res://scenes/props/oil_barrel.tscn")
const GAS_VENT_SCENE := preload("res://scenes/props/gas_vent.tscn")
```

- [ ] **Step 2: Extend `_spawn_entity` match.**

```gdscript
func _spawn_entity(marker: int, world_pos: Vector2, sector_dist: int, floor_num: int, is_boss_room: bool) -> void:
    match marker:
        1: _spawn_enemy(world_pos, sector_dist, floor_num, false, false)
        2: _spawn_enemy(world_pos, sector_dist, floor_num, false, true)
        3: _spawn_chest(world_pos, false)
        4: _spawn_shop(world_pos)
        5: _spawn_chest(world_pos, true)
        6: _spawn_enemy(world_pos, sector_dist, floor_num, true, false)
        7: pass
        8: _spawn_prop_scene(EXPLOSIVE_BARREL_SCENE, world_pos)
        9: _spawn_prop_scene(OIL_BARREL_SCENE, world_pos)
        10: _spawn_prop_scene(GAS_VENT_SCENE, world_pos)
        11: _world_manager.place_lava(world_pos, 1.0)
        12: _world_manager.place_material(world_pos, 1.0, MaterialRegistry.MAT_OIL)
        13: _world_manager.place_material(world_pos, 1.0, MaterialRegistry.MAT_WATER)

func _spawn_prop_scene(scene: PackedScene, world_pos: Vector2) -> void:
    var inst := scene.instantiate()
    inst.global_position = world_pos
    _spawn_parent.add_child(inst)
```

- [ ] **Step 3: Commit (scenes themselves come in Task 7).**

```bash
git add src/core/spawn_dispatcher.gd
git commit -m "feat(spawn): marker types 8-13 for props and pool seeds"
```

---

## Task 7: Prop scenes

**Files:**
- Create: `scenes/props/explosive_barrel.tscn`, `scenes/props/oil_barrel.tscn`, `scenes/props/gas_vent.tscn`
- Create: `src/drops/explosive_barrel.gd`, `src/drops/oil_barrel.gd`, `src/drops/gas_vent.gd`

Each is a `StaticBody2D` (or `Node2D` if collision is purely terrain-based) with sprite + script.

- [ ] **Step 1: Author `explosive_barrel.gd`.**

```gdscript
# src/drops/explosive_barrel.gd
class_name ExplosiveBarrel
extends StaticBody2D

@export var explosion_power: int = 120
@export var max_health: int = 1

var health: int

func _ready() -> void:
    health = max_health
    add_to_group("destructible_prop")

func take_damage(amount: int) -> void:
    health -= amount
    if health <= 0:
        _detonate()

func _detonate() -> void:
    var wm := get_tree().get_first_node_in_group("world_manager")
    if wm and wm.has_method("place_material_with_temp"):
        wm.place_material_with_temp(global_position, 1.0, MaterialRegistry.MAT_EXPLODE_WAVE, explosion_power)
    queue_free()
```

Similar for `oil_barrel.gd` (on damage spawns an oil pool, then explodes) and `gas_vent.gd` (every N seconds emits gas via `wm.place_gas`).

- [ ] **Step 2: Create the .tscn files** in the editor (sprite + collision + script). Use placeholder colored squares as sprites if no art is available yet.

- [ ] **Step 3: Hand-test in editor:** spawn a barrel via debug console, hit it with a melee swing, confirm explosion + visual wave.

- [ ] **Step 4: Commit.**

```bash
git add scenes/props/ src/drops/
git commit -m "feat(props): explosive barrel, oil barrel, gas vent scenes"
```

---

## Task 8: Add `is_elite_chest` flag

**Files:**
- Modify: `src/core/room_template.gd`

- [ ] **Step 1: Add field.**

```gdscript
@export var is_elite_chest: bool = false
```

- [ ] **Step 2: Commit.**

```bash
git add src/core/room_template.gd
git commit -m "feat(rooms): add is_elite_chest flag to RoomTemplate"
```

---

## Task 9: Add `perimeter_material` and `cracked_material` to BiomeDef

**Files:**
- Modify: `src/core/biome_def.gd`

- [ ] **Step 1: Add fields.**

```gdscript
@export var perimeter_material: int = 0
@export var cracked_material: int = 0
```

Remove `secret_ring_thickness`.

- [ ] **Step 2: Update each `assets/biomes/*.tres`** in the Godot editor's inspector — populate `perimeter_material` and `cracked_material` with the IDs for that biome's accent (e.g. caves → `MAT_STONE_BRICKS` and `MAT_STONE_CRACKED`).

Find ID values via:

```bash
godot --headless -s tools/print_material_ids.gd
```

(Add this helper if needed.)

- [ ] **Step 3: Commit.**

```bash
git add src/core/biome_def.gd assets/biomes/
git commit -m "feat(biomes): perimeter_material and cracked_material fields"
```

---

## Task 10: Boss arena PNG authoring — caves biome (4 variants)

**Files:**
- Create: `assets/rooms/caves/boss_arena_a.png` through `_d.png` (512×512)

PNG marker palette (existing convention, extended for new markers):

| Color | Material/Entity |
|---|---|
| (0,0,0) | AIR (carved interior) |
| Biome background tint | wall (uses biome.background_material) |
| Biome perimeter accent tint | perimeter wall (uses biome.perimeter_material) |
| (255,0,0) | marker 1 = enemy |
| (255,128,0) | marker 2 = elite |
| (255,255,0) | marker 3 = chest |
| (0,255,255) | marker 4 = shop |
| (255,0,255) | marker 5 = secret chest |
| (128,0,0) | marker 6 = boss |
| (0,255,0) | marker 7 = unused |
| (192,64,0) | marker 8 = explosive barrel |
| (64,32,16) | marker 9 = oil barrel |
| (0,128,255) | marker 10 = gas vent |
| (255,64,0) | marker 11 = lava pool |
| (96,48,0) | marker 12 = oil pool |
| (0,96,192) | marker 13 = water pool |

- [ ] **Step 1: Author boss_arena_a.png at 512×512.**
  - Crenellated perimeter ring at radius ~225 from center, ~16px thick, color = stone-bricks tint, with regular 24-px gaps
  - Interior: 4 stone-bricks pillars in a square pattern
  - 2 lava pool markers in opposite quadrants
  - 4 enemy markers (melee)
  - 2 explosive barrel markers
  - 1 boss marker at center

- [ ] **Step 2: Author `boss_arena_b.png`** — different pillar arrangement, swap lava for oil pool + 1 oil barrel.

- [ ] **Step 3: Author `boss_arena_c.png`** — sparse pillars, 1 gas vent, 3 elites alongside the boss.

- [ ] **Step 4: Author `boss_arena_d.png`** — multiple concentric pillar rings, water pond, 2 explosive barrels.

- [ ] **Step 5: Update the `room_templates` and/or `boss_templates` array in `caves.tres`** to reference the 4 new PNGs with `size_class=512`, `is_boss=true`, `rotatable=false`.

- [ ] **Step 6: Hand-playtest:** load a run, walk to the boss ring, confirm each arena loads correctly. Cycle through seeds to see all 4 variants.

- [ ] **Step 7: Commit.**

```bash
git add assets/rooms/caves/ assets/biomes/caves.tres
git commit -m "feat(rooms): 4 boss arena variants for caves biome"
```

---

## Task 11: Boss arena PNGs — mines, magma, frozen, vault

Repeat Task 10 for each remaining biome, using its perimeter accent material.

- [ ] **Step 1: Mines** — wood-beam perimeter, oil barrels, gas pools, wooden pillars in interior.
- [ ] **Step 2: Magma** — obsidian perimeter, lava pools dominant, magma stone pillars.
- [ ] **Step 3: Frozen** — packed-ice perimeter, ice powder patches, sparser features.
- [ ] **Step 4: Vault** — engraved-metal perimeter, explosive barrels, water ponds.
- [ ] **Step 5: Commit each biome separately.**

```bash
# After each biome:
git add assets/rooms/<biome>/ assets/biomes/<biome>.tres
git commit -m "feat(rooms): 4 boss arena variants for <biome> biome"
```

---

## Task 12: Pixel scene stamp — perimeter accent material support

**Files:**
- Modify: `shaders/include/pixel_scene_stamp.glslinc`

Currently `pixel_scene_stamp` maps PNG pixel R values to material IDs. For boss arenas to use the perimeter accent, we need to route a specific PNG color value to `biome.perimeter_material` (not a fixed material ID).

- [ ] **Step 1: Inspect the existing stamp function.**

```bash
sed -n '50,80p' shaders/include/pixel_scene_stamp.glslinc
```

- [ ] **Step 2: Add a sentinel value.** Convention: PNG red byte = 254 → "use biome.perimeter_material"; 253 → "use biome.cracked_material".

```glsl
// In pixel_scene_stamp.glslinc, in the per-cell stamp:
int mat;
if (r == 254) {
    mat = biome.perimeter_material;
} else if (r == 253) {
    mat = biome.cracked_material;
} else if (r == 255) {
    mat = biome.background_material;
} else {
    mat = r;
}
```

- [ ] **Step 3: Re-author boss arena PNGs** to use color (254,0,0) for perimeter cells. (Tedious — do it via an ImageMagick script if many cells.)

```bash
for f in assets/rooms/*/boss_arena_*.png; do
  convert "$f" -fuzz 5% -fill 'rgb(254,0,0)' -opaque '<stone-bricks-tint>' "$f"
done
```

- [ ] **Step 4: Verify in-game.**

- [ ] **Step 5: Commit.**

```bash
git add -A
git commit -m "feat(rooms): biome-aware perimeter+cracked material in pixel stamp"
```

---

## Task 13: Elite chest room PNGs — all biomes

**Files:**
- Create: `assets/rooms/<biome>/elite_chest_a.png` … `_c.png` (256×256), 3 per biome × 5 biomes

Open carved-air shapes, no perimeter. Each has:
- 1 chest marker centered or near-centered
- 2–3 elite markers placed around the chest
- 0–1 hazard feature (oil pool, gas vent, or 1–2 explosive barrels)

- [ ] **Step 1: Author 3 PNGs per biome.** ~15 minutes per PNG.

- [ ] **Step 2: Add to each `biome.tres`'s `room_templates`** array with `is_elite_chest=true`, `size_class=256`, `rotatable=true`, weight ≈ 0.5 (tune so ~10% of sectors land elite-chest).

- [ ] **Step 3: Hand-playtest:** generate a few levels, confirm elite chest rooms appear at reasonable density.

- [ ] **Step 4: Commit each biome.**

```bash
git add assets/rooms/<biome>/elite_chest_*.png assets/biomes/<biome>.tres
git commit -m "feat(rooms): elite chest room variants for <biome>"
```

---

## Task 14: Secret stamp — solid-validation in shader

**Files:**
- Modify: `shaders/include/pixel_scene_stamp.glslinc`

For secret stamps only (the `is_secret` flag in stamp meta), check the 32×32 probe around the stamp center; if ≥90% solid, proceed; else skip the entire stamp.

Implementation: each cell of the stamp first probes a 32×32 region around the stamp center via 9-point sampling (cheap proxy for 32×32 = 1024 cells). If <90% solid, return without stamping.

- [ ] **Step 1: Add the validation block.** Inside the per-stamp loop, before applying stamp cells:

```glsl
if ((flags & 1) != 0) {  // is_secret
    int solid_count = 0;
    int sample_total = 25;  // 5x5 grid of 32x32 -> 25 samples
    for (int sy = -2; sy <= 2; sy++) {
        for (int sx = -2; sx <= 2; sx++) {
            ivec2 sample_world = ivec2(s.xy) + ivec2(sx, sy) * 6;  // 6-px stride covers ~32px
            ivec2 sample_local = sample_world - ctx.chunk_coord * 256;
            if (sample_local.x < 0 || sample_local.x >= 256 || sample_local.y < 0 || sample_local.y >= 256) {
                sample_total -= 1;
                continue;
            }
            vec4 probe = imageLoad(chunk_tex, sample_local);
            int pmat = int(round(probe.r * 255.0));
            if (pmat != MAT_AIR) solid_count += 1;
        }
    }
    if (sample_total <= 0 || float(solid_count) / float(sample_total) < 0.9) continue;
}
```

- [ ] **Step 2: Commit.**

```bash
git add shaders/include/pixel_scene_stamp.glslinc
git commit -m "feat(rooms): secret stamp validates solid surroundings before placing"
```

---

## Task 15: Secret chest PNG re-authoring + cracked hint

**Files:**
- Modify: `assets/rooms/<biome>/secret_a.png` (re-author 5 PNGs)

Each PNG is small (~32×32) and contains:
- 1 chest marker (color 255,0,255 — marker 5)
- A small cracked-material hint patch (~6×3 cells, color 253,0,0)

The hint patch sits adjacent to the chest, in a direction that will face the nearest air pocket. Since we can't know which direction at authoring time, author the PNG with the hint patch on the +X side. Make `rotatable=true` in the BiomeDef so rotation picks an orientation that may align with air.

- [ ] **Step 1: Re-author each `secret_a.png`.**

- [ ] **Step 2: Update each biome's `secret_a` template** — `is_secret=true`, `rotatable=true`, `size_class=32`.

- [ ] **Step 3: Delete `shaders/include/secret_ring_stage.glslinc`** and remove its inclusion from gen shader.

- [ ] **Step 4: Remove `secret_ring_thickness` from biome_def.gd and the .tres files.** (Field was removed in Task 9 — verify all references are gone.)

- [ ] **Step 5: Commit.**

```bash
git add -A
git rm shaders/include/secret_ring_stage.glslinc
git commit -m "feat(rooms): redesigned secret chest with cracked-hint patches"
```

---

## Task 16: Visual regression — boss arena render check

**Files:**
- Modify: `addons/level_preview/level_preview_plugin.gd`

Add a debug toggle to render the boss arena perimeter on a level preview. The plugin already has a chunk visualization; extend it to overlay boss sectors with a tinted border in the perimeter material's color.

- [ ] **Step 1: Locate the plugin's draw entry.**

```bash
grep -n "draw\|_draw\|update_preview" addons/level_preview/level_preview_plugin.gd
```

- [ ] **Step 2: Add boss-sector overlay.** For each sector at Chebyshev distance 10 from origin, draw a 512-px outlined rectangle on the preview using the current biome's `perimeter_material` tint color.

- [ ] **Step 3: Eyeball-check** that the 4 variants render distinctly across biomes.

- [ ] **Step 4: Commit.**

```bash
git add addons/level_preview/
git commit -m "feat(preview): overlay boss arena perimeters in level preview"
```

---

## Done Criteria

- [ ] All boss sectors load one of 4 variants without errors; perimeter material renders distinctly
- [ ] Elite chest rooms appear at ~10% of sector roll-rate
- [ ] No `secret_ring_stage` code path remains; secrets only place inside solid regions
- [ ] Oil pools ignite from lava contact; burning oil emits fire and ends in a small explode wave
- [ ] Explosive barrels detonate into a clean expanding ring of damage
- [ ] All tests in `tests/unit/test_oil_chain.gd` and `tests/unit/test_explode_wave_shell.gd` pass
