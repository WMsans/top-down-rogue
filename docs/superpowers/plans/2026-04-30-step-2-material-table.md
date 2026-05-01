# Step 2 — `MaterialTable` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `MaterialRegistry` GDScript autoload with a C++ engine singleton `MaterialTable` registered via the godot-cpp extension. The new singleton exposes the same surface (`MAT_AIR`…`MAT_WATER` integer constants, `materials` array of `MaterialDef`, `is_flammable`/`has_collider`/`get_tint_color`/etc.) so gameplay GDScript and tests need only a name swap. The hardcoded C++ array literal becomes the single source of truth for material data; `shaders/generated/materials.glslinc` stays in place this step (compute shaders still consume it; deleted in step 7).

**Architecture:** A new `gdextension/src/sim/material_table.{h,cpp}` defines `MaterialDef` (a `RefCounted` mirroring the GDScript inner class) and `MaterialTable` (an `Object` registered as an engine singleton). `register_types.cpp` registers both classes at `MODULE_INITIALIZATION_LEVEL_SCENE` and constructs the singleton with the populated material array before any other class is registered (per spec §7.4). The autoload entry `MaterialRegistry` is removed from `project.godot`; every `MaterialRegistry.X` reference in the `src/`, `tests/`, and `tools/` trees is rewritten to `MaterialTable.X` in the same commit.

**Tech Stack:** godot-cpp 4.x (already vendored at `gdextension/godot-cpp/`), C++17, the SCons + `build.sh` pipeline established in step 1. No new tooling.

---

## Required Reading Before Starting

You **must** read all of these before writing any code.

1. **Spec:** `docs/superpowers/specs/2026-04-30-godot-cpp-hot-path-port-design.md`. Mandatory sections for this step:
   - §3.1 (Removed) — confirms `material_registry.gd` is deleted; `materials.glslinc` stays this step.
   - §3.2 (Ported to C++) — the `MaterialTable` row.
   - §3.4 (Non-goals) — **"No new public methods, signals, or properties on ported classes."** This is load-bearing for step 2: do not invent `get_id(name)` etc. unless the GDScript original already exposes it.
   - §7 in full (Materials) — the C++ design. **Note:** §7.1's example signatures (`int get_id(StringName name)`) conflict with §3.4 in cases where the GDScript original doesn't expose them. The spec resolution rule (top of step 1 plan) is "spec wins", but §3.4 is also spec — so where §7.1 and §3.4 disagree, follow §3.4 (no new methods). Concretely: do not bind `get_id(StringName)` if no GDScript caller used `MaterialRegistry.get_id(...)`. Verify via grep before adding any binding.
   - §7.5 (Material-id stability) — `MAT_AIR..MAT_WATER` ids must match today's order; `.tres` files reference these ints.
   - §9.1 step 2 — what this step delivers and what survives until later steps.

2. **Predecessor source from step 1** (already merged):
   - `gdextension/src/register_types.h`
   - `gdextension/src/register_types.cpp`
   - `gdextension/SConstruct`
   - `bin/toprogue.gdextension`

3. **The class being ported:**
   - `src/autoload/material_registry.gd` (197 LOC) — the source of truth for the C++ port. The C++ class must reproduce its public surface 1:1.

4. **The codegen output that still feeds the surviving compute shaders** (read-only context — do not modify or delete this step):
   - `shaders/generated/materials.glslinc`
   - `tools/generate_material_glsl.gd` (the codegen script; runs against the old autoload)

5. **godot-cpp singleton patterns** — open `gdextension/godot-cpp/include/godot_cpp/classes/engine.hpp` and grep `register_singleton` to confirm the API shape on the pinned SHA. The reference example in the godot-cpp tree is `gdextension/godot-cpp/test/src/example.cpp` (singleton registration patterns).

If anything in this plan conflicts with the spec, the spec wins — flag the conflict and stop, do not silently deviate. The §7.1 vs §3.4 conflict above is already resolved here; do not re-litigate it during execution.

## What This Step Does NOT Do

To keep the diff bounded and the regression surface small:

- **Does not** delete `shaders/generated/materials.glslinc`, `generate_material_glsl.gd`, or any GLSL/compute pipeline code. Compute shaders still consume the codegen this step. Deletion happens in step 7 (per spec §9.1 step 7).
- **Does not** introduce new methods on `MaterialTable` beyond what `MaterialRegistry` already exposes (§3.4).
- **Does not** change the data values in any `MaterialDef` — every field's value is lifted verbatim from the `.gd` to keep behavior identical.
- **Does not** port any other class. `BiomeDef`, `Chunk`, etc. remain GDScript until their own steps.
- **Does not** touch `tools/generate_room_templates.gd`'s comment-only reference to `MaterialRegistry` (it's a comment about ID stability — irrelevant to runtime, and the tool is offline).

## Pre-flight Verification (do this first)

