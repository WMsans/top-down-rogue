# Solidity-Aware Dirtying — Design Spec

**Date:** 2026-06-06
**Phase:** 8 (Steady-State Performance), Sub-project 1
**Status:** Approved design, ready for implementation plan

---

## Problem

After the enemy navigation system landed, frame time regressed to ~47–83 ms (12–21 fps).
Profiling shows this is **not** a chunk-generation spike but a **steady-state floor**: with no
chunks streaming, two systems own almost the entire frame:

| System | Cost/frame (steady state) | Work it does every frame |
|---|---|---|
| `NavField` | ~24 ms | `read_region` ×2 (262 KB GPU readback + 65 K-px GDScript copy) + `update_chunk` ×2 (65 K-px GDScript downsample) |
| `TerrainCollisionHelper` | ~25 ms | `rebuild_dirty`: dispatch + `read_collider_buffer` (~10 ms) + consume/build |

### Root cause

`dispatch_simulation` runs every frame and **blanket-marks every loaded chunk dirty**:

```gdscript
# src/core/compute_device.gd:604-606
if world_manager:
    for coord in chunks:
        world_manager.mark_terrain_dirty(coord)   # ALL chunks, every frame
```

`mark_terrain_dirty` dirties **both** NavField and the collision helper
(`src/core/world_manager.gd:86-90`). Because every chunk is re-dirtied every frame, NavField
(budget 2 chunks/frame) can never drain its set, and the collision helper dispatches + reads
back every chunk forever. The sim does this conservatively — it assumes any chunk *might* have
changed — but solidity actually changes only rarely and locally.

### What depends on the blanket dirty

Tracing every `mark_terrain_dirty` caller:

- **Carving** — melee (`compute_device.gd:376-378`), projectiles, digging — already dirties its
  *affected* chunks explicitly. Independent of the blanket dirty.
- **Generation** — `compute_device.gd:561`, `chunk_manager.gd:411` — dirties new chunks explicitly.
- **`terrain_modifier`** placements (gas/lava/blood/fire/material) — dirty their affected chunks.
- **The sim itself** — the *only* consumer that relies on the blanket dirty. The sim changes
  solidity in exactly two places, both "solid → air" removals:
  - `shaders/include/sim/burning.glslinc:76` — flammable wall (wood/coal) burns to `MAT_AIR`.
  - `shaders/include/sim/explode_wave.glslinc:97,126` — explosion wave eats a wall to `MAT_AIR`
    (`MAT_BEDROCK` is immune, `explode_wave.glslinc:109`).

Lava/water/gas/blood/dust only move **non-solid** materials; they never change solidity. Nothing
in the sim *creates* a solid (no air→wall). Solid materials with colliders are: WOOD, STONE,
DIRT, COAL, ICE, BEDROCK (`MaterialRegistry.has_collider`).

Fire is *ignited* via a CPU call (which dirties the chunk once) but then **spreads and consumes
walls over many frames entirely on the GPU**, with nothing re-marking those chunks. So we cannot
simply delete the blanket dirty without losing collision/nav updates for burning/exploding walls.

---

## Goal & success criteria

- **Steady state** (terrain flowing, no carving/combat): NavField & collision-helper dirty sets
  stay empty → both drop from ~24/25 ms to ~0 ms. Frame returns to budget.
- **Correctness preserved**: digging, melee carving, generation, *and* walls that burn or explode
  away still update nav + collision within a frame or two.
- No new per-frame GPU stalls.

---

## Architecture — GPU "solidity-changed" flag

Replace the sim's blanket per-frame dirty with a precise GPU signal. The sim already touches
every pixel; when it performs a solidity-changing write, it atomically flags that chunk. The CPU
reads the flags back **one frame late** (no stall) and dirties only the flagged chunks — mirroring
the existing double-buffered collider / light / probe readback pattern in `ComputeDevice`.

### Components

1. **Shared flag buffer (`ComputeDevice`)**
   - One storage buffer of `SIM_MAX_CHUNKS` u32 slots, **double-buffered** (`[2]`).
   - Each dispatched chunk is assigned a slot index for the frame; a per-frame **manifest**
     (`PackedInt32Array` of `[cx, cy, slot]` triples, or slot-indexed coords) records the mapping,
     stored per write-index like `collider_dispatch_manifests`.
   - `SIM_MAX_CHUNKS` must be ≥ the maximum number of concurrently loaded chunks (bounded by view
     radius). Cap with a `push_warning` if exceeded, matching `COLLIDER_MAX_DISPATCH_PER_FRAME`.

