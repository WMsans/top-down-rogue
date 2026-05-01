# Step 5 — `ColliderBuilder` + `TerrainCollider` + `TerrainCollisionHelper` + `GasInjector` + `TerrainPhysical` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the collider + physics wave to native C++ via godot-cpp, and **delete the first compute shader (`collider.glsl`)**. Five classes are ported (`TerrainCollider`, `GasInjector`, `TerrainCollisionHelper`, `TerrainPhysical`) and one new C++ class is introduced (`ColliderBuilder`, per spec §8.3). Class names are preserved so existing GDScript callsites resolve to the native types unchanged. The bridge contract from step 4 still holds for the rest of the pipeline: `compute_device.gd`, `terrain_modifier.gd`, `world_manager.gd`, `chunk_manager.gd` remain in GDScript and continue to drive the compute pipeline for **generation** and **simulation**. Only the **collider** path of the compute pipeline goes away in this step (`collider.glsl` + the `rebuild_chunk_collision_gpu` route). Generation (`generation.glsl`, `generation_simplex_cave.glsl`) and simulation (`simulation.glsl`) survive until steps 6 and 7.

**Architecture:** Five new translation units under `gdextension/src/physics/` (`terrain_collider.{h,cpp}`, `gas_injector.{h,cpp}`, `collider_builder.{h,cpp}`) and `gdextension/src/terrain/` (`terrain_collision_helper.{h,cpp}`, `terrain_physical.{h,cpp}`). Today's `TerrainCollider.build_collision` is split per spec §8.3: `ColliderBuilder` owns the cell-mask → segments pipeline (marching squares), `TerrainCollider` owns segments → `CollisionShape2D` / `OccluderPolygon2D` shape construction. `TerrainCollisionHelper` walks active chunks on a round-robin timer (existing behavior preserved), pulls each chunk's solid mask via the existing `RenderingDevice::texture_get_data(chunk.rd_texture, 0)` readback (now driven from C++), runs `ColliderBuilder` + `TerrainCollider`, and attaches the resulting shapes/occluders. `GasInjector::build_payload` and `TerrainPhysical::query`/`invalidate_rect`/`set_center` keep their public signatures so `world_manager.gd` and `lava_damage_checker.gd` keep working with no changes.

**Tech Stack:** godot-cpp pinned per step 1, C++17, the existing SCons + `build.sh` pipeline. No new external dependencies.

---

## Required Reading Before Starting

You **must** read all of these before writing any code.

