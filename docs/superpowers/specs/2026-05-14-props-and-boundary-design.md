# Props & World Boundary — Design

**Status:** Draft
**Date:** 2026-05-14
**Scope:** Part 3 of 3 in the level-generation overhaul. Adds environmental props (lava/oil/water/gas pools, ice and sand powders, explosive boxes, oil barrels, wooden pillars), the powder sim, destruction debris, and a bounded world via wardstone + void-stone rings.
**Companion specs:** Part 1 — walkable space (committed). Part 2 — set-piece rooms (committed). This spec depends on materials introduced by Part 2 (`MAT_OIL`, `MAT_EXPLODE_WAVE`).

---

## 1. Goal

Two coupled improvements to the world's "filling":

- **Environmental props** — scatter material-based hazards and entity-based interactables through normal cave chunks so the player has things to manipulate everywhere, not just inside set-pieces.
- **World boundary** — bound the infinite world at sector Chebyshev distance 10.5 / 11 so the player can't miss the boss arena by walking past it. Soft wardstone warning ring + hard indestructible void-stone wall.

---

## 2. Prop Placement Pipeline

### 2.1 Split: GPU material stage + GDScript entity pass

**Material props** (lava, oil, water, gas pools, ice and sand powders) are placed by a new GPU stage `stage_biome_props` running after `stage_walkability_enforce` and before final scratch-channel cleanup. Each prop in the biome's `prop_pools` list is defined by `{material_id, noise_scale, noise_threshold}` — same shape as the existing `PoolDef`, evaluated independently per prop. Cells passing a prop's noise threshold AND currently `MAT_AIR` AND without the `NO_PROPS` mask bit set get stamped with that prop's material.

`stage_biome_props` is *separate* from the existing `stage_biome_pools` (which deposits solid pool variants of the background material). Pools are *terrain*; props are *gameplay*.

**Entity props** (explosive box, oil barrel, wooden pillar) are placed by a new GDScript pass `PropDispatcher` hooked to `world_manager.chunks_generated`. For each newly-generated chunk, for each entity prop in the biome's `entity_prop_pool`, sample a Poisson count from the configured mean. For each instance:

1. Pick a random cell in the chunk.
2. Read material data via `world_manager.read_region` for a small footprint (e.g. 8×8 px) including the companion `chunk_flags_tex`.
3. Validate: all cells air, `NO_PROPS` not set, not inside a boss-arena sector (defensive — the mask should already cover this).
4. Spawn the scene at the cell.

Retry up to 8 times per instance; if no valid placement found, skip silently.

### 2.2 Biome assignments (locked)

| Prop | caves | mines | magma | frozen | vault | Type |
|---|---|---|---|---|---|---|
| Lava pool | — | — | 4% | — | — | material |
| Oil pool | — | 2% | — | — | 1% | material |
| Water pond | 2% | 1% | — | — | — | material |
| Gas pool | 1% | 3% | 1% | — | 2% | material |
| Ice powder | — | — | — | 4% | — | material |
| Sand/dust powder | 1% | — | — | — | — | material |
| Wooden pillar | — | 2/chunk | — | — | — | entity |
| Explosive box | 0.5 | 1 | 0.5 | 0.5 | 1 | entity |
| Oil barrel | 0.3 | 1 | 0.3 | — | 0.5 | entity |

Material percentages are average target coverage of a chunk's air cells. Entity numbers are Poisson means per chunk.

---

## 3. Powder Sim

Top-down game — no gravity. Powders are *static piles* on the floor that don't move on their own.

### 3.1 Per-cell rules (new `stage_powder` in the sim shader)