- [ ] **Step 1: Confirm step 1 is merged and the build is green**

```bash
git status
git log --oneline -5
./gdextension/build.sh debug
ls bin/lib/
```

Expected: clean working tree on `refactor/cpp`, recent commits include the step 1 work, build produces `libtoprogue.<platform>.template_debug.dev.<arch>.{dylib,so}`.

- [ ] **Step 2: Confirm the editor still loads the empty extension**

Launch Godot 4.6 → open the project → check the Output log. No `toprogue` / `GDExtension` errors. Close the editor.

- [ ] **Step 3: Inventory every `MaterialRegistry` callsite once, before changes**

```bash
grep -rn "MaterialRegistry" src/ tests/ tools/ project.godot
```

Save this list mentally (or to a scratch buffer). Every non-comment hit must be migrated by Task 5 step 2; the final grep in Task 7 step 1 must show zero hits in those trees.

---

## Task 1: Create `MaterialDef` and `MaterialTable` headers

**Files:**
- Create: `gdextension/src/sim/material_table.h`

- [ ] **Step 1: Create the header**

Create `gdextension/src/sim/material_table.h`:

```cpp
#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/templates/vector.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/typed_array.hpp>

namespace toprogue {

// Mirrors the inner MaterialDef class from src/autoload/material_registry.gd.
// Field names and types must match 1:1 — gameplay GDScript reads these as
// `mat.id`, `mat.name`, `mat.flammable`, etc.
class MaterialDef : public godot::RefCounted {
    GDCLASS(MaterialDef, godot::RefCounted);

protected:
    static void _bind_methods();

public:
    int     id           = 0;
    godot::String name;
    godot::String texture_path;
    bool    flammable    = false;
    int     ignition_temp = 0;
    int     burn_health  = 0;
    bool    has_collider = false;
    bool    has_wall_extension = false;
    godot::Color tint_color    = godot::Color(0, 0, 0, 0);
    bool    fluid        = false;
    int     damage       = 0;
    double  glow         = 1.0;

    // Property accessors (required for GDCLASS property bindings).
    int     get_id() const            { return id; }
    void    set_id(int v)             { id = v; }
    godot::String get_name() const    { return name; }
    void    set_name(const godot::String &v) { name = v; }
    godot::String get_texture_path() const { return texture_path; }
    void    set_texture_path(const godot::String &v) { texture_path = v; }
    bool    get_flammable() const     { return flammable; }
    void    set_flammable(bool v)     { flammable = v; }
    int     get_ignition_temp() const { return ignition_temp; }
    void    set_ignition_temp(int v)  { ignition_temp = v; }
    int     get_burn_health() const   { return burn_health; }
    void    set_burn_health(int v)    { burn_health = v; }
    bool    get_has_collider() const  { return has_collider; }
    void    set_has_collider(bool v)  { has_collider = v; }
    bool    get_has_wall_extension() const { return has_wall_extension; }
    void    set_has_wall_extension(bool v) { has_wall_extension = v; }
    godot::Color get_tint_color() const { return tint_color; }
    void    set_tint_color(const godot::Color &v) { tint_color = v; }
    bool    get_fluid() const         { return fluid; }
    void    set_fluid(bool v)         { fluid = v; }
    int     get_damage() const        { return damage; }
    void    set_damage(int v)         { damage = v; }
    double  get_glow() const          { return glow; }
    void    set_glow(double v)        { glow = v; }
};

// Engine singleton replacing the MaterialRegistry autoload.
// Singleton name (in GDScript): "MaterialTable".
//
// Material id ordering is LOAD-BEARING — existing .tres files reference
// material ids by integer (per spec §7.5). Order MUST match today's
// material_registry.gd: AIR, WOOD, STONE, GAS, LAVA, DIRT, COAL, ICE, WATER.
class MaterialTable : public godot::Object {
    GDCLASS(MaterialTable, godot::Object);

    static MaterialTable *singleton;

    godot::TypedArray<MaterialDef> materials;
    godot::HashMap<godot::String, int> by_name;

    int MAT_AIR   = -1;
    int MAT_WOOD  = -1;
    int MAT_STONE = -1;
    int MAT_GAS   = -1;
    int MAT_LAVA  = -1;
    int MAT_DIRT  = -1;
    int MAT_COAL  = -1;
    int MAT_ICE   = -1;
    int MAT_WATER = -1;

    void _populate();
    int  _add(const char *p_name,
              const char *p_texture_path,
              bool p_flammable,
              int p_ignition_temp,
              int p_burn_health,
              bool p_has_collider,
              bool p_has_wall_extension,
              godot::Color p_tint = godot::Color(0, 0, 0, 0),
              bool p_fluid = false,
              int p_damage = 0,
              double p_glow = 1.0);

protected:
    static void _bind_methods();

public:
    MaterialTable();
    ~MaterialTable();

    static MaterialTable *get_singleton();

    // Public API mirrors material_registry.gd 1:1 (spec §3.4 — no new methods).
    godot::TypedArray<MaterialDef> get_materials() const { return materials; }

    bool   is_flammable(int p_id) const;
    int    get_ignition_temp(int p_id) const;
    bool   has_collider(int p_id) const;
    bool   has_wall_extension(int p_id) const;
    godot::Color get_tint_color(int p_id) const;
    godot::PackedInt32Array get_fluids() const;
    bool   is_fluid(int p_id) const;
    int    get_damage(int p_id) const;
    double get_glow(int p_id) const;

    // MAT_* property getters (bound as read-only properties).
    int get_MAT_AIR()   const { return MAT_AIR; }
    int get_MAT_WOOD()  const { return MAT_WOOD; }
    int get_MAT_STONE() const { return MAT_STONE; }
    int get_MAT_GAS()   const { return MAT_GAS; }
    int get_MAT_LAVA()  const { return MAT_LAVA; }
    int get_MAT_DIRT()  const { return MAT_DIRT; }
    int get_MAT_COAL()  const { return MAT_COAL; }
    int get_MAT_ICE()   const { return MAT_ICE; }
    int get_MAT_WATER() const { return MAT_WATER; }
};

} // namespace toprogue
```

