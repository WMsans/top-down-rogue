# Step 6 — `Generator` + `SimplexCaveGenerator` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port chunk generation to native C++ via godot-cpp and **delete the next two compute shaders (`generation.glsl`, `generation_simplex_cave.glsl`) plus every `.glslinc` they pull in**. Two new C++ classes are introduced (`Generator`, `SimplexCaveGenerator`, both per spec §8.1–§8.2). After this step, generation runs entirely on the CPU, dispatched per-chunk via `WorkerThreadPool::add_group_task`. Simulation still runs on the GPU (`simulation.glsl` survives until step 7), so each generated chunk's bytes are written into both `chunk->cells[]` *and* `chunk->rd_texture` (via `RenderingDevice::texture_update`) so the GPU simulator and the existing chunk-render shader keep consuming the same data they do today.

**Architecture:** A small `util/simplex.{h,cpp}` translation unit replaces `simplex_2d.glslinc` + `simplex_cave_utils.glslinc` (hash, `snoise`, `snoise01`, `simplex_fbm`, `simplex_ridge`). Each GLSL stage becomes one free function under `gdextension/src/generation/stages/*.cpp`, taking `(Chunk *, const StageContext &)` and writing into `chunk->cells[]` directly — same file split as the `.glslinc` files (1:1) so each stage can be ported and verified in isolation. Two `RefCounted` driver classes own the stage pipelines: `Generator` runs `wood_fill → biome_cave → biome_pools → pixel_scene_stamp → secret_ring` (matching `generation.glsl`); `SimplexCaveGenerator` runs `stone_fill → simplex_cave` (matching `generation_simplex_cave.glsl`). Both expose a single bound entry point `generate_chunks(chunks, new_coords, world_seed, biome, stamp_bytes)` that mirrors today's `ComputeDevice.dispatch_generation` signature so the GDScript callsite in `chunk_manager.gd` collapses to a one-line replacement. Internally each class dispatches the new-coords list through `WorkerThreadPool::add_group_task`, joins, and uploads each freshly generated chunk's `cells[]` to its `rd_texture` on the calling thread before returning.

**Tech Stack:** godot-cpp pinned per step 1, C++17, the existing SCons + `build.sh` pipeline. No new external dependencies. `WorkerThreadPool` is godot-cpp's standard parallel-task pool — no new threading library.

---

## Required Reading Before Starting

You **must** read all of these before writing any code.

1. **Spec:** `docs/superpowers/specs/2026-04-30-godot-cpp-hot-path-port-design.md`. Mandatory sections:
   - §3.1 — confirms which shader files are removed in this refactor (the full `shaders/compute/` and `shaders/include/` directories), but only the generation subset is removed *this step*.
   - §3.2 — `Generator` and `SimplexCaveGenerator` rows. Both `RefCounted`. They're "new C++ classes" (no GDScript predecessor), so there's no class-name preservation to honor; just pick the names the spec uses.
   - §3.4 (Non-goals) — no bit-exact GLSL parity (Q3). Output is "deterministic CPU output, no GLSL parity." Worlds will differ visually after this step from worlds generated before — that's acceptable. Smoke "level looks like a level" is the bar (§9.6, §10.2).
   - §4.1 (Layout) — `gdextension/src/generation/{generator,simplex_cave_generator}.{h,cpp}` + `stages/*.cpp` + `gdextension/src/util/simplex.{h,cpp}`. Use that layout exactly.
   - §6.1 (Cell layout) — `Cell { uint8_t material, health, temperature, flags }`. Stage free functions write into this struct directly (4 bytes per cell). Today's GLSL stores `vec4(material/255, health/255, 0, 0)` into an `R8G8B8A8_UNORM` image — the byte layout matches `Cell` byte-for-byte (R=material, G=health, B=temperature, A=flags), so the texture upload at end-of-generate is a `memcpy`-shaped operation, not a recoding.
   - §8.1 (`Generator`) — defines the stage pipeline and the per-chunk job model. Note: spec describes "return the Chunk via signal back on the main thread." For this step we keep generation **synchronous within the call** (matches today's `dispatch_generation` synchronous shape and `chunk_manager.gd`'s expectation that chunks are usable immediately after the call returns). The `WorkerThreadPool::add_group_task` call uses `high_priority=true, wait_for_completion=true` so the helper joins before returning. Asynchronous signal-emission lands when `ChunkManager` itself goes C++ in step 7.
   - §8.2 (`SimplexCaveGenerator`) — same shape as `Generator`, different stage list.
   - §9.1 step 6 — what this step delivers and what it deletes:
     - delete `shaders/compute/generation.glsl` (+ `.glsl.import`)
     - delete `shaders/compute/generation_simplex_cave.glsl` (+ `.glsl.import`)
     - delete `shaders/include/cave_stage.glslinc`, `cave_utils.glslinc`, `biome_cave_stage.glslinc`, `biome_pools_stage.glslinc`, `pixel_scene_stamp.glslinc`, `secret_ring_stage.glslinc`, `simplex_2d.glslinc`, `simplex_cave_stage.glslinc`, `simplex_cave_utils.glslinc`, `stone_fill_stage.glslinc`, `wood_fill_stage.glslinc`
   - §10.1 risks #5 — restart the editor for verification (don't trust hot-reload across this step's ABI change).

2. **Predecessor C++ source from step 5** (already merged) — read in full before writing C++:
   - `gdextension/src/physics/collider_builder.{h,cpp}` — closest precedent for a per-chunk RefCounted driver that consumes a chunk's bytes. The `Generator` API mirrors this surface.
   - `gdextension/src/terrain/chunk.{h,cpp}` — every stage writes into `chunk->cells[]`. Confirm `cells` is exposed as a writable C++ field (not just `get_cells_data`/`set_cells_data` PackedByteArray getters) — stages must mutate cells in place without round-tripping through `PackedByteArray`. If the C++ field is `private`, add a `friend` declaration for the stages or expose `Cell *cells_ptr()`. Do this in the same commit that lands stage 1 — don't pre-modify `chunk.h` ahead of time.
   - `gdextension/src/sim/material_table.{h,cpp}` — stages read material ids by name (e.g. `MAT_WOOD`, `MAT_STONE`). Confirm `MaterialTable::id_of("wood")` etc. return the integer ids today's GLSL `materials.glslinc` hard-codes as `MAT_WOOD`, `MAT_STONE`. If the spelling differs (`get_id`, `lookup`, …), use whatever step 2 actually bound — don't invent.
   - `gdextension/src/resources/biome_def.{h,cpp}` — stages need `cave_noise_scale`, `cave_threshold`, `ridge_weight`, `ridge_scale`, `octaves`, `background_material`, `secret_ring_thickness`, `pool_materials`. Confirm the C++ field names match what `compute_device.gd::upload_biome_buffer` reads off `biome` today.
   - `gdextension/src/resources/template_pack.{h,cpp}` and `gdextension/src/resources/room_template.{h,cpp}` — `pixel_scene_stamp` reads template pixel data per stamp. The PNG-backed Texture2DArray no longer carries the stage's data; the pure-CPU stage reads pixel bytes directly from `RoomTemplate::image` (the source-of-truth `Image` set by `TemplatePack::register`). Confirm `RoomTemplate` exposes a `Ref<Image>` (or equivalent) accessor — if it doesn't, add it in this step's task 2 (it's load-bearing for `pixel_scene_stamp`).
   - `gdextension/src/register_types.cpp` — where the new `GDREGISTER_CLASS` calls land.

