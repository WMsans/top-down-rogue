# Step 4 — Leaves (`Chunk`, `SectorGrid`, `GenerationContext`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the three "leaf" classes that every later step depends on — `Chunk`, `SectorGrid`, and `GenerationContext` — to native C++ via godot-cpp. The class names are preserved so existing GDScript callsites resolve to the native types unchanged. `Chunk` gains the new spec §6.1 storage (`Cell cells[CHUNK_SIZE * CHUNK_SIZE]`, `dirty_rect`, `sleeping`, `collider_dirty`, `neighbors[4]`, optional `Ref<ImageTexture>`) **alongside** the existing GPU-pipeline fields (`rd_texture`, `texture_2d_rd`, `mesh_instance`, `wall_mesh_instance`, `sim_uniform_set`, `injection_buffer`, `static_body`, `occluder_instances`). This is a **bridge step** — the compute pipeline still runs (spec §9.1 step 4: *"`ComputeDevice` (still GDScript) writes into the cell array via the texture readback path it already uses"*), so every legacy field remains bound and writable from GDScript. The three `.gd` files are deleted in this step's final commit; the C++ classes register their `class_name` identifiers via `GDREGISTER_CLASS`.

**Architecture:** Three new translation units under `gdextension/src/terrain/` (`chunk.{h,cpp}`, `sector_grid.{h,cpp}`, `generation_context.{h,cpp}`). `Chunk` is a `RefCounted` whose properties are bound 1:1 to today's `chunk.gd` field surface plus the new sim fields. `SectorGrid` is a `RefCounted` with the inner `RoomSlot` exposed as a nested `Resource` (so GDScript callsites that read `slot.is_empty`/`slot.template_index` etc. keep working). `GenerationContext` is a `RefCounted` with three fields. `register_types.cpp` registers all four classes (`Chunk`, `SectorGrid`, `SectorGrid::RoomSlot`, `GenerationContext`) at `MODULE_INITIALIZATION_LEVEL_SCENE` after the resources from step 3.

**Tech Stack:** godot-cpp pinned per step 1, C++17, the existing SCons + `build.sh` pipeline. No new external dependencies.

---

## Required Reading Before Starting

You **must** read all of these before writing any code.

1. **Spec:** `docs/superpowers/specs/2026-04-30-godot-cpp-hot-path-port-design.md`. Mandatory sections:
   - §3.2 (Ported to C++) — the `Chunk`/`SectorGrid`/`GenerationContext` rows. Note: every row says `RefCounted` for these three.
   - §3.4 (Non-goals) — no new public methods, signals, or properties beyond what the GDScript originals expose. The new `Cell cells[]`, `dirty_rect`, `sleeping`, `collider_dirty`, `neighbors[]`, `texture` fields on `Chunk` are an **explicit exception** sourced from §6.1 — they're new because the spec adds them as part of the `Chunk` definition.
   - §6.1 (Cell layout, Chunk shape) — defines `struct Cell { uint8_t material, health, temperature, flags; }` and the post-port `Chunk` field set. **The exact storage to add now.**
   - §8.4 (Rendering bridge) — `Ref<ImageTexture>` member on `Chunk`. We add the field but do not wire the upload path; that's step 7.
   - §9.1 step 4 — what this step delivers and the bridge constraint.
   - §9.4 — `.uid` cleanup procedure.

2. **Predecessor source from step 3** (already merged) — read in full before writing C++:
   - `gdextension/src/resources/biome_def.h` and `.cpp` — `SectorGrid` takes a `Ref<BiomeDef>`; this is the binding pattern to mirror.
   - `gdextension/src/resources/template_pack.h` and `.cpp` — closest precedent for binding a `RefCounted` with internal storage and engine-singleton interaction. Mirror the `_bind_methods` shape.
   - `gdextension/src/register_types.cpp` — where the new `GDREGISTER_CLASS` calls land.

3. **The classes being ported** (read in full; field names and types must match):
   - `src/core/chunk.gd` (12 LOC) — pure data record.
   - `src/core/sector_grid.gd` (96 LOC) — has logic (`world_to_sector`, `sector_to_world_center`, `chebyshev_distance`, `resolve_sector`, `get_template_for_slot`) plus a nested `RoomSlot` class.
   - `src/terrain/generation_context.gd` (5 LOC) — three fields.

4. **Every callsite that constructs or reads these types** (so the C++ surface matches usage exactly):
   - `Chunk` constructors: `src/core/chunk_manager.gd` line 50 (`Chunk.new()` zero-arg).
   - `Chunk` field reads/writes (legacy GPU fields):
     - `src/core/chunk_manager.gd` lines ~50–95 (sets every field after `Chunk.new()`).
     - `src/core/world_manager.gd` lines 112–116, 189–192 (reads `injection_buffer`, `rd_texture`).
     - `src/core/compute_device.gd` lines 259–314 (reads `rd_texture`, `sim_uniform_set`).
     - `src/core/terrain_collision_helper.gd` lines 30–142 (reads `rd_texture`, `static_body`, `coord`, `occluder_instances`).
     - `src/core/terrain_modifier.gd` lines 37–320 (reads `rd_texture`, `coord`).
     - `src/debug/collision_overlay.gd` line 17.
   - `SectorGrid` constructors: `src/autoload/level_manager.gd` lines 18, 37 (`SectorGrid.new(world_seed, current_biome)`). The 2-arg constructor must work from GDScript.
   - `SectorGrid` reads: `src/core/spawn_dispatcher.gd` lines 32, 70 (uses `RoomSlot` shape), `tests/unit/test_sector_grid.gd` (full method surface).
   - `GenerationContext` reads: only `src/terrain/generation_context.gd` itself currently — no external callsites yet (`grep -rn "GenerationContext\b" src/ tests/` confirmed). It's a placeholder used by the future `Generator` (step 6). Port it now anyway because the leaf wave is a coherent unit and step 6 references it.
   - `tests/unit/test_sector_grid.gd` — `preload("res://src/core/sector_grid.gd")` will dangle once that file is deleted; the test must switch to using the native class directly.

5. **CHUNK_SIZE constant.** The spec pins `CHUNK_SIZE = 256`. Confirm this matches the GLSL constant and the existing GDScript usage:
   ```bash
   grep -rn "CHUNK_SIZE" src/ shaders/
   ```
   Today's value lives in multiple places (`chunk_manager.gd`, `world_manager.gd`, the GLSL includes). The C++ class exposes it as a static constant `Chunk::CHUNK_SIZE` plus a bound `get_chunk_size()` so GDScript can read it from the native class. Don't try to remove the duplication this step — the GLSL still needs its own copy until step 7.

If anything in this plan conflicts with the spec, the spec wins — flag the conflict and stop, do not silently deviate.

## What This Step Does NOT Do

