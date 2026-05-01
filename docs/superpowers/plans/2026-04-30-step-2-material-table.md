# Step 2 — MaterialTable Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port `MaterialRegistry` (GDScript autoload) to a C++ `MaterialTable` class registered as an engine singleton. Replace every `MaterialRegistry.X` reference in GDScript with `MaterialTable.X`. Remove the old autoload and its `.gd` file.

**Architecture:** A new `MaterialTable` class under `gdextension/src/sim/` inherits from `Object`. Nine materials are hardcoded in a C++ array literal matching the current order from `material_registry.gd`. The class is registered via `ClassDB` and installed as an engine singleton via `Engine::register_singleton` during `MODULE_INITIALIZATION_LEVEL_SCENE`. GDScript callers access it identically to the old autoload: `MaterialTable.MAT_AIR`, `MaterialTable.is_flammable(id)`, `for m in MaterialTable.materials`. Shader codegen files survive (deleted in step 7).

**Tech Stack:** godot-cpp (4.x, pinned in Step 1), C++17, Engine singleton pattern.

---

## Required Reading

1. **Spec:** `docs/superpowers/specs/2026-04-30-godot-cpp-hot-path-port-design.md` sections §3.1, §3.2, §7, §9.1 step 2.
2. **Existing MaterialRegistry:** `src/autoload/material_registry.gd` — the GDScript being replaced. Must understand every method and property.
3. **Existing codegen tool:** `tools/generate_material_glsl.gd` — instantiates MaterialRegistry to produce GLSL constants.

---

## File Structure (created/modified in this plan)

```
gdextension/
├── src/
│   ├── register_types.cpp                           MODIFIED — register MaterialTable, install singleton
│   └── sim/
│       ├── material_table.h                         NEW — struct MaterialDef, class MaterialTable
│       └── material_table.cpp                       NEW — hardcoded data, method implementations
src/
├── autoload/
│   └── material_registry.gd                         DELETED — replaced by C++ class
│   └── material_registry.gd.uid                     DELETED — stale reference
├── core/
│   ├── compute_device.gd                            MODIFIED — MaterialRegistry → MaterialTable iteration
│   ├── terrain_modifier.gd                          MODIFIED — MaterialRegistry → MaterialTable
│   ├── terrain_physical.gd                          MODIFIED — MaterialRegistry → MaterialTable
│   ├── terrain_collision_helper.gd                  MODIFIED — MaterialRegistry → MaterialTable
│   └── world_manager.gd                             MODIFIED — MaterialRegistry → MaterialTable
├── console/commands/
│   └── spawn_mat_command.gd                         MODIFIED — MaterialRegistry → MaterialTable
├── weapons/
│   └── melee_weapon.gd                              MODIFIED — MaterialRegistry → MaterialTable
tools/
│   └── generate_material_glsl.gd                    MODIFIED — use C++ MaterialTable instead of loading .gd
project.godot                                        MODIFIED — remove MaterialRegistry autoload entry
```

---

## Task 1: Create `material_table.h`

**Files:**
- Create: `gdextension/src/sim/material_table.h`

- [ ] **Step 1: Create the `sim/` directory**

```bash
mkdir -p gdextension/src/sim
```

- [ ] **Step 2: Write `gdextension/src/sim/material_table.h`**