3. **The GLSL being replaced** (read in full so the port isn't blind):
   - `shaders/compute/generation.glsl` (33 LOC) — stage order: `wood_fill → biome_cave → biome_pools → pixel_scene_stamp → secret_ring`.
   - `shaders/compute/generation_simplex_cave.glsl` (26 LOC) — stage order: `stone_fill → simplex_cave`.
   - `shaders/include/wood_fill_stage.glslinc` (13 LOC).
   - `shaders/include/stone_fill_stage.glslinc` (12 LOC).
   - `shaders/include/biome_cave_stage.glslinc` (35 LOC).
   - `shaders/include/biome_pools_stage.glslinc` (29 LOC).
   - `shaders/include/pixel_scene_stamp.glslinc` (65 LOC).
   - `shaders/include/secret_ring_stage.glslinc` (28 LOC).
   - `shaders/include/simplex_cave_stage.glslinc` (31 LOC).
   - `shaders/include/simplex_2d.glslinc` (73 LOC).
   - `shaders/include/simplex_cave_utils.glslinc` (52 LOC).
   - `shaders/include/cave_stage.glslinc` (219 LOC) and `cave_utils.glslinc` (309 LOC) — **dead weight at HEAD**. Neither `generation.glsl` nor `generation_simplex_cave.glsl` includes them; `grep -rn "cave_stage.glslinc\|cave_utils.glslinc" shaders/` confirms no references. They predate the simplex/biome split. The spec marks them for deletion anyway (§9.1 step 6 list); we delete them without porting. Confirm the grep before relying on this.

4. **Every callsite that drives generation** (so the C++ surface matches usage exactly):
   - `src/core/chunk_manager.gd` line 246 — single live caller of `compute_device.dispatch_generation(chunks, new_chunks, seed_val)`. This call collapses to `_get_generator(biome).generate_chunks(chunks, new_chunks, seed_val, biome, PackedByteArray())`. The biome lookup happens here.
   - `src/core/world_manager.gd` line 94 — second live caller, this one passes `stamp_bytes`. Same collapse, just with the `stamp_bytes` argument forwarded.
   - `src/core/world_manager.gd` lines 30–34, 264–265 — calls `compute_device.init_gen_stamp_buffer()`, `init_gen_biome_buffer()`, `upload_biome_buffer(biome)`, `bind_template_arrays(...)`. **All four become dead** after this step (their work is internal to `Generator` now). They survive in `ComputeDevice` until task 7, then get excised.
   - `src/autoload/level_manager.gd` line 48 (`build_stamp_bytes`) — produces the `PackedByteArray` consumed by `pixel_scene_stamp_stage`. The byte format (`[count: s32][12 pad][stamp_count × 16B]`, each stamp = `(cx: f32, cy: f32, idx: f32, meta: f32)`) **must be preserved byte-for-byte** so `level_manager.gd` doesn't change. Cross-reference the `STAMP_BUFFER_SIZE` constant (`16 + 128 * 16`) and the `meta` packing (`size_class & 0xFF | rot_steps << 8 | flags << 16`) — same in C++.

5. **Determinism contract (per spec §6.8 and §3.4 Q3):**
   - Same `world_seed` + same biome + same chunk coord → same chunk bytes. This step uses straight-line per-cell loops with no thread-shared mutation inside a single chunk's job, so determinism is a function of the noise function's bit-stable output. `simplex.{h,cpp}` must use `float` (not `double`) and the same coefficient constants as `simplex_2d.glslinc` so output is reproducible across runs on a single machine. **Cross-machine determinism is not promised** (different FP rounding modes, different libm). Follow the GLSL math spelled exactly — no "cleanup" of constants.
   - Worlds *will* differ from pre-step-6 GPU-generated worlds (per Q3). That's expected. Do not chase pixel parity.

If anything in this plan conflicts with the spec, the spec wins — flag the conflict and stop, do not silently deviate.

## What This Step Does NOT Do

- **Does not** port `ChunkManager`, `WorldManager`, `TerrainModifier`, or any class outside the two listed in the title. The chunk-streaming loop stays in `chunk_manager.gd`; only its inner generation call swaps targets.
- **Does not** delete `shaders/compute/simulation.glsl` or any `shaders/include/sim/` file. Simulation is step 7.
- **Does not** introduce `Chunk::cells[]` → `rd_texture` *streaming* mid-frame. The bridge is one-shot at end-of-generate: write `cells[]`, then `rd->texture_update(chunk->rd_texture, 0, cells_byte_view)` once. The simulator still owns mid-frame texture mutation (it writes via `imageStore` from `simulation.glsl`).
- **Does not** wire `dirty_rect`/`sleeping`/`Chunk::upload_texture()` paths from §6.1/§8.4. Those are step 7 plumbing. After generation we *do* set `chunk->dirty_rect = full chunk` and `chunk->sleeping = false` per spec §8.1, since step 7 will read those flags. They cost nothing today (no consumer until step 7).
- **Does not** introduce `WorkerThreadPool` for simulation, collider, or any other subsystem. This step uses it for generation only.
- **Does not** change `level_manager.gd::build_stamp_bytes`. Byte format preserved exactly.
- **Does not** change `BiomeRegistry` or template loading. `TemplatePack` already builds the `Texture2DArray`s today; we now also need each template's source `Image` for CPU sampling. If `TemplatePack` doesn't already retain the `Image` (i.e. it discards after `Texture2DArray` build), task 2 step 1 adds retention — small change, document it as part of this step.
- **Does not** add a `cell` accessor that returns a `Ref<TerrainCell>`. Stages mutate raw `Cell` structs by pointer for speed; `TerrainCell` is the GDScript-facing query type and stays untouched.
- **Does not** delete `comp.spv`. That file is a stale build artifact unrelated to generation; it goes in step 7's cleanup wave.

## Pre-flight Verification (do this first)

- [ ] **Step 1: Confirm step 5 is merged and the build is green**

```bash
git status
git log --oneline -10
./gdextension/build.sh debug
ls bin/lib/
```

Expected: clean working tree on `refactor/cpp`. Recent commits include the step 5 work (`feat: add TerrainCollider C++ class`, `feat: add ColliderBuilder C++ class`, `feat: add GasInjector C++ class`, `feat: add TerrainCollisionHelper C++ class (CPU path only)`, `feat: add TerrainPhysical C++ class`, `feat: register ColliderBuilder, TerrainCollider, GasInjector, TerrainCollisionHelper, TerrainPhysical`, `refactor: delete GDScript collider/physics, GPU collider shader, and ComputeDevice collider plumbing`, `chore: clang-format collider/physics sources`). Build produces the dylib/so for the current platform.

- [ ] **Step 2: Confirm the editor still loads cleanly with step 5's natives**

Launch Godot 4.6 → open project → Output log clean. F5 → walk for ~10s in a generated level → quit. Smoke confirms generation+collider+sim all still cooperate end-to-end before we change generation.

- [ ] **Step 3: Inventory generation callsites once, before changes**

```bash
grep -rn "dispatch_generation\|init_gen_stamp_buffer\|init_gen_biome_buffer\|upload_biome_buffer\|bind_template_arrays\|gen_stamp_buffer\|gen_biome_buffer\|gen_template_uniform_set\|gen_template_array_rids\|gen_shader\|gen_pipeline\|res://shaders/compute/generation\|res://shaders/include/" \
    src/ tests/ tools/ project.godot \
    > /tmp/step6-inventory-before.txt
wc -l /tmp/step6-inventory-before.txt
```

Save that file — Task 8 step 2 re-greps and confirms zero hits remain (every entry is either deleted or replaced).

- [ ] **Step 4: Confirm `cave_stage.glslinc` and `cave_utils.glslinc` are unreferenced at HEAD**

```bash
grep -rn "cave_stage\.glslinc\|cave_utils\.glslinc" shaders/ src/
```

Expected: zero hits. If anything references them, **stop and flag** — the assumption that they're dead weight is load-bearing for "delete without porting." If a reference appears in a file we forgot, port it as a stage in task 2 instead.

- [ ] **Step 5: Confirm `MaterialTable` exposes the material ids the stages need**

```bash
grep -n "MAT_AIR\|MAT_WOOD\|MAT_STONE\|id_of\|get_id" gdextension/src/sim/material_table.h gdextension/src/sim/material_table.cpp
```

Expected: a way to look up ids `wood`, `stone`, `air` (or whatever today's `materials.glslinc` calls them). If `MaterialTable` only exposes `get_id(StringName)` (no compile-time constants for the canonical four), stages cache them once at `Generator` construction time (an `int wood_id`, `stone_id`, `air_id` member) — not per-cell.

- [ ] **Step 6: Confirm `BiomeDef` C++ field surface matches what stages need**

```bash
grep -n "cave_noise_scale\|cave_threshold\|ridge_weight\|ridge_scale\|octaves\|background_material\|secret_ring_thickness\|pool_materials" \
    gdextension/src/resources/biome_def.h gdextension/src/resources/biome_def.cpp
```

Expected: every field listed. Cross-check with `src/core/compute_device.gd::upload_biome_buffer` (lines 163–183) to confirm types (`float` vs `int`) match. A type mismatch becomes a stage-level cast and a code-comment noting "narrowing from BiomeDef.X for parity with old GLSL int cast."

- [ ] **Step 7: Confirm `RoomTemplate` retains its source `Image`**

```bash
grep -n "image\|Image\|get_image" gdextension/src/resources/room_template.h
```

Expected: a `Ref<Image>` field or accessor. If absent (i.e. `RoomTemplate` only carries the `texture_path` string), task 2 step 1 adds an `image` field and `TemplatePack::register` populates it. The CPU pixel-scene-stamp stage reads pixel rows from this `Image`, not from a `Texture2DArray`.

- [ ] **Step 8: Confirm the gdUnit4 suite is green at HEAD**

Run gdUnit4 via the editor's Test panel. All green. Document any pre-existing failure before proceeding.

---

## Task 1: Add `simplex.{h,cpp}` noise utility

Replaces `simplex_2d.glslinc` and the FBM/ridge helpers from `simplex_cave_utils.glslinc`. Pure header + free functions; no godot-cpp class registration.

**Files:**
- Create: `gdextension/src/util/simplex.h`
- Create: `gdextension/src/util/simplex.cpp`

- [ ] **Step 1: Write the header**

```cpp
#pragma once

#include <cstdint>

namespace toprogue::simplex {

// Replaces shaders/include/simplex_2d.glslinc + simplex_cave_utils.glslinc.
// All functions are deterministic on a single machine for given inputs;
// cross-machine determinism is not guaranteed (libm/FP rounding).

uint32_t hash_uint(uint32_t x);
uint32_t hash_combine(uint32_t a, uint32_t b);

// Simplex noise, [-1, 1].
float snoise(float x, float y);

// Same noise, offset deterministically by `seed` (matches GLSL `snoise_seeded`).
float snoise_seeded(float x, float y, uint32_t seed);

// snoise_seeded mapped to [0, 1].
float snoise01(float x, float y, uint32_t seed);

// Fractal-Brownian-motion using snoise01.
float simplex_fbm(float x, float y, uint32_t seed, int octaves);

// Ridge noise (1 - |snoise|)^2 accumulated FBM-style.
float simplex_ridge(float x, float y, uint32_t seed, int octaves);

} // namespace toprogue::simplex
```

- [ ] **Step 2: Write the implementation**

Port the functions in `simplex_2d.glslinc` and `simplex_cave_utils.glslinc` line-by-line:

- `_mod289`, `_permute`, `snoise` — straight transliteration of the GLSL. `vec2`/`vec3`/`vec4` become local `float` variables (or small `struct`s); use `std::floor` and `std::fabs`. **Do not** "modernize" the constants. `0.211324865405187`, `0.366025403784439`, etc. stay as-is. `inversesqrt` becomes `1.0f / std::sqrt(...)` (or use the same `1.79284291400159 - 0.85373472095314 * (a0² + h²)` denormalization the GLSL uses — copy literally).
- `_simple_hash`, `snoise_seeded`, `snoise01` — also literal ports.
- `hash_uint`, `hash_combine`, `simplex_fbm`, `simplex_ridge` from `simplex_cave_utils.glslinc` — same.

**Float vs double.** Use `float` everywhere. The GLSL operates on 32-bit floats; doubling precision changes thresholds and the resulting world differs visibly. Stick to `float`.

- [ ] **Step 3: Build standalone**

```bash
./gdextension/build.sh debug
```

Expected: clean. Common failure modes:
- Missing `<cmath>` include for `std::floor`, `std::fabs`, `std::sqrt`. Add it.
- `-Wfloat-conversion` warnings on the `0.5 - vec3(...)` clamp sequence — silence by writing `0.5f` literals.

- [ ] **Step 4: Smoke-test the noise function determinism**

Add a temporary scratch test (delete before committing) at the bottom of `gdextension/src/util/simplex.cpp`:

```cpp
#ifdef TOPROGUE_SIMPLEX_SMOKE
int main() {
    using namespace toprogue::simplex;
    // Print a 3-decimal-rounded value at a fixed input. Run twice; compare.
    printf("%.6f\n", snoise01(123.456f, 789.012f, 0xDEADBEEFu));
    printf("%.6f\n", simplex_fbm(0.5f, 0.5f, 0xCAFEBABEu, 5));
    printf("%.6f\n", simplex_ridge(1.0f, 1.0f, 0xFEEDFACEu, 4));
    return 0;
}
#endif
```

Skip this step if running it requires SCons gymnastics; the inline grep against the GLSL constants is the actual safety net.

- [ ] **Step 5: Commit**

```bash
git add gdextension/src/util/simplex.{h,cpp}
git commit -m "feat: add simplex noise utility (port of simplex_2d.glslinc + simplex_cave_utils.glslinc)"
```

---

## Task 2: Port the generation stages as free functions

Each `.glslinc` stage becomes one `.cpp` under `gdextension/src/generation/stages/`, each exposing a free function named `stage_X(Chunk *chunk, const StageContext &ctx)`. Together they are the per-chunk job body.

**Shared header:**
- Create: `gdextension/src/generation/stage_context.h`

```cpp
#pragma once

#include "../resources/biome_def.h"

#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <cstdint>

namespace toprogue {

// Per-stage context. Read-only by stages; mutation happens on the chunk only.
struct StageContext {
    godot::Vector2i      chunk_coord;
    uint32_t             world_seed;
    godot::Ref<BiomeDef> biome;            // may be null for SimplexCaveGenerator's stages
    godot::PackedByteArray stamp_bytes;     // raw level_manager.gd::build_stamp_bytes output

    // Cached material ids resolved once at Generator construction time.
    int                  air_id   = 0;
    int                  wood_id  = 0;
    int                  stone_id = 0;
};

} // namespace toprogue
```

**Files for each stage (one `.cpp` per `.glslinc`, no headers — declared in `generator.h`/`simplex_cave_generator.h`):**

- Create: `gdextension/src/generation/stages/wood_fill_stage.cpp`
- Create: `gdextension/src/generation/stages/stone_fill_stage.cpp`
- Create: `gdextension/src/generation/stages/biome_cave_stage.cpp`
- Create: `gdextension/src/generation/stages/biome_pools_stage.cpp`
- Create: `gdextension/src/generation/stages/pixel_scene_stamp_stage.cpp`
- Create: `gdextension/src/generation/stages/secret_ring_stage.cpp`
- Create: `gdextension/src/generation/stages/simplex_cave_stage.cpp`

Each stage has the same shape:

```cpp
#include "../../terrain/chunk.h"
#include "../stage_context.h"
#include "../../util/simplex.h"
#include "../../sim/material_table.h"

using namespace godot;

namespace toprogue {

void stage_wood_fill(Chunk *chunk, const StageContext &ctx);

} // namespace toprogue
```

The stage forward declarations live as `extern` declarations on `Generator`/`SimplexCaveGenerator` (task 3 step 1 / task 4 step 1). No public header per stage.

- [ ] **Step 1: If `RoomTemplate` doesn't already retain its source `Image`, add it**

Per pre-flight step 7: `pixel_scene_stamp` needs `RoomTemplate::image` to read pixel bytes. Inspect `gdextension/src/resources/room_template.{h,cpp}` and `gdextension/src/resources/template_pack.{h,cpp}`:

- If `image` is already retained: skip this step.
- If not: add `Ref<Image> image` field on `RoomTemplate`, bind it via `_bind_methods` (`get_image`/`set_image`), and update `TemplatePack::register` to set it. This is a small, additive change; no migration needed because `.tres` files don't serialize the field (it's loaded at runtime from `texture_path`).

Commit boundary: roll this into the same commit as task 2 step 5 (the pixel_scene_stamp stage) or land it separately. Up to taste; keep it small either way.

- [ ] **Step 2: Port `stage_wood_fill` and `stage_stone_fill`**

Both are trivial constant fills. From `wood_fill_stage.glslinc`:

```cpp
void stage_wood_fill(Chunk *chunk, const StageContext &ctx) {
    Cell *cells = chunk->cells_ptr();
    for (int i = 0; i < Chunk::CHUNK_SIZE * Chunk::CHUNK_SIZE; i++) {
        cells[i].material    = static_cast<uint8_t>(ctx.wood_id);
        cells[i].health      = 255;
        cells[i].temperature = 0;
        cells[i].flags       = 0;
    }
}
```

`stage_stone_fill` is identical with `wood_id` → `stone_id`.

**`Cell *cells_ptr()` accessor.** If `Chunk` doesn't already expose a raw pointer to its cell array, add `Cell *cells_ptr() { return cells; }` and `const Cell *cells_ptr() const { return cells; }` to `chunk.h`. Not bound to GDScript — pure C++ accessor. Stages depend on it.

- [ ] **Step 3: Port `stage_biome_cave`**

From `biome_cave_stage.glslinc`. The GLSL uses `gl_GlobalInvocationID.xy`; in CPU, that becomes the cell index inside a double loop:

```cpp
void stage_biome_cave(Chunk *chunk, const StageContext &ctx) {
    Cell *cells = chunk->cells_ptr();
    Ref<BiomeDef> b = ctx.biome;
    if (b.is_null()) return;

    const float cave_scale     = b->cave_noise_scale;
    const float cave_threshold = b->cave_threshold;
    const float ridge_weight   = b->ridge_weight;
    const float ridge_scale    = b->ridge_scale;
    const int   octaves        = b->octaves;
    const int   bg_mat         = b->background_material;

    for (int y = 0; y < Chunk::CHUNK_SIZE; y++) {
        for (int x = 0; x < Chunk::CHUNK_SIZE; x++) {
            float wx = float(ctx.chunk_coord.x * Chunk::CHUNK_SIZE + x);
            float wy = float(ctx.chunk_coord.y * Chunk::CHUNK_SIZE + y);

            float n  = simplex::simplex_fbm(wx * cave_scale, wy * cave_scale, ctx.world_seed, octaves);
            float r  = simplex::simplex_ridge(wx * ridge_scale, wy * ridge_scale,
                                              simplex::hash_combine(ctx.world_seed, 1000u), 4);
            float c  = n * (1.0f - ridge_weight) + r * ridge_weight;

            int idx = y * Chunk::CHUNK_SIZE + x;
            if (c > cave_threshold) {
                cells[idx] = Cell{ static_cast<uint8_t>(ctx.air_id), 0, 0, 0 };
            } else {
                cells[idx] = Cell{ static_cast<uint8_t>(bg_mat),     0, 0, 0 };
            }
        }
    }
}
```

**Health byte for background.** Today's GLSL stores `vec4(r, 0, 0, 0)` — health=0 — for the carved background. Match that. The `wood_fill` / `stone_fill` stages set health=255 for solid wall; `biome_cave` overwrites *both* air and background with health=0. That's the existing GLSL behavior; preserve it. (The mismatch is benign because `biome_pools` and `pixel_scene_stamp` overwrite further; consumers don't read health from generated terrain until the simulator wakes up.)

- [ ] **Step 4: Port `stage_biome_pools`**

From `biome_pools_stage.glslinc`. Walks the `b->pool_materials` array (up to 4 entries). Each `PoolDef` exposes `material_id`, `noise_scale`, `noise_threshold`, `seed_offset`. Confirm field names against `gdextension/src/resources/pool_def.h`. Skip cells whose current material is `air_id`. First pool that exceeds threshold wins.

```cpp
void stage_biome_pools(Chunk *chunk, const StageContext &ctx) {
    Cell *cells = chunk->cells_ptr();
    Ref<BiomeDef> b = ctx.biome;
    if (b.is_null()) return;

    TypedArray<PoolDef> pools = b->pool_materials;
    int pool_count = MIN(pools.size(), 4);
    if (pool_count == 0) return;

    for (int y = 0; y < Chunk::CHUNK_SIZE; y++) {
        for (int x = 0; x < Chunk::CHUNK_SIZE; x++) {
            int idx = y * Chunk::CHUNK_SIZE + x;
            if (cells[idx].material == ctx.air_id) continue;

            float wx = float(ctx.chunk_coord.x * Chunk::CHUNK_SIZE + x);
            float wy = float(ctx.chunk_coord.y * Chunk::CHUNK_SIZE + y);

            for (int i = 0; i < pool_count; i++) {
                Ref<PoolDef> p = pools[i];
                if (p.is_null() || p->material_id <= 0) continue;
                uint32_t pseed = simplex::hash_combine(ctx.world_seed, uint32_t(p->seed_offset));
                float n = simplex::simplex_fbm(wx * p->noise_scale, wy * p->noise_scale, pseed, 2);
                if (n > p->noise_threshold) {
                    cells[idx].material = static_cast<uint8_t>(p->material_id);
                    break; // first pool wins
                }
            }
        }
    }
}
```

- [ ] **Step 5: Port `stage_pixel_scene_stamp`**

This is the biggest stage. Decode the stamp buffer (16-byte header + up to 128 × 16-byte stamps), iterate stamps, and for each stamp test every cell of the chunk for AABB intersection with the stamp's footprint. For cells inside, sample the rotated template image at the corresponding local pixel.

Key shape, lifted from `pixel_scene_stamp.glslinc`:

```cpp
namespace {
struct Stamp {
    float cx, cy, idx, meta_f;
};

inline int stamp_count(const PackedByteArray &b) { return b.decode_s32(0); }
inline Stamp stamp_at(const PackedByteArray &b, int i) {
    int off = 16 + i * 16;
    return Stamp{ b.decode_float(off+0), b.decode_float(off+4),
                  b.decode_float(off+8), b.decode_float(off+12) };
}

// rot_steps: 0=0°, 1=90°, 2=180°, 3=270° (CCW). Same as the GLSL.
inline void rotate_local(float lx, float ly, int rot, float size, float &ox, float &oy) {
    if (rot == 0) { ox = lx;            oy = ly;            return; }
    if (rot == 1) { ox = ly;            oy = size - 1 - lx; return; }
    if (rot == 2) { ox = size - 1 - lx; oy = size - 1 - ly; return; }
                  ox = size - 1 - ly; oy = lx;
}
} // anonymous

void stage_pixel_scene_stamp(Chunk *chunk, const StageContext &ctx) {
    if (ctx.stamp_bytes.size() < 16) return;
    int n = stamp_count(ctx.stamp_bytes);
    if (n <= 0) return;

    int bg_mat = ctx.biome.is_valid() ? ctx.biome->background_material : ctx.stone_id;
    Cell *cells = chunk->cells_ptr();

    // For each stamp, compute its world-AABB intersection with this chunk.
    for (int s = 0; s < n; s++) {
        Stamp st = stamp_at(ctx.stamp_bytes, s);
        int meta = int(std::round(st.meta_f));
        int size_class = meta & 0xFF;
        int rot_steps  = (meta >> 8) & 0xFF;
        if (size_class <= 0) continue;

        Ref<RoomTemplate> tmpl = TemplatePack::get_singleton()->get_template_at_index(size_class, int(std::round(st.idx)));
        if (tmpl.is_null() || tmpl->image.is_null()) continue;
        Ref<Image> img = tmpl->image;

        float half = float(size_class) * 0.5f;
        float chunk_origin_x = float(ctx.chunk_coord.x * Chunk::CHUNK_SIZE);
        float chunk_origin_y = float(ctx.chunk_coord.y * Chunk::CHUNK_SIZE);

        // Local-pixel ranges this chunk overlaps.
        int x_min = std::max(0,                   int(std::floor(st.cx - half - chunk_origin_x)));
        int x_max = std::min(Chunk::CHUNK_SIZE-1, int(std::ceil (st.cx + half - chunk_origin_x)) - 1);
        int y_min = std::max(0,                   int(std::floor(st.cy - half - chunk_origin_y)));
        int y_max = std::min(Chunk::CHUNK_SIZE-1, int(std::ceil (st.cy + half - chunk_origin_y)) - 1);
        if (x_min > x_max || y_min > y_max) continue;

        for (int y = y_min; y <= y_max; y++) {
            for (int x = x_min; x <= x_max; x++) {
                float wx = chunk_origin_x + x;
                float wy = chunk_origin_y + y;
                float dx = wx - st.cx;
                float dy = wy - st.cy;
                if (std::fabs(dx) >= half || std::fabs(dy) >= half) continue;

                float lx = dx + half;
                float ly = dy + half;
                float sx, sy;
                rotate_local(lx, ly, rot_steps, float(size_class), sx, sy);

                int ix = std::clamp(int(sx), 0, size_class - 1);
                int iy = std::clamp(int(sy), 0, size_class - 1);
                Color px = img->get_pixel(ix, iy);
                if (px.a < 0.5f) continue;            // transparent → skip

                int r = int(std::round(px.r * 255.0f));
                int mat = (r == 255) ? bg_mat : r;
                cells[y * Chunk::CHUNK_SIZE + x].material = static_cast<uint8_t>(mat);
            }
        }
    }
}
```

**`TemplatePack::get_template_at_index(size_class, idx)`.** Required accessor. If today's `TemplatePack` only exposes the `Texture2DArray` per size class (and stores templates in some internal `Vector` per size class), add a bound `get_template_at_index(int size_class, int idx) -> Ref<RoomTemplate>` in this step. Fold the addition into task 2 step 5's commit; mention it in the message.

**`Image::get_pixel` is slow.** Calling it once per cell per stamp is bearable for our chunk size (256² = 65k cells worst case, but the AABB clip drastically reduces actual reads). If a perf trace reveals it dominating, cache `Image::get_data()` once per stamp into a local `PackedByteArray` and read raw bytes. Don't pre-optimize.

- [ ] **Step 6: Port `stage_secret_ring`**

From `secret_ring_stage.glslinc`. Reads the same stamp buffer; for stamps with the secret flag set, paints an annular ring of `bg_mat` around the stamp center.

```cpp
void stage_secret_ring(Chunk *chunk, const StageContext &ctx) {
    if (ctx.stamp_bytes.size() < 16) return;
    int n = stamp_count(ctx.stamp_bytes);
    if (n <= 0) return;
    Ref<BiomeDef> b = ctx.biome;
    if (b.is_null()) return;
    int bg_mat    = b->background_material;
    int thickness = b->secret_ring_thickness;

    Cell *cells = chunk->cells_ptr();
    for (int s = 0; s < n; s++) {
        Stamp st = stamp_at(ctx.stamp_bytes, s);
        int meta  = int(std::round(st.meta_f));
        int flags = (meta >> 16) & 0xFF;
        if ((flags & 1) == 0) continue;
        int size_class = meta & 0xFF;

        float inner = float(size_class) * 0.45f;
        float outer = inner + float(thickness);

        // Tight AABB on the outer ring.
        float chunk_origin_x = float(ctx.chunk_coord.x * Chunk::CHUNK_SIZE);
        float chunk_origin_y = float(ctx.chunk_coord.y * Chunk::CHUNK_SIZE);
        int x_min = std::max(0,                   int(std::floor(st.cx - outer - chunk_origin_x)));
        int x_max = std::min(Chunk::CHUNK_SIZE-1, int(std::ceil (st.cx + outer - chunk_origin_x)) - 1);
        int y_min = std::max(0,                   int(std::floor(st.cy - outer - chunk_origin_y)));
        int y_max = std::min(Chunk::CHUNK_SIZE-1, int(std::ceil (st.cy + outer - chunk_origin_y)) - 1);
        if (x_min > x_max || y_min > y_max) continue;

        for (int y = y_min; y <= y_max; y++) {
            for (int x = x_min; x <= x_max; x++) {
                float wx = chunk_origin_x + x;
                float wy = chunk_origin_y + y;
                float dx = wx - st.cx;
                float dy = wy - st.cy;
                float d  = std::sqrt(dx*dx + dy*dy);
                if (d >= inner && d < outer) {
                    cells[y * Chunk::CHUNK_SIZE + x].material = static_cast<uint8_t>(bg_mat);
                }
            }
        }
    }
}
```

- [ ] **Step 7: Port `stage_simplex_cave`**

From `simplex_cave_stage.glslinc`. Constants are baked into the GLSL (not biome-driven). Carve `air_id` where noise exceeds threshold; otherwise leave the cell as the prior stage left it.

```cpp
void stage_simplex_cave(Chunk *chunk, const StageContext &ctx) {
    constexpr float SCALE        = 0.008f;
    constexpr float THRESHOLD    = 0.42f;
    constexpr float RIDGE_SCALE  = 0.012f;
    constexpr float RIDGE_WEIGHT = 0.3f;
    constexpr int   OCTAVES      = 5;

    Cell *cells = chunk->cells_ptr();
    for (int y = 0; y < Chunk::CHUNK_SIZE; y++) {
        for (int x = 0; x < Chunk::CHUNK_SIZE; x++) {
            float wx = float(ctx.chunk_coord.x * Chunk::CHUNK_SIZE + x);
            float wy = float(ctx.chunk_coord.y * Chunk::CHUNK_SIZE + y);
            float n  = simplex::simplex_fbm(wx * SCALE, wy * SCALE, ctx.world_seed, OCTAVES);
            float r  = simplex::simplex_ridge(wx * RIDGE_SCALE, wy * RIDGE_SCALE,
                                              simplex::hash_combine(ctx.world_seed, 1000u), 4);
            float c  = n * (1.0f - RIDGE_WEIGHT) + r * RIDGE_WEIGHT;
            if (c > THRESHOLD) {
                cells[y * Chunk::CHUNK_SIZE + x] = Cell{ static_cast<uint8_t>(ctx.air_id), 0, 0, 0 };
            }
        }
    }
}
```

- [ ] **Step 8: Build standalone**

```bash
./gdextension/build.sh debug
```

Expected: clean. The stages are unused at this point — they exist as free functions but no driver class calls them yet. Compile passes nothing more than syntactic.

- [ ] **Step 9: Commit**

```bash
git add gdextension/src/generation/stages/ \
        gdextension/src/generation/stage_context.h \
        gdextension/src/terrain/chunk.{h,cpp}        # if cells_ptr() was added
git commit -m "feat: add CPU generation stages (wood/stone/biome_cave/biome_pools/pixel_scene_stamp/secret_ring/simplex_cave)"
```

If `RoomTemplate::image` and/or `TemplatePack::get_template_at_index` were added in steps 1/5, fold them into this commit (same logical change) and adjust the message: `feat: add CPU generation stages and RoomTemplate/TemplatePack accessors used by pixel_scene_stamp`.

---

## Task 3: Add `Generator` C++ class

The driver for `generation.glsl`'s pipeline. Owns the stage list, dispatches per-chunk jobs through `WorkerThreadPool`, uploads each chunk's bytes to its `rd_texture` so the GPU sim continues to work.

**Files:**
- Create: `gdextension/src/generation/generator.h`
- Create: `gdextension/src/generation/generator.cpp`

- [ ] **Step 1: Write the header**

```cpp
#pragma once

#include "../resources/biome_def.h"
#include "../terrain/chunk.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/rendering_device.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace toprogue {

// Spec §8.1. Replaces shaders/compute/generation.glsl + every .glslinc it pulls in.
class Generator : public godot::RefCounted {
    GDCLASS(Generator, godot::RefCounted);

public:
    Generator();

    // Generates every chunk in `new_coords`. Each chunk is dispatched as a
    // WorkerThreadPool task; the call joins before returning, so GDScript
    // can use the chunks immediately. After per-chunk generation, the cells[]
    // bytes are uploaded to chunk->rd_texture on the calling thread (the GPU
    // simulator and the chunk-render shader still consume the texture).
    void generate_chunks(
        const godot::Dictionary             &chunks,
        const godot::TypedArray<godot::Vector2i> &new_coords,
        int64_t                              world_seed,
        const godot::Ref<BiomeDef>          &biome,
        const godot::PackedByteArray        &stamp_bytes);

protected:
    static void _bind_methods();

private:
    int air_id_   = 0;
    int wood_id_  = 0;
    int stone_id_ = 0;

    void run_pipeline(Chunk *chunk, const struct StageContext &ctx) const;
};

} // namespace toprogue
```

- [ ] **Step 2: Write the implementation**

```cpp
#include "generator.h"

#include "stage_context.h"
#include "../sim/material_table.h"

#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>

using namespace godot;

namespace toprogue {

// Forward declarations of the stage free functions (defined in stages/*.cpp).
void stage_wood_fill        (Chunk *chunk, const StageContext &ctx);
void stage_biome_cave       (Chunk *chunk, const StageContext &ctx);
void stage_biome_pools      (Chunk *chunk, const StageContext &ctx);
void stage_pixel_scene_stamp(Chunk *chunk, const StageContext &ctx);
void stage_secret_ring      (Chunk *chunk, const StageContext &ctx);

Generator::Generator() {
    MaterialTable *mt = MaterialTable::get_singleton();
    air_id_   = mt ? mt->get_id("air")   : 0;
    wood_id_  = mt ? mt->get_id("wood")  : 0;
    stone_id_ = mt ? mt->get_id("stone") : 0;
}

void Generator::run_pipeline(Chunk *chunk, const StageContext &ctx) const {
    stage_wood_fill        (chunk, ctx);
    stage_biome_cave       (chunk, ctx);
    stage_biome_pools      (chunk, ctx);
    stage_pixel_scene_stamp(chunk, ctx);
    stage_secret_ring      (chunk, ctx);
}

void Generator::generate_chunks(
    const Dictionary &chunks,
    const TypedArray<Vector2i> &new_coords,
    int64_t world_seed,
    const Ref<BiomeDef> &biome,
    const PackedByteArray &stamp_bytes) {

    int n = new_coords.size();
    if (n == 0) return;

    // Per-chunk job state. Vectors so worker threads can index by job id.
    std::vector<Chunk *>     job_chunks(n);
    std::vector<StageContext> job_ctx(n);
    for (int i = 0; i < n; i++) {
        Vector2i coord = new_coords[i];
        Ref<Chunk> chunk = chunks[coord];
        if (chunk.is_null()) {
            job_chunks[i] = nullptr;
            continue;
        }
        job_chunks[i] = chunk.ptr();

        StageContext &c = job_ctx[i];
        c.chunk_coord = coord;
        c.world_seed  = uint32_t(world_seed);
        c.biome       = biome;
        c.stamp_bytes = stamp_bytes;
        c.air_id      = air_id_;
        c.wood_id     = wood_id_;
        c.stone_id    = stone_id_;
    }

    // Dispatch the per-chunk pipeline across worker threads, join here.
    WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
    int64_t group = pool->add_group_task(
        callable_mp(this, &Generator::_run_one_indexed).bind(&job_chunks, &job_ctx),
        n,
        /*tasks_needed=*/-1,   // pool default
        /*high_priority=*/true,
        "toprogue.Generator.generate_chunks");
    pool->wait_for_group_task_completion(group);

    // Main-thread tail: upload cells[] to each rd_texture so the GPU sim/
    // render shader keep seeing live data. Also set the dirty_rect / sleeping
    // flags spec §8.1 step 3 documents (no consumer reads them this step).
    RenderingDevice *rd = RenderingServer::get_singleton()->get_rendering_device();
    for (int i = 0; i < n; i++) {
        Chunk *c = job_chunks[i];
        if (!c) continue;
        // Cell layout matches R8G8B8A8_UNORM byte-for-byte (R=mat, G=health,
        // B=temp, A=flags). One memcpy via PackedByteArray view.
        PackedByteArray bytes;
        bytes.resize(Chunk::CHUNK_SIZE * Chunk::CHUNK_SIZE * 4);
        memcpy(bytes.ptrw(), c->cells_ptr(),
               Chunk::CHUNK_SIZE * Chunk::CHUNK_SIZE * sizeof(Cell));
        rd->texture_update(c->rd_texture, 0, bytes);

        c->dirty_rect = Rect2i(0, 0, Chunk::CHUNK_SIZE, Chunk::CHUNK_SIZE);
        c->sleeping = false;
    }
}

// Indexed worker entry. Bound via callable_mp + .bind() — godot-cpp pattern.
// (Method body lives next to the class; signature must match what
// add_group_task hands to the callback: a single int.)
void Generator::_run_one_indexed(int idx,
                                 std::vector<Chunk *> *jobs,
                                 std::vector<StageContext> *ctxs) {
    Chunk *c = (*jobs)[idx];
    if (!c) return;
    run_pipeline(c, (*ctxs)[idx]);
}

void Generator::_bind_methods() {
    ClassDB::bind_method(
        D_METHOD("generate_chunks", "chunks", "new_coords", "world_seed", "biome", "stamp_bytes"),
        &Generator::generate_chunks);
}

} // namespace toprogue
```

**Hidden helpers in the header.** `_run_one_indexed` is private; you'll need to declare it in `generator.h` so `callable_mp(this, &Generator::_run_one_indexed)` resolves. Add:

```cpp
private:
    void _run_one_indexed(int idx,
                          std::vector<Chunk *> *jobs,
                          std::vector<struct StageContext> *ctxs);
```

If `callable_mp + .bind()` doesn't accept raw pointer args in the pinned godot-cpp SHA, fall back to a single-call `add_group_task` that captures the vectors via a lambda by storing them in member variables (`std::vector<Chunk*> _current_jobs;` etc.) cleared at the end of `generate_chunks`. Only one generation call runs at a time (it's synchronous), so the member-state approach is safe.

**`MaterialTable::get_id` lookup keys.** The strings `"air"`, `"wood"`, `"stone"` must match what step 2 registered. Cross-check `gdextension/src/sim/material_table.cpp`'s init data. If the canonical names are different (`"AIR"`, `"MAT_AIR"`, …), use those.

- [ ] **Step 3: Build standalone**

```bash
./gdextension/build.sh debug
```

Expected: clean. Common failure modes:
- `WorkerThreadPool::add_group_task` signature on the pinned SHA — check `gdextension/godot-cpp/gen/include/godot_cpp/classes/worker_thread_pool.hpp`.
- `RenderingDevice::texture_update` arg order — also varies by SHA. Newer godot-cpp dropped the `post_barrier` arg; older expects 4 args.
- `Ref<Chunk>` from `Variant` — `chunks[coord]` returns `Variant`; godot-cpp's implicit conversion to `Ref<Chunk>` works on recent SHAs. If not, use `Ref<Chunk> chunk = Object::cast_to<Chunk>(chunks[coord]);`.

- [ ] **Step 4: Commit**

```bash
git add gdextension/src/generation/generator.{h,cpp}
git commit -m "feat: add Generator C++ class (CPU generation pipeline driver)"
```

---

## Task 4: Add `SimplexCaveGenerator` C++ class

Same shape as `Generator`. Stage list: `stone_fill → simplex_cave`. Per spec §8.2 it's currently used by some biomes only — for now, **no biome dispatches to it** in live code (today's `compute_device.gd` only loads `generation.glsl`, never `generation_simplex_cave.glsl`). We port it for completeness so the spec-listed shader can be deleted, and so the `BiomeDef` switch in task 6 has a target.

