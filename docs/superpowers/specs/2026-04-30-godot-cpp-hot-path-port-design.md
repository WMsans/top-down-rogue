# Compute-Shader Removal & CPU Hot-Path Port to godot-cpp — Design Spec

**Date:** 2026-04-30
**Status:** Approved (pending user review of this written form)
**Branch:** refactor/cpp (port work lands in per-step PRs against this branch)

## 1. Goal

**Eliminate every compute shader in the project.** All logic currently expressed in GLSL — terrain generation, simplex cave generation, per-frame cellular simulation, collider build — is reimplemented in **CPU C++** via godot-cpp. After this refactor, the project contains zero compute shaders, zero `RenderingDevice` calls, zero push-constant structs, and no `shaders/compute/`, `shaders/include/`, or `shaders/generated/` directories.

The hot-path GDScript that orchestrates today's compute pipeline (`compute_device.gd`, `chunk_manager.gd`, `world_manager.gd`, `terrain_modifier.gd`, `terrain_collider.gd`, `gas_injector.gd`, `terrain_collision_helper.gd`, `terrain_physical.gd`, `chunk.gd`, `sector_grid.gd`, `generation_context.gd`) is also ported to C++, since it loses its purpose without the GPU pipeline. Resources used by these classes (`TerrainCell`, `BiomeDef`, `PoolDef`, `RoomTemplate`, `TemplatePack`) are ported to C++ `Resource` subclasses.

Gameplay GDScript (UI, console, economy, drops, weapons, enemies, autoloads, juice, `spawn_dispatcher`, etc.) stays in GDScript and calls into the C++ classes by their existing names.

## 2. Why CPU, not GPU

Three drivers, all real:

1. **Eliminates GPU readback round-trip.** Today's pipeline does compute → `buffer_get_data` → CPU consume. Readback latency on Godot's RD path is often the dominant cost — not the compute itself. CPU sim consumes results in-place, no readback.
2. **Debuggability.** Native debugger on every cell of the sim. Today, debugging GLSL is print-shader-output and pray.
3. **Determinism + flexibility.** No GPU vendor differences in float ordering. Material rules can branch arbitrarily without GLSL's "every thread takes every branch" cost. New gameplay-coupled simulation behaviors land as plain C++.

Reference architecture: Petri Purho / Nolla's *Falling Everything* engine (Noita), GDC 2019. Chunked grid, per-frame cellular update, dirty rects, sleeping chunks, 4-phase checkerboard chunk scheduling so non-adjacent chunks update on parallel threads without locks. This refactor adopts that design.

## 3. Scope

### 3.1 Removed

- `shaders/compute/` (4 GLSL files, 283 LOC) — entire directory.
- `shaders/include/` (16 `.glslinc` files, ~1400 LOC) — entire directory.
- `shaders/generated/` (codegen output) — entire directory.
- `generate_materials.sh` — codegen script.
- `comp.spv` — stale build artifact in project root.
- `src/core/compute_device.gd` — no callers after the port.
- `src/autoload/material_registry.gd` — replaced by C++ `MaterialTable`.
- `src/terrain/world_preview.gd` (+ `.uid`) and any preview-mode wiring (autoload entries, scene refs, console commands). Feature is dead.

### 3.2 Ported to C++ (godot-cpp)

| File | Becomes | Base |
|---|---|---|
| `src/core/chunk.gd` | `Chunk` | `RefCounted` |
| `src/core/sector_grid.gd` | `SectorGrid` | `RefCounted` |
| `src/core/chunk_manager.gd` | `ChunkManager` | `RefCounted` |
| `src/core/terrain_modifier.gd` | `TerrainModifier` | `RefCounted` |
| `src/core/terrain_collision_helper.gd` | `TerrainCollisionHelper` | `RefCounted` |
| `src/core/terrain_physical.gd` | `TerrainPhysical` | `Node` |
| `src/core/world_manager.gd` | `WorldManager` | `Node2D` |
| `src/physics/terrain_collider.gd` | `TerrainCollider` | (base TBD on read at port time) |
| `src/physics/gas_injector.gd` | `GasInjector` | `Node` |
| `src/terrain/generation_context.gd` | `GenerationContext` | `RefCounted` |
| `src/core/terrain_cell.gd` | `TerrainCell` | `Resource` |
| `src/core/biome_def.gd` | `BiomeDef` | `Resource` |
| `src/core/pool_def.gd` | `PoolDef` | `Resource` |
| `src/core/room_template.gd` | `RoomTemplate` | `Resource` |
| `src/core/template_pack.gd` | `TemplatePack` | `Resource` |