```cpp
#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/templates/vector.hpp>

namespace godot {

struct MaterialDef {
    int id = 0;
    String name;
    String texture_path;
    bool flammable = false;
    int ignition_temp = 0;
    int burn_health = 0;
    bool has_collider = false;
    bool has_wall_extension = false;
    Color tint_color;
    bool fluid = false;
    int damage = 0;
    float glow = 1.0f;
};

class MaterialTable : public Object {
    GDCLASS(MaterialTable, Object);

public:
    static const int MAT_AIR = 0;
    static const int MAT_WOOD = 1;
    static const int MAT_STONE = 2;
    static const int MAT_GAS = 3;
    static const int MAT_LAVA = 4;
    static const int MAT_DIRT = 5;
    static const int MAT_COAL = 6;
    static const int MAT_ICE = 7;
    static const int MAT_WATER = 8;
    static const int MAT_COUNT = 9;

    MaterialTable();
    ~MaterialTable();

    void populate();

    // C++ fast path (not called from GDScript)
    const MaterialDef &def(int p_id) const;

    // Bound to GDScript — match old MaterialRegistry API exactly.
    // Property getters.
    int get_MAT_AIR() const { return MAT_AIR; }
    int get_MAT_WOOD() const { return MAT_WOOD; }
    int get_MAT_STONE() const { return MAT_STONE; }
    int get_MAT_GAS() const { return MAT_GAS; }
    int get_MAT_LAVA() const { return MAT_LAVA; }
    int get_MAT_DIRT() const { return MAT_DIRT; }
    int get_MAT_COAL() const { return MAT_COAL; }
    int get_MAT_ICE() const { return MAT_ICE; }
    int get_MAT_WATER() const { return MAT_WATER; }

    // Method bindings — signatures match old MaterialRegistry exactly.
    bool is_flammable(int p_material_id) const;
    int get_ignition_temp(int p_material_id) const;
    bool has_collider(int p_material_id) const;
    bool has_wall_extension(int p_material_id) const;
    Color get_tint_color(int p_material_id) const;
    PackedInt32Array get_fluids() const;
    bool is_fluid(int p_material_id) const;
    int get_damage(int p_material_id) const;
    float get_glow(int p_material_id) const;

    // Return all materials as an Array of Dictionary so GDScript iteration
    // patterns (for m in MaterialTable.materials) continue to work.
    Array get_materials() const;

    // Bounds-checked helper, used by all getters above.
    bool _valid_id(int p_id) const;

protected:
    static void _bind_methods();

private:
    Vector<MaterialDef> defs;
};

} // namespace godot
```

- [ ] **Step 3: Commit**

```bash
git add gdextension/src/sim/material_table.h
git commit -m "feat: add MaterialTable C++ header with MaterialDef struct"
```

---

## Task 2: Create `material_table.cpp`

**Files:**
- Create: `gdextension/src/sim/material_table.cpp`

- [ ] **Step 1: Write `gdextension/src/sim/material_table.cpp`**