1. **Spec:** `docs/superpowers/specs/2026-04-30-godot-cpp-hot-path-port-design.md`. Mandatory sections:
   - §3.2 (Ported to C++) — confirms `TerrainCollider` base is "TBD on read at port time" (it's a `RefCounted`-shaped helper today with only static methods; we port it as a `RefCounted` wrapper that exposes those methods as bound static methods, mirroring the GDScript surface).
   - §3.4 (Non-goals) — no new public methods, signals, or properties beyond what the GDScript originals expose. `ColliderBuilder` is the **explicit new class** spec §8.3 introduces.
   - §8.3 (`ColliderBuilder`) — defines the cell-mask → polygons/segments contract. Trigger is `Chunk::collider_dirty` *eventually*; this step does not yet wire that flag. Today's round-robin rebuild (every 0.2s, 4 chunks/frame) is preserved unchanged.
   - §8.5 (`TerrainModifier` post-port) — informational only. `TerrainModifier` is **not** ported in this step; it's part of step 7. We do not change `terrain_modifier.gd` here.
   - §8.6 (`GasInjector` post-port) — long-term shape (per-chunk injection queue). For now, `build_payload` keeps its current shape (returns `PackedByteArray` of GLSL-compatible bytes), since the simulator that owns the queue lands in step 7.
   - §8.7 (`TerrainCollisionHelper`) — "Pure CPU query helper, no shader involvement today." The GPU collider path is in `terrain_collision_helper.gd` (`rebuild_chunk_collision_gpu`), and that's the path we're deleting; the CPU helper character of the class itself is preserved.
   - §9.1 step 5 — what this step delivers and what it deletes:
     - delete `shaders/compute/collider.glsl`
     - delete `shaders/compute/collider.glsl.import`
   - §10.1 risks #5 (hot-reload) — restart the editor for verification.

2. **Predecessor C++ source from step 4** (already merged) — read in full before writing C++:
   - `gdextension/src/terrain/chunk.h` and `.cpp` — every collider path goes through `Chunk` properties. Note `get_cells_data()`/`set_cells_data()` (PackedByteArray, 4 bytes/cell, RGBA-ordered) and the legacy `rd_texture`/`static_body`/`occluder_instances` getters that already work.
   - `gdextension/src/terrain/sector_grid.h` and `.cpp` — closest precedent for a `RefCounted` with non-trivial logic. Mirror its `_bind_methods` shape and `MAX/std::abs` usage.
   - `gdextension/src/sim/material_table.h` and `.cpp` — the `MaterialTable::has_collider`/`is_fluid`/`get_damage` methods that `TerrainCollisionHelper`/`TerrainPhysical` query today via `MaterialTable.X`. Verify the C++ symbol names match.
   - `gdextension/src/register_types.cpp` — where the new `GDREGISTER_CLASS` calls land.

3. **The classes being ported** (read in full; field names, method names, and types must match):
   - `src/physics/terrain_collider.gd` (~360 LOC) — only static helpers (`build_collision`, `build_from_segments`, `create_occluder_polygons`, `shrink_polygon`, `_signed_area`, `_polygon_area`, internal `_get_segments`/`_edge_point`/`_simplify_closed_polygon`/`_douglas_peucker`/`_point_to_segment_distance`).
   - `src/physics/gas_injector.gd` (~128 LOC) — only static helpers (`build_payload` plus internal `_get_node_velocity`/`_world_aabb_of`/`_shape_aabb`).
   - `src/core/terrain_collision_helper.gd` (~145 LOC) — `RefCounted`. Has both GPU path (`rebuild_chunk_collision_gpu`) and CPU path (`rebuild_chunk_collision_cpu`); we keep only the CPU path's shape-building work and replace the data source with the existing texture readback.
   - `src/core/terrain_physical.gd` (~48 LOC) — `Node`. Public surface: `query(world_pos) -> TerrainCell`, `invalidate_rect(rect)`, `set_center(world_center)`, `var world_manager: Node2D`.

4. **Every callsite that constructs or calls these types** (so the C++ surface matches usage exactly):
   - `TerrainCollider`: only called from `terrain_collision_helper.gd` (lines 53, 124, 135). Today's static-method shape (`TerrainCollider.build_collision(...)`) must keep working. After the port, the *callsite that reaches into `TerrainCollider`* moves into the C++ `TerrainCollisionHelper` — but the bound static methods stay callable from any GDScript that wants them (no breakage).
   - `GasInjector`: called from `world_manager.gd` line 114 (`GasInjector.build_payload(tree, coord)`). Single call site. Static method must remain callable from GDScript by that exact name.
   - `TerrainCollisionHelper`: constructed in `world_manager.gd` line 43 (`TerrainCollisionHelper.new()`), assigned `world_manager`, then called per-frame as `_collision_helper.rebuild_dirty(chunks, delta)`. Single consumer.
   - `TerrainPhysical`: constructed in `world_manager.gd` lines 38–41 (`TerrainPhysical.new()`, set `name`, set `world_manager`, `add_child`). Read in `lava_damage_checker.gd` lines 16–36 via `wm.get_node_or_null("TerrainPhysical")` then `query(...)`. Read in `terrain_modifier.gd` (multiple lines) via `terrain_physical.invalidate_rect(rect)`. Read in `world_manager.gd` line 67 via `terrain_physical.set_center(...)`.
   - `MaterialTable.has_collider/is_fluid/get_damage`: called from `terrain_collision_helper.gd` line 46 and `terrain_physical.gd` lines 42–44. Already bound on the C++ singleton from step 2 — confirm method names are `has_collider`, `is_fluid`, `get_damage` (not e.g. `get_is_fluid`).
   - `terrain_modifier.gd` references `chunk.coord`, `chunk.rd_texture` and calls `terrain_physical.invalidate_rect(...)`. **Not changed in this step.** It still drives the compute pipeline for digging.

5. **What stays GDScript this step (unchanged):**
   - `src/core/compute_device.gd` — still owns `rd`, `collider_storage_buffer`, `collider_pipeline`, `collider_shader`. The `collider_*` fields/loads become **dead weight after this step**, since `terrain_collision_helper.gd`'s GPU path is gone. Task 8 deletes those specific fields/loads but leaves the rest of `ComputeDevice` (generation, simulation) alive.
   - `src/core/world_manager.gd`, `src/core/chunk_manager.gd`, `src/core/terrain_modifier.gd` — entirely.
   - `shaders/compute/generation.glsl`, `generation_simplex_cave.glsl`, `simulation.glsl` — entirely (steps 6 and 7).

If anything in this plan conflicts with the spec, the spec wins — flag the conflict and stop, do not silently deviate.

## What This Step Does NOT Do

- **Does not** port `ChunkManager`, `WorldManager`, `TerrainModifier`, or any class outside the five listed in the title.
- **Does not** delete `shaders/compute/generation.glsl`, `generation_simplex_cave.glsl`, or `simulation.glsl`. Only `collider.glsl` (+ `.glsl.import`) goes.
- **Does not** introduce dirty-rect-driven rebuild. `Chunk::collider_dirty` exists from step 4 but stays unread this step — round-robin (`COLLISION_REBUILD_INTERVAL`, `COLLISIONS_PER_FRAME`) is preserved exactly as today.
- **Does not** change the GLSL ↔ CPU bridge: `compute_device.gd` still writes `rd_texture`, and `TerrainCollisionHelper` still reads via `RenderingDevice::texture_get_data(chunk.rd_texture, 0)`. The change is *who* runs the readback (GDScript → C++) and what happens after (the GPU marching-squares variant is gone).
- **Does not** populate `chunk.cells[]`. Step 4 added the storage; step 7 owns population. Until then, `ColliderBuilder` consumes the readback `PackedByteArray` directly (same shape as today's `texture_get_data` output) — it does **not** read `chunk.cells[]` yet. The C++ method takes a `PackedByteArray` argument, exactly as today's GDScript `TerrainCollider.build_collision(data, ...)` does.
- **Does not** touch `GasInjector`'s payload byte format. Today's GLSL simulator expects a specific `[count: u32][padding: 12B][body: 32B × N]` layout. We preserve it byte-for-byte until step 7 replaces the simulator. Cross-check the byte offsets against `shaders/include/sim/` consumers if you change anything in `build_payload`.
- **Does not** add a new public field, signal, or method beyond what GDScript exposes today (spec §3.4). The introduction of `ColliderBuilder` is the documented exception.

## Pre-flight Verification (do this first)

- [ ] **Step 1: Confirm step 4 is merged and the build is green**

```bash
git status
git log --oneline -10
./gdextension/build.sh debug
ls bin/lib/
```

Expected: clean working tree on `refactor/cpp`. Recent commits include the step 4 work (`feat: register Chunk, SectorGrid, RoomSlot, GenerationContext`, `refactor: migrate SectorGrid callsites to native init_args shim`, `refactor: delete GDScript Chunk, SectorGrid, GenerationContext`, `chore: clang-format leaf sources`). Build produces the dylib/so for the current platform.

- [ ] **Step 2: Confirm the editor still loads cleanly with step 4's natives**

Launch Godot 4.6 → open project → Output log clean. F5 → walk for ~10s in a generated level → quit. Smoke confirms the bridge from step 4 still works before we change anything.

- [ ] **Step 3: Inventory every callsite once, before changes**

```bash
grep -rn "\bTerrainCollider\b\|\bGasInjector\b\|\bTerrainCollisionHelper\b\|\bTerrainPhysical\b\|\bColliderBuilder\b" \
    src/ tests/ tools/ project.godot \
    > /tmp/step5-inventory-before.txt
wc -l /tmp/step5-inventory-before.txt
```

Save that file — Task 9 step 2 re-greps and compares. Every external hit should still resolve after the port; only the four `.gd` files (`terrain_collider.gd`, `gas_injector.gd`, `terrain_collision_helper.gd`, `terrain_physical.gd`) get deleted.

- [ ] **Step 4: Inventory every place that touches the GPU collider path**

```bash
grep -rn "collider_storage_buffer\|collider_pipeline\|collider_shader\|rebuild_chunk_collision_gpu\|collider\.glsl" \
    src/ tests/ tools/ project.godot
```

Save the list. Task 8 walks it and excises every dead reference. Expected sites (cross-check against your output):
- `src/core/compute_device.gd` — declares and loads `collider_shader`, `collider_pipeline`, `collider_storage_buffer`.
- `src/core/terrain_collision_helper.gd` — `rebuild_chunk_collision_gpu` (entire method).
- `shaders/compute/collider.glsl` and `.glsl.import` — the shader itself.

If any other site appears (e.g. a test, a tool script), call it out before continuing.

- [ ] **Step 5: Confirm `MaterialTable` exposes the methods this step needs**

```bash
grep -n "has_collider\|is_fluid\|get_damage" gdextension/src/sim/material_table.h gdextension/src/sim/material_table.cpp
```

Expected: each of `has_collider(int)`, `is_fluid(int)`, `get_damage(int)` is bound. If any is missing, **stop and flag** — that's a step 2 omission and must be fixed before continuing (a one-line `bind_method` + accessor in `material_table.cpp`).

- [ ] **Step 6: Confirm the gdUnit4 suite is green at HEAD**

Run gdUnit4 via the editor's Test panel. All green. If any test is red at HEAD before this step starts, fix or document the pre-existing failure before proceeding.

---

## Task 1: Port `TerrainCollider` to C++

`TerrainCollider` is a static-method bag (no instance state). The C++ port keeps the exact static-method surface so any GDScript that calls `TerrainCollider.build_collision(...)` keeps working. After this task lands, `terrain_collision_helper.gd` still calls `TerrainCollider.X` from GDScript (it gets ported in Task 4); the static methods are bound on a `RefCounted` shell.

**Files:**
- Create: `gdextension/src/physics/terrain_collider.h`
- Create: `gdextension/src/physics/terrain_collider.cpp`

- [ ] **Step 1: Write the header**

Create `gdextension/src/physics/terrain_collider.h`:

```cpp
#pragma once

#include <godot_cpp/classes/collision_shape2d.hpp>
#include <godot_cpp/classes/occluder_polygon2d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/static_body2d.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace toprogue {

// Static-method shell. Mirrors src/physics/terrain_collider.gd 1:1.
// All logic is static; the RefCounted base exists only so godot-cpp can register
// the class and bind static methods callable from GDScript as `TerrainCollider.X(...)`.
class TerrainCollider : public godot::RefCounted {
    GDCLASS(TerrainCollider, godot::RefCounted);

public:
    static constexpr int    CELL_SIZE         = 2;
    static constexpr double DP_EPSILON        = 0.8;
    static constexpr double OCCLUDER_INSET    = 4.0;
    static constexpr double MIN_OCCLUDER_AREA = 16.0;

    static godot::CollisionShape2D *build_collision(
        const godot::PackedByteArray &data,
        int                           size,
        godot::StaticBody2D          *static_body,
        const godot::Vector2i        &world_offset);

    static godot::CollisionShape2D *build_from_segments(
        const godot::PackedVector2Array &segments,
        godot::StaticBody2D             *static_body,
        const godot::Vector2i           &world_offset);

    static godot::TypedArray<godot::OccluderPolygon2D> create_occluder_polygons(
        const godot::PackedVector2Array &segments);

    static godot::PackedVector2Array shrink_polygon(
        const godot::PackedVector2Array &points,
        double                           distance);

protected:
    static void _bind_methods();
};

} // namespace toprogue
```

**Why static-method-only:** today's GDScript class is `class_name TerrainCollider` with only `static func` members. No instance state, no constructor calls anywhere. Mirroring as bound `static_method`s preserves the call shape. If a callsite somewhere uses `TerrainCollider.new().build_collision(...)`, that still works (it just constructs a useless RefCounted), but `grep -rn "TerrainCollider\.new(" src/ tests/` should return zero — confirm before continuing.

- [ ] **Step 2: Write the implementation**

Create `gdextension/src/physics/terrain_collider.cpp`. Port each method 1:1 from `terrain_collider.gd`. Internal helpers (`_get_segments`, `_edge_point`, `_simplify_closed_polygon`, `_douglas_peucker`, `_point_to_segment_distance`, `_signed_area`, `_polygon_area`) are anonymous-namespace free functions, not bound. The marching-squares lookup table can be a `static constexpr` array.

```cpp
#include "terrain_collider.h"

#include <godot_cpp/classes/concave_polygon_shape2d.hpp>
#include <godot_cpp/classes/geometry2d.hpp>
#include <godot_cpp/classes/light_occluder2d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>
#include <vector>

using namespace godot;

namespace toprogue {
namespace {

// Marching-squares case → segment index pairs.
// Each entry is up to two segments (segments_count, [(edge_a, edge_b), …]).
struct MsCase { int count; int seg[2][2]; };
static constexpr MsCase MS_TABLE[16] = {
    /*  0 */ {0, {{0,0},{0,0}}},
    /*  1 */ {1, {{3,2},{0,0}}},
    /*  2 */ {1, {{2,1},{0,0}}},
    /*  3 */ {1, {{3,1},{0,0}}},
    /*  4 */ {1, {{1,0},{0,0}}},
    /*  5 */ {2, {{0,1},{3,2}}},
    /*  6 */ {1, {{2,0},{0,0}}},
    /*  7 */ {1, {{3,0},{0,0}}},
    /*  8 */ {1, {{0,3},{0,0}}},
    /*  9 */ {1, {{0,2},{0,0}}},
    /* 10 */ {2, {{0,3},{1,2}}},
    /* 11 */ {1, {{0,1},{0,0}}},
    /* 12 */ {1, {{1,3},{0,0}}},
    /* 13 */ {1, {{1,2},{0,0}}},
    /* 14 */ {1, {{2,3},{0,0}}},
    /* 15 */ {0, {{0,0},{0,0}}},
};

static Vector2i edge_point(int cx, int cy, int edge) {
    constexpr int half = TerrainCollider::CELL_SIZE / 2;
    switch (edge) {
        case 0: return Vector2i(cx * TerrainCollider::CELL_SIZE + half, cy * TerrainCollider::CELL_SIZE);
        case 1: return Vector2i((cx + 1) * TerrainCollider::CELL_SIZE, cy * TerrainCollider::CELL_SIZE + half);
        case 2: return Vector2i(cx * TerrainCollider::CELL_SIZE + half, (cy + 1) * TerrainCollider::CELL_SIZE);
        case 3: return Vector2i(cx * TerrainCollider::CELL_SIZE, cy * TerrainCollider::CELL_SIZE + half);
    }
    return Vector2i(0, 0);
}

static double point_to_segment_distance(const Vector2 &p, const Vector2 &a, const Vector2 &b) {
    Vector2 line = b - a;
    double  ls   = line.length_squared();
    if (ls < 1e-4) return p.distance_to(a);
    double  t    = Math::clamp((p - a).dot(line) / ls, 0.0, 1.0);
    Vector2 proj = a + line * t;
    return p.distance_to(proj);
}

static PackedVector2Array douglas_peucker(const PackedVector2Array &pts, double eps) {
    if (pts.size() <= 2) return pts;
    double  max_dist = 0.0;
    int     max_idx  = 0;
    Vector2 first    = pts[0];
    Vector2 last     = pts[pts.size() - 1];
    for (int i = 1; i < pts.size() - 1; i++) {
        double d = point_to_segment_distance(pts[i], first, last);
        if (d > max_dist) { max_dist = d; max_idx = i; }
    }
    PackedVector2Array out;
    if (max_dist > eps) {
        PackedVector2Array left  = douglas_peucker(pts.slice(0, max_idx + 1), eps);
        PackedVector2Array right = douglas_peucker(pts.slice(max_idx),       eps);
        for (int i = 0; i < left.size() - 1; i++) out.push_back(left[i]);
        for (int i = 0; i < right.size();    i++) out.push_back(right[i]);
    } else {
        out.push_back(first);
        out.push_back(last);
    }
    return out;
}

static PackedVector2Array simplify_closed_polygon(const PackedVector2Array &pts, double eps) {
    int n = pts.size();
    if (n <= 4) return pts;
    int mid = n / 2;
    PackedVector2Array c1, c2;
    for (int i = 0; i <= mid; i++)        c1.push_back(pts[i]);
    for (int i = mid; i < n;  i++)        c2.push_back(pts[i]);
    c2.push_back(pts[0]);
    c1 = douglas_peucker(c1, eps);
    c2 = douglas_peucker(c2, eps);
    PackedVector2Array out;
    for (int i = 0; i < c1.size();           i++) out.push_back(c1[i]);
    for (int i = 1; i < c2.size() - 1;       i++) out.push_back(c2[i]);
    return out;
}

static double signed_area(const PackedVector2Array &pts) {
    if (pts.size() < 3) return 0.0;
    double s = 0.0;
    for (int i = 0; i < pts.size(); i++) {
        int j = (i + 1) % pts.size();
        s += pts[i].x * pts[j].y - pts[j].x * pts[i].y;
    }
    return s * 0.5;
}

static double polygon_area(const PackedVector2Array &pts) { return std::abs(signed_area(pts)); }

} // anonymous namespace

CollisionShape2D *TerrainCollider::build_collision(
    const PackedByteArray &data, int size, StaticBody2D *static_body,
    const Vector2i &world_offset) {

    int samples_w = size / CELL_SIZE + 1;
    int samples_h = size / CELL_SIZE + 1;
    std::vector<uint8_t> samples(samples_w * samples_h, 0);

    for (int sy = 0; sy < samples_h; sy++) {
        for (int sx = 0; sx < samples_w; sx++) {
            if (sx == 0 || sx == samples_w - 1 || sy == 0 || sy == samples_h - 1) continue;
            int gx = MIN(sx * CELL_SIZE, size - 1);
            int gy = MIN(sy * CELL_SIZE, size - 1);
            samples[sy * samples_w + sx] = (data[gy * size + gx] != 0) ? 1 : 0;
        }
    }

    int cells_w = samples_w - 1;
    int cells_h = samples_h - 1;

    HashMap<Vector2i, std::vector<Vector2i>> adj;
    auto add_edge = [&](const Vector2i &a, const Vector2i &b) {
        adj[a].push_back(b);
        adj[b].push_back(a);
    };

    for (int cy = 0; cy < cells_h; cy++) {
        for (int cx = 0; cx < cells_w; cx++) {
            int tl = samples[cy * samples_w + cx];
            int tr = samples[cy * samples_w + cx + 1];
            int br = samples[(cy + 1) * samples_w + cx + 1];
            int bl = samples[(cy + 1) * samples_w + cx];
            int idx = (tl << 3) | (tr << 2) | (br << 1) | bl;
            for (int k = 0; k < MS_TABLE[idx].count; k++) {
                Vector2i p1 = edge_point(cx, cy, MS_TABLE[idx].seg[k][0]);
                Vector2i p2 = edge_point(cx, cy, MS_TABLE[idx].seg[k][1]);
                add_edge(p1, p2);
            }
        }
    }

    PackedVector2Array all_segments;
    HashMap<Vector2i, bool> visited;

    for (const KeyValue<Vector2i, std::vector<Vector2i>> &kv : adj) {
        Vector2i start = kv.key;
        if (visited.has(start)) continue;
        if (kv.value.empty())   continue;

        PackedVector2Array poly;
        Vector2i current = start;
        Vector2i prev    = Vector2i(-999999, -999999);
        bool     closed  = false;

        while (true) {
            visited[current] = true;
            poly.push_back(Vector2(current.x, current.y));

            const std::vector<Vector2i> &nbrs = adj[current];
            Vector2i next = Vector2i(-999999, -999999);
            for (const Vector2i &n : nbrs) {
                if (n == prev) continue;
                if (n == start && poly.size() >= 3) { next = start; break; }
                if (!visited.has(n))                 { next = n;     break; }
            }
            if (next == start)                       { closed = true; break; }
            if (next == Vector2i(-999999, -999999))                   break;
            prev    = current;
            current = next;
        }

        if (poly.size() >= 3 && closed) {
            poly = simplify_closed_polygon(poly, DP_EPSILON);
            for (int i = 0; i < poly.size(); i++) {
                all_segments.push_back(poly[i]);
                all_segments.push_back(poly[(i + 1) % poly.size()]);
            }
        }
    }

    if (all_segments.size() < 4) return nullptr;
    return build_from_segments(all_segments, static_body, world_offset);
}

CollisionShape2D *TerrainCollider::build_from_segments(
    const PackedVector2Array &segments, StaticBody2D *static_body,
    const Vector2i &world_offset) {

    if (segments.size() % 2 != 0) return nullptr;
    if (segments.size() < 4)      return nullptr;

    Ref<ConcavePolygonShape2D> shape;
    shape.instantiate();
    shape->set_segments(segments);

    CollisionShape2D *cs = memnew(CollisionShape2D);
    cs->set_shape(shape);
    static_body->set_position(Vector2(world_offset.x, world_offset.y));
    return cs;
}

PackedVector2Array TerrainCollider::shrink_polygon(const PackedVector2Array &points, double distance) {
    if (points.size() < 3) return PackedVector2Array();
    double sa = signed_area(points);
    double inward = (sa > 0.0) ? 1.0 : -1.0;
    PackedVector2Array out;
    out.resize(points.size());
    for (int i = 0; i < points.size(); i++) {
        int prev_i = (i - 1 + points.size()) % points.size();
        int next_i = (i + 1) % points.size();
        Vector2 e1 = points[i]      - points[prev_i];
        Vector2 e2 = points[next_i] - points[i];
        Vector2 p1(-e1.y, e1.x);
        Vector2 p2(-e2.y, e2.x);
        Vector2 normal = (p1.normalized() + p2.normalized()).normalized();
        out[i] = points[i] + normal * distance * inward;
    }
    return out;
}

TypedArray<OccluderPolygon2D> TerrainCollider::create_occluder_polygons(const PackedVector2Array &segments) {
    TypedArray<OccluderPolygon2D> result;
    if (segments.size() < 4) return result;

    HashMap<Vector2, std::vector<Vector2>> adj;
    for (int i = 0; i < segments.size(); i += 2) {
        adj[segments[i]].push_back(segments[i + 1]);
        adj[segments[i + 1]].push_back(segments[i]);
    }

    HashMap<Vector2, bool> visited;
    Geometry2D *g2d = Geometry2D::get_singleton();

    for (const KeyValue<Vector2, std::vector<Vector2>> &kv : adj) {
        Vector2 start = kv.key;
        if (visited.has(start)) continue;
        if (kv.value.empty())   continue;

        PackedVector2Array chain;
        Vector2 current = start;
        Vector2 prev(-1e9, -1e9);
        bool    closed = false;

        while (true) {
            visited[current] = true;
            chain.push_back(current);
            const std::vector<Vector2> &nbrs = adj[current];
            Vector2 next(-1e9, -1e9);
            for (const Vector2 &n : nbrs) {
                if (n == prev) continue;
                if (n == start && chain.size() >= 3) { next = start; break; }
                if (!visited.has(n))                  { next = n;     break; }
            }
            if (next == start)                  { closed = true; break; }
            if (next == Vector2(-1e9, -1e9))                     break;
            prev    = current;
            current = next;
        }

        if (chain.size() >= 3 && closed) {
            if (signed_area(chain) < 0.0) continue; // skip air-hole loops
            TypedArray<PackedVector2Array> shrunk = g2d->offset_polygon(chain, -OCCLUDER_INSET, Geometry2D::JOIN_MITER);
            for (int i = 0; i < shrunk.size(); i++) {
                PackedVector2Array s = shrunk[i];
                if (s.size() >= 3 && polygon_area(s) >= MIN_OCCLUDER_AREA) {
                    Ref<OccluderPolygon2D> poly;
                    poly.instantiate();
                    poly->set_polygon(s);
                    result.push_back(poly);
                }
            }
        }
    }

    return result;
}

void TerrainCollider::_bind_methods() {
    ClassDB::bind_static_method("TerrainCollider",
        D_METHOD("build_collision", "data", "size", "static_body", "world_offset"),
        &TerrainCollider::build_collision);
    ClassDB::bind_static_method("TerrainCollider",
        D_METHOD("build_from_segments", "segments", "static_body", "world_offset"),
        &TerrainCollider::build_from_segments);
    ClassDB::bind_static_method("TerrainCollider",
        D_METHOD("create_occluder_polygons", "segments"),
        &TerrainCollider::create_occluder_polygons);
    ClassDB::bind_static_method("TerrainCollider",
        D_METHOD("shrink_polygon", "points", "distance"),
        &TerrainCollider::shrink_polygon);
}

} // namespace toprogue
```

**Cross-check the marching-squares table against the GDScript source.** Line-by-line: case `1` → `[[3, 2]]`, etc. A swapped pair here silently corrupts every collider in the game.

**Memory ownership of returned `CollisionShape2D *`.** `memnew(CollisionShape2D)` returns an unparented `Node`; the GDScript caller (today's `terrain_collision_helper.gd`) owns the reference and parents it via `chunk.static_body.add_child(shape)`. Same contract holds when called from C++ in Task 4: caller adds to a parent within the same call frame, godot-cpp memory management is satisfied.

**`Geometry2D::offset_polygon` return shape.** Verify `gdextension/godot-cpp/gen/include/godot_cpp/classes/geometry2d.hpp` — recent godot-cpp returns `TypedArray<PackedVector2Array>`. If on the pinned SHA it returns `Array`, switch `shrunk[i]` to `((Array)shrunk)[i]` and cast accordingly.

- [ ] **Step 3: Build standalone**

```bash
./gdextension/build.sh debug
```

Expected: clean. Common failure modes:
- `HashMap<Vector2i, ...>` requires `Vector2i` to have a hash trait — godot-cpp provides one. If the compiler complains, include `<godot_cpp/templates/hashfuncs.hpp>` or fall back to keying by `int64_t` (pack `(x << 32) | (uint32_t)y`).
- `ConcavePolygonShape2D::set_segments` signature — check the generated header.
- `Geometry2D::JOIN_MITER` enum spelling — check the generated header.

- [ ] **Step 4: Commit**

```bash
git add gdextension/src/physics/terrain_collider.h gdextension/src/physics/terrain_collider.cpp
git commit -m "feat: add TerrainCollider C++ class"
```

---

## Task 2: Add `ColliderBuilder` C++ class

`ColliderBuilder` is the new class introduced by spec §8.3. It owns the cell-mask → segments piece that today's `TerrainCollider.build_collision` does inline; we extract it so the spec's eventual chunk → polygons → TerrainCollider pipeline is clean. Concretely, `ColliderBuilder::build_segments(data, size)` returns a `PackedVector2Array` of segment-pair endpoints, exactly what `TerrainCollider::build_from_segments` and `TerrainCollider::create_occluder_polygons` already consume.

**Files:**
- Create: `gdextension/src/physics/collider_builder.h`
- Create: `gdextension/src/physics/collider_builder.cpp`

- [ ] **Step 1: Write the header**

```cpp
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

namespace toprogue {

// Spec §8.3. Walks a chunk's solid-cell mask and produces the segment-pair endpoint
// list consumed by TerrainCollider::build_from_segments / create_occluder_polygons.
// Replaces shaders/compute/collider.glsl.
class ColliderBuilder : public godot::RefCounted {
    GDCLASS(ColliderBuilder, godot::RefCounted);

public:
    // `data` is `size * size` bytes, one byte per cell, non-zero = solid.
    // Returns a flat array of segment endpoint pairs: [A0, B0, A1, B1, ...].
    static godot::PackedVector2Array build_segments(
        const godot::PackedByteArray &data, int size);

protected:
    static void _bind_methods();
};

} // namespace toprogue
```

- [ ] **Step 2: Write the implementation**

`build_segments` is the marching-squares + chain-tracing portion of `TerrainCollider::build_collision`, returning the `all_segments` array instead of building a `CollisionShape2D`. Factor by **calling the same internal logic**: refactor Task 1's `build_collision` into a thin wrapper that calls `ColliderBuilder::build_segments` then `TerrainCollider::build_from_segments`.

After the refactor:
- `ColliderBuilder::build_segments(data, size)` → `PackedVector2Array` (the segment list).
- `TerrainCollider::build_collision(data, size, body, off)` calls `ColliderBuilder::build_segments(data, size)` then `build_from_segments(segs, body, off)`.

This means **Task 1's `build_collision` body moves into `ColliderBuilder::build_segments`** (returning `all_segments`), and the small wrapper stays in `TerrainCollider`. Re-edit `terrain_collider.cpp` accordingly.

```cpp
// gdextension/src/physics/collider_builder.cpp
#include "collider_builder.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/templates/hash_map.hpp>

#include <vector>

using namespace godot;

namespace toprogue {

// Same MS_TABLE / edge_point as terrain_collider.cpp. Either move the
// helpers into a shared anonymous-namespace header (e.g.
// gdextension/src/physics/_marching_squares.inl included from both .cpp files)
// or re-declare them here. Pick the option that keeps both translation units
// readable; do not duplicate the table by accident.

PackedVector2Array ColliderBuilder::build_segments(const PackedByteArray &data, int size) {
    // ... body lifted from old TerrainCollider::build_collision, returning all_segments.
}

void ColliderBuilder::_bind_methods() {
    ClassDB::bind_static_method("ColliderBuilder",
        D_METHOD("build_segments", "data", "size"),
        &ColliderBuilder::build_segments);
}

} // namespace toprogue
```

**Decide where the marching-squares helpers live** before writing the body:
- Option A: `gdextension/src/physics/_marching_squares.inl` — anonymous-namespace `static` definitions, included by both `terrain_collider.cpp` and `collider_builder.cpp`. Compile-fast, no link issues, two TUs each have their own copy.
- Option B: a new internal header `_marching_squares.h` + `.cpp` with non-`static` linkage. More moving parts, no benefit at this scale.

Go with Option A. It mirrors how godot-cpp itself handles small shared inline helpers.

- [ ] **Step 3: Refactor `TerrainCollider::build_collision` to delegate**

```cpp
CollisionShape2D *TerrainCollider::build_collision(
    const PackedByteArray &data, int size, StaticBody2D *static_body,
    const Vector2i &world_offset) {
    PackedVector2Array segs = ColliderBuilder::build_segments(data, size);
    if (segs.size() < 4) return nullptr;
    return build_from_segments(segs, static_body, world_offset);
}
```

- [ ] **Step 4: Build, run a quick smoke**

```bash
./gdextension/build.sh debug
```

Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add gdextension/src/physics/collider_builder.{h,cpp} \
        gdextension/src/physics/terrain_collider.cpp \
        gdextension/src/physics/_marching_squares.inl
git commit -m "feat: add ColliderBuilder C++ class; factor marching squares from TerrainCollider"
```

---

## Task 3: Port `GasInjector` to C++

Static-method bag, single call site, byte-format must be preserved.

**Files:**
- Create: `gdextension/src/physics/gas_injector.h`
- Create: `gdextension/src/physics/gas_injector.cpp`

- [ ] **Step 1: Write the header**

```cpp
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace toprogue {

// Mirrors src/physics/gas_injector.gd 1:1. Byte format is consumed by
// shaders/include/sim/* — must stay byte-for-byte stable until step 7.
class GasInjector : public godot::RefCounted {
    GDCLASS(GasInjector, godot::RefCounted);

public:
    static constexpr int MAX_INJECTIONS_PER_CHUNK = 32;
    static constexpr double MIN_SPEED_SQ          = 0.25;
    static constexpr double VELOCITY_SCALE        = 1.0 / 60.0;
    static constexpr int CHUNK_SIZE               = 256;
    static constexpr int HEADER_BYTES             = 16;
    static constexpr int BODY_BYTES               = 32;
    static constexpr int BUFFER_BYTES             = HEADER_BYTES + BODY_BYTES * MAX_INJECTIONS_PER_CHUNK;

    static godot::PackedByteArray build_payload(
        godot::SceneTree     *scene,
        const godot::Vector2i &coord);

protected:
    static void _bind_methods();
};

} // namespace toprogue
```

- [ ] **Step 2: Write the implementation**

Port `_get_node_velocity`, `_world_aabb_of`, `_shape_aabb` as anonymous-namespace free functions.

Pay attention to:
- **`"velocity" in node` fallback in `_get_node_velocity`.** GDScript's `in` operator on a `Node2D` checks `has_method`/`has_property`. In C++, use `node->has_meta("velocity")` ? No — actually use `node->get_property_list()` lookup, or simpler: `Variant v = node->get("velocity"); if (v.get_type() == Variant::VECTOR2) return v;`. The latter matches the GDScript semantic without iterating properties.
- **`CollisionObject2D::get_shape_owners`** returns `PackedInt32Array` in godot-cpp (not GDScript's untyped Array). Iterate with `int32_t` index.
- **`Transform2D` × `Rect2`** operator is bound in godot-cpp on `Transform2D` — verify with `xform_inv` not needed; just use `xform * rect`.
- **`encode_s32` byte-offset math.** Translates 1:1 from GDScript: `out.encode_s32(offset, value)`. Call exists on `PackedByteArray` in godot-cpp.

After porting, run a unit-byte-equality check (Task 8 step 3) where you call the C++ `build_payload` and the GDScript `build_payload` on the same scene and `memcmp` the results before deleting the GDScript version.

- [ ] **Step 3: Build standalone**

```bash
./gdextension/build.sh debug
```

- [ ] **Step 4: Commit**

```bash
git add gdextension/src/physics/gas_injector.{h,cpp}
git commit -m "feat: add GasInjector C++ class"
```

---

## Task 4: Port `TerrainCollisionHelper` to C++

Owns the round-robin rebuild loop. Drops the GPU collider path entirely; keeps the texture readback (`RenderingDevice::texture_get_data`) and feeds it into `ColliderBuilder` + `TerrainCollider`.

**Files:**
- Create: `gdextension/src/terrain/terrain_collision_helper.h`
- Create: `gdextension/src/terrain/terrain_collision_helper.cpp`

- [ ] **Step 1: Write the header**

```cpp
#pragma once

#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace toprogue {

// Mirrors src/core/terrain_collision_helper.gd's surface, minus the GPU path.
class TerrainCollisionHelper : public godot::RefCounted {
    GDCLASS(TerrainCollisionHelper, godot::RefCounted);

public:
    static constexpr int    CHUNK_SIZE                  = 256;
    static constexpr double COLLISION_REBUILD_INTERVAL  = 0.2;
    static constexpr int    COLLISIONS_PER_FRAME        = 4;

    godot::Node2D *world_manager = nullptr;

    TerrainCollisionHelper() = default;

    void rebuild_dirty(const godot::Dictionary &chunks, double delta);
    void rebuild_chunk_collision_cpu(const godot::Variant &chunk);

    godot::Node2D *get_world_manager() const                 { return world_manager; }
    void           set_world_manager(godot::Node2D *v)        { world_manager = v; }

protected:
    static void _bind_methods();

private:
    double _collision_rebuild_timer = 0.0;
    int    _collision_rebuild_index = 0;
};

} // namespace toprogue
```

**Why `Variant chunk` not `Ref<Chunk>`:** the GDScript `chunks: Dictionary` stores `Variant` values; iterating yields `Variant`. We `Ref<Chunk> c = Object::cast_to<Chunk>(chunk_v)` inside the body. If we typed it as `Ref<Chunk>` directly, godot-cpp would still coerce — but the `Variant` form documents the bridge layer.

- [ ] **Step 2: Write the implementation**

Port `rebuild_dirty` and `rebuild_chunk_collision_cpu` from the GDScript. Replace the GPU branch with the CPU path unconditionally:

```cpp
void TerrainCollisionHelper::rebuild_dirty(const Dictionary &chunks, double delta) {
    if (chunks.is_empty()) return;
    _collision_rebuild_timer += delta;
    if (_collision_rebuild_timer < COLLISION_REBUILD_INTERVAL) return;
    _collision_rebuild_timer = 0.0;

    Array coords = chunks.keys();
    int   total  = coords.size();
    int   count  = MIN(COLLISIONS_PER_FRAME, total);
    for (int i = 0; i < count; i++) {
        int idx = (_collision_rebuild_index + i) % total;
        Variant chunk_v = chunks[coords[idx]];
        rebuild_chunk_collision_cpu(chunk_v);
    }
    _collision_rebuild_index = (_collision_rebuild_index + count) % MAX(1, total);
}
```

The CPU path needs three things from `world_manager`:
1. The `RenderingDevice` (`world_manager.rd`) for `texture_get_data`.
2. The `collision_container` (`world_manager.collision_container`) for parenting `LightOccluder2D`s.

Both today live as GDScript fields on the `world_manager` Node2D. From C++, fetch them via `world_manager->get("rd")` and `world_manager->get("collision_container")`. This is the bridge contract — `world_manager` stays GDScript this step.

```cpp
void TerrainCollisionHelper::rebuild_chunk_collision_cpu(const Variant &chunk_v) {
    Ref<Chunk> chunk = chunk_v;
    if (chunk.is_null()) return;
    if (world_manager == nullptr) return;

    // Pull rd and collision_container from the GDScript WorldManager.
    Object *rd_obj = world_manager->get("rd");
    RenderingDevice *rd = Object::cast_to<RenderingDevice>(rd_obj);
    if (rd == nullptr) return;

    PackedByteArray chunk_data = rd->texture_get_data(chunk->rd_texture, 0);

    PackedByteArray material_data;
    material_data.resize(CHUNK_SIZE * CHUNK_SIZE);
    MaterialTable *mt = MaterialTable::get_singleton();
    for (int y = 0; y < CHUNK_SIZE; y++) {
        for (int x = 0; x < CHUNK_SIZE; x++) {
            int  src = (y * CHUNK_SIZE + x) * 4;
            int  mat = chunk_data[src];
            material_data[y * CHUNK_SIZE + x] = mt->has_collider(mat) ? mat : 0;
        }
    }

    Vector2i world_offset = chunk->coord * CHUNK_SIZE;

    StaticBody2D *body = chunk->static_body;
    if (body && body->get_child_count() > 0) {
        TypedArray<Node> children = body->get_children();
        for (int i = 0; i < children.size(); i++) {
            Node *c = Object::cast_to<Node>(children[i]);
            if (c) c->queue_free();
        }
    }

    PackedVector2Array segs = ColliderBuilder::build_segments(material_data, CHUNK_SIZE);
    CollisionShape2D *shape = TerrainCollider::build_from_segments(segs, body, world_offset);
    if (shape) body->add_child(shape);

    // Occluders.
    Node *occluder_parent = Object::cast_to<Node>(world_manager->get("collision_container").operator Object*());
    TypedArray<LightOccluder2D> existing = chunk->occluder_instances;
    for (int i = 0; i < existing.size(); i++) {
        Object *o = existing[i];
        Node   *n = Object::cast_to<Node>(o);
        if (n && n->is_inside_tree()) n->queue_free();
    }
    existing.clear();
    chunk->occluder_instances = existing;

    if (segs.size() >= 4 && occluder_parent) {
        TypedArray<OccluderPolygon2D> polys = TerrainCollider::create_occluder_polygons(segs);
        Vector2 chunk_pos(chunk->coord.x * CHUNK_SIZE, chunk->coord.y * CHUNK_SIZE);
        for (int i = 0; i < polys.size(); i++) {
            Ref<OccluderPolygon2D> p = polys[i];
            LightOccluder2D *occ = memnew(LightOccluder2D);
            occ->set_position(chunk_pos);
            occ->set_occluder(p);
            occluder_parent->add_child(occ);
            existing.push_back(occ);
        }
        chunk->occluder_instances = existing;
    }
}
```

**The `parse_segment_buffer` and `rebuild_chunk_collision_gpu` methods are gone.** Don't port them. The GPU buffer no longer exists.

**`Object *` from `Variant`.** `world_manager->get("rd").operator Object*()` is the spelling for unwrapping a Variant to a raw Object pointer in godot-cpp. Verify in the generated headers; if the cast spelling differs, use `((Object *)Variant(world_manager->get("rd")))`.

- [ ] **Step 3: Bind methods**

```cpp
void TerrainCollisionHelper::_bind_methods() {
    ClassDB::bind_method(D_METHOD("rebuild_dirty", "chunks", "delta"),
        &TerrainCollisionHelper::rebuild_dirty);
    ClassDB::bind_method(D_METHOD("rebuild_chunk_collision_cpu", "chunk"),
        &TerrainCollisionHelper::rebuild_chunk_collision_cpu);

    ClassDB::bind_method(D_METHOD("get_world_manager"), &TerrainCollisionHelper::get_world_manager);
    ClassDB::bind_method(D_METHOD("set_world_manager", "v"), &TerrainCollisionHelper::set_world_manager);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "world_manager",
                              PROPERTY_HINT_NODE_TYPE, "Node2D"),
                 "set_world_manager", "get_world_manager");
}
```

- [ ] **Step 4: Build standalone**

```bash
./gdextension/build.sh debug
```

- [ ] **Step 5: Commit**

```bash
git add gdextension/src/terrain/terrain_collision_helper.{h,cpp}
git commit -m "feat: add TerrainCollisionHelper C++ class (CPU path only)"
```

---

## Task 5: Port `TerrainPhysical` to C++

`Node`-derived. Tiny class. Public surface: `query`, `invalidate_rect`, `set_center`, `world_manager` field.

**Files:**
- Create: `gdextension/src/terrain/terrain_physical.h`
- Create: `gdextension/src/terrain/terrain_physical.cpp`

- [ ] **Step 1: Write the header**

```cpp
#pragma once