2. **Generated `HAS_COLLIDER[]` array (shader)**
   - Add a `const bool HAS_COLLIDER[N]` array to the generated `shaders/generated/materials.glslinc`
     (and the generator/exporter that produces it), populated from `MaterialRegistry.has_collider`,
     exactly like the existing `IS_FLAMMABLE[]` array.

3. **Sim shader writes the flag (`simulation.glsl` + the two includes)**
   - Bind the flag buffer at **set 0, binding 6** (next free binding after the injection buffer at
     binding 5).
   - Pass the per-chunk `slot` index via the push constant. The push constant currently is
     `{ int phase; int frame_seed; int _pad2; int _pad3; }` — repurpose `_pad2` as `chunk_slot`.
   - At each solidity-removal site (`burning.glslinc:76`, `explode_wave.glslinc:97` and `:126`),
     after computing the new material, emit the generic check:
     ```glsl
     if (HAS_COLLIDER[orig_material] && !HAS_COLLIDER[new_material]) {
         atomicOr(solidity_flags[pc.chunk_slot], 1u);
     }
     ```
     Using the generic `HAS_COLLIDER` check (rather than hard-coding `MAT_AIR`) future-proofs the
     instrumentation against new solid/non-solid materials and any future solid-creating transition.

4. **`dispatch_simulation` (`ComputeDevice`)**
   - Before dispatch: zero the write-index flag buffer (one `buffer_update` of zeros, or a clear).
   - Assign each chunk a slot, build the manifest, bind the flag buffer (already in each chunk's
     `sim_uniform_set`), dispatch.
   - The sim dispatches each chunk **twice per frame** (even phase, then odd phase). The push
     constant is currently built once per phase (`push_even` / `push_odd`) and shared across all
     chunks; it must now be set **per chunk** so each carries its own `chunk_slot`, in *both*
     phases. Both phases `atomicOr` into the same slot — accumulation is correct.
   - **Remove** the blanket `mark_terrain_dirty` loop (`compute_device.gd:604-606`).

5. **`read_solidity_flags()` (`ComputeDevice`)**
   - Reads back the **previous** frame's flag buffer (`read_index = 1 - write_index`), coalesced
     (`buffer_get_data` of `slot_count * 4` bytes).
   - Returns the set/array of changed `Vector2i` coords (slots whose u32 != 0), filtered to coords
     still present in `chunks`.
   - First-frame guard returns empty and advances the index (collider pattern,
     `compute_device.gd:713-716`).
   - Swap write index.

6. **`WorldManager` wiring**
   - In `_run_simulation` (or immediately after it in `_physics_process`), call
     `read_solidity_flags()` and `mark_terrain_dirty(coord)` for each returned coord.
   - All other `mark_terrain_dirty` call sites are unchanged.

7. **`build_sim_uniform_set` (`ChunkManager`)**
   - Add a `UNIFORM_TYPE_STORAGE_BUFFER` uniform at binding 6 pointing at the shared flag buffer
     (the same global buffer for every chunk's sim uniform set — it is indexed per-chunk by the
     push-constant slot, not by separate buffers).

### Secondary: NavField tile change-detection

When a flagged chunk reaches NavField, hash its downsampled 32×32 tile and skip storing it /
invalidating the flow field if the tile is byte-identical to the cached tile — mirroring the
collision helper's `seg_hash` skip (`terrain_collision_helper.gd:60-63`). This is cheap insurance
for the case "a solid pixel changed but the coarse 8-px cell stayed solid." The readback still
happens for flagged chunks; this only avoids needless flow-field rebuilds.

Implementation: in `PassabilityGrid.update_chunk` (or `NavField._drain_tiles`), compute
`hash(tile)`, compare against a per-chunk `_last_tile_hash`, and skip `_tiles[coord] = tile` +
flow invalidation when unchanged.

---

## Data flow (one frame)