**Files:**
- Create: `gdextension/src/generation/simplex_cave_generator.h`
- Create: `gdextension/src/generation/simplex_cave_generator.cpp`

- [ ] **Step 1: Header**

Mirror `Generator` exactly, swap class name, drop the `biome`/`stamp_bytes` arguments where the simplex pipeline doesn't read them. Stages still receive a `StageContext` with biome/stamps left null/empty so the type is uniform; they no-op on null biome (`stage_simplex_cave` doesn't read biome at all).

Public entry point:

```cpp
void generate_chunks(
    const godot::Dictionary             &chunks,
    const godot::TypedArray<godot::Vector2i> &new_coords,
    int64_t                              world_seed,
    const godot::Ref<BiomeDef>          &biome,           // accepted for symmetry; can be null
    const godot::PackedByteArray        &stamp_bytes);   // accepted for symmetry; can be empty
```

Keeping the signatures identical means `chunk_manager.gd` can dispatch to either generator with the same call.

- [ ] **Step 2: Implementation**

Forward-declare `stage_stone_fill` and `stage_simplex_cave`. `run_pipeline` runs only those two. The texture-upload tail is identical to `Generator`'s.

Factor common code if it tempts you, but the bodies are short — a small amount of duplication is preferable to a shared base class for two short methods.