New C++ classes (no GDScript predecessor):

- `Simulator` (`RefCounted`) — per-frame cellular sim driver.
- `Generator` (`RefCounted`) — replaces `generation.glsl` + stage includes.
- `SimplexCaveGenerator` (`RefCounted`) — replaces `generation_simplex_cave.glsl` + its includes.
- `ColliderBuilder` (`RefCounted`) — replaces `collider.glsl`.
- `MaterialTable` (`Object`, engine singleton) — replaces `materials.glslinc` + `material_registry.gd`.

Class names of ported classes are preserved so existing `.tscn` and GDScript references resolve transparently.

### 3.3 Untouched (stays GDScript)

All UI under `src/ui/` and `src/economy/`. All gameplay: `src/weapons/`, `src/enemies/`, `src/drops/`, `src/player/`. `src/core/spawn_dispatcher.gd` (event-driven, not per-frame). `src/core/juice/`. All autoloads other than `material_registry.gd`. `src/utils/`, `src/console/`, `src/debug/`, `src/portal.gd`. The non-compute chunk-rendering shader the project already uses.

### 3.4 Explicit non-goals

- No new public methods, signals, or properties on ported classes. Internal helpers may be added freely.
- No new gameplay materials or rules — port preserves today's set, no additions.
- No bit-exact parity with previous GLSL output (Q3 = deterministic CPU output, no GLSL parity).
- No cross-machine determinism (would require single-threaded sim).
- No CI / GitHub Actions.
- No Windows target.
- No SPIR-V prebuild, no `.glslinc` cleanup (the files are being deleted).
- No rendering changes; chunk-rendering material/shader untouched.
- No port of non-hot-path GDScript.
- No performance benchmarking harness; profile after the simulator step lands.

## 4. Architecture

```
WorldManager (Node2D, C++)
  ├─ ChunkManager (RefCounted, C++)         streaming, activation, lifecycle
  │    └─ SectorGrid (RefCounted, C++)      Vector2i → Ref<Chunk>
  ├─ Simulator (RefCounted, C++)            per-frame cellular sim driver
  │    ├─ DirtyRect tracker (per chunk)
  │    ├─ Sleep tracker (per chunk)
  │    └─ 4-phase chunk scheduler
  ├─ Generator + SimplexCaveGenerator (RefCounted, C++)
  ├─ ColliderBuilder (RefCounted, C++)      chunk → collision shapes
  └─ MaterialTable (Object singleton, C++)  static material data
```

Threading: `WorkerThreadPool::add_group_task` for the per-phase chunk batch. Within a phase, all scheduled chunks run on parallel threads with no locks; the 4-phase checkerboard guarantees no two parallel chunks read each other's interior. Generation and collider builds dispatch per-chunk jobs the same way.

GDScript ↔ C++ interop uses the standard Variant call path. Hot loops live entirely inside C++; the boundary is crossed at most once per frame per subsystem (signal-emission for "chunk ready," etc.).

### 4.1 Layout

