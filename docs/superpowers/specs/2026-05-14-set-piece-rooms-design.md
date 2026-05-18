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

**Scope note:** This iteration defines the materials and their sim behavior. The only entry point is the existing `spawn_mat` console command (`src/console/commands/spawn_mat_command.gd`), which automatically picks up any new entry in `MaterialRegistry.materials`. Gameplay sources (barrels, gas vents, pool seeds, spawn-dispatcher markers, level-gen placement) are deferred to a later spec.

### 3.5.1 MAT_OIL

- **Fluid sim:** new `shaders/include/sim/oil.glslinc`, modeled on `lava.glslinc`. Spreads, pools, and flows like other liquids.
- **Heat sim:** **fully participates** in heat diffusion. `IS_FLAMMABLE[MAT_OIL] = true`, `IGNITION_TEMP[MAT_OIL] = 200`. Burning, ignition, and heat spread reuse the existing `burning.glslinc` path unchanged — oil ignites from neighboring fire, lava, hot wood, or hot oil exactly like any other flammable, including gradient soak from generally-hot neighbors.
- **Burn lifetime:** uses the standard `health` decrement in `burning.glslinc`. Initial health is set so total burn ≈ 60 ticks.
- **End of burn:** when a burning oil cell reaches `health == 0`, instead of replacing with `MAT_AIR` (the default path in `burning.glslinc`), it replaces with `MAT_EXPLODE_WAVE` seeded at power = `OIL_BURN_END_POWER` (default 18). This is a small special-case in `burning.glslinc`: if the cell that just burned out was `MAT_OIL`, write a wave seed instead of air.
- **Color:**
  - Cold (`temp < IGNITION_TEMP[MAT_OIL]`): dark amber/black.
  - Burning (`temp ≥ IGNITION_TEMP[MAT_OIL]`): glowing orange-red. Renderer branches on temperature for `MAT_OIL`.

### 3.5.2 MAT_EXPLODE_WAVE

Custom sim. New file: `shaders/include/sim/explode_wave.glslinc`. **Not** a fluid; **not** routed through `burning.glslinc`.

#### Pixel encoding

- `material = MAT_EXPLODE_WAVE`
- `temperature` channel stores the wave's **power** (0–255).
- `health` channel unused (reserved for future directional state if needed).

#### Propagation rule

Each tick, every wave cell:

1. **Writes into its 4 orthogonal neighbors** (up/down/left/right — Manhattan, **not** 8-neighbor) that are currently `MAT_AIR` with `temperature < SCORCH_TEMP`. The neighbor becomes `MAT_EXPLODE_WAVE` with `power_new = power_current - WAVE_DECAY`. If `power_new ≤ 0`, no write.
2. **Decays to scorched air:** the originator becomes `MAT_AIR` with `temperature = SCORCH_TEMP` (default 100). This prevents the originator from being re-lit by its now-active forward neighbors next tick (backfill prevention).
3. The scorch heat dissipates naturally via the existing heat-diffusion sim over ~30 ticks. Side effect: leaves a brief warm patch in the wave's wake; nearby flammables can be partially pre-heated by passing waves.

Each wave cell lives exactly one tick. The wave is a clean 1-cell-thick expanding **diamond** (Manhattan front), advancing 1 cell per tick.

#### Per-cell effects (the tick a cell becomes a wave)

- **Damages entities** overlapping that pixel by `power` (treats wave cells as damaging cells, reusing the existing entity-vs-pixel-damage hook used by lava/fire).
- **Raises adjacent flammable terrain temperature by `power`** — this is what ignites oil chains and burning wood.
- **Subtracts `power` from terrain `health`** of adjacent solid (rock/wood) cells — wave chews through weak terrain.

#### Chunk boundary handling

Propagation reads neighbors via the existing `read_neighbor` helper in `shaders/include/sim/common.glslinc`, so waves cross chunk seams the same way liquids do. The propagation rule is fully local — no global state needed.

#### Cascade

Burning oil at end-of-life → small wave (power 18 → 4-cell-radius diamond) → adjacent oil temperature instantly raised by 18 (more than enough to push over the 200 ignition threshold if pre-warmed) → those oil cells burn for 60 ticks → each emits its own power-18 wave. Chain reaction emerges without special-case code.

#### Color

White-yellow flash. Renderer branches on `MAT_EXPLODE_WAVE` and ignores temperature for color purposes (temperature is being used as power, not heat).

### 3.5.3 Expected spread pattern

With **console default `WAVE_DEFAULT_POWER = 60`, `WAVE_DECAY = 4`:**

| Tick | Front shape | Manhattan radius | Cell count on front | Power on front |
|---|---|---|---|---|
| 0 | single cell | 0 | 1 | 60 |
| 1 | diamond | 1 | 4 | 56 |
| 2 | diamond | 2 | 8 | 52 |
| r | diamond | r | 4r (r > 0) | 60 − 4r |
| 14 | diamond | 14 | 56 | 4 |
| 15 | — | 15 | — | 0 → terminates |

At 60 fps that's a ~0.25-second burst reaching 15 cells radius. Behind it, a fading scorch-hot air region that dissipates over the next ~30 ticks.

With **`OIL_BURN_END_POWER = 18`, `WAVE_DECAY = 4`:** wave reaches Manhattan radius 4 in 4 ticks (~0.07 s) before terminating. Tiny pop per cell — visible but localized. Cascades emerge when neighboring oil cells fall inside that 4-cell radius.

### 3.5.4 Console integration (only integration in this iteration)

`spawn_mat oil <radius>` works automatically once `MAT_OIL` is registered — it routes through `world_manager.place_material()` like any solid or liquid.

`spawn_mat explode_wave <radius>` is **seed-and-go**: it stamps a small core of wave cells at the cursor with `temperature = WAVE_DEFAULT_POWER` (default 60), then the sim takes over and the diamond expands until power decays to zero. Implementation: add a minor branch in `spawn_mat_command.gd` (or in `world_manager.place_material`) so wave stamps get `temperature = WAVE_DEFAULT_POWER` rather than 0. The `radius` console arg controls the seed-core size only — propagation distance is governed entirely by `power / WAVE_DECAY`.

### 3.5.5 Tuning constants

Defined in `shaders/include/sim/common.glslinc` (or a dedicated header) and mirrored on the GDScript side where needed.

| Constant | Default | Meaning |
|---|---|---|
| `IGNITION_TEMP[MAT_OIL]` | 200 | Heat threshold for oil to start burning |
| Oil burn lifetime (initial `health`) | 60 | Ticks a burning oil cell lasts before seeding a wave |
| `OIL_BURN_END_POWER` | 18 | Wave power seeded when a burning oil cell expires |
| `WAVE_DEFAULT_POWER` | 60 | Power used by `spawn_mat explode_wave` (and future barrels, until per-source overrides exist) |
| `WAVE_DECAY` | 4 | Power lost per cell of propagation |
| `SCORCH_TEMP` | 100 | Temperature stamped on air behind a wave; blocks re-light until heat dissipates |

### 3.5.6 Out of scope (deferred to a later spec)

- Barrels, gas vents, pool seeds, and any level-gen markers for these materials.
- Spawn-dispatcher marker types for these materials.
- Tuning passes for explosion damage curves vs. enemies.
- Per-source power overrides (barrel power, end-of-burn power scaling with oil depth, etc.).

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
