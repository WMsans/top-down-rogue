# Step 7 — `Simulator` + `ChunkManager` + `WorldManager` + `TerrainModifier` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the cellular simulation, chunk-streaming loop, world-manager, and terrain-modifier to native C++ and **delete every remaining compute shader (`simulation.glsl`), every `shaders/include/sim/*.glslinc`, the `shaders/generated/` directory, `generate_materials.sh`, `comp.spv`, `src/core/compute_device.gd`, and `src/terrain/world_preview.gd`**. After this step the project contains zero compute shaders, zero `RenderingDevice` calls, zero `RDShaderFile`/`RDUniform`/`compute_list`/`push_constant` references, and no `shaders/compute/` or `shaders/include/` directories. Per-frame simulation runs entirely on the CPU with the Noita-style 4-phase chunk-checkerboard scheduler dispatched via `WorkerThreadPool::add_group_task`.

**Architecture:** A new `Simulator` (`RefCounted`) drives the per-frame tick. Each scheduled chunk's update body lives in one of four material-rule translation units under `gdextension/src/sim/rules/{injection,lava,gas,burning}.cpp`, called through a `SimContext` (the single boundary that handles cross-chunk routing + dirty-rect accumulation). `Chunk::upload_texture()` (main thread) mirrors `cells[]` to a `Ref<ImageTexture>` consumed by the existing chunk-render shader. `ChunkManager` and `WorldManager` collapse from GDScript into C++ — `ChunkManager` (`RefCounted`) owns the activation set and per-chunk lifecycle; `WorldManager` (`Node2D`) is the per-frame driver that wires `ChunkManager`, `Simulator`, `Generator`/`SimplexCaveGenerator`, `ColliderBuilder`, `TerrainModifier`, and `GasInjector` together. `TerrainModifier` (`RefCounted`) flips from GPU read-modify-write to direct `Chunk::cells[]` writes that flag `dirty_rect`/`collider_dirty` and clear `sleeping`. The simulator owns no GPU state; the only texture in the system is the per-chunk `ImageTexture` for rendering.

**Tech Stack:** godot-cpp pinned per step 1, C++17, the existing SCons + `build.sh` pipeline. `WorkerThreadPool` is godot-cpp's standard pool — no new threading library. `std::atomic` for the cross-chunk dirty-rect bound updates (header-only, no link change). No new external dependencies.

---

## Required Reading Before Starting

You **must** read all of these before writing any code.

1. **Spec:** `docs/superpowers/specs/2026-04-30-godot-cpp-hot-path-port-design.md`. Mandatory sections:
   - §3.1 — full deletion list. After this step, every entry must be gone (`shaders/compute/`, `shaders/include/`, `shaders/generated/`, `generate_materials.sh`, `comp.spv`, `compute_device.gd`, `material_registry.gd` (already deleted in step 2), `world_preview.gd`).
   - §3.2 — `Chunk`, `SectorGrid`, `ChunkManager`, `TerrainModifier`, `TerrainCollisionHelper`, `TerrainPhysical`, `WorldManager`, `GenerationContext` rows. **Class names must be preserved** — existing `.tscn` and GDScript references resolve to native classes by string-equal class name. Land each port under its existing name; no renames.
   - §3.3 — every gameplay GDScript that calls `WorldManager`/`ChunkManager`/`TerrainModifier`/`TerrainSurface` keeps working through the same surface. Public method names, signatures, and signals do not change.
   - §3.4 — non-goals. No new public surface (§3.4 #1). No bit-exact GLSL parity. No cross-machine determinism. No benchmarking harness.
   - §4 (Architecture) — the `WorldManager → {ChunkManager, Simulator, Generator/SimplexCaveGenerator, ColliderBuilder, MaterialTable}` topology. This is the diagram you implement.
   - §6 in full — load-bearing. Specifically:
     - §6.1 cell layout — `Cell { uint8_t material, health, temperature, flags }`. Step 4 already added `Cell cells[]`; this step starts using it as the single source of truth.
     - §6.2 4-phase checkerboard — `(coord.x & 1, coord.y & 1)` partitions the active set; `WorkerThreadPool::add_group_task` per phase, joined before advancing. Four sync points per frame.
     - §6.3 per-chunk update — sleeping early-return → dirty-rect iteration → rule dispatch → next-frame dirty rect = bounding box of moved cells.
     - §6.4 cross-chunk write safety — `next_dirty_rect` bounds extend via `std::atomic` compare-exchange min/max. **No mutex anywhere in the sim path.**
     - §6.5 wake conditions — injection / neighbor write / `TerrainModifier` write all clear `sleeping` and extend `next_dirty_rect`.
     - §6.6 material rules — one TU per rule, all access through `SimContext`. `hash(pos.x ^ hash(pos.y ^ frame_seed ^ salt))` for stochastic decisions, same shape as the GLSL `stochastic_div`.
     - §6.7 no double-buffering — mutate in place. Don't re-litigate this.
     - §6.8 determinism — `(seed, frame_index)` is bit-stable on a single machine; cross-machine determinism is explicitly out of scope.
     - §6.9 frame budget — no specific budget guarantee; profile after the simulator step lands. If the budget busts, see risk #1 in §10.
   - §7 — `MaterialTable`. The struct shape (`MaterialKind`, `flammable`, `ignition_temp`, `burn_rate`, `max_health`, …) is the contract the rules read. **Today's `MaterialTable` (per step 2) lacks the simulation-specific fields the rules need** (density, viscosity, dispersion, diffusion-rate, max-temp). This step extends `MaterialDef` with whatever today's GLSL `materials.glslinc` and `sim/*.glslinc` consume — see Task 2.
   - §8.4 (rendering bridge) — `Chunk::upload_texture()` runs on the main thread after each tick; uploads only the dirty rect; feeds the existing non-compute chunk-render shader.
   - §8.5 (`TerrainModifier` post-port) — direct `cells[]` edits, flag `dirty_rect`, flag `collider_dirty`, clear `sleeping`.
   - §8.6 (`GasInjector` post-port) — push injection AABBs onto a per-chunk injection queue consumed by `Simulator` at start of tick. Step 5's `GasInjector` builds a GPU-shaped `PackedByteArray` payload; this step replaces that with a plain `Vector<InjectionAABB>` queue on each chunk.
   - §9.1 step 7 — exact deletion list. Re-grep for it before declaring the step done.
   - §10.1 — risks. #1 (frame budget), #2 (cross-chunk race), #4 (image upload), #5 (hot-reload — restart the editor for verification, do not trust hot-reload across this ABI change).
   - §11 — Done Definition. Every bullet must be true at end of step.

2. **Predecessor C++ source** (steps 1–6, already merged) — read in full before writing C++:
   - `gdextension/src/terrain/chunk.{h,cpp}` — already carries `Cell cells[]`, `dirty_rect`, `next_dirty_rect`, `sleeping`, `collider_dirty`, `neighbor_*`, `Ref<ImageTexture> texture`, plus the legacy GPU mirror fields (`rd_texture`, `texture_2d_rd`, `sim_uniform_set`, `injection_buffer`, …). The legacy GPU fields must be **removed** in this step's task 13 — they go away with `compute_device.gd`. Confirm `Cell *cells_ptr()` exists (added in step 6 task 2 step 2 if it didn't already); the rules need it.
   - `gdextension/src/terrain/sector_grid.{h,cpp}` — pure CPU class, no sim involvement; untouched this step.
   - `gdextension/src/sim/material_table.{h,cpp}` — current `MaterialDef` fields: `id`, `name`, `texture_path`, `flammable`, `ignition_temp`, `burn_health`, `has_collider`, `has_wall_extension`, `tint_color`, `fluid`, `damage`, `glow`. Missing: `density`, `viscosity`, `dispersion`, `diffusion_rate`, `max_temp`, `kind` (POWDER/LIQUID/GAS/SOLID/FIRE/NONE). Task 2 adds them.
   - `gdextension/src/generation/generator.{h,cpp}` and `simplex_cave_generator.{h,cpp}` — Step 6 left a TODO at end-of-`generate_chunks`: it currently uploads to `chunk->rd_texture` via `RenderingDevice::texture_update`. That GPU upload **goes away** in this step (the rd_texture itself goes away); replace with `chunk->upload_texture()` so the new `ImageTexture` carries the bytes the chunk-render shader samples. Same one-line swap, no behavior change in the consumer.
   - `gdextension/src/physics/collider_builder.{h,cpp}` — already CPU-only since step 5; reads `chunk->cells[]` directly. No change needed.
   - `gdextension/src/physics/gas_injector.{h,cpp}` — currently builds a `PackedByteArray` matching the shader's `InjectionAABB[32]` layout. Task 4 step 1 changes the surface to a `Vector<InjectionAABB>` queue stored on the chunk; the byte-shaped output and shader compatibility go away with the shader.
   - `gdextension/src/register_types.cpp` — where the new `GDREGISTER_CLASS` calls land (`Simulator`, `ChunkManager`, `WorldManager`, `TerrainModifier`).