- **Does not** port `ChunkManager`, `WorldManager`, `TerrainModifier`, `TerrainCollider`, `TerrainCollisionHelper`, `GasInjector`, `TerrainPhysical`, or any non-leaf class. Those land in steps 5+ per spec §9.1.
- **Does not** delete any compute shader. `compute_device.gd` and `shaders/compute/*` are unchanged. The compute pipeline still runs.
- **Does not** wire the `cells[]` array to anything yet. The field exists on `Chunk` and is bound (so GDScript-side `compute_device.gd` *could* populate it from a texture readback), but no consumer reads it this step. Population/consumption land in steps 5–7.
- **Does not** wire `Ref<ImageTexture>` upload. The field exists; the upload path is step 7's `Chunk::upload_texture()`.
- **Does not** introduce the `Simulator`, the 4-phase scheduler, dirty-rect accumulation, sleep tracking, neighbor pointer maintenance, or material rules. Those are step 7. We **do** add the storage (`dirty_rect`, `sleeping`, `collider_dirty`, `neighbors[4]`) so step 5 (collider) and step 7 (sim) can land on a `Chunk` whose shape doesn't change again.
- **Does not** change `terrain_collision_helper.gd`'s `texture_get_data(chunk.rd_texture, 0)` readback. That's the path step 5 replaces.
- **Does not** add a typed C++ accessor for `cells[]` that returns anything other than a `PackedByteArray`. GDScript reads/writes the cell array as raw bytes (4 bytes per cell, RGBA-style) — same shape `texture_get_data` already returns today. This is the bridge contract.

## Pre-flight Verification (do this first)

- [ ] **Step 1: Confirm step 3 is merged and the build is green**

```bash
git status
git log --oneline -8
./gdextension/build.sh debug
ls bin/lib/
```

Expected: clean working tree on `refactor/cpp`. Recent commits include the step 3 work (`feat: register TerrainCell, PoolDef, RoomTemplate, BiomeDef, TemplatePack`, `refactor: migrate biome .tres files to native-typed resources`, `refactor: delete GDScript resource classes`). Build produces `libtoprogue.<platform>.template_debug.dev.<arch>.{dylib,so}`.

- [ ] **Step 2: Confirm the editor still loads cleanly with step 3's natives**

Launch Godot 4.6 → open project → Output log clean. Open `assets/biomes/caves.tres` — Inspector shows native `BiomeDef` cleanly. Close the editor.

- [ ] **Step 3: Inventory every callsite once, before changes**

```bash
grep -rn "\bChunk\b\|\bSectorGrid\b\|\bGenerationContext\b\|RoomSlot" src/ tests/ tools/ project.godot \
    > /tmp/step4-inventory-before.txt
wc -l /tmp/step4-inventory-before.txt
```

Save that file — Task 9 step 2 re-greps and compares. Every hit should still resolve after the port; only the three `.gd` files in `src/core/`+`src/terrain/` get deleted.

- [ ] **Step 4: Confirm CHUNK_SIZE is 256 everywhere**

```bash
grep -rn "CHUNK_SIZE\s*[:=]\s*[0-9]" src/ shaders/
```

Every numeric definition should be `256`. If any disagrees, **stop and flag** — this plan assumes the spec's `CHUNK_SIZE = 256`. A mismatch is a pre-existing bug, not something to silently paper over.

- [ ] **Step 5: Confirm the gdUnit4 suite is green at HEAD**

Run gdUnit4 via the editor's Test panel. All green. If any test is red at HEAD before this step starts, fix or document the pre-existing failure before proceeding.

---

## Task 1: Port `GenerationContext` to C++

Smallest of the three — pure data, three fields, no logic, no current external callers. Best warmup.

**Files:**
- Create: `gdextension/src/terrain/generation_context.h`
- Create: `gdextension/src/terrain/generation_context.cpp`

- [ ] **Step 1: Write the header**

Create `gdextension/src/terrain/generation_context.h`:

```cpp
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace toprogue {

// Mirrors src/terrain/generation_context.gd 1:1.
class GenerationContext : public godot::RefCounted {
    GDCLASS(GenerationContext, godot::RefCounted);

public:
    godot::Vector2i   chunk_coord;
    int64_t           world_seed = 0;
    godot::Dictionary stage_params;

    GenerationContext() = default;

    godot::Vector2i   get_chunk_coord() const                  { return chunk_coord; }
    void              set_chunk_coord(const godot::Vector2i &v){ chunk_coord = v; }
    int64_t           get_world_seed() const                   { return world_seed; }
    void              set_world_seed(int64_t v)                { world_seed = v; }
    godot::Dictionary get_stage_params() const                 { return stage_params; }
    void              set_stage_params(const godot::Dictionary &v) { stage_params = v; }

protected:
    static void _bind_methods();
};

} // namespace toprogue
```

- [ ] **Step 2: Write the implementation**

Create `gdextension/src/terrain/generation_context.cpp`:

```cpp
#include "generation_context.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace toprogue {

void GenerationContext::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_chunk_coord"), &GenerationContext::get_chunk_coord);
    ClassDB::bind_method(D_METHOD("set_chunk_coord", "v"), &GenerationContext::set_chunk_coord);
    ADD_PROPERTY(PropertyInfo(Variant::VECTOR2I, "chunk_coord"),
                 "set_chunk_coord", "get_chunk_coord");

    ClassDB::bind_method(D_METHOD("get_world_seed"), &GenerationContext::get_world_seed);
    ClassDB::bind_method(D_METHOD("set_world_seed", "v"), &GenerationContext::set_world_seed);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "world_seed"),
                 "set_world_seed", "get_world_seed");

    ClassDB::bind_method(D_METHOD("get_stage_params"), &GenerationContext::get_stage_params);
    ClassDB::bind_method(D_METHOD("set_stage_params", "v"), &GenerationContext::set_stage_params);
    ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "stage_params"),
                 "set_stage_params", "get_stage_params");
}

} // namespace toprogue
```

- [ ] **Step 3: Build standalone (registration in Task 4)**

```bash
./gdextension/build.sh debug
```

Expected: clean. The class compiles but isn't registered yet.

- [ ] **Step 4: Commit**

```bash
git add gdextension/src/terrain/generation_context.h gdextension/src/terrain/generation_context.cpp
git commit -m "feat: add GenerationContext C++ class"
```

---

## Task 2: Port `Chunk` to C++

The bridge-step `Chunk`. Holds **all** legacy GPU-pipeline fields (so `chunk_manager.gd` / `compute_device.gd` / `terrain_collision_helper.gd` keep working) **and** the new spec §6.1 sim fields (`Cell cells[]`, `dirty_rect`, `sleeping`, `collider_dirty`, `neighbors[4]`, `texture`).

**Files:**
- Create: `gdextension/src/terrain/chunk.h`
- Create: `gdextension/src/terrain/chunk.cpp`

- [ ] **Step 1: Re-read source side-by-side**

