# Step 3 — Resources Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the five GDScript-backed resource classes (`TerrainCell`, `PoolDef`, `RoomTemplate`, `BiomeDef`, `TemplatePack`) to native C++ classes registered through the godot-cpp extension. After this step, `assets/biomes/*.tres` files load as native-typed `BiomeDef` resources without a `script_class` indirection, and gameplay GDScript that reads `b.room_templates`, `tmpl.png_path`, `cell.material_id`, etc. continues to work unchanged because the C++ classes expose identical property surfaces. The five `.gd` files under `src/core/` are deleted in this step's final commit; their `class_name` identifiers are taken over by the C++ classes via `GDREGISTER_CLASS`.

**Architecture:** Four new resource translation units under `gdextension/src/resources/` (`terrain_cell.{h,cpp}`, `pool_def.{h,cpp}`, `room_template.{h,cpp}`, `biome_def.{h,cpp}`) plus one `RefCounted` translation unit (`template_pack.{h,cpp}`). `register_types.cpp` registers them at `MODULE_INITIALIZATION_LEVEL_SCENE` after `MaterialDef`/`MaterialTable` (resources may reference material ids by integer, but the order is fixed in C++ already). A new one-shot Python script at `tools/migrate_tres.py` rewrites the five `.tres` files from `script_class="BiomeDef"` form to native `type="BiomeDef"` form (per spec §9.3). Five GDScript files plus their `.uid` sidecars are deleted at the end.

**Tech Stack:** godot-cpp (already vendored, pinned per step 1), C++17, the SCons + `build.sh` pipeline. New `tools/migrate_tres.py` written in Python 3, run once.

---

## Required Reading Before Starting

You **must** read all of these before writing any code.

1. **Spec:** `docs/superpowers/specs/2026-04-30-godot-cpp-hot-path-port-design.md`. Mandatory sections:
   - §3.2 (Ported to C++) — the `TerrainCell`/`BiomeDef`/`PoolDef`/`RoomTemplate`/`TemplatePack` rows. **Note the discrepancy:** the table lists `TemplatePack` as `Resource`, but the GDScript original is `RefCounted` and is never loaded from a `.tres`. Per the spec-wins rule, the spec drives — but the spec also says "No new public methods, signals, or properties on ported classes" (§3.4). Changing the base class from `RefCounted` to `Resource` materially changes lifetime semantics, which gameplay code depends on (`BiomeRegistry.template_pack` is a per-process singleton built at runtime, not a saved asset). Resolution applied in this plan: keep `TemplatePack` as `RefCounted`. Treat the spec table row as a typo. Flag this in the PR description so a reviewer can object before merge.
   - §3.4 (Non-goals) — the no-new-public-methods rule applies in full. The C++ class surface is exactly what gameplay GDScript reads today.
   - §7.5 (Material-id stability) — `BiomeDef.background_material` and `PoolDef.material_id` are integers referencing the `MaterialTable` order locked in step 2. The defaults in the GDScript originals (`background_material = 2 # STONE`, `pool_def.material_id = 0`) must be preserved verbatim.
   - §9.1 step 3 — what this step delivers.
   - §9.3 (`.tres` migration mechanics) — the rewrite shape (`script_class` form → native `type` form) and the verification gate (open one or two manually before bulk-running).
   - §9.4 — `.uid` cleanup.

2. **Predecessor source from steps 1–2** (already merged):
   - `gdextension/SConstruct`
   - `gdextension/src/register_types.{h,cpp}`
   - `gdextension/src/sim/material_table.{h,cpp}` — read in full. The `MaterialDef` class is the closest precedent for how this step's resource classes get bound (`GDCLASS`, `_bind_methods`, `ADD_PROPERTY` per field). Mirror its shape.

3. **The classes being ported** (read in full before writing C++; field defaults must match):
   - `src/core/terrain_cell.gd` (14 LOC)
   - `src/core/pool_def.gd` (8 LOC)
   - `src/core/room_template.gd` (10 LOC)
   - `src/core/biome_def.gd` (16 LOC)
   - `src/core/template_pack.gd` (80 LOC) — the only port with logic, not just data.

4. **Every callsite that constructs or reads these types** (so the C++ surface matches usage exactly):
   - `src/core/terrain_physical.gd` — constructs `TerrainCell.new(mat_id, is_solid, is_fluid, dmg)`. The 4-arg constructor must work from GDScript.
   - `src/player/lava_damage_checker.gd` — reads `cell.material_id`, `cell.is_fluid`, `cell.damage`.
   - `src/core/sector_grid.gd` — reads `BiomeDef.boss_templates`, `room_templates`, and `RoomTemplate.weight`/`size_class`/`rotatable`.
   - `src/core/spawn_dispatcher.gd` — constructs/reads `RoomTemplate`.
   - `src/autoload/biome_registry.gd` — `load(path) as BiomeDef`, iterates `b.room_templates`, calls `TemplatePack.new()`, `pack.register(tmpl)`, `pack.build_arrays()`, `pack.get_size_classes()`, `pack.get_array(sc)`.
   - `src/autoload/level_manager.gd` — references `BiomeDef`.
   - `src/core/compute_device.gd` — references `BiomeDef`/`PoolDef` (still alive this step; deleted in step 7).
   - `tests/unit/test_terrain_physical.gd`, `test_template_pack.gd`, `test_biome_def.gd`, `test_sector_grid.gd`.
   - `tools/generate_biome_resources.gd`, `tools/room_generators/arena.gd` — offline tools that construct these resources programmatically; stay in GDScript and continue to work because the class names and properties are unchanged.

5. **The five `.tres` files this step rewrites:**
   - `assets/biomes/caves.tres`
   - `assets/biomes/mines.tres`
   - `assets/biomes/magma.tres`
   - `assets/biomes/frozen.tres`
   - `assets/biomes/vault.tres`

   Open `caves.tres` once before reading any further — it's the canonical example of the `script_class="BiomeDef"` + `[ext_resource type="Script" ...]` + `script = ExtResource("...")` shape that step 3 erases.

If anything in this plan conflicts with the spec, the spec wins — flag the conflict and stop, do not silently deviate. The two pre-resolved conflicts (the §3.2-vs-§3.4 `TemplatePack` base class question, and the no-new-method rule applied to constructors below) are already settled here; do not re-litigate during execution.

## What This Step Does NOT Do