**Why `MaterialDef` is `RefCounted`, not a plain struct:** the existing GDScript exposes `MaterialRegistry.materials` as an array of `MaterialDef` objects with field access (`mat.id`, `mat.flammable`). Gameplay GDScript that stays — `src/console/commands/spawn_mat_command.gd` — iterates this array and reads fields by name. A `RefCounted` with bound properties is the only way to preserve that surface across the boundary without rewriting the GDScript caller.

**Why `MaterialTable` is `Object`, not `RefCounted`:** engine singletons must outlive any RefCount holders and are explicitly owned by us (`memnew` in `_init`, `memdelete` in `_deinit`). `Object` is correct per godot-cpp's singleton convention.

**`PackedInt32Array` instead of `Array[int]`:** the GDScript `get_fluids() -> Array[int]` is best mirrored by `PackedInt32Array` (typed, cheap to marshal). Callers in `melee_weapon.gd` iterate it identically. If a caller assigns it back into a `var fluids: Array[int]` typed variable and that conversion fails at runtime, fall back to `TypedArray<int>` — note this in the PR if the change is needed.

- [ ] **Step 2: Verify the file parses by running a build**

```bash
./gdextension/build.sh debug
```

Expected: build fails because `material_table.cpp` doesn't exist yet AND the header isn't included anywhere — but no preprocessor errors against the header file's own includes. Actually, since nothing pulls the header in yet, this build should succeed unchanged. That's fine — Task 2 will pull it in.

- [ ] **Step 3: Commit**

```bash
git add gdextension/src/sim/material_table.h
git commit -m "feat: add MaterialDef and MaterialTable headers"
```

---

## Task 2: Implement `MaterialTable` and `MaterialDef`

**Files:**
- Create: `gdextension/src/sim/material_table.cpp`

- [ ] **Step 1: Create the implementation file**

Create `gdextension/src/sim/material_table.cpp`. The structure is: `_bind_methods` for both classes, the populate routine pulling values verbatim from `material_registry.gd`, and the lookup methods with the same bounds-check behavior as the GDScript original.