```
top-down-rogue/
├── gdextension/
│   ├── godot-cpp/                          git submodule, pinned
│   ├── src/
│   │   ├── register_types.{h,cpp}
│   │   ├── sim/
│   │   │   ├── simulator.{h,cpp}
│   │   │   ├── material_table.{h,cpp}
│   │   │   ├── sim_context.{h,cpp}
│   │   │   └── rules/
│   │   │       ├── lava.cpp
│   │   │       ├── gas.cpp
│   │   │       ├── burning.cpp
│   │   │       └── injection.cpp
│   │   ├── generation/
│   │   │   ├── generator.{h,cpp}
│   │   │   ├── simplex_cave_generator.{h,cpp}
│   │   │   └── stages/
│   │   │       ├── cave_stage.cpp
│   │   │       ├── biome_cave_stage.cpp
│   │   │       ├── biome_pools_stage.cpp
│   │   │       ├── stone_fill_stage.cpp
│   │   │       ├── wood_fill_stage.cpp
│   │   │       ├── pixel_scene_stamp.cpp
│   │   │       ├── secret_ring_stage.cpp
│   │   │       ├── simplex_cave_stage.cpp
│   │   │       └── simplex_cave_utils.cpp
│   │   ├── terrain/
│   │   │   ├── chunk.{h,cpp}
│   │   │   ├── sector_grid.{h,cpp}
│   │   │   ├── chunk_manager.{h,cpp}
│   │   │   ├── terrain_modifier.{h,cpp}
│   │   │   ├── terrain_collision_helper.{h,cpp}
│   │   │   ├── terrain_physical.{h,cpp}
│   │   │   ├── generation_context.{h,cpp}
│   │   │   └── world_manager.{h,cpp}
│   │   ├── physics/
│   │   │   ├── terrain_collider.{h,cpp}
│   │   │   ├── gas_injector.{h,cpp}
│   │   │   └── collider_builder.{h,cpp}
│   │   ├── resources/
│   │   │   ├── terrain_cell.{h,cpp}
│   │   │   ├── biome_def.{h,cpp}
│   │   │   ├── pool_def.{h,cpp}
│   │   │   ├── room_template.{h,cpp}
│   │   │   └── template_pack.{h,cpp}
│   │   └── util/
│   │       └── simplex.{h,cpp}             noise, replaces simplex_2d.glslinc
│   ├── SConstruct
│   ├── build.sh                            platform-detecting wrapper
│   ├── format.sh                           clang-format -i over src/
│   └── .clang-format                       copied from godot-cpp
├── bin/
│   └── toprogue.gdextension                entry symbol + per-platform binary paths
└── tools/
    └── migrate_tres.py                     one-shot rewrite of script-backed .tres
```

`bin/lib/` is gitignored; each machine builds locally.

## 5. Build System & Toolchain

### 5.1 Targets

Two platforms only:
- **macOS** — Apple clang, arm64 (x86_64 if Intel; auto-detected via `uname -m`).
- **Arch Linux** — system clang or gcc (SCons honors `CXX`, defaults to gcc on Arch), x86_64.

Windows entries omitted from the `.gdextension` manifest.

### 5.2 Per-machine prerequisites

- macOS: Xcode CLT (`xcode-select --install`), Python 3, `pip install scons`.
- Arch: `sudo pacman -S base-devel scons python` (clang optional).

### 5.3 Pins

godot-cpp pinned to commit `973a98f9b877327a5f51abe58e035bf7eeabf3e4` (master branch as of bootstrap). Submodule SHA recorded in this repo at `gdextension/godot-cpp`. Godot editor pinned to 4.6. C++17.

### 5.4 Wrapper `gdextension/build.sh`

- Detects platform via `uname -s`, arch via `uname -m`, jobs via `sysctl -n hw.ncpu` (mac) / `nproc` (Linux).
- Subcommands: `debug`, `release`, `clean`, `both`.
- Logs `cc/clang/scons/python` versions at the top of every build.
- Debug: `target=template_debug dev_build=yes debug_symbols=yes` (`-O0`/`-Og`, assertions on).
- Release: `target=template_release debug_symbols=yes` (still profileable).
- Each invocation only writes to its own platform's output path.

### 5.5 Output layout

- `bin/lib/libtoprogue.macos.template_{debug,release}.{arm64,x86_64}.dylib`
- `bin/lib/libtoprogue.linux.template_{debug,release}.x86_64.so`

`bin/toprogue.gdextension` declares entry symbol, `compatibility_minimum = "4.6"`, and entries for both platforms.

