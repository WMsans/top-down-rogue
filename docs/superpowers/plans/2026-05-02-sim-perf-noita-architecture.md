# Sim Performance: Noita-Style Architecture — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the C++ falling-sand simulation pipeline (Simulator + Chunk + 4 rules + texture upload) into a Noita-style unified pipeline so player movement through lava produces visible displacement at 60 FPS without per-frame stutters.

**Architecture:** Eight sequential migrations on `master`-based branch `refactor/cpp`. Each migration leaves the build green and tests passing. In order: (1) raw-pointer active list, (2) Texture2DArray tiling for partial GPU upload, (3) ChunkView + inner/border split, (4) shrinking dirty rect, (5) drop intra-chunk atomics, (6) SoA cell storage, (7) unified per-cell dispatch + rule collapse, (8) dynamic-parity threading.

**Tech Stack:** C++17 (godot-cpp 4.x GDExtension), SCons via `gdextension/build.sh`, Godot 4.x shaders (`*.gdshader`), GUT (Godot Unit Test) for GDScript-side tests under `tests/unit/`.

**Spec:** `docs/superpowers/specs/2026-05-02-sim-perf-noita-architecture-design.md`

---

## Conventions

- **Build command** (run from `gdextension/`): `./build.sh debug` — must succeed at the end of every Task.
- **Run-game smoke test**: open the project in Godot Editor, press F5, walk into the lava demo scene; confirm no crash and visual sanity.
- **Snapshot regression**: a tiny new GDScript test under `tests/unit/test_sim_snapshot.gd` (added in Task 0). Re-run via Godot's GUT runner after every Task; output should match the recorded golden hash.
- **Commit format**: `feat: …`, `refactor: …`, `perf: …` — match the project's existing commit style.
- **Namespace**: all new C++ types live in `namespace toprogue { ... }`.
- **Headers**: include guards via `#pragma once`; clang-format is enforced (see `gdextension/format.sh`).
- **Ref vs raw**: hot paths (Simulator inner loops, ChunkView) use `Chunk*`. `Ref<Chunk>` survives only at ChunkManager dictionary boundaries and GDScript bindings.

---

## File Structure

| Path | Responsibility | Status |
|---|---|---|
| `gdextension/src/sim/simulator.{h,cpp}` | Owns active-chunk list, drives per-tick scan, dispatches threading | Modified |
| `gdextension/src/sim/sim_context.{h,cpp}` | Border-cell helpers (no longer hot-path) | Modified |
| `gdextension/src/sim/chunk_view.{h,cpp}` | NEW — POD with pre-resolved SoA pointers per chunk per tick | Create |
| `gdextension/src/sim/material_kind.{h,cpp}` | NEW — `MaterialKind` enum + `mt_kind[256]` LUT | Create |
| `gdextension/src/sim/rules/lava.{h,cpp}` | Lava rule (eventually `step_lava` inline handler) | Modified |
| `gdextension/src/sim/rules/gas.{h,cpp}` | Gas rule (eventually `step_gas` inline handler) | Modified |
| `gdextension/src/sim/rules/burning.{h,cpp}` | Burning rule (push-semantics ignition) | Modified |
| `gdextension/src/sim/rules/injection.{h,cpp}` | Injection drain (no grid scan) | Modified |
| `gdextension/src/terrain/chunk.{h,cpp}` | Cell storage (eventually SoA), tiled texture array, plain dirty rect | Modified |
| `gdextension/src/terrain/chunk_manager.cpp` | Wires Simulator's active-list calls; per-chunk tile rendering | Modified |
| `shaders/visual/render_chunk.gdshader` | Reads `sampler2DArray chunk_data` with computed layer index | Modified |
| `tests/unit/test_sim_snapshot.gd` | NEW — golden-hash regression after N ticks of a seeded scenario | Create |
| `tests/unit/test_sim_settled_sleep.gd` | NEW — settled puddle sleeps within N ticks | Create (Task 4) |
| `docs/superpowers/specs/2026-05-02-sim-perf-noita-architecture-design.md` | Profiling appendix appended after each Task | Modified |

---

## Task 0: Snapshot regression harness + profiling baseline

Establish the safety net before changing anything.

**Files:**
- Create: `tests/unit/test_sim_snapshot.gd`
- Create: `tools/sim_bench.gd` (headless profiling helper)
- Modify: `docs/superpowers/specs/2026-05-02-sim-perf-noita-architecture-design.md` (appendix)

- [ ] **Step 1: Write the snapshot test**

```gdscript
# tests/unit/test_sim_snapshot.gd
extends GutTest

# Deterministic seeded scenario: load 4 chunks at (0,0)..(1,1), inject a
# lava blob at (128, 128), tick the Simulator N times, hash all chunk
# cells together. The hash is the regression key.

const TICK_COUNT := 200
const WORLD_SEED := 0xC0FFEE
const EXPECTED_SHA256 := "" # filled in by Step 3 after recording

func test_snapshot_after_200_ticks() -> void:
    var sim: Simulator = Simulator.new()
    sim.set_world_seed(WORLD_SEED)

    var chunks := {}
    for cx in range(2):
        for cy in range(2):
            var c: Chunk = Chunk.new()
            c.coord = Vector2i(cx, cy)
            chunks[c.coord] = c
    _wire_neighbors(chunks)
    sim.set_chunks(chunks)

    _inject_lava_blob(chunks[Vector2i(0, 0)], Vector2i(128, 128), 16)

    for i in TICK_COUNT:
        sim.tick()

    var ctx := HashingContext.new()
    ctx.start(HashingContext.HASH_SHA256)
    for coord in chunks.keys():
        ctx.update(chunks[coord].get_cells_data())
    var got := ctx.finish().hex_encode()

    if EXPECTED_SHA256 == "":
        push_warning("RECORD: %s" % got)
        # First-time recording: do not fail; copy the hex into EXPECTED_SHA256.
    else:
        assert_eq(got, EXPECTED_SHA256, "Snapshot regression")

func _wire_neighbors(chunks: Dictionary) -> void:
    for coord in chunks.keys():
        var c: Chunk = chunks[coord]
        var up: Vector2i = coord + Vector2i(0, -1)
        var dn: Vector2i = coord + Vector2i(0,  1)
        var lf: Vector2i = coord + Vector2i(-1, 0)
        var rt: Vector2i = coord + Vector2i( 1, 0)
        if chunks.has(up): c.neighbor_up = chunks[up]
        if chunks.has(dn): c.neighbor_down = chunks[dn]
        if chunks.has(lf): c.neighbor_left = chunks[lf]
        if chunks.has(rt): c.neighbor_right = chunks[rt]

func _inject_lava_blob(chunk: Chunk, center: Vector2i, radius: int) -> void:
    # MAT_LAVA == 4 in MaterialTable._populate. Density 200, temperature 220.
    var bytes := chunk.get_cells_data()
    var sz := Chunk.get_chunk_size()
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            if dx*dx + dy*dy > radius*radius:
                continue
            var x := center.x + dx
            var y := center.y + dy
            if x < 0 or x >= sz or y < 0 or y >= sz:
                continue
            var idx := (y * sz + x) * 4
            bytes[idx + 0] = 4    # material = MAT_LAVA
            bytes[idx + 1] = 200  # health (density)
            bytes[idx + 2] = 220  # temperature
            bytes[idx + 3] = 0x88 # flags: vx=0, vy=0 packed
    chunk.set_cells_data(bytes)
    chunk.dirty_rect = Rect2i(center.x - radius, center.y - radius,
                              radius * 2 + 1, radius * 2 + 1)
    chunk.sleeping = false
```

- [ ] **Step 2: Run the test and record the baseline hash**

Run via Godot's GUT runner (project's existing convention):

```bash
# From project root. Adjust if the project uses a different runner script.
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_sim_snapshot.gd -gexit
```

Expected: test prints `RECORD: <64-hex-digit-sha256>` as a warning, passes. Copy the hash.

- [ ] **Step 3: Pin the baseline hash into the test**

Edit `tests/unit/test_sim_snapshot.gd`: replace `const EXPECTED_SHA256 := ""` with the recorded hash, e.g. `const EXPECTED_SHA256 := "abc123..."`.

- [ ] **Step 4: Re-run the test to verify it locks**

Run the same `godot --headless ...` command. Expected: PASS, no warning.

- [ ] **Step 5: Write profiling helper**

```gdscript
# tools/sim_bench.gd
# Headless: tick the Simulator for N frames over the same seeded scenario as
# the snapshot test, print median + p99 ms/tick. Used as the before/after gate
# for each Task. Run with:
#   godot --headless --path . -s tools/sim_bench.gd
extends SceneTree

const TICKS := 600

func _initialize() -> void:
    var sim: Simulator = Simulator.new()
    sim.set_world_seed(0xC0FFEE)
    var chunks := {}
    for cx in range(2):
        for cy in range(2):
            var c: Chunk = Chunk.new()
            c.coord = Vector2i(cx, cy)
            chunks[c.coord] = c
    for coord in chunks.keys():
        var c: Chunk = chunks[coord]
        for delta in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]:
            if chunks.has(coord + delta):
                pass  # neighbor wiring is needed; reuse helper if extracted
    sim.set_chunks(chunks)

    var samples := PackedFloat64Array()
    samples.resize(TICKS)
    for i in TICKS:
        var t0 := Time.get_ticks_usec()
        sim.tick()
        samples[i] = (Time.get_ticks_usec() - t0) / 1000.0  # ms

    samples.sort()
    var median := samples[TICKS / 2]
    var p99 := samples[int(TICKS * 0.99)]
    print("median_ms=%.3f p99_ms=%.3f" % [median, p99])
    quit()
```

- [ ] **Step 6: Record baseline numbers**

Run `godot --headless --path . -s tools/sim_bench.gd`. Append to the spec appendix:

```markdown
### Task 0 baseline (HEAD before Task 1)
- median_ms=<X>  p99_ms=<Y>
- Snapshot SHA256: <hash>
```

- [ ] **Step 7: Commit**

