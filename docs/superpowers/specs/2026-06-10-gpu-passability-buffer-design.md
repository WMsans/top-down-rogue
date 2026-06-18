# GPU Passability Buffer (NavField Structural)

**Phase 8, Sub-project 2** — see `docs/design_docs/implementation_todo.md`.

## Problem

NavField rebuilds its coarse passability grid by reading terrain back from the
GPU and downsampling on the CPU, once per dirty chunk:

- `nav_field.gd:43` — `_world_manager.read_region(...)` calls
  `rd.texture_get_data(chunk.rd_texture, 0)` (`world_manager.gd:294`), a full
  256×256 RGBA8 = **262 KB** GPU readback per dirty chunk.
- `passability_grid.gd:25-39` — `update_chunk()` then runs a **65,536-pixel
  GDScript double loop** to downsample that into a 32×32 (1 KB) solidity tile.

Phase 8 sub-project 1 cut *how often* this runs (solid-aware dirtying), but the
per-rebuild cost is unchanged. This sub-project removes the readback and the
GDScript loop from the nav path entirely.

## Approach

The **collider compute pass** (`collider.glsl`) already dispatches over every
dirty chunk each frame at 128×128 invocations (one per 2px marching-squares
cell) and writes to a double-buffered, slot-packed storage buffer that
`TerrainCollisionHelper` reads back coalesced. We piggyback on that dispatch:
the same pass also writes a 32×32 solidity grid to a second buffer, and the
collision helper feeds each decoded tile straight into `NavField.grid`.

Passability **cannot** be derived from the collider's segments — an all-solid
region emits zero segments — so the shader samples pixels explicitly for the
grid. The two outputs are independent within the same dispatch.

Every loaded chunk is already marked dirty for the collider on generation
(`chunk_manager.gd:417`), so the grid gets populated for all chunks with no new
dirty-tracking.

## Components

### 1. GPU buffer layout (`compute_device.gd`)

A new double-buffered `passability_output_buffers: Array[RID] = [RID(), RID()]`,
parallel to `collider_output_buffers` and sharing the collider's
`collider_write_index` / `collider_dispatch_manifests` / double-buffer
machinery (the same dispatch writes both).

Constants:

```
PASSABILITY_CELLS_PER_SIDE := 32          # 256px chunk / 8px cell
PASSABILITY_SLOT_U32       := 1024        # 32 * 32, one uint per cell (1 = solid)
PASSABILITY_SLOT_BYTES     := 4096        # 1024 * 4
PASSABILITY_BUFFER_SIZE    := COLLIDER_MAX_DISPATCH_PER_FRAME * PASSABILITY_SLOT_BYTES  # 16 KB
```

- Create + zero both buffers in init (alongside `init_collider_storage_buffer`,
  or a new `init_passability_buffer()` called from the same site).
- Free both in `free_resources()` next to the collider buffers.
- **No header / no clear needed.** The 32×32 = 1024 designated invocations each
  write exactly one cell every dispatch, fully overwriting all 1024 cells of the
  slot — stale data from a prior chunk in that slot cannot survive.

### 2. Shader (`shaders/compute/collider.glsl`)

Add a third binding:

```glsl
layout(std430, binding = 2) buffer PassabilityBuffer {
    uint data[];
} passability_buffer;

const uint PASS_CELL = 8u;
const uint PASS_CELLS_PER_SIDE = 32u;   // CHUNK_SIZE / PASS_CELL
const uint PASS_SLOT_U32 = 1024u;       // 32 * 32
```

An 8px passability cell spans a 4×4 block of the existing 2px collider cells.
The invocation where `cell_x % 4u == 0u && cell_y % 4u == 0u` owns passability
cell `(cell_x / 4u, cell_y / 4u)`. Inserted near the top of `main()`, after the
`cell_x/cell_y >= CELLS_PER_SIDE` range check and after `gx`/`gy` are computed,
**before** the all-air/all-solid early-return:

```glsl
if ((cell_x & 3u) == 0u && (cell_y & 3u) == 0u) {
    uint solid = 0u;
    for (uint py = 0u; py < PASS_CELL; py++) {
        for (uint px = 0u; px < PASS_CELL; px++) {
            uint mat = uint(round(imageLoad(terrain_texture,
                ivec2(gx + px, gy + py)).r * 255.0));
            if (mat != 0u && HAS_COLLIDER[mat]) { solid = 1u; break; }
        }
        if (solid == 1u) break;
    }
    uint pcell = (cell_y / 4u) * PASS_CELLS_PER_SIDE + (cell_x / 4u);
    passability_buffer.data[pc.slot_index * PASS_SLOT_U32 + pcell] = solid;
}
```

Notes:
- `gx = cell_x * 2`, max designated `cell_x = 124` → `gx = 248`, `+8 = 256` —
  the loop stays in-bounds with no clamping (32 × 8 = 256 exactly).
- **No border-air forcing.** Unlike the segment path (lines 74-77, which force
  chunk-edge corners to air so contours close), passability uses raw solidity so
  a wall touching the chunk edge reads solid and enemies don't path into it.
- No atomics: exactly one invocation writes each cell.
- The owning invocation still runs its normal marching-squares segment logic
  afterward; the passability block is purely additive.

### 3. Uniform set (`chunk_manager.build_collider_uniform_sets`)

Add a `binding = 2` `UNIFORM_TYPE_STORAGE_BUFFER` uniform pointing at
`compute.passability_output_buffers[i]`, built into the same uniform set as the
terrain image (binding 0) and segment buffer (binding 1). Guard on the buffer
being valid, mirroring the existing binding-1 guard.

