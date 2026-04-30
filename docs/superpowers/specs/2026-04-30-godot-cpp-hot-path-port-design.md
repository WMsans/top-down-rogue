# godot-cpp Hot-Path Port — Design Spec

**Date:** 2026-04-30
**Status:** Approved (pending user review of this written form)
**Branch:** feat/prototype (port work will land in per-class PRs against this branch)

## 1. Motivation

Move the project's terrain / compute-dispatch / physics hot path from GDScript to C++ via the official `godot-cpp` GDExtension bindings. Three drivers:

- **Performance.** Tight per-frame loops in `ChunkManager`, `TerrainModifier`, `TerrainCollider`, and the `ComputeDevice` dispatch path pay GDScript Variant overhead on every iteration. Native code removes that.
- **CPU-exclusive features.** Things that GDScript can't express ergonomically (POD push-constant structs with `static_assert`-checked layouts, native `HashMap`/`Vector` data layouts, direct `RenderingDevice` access without Variant wrapping).
- **Development convenience.** A native debugger (lldb / gdb) on the hot path; compile-time checks that today are runtime errors; the kind of refactoring tooling C++ has and GDScript doesn't.

GDScript stays the host language for everything not on the hot path: UI, console, economy, drops, weapons, enemies, autoloads, juice, gameplay glue. GDScript→C++ calls are first-class and cheap; C++→GDScript calls go through Variant and aren't free, so the boundary sits where the Variant cost is amortized over a frame's worth of native work.

## 2. Scope

### In scope (port to C++)

| File | Lines | Becomes |
|---|---:|---|
| `src/core/compute_device.gd` | 326 | `ComputeDevice : RefCounted` |
| `src/core/chunk_manager.gd` | 251 | `ChunkManager : RefCounted` |
| `src/core/sector_grid.gd` | 96 | `SectorGrid : RefCounted` |
| `src/core/chunk.gd` | 12 | `Chunk : RefCounted` |
| `src/core/terrain_modifier.gd` | 356 | `TerrainModifier : RefCounted` |
| `src/core/terrain_collision_helper.gd` | 144 | `TerrainCollisionHelper : RefCounted` |
| `src/core/terrain_physical.gd` | 45 | `TerrainPhysical : Node` |
| `src/core/world_manager.gd` | 267 | `WorldManager : Node2D` |
| `src/physics/terrain_collider.gd` | 360 | `TerrainCollider` (base TBD on read) |
| `src/physics/gas_injector.gd` | 127 | `GasInjector : Node` |
| `src/terrain/generation_context.gd` | 5 | `GenerationContext : RefCounted` |
| `src/core/terrain_cell.gd` | — | `TerrainCell : Resource` |
| `src/core/biome_def.gd` | — | `BiomeDef : Resource` |
| `src/core/pool_def.gd` | — | `PoolDef : Resource` |
| `src/core/room_template.gd` | — | `RoomTemplate : Resource` |
| `src/core/template_pack.gd` | — | `TemplatePack : Resource` |

Approx. 2,200 LOC of GDScript → C++.

### Delete

- `src/terrain/world_preview.gd` (+ `.uid`) — feature is dead.
- Any preview-mode wiring that referenced it (autoload entries, scene refs, console commands). The 4 historical doc files mentioning `world_preview` stay as record.

### Out of scope (stay GDScript)

- All UI under `src/ui/` and `src/economy/`.
- All gameplay: `src/weapons/`, `src/enemies/`, `src/drops/`, `src/player/`.
- `src/core/spawn_dispatcher.gd` — event-driven gameplay, not per-frame.
- `src/core/juice/` — `hit_reaction.gd`, `hit_spec.gd`.
- `src/core/terrain_surface.gd` — autoload glue.
- All other autoloads (`material_registry.gd`, `biome_registry.gd`, `level_manager.gd`, `scene_manager.gd`, `console_manager.gd`, `weapon_registry.gd`, `game_mode_manager.gd`).
- `src/utils/`, `src/console/`, `src/debug/`, `src/portal.gd`.
- All `.glsl` and `.glslinc` files in `shaders/compute/` and `shaders/include/`. Not touched.