```cpp
#include "material_table.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

// The order of entries in this array is load-bearing. It must match the order
// that material_registry.gd produced before deletion. Changing the order
// would shift material IDs and break any .tres files that reference them.
static const MaterialDef s_material_data[MaterialTable::MAT_COUNT] = {
    /* MAT_AIR   */ { 0, "AIR",   "",                                  false,   0,   0, false, false, Color(0.0f, 0.0f, 0.0f, 0.0f), false,  0, 1.0f },
    /* MAT_WOOD  */ { 1, "WOOD",  "res://textures/Environments/Walls/plank.png", true,  180, 255, true,  true,  Color(0.0f, 0.0f, 0.0f, 0.0f), false,  0, 1.0f },
    /* MAT_STONE */ { 2, "STONE", "res://textures/Environments/Walls/stone.png", false,   0,   0, true,  true,  Color(0.0f, 0.0f, 0.0f, 0.0f), false,  0, 1.0f },
    /* MAT_GAS   */ { 3, "GAS",   "",                                  false,   0,   0, false, false, Color(0.4f, 0.9f, 0.3f, 1.0f),  true,   0, 1.0f },
    /* MAT_LAVA  */ { 4, "LAVA",  "",                                  false,   0,   0, false, false, Color(0.9f, 0.4f, 0.1f, 1.0f),  true,  10, 10.0f },
    /* MAT_DIRT  */ { 5, "DIRT",  "res://textures/Environments/Walls/dirt.png",  false,   0,   0, true,  true,  Color(0.45f, 0.32f, 0.18f, 1.0f), false,  0, 1.0f },
    /* MAT_COAL  */ { 6, "COAL",  "res://textures/Environments/Walls/coal.png",  true,  220, 200, true,  true,  Color(0.12f, 0.12f, 0.14f, 1.0f), false,  0, 20.0f },
    /* MAT_ICE   */ { 7, "ICE",   "res://textures/Environments/Walls/ice.png",   false,   0,   0, true,  true,  Color(0.7f, 0.85f, 0.95f, 1.0f),  false,  0, 1.0f },
    /* MAT_WATER */ { 8, "WATER", "",                                  false,   0,   0, true,  true,  Color(0.2f, 0.45f, 0.75f, 1.0f),  false,  0, 1.0f },
};

MaterialTable::MaterialTable() {
    for (int i = 0; i < MAT_COUNT; i++) {
        defs.push_back(s_material_data[i]);
    }
}

MaterialTable::~MaterialTable() {
}

void MaterialTable::populate() {
    // defs is already populated by the constructor. This method exists as an
    // explicit "ready" hook called during MODULE_INITIALIZATION_LEVEL_SCENE
    // in case future steps need to add post-init work.
}

const MaterialDef &MaterialTable::def(int p_id) const {
    return defs[_valid_id(p_id) ? p_id : 0];
}

bool MaterialTable::_valid_id(int p_id) const {
    return p_id >= 0 && p_id < defs.size();
}

bool MaterialTable::is_flammable(int p_material_id) const {
    return _valid_id(p_material_id) && defs[p_material_id].flammable;
}

int MaterialTable::get_ignition_temp(int p_material_id) const {
    return _valid_id(p_material_id) ? defs[p_material_id].ignition_temp : 0;
}

bool MaterialTable::has_collider(int p_material_id) const {
    return _valid_id(p_material_id) && defs[p_material_id].has_collider;
}

bool MaterialTable::has_wall_extension(int p_material_id) const {
    return _valid_id(p_material_id) && defs[p_material_id].has_wall_extension;
}

Color MaterialTable::get_tint_color(int p_material_id) const {
    return _valid_id(p_material_id) ? defs[p_material_id].tint_color : Color(0.0f, 0.0f, 0.0f, 0.0f);
}

PackedInt32Array MaterialTable::get_fluids() const {
    PackedInt32Array result;
    for (const MaterialDef &m : defs) {
        if (m.fluid) {
            result.append(m.id);
        }
    }
    return result;
}

bool MaterialTable::is_fluid(int p_material_id) const {
    return _valid_id(p_material_id) && defs[p_material_id].fluid;
}

int MaterialTable::get_damage(int p_material_id) const {
    return _valid_id(p_material_id) ? defs[p_material_id].damage : 0;
}

float MaterialTable::get_glow(int p_material_id) const {
    return _valid_id(p_material_id) ? defs[p_material_id].glow : 1.0f;
}

Array MaterialTable::get_materials() const {
    Array result;
    for (const MaterialDef &m : defs) {
        Dictionary d;
        d["id"] = m.id;
        d["name"] = m.name;
        d["texture_path"] = m.texture_path;
        d["flammable"] = m.flammable;
        d["ignition_temp"] = m.ignition_temp;
        d["burn_health"] = m.burn_health;
        d["has_collider"] = m.has_collider;
        d["has_wall_extension"] = m.has_wall_extension;
        d["tint_color"] = m.tint_color;
        d["fluid"] = m.fluid;
        d["damage"] = m.damage;
        d["glow"] = m.glow;
        result.append(d);
    }
    return result;
}

void MaterialTable::_bind_methods() {
    // Material ID constants — GDScript reads as MaterialTable.MAT_AIR etc.
    BIND_CONSTANT(MAT_AIR);
    BIND_CONSTANT(MAT_WOOD);
    BIND_CONSTANT(MAT_STONE);
    BIND_CONSTANT(MAT_GAS);
    BIND_CONSTANT(MAT_LAVA);
    BIND_CONSTANT(MAT_DIRT);
    BIND_CONSTANT(MAT_COAL);
    BIND_CONSTANT(MAT_ICE);
    BIND_CONSTANT(MAT_WATER);

    // Query methods — match old MaterialRegistry API exactly.
    ClassDB::bind_method(D_METHOD("is_flammable", "material_id"), &MaterialTable::is_flammable);
    ClassDB::bind_method(D_METHOD("get_ignition_temp", "material_id"), &MaterialTable::get_ignition_temp);
    ClassDB::bind_method(D_METHOD("has_collider", "material_id"), &MaterialTable::has_collider);
    ClassDB::bind_method(D_METHOD("has_wall_extension", "material_id"), &MaterialTable::has_wall_extension);
    ClassDB::bind_method(D_METHOD("get_tint_color", "material_id"), &MaterialTable::get_tint_color);
    ClassDB::bind_method(D_METHOD("get_fluids"), &MaterialTable::get_fluids);
    ClassDB::bind_method(D_METHOD("is_fluid", "material_id"), &MaterialTable::is_fluid);
    ClassDB::bind_method(D_METHOD("get_damage", "material_id"), &MaterialTable::get_damage);
    ClassDB::bind_method(D_METHOD("get_glow", "material_id"), &MaterialTable::get_glow);
    ClassDB::bind_method(D_METHOD("get_materials"), &MaterialTable::get_materials);

    // Expose `materials` as a property so GDScript can write
    // `for m in MaterialTable.materials` (same pattern as today).
    ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "materials"), "get_materials", "");
}

} // namespace godot
```

- [ ] **Step 2: Commit**

```bash
git add gdextension/src/sim/material_table.cpp
git commit -m "feat: add MaterialTable C++ implementation with hardcoded material data"
```

---

## Task 3: Register MaterialTable in `register_types.cpp`

**Files:**
- Modify: `gdextension/src/register_types.cpp`