#include "../resources/terrain_cell.h"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <vector>

namespace toprogue {

class TerrainPhysical : public godot::Node {
    GDCLASS(TerrainPhysical, godot::Node);

public:
    godot::Node2D *world_manager = nullptr;

    TerrainPhysical() = default;

    godot::Ref<TerrainCell> query(const godot::Vector2 &world_pos) const;
    void                    invalidate_rect(const godot::Rect2i &rect);
    void                    set_center(const godot::Vector2i &world_center);

    godot::Node2D *get_world_manager() const             { return world_manager; }
    void           set_world_manager(godot::Node2D *v)    { world_manager = v; }

protected:
    static void _bind_methods();

private:
    godot::HashMap<godot::Vector2i, int> _grid;
    godot::Vector2i                      _grid_center;
    int                                  _grid_size = 128;
    int                                  _half_grid = 64;
    std::vector<godot::Rect2i>           _dirty_sectors;

    godot::Ref<TerrainCell> _cell_from_material(int mat_id) const;
};

} // namespace toprogue
```

- [ ] **Step 2: Write the implementation**

Port the four methods 1:1. `_segments_per_chunk` from the GDScript is unused (declared but never read by anything outside the class) — verify with `grep -rn "_segments_per_chunk"` and drop it from the C++ port if confirmed.

```cpp
Ref<TerrainCell> TerrainPhysical::query(const Vector2 &world_pos) const {
    Vector2i cp(int(std::floor(world_pos.x)), int(std::floor(world_pos.y)));
    HashMap<Vector2i, int>::ConstIterator it = _grid.find(cp);
    if (it != _grid.end()) {
        return _cell_from_material(it->value);
    }
    Ref<TerrainCell> empty;
    empty.instantiate();
    return empty;
}