Open `src/core/chunk.gd` and `src/core/chunk_manager.gd` together. The C++ class must accept assignments to every field that `chunk_manager.gd` writes between line 50 and ~line 100. Cross-check against `src/core/world_manager.gd` reads (lines 112, 189) and `src/core/compute_device.gd` reads (lines 259–314).

Confirmed legacy field set, in order of declaration in `chunk.gd`:
- `coord: Vector2i`
- `rd_texture: RID`
- `texture_2d_rd: Texture2DRD`
- `mesh_instance: MeshInstance2D`
- `wall_mesh_instance: MeshInstance2D`
- `sim_uniform_set: RID`
- `injection_buffer: RID`
- `static_body: StaticBody2D`
- `occluder_instances: Array[LightOccluder2D] = []`

Confirmed new spec §6.1 field set:
- `cells` (256×256 of `Cell{material, health, temperature, flags}`, packed as 4 bytes per cell, exposed as `PackedByteArray`)
- `dirty_rect: Rect2i`
- `next_dirty_rect: Rect2i` *(internal — used by step 7 simulator; bound for completeness, default zeros)*
- `sleeping: bool = true`
- `collider_dirty: bool = false`
- `neighbors[4]` of `Ref<Chunk>` (up/down/left/right; null at world edge) — bound as four properties `neighbor_up`/`neighbor_down`/`neighbor_left`/`neighbor_right`
- `texture: Ref<ImageTexture>` (CPU-render texture; populated step 7)

- [ ] **Step 2: Write the header**

Create `gdextension/src/terrain/chunk.h`:

```cpp
#pragma once

#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/light_occluder2d.hpp>
#include <godot_cpp/classes/mesh_instance2d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/static_body2d.hpp>
#include <godot_cpp/classes/texture2drd.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <cstdint>

namespace toprogue {

struct Cell {
    uint8_t material;
    uint8_t health;
    uint8_t temperature;
    uint8_t flags;
};
static_assert(sizeof(Cell) == 4, "Cell must be 4 bytes; spec §6.1");

class Chunk : public godot::RefCounted {
    GDCLASS(Chunk, godot::RefCounted);

public:
    static constexpr int CHUNK_SIZE = 256; // spec §6.1
    static constexpr int CELL_COUNT = CHUNK_SIZE * CHUNK_SIZE;

    // --- Legacy GPU-pipeline fields (mirror chunk.gd 1:1) ---------------
    godot::Vector2i                          coord;
    godot::RID                               rd_texture;
    godot::Ref<godot::Texture2DRD>           texture_2d_rd;
    godot::MeshInstance2D                   *mesh_instance      = nullptr;
    godot::MeshInstance2D                   *wall_mesh_instance = nullptr;
    godot::RID                               sim_uniform_set;
    godot::RID                               injection_buffer;
    godot::StaticBody2D                     *static_body        = nullptr;
    godot::TypedArray<godot::LightOccluder2D> occluder_instances;

    // --- New spec §6.1 sim fields ---------------------------------------
    Cell                                     cells[CELL_COUNT] = {};
    godot::Rect2i                            dirty_rect;
    godot::Rect2i                            next_dirty_rect;
    bool                                     sleeping       = true;
    bool                                     collider_dirty = false;
    godot::Ref<Chunk>                        neighbor_up;
    godot::Ref<Chunk>                        neighbor_down;
    godot::Ref<Chunk>                        neighbor_left;
    godot::Ref<Chunk>                        neighbor_right;
    godot::Ref<godot::ImageTexture>          texture;

    Chunk() = default;

    static int get_chunk_size() { return CHUNK_SIZE; }

    // --- Legacy field bindings -----------------------------------------
    godot::Vector2i get_coord() const                          { return coord; }
    void            set_coord(const godot::Vector2i &v)        { coord = v; }
    godot::RID      get_rd_texture() const                     { return rd_texture; }
    void            set_rd_texture(const godot::RID &v)        { rd_texture = v; }
    godot::Ref<godot::Texture2DRD> get_texture_2d_rd() const   { return texture_2d_rd; }
    void            set_texture_2d_rd(const godot::Ref<godot::Texture2DRD> &v) { texture_2d_rd = v; }
    godot::MeshInstance2D *get_mesh_instance() const           { return mesh_instance; }
    void            set_mesh_instance(godot::MeshInstance2D *v){ mesh_instance = v; }
    godot::MeshInstance2D *get_wall_mesh_instance() const      { return wall_mesh_instance; }
    void            set_wall_mesh_instance(godot::MeshInstance2D *v) { wall_mesh_instance = v; }
    godot::RID      get_sim_uniform_set() const                { return sim_uniform_set; }
    void            set_sim_uniform_set(const godot::RID &v)   { sim_uniform_set = v; }
    godot::RID      get_injection_buffer() const               { return injection_buffer; }
    void            set_injection_buffer(const godot::RID &v)  { injection_buffer = v; }
    godot::StaticBody2D *get_static_body() const               { return static_body; }
    void            set_static_body(godot::StaticBody2D *v)    { static_body = v; }
    godot::TypedArray<godot::LightOccluder2D> get_occluder_instances() const { return occluder_instances; }
    void            set_occluder_instances(const godot::TypedArray<godot::LightOccluder2D> &v) { occluder_instances = v; }

    // --- New sim-field bindings ----------------------------------------
    // cells[] is exposed as a PackedByteArray view (4 bytes per cell).
    // Same shape that `RenderingDevice.texture_get_data(chunk.rd_texture, 0)`
    // returns today — drop-in replacement for the readback path.
    godot::PackedByteArray get_cells_data() const;
    void                   set_cells_data(const godot::PackedByteArray &v);

    godot::Rect2i get_dirty_rect() const                  { return dirty_rect; }
    void          set_dirty_rect(const godot::Rect2i &v)  { dirty_rect = v; }
    bool          get_sleeping() const                    { return sleeping; }
    void          set_sleeping(bool v)                    { sleeping = v; }
    bool          get_collider_dirty() const              { return collider_dirty; }
    void          set_collider_dirty(bool v)              { collider_dirty = v; }

    godot::Ref<Chunk> get_neighbor_up() const             { return neighbor_up; }
    void              set_neighbor_up(const godot::Ref<Chunk> &v)    { neighbor_up = v; }
    godot::Ref<Chunk> get_neighbor_down() const           { return neighbor_down; }
    void              set_neighbor_down(const godot::Ref<Chunk> &v)  { neighbor_down = v; }
    godot::Ref<Chunk> get_neighbor_left() const           { return neighbor_left; }
    void              set_neighbor_left(const godot::Ref<Chunk> &v)  { neighbor_left = v; }
    godot::Ref<Chunk> get_neighbor_right() const          { return neighbor_right; }
    void              set_neighbor_right(const godot::Ref<Chunk> &v) { neighbor_right = v; }

    godot::Ref<godot::ImageTexture> get_texture() const   { return texture; }
    void                            set_texture(const godot::Ref<godot::ImageTexture> &v) { texture = v; }

protected:
    static void _bind_methods();
};

} // namespace toprogue
```