- **Does not** port `Chunk`, `SectorGrid`, `GenerationContext`, or any non-resource class. Those land in step 4.
- **Does not** introduce new public methods or properties beyond what the GDScript originals exposed.
- **Does not** delete `compute_device.gd` or any compute shader. The compute pipeline still consumes `BiomeDef`/`PoolDef` after this step (it survives until step 7).
- **Does not** change `BiomeRegistry`, `LevelManager`, or any other autoload. Those autoloads still work because the class names (`BiomeDef`, `RoomTemplate`, `TemplatePack`) are preserved by registering the native C++ classes under those names.
- **Does not** touch `tools/generate_biome_resources.gd` beyond confirming it still runs against the new native types if invoked. (It's an offline tool; not part of the runtime.)
- **Does not** add a typed C++ accessor for `BiomeDef.pool_materials` etc. that returns anything other than a Variant `Array`. The exports are `Array[PoolDef]` / `Array[RoomTemplate]` in the GDScript original, which the editor inspector renders as typed arrays. We'll mirror this with `TypedArray<PoolDef>` etc. in the binding (cf. `MaterialTable.materials` from step 2).

## Pre-flight Verification (do this first)

- [ ] **Step 1: Confirm step 2 is merged and the build is green**

```bash
git status
git log --oneline -8
./gdextension/build.sh debug
ls bin/lib/
```

Expected: clean working tree on `refactor/cpp`, recent commits include the step 2 work (look for `MaterialTable`/`MaterialRegistry` removal commits), build produces `libtoprogue.<platform>.template_debug.dev.<arch>.{dylib,so}`.

- [ ] **Step 2: Confirm the editor still loads with the MaterialTable singleton**

Launch Godot 4.6 → open the project → Output log. No `MaterialRegistry`/`MaterialTable` errors. Close the editor.

- [ ] **Step 3: Inventory every callsite once, before changes**

```bash
grep -rn "\bTerrainCell\b\|\bPoolDef\b\|\bRoomTemplate\b\|\bBiomeDef\b\|\bTemplatePack\b" src/ tests/ tools/ assets/ project.godot
```

Save the output (scratch buffer or temporary file) — Task 8 step 4 re-greps and compares. Every hit should still resolve after the port; only the `.tres` files in `assets/biomes/` will be rewritten in shape.

- [ ] **Step 4: Confirm the gdUnit4 suite is green at HEAD**

Run gdUnit4 via the editor's Test panel. All green. If any test is red at HEAD before this step starts, fix or document the pre-existing failure before proceeding — otherwise you can't tell whether this step regressed something.

---

## Task 1: Port `TerrainCell` to C++

Smallest of the five — pure data, four fields, one parameterized constructor. Best warmup for the binding pattern.

**Files:**
- Create: `gdextension/src/resources/terrain_cell.h`
- Create: `gdextension/src/resources/terrain_cell.cpp`

- [ ] **Step 1: Write the header**

Create `gdextension/src/resources/terrain_cell.h`:

```cpp
#pragma once

#include <godot_cpp/classes/resource.hpp>

namespace toprogue {

// Mirrors src/core/terrain_cell.gd 1:1.
// Constructed from GDScript as `TerrainCell.new()` (zero-arg) or
// `TerrainCell.new(mat_id, is_solid, is_fluid, damage)` per terrain_physical.gd.
class TerrainCell : public godot::Resource {
    GDCLASS(TerrainCell, godot::Resource);

public:
    int    material_id = 0;
    bool   is_solid    = false;
    bool   is_fluid    = false;
    double damage      = 0.0;

    TerrainCell();

    // Bound static factory mirrors `_init(p_material_id, p_is_solid, p_is_fluid, p_damage)`.
    // GDScript callers use `TerrainCell.new(...)`, which Godot routes via _init —
    // we expose the same effect through a static `create(...)` and bind it under the
    // name `new` is impossible (engine reserves `new`), so callers in
    // `src/core/terrain_physical.gd` are migrated to construct via the four-arg
    // `_init` shim bound below. See Task 1 step 3.

    int    get_material_id() const   { return material_id; }
    void   set_material_id(int v)    { material_id = v; }
    bool   get_is_solid() const      { return is_solid; }
    void   set_is_solid(bool v)      { is_solid = v; }
    bool   get_is_fluid() const      { return is_fluid; }
    void   set_is_fluid(bool v)      { is_fluid = v; }
    double get_damage() const        { return damage; }
    void   set_damage(double v)      { damage = v; }

    // GDScript-callable initializer: lets `TerrainCell.new(a, b, c, d)` keep
    // working when the GDScript `_init(...)` is replaced by C++. See cpp file.
    void   init_from_args(int p_material_id, bool p_is_solid, bool p_is_fluid, double p_damage);

protected:
    static void _bind_methods();
};

} // namespace toprogue
```

**Why a `init_from_args` shim:** the GDScript original's `_init(p_material_id=0, ...)` is a 4-arg-with-defaults constructor that GDScript callers invoke via `TerrainCell.new(mat_id, is_solid, is_fluid, dmg)`. godot-cpp does not let you bind `_init` with custom arguments via `_bind_methods`; the engine constructs the object zero-arg and then GDScript-side defaults take over. Two clean ports of the existing API:

- **A (chosen):** keep the call surface by binding a method named `init_args` (or similar) and updating `terrain_physical.gd`'s two construction sites to call `var c := TerrainCell.new(); c.init_args(mat_id, is_solid, is_fluid, dmg)`. This is the single GDScript edit step 3 introduces. It's a 2-line change in one file.
- **B (rejected):** wrap construction inside `MaterialTable` as `MaterialTable.make_cell(mat_id)`. Adds a method to `MaterialTable` that didn't exist before, violates §3.4. Rejected.

We pick A. The plan calls the bound method `init_args` to be unambiguous.

- [ ] **Step 2: Write the implementation**

Create `gdextension/src/resources/terrain_cell.cpp`:

```cpp
#include "terrain_cell.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace toprogue {

TerrainCell::TerrainCell() = default;

void TerrainCell::init_args(int p_material_id, bool p_is_solid, bool p_is_fluid, double p_damage) {
    // Forward-compat shim for the 4-arg form once used as `TerrainCell.new(...)`.
    material_id = p_material_id;
    is_solid    = p_is_solid;
    is_fluid    = p_is_fluid;
    damage      = p_damage;
}

void TerrainCell::_bind_methods() {
    ClassDB::bind_method(D_METHOD("init_args", "material_id", "is_solid", "is_fluid", "damage"),
                         &TerrainCell::init_args);

    ClassDB::bind_method(D_METHOD("get_material_id"), &TerrainCell::get_material_id);
    ClassDB::bind_method(D_METHOD("set_material_id", "v"), &TerrainCell::set_material_id);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "material_id"), "set_material_id", "get_material_id");

    ClassDB::bind_method(D_METHOD("get_is_solid"), &TerrainCell::get_is_solid);
    ClassDB::bind_method(D_METHOD("set_is_solid", "v"), &TerrainCell::set_is_solid);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_solid"), "set_is_solid", "get_is_solid");

    ClassDB::bind_method(D_METHOD("get_is_fluid"), &TerrainCell::get_is_fluid);
    ClassDB::bind_method(D_METHOD("set_is_fluid", "v"), &TerrainCell::set_is_fluid);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_fluid"), "set_is_fluid", "get_is_fluid");

    ClassDB::bind_method(D_METHOD("get_damage"), &TerrainCell::get_damage);
    ClassDB::bind_method(D_METHOD("set_damage", "v"), &TerrainCell::set_damage);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "damage"), "set_damage", "get_damage");
}

} // namespace toprogue
```

- [ ] **Step 3: Build to confirm it compiles standalone (registration comes in Task 6)**

```bash
./gdextension/build.sh debug
```

Expected: clean build. The class compiles but isn't registered yet — that's fine, Task 6 wires registration.

- [ ] **Step 4: Commit**

```bash
git add gdextension/src/resources/terrain_cell.h gdextension/src/resources/terrain_cell.cpp
git commit -m "feat: add TerrainCell C++ resource"
```

---

## Task 2: Port `PoolDef` to C++

Pure data — four fields, no logic.

**Files:**
- Create: `gdextension/src/resources/pool_def.h`
- Create: `gdextension/src/resources/pool_def.cpp`

- [ ] **Step 1: Write the header**

Create `gdextension/src/resources/pool_def.h`:

```cpp
#pragma once

#include <godot_cpp/classes/resource.hpp>

namespace toprogue {

// Mirrors src/core/pool_def.gd 1:1. All four fields are `@export` in GDScript,
// so they need editor-visible property bindings here.
class PoolDef : public godot::Resource {
    GDCLASS(PoolDef, godot::Resource);

public:
    int    material_id    = 0;
    double noise_scale    = 0.005;
    double noise_threshold = 0.6;
    int    seed_offset    = 0;

    PoolDef() = default;

    int    get_material_id() const     { return material_id; }
    void   set_material_id(int v)      { material_id = v; }
    double get_noise_scale() const     { return noise_scale; }
    void   set_noise_scale(double v)   { noise_scale = v; }
    double get_noise_threshold() const { return noise_threshold; }
    void   set_noise_threshold(double v){ noise_threshold = v; }
    int    get_seed_offset() const     { return seed_offset; }
    void   set_seed_offset(int v)      { seed_offset = v; }

protected:
    static void _bind_methods();
};

} // namespace toprogue
```

- [ ] **Step 2: Write the implementation**

Create `gdextension/src/resources/pool_def.cpp`:

```cpp
#include "pool_def.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace toprogue {

void PoolDef::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_material_id"), &PoolDef::get_material_id);
    ClassDB::bind_method(D_METHOD("set_material_id", "v"), &PoolDef::set_material_id);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "material_id"), "set_material_id", "get_material_id");

    ClassDB::bind_method(D_METHOD("get_noise_scale"), &PoolDef::get_noise_scale);
    ClassDB::bind_method(D_METHOD("set_noise_scale", "v"), &PoolDef::set_noise_scale);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "noise_scale"), "set_noise_scale", "get_noise_scale");

    ClassDB::bind_method(D_METHOD("get_noise_threshold"), &PoolDef::get_noise_threshold);
    ClassDB::bind_method(D_METHOD("set_noise_threshold", "v"), &PoolDef::set_noise_threshold);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "noise_threshold"),
                 "set_noise_threshold", "get_noise_threshold");

    ClassDB::bind_method(D_METHOD("get_seed_offset"), &PoolDef::get_seed_offset);
    ClassDB::bind_method(D_METHOD("set_seed_offset", "v"), &PoolDef::set_seed_offset);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "seed_offset"), "set_seed_offset", "get_seed_offset");
}

} // namespace toprogue
```

- [ ] **Step 3: Build**

```bash
./gdextension/build.sh debug
```

Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add gdextension/src/resources/pool_def.h gdextension/src/resources/pool_def.cpp
git commit -m "feat: add PoolDef C++ resource"
```

---

## Task 3: Port `RoomTemplate` to C++

Pure data — six `@export` fields.

**Files:**
- Create: `gdextension/src/resources/room_template.h`
- Create: `gdextension/src/resources/room_template.cpp`

- [ ] **Step 1: Write the header**

Create `gdextension/src/resources/room_template.h`:

```cpp
#pragma once

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/string.hpp>

namespace toprogue {

class RoomTemplate : public godot::Resource {
    GDCLASS(RoomTemplate, godot::Resource);

public:
    godot::String png_path;
    double weight     = 1.0;
    int    size_class = 64;
    bool   is_secret  = false;
    bool   is_boss    = false;
    bool   rotatable  = true;

    RoomTemplate() = default;

    godot::String get_png_path() const          { return png_path; }
    void          set_png_path(const godot::String &v) { png_path = v; }
    double        get_weight() const            { return weight; }
    void          set_weight(double v)          { weight = v; }
    int           get_size_class() const        { return size_class; }
    void          set_size_class(int v)         { size_class = v; }
    bool          get_is_secret() const         { return is_secret; }
    void          set_is_secret(bool v)         { is_secret = v; }
    bool          get_is_boss() const           { return is_boss; }
    void          set_is_boss(bool v)           { is_boss = v; }
    bool          get_rotatable() const         { return rotatable; }
    void          set_rotatable(bool v)         { rotatable = v; }

protected:
    static void _bind_methods();
};

} // namespace toprogue
```

- [ ] **Step 2: Write the implementation**

Create `gdextension/src/resources/room_template.cpp`:

```cpp
#include "room_template.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace toprogue {

void RoomTemplate::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_png_path"), &RoomTemplate::get_png_path);
    ClassDB::bind_method(D_METHOD("set_png_path", "v"), &RoomTemplate::set_png_path);
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "png_path"), "set_png_path", "get_png_path");

    ClassDB::bind_method(D_METHOD("get_weight"), &RoomTemplate::get_weight);
    ClassDB::bind_method(D_METHOD("set_weight", "v"), &RoomTemplate::set_weight);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "weight"), "set_weight", "get_weight");

    ClassDB::bind_method(D_METHOD("get_size_class"), &RoomTemplate::get_size_class);
    ClassDB::bind_method(D_METHOD("set_size_class", "v"), &RoomTemplate::set_size_class);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "size_class"), "set_size_class", "get_size_class");

    ClassDB::bind_method(D_METHOD("get_is_secret"), &RoomTemplate::get_is_secret);
    ClassDB::bind_method(D_METHOD("set_is_secret", "v"), &RoomTemplate::set_is_secret);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_secret"), "set_is_secret", "get_is_secret");

    ClassDB::bind_method(D_METHOD("get_is_boss"), &RoomTemplate::get_is_boss);
    ClassDB::bind_method(D_METHOD("set_is_boss", "v"), &RoomTemplate::set_is_boss);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_boss"), "set_is_boss", "get_is_boss");

    ClassDB::bind_method(D_METHOD("get_rotatable"), &RoomTemplate::get_rotatable);
    ClassDB::bind_method(D_METHOD("set_rotatable", "v"), &RoomTemplate::set_rotatable);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "rotatable"), "set_rotatable", "get_rotatable");
}

} // namespace toprogue
```

- [ ] **Step 3: Build**

```bash
./gdextension/build.sh debug
```

Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add gdextension/src/resources/room_template.h gdextension/src/resources/room_template.cpp
git commit -m "feat: add RoomTemplate C++ resource"
```

