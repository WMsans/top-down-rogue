# Simulation Performance: Noita-Style Architecture Redesign

**Date**: 2026-05-02
**Author**: Jeremy (with Claude)
**Status**: Draft — pending review

## Background

After the Step 1–8 GLSL → C++ port (commits `f215759`..`d2ddfa3`), the
falling-everything simulation now runs entirely on the CPU through a 4-phase
chunk-checkerboard `WorkerThreadPool` dispatch. Performance has regressed:
stutters/spikes are common and, more critically, simulation throughput is so
low that player movement through lava produces no visible displacement —
injection writes never get processed quickly enough to propagate.

Active-chunk budget is small: at most 4 chunks active at once (player at the
intersection corner of four chunks). Off-camera chunks do not simulate.

This is the "fundamental shift in architecture" pass: collapse to a Noita-style
unified pipeline, not a tweak.

## Diagnosis

In priority order, the costs the current design pays per frame:

1. **Texture upload is full-chunk every frame.** `Chunk::upload_texture_full()`
   allocates a 256 KB `PackedByteArray`, builds a fresh `Image`, then calls
   `ImageTexture::update`. With 4 dirty chunks: ~1 MB GPU upload, 4 image
   allocations, 4 driver-side full-texture replacements per frame on the main
   thread. Prime stutter source.

2. **`tick()` walks `Dictionary _chunks.keys()` and constructs `Ref<Chunk>`
   per key every frame.** Refcount atomics on every chunk in the world, not
   just the active four.

3. **Each rule re-scans the dirty rect.** Four rules
   (`injection → lava → gas → burning`) × ~65k cells per chunk × 4 chunks ≈
   1M cell-visits per frame. Each neighbor read goes through
   `SimContext::cell_at()` → `resolve_target()` (5 branches per read).

4. **Dirty rect only ever grows.** Once disturbed, a chunk's rect inflates
   toward whole-chunk and never shrinks. A settled puddle keeps re-scanning
   the entire chunk forever until exactly zero cells change in one tick.

5. **4-phase chunk-checkerboard with ≤ 4 active chunks is degenerate.** Each
   phase typically holds 0–1 chunk; we dispatch 4 group-tasks per tick to do
   work that should be one parallel batch.

6. **Atomic CAS on every `extend_next_dirty_rect`.** Even single-threaded
   inside one chunk, every cell write does 4 CAS loops.

## Approach (Approach 3: full Noita-style)

### 1. Chunk ownership and the active list

`Simulator` owns `std::vector<Chunk*> _active`. `ChunkManager` maintains it
via `add_active(Chunk*)` / `remove_active(Chunk*)` on chunk wake / unload.
`tick()` iterates raw `Chunk*` — no Dictionary walking, no `Ref<Chunk>`
churn in the hot path. `Ref<Chunk>` survives only at ownership boundaries
(ChunkManager dictionary, GDScript bindings).

### 2. ChunkView and the inner / border split

A small POD `ChunkView` is built once per chunk per tick, *outside* the
parallel section, and passed to the per-chunk worker:

```cpp
struct ChunkView {
    Chunk *center;
    Chunk *up, *down, *left, *right;

    // SoA pointers for center
    uint8_t *mat;
    uint8_t *health;
    uint8_t *temperature;
    uint8_t *flags;

    // SoA pointers for neighbors (nullable when at world edge)
    uint8_t *mat_up, *mat_down, *mat_left, *mat_right;
    // ... same for health/temperature/flags

    const uint8_t *mt_kind;   // material → kind LUT (256 bytes), copied for cache locality
    uint32_t frame_seed;
    uint64_t frame_index;
    uint8_t  air_id, gas_id, lava_id, water_id;
};
```

Every per-chunk scan splits in two:

- **Inner loop**: `y ∈ [1, SZ-2]`, `x ∈ [1, SZ-2]`. Pure pointer arithmetic
  (`mat[y*SZ + x]`, `mat[(y-1)*SZ + x]`, …). No `cell_at`, no branches.
  ~99% of cells in a 256×256 chunk.
- **Border loop**: 4 edges + 4 corners (~1020 cells). Uses the equivalent of
  today's `cell_at()` to resolve neighbor pointers across chunks.

### 3. SoA cell storage

`Chunk::cells[CELL_COUNT]` (AoS `Cell{material, health, temperature, flags}`)
becomes:

```cpp
struct ChunkCells {
    alignas(64) uint8_t material   [CELL_COUNT];
    alignas(64) uint8_t health     [CELL_COUNT];
    alignas(64) uint8_t temperature[CELL_COUNT];
    alignas(64) uint8_t flags      [CELL_COUNT];
};
```

Same total size (256 KB / chunk). The hot gate read (`if (mat == lava_id ||
mat == air_id)`) now pulls only `material` — 4× the cells per cache line on
the dominant scan.

