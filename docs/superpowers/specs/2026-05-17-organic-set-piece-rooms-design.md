# Organic Set-Piece Rooms — Design

**Status:** Draft
**Date:** 2026-05-17
**Scope:** Replace the rectangular boss-arena and elite-chest-room stamps from the 2026-05-14 set-piece spec with procedurally-carved organic caverns that blend with surrounding cave noise. Boss arena scales up to ~1024² (3×3 sectors) and elite chest room to ~512² (1.4×1.4 sectors). Hand-painted PNGs carry only interior markers; the outline is procedural.
**Companion specs:** 2026-05-14 walkable space (committed). 2026-05-14 set-piece rooms (partially superseded — see §1.1). 2026-05-14 props-and-boundary (to be rewritten; this spec defers all prop/entity behavior to that rewrite).

---

## 1. Goal

Two problems with the current set-pieces:

- **Boss arena is too small to be a landmark.** 512² is barely larger than one 384px sector. The player can walk past the boss-ring at Chebyshev 10 without noticing. We want a room that's unmissable from across the floor.
- **Both rooms feel dropped-in.** The crenellated rectangular perimeter on the boss arena and the carved-square outline of the elite room read as foreign objects sitting on top of organic cave noise. The hard rectangular edge is the worst offender.

Fix: boss grows to 1024×1024 and elite to 512×512; both lose their rectangular outline entirely. Outlines are produced by a dedicated procedural carve stage with angular-noise modulation. Cave noise continues to run through the footprint, so entrances emerge naturally where tunnels meet cavern lobes. The set-piece-ness comes from scale + dense curated interior + a guaranteed central feature, not from architectural framing.

### 1.1 Relationship to the 2026-05-14 set-piece spec

This spec **supersedes**:

- §2 of the set-piece spec — boss arena size, perimeter, and stamping approach.
- §3 of the set-piece spec — elite chest room size and stamping approach.

This spec **keeps unchanged**:

- §3.5 — `MAT_OIL`, `MAT_EXPLODE_WAVE`, and tuning constants.
- §4 — secret-chest design (no architectural changes; secret chests are still PNG stamps inside solid terrain).
- Marker IDs 8–13 from §2 and their dispatcher entries.

Removed:

- `BiomeDef.perimeter_material` field. No biome accent ring anymore.
- The 5 per-biome perimeter accent material registrations.

---

## 2. Boss Arena

### 2.1 Footprint

- Nominal radius 480 px, modulated by angular noise (§2.2). Outer reach ~560 px, inner pinch ~400 px.
- Anchored on a boss-ring sector (Chebyshev distance 10 from origin, existing `BOSS_RING_DISTANCE` constant).
- Occupies a 3×3 sector block (the boss sector plus 8 neighbors). The 8 neighbors are *claimed* — they resolve to empty in `sector_grid` and contribute no templates of their own. Cave noise still runs across them.

### 2.2 Procedural carve stage — `stage_boss_cavern_carve`

A new GPU stage in `shaders/include/boss_cavern_carve_stage.glslinc`. Runs *before* `stage_walkability_enforce` and *before* `stage_biome_props`.

Per cell within the boss sector's 3×3 block:

```
center = boss_sector_world_center
d = length(cell_world_pos - center)
theta = atan2(cell.y - center.y, cell.x - center.x)
r = 480.0 + boss_angular_noise(theta) * 80.0
if d < 96:
    cell.material = MAT_AIR           # hard-guaranteed inner disc
elif d < r - 16:
    cell.material = MAT_AIR           # carved interior
elif d < r:
    # soft band — leave whatever cave noise produced
    pass
else:
    pass                              # untouched, cave noise rules
```

`boss_angular_noise` is a 1D periodic noise sampled over `theta`, seeded from world seed + boss sector coord. Produces ±80 px lobing around the nominal radius. Same noise per boss sector instance, so the carve is deterministic per seed.

### 2.3 Interior markers

4 hand-painted PNGs per biome at 1024×1024: `assets/rooms/<biome>/boss_arena_a.png` … `_d.png`. 20 PNGs total.

Author paints **only marker pixels** on an otherwise empty canvas. Marker palette is the existing one (boss spawn, enemy spawn, prop seeds, pool seeds, barrels, vents — markers 1–13). Wall pixels are ignored; the outline is procedural.

Density target: 120–200 marker pixels per PNG. Author should paint chaos directly — clusters of barrels, pillar forests, pool puddles, gas vents. The hand-painted interior is what makes one arena visually distinct from another; the carve only handles the outline.

### 2.4 Marker stamping

A new GPU stage `stage_boss_interior_stamp` runs *after* `stage_boss_cavern_carve` and reads the PNG via the existing pixel-scene-stamp machinery. For each marker pixel:

- If the cell at the stamp target is `MAT_AIR` (i.e. the carve produced air there): apply the marker.
- Otherwise (the carve left wall or a lobe pinched in): skip the marker silently.

This means some authored markers will not appear in any given instance. Authors should over-paint by ~20% to compensate. Authoring tooling (level preview overlay, §6) renders the nominal radius circle and the typical lobing envelope so authors can keep most markers in the safe inner zone.