---

## Task 4: Port `BiomeDef` to C++

Twelve `@export` fields, two of which are `Array[PoolDef]` and two are `Array[RoomTemplate]`. The typed-array bindings are the only non-trivial part.

**Files:**
- Create: `gdextension/src/resources/biome_def.h`
- Create: `gdextension/src/resources/biome_def.cpp`

- [ ] **Step 1: Write the header**

Create `gdextension/src/resources/biome_def.h`:

```cpp
#pragma once

#include "pool_def.h"
#include "room_template.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/typed_array.hpp>

namespace toprogue {

class BiomeDef : public godot::Resource {
    GDCLASS(BiomeDef, godot::Resource);

public:
    godot::String display_name;
    double cave_noise_scale     = 0.008;
    double cave_threshold       = 0.42;
    double ridge_weight         = 0.3;
    double ridge_scale          = 0.012;
    int    octaves              = 5;
    int    background_material  = 2; // STONE — see spec §7.5
    godot::TypedArray<PoolDef>      pool_materials;
    godot::TypedArray<RoomTemplate> room_templates;
    godot::TypedArray<RoomTemplate> boss_templates;
    int    secret_ring_thickness = 3;
    godot::Color tint = godot::Color(1, 1, 1, 1);

    BiomeDef() = default;

    godot::String get_display_name() const            { return display_name; }
    void          set_display_name(const godot::String &v) { display_name = v; }
    double        get_cave_noise_scale() const        { return cave_noise_scale; }
    void          set_cave_noise_scale(double v)      { cave_noise_scale = v; }
    double        get_cave_threshold() const          { return cave_threshold; }
    void          set_cave_threshold(double v)        { cave_threshold = v; }
    double        get_ridge_weight() const            { return ridge_weight; }
    void          set_ridge_weight(double v)          { ridge_weight = v; }
    double        get_ridge_scale() const             { return ridge_scale; }
    void          set_ridge_scale(double v)           { ridge_scale = v; }
    int           get_octaves() const                 { return octaves; }
    void          set_octaves(int v)                  { octaves = v; }
    int           get_background_material() const     { return background_material; }
    void          set_background_material(int v)      { background_material = v; }

    godot::TypedArray<PoolDef>      get_pool_materials() const { return pool_materials; }
    void                            set_pool_materials(const godot::TypedArray<PoolDef> &v) { pool_materials = v; }
    godot::TypedArray<RoomTemplate> get_room_templates() const { return room_templates; }
    void                            set_room_templates(const godot::TypedArray<RoomTemplate> &v) { room_templates = v; }
    godot::TypedArray<RoomTemplate> get_boss_templates() const { return boss_templates; }
    void                            set_boss_templates(const godot::TypedArray<RoomTemplate> &v) { boss_templates = v; }

    int           get_secret_ring_thickness() const   { return secret_ring_thickness; }
    void          set_secret_ring_thickness(int v)    { secret_ring_thickness = v; }
    godot::Color  get_tint() const                    { return tint; }
    void          set_tint(const godot::Color &v)     { tint = v; }

protected:
    static void _bind_methods();
};

} // namespace toprogue
```