void TerrainPhysical::invalidate_rect(const Rect2i &rect) {
    for (int x = rect.position.x; x < rect.position.x + rect.size.x; x++) {
        for (int y = rect.position.y; y < rect.position.y + rect.size.y; y++) {
            _grid.erase(Vector2i(x, y));
        }
    }
    _dirty_sectors.push_back(rect);
}

void TerrainPhysical::set_center(const Vector2i &world_center) {
    _grid_center = world_center;
}

Ref<TerrainCell> TerrainPhysical::_cell_from_material(int mat_id) const {
    MaterialTable *mt = MaterialTable::get_singleton();
    bool is_solid = mt->has_collider(mat_id);
    bool is_fluid = mt->is_fluid(mat_id);
    int  dmg      = mt->get_damage(mat_id);
    Ref<TerrainCell> c;
    c.instantiate();
    c->init_args(mat_id, is_solid, is_fluid, dmg);
    return c;
}
```

**`_grid` populated where?** Not in this class — `lava_damage_checker.gd` calls `query` and the cache is currently empty until something writes to it. Inspecting `terrain_modifier.gd`: it calls `invalidate_rect` (which only erases entries, never inserts). So today's `_grid` is **always empty**, and `query` always returns the default `TerrainCell` (no material). This is a pre-existing latent feature, not a bug, and not something to fix in this step. Port the empty-grid behavior verbatim.

- [ ] **Step 3: Bind methods**

```cpp
void TerrainPhysical::_bind_methods() {
    ClassDB::bind_method(D_METHOD("query", "world_pos"), &TerrainPhysical::query);
    ClassDB::bind_method(D_METHOD("invalidate_rect", "rect"), &TerrainPhysical::invalidate_rect);
    ClassDB::bind_method(D_METHOD("set_center", "world_center"), &TerrainPhysical::set_center);

    ClassDB::bind_method(D_METHOD("get_world_manager"), &TerrainPhysical::get_world_manager);
    ClassDB::bind_method(D_METHOD("set_world_manager", "v"), &TerrainPhysical::set_world_manager);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "world_manager",
                              PROPERTY_HINT_NODE_TYPE, "Node2D"),
                 "set_world_manager", "get_world_manager");
}
```

- [ ] **Step 4: Build standalone**

```bash
./gdextension/build.sh debug
```

- [ ] **Step 5: Commit**

```bash
git add gdextension/src/terrain/terrain_physical.{h,cpp}
git commit -m "feat: add TerrainPhysical C++ class"
```

---

## Task 6: Register the new classes

**Files:**
- Modify: `gdextension/src/register_types.cpp`

- [ ] **Step 1: Add includes and `GDREGISTER_CLASS` calls**

```cpp
#include "physics/collider_builder.h"
#include "physics/gas_injector.h"
#include "physics/terrain_collider.h"
#include "terrain/terrain_collision_helper.h"
#include "terrain/terrain_physical.h"
```

In `initialize_toprogue_module`, after the leaf registrations, add:

```cpp
    // Collider + physics — register before TerrainCollisionHelper, which calls them.
    GDREGISTER_CLASS(ColliderBuilder);
    GDREGISTER_CLASS(TerrainCollider);
    GDREGISTER_CLASS(GasInjector);
    GDREGISTER_CLASS(TerrainCollisionHelper);
    GDREGISTER_CLASS(TerrainPhysical);