### 5.6 Git

- `.gitignore` adds: `bin/lib/`, `gdextension/godot-cpp/bin/`, `gdextension/godot-cpp/gen/`, `*.o`, `*.os`, `.sconsign.dblite`, SCons cache dirs.
- godot-cpp is a submodule; cloners run `git submodule update --init --recursive`.

### 5.7 Editor reload

Restart the editor for verification runs — don't trust hot-reload for the sim, since live-reloading a class with a running per-frame `WorkerThreadPool` job has obvious failure modes. Hot-reload remains useful as dev convenience between verification runs.

### 5.8 Formatting

`gdextension/.clang-format` copied from godot-cpp; `gdextension/format.sh` runs `clang-format -i` over `gdextension/src/`. No CI enforcement.

## 6. Cellular Simulation (load-bearing section)

### 6.1 Data layout

```cpp
struct Cell {
    uint8_t material;     // index into MaterialTable
    uint8_t health;       // 0..255
    uint8_t temperature;  // 0..255
    uint8_t flags;        // bit 0: moved-this-frame, bit 1: ignited, etc.
};
static_assert(sizeof(Cell) == 4);

class Chunk : public RefCounted {
    static constexpr int CHUNK_SIZE = 256;   // matches today's GLSL constant
    Cell cells[CHUNK_SIZE * CHUNK_SIZE];
    Rect2i dirty_rect;
    Rect2i next_dirty_rect;                  // accumulated during the tick
    bool sleeping = true;
    bool collider_dirty = false;
    Vector2i coord;
    Chunk* neighbors[4] = {nullptr};         // up/down/left/right; null at world edge
    Ref<ImageTexture> texture;               // mirrors cells[] for rendering
};
```

Cell access is a flat pointer index. Neighbor access reads through `neighbors[]`. No images, textures, or RDs in the sim path.

### 6.2 4-phase chunk-checkerboard scheduling

Each frame, `Simulator::tick()` runs the active-chunk set in 4 phases by `(coord.x & 1, coord.y & 1)`:

```
Phase 0: (even, even)
Phase 1: (odd,  even)
Phase 2: (even, odd)
Phase 3: (odd,  odd)
```

Within a phase, no two scheduled chunks are adjacent — so each chunk's update can read/write its own cells *and* read its neighbors' cells without locks. `WorkerThreadPool::add_group_task` dispatches all chunks in the current phase, joins, advances to the next phase. Four sync points per frame; the work between them is fully parallel.

This is the parallelism guarantee. Without it, locking would dominate. With it, locks are unnecessary by construction.

### 6.3 Per-chunk update

For each scheduled chunk, the worker:

1. If `sleeping`, return immediately.
2. Iterate cells inside `dirty_rect` only. For each cell:
   - Read material → dispatch to material rule (`update_lava`, `update_gas`, `update_burning`, …).
   - Rule may write to this chunk *or* a neighbor chunk. Cross-chunk writes extend the target's `next_dirty_rect` via lock-free atomic min/max on the rect bounds (no mutex — see 6.4).
3. Cells that move set their own and the destination cell's `flags |= moved`.
4. After iteration: shrink `next_dirty_rect` to bounding box of cells with `moved` set. Empty → `sleeping = true`. Otherwise `dirty_rect = next_dirty_rect`, clear `next_dirty_rect`.
5. Clear `moved` flags for next frame.

### 6.4 Cross-chunk write safety

Within a phase, since scheduled chunks are non-adjacent, only one writing thread can touch any given target chunk per phase. `next_dirty_rect`'s four `int32_t` bounds are extended via `std::atomic` compare-exchange min/max. No mutex anywhere in the sim path.

### 6.5 Wake conditions

A sleeping chunk wakes when:
- An injection (rigidbody push, weapon effect, gas emitter) writes into it.
- A neighbor chunk's update writes a cell into it (lava flowing across the border, etc.).
- The player digs into it via `TerrainModifier`.

Each writer atomically clears `sleeping` on the target and extends its `next_dirty_rect`.