The center marker (boss spawn, marker 1) is special-cased: it is *always* placed at the exact boss-sector center regardless of what the author painted, so the boss never fails to spawn.

### 2.5 Claimed neighbors

`SectorGrid.RoomSlot` gains a field `is_claimed: bool`. When `resolve_sector` is called for a Chebyshev-10 sector that resolves to boss, the resolution also writes claim entries (via a small per-resolver cache or by deterministic re-derivation) for the 8 neighbors. When `resolve_sector` is later called on a neighbor, it computes whether any adjacent sector at Chebyshev 10 resolved to boss; if so, the neighbor returns `is_empty=true, is_claimed=true`.

Implementation note: keep this purely deterministic — for any sector at Chebyshev distance 9, 10, or 11, scan its neighborhood at distance ≤ 1 for boss-ring sectors and check if they resolved to boss. Cheap because there are at most a few boss sectors adjacent. No global state needed.

`is_claimed` is informational — downstream code that wants to know "this sector is part of a boss footprint" can read it (e.g. minimap rendering, fog-of-war reveal).

---

## 3. Elite Chest Room

Same approach, smaller scale.

### 3.1 Footprint

- Nominal radius 224 px, modulated by angular noise to ±48 px. Outer reach ~272 px.
- Centered on whichever non-boss sector rolls this template.
- Occupies ~1.4×1.4 sectors. Claims 1 neighbor sector — specifically the neighbor whose center is closest to the carve's "long axis" (the direction of maximum lobing). Other neighbors unaffected.

### 3.2 Procedural carve stage — reuses `stage_boss_cavern_carve` with parameters

Same shader stage, parameterized by `(center, base_radius, lobing_amplitude, inner_disc_radius)`. Boss invocation passes `(boss_center, 480, 80, 96)`. Elite invocation passes `(elite_center, 224, 48, 48)`.

The stage is dispatched once per claimed sector cluster per chunk during generation. Multiple set-pieces in the same chunk dispatch the stage multiple times with different parameters.

### 3.3 Interior markers

3 hand-painted PNGs per biome at 512×512: `assets/rooms/<biome>/elite_chest_a.png` … `_c.png`. 15 PNGs total.

Contents per PNG (unchanged from 2026-05-14 set-piece spec §3):

- 1 chest marker (visible from any entry point).
- 2–3 elite enemy markers.
- 0–1 hazard cluster (oil pool, gas vent, or 2–3 explosive barrels) — sparingly.

Chest marker is special-cased like the boss spawn: always placed at the exact sector center. Other markers respect the carve.

### 3.4 Template pool integration

Elite chest stays in `BiomeDef.room_templates` with `is_elite_chest=true`. Weight tuned so ~10% of non-empty sectors roll an elite chest (existing target from the 2026-05-14 set-piece spec §3).

The `RoomTemplate` carries a `cavern_carve: bool` flag. When true, `sector_grid` triggers the carve stage and the claim machinery; when false, the template stamps the old PNG way. Existing blob/corridor templates keep `cavern_carve=false`. Elite chest sets `cavern_carve=true`.

---

## 4. Integration With Existing Pipeline

### 4.1 Pipeline order

1. `stage_simplex_cave` (existing) — produces base cave noise.
2. `stage_biome_pools` (existing) — solid pool variants.
3. `stage_pixel_scene_stamp` (existing) — secret-chest stamps, and any old-style room templates.
4. **`stage_boss_cavern_carve`** (new) — irregular cavern carve at boss/elite sector centers.
5. **`stage_boss_interior_stamp`** (new) — applies marker PNGs at carve-air cells.
6. `stage_walkability_enforce` (Part 1) — trivially satisfied within the guaranteed inner disc.
7. Prop/boundary stages from the pending Part 3 rewrite — respect `NO_PROPS` mask written by step 5.

### 4.2 Walkability interaction

The guaranteed inner disc (boss `r < 96`, elite `r < 48`) is always air. That's more than enough to satisfy Part 1's centroid walkability invariant for any sector overlapping the carve. The walkability stage runs after the carve, sees the giant air pocket, and does nothing.

### 4.3 NO_PROPS mask

`stage_boss_interior_stamp` writes the `NO_PROPS` bit in `chunk_flags_tex` (from the pending Part 3 rewrite) for every cell inside the carve footprint, regardless of whether a marker landed there. Ambient props from the prop dispatcher won't compete with the curated interior.

### 4.4 Cave noise continuity

`stage_simplex_cave` runs first across the entire 3×3 boss footprint untouched. When the carve stage runs, the soft band (`r - 16 < d < r`) preserves whatever the cave noise produced. So at the rim, you get cave-noise tunnels naturally piercing into the cavern from outside, which become entrances. No special-case entrance logic.

---

## 5. Implementation Surface

### 5.1 New files