`get_cells_data()` / `set_cells_data()` keep the AoS RGBA8 byte format at
the API boundary (used by save/load and tests). They pack/unpack at the
shim. The bare `Cell` struct survives as a transient value type used by
`InjectionAABB` and border helpers; it no longer corresponds to physical
storage.

`cells_ptr()` is removed. Hot-path access is via `ChunkView` SoA pointers.

### 4. Unified per-cell dispatch (rule collapse)

Per chunk per tick:

1. **Drain the injection queue first**, before the grid scan.
   `chunk->take_injections()` → tight loop that writes cells directly through
   `ChunkView` and extends the next dirty rect. This is what unblocks the
   "player swims through lava but lava doesn't displace" symptom — the
   injection becomes visible to the lava handler in the *same* tick.

2. **One unified row-major scan** over the dirty rect, single direction.
   (The simulation has no gravity — it's a top-down game. Lava and gas
   spread by packed velocity, not by direction. Single-pass is sufficient.)
   For each cell:

   ```cpp
   uint8_t m = mat[idx];
   switch (mt_kind[m]) {
       case KIND_INERT:   continue;
       case KIND_LAVA:    step_lava   (view, x, y, idx); break;
       case KIND_GAS:     step_gas    (view, x, y, idx); break;
       case KIND_BURNING: step_burning(view, x, y, idx); break;
   }
   ```

3. **Rule handlers are `static inline`** in headers; they take
   `ChunkView&` and a precomputed `idx`. Same logic as today, operating on
   SoA pointers.

4. **Push semantics for ignition.** Burning previously walked every cell
   looking for flammable neighbors of burning/lava cells. Under unified
   dispatch, inert flammable cells aren't visited. Fix: when `step_burning`
   runs on a burning cell, *it* writes ignition into its 4 neighbors.
   Equivalent steady-state behavior, scan-friendly.

5. **Determinism preserved.** Same `(world_seed ^ frame_index * 0x9E3779B1)`
   `frame_seed`; same `hash3(x, y, salt)`. Per-cell rule order is fixed
   (a cell is one kind at a time).

### 5. Dirty rect, sleep, and threading

- **Shrinking dirty rect.** Track only *changed* cells, not *visited* cells.
  Handlers return / set a `bool changed`; `next_dirty_rect` is the AABB of
  cells where `changed == true`. Settled puddles tighten to empty in a few
  ticks → chunk sleeps.
- **No atomics inside one chunk.** `next_dirty_rect` is a plain
  `int32_t` quad updated by direct comparison (single-writer per tick by
  threading invariant — see below).
- **Cross-chunk wakes via `std::atomic<bool> wake_pending`.** When a border
  write pushes outflow into a neighbor outside the current parity class, set
  `wake_pending`. `Simulator::finalize_tick()` promotes pending neighbors
  into the active list.
- **Active-list maintenance.** A chunk leaves the active list at
  `finalize_tick()` when its `next_dirty_rect` is empty, its injection queue
  is empty, and `wake_pending` is clear.
- **Dynamic-parity threading.** Bucket `_active` into the 4 chunk-checkerboard
  parity classes per tick; dispatch only non-empty classes via
  `WorkerThreadPool::add_group_task`. With 4 isolated chunks (the common
  case), all four fall into one parity class → one parallel batch, one sync
  point. Cost: O(N) bucket sort per tick.
- **Serial fallback.** A `--sim-serial` runtime flag disables the
  dispatcher; useful for profiling and as an option if threading proves
  unnecessary at the 4-chunk budget.

### 6. Texture upload (verified against godot-cpp API)

godot-cpp 4.x exposes only **full-image** GPU texture updates:

| API | Surface |
|---|---|
| `ImageTexture::update(Image)` | full-image only |
| `ImageTexture::set_image(Image)` | full-image only |
| `RenderingServer::texture_2d_update(rid, image, layer)` | full-image, but **per layer** |
| `Image::blit_rect(src, src_rect, dst)` | CPU-side image-to-image |

Searched: no `update_region`, `texture_update_region`, or `texture_partial`
API exists.

**Conclusion: the only knob is texture size.** We tile each chunk into a
4×4 grid of 64×64 sub-textures so a stir of a few cells uploads
1–4 × 16 KB = 16–64 KB instead of 256 KB.

**Implementation: 5b-B (preferred) — `Texture2DArray`.**

- Each chunk owns one `Texture2DArray` of 16 layers (64×64 RGBA8 each).
- Chunk renders as one `MeshInstance2D` with one quad; the shader picks
  layer = `floor(uv.y * 4) * 4 + floor(uv.x * 4)`.
- Updates use `RenderingServer::texture_2d_update(rid, image, layer)` —
  the `layer` argument is the API hook we exploit.