- [ ] **Step 1: Read the current `gdextension/src/register_types.cpp`**

The file was created in Step 1. Open it to understand the current registration structure.

- [ ] **Step 2: Replace `register_types.cpp` with the updated version**

```cpp
#include "register_types.h"

#include <gdextension_interface.h>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "sim/material_table.h"

using namespace godot;

static MaterialTable *s_material_table = nullptr;

void initialize_toprogue_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }

    // Register MaterialTable first — every later class may reference material IDs.
    ClassDB::register_class<MaterialTable>();
    s_material_table = memnew(MaterialTable);
    Engine::get_singleton()->register_singleton("MaterialTable", s_material_table);

    // Step 3+ will register Resource subclasses, Chunk, Simulator, etc. here.
}

void uninitialize_toprogue_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }

    if (s_material_table) {
        Engine::get_singleton()->unregister_singleton("MaterialTable");
        memdelete(s_material_table);
        s_material_table = nullptr;
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

- [ ] **Step 3: Build and verify the extension compiles**

```bash
./gdextension/build.sh debug
```

Expected: SCons compiles `material_table.cpp`, links successfully, produces updated `.dylib`.

- [ ] **Step 4: Verify no link errors (class must be instantiable)**

```bash
file bin/lib/libtoprogue.macos.template_debug.dev.arm64.dylib
```

Expected: `Mach-O 64-bit dynamically linked shared library arm64`.

- [ ] **Step 5: Commit**

```bash
git add gdextension/src/register_types.cpp
git commit -m "feat: register MaterialTable as engine singleton"
```

---

## Task 4: Replace MaterialRegistry references in GDScript files

**Files:**
- Modify: 7 GDScript files (see file table above)
- Modify: `project.godot` — remove autoload entry
- Modify: `tools/generate_material_glsl.gd` — use C++ class

- [ ] **Step 1: Remove `MaterialRegistry` autoload from `project.godot`**

Open `project.godot`. Find and delete this line (around line 20):

```
MaterialRegistry="*res://src/autoload/material_registry.gd"
```

The `[autoload]` section after removal should look like:

```
[autoload]