```bash
git add tests/unit/test_sim_snapshot.gd tools/sim_bench.gd \
        docs/superpowers/specs/2026-05-02-sim-perf-noita-architecture-design.md
git commit -m "test: add sim snapshot regression + bench harness (baseline)"
```

---

## Task 1: Active list + raw-pointer hot path

Replace `Dictionary _chunks` traversal in `Simulator::tick()` with a
maintained `std::vector<Chunk*> _active`. ChunkManager populates it.

**Files:**
- Modify: `gdextension/src/sim/simulator.h`
- Modify: `gdextension/src/sim/simulator.cpp`
- Modify: `gdextension/src/terrain/chunk_manager.h`
- Modify: `gdextension/src/terrain/chunk_manager.cpp`

- [ ] **Step 1: Add `_active` field + add/remove methods to Simulator**

In `gdextension/src/sim/simulator.h`, add inside the class:

```cpp
public:
    void add_active(Chunk *chunk);
    void remove_active(Chunk *chunk);

private:
    std::vector<Chunk *> _active;
```

Add `#include <vector>` to the header.

- [ ] **Step 2: Implement add/remove (idempotent, O(N))**

In `gdextension/src/sim/simulator.cpp`:

```cpp
void Simulator::add_active(Chunk *chunk) {
    if (!chunk) return;
    for (Chunk *c : _active) if (c == chunk) return;
    _active.push_back(chunk);
}

void Simulator::remove_active(Chunk *chunk) {
    for (auto it = _active.begin(); it != _active.end(); ++it) {
        if (*it == chunk) { _active.erase(it); return; }
    }
}
```

Bind both to GDScript in `_bind_methods` so ChunkManager (currently called from GDScript glue in some paths) can reach them:

```cpp
ClassDB::bind_method(D_METHOD("add_active", "chunk"), &Simulator::add_active);
ClassDB::bind_method(D_METHOD("remove_active", "chunk"), &Simulator::remove_active);
```

- [ ] **Step 3: Switch tick() to iterate `_active` instead of Dictionary keys**

Replace the active-set construction at the top of `Simulator::tick()` (currently lines 36–44):

```cpp
// Old:
//   Array keys = _chunks.keys();
//   Vector<Chunk *> active;
//   for (int i = 0; i < keys.size(); i++) { Ref<Chunk> c = _chunks[keys[i]]; ... }

// New:
Vector<Chunk *> active;
active.resize(0);
for (Chunk *c : _active) {
    if (c && !c->get_sleeping()) active.push_back(c);
}
```

Leave `set_chunks(Dictionary)` in place — `rotate_dirty_rects()` and
`upload_dirty_textures()` still walk the Dictionary. They will be migrated
in later tasks; for now we just need the active set to come from `_active`.

- [ ] **Step 4: Auto-populate `_active` from existing chunks at the start of each tick (transitional)**

Until ChunkManager gets wired up (next steps), keep a one-frame sync:

```cpp
void Simulator::tick() {
    // Transitional: rebuild _active from _chunks if any non-sleeping chunk
    // is missing. Removed in Task 1 Step 7.
    Array keys = _chunks.keys();
    for (int i = 0; i < keys.size(); i++) {
        Ref<Chunk> c = _chunks[keys[i]];
        if (c.is_valid() && !c->get_sleeping()) add_active(c.ptr());
    }
    // ... rest of tick()
}
```

- [ ] **Step 5: Build**

```bash
cd gdextension && ./build.sh debug
```

Expected: clean build.

- [ ] **Step 6: Run snapshot test — must still pass with same hash**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
      -gtest=res://tests/unit/test_sim_snapshot.gd -gexit
```

Expected: PASS, hash unchanged.

- [ ] **Step 7: Wire ChunkManager → add_active / remove_active**

In `gdextension/src/terrain/chunk_manager.h`, add:

```cpp
public:
    void set_simulator(Simulator *s) { _simulator = s; }
private:
    Simulator *_simulator = nullptr;
```

(Add forward decl `class Simulator;` near the top.) Bind in
`_bind_methods`:

```cpp
ClassDB::bind_method(D_METHOD("set_simulator", "s"), &ChunkManager::set_simulator);
```

In `chunk_manager.cpp`:

- After `wire_neighbors(chunk.ptr())` inside `create_chunk`, add:
  ```cpp
  if (_simulator) _simulator->add_active(chunk.ptr());
  ```
- Inside `unload_chunk`, before `_chunks.erase(coord)`:
  ```cpp
  if (_simulator) _simulator->remove_active(chunk.ptr());
  ```
- Inside `clear_all_chunks`, after iterating chunks, walk them again to call
  `_simulator->remove_active(...)` for each (or just call once with each).

GDScript glue that constructs Simulator + ChunkManager: pass the Simulator
pointer to ChunkManager via the new bound method on startup.

- [ ] **Step 8: Drop the transitional sync from Step 4**

Remove the rebuild block from `Simulator::tick()`. `_active` is now the
authoritative source.

- [ ] **Step 9: Build + snapshot**

```bash
cd gdextension && ./build.sh debug
cd .. && godot --headless --path . -s addons/gut/gut_cmdln.gd \
      -gtest=res://tests/unit/test_sim_snapshot.gd -gexit
```

Expected: build clean, snapshot hash unchanged.

- [ ] **Step 10: Smoke test in editor**

Open Godot editor, F5, walk player into lava. Confirm: no crash, sim still
runs (lava still flows the same, even if slowly).

- [ ] **Step 11: Bench + appendix**

```bash
godot --headless --path . -s tools/sim_bench.gd
```

Append to spec appendix as `Task 1 result`.

- [ ] **Step 12: Commit**

```bash
git add gdextension/src/sim/simulator.{h,cpp} \
        gdextension/src/terrain/chunk_manager.{h,cpp} \
        docs/superpowers/specs/2026-05-02-sim-perf-noita-architecture-design.md
git commit -m "refactor: Simulator owns std::vector<Chunk*> active list

Eliminate Dictionary.keys() walking and Ref<Chunk> refcount churn from
the per-tick hot path. ChunkManager wires add_active/remove_active on
chunk create/unload. Snapshot hash unchanged."
```

---

## Task 2: Texture upload tiling — Texture2DArray with per-layer update

**Goal:** stutter fix. Replace the per-chunk single `ImageTexture` with a
16-layer `Texture2DArray` of 64×64 RGBA8 layers. Only re-upload layers that
intersect the dirty rect. Update the shader to sample by computed layer.

**Files:**
- Modify: `gdextension/src/terrain/chunk.h`
- Modify: `gdextension/src/terrain/chunk.cpp`
- Modify: `gdextension/src/terrain/chunk_manager.cpp`
- Modify: `shaders/visual/render_chunk.gdshader`

- [ ] **Step 1: Add tiled-texture fields to Chunk**

In `chunk.h`, alongside the existing `Ref<ImageTexture> texture`:

```cpp
public:
    static constexpr int TILE_SIZE = 64;
    static constexpr int TILES_PER_SIDE = CHUNK_SIZE / TILE_SIZE; // 4
    static constexpr int TILE_COUNT = TILES_PER_SIDE * TILES_PER_SIDE; // 16

    godot::Ref<godot::Texture2DArray> tiled_texture;
    // Persistent per-layer staging images (reused across uploads).
    godot::Ref<godot::Image> tile_images[TILE_COUNT];
```

Add `#include <godot_cpp/classes/texture2d_array.hpp>`.

- [ ] **Step 2: Initialize tiled_texture + per-tile images in ChunkManager::create_chunk**

In `chunk_manager.cpp`, replace the `ImageTexture::create_from_image(blank)`
block (lines 166–172) with:

```cpp
// Build 16 zeroed RGBA8 64x64 layers and create the Texture2DArray once.
TypedArray<Ref<Image>> layers;
for (int t = 0; t < Chunk::TILE_COUNT; t++) {
    PackedByteArray zeros;
    zeros.resize(Chunk::TILE_SIZE * Chunk::TILE_SIZE * 4);
    Ref<Image> tile_img = Image::create_from_data(
        Chunk::TILE_SIZE, Chunk::TILE_SIZE, false, Image::FORMAT_RGBA8, zeros);
    chunk->tile_images[t] = tile_img;
    layers.append(tile_img);
}
chunk->tiled_texture.instantiate();
chunk->tiled_texture->create_from_images(layers);
```

(Remove the now-unused `chunk->texture = ...` line from this path. Keep the
field on Chunk for save/load compat — `set_cells_data` still works.)

- [ ] **Step 3: Update both ShaderMaterial bindings to use tiled_texture**

In the same `create_chunk`, where the material is set up
(`mat->set_shader_parameter("chunk_data", chunk->get_texture())` and the
wall_mat equivalent), change to:

```cpp
mat->set_shader_parameter("chunk_data", chunk->tiled_texture);
// ...
wall_mat->set_shader_parameter("chunk_data", chunk->tiled_texture);
```

In `update_render_neighbors`, the existing
`mat->set_shader_parameter("neighbor_data", north_chunk->get_texture())`
call becomes:

```cpp
mat->set_shader_parameter("neighbor_data", north_chunk->tiled_texture);
```

- [ ] **Step 4: Update the shader to read sampler2DArray**

Edit `shaders/visual/render_chunk.gdshader`:

Replace:
```glsl
uniform sampler2D chunk_data : filter_nearest;
uniform sampler2D neighbor_data : filter_nearest;
```
with:
```glsl
uniform sampler2DArray chunk_data : filter_nearest;
uniform sampler2DArray neighbor_data : filter_nearest;
const int TILE_SIZE = 64;
const int TILES_PER_SIDE = 4;
```

Replace `read_pixel`:
```glsl
vec4 read_pixel(ivec2 pos) {
    int tile_x = pos.x / TILE_SIZE;
    int tile_y = pos.y / TILE_SIZE;
    int layer = tile_y * TILES_PER_SIDE + tile_x;
    ivec2 local = pos - ivec2(tile_x * TILE_SIZE, tile_y * TILE_SIZE);
    vec2 uv = (vec2(local) + 0.5) / float(TILE_SIZE);
    uv.y = 1.0 - uv.y; // preserve existing Y-flip
    return texture(chunk_data, vec3(uv, float(layer)));
}
```