### 4. Readback & decode (`compute_device.gd`)

```
func decode_passability_slice(data: PackedByteArray, slot: int) -> PackedByteArray
```

Returns a 1024-byte tile (1 = solid), reading `PASSABILITY_SLOT_U32` uints from
`slot * PASSABILITY_SLOT_BYTES`. Pure CPU, mirrors `decode_solidity_flags` —
unit-testable without a `RenderingDevice`.

`read_collider_buffer_coalesced()` reads **both** buffers in one call, using the
same `read_index` and manifest, **before** the `collider_write_index` flip (a
second read after the flip would target the wrong buffer). Return shape changes
from `Dictionary` of `coord → segments` to:

```gdscript
{
    "segments":    { Vector2i: PackedVector2Array },
    "passability": { Vector2i: PackedByteArray },   # 1024 bytes per chunk
}
```

The passability read uses the same `bytes_needed` logic as the collider read
(scaled to `PASSABILITY_SLOT_BYTES`), and on the `collider_first_frame` /
empty-manifest early-outs returns `{"segments": {}, "passability": {}}`.

### 5. Consumption (`terrain_collision_helper.gd`)

`_consume_readback()` updates to the new return shape:

- Iterate `readback["segments"]` exactly as today, keeping the seg-hash skip for
  collision-shape and occluder rebuilds.
- **Separately**, iterate `readback["passability"]` and call
  `world_manager.nav_field.grid.set_tile(coord, tile)` for **every** dispatched
  chunk — independent of the seg-hash skip (an all-solid chunk produces no
  segments but a meaningful grid). Guard `world_manager.nav_field != null`.

This couples nav-grid population to the collision helper, which is the unit that
already owns the collider GPU readback. (Considered routing it up through
`world_manager` instead; rejected because the `buffer_get_data` + buffer-index
flip happen inside `read_collider_buffer_coalesced`, so the helper is the
natural consumer and a second reader would double-flip the index.)

### 6. NavField (`src/core/nav/nav_field.gd`)

- Remove `_dirty`, `mark_dirty()`, and `_drain_tiles()`.
- `update()` becomes just `flow.update(grid, player_world_pos, delta)`.
- `_world_manager` is retained only if still needed (it is not after removing
  `read_region`); drop the field and the `read_region` call.
- Keep `_build_solid_lut()` + passing the LUT to `PassabilityGrid` (still used
  by the retained `update_chunk` CPU fallback / reference path).

### 7. PassabilityGrid (`src/core/nav/passability_grid.gd`)

Add:

```gdscript
func set_tile(chunk_coord: Vector2i, tile: PackedByteArray) -> void:
    _tiles[chunk_coord] = tile
```

`tile` is a pre-downsampled `_cells_per_chunk² = 1024`-byte grid (1 = solid),
exactly the format `update_chunk` produces internally. `is_solid_cell` /
`is_solid_world` read it unchanged.

**Keep** `update_chunk` (the CPU downsample) and its existing tests as the
semantic reference and a CPU fallback. It is no longer in the live nav update
loop — which satisfies the sub-project's "drop `read_region` + GDScript
downsample from nav entirely."

### 8. Wiring changes (`world_manager.gd`)

- `mark_terrain_dirty()` stops calling `nav_field.mark_dirty(coord)` — the
  collider dispatch now drives nav grid population. It continues to call
  `_collision_helper.mark_dirty(coord)`.
- On chunk unload, call `nav_field.grid.drop_chunk(coord)` alongside
  `_collision_helper.on_chunk_unloaded(coord)`. Nav tiles are currently never
  dropped on unload (latent leak); this is a small in-scope correctness fix.

## Data flow (after)

```
chunk dirtied (solid change / load)
  └─> collision_helper.mark_dirty(coord)            # nav no longer marked separately
        └─> collider dispatch (next frame)
              ├─> segment buffer  (slot)            # existing
              └─> passability buffer (slot)         # NEW, same dispatch
        └─> read_collider_buffer_coalesced()        # reads BOTH buffers, one flip
              ├─> {"segments": ...}    -> shape/occluder rebuild (seg-hash skip)
              └─> {"passability": ...} -> nav_field.grid.set_tile(coord, tile)
NavField.update() -> flow.update(grid, ...)         # no readback, no downsample
```

## Testing

- **Unit (pure CPU):**
  - `PassabilityGrid.set_tile` + `is_solid_cell` round-trip: a hand-built
    1024-byte tile with a known solid cell reads back solid; neighbors open.
  - `decode_passability_slice` decodes a hand-built 1024-uint buffer (a solid
    cell at a known index, non-zero `slot` offset) into the correct 1024-byte
    tile. Mirrors `test`-style coverage of `decode_solidity_flags`.
- **Regression:** `test_passability_grid.gd` (CPU `update_chunk`) stays green.
- **Manual / in-engine:** enemies still path around walls; `grep` confirms
  `nav_field.gd` no longer references `read_region`.

## Success criteria

- The per-dirty-chunk 262 KB `texture_get_data` readback and the 65,536-pixel
  GDScript downsample are gone from the nav path.
- Nav grid population rides the collider's existing dispatch and coalesced
  readback, adding ≤16 KB to that readback.
- Enemy pathing is unchanged (same conservative "any solid pixel in the 8px
  block inflates the cell" rule, now computed on the GPU).

## Out of scope

- Sub-project 3 (collision-helper readback reduction: GPU-side segment hash,
  skip coalesced readback when idle).
- The `terrain_modifier` per-placement `texture_get_data` readback (noted,
  deferred in the Phase 8 header).
- Fully deleting the CPU `update_chunk` path (retained as reference / fallback).
