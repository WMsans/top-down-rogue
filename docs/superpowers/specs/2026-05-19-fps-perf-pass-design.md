# FPS Performance Pass Design

## Problem

The editor profile (588 enemies, active lava/fire scene) shows
**Frame Time 88.20 ms** — well below 60 FPS even before export
optimizations. Three peaks dominate the `_process` budget:

| Symptom | Cost | Site |
|---|---|---|
| GPU readback stall + backlog growth | 66.82 ms | `WorldManager._run_terrain_probes` → `TerrainPhysical.prepare_probe_batch` + `ComputeDevice.read_terrain_probe` |
| Per-enemy terrain damage check | 9.99 ms | 588× `TerrainDamageReceiver._physics_process` |
| Melee swing readback | ~24.5 ms (per swing) | `MeleeWeapon._use_impl` → `TerrainModifier.clear_and_push_materials_in_arc` (2 calls), each doing `rd.texture_get_data` per affected chunk |
| Group scan on attack | 6.90 ms (per swing) | `MeleeWeapon._hit_attackables_in_arc` iterating all `attackable` nodes |
| Per-query allocation | ~0.4 ms × 529 | `TerrainCell.new()` on every `query()` |

### Root causes

1. **Probe pipeline backlog is unbounded.**
   `TerrainDamageReceiver` and `LavaDamageChecker` together emit
   roughly 5,300 `query()` requests per physics frame (588 enemies ×
   9 samples + 9 player samples), but `PROBE_BUDGET` is 64. The
   `_pending_probes` dict grows without bound; `prepare_probe_batch`
   iterates the entire dict each frame to drain 64 entries and
   rebuild the leftover dict. That iteration is the bulk of the
   62.60 ms attributed to `prepare_probe_batch` in the profile.

2. **`read_terrain_probe` forces a GPU sync stall.**
   `rd.buffer_get_data` blocks the CPU until the dispatch from this
   same frame finishes. Even with a small payload, the synchronous
   barrier is expensive.

3. **Every enemy queries terrain every physics frame.**
   The 588× `TerrainDamageReceiver._physics_process` calls fire
   regardless of whether the enemy is anywhere near a hazard.

4. **Melee terrain mods read full chunk textures back to CPU.**
   `clear_and_push_materials_in_arc` calls `rd.texture_get_data` on
   each affected chunk (256 × 256 × 4 = 256 KB), iterates pixels on
   CPU, then writes results back. Each swing pays this cost twice
   (fluids pass + solids pass).

5. **`_hit_attackables_in_arc` iterates every `attackable` node in
   the scene**, not just the ones near the swing.

## Goals

- Sustained 60 FPS in editor with the current stress scene.
- Reach budget by **reducing call volume** (hazard gating) and
  **eliminating GPU sync stalls** (double-buffered readbacks and
  fire-and-forget terrain dispatches), not by lowering simulation
  fidelity.
- No correctness regression. In particular, queries must still
  reflect dynamic GPU sim state (lava flow, fire spread, etc.) —
  CPU-side material mirroring is rejected because it diverges from
  the GPU simulation. See "Alternatives considered."

## Non-goals

- Optimizing FX spawn cost (`place_blood`, `_spawn_sparks`, etc.).
  These are per-event, not per-frame.
- Reducing enemy count or simulation tick rate.
- Touching rendering / shader cost. The profile shows process and
  physics are the bottleneck, not the GPU frame.

## Solution Overview

Three coordinated changes, each attacking one peak:

1. **Hazard sub-cell map.** Extend the existing 4×4 light cell
   pipeline to also emit a hazard bitmask per cell. CPU stores
   `chunk.hazard_cells[16]`; consumers gate their terrain queries on
   `hazard_at(pos, mask)` — an O(1) lookup. Most enemies skip the
   query entirely.

2. **Probe pipeline: bigger budget + double-buffered readback +
   `TerrainCell` interning.** Raise `PROBE_BUDGET` to 256; cycle
   two input/output SSBO pairs so the CPU reads frame N−1 while the
   GPU writes frame N. Cap `_pending_probes` to prevent any future
   unbounded growth. Cache one `TerrainCell` per material id in
   `MaterialRegistry`.

3. **Melee split: physics for enemies, fire-and-forget compute for
   terrain.**
   - Enemy hits become a `PhysicsServer2D.intersect_shape` query
     against an `attackable` collision layer, then arc-angle filter.
     Same-frame, scales with local density.
   - Terrain modification becomes a GPU compute dispatch with no
     return value. Impact FX positions (for `TerrainImpact`) are
     written by the shader to a triple-buffered hit-list SSBO and
     drained 3 frames later by `WorldManager._process` — no sync
     stall, ~50 ms FX lag (imperceptible for sparks/debris).