3. **The GDScript being replaced** (read in full so the port isn't blind):
   - `src/core/chunk_manager.gd` (~249 LOC) — `get_desired_chunks()`, `create_chunk()`, `unload_chunk()`, `rebuild_sim_uniform_sets()`, `build_sim_uniform_set()`, `update_render_neighbors()`, `clear_all_chunks()`, `generate_chunks_at()`. Lines 134–193 build per-chunk GPU uniform sets — those die. Lines 46–86 create `chunk.rd_texture` / `chunk.texture_2d_rd` and populate the render shader's `material_textures` param — the texture-2d-rd half dies, the render-shader binding moves to `chunk->texture` (the new `ImageTexture`).
   - `src/core/world_manager.gd` (~262 LOC) — `_ready` (lines 22–51) wires `compute_device`/`chunk_manager`/`terrain_physical`/`terrain_modifier`. `_update_chunks` (lines 68–97) is the per-frame chunk-streaming pass. `_run_simulation` (lines 106–118) drives `compute.dispatch_simulation(chunks, shadow_grid)` — this collapses to `_simulator.tick()`. Public terrain-modification methods (`place_gas`, `place_lava`, `place_material`, `place_fire`, `disperse_materials_in_arc`, `clear_and_push_materials_in_arc`) all delegate to `terrain_modifier`; their public surface is preserved exactly.
   - `src/core/terrain_modifier.gd` (~356 LOC) — every method does `rd.texture_get_data(chunk.rd_texture, …) → mutate bytes → rd.texture_update(...)`. Each becomes a direct `cells[]` write. The "encode velocity into flags" packing in `place_gas` and `disperse_materials_in_arc`/`clear_and_push_materials_in_arc` is preserved byte-for-byte (same `flags` bit layout the rules read).
   - `shaders/compute/simulation.glsl` (60 LOC) — main shader. Bindings, push-constant struct, dispatch order: `try_inject_rigidbody_velocity → simulate_lava → simulate_gas → simulate_burning`. Same order in C++.
   - `shaders/include/sim/common.glslinc` (60 LOC) — hash RNG, cell codec, neighbor reads, flammability checks. Becomes `gdextension/src/sim/sim_context.{h,cpp}` plus inline helpers in the rules.
   - `shaders/include/sim/injection.glslinc` (59 LOC) — AABB-based velocity injection on gas/lava. Becomes `gdextension/src/sim/rules/injection.cpp`.
   - `shaders/include/sim/lava.glslinc` (163 LOC) — advection + buoyancy + temperature. Becomes `gdextension/src/sim/rules/lava.cpp`.
   - `shaders/include/sim/gas.glslinc` (188 LOC) — advection, density, velocity mixing, diffusion. Becomes `gdextension/src/sim/rules/gas.cpp`.
   - `shaders/include/sim/burning.glslinc` (77 LOC) — heat spread, ignition, combustion. Becomes `gdextension/src/sim/rules/burning.cpp`. Today this shader uses a `(pos.x + pos.y) % 2 != phase` checkerboard inside a 2-phase even/odd dispatch; under the C++ 4-phase chunk scheduler this in-cell checkerboard goes away (parallelism guarantee comes from the chunk-level partition now). The behavior change is benign per §3.4 Q3.
   - `shaders/generated/materials.glslinc` and `materials.gdshaderinc` — generated by `generate_materials.sh`. The data they encode (per-material constants) is what `MaterialDef` must carry post-port; cross-reference task 2 step 1.
   - `src/core/compute_device.gd` (~109 LOC at HEAD after step 6) — only the simulation half remains. `init_shaders`, `init_dummy_texture`, `init_material_textures` plus `dispatch_simulation`. Whole file gets deleted in task 13.
   - `src/terrain/world_preview.gd` (+ `.uid`) — preview-mode wiring, dead feature per spec §3.1. Deleted in task 13.

4. **Every callsite that drives the sim or modifies terrain** (so the C++ surface matches usage exactly):
   - `src/core/world_manager.gd::_run_simulation()` line 118 — `compute_device.dispatch_simulation(chunks, shadow_grid)`. Becomes `_simulator.tick()` inside C++ `WorldManager::_process()`.
   - `src/weapons/test_weapon.gd`, `src/weapons/lava_emitter_modifier.gd`, anything in `src/drops/`, `src/enemies/`, `src/player/`, `src/console/cheat_command_system.gd` — every `TerrainSurface.place_*` callsite. Public surface preserved; no changes here.
   - `src/autoload/level_manager.gd` — calls into `WorldManager` (e.g. `world_manager.advance_floor`/`reset` if present). Public surface preserved.
   - `project.godot` autoload list — `MaterialRegistry` is already gone (step 2). Confirm no autoload references `compute_device.gd` directly. The `WorldManager`/`ChunkManager`/`TerrainModifier` instances live inside scenes, not autoloads, so this step doesn't touch the autoload list.
   - `.tscn` files that instance `WorldManager` or `ChunkManager` — these reference the classes by **string class name** (`type="WorldManager"`). Native-class registration with the same name resolves transparently; no `.tscn` edits needed if the class names are preserved (they are). If any scene uses `[ext_resource type="Script" path="res://src/core/world_manager.gd" id="..."]` + `script = ExtResource("...")`, that's the script-backed shape and must be migrated to the native shape (`type="WorldManager"`, no script). `tools/migrate_tres.py` from step 3 already handles this for resources; reuse the same approach for scenes via a one-shot grep + per-scene rewrite. Sample audit:

     ```bash
     grep -rn 'path="res://src/core/world_manager.gd\|path="res://src/core/chunk_manager.gd\|path="res://src/core/terrain_modifier.gd\|path="res://src/core/world_manager.tscn"' --include="*.tscn" .
     ```

5. **Determinism contract (per spec §6.8 and §3.4 Q3):**
   - Per `(initial seed, frame index, input event sequence)`: bit-stable output on a single machine. Cross-machine determinism is not promised. The 4-phase scheduler's lock-free behavior depends on `WorkerThreadPool` job-completion ordering; within a phase the order doesn't matter (chunks are non-adjacent, so writes don't collide), but two `WorkerThreadPool`s with different scheduling can produce different `next_dirty_rect` bounds — that's fine, the rect is conservative. The sim cell content is deterministic.
   - Worlds *will* differ from the GPU-simulated worlds at HEAD. That's expected per §3.4 Q3.

If anything in this plan conflicts with the spec, the spec wins — flag the conflict and stop, do not silently deviate.

## What This Step Does NOT Do

- **Does not** add new public methods, signals, or properties on the ported classes (per §3.4 #1). Internal helpers may be added freely.
- **Does not** introduce cross-machine determinism. If anyone asks for replays/networking later, single-thread the sim — out of scope here.
- **Does not** add a benchmarking harness, a frame-budget guard, or any CI gate. Profile after this step lands; if it busts, follow-up work is per spec §10.1 risk #1.
- **Does not** rebalance gameplay. Material parameters are ported faithfully from `materials.glslinc` / `material_registry.gd` (already in `MaterialTable`) plus whatever sim constants the rule shaders hardcoded (e.g. `DIFFUSION_RATE=4`, `V_MAX_OUTFLOW=8`). New parameter values land in follow-up gameplay work.
- **Does not** change `level_manager.gd::build_stamp_bytes`, `BiomeRegistry`, generation stages, or `ColliderBuilder`. Those landed in steps 3, 5, 6.
- **Does not** introduce per-chunk threading for `Generator`, `SimplexCaveGenerator`, or `ColliderBuilder` beyond what they already do (step 6 already wired `Generator`'s `WorkerThreadPool::add_group_task`). The simulator gets its own dispatch.
- **Does not** delete `comp.spv` separately — it's bundled into task 13's deletion wave alongside the other build artifacts.
- **Does not** add a `Chunk::tick()` method. The per-cell loop body lives in `Simulator::tick_chunk(Chunk *)` so cross-chunk routing flows through the simulator; rules access state via `SimContext`, not via methods on `Chunk`.

## Pre-flight Verification (do this first)

- [ ] **Step 1: Confirm step 6 is merged and the build is green**

```bash
git status
git log --oneline -10
./gdextension/build.sh debug
ls bin/lib/
```

Expected: clean working tree on `refactor/cpp`. Recent commits include the step 6 work (the seven step-6 commits ending in `chore: clang-format generation sources`). Build produces the dylib/so for the current platform.

- [ ] **Step 2: Confirm the editor still loads and runs cleanly with step 6's natives**

Launch Godot 4.6 → open project → Output log clean. F5 → walk for ~30s in a generated level → exercise lava/gas/digging → quit. Smoke confirms the GPU simulation is still alive and that step 6's CPU generation feeds it correctly. This is the last time before step 7 lands that we can sanity-check the GPU sim against the new CPU generation.

- [ ] **Step 3: Inventory simulation/chunk-manager/world-manager/terrain-modifier callsites once, before changes**

```bash
grep -rn "dispatch_simulation\|sim_shader\|sim_pipeline\|sim_uniform_set\|init_material_textures\|init_dummy_texture\|compute_device\|RenderingDevice\|RDShaderFile\|RDUniform\|compute_list\|push_constant\|texture_get_data\|texture_update\|res://shaders/compute/simulation\|res://shaders/include/sim\|res://shaders/generated\|world_preview" \
    src/ tests/ tools/ project.godot \
    > /tmp/step7-inventory-before.txt
wc -l /tmp/step7-inventory-before.txt
```

Save that file — task 14 step 1 re-greps and confirms zero hits remain.

- [ ] **Step 4: Inventory `.tscn` script-backed references to the four ported scripts**

```bash
grep -rn 'path="res://src/core/world_manager.gd\|path="res://src/core/chunk_manager.gd\|path="res://src/core/terrain_modifier.gd' --include="*.tscn" .
```

Capture the list. Task 12 step 3 migrates each to the native-class shape.

- [ ] **Step 5: Confirm `MaterialTable`'s current field set against `materials.glslinc`**

```bash
grep -n "id\|name\|flammable\|ignition_temp\|burn_health\|fluid\|tint_color\|damage\|glow" gdextension/src/sim/material_table.h
diff <(grep -E "^const|^#define" shaders/generated/materials.glslinc) <(echo "manual cross-check")
```

Expected: `MaterialTable` carries `flammable`/`ignition_temp`/`burn_health`/`fluid`/`tint_color`/`damage`/`glow`. **Missing fields the rules need** (per cross-reference with `sim/lava.glslinc`, `sim/gas.glslinc`, `sim/burning.glslinc`):
- `kind` (`MaterialKind` enum: `SOLID`, `POWDER`, `LIQUID`, `GAS`, `FIRE`, `NONE`) — used by every rule's dispatch
- `density` (uint8) — gas advection
- `viscosity` (uint8) — lava advection
- `dispersion` (uint8) — gas diffusion
- `diffusion_rate` (uint8) — burning heat spread
- `max_temp` (uint8) — burning ceiling

Task 2 adds them. The values come from `materials.glslinc` plus the per-material constants hardcoded in each `sim/*.glslinc` (e.g. `DIFFUSION_RATE = 4` becomes a property on the burnable materials).

- [ ] **Step 6: Confirm the gdUnit4 suite is green at HEAD**

Run gdUnit4 via the editor's Test panel. All green. Document any pre-existing failure before proceeding.

- [ ] **Step 7: Confirm the simulator-relevant `Chunk` fields exist**

```bash
grep -n "cells\|cells_ptr\|dirty_rect\|next_dirty_rect\|sleeping\|collider_dirty\|neighbor_up\|neighbor_down\|neighbor_left\|neighbor_right\|texture\b" gdextension/src/terrain/chunk.h
```

Expected: every field listed (steps 4 and 6 already added them). If `next_dirty_rect` is missing, add it in task 1; the spec calls for it per §6.3.

---

## Task 1: Extend `Chunk` with sim-side concurrency primitives

The simulator needs lock-free atomic min/max on `next_dirty_rect`'s four bounds (per spec §6.4) and a per-chunk injection queue (per spec §8.6). Step 4 added `next_dirty_rect` as a plain `Rect2i`; this task swaps the four bound int32_t fields to `std::atomic<int32_t>` and adds the injection queue. Legacy GPU fields (`rd_texture`, `texture_2d_rd`, `sim_uniform_set`, `injection_buffer`) **stay for now** — task 13 deletes them after the sim is detached.

**Files:**
- Modify: `gdextension/src/terrain/chunk.h`
- Modify: `gdextension/src/terrain/chunk.cpp`

- [ ] **Step 1: Add the injection-queue type**

```cpp
// chunk.h
struct InjectionAABB {
    int16_t min_x, min_y, max_x, max_y;
    int8_t  vel_x, vel_y;
    uint8_t target_kind;   // bit 0: gas, bit 1: lava
    uint8_t _pad;
};
static_assert(sizeof(InjectionAABB) == 10);
```

The shape mirrors today's GLSL `InjectionAABB` (32 bytes) but drops the GPU padding — we don't ship it to a buffer anymore.

- [ ] **Step 2: Replace `next_dirty_rect` with atomic bounds**

```cpp
// chunk.h, replacing the existing next_dirty_rect Rect2i
private:
    std::atomic<int32_t> next_min_x;
    std::atomic<int32_t> next_min_y;
    std::atomic<int32_t> next_max_x;
    std::atomic<int32_t> next_max_y;
public:
    // Lock-free bound extension. Returns true if any bound was updated.
    bool extend_next_dirty_rect(int x0, int y0, int x1, int y1);
    Rect2i take_next_dirty_rect();   // atomic load + reset to empty
    void   reset_next_dirty_rect();
```

Initial values: `next_min_x = INT32_MAX`, `next_min_y = INT32_MAX`, `next_max_x = INT32_MIN`, `next_max_y = INT32_MIN` (empty rect sentinel).

Implementation in `chunk.cpp`:

```cpp
bool Chunk::extend_next_dirty_rect(int x0, int y0, int x1, int y1) {
    bool changed = false;
    int32_t old_v;
    old_v = next_min_x.load(std::memory_order_relaxed);
    while (x0 < old_v && !next_min_x.compare_exchange_weak(old_v, x0, std::memory_order_relaxed)) {}
    if (x0 < old_v) changed = true;
    // ...same shape for next_min_y (with y0), next_max_x (x1, swap < for >), next_max_y (y1, >)
    return changed;
}
```

`take_next_dirty_rect` snapshots all four bounds, resets to the empty sentinel, returns the snapshot as a `Rect2i` (empty if `max < min` on either axis).

- [ ] **Step 3: Add the per-chunk injection queue**

```cpp
// chunk.h
private:
    Vector<InjectionAABB> injection_queue;   // populated outside tick, consumed at tick start
    Mutex injection_queue_mutex;             // guards push/clear; not held during tick body
public:
    void push_injection(const InjectionAABB &aabb);
    Vector<InjectionAABB> take_injections();   // swap-and-clear, called at start of chunk tick
```

The mutex is fine here — `push_injection` is called from `GasInjector::build_payloads` once per frame *before* `Simulator::tick`, and `take_injections` is called once per chunk job at the *start* of its body. They never overlap with the per-cell hot loop.

- [ ] **Step 4: Remove `Cell *cells_ptr()` from the GDScript binding surface (if it was bound)**

Per step 6 task 2 step 2 it should already be C++-only. Re-confirm `_bind_methods` doesn't expose it.

- [ ] **Step 5: Build, commit**

```bash
./gdextension/build.sh debug
git add gdextension/src/terrain/chunk.{h,cpp}
git commit -m "feat: add Chunk concurrency primitives (atomic dirty rect, injection queue)"
```

---

## Task 2: Extend `MaterialTable` with simulation parameters

Per pre-flight step 5, the rules need `kind`, `density`, `viscosity`, `dispersion`, `diffusion_rate`, `max_temp`. Lift values from `shaders/generated/materials.glslinc` and the constants embedded in each `sim/*.glslinc`.

**Files:**
- Modify: `gdextension/src/sim/material_table.h`
- Modify: `gdextension/src/sim/material_table.cpp`

- [ ] **Step 1: Add `MaterialKind` enum + extend `MaterialDef`**

```cpp
// material_table.h
enum class MaterialKind : uint8_t {
    NONE, SOLID, POWDER, LIQUID, GAS, FIRE
};

struct MaterialDef {
    // ...existing fields preserved verbatim...

    MaterialKind kind         = MaterialKind::SOLID;
    uint8_t      density      = 0;     // gas/liquid advection weight
    uint8_t      viscosity    = 0;     // 0..255, lava flow resistance
    uint8_t      dispersion   = 0;     // gas spread radius / frame
    uint8_t      diffusion_rate = 0;   // burning heat spread / frame
    uint8_t      max_temp     = 255;
};
```

Keep field order stable; existing GDScript readers should not break (they read by name through `_bind_methods` getters — confirm before declaring the field reorder safe).

- [ ] **Step 2: Populate the new fields in `MaterialTable::populate`**

For each material currently registered (AIR, WOOD, STONE, GAS, LAVA, DIRT, COAL, ICE, WATER), set the new fields. Source values:
- `kind`: AIR=`NONE`, WOOD/STONE/COAL/ICE/DIRT=`SOLID`, GAS=`GAS`, LAVA/WATER=`LIQUID`. (Today's `fluid` flag remains, redundantly — keep both for now; cleanup is follow-up.)
- `density`/`dispersion` for GAS: from `sim/gas.glslinc` constants — typically `density=128`, `dispersion=4` (cross-check `DIFFUSION_RATE` and the gas-specific tuning that lives at HEAD).
- `viscosity` for LAVA: from `sim/lava.glslinc` — typical `192`.
- `diffusion_rate`/`max_temp` for flammables (WOOD, COAL): `diffusion_rate=4` (the GLSL `DIFFUSION_RATE`), `max_temp=255`.

If the GLSL pulls numbers from `materials.glslinc` (rather than hardcoded constants), copy from there. **Do not invent** values. If a value is genuinely shader-only and not currently per-material, lift it as a per-material default and code-comment "GLSL-derived; tune in follow-up gameplay work."

- [ ] **Step 3: Bind the new fields to GDScript via `_bind_methods`**

Read-only getters are sufficient: `get_density`, `get_viscosity`, `get_dispersion`, `get_diffusion_rate`, `get_max_temp`, `get_kind`. GDScript shouldn't need to set them; the table is C++-populated.

- [ ] **Step 4: Build and editor smoke**

```bash
./gdextension/build.sh debug
```

Open Godot → Output log clean. In a scratch script: `print(MaterialTable.get_density(MaterialTable.get_id("gas")))` — should print the populated value.

- [ ] **Step 5: Commit**

```bash
git add gdextension/src/sim/material_table.{h,cpp}
git commit -m "feat: extend MaterialDef with sim parameters (kind, density, viscosity, dispersion, diffusion_rate, max_temp)"
```

---

## Task 3: Add `SimContext` and `Simulator` skeleton

This is the spine of the cellular simulation. The skeleton runs the 4-phase checkerboard, dispatches `WorkerThreadPool::add_group_task` per phase, joins, and rotates `dirty_rect`/`next_dirty_rect`. Material rules are stub no-ops at this step; they land in tasks 4–7.

**Files:**
- Create: `gdextension/src/sim/sim_context.h`
- Create: `gdextension/src/sim/sim_context.cpp`
- Create: `gdextension/src/sim/simulator.h`
- Create: `gdextension/src/sim/simulator.cpp`

- [ ] **Step 1: Write `sim_context.h`**

```cpp
#pragma once

#include "../terrain/chunk.h"
#include <godot_cpp/variant/vector2i.hpp>
#include <cstdint>

namespace toprogue {

class SimContext {
public:
    Chunk *chunk;          // current chunk
    Chunk *up;             // neighbor; nullable
    Chunk *down;
    Chunk *left;
    Chunk *right;
    uint32_t frame_seed;
    int      frame_index;

    // Cached material ids resolved once per tick.
    int air_id, gas_id, lava_id, water_id;

    // Stochastic helpers — same shape as GLSL stochastic_div.
    uint32_t hash3(int x, int y, uint32_t salt) const;
    bool     stochastic_div(int x, int y, uint32_t salt, int divisor) const;

    // Cell read/write through chunk routing. (x, y) are chunk-local; out-of-range
    // values dispatch to the neighbor and accumulate dirty-rect on the target.
    Cell *  cell_at(int x, int y);            // null if out of world (no neighbor)
    void    write_cell(int x, int y, const Cell &c);
    void    swap_cell(int x_a, int y_a, int x_b, int y_b);
    bool    is_solid(int x, int y) const;

    // Wake helper; called on cross-chunk writes.
    void    wake(Chunk *target, int x, int y);
};

} // namespace toprogue
```

- [ ] **Step 2: Write `sim_context.cpp`**

Implement the helpers. `cell_at` resolves the target chunk via `chunk` + `up/down/left/right`, computes the local index, returns a pointer. `write_cell` calls `target->extend_next_dirty_rect(...)` and clears `target->sleeping`. `hash3` uses `hash(pos.x ^ hash(pos.y ^ frame_seed ^ salt))` per spec §6.6 — straight transliteration of `common.glslinc::hash` and `stochastic_div`.

**Cross-chunk safety.** Reads through `cell_at` are always safe (the 4-phase scheduler guarantees no parallel chunk reads its neighbors mid-write). Writes through `write_cell` are safe per §6.4: within a phase, only one writing thread can target any neighbor, since neighbors are by construction in a different phase and sleeping (the writer is the only awake party touching them this phase).

- [ ] **Step 3: Write `simulator.h`**

```cpp
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include "../terrain/chunk.h"

namespace toprogue {

class Simulator : public godot::RefCounted {
    GDCLASS(Simulator, godot::RefCounted);

    int64_t  _world_seed = 0;
    int      _frame_index = 0;
    godot::Dictionary _chunks;   // Vector2i -> Ref<Chunk>; non-owning view, ChunkManager owns lifetimes

public:
    void set_world_seed(int64_t seed);
    void set_chunks(const godot::Dictionary &chunks);
    void tick();   // single per-frame entry point

protected:
    static void _bind_methods();

private:
    void run_phase(int phase_x, int phase_y);
    void tick_chunk(Chunk *chunk);
    void rotate_dirty_rects();
    void upload_dirty_textures();   // main thread, after all phases joined
};

} // namespace toprogue
```

- [ ] **Step 4: Write `simulator.cpp` skeleton (no rules yet)**

```cpp
void Simulator::tick() {
    using namespace godot;
    _frame_index++;
    uint32_t frame_seed = uint32_t(_world_seed) ^ uint32_t(_frame_index * 0x9E3779B1u);
    (void)frame_seed;  // used by tick_chunk in tasks 4–7

    // Build the active set: all non-sleeping chunks.
    Array keys = _chunks.keys();
    Vector<Chunk *> active;
    active.reserve(keys.size());
    for (int i = 0; i < keys.size(); i++) {
        Ref<Chunk> c = _chunks[keys[i]];
        if (c.is_valid() && !c->is_sleeping()) {
            active.push_back(c.ptr());
        }
    }

    // 4-phase chunk-checkerboard.
    for (int phase = 0; phase < 4; phase++) {
        int px = phase & 1, py = (phase >> 1) & 1;
        run_phase(px, py);   // joins before returning
    }

    rotate_dirty_rects();
    upload_dirty_textures();
}
```

`run_phase` filters `active` by `(coord.x & 1, coord.y & 1) == (phase_x, phase_y)`, calls `WorkerThreadPool::get_singleton()->add_group_task(callable, count, -1, true)` with `wait_for_completion = true`, callable = lambda capturing the filtered list and dispatching to `tick_chunk`.

`tick_chunk` is empty for now (rules in tasks 4–7).

`rotate_dirty_rects` walks all active chunks: `dirty_rect = chunk->take_next_dirty_rect()`. If empty → `chunk->set_sleeping(true)`.

`upload_dirty_textures` iterates active chunks on the main thread, calls `chunk->upload_texture()` (Task 8 implements this).

- [ ] **Step 5: Build, commit**

```bash
./gdextension/build.sh debug
git add gdextension/src/sim/sim_context.{h,cpp} gdextension/src/sim/simulator.{h,cpp}
git commit -m "feat: add Simulator skeleton + SimContext (4-phase checkerboard, no rules yet)"
```

---

## Task 4: Port the `injection` rule

Consumes per-chunk injection queues (populated by `GasInjector` once per frame before `Simulator::tick`). Applies AABB-based velocity to gas/lava cells. Mirrors `shaders/include/sim/injection.glslinc`.

**Files:**
- Create: `gdextension/src/sim/rules/injection.h` (forward declarations only)
- Create: `gdextension/src/sim/rules/injection.cpp`
- Modify: `gdextension/src/physics/gas_injector.{h,cpp}` — change output target

- [ ] **Step 1: Switch `GasInjector` from byte-payload to per-chunk queue**

Today `GasInjector::build_payload(scene, coord)` returns a `PackedByteArray` matching the GLSL struct. Replace with:

```cpp
// Pushes InjectionAABBs onto each chunk's injection queue.
// Called once per frame from WorldManager::_process before Simulator::tick.
static void build_payloads(SceneTree *scene, const Dictionary &chunks);
```

The body walks `gas_interactors` group nodes (same scene-tree traversal as today), computes world AABB + velocity, but for each chunk the AABB intersects, pushes an `InjectionAABB` onto `chunk->push_injection(aabb)` instead of writing to a `PackedByteArray`. The AABB coordinates are now chunk-local (clipped per chunk).

The `target_kind` field is set per the existing GLSL distinction (gas-interactor only injects on gas; if a future interactor type targets lava, set bit 1). At HEAD only gas is targeted — keep that.

Old `build_payload(scene, coord)` deleted; old `PackedByteArray` shape gone.

- [ ] **Step 2: Write `injection.cpp`**

```cpp
#include "../sim_context.h"
#include "../material_table.h"
#include "../../terrain/chunk.h"

namespace toprogue {

void run_injection(SimContext &ctx) {
    Vector<InjectionAABB> queue = ctx.chunk->take_injections();
    if (queue.is_empty()) return;

    for (const InjectionAABB &aabb : queue) {
        for (int y = aabb.min_y; y <= aabb.max_y; y++) {
            for (int x = aabb.min_x; x <= aabb.max_x; x++) {
                Cell *c = ctx.cell_at(x, y);
                if (!c) continue;
                MaterialKind k = MaterialTable::get_singleton()->get_kind(c->material);
                bool target_gas  = (aabb.target_kind & 1) && k == MaterialKind::GAS;
                bool target_lava = (aabb.target_kind & 2) && k == MaterialKind::LIQUID && c->material == ctx.lava_id;
                if (!target_gas && !target_lava) continue;

                // Encode velocity into flags (same packing as today's terrain_modifier.gd::place_gas).
                int8_t vx = aabb.vel_x, vy = aabb.vel_y;
                c->flags = pack_velocity(vx, vy);   // helper from sim_context.h
                ctx.chunk->extend_next_dirty_rect(x, y, x + 1, y + 1);
            }
        }
    }
}

} // namespace toprogue
```

`pack_velocity` matches the GLSL `flags` byte layout:
- bits 0..3: signed vx (-8..7)
- bits 4..7: signed vy (-8..7)

Cross-reference `terrain_modifier.gd::place_gas` (lines ~14–54) and `sim/injection.glslinc` to confirm the exact packing.

- [ ] **Step 3: Wire into `Simulator::tick_chunk`**

```cpp
void Simulator::tick_chunk(Chunk *chunk) {
    SimContext ctx{ /* fill in */ };
    run_injection(ctx);
    // run_lava, run_gas, run_burning land in tasks 5–7.
    rotate_dirty_for_chunk(ctx);
}
```

Note: injection runs **before** the per-cell rule pass, but it's still inside the per-chunk job (in the current chunk's phase). That means injections only land on cells the chunk owns + neighbor cells the AABB clips into. This matches today's GLSL where injection runs in the same dispatch as the rules.

- [ ] **Step 4: Update `WorldManager` GDScript caller temporarily**

Until `WorldManager` is C++ (task 11), the GDScript `_run_simulation` needs to call `GasInjector.build_payloads(get_tree(), chunks)` once per frame before whatever simulation entry point exists. This is a transient state; task 11 collapses it into C++. For this task, keep the GPU sim alive and just plumb the new payload path so the queue is populated. The GPU sim's `chunk.injection_buffer` continues to exist via the legacy code; the new queue is dormant until task 11 wires `Simulator::tick`.

Pragmatic shortcut: skip step 4 entirely. The new `build_payloads` is dead code until `Simulator::tick` is the per-frame driver. Leaving the legacy `build_payload(scene, coord)` *and* the new `build_payloads(scene, chunks)` alive in parallel for one task is acceptable; task 11 deletes the legacy version.

- [ ] **Step 5: Build, commit**

```bash
./gdextension/build.sh debug
git add gdextension/src/sim/rules/injection.{h,cpp} gdextension/src/physics/gas_injector.{h,cpp}
git commit -m "feat: port injection rule to C++ + add per-chunk injection queue"
```

---

## Task 5: Port the `lava` rule

Mirrors `shaders/include/sim/lava.glslinc` (163 LOC). Advection + buoyancy + temperature blending + inflow/outflow. The GLSL operates on `vec4` cells; the C++ port uses `Cell` directly.

**Files:**
- Create: `gdextension/src/sim/rules/lava.cpp`

- [ ] **Step 1: Translate the GLSL line-by-line**

`lava_advect_pull` becomes `void run_lava(SimContext &ctx)`. Iterate `chunk->dirty_rect`. For each cell where `material == lava_id`, dispatch to:
- `lava_advect`: read upstream cell along velocity, swap if it's empty/gas
- `lava_buoyancy`: heat rises; if cell below is non-lava and current temp > threshold, swap with cell above
- `lava_cool`: temperature decays each frame by a constant (lift from GLSL)
- `lava_ignite_neighbor`: if neighbor is flammable and lava temp ≥ neighbor's `ignition_temp`, mark neighbor's `flags |= IGNITED`

Use `ctx.cell_at(x, y)` for cross-chunk reads/writes. Use `ctx.swap_cell(...)` to move lava across the boundary.

**Constants.** Lift `LAVA_VISCOSITY`, `LAVA_COOL_RATE`, `LAVA_BUOYANCY_TEMP` from the GLSL. If they're per-material, read from `MaterialTable`'s new `viscosity`/`max_temp` fields. If they're global, define as `static constexpr` in `lava.cpp`.

**Stochastic decisions.** Replace every GLSL `stochastic_div(...)` with `ctx.stochastic_div(x, y, salt, divisor)`. Salt values must match the GLSL salts byte-for-byte (read each call site in the GLSL and copy the literal salt).

- [ ] **Step 2: Wire into `Simulator::tick_chunk`**

```cpp
run_injection(ctx);
run_lava(ctx);
```

- [ ] **Step 3: Build**

```bash
./gdextension/build.sh debug
```

The simulator still doesn't drive frame-to-frame state until task 11; we can't run-test the rule yet. Compile-clean is the bar at this task.

- [ ] **Step 4: Commit**

```bash
git add gdextension/src/sim/rules/lava.cpp gdextension/src/sim/simulator.cpp
git commit -m "feat: port lava rule to C++"
```

---

## Task 6: Port the `gas` rule

Mirrors `shaders/include/sim/gas.glslinc` (188 LOC). Advection, density, velocity mixing, diffusion (`DIFFUSION_RATE = 4`).

**Files:**
- Create: `gdextension/src/sim/rules/gas.cpp`

- [ ] **Step 1: Translate the GLSL line-by-line**

`gas_advect_pull` becomes `run_gas(ctx)`. Per-cell: read encoded velocity from `flags`, advect (swap with destination if empty/lighter), apply diffusion (the `DIFFUSION_RATE = 4` mix with neighbors), update density (`health` field) by mixing with neighbors weighted by their density, decay velocity over time.

Salts and stochastic_div calls match the GLSL byte-for-byte (per task 5 step 1 rule).

`DIFFUSION_RATE = 4` becomes a `static constexpr int DIFFUSION_RATE = 4;` in `gas.cpp`.

- [ ] **Step 2: Wire into `Simulator::tick_chunk` after lava**

```cpp
run_injection(ctx);
run_lava(ctx);
run_gas(ctx);
```

- [ ] **Step 3: Build, commit**

```bash
./gdextension/build.sh debug
git add gdextension/src/sim/rules/gas.cpp gdextension/src/sim/simulator.cpp
git commit -m "feat: port gas rule to C++"
```

---

## Task 7: Port the `burning` rule

Mirrors `shaders/include/sim/burning.glslinc` (77 LOC). Heat spread, ignition, combustion.

**Files:**
- Create: `gdextension/src/sim/rules/burning.cpp`

- [ ] **Step 1: Translate the GLSL line-by-line**

`run_burning(ctx)` iterates dirty cells. For each flammable cell:
- Spread heat from burning neighbors at `diffusion_rate` per frame, capped at `max_temp`
- If `temperature >= ignition_temp`, set `flags |= IGNITED`
- If ignited, drain `health` at `burn_rate` per frame; when `health == 0`, replace with `air_id` and emit a gas/fire effect (per the GLSL's combustion-product logic)

**In-cell checkerboard.** Today's GLSL has `(pos.x + pos.y) % 2 != phase` to avoid race conditions inside the GPU's 2-phase even/odd dispatch. **Drop this** in the C++ port — the chunk-level 4-phase scheduler already provides parallelism. Behavior change is benign per §3.4 Q3 (slightly different burn-front shape, no functional regression).

- [ ] **Step 2: Wire into `Simulator::tick_chunk` after gas**

```cpp
run_injection(ctx);
run_lava(ctx);
run_gas(ctx);
run_burning(ctx);
```

- [ ] **Step 3: Build, commit**

```bash
./gdextension/build.sh debug
git add gdextension/src/sim/rules/burning.cpp gdextension/src/sim/simulator.cpp
git commit -m "feat: port burning rule to C++"
```

---

## Task 8: Implement `Chunk::upload_texture()` (rendering bridge)

Per spec §8.4. After all sim phases join, dirty chunks upload their `cells[]` (or just the dirty rect) to a `Ref<ImageTexture>` consumed by the existing chunk-render shader. Step 4 already added the `Ref<ImageTexture> texture` field; this task gives it a body.

**Files:**
- Modify: `gdextension/src/terrain/chunk.{h,cpp}`

- [ ] **Step 1: Add `upload_texture` method**

```cpp
// chunk.h
void upload_texture();   // main thread only
void upload_texture_full();   // initial creation
```

- [ ] **Step 2: Implement**

```cpp
void Chunk::upload_texture_full() {
    PackedByteArray bytes;
    bytes.resize(CHUNK_SIZE * CHUNK_SIZE * 4);
    memcpy(bytes.ptrw(), cells, CHUNK_SIZE * CHUNK_SIZE * 4);
    Ref<Image> img = Image::create_from_data(CHUNK_SIZE, CHUNK_SIZE, false, Image::FORMAT_RGBA8, bytes);
    if (texture.is_null()) {
        texture = ImageTexture::create_from_image(img);
    } else {
        texture->update(img);
    }
}

void Chunk::upload_texture() {
    if (dirty_rect.size.x == 0 || dirty_rect.size.y == 0) return;
    // Dirty-only upload via Image::blit_rect — TBD if godot-cpp ImageTexture supports
    // partial update without a full image rebuild. If not, full re-upload is fine for now;
    // optimize as follow-up per §10.1 risk #4.
    upload_texture_full();
}
```

godot-cpp's `ImageTexture::update` requires a same-size image, so partial-rect uploads need an `Image::create_from_data` over the dirty rect + `ImageTexture::update_partial` if available. If godot-cpp doesn't expose `update_partial`, accept the full re-upload at this step — document the perf TODO inline.

- [ ] **Step 3: Wire into `Simulator::upload_dirty_textures`**

```cpp
void Simulator::upload_dirty_textures() {
    for (Chunk *c : last_active_set) {
        if (c->dirty_rect.size.x > 0) c->upload_texture();
    }
}
```

- [ ] **Step 4: Build, commit**

```bash
./gdextension/build.sh debug
git add gdextension/src/terrain/chunk.{h,cpp} gdextension/src/sim/simulator.cpp
git commit -m "feat: implement Chunk::upload_texture (CPU cells -> ImageTexture)"
```

---

## Task 9: Port `TerrainModifier` to C++ (CPU writes)

Replaces `src/core/terrain_modifier.gd` (~356 LOC). Every method becomes a direct `cells[]` write that flags `dirty_rect`/`collider_dirty` and clears `sleeping`. No `RenderingDevice` calls.

**Files:**
- Create: `gdextension/src/terrain/terrain_modifier.h`
- Create: `gdextension/src/terrain/terrain_modifier.cpp`

Public surface preserved exactly — every method name, parameter name, parameter order, return type matches the GDScript original. Confirm by greppping callers.

- [ ] **Step 1: Header**

```cpp
class TerrainModifier : public RefCounted {
    GDCLASS(TerrainModifier, RefCounted);

    Dictionary _chunks;        // Vector2i -> Ref<Chunk>; non-owning view
    TerrainPhysical *_terrain_physical = nullptr;

public:
    void set_chunks(const Dictionary &chunks);
    void set_terrain_physical(TerrainPhysical *tp);

    void place_gas(Vector2 world_pos, int radius, int density, Vector2 velocity);
    void place_lava(Vector2 world_pos, int radius);
    void place_fire(Vector2 world_pos, int radius);
    void place_material(Vector2 world_pos, int radius, int material_id);
    void disperse_materials_in_arc(Vector2 origin, Vector2 direction, float arc_rad, float radius, float force);
    void clear_and_push_materials_in_arc(Vector2 origin, Vector2 direction, float arc_rad, float radius, float force);

protected:
    static void _bind_methods();

private:
    void mark_dirty(Chunk *c, int x_min, int y_min, int x_max, int y_max);
};
```

Parameter types match the GDScript exactly (e.g. `radius` is `int`, not `float`, if the GDScript uses `int`).

- [ ] **Step 2: Translate each method**

Each method: walk world coords → resolve chunk + local coords → mutate `chunk->cells[i]` directly → `mark_dirty(chunk, ...)`. `mark_dirty` calls `chunk->extend_next_dirty_rect(...)`, sets `collider_dirty = true` if the material change crosses the solid/non-solid boundary, and sets `sleeping = false`.

For `place_gas`: the velocity is packed into `flags` using the same bit layout as today's GDScript (low nibble = vx, high nibble = vy, signed). Cross-reference task 4 step 2's `pack_velocity`.

For `disperse_materials_in_arc` and `clear_and_push_materials_in_arc`: the angular-push physics from `terrain_modifier.gd` lines 174–357 ports as direct `for` loops; no algorithmic change, just GDScript-to-C++ syntax.

`_terrain_physical->invalidate_rect(...)` calls preserved — same signal flow as before.

- [ ] **Step 3: Migrate callsites**

Every caller of `TerrainSurface.place_*` continues to work — `TerrainSurface` is the adapter (in `src/utils/terrain_surface.gd` per the test inventory). It calls `world_manager.place_gas(...)`; `WorldManager` (still GDScript at this task) delegates to `_terrain_modifier.place_gas(...)`. After this task lands the delegate target is C++ instead of GDScript, but the signature is identical.

- [ ] **Step 4: Register**

In `gdextension/src/register_types.cpp`:

```cpp
GDREGISTER_CLASS(TerrainModifier);
```

- [ ] **Step 5: Replace the GDScript**

Delete `src/core/terrain_modifier.gd` (+ `.uid`). Re-grep:

```bash
grep -rn "res://src/core/terrain_modifier.gd\|class_name TerrainModifier" .
```

Expected: zero hits. The native registration provides the class name.

- [ ] **Step 6: Build, run editor smoke**

GPU sim still drives the per-frame loop at this task. F5 → fire a weapon that calls `place_lava` → confirm the lava lands and the GPU sim picks it up (the `cells[]` and `rd_texture` are now out of sync — the C++ `TerrainModifier` writes only to `cells[]`, but `compute_device.dispatch_simulation` reads from `rd_texture`). **This is expected and broken at this task** — the chunk's `cells[]` is the new source of truth, but the legacy GPU sim still reads the old texture. Task 11 fixes the loop by detaching from GPU sim entirely; for now, write to *both* `cells[]` and the texture (`rd->texture_update`) so the legacy sim keeps working as a bridge.

Add a transitional `_upload_to_rd_texture(chunk)` helper inside `TerrainModifier` that mirrors any cell mutation to `chunk->rd_texture` via `rd->texture_update`. **This is a one-task hack** — task 13 deletes `_upload_to_rd_texture` along with `rd_texture`.

- [ ] **Step 7: Commit**

```bash
git add gdextension/src/terrain/terrain_modifier.{h,cpp} gdextension/src/register_types.cpp src/core/terrain_modifier.gd
git commit -m "feat: port TerrainModifier to C++ (CPU cells writes + transitional GPU mirror)"
```

---

## Task 10: Port `ChunkManager` to C++

Replaces `src/core/chunk_manager.gd` (~249 LOC). The streaming loop, `Chunk` lifecycle, and neighbor wiring move to C++. The GPU uniform-set construction (lines 134–193 of the GDScript) goes away — the simulator doesn't need uniform sets. The `material_textures` binding for the chunk-render shader stays.

**Files:**
- Create: `gdextension/src/terrain/chunk_manager.h`
- Create: `gdextension/src/terrain/chunk_manager.cpp`

- [ ] **Step 1: Header**

Public surface mirrors the GDScript exactly:

```cpp
class ChunkManager : public RefCounted {
    GDCLASS(ChunkManager, RefCounted);

    Dictionary _chunks;   // Vector2i -> Ref<Chunk>
    Ref<SectorGrid> _sector_grid;
    Ref<Generator> _generator;
    Ref<SimplexCaveGenerator> _simplex_cave_generator;
    Ref<ColliderBuilder> _collider_builder;
    Node *_world_root = nullptr;   // parent for chunk MeshInstance2D nodes
    // ... whatever fields the GDScript has

public:
    TypedArray<Vector2i> get_desired_chunks(Vector2 viewport_center, Vector2 viewport_size) const;
    Ref<Chunk> create_chunk(Vector2i coord);
    void unload_chunk(Vector2i coord);
    void update_render_neighbors();
    void clear_all_chunks();
    void generate_chunks_at(const TypedArray<Vector2i> &coords, int64_t seed_val);
    Dictionary get_chunks() const;
    // ...

protected:
    static void _bind_methods();

private:
    void wire_neighbors(Chunk *chunk);
};
```

- [ ] **Step 2: Translate the body**

Each method ports the GDScript line-by-line. Notable differences:
- `rebuild_sim_uniform_sets` and `build_sim_uniform_set` (lines 134–193) **delete** entirely — no uniform sets in the C++ sim.
- `create_chunk` no longer creates `chunk.rd_texture` / `chunk.texture_2d_rd`. The render shader binds `chunk->texture` (the new `ImageTexture` from task 8) instead. Pass `chunk->texture` to the chunk's `MeshInstance2D` material via `set_shader_parameter("chunk_tex", chunk->texture)`.
- `update_render_neighbors` now wires `chunk->neighbor_*` Ref<Chunk> pointers (already in `Chunk` per step 4) instead of GPU uniform-set neighbor textures.
- `material_textures` for the chunk-render shader: build it once at `ChunkManager` construction from `MaterialTable`, set on each chunk's `MeshInstance2D` shader material. The `Texture2DArray` itself can be built on the CPU (no `RenderingDevice` involvement — `Texture2DArray.create_from_images` is a public method).

- [ ] **Step 3: Register**

```cpp
GDREGISTER_CLASS(ChunkManager);
```

- [ ] **Step 4: Replace the GDScript**

Delete `src/core/chunk_manager.gd` (+ `.uid`). Migrate any `.tscn` that script-binds it (per pre-flight step 4).

- [ ] **Step 5: Build, run editor smoke**

The GPU sim is still the per-frame driver until task 11. The `chunk.rd_texture` field is gone (we just removed it via the new `create_chunk`), so `compute_device.dispatch_simulation` will fail. **Expected** — task 11 swaps the per-frame driver to `Simulator::tick`. Until then, comment out the `_run_simulation` call in `world_manager.gd::_process` so the project loads. Restore in task 11.

This is a transient-broken state across one task. If the discomfort is high, fold task 10 + task 11 into a single commit.

- [ ] **Step 6: Commit**

```bash
git add gdextension/src/terrain/chunk_manager.{h,cpp} gdextension/src/register_types.cpp src/core/chunk_manager.gd src/core/world_manager.gd
git commit -m "feat: port ChunkManager to C++ (drop GPU uniform sets; render via Chunk::texture)"
```

---

## Task 11: Port `WorldManager` to C++

Replaces `src/core/world_manager.gd` (~262 LOC). The per-frame driver. Public surface preserved exactly.

**Files:**
- Create: `gdextension/src/terrain/world_manager.h`
- Create: `gdextension/src/terrain/world_manager.cpp`

- [ ] **Step 1: Header**

```cpp
class WorldManager : public Node2D {
    GDCLASS(WorldManager, Node2D);

    Ref<ChunkManager>     _chunk_manager;
    Ref<Simulator>        _simulator;
    Ref<Generator>        _generator;
    Ref<SimplexCaveGenerator> _simplex_cave_generator;
    Ref<ColliderBuilder>  _collider_builder;
    Ref<TerrainModifier>  _terrain_modifier;
    TerrainPhysical      *_terrain_physical = nullptr;

public:
    // Lifecycle
    void _ready() override;
    void _process(double delta) override;

    // Public API preserved from GDScript
    void place_gas(Vector2 world_pos, int radius, int density, Vector2 velocity);
    void place_lava(Vector2 world_pos, int radius);
    void place_material(Vector2 world_pos, int radius, int material_id);
    void place_fire(Vector2 world_pos, int radius);
    void disperse_materials_in_arc(...);
    void clear_and_push_materials_in_arc(...);
    void reset();
    // ...all other public methods from world_manager.gd

protected:
    static void _bind_methods();

private:
    void _update_chunks();
    void _run_simulation();
};
```

Signals (`chunks_generated`, etc.) declared via `ADD_SIGNAL` in `_bind_methods` with the same names + signatures.

- [ ] **Step 2: Body**

`_ready`: instantiate `_chunk_manager`, `_simulator`, `_generator`, `_simplex_cave_generator`, `_collider_builder`, `_terrain_modifier`. Wire references (`_simulator->set_chunks(_chunk_manager->get_chunks())`, etc.). No `compute_device`, no `init_shaders`, no `init_dummy_texture`, no `init_material_textures` (the last folds into `ChunkManager`).

`_process(delta)`:
1. `_update_chunks()` — same logic as the GDScript: compute desired set, unload stale, create new, dispatch generator.
2. `GasInjector::build_payloads(get_tree(), _chunk_manager->get_chunks())` — populates per-chunk injection queues.
3. `_simulator->tick()` — runs the 4-phase sim.
4. `_collider_builder->rebuild_dirty(_chunk_manager->get_chunks())` — walks chunks with `collider_dirty`, rebuilds shapes, clears the flag.

The order matters: injections must land before the simulator reads the queues; the simulator must run before the collider rebuilds (so collider sees the post-tick state).

`place_gas`/`place_lava`/...: thin delegations to `_terrain_modifier->place_*`.

`reset`: clear chunks, reset frame index. Same shape as the GDScript.

- [ ] **Step 3: Register, migrate scene**

```cpp
GDREGISTER_CLASS(WorldManager);
```

Delete `src/core/world_manager.gd` (+ `.uid`). Migrate any `.tscn` that script-binds it (pre-flight step 4 list).

- [ ] **Step 4: Build, full smoke run**

```bash
./gdextension/build.sh debug
```

Open Godot 4.6 → F5 → walk for ~2 minutes touching gas/lava/fire/digging/combat. **Expected behavior:**
- Level generates (per step 6).
- Sim runs entirely on CPU.
- Lava flows. Gas drifts. Fire spreads.
- Digging works (TerrainModifier writes → cells[] → next tick picks up).
- Collider rebuilds when terrain changes.

**Common failures and fixes:**
- *Black/empty chunks visible.* `Chunk::texture` not populated. Trace: does `Generator` call `chunk->upload_texture_full()` after generation? If task 8 didn't wire that, do it now in `Generator::generate_chunks` (replace the step-6 `rd->texture_update` line).
- *Sim doesn't run.* `Simulator::tick`'s active set is empty. Print `_chunks.size()` and `chunk->is_sleeping()` per chunk. After generation, `chunk->sleeping = false` per spec §8.1; if sleeping is true, generation didn't wake it.
- *Crash inside `tick_chunk`.* Most likely a null neighbor pointer dereferenced through a non-`cell_at` path. Audit the rule files for direct `chunk->cells[i]` writes that should go through `ctx`.
- *Visible flicker / wrong material at chunk edges.* Cross-chunk write race despite the 4-phase guarantee. Print frame index on each `extend_next_dirty_rect` call from the rules; confirm the writing chunk is in the expected phase.
- *Frame stutter at ~16ms boundary.* Expected if active set is large; per §10.1 risk #1 the mitigation is dirty-rect/sleep working correctly. Confirm `sleeping` actually triggers on settled chunks (most chunks should be sleeping after a few seconds of no activity).

- [ ] **Step 5: gdUnit4**

Run the suite. All green. Tests that poked at private GDScript fields on `WorldManager`/`ChunkManager`/`TerrainModifier` adapt to the public C++ surface (per §9.5).

- [ ] **Step 6: Commit**

```bash
git add gdextension/src/terrain/world_manager.{h,cpp} gdextension/src/register_types.cpp src/core/world_manager.gd
git commit -m "feat: port WorldManager to C++ (CPU simulator drives per-frame loop)"
```

---

## Task 12: Migrate `.tscn` files and any straggler GDScript references

Per pre-flight step 4 inventory.

- [ ] **Step 1: Run the migration grep**

```bash
grep -rn 'path="res://src/core/world_manager.gd\|path="res://src/core/chunk_manager.gd\|path="res://src/core/terrain_modifier.gd' --include="*.tscn" .
```

For each hit, edit the `.tscn`: convert from script-backed (`[ext_resource type="Script" path="..." id="X"]` + `script = ExtResource("X")`) to native-class (`type="WorldManager"`, no script attribute). The migration is the same one `tools/migrate_tres.py` does for resources; for scenes the rewrite is structurally identical.

If the count is small (1–3 files), edit by hand. If larger, extend `tools/migrate_tres.py` with a `--scenes` mode.

- [ ] **Step 2: Re-grep for any remaining `.gd` references**

```bash
grep -rn "res://src/core/world_manager.gd\|res://src/core/chunk_manager.gd\|res://src/core/terrain_modifier.gd" .
grep -rn "class_name WorldManager\|class_name ChunkManager\|class_name TerrainModifier" .
```

Expected: zero hits.

- [ ] **Step 3: Open each migrated scene in the editor → Save**

Confirms Godot accepts the native-class shape. Watch the Output log for "could not load scene" errors.

- [ ] **Step 4: Commit**

```bash
git add . -A
git commit -m "refactor: migrate scenes from script-backed to native WorldManager/ChunkManager/TerrainModifier"
```

---

## Task 13: Delete `simulation.glsl`, `sim/`, `shaders/generated/`, `compute_device.gd`, `world_preview.gd`, `comp.spv`, transitional hacks

The big deletion. After this task lands, every spec-listed deletion is done and the migration is complete except for cleanup.

**Files deleted:**
- `shaders/compute/simulation.glsl` + `.glsl.import`
- `shaders/include/sim/burning.glslinc`, `common.glslinc`, `gas.glslinc`, `injection.glslinc`, `lava.glslinc`
- `shaders/compute/` (empty directory) — `rmdir`
- `shaders/include/sim/` (empty directory) — `rmdir`
- `shaders/include/` (empty directory if empty after step 6 + the `sim/` deletion above) — `rmdir`
- `shaders/generated/` (entire directory: `materials.glslinc`, `materials.gdshaderinc`, anything else)
- `generate_materials.sh`
- `comp.spv` (project root)
- `src/core/compute_device.gd` + `.uid`
- `src/terrain/world_preview.gd` + `.uid`

**Files modified:**
- `gdextension/src/terrain/chunk.{h,cpp}` — remove `rd_texture`, `texture_2d_rd`, `sim_uniform_set`, `injection_buffer` fields and their bindings/getters/setters. The `Ref<ImageTexture> texture` survives.
- `gdextension/src/terrain/terrain_modifier.cpp` — remove the transitional `_upload_to_rd_texture` helper + every callsite. The C++ `cells[]` write is now the only write.
- `gdextension/src/terrain/chunk_manager.cpp` — remove any dummy_texture/material-textures Texture2DArray RD-backed code (use plain `Texture2DArray::create_from_images` instead, no `RenderingDevice`).
- `project.godot` — remove any preview-mode autoload entry (per spec §3.1, the `world_preview` feature is dead).
- `src/console/cheat_command_system.gd` (or wherever) — remove any `world_preview` console command. Re-grep:

  ```bash
  grep -rn "world_preview\|WorldPreview" --exclude-dir=docs .
  ```

- [ ] **Step 1: Pre-delete grep — capture every reference to anything we're about to delete**

```bash
grep -rn "compute_device\|res://shaders/compute/simulation\|res://shaders/include/sim\|res://shaders/generated\|world_preview\|WorldPreview\|comp\.spv\|generate_materials" \
    src/ tests/ tools/ project.godot \
    > /tmp/step7-deletions-before.txt
cat /tmp/step7-deletions-before.txt
```

Every line in the output is a callsite that must either be deleted or migrated before the delete commit lands.

- [ ] **Step 2: Excise transitional hacks from `TerrainModifier`**

Remove `_upload_to_rd_texture` and every callsite (per task 9 step 6). Re-grep:

```bash
grep -n "_upload_to_rd_texture\|rd_texture\|texture_update\|texture_get_data" gdextension/src/terrain/terrain_modifier.cpp
```

Expected: zero hits.

- [ ] **Step 3: Remove legacy GPU fields from `Chunk`**

Edit `gdextension/src/terrain/chunk.h`:
- Delete `rd_texture` (RID), `texture_2d_rd` (Ref<Texture2DRD>), `sim_uniform_set` (RID), `injection_buffer` (RID).
- Delete the corresponding bindings in `_bind_methods`.
- Delete the destructor logic that frees `rd_texture` / `injection_buffer` via `RenderingDevice`.

Build:

```bash
./gdextension/build.sh debug
```

Expected: clean. Any remaining reference to `rd_texture` from inside the C++ module is a missed migration — fix and rebuild.

- [ ] **Step 4: Excise `material_textures` Texture2DArray RD path from `ChunkManager`**

If `ChunkManager::_init_material_textures` (or wherever the `Texture2DArray` is built) uses `RenderingDevice` to construct the array, swap to `Texture2DArray::create_from_images`. Re-grep:

```bash
grep -n "RenderingDevice\|RDShaderFile\|RDUniform\|compute_list\|push_constant" gdextension/src/
```

Expected: zero hits.

- [ ] **Step 5: Delete the GDScript files**

```bash
rm src/core/compute_device.gd src/core/compute_device.gd.uid
rm src/terrain/world_preview.gd src/terrain/world_preview.gd.uid
```

If the `.uid` files have different suffixes, find them first:

```bash
find src/core/ src/terrain/ -name "compute_device*" -o -name "world_preview*"
```

- [ ] **Step 6: Delete the shaders + generated outputs**

```bash
rm shaders/compute/simulation.glsl shaders/compute/simulation.glsl.import
rm shaders/include/sim/burning.glslinc
rm shaders/include/sim/common.glslinc
rm shaders/include/sim/gas.glslinc
rm shaders/include/sim/injection.glslinc
rm shaders/include/sim/lava.glslinc
rmdir shaders/include/sim
rmdir shaders/include
rmdir shaders/compute
rm -rf shaders/generated
rm generate_materials.sh
rm comp.spv
```

If any `rmdir` fails because the directory isn't empty, list contents and resolve before continuing.

- [ ] **Step 7: Remove preview-mode autoload + console command**

Edit `project.godot`: remove any autoload entry whose path resolves to `world_preview.gd` (already deleted). Remove `world_preview` references from `src/console/cheat_command_system.gd` or wherever the preview command lives.

```bash
grep -rn "world_preview\|WorldPreview" --exclude-dir=docs --exclude-dir=.git .
```

Expected: zero hits.

- [ ] **Step 8: Final build + editor smoke**

```bash
./gdextension/build.sh debug
```

Open Godot 4.6 → Output log clean (no "Failed to load resource: res://shaders/..." errors, no "could not parse compute_device.gd" errors, no missing-script errors on any scene). F5 → walk for ~2 minutes → exercise lava/gas/fire/digging/combat → exit cleanly.

- [ ] **Step 9: Commit**

```bash
git add . -A
git commit -m "refactor: delete simulation shader, sim includes, generated/, ComputeDevice, world_preview, comp.spv"
```

---

## Task 14: Final verification

- [ ] **Step 1: Spec-defined end-of-refactor greps**

```bash
find shaders/compute -type f 2>&1
find shaders/include -type f 2>&1
find shaders/generated -type f 2>&1
ls shaders/ 2>&1
```

Expected: every `find` returns "No such file or directory" or empty. `ls shaders/` shows only the non-compute chunk-render shader (or whatever non-compute shader the project keeps for visuals — confirm it's the one §3.3 calls out as "untouched").

```bash
grep -rn "RenderingDevice\|RDShaderFile\|RDShaderSPIRV\|compute_list\|push_constant" src/ gdextension/src/
```

Expected: zero hits.

```bash
grep -rn "compute_device\|MaterialRegistry\|world_preview\|WorldPreview" src/ tests/ tools/ project.godot --exclude-dir=docs
```

Expected: zero hits.

```bash
ls comp.spv generate_materials.sh shaders/generated 2>&1
```

Expected: all "No such file or directory."

- [ ] **Step 2: Diff against pre-flight inventory**

```bash
grep -rn "dispatch_simulation\|sim_shader\|sim_pipeline\|sim_uniform_set\|init_material_textures\|init_dummy_texture\|compute_device\|RenderingDevice\|RDShaderFile\|RDUniform\|compute_list\|push_constant\|texture_get_data\|texture_update\|res://shaders/compute/simulation\|res://shaders/include/sim\|res://shaders/generated\|world_preview" \
    src/ tests/ tools/ project.godot \
    > /tmp/step7-inventory-after.txt
diff /tmp/step7-inventory-before.txt /tmp/step7-inventory-after.txt | head -60
cat /tmp/step7-inventory-after.txt
```

Expected: `step7-inventory-after.txt` is empty.

- [ ] **Step 3: Confirm class registration**

```bash
grep "GDREGISTER_CLASS" gdextension/src/register_types.cpp
```

Expected to include: `Simulator`, `ChunkManager`, `WorldManager`, `TerrainModifier`, plus all step 1–6 classes.

- [ ] **Step 4: Build clean**

```bash
./gdextension/build.sh clean
./gdextension/build.sh debug
./gdextension/build.sh release
ls -la bin/lib/
```

Expected: both debug and release dylibs built.

- [ ] **Step 5: Editor smoke + gdUnit4**

Launch Godot 4.6 → Output log clean → run gdUnit4 → all green.

- [ ] **Step 6: Smoke playthrough (~2 min, per spec §10.2)**

Launch → generate a large level → walk through it for ~2 minutes. Specifically exercise:
- **Generation visual sanity.** Caves/biomes/stamps/secret rings render correctly (preserved from step 6).
- **Lava simulation.** Place lava (cheat command or weapon) at multiple chunk boundaries. Confirm:
  - Lava flows downhill, pools, cools.
  - Crossing chunk boundaries: lava enters neighbor chunk, neighbor wakes, sim continues.
  - No flicker, no spurious solids appearing at edges.
- **Gas simulation.** Gas weapon → gas drifts, diffuses, dissipates. Cross-chunk gas migration works.
- **Burning.** Lava on wood → wood ignites → flames spread → combustion drains health → wood becomes air. Gas + fire interaction matches today's behavior.
- **Digging.** `TerrainModifier::place_material(MAT_AIR, ...)` carves walls. Collision rebuilds (`ColliderBuilder` triggered via `collider_dirty`). Player can move through.
- **Sleeping.** Stand still in a settled area for ~5s → confirm CPU drops as chunks go to sleep. Reactivate by walking → frames recover.
- **Floor advance.** Portal → next floor → fresh level → sim still works.

No crashes, no visible deadlocks, no frame stutters > 1s.

If frame budget busts (per §10.1 risk #1):
- Profile the inner loop with the platform profiler (Instruments on macOS, perf on Linux).
- If `tick_chunk` dominates, micro-optimize the cell loop (LICM, branch reduction in the rule dispatch).
- If `upload_texture` dominates, switch to dirty-rect partial upload (see task 8 TODO).
- If both are flat and the budget still busts: drop sim to per-2-frames per spec §10.1 risk #1 mitigation. That's a follow-up — open a separate PR; do not bundle into this step.

- [ ] **Step 7: Format C++ sources**

```bash
./gdextension/format.sh
git diff gdextension/src/
```

If the formatter changed anything:
```bash
git add gdextension/src/
git commit -m "chore: clang-format sim/terrain sources"
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

Per spec §6.8, cross-machine determinism is not promised — visible noise differences (different lava pool shapes, different burn fronts) are expected. The bar is "the level generates and plays correctly, sim is stable, no crashes."

If something is structurally broken on the second machine (crash, infinite floors, missing rooms, sim deadlock): fix and commit before declaring step 7 done.

---

## Done Definition for Step 7

(Cross-reference spec §11 "Done Definition" — every bullet there must be true at the end of this step.)

- `gdextension/src/sim/simulator.{h,cpp}` exists; `Simulator` is registered as a native class; `Simulator.new()` works from GDScript.
- `gdextension/src/sim/sim_context.{h,cpp}` provides the cross-chunk safety boundary; rules access state exclusively through it.
- Each material rule (`injection`, `lava`, `gas`, `burning`) lives in its own translation unit under `gdextension/src/sim/rules/` and is wired into `Simulator::tick_chunk` in the order the GLSL ran them.
- `gdextension/src/terrain/{chunk_manager,world_manager}.{h,cpp}` and `gdextension/src/terrain/terrain_modifier.{h,cpp}` exist, are registered, instantiate by their original class names from GDScript and `.tscn` files.
- `Chunk` carries `Cell cells[]`, `dirty_rect`, atomic `next_dirty_rect` bounds, `sleeping`, `collider_dirty`, four `Ref<Chunk>` neighbors, an injection queue, and a `Ref<ImageTexture> texture`. Legacy GPU fields (`rd_texture`, `texture_2d_rd`, `sim_uniform_set`, `injection_buffer`) are gone.
- `MaterialDef` carries `kind`, `density`, `viscosity`, `dispersion`, `diffusion_rate`, `max_temp` in addition to step-2 fields; values are populated from `materials.glslinc` and the per-rule GLSL constants.
- `Simulator::tick` runs the 4-phase chunk-checkerboard via `WorkerThreadPool::add_group_task`, joins per phase, rotates dirty rects, uploads dirty textures on the main thread.
- `WorldManager::_process` drives `ChunkManager::_update_chunks → GasInjector::build_payloads → Simulator::tick → ColliderBuilder::rebuild_dirty` once per frame; no `compute_device`, no `RenderingDevice`.
- `TerrainModifier` writes directly to `Chunk::cells[]`, flags dirty rect + collider, clears sleeping; no GPU readback/upload.
- `shaders/compute/`, `shaders/include/`, `shaders/generated/` directories are gone.
- `generate_materials.sh`, `comp.spv` are gone.
- `src/core/compute_device.gd` (+ `.uid`) is gone; no callers remain.
- `src/terrain/world_preview.gd` (+ `.uid`) is gone; preview-mode wiring is gone (autoload entry, scene refs, console commands).
- Zero `RenderingDevice`, `RDShaderFile`, `RDShaderSPIRV`, `compute_list`, `push_constant`, `RDUniform` references remain in `src/` or `gdextension/src/`.
- `gdUnit4` suite passes on both macOS and Arch.
- Smoke playthrough passes on both macOS and Arch — generation, lava, gas, fire, digging, combat, floor advance all functional with no crashes and no stutters > 1s.
- Spec §11 Done Definition is fully satisfied.