Replace `read_neighbor`:
```glsl
vec4 read_neighbor(ivec2 neighbor_pos) {
    int tile_x = neighbor_pos.x / TILE_SIZE;
    int tile_y = neighbor_pos.y / TILE_SIZE;
    int layer = tile_y * TILES_PER_SIDE + tile_x;
    ivec2 local = neighbor_pos - ivec2(tile_x * TILE_SIZE, tile_y * TILE_SIZE);
    vec2 uv = (vec2(local) + 0.5) / float(TILE_SIZE);
    uv.y = 1.0 - uv.y;
    return texture(neighbor_data, vec3(uv, float(layer)));
}
```

The rest of the shader is unchanged — `read_pixel_extended`, `is_solid`,
etc., still work because they call the new `read_pixel` / `read_neighbor`.

- [ ] **Step 5: Rewrite Chunk::upload_texture for tiled partial updates**

In `chunk.cpp`, replace the existing `upload_texture` and
`upload_texture_full` with:

```cpp
static inline void pack_tile_aos(const Cell *cells, int tile_x, int tile_y,
                                 uint8_t *out_4bpp) {
    constexpr int SZ = Chunk::CHUNK_SIZE;
    constexpr int TS = Chunk::TILE_SIZE;
    int x0 = tile_x * TS;
    int y0 = tile_y * TS;
    for (int ly = 0; ly < TS; ly++) {
        const Cell *src = &cells[(y0 + ly) * SZ + x0];
        std::memcpy(out_4bpp + ly * TS * 4, src, TS * 4);
    }
}

void Chunk::upload_texture() {
    if (dirty_rect.size.x == 0 || dirty_rect.size.y == 0) return;
    if (tiled_texture.is_null()) return;

    int tx0 = std::max(0, dirty_rect.position.x / TILE_SIZE);
    int ty0 = std::max(0, dirty_rect.position.y / TILE_SIZE);
    int tx1 = std::min(TILES_PER_SIDE - 1,
                       (dirty_rect.position.x + dirty_rect.size.x - 1) / TILE_SIZE);
    int ty1 = std::min(TILES_PER_SIDE - 1,
                       (dirty_rect.position.y + dirty_rect.size.y - 1) / TILE_SIZE);

    PackedByteArray buf;
    buf.resize(TILE_SIZE * TILE_SIZE * 4);
    for (int ty = ty0; ty <= ty1; ty++) {
        for (int tx = tx0; tx <= tx1; tx++) {
            pack_tile_aos(cells, tx, ty, buf.ptrw());
            int layer = ty * TILES_PER_SIDE + tx;
            // Reuse the persistent Ref<Image> per layer; just refresh data.
            tile_images[layer] = Image::create_from_data(
                TILE_SIZE, TILE_SIZE, false, Image::FORMAT_RGBA8, buf);
            tiled_texture->update_layer(tile_images[layer], layer);
        }
    }
}

void Chunk::upload_texture_full() {
    // Re-upload every layer (cold path: chunk just created, save load).
    for (int t = 0; t < TILE_COUNT; t++) {
        int tx = t % TILES_PER_SIDE;
        int ty = t / TILES_PER_SIDE;
        PackedByteArray buf;
        buf.resize(TILE_SIZE * TILE_SIZE * 4);
        pack_tile_aos(cells, tx, ty, buf.ptrw());
        tile_images[t] = Image::create_from_data(
            TILE_SIZE, TILE_SIZE, false, Image::FORMAT_RGBA8, buf);
        tiled_texture->update_layer(tile_images[t], t);
    }
}
```

Add `#include <godot_cpp/classes/texture2d_array.hpp>` and
`#include <algorithm>` to `chunk.cpp`.

- [ ] **Step 6: Bind tiled_texture as a property**

In `Chunk::_bind_methods` (chunk.cpp around line 188), add:

```cpp
ClassDB::bind_method(D_METHOD("get_tiled_texture"), &Chunk::get_tiled_texture);
ClassDB::bind_method(D_METHOD("set_tiled_texture", "v"), &Chunk::set_tiled_texture);
ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "tiled_texture",
                          PROPERTY_HINT_RESOURCE_TYPE, "Texture2DArray"),
             "set_tiled_texture", "get_tiled_texture");
```

In `chunk.h` add the trivial getters/setters next to the existing
`get_texture/set_texture`:

```cpp
godot::Ref<godot::Texture2DArray> get_tiled_texture() const { return tiled_texture; }
void set_tiled_texture(const godot::Ref<godot::Texture2DArray> &v) { tiled_texture = v; }
```

- [ ] **Step 7: Build**

```bash
cd gdextension && ./build.sh debug
```

Expected: clean build. If `update_layer` is not present in your godot-cpp
version, fall back to:

```cpp
RenderingServer::get_singleton()->texture_2d_update(
    tiled_texture->get_rid(), tile_images[layer], layer);
```

(Verify the exact name in `gdextension/godot-cpp/gen/include/godot_cpp/classes/texture2d_array.hpp` before choosing.)

- [ ] **Step 8: Snapshot test passes (cell data unchanged — only render path changed)**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd \
      -gtest=res://tests/unit/test_sim_snapshot.gd -gexit
```

Expected: PASS, hash unchanged.

- [ ] **Step 9: Visual smoke test**

Open Godot editor, F5. Walk around lava. Watch carefully at tile boundaries
(every 64 px within a chunk: x=64, 128, 192) for seams or color
discontinuity. Expected: visually identical to pre-Task-2 build.

If seams appear, the bug is most likely in the shader's UV math (Step 4) —
recheck the Y-flip and the `local = pos - ivec2(tx*TS, ty*TS)` expression.

- [ ] **Step 10: Bench + appendix**

```bash
godot --headless --path . -s tools/sim_bench.gd
```

Append `Task 2 result`. Expected: stutter spikes (p99) reduced
significantly.

- [ ] **Step 11: Commit**

```bash
git add gdextension/src/terrain/chunk.{h,cpp} \
        gdextension/src/terrain/chunk_manager.cpp \
        shaders/visual/render_chunk.gdshader \
        docs/superpowers/specs/2026-05-02-sim-perf-noita-architecture-design.md
git commit -m "perf: tile chunk texture into 4x4 Texture2DArray for partial GPU upload

Replaces per-frame full 256KB ImageTexture re-upload with per-layer
update of only dirty 64x64 tiles. Eliminates the main per-frame stutter
source. Shader updated to sample sampler2DArray with computed layer.
Snapshot hash unchanged."
```

---

## Task 3: ChunkView + inner / border split

Introduce a per-chunk-per-tick POD that holds pre-resolved neighbor
pointers. Convert each rule's inner loop to use `ChunkView` directly
(still on AoS Cells; SoA migration happens in Task 6).

**Files:**
- Create: `gdextension/src/sim/chunk_view.h`
- Modify: `gdextension/src/sim/simulator.cpp`
- Modify: `gdextension/src/sim/rules/lava.cpp`
- Modify: `gdextension/src/sim/rules/gas.cpp`
- Modify: `gdextension/src/sim/rules/burning.cpp`
- Modify: `gdextension/src/sim/rules/injection.cpp`

- [ ] **Step 1: Create ChunkView header**

```cpp
// gdextension/src/sim/chunk_view.h
#pragma once

#include "../terrain/chunk.h"

#include <cstdint>

namespace toprogue {

// POD assembled once per chunk per tick by Simulator, passed to rules.
// All pointers may be null if a neighbor doesn't exist (world edge).
struct ChunkView {
    Chunk *center;
    Chunk *up, *down, *left, *right;

    // AoS pointers (Task 3). Replaced with SoA pointers in Task 6.
    Cell *cells;       // center->cells
    Cell *cells_up;
    Cell *cells_down;
    Cell *cells_left;
    Cell *cells_right;

    uint32_t frame_seed;
    int      frame_index;
    int      air_id, gas_id, lava_id, water_id;

    static constexpr int SZ = Chunk::CHUNK_SIZE;

    // Inline cell access helpers; inner-loop callers should bypass these.
    inline Cell *at(int x, int y) {
        if (x >= 0 && x < SZ && y >= 0 && y < SZ)
            return &cells[y * SZ + x];
        return at_border(x, y);
    }
    Cell *at_border(int x, int y); // defined in chunk_view.cpp; covers cross-chunk

    static uint32_t hash_u32(uint32_t n);
    uint32_t hash3(int x, int y, uint32_t salt) const;
    bool stochastic_div(int x, int y, uint32_t salt, int divisor) const;
    static void pack_velocity(uint8_t &flags, int8_t vx, int8_t vy);
    static void unpack_velocity(uint8_t flags, int8_t &vx, int8_t &vy);
};

} // namespace toprogue
```

- [ ] **Step 2: Implement ChunkView helpers**

```cpp
// gdextension/src/sim/chunk_view.cpp
#include "chunk_view.h"