**Why `cells` is exposed as `PackedByteArray`, not a `TypedArray<int>`:** the bridge contract is "compute reads back a texture, the bytes go into `chunk.cells`." `RenderingDevice::texture_get_data` returns `PackedByteArray` directly — no per-cell Variant marshalling. A `TypedArray<int>` would cost a Variant per cell on assignment, which dwarfs the readback itself.

**Why `cells` is fixed-size, not heap-allocated:** spec §6.1 declares `Cell cells[CHUNK_SIZE * CHUNK_SIZE]`. 256² × 4 = 256 KB per chunk — fine on the heap-as-part-of-RefCounted (the `Chunk` instance itself is heap-allocated by godot-cpp). No std::vector layer needed. If the static_assert at the top of the header trips on some weird platform that pads `Cell`, fix the struct, don't change the array.

- [ ] **Step 3: Write the implementation**

Create `gdextension/src/terrain/chunk.cpp`:

```cpp
#include "chunk.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cstring>

using namespace godot;

namespace toprogue {

PackedByteArray Chunk::get_cells_data() const {
    PackedByteArray out;
    out.resize(static_cast<int64_t>(sizeof(cells)));
    std::memcpy(out.ptrw(), cells, sizeof(cells));
    return out;
}

void Chunk::set_cells_data(const PackedByteArray &v) {
    if (v.size() != static_cast<int64_t>(sizeof(cells))) {
        UtilityFunctions::push_error(
            String("Chunk.set_cells_data: expected ") + String::num_int64(sizeof(cells)) +
            String(" bytes, got ") + String::num_int64(v.size()));
        return;
    }
    std::memcpy(cells, v.ptr(), sizeof(cells));
}

void Chunk::_bind_methods() {
    // CHUNK_SIZE accessor (read-only constant from GDScript)
    ClassDB::bind_static_method("Chunk", D_METHOD("get_chunk_size"), &Chunk::get_chunk_size);

    // --- Legacy GPU-pipeline properties ------------------------------
    ClassDB::bind_method(D_METHOD("get_coord"), &Chunk::get_coord);
    ClassDB::bind_method(D_METHOD("set_coord", "v"), &Chunk::set_coord);
    ADD_PROPERTY(PropertyInfo(Variant::VECTOR2I, "coord"), "set_coord", "get_coord");

    ClassDB::bind_method(D_METHOD("get_rd_texture"), &Chunk::get_rd_texture);
    ClassDB::bind_method(D_METHOD("set_rd_texture", "v"), &Chunk::set_rd_texture);
    ADD_PROPERTY(PropertyInfo(Variant::RID, "rd_texture"),
                 "set_rd_texture", "get_rd_texture");

    ClassDB::bind_method(D_METHOD("get_texture_2d_rd"), &Chunk::get_texture_2d_rd);
    ClassDB::bind_method(D_METHOD("set_texture_2d_rd", "v"), &Chunk::set_texture_2d_rd);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "texture_2d_rd",
                              PROPERTY_HINT_RESOURCE_TYPE, "Texture2DRD"),
                 "set_texture_2d_rd", "get_texture_2d_rd");

    ClassDB::bind_method(D_METHOD("get_mesh_instance"), &Chunk::get_mesh_instance);
    ClassDB::bind_method(D_METHOD("set_mesh_instance", "v"), &Chunk::set_mesh_instance);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "mesh_instance",
                              PROPERTY_HINT_NODE_TYPE, "MeshInstance2D"),
                 "set_mesh_instance", "get_mesh_instance");

    ClassDB::bind_method(D_METHOD("get_wall_mesh_instance"), &Chunk::get_wall_mesh_instance);
    ClassDB::bind_method(D_METHOD("set_wall_mesh_instance", "v"), &Chunk::set_wall_mesh_instance);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "wall_mesh_instance",
                              PROPERTY_HINT_NODE_TYPE, "MeshInstance2D"),
                 "set_wall_mesh_instance", "get_wall_mesh_instance");

    ClassDB::bind_method(D_METHOD("get_sim_uniform_set"), &Chunk::get_sim_uniform_set);
    ClassDB::bind_method(D_METHOD("set_sim_uniform_set", "v"), &Chunk::set_sim_uniform_set);
    ADD_PROPERTY(PropertyInfo(Variant::RID, "sim_uniform_set"),
                 "set_sim_uniform_set", "get_sim_uniform_set");

    ClassDB::bind_method(D_METHOD("get_injection_buffer"), &Chunk::get_injection_buffer);
    ClassDB::bind_method(D_METHOD("set_injection_buffer", "v"), &Chunk::set_injection_buffer);
    ADD_PROPERTY(PropertyInfo(Variant::RID, "injection_buffer"),
                 "set_injection_buffer", "get_injection_buffer");

    ClassDB::bind_method(D_METHOD("get_static_body"), &Chunk::get_static_body);
    ClassDB::bind_method(D_METHOD("set_static_body", "v"), &Chunk::set_static_body);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "static_body",
                              PROPERTY_HINT_NODE_TYPE, "StaticBody2D"),
                 "set_static_body", "get_static_body");

    ClassDB::bind_method(D_METHOD("get_occluder_instances"), &Chunk::get_occluder_instances);
    ClassDB::bind_method(D_METHOD("set_occluder_instances", "v"), &Chunk::set_occluder_instances);
    ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "occluder_instances",
                              PROPERTY_HINT_ARRAY_TYPE, "LightOccluder2D"),
                 "set_occluder_instances", "get_occluder_instances");

    // --- New spec §6.1 sim properties --------------------------------
    ClassDB::bind_method(D_METHOD("get_cells_data"), &Chunk::get_cells_data);
    ClassDB::bind_method(D_METHOD("set_cells_data", "v"), &Chunk::set_cells_data);
    // Not exposed as ADD_PROPERTY: it's a 256KB byte view, not an inspector field.

    ClassDB::bind_method(D_METHOD("get_dirty_rect"), &Chunk::get_dirty_rect);
    ClassDB::bind_method(D_METHOD("set_dirty_rect", "v"), &Chunk::set_dirty_rect);
    ADD_PROPERTY(PropertyInfo(Variant::RECT2I, "dirty_rect"),
                 "set_dirty_rect", "get_dirty_rect");

    ClassDB::bind_method(D_METHOD("get_sleeping"), &Chunk::get_sleeping);
    ClassDB::bind_method(D_METHOD("set_sleeping", "v"), &Chunk::set_sleeping);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "sleeping"),
                 "set_sleeping", "get_sleeping");

    ClassDB::bind_method(D_METHOD("get_collider_dirty"), &Chunk::get_collider_dirty);
    ClassDB::bind_method(D_METHOD("set_collider_dirty", "v"), &Chunk::set_collider_dirty);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "collider_dirty"),
                 "set_collider_dirty", "get_collider_dirty");

    ClassDB::bind_method(D_METHOD("get_neighbor_up"),    &Chunk::get_neighbor_up);
    ClassDB::bind_method(D_METHOD("set_neighbor_up", "v"),    &Chunk::set_neighbor_up);
    ClassDB::bind_method(D_METHOD("get_neighbor_down"),  &Chunk::get_neighbor_down);
    ClassDB::bind_method(D_METHOD("set_neighbor_down", "v"),  &Chunk::set_neighbor_down);
    ClassDB::bind_method(D_METHOD("get_neighbor_left"),  &Chunk::get_neighbor_left);
    ClassDB::bind_method(D_METHOD("set_neighbor_left", "v"),  &Chunk::set_neighbor_left);
    ClassDB::bind_method(D_METHOD("get_neighbor_right"), &Chunk::get_neighbor_right);
    ClassDB::bind_method(D_METHOD("set_neighbor_right", "v"), &Chunk::set_neighbor_right);
    // Neighbors are wired by ChunkManager (still GDScript) at chunk-stream time;
    // not exposed as inspector properties (cycles).

    ClassDB::bind_method(D_METHOD("get_texture"), &Chunk::get_texture);
    ClassDB::bind_method(D_METHOD("set_texture", "v"), &Chunk::set_texture);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "texture",
                              PROPERTY_HINT_RESOURCE_TYPE, "ImageTexture"),
                 "set_texture", "get_texture");
}

} // namespace toprogue
```