```
_physics_process
  └─ _run_simulation
       ├─ zero solidity_flags[write_index]
       ├─ dispatch sim (each chunk: per-chunk push constant w/ slot; on a solidity removal,
       │    atomicOr solidity_flags[slot] |= 1)
       └─ (no blanket dirty)
  └─ read_solidity_flags()           # reads solidity_flags[read_index] = previous frame
       └─ for each changed coord still loaded: mark_terrain_dirty(coord)
  └─ collision_helper.rebuild_dirty  # now-tiny dirty set
  └─ nav_field.update                # now-tiny dirty set, optional tile-hash skip
  └─ swap write_index
```

---

## Edge cases

- **Buffer sizing**: `SIM_MAX_CHUNKS` ≥ max concurrent loaded chunks. Cap + `push_warning` if a
  frame dispatches more (matches `COLLIDER_MAX_DISPATCH_PER_FRAME` handling).
- **Chunk unloaded between write and read**: `read_solidity_flags()` skips coords not in `chunks`
  (collider readback pattern).
- **First frame**: first-frame guard returns empty; the read buffer holds undefined data until the
  first real write completes.
- **Freshly generated chunks**: already dirtied by the generation path; not reliant on the flag.
- **Atomic contention**: only transition pixels (rare) touch a slot; single-word `atomicOr`
  contention is negligible.
- **Slot reuse across frames**: slots are reassigned per frame from the manifest; zeroing the
  write buffer before dispatch prevents stale flags from leaking into the next read.

---

## Testing

### Pure unit test
Extract a static, side-effect-free helper that maps `(flag_bytes, manifest, loaded_chunks)` →
`Array[Vector2i]` of changed coords. Table-test:
- empty manifest → empty result
- some slots set, some zero → only set slots returned
- a set slot whose coord is no longer loaded → filtered out
- all slots set → all loaded coords returned

### Manual / profiler verification
- **Idle near flowing lava/gas**: open the profiler; NavField `_drain_tiles` and the collision
  helper's `rebuild_dirty` dirty sets are empty; `read_region` calls ≈ 0/frame; frame time returns
  to budget (target: steady-state frame well under 16.6 ms for these systems).
- **Dig a tunnel** (melee/projectile carve): enemies route through the new opening; player collides
  correctly against the new walls.
- **Burn a wood wall** (fire) and **detonate oil** (explode wave): after the wall clears, nav +
  collision update within a frame or two — enemies path through the gap, player passes through.
- **Regression**: enemies still route *around* intact walls; player wall collision intact; no
  walk-through-wall or invisible-wall artifacts.

---

## Files touched

| File | Change |
|---|---|
| `shaders/generated/materials.glslinc` (+ its generator) | Add `HAS_COLLIDER[]` array |
| `shaders/include/sim/burning.glslinc` | Flag write on solid→air burn |
| `shaders/include/sim/explode_wave.glslinc` | Flag write on solid→air explosion (×2 sites) |
| `shaders/compute/simulation.glsl` | Bind flag buffer (set 0, binding 6); `chunk_slot` push constant |
| `src/core/compute_device.gd` | Flag buffer alloc + double-buffer; slot assignment + manifest in `dispatch_simulation`; `read_solidity_flags()`; remove blanket dirty loop |
| `src/core/chunk_manager.gd` | Bind flag buffer at binding 6 in `build_sim_uniform_set` |
| `src/core/world_manager.gd` | After `_run_simulation`, dirty only flagged coords |
| `src/core/nav/nav_field.gd` / `passability_grid.gd` | Optional tile-hash skip |

---

## Out of scope (later sub-projects)

- **Sub-project 2** — GPU passability buffer: collider pass emits a 32×32 solidity grid per chunk;
  NavField reads ~1 KB instead of 262 KB, dropping `read_region` + GDScript downsample entirely.
- **Sub-project 3** — Collision-helper readback reduction: GPU-side segment hash so the ~10 ms
  coalesced `buffer_get_data` is skipped when no dispatched chunk changed.
- **Noted, deferred**: `terrain_modifier` itself does a full `texture_get_data` readback per
  placement — same anti-pattern.

**Measure after this sub-project before committing to 2 and 3.** Sub-project 1 alone is expected
to recover most of the frame; 2 and 3 are only needed if walls change often enough that the
remaining flagged-chunk readbacks are still heavy.