```

- [ ] **Step 2: Build and confirm clean**

```bash
./gdextension/build.sh debug
```

- [ ] **Step 3: Open the editor — verify class registration**

Launch Godot 4.6 → open project. Output log:
- Expected warning: `Class "TerrainCollider" hides a global script class` etc. for each ported class. Disappears in Task 8 when the GDScript files are deleted.
- No errors.

In the GDScript console (or a scratch `_ready()`):
```gdscript
print(ClassDB.class_exists("ColliderBuilder"))         # true
print(ClassDB.class_exists("TerrainCollider"))         # true
print(ClassDB.class_exists("GasInjector"))             # true
print(ClassDB.class_exists("TerrainCollisionHelper"))  # true
print(ClassDB.class_exists("TerrainPhysical"))         # true
```

- [ ] **Step 4: Commit**

```bash
git add gdextension/src/register_types.cpp
git commit -m "feat: register ColliderBuilder, TerrainCollider, GasInjector, TerrainCollisionHelper, TerrainPhysical"
```

---

## Task 7: Migrate GDScript callsites

Most callsites need no change — the native types use the original class names. Two specific tweaks are needed:

1. `world_manager.gd` constructs `TerrainCollisionHelper.new()` and `TerrainPhysical.new()`, then sets `world_manager` and (for `TerrainPhysical`) `name = "TerrainPhysical"` and `add_child(...)`. The native types accept all of these via the bound `world_manager` property and `Node` API. **No code changes expected here**, but verify by reading `world_manager.gd` lines 38–47 against the bindings in Tasks 4 and 5. If the editor errors at runtime when assigning `terrain_physical.world_manager = self`, the binding spelling doesn't match — fix in the C++ binding, not the GDScript.
2. `lava_damage_checker.gd` calls `wm.get_node_or_null("TerrainPhysical")` then `query(Vector2(...))`. `query` returns `Ref<TerrainCell>`. The GDScript-side callsite annotates the result as `var cell: TerrainCell`. Both are fine — `Ref<TerrainCell>` resolves to GDScript's `TerrainCell` type identifier.

- [ ] **Step 1: Re-grep callsites and confirm no `.new(...)` uses arguments**

```bash
grep -rn "TerrainCollider\.new(\|GasInjector\.new(\|TerrainCollisionHelper\.new(\|TerrainPhysical\.new(\|ColliderBuilder\.new(" \
    src/ tests/ tools/