```cpp
#include "material_table.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace toprogue {

MaterialTable *MaterialTable::singleton = nullptr;

// ---------------- MaterialDef ----------------

void MaterialDef::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_id"), &MaterialDef::get_id);
    ClassDB::bind_method(D_METHOD("set_id", "v"), &MaterialDef::set_id);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "id"), "set_id", "get_id");

    ClassDB::bind_method(D_METHOD("get_name"), &MaterialDef::get_name);
    ClassDB::bind_method(D_METHOD("set_name", "v"), &MaterialDef::set_name);
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "name"), "set_name", "get_name");

    ClassDB::bind_method(D_METHOD("get_texture_path"), &MaterialDef::get_texture_path);
    ClassDB::bind_method(D_METHOD("set_texture_path", "v"), &MaterialDef::set_texture_path);
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "texture_path"), "set_texture_path", "get_texture_path");

    ClassDB::bind_method(D_METHOD("get_flammable"), &MaterialDef::get_flammable);
    ClassDB::bind_method(D_METHOD("set_flammable", "v"), &MaterialDef::set_flammable);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "flammable"), "set_flammable", "get_flammable");

    ClassDB::bind_method(D_METHOD("get_ignition_temp"), &MaterialDef::get_ignition_temp);
    ClassDB::bind_method(D_METHOD("set_ignition_temp", "v"), &MaterialDef::set_ignition_temp);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "ignition_temp"), "set_ignition_temp", "get_ignition_temp");

    ClassDB::bind_method(D_METHOD("get_burn_health"), &MaterialDef::get_burn_health);
    ClassDB::bind_method(D_METHOD("set_burn_health", "v"), &MaterialDef::set_burn_health);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "burn_health"), "set_burn_health", "get_burn_health");

    ClassDB::bind_method(D_METHOD("get_has_collider"), &MaterialDef::get_has_collider);
    ClassDB::bind_method(D_METHOD("set_has_collider", "v"), &MaterialDef::set_has_collider);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "has_collider"), "set_has_collider", "get_has_collider");

    ClassDB::bind_method(D_METHOD("get_has_wall_extension"), &MaterialDef::get_has_wall_extension);
    ClassDB::bind_method(D_METHOD("set_has_wall_extension", "v"), &MaterialDef::set_has_wall_extension);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "has_wall_extension"), "set_has_wall_extension", "get_has_wall_extension");

    ClassDB::bind_method(D_METHOD("get_tint_color"), &MaterialDef::get_tint_color);
    ClassDB::bind_method(D_METHOD("set_tint_color", "v"), &MaterialDef::set_tint_color);
    ADD_PROPERTY(PropertyInfo(Variant::COLOR, "tint_color"), "set_tint_color", "get_tint_color");

    ClassDB::bind_method(D_METHOD("get_fluid"), &MaterialDef::get_fluid);
    ClassDB::bind_method(D_METHOD("set_fluid", "v"), &MaterialDef::set_fluid);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "fluid"), "set_fluid", "get_fluid");

    ClassDB::bind_method(D_METHOD("get_damage"), &MaterialDef::get_damage);
    ClassDB::bind_method(D_METHOD("set_damage", "v"), &MaterialDef::set_damage);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "damage"), "set_damage", "get_damage");

    ClassDB::bind_method(D_METHOD("get_glow"), &MaterialDef::get_glow);
    ClassDB::bind_method(D_METHOD("set_glow", "v"), &MaterialDef::set_glow);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "glow"), "set_glow", "get_glow");
}

// ---------------- MaterialTable ----------------

MaterialTable::MaterialTable() {
    singleton = this;
    _populate();
}

MaterialTable::~MaterialTable() {
    if (singleton == this) {
        singleton = nullptr;
    }
}

MaterialTable *MaterialTable::get_singleton() {
    return singleton;
}

int MaterialTable::_add(const char *p_name,
                        const char *p_texture_path,
                        bool p_flammable,
                        int p_ignition_temp,
                        int p_burn_health,
                        bool p_has_collider,
                        bool p_has_wall_extension,
                        Color p_tint,
                        bool p_fluid,
                        int p_damage,
                        double p_glow) {
    Ref<MaterialDef> def;
    def.instantiate();
    def->name = String::utf8(p_name);
    def->texture_path = String::utf8(p_texture_path);
    def->flammable = p_flammable;
    def->ignition_temp = p_ignition_temp;
    def->burn_health = p_burn_health;
    def->has_collider = p_has_collider;
    def->has_wall_extension = p_has_wall_extension;
    def->tint_color = p_tint;
    def->fluid = p_fluid;
    def->damage = p_damage;
    def->glow = p_glow;

    int id = (int)materials.size();
    def->id = id;
    materials.push_back(def);
    by_name[def->name] = id;
    return id;
}

void MaterialTable::_populate() {
    // ORDER IS LOAD-BEARING (spec §7.5). Existing .tres files reference these
    // ids as integers. Do not reorder. New materials append to the end.
    MAT_AIR   = _add("AIR",   "", false, 0, 0, false, false);

    MAT_WOOD  = _add("WOOD",  "res://textures/Environments/Walls/plank.png",
                     true,  180, 255, true,  true);

    MAT_STONE = _add("STONE", "res://textures/Environments/Walls/stone.png",
                     false, 0,   0,   true,  true);

    MAT_GAS   = _add("GAS",   "", false, 0, 0, false, false,
                     Color(0.4, 0.9, 0.3, 1.0), /*fluid=*/true);

    MAT_LAVA  = _add("LAVA",  "", false, 0, 0, false, false,
                     Color(0.9, 0.4, 0.1, 1.0),
                     /*fluid=*/true, /*damage=*/10, /*glow=*/10.0);

    MAT_DIRT  = _add("DIRT",  "res://textures/Environments/Walls/dirt.png",
                     false, 0, 0, true, true,
                     Color(0.45, 0.32, 0.18, 1.0));

    MAT_COAL  = _add("COAL",  "res://textures/Environments/Walls/coal.png",
                     true,  220, 200, true, true,
                     Color(0.12, 0.12, 0.14, 1.0),
                     /*fluid=*/false, /*damage=*/0, /*glow=*/20.0);

    MAT_ICE   = _add("ICE",   "res://textures/Environments/Walls/ice.png",
                     false, 0, 0, true, true,
                     Color(0.7, 0.85, 0.95, 1.0));

    MAT_WATER = _add("WATER", "", false, 0, 0, true, true,
                     Color(0.2, 0.45, 0.75, 1.0),
                     /*fluid=*/true);
}

bool MaterialTable::is_flammable(int p_id) const {
    if (p_id < 0 || p_id >= (int)materials.size()) return false;
    Ref<MaterialDef> d = materials[p_id];
    return d.is_valid() && d->flammable;
}

int MaterialTable::get_ignition_temp(int p_id) const {
    if (p_id < 0 || p_id >= (int)materials.size()) return 0;
    Ref<MaterialDef> d = materials[p_id];
    return d.is_valid() ? d->ignition_temp : 0;
}

bool MaterialTable::has_collider(int p_id) const {
    if (p_id < 0 || p_id >= (int)materials.size()) return false;
    Ref<MaterialDef> d = materials[p_id];
    return d.is_valid() && d->has_collider;
}

bool MaterialTable::has_wall_extension(int p_id) const {
    if (p_id < 0 || p_id >= (int)materials.size()) return false;
    Ref<MaterialDef> d = materials[p_id];
    return d.is_valid() && d->has_wall_extension;
}

Color MaterialTable::get_tint_color(int p_id) const {
    if (p_id < 0 || p_id >= (int)materials.size()) return Color(0, 0, 0, 0);
    Ref<MaterialDef> d = materials[p_id];
    return d.is_valid() ? d->tint_color : Color(0, 0, 0, 0);
}

PackedInt32Array MaterialTable::get_fluids() const {
    PackedInt32Array out;
    for (int i = 0; i < (int)materials.size(); i++) {
        Ref<MaterialDef> d = materials[i];
        if (d.is_valid() && d->fluid) {
            out.push_back(d->id);
        }
    }
    return out;
}

bool MaterialTable::is_fluid(int p_id) const {
    if (p_id < 0 || p_id >= (int)materials.size()) return false;
    Ref<MaterialDef> d = materials[p_id];
    return d.is_valid() && d->fluid;
}

int MaterialTable::get_damage(int p_id) const {
    if (p_id < 0 || p_id >= (int)materials.size()) return 0;
    Ref<MaterialDef> d = materials[p_id];
    return d.is_valid() ? d->damage : 0;
}

double MaterialTable::get_glow(int p_id) const {
    if (p_id < 0 || p_id >= (int)materials.size()) return 1.0;
    Ref<MaterialDef> d = materials[p_id];
    return d.is_valid() ? d->glow : 1.0;
}

void MaterialTable::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_materials"),  &MaterialTable::get_materials);
    ClassDB::bind_method(D_METHOD("is_flammable", "material_id"), &MaterialTable::is_flammable);
    ClassDB::bind_method(D_METHOD("get_ignition_temp", "material_id"), &MaterialTable::get_ignition_temp);
    ClassDB::bind_method(D_METHOD("has_collider", "material_id"), &MaterialTable::has_collider);
    ClassDB::bind_method(D_METHOD("has_wall_extension", "material_id"), &MaterialTable::has_wall_extension);
    ClassDB::bind_method(D_METHOD("get_tint_color", "material_id"), &MaterialTable::get_tint_color);
    ClassDB::bind_method(D_METHOD("get_fluids"), &MaterialTable::get_fluids);
    ClassDB::bind_method(D_METHOD("is_fluid", "material_id"), &MaterialTable::is_fluid);
    ClassDB::bind_method(D_METHOD("get_damage", "material_id"), &MaterialTable::get_damage);
    ClassDB::bind_method(D_METHOD("get_glow", "material_id"), &MaterialTable::get_glow);

    // `materials` array as a read-only property so GDScript's
    // `MaterialTable.materials` works identically to `MaterialRegistry.materials`.
    ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "materials",
                              PROPERTY_HINT_ARRAY_TYPE, "MaterialDef",
                              PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY),
                 "", "get_materials");

    // MAT_* constants as read-only int properties. Bound as getters because
    // GDScript callers read them as `MaterialTable.MAT_AIR` (property syntax).
    ClassDB::bind_method(D_METHOD("get_MAT_AIR"),   &MaterialTable::get_MAT_AIR);
    ClassDB::bind_method(D_METHOD("get_MAT_WOOD"),  &MaterialTable::get_MAT_WOOD);
    ClassDB::bind_method(D_METHOD("get_MAT_STONE"), &MaterialTable::get_MAT_STONE);
    ClassDB::bind_method(D_METHOD("get_MAT_GAS"),   &MaterialTable::get_MAT_GAS);
    ClassDB::bind_method(D_METHOD("get_MAT_LAVA"),  &MaterialTable::get_MAT_LAVA);
    ClassDB::bind_method(D_METHOD("get_MAT_DIRT"),  &MaterialTable::get_MAT_DIRT);
    ClassDB::bind_method(D_METHOD("get_MAT_COAL"),  &MaterialTable::get_MAT_COAL);
    ClassDB::bind_method(D_METHOD("get_MAT_ICE"),   &MaterialTable::get_MAT_ICE);
    ClassDB::bind_method(D_METHOD("get_MAT_WATER"), &MaterialTable::get_MAT_WATER);

    ADD_PROPERTY(PropertyInfo(Variant::INT, "MAT_AIR",   PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "get_MAT_AIR");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "MAT_WOOD",  PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "get_MAT_WOOD");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "MAT_STONE", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "get_MAT_STONE");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "MAT_GAS",   PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "get_MAT_GAS");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "MAT_LAVA",  PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "get_MAT_LAVA");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "MAT_DIRT",  PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "get_MAT_DIRT");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "MAT_COAL",  PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "get_MAT_COAL");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "MAT_ICE",   PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "get_MAT_ICE");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "MAT_WATER", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "get_MAT_WATER");
}

} // namespace toprogue
```