- [ ] **Step 2: Write the implementation**

Create `gdextension/src/resources/biome_def.cpp`:

```cpp
#include "biome_def.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace toprogue {

void BiomeDef::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_display_name"), &BiomeDef::get_display_name);
    ClassDB::bind_method(D_METHOD("set_display_name", "v"), &BiomeDef::set_display_name);
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "display_name"),
                 "set_display_name", "get_display_name");

    ClassDB::bind_method(D_METHOD("get_cave_noise_scale"), &BiomeDef::get_cave_noise_scale);
    ClassDB::bind_method(D_METHOD("set_cave_noise_scale", "v"), &BiomeDef::set_cave_noise_scale);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cave_noise_scale"),
                 "set_cave_noise_scale", "get_cave_noise_scale");

    ClassDB::bind_method(D_METHOD("get_cave_threshold"), &BiomeDef::get_cave_threshold);
    ClassDB::bind_method(D_METHOD("set_cave_threshold", "v"), &BiomeDef::set_cave_threshold);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cave_threshold"),
                 "set_cave_threshold", "get_cave_threshold");

    ClassDB::bind_method(D_METHOD("get_ridge_weight"), &BiomeDef::get_ridge_weight);
    ClassDB::bind_method(D_METHOD("set_ridge_weight", "v"), &BiomeDef::set_ridge_weight);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "ridge_weight"),
                 "set_ridge_weight", "get_ridge_weight");

    ClassDB::bind_method(D_METHOD("get_ridge_scale"), &BiomeDef::get_ridge_scale);
    ClassDB::bind_method(D_METHOD("set_ridge_scale", "v"), &BiomeDef::set_ridge_scale);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "ridge_scale"),
                 "set_ridge_scale", "get_ridge_scale");

    ClassDB::bind_method(D_METHOD("get_octaves"), &BiomeDef::get_octaves);
    ClassDB::bind_method(D_METHOD("set_octaves", "v"), &BiomeDef::set_octaves);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "octaves"), "set_octaves", "get_octaves");

    ClassDB::bind_method(D_METHOD("get_background_material"), &BiomeDef::get_background_material);
    ClassDB::bind_method(D_METHOD("set_background_material", "v"),
                         &BiomeDef::set_background_material);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "background_material"),
                 "set_background_material", "get_background_material");

    ClassDB::bind_method(D_METHOD("get_pool_materials"), &BiomeDef::get_pool_materials);
    ClassDB::bind_method(D_METHOD("set_pool_materials", "v"), &BiomeDef::set_pool_materials);
    ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "pool_materials",
                              PROPERTY_HINT_ARRAY_TYPE, "PoolDef"),
                 "set_pool_materials", "get_pool_materials");

    ClassDB::bind_method(D_METHOD("get_room_templates"), &BiomeDef::get_room_templates);
    ClassDB::bind_method(D_METHOD("set_room_templates", "v"), &BiomeDef::set_room_templates);
    ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "room_templates",
                              PROPERTY_HINT_ARRAY_TYPE, "RoomTemplate"),
                 "set_room_templates", "get_room_templates");

    ClassDB::bind_method(D_METHOD("get_boss_templates"), &BiomeDef::get_boss_templates);
    ClassDB::bind_method(D_METHOD("set_boss_templates", "v"), &BiomeDef::set_boss_templates);
    ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "boss_templates",
                              PROPERTY_HINT_ARRAY_TYPE, "RoomTemplate"),
                 "set_boss_templates", "get_boss_templates");

    ClassDB::bind_method(D_METHOD("get_secret_ring_thickness"),
                         &BiomeDef::get_secret_ring_thickness);
    ClassDB::bind_method(D_METHOD("set_secret_ring_thickness", "v"),
                         &BiomeDef::set_secret_ring_thickness);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "secret_ring_thickness"),
                 "set_secret_ring_thickness", "get_secret_ring_thickness");

    ClassDB::bind_method(D_METHOD("get_tint"), &BiomeDef::get_tint);
    ClassDB::bind_method(D_METHOD("set_tint", "v"), &BiomeDef::set_tint);
    ADD_PROPERTY(PropertyInfo(Variant::COLOR, "tint"), "set_tint", "get_tint");
}

} // namespace toprogue
```

- [ ] **Step 3: Build**

```bash
./gdextension/build.sh debug
```

If `TypedArray<PoolDef>` requires `PoolDef` to be a complete type at template instantiation, the `#include "pool_def.h"` in the header handles that. If linker errors mention undefined references to `TypedArray<PoolDef>::TypedArray()` etc., add `<godot_cpp/variant/typed_array.hpp>` to the cpp file too.

- [ ] **Step 4: Commit**

```bash
git add gdextension/src/resources/biome_def.h gdextension/src/resources/biome_def.cpp
git commit -m "feat: add BiomeDef C++ resource"
```

---

## Task 5: Port `TemplatePack` to C++

The only port with logic. Reads PNG files from disk, pads them to size_class, builds `Texture2DArray`s, exposes lookups by size class.

**Resolved deviation from spec:** kept as `RefCounted` (not `Resource`) — see "Required Reading" §3.2 note.