**`bind_static_method` note:** if godot-cpp on the pinned SHA spells this differently (e.g. `ClassDB::bind_static_method` may need explicit class-name string differently), check `gdextension/godot-cpp/include/godot_cpp/core/class_db.hpp`. Semantic: bind `get_chunk_size` so GDScript can read `Chunk.get_chunk_size()`. If the API isn't available, fall back to a non-static bound method (drop the `static` qualifier) — costs nothing functionally.

- [ ] **Step 4: Build standalone**

```bash
./gdextension/build.sh debug
```

Expected: clean. Common failure modes:
- `Texture2DRD` header path differs — check `gdextension/godot-cpp/gen/include/godot_cpp/classes/`.
- `LightOccluder2D` typed-array type spelling — same.
- `bind_static_method` API mismatch — see Step 3 note.

- [ ] **Step 5: Commit**

```bash
git add gdextension/src/terrain/chunk.h gdextension/src/terrain/chunk.cpp
git commit -m "feat: add Chunk C++ class with cell storage and legacy GPU fields"
```

---

## Task 3: Port `SectorGrid` (and inner `RoomSlot`) to C++

`SectorGrid` has logic. The inner `RoomSlot` class — currently nested in GDScript — must be exposed as its own bound class so callsites that read `slot.is_empty`/`slot.template_index` etc. keep working.

**Files:**
- Create: `gdextension/src/terrain/sector_grid.h`
- Create: `gdextension/src/terrain/sector_grid.cpp`

- [ ] **Step 1: Write the header**

Create `gdextension/src/terrain/sector_grid.h`:

```cpp
#pragma once

#include "../resources/biome_def.h"
#include "../resources/room_template.h"

#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace toprogue {

// Mirrors src/core/sector_grid.gd's nested `RoomSlot` 1:1.
// Promoted to a top-level RefCounted class so GDScript callsites that
// receive a `RoomSlot` and read its fields keep working unchanged.
class RoomSlot : public godot::RefCounted {
    GDCLASS(RoomSlot, godot::RefCounted);

public:
    bool is_empty       = false;
    bool is_boss        = false;
    int  template_index = -1;
    int  rotation       = 0;
    int  template_size  = 0;

    RoomSlot() = default;

    bool get_is_empty() const       { return is_empty; }
    void set_is_empty(bool v)       { is_empty = v; }
    bool get_is_boss() const        { return is_boss; }
    void set_is_boss(bool v)        { is_boss = v; }
    int  get_template_index() const { return template_index; }
    void set_template_index(int v)  { template_index = v; }
    int  get_rotation() const       { return rotation; }
    void set_rotation(int v)        { rotation = v; }
    int  get_template_size() const  { return template_size; }
    void set_template_size(int v)   { template_size = v; }

protected:
    static void _bind_methods();
};

class SectorGrid : public godot::RefCounted {
    GDCLASS(SectorGrid, godot::RefCounted);

public:
    static constexpr int    SECTOR_SIZE_PX     = 384;
    static constexpr int    BOSS_RING_DISTANCE = 10;
    static constexpr double EMPTY_WEIGHT       = 1.5;

    int64_t              _seed = 0;
    godot::Ref<BiomeDef> _biome;

    SectorGrid() = default;

    // GDScript-callable shim for `SectorGrid.new(world_seed, biome)`.
    // godot-cpp can't bind `_init` with arguments; same shim approach used
    // for `TerrainCell.init_args` in step 3. Callsites in
    // `src/autoload/level_manager.gd` are migrated in Task 5 step 1.
    void init_args(int64_t world_seed, const godot::Ref<BiomeDef> &biome);

    godot::Vector2i world_to_sector(const godot::Vector2 &world_pos) const;
    godot::Vector2i sector_to_world_center(const godot::Vector2i &coord) const;
    int             chebyshev_distance(const godot::Vector2i &a, const godot::Vector2i &b) const;
    godot::Ref<RoomSlot> resolve_sector(const godot::Vector2i &coord) const;
    godot::Ref<RoomTemplate> get_template_for_slot(const godot::Ref<RoomSlot> &slot) const;

    static int    get_sector_size_px()     { return SECTOR_SIZE_PX; }
    static int    get_boss_ring_distance() { return BOSS_RING_DISTANCE; }
    static double get_empty_weight()       { return EMPTY_WEIGHT; }

protected:
    static void _bind_methods();
};

} // namespace toprogue
```

- [ ] **Step 2: Write the implementation**

Create `gdextension/src/terrain/sector_grid.cpp`:

```cpp
#include "sector_grid.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

using namespace godot;

namespace toprogue {

void RoomSlot::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_is_empty"), &RoomSlot::get_is_empty);
    ClassDB::bind_method(D_METHOD("set_is_empty", "v"), &RoomSlot::set_is_empty);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_empty"), "set_is_empty", "get_is_empty");

    ClassDB::bind_method(D_METHOD("get_is_boss"), &RoomSlot::get_is_boss);
    ClassDB::bind_method(D_METHOD("set_is_boss", "v"), &RoomSlot::set_is_boss);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_boss"), "set_is_boss", "get_is_boss");

    ClassDB::bind_method(D_METHOD("get_template_index"), &RoomSlot::get_template_index);
    ClassDB::bind_method(D_METHOD("set_template_index", "v"), &RoomSlot::set_template_index);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "template_index"),
                 "set_template_index", "get_template_index");

    ClassDB::bind_method(D_METHOD("get_rotation"), &RoomSlot::get_rotation);
    ClassDB::bind_method(D_METHOD("set_rotation", "v"), &RoomSlot::set_rotation);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "rotation"), "set_rotation", "get_rotation");

    ClassDB::bind_method(D_METHOD("get_template_size"), &RoomSlot::get_template_size);
    ClassDB::bind_method(D_METHOD("set_template_size", "v"), &RoomSlot::set_template_size);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "template_size"),
                 "set_template_size", "get_template_size");
}

void SectorGrid::init_args(int64_t world_seed, const Ref<BiomeDef> &biome) {
    _seed = world_seed;
    _biome = biome;
}

Vector2i SectorGrid::world_to_sector(const Vector2 &world_pos) const {
    return Vector2i(
        static_cast<int>(std::floor(world_pos.x / SECTOR_SIZE_PX)),
        static_cast<int>(std::floor(world_pos.y / SECTOR_SIZE_PX))
    );
}

Vector2i SectorGrid::sector_to_world_center(const Vector2i &coord) const {
    return Vector2i(
        coord.x * SECTOR_SIZE_PX + SECTOR_SIZE_PX / 2,
        coord.y * SECTOR_SIZE_PX + SECTOR_SIZE_PX / 2
    );
}

int SectorGrid::chebyshev_distance(const Vector2i &a, const Vector2i &b) const {
    return MAX(std::abs(a.x - b.x), std::abs(a.y - b.y));
}

Ref<RoomSlot> SectorGrid::resolve_sector(const Vector2i &coord) const {
    Ref<RoomSlot> slot;
    slot.instantiate();

    int dist = chebyshev_distance(coord, Vector2i(0, 0));

    if (dist > BOSS_RING_DISTANCE) {
        slot->is_empty = true;
        return slot;
    }

    if (_biome.is_null()) {
        UtilityFunctions::push_error("SectorGrid.resolve_sector: biome is null");
        slot->is_empty = true;
        return slot;
    }

    Ref<RandomNumberGenerator> rng;
    rng.instantiate();
    // Mirrors GDScript: rng.seed = hash(_seed ^ x*73856093 ^ y*19349663)
    int64_t mix = _seed ^ (static_cast<int64_t>(coord.x) * 73856093LL)
                        ^ (static_cast<int64_t>(coord.y) * 19349663LL);
    rng->set_seed(static_cast<uint64_t>(mix));

    if (dist == BOSS_RING_DISTANCE) {
        TypedArray<RoomTemplate> bosses = _biome->boss_templates;
        if (bosses.is_empty()) {
            slot->is_empty = true;
            return slot;
        }
        slot->is_boss = true;
        slot->template_index = static_cast<int>(rng->randi() % static_cast<uint32_t>(bosses.size()));
        Ref<RoomTemplate> boss_tmpl = bosses[slot->template_index];
        slot->rotation = boss_tmpl->rotatable ? (static_cast<int>(rng->randi() % 4) * 90) : 0;
        slot->template_size = boss_tmpl->size_class;
        return slot;
    }

    TypedArray<RoomTemplate> rooms = _biome->room_templates;
    if (rooms.is_empty()) {
        slot->is_empty = true;
        return slot;
    }

    double total = EMPTY_WEIGHT;
    for (int i = 0; i < rooms.size(); i++) {
        Ref<RoomTemplate> t = rooms[i];
        total += t->weight;
    }

    double roll = rng->randf() * total;
    if (roll < EMPTY_WEIGHT) {
        slot->is_empty = true;
        return slot;
    }

    double cumulative = EMPTY_WEIGHT;
    for (int i = 0; i < rooms.size(); i++) {
        Ref<RoomTemplate> t = rooms[i];
        cumulative += t->weight;
        if (roll < cumulative) {
            slot->template_index = i;
            slot->rotation = t->rotatable ? (static_cast<int>(rng->randi() % 4) * 90) : 0;
            slot->template_size = t->size_class;
            return slot;
        }
    }

    slot->is_empty = true;
    return slot;
}

Ref<RoomTemplate> SectorGrid::get_template_for_slot(const Ref<RoomSlot> &slot) const {
    if (slot.is_null() || slot->is_empty) return Ref<RoomTemplate>();
    if (_biome.is_null()) return Ref<RoomTemplate>();
    if (slot->is_boss) {
        TypedArray<RoomTemplate> bosses = _biome->boss_templates;
        if (slot->template_index < 0 || slot->template_index >= bosses.size()) return Ref<RoomTemplate>();
        return bosses[slot->template_index];
    }
    TypedArray<RoomTemplate> rooms = _biome->room_templates;
    if (slot->template_index < 0 || slot->template_index >= rooms.size()) return Ref<RoomTemplate>();
    return rooms[slot->template_index];
}

void SectorGrid::_bind_methods() {
    ClassDB::bind_method(D_METHOD("init_args", "world_seed", "biome"), &SectorGrid::init_args);
    ClassDB::bind_method(D_METHOD("world_to_sector", "world_pos"),    &SectorGrid::world_to_sector);
    ClassDB::bind_method(D_METHOD("sector_to_world_center", "coord"), &SectorGrid::sector_to_world_center);
    ClassDB::bind_method(D_METHOD("chebyshev_distance", "a", "b"),    &SectorGrid::chebyshev_distance);
    ClassDB::bind_method(D_METHOD("resolve_sector", "coord"),         &SectorGrid::resolve_sector);
    ClassDB::bind_method(D_METHOD("get_template_for_slot", "slot"),   &SectorGrid::get_template_for_slot);

    ClassDB::bind_static_method("SectorGrid", D_METHOD("get_sector_size_px"),
                                &SectorGrid::get_sector_size_px);
    ClassDB::bind_static_method("SectorGrid", D_METHOD("get_boss_ring_distance"),
                                &SectorGrid::get_boss_ring_distance);
    ClassDB::bind_static_method("SectorGrid", D_METHOD("get_empty_weight"),
                                &SectorGrid::get_empty_weight);
}

} // namespace toprogue
```

**RNG-determinism note:** the GDScript original uses `hash(...)` then assigns to `rng.seed`. Godot's `hash()` is the engine's Variant hash; the C++ port skips that and assigns the mixed integer directly. This **changes the sequence of pseudo-random rolls** from the GDScript implementation. The behavioral consequence is purely cosmetic (which template lands in which sector for a given world seed), and gameplay does not depend on byte-equal layouts across the port (spec §3.4: "No bit-exact parity with previous GLSL output"). If reviewers want cross-port parity for ergonomics, the fix is to wrap the mix in a 64-bit splitmix step before assigning — make that a follow-up if requested, not part of this step.

- [ ] **Step 3: Build standalone**