namespace toprogue {

Cell *ChunkView::at_border(int x, int y) {
    constexpr int SZ_ = SZ;
    if (y < 0)   { return up    ? &cells_up   [(SZ_ + y) * SZ_ + x] : nullptr; }
    if (y >= SZ_){ return down  ? &cells_down [(y - SZ_) * SZ_ + x] : nullptr; }
    if (x < 0)   { return left  ? &cells_left [y * SZ_ + (SZ_ + x)] : nullptr; }
    return         right ? &cells_right[y * SZ_ + (x - SZ_)] : nullptr;
}

uint32_t ChunkView::hash_u32(uint32_t n) {
    n = (n >> 16) ^ n; n *= 0xed5ad0bb;
    n = (n >> 16) ^ n; n *= 0xac4c1b51;
    n = (n >> 16) ^ n; return n;
}

uint32_t ChunkView::hash3(int x, int y, uint32_t salt) const {
    return hash_u32(static_cast<uint32_t>(x) ^
        hash_u32(static_cast<uint32_t>(y) ^ frame_seed ^ salt));
}

bool ChunkView::stochastic_div(int x, int y, uint32_t salt, int divisor) const {
    if (divisor <= 0) return false;
    return (hash3(x, y, salt) % static_cast<uint32_t>(divisor)) == 0;
}

void ChunkView::pack_velocity(uint8_t &flags, int8_t vx, int8_t vy) {
    uint8_t pvx = static_cast<uint8_t>(vx + 8) & 0x0F;
    uint8_t pvy = static_cast<uint8_t>(vy + 8) & 0x0F;
    flags = static_cast<uint8_t>((pvx << 4) | pvy);
}

void ChunkView::unpack_velocity(uint8_t flags, int8_t &vx, int8_t &vy) {
    vx = static_cast<int8_t>((flags >> 4) & 0x0F) - 8;
    vy = static_cast<int8_t>(flags & 0x0F) - 8;
}

} // namespace toprogue
```

- [ ] **Step 3: Build (the new file should compile in isolation)**

```bash
cd gdextension && ./build.sh debug
```

Expected: clean build (the new file is unused so far — confirms no header
errors).

- [ ] **Step 4: Update Simulator to build ChunkView and pass it down**

In `simulator.h`, add `#include "chunk_view.h"` and change rule signatures
from `void run_lava(SimContext &)` to `void run_lava(ChunkView &)`. Also
add a temporary thread-local view storage for `_group_task_body` to read:

```cpp
private:
    godot::Vector<ChunkView> _phase_views;
```

In `simulator.cpp`, in `tick()`'s phase-loop body, before
`add_group_task`, build the views in parallel order:

```cpp
_phase_views.clear();
for (Chunk *c : _phase_chunks) {
    ChunkView v;
    v.center = c;
    v.up = c->get_neighbor_up().ptr();
    v.down = c->get_neighbor_down().ptr();
    v.left = c->get_neighbor_left().ptr();
    v.right = c->get_neighbor_right().ptr();
    v.cells = c->cells;
    v.cells_up    = v.up    ? v.up   ->cells : nullptr;
    v.cells_down  = v.down  ? v.down ->cells : nullptr;
    v.cells_left  = v.left  ? v.left ->cells : nullptr;
    v.cells_right = v.right ? v.right->cells : nullptr;
    MaterialTable *mt = MaterialTable::get_singleton();
    v.frame_seed = _current_frame_seed;
    v.frame_index = _frame_index;
    v.air_id   = mt->get_MAT_AIR();
    v.gas_id   = mt->get_MAT_GAS();
    v.lava_id  = mt->get_MAT_LAVA();
    v.water_id = mt->get_MAT_WATER();
    _phase_views.push_back(v);
}
```

Replace `tick_chunk(_phase_chunks[index])` body to call rules with
`_phase_views[index]`.

- [ ] **Step 5: Migrate run_lava — extract inner-loop from rules/lava.cpp**

Change the signature to `void run_lava(ChunkView &v)`. Inside the function:

```cpp
void run_lava(ChunkView &v) {
    Chunk *chunk = v.center;
    if (!chunk) return;
    godot::Rect2i dr = chunk->dirty_rect;
    if (dr.size.x <= 0 || dr.size.y <= 0) return;

    int air_id  = v.air_id;
    int lava_id = v.lava_id;

    // Two regions: inner (no border crossing) and border (uses v.at()).
    int x0 = dr.position.x, y0 = dr.position.y;
    int x1 = x0 + dr.size.x, y1 = y0 + dr.size.y;

    // Inner box: [max(x0,1), min(x1, SZ-1)) × [max(y0,1), min(y1, SZ-1))
    int ix0 = std::max(x0, 1), iy0 = std::max(y0, 1);
    int ix1 = std::min(x1, ChunkView::SZ - 1);
    int iy1 = std::min(y1, ChunkView::SZ - 1);

    constexpr int SZ = ChunkView::SZ;
    Cell *cells = v.cells;

    auto step_lava_at = [&](int x, int y, Cell &self,
                            const Cell &n_up, const Cell &n_down,
                            const Cell &n_left, const Cell &n_right) {
        // PASTE the entire body of the existing per-cell logic here,
        // replacing every reference like `n_up_cell` with `n_up`, etc.
        // The arithmetic is identical to today's lava.cpp lines 71-265.
        //
        // The only writes go through helper lambdas:
        //   write_self(c)  ->  cells[y*SZ+x] = c; mark_dirty(x,y);
        //   write_neigh(...) -> uses v.at(x±1,y±1), null-check, then assign.
        // (Today's ctx.write_cell / ctx.swap_cell encapsulate this; we
        //  inline equivalents to drop the SimContext indirection.)
    };

    auto mark_dirty_local = [&](int x, int y) {
        chunk->extend_next_dirty_rect(x, y, x + 1, y + 1);
        chunk->set_sleeping(false);
    };

    // Inner loop: read neighbors via direct indexing, no branches.
    for (int y = iy0; y < iy1; y++) {
        for (int x = ix0; x < ix1; x++) {
            Cell &self = cells[y * SZ + x];
            int m = self.material;
            if (m != lava_id && m != air_id) continue;
            // Quick gate: check 4 neighbors for any lava
            const Cell &n_up    = cells[(y-1)*SZ + x];
            const Cell &n_down  = cells[(y+1)*SZ + x];
            const Cell &n_left  = cells[y*SZ + (x-1)];
            const Cell &n_right = cells[y*SZ + (x+1)];
            if (m == air_id &&
                n_up.material   != lava_id && n_down.material != lava_id &&
                n_left.material != lava_id && n_right.material != lava_id) continue;
            step_lava_at(x, y, self, n_up, n_down, n_left, n_right);
        }
    }

    // Border loop: 4 strips that touch x=0, x=SZ-1, y=0, y=SZ-1 within dr.
    auto run_one = [&](int x, int y) {
        Cell *self_p = v.at(x, y);
        if (!self_p) return;
        Cell self = *self_p;
        int m = self.material;
        if (m != lava_id && m != air_id) return;
        Cell n_up    = v.at(x, y-1) ? *v.at(x, y-1) : Cell{0,0,0,0};
        Cell n_down  = v.at(x, y+1) ? *v.at(x, y+1) : Cell{0,0,0,0};
        Cell n_left  = v.at(x-1, y) ? *v.at(x-1, y) : Cell{0,0,0,0};
        Cell n_right = v.at(x+1, y) ? *v.at(x+1, y) : Cell{0,0,0,0};
        if (m == air_id &&
            n_up.material   != lava_id && n_down.material != lava_id &&
            n_left.material != lava_id && n_right.material != lava_id) return;
        step_lava_at(x, y, self, n_up, n_down, n_left, n_right);
    };
    if (y0 < 1)               for (int x = x0; x < x1; x++) run_one(x, y0);
    if (y1 > SZ - 1)          for (int x = x0; x < x1; x++) run_one(x, y1 - 1);
    if (x0 < 1)               for (int y = std::max(y0,1); y < std::min(y1,SZ-1); y++) run_one(x0, y);
    if (x1 > SZ - 1)          for (int y = std::max(y0,1); y < std::min(y1,SZ-1); y++) run_one(x1 - 1, y);
}
```

The `step_lava_at` body is mechanical: copy lines 94–264 of the current
`lava.cpp` `run_lava` function, replacing `self->X` with `self.X`,
`n_up_cell.X` with `n_up.X`, etc. Use `v.pack_velocity` / `v.unpack_velocity`
in place of `ctx.pack_velocity` / `ctx.unpack_velocity`. Replace
`ctx.write_cell(x, y, c)` with:

```cpp
cells[y*SZ + x] = c;
mark_dirty_local(x, y);
```

For writes that may cross into a neighbor (the lambda must handle this),
use `Cell *p = v.at(nx, ny); if (p) { *p = c; /* mark neighbor dirty */ }`.

- [ ] **Step 6: Build + snapshot**

```bash
cd gdextension && ./build.sh debug
godot --headless --path . -s addons/gut/gut_cmdln.gd \
      -gtest=res://tests/unit/test_sim_snapshot.gd -gexit
```

Expected: clean build, snapshot hash UNCHANGED. If hash differs, the
inner-loop translation has a bug — diff the migrated body against
`lava.cpp` line by line.

- [ ] **Step 7: Commit lava migration**

```bash
git add gdextension/src/sim/chunk_view.{h,cpp} \
        gdextension/src/sim/simulator.{h,cpp} \
        gdextension/src/sim/rules/lava.{h,cpp} \
        gdextension/SConstruct  # if chunk_view.cpp needs explicit add
git commit -m "refactor: introduce ChunkView; migrate lava rule to inner/border split

ChunkView pre-resolves neighbor pointers once per chunk per tick. Lava
rule's inner loop now uses direct array indexing (no cell_at branches);
border strips fall back to ChunkView::at(). Snapshot hash unchanged."
```

- [ ] **Step 8: Repeat Steps 5–7 for gas rule**

Apply the same inner/border split pattern to `rules/gas.cpp`. The current
`run_gas` is in the file; signature change `SimContext` → `ChunkView`,
inner loop direct-indexed, border strips via `v.at()`. Build + snapshot
must remain unchanged. Commit.

- [ ] **Step 9: Repeat for burning rule**

Apply same pattern to `rules/burning.cpp`. Build + snapshot unchanged.
Commit.

- [ ] **Step 10: Migrate injection rule**

`rules/injection.cpp` doesn't grid-scan; it walks AABBs from
`chunk->take_injections()`. Just change signature `SimContext` → `ChunkView`
and route writes through `v.at()` / `v.cells`. Build + snapshot unchanged.
Commit.

- [ ] **Step 11: Bench + appendix**

```bash
godot --headless --path . -s tools/sim_bench.gd
```

Append `Task 3 result`. Expected: median ms/tick noticeably lower than
Task 2.

---

## Task 4: Shrinking dirty rect + handler `did-change` return

`next_dirty_rect` currently extends on every *write*; we change it to
extend only on *cells that actually changed value*. Settled puddles will
shrink to empty and the chunk will sleep.