- [ ] **Step 3: Build, commit**

```bash
./gdextension/build.sh debug
git add gdextension/src/generation/simplex_cave_generator.{h,cpp}
git commit -m "feat: add SimplexCaveGenerator C++ class"
```

---

## Task 5: Register the new classes

**Files:**
- Modify: `gdextension/src/register_types.cpp`

- [ ] **Step 1: Add includes and `GDREGISTER_CLASS` calls**

```cpp
#include "generation/generator.h"
#include "generation/simplex_cave_generator.h"
```

In `initialize_toprogue_module`, after the step-5 collider/physics registrations:

```cpp
    GDREGISTER_CLASS(Generator);
    GDREGISTER_CLASS(SimplexCaveGenerator);
```

- [ ] **Step 2: Build and confirm clean**

```bash
./gdextension/build.sh debug
```

- [ ] **Step 3: Editor smoke**

Launch Godot 4.6 → open project. Output log:
- No errors.
- No "Class X hides a global script class" warnings (these are new classes; nothing collides).

In a scratch `_ready()`:
```gdscript
print(ClassDB.class_exists("Generator"))             # true
print(ClassDB.class_exists("SimplexCaveGenerator"))  # true
var g := Generator.new()
print(g != null)                                     # true
```

- [ ] **Step 4: Commit**