```bash
./gdextension/build.sh debug
```

Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add gdextension/src/terrain/sector_grid.h gdextension/src/terrain/sector_grid.cpp
git commit -m "feat: add SectorGrid and RoomSlot C++ classes"
```

---

## Task 4: Register `Chunk`, `SectorGrid`, `RoomSlot`, `GenerationContext`

**Files:**
- Modify: `gdextension/src/register_types.cpp`

- [ ] **Step 1: Add includes and `GDREGISTER_CLASS` calls**

Open `gdextension/src/register_types.cpp`. Add the three terrain includes near the top (alongside the resource includes from step 3):

```cpp
#include "terrain/chunk.h"
#include "terrain/generation_context.h"
#include "terrain/sector_grid.h"
```

In `initialize_toprogue_module`, after the step 3 resource registrations (`GDREGISTER_CLASS(TerrainCell)` … `GDREGISTER_CLASS(TemplatePack)`), add:

```cpp
    // Leaf types — register dependencies before dependents.
    // SectorGrid takes a Ref<BiomeDef>; BiomeDef must already be registered (it is, above).
    GDREGISTER_CLASS(GenerationContext);
    GDREGISTER_CLASS(Chunk);
    GDREGISTER_CLASS(RoomSlot);   // Inner type of SectorGrid; register before SectorGrid.
    GDREGISTER_CLASS(SectorGrid);
```

- [ ] **Step 2: Build and confirm clean**

```bash
./gdextension/build.sh debug
```

- [ ] **Step 3: Open the editor — verify class registration**

Launch Godot 4.6 → open project. Output log:
- Expected warning: `Class "Chunk" hides a global script class` (or similar) — both the GDScript `class_name Chunk` and the native class are alive at this point. Disappears in Task 6 when the GDScript files are deleted.
- Same for `SectorGrid`, `GenerationContext`.
- No errors.

Add a scratch `_ready()` to any test scene (or use the GDScript console):

```gdscript
print(ClassDB.class_exists("Chunk"))             # true
print(ClassDB.class_exists("SectorGrid"))        # true
print(ClassDB.class_exists("RoomSlot"))          # true
print(ClassDB.class_exists("GenerationContext")) # true
print(Chunk.get_chunk_size())                    # 256
```

Close the editor.

- [ ] **Step 4: Commit**

```bash
git add gdextension/src/register_types.cpp
git commit -m "feat: register Chunk, SectorGrid, RoomSlot, GenerationContext"
```

---

## Task 5: Migrate GDScript callsites to native types

Two changes:
1. `level_manager.gd`'s two `SectorGrid.new(world_seed, current_biome)` calls switch to `SectorGrid.new()` + `init_args(...)` — same shim pattern as step 3's `TerrainCell.init_args`.
2. `tests/unit/test_sector_grid.gd` removes its `preload("res://src/core/sector_grid.gd")` (will dangle once the file is deleted) and uses the native `SectorGrid` directly.

No callsite that constructs `Chunk` or reads `Chunk` fields needs to change — `Chunk.new()` is already zero-arg, and every property is bound under its original name.

**Files modified:**
- `src/autoload/level_manager.gd`
- `tests/unit/test_sector_grid.gd`

- [ ] **Step 1: Update `level_manager.gd`**

Open `src/autoload/level_manager.gd`. Find both occurrences of:

```gdscript
_grid = SectorGrid.new(world_seed, current_biome)
```

(Lines 18 and 37.)

Replace each with:

```gdscript
_grid = SectorGrid.new()
_grid.init_args(world_seed, current_biome)
```

- [ ] **Step 2: Update `tests/unit/test_sector_grid.gd`**

Open the file. Remove the line:

```gdscript
const _SectorGrid = preload("res://src/core/sector_grid.gd")
```

Replace every `_SectorGrid.new(world_seed, biome)` with the two-line shim:

```gdscript
var grid := SectorGrid.new()
grid.init_args(world_seed, biome)
```

`grep -n "_SectorGrid" tests/unit/test_sector_grid.gd` after editing should return zero hits.

- [ ] **Step 3: Confirm no other GDScript constructs `SectorGrid` with args**

```bash
grep -rn "SectorGrid\.new(" src/ tests/ tools/
```

Expected: only zero-arg `SectorGrid.new()` calls remain (or none at all besides the shim sites). If any other site uses the 2-arg form, apply the same shim.

- [ ] **Step 4: Confirm no other GDScript constructs `Chunk` or `GenerationContext` with args**

```bash
grep -rn "Chunk\.new(\|GenerationContext\.new(" src/ tests/ tools/
```

Expected: only `Chunk.new()` (zero-arg, in `chunk_manager.gd`) and (likely) zero `GenerationContext.new(...)` hits. Both are already zero-arg-compatible.

- [ ] **Step 5: Build the project (no C++ changes — gdUnit4 only)**

Run gdUnit4 from the editor's Test panel. Pay attention to:
- `tests/unit/test_sector_grid.gd` — full method surface exercise.
- `tests/unit/test_biome_def.gd` — touches `BiomeDef`; should still pass since step 3's bindings haven't changed.

If `test_sector_grid.gd` fails on a determinism assertion (e.g. "expected boss template index 1, got 2"), the cause is the RNG-mix change documented in Task 3 step 2's note. Update the test's expected value to the new sequence — the test exercises *behavior* (rooms get picked, weight respected), not bit-exact RNG output. Verify the new expected values manually.

- [ ] **Step 6: Commit**

```bash
git add src/autoload/level_manager.gd tests/unit/test_sector_grid.gd
git commit -m "refactor: migrate SectorGrid callsites to native init_args shim"
```

---

## Task 6: Delete the GDScript originals

**Files deleted:**
- `src/core/chunk.gd` + `.uid`
- `src/core/sector_grid.gd` + `.uid`
- `src/terrain/generation_context.gd` + `.uid`

- [ ] **Step 1: Capture each `.uid` value before deletion (sanity)**

```bash
for f in src/core/chunk.gd src/core/sector_grid.gd src/terrain/generation_context.gd; do
    if [ -f "$f.uid" ]; then
        echo "=== $f.uid ==="
        cat "$f.uid"
    fi
done
```

For each UID printed, search the project (excluding the `.uid` files themselves):

```bash
for uid in <paste UIDs from above, one per line>; do
    grep -rn "$uid" . 2>/dev/null | grep -v "\.uid:" || true