1. **Idle by default.** A powder cell with no disturbance and no heat/contact trigger stays put. No per-tick movement.
2. **Dispersed by melee swings.** Existing `disperse_materials_in_arc` and `clear_and_push_materials_in_arc` already accept a `materials` list. Powder material IDs are added when swings hit them; powder gets pushed out of the arc into adjacent cells, identical to gas dispersal.
3. **Dispersed by explode waves.** When `MAT_EXPLODE_WAVE` enters a powder cell, the powder is pushed one cell outward in the wave's direction of travel (using the wave's expansion vector). Powder doesn't block the wave; it just gets shoved.
4. **Heat reactions (per-material):**
   - **Ice powder:** if any 4-neighbor has `temperature ≥ 100` OR cell is inside an explode wave, decrement `health` by 1; cool the trigger neighbor by 20. When `health == 0`, replace with `MAT_WATER`.
   - **Sand/dust powder:** inert. No reactions.

### 3.2 Passability

Powder cells are non-solid — entities and projectiles pass through. They don't block movement, line-of-sight, or fluid flow. Fluids advect through powder cells without displacing them. Powder is a purely interactive overlay deposit.

### 3.3 Visuals

Each powder material has its own color in the material visual textures. Ice powder pale blue-white; sand/dust tan/grey. Standard top-down floor-overlay rendering — no special shader needed.

### 3.4 Performance

Idle powder costs one material lookup per tick. Active paths (dispersal, heat reaction) only run on cells being disturbed.

### 3.5 Future-proofing

Framework is "idle pile + per-material trigger reactions." A future `MAT_GUNPOWDER` that ignites into `MAT_EXPLODE_WAVE` plugs in as a new table entry.

---

## 4. Destruction Debris

Each material gets a new compile-time field in `MaterialRegistry`:

- `destruction_distribution: Dictionary[int, float]` — probability distribution over result material IDs when this material is destroyed. Authored as `{MAT_AIR: 0.6, MAT_SAND_DUST: 0.4}`.

`tools/generate_material_glsl.gd` expands this into a 256-entry lookup table per material:

```glsl
const int DESTRUCTION_TABLE[MAT_COUNT][256] = int[][](
    int[256](MAT_AIR, MAT_AIR, ...),   // AIR
    int[256](MAT_AIR, MAT_AIR, ...),   // WOOD
    int[256](MAT_SAND_DUST, MAT_AIR, ...),  // STONE
    ...
);
```

Destruction code (GPU shader and/or `terrain_modifier`) becomes branchless:

```
hash_byte = hash(world_pos) & 0xFF
new_material = DESTRUCTION_TABLE[material][hash_byte]
write_cell(pos, new_material)
```

### 4.1 Per-material distributions

| Material | Distribution |
|---|---|
| Stone (caves bg) | 40% `MAT_SAND_DUST`, 60% `MAT_AIR` |
| Mineshaft stone | 40% `MAT_SAND_DUST`, 60% `MAT_AIR` |
| Magma stone | 30% `MAT_SAND_DUST`, 70% `MAT_AIR` |
| Frozen rock | 40% `MAT_ICE_POWDER`, 60% `MAT_AIR` |
| Vault metal | 100% `MAT_AIR` |
| Stone bricks (caves perimeter) | 30% `MAT_SAND_DUST`, 70% `MAT_AIR` |
| Wooden beams (pillars / mines perimeter) | 100% `MAT_AIR` |
| Obsidian | 30% `MAT_SAND_DUST`, 70% `MAT_AIR` |
| Packed ice (frozen perimeter) | 50% `MAT_ICE_POWDER`, 50% `MAT_AIR` |
| Engraved metal (vault perimeter) | 100% `MAT_AIR` |
| Cracked-stone hint variants | same as their biome wall |
| All powders / fluids / gases | 100% `MAT_AIR` (included for table-uniformity) |

Carving through frozen rock leaves a trail of ice powder; through stone, a trail of sand piles. The next swing kicks the debris up. Vault is clean and metallic by design.

### 4.2 Indestructibility

New `MaterialDef.indestructible: bool` flag. When set, the destruction path no-ops — the cell never changes. Generated as `const bool INDESTRUCTIBLE[MAT_COUNT]` in the materials include.

Used by: `MAT_WARDSTONE`, `MAT_VOID_STONE`.

---