## Components

### 1. Hazard sub-cell map

#### Shader changes — `shaders/compute/light_extract.glsl` (or current light shader)

The light shader already iterates every pixel of each 64×64 sub-cell
to build the lights SSBO. Add a parallel reduction that ORs hazard
material flags into a new output field per cell.

Hazard bitmask layout (`uint`):

| Bit | Meaning |
|---|---|
| 0 | lava present in cell |
| 1 | fire present in cell |
| 2 | oil present in cell |
| 3 | blood present in cell |
| 4–31 | reserved |

Material → bit mapping lives in `MaterialRegistry.get_hazard_bit(mat_id)`,
returning −1 for non-hazardous materials.

#### `ComputeDevice.decode_light_ssbo` change

The decoded per-cell entry gains a `hazard: int` field
(default 0). Existing callers ignore it; new callers read it.

#### `Chunk.hazard_cells: PackedInt32Array`

A 16-entry array (`LIGHT_CELLS_X * LIGHT_CELLS_Y`) initialized to
zero. `WorldManager._update_lights` writes the values from the
decoded SSBO.

#### `TerrainPhysical.hazard_at(world_pos, mask) -> bool`

```gdscript
func hazard_at(world_pos: Vector2, mask: int) -> bool:
    var chunk_coord := Vector2i(
        floori(world_pos.x / CHUNK_SIZE),
        floori(world_pos.y / CHUNK_SIZE),
    )
    var chunk: Chunk = world_manager.chunks.get(chunk_coord, null)
    if chunk == null:
        return false
    var local_x := int(floor(posmod(world_pos.x, CHUNK_SIZE) / (CHUNK_SIZE / LIGHT_CELLS_X)))
    var local_y := int(floor(posmod(world_pos.y, CHUNK_SIZE) / (CHUNK_SIZE / LIGHT_CELLS_Y)))
    var idx := local_y * LIGHT_CELLS_X + local_x
    return (chunk.hazard_cells[idx] & mask) != 0
```

#### Caller updates

- `TerrainDamageReceiver._physics_process`: early-out if
  `not hazard_at(enemy.position, HAZARD_LAVA | HAZARD_FIRE)`.
  Falls through to existing 9-sample query only when a hazard is in
  the sub-cell.
- `LavaDamageChecker._physics_process`: same gate against player
  position.

Both still do the precise 9-sample query when the gate passes — the
gate is conservative (sub-cell coarse), so behavior is unchanged
when the player or enemy is actually near hazards.

**Freshness.** Hazard cells lag by the light pipeline's existing
1-frame readback. Acceptable: a tile newly turned to lava becomes
"hazardous" 1 frame (≈16 ms) after the GPU sim reports it.

### 2. Probe pipeline

#### `ComputeDevice` changes

Replace single SSBOs with double-buffered pairs:

- `terrain_probe_input_buffers: Array[RID]` (size 2)
- `terrain_probe_output_buffers: Array[RID]` (size 2)
- `terrain_probe_write_index: int` — toggles 0/1 each frame.

`PROBE_BUDGET` raised from 64 to 256. Buffer sizes scale
accordingly: input `256 × 8 = 2 KB`, output `256 × 4 = 1 KB`. Total
allocation ~6 KB.

API changes:

- `dispatch_terrain_probe(chunks, batch, packed_input)` writes to
  `input_buffers[write_index]` and dispatches with
  `output_buffers[write_index]` bound. Does **not** flip the index.
- `read_terrain_probe(byte_count) -> PackedByteArray` reads from
  `output_buffers[1 - write_index]` (the *previous* frame's output,
  which is guaranteed signaled). Then flips `write_index`.
- On the first frame after init, `read_terrain_probe` returns an
  empty array; `TerrainPhysical.apply_probe_results` treats an
  empty array as "no results this frame" (no-op).

#### `TerrainPhysical` changes

- `_pending_probes` is replaced with a deduplicated FIFO:
  - `_pending_probes: Dictionary` (insertion-ordered, Vector2i → true)
    keeps current set semantics for dedup.
  - On insertion past `MAX_PENDING := 4 * PROBE_BUDGET` (1024), drop
    the oldest entry (pop first key, insert new). Prevents pathological
    growth; in practice with hazard gating the dict stays in the low
    hundreds.
- `prepare_probe_batch` unchanged in logic but now operates on a
  bounded dict; cost becomes constant per frame.
- A separate `_pending_batch` field holds the most recently drained
  batch (so `apply_probe_results` next frame matches the readback
  to the correct world coordinates).

Pipeline timing:

```
Frame N:
  prepare_probe_batch -> batch_N (drains pending)
  dispatch_terrain_probe(batch_N) -> writes input/output[w]
  read_terrain_probe -> reads output[1-w] = batch_(N-1) results
  apply_probe_results(batch_(N-1), raw_(N-1))
  store _pending_batch = batch_N
  flip w
```