### 6.6 Material rules

One translation unit per rule under `gdextension/src/sim/rules/`. Function shape:

```cpp
// returns true if this cell is fully processed for the frame
bool update_lava(SimContext& ctx, Cell& cell, Vector2i pos);
```

`SimContext` holds: pointer to current chunk, neighbor pointers, frame seed, RNG helpers, write-cell helper that handles cross-chunk routing + dirty-rect accumulation. Rules never touch chunk internals directly — they go through `SimContext`. This is the single boundary where cross-chunk safety is enforced.

Stochastic decisions use `hash(pos.x ^ hash(pos.y ^ frame_seed ^ salt))` — same shape as today's GLSL `stochastic_div`. Determinism preserved per `(seed, frame_index)` on a single machine.

### 6.7 No double-buffering

Mutate the grid in place. Noita doesn't double-buffer; the dirty-rect + checkerboard phases bound visible artifacts. Double buffering would double memory and cost a copy per frame for no behavioral gain.

### 6.8 Determinism

Per `(initial seed, frame count, input event sequence)`, output is bit-stable on a single machine. Cross-machine determinism is not promised — different `WorkerThreadPool` job-completion ordering can change which neighbor write lands first when two chunks both write into a third. If cross-machine determinism is ever needed (replays, networking), single-thread the sim — out of scope here.

### 6.9 Frame budget

At 60Hz, 16ms total. Active world is bounded near the player by `ChunkManager`. Sleep + dirty rect should keep typical-case work to a small fraction of the active set. No specific budget guarantee in this spec — measured during verification (§9). If budget busts, see risk #1 in §9.

## 7. Materials

The C++ material table replaces both `shaders/generated/materials.glslinc` and `src/autoload/material_registry.gd`. Single source of truth, no codegen.

### 7.1 Definition

```cpp
enum class MaterialKind : uint8_t {
    SOLID, POWDER, LIQUID, GAS, FIRE, NONE
};

struct MaterialDef {
    StringName name;
    Color      color;
    MaterialKind kind;
    bool       flammable;
    uint8_t    ignition_temp;
    uint8_t    burn_rate;
    uint8_t    max_health;
    // ... full set lifted from current materials.glslinc + material_registry.gd
};

class MaterialTable : public Object {
    GDCLASS(MaterialTable, Object);
    static MaterialTable* singleton;
    Vector<MaterialDef> defs;          // index = material id (uint8_t)
    HashMap<StringName, uint8_t> by_name;
public:
    static MaterialTable* get_singleton();
    uint8_t            id_of(const StringName& name) const;
    const MaterialDef& def(uint8_t id) const;
    // Bound to GDScript:
    int   get_id(StringName name) const;
    Color get_color(int id) const;
    bool  is_flammable(int id) const;
    // ... thin getters for every field GDScript currently reads
};
```

Populated once at extension init from a hardcoded C++ array literal. New materials added by editing this file; no `.tres`, no codegen.

### 7.2 Why hardcoded C++

Materials are referenced by integer index from inside the simulation hot loop, every cell, every frame. `.tres` lookups would force Variant indirection per cell read. C++ `Vector<MaterialDef>` is pointer + index — what the inner loop wants. Designer ergonomics doesn't apply: materials are stable game-design entities, not designer-tweaked content.

### 7.3 GDScript access

Registered as engine singleton via `Engine::register_singleton`. GDScript reads as `MaterialTable.get_id("lava")`, identical surface to today's `MaterialRegistry.get_id("lava")`. A grep-and-replace of `MaterialRegistry` → `MaterialTable` is part of the materials port commit.

### 7.4 Init order

`register_types.cpp` registers `MaterialTable` first, populates it during `MODULE_INITIALIZATION_LEVEL_SCENE`, then registers everything else. By the time any `Chunk` or `Simulator` instance can exist, the table is populated.

### 7.5 Material-id stability

If any existing `.tres` references a material by integer id, that id must remain stable across the port. Mitigation: enumerate `MaterialRegistry` once before deletion, lock that order in the C++ array literal. Code-comment that the order is load-bearing.