```

Expected: only zero-arg `.new()` calls. None should pass arguments. If anything does, write an `init_args` shim like step 4 did for `SectorGrid`.

- [ ] **Step 2: Run the project**

F5. Generate a level. Walk through it, dig into terrain, splash through gas. Confirm:
- Collisions still work (player doesn't fall through floors).
- Occluders still cast shadows around walls.
- `lava_damage_checker.gd` doesn't crash when sampling.
- Gas movement (rigidbody-pushed) still propagates — `GasInjector.build_payload` is feeding the GLSL simulator the same bytes.

If the player falls through floors immediately on spawn, the most likely cause is `rebuild_chunk_collision_cpu` not firing or producing zero segments. Add a `UtilityFunctions::print_verbose("rebuild_chunk_collision_cpu coord=", chunk->coord, " segs=", segs.size())` at the top of the C++ method, rerun, and trace.

- [ ] **Step 3: Run gdUnit4**

All green.

- [ ] **Step 4: Commit (only if any GDScript actually changed)**

```bash
git status
# If src/ shows changes:
git add src/
git commit -m "refactor: migrate collider/physics callsites to native types"
# If not, skip this commit.
```

---

## Task 8: Delete the GDScript originals, the GPU collider path, and `collider.glsl`

**Files deleted:**
- `src/physics/terrain_collider.gd` + `.uid`
- `src/physics/gas_injector.gd` + `.uid`
- `src/core/terrain_collision_helper.gd` + `.uid`
- `src/core/terrain_physical.gd` + `.uid`
- `shaders/compute/collider.glsl`
- `shaders/compute/collider.glsl.import`

**Files modified:**
- `src/core/compute_device.gd` — remove `collider_shader`, `collider_pipeline`, `collider_storage_buffer` fields, their initialization, and any teardown.

- [ ] **Step 1: Capture each `.uid` value before deletion**

```bash
for f in src/physics/terrain_collider.gd src/physics/gas_injector.gd \
         src/core/terrain_collision_helper.gd src/core/terrain_physical.gd; do
    if [ -f "$f.uid" ]; then
        echo "=== $f.uid ==="
        cat "$f.uid"
    fi