Result lag: 1 frame (consistent with current behavior; the previous
single-buffer code happened to be 0-frame *because* it stalled).

#### `MaterialRegistry` — cell interning

```gdscript
static var _cell_cache: Dictionary = {}  # int mat_id -> TerrainCell

static func get_cell(mat_id: int) -> TerrainCell:
    if not _cell_cache.has(mat_id):
        _cell_cache[mat_id] = TerrainCell.new(
            mat_id, has_collider(mat_id), is_fluid(mat_id), get_damage(mat_id)
        )
    return _cell_cache[mat_id]
```

`TerrainPhysical.query` returns `MaterialRegistry.get_cell(mat_id)`
instead of `TerrainCell.new(...)`. `TerrainCell` is treated as
immutable after construction; if any caller mutates it, that bug
exists today and would be caught by the change.

### 3. Melee split

#### Enemy hits — `PhysicsServer2D.intersect_shape`

Enemies (and the player) already expose collision shapes for
gameplay. Add them to a new physics layer `attackable_hit` (distinct
from solid-body collision).

`MeleeWeapon._hit_attackables_in_arc` replaces its group iteration
with:

```gdscript
var params := PhysicsShapeQueryParameters2D.new()
var circle := CircleShape2D.new()
circle.radius = weapon_reach
params.shape = circle
params.transform = Transform2D(0, origin)
params.collision_mask = ATTACKABLE_LAYER
params.collide_with_areas = true
params.collide_with_bodies = true
var hits := user.get_world_2d().direct_space_state.intersect_shape(params, 32)
```

Each hit's `collider` is then arc-angle filtered exactly as today.
Self-exclusion and `try_parry` flow unchanged.

#### Terrain modification — fire-and-forget compute

New shader `shaders/compute/melee_arc.glsl`:

Bindings (set 0):
- binding 0: chunk image, `rgba8` (read/write).
- binding 1: chunk velocity/displacement image (matches existing
  push pipeline).
- binding 2: output SSBO — hit list with atomic counter.

Push constants (one dispatch per affected chunk):
- `vec2 origin` (chunk-local)
- `vec2 direction`
- `float radius`
- `float inner_radius`
- `float arc_angle`
- `float push_speed`
- `float damage`
- `uint target_mask` — bitmask of target material IDs (packed via
  the existing material id range; for the current ≤32 materials
  this fits a `uint`).
- `uint chunk_origin_xy` — packed `(chunk_coord.x << 16) | chunk_coord.y`,
  so the shader can emit world coords in the hit list.

Per-invocation logic: pixel-local check identical to current CPU
code (distance, arc angle, target match, hardness scaling); if hit,
clear or push the pixel and `atomicAdd` an entry to the hit list
(world position, material id, impact scale).

Hit list SSBO:
- 3 buffers cycled (`HIT_LIST_RING := 3`).
- Each buffer: `4 + 64 × 12` bytes (atomic count + 64 entries of
  `{ivec2 pos, uint mat_id, float scale}`).
- Allocation: 3 × 772 B ≈ 2.3 KB total. Negligible.

#### `TerrainModifier` API change

`clear_and_push_materials_in_arc(...) -> void` (no return value).
Callers that previously consumed the `impact_list` return:

- `MeleeWeapon._use_impl`: stops capturing the return; impact FX
  arrive through the deferred channel below.

#### Deferred impact FX dispatcher

`WorldManager._process` gains a step (after `_update_lights`,
before `_run_terrain_probes`):

```gdscript
_drain_terrain_impacts()
```

Which reads `hit_list_buffers[(write_index + 1) % 3]` (3 frames old,
GPU guaranteed signaled) and calls `TerrainImpact.play_impact` for
each entry. The shader's atomic counter is reset to zero in the
ring slot before the next dispatch writes to it.

**Lag.** ~50 ms (3 frames at 60 FPS) between swing and impact spark
spawn. Validated as acceptable for sparks/debris; the swing motion,
sound, and enemy damage are all same-frame, so the felt feedback is
unchanged.

#### Fluid push pass

`clear_and_push_materials_in_arc(..., fluids)` uses the same shader
with `damage = 0` and a push-only branch: the shader skips the
atomic append entirely when `damage <= 0.0`. Fluid pushes never
produce impact FX (current behavior), so no hit list traffic is
generated.

## Data Flow