The GDScript original depends on the `TextureArrayBuilder` autoload (`src/utils/texture_array_builder.gd`). That autoload stays in GDScript per spec §3.3. The C++ port calls into it via `Engine::get_singleton("TextureArrayBuilder")` and a `call("build_from_images", ...)`.

**Files:**
- Create: `gdextension/src/resources/template_pack.h`
- Create: `gdextension/src/resources/template_pack.cpp`

- [ ] **Step 1: Re-read the GDScript and the test suite together**

Open `src/core/template_pack.gd` and `tests/unit/test_template_pack.gd` side by side. The bound surface this port must expose:

- `register(tmpl: RoomTemplate) -> int`
- `build_arrays() -> void`
- `get_array(size_class: int) -> Texture2DArray`
- `get_image(size_class: int, index: int) -> Image`
- `collect_markers(size_class: int, index: int) -> Array` (of `{"pos": Vector2i, "type": int}` dictionaries)
- `get_size_classes() -> Array`
- `template_count(size_class: int) -> int`

Internal storage (not bound, not visible to GDScript): a per-size-class bucket of `(template, image)` and a per-size-class `Texture2DArray` cache.

- [ ] **Step 2: Write the header**

Create `gdextension/src/resources/template_pack.h`:

```cpp
#pragma once

#include "room_template.h"

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/texture2d_array.hpp>
#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/templates/vector.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace toprogue {

class TemplatePack : public godot::RefCounted {
    GDCLASS(TemplatePack, godot::RefCounted);

    struct Entry {
        godot::Ref<RoomTemplate> tmpl;
        godot::Ref<godot::Image> image;
    };

    // size_class -> bucket
    godot::HashMap<int, godot::Vector<Entry>> _by_size;
    // size_class -> Texture2DArray
    godot::HashMap<int, godot::Ref<godot::Texture2DArray>> _arrays;

public:
    TemplatePack() = default;

    int  register_template(const godot::Ref<RoomTemplate> &tmpl);
    void build_arrays();
    godot::Ref<godot::Texture2DArray> get_array(int size_class) const;
    godot::Ref<godot::Image>          get_image(int size_class, int index) const;
    godot::Array                      collect_markers(int size_class, int index) const;
    godot::Array                      get_size_classes() const;
    int                               template_count(int size_class) const;

protected:
    static void _bind_methods();
};

} // namespace toprogue
```

**Why `register_template` instead of `register`:** `register` is a C/C++ keyword, so the C++ identifier can't be `register`. The bound name (visible to GDScript) is still `register` via `D_METHOD("register", ...)` — see the cpp file. GDScript callers (`biome_registry.gd` line 34: `template_pack.register(tmpl)`) keep working unchanged.

- [ ] **Step 3: Write the implementation**

Create `gdextension/src/resources/template_pack.cpp`:

```cpp
#include "template_pack.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/vector2i.hpp>

using namespace godot;

namespace toprogue {

int TemplatePack::register_template(const Ref<RoomTemplate> &tmpl) {
    if (tmpl.is_null()) {
        UtilityFunctions::push_error("TemplatePack.register: null template");
        return -1;
    }
    int sc = tmpl->size_class;
    Vector<Entry> &bucket = _by_size[sc];
    int idx = bucket.size();
    Entry e;
    e.tmpl = tmpl;
    e.image = Ref<Image>();
    bucket.push_back(e);
    return idx;
}

void TemplatePack::build_arrays() {
    Object *array_builder = Engine::get_singleton()->get_singleton("TextureArrayBuilder");
    if (array_builder == nullptr) {
        UtilityFunctions::push_error("TemplatePack: TextureArrayBuilder autoload missing");
        return;
    }

    for (KeyValue<int, Vector<Entry>> &kv : _by_size) {
        int sc = kv.key;
        Vector<Entry> &bucket = kv.value;
        Array images;
        for (int i = 0; i < bucket.size(); i++) {
            Entry &e = bucket.write[i];
            String path = e.tmpl.is_valid() ? e.tmpl->png_path : String();
            Ref<Image> img = Image::load_from_file(path);
            if (img.is_null()) {
                UtilityFunctions::push_error(String("TemplatePack: failed to load ") + path);
                continue;
            }
            if (img->get_width() != sc || img->get_height() != sc) {
                Ref<Image> padded = Image::create(sc, sc, false, Image::FORMAT_RGBA8);
                padded->fill(Color(0, 0, 0, 0));
                int ox = (sc - img->get_width()) / 2;
                int oy = (sc - img->get_height()) / 2;
                padded->blit_rect(img,
                                  Rect2i(0, 0, img->get_width(), img->get_height()),
                                  Vector2i(ox, oy));
                img = padded;
            }
            e.image = img;
            images.push_back(img);
        }
        if (!images.is_empty()) {
            Variant result = array_builder->call("build_from_images", images);
            _arrays[sc] = Ref<Texture2DArray>(result);
        }
    }
}

Ref<Texture2DArray> TemplatePack::get_array(int size_class) const {
    const Ref<Texture2DArray> *p = _arrays.getptr(size_class);
    return p ? *p : Ref<Texture2DArray>();
}

Ref<Image> TemplatePack::get_image(int size_class, int index) const {
    const Vector<Entry> *bucket = _by_size.getptr(size_class);
    if (bucket == nullptr) return Ref<Image>();
    if (index < 0 || index >= bucket->size()) return Ref<Image>();
    return (*bucket)[index].image;
}

Array TemplatePack::collect_markers(int size_class, int index) const {
    Array result;
    Ref<Image> img = get_image(size_class, index);
    if (img.is_null()) return result;
    int w = img->get_width();
    int h = img->get_height();
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            Color c = img->get_pixel(x, y);
            if (int(c.a8) != 255) continue;
            int marker = int(c.g8);
            if (marker > 0) {
                Dictionary d;
                d["pos"]  = Vector2i(x, y);
                d["type"] = marker;
                result.push_back(d);
            }
        }
    }
    return result;
}

Array TemplatePack::get_size_classes() const {
    Array result;
    for (const KeyValue<int, Vector<Entry>> &kv : _by_size) {
        result.push_back(kv.key);
    }
    return result;
}

int TemplatePack::template_count(int size_class) const {
    const Vector<Entry> *bucket = _by_size.getptr(size_class);
    return bucket ? bucket->size() : 0;
}

void TemplatePack::_bind_methods() {
    // Bind under the GDScript-visible name `register` (cannot be the C++ name).
    ClassDB::bind_method(D_METHOD("register", "tmpl"), &TemplatePack::register_template);
    ClassDB::bind_method(D_METHOD("build_arrays"),     &TemplatePack::build_arrays);
    ClassDB::bind_method(D_METHOD("get_array", "size_class"), &TemplatePack::get_array);
    ClassDB::bind_method(D_METHOD("get_image", "size_class", "index"), &TemplatePack::get_image);
    ClassDB::bind_method(D_METHOD("collect_markers", "size_class", "index"),
                         &TemplatePack::collect_markers);
    ClassDB::bind_method(D_METHOD("get_size_classes"), &TemplatePack::get_size_classes);
    ClassDB::bind_method(D_METHOD("template_count", "size_class"),
                         &TemplatePack::template_count);
}

} // namespace toprogue
```