```bash
git add gdextension/src/register_types.cpp
git commit -m "feat: register Generator, SimplexCaveGenerator"
```

---

## Task 6: Migrate `chunk_manager.gd` and `world_manager.gd` to the new generators

The bridge swap. Behavior must be byte-equivalent at the *interface* level (chunks come back populated; downstream sim/collider see no shape change), even though world bytes are no longer GLSL-equivalent (per Q3).

**Files modified:**
- `src/core/chunk_manager.gd`
- `src/core/world_manager.gd`

- [ ] **Step 1: Cache a `Generator` (and `SimplexCaveGenerator`) in `WorldManager`**

In `world_manager.gd::_ready()`, alongside the `compute_device` setup:

```gdscript
var _generator: Generator
var _simplex_cave_generator: SimplexCaveGenerator

func _ready() -> void:
    # ... existing setup ...
    _generator = Generator.new()
    _simplex_cave_generator = SimplexCaveGenerator.new()
```

The `compute_device` lines that init the generation buffers (`init_gen_stamp_buffer`, `init_gen_biome_buffer`, `upload_biome_buffer`, `bind_template_arrays`) and the `advance_floor` re-init pair (`world_manager.gd` lines 264–265) become dead — the work moved into `Generator` itself. **Don't delete them yet** — task 7 step 2 excises them from `compute_device.gd` after generation is fully detached from GPU.