```
Frame N (60 Hz):

  WorldManager._process
    _update_lights
      -> light shader writes per-cell light + hazard
      -> CPU reads (already 1-frame lagged) -> chunk.hazard_cells
    _drain_terrain_impacts
      -> read hit_list_buffers[(w+1) % 3]
      -> TerrainImpact.play_impact for each entry
    _run_terrain_probes
      -> prepare batch from _pending_probes (capped FIFO)
      -> dispatch_terrain_probe writes buffers[w]
      -> read_terrain_probe from buffers[1-w] -> apply results
      -> flip w

  Per enemy._physics_process
    TerrainDamageReceiver
      -> hazard_at(pos, LAVA|FIRE)? if no, return (~588 fast-paths)
      -> else 9-sample query -> hits enemy if any cell damages

  Player attack
    MeleeWeapon._use_impl
      -> _hit_attackables_in_arc: intersect_shape -> arc filter
                                   -> on_hit_impact (same frame)
      -> TerrainModifier.clear_and_push_materials_in_arc(fluids)
         -> dispatch (no return)
      -> TerrainModifier.clear_and_push_materials_in_arc(solids)
         -> dispatch (no return)
      ... 3 frames later, drainer emits impact FX
```

## Expected Budget

| Subsystem | Before | After |
|---|---|---|
| `_run_terrain_probes` | 66.82 ms | < 1.0 ms |
| TerrainDamageReceiver (588×) | 9.99 ms | < 1.0 ms |
| `_hit_attackables_in_arc` (per swing) | 6.90 ms | < 0.3 ms |
| `clear_and_push_materials_in_arc` ×2 (per swing) | 24.48 ms | < 1.0 ms (dispatch only) |
| `TerrainCell` allocations | ~0.2 ms | 0 ms |
| **Total per-frame `_process`** | **88 ms** | **~12 ms** |

Comfortably under the 16.6 ms / 60 FPS budget with headroom for
spikes.

## Alternatives Considered

### CPU-side material mirror

A per-chunk CPU array of material ids, written every time a CPU or
GPU operation mutates the chunk. Reads are O(1) array index.

**Rejected because the GPU is the authoritative simulator of
terrain.** Lava flows, fire spreads, oil cascades, gas diffuses,
sand falls — all every frame on the GPU. The CPU has no visibility
into those changes without `rd.texture_get_data` per chunk per
frame (256 KB × N chunks), which is exactly the readback stall the
original probe pipeline replaced.

A "mirror placements only" variant (CPU tracks player-placed
materials but not sim evolution) is worse than no mirror: it
returns wrong answers for cells that the simulation has moved
materials into. `LavaDamageChecker` querying a tile where lava
*flowed to* would report "safe."

The chosen design lets the GPU stay authoritative and pays a
fixed-cost 1-frame readback through a small SSBO. The hazard
sub-cell map already reduces *how often* we ask, which addresses
the underlying call-volume problem without inverting the
GPU/CPU relationship.

### Throttling enemy terrain checks (round-robin)

Check 1 in N enemies per frame so the total query rate drops by N.
Simpler than hazard gating but every enemy still allocates queries
on its turn; backlog still grows linearly with enemy count. Hazard
gating is strictly better — it eliminates queries entirely from
enemies not near hazards, which is the common case.

### Keeping the probe pipeline at strict 0-frame freshness

Would require keeping the synchronous readback and instead
massively cutting query volume. With hazard gating alone this is
plausible (queries drop ~50×). But the readback itself, even on a
tiny buffer, is a Vulkan barrier with measurable cost, and there
is no gameplay reason that probe results must be 0-frame fresh
(lava damage at 60 Hz tolerates 1-frame lag trivially). Pay the
small lag, take the big speedup.

## Risks and Open Questions

1. **`attackable_hit` collision layer migration.** Every existing
   enemy and the player must register on the new layer. If any
   `attackable`-grouped node lacks a CollisionShape2D, the new
   `intersect_shape` will miss it. Migration plan: keep the group
   for backwards compatibility, but the layer assignment is the
   new source of truth. A scene audit confirms which enemy
   archetypes need shape additions.

2. **Hazard bit budget.** 32 bits is plenty today (≤32 distinct
   materials, only ~4 hazardous). If material count exceeds 32 in
   the future, expand to `uvec2`.

3. **Probe result lag for `CaveSpawner`.** The spawner currently
   polls a stable hot set and tolerates 1-frame lag per the
   existing spec. No change.

4. **Editor-only profile.** All measurements are from editor play,
   not export. Exported builds remove debugger overhead and run
   faster; reaching 60 FPS in editor implies comfortable margin
   exported.

## Out of Scope (deferred)

- `place_blood` cost (6.46 ms × 6 calls): per-hit, not per-frame.
  Will revisit after the three changes land.
- `Enemy.on_hit_impact` (6.82 ms): spike on hit waves, not steady
  state. Revisit if it remains visible.
- Audit of remaining per-frame allocations beyond `TerrainCell`.