**Files:**
- Modify: `gdextension/src/sim/rules/lava.cpp`
- Modify: `gdextension/src/sim/rules/gas.cpp`
- Modify: `gdextension/src/sim/rules/burning.cpp`
- Modify: `gdextension/src/sim/rules/injection.cpp`
- Modify: `gdextension/src/terrain/chunk.h` (helper)
- Create: `tests/unit/test_sim_settled_sleep.gd`

- [ ] **Step 1: Add a helper that extends the dirty rect only on cell-value change**

In `chunk.h`, add inline helper near `extend_next_dirty_rect`:

```cpp
// Extend the next dirty rect ONLY if the new cell value differs from the
// existing one. Returns true if a write actually happened.
inline bool write_cell_if_changed(int x, int y, const Cell &nv) {
    Cell &slot = cells[y * CHUNK_SIZE + x];
    if (slot.material == nv.material && slot.health == nv.health &&
        slot.temperature == nv.temperature && slot.flags == nv.flags) {
        return false;
    }
    slot = nv;
    extend_next_dirty_rect(x, y, x + 1, y + 1);
    return true;
}
```

- [ ] **Step 2: Plumb the helper through ChunkView**

In `chunk_view.h`, add:

```cpp
inline bool write_changed(int x, int y, const Cell &nv) {
    Cell *slot = at(x, y);
    if (!slot) return false;
    if (slot->material == nv.material && slot->health == nv.health &&
        slot->temperature == nv.temperature && slot->flags == nv.flags) return false;
    *slot = nv;
    // Mark dirty on the *target* chunk (may be a neighbor).
    Chunk *target = (x >= 0 && x < SZ && y >= 0 && y < SZ) ? center
                  : (y < 0 ? up : (y >= SZ ? down : (x < 0 ? left : right)));
    int lx, ly;
    if (target == center) { lx = x; ly = y; }
    else if (target == up)    { lx = x;       ly = SZ + y; }
    else if (target == down)  { lx = x;       ly = y - SZ; }
    else if (target == left)  { lx = SZ + x;  ly = y; }
    else                      { lx = x - SZ;  ly = y; }
    target->extend_next_dirty_rect(lx, ly, lx + 1, ly + 1);
    return true;
}
```

- [ ] **Step 3: Replace every `cells[idx] = c; mark_dirty(...)` in lava.cpp with `v.write_changed(x, y, c)`**

Mechanical edit. The inner-loop writes that previously did
`cells[y*SZ + x] = c; mark_dirty_local(x, y)` become
`v.write_changed(x, y, c)`. Border lambda already used `v.at(...) = c`;
replace with `v.write_changed(...)`.

- [ ] **Step 4: Same for gas.cpp, burning.cpp, injection.cpp**

Apply identically. Injection rule's writes are unconditional today
(injection always wakes the cell); use `write_changed` anyway — if the
injected value matches the slot's current value, it's a true no-op and
correctly leaves the dirty rect untouched.

- [ ] **Step 5: Add the settled-sleep test**

```gdscript
# tests/unit/test_sim_settled_sleep.gd
extends GutTest

func test_settled_lava_puddle_chunk_sleeps_within_30_ticks() -> void:
    var sim: Simulator = Simulator.new()
    sim.set_world_seed(0xBEEF)

    var chunks := {}
    var c: Chunk = Chunk.new()
    c.coord = Vector2i(0, 0)
    chunks[c.coord] = c
    sim.set_chunks(chunks)

    # Drop a small still puddle. With no neighbors and zero velocity, the
    # rule should converge to all-quiet quickly.
    var bytes := c.get_cells_data()
    var sz := Chunk.get_chunk_size()
    for dy in range(-3, 4):
        for dx in range(-3, 4):
            var x := 128 + dx
            var y := 128 + dy
            var idx := (y * sz + x) * 4
            bytes[idx + 0] = 4    # MAT_LAVA
            bytes[idx + 1] = 100
            bytes[idx + 2] = 200
            bytes[idx + 3] = 0x88 # vx=0 vy=0
    c.set_cells_data(bytes)
    c.dirty_rect = Rect2i(125, 125, 7, 7)
    c.sleeping = false

    for i in 30:
        sim.tick()

    assert_true(c.sleeping, "Chunk should be sleeping after 30 ticks")
```

- [ ] **Step 6: Build + run all tests**

```bash
cd gdextension && ./build.sh debug
cd .. && godot --headless --path . -s addons/gut/gut_cmdln.gd \
      -gtest=res://tests/unit/test_sim_snapshot.gd -gexit
godot --headless --path . -s addons/gut/gut_cmdln.gd \
      -gtest=res://tests/unit/test_sim_settled_sleep.gd -gexit
```

Snapshot hash WILL change in this Task (semantic change: dirty rect
shrinks → which cells get re-evaluated next frame differs → randomness
seed paths can diverge for stochastic outflow). Expected: snapshot test
fails; settled-sleep test passes.

- [ ] **Step 7: Re-record the snapshot baseline**

In `test_sim_snapshot.gd`, set `EXPECTED_SHA256 := ""` to re-print the
warning, run the test, copy the new hash, set the constant to that hash.

- [ ] **Step 8: Bench + appendix**

```bash
godot --headless --path . -s tools/sim_bench.gd
```

Expected: settled-state median ms/tick drops dramatically (chunks sleeping).

- [ ] **Step 9: Commit**

```bash
git add gdextension/src/terrain/chunk.h \
        gdextension/src/sim/chunk_view.h \
        gdextension/src/sim/rules/*.cpp \
        tests/unit/test_sim_snapshot.gd \
        tests/unit/test_sim_settled_sleep.gd \
        docs/superpowers/specs/2026-05-02-sim-perf-noita-architecture-design.md
git commit -m "perf: shrink dirty rect to actually-changed cells; settled chunks sleep

Rules now write through ChunkView::write_changed, which compares against
the existing cell value before extending next_dirty_rect. Settled lava
puddles converge to no-change → empty rect → chunk sleeps. New
behavioral test asserts a still puddle sleeps within 30 ticks. Snapshot
baseline re-recorded due to expected semantic divergence."
```

---

## Task 5: Drop intra-chunk atomics; cross-chunk `wake_pending`

Within one chunk, the per-tick scan is single-threaded by the parity
invariant (Task 8 makes this explicit; today it's already the case
because the same chunk is never processed twice in one tick). So we can
replace the 4 atomic CAS loops in `extend_next_dirty_rect` with plain
ints. Cross-chunk wakes (border writes into a neighbor) need an atomic
flag.

**Files:**
- Modify: `gdextension/src/terrain/chunk.h`
- Modify: `gdextension/src/terrain/chunk.cpp`
- Modify: `gdextension/src/sim/simulator.cpp`

- [ ] **Step 1: Replace atomic next_dirty_rect with plain int32_t**

In `chunk.h`, change:

```cpp
private:
    std::atomic<int32_t> next_min_x{ INT32_MAX };
    std::atomic<int32_t> next_min_y{ INT32_MAX };
    std::atomic<int32_t> next_max_x{ INT32_MIN };
    std::atomic<int32_t> next_max_y{ INT32_MIN };
```

to:

```cpp
private:
    int32_t next_min_x = INT32_MAX;
    int32_t next_min_y = INT32_MAX;
    int32_t next_max_x = INT32_MIN;
    int32_t next_max_y = INT32_MIN;
public:
    std::atomic<bool> wake_pending{ false };  // set by cross-chunk writes
```

Drop `<atomic>` from the includes only if no longer needed elsewhere
(`wake_pending` still needs it).

- [ ] **Step 2: Rewrite extend_next_dirty_rect/take_next_dirty_rect/reset_next_dirty_rect without CAS**

In `chunk.cpp`, replace the 3 functions with their plain-int equivalents:

```cpp
bool Chunk::extend_next_dirty_rect(int x0, int y0, int x1, int y1) {
    bool changed = false;
    if (x0 < next_min_x) { next_min_x = x0; changed = true; }
    if (y0 < next_min_y) { next_min_y = y0; changed = true; }
    if (x1 > next_max_x) { next_max_x = x1; changed = true; }
    if (y1 > next_max_y) { next_max_y = y1; changed = true; }
    return changed;
}

Rect2i Chunk::take_next_dirty_rect() {
    int32_t mx = next_min_x, my = next_min_y;
    int32_t Mx = next_max_x, My = next_max_y;
    next_min_x = INT32_MAX; next_min_y = INT32_MAX;
    next_max_x = INT32_MIN; next_max_y = INT32_MIN;
    if (Mx < mx || My < my) return Rect2i();
    return Rect2i(mx, my, Mx - mx, My - my);
}

void Chunk::reset_next_dirty_rect() {
    next_min_x = INT32_MAX; next_min_y = INT32_MAX;
    next_max_x = INT32_MIN; next_max_y = INT32_MIN;
}
```

- [ ] **Step 3: When a write crosses into a neighbor, set neighbor's wake_pending**

In `chunk_view.h::write_changed`, after `target->extend_next_dirty_rect(...)`:

```cpp
if (target != center) {
    target->wake_pending.store(true, std::memory_order_relaxed);
}
return true;
```

- [ ] **Step 4: Promote wake_pending neighbors at end of tick**

In `simulator.cpp`, at the very end of `Simulator::tick()` (after
`upload_dirty_textures();`), add:

```cpp
// Promote any chunk whose neighbor pushed border writes into it.
Array keys = _chunks.keys();
for (int i = 0; i < keys.size(); i++) {
    Ref<Chunk> c = _chunks[keys[i]];
    if (c.is_valid() && c->wake_pending.load(std::memory_order_relaxed)) {
        c->wake_pending.store(false, std::memory_order_relaxed);
        c->set_sleeping(false);
        add_active(c.ptr());
    }
}
```

(After Task 7+, this becomes O(active set) instead of O(all chunks); for
now O(N) over all loaded chunks is fine.)

- [ ] **Step 5: Build, run snapshot + sleep tests**