BiomeRegistry="*res://src/autoload/biome_registry.gd"
LevelManager="*res://src/autoload/level_manager.gd"
SceneManager="*res://src/autoload/scene_manager.gd"
ConsoleManager="*res://src/autoload/console_manager.gd"
WeaponRegistry="*res://src/autoload/weapon_registry.gd"
HitReaction="*res://src/core/juice/hit_reaction.gd"
TerrainSurface="*res://src/core/terrain_surface.gd"
GameModeManager="*res://src/autoload/game_mode_manager.gd"
```

- [ ] **Step 2: Replace `MaterialRegistry` → `MaterialTable` in all GDScript files**

Run a global search-and-replace across the `src/` directory:

```bash
# macOS sed (note: use sed -i '' for BSD sed)
find src -name "*.gd" -exec sed -i '' 's/MaterialRegistry/MaterialTable/g' {} +
```

This replaces the text in these files:
- `src/weapons/melee_weapon.gd` (line ~100: `MaterialTable.get_fluids()`)
- `src/core/world_manager.gd` (line ~253: `MaterialTable.MAT_AIR`)
- `src/console/commands/spawn_mat_command.gd` (lines ~8,9,33,41: `MaterialTable.materials`, `MaterialTable.MAT_AIR`, `MaterialTable.MAT_GAS`)
- `src/core/terrain_modifier.gd` (lines ~42,44,81,83,120,162,339: `MaterialTable.MAT_*`, `MaterialTable.is_flammable()`)
- `src/core/compute_device.gd` (line ~73: `MaterialTable.materials` iteration)
- `src/core/terrain_physical.gd` (lines ~42,43,44: `MaterialTable.has_collider()`, `MaterialTable.is_fluid()`, `MaterialTable.get_damage()`)
- `src/core/terrain_collision_helper.gd` (line ~46: `MaterialTable.has_collider()`)

**Note:** `MaterialTable.get_materials()` returns `Array[Dictionary]` (not `Array[MaterialDef]`), but GDScript dot-access (`m.texture_path`, `m.tint_color`, `m.flammable`, etc.) works identically on both types. No GDScript code changes needed beyond the rename.

- [ ] **Step 3: Update `tools/generate_material_glsl.gd`**

The tool currently instantiates `material_registry.gd` via `load()` + `.new()` + `._ready()`. Replace lines 4–6:

**Old (lines 4–6):**
```gdscript
var registry_script = load("res://src/autoload/material_registry.gd")
var registry = registry_script.new()
registry._ready()
```

**New:**
```gdscript
var registry = MaterialTable.new()
```

The rest of the file (lines 8–96) accesses `registry.materials` and `registry.materials[i].name`, `.id`, `.flammable`, etc. These work unchanged thanks to `get_materials()` returning `Array[Dictionary]`.

- [ ] **Step 4: Verify no remaining `MaterialRegistry` references**

```bash
grep -r "MaterialRegistry" src/ tools/ --include="*.gd" || echo "No matches (ok)"
```

Expected: `No matches (ok)`.

- [ ] **Step 5: Verify `project.godot` has no MaterialRegistry autoload**

```bash
grep "MaterialRegistry" project.godot || echo "No matches (ok)"
```

Expected: `No matches (ok)`.

- [ ] **Step 6: Commit**

```bash
git add src/ tools/ project.godot
git commit -m "refactor: replace MaterialRegistry with C++ MaterialTable singleton"
```

---

## Task 5: Delete old MaterialRegistry files

**Files:**
- Delete: `src/autoload/material_registry.gd`
- Delete: `src/autoload/material_registry.gd.uid` (if exists)

- [ ] **Step 1: Delete the old files**

```bash
rm -f src/autoload/material_registry.gd
rm -f src/autoload/material_registry.gd.uid
```

- [ ] **Step 2: Commit**

```bash
git add src/autoload/
git commit -m "chore: remove old MaterialRegistry GDScript"
```

---

## Task 6: Build, verify, and run tests

- [ ] **Step 1: Clean build from scratch**

```bash
./gdextension/build.sh clean
./gdextension/build.sh debug
```

Expected: `scons: done building targets.` — no errors.

- [ ] **Step 2: Verify the binary is valid**

```bash
file bin/lib/libtoprogue.macos.template_debug.dev.arm64.dylib
```

Expected: `Mach-O 64-bit dynamically linked shared library arm64`.

- [ ] **Step 3: Verify the MaterialTable symbol is present in the dylib**

```bash
nm bin/lib/libtoprogue.macos.template_debug.dev.arm64.dylib | grep MaterialTable | head -5
```

Expected: several `MaterialTable` symbols (constructor, `_bind_methods`, etc.) are present — confirms the class was compiled and linked.

- [ ] **Step 4: Regenerate GLSL material constants**

The codegen tool must still produce correct output. Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --script res://tools/generate_material_glsl.gd
```

Expected output:
```
Generated shaders/generated/materials.glslinc
Generated shaders/generated/materials.gdshaderinc
```

Verify the generated file matches the expected content:

```bash
head -6 shaders/generated/materials.glslinc
```

Expected:
```
// Auto-generated by generate_material_glsl.gd
// DO NOT EDIT ...
const int MAT_COUNT = 9;
const int MAT_AIR = 0;
const int MAT_WOOD = 1;
const int MAT_STONE = 2;
```

- [ ] **Step 5: Open the project in Godot 4.6 and confirm clean load**

Launch Godot 4.6, open the project. Check the Output panel for errors.

Expected: No `MaterialTable`, `MaterialRegistry`, or `GDExtension` errors. The game should launch and play identically to before the port.

- [ ] **Step 6: Run gdUnit4 test suite**

Run tests via the Godot editor's Test panel (or gdUnit4 CLI if configured).

Expected: All tests pass — zero regressions.

- [ ] **Step 7: Run a smoke playthrough**

Launch the game scene, place gas/fire/lava, verify terrain renders and simulates correctly.

- [ ] **Step 8: Commit any stragglers and push**

```bash
git status
# Should be clean. If any generated files changed, commit them:
# git add shaders/generated/ && git commit -m "chore: regenerate GLSL materials from C++ MaterialTable"
```

---

## Done definition for Step 2

- `gdextension/src/sim/material_table.{h,cpp}` exists with 9 hardcoded materials matching the old `material_registry.gd` order.
- `register_types.cpp` registers `MaterialTable` as an engine singleton via `Engine::register_singleton`.
- No GDScript file references `MaterialRegistry` (all renamed to `MaterialTable`).
- `src/autoload/material_registry.gd` and `.uid` are deleted.
- `project.godot` has no `MaterialRegistry` autoload entry.
- `./gdextension/build.sh debug` succeeds.
- `godot --headless --script res://tools/generate_material_glsl.gd` produces correct output.
- Godot 4.6 editor opens the project without errors.
- `gdUnit4` test suite passes.
- Game plays correctly — zero behavioral changes.
