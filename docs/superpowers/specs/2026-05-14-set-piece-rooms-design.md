# Set-Piece Rooms — Design

**Status:** Draft
**Date:** 2026-05-14
**Scope:** Part 2 of 3 in the level-generation overhaul. Covers boss arena, elite chest room, secret chest, and the new materials (`MAT_OIL`, `MAT_EXPLODE_WAVE`) introduced by boss-arena features.
**Companion specs:** Part 1 — walkable space (committed). Part 3 — props & world boundary (forthcoming).

---

## 1. Goal

Replace the three failing set-pieces with distinct, recognizable encounters that match the build-driven environmental-chaos gameplay vision in `docs/design_docs/gameplay.md`. Each set-piece has its own visual grammar; the player learns to read the world's architecture.

- **Boss arena** — large landmark room, unmissable from outside, full of features for the player's modifier build to interact with. Reference: Naga Courtyard from Twilight Forest.
- **Elite chest room** — open chamber with elites + chest clearly visible, scattered through the level via the existing weighted template pool.
- **Secret chest** — hidden inside solid terrain, found by carving toward a subtle cracked-stone hint patch.

---

## 2. Boss Arena

**Size:** 512×512 px, spanning ~2×2 cave chunks. Player spots the perimeter from up to 2 chunks away.

**Perimeter:** Thick ring (`size * 0.45` to `size * 0.45 + perimeter_thickness`) crenellated — alternating wall blocks and gaps every ~24 px around the ring, like a castle parapet. Drawn in a biome-specific accent material distinct from the regular `background_material`:

| Biome | Perimeter material |
|---|---|
| caves | carved stone bricks |
| mines | wooden support beams |
| magma | obsidian |
| frozen | packed ice block |
| vault | engraved metal |

Each accent is a new entry in the material registry (5 total). Distinct colors so the perimeter reads at distance.

**Interior:** Each biome ships 4 hand-authored 512×512 boss arena PNGs (`boss_arena_a.png` … `boss_arena_d.png`). All features are baked in as marker pixels — pillars (solid `background_material` blobs), pool seeds, barrel markers, vent markers, enemy markers, boss marker. The author paints the chaos directly.

**Placement:** Existing sector ring at Chebyshev distance 10. Each boss sector picks one of the 4 variants uniformly at random (existing `sector_grid.gd:53-61` already supports multiple boss templates).

**New marker types** in `spawn_dispatcher._spawn_entity`:
- 8 = explosive barrel
- 9 = oil barrel
- 10 = gas vent (emits gas periodically)
- 11 = lava pool seed (stamped as `MAT_LAVA` cell at gen; fluid sim spreads it)
- 12 = oil pool seed (`MAT_OIL`)
- 13 = water pool seed (`MAT_WATER`)

Pool seeds stamp as fluid material at gen time; the existing liquid sim handles spreading. No new runtime system needed for pools themselves.

---

## 3. Elite Chest Room

**Size:** 256×256 px.

**Perimeter:** None. Just a carved-air chamber, same visual treatment as regular blob rooms. Set-piece-ness comes from what's inside, not architecture.

**Interior:** 3 hand-authored PNGs per biome (`elite_chest_a.png` … `elite_chest_c.png`). Each bakes in:
- 1 chest marker (visible from any entry point)
- 2–3 elite enemy markers
- 0–1 hazard feature (oil pool, gas vent, or a few explosive barrels) — sparingly

**Placement:** Weighted into `biome.room_templates` alongside blob/corridor templates. New `is_elite_chest: bool` flag on `RoomTemplate` (sibling of `is_secret` / `is_boss`) — purely informational. Weight tuned so ~10% of non-empty sectors roll an elite chest room.

The chest is the regular chest scene (not the secret rare variant). Reward worth comes from floor-depth scaling, not chest type.

---

## 3.5 New Materials

Two new materials. Both leverage the existing chunk-data layout (R=material, G=health, B=temperature, A=reserved). Burning is a temperature state of oil, not a separate material ID — same pattern as wood ignition.

### 3.5.1 MAT_OIL