```bash
cd gdextension && ./build.sh debug
godot --headless --path . -s addons/gut/gut_cmdln.gd \
      -gtest=res://tests/unit/test_sim_snapshot.gd -gexit
godot --headless --path . -s addons/gut/gut_cmdln.gd \
      -gtest=res://tests/unit/test_sim_settled_sleep.gd -gexit
```

Both expected to PASS (snapshot hash should be stable since this is a
no-op change to the *values* written; only the synchronization mechanism
changed).

- [ ] **Step 6: Bench + appendix**

```bash
godot --headless --path . -s tools/sim_bench.gd
```

Append `Task 5 result`.

- [ ] **Step 7: Commit**

```bash
git add gdextension/src/terrain/chunk.{h,cpp} \
        gdextension/src/sim/chunk_view.h \
        gdextension/src/sim/simulator.cpp \
        docs/superpowers/specs/2026-05-02-sim-perf-noita-architecture-design.md
git commit -m "perf: drop atomic CAS on intra-chunk dirty rect; wake_pending for crossings

Each chunk is processed by exactly one worker per tick (parity
invariant), so next_min/max_x/y are plain int32_t now — no CAS loop on
every cell write. Cross-chunk writes set the neighbor's atomic
wake_pending; Simulator::tick promotes pending neighbors at end of
frame."
```

---

## Task 6: SoA cell storage

Change Chunk's cells from AoS `Cell[]` to SoA `material[] / health[] /
temperature[] / flags[]`. Keep the AoS RGBA8 byte format at
`get_cells_data` / `set_cells_data` boundary (used by tests, snapshots,
save/load).

**Files:**
- Modify: `gdextension/src/terrain/chunk.h`
- Modify: `gdextension/src/terrain/chunk.cpp`
- Modify: `gdextension/src/terrain/chunk_manager.cpp` (one read in `read_region`)
- Modify: `gdextension/src/sim/chunk_view.h`
- Modify: `gdextension/src/sim/chunk_view.cpp`
- Modify: `gdextension/src/sim/sim_context.cpp` (still used by border helpers if anything else hits it)
- Modify: `gdextension/src/sim/rules/*.cpp`
- Modify: `gdextension/src/physics/*.cpp` (any caller that reads `cells[]` directly)

- [ ] **Step 1: Audit current direct accessors**

Run, from project root:

```bash
grep -rn 'cells\[' gdextension/src
grep -rn 'cells_ptr\|->cells' gdextension/src
```

List every hit. The migration touches each location. Save the list as a
checklist in your scratch buffer.

- [ ] **Step 2: Add SoA storage to Chunk; keep AoS as a temporary view for migration**

In `chunk.h`, replace `Cell cells[CELL_COUNT] = {};` with:

```cpp
struct ChunkCells {
    alignas(64) uint8_t material   [CELL_COUNT] = {};
    alignas(64) uint8_t health     [CELL_COUNT] = {};
    alignas(64) uint8_t temperature[CELL_COUNT] = {};
    alignas(64) uint8_t flags      [CELL_COUNT] = {};
};
ChunkCells _cells;

// SoA accessors (the new hot path).
uint8_t *material_ptr()    { return _cells.material; }
uint8_t *health_ptr()      { return _cells.health; }
uint8_t *temperature_ptr() { return _cells.temperature; }
uint8_t *flags_ptr()       { return _cells.flags; }
const uint8_t *material_ptr()    const { return _cells.material; }
const uint8_t *health_ptr()      const { return _cells.health; }
const uint8_t *temperature_ptr() const { return _cells.temperature; }
const uint8_t *flags_ptr()       const { return _cells.flags; }
```

Remove `Cell *cells_ptr() { return cells; }` and the public `Cell cells[CELL_COUNT]` field.

- [ ] **Step 3: Update get_cells_data / set_cells_data to pack/unpack**

In `chunk.cpp`:

```cpp
PackedByteArray Chunk::get_cells_data() const {
    PackedByteArray out;
    out.resize(CELL_COUNT * 4);
    uint8_t *p = out.ptrw();
    for (int i = 0; i < CELL_COUNT; i++) {
        p[i*4 + 0] = _cells.material[i];
        p[i*4 + 1] = _cells.health[i];
        p[i*4 + 2] = _cells.temperature[i];
        p[i*4 + 3] = _cells.flags[i];
    }
    return out;
}

void Chunk::set_cells_data(const PackedByteArray &v) {
    if (v.size() != CELL_COUNT * 4) {
        UtilityFunctions::push_error(
            String("Chunk.set_cells_data: expected ") + String::num_int64(CELL_COUNT * 4) +
            String(" bytes, got ") + String::num_int64(v.size()));
        return;
    }
    const uint8_t *p = v.ptr();
    for (int i = 0; i < CELL_COUNT; i++) {
        _cells.material[i]    = p[i*4 + 0];
        _cells.health[i]      = p[i*4 + 1];
        _cells.temperature[i] = p[i*4 + 2];
        _cells.flags[i]       = p[i*4 + 3];
    }
}
```

- [ ] **Step 4: Update Chunk::upload_texture's pack_tile_aos to read SoA**

Replace the existing pack helper with:

```cpp
static inline void pack_tile_aos(const Chunk &chunk, int tile_x, int tile_y,
                                 uint8_t *out) {
    constexpr int SZ = Chunk::CHUNK_SIZE;
    constexpr int TS = Chunk::TILE_SIZE;
    const uint8_t *m = chunk.material_ptr();
    const uint8_t *h = chunk.health_ptr();
    const uint8_t *t = chunk.temperature_ptr();
    const uint8_t *f = chunk.flags_ptr();
    int x0 = tile_x * TS, y0 = tile_y * TS;
    for (int ly = 0; ly < TS; ly++) {
        for (int lx = 0; lx < TS; lx++) {
            int src = (y0 + ly) * SZ + (x0 + lx);
            int dst = (ly * TS + lx) * 4;
            out[dst + 0] = m[src];
            out[dst + 1] = h[src];
            out[dst + 2] = t[src];
            out[dst + 3] = f[src];
        }
    }
}
```

Update both `upload_texture` and `upload_texture_full` to call
`pack_tile_aos(*this, tx, ty, buf.ptrw())`.

- [ ] **Step 5: Update ChunkView to expose SoA pointers**

In `chunk_view.h`, replace AoS pointers with:

```cpp
struct ChunkView {
    Chunk *center, *up, *down, *left, *right;

    uint8_t *mat,         *mat_up,         *mat_down,         *mat_left,         *mat_right;
    uint8_t *health,      *health_up,      *health_down,      *health_left,      *health_right;
    uint8_t *temperature, *temperature_up, *temperature_down, *temperature_left, *temperature_right;
    uint8_t *flags,       *flags_up,       *flags_down,       *flags_left,       *flags_right;

    uint32_t frame_seed;
    int frame_index;
    int air_id, gas_id, lava_id, water_id;

    static constexpr int SZ = Chunk::CHUNK_SIZE;

    // Border helpers replaced by per-component getters; the AoS Cell value
    // type still exists (for InjectionAABB and as a return convenience).
    Cell read(int x, int y);
    bool write_changed(int x, int y, const Cell &nv);

    static uint32_t hash_u32(uint32_t n);
    uint32_t hash3(int x, int y, uint32_t salt) const;
    bool stochastic_div(int x, int y, uint32_t salt, int divisor) const;
    static void pack_velocity(uint8_t &flags, int8_t vx, int8_t vy);
    static void unpack_velocity(uint8_t flags, int8_t &vx, int8_t &vy);
};
```

In `chunk_view.cpp`, implement `read` / `write_changed`:

```cpp
Cell ChunkView::read(int x, int y) {
    if (x >= 0 && x < SZ && y >= 0 && y < SZ) {
        int i = y * SZ + x;
        return Cell{ mat[i], health[i], temperature[i], flags[i] };
    }
    if (y < 0 && up) {
        int i = (SZ + y) * SZ + x;
        return Cell{ mat_up[i], health_up[i], temperature_up[i], flags_up[i] };
    }
    if (y >= SZ && down) {
        int i = (y - SZ) * SZ + x;
        return Cell{ mat_down[i], health_down[i], temperature_down[i], flags_down[i] };
    }
    if (x < 0 && left) {
        int i = y * SZ + (SZ + x);
        return Cell{ mat_left[i], health_left[i], temperature_left[i], flags_left[i] };
    }
    if (x >= SZ && right) {
        int i = y * SZ + (x - SZ);
        return Cell{ mat_right[i], health_right[i], temperature_right[i], flags_right[i] };
    }
    return Cell{ 0, 0, 0, 0 };
}

bool ChunkView::write_changed(int x, int y, const Cell &nv) {
    auto try_write = [&](Chunk *target, uint8_t *m, uint8_t *h,
                         uint8_t *t, uint8_t *f, int lx, int ly) -> bool {
        if (!target) return false;
        int i = ly * SZ + lx;
        if (m[i] == nv.material && h[i] == nv.health &&
            t[i] == nv.temperature && f[i] == nv.flags) return false;
        m[i] = nv.material; h[i] = nv.health;
        t[i] = nv.temperature; f[i] = nv.flags;
        target->extend_next_dirty_rect(lx, ly, lx + 1, ly + 1);
        if (target != center)
            target->wake_pending.store(true, std::memory_order_relaxed);
        return true;
    };
    if (x >= 0 && x < SZ && y >= 0 && y < SZ)
        return try_write(center, mat, health, temperature, flags, x, y);
    if (y < 0)    return try_write(up,    mat_up,    health_up,    temperature_up,    flags_up,    x, SZ + y);
    if (y >= SZ)  return try_write(down,  mat_down,  health_down,  temperature_down,  flags_down,  x, y - SZ);
    if (x < 0)    return try_write(left,  mat_left,  health_left,  temperature_left,  flags_left,  SZ + x, y);
    /* x >= SZ */ return try_write(right, mat_right, health_right, temperature_right, flags_right, x - SZ, y);
}
```

- [ ] **Step 6: Update Simulator's view-build to populate SoA pointers**

In `simulator.cpp`, where the view is constructed, replace the AoS pointer
assignments with the SoA equivalents:

```cpp
v.mat   = c->material_ptr();      v.mat_up    = v.up    ? v.up   ->material_ptr()    : nullptr;
v.health= c->health_ptr();        v.health_up = v.up    ? v.up   ->health_ptr()      : nullptr;
// ... etc for temperature, flags, and down/left/right neighbors.
```

- [ ] **Step 7: Migrate each rule to read SoA via `view.mat[idx]` etc.**

For each of `lava.cpp`, `gas.cpp`, `burning.cpp`, `injection.cpp`:

- Inner loop: replace `cells[idx]` with explicit per-component reads:
  ```cpp
  int m = view.mat[idx];
  int h = view.health[idx];
  // ...
  ```
  And neighbor reads similarly: `view.mat[(y-1)*SZ + x]` etc.
- All writes go through `view.write_changed(x, y, Cell{m, h, t, f})`.
- Border lambdas use `view.read(x, y)` which returns a `Cell` by value.

This is the most mechanical and most error-prone step. Migrate one rule
at a time, building + running the snapshot test after each:

```bash
cd gdextension && ./build.sh debug
cd .. && godot --headless --path . -s addons/gut/gut_cmdln.gd \
      -gtest=res://tests/unit/test_sim_snapshot.gd -gexit