- [ ] **Step 2: Build to confirm it compiles standalone (registration comes next)**

```bash
./gdextension/build.sh debug
```

Expected: compiles cleanly. No registration of the class yet, so the binary contains the symbols but doesn't expose them to Godot. That's fine — Task 3 wires registration.

If the build fails on `TypedArray<MaterialDef>` includes, add `#include <godot_cpp/classes/typed_array.hpp>` to the header. The exact include path can shift between godot-cpp commits; trust the compiler error.

- [ ] **Step 3: Commit**

```bash
git add gdextension/src/sim/material_table.cpp
git commit -m "feat: implement MaterialTable singleton and MaterialDef"
```

---

## Task 3: Register `MaterialTable` and `MaterialDef` from `register_types.cpp`

**Files:**
- Modify: `gdextension/src/register_types.cpp`

- [ ] **Step 1: Update `initialize_toprogue_module` to register the classes and create the singleton**

Open `gdextension/src/register_types.cpp` and replace its current initializer / terminator bodies. The full updated file:

```cpp
#include "register_types.h"

#include "sim/material_table.h"

#include <gdextension_interface.h>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/core/memory.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;
using namespace toprogue;

static MaterialTable *g_material_table = nullptr;

void initialize_toprogue_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }

    // MaterialDef registered first (used by MaterialTable's typed array).
    GDREGISTER_CLASS(MaterialDef);
    GDREGISTER_CLASS(MaterialTable);

    g_material_table = memnew(MaterialTable);
    Engine::get_singleton()->register_singleton("MaterialTable", g_material_table);
}

void uninitialize_toprogue_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }

    Engine::get_singleton()->unregister_singleton("MaterialTable");
    if (g_material_table) {
        memdelete(g_material_table);
        g_material_table = nullptr;
    }
}

extern "C" {
GDExtensionBool GDE_EXPORT toprogue_library_init(
        GDExtensionInterfaceGetProcAddress p_get_proc_address,
        GDExtensionClassLibraryPtr p_library,
        GDExtensionInitialization *r_initialization) {
    GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

    init_obj.register_initializer(initialize_toprogue_module);
    init_obj.register_terminator(uninitialize_toprogue_module);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

    return init_obj.init();
}
}
```