done
```

For each UID printed, search the project (excluding `.uid` files):

```bash
for uid in <paste UIDs from above, one per line>; do
    grep -rn "$uid" . 2>/dev/null | grep -v "\.uid:" || true
done
```

Expected: zero hits.

- [ ] **Step 2: Excise the GPU collider plumbing from `compute_device.gd`**

Open `src/core/compute_device.gd`. Find every reference to `collider_shader`, `collider_pipeline`, `collider_storage_buffer`. Remove:
- Field declarations.
- The `load("res://shaders/compute/collider.glsl")` line and its `RenderingDevice.shader_create_from_spirv(...)` setup.
- The pipeline create call.
- The storage-buffer create call.
- Any `rd.free_rid(...)` calls in teardown that target these specific RIDs.

Re-grep before committing:
```bash
grep -rn "collider_shader\|collider_pipeline\|collider_storage_buffer" src/
```
Expected: zero hits.

The rest of `ComputeDevice` (generation, simulation) stays.

- [ ] **Step 3: Delete the four `.gd` files and their `.uid` sidecars, plus the shader files**

```bash
rm src/physics/terrain_collider.gd      src/physics/terrain_collider.gd.uid
rm src/physics/gas_injector.gd          src/physics/gas_injector.gd.uid
rm src/core/terrain_collision_helper.gd src/core/terrain_collision_helper.gd.uid
rm src/core/terrain_physical.gd         src/core/terrain_physical.gd.uid
rm shaders/compute/collider.glsl        shaders/compute/collider.glsl.import
```

- [ ] **Step 4: Confirm zero stale references**

```bash
grep -rn \
  "res://src/physics/terrain_collider\.gd\|\
res://src/physics/gas_injector\.gd\|\
res://src/core/terrain_collision_helper\.gd\|\
res://src/core/terrain_physical\.gd\|\
res://shaders/compute/collider\.glsl" .
```

Expected: zero hits. If a `.tscn` (or any other file) still references one of these paths, it's a stale ref — fix it before committing.

- [ ] **Step 5: Open the editor and confirm a clean load**

Launch Godot 4.6 → open project. Output log:
- No "Identifier 'TerrainCollider' not declared" or similar.
- No "could not parse script" errors.
- No "Class TerrainCollider hides a global script class" warnings (they cleared with the `.gd` deletion).
- No errors loading `compute_device.gd` (you removed the collider shader load, so `collider.glsl` being gone is fine).

F5 → walk for 10s → quit.

- [ ] **Step 6: Commit**

```bash
git add src/ shaders/
git commit -m "refactor: delete GDScript collider/physics, GPU collider shader, and ComputeDevice collider plumbing"
```

---

## Task 9: Final verification

- [ ] **Step 1: Final greps — deleted GDScript classes**

```bash
ls src/physics/terrain_collider.gd src/physics/gas_injector.gd \
   src/core/terrain_collision_helper.gd src/core/terrain_physical.gd 2>&1