```

Snapshot hash should be UNCHANGED (this is a pure storage layout change;
all arithmetic identical). Commit per-rule.

- [ ] **Step 8: Migrate non-rule callers**

`chunk_manager.cpp::read_region` line 434:

```cpp
// Old:
//   out[out_idx] = chunk->cells[local_y * CHUNK_SIZE + local_x].material;
// New:
out[out_idx] = chunk->material_ptr()[local_y * CHUNK_SIZE + local_x];
```

Audit the other hits from Step 1's grep (likely `physics/`,
`terrain/terrain_modifier.cpp`, etc.) and convert each. Build + snapshot
must remain unchanged after every conversion.

- [ ] **Step 9: Delete obsolete `SimContext` if unused**

If after the migration nothing references `SimContext` any more, delete
`gdextension/src/sim/sim_context.{h,cpp}` and remove their includes from
the rule files. Otherwise keep them.

```bash
grep -rn SimContext gdextension/src
```

- [ ] **Step 10: Final build + snapshot + sleep tests + smoke**

```bash
cd gdextension && ./build.sh debug
cd .. && godot --headless --path . -s addons/gut/gut_cmdln.gd \
      -gtest=res://tests/unit/test_sim_snapshot.gd -gexit
godot --headless --path . -s addons/gut/gut_cmdln.gd \
      -gtest=res://tests/unit/test_sim_settled_sleep.gd -gexit