- [ ] **Step 2: Add a small dispatch helper on `WorldManager`**

```gdscript
func _generator_for(biome: BiomeDef) -> RefCounted:
    if biome != null and biome.use_simplex_cave_generator:
        return _simplex_cave_generator
    return _generator
```

If `BiomeDef` doesn't have a `use_simplex_cave_generator` field today: it doesn't (today nothing dispatches the simplex variant). Add the field to `BiomeDef` (`bool use_simplex_cave_generator = false`) in this commit, default false, and don't set it on any current biome `.tres`. The branch is dormant — present so the spec-listed `SimplexCaveGenerator` has a path, but the smoke playthrough exercises the `Generator` path only.

- [ ] **Step 3: Swap the two generation callsites**

In `world_manager.gd::_update_chunks` (around line 92):

```gdscript
if not new_chunks.is_empty():
    var stamp_bytes := LevelManager.build_stamp_bytes(new_chunks)
    _generator_for(LevelManager.current_biome).generate_chunks(
        chunks, new_chunks, LevelManager.world_seed,
        LevelManager.current_biome, stamp_bytes
    )
    chunks_generated.emit(new_chunks)
```

In `chunk_manager.gd::generate_chunks_at` (line 246):

```gdscript
world_manager._generator_for(LevelManager.current_biome).generate_chunks(
    chunks, new_chunks, seed_val, LevelManager.current_biome, PackedByteArray()
)
```