**Image API note:** the godot-cpp shape of `Image::create(...)`, `Image::blit_rect(...)`, `Image::load_from_file(...)` may differ from this exact signature on the pinned SHA. If the build fails, look up the binding in `gdextension/godot-cpp/gen/include/godot_cpp/classes/image.hpp` and adapt. The semantic is fixed; the spelling may not be.

- [ ] **Step 4: Build**

```bash
./gdextension/build.sh debug
```

Expected: clean. If it fails on Image API mismatches, fix per the note above and rebuild.

- [ ] **Step 5: Commit**

```bash
git add gdextension/src/resources/template_pack.h gdextension/src/resources/template_pack.cpp
git commit -m "feat: add TemplatePack C++ class"
```

---

## Task 6: Register all five new classes in `register_types.cpp`

**Files:**
- Modify: `gdextension/src/register_types.cpp`

- [ ] **Step 1: Add includes and `GDREGISTER_CLASS` calls**

Open `gdextension/src/register_types.cpp`. Add the five resource includes near the top:

```cpp
#include "resources/biome_def.h"
#include "resources/pool_def.h"
#include "resources/room_template.h"
#include "resources/template_pack.h"
#include "resources/terrain_cell.h"
```

In `initialize_toprogue_module`, after the existing `MaterialDef`/`MaterialTable` registration but before any other code, add:

```cpp
    // Resources — register dependencies before dependents:
    // BiomeDef references PoolDef and RoomTemplate; TemplatePack references RoomTemplate.
    GDREGISTER_CLASS(TerrainCell);
    GDREGISTER_CLASS(PoolDef);
    GDREGISTER_CLASS(RoomTemplate);
    GDREGISTER_CLASS(BiomeDef);
    GDREGISTER_CLASS(TemplatePack);
```

- [ ] **Step 2: Build and confirm clean**

```bash
./gdextension/build.sh debug
```

- [ ] **Step 3: Open the editor — verify the five classes are visible**

Launch Godot 4.6 → open the project. Output log clean. Open the script editor and run a scratch expression (or add to a temporary `_ready`):

```gdscript
print(ClassDB.class_exists("BiomeDef"))      # true
print(ClassDB.class_exists("PoolDef"))       # true
print(ClassDB.class_exists("RoomTemplate"))  # true
print(ClassDB.class_exists("TerrainCell"))   # true
print(ClassDB.class_exists("TemplatePack"))  # true
```

Expected: five `true` lines. If any prints `false`, the registration didn't happen — check the `GDREGISTER_CLASS` calls and the build's output for warnings.

If you see a warning like `Class "BiomeDef" already exists` because `class_name BiomeDef` in `biome_def.gd` collides with the native registration, **that is expected at this point** — the GDScript files are still on disk and assert their `class_name` at parse time. Task 7 deletes them and the warning goes away.

Close the editor.

- [ ] **Step 4: Commit**

```bash
git add gdextension/src/register_types.cpp
git commit -m "feat: register TerrainCell, PoolDef, RoomTemplate, BiomeDef, TemplatePack"
```

---

## Task 7: Migrate `.tres` files (`script_class` form → native `type` form)

Per spec §9.3. The five `.tres` files in `assets/biomes/` reference these classes via `[ext_resource type="Script" ...]` + `script = ExtResource("...")`. After the GDScript files are deleted, those references will be dangling. The fix is mechanical: rewrite the resource header to use the native class as the `type`, drop the `script_class`, drop the script `ext_resource`, drop the `script = ExtResource(...)` lines.

**Files:**
- Create: `tools/migrate_tres.py`
- Modify: `assets/biomes/caves.tres`, `mines.tres`, `magma.tres`, `frozen.tres`, `vault.tres`

- [ ] **Step 1: Write `tools/migrate_tres.py`**

Create the script. It rewrites a single `.tres` in place. Argv = list of files. Idempotent — running twice on a migrated file is a no-op.

```python
#!/usr/bin/env python3
"""
One-shot rewrite of script-backed .tres files for step 3 of the godot-cpp port.

Before:
    [gd_resource type="Resource" script_class="BiomeDef" load_steps=2 format=3]
    [ext_resource type="Script" path="res://src/core/biome_def.gd" id="X"]
    [ext_resource type="Script" path="res://src/core/pool_def.gd" id="Y"]
    [sub_resource type="Resource" id="Z"]
    script = ExtResource("Y")
    material_id = 5

    [resource]
    script = ExtResource("X")
    display_name = "Caves"

After:
    [gd_resource type="BiomeDef" load_steps=1 format=3]
    [sub_resource type="PoolDef" id="Z"]
    material_id = 5

    [resource]
    display_name = "Caves"

The mapping from script path -> native class name is hardcoded below to the
five resources ported in step 3.
"""
import re
import sys
from pathlib import Path

SCRIPT_TO_NATIVE = {
    "res://src/core/biome_def.gd":     "BiomeDef",
    "res://src/core/pool_def.gd":      "PoolDef",
    "res://src/core/room_template.gd": "RoomTemplate",
    "res://src/core/terrain_cell.gd":  "TerrainCell",
    # template_pack.gd is RefCounted, never serialized to .tres -- not in this map.
}

EXT_RESOURCE_RE = re.compile(
    r'^\[ext_resource\s+type="Script"\s+path="([^"]+)"\s+id="([^"]+)"\]\s*$'
)
HEADER_RE = re.compile(
    r'^\[gd_resource\s+type="Resource"\s+script_class="([^"]+)"(.*)\]\s*$'
)
SUBRES_RE = re.compile(
    r'^\[sub_resource\s+type="Resource"\s+id="([^"]+)"\]\s*$'
)
SCRIPT_LINE_RE = re.compile(r'^\s*script\s*=\s*ExtResource\("([^"]+)"\)\s*$')

def migrate(path: Path) -> bool:
    """Rewrite `path` in place. Returns True if changed."""
    text = path.read_text()
    lines = text.splitlines(keepends=True)

    # Pass 1: collect script ext_resource id -> native class.
    id_to_native = {}
    for line in lines:
        m = EXT_RESOURCE_RE.match(line)
        if m:
            script_path, ext_id = m.group(1), m.group(2)
            native = SCRIPT_TO_NATIVE.get(script_path)
            if native:
                id_to_native[ext_id] = native

    if not id_to_native:
        return False  # already migrated, or no script-backed resources to rewrite

    # Pass 2: rewrite. We track which sub_resource id's native type we know,
    # by reading ahead one line for the `script = ExtResource("...")` after
    # the `[sub_resource type="Resource" id="..."]` line.
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]

        # Drop script ext_resource lines (we replaced them with native types).
        m = EXT_RESOURCE_RE.match(line)
        if m and m.group(1) in SCRIPT_TO_NATIVE:
            i += 1
            continue

        # Rewrite the gd_resource header.
        m = HEADER_RE.match(line)
        if m:
            native = m.group(1)
            tail = m.group(2)
            # Drop load_steps; Godot recomputes it on save.
            tail = re.sub(r'\s*load_steps=\d+', '', tail)
            out.append(f'[gd_resource type="{native}"{tail}]\n')
            i += 1
            continue

        # Rewrite [sub_resource type="Resource" id="..."]: peek ahead for the
        # `script = ExtResource("...")` line to learn the native type.
        m = SUBRES_RE.match(line)
        if m:
            sub_id = m.group(1)
            native = None
            # Look at the next few lines for `script = ExtResource("X")`.
            for j in range(i + 1, min(i + 5, len(lines))):
                sm = SCRIPT_LINE_RE.match(lines[j])
                if sm and sm.group(1) in id_to_native:
                    native = id_to_native[sm.group(1)]
                    break
                if lines[j].startswith('['):  # next section, stop.
                    break
            if native:
                out.append(f'[sub_resource type="{native}" id="{sub_id}"]\n')
                i += 1
                continue

        # Drop `script = ExtResource("X")` lines that point to a migrated script.
        m = SCRIPT_LINE_RE.match(line)
        if m and m.group(1) in id_to_native:
            i += 1
            continue

        out.append(line)
        i += 1

    new = "".join(out)
    if new == text:
        return False
    path.write_text(new)
    return True

def main() -> int:
    if len(sys.argv) < 2:
        print("usage: migrate_tres.py FILE [FILE ...]", file=sys.stderr)
        return 2
    changed = 0
    for arg in sys.argv[1:]:
        p = Path(arg)
        if not p.is_file():
            print(f"skip (not a file): {p}", file=sys.stderr)
            continue
        if migrate(p):
            print(f"migrated: {p}")
            changed += 1
        else:
            print(f"unchanged: {p}")
    print(f"{changed} file(s) changed.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Hand-verify on `caves.tres` first (per spec §9.3)**

```bash
chmod +x tools/migrate_tres.py
cp assets/biomes/caves.tres /tmp/caves.before.tres
python3 tools/migrate_tres.py assets/biomes/caves.tres
diff /tmp/caves.before.tres assets/biomes/caves.tres | head -60
```

Expected: the diff shows the `script_class="BiomeDef"` removed from the header (now `type="BiomeDef"`), the two `[ext_resource type="Script" ...]` lines removed, the `[sub_resource type="Resource" id="..."]` lines rewritten to `[sub_resource type="RoomTemplate" id="..."]` / `[sub_resource type="PoolDef" id="..."]`, and every `script = ExtResource("...")` line dropped. No data lines (`material_id = 5`, `display_name = "Caves"`, etc.) changed.

Open the migrated `caves.tres` in Godot 4.6 (double-click in the editor's FileSystem). Confirm the inspector shows the same values that were in the original (display_name "Caves", populated `pool_materials`, populated `room_templates`/`boss_templates`).

If anything looks wrong, restore from `/tmp/caves.before.tres` and fix the script before continuing.

- [ ] **Step 3: Run the migration on all five biome files**

```bash
python3 tools/migrate_tres.py \
    assets/biomes/caves.tres \
    assets/biomes/mines.tres \
    assets/biomes/magma.tres \
    assets/biomes/frozen.tres \
    assets/biomes/vault.tres