```

Open Godot editor, F5, smoke test player walking through lava.

- [ ] **Step 11: Bench + appendix**

```bash
godot --headless --path . -s tools/sim_bench.gd
```

Append `Task 6 result`. Expected: gate-scan (`mat[idx] == lava_id`)
becomes much faster — measurable in mostly-inert chunks.

- [ ] **Step 12: Final commit (or accumulated commits if you've been
       committing per Step 7 sub-rule)**

```bash
git add gdextension/src/terrain/chunk.{h,cpp} \
        gdextension/src/sim/chunk_view.{h,cpp} \
        gdextension/src/sim/rules/*.cpp \
        gdextension/src/terrain/chunk_manager.cpp \
        # (and any physics/terrain hits from Step 8)
        docs/superpowers/specs/2026-05-02-sim-perf-noita-architecture-design.md
git commit -m "perf: SoA cell storage; rules read mat/health/temp/flags directly

Chunk now stores cells as four contiguous uint8_t[CELL_COUNT] arrays
(aligned 64). Hot gate scan (mat == lava_id) pulls 4x more cells per
cache line. AoS RGBA8 byte format preserved at the get/set_cells_data
shim for save/load and tests. Snapshot hash unchanged (pure layout
change)."
```

---

## Task 7: Unified per-cell dispatch (rule collapse)

Replace the four sequential rule passes with **one** unified bottom-up
scan over the dirty rect that dispatches by material kind. Drain
injections first.

**Files:**
- Create: `gdextension/src/sim/material_kind.{h,cpp}`
- Modify: `gdextension/src/sim/material_table.h` (add `kind` to MaterialDef)
- Modify: `gdextension/src/sim/material_table.cpp` (populate `kind` per material)
- Modify: `gdextension/src/sim/simulator.{h,cpp}` (collapse rule sequence)
- Modify: `gdextension/src/sim/rules/lava.h` → expose `step_lava(view, x, y, idx)`
- Modify: `gdextension/src/sim/rules/gas.h` → expose `step_gas`
- Modify: `gdextension/src/sim/rules/burning.h` → expose `step_burning` with push semantics

- [ ] **Step 1: Define MaterialKind enum + LUT**

```cpp
// gdextension/src/sim/material_kind.h
#pragma once
#include <cstdint>

namespace toprogue {

enum MaterialKind : uint8_t {
    KIND_INERT   = 0,
    KIND_LAVA    = 1,
    KIND_GAS     = 2,
    KIND_BURNING = 3,
};

// 256-entry LUT, one byte per material id. Built once at sim startup
// from MaterialTable.
struct MaterialKindTable {
    uint8_t kind[256];
};

const MaterialKindTable &material_kind_table();
void rebuild_material_kind_table();

} // namespace toprogue
```

```cpp
// gdextension/src/sim/material_kind.cpp
#include "material_kind.h"
#include "material_table.h"

namespace toprogue {

static MaterialKindTable g_table = {};

const MaterialKindTable &material_kind_table() { return g_table; }

void rebuild_material_kind_table() {
    for (int i = 0; i < 256; i++) g_table.kind[i] = KIND_INERT;
    MaterialTable *mt = MaterialTable::get_singleton();
    g_table.kind[mt->get_MAT_LAVA()] = KIND_LAVA;
    g_table.kind[mt->get_MAT_GAS()]  = KIND_GAS;
    // Burning is a transient state on flammable materials; it is
    // distinguished by a flags bit, not by material id, so the LUT alone
    // can't classify it. step_lava / step_gas / inert handler all check
    // the burning flag bit themselves.
}

} // namespace toprogue
```

- [ ] **Step 2: Call rebuild_material_kind_table on Simulator construction**

In `simulator.cpp`, add a constructor body or a one-time guard:

```cpp
Simulator::Simulator() {
    rebuild_material_kind_table();
}
```

(Add the constructor declaration to `simulator.h` if absent.)

- [ ] **Step 3: Convert each rule body into a `step_*` inline handler**

For each rule, factor out the per-cell logic into:

```cpp
// rules/lava.h
namespace toprogue {
struct ChunkView;
void step_lava(ChunkView &v, int x, int y, int idx);   // implemented inline-ish in lava.cpp
void run_lava_drain(ChunkView &v); // legacy entry — to be removed at end of Task
}
```

Move the per-cell body of `step_lava_at` from Task 3 Step 5 into this new
free function `step_lava`. The dirty-rect-scan loop is REMOVED from the
rule file — that's the simulator's job now.

Same for `gas` and `burning`. For burning, switch ignition logic to push
semantics: when `step_burning` runs on a burning cell, *it* writes
ignition into its 4 flammable neighbors via `view.write_changed`. Inert
flammable cells are no longer visited.

- [ ] **Step 4: Implement the unified scan in Simulator::tick_chunk**

Replace the body of `Simulator::tick_chunk` with:

```cpp
void Simulator::tick_chunk(ChunkView &v) {
    Chunk *chunk = v.center;
    if (!chunk || chunk->get_sleeping()) return;

    // 1) Drain injections first.
    drain_injections(v);

    Rect2i dr = chunk->dirty_rect;
    if (dr.size.x <= 0 || dr.size.y <= 0) return;

    int x0 = dr.position.x, y0 = dr.position.y;
    int x1 = x0 + dr.size.x, y1 = y0 + dr.size.y;
    constexpr int SZ = ChunkView::SZ;

    const auto *kt = &material_kind_table();
    const uint8_t *kind = kt->kind;
    const uint8_t *mat = v.mat;

    // 2) Single unified row-major scan.
    for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
            int idx = y * SZ + x;
            uint8_t m = mat[idx];
            uint8_t k = kind[m];
            uint8_t flg = v.flags[idx];
            bool burning_bit = (flg & 0x01) != 0; // example: low bit reserved for "is burning"
            if (k == KIND_INERT && !burning_bit) continue;
            switch (k) {
                case KIND_LAVA:    step_lava(v, x, y, idx); break;
                case KIND_GAS:     step_gas (v, x, y, idx); break;
                default:           break;
            }
            if (burning_bit) step_burning(v, x, y, idx);
        }
    }
}
```

(The exact "burning bit" check depends on whether your existing burning
rule encodes burning state in flags or via a temperature threshold. Check
`rules/burning.cpp` and use its current trigger condition as the gate.)

- [ ] **Step 5: Remove `run_injection`, `run_lava`, `run_gas`, `run_burning` calls**

Delete the four sequential `run_*(ctx)` lines from where they were called
(today's `Simulator::tick_chunk` lines 104–107 in the original). Also
delete the now-unused dirty-rect-scan loops inside each rule's `run_*`
function — keep only the per-cell handler `step_*` functions.

- [ ] **Step 6: Implement `drain_injections` next to the simulator (or in injection.cpp)**

```cpp
// In injection.cpp
void drain_injections(ChunkView &v) {
    Chunk *chunk = v.center;
    auto queued = chunk->take_injections();
    for (const InjectionAABB &q : queued) {
        for (int y = q.min_y; y < q.max_y; y++) {
            for (int x = q.min_x; x < q.max_x; x++) {
                if (x < 0 || x >= ChunkView::SZ || y < 0 || y >= ChunkView::SZ) continue;
                uint8_t kind_target = q.target_kind;
                Cell nv;
                nv.material    = kind_target;
                nv.health      = 200;
                nv.temperature = 220; // tune to match prior behavior
                ChunkView::pack_velocity(nv.flags, q.vel_x, q.vel_y);
                v.write_changed(x, y, nv);
            }
        }
    }
}
```

(Reuse the existing per-injection logic from current `rules/injection.cpp`
verbatim; this is a sketch of the wrapper.)

- [ ] **Step 7: Build, run snapshot + sleep tests**

```bash
cd gdextension && ./build.sh debug
godot --headless --path . -s addons/gut/gut_cmdln.gd \
      -gtest=res://tests/unit/test_sim_snapshot.gd -gexit
godot --headless --path . -s addons/gut/gut_cmdln.gd \
      -gtest=res://tests/unit/test_sim_settled_sleep.gd -gexit
```

Snapshot hash WILL change (unified scan order differs from per-rule
sequential scans). Re-record like Task 4 Step 7. Sleep test must still
pass. If sleep test fails, the unified scan is doing extra work somewhere
— most likely the burning-bit gate is too eager. Diagnose by inspecting
which cells the rule writes during the still-puddle scenario.

- [ ] **Step 8: Add a behavioral conservation test**

```gdscript
# Append to tests/unit/test_sim_snapshot.gd or new test:
func test_lava_density_conserved_within_1pct() -> void:
    var sim: Simulator = Simulator.new()
    sim.set_world_seed(0xCAFE)
    var c: Chunk = Chunk.new()
    c.coord = Vector2i(0, 0)
    sim.set_chunks({c.coord: c})
    # Drop 32x32 lava blob centered at (128,128), density 200.
    var bytes := c.get_cells_data()
    var sz := Chunk.get_chunk_size()
    var initial_density := 0
    for dy in range(-16, 16):
        for dx in range(-16, 16):
            var x := 128 + dx
            var y := 128 + dy
            var idx := (y * sz + x) * 4
            bytes[idx + 0] = 4
            bytes[idx + 1] = 200
            bytes[idx + 2] = 220
            bytes[idx + 3] = 0x88
            initial_density += 200
    c.set_cells_data(bytes)
    c.dirty_rect = Rect2i(112, 112, 32, 32)
    c.sleeping = false
    for i in 50: sim.tick()
    var after := c.get_cells_data()
    var final_density := 0
    for i in range(0, after.size(), 4):
        if after[i] == 4: final_density += after[i + 1]
    var diff := abs(final_density - initial_density)
    assert_lt(float(diff) / initial_density, 0.01,
              "Lava density conservation: started %d ended %d" % [initial_density, final_density])
```

Run; expected PASS.

- [ ] **Step 9: Manual interactive test — the original symptom**

Open Godot editor, F5. Walk player into lava. **Confirm: lava visibly
displaces around the player at frame rate.** This is the headline
acceptance check for the whole redesign.

If displacement still doesn't appear, debug by:
1. Checking that injection events are actually being pushed to chunks
   (add a temporary `UtilityFunctions::print` in `Chunk::push_injection`).
2. Checking that `drain_injections` is running (print at top of function).
3. Checking that the lava rule's outflow cap (`max_outflow = max(1,
   density/2)`) isn't the limiter (this is a rule-design cap, not a perf
   bug; tune if needed).

- [ ] **Step 10: Bench + appendix**

```bash
godot --headless --path . -s tools/sim_bench.gd
```

Append `Task 7 result`. Expected: median ms/tick down significantly from
Task 6 (one scan instead of four).

- [ ] **Step 11: Commit**

```bash
git add gdextension/src/sim/material_kind.{h,cpp} \
        gdextension/src/sim/simulator.{h,cpp} \
        gdextension/src/sim/material_table.{h,cpp} \
        gdextension/src/sim/rules/*.{h,cpp} \
        tests/unit/test_sim_snapshot.gd \
        docs/superpowers/specs/2026-05-02-sim-perf-noita-architecture-design.md
git commit -m "perf: unified per-cell dispatch — collapse 4 rule passes into 1

Per chunk per tick: drain injection queue, then ONE row-major scan over
the dirty rect dispatching on MaterialKind LUT to step_lava /
step_gas / step_burning. Burning switches to push-semantics ignition.
Snapshot baseline re-recorded due to scan-order change. Conservation +
sleep tests still pass."
```

---

## Task 8: Dynamic-parity threading

The 4-phase chunk-checkerboard is wasteful when active chunks fall in
fewer than 4 parity classes. Dispatch only the non-empty classes.

**Files:**
- Modify: `gdextension/src/sim/simulator.h`
- Modify: `gdextension/src/sim/simulator.cpp`

- [ ] **Step 1: Bucket the active list by parity per tick**

In `simulator.cpp`, replace the 4-iteration phase loop in `tick()` with:

```cpp
godot::Vector<Chunk *> buckets[4];
for (int b = 0; b < 4; b++) buckets[b].clear();
for (Chunk *c : _active) {
    if (!c || c->get_sleeping()) continue;
    Vector2i co = c->get_coord();
    int b = (co.x & 1) | ((co.y & 1) << 1);
    buckets[b].push_back(c);
}

for (int b = 0; b < 4; b++) {
    if (buckets[b].size() == 0) continue;

    _phase_chunks = buckets[b];
    // Build views as before.
    _phase_views.clear();
    for (Chunk *c : _phase_chunks) {
        // ... build ChunkView v ... (same as Task 3 Step 4)
        _phase_views.push_back(v);
    }

    if (_serial_mode) {
        for (int i = 0; i < _phase_chunks.size(); i++)
            tick_chunk(_phase_views.write[i]);
    } else {
        WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
        Callable task = callable_mp(this, &Simulator::_group_task_body);
        pool->add_group_task(task, _phase_chunks.size(), -1, true,
            String("Simulator::parity_") + String::num_int64(b));
    }
}
```

Add `bool _serial_mode = false;` field and a binding to set it from
GDScript or from a CLI flag.

- [ ] **Step 2: Bind serial mode toggle**

```cpp
ClassDB::bind_method(D_METHOD("set_serial_mode", "v"), &Simulator::set_serial_mode);
```

```cpp
void Simulator::set_serial_mode(bool v) { _serial_mode = v; }
```

- [ ] **Step 3: Build, run all tests**

```bash
cd gdextension && ./build.sh debug
godot --headless --path . -s addons/gut/gut_cmdln.gd \
      -gtest=res://tests/unit/test_sim_snapshot.gd -gexit
godot --headless --path . -s addons/gut/gut_cmdln.gd \
      -gtest=res://tests/unit/test_sim_settled_sleep.gd -gexit
```

Expected: snapshot hash unchanged (within a parity class, no two chunks
share a border, so the dispatch order is equivalent to the previous
4-phase scheme); sleep test passes.

- [ ] **Step 4: Adjacency stress test**

Manually arrange 4 mutually-adjacent chunks in a 2×2 square (the
player-at-corner case). Tick 200× with lava bridging across all four.
Run a TSan build:

```bash
# (One-shot; do not commit a TSan build artifact.)
cd gdextension && CXXFLAGS="-fsanitize=thread" \
                  LINKFLAGS="-fsanitize=thread" \
                  ./build.sh debug
godot --headless --path . -s tools/sim_bench.gd
```

Expected: no TSan reports. If any race appears, it's most likely a write
into a neighbor's dirty rect (now plain int, not atomic). Resolution:
either (a) move the cross-chunk dirty-rect extension behind a per-chunk
mutex, or (b) buffer cross-chunk writes per-tick and flush them in
`finalize_tick`.

- [ ] **Step 5: Bench + appendix**

```bash
# Re-build without TSan flags first.
cd gdextension && ./build.sh debug
cd .. && godot --headless --path . -s tools/sim_bench.gd
```

Append `Task 8 result`.

- [ ] **Step 6: Final smoke test against acceptance criteria**

Open Godot editor, F5. Run through the spec's interactive scenarios:
- Player swims through lava → visible displacement at frame rate. ✓
- Melee attack into lava → splash propagates within 2 frames. ✓
- 4 chunks active in 2×2 corner pattern → no flicker. ✓
- Settled puddle for 30 s → CPU drops to baseline. ✓

Append the final `Acceptance:` line to the spec appendix with median /
p99 / settled-tick numbers.

- [ ] **Step 7: Commit**

```bash
git add gdextension/src/sim/simulator.{h,cpp} \
        docs/superpowers/specs/2026-05-02-sim-perf-noita-architecture-design.md
git commit -m "perf: dynamic-parity threading — dispatch only non-empty parity classes

Buckets _active by (x&1, y&1) per tick; calls add_group_task once per
non-empty bucket instead of always 4 times. With 4 isolated chunks the
common case becomes a single sync point. Adds --sim-serial-mode toggle
for profiling/fallback."
```

---

## Self-review

- [x] **Spec coverage.** Each numbered section in the spec has a Task:
  §1 ChunkView/raw-pointer → Tasks 1, 3.
  §2 SoA → Task 6.
  §3 Unified dispatch → Task 7.
  §4 Dirty rect / sleep / threading → Tasks 4, 5, 8.
  §5 Texture upload (Texture2DArray) → Task 2.
  §6 Migration order → followed Task-for-Task.
  §7 Injection flow (the original symptom) → Task 7 Step 9 (interactive
  acceptance check).

- [x] **Placeholder scan.** No TBD/TODO; all "fill in details" eliminated.
  `step_lava` body is described as "PASTE the entire body of the existing
  per-cell logic here" — this is intentional and references the exact
  source line range to copy from. The sentinel that needs developer
  judgment is the burning-flag bit identification in Task 7 Step 4 — the
  plan explicitly directs the developer to read `rules/burning.cpp` and
  use its current trigger.

- [x] **Type consistency.** `ChunkView` field names stay stable across
  Tasks 3 → 6 (the SoA migration in Task 6 explicitly enumerates the
  rename from `cells/cells_up/...` to `mat/mat_up/...`). `write_changed`
  is the consistent write API from Task 4 onward. `Chunk::TILE_SIZE` /
  `TILES_PER_SIDE` / `TILE_COUNT` defined in Task 2 reused in Task 6.

- [x] **Build invariant.** Each Task ends with a build + snapshot test
  step; no Task assumes the next was started.