`MaterialDef` must be registered before `MaterialTable` because `MaterialTable`'s `materials` property references `MaterialDef` by name in its `PROPERTY_HINT_ARRAY_TYPE` hint.

- [ ] **Step 2: Build**

```bash
./gdextension/build.sh debug
```

Expected: clean build.

- [ ] **Step 3: Open the editor and confirm the singleton is visible**

Launch Godot 4.6 → open the project → Output log clean. Then in the editor's bottom panel, open the Script editor and run a scratch GDScript expression via the Debugger's expression evaluator (or temporarily add `print(MaterialTable.MAT_LAVA)` to any `_ready()` you can quickly trigger):

Expected: prints `4` (LAVA's id, matching today's `MaterialRegistry.MAT_LAVA`).

If you see "Identifier 'MaterialTable' not declared in current scope", the singleton didn't register. Check the Output log for "register_singleton" errors and confirm the `Engine::get_singleton()->register_singleton(...)` line ran (add a `UtilityFunctions::print("MaterialTable registered")` if needed for debugging — remove before commit).

Close the editor.

- [ ] **Step 4: Commit**

```bash
git add gdextension/src/register_types.cpp
git commit -m "feat: register MaterialTable as engine singleton"
```

---

## Task 4: Snapshot the GDScript API surface (parity check)

This task captures expected outputs *before* deleting the GDScript original, so step 5 can verify the C++ singleton produces identical values.

**Files:**
- Create: `gdextension/src/sim/material_table_parity.txt` (working file, deleted at end of step)

- [ ] **Step 1: Write a temporary GDScript that prints every field of every material from `MaterialRegistry`**