```
Expected: "No such file or directory" for all four.

```bash
grep -rn "res://src/physics/terrain_collider\.gd\|\
res://src/physics/gas_injector\.gd\|\
res://src/core/terrain_collision_helper\.gd\|\
res://src/core/terrain_physical\.gd" .
```
Expected: zero hits.

- [ ] **Step 2: Final greps — GPU collider gone**

```bash
ls shaders/compute/collider.glsl shaders/compute/collider.glsl.import 2>&1
grep -rn "collider_storage_buffer\|collider_pipeline\|collider_shader\|rebuild_chunk_collision_gpu\|res://shaders/compute/collider\.glsl" \
    src/ tests/ tools/ project.godot
```
Expected: "No such file or directory" for both shader files; zero hits in the grep.

- [ ] **Step 3: Inventory diff**

```bash
grep -rn "\bTerrainCollider\b\|\bGasInjector\b\|\bTerrainCollisionHelper\b\|\bTerrainPhysical\b\|\bColliderBuilder\b" \
    src/ tests/ tools/ project.godot \
    > /tmp/step5-inventory-after.txt
diff /tmp/step5-inventory-before.txt /tmp/step5-inventory-after.txt | head -60
```
Expected: only changes are (a) the four deleted `.gd` files no longer show up, (b) any callsite tweaks from Task 7. Every other site still resolves.

- [ ] **Step 4: Confirm the build still produces the binary on macOS**

```bash
./gdextension/build.sh debug
ls -la bin/lib/
```

- [ ] **Step 5: Open the editor and run gdUnit4**

Launch Godot 4.6 → Output log clean → run gdUnit4 → all green.

- [ ] **Step 6: Smoke playthrough (~2 min, per spec §10.2)**

Launch → generate a large level → walk through it for ~2 minutes touching gas/lava/fire/digging/combat → exit cleanly. Specifically exercise:
- Walking into terrain (collider rebuild path).
- Digging into terrain (`terrain_modifier.gd` invalidates → `terrain_collision_helper` rebuilds within ≤ 0.2s).
- Lava damage on player (`lava_damage_checker.gd` queries `TerrainPhysical`).
- Gas pushed by rigidbody (`GasInjector` payload → GLSL sim consumes).

No crashes, no visible deadlocks, no frame stutters > 1s.

- [ ] **Step 7: Format C++ sources**

```bash
./gdextension/format.sh
git diff gdextension/src/
```

If formatter changed anything:

```bash
git add gdextension/src/
git commit -m "chore: clang-format collider/physics sources"
```

- [ ] **Step 8: Push the branch**

```bash
git push origin refactor/cpp
```

- [ ] **Step 9: Cross-machine verification**

On the other machine:

```bash
git pull
git submodule update --init --recursive
./gdextension/build.sh debug
```

Open the project in Godot 4.6 → Output log clean → smoke-test as in Step 6.

If anything fails on the second machine that didn't fail on the first, fix and commit before declaring step 5 done.

---

## Done Definition for Step 5

- `gdextension/src/physics/{terrain_collider,gas_injector,collider_builder}.{h,cpp}` and `gdextension/src/terrain/{terrain_collision_helper,terrain_physical}.{h,cpp}` exist and compile clean on macOS and Arch.
- `TerrainCollider`, `GasInjector`, `TerrainCollisionHelper`, `TerrainPhysical`, `ColliderBuilder` are registered as native classes.
- `ColliderBuilder::build_segments` owns the cell-mask → segments pipeline; `TerrainCollider::build_collision` delegates to it.
- The four GDScript files (`src/physics/terrain_collider.gd`, `src/physics/gas_injector.gd`, `src/core/terrain_collision_helper.gd`, `src/core/terrain_physical.gd`) and their `.uid` sidecars are deleted.
- `shaders/compute/collider.glsl` and `shaders/compute/collider.glsl.import` are deleted — **the first compute shader is gone.**
- `src/core/compute_device.gd` no longer declares or initializes `collider_shader`, `collider_pipeline`, or `collider_storage_buffer`.
- Zero stale `res://` references remain to any deleted file.
- Behavior is preserved: collisions rebuild on the existing 0.2s round-robin, occluders still attach, lava damage still triggers, gas physics still injects via the GLSL byte-format.
- Generation and simulation still run on the GPU (steps 6 and 7 own those).
- `gdUnit4` suite passes on both machines.
- Smoke playthrough passes on both machines.

When all of the above are true, Step 5 is complete. Proceed to write the plan for **Step 6 — `Generator` + `SimplexCaveGenerator`** per spec §8.1, §8.2, and §9.1 step 6. The relevant predecessor C++ source for that plan is `gdextension/src/physics/collider_builder.cpp` (the per-chunk job dispatch pattern that `Generator::generate_async` mirrors) and the existing `Chunk` shape from step 4 (the destination of generated cells).