### Explicit non-goals

- No public API changes. Every C++ class exposes the same method names, arg types, and signals as its GDScript predecessor.
- No algorithm changes. Behavioral parity is the bar; bit-for-bit chunk-generation output is the regression test.
- No class renaming. `ChunkManager` stays `ChunkManager`, etc.
- No new third-party dependencies beyond godot-cpp.
- No restructuring of `shaders/`.
- No SPIR-V prebuild, no `.glslinc` cleanup, no CI, no Windows target. All deferred.

## 3. Architecture

A new top-level `gdextension/` directory holds C++ source and the godot-cpp submodule. A single shared library is built and loaded via one `.gdextension` manifest.

```
top-down-rogue/
├── gdextension/
│   ├── godot-cpp/              # git submodule, pinned to godot-4.x branch
│   ├── src/
│   │   ├── register_types.{h,cpp}   # GDREGISTER_CLASS for every exposed class
│   │   ├── compute/
│   │   │   ├── compute_device.{h,cpp}
│   │   │   └── push_constants.h     # POD mirrors of GLSL layout(push_constant) blocks
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
│   │   │   └── gas_injector.{h,cpp}
│   │   └── resources/
│   │       ├── terrain_cell.{h,cpp}
│   │       ├── biome_def.{h,cpp}
│   │       ├── pool_def.{h,cpp}
│   │       ├── room_template.{h,cpp}
│   │       └── template_pack.{h,cpp}
│   ├── SConstruct
│   ├── build.sh                 # platform-detecting wrapper
│   ├── format.sh                # clang-format -i over src/
│   └── .clang-format            # copied from godot-cpp
├── bin/
│   └── toprogue.gdextension     # entry symbol + per-platform binary paths
└── tools/
    └── migrate_tres.py          # one-shot rewrite of script-backed .tres → native-class .tres
```

`bin/lib/` (where the per-platform binaries land) is git-ignored; each machine builds locally after `git pull`.