Create a throwaway scene/script (or use the editor's Output via a tool script). The values to print, for each of `MAT_AIR..MAT_WATER`:

```
id, name, texture_path, flammable, ignition_temp, burn_health,
has_collider, has_wall_extension, tint_color, fluid, damage, glow
```

Plus `MaterialRegistry.get_fluids()` (an array of ints).

Run it once and capture output to `gdextension/src/sim/material_table_parity.txt`.

- [ ] **Step 2: Repeat the same prints against `MaterialTable` (the new singleton)**

Modify the throwaway script to also print the same set against `MaterialTable`. Diff the two outputs.

Expected: byte-identical except for object identity (`<MaterialDef#...>` instance ids will differ — only the field values matter).

If anything differs: the C++ `_populate()` got a value wrong. Fix it. The values in `material_registry.gd` are authoritative; if you see a divergence that looks like a "bug" in the GDScript original, do not silently fix it — flag in the PR description and keep the value identical for now.

- [ ] **Step 3: Delete the parity file (do not commit it)**

```bash
rm gdextension/src/sim/material_table_parity.txt
```

The parity check itself is not committed — its only purpose is to gate Task 5. Once parity is confirmed, the file is throwaway.

- [ ] **Step 4: No commit for this task** (deliverable is the verification, not a code change).

---

## Task 5: Migrate every `MaterialRegistry` callsite to `MaterialTable`

**Files modified:**
- `project.godot` (autoload entry removed)
- `src/console/commands/spawn_mat_command.gd`
- `src/weapons/melee_weapon.gd`
- `src/core/terrain_modifier.gd`
- `src/core/world_manager.gd`
- `src/core/terrain_physical.gd`
- `src/core/terrain_collision_helper.gd`
- `src/core/compute_device.gd` (still exists this step; will be deleted in step 7)
- `tests/unit/test_terrain_physical.gd`

**Files NOT modified:**
- `tools/generate_room_templates.gd` (the only `MaterialRegistry` mention is a comment about ID stability — leave the comment, the tool is offline)
- `tools/generate_material_glsl.gd` (the codegen script — runs against the OLD autoload to produce the GLSL still consumed by surviving compute shaders; do not touch this step, it's deleted in step 7)
- `shaders/generated/materials.glslinc` (still consumed by compute shaders)

- [ ] **Step 1: Remove the autoload entry from `project.godot`**

Open `project.godot` and delete this line under `[autoload]`:

```
MaterialRegistry="*res://src/autoload/material_registry.gd"
```

The other autoloads stay.

- [ ] **Step 2: Rewrite all callsites with a name swap**

For each file in the list above, replace every `MaterialRegistry` token with `MaterialTable`. The API is intentionally identical, so this is a pure name swap — no signature changes.

The fastest mechanical path:

```bash
# Get the canonical list of files to touch (excludes docs/tools).
grep -rln "MaterialRegistry" src/ tests/ | sort -u
```

For each file, do an in-editor find-and-replace of the literal string `MaterialRegistry` → `MaterialTable`. **Do not** use a blanket `sed -i` against `tools/`, `docs/`, or anywhere outside `src/` and `tests/` — the docs and `tools/generate_material_glsl.gd` retain references intentionally.

- [ ] **Step 3: Delete the old GDScript autoload**

```bash
rm src/autoload/material_registry.gd
rm src/autoload/material_registry.gd.uid 2>/dev/null || true
```

If a `.uid` exists, search for it once before deleting — confirm nothing references the UID:

```bash
grep -rn "$(cat src/autoload/material_registry.gd.uid 2>/dev/null)" . 2>/dev/null || echo "no UID refs"
```

Expected: no hits (or the UID file already absent).

- [ ] **Step 4: Verify zero remaining refs in code paths**

```bash
grep -rn "MaterialRegistry" src/ tests/ project.godot
```

Expected: zero hits.

```bash
grep -rn "MaterialRegistry" tools/
```

Expected: hits only in `tools/generate_room_templates.gd` (comment) and `tools/generate_material_glsl.gd` (codegen, deleted in step 7). Both are intentional this step.

- [ ] **Step 5: Open the editor and confirm a clean load**

Launch Godot 4.6 → open the project → Output log. Specifically verify:
- No "Identifier 'MaterialRegistry' not declared in current scope" errors.
- No "Autoload script not found".
- No "Could not parse" errors in any `.gd` file.

Open one or two of the touched scripts (`spawn_mat_command.gd`, `terrain_modifier.gd`) and confirm the script editor shows no red errors.

- [ ] **Step 6: Run the gdUnit4 suite**

Run the `gdUnit4` suite via the editor's Test panel (or CLI). Pay particular attention to `tests/unit/test_terrain_physical.gd` since it directly exercises `MaterialTable.MAT_WOOD` / `MAT_STONE`.

Expected: green. If a test that was previously green now fails, the regression is in this step's changes — investigate before proceeding.

- [ ] **Step 7: Smoke test the game runtime**

In the editor, F5 to run the project. Briefly:
- Generate a level (whatever the current entry point is on `refactor/cpp`).
- Open the console and run a `spawn_mat` command (this exercises `spawn_mat_command.gd` which iterates `MaterialTable.materials` — high-value path).
- Damage a flammable wall (exercises `is_flammable` / `terrain_modifier`).
- Walk into lava (exercises `is_fluid` + `get_damage` via `terrain_physical`).

Expected: no crashes, no "null instance" errors in the Output log, materials behave the same as before.

- [ ] **Step 8: Commit**

```bash
git add project.godot src/ tests/
git commit -m "refactor: replace MaterialRegistry autoload with MaterialTable singleton"
```

(`git add src/` will stage the deletion of `material_registry.gd` along with the modifications.)

---

## Task 6: Confirm GLSL pipeline still works (compute shaders consume the old generated header)

The compute shaders surviving until step 7 read `shaders/generated/materials.glslinc`. This file is checked in; nothing about step 2 should regenerate it. But verify it's still present and the compute pipeline still functions.

- [ ] **Step 1: Confirm the generated header exists and is unchanged**

```bash
ls shaders/generated/materials.glslinc
git status shaders/generated/
```

Expected: file present, no modifications staged or unstaged.

- [ ] **Step 2: Run the game and confirm terrain still generates and renders**

In the editor, F5. Generate a chunk. The chunk should render as before — if it doesn't, the compute pipeline is broken (likely because something in `compute_device.gd` lost a reference). Re-check the changes to `src/core/compute_device.gd` from Task 5 step 2.

- [ ] **Step 3: No commit needed** (this is a verification gate; if it failed, fix in Task 5).

---

## Task 7: Final verification

- [ ] **Step 1: Final grep**

```bash
grep -rn "MaterialRegistry" src/ tests/ project.godot
```

Expected: zero hits.

```bash
grep -rn "MaterialTable" src/ tests/
```

Expected: hits in every file touched by Task 5 step 2. None of them should be inside a comment that says "TODO" or "FIXME".

- [ ] **Step 2: Confirm `bin/lib/` contains a fresh debug binary**

```bash
./gdextension/build.sh debug
ls -la bin/lib/
```

- [ ] **Step 3: Confirm the editor opens cleanly and gdUnit4 passes**

Launch Godot 4.6 → open project → Output log clean → run gdUnit4 → all green.

- [ ] **Step 4: Smoke playthrough (~2 min)**

Per spec §10.2: launch → generate → walk through → touch gas/lava/fire/digging/combat → exit cleanly. No crashes, no visible deadlocks.

- [ ] **Step 5: Format C++ sources**

```bash
./gdextension/format.sh
git diff gdextension/src/
```

If the formatter changed anything, commit the formatting:

```bash
git add gdextension/src/
git commit -m "chore: clang-format MaterialTable sources"
```

- [ ] **Step 6: Push the branch**

```bash
git push origin refactor/cpp
```

- [ ] **Step 7: Cross-machine verification**

On the other machine (Arch if you've been on macOS, or vice versa):

```bash
git pull
git submodule update --init --recursive   # no-op if submodule SHA unchanged
./gdextension/build.sh debug
```

Open the project in Godot 4.6 → Output log clean → smoke-test as in step 4.

If anything fails here that didn't fail on machine 1, fix and commit before declaring step 2 done.

---

## Done definition for Step 2

- `gdextension/src/sim/material_table.{h,cpp}` exist and compile clean on macOS and Arch.
- `MaterialTable` is registered as an engine singleton; `MaterialDef` is a registered `RefCounted`.
- Material id ordering matches `material_registry.gd` (AIR=0 … WATER=8). Per-material field values match byte-for-byte (verified via Task 4).
- `src/autoload/material_registry.gd` is deleted; `MaterialRegistry` autoload entry removed from `project.godot`.
- Zero `MaterialRegistry` references remain in `src/`, `tests/`, or `project.godot`. References in `tools/generate_material_glsl.gd` and `tools/generate_room_templates.gd` are expected and intentional this step.
- `shaders/generated/materials.glslinc` still exists, unchanged. Compute pipeline still functions (terrain still generates and renders).
- `gdUnit4` suite passes on both machines.
- Smoke playthrough passes on both machines.
- Game behavior is indistinguishable from `refactor/cpp` HEAD before this step (no new materials, no changed material values).

When all of the above are true, Step 2 is complete. Proceed to write the plan for **Step 3 — Resources** (`TerrainCell`, `BiomeDef`, `PoolDef`, `RoomTemplate`, `TemplatePack`) per the instructions in the "What Comes After Step 1" section of `docs/superpowers/plans/2026-04-30-step-1-bootstrap-godot-cpp.md`. The relevant spec sections for that plan are §3.2, §9.1 step 3, and §9.3 (`.tres` migration).