```

Expected: 5 file(s) changed (or 4 if you already migrated caves.tres in Step 2 and didn't restore).

- [ ] **Step 4: Open each `.tres` in the editor and confirm it loads**

Launch Godot 4.6 → open the project → in the FileSystem panel, double-click each of the five `.tres` files. The Inspector should display the resource cleanly (no "missing script", no "could not load resource"). Tab through them quickly.

If any fails to load:
- Most common cause: a `[sub_resource type="Resource" id="..."]` whose `script = ExtResource(...)` was on a non-adjacent line. Rerun the migration script with `--peek-window=20` (you'll need to add that argument) or hand-edit.
- Second cause: a `.tres` references a script `.gd` not in `SCRIPT_TO_NATIVE`. Check the file — if it really does reference some unmigrated GDScript, that's a bug; flag it.

- [ ] **Step 5: Commit (script + migrated files together)**

```bash
git add tools/migrate_tres.py assets/biomes/
git commit -m "refactor: migrate biome .tres files to native-typed resources"
```

---

## Task 8: Delete the GDScript originals

Now the C++ classes own the names; the `.tres` files reference them natively. The five `.gd` files are no longer pulled in by anything.

**Files deleted:**
- `src/core/terrain_cell.gd` + `.uid`
- `src/core/pool_def.gd` + `.uid`
- `src/core/room_template.gd` + `.uid`
- `src/core/biome_def.gd` + `.uid`
- `src/core/template_pack.gd` + `.uid`

**Files modified:**
- `src/core/terrain_physical.gd` — switch `TerrainCell.new(a, b, c, d)` to `var c := TerrainCell.new(); c.init_args(a, b, c, d); return c` (the only callsite that uses the parameterized constructor).

- [ ] **Step 1: Update `terrain_physical.gd`'s `TerrainCell.new(...)` callsites**

Open `src/core/terrain_physical.gd`. Find:

```gdscript
func _cell_from_material(mat_id: int) -> TerrainCell:
    var is_solid := MaterialTable.has_collider(mat_id)
    var is_fluid := MaterialTable.is_fluid(mat_id)
    var dmg := MaterialTable.get_damage(mat_id)
    return TerrainCell.new(mat_id, is_solid, is_fluid, dmg)
```

Replace the `return` line with:

```gdscript
    var cell := TerrainCell.new()
    cell.init_args(mat_id, is_solid, is_fluid, dmg)
    return cell
```

The other `TerrainCell.new()` (zero-arg, around line 27) stays as is — works identically against the native class.

- [ ] **Step 2: Confirm no other callsite uses the parameterized constructor**

```bash
grep -rn "TerrainCell\.new(" src/ tests/ tools/
```

Expected: only the two hits in `terrain_physical.gd` (one zero-arg, one we just rewrote) plus possibly `tests/` if a unit test exercises it. If a test uses `TerrainCell.new(mat, solid, fluid, dmg)`, apply the same shim.

- [ ] **Step 3: Capture each `.uid` value before deletion (sanity)**

```bash
for f in src/core/terrain_cell.gd src/core/pool_def.gd src/core/room_template.gd \
         src/core/biome_def.gd src/core/template_pack.gd; do
    if [ -f "$f.uid" ]; then
        echo "=== $f.uid ==="
        cat "$f.uid"
    fi
done
```

For each UID printed, search for it in the project to confirm nothing references it directly:

```bash
for uid in <paste UIDs from above, one per line>; do
    grep -rn "$uid" . 2>/dev/null | grep -v "\.uid:" || true
done
```

Expected: zero hits (or only the `.uid` files themselves, which we're about to delete). If anything references a UID, fix that reference before continuing.

- [ ] **Step 4: Delete the five `.gd` files and their `.uid` sidecars**

```bash
rm src/core/terrain_cell.gd src/core/terrain_cell.gd.uid
rm src/core/pool_def.gd     src/core/pool_def.gd.uid
rm src/core/room_template.gd src/core/room_template.gd.uid
rm src/core/biome_def.gd    src/core/biome_def.gd.uid
rm src/core/template_pack.gd src/core/template_pack.gd.uid
```

- [ ] **Step 5: Re-grep — confirm zero stale references to the deleted scripts**

```bash
grep -rn "res://src/core/terrain_cell\.gd\|res://src/core/pool_def\.gd\|res://src/core/room_template\.gd\|res://src/core/biome_def\.gd\|res://src/core/template_pack\.gd" .
```

Expected: zero hits. If a `.tres` (or `.tscn`) still references one of these paths, the migration in Task 7 missed a file — investigate and fix before committing.

```bash
grep -rn "\bTerrainCell\b\|\bPoolDef\b\|\bRoomTemplate\b\|\bBiomeDef\b\|\bTemplatePack\b" src/ tests/ tools/ assets/ project.godot \
    | wc -l