## 8. Generation, Collider, Rendering Bridge

### 8.1 `Generator` (`RefCounted`)

Replaces `generation.glsl` + `cave_stage`, `cave_utils`, `biome_cave_stage`, `biome_pools_stage`, `pixel_scene_stamp`, `secret_ring_stage`, `stone_fill_stage`, `wood_fill_stage`.

Per-chunk job dispatched via `WorkerThreadPool::add_task` from `ChunkManager::request_chunk(coord, biome)`. Job:

1. Allocate a fresh `Chunk` (256×256 cells).
2. Run stage pipeline in order: cave carve → biome cave → biome pools → stone fill → wood fill → pixel-scene stamps → secret rings. Same order today's GLSL chains the includes.
3. Set `dirty_rect` to full chunk and `sleeping = false` so the simulator picks up the freshly-generated chunk on its first tick.
4. Return the `Chunk` via signal back on the main thread.

Each stage is a free function in `gdextension/src/generation/stages/*.cpp`, taking `(Chunk*, GenerationContext*, Rng&)`. Stage organization mirrors the `.glslinc` file split 1:1 so each stage can be ported and verified individually.

Noise: `simplex_2d.glslinc` becomes `gdextension/src/util/simplex.{h,cpp}`.

### 8.2 `SimplexCaveGenerator` (`RefCounted`)

Replaces `generation_simplex_cave.glsl` + `simplex_cave_stage` + `simplex_cave_utils`. Same shape as `Generator`, different stage list. Currently used by some biomes only — the dispatch decision (`Generator` vs. `SimplexCaveGenerator`) lives in `BiomeDef`/`ChunkManager` and stays there.

### 8.3 `ColliderBuilder` (`RefCounted`)

Replaces `collider.glsl`. Walks a chunk's solid-cell mask and produces collision polygons / segments for `TerrainCollider`. Per-chunk job dispatched the same way as generation. Output: list of `PackedVector2Array` polygons; consumed by `TerrainCollider::rebuild_chunk_shapes(coord, polys)`.

Trigger: `Chunk::collider_dirty` flag, set by `TerrainModifier` when solid mask changes.

### 8.4 Rendering bridge — `Chunk::upload_texture()`