## 5. Conflict Mask (NO_PROPS)

Props must not spawn inside set-piece interiors or walkable-guarantee pockets from Part 1. One `NO_PROPS` mask bit covers all protected regions.

### 5.1 Companion scratch buffer

Part 1's A channel is full (bits 0–6 = inscribed radius, bit 7 = pool-origin). Rather than bit-juggling across pipeline stages, allocate a companion R8 storage texture `chunk_flags_tex` parallel to `chunk_tex`:

- 64 KB per chunk × ~25 active chunks ≈ 1.6 MB GPU
- bit 0 = NO_PROPS
- bits 1–7 = reserved for future gen stages

Allocated alongside `chunk_tex` in `ComputeDevice`; freed/recycled per chunk. Reset to 0 on chunk re-generation.

### 5.2 Which stages write NO_PROPS

- `stage_pixel_scene_stamp` — every cell inside a stamp's bounding rect (regardless of material vs. air) gets `NO_PROPS` set. Covers boss arena, elite chest room, secret stamps.
- `stage_walkability_enforce` (Part 1) — every cell inside the centroid's 150×150 guaranteed pocket gets `NO_PROPS` set.

### 5.3 Which stages read NO_PROPS

- `stage_biome_props` — skips cells where bit is set.
- `PropDispatcher` (GDScript) — reads via `world_manager.read_region` augmented to return flag-tex bytes alongside material bytes.

---

## 6. World Boundary

### 6.1 Materials

Two new materials in `MaterialRegistry`:

- **`MAT_WARDSTONE`** — warning ring. Glowing biome-tinted material (rune-etched look). `indestructible = true`. High `glow` so it reads at distance. Solid for sim purposes (`has_collider = true`).
- **`MAT_VOID_STONE`** — outer wall. Deep black, no light emission. `indestructible = true`. Solid.

Both opt out of standard cave carving via the new `indestructible` flag — terrain damage path checks it and no-ops.

### 6.2 Generation override — `stage_world_boundary`

Runs first in the gen pipeline, before any cave/pool/stamp/walkability/prop stages.

- Compute the chunk's centroid sector via the sector grid.
- Chebyshev distance from origin:
  - `dist ≤ 10` (inside boss ring): no override; normal cave generation proceeds.
  - `10 < dist < 11`: **wardstone ring zone.** Per-cell, cells within ~32 px of the sector-distance-10.5 line are written as `MAT_WARDSTONE`; the rest let subsequent cave stages run normally.
  - `dist ≥ 11`: **void zone.** Chunk filled entirely with `MAT_VOID_STONE`. A chunk-level scalar `chunk_is_void` is set.

### 6.3 Subsequent stage early-out

Each gen stage downstream of `stage_world_boundary` reads `chunk_is_void` once per chunk; if true, returns immediately. Cheap — one chunk-level branch, not per-cell.

Cells set to `MAT_WARDSTONE` in the ring zone are also protected from later stage overwrites: each subsequent stage checks `if current_cell == MAT_WARDSTONE: continue` (same pattern as existing stamp-material protection).

### 6.4 Behavior at the boundary

- Player swings on wardstone no-op via `INDESTRUCTIBLE`. The ring stays intact.
- Wardstone counts as solid in all sim paths; lava/water/gas pile against it but don't cross.
- The ring is mathematically continuous (per-cell distance test); no gaps regardless of cave noise.
- Wardstone visual tint matches the biome's perimeter accent (Part 2 §2) so it reads as "this floor's ward."

---

## 7. Implementation Surface

### 7.1 New files

- `shaders/include/biome_props_stage.glslinc` — material prop scatter
- `shaders/include/world_boundary_stage.glslinc` — wardstone ring + void-zone fill
- `shaders/include/powder_stage.glslinc` — powder sim (idle + dispersal + heat reactions)
- `src/core/prop_dispatcher.gd` — post-gen entity scatter
- `src/core/prop_def.gd`, `src/core/entity_prop_def.gd` — biome resource definitions
- `scenes/props/explosive_box.tscn`, `scenes/props/oil_barrel.tscn`, `scenes/props/wooden_pillar.tscn`