```

Compare with the inventory from Pre-flight Step 3. The new count should be lower (script files removed) but every callsite that was hitting these names must still resolve (because the names are now bound by the C++ extension).

- [ ] **Step 6: Open the editor and confirm a clean load**

Launch Godot 4.6 → open the project. Output log:
- No "Identifier 'BiomeDef' not declared".
- No "could not parse script".
- No "missing dependency" on any `.tres`.
- No "Class BiomeDef already exists" (this warning was expected during Task 6 when both the GDScript and the native class declared the same `class_name`; deleting the GDScript clears it).

Open `caves.tres`, then any one `.tscn` that references `BiomeDef`/`RoomTemplate`. Confirm clean load.

- [ ] **Step 7: Run the gdUnit4 suite**

Run gdUnit4. Pay particular attention to:
- `tests/unit/test_template_pack.gd` — exercises `TemplatePack.new()`, `register`, `build_arrays`, `get_image`, `collect_markers`. The exact API the C++ port mirrors.
- `tests/unit/test_biome_def.gd`
- `tests/unit/test_sector_grid.gd` — exercises `BiomeDef`/`RoomTemplate`.
- `tests/unit/test_terrain_physical.gd` — exercises `TerrainCell` four-arg construction (now via `init_args`).

Expected: green. If `test_terrain_physical.gd` fails on `TerrainCell.new(...)` four-arg form, update it the same way as `terrain_physical.gd` in Step 1 — the test owns its own callsite.

- [ ] **Step 8: Smoke test the runtime**

In the editor, F5 to run. Briefly:
- Generate a level (entry point on `refactor/cpp`).
- Walk through one biome; confirm rooms render (`TemplatePack` working).
- Damage a wall (touches `MaterialTable` + `TerrainCell` query path via `terrain_physical`).
- Walk into lava (touches `TerrainCell.is_fluid` + `damage`).

Expected: no crashes, no "null instance" errors. Indistinguishable from pre-step behavior.

- [ ] **Step 9: Commit**

```bash
git add src/ tests/ assets/
git commit -m "refactor: replace GDScript resources with C++-backed native types"
```

(`git add src/` stages both the deletions and the `terrain_physical.gd` edit.)

---

## Task 9: Confirm GLSL pipeline still works (compute shaders read BiomeDef/PoolDef)

The compute pipeline survives until step 7. `compute_device.gd` (still GDScript) reads `BiomeDef` and `PoolDef` to build push-constants. Step 3 changed the storage backing those types but not their property surface — the GDScript reads should still work.

- [ ] **Step 1: Confirm `compute_device.gd` is unmodified**

```bash
git status src/core/compute_device.gd
```

Expected: not in the diff for this commit. If it is, you over-touched it.

- [ ] **Step 2: F5 the project, generate a chunk, confirm it renders**

If terrain doesn't render, the compute pipeline broke — most likely cause is a `BiomeDef`/`PoolDef` field name or type that compute_device.gd reads via Variant access where the native binding spelled it differently. The native bindings preserve names exactly, so this should be a no-op — but if it isn't, the fix is in the C++ binding, not in `compute_device.gd`.

- [ ] **Step 3: No commit needed.** Verification gate.

---

## Task 10: Final verification

- [ ] **Step 1: Final greps**

```bash
grep -rn "extends Resource" src/core/
```

Expected: no hits in `src/core/` for `terrain_cell`, `pool_def`, `room_template`, `biome_def` (deleted). Other unrelated `extends Resource` files stay.

```bash
grep -rn "script_class=\"BiomeDef\"\|script_class=\"PoolDef\"\|script_class=\"RoomTemplate\"\|script_class=\"TerrainCell\"" assets/
```

Expected: zero hits.

```bash
grep -rn "res://src/core/biome_def\.gd\|res://src/core/pool_def\.gd\|res://src/core/room_template\.gd\|res://src/core/terrain_cell\.gd\|res://src/core/template_pack\.gd" .
```

Expected: zero hits.

- [ ] **Step 2: Confirm the build still produces the binary**

```bash
./gdextension/build.sh debug
ls -la bin/lib/
```

- [ ] **Step 3: Open the editor and confirm clean load + run gdUnit4**

Launch Godot 4.6 → open project → Output log clean → run gdUnit4 → all green.

- [ ] **Step 4: Smoke playthrough (~2 min)**

Per spec §10.2: launch → generate → walk through → touch gas/lava/fire/digging/combat → exit cleanly. No crashes, no visible deadlocks.

- [ ] **Step 5: Format C++ sources**

```bash
./gdextension/format.sh
git diff gdextension/src/
```

If formatter changed anything:

```bash
git add gdextension/src/
git commit -m "chore: clang-format resources sources"
```

- [ ] **Step 6: Push the branch**

```bash
git push origin refactor/cpp
```

- [ ] **Step 7: Cross-machine verification**

On the other machine:

```bash
git pull
git submodule update --init --recursive
./gdextension/build.sh debug
```

Open the project in Godot 4.6 → Output log clean → smoke-test as in Step 4.

If anything fails on the second machine that didn't fail on the first, fix and commit before declaring step 3 done.

---

## Done definition for Step 3

- `gdextension/src/resources/{terrain_cell,pool_def,room_template,biome_def,template_pack}.{h,cpp}` exist and compile clean on macOS and Arch.
- `TerrainCell`, `PoolDef`, `RoomTemplate`, `BiomeDef` are registered as native `Resource` subclasses; `TemplatePack` is a registered `RefCounted`.
- The five `.gd` files (`src/core/{terrain_cell,pool_def,room_template,biome_def,template_pack}.gd`) and their `.uid` sidecars are deleted.
- The five biome `.tres` files (`assets/biomes/*.tres`) are migrated to native-typed form (no `script_class`, no `[ext_resource type="Script" ...]`, no `script = ExtResource(...)`). They open and inspect cleanly in Godot 4.6.
- `tools/migrate_tres.py` exists, is committed, and is idempotent.
- `terrain_physical.gd`'s parameterized `TerrainCell.new(...)` callsites use the `init_args` shim.
- Zero stale `res://src/core/{terrain_cell,pool_def,room_template,biome_def,template_pack}.gd` references remain in any file.
- `compute_device.gd` and the compute pipeline still function (terrain still generates and renders).
- `gdUnit4` suite passes on both machines.
- Smoke playthrough passes on both machines.
- Game behavior is indistinguishable from `refactor/cpp` HEAD before this step (no changed values, no new fields).

When all of the above are true, Step 3 is complete. Proceed to write the plan for **Step 4 — Leaves** (`Chunk`, `SectorGrid`, `GenerationContext`) per the instructions in the "What Comes After Step 1" section of `docs/superpowers/plans/2026-04-30-step-1-bootstrap-godot-cpp.md`. The relevant spec sections for that plan are §6.1 (Cell layout), §3.2, and §9.1 step 4. Predecessor source under `gdextension/src/resources/` provides the binding patterns to mirror.