- **Fluid sim:** existing liquid sim (same path as water/lava). Spreads, pools, flows.
- **Heat diffusion:** **excluded from the heat-diffusion sim.** Temperature rises only via direct contact with `MAT_LAVA`, `MAT_FIRE`, or `MAT_EXPLODE_WAVE` (the wave's power-as-temperature transfer). No gradient soak from generally-hot neighbors. Keeps oil chains gated on fire contact.
- **Temperature-driven burning:**
  - When `temperature ≥ 200` ("burning"): the cell emits `MAT_FIRE` into adjacent air, decrements its `health` channel by 1 per tick (~60-tick burn lifetime), and renders glowing orange-red instead of dark amber.
  - When burning cell `health == 0`: replaced with `MAT_EXPLODE_WAVE` seeded with power ~30.
- **Color:**
  - Cold (`temp < 200`): dark amber/black.
  - Burning (`temp ≥ 200`): glowing orange-red. The renderer branches on temperature for this material.

### 3.5.2 MAT_EXPLODE_WAVE

Custom sim — does not use the gas sim. New stage: `shaders/include/explode_wave_stage.glslinc`.

- Each frame the wave expands one cell radially outward in all 8 directions. Mechanically uniform — no randomness — front is always a clean expanding ring.
- The `temperature` channel stores the wave's power. On expansion into a new cell, power is decremented by `decay_rate` (default 4). When `power ≤ 0`, the cell reverts to `MAT_AIR`.
- On entering a cell: deals damage equal to current power to any entity in the cell; raises adjacent flammable materials' temperature by `power` (igniting oil and burning wood); damages terrain (subtracts power from terrain `health`).
- A wave cell lasts exactly 1 tick before decaying or propagating. The wave is a thin expanding shell, not a filled disk.
- **Color:** white-yellow flash (1-tick visible duration per cell).
- **Source — explosive barrels (marker 8):** when destroyed, spawn `MAT_EXPLODE_WAVE` in a small core with initial power ~120.
- **Cascade:** burning oil at end-of-life → small wave (power 30) → adjacent oil heats to ≥ 200 → ignites → more waves. Chain reaction emerges without special-case code.

### 3.5.3 Tuning constants

| Constant | Default |
|---|---|
| Oil ignition temperature | 200 |
| Oil burning lifetime (health) | 60 ticks |
| End-of-burn wave power | 30 |
| Barrel initial power | 120 |
| Wave decay per cell of travel | 4 |
| Barrel-wave max travel | 30 cells |

---

## 4. Secret Chest

### 4.1 Position selection

During generation, before stamping a secret room, sample a 32×32-px probe of the chunk material data at the secret-stamp center. If ≥ 90% of the probe is solid (non-air), the stamp proceeds. Otherwise the secret is skipped in this sector (no fallback to air placement).

This pushes secret chests deep inside cave walls — the chest sits in a 1-cell air bubble surrounded by solid stone. Invisible from any nearby corridor until carved.

### 4.2 Cracked-wall hint

New material per biome: `MAT_<biome>_CRACKED` (5 total — stone-cracked, mineshaft-cracked, magma-cracked, ice-cracked, vault-cracked). Subtle variant of `background_material` — same base color with faint diagonal crack texture overlay. Reads as "this wall is different" without screaming "loot here."

At gen time, when a secret room is placed, a small hint patch of cracked-material cells is stamped on the cave-side surface of the wall closest to the chest. The patch:
- ~6 cells wide × ~3 cells deep
- Sits on the outer perimeter of the surrounding solid region, facing the nearest carved-air pocket (computed from the chunk's air/solid layout at gen time)
- Replaces existing wall material cells only — does not carve any air

Players walking past an unbroken cave wall see a small unusual texture patch. Carving in reveals the path to the chest a few cells deeper. New players miss the first few; experienced players learn the cue.

### 4.3 Changes to current secret system

- `secret_ring_stage.glslinc` — **deleted.** No annular wall ring; the chest is naturally surrounded by solid via §4.1.
- Secret stamp PNGs (`secret_a.png`) — re-authored: 1-cell chest marker plus the cracked-material hint patch authored in.
- `BiomeDef.secret_ring_thickness` — removed.
- New per-biome property `cracked_material: int`.

### 4.4 Failure mode

If a secret sector rolls but no valid solid region is found, the sector becomes empty rather than placing a visible secret. Secret chests are therefore rarer on very open levels — acceptable tradeoff. Deeper, denser floors host more secrets, reinforcing "deeper = more to find."

---

## 5. Implementation Surface

### 5.1 New files

- `shaders/include/explode_wave_stage.glslinc` — wave expansion sim stage.
- `assets/rooms/<biome>/boss_arena_a.png` … `_d.png` — 4 × 5 biomes = 20 PNGs at 512×512.
- `assets/rooms/<biome>/elite_chest_a.png` … `_c.png` — 3 × 5 = 15 PNGs at 256×256.
- `assets/rooms/<biome>/secret_a.png` — re-authored, 1 per biome.
- `scenes/explosive_barrel.tscn`, `scenes/oil_barrel.tscn`, `scenes/gas_vent.tscn` — entities placed by `spawn_dispatcher` markers 8/9/10.

### 5.2 Modified files

- `src/core/room_template.gd` — add `is_elite_chest: bool` flag.
- `src/core/biome_def.gd` — add `cracked_material: int`, `perimeter_material: int`; remove `secret_ring_thickness`.
- `src/autoload/biome_registry.gd` — wire new biome fields.
- `assets/biomes/*.tres` — populate `perimeter_material`, `cracked_material`; swap in new boss/elite-chest/secret templates.
- `src/core/sector_grid.gd` — no algorithmic change; boss ring now picks from 4 variants (already supported).
- `src/core/spawn_dispatcher.gd:_spawn_entity` — handle marker types 8–13.
- `shaders/include/secret_ring_stage.glslinc` — **deleted.**
- `shaders/include/pixel_scene_stamp.glslinc` — secret stamps validate solid surroundings (32×32 probe ≥ 90% solid) before stamping; skip if invalid.
- `shaders/include/<liquid sim include>` — add `MAT_OIL` flow rules, exclude oil from heat-diffusion path, add temperature-driven burning behavior.
- `shaders/compute/<sim shader>` — add `stage_explode_wave` to the sim pipeline.
- `MaterialRegistry` — register `MAT_OIL`, `MAT_EXPLODE_WAVE`, 5 per-biome cracked variants, 5 per-biome perimeter accent variants.
- Material visual textures — color entries for all new materials; oil renderer branches on temperature.

### 5.3 Elite chest pool integration

Keep elite chest templates in the existing `room_templates` array with `is_elite_chest=true` and tuned weight. No new branching in `sector_grid.resolve_sector`; the flag is informational only.

---

## 6. Testing

- **Boss arena visibility:** for 100 seeds × 5 biomes, generate boss-ring sectors and assert the perimeter accent material is contiguous along ≥ 80% of the ring circumference.
- **Boss arena variety:** over 1000 seeded boss spawns per biome, each of the 4 variants is selected within 20–30% of the time.
- **Elite chest distribution:** over 100 generated levels per biome, mean elite-chest-room count is in [3, 10].
- **Secret chest occlusion:** for 200 secret stamps across biomes, each chest position is surrounded by ≥ 90% solid material in a 32×32 probe.
- **Cracked-hint reachability:** for each placed secret, flood-fill from the nearest air cell to the cracked-hint patch; path length ≤ 20 cells.
- **Oil ignition chain:** sim integration — place a 5×5 oil patch with one `MAT_FIRE` seed; after 200 ticks, all oil cells burned through and exactly one `MAT_EXPLODE_WAVE` emitted per cell.
- **Explode wave shell:** spawn a power-120 wave at origin; at tick N, wave cells form a ring at radius N (not a disk) with power decremented by 4N.
- **Cascade integration:** two adjacent 5×5 oil patches separated by 2 air cells. Ignite one. Second ignites within 100 ticks.
- **Visual regression:** extend `addons/level_preview` to render boss arenas, elite chest rooms, and secret-chest hint patches with overlay annotations.

---

## 7. Out of Scope (Handled in Companion Specs)

- Walkability invariant on cave chunks → Part 1 (committed).
- World boundary and ambient props (lava pools, gas pools, wooden pillars, water ponds, powders, explosive boxes outside set-piece rooms, oil barrels outside set-piece rooms) → Part 3.