### 7.2 Modified files

- `src/autoload/material_registry.gd` — register `MAT_OIL`, `MAT_EXPLODE_WAVE` (Part 2), `MAT_ICE_POWDER`, `MAT_SAND_DUST`, `MAT_WARDSTONE`, `MAT_VOID_STONE`, the 5 biome perimeter accents (Part 2), the 5 biome cracked-stone variants (Part 2); add `destruction_distribution: Dictionary` and `indestructible: bool` fields to `MaterialDef`
- `tools/generate_material_glsl.gd` — emit `DESTRUCTION_TABLE[MAT_COUNT][256]` and `INDESTRUCTIBLE[MAT_COUNT]` constants into `shaders/generated/materials.glslinc`
- `src/core/biome_def.gd` — add `prop_pools: Array[PropDef]`, `entity_prop_pool: Array[EntityPropDef]`
- `assets/biomes/*.tres` — populate prop pools per the §2.2 mapping
- `shaders/compute/generation.glsl` / `generation_simplex_cave.glsl` — wire boundary stage (first), props stage (after walkability_enforce); allocate companion `chunk_flags_tex`; all stages check `chunk_is_void` and `MAT_WARDSTONE` protection
- `shaders/compute/<sim shader>` — add `stage_powder`; `stage_explode_wave` was added in Part 2
- `src/core/terrain_modifier.gd` (and any other cell-destruction site) — replace `material = MAT_AIR` with `DESTRUCTION_TABLE[mat][hash(pos) & 0xFF]`; check `INDESTRUCTIBLE` and no-op
- `shaders/include/walkability_enforce_stage.glslinc` (Part 1) — also write `NO_PROPS` bit in `chunk_flags_tex` for guaranteed-pocket cells
- `shaders/include/pixel_scene_stamp.glslinc` — write `NO_PROPS` bit in `chunk_flags_tex` for all stamp footprint cells
- `src/core/world_manager.gd` — `read_region` augmented to optionally return flag-tex bytes alongside material bytes

---

## 8. Testing

- **Boundary continuity:** generate 30×30 chunks; for every cell at sector Chebyshev distance ∈ [10.4, 10.6], assert material is `MAT_WARDSTONE`. No gaps.
- **Void-zone fill:** for every cell at sector distance ≥ 11, assert material is `MAT_VOID_STONE` and no entities or other materials present.
- **Indestructibility:** apply max-damage swings and explode waves to wardstone and void-stone cells; material unchanged after 1000 ticks.
- **Prop conflict mask:** 100 seeded levels — no prop ever lands inside `is_boss` / `is_elite_chest` / `is_secret` sectors, nor in cells with Part 1's guaranteed pocket.
- **Prop density:** 100 chunks per biome — material-prop coverage and entity Poisson means within ±20% of configured targets.
- **Destruction debris distribution:** destroy 10,000 cells of each material; distribution matches `destruction_distribution` within ±2%.
- **Powder idle cost:** sim tick on 1000 idle powder cells vs. 1000 air cells — overhead < 0.5 ms.
- **Powder dispersal:** 16×16 sand-dust pile + melee swing arc; ≥ 80% of arc-covered cells cleared, comparable count in adjacent cells.
- **Ice powder melt:** 5×5 ice-powder patch adjacent to `MAT_LAVA`; all cells convert to `MAT_WATER` within 200 ticks.
- **Carving debris trail:** straight tunnel through `MAT_STONE` (40% debris); ~40% of destroyed cells became `MAT_SAND_DUST`, rest `MAT_AIR`.

---

## 9. Out of Scope

- Walkability invariant on cave chunks → Part 1 (committed).
- Boss arena / elite chest room / secret chest design → Part 2 (committed).
- New weapon-side gameplay tied to props (e.g. modifiers that consume powder) — future weapon-system work, not gen-pipeline work.