- One draw call per chunk; only dirty layers re-uploaded.

**Fallback 5b-A — 16 child `MeshInstance2D`s per chunk** with separate
`ImageTexture` per tile, in case the `Texture2DArray` shader path hits
driver issues. 16 draw calls per chunk; Godot's 2D batcher may or may not
merge them.

**Other points:**

- **5c**: SoA → AoS pack happens in the upload step, only over dirty tiles.
- **5e**: `Ref<Image>` and per-layer textures are allocated once at chunk
  creation; `update` calls reuse them.
- **5d**: moving the upload onto worker threads is deferred. With per-tile
  uploads, main-thread cost should be ≤ a few hundred microseconds.

### 7. Injection flow (the original symptom)

The "player walks through lava but lava doesn't displace" bug traces to
two compounding issues:

1. Injection writes happen in `run_injection`, but the affected cells aren't
   processed by `run_lava` until that rule runs *next* in the per-chunk
   sequence. Today this works in principle, but the per-cell cost compounds
   so heavily that the simulation can't keep up with the injection rate.
2. The dirty rect grows but never shrinks, so each tick wastes CPU on
   already-settled cells.

The unified scan (§4) drains injections first and processes them in the
same tick. Combined with §1–§5, the injection → displacement loop should
close inside one frame.

## Public API impact

- `Chunk::cells[]` (public field) → removed. Replaced by private
  `ChunkCells _cells`. Hot-path access is via `ChunkView`.
- `Chunk::cells_ptr()` (Cell*) → removed.
- `SimContext::cell_at()` etc. → still exist for the border helpers, but no
  longer used in inner loops.
- `Chunk::get_cells_data() / set_cells_data()` → keep the AoS RGBA8 wire
  format; pack/unpack at the shim. Tests and save/load are unaffected.
- `Chunk` rendering: now backed by a `Texture2DArray` instead of an
  `ImageTexture`. `render_chunk.gdshader` updates to compute the layer
  index in the fragment shader. The `texture` property binding will need
  to rename or change type — flag for migration impact on GDScript.

## Migration order

Each step is a separate commit; each leaves the project building and the
existing tests passing.

1. **Active list + raw-pointer hot path.** Add
   `Simulator::add_active/remove_active/_active`. `ChunkManager` populates
   it. `tick()` iterates `_active`. Rules unchanged.
2. **Texture upload tiling (Texture2DArray, §6 5b-B).** Ship the stutter fix
   early.
3. **`ChunkView` + inner / border split.** Rules updated one at a time
   (`lava → gas → burning → injection`). Still AoS at this step.
4. **Shrinking dirty rect + handler `did-change` return.**
5. **Drop atomics inside one chunk; cross-chunk `wake_pending`.**
6. **SoA cell storage.** Mechanical migration; `ChunkView` swaps from AoS
   to SoA pointers.
7. **Unified scan + material-kind LUT dispatch (§4).** Collapse the four
   rules.
8. **Dynamic-parity threading (§5).**

## Testing strategy

### Snapshot regression

For each migration step, record `(seed, tick_count, chunks)` → final cell
SHA256.

- **Bit-identical** required after steps 1, 2, 3, 5, 6.
- Steps 4, 7, 8 may diverge (semantic changes to dirty rect / dispatch).
  Replace bit-identical with **behavioral assertions**:
  - Settled puddle → chunk sleeps within N ticks.
  - Total-density conservation within ±1% across a tick (lava and gas).

### Interactive scenarios

- Player swims through lava → visible displacement at frame rate.
- Melee attack into lava → splash propagates within 2 frames.
- 4 chunks active in 2×2 corner pattern → no flicker, no race artifacts.
- Settled lava puddle for 30 seconds → CPU usage drops to baseline.

### Profiling gates

Before/after each step, capture into the appendix below:

- Frame time (median, p99) under a scripted "stir lava and sweep camera"
  scenario.
- Steady-state `Simulator::tick` ms/frame on a settled world.

## Acceptance criteria

- Stir-test scenario: median frame time ≤ 16 ms (60 FPS), p99 ≤ 25 ms.
- Settled world: < 0.5 ms/frame in `Simulator::tick`.
- Player-displaces-lava test: visible displacement within 1 frame of
  contact.

## Risks

- **`Texture2DArray` shader path on certain drivers / mobile.** Mitigation:
  fallback 5b-A (16 child `MeshInstance2D`s) is wired in as a
  compile-time/runtime switch.
- **Determinism drift** during the rule-collapse step (§7 of migration).
  Mitigation: behavioral assertions instead of bit-identical, plus
  golden-image visual check on recorded gameplay.
- **GDScript callers of removed APIs** (`cells_ptr`, raw `cells[]`). Audit
  during step 6.

## Appendix — profiling log

(to be filled in as migration steps land)