Class names in GDScript stay identical to today, so existing `.tscn`/`.gd` references resolve transparently after each per-class port. Each port is a 1:1 swap: delete the `.gd`, register the C++ class with the same name, leave callsites untouched unless API actually changes (it shouldn't).

The class hierarchy mirrors today's GDScript: `extends RefCounted` → `public RefCounted`, `extends Node2D` → `public Node2D`, etc. No re-architecting of the class graph.

GDScript→C++ interop uses the standard Variant call path; no special bindings layer. Hot loops live entirely inside C++, so the GDScript→C++ boundary is crossed at most once per frame per subsystem.

## 4. Build System & Toolchain

### Targets

Two platforms only for this refactor:
- **macOS** — Apple clang, arm64 (or x86_64 if the dev machine is Intel; auto-detected via `uname -m`).
- **Arch Linux** — system clang or gcc (whichever is installed; SCons honors `CXX`, defaults to gcc on Arch), x86_64.

Windows is not a target; the `.gdextension` manifest omits Windows entries. Easy to add later.

### Per-machine prerequisites

- macOS: Xcode Command Line Tools (`xcode-select --install`), Python 3, `pip install scons`.
- Arch: `sudo pacman -S base-devel scons python` (clang optional: `sudo pacman -S clang`).

### Toolchain pins

- godot-cpp: pinned to a specific commit on the `4.x` branch matching engine 4.6. Pin recorded as the submodule SHA in this repo. Bump deliberately, not as drift.
- Godot editor: 4.6 (matches `project.godot` `config/features`).
- C++ standard: C++17 (godot-cpp's minimum).

### Wrapper `gdextension/build.sh`

- Detects platform via `uname -s` (`Darwin` → `platform=macos`, `Linux` → `platform=linux`).
- Detects arch via `uname -m`.
- Picks `-j` count from `sysctl -n hw.ncpu` on mac, `nproc` on Linux.
- Subcommands: `./build.sh debug`, `./build.sh release`, `./build.sh clean`, `./build.sh both`.
- Logs `clang/gcc/scons/python` versions at the top of every build (so a busted Arch system update leaves a fingerprint in the terminal scrollback).
- Same script works on both machines, no per-machine config files.
- Debug builds: `target=template_debug dev_build=yes debug_symbols=yes` (`-O0`/`-Og`, assertions on).
- Release builds: `target=template_release debug_symbols=yes` (still profileable).
- Each invocation only writes to its own platform's output path; never overwrites the other platform's binary.

### Output layout

- `bin/lib/libtoprogue.macos.template_{debug,release}.{arm64,x86_64}.dylib`
- `bin/lib/libtoprogue.linux.template_{debug,release}.x86_64.so`
- `bin/toprogue.gdextension` declares entry symbol, `compatibility_minimum = "4.6"`, and entries for both platforms above.

### Git

- `bin/lib/` is `.gitignored`. Build after `git pull` on each machine.
- `gdextension/godot-cpp/` is a submodule; cloners run `git submodule update --init --recursive` once.
- `.gitignore` adds: `bin/lib/`, `gdextension/godot-cpp/bin/`, `gdextension/godot-cpp/gen/`, `*.o`, `*.os`, `.sconsign.dblite`, SCons cache dirs.

### Editor reload

Godot 4.6 hot-reloads GDExtensions on lib change. Caveats: (a) classes currently instantiated in an open scene may need that scene reopened; (b) renaming a registered class requires an editor restart — avoided here by keeping every class name identical. For the per-class verification step, fully restart the editor regardless.

## 5. Class Responsibilities & API Preservation

For each ported class, the public surface stays identical to today's GDScript so callsites don't change. Internal storage switches to native types where it pays off.

- **`ComputeDevice` (`RefCounted`)** — owns `RenderingDevice` handle, shader / pipeline cache (`HashMap<StringName, RID>`), buffer / dispatch helpers. All `RD` calls funnel through here.
- **`Chunk` (`RefCounted`)** — trivial data holder. Direct field port; getters/setters bound only where GDScript reads them.
- **`SectorGrid` (`RefCounted`)** — sparse grid keyed `Vector2i → Ref<Chunk>` via native `HashMap`. Public API (`get_chunk`, `set_chunk`, iteration helpers) preserved.
- **`ChunkManager` (`RefCounted`)** — chunk streaming, activation, lifecycle. Holds `Ref<SectorGrid>`; dispatches generation through `ComputeDevice`. Per-frame distance/activation loops stay native; GDScript-facing signals stay as `emit_signal` with identical names.
- **`TerrainModifier` (`RefCounted`)** — CPU-side terrain modifications (carve, paint, stamp). Internals: native `Vector<>` cell-delta buffers, no `Array<Variant>` in inner loops. Public methods (`carve_circle`, `apply_modifier`, …) keep signatures.
- **`TerrainCollisionHelper` (`RefCounted`)** — collision queries against terrain grid. Pure compute; no Variant in inner loops.
- **`TerrainPhysical` (`Node`)** — scene-attached physical-state holder (exact base confirmed at port time). Surface preserved; only the body becomes C++.
- **`WorldManager` (`Node2D`)** — top-level orchestrator. Owns `Ref<ChunkManager>`, `Ref<ComputeDevice>`, biome state. `_ready`/`_process` ported to C++ overrides. Signals preserved with identical names so GDScript listeners work unchanged.
- **`TerrainCollider`** — terrain collision body management; rebuilds shapes from terrain state. Heaviest expected measurable win.
- **`GasInjector` (`Node`)** — pushes gas-cell deltas into simulation buffers via `ComputeDevice`.
- **`GenerationContext`** — 5-line container; direct port.
- **Resources** (`TerrainCell`, `BiomeDef`, `PoolDef`, `RoomTemplate`, `TemplatePack`) — each becomes a `public Resource` C++ class. Properties registered via `ClassDB::bind_method` + `ADD_PROPERTY` so existing `.tres` files load unchanged after a one-time mechanical header rewrite (see §7).

No new public methods, signals, or properties are introduced in any ported class. Internal helpers may be added freely.

## 6. Compute / RenderingDevice Integration

This is the part the refactor exists for; behavioral parity is the bar.

### Boundary

All `RenderingDevice` calls (shader load, pipeline create, buffer create / update, compute list begin / dispatch / end, sync) move into `ComputeDevice` and its callers (`ChunkManager`, `TerrainModifier`, `TerrainCollider`, `GasInjector`). After this refactor, GDScript never touches `RenderingDevice` — it calls C++ methods like `ChunkManager::generate_chunk(coord)` and the C++ side handles dispatch.

### Shader loading

GLSL files in `shaders/compute/*.glsl` and `shaders/include/**/*.glslinc` continue to be loaded as `RDShaderFile` resources via `ResourceLoader::load`. godot-cpp exposes the same `RDShaderFile`/`RDShaderSPIRV` classes. Existing `.glsl.import` files unchanged.

### Pipeline cache

`ComputeDevice` keeps a `HashMap<StringName, RID>` of compiled pipelines keyed by shader path. First dispatch compiles + caches; subsequent dispatches hit the cache. Same behavior as today, native code path.

### Push constants

Each compute shader's `layout(push_constant)` block gets a mirrored C++ POD struct in `gdextension/src/compute/push_constants.h`:

```cpp
struct GenerationPushConstants {
    int32_t  chunk_x, chunk_y;
    uint32_t seed;
    float    biome_blend;
    // ... matches generation.glsl layout exactly
};
static_assert(sizeof(GenerationPushConstants) % 16 == 0,
              "push constants must be 16-byte aligned");
```

One header section per shader stage. Mismatches between GLSL and C++ layout fail at compile time, not as silent runtime corruption.

### Storage buffers

Buffer RIDs owned by `ComputeDevice`; lifetime tied to its `Ref`. Upload paths use `PackedByteArray` views over native `Vector<uint8_t>` — no copy at the RD boundary. Readbacks use `RD::buffer_get_data` directly into native buffers; data exposed to GDScript only at the gameplay-relevant boundary (e.g., chunk-finished signal carrying a `Ref<Chunk>`).

### Dispatch ordering

Stage sequencing currently in `chunk_manager.gd` / `terrain_modifier.gd` (generation → biome stages → collider regen → simulation tick) is preserved 1:1. No reordering, no fusing, no parallelism changes. Performance gains come from removing GDScript overhead, not from changing the algorithm.

### Sync model

Existing GPU sync points (waits, fences, frame boundaries) preserved. If today's code does `RD.sync()` after a stage, the C++ port does the same.

### Failure handling

Today's GDScript `if shader.is_null():` checks port over identically. No new validation, no fallbacks, no retries. Failures print/error exactly like today.

## 7. Migration Plan

Sequential per-class, leaves-first, no runtime toggle. Each step is one PR / commit. After each, the game must launch, terrain must generate, and existing tests must pass before the next step starts. Each PR is self-contained; `git revert` of any single commit returns to a working state.

### Step order

1. **Bootstrap** — `gdextension/` skeleton, godot-cpp submodule, `SConstruct`, `build.sh`, empty `register_types.cpp`, `bin/toprogue.gdextension`, `.gitignore` / `.gitattributes`. No GDScript changes. Verifies on macOS + Arch.
2. **Resources** — `TerrainCell`, `BiomeDef`, `PoolDef`, `RoomTemplate`, `TemplatePack`. For each: implement C++ class with identical exported properties, register, run `tools/migrate_tres.py` to rewrite that resource's `.tres` files, commit C++ + migrated `.tres` together.
3. **Leaves** — `Chunk`, `GenerationContext`, `SectorGrid`. Trivial; unblock heavier classes.
4. **`ComputeDevice`** — central piece for everything below. Capture golden output baseline before this step (see §8).
5. **`TerrainModifier`** then **`TerrainCollisionHelper`** — depend on `ComputeDevice` / `SectorGrid`.
6. **`ChunkManager`** — depends on everything above.
7. **`TerrainPhysical`** then **`GasInjector`** then **`TerrainCollider`** — physics layer; biggest measurable win in `TerrainCollider`.
8. **`WorldManager`** — last; most scene-coupled. After this step, delete `src/terrain/world_preview.gd` / `.uid` and any preview-mode wiring (autoload entries, scene refs, console commands).

### `.tres` migration mechanics

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

`tools/migrate_tres.py` does this rewrite per-resource-class. Before bulk-running, hand-verify on 1–2 representative `.tres` files and open them in the editor to confirm property round-trip.

### `.uid` and reference cleanup

Per-port checklist greps for the deleted `.gd`'s `res://...gd` path and its `.uid` string before deletion. Any stragglers in scenes / scripts get fixed in the same commit.

### Untouched code

`spawn_dispatcher.gd` and all gameplay GDScript continue to call into the same class names. No edits to those files in any port commit.

## 8. Verification

### Per-step gates

Before merging any port commit:
- `./build.sh debug` succeeds on the authoring machine. (The other machine builds on next pull.)
- `gdUnit4` test suite passes — same tests, no test changes.
- Manual smoke checklist: launch, generate level, kill enemy, fire weapon, open console, exit cleanly.
- Editor restart performed after the build for the smoke run (don't trust hot-reload for verification).

### Golden-output regression test

`tests/golden/` holds dumped chunk-generation outputs for a fixed `(seed, chunk_coord)` set, captured **before** the `ComputeDevice` port. A GDScript test (`tests/golden/test_chunk_generation_parity.gd`) loads the baseline, regenerates via current code, asserts byte-equality. Runs from the `ComputeDevice` step onward. If it fails, GLSL or dispatch is diverging — investigate, do not update the baseline.

### Test contract

Every test that passes pre-port must pass post-port unchanged. If a test was written against private GDScript internals (e.g. asserting on a `_private_field`), it gets adapted to the public surface in that class's port commit — flagged in the PR.

### Logging

C++ uses `UtilityFunctions::print` / `print_verbose` (lands in the Godot console). No `std::cout`. GDScript `print()` calls being ported translate 1:1.

### Formatting

`gdextension/.clang-format` copied from godot-cpp. `gdextension/format.sh` runs `clang-format -i` over `gdextension/src/`. Both machines run it manually before commits. No CI enforcement.

## 9. Risks & Mitigations

1. **`.tres` migration breakage** if header syntax drifts or property names diverge. Mitigation: mechanical `migrate_tres.py`; C++ properties registered with identical names/types; spot-check 1–2 `.tres` in editor before bulk run.
2. **Push-constant struct drift** silently corrupting compute output. Mitigation: per-stage `static_assert` on size/alignment; co-located C++ header with `compute_device.h`; reviewer checks GLSL + C++ header together; golden-output test catches what slips past review.
3. **`.uid` references to deleted `.gd`s.** Mitigation: per-port grep checklist; smoke test opens scenes referencing the class.
4. **Hot-reload state loss mid-session.** Mitigation: editor restart for verification. Hot-reload is dev-loop convenience only.
5. **godot-cpp / engine version skew between machines.** Mitigation: submodule SHA + Godot editor version pinned in this doc; deliberate bumps.
6. **Arch rolling-release toolchain drift.** Mitigation: `build.sh` logs `cc/clang/scons/python` versions at the top of every build.

## 10. Done Definition

- All 16 files listed in §2 ("In scope") are deleted from `src/`.
- `world_preview.gd` is deleted; preview-mode wiring removed.
- `bin/toprogue.gdextension` loads on both macOS and Arch.
- Golden-output parity test passes.
- `gdUnit4` suite passes.
- Game launches, generates terrain, plays, exits cleanly on both machines.
- All gameplay GDScript (UI, weapons, enemies, drops, autoloads, etc.) compiles and runs against the C++ classes with no edits beyond what `.uid` cleanup required.

## 11. Deferred (explicit follow-ups)

- Pre-compile GLSL → SPIR-V at build time.
- `.glslinc` include-convention cleanup.
- Port gameplay GDScript (enemies, weapons, drops, player).
- Port UI / menus.
- CI / GitHub Actions.
- Cross-compile to Windows.
- Performance benchmarking harness — profile after `WorldManager` lands.