Each chunk owns a `Ref<ImageTexture>` whose pixels mirror `cells[]`. After a phase finishes, dirty chunks call `upload_texture()` on the main thread (godot-cpp `Texture2D` updates aren't thread-safe). Implementation: build a `PackedByteArray` view over the dirty rect, `Image::create_from_data`, `ImageTexture::update`. Only the `dirty_rect` portion uploads.

The texture feeds the existing chunk-rendering material/shader (non-compute, untouched).

### 8.5 `TerrainModifier` post-port

Now: edit `Chunk.cells[]` directly, flag `dirty_rect`, flag `collider_dirty`. Smaller and simpler than today's compute-dispatch version.

### 8.6 `GasInjector` post-port

Pushes injection AABBs onto a per-chunk injection queue (replacing the GLSL injection buffer). Consumed by `Simulator` at the start of each tick.

### 8.7 `TerrainCollisionHelper`

Pure CPU query helper, no shader involvement today. Trivial port.

## 9. Migration Plan

Sequential, leaves-first, no runtime toggle. Each step is one PR. After each, the game must launch, generate, simulate, and play.

### 9.1 Step order

1. **Bootstrap.** `gdextension/` skeleton, godot-cpp submodule, `SConstruct`, `build.sh`, empty `register_types.cpp`, `bin/toprogue.gdextension`, `.gitignore`. No GDScript / shader changes. Builds clean on macOS + Arch.

2. **`MaterialTable`.** C++ class + hardcoded material array literal (data lifted from `material_registry.gd`, ordered to match its output). Register as engine singleton. Replace every `MaterialRegistry.X` call in GDScript with `MaterialTable.X`. Remove `MaterialRegistry` autoload from `project.godot`. Delete `src/autoload/material_registry.gd`. (`shaders/generated/materials.glslinc` and `generate_materials.sh` survive temporarily — GLSL still uses them — and are deleted in step 7.)

3. **Resources.** `TerrainCell`, `BiomeDef`, `PoolDef`, `RoomTemplate`, `TemplatePack` ported. `tools/migrate_tres.py` rewrites each resource's `.tres` files from script-backed (`script_class="..."` + `[ext_resource type="Script" ...]` + `script = ExtResource(...)`) to native-class (`type="BiomeDef"` etc.) form. Verify by opening representative `.tres` files in the editor.

4. **Leaves.** `Chunk`, `SectorGrid`, `GenerationContext` ported. `Chunk` holds `Cell cells[]` + `dirty_rect` + `sleeping` directly. Existing GDScript reads through bound C++ getters. **The compute pipeline still runs at this step** — `ComputeDevice` (still GDScript) writes into the cell array via the texture readback path it already uses. Bridge step.

5. **`ColliderBuilder` + `TerrainCollider` + `TerrainCollisionHelper` + `GasInjector` + `TerrainPhysical`.** Collider + physics ported. `ColliderBuilder` replaces `collider.glsl` — first compute shader gone. Delete `shaders/compute/collider.glsl` + `.glsl.import`.

6. **`Generator` + `SimplexCaveGenerator`.** Replaces `generation.glsl` and `generation_simplex_cave.glsl` plus stage includes. `ChunkManager` (still GDScript) calls `Generator::generate_async(coord, biome)` instead of dispatching the compute pipeline. Delete:
   - `shaders/compute/generation.glsl`, `generation_simplex_cave.glsl`
   - `shaders/include/cave_stage.glslinc`, `cave_utils.glslinc`, `biome_cave_stage.glslinc`, `biome_pools_stage.glslinc`, `pixel_scene_stamp.glslinc`, `secret_ring_stage.glslinc`, `simplex_2d.glslinc`, `simplex_cave_stage.glslinc`, `simplex_cave_utils.glslinc`, `stone_fill_stage.glslinc`, `wood_fill_stage.glslinc`

7. **`Simulator` + `ChunkManager` + `WorldManager` + `TerrainModifier`.** The big step. Cellular sim ported with full Noita treatment (4-phase checkerboard, dirty rects, sleeping). At this point delete:
   - `shaders/compute/simulation.glsl`
   - `shaders/include/sim/` (entire directory)
   - `shaders/generated/` (entire directory, including `materials.glslinc`)
   - `generate_materials.sh`
   - `src/core/compute_device.gd`
   - `comp.spv` (project root)

8. **Cleanup.** Delete `world_preview.gd` + `.uid` + preview wiring. Confirm `shaders/compute/` and `shaders/include/` are empty; remove the directories. Final grep for `RenderingDevice`, `RDShaderFile`, `compute_list`, `push_constant` to confirm zero hits in `src/` and `gdextension/src/`.

### 9.2 Why this order

- `MaterialTable` first: every later step references material ids; locking the table early prevents drift.
- Resources before leaves: `BiomeDef`/`PoolDef` exist as C++ types before `Generator` consumes them.
- `Chunk` before any consumer: every other class touches cells.
- Collider before generator: simpler, exercises the per-chunk job pipeline once before the generator uses the same machinery.
- Generator before simulator: a freshly generated chunk has to exist before the sim has anything to tick; landing them together would conflate two regression surfaces.
- Simulator last: highest risk; depends on all of the above being stable.

### 9.3 `.tres` migration mechanics

Before:
```
[gd_resource type="Resource" script_class="BiomeDef" load_steps=2 format=3]
[ext_resource type="Script" path="res://src/core/biome_def.gd" id="..."]
...
script = ExtResource("...")
```

After:
```
[gd_resource type="BiomeDef" load_steps=1 format=3]
...
```

`tools/migrate_tres.py` does this rewrite per-resource-class. Hand-verify on 1–2 representative `.tres` files and open them in the editor before bulk-running.

### 9.4 `.uid` and reference cleanup

Per-port checklist greps for the deleted `.gd`'s `res://...gd` path and its `.uid` string before deletion. Stragglers fixed in the same commit.

### 9.5 Test contract

`gdUnit4` suite passes at every step. Tests don't change unless they were poking at a private GDScript field that got ported away — those adapt to the public surface in the same step.

### 9.6 No GLSL parity test

Per Q3, deterministic CPU output without GLSL parity. No golden-output regression file. Verification is "the level generates and plays correctly," not "byte-equal to previous GLSL output."

## 10. Risks & Verification

### 10.1 Risks

1. **Per-frame sim busts the 16ms budget on a busy world.** Only risk that could invalidate the whole refactor. Mitigations baked in: dirty-rect + sleeping (typical-case savings), 4-phase checkerboard parallelism (worst-case scaling). If the budget still busts: micro-optimize the inner cell loop. If still busted: drop sim tick rate to per-2-frames (Noita-acceptable degradation; visible only on the fastest fluids). Rate-drop is a follow-up, not part of this refactor.
2. **Cross-chunk write race during a phase.** Mitigated by construction (4-phase checkerboard guarantees non-adjacency). Verified by stress-test: spawn lava at chunk boundary, run for 10k frames, assert no crashes and visible behavior matches single-threaded reference.
3. **Material-id drift between old `.tres` and new `MaterialTable`.** Mitigated by enumerating today's registry once before deletion, locking that order in the C++ array literal, code-comment that the order is load-bearing.
4. **Image upload bottleneck.** Per-frame `ImageTexture::update` for visibly-dirty chunks must stay cheap. Uploading only `dirty_rect` keeps cost proportional to actual change. If uploads dominate, batch into a texture array — out of scope here.
5. **Hot-reload with running simulator.** Mitigated: full editor restart for verification.
6. **godot-cpp / engine version skew between machines.** Submodule SHA + Godot 4.6 pinned.
7. **Arch rolling-release toolchain drift.** `build.sh` logs toolchain versions.

### 10.2 Verification

Per-step gates from §9 plus end-of-refactor checks:

- `find shaders/compute -type f` returns empty; `find shaders/include -type f` returns empty; both directories removed.
- `grep -r RenderingDevice src/ gdextension/src/` zero hits. Same for `RDShaderFile`, `compute_list`, `push_constant`.
- `generate_materials.sh` deleted; `shaders/generated/` removed.
- `MaterialRegistry` autoload entry gone from `project.godot`; no GDScript references remain.
- `comp.spv` deleted from project root.
- Smoke playthrough on both macOS and Arch: launch → generate large level → walk through it for ~2 minutes touching gas/lava/fire/digging/combat → exit cleanly. No crashes, no visible deadlocks, no frame stutters > 1s.
- `gdUnit4` suite green.

### 10.3 Logging

C++ uses `UtilityFunctions::print` / `print_verbose` (lands in Godot console). No `std::cout`. GDScript `print()` ports translate 1:1.

## 11. Done Definition

- Every file in `shaders/compute/` and `shaders/include/` deleted; both directories removed.
- `shaders/generated/` removed; `generate_materials.sh` deleted.
- `src/autoload/material_registry.gd` deleted; `project.godot` autoload list updated.
- `src/core/compute_device.gd` deleted (no callers remain).
- `src/terrain/world_preview.gd` (+ `.uid`) deleted; preview wiring removed.
- All ported classes in §3.2 exist in C++ under `gdextension/src/`, registered, and instantiated by their original names from GDScript and scenes.
- New C++ classes (`Simulator`, `Generator`, `SimplexCaveGenerator`, `ColliderBuilder`, `MaterialTable`) registered and operational.
- `comp.spv` removed.
- `bin/toprogue.gdextension` loads on macOS and Arch.
- `gdUnit4` suite passes.
- Smoke playthrough passes on both machines.
- No `RenderingDevice`, `RDShaderFile`, `RDShaderSPIRV`, `compute_list`, `push_constant` references anywhere in `src/` or `gdextension/src/`.