Note: `_get_uniform_sets_to_free` and the surrounding `rd.free_rid` loop in `world_manager._update_chunks` go away in the same edit — there are no per-dispatch RIDs to free anymore. The `_gen_uniform_sets_to_free` field on `WorldManager` becomes dead and gets removed.

- [ ] **Step 4: Build, run the editor, smoke-play**

```bash
./gdextension/build.sh debug
```

Open Godot 4.6. F5. Generate a level.

**Expected behavior:**
- A level appears (visually different from previous GPU-generated worlds — that's per Q3).
- Walking does not fall through floors.
- Digging works.
- Lava, gas, fire still simulate (GPU sim still runs).
- No editor errors.

**Common failures:**
- *Black/empty chunks:* likely the `rd->texture_update` upload didn't fire, or the byte layout disagrees with the texture format. `print` chunk's first cell after `generate_chunks` returns; it should be non-zero (wood after the wood_fill stage).
- *Crash inside `generate_chunks`:* most likely `Ref<Chunk> chunk = chunks[coord]` failed to coerce. Add a `print("coord=", coord, " chunk=", chunk.is_null())` at the top of the body.
- *Stamp rooms missing:* `RoomTemplate::image` not retained, or the `TemplatePack::get_template_at_index` lookup returned null. Trace from the stamp loop.
- *Shape clipping wrong:* `rotate_local` arg order mismatched between GLSL and C++ ports. Walk the GLSL `rotate_local` and the C++ port side by side.

- [ ] **Step 5: Run gdUnit4**

All green. Anything that compared world bytes to a golden output is expected to fail; per §9.6 we don't have such a test, but if a unit test was poking the noise function or stamp decode by hand, it may need adapting.

- [ ] **Step 6: Commit**

```bash
git add src/core/world_manager.gd src/core/chunk_manager.gd \
        gdextension/src/resources/biome_def.{h,cpp}      # if use_simplex_cave_generator added
git commit -m "refactor: dispatch chunk generation through Generator/SimplexCaveGenerator"
```

---

## Task 7: Delete the generation shaders, includes, and `ComputeDevice` plumbing

After this task lands, `comp.spv` is the only build artifact left on the generation side. The `simulation.glsl` plumbing inside `ComputeDevice` is **untouched** — that's step 7's territory.

**Files deleted:**
- `shaders/compute/generation.glsl` + `.glsl.import`
- `shaders/compute/generation_simplex_cave.glsl` + `.glsl.import`
- `shaders/include/cave_stage.glslinc`
- `shaders/include/cave_utils.glslinc`
- `shaders/include/biome_cave_stage.glslinc`
- `shaders/include/biome_pools_stage.glslinc`
- `shaders/include/pixel_scene_stamp.glslinc`
- `shaders/include/secret_ring_stage.glslinc`
- `shaders/include/simplex_2d.glslinc`
- `shaders/include/simplex_cave_stage.glslinc`
- `shaders/include/simplex_cave_utils.glslinc`
- `shaders/include/stone_fill_stage.glslinc`
- `shaders/include/wood_fill_stage.glslinc`

**Files modified:**
- `src/core/compute_device.gd` — remove every `gen_*` field, every `init_gen_*` / `upload_biome_buffer` / `bind_template_arrays` method, every `dispatch_generation` method, and the `gen_shader`/`gen_pipeline` load + teardown.
- `src/core/world_manager.gd` — remove the now-dead `compute_device.init_gen_*` / `upload_biome_buffer` / `bind_template_arrays` calls (`_ready` lines 30–34 and `advance_floor` lines 264–265 if those still call them).

- [ ] **Step 1: Pre-delete grep**

```bash
grep -rn "res://shaders/compute/generation\|\
res://shaders/include/cave_stage\|\
res://shaders/include/cave_utils\|\
res://shaders/include/biome_cave_stage\|\
res://shaders/include/biome_pools_stage\|\
res://shaders/include/pixel_scene_stamp\|\
res://shaders/include/secret_ring_stage\|\
res://shaders/include/simplex_2d\|\
res://shaders/include/simplex_cave_stage\|\
res://shaders/include/simplex_cave_utils\|\
res://shaders/include/stone_fill_stage\|\
res://shaders/include/wood_fill_stage" \
    src/ tests/ tools/ project.godot
```

Expected hits: only `compute_device.gd::init_shaders` (`load("res://shaders/compute/generation.glsl")`). Everything else is included from inside the `.glsl` files we're deleting; those references die with the files.

- [ ] **Step 2: Excise generation plumbing from `compute_device.gd`**

Delete from `src/core/compute_device.gd`:
- Field declarations: `gen_shader`, `gen_pipeline`, `gen_stamp_buffer`, `gen_stamp_uniform_set`, `gen_biome_buffer`, `gen_biome_uniform_set`, `gen_template_uniform_set`, `gen_template_array_rids`, plus the constants `STAMP_BUFFER_SIZE` and `BIOME_BUFFER_SIZE`.
- Method bodies: the generation-specific half of `init_shaders` (the `gen_file`/`gen_spirv`/`gen_shader`/`gen_pipeline` block — keep the simulation half), `init_gen_stamp_buffer`, `init_gen_biome_buffer`, `bind_template_arrays`, `_texture_array_to_rid`, `upload_biome_buffer`, `dispatch_generation`.
- Free-resources branches: every `if gen_*.is_valid(): rd.free_rid(gen_*)`. The `dummy_texture` / `sim_pipeline` / `sim_shader` `free_rid` calls **stay** — sim still runs.
- The `material_textures` and `init_material_textures` plumbing — confirm whether the chunk-render shader still consumes `material_textures`. It does (`chunk_manager.gd` lines 83, 100 set it as a shader param). **Keep `material_textures` and `init_material_textures`.** They're used by the render shader, not by generation.

After the edit, re-grep:
```bash
grep -n "gen_shader\|gen_pipeline\|gen_stamp\|gen_biome\|gen_template\|dispatch_generation\|upload_biome_buffer\|init_gen_\|bind_template_arrays" src/core/compute_device.gd
```
Expected: zero hits.

- [ ] **Step 3: Excise dead calls from `world_manager.gd`**

Remove `compute_device.init_gen_stamp_buffer()`, `init_gen_biome_buffer()`, `upload_biome_buffer(...)`, `bind_template_arrays(...)` from `_ready` and `advance_floor` (or wherever else they appear). Re-grep:

```bash
grep -n "init_gen_stamp_buffer\|init_gen_biome_buffer\|upload_biome_buffer\|bind_template_arrays" src/
```
Expected: zero hits.

- [ ] **Step 4: Delete the shader files**

```bash
rm shaders/compute/generation.glsl              shaders/compute/generation.glsl.import
rm shaders/compute/generation_simplex_cave.glsl shaders/compute/generation_simplex_cave.glsl.import
rm shaders/include/cave_stage.glslinc
rm shaders/include/cave_utils.glslinc
rm shaders/include/biome_cave_stage.glslinc
rm shaders/include/biome_pools_stage.glslinc
rm shaders/include/pixel_scene_stamp.glslinc
rm shaders/include/secret_ring_stage.glslinc
rm shaders/include/simplex_2d.glslinc
rm shaders/include/simplex_cave_stage.glslinc
rm shaders/include/simplex_cave_utils.glslinc
rm shaders/include/stone_fill_stage.glslinc
rm shaders/include/wood_fill_stage.glslinc
```

- [ ] **Step 5: Confirm zero stale references**

```bash
grep -rn "shaders/compute/generation\|\
shaders/include/cave_stage\|\
shaders/include/cave_utils\|\
shaders/include/biome_cave_stage\|\
shaders/include/biome_pools_stage\|\
shaders/include/pixel_scene_stamp\|\
shaders/include/secret_ring_stage\|\
shaders/include/simplex_2d\|\
shaders/include/simplex_cave_stage\|\
shaders/include/simplex_cave_utils\|\
shaders/include/stone_fill_stage\|\
shaders/include/wood_fill_stage" .
```

Expected: zero hits. If a `.tscn` or any other file still references one of these paths, fix it before committing.

- [ ] **Step 6: Open the editor and confirm a clean load**

Launch Godot 4.6 → open project. Output log:
- No "could not parse script `compute_device.gd`" errors.
- No "Failed to load resource: `res://shaders/compute/generation.glsl`" errors (the load call is gone).
- No errors about missing `.glsl.import` files (the import system is fine with files that no longer exist if no resource references them).

F5 → walk for ~10 seconds → quit.

- [ ] **Step 7: Commit**

```bash
git add src/ shaders/
git commit -m "refactor: delete generation shaders, includes, and ComputeDevice generation plumbing"
```

---

## Task 8: Final verification

- [ ] **Step 1: Final greps — generation shaders gone**

```bash
ls shaders/compute/generation*.glsl* 2>&1
ls shaders/include/{cave_stage,cave_utils,biome_cave_stage,biome_pools_stage,pixel_scene_stamp,secret_ring_stage,simplex_2d,simplex_cave_stage,simplex_cave_utils,stone_fill_stage,wood_fill_stage}.glslinc 2>&1
```
Expected: "No such file or directory" for all.

```bash
ls shaders/compute/
ls shaders/include/
```
Expected: only `simulation.glsl` (+ `.import`) in `compute/`; only the `sim/` subdirectory in `include/`. Step 7 deletes the rest.

- [ ] **Step 2: Final greps — `ComputeDevice` generation plumbing gone**

```bash
grep -rn "dispatch_generation\|init_gen_stamp_buffer\|init_gen_biome_buffer\|upload_biome_buffer\|bind_template_arrays\|gen_stamp_buffer\|gen_biome_buffer\|gen_template_uniform_set\|gen_template_array_rids\|gen_shader\|gen_pipeline\|res://shaders/compute/generation" \
    src/ tests/ tools/ project.godot \
    > /tmp/step6-inventory-after.txt
diff /tmp/step6-inventory-before.txt /tmp/step6-inventory-after.txt | head -60
cat /tmp/step6-inventory-after.txt
```

Expected: `step6-inventory-after.txt` is empty. If any line remains, it's a missed delete — track it down.

- [ ] **Step 3: Confirm the build still produces the binary**

```bash
./gdextension/build.sh debug
ls -la bin/lib/
```

- [ ] **Step 4: Open the editor and run gdUnit4**

Launch Godot 4.6 → Output log clean → run gdUnit4 → all green.

- [ ] **Step 5: Smoke playthrough (~2 min, per spec §10.2)**

Launch → generate a large level → walk through it for ~2 minutes. Specifically exercise:
- **Generation visual sanity.** Caves are caves. Background material (wood for biomes that use it) shows. Stamps (rooms) appear on the map. Secret rings appear around secret rooms.
- **Collisions still work.** Step 5's `TerrainCollisionHelper` reads `chunk->rd_texture` via the existing readback, sees the new CPU-generated bytes, builds the same shape pipeline.
- **Sim still works.** Lava flows. Gas drifts. Fire ignites flammables. The sim shader reads `chunk->rd_texture`; the texture was just `texture_update`d from the CPU `cells[]` at end-of-generate, so the simulator sees a consistent world.
- **Digging works.** `terrain_modifier.gd` writes to `chunk->rd_texture` (via the existing GPU path); rebuilds collision; queries `TerrainPhysical`.
- **Floor advance works.** Walk to the portal → next floor → confirm `_generator_for(LevelManager.current_biome)` picks the right generator and a fresh level appears.

No crashes, no visible deadlocks, no frame stutters > 1s.

If frame time spikes at chunk boundaries: `WorkerThreadPool::add_group_task` may be running with too few worker threads (or the tail-upload `texture_update` is blocking). Profile with the Godot debugger; if it's the upload, batch into a single `texture_update_multi` if godot-cpp exposes one; otherwise leave it (per spec §10.1 risk #4, batching is out of scope — but flag it for follow-up if the spike is > 100ms).

- [ ] **Step 6: Format C++ sources**

```bash
./gdextension/format.sh
git diff gdextension/src/
```

If the formatter changed anything:
```bash
git add gdextension/src/
git commit -m "chore: clang-format generation sources"
```

- [ ] **Step 7: Push the branch**

```bash
git push origin refactor/cpp
```

- [ ] **Step 8: Cross-machine verification**

On the other machine:

```bash
git pull
git submodule update --init --recursive
./gdextension/build.sh debug
```

Open the project in Godot 4.6 → Output log clean → smoke-test as in Step 5.

If the level looks structurally different between machines (e.g. cave shapes don't match), that's *expected* — per spec §6.8 cross-machine determinism is not a goal. The bar is "the level generates and plays correctly," not "byte-equal across machines."

If the level is broken on the second machine in ways that aren't visible noise differences (crash, missing rooms, infinite floors), fix and commit before declaring step 6 done.

---

## Done Definition for Step 6

- `gdextension/src/util/simplex.{h,cpp}` exists.
- `gdextension/src/generation/{generator,simplex_cave_generator}.{h,cpp}` exist and compile clean on macOS and Arch.
- Each `.glslinc` stage has a corresponding `gdextension/src/generation/stages/*.cpp` free function.
- `Generator` and `SimplexCaveGenerator` are registered as native classes; `Generator.new()` and `SimplexCaveGenerator.new()` work from GDScript.
- `Generator::generate_chunks` runs the per-chunk pipeline through `WorkerThreadPool::add_group_task`, joins, and uploads each chunk's `cells[]` to its `rd_texture` so the GPU sim and chunk-render shader keep working.
- `chunk_manager.gd` and `world_manager.gd` dispatch generation through `_generator_for(biome).generate_chunks(...)` instead of `compute_device.dispatch_generation(...)`.
- `compute_device.gd` no longer declares or initializes any `gen_*` field, no longer loads `generation.glsl`, no longer exposes `dispatch_generation`/`upload_biome_buffer`/`bind_template_arrays`/`init_gen_*`. The simulation half is untouched.
- `shaders/compute/generation.glsl` and `generation_simplex_cave.glsl` (+ `.import`) are deleted.
- All eleven `.glslinc` files listed in the spec's step-6 deletion list are deleted (`cave_stage`, `cave_utils`, `biome_cave_stage`, `biome_pools_stage`, `pixel_scene_stamp`, `secret_ring_stage`, `simplex_2d`, `simplex_cave_stage`, `simplex_cave_utils`, `stone_fill_stage`, `wood_fill_stage`).
- `shaders/compute/` contains only `simulation.glsl` (+ `.import`); `shaders/include/` contains only the `sim/` subdirectory (deleted in step 7).
- Zero stale `res://shaders/compute/generation` or `res://shaders/include/<deleted>` references remain.
- Behavior is preserved at the interface level: levels generate, look like levels, walk fine, dig fine, sim fine, collide fine. World bytes differ from pre-step-6 GPU-generated worlds (per Q3).
- `gdUnit4` suite passes on both machines.
- Smoke playthrough passes on both machines.

When all of the above are true, Step 6 is complete. Proceed to write the plan for **Step 7 — `Simulator` + `ChunkManager` + `WorldManager` + `TerrainModifier`** per spec §6 (the load-bearing cellular-sim section), §8.4–§8.6, and §9.1 step 7. The relevant predecessor C++ source for that plan is `gdextension/src/generation/generator.cpp` (the `WorkerThreadPool::add_group_task` per-chunk dispatch pattern that `Simulator::tick`'s 4-phase scheduler reuses) and `gdextension/src/terrain/chunk.{h,cpp}` (the `dirty_rect`/`sleeping`/`neighbors[4]`/`Ref<ImageTexture>` storage that step 7 finally activates). Step 7 is the largest of the migration steps; budget review time accordingly.