- `shaders/include/boss_cavern_carve_stage.glslinc` — parameterized organic carve.
- `shaders/include/boss_interior_stamp_stage.glslinc` — post-carve marker application + `NO_PROPS` mask writes.
- `assets/rooms/<biome>/boss_arena_a.png` … `_d.png` — 4 × 5 = 20 PNGs at 1024².
- `assets/rooms/<biome>/elite_chest_a.png` … `_c.png` — 3 × 5 = 15 PNGs at 512² (replaces the 256² versions in the 2026-05-14 set-piece spec §3).

### 5.2 Modified files

- `src/core/sector_grid.gd` — add `is_claimed` to `RoomSlot`; in `resolve_sector`, scan neighborhood for boss-ring sectors whose resolved slot is a 3×3-claimer and return `is_empty=true, is_claimed=true` for the 8 neighbors. Same logic for elite claimers (1 neighbor).
- `src/core/room_template.gd` — add `cavern_carve: bool` flag.
- `src/core/biome_def.gd` — drop `perimeter_material` (added by 2026-05-14 set-piece spec); keep `cracked_material` and all other fields.
- `src/autoload/biome_registry.gd` — drop `perimeter_material` wiring.
- `src/autoload/material_registry.gd` — drop the 5 per-biome perimeter accent registrations.
- `assets/biomes/*.tres` — drop `perimeter_material`; swap in new boss/elite templates with `cavern_carve=true`; reference the new 1024² and 512² PNGs.
- `shaders/compute/generation.glsl` (or whichever pipeline file owns stage ordering) — insert `stage_boss_cavern_carve` and `stage_boss_interior_stamp` between pixel-scene-stamp and walkability-enforce.

### 5.3 Removed work from 2026-05-14 set-piece spec

The following items from the set-piece spec are no longer needed:

- 5 per-biome perimeter accent materials.
- Crenellated perimeter logic in the boss arena pixel-scene-stamp path.
- `BiomeDef.perimeter_material` field and tuning.

If implementation of those items already landed, remove them as part of executing this spec.

---

## 6. Tooling

Extend `addons/level_preview` (existing) with two overlays useful during PNG authoring:

- **Nominal radius circles.** Draw the boss/elite nominal radius and the inner-disc radius on top of the marker PNG so authors see roughly where their markers will land in carved air.
- **Lobing envelope band.** For a representative seed, draw the actual carved outline in soft outline over the PNG. Lets authors visualize how the lobing might bite into their marker layout.

These are author-side only — no runtime cost.

---

## 7. Testing

- **Boss carve geometry:** for 100 seeds × 5 biomes, sample the boss sector center disc (radius 96) and assert 100% of cells are `MAT_AIR`.
- **Boss carve outline organic:** for 100 seeds, compute the carved-air radius at 64 evenly-spaced angles; standard deviation across angles must be within [30, 100] px (lobing exists but is bounded).
- **Boss claimed neighbors:** for 100 seeds × 5 biomes, all 8 neighbors of every boss sector resolve to `is_empty=true, is_claimed=true`.
- **Elite carve geometry:** same as boss, with radius 48 inner disc and radius 224 nominal.
- **Marker survival rate:** for each authored boss PNG, average across 100 seeds, ≥ 75% of authored marker pixels land in carve-air. Authors tune over-paint to hit this.
- **Boss spawn guarantee:** for 1000 seeded boss sectors across all biomes, exactly one boss entity spawns within the inner disc.
- **Walkability invariant unchanged:** existing walkability tests still pass with the carve stage in the pipeline.
- **Entrance presence:** for 100 seeded boss sectors, flood-fill from the inner disc; at least one cave-noise tunnel reaches beyond the 3×3 footprint (i.e. the arena is not fully sealed).
- **Visual regression:** level-preview overlay renders 20 boss arenas and 15 elite chest rooms with carve outline + markers; manual review.

---

## 8. Out of Scope (Deferred)

- Prop / barrel / vent / pool entity behavior behind marker IDs 8–13 — defined in 2026-05-14 set-piece spec §3.5 and the pending Part 3 rewrite.
- World boundary (wardstone ring, void-stone wall) — Part 3 rewrite.
- Ambient props in normal cave chunks — Part 3 rewrite.
- Powder sim, destruction debris tables, `MAT_WARDSTONE` / `MAT_VOID_STONE` — Part 3 rewrite.
- Secret chest design — already covered by 2026-05-14 set-piece spec §4, unchanged.

---

## 9. Open Risks

- **Readability without architectural framing.** A purely-organic cavern might not telegraph "this is the boss room" until the player is already inside. Mitigation: scale alone (1024² vs typical 200–300 px tunnels) should make it obvious from one sector away. If playtesting shows it doesn't read, the fallback is to scatter a small amount of biome-accent debris in the soft band (rubble piles, not a wall) — re-author as a follow-up, not a re-spec.
- **Author over-paint discipline.** If authors paint markers near the lobing band, ~25% may get skipped. The level-preview overlays in §6 are the primary mitigation; the 75% survival test in §7 catches regression.
- **Aggressive sector claim.** The boss arena consumes 9 sectors of potential normal-room real estate. On a floor with one boss, this is fine. If a future change adds multiple bosses per floor, revisit.