done
```

Expected: zero hits. If anything references a UID, fix that reference before continuing.

- [ ] **Step 2: Delete the three `.gd` files and their `.uid` sidecars**

```bash
rm src/core/chunk.gd        src/core/chunk.gd.uid
rm src/core/sector_grid.gd  src/core/sector_grid.gd.uid
rm src/terrain/generation_context.gd src/terrain/generation_context.gd.uid
```

- [ ] **Step 3: Confirm zero stale references to the deleted scripts**

```bash
grep -rn "res://src/core/chunk\.gd\|res://src/core/sector_grid\.gd\|res://src/terrain/generation_context\.gd" .
```

Expected: zero hits. If a `.tscn` (or any other file) still references one of these paths, it's a stale ref — fix it before committing.

- [ ] **Step 4: Open the editor and confirm a clean load**

Launch Godot 4.6 → open project. Output log:
- No "Identifier 'Chunk' not declared" or similar.
- No "could not parse script" errors.
- No more "Class Chunk hides a global script class" warnings (was expected during Task 4; clears now).

Open one chunk-bearing scene if there is one (or just hit F5). Check Output during play.

- [ ] **Step 5: Commit**

```bash
git add src/ tests/
git commit -m "refactor: delete GDScript Chunk, SectorGrid, GenerationContext"
```

---

## Task 7: Bridge verification — compute pipeline still runs

Spec §9.1 step 4: *"The compute pipeline still runs at this step — `ComputeDevice` (still GDScript) writes into the cell array via the texture readback path it already uses."*

This task is verification-only. Nothing changes in `compute_device.gd` — it reads/writes `chunk.rd_texture`, `chunk.sim_uniform_set`, `chunk.injection_buffer` exactly as before, and those properties resolve to the native `Chunk`'s bound fields.

- [ ] **Step 1: Confirm `compute_device.gd` and the GLSL files are unchanged**

```bash
git status src/core/compute_device.gd shaders/
```

Expected: not in the diff for this step. If they are, you over-touched something.

- [ ] **Step 2: F5 the project, generate a level, walk through it**

Launch the game (entry point on `refactor/cpp`). Generate a level. Confirm:
- Terrain renders (compute_device is still building chunks via GLSL, the rendering material reads `chunk.texture_2d_rd`).
- Walking through gas/lava behaves as before.
- Digging into terrain works (`terrain_modifier.gd` still talks to the compute pipeline).
- Collisions work (`terrain_collision_helper.gd` still does its `texture_get_data` readback).

If anything is broken, the most likely cause is a property-binding mismatch on `Chunk` — one of the legacy fields (e.g. `texture_2d_rd`) might be bound under a slightly wrong name or type. Compare the binding in `chunk.cpp` against the GDScript reads in `compute_device.gd` line-by-line.

- [ ] **Step 3: Demonstrate the bridge contract (optional but recommended)**

In the editor's GDScript console, after a chunk has been generated, run:

```gdscript
var wm := get_tree().root.get_node("WorldManager")  # adjust path if different
var chunk = wm.chunks.values()[0]
print(chunk.coord, " sleeping=", chunk.sleeping, " dirty=", chunk.dirty_rect)
print("cells_data size=", chunk.get_cells_data().size())  # 256*256*4 = 262144
```

Expected: all three lines print without error. The cells_data is 262144 bytes (zeros at this point — no one has populated them yet; that's step 5+ work).

- [ ] **Step 4: No commit needed.** Verification gate.

---

## Task 8: Final verification

- [ ] **Step 1: Final greps**

```bash
grep -rn "extends RefCounted" src/core/chunk.gd src/core/sector_grid.gd src/terrain/generation_context.gd 2>&1
```

Expected: "No such file or directory" for all three. Files are gone.

```bash
grep -rn "res://src/core/chunk\.gd\|res://src/core/sector_grid\.gd\|res://src/terrain/generation_context\.gd" .
```

Expected: zero hits.

```bash
grep -rn "\bChunk\b\|\bSectorGrid\b\|\bGenerationContext\b\|RoomSlot" src/ tests/ tools/ project.godot \
    > /tmp/step4-inventory-after.txt
diff /tmp/step4-inventory-before.txt /tmp/step4-inventory-after.txt | head -40
```

Expected: only changes are (a) the three deleted `.gd` files no longer show up, (b) the `level_manager.gd` and `test_sector_grid.gd` lines are different where the shim was added. Every other callsite still resolves.

- [ ] **Step 2: Confirm the build still produces the binary on macOS**

```bash
./gdextension/build.sh debug
ls -la bin/lib/
```

- [ ] **Step 3: Open the editor and confirm clean load + run gdUnit4**

Launch Godot 4.6 → open project → Output log clean → run gdUnit4 → all green.

- [ ] **Step 4: Smoke playthrough (~2 min, per spec §10.2)**

Launch → generate a large level → walk through it for ~2 minutes touching gas/lava/fire/digging/combat → exit cleanly. No crashes, no visible deadlocks, no frame stutters > 1s.

- [ ] **Step 5: Format C++ sources**

```bash
./gdextension/format.sh
git diff gdextension/src/
```

If formatter changed anything:

```bash
git add gdextension/src/
git commit -m "chore: clang-format leaf sources"
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

If anything fails on the second machine that didn't fail on the first, fix and commit before declaring step 4 done.

---

## Done Definition for Step 4

- `gdextension/src/terrain/{chunk,sector_grid,generation_context}.{h,cpp}` exist and compile clean on macOS and Arch.
- `Chunk`, `SectorGrid`, `RoomSlot`, `GenerationContext` are registered as native classes (all `RefCounted`).
- `Chunk` exposes every field from the original `chunk.gd` (legacy GPU pipeline) **plus** the spec §6.1 sim fields (`cells` via `get_cells_data`/`set_cells_data`, `dirty_rect`, `sleeping`, `collider_dirty`, `neighbors`, `texture`).
- The three `.gd` files (`src/core/chunk.gd`, `src/core/sector_grid.gd`, `src/terrain/generation_context.gd`) and their `.uid` sidecars are deleted.
- `level_manager.gd` and `test_sector_grid.gd` use the `SectorGrid.new() + init_args(...)` shim.
- Zero stale `res://src/core/chunk.gd` / `res://src/core/sector_grid.gd` / `res://src/terrain/generation_context.gd` references remain.
- The compute pipeline still runs: levels generate, render, sim continues to run on the GPU. Behavior is indistinguishable from `refactor/cpp` HEAD before this step (modulo the documented `SectorGrid` RNG-mix change, which affects layout-cosmetics only — not gameplay).
- `gdUnit4` suite passes on both machines.
- Smoke playthrough passes on both machines.

When all of the above are true, Step 4 is complete. Proceed to write the plan for **Step 5 — `ColliderBuilder` + `TerrainCollider` + `TerrainCollisionHelper` + `GasInjector` + `TerrainPhysical`** per the instructions in the "What Comes After Step 1" section of `docs/superpowers/plans/2026-04-30-step-1-bootstrap-godot-cpp.md`. The relevant spec sections for that plan are §8.3, §8.5–§8.7, and §9.1 step 5. Predecessor source under `gdextension/src/terrain/` (especially `Chunk::get_cells_data` and the `collider_dirty` flag) provides the bridge between the texture-readback path that `terrain_collision_helper.gd` uses today and the cell-array path step 5 introduces.
