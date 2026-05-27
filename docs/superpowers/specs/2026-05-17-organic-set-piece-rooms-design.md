# Organic Set-Piece Rooms — Design

**Status:** Draft
**Date:** 2026-05-17
**Scope:** Replace the rectangular boss-arena and elite-chest-room stamps from the 2026-05-14 set-piece spec with procedurally-carved organic caverns whose interiors are populated from **data-driven composition resources** (no hand-painted marker PNGs). Boss arena grows to 2048×2048 (~5×5 sectors). Elite chest room stays modest at 512×512. The `level_preview` addon is deleted as part of this work.
**Companion specs:** 2026-05-14 walkable space (committed). 2026-05-14 set-piece rooms (partially superseded — see §1.1). 2026-05-14 props-and-boundary (to be rewritten; this spec has no runtime dependency on it).

---

## 1. Goal

Three problems being fixed:

- **Boss arena too small to be a landmark.** 512² is barely larger than one 384px sector. Player can walk past Chebyshev-10 without noticing. We want an unmissable arena.
- **Both set-pieces feel dropped-in.** The crenellated rectangular perimeter on the boss arena and the carved-square outline of the elite room read as foreign objects on top of organic cave noise. The hard rectangular edge is the worst offender.
- **PNG-based interior authoring doesn't scale.** At 2048×2048 = 4 megapixels per variant, hand-painted marker PNGs become unreasonable design pressure. Switch to structured data ("place 3 pillar clusters in a ring at r=600..900, 6 enemies in an outer arc, a lava puddle west of center") authored by Claude.

Fix:
- Boss arena becomes a 2048² organic cavern carved by angular-noise around boss-ring sector centers; surrounding cave noise blends naturally into the rim so entrances emerge for free.
- Interior contents come from a per-variant `ArenaComposition` resource — a list of typed features with positional regions, evaluated at gen time. No PNGs.
- Compositions are authored by Claude (the assistant). Reviewer-author (user) is responsible only for material/entity sprites and high-level review.

### 1.1 Relationship to the 2026-05-14 set-piece spec

This spec **supersedes**:

- §2 of the set-piece spec (boss arena perimeter, size, PNG approach).
- §3 of the set-piece spec (elite chest room size, PNG approach).
- §3.5 of the set-piece spec (`MAT_OIL`, `MAT_EXPLODE_WAVE`, tuning constants) — **explicitly deferred out of this session.** Oil and explode-wave mechanics are out of scope for this spec; their interior-feature types (`oil_pool`, `oil_barrel`) are accepted as named feature types in the composition schema but resolve to no-op stubs until a later spec wires them up.

This spec **keeps unchanged**:

- §4 — secret-chest design (PNG stamp inside solid terrain, cracked-wall hint).
- Marker IDs 1–7 from §2 and their dispatcher entries (boss spawn, enemy variants, chest, pool seeds for water/lava/gas).

Removed:

- `BiomeDef.perimeter_material` field. No biome accent ring anymore.
- The 5 per-biome perimeter accent material registrations.
- All references to `addons/level_preview` — addon is **deleted** in §5.3.

---

## 2. Boss Arena

### 2.1 Footprint and sector claiming

- Nominal radius **960 px**, modulated by angular noise (§2.2). Outer reach ~1120 px, inner pinch ~800 px. Total arena width ~2240 px.
- Spans roughly 5×5 sectors (sector size 384 px). Claims a **7×7 sector block** around its anchor (the boss sector plus its 24 neighbors at Chebyshev distance ≤ 3).
- **Boss ring spacing.** With a 7×7 claim block, naïvely letting every Chebyshev-10 sector roll boss causes overlap (the ring has 80 sectors). Boss sectors are selected as a **spaced subset** of the ring: walking the ring in clockwise order from `(10, -10)`, every 8th sector becomes a boss sector. Yields exactly 10 boss arenas per floor, evenly distributed, no overlap. The selection is deterministic on world seed.
- Claimed neighbor sectors (the 48 sectors per boss = 49 minus the boss sector itself, but most are inside the ring spacing already) return `is_empty=true, is_claimed=true` and contribute no templates of their own. Cave noise still runs across them, then the carve overrides.

### 2.2 Procedural carve stage — `stage_cavern_carve`

New GPU stage in `shaders/include/cavern_carve_stage.glslinc`. Parameterized per invocation by `(center, base_radius, lobing_amplitude, inner_disc_radius, noise_seed)`. Runs *after* base cave noise and pool stages, *before* walkability enforcement and any prop stages.

Per cell within the carve's bounding region:

```
d = length(cell_world_pos - center)
theta = atan2(cell.y - center.y, cell.x - center.x)
r = base_radius + cavern_angular_noise(theta, noise_seed) * lobing_amplitude
if d < inner_disc_radius:
    cell.material = MAT_AIR          # hard-guaranteed inner disc
elif d < r - 16:
    cell.material = MAT_AIR          # carved interior
elif d < r:
    # soft band — preserve cave noise to produce organic rim and entrances
    pass
else:
    pass                              # untouched
```

`cavern_angular_noise(theta, seed)` is a 1D periodic noise (sum of 3–4 sine harmonics with seeded random phase/amplitude) sampled over `theta`. Deterministic per `noise_seed`.

Boss invocation: `(boss_center, 960, 160, 256, hash(world_seed ^ boss_sector_coord))`.

The stage also writes the `NO_PROPS` bit in `chunk_flags_tex` (mask buffer from the pending Part 3 rewrite, allocated for this spec — see §4.2) for every cell where it produced or preserved arena interior, so the eventual ambient-prop dispatcher won't compete with the curated interior.

### 2.3 Composition resources

`ArenaComposition` is a new `Resource` class:

```gdscript
class_name ArenaComposition extends Resource

@export var arena_kind: StringName          # &"boss" or &"elite"
@export var biome: StringName               # &"caves" / &"mines" / ...
@export var variant_id: StringName          # &"a" / &"b" / &"c" / &"d"
@export var nominal_radius: int             # 960 (boss) or 224 (elite)
@export var features: Array[ArenaFeature]
```

`ArenaFeature` is a base resource with concrete subclasses, each carrying a `region: ArenaRegion` and feature-specific parameters.

#### 2.3.1 Region types

- `RegionPoint { offset: Vector2 }` — single position relative to arena center.
- `RegionDisc { center: Vector2, radius: float }` — uniform sample inside disc.
- `RegionRing { center: Vector2, r_min: float, r_max: float }` — uniform sample in annulus.
- `RegionArc { center: Vector2, angle: float, span: float, r_min: float, r_max: float }` — annular wedge.

All sampling is rejection-sampled against the carve mask: positions that fall on non-air cells (e.g. landed in the soft band on a wall) are re-rolled up to 8 times per item, then dropped silently.

#### 2.3.2 Feature types

- `FeatureBossSpawn { boss_id: StringName }` — uses `RegionPoint` only, always placed at exact arena center regardless of mask (carve guarantees inner disc air).
- `FeatureEnemyPack { enemy_id: StringName, count: int }` — `count` enemies sampled in `region`.
- `FeaturePillarCluster { count: int, spacing_min: float }` — places solid `background_material` blobs (radius 8–14 cells) at sampled positions; Poisson-disk-style rejection on `spacing_min`.
- `FeaturePoolPatch { material_id: int, count: int, size_min: int, size_max: int }` — stamps disc-shaped pools of `material_id` (water/lava/gas — `MAT_OIL` deferred). `material_id` must resolve to a non-deferred material; if the named material is deferred (oil), the feature is skipped at runtime and a warning logged.
- `FeatureBarrelCluster { barrel_kind: StringName, count: int }` — spawns barrel entities. `barrel_kind=&"explosive"` works using whatever damage the barrel's existing scene does on destruction. `barrel_kind=&"oil"` resolves to a no-op stub (deferred).
- `FeatureVent { vent_kind: StringName, count: int }` — spawns gas-vent entities. `vent_kind=&"gas"` works. Other kinds deferred → no-op.
- `FeatureChestSpawn { chest_id: StringName }` — used by elite compositions; uses `RegionPoint`, always placed at exact arena center.

The deferred-stub policy means I can author compositions today that reference oil and explode behavior, and they'll silently no-op until the post-spec wires them up. No breakage.

### 2.4 Boss arena compositions (Claude authors)

20 `.tres` files total: 4 variants × 5 biomes.

Path: `assets/arenas/boss/<biome>_<variant>.tres`.

I (Claude) author all 20 in the implementation pass. Each composition specifies ~15–25 features. Variants per biome differ on layout *concept*, not just feature counts:

- **Variant A — Pillar Hall:** dense ring of pillars at r=600..900, enemies in outer arc, boss + 2 elites at center, 1 lava patch.
- **Variant B — Pool Trap:** central lava + water pools, scattered barrels, enemies pinned to perimeter, pillars sparse.
- **Variant C — Vent Maze:** clusters of gas vents creating "vision pockets," pillars in irregular clumps, boss in a small clearing.
- **Variant D — Open Killing Field:** few pillars, many enemies in concentric rings, several barrel clusters as kiteable threats.

Per-biome flavor adjusts material IDs (e.g. `frozen` swaps lava→water, adds ice pillars; `vault` uses metal pillars, no pools).

The actual feature lists live in the `.tres` files written during implementation. This spec defines the schema, not the content; reviewing 20 composition files belongs in the implementation PR.

---

## 3. Elite Chest Room

Same approach, smaller scale.

### 3.1 Footprint

- Nominal radius 224 px, lobing amplitude 48 px. Inner disc 48 px. Outer reach ~272 px.
- Occupies ~1.4×1.4 sectors. Claims 1 neighbor sector — the neighbor whose center is closest to the carve's long axis direction. Other neighbors unaffected.
- Uses the same `stage_cavern_carve` invoked with parameters `(elite_center, 224, 48, 48, hash(seed^coord))`.

### 3.2 Compositions (Claude authors)

15 `.tres` files: 3 variants × 5 biomes.

Path: `assets/arenas/elite/<biome>_<variant>.tres`.

Each composition has ~5–8 features:

- 1 `FeatureChestSpawn` (center, fixed).
- 2–3 `FeatureEnemyPack` (elite variants).
- 0–1 hazard cluster (one of: small lava puddle, gas vent cluster, or 2–3 explosive barrels).
- 0–1 `FeaturePillarCluster` (small, ≤ 4 pillars).

### 3.3 Pool integration

Elite chest stays in `BiomeDef.room_templates` with `is_elite_chest=true, cavern_carve=true`. Weight tuned for ~10% of non-empty sectors (unchanged from 2026-05-14 spec §3).

---

## 4. Pipeline Integration

### 4.1 Stage order

1. `stage_simplex_cave` (existing) — base cave noise.
2. `stage_biome_pools` (existing) — solid pool variants.
3. `stage_pixel_scene_stamp` (existing) — secret-chest stamps + any non-cavern-carve room templates (legacy blob/corridor types).
4. **`stage_cavern_carve`** (new) — runs once per claimed cavern (boss or elite) overlapping the chunk. Multiple dispatches per chunk if multiple cavern sectors overlap.
5. **Composition evaluation (`CompositionDispatcher`, GDScript)** — runs on `chunks_generated`, after the GPU stages, before enemy/entity spawn. For each cavern overlapping the chunk, looks up the chosen variant's composition resource and evaluates its features (samples regions, validates against carve mask, spawns/stamps).
6. `stage_walkability_enforce` (Part 1) — trivially satisfied within the guaranteed inner disc.
7. Subsequent prop/boundary stages — respect `NO_PROPS` mask.

### 4.2 Mask buffer (NO_PROPS)

The companion `chunk_flags_tex` storage texture from the pending Part 3 rewrite is allocated by this spec (otherwise we have nowhere to write the protection bit). Allocation lives in `ComputeDevice`:

- R8 storage texture, one byte per chunk cell, parallel to `chunk_tex`.
- bit 0 = `NO_PROPS`. Other bits reserved.
- 64 KB/chunk × ~25 active chunks ≈ 1.6 MB GPU.

If Part 3 rewrite already lands this buffer, this spec is a no-op for that piece.

### 4.3 Composition evaluation in `CompositionDispatcher`

Per cavern instance overlapping a freshly-generated chunk:

1. Resolve the cavern's anchor sector and chosen variant (deterministic from world seed + sector coord + variant pool size).
2. Load the `ArenaComposition` resource.
3. RNG seeded by `hash(world_seed ^ anchor_coord ^ feature_index)` — ensures determinism per-cavern-per-feature.
4. For each feature, sample positions from its region, rejection-test against carve mask (read via `world_manager.read_region`), drop after 8 retries.
5. Spawn entities (enemies, barrels, vents, chest, boss) into the scene tree, or stamp material cells (pillars as solid blobs, pool patches as fluid material) into the chunk.

The dispatcher only fires for chunks that *contain* a cavern center or are within a cavern's reach (`> max_radius_overlap_check`). Other chunks skip entirely.

### 4.4 Cave-noise continuity

`stage_simplex_cave` runs first across the entire footprint untouched. The carve's soft band (`r - 16 < d < r`) preserves whatever the cave noise produced, so cave tunnels reach into the cavern as natural entrances. No special-case entrance logic.

---

## 5. Implementation Surface

### 5.1 New files

- `shaders/include/cavern_carve_stage.glslinc` — parameterized organic carve.
- `src/core/arena_composition.gd` — `ArenaComposition` resource class.
- `src/core/arena_feature.gd` — `ArenaFeature` base + subclass files (`feature_boss_spawn.gd`, `feature_enemy_pack.gd`, `feature_pillar_cluster.gd`, `feature_pool_patch.gd`, `feature_barrel_cluster.gd`, `feature_vent.gd`, `feature_chest_spawn.gd`).
- `src/core/arena_region.gd` — `ArenaRegion` base + subclass files (`region_point.gd`, `region_disc.gd`, `region_ring.gd`, `region_arc.gd`).
- `src/core/composition_dispatcher.gd` — post-gen GDScript pass that evaluates compositions.
- `assets/arenas/boss/{caves,mines,magma,frozen,vault}_{a,b,c,d}.tres` — 20 boss compositions.
- `assets/arenas/elite/{caves,mines,magma,frozen,vault}_{a,b,c}.tres` — 15 elite compositions.

### 5.2 Modified files

- `src/core/sector_grid.gd` — add `is_claimed` to `RoomSlot`; implement spaced boss-sector selection (every 8th ring sector); claim 7×7 (boss) or single-neighbor (elite) blocks.
- `src/core/room_template.gd` — add `cavern_carve: bool` flag and `composition_pool: Array[ArenaComposition]` field on the template; remove PNG-based boss/elite fields.
- `src/core/biome_def.gd` — drop `perimeter_material` (added by 2026-05-14 set-piece spec).
- `src/autoload/biome_registry.gd` — drop `perimeter_material` wiring.
- `src/autoload/material_registry.gd` — drop the 5 per-biome perimeter accent registrations. **Keep** `cracked_material` registrations (used by secret chests, unaffected).
- `assets/biomes/*.tres` — drop `perimeter_material`; reference the new boss/elite composition pools instead of PNG templates.
- `src/core/world_manager.gd` — emit `chunks_generated` with the chunk's bounding sectors; `composition_dispatcher` hooks here.
- `shaders/compute/generation.glsl` (or equivalent pipeline file) — insert `stage_cavern_carve` invocation per overlapping cavern; allocate `chunk_flags_tex` if not already.

### 5.3 Deletions

- **`addons/level_preview/`** — entire directory removed.
- Any references to `level_preview` in `project.godot` (`addons/...` enabled list), tests, docs.
- The previous 2026-05-17 spec's §6 (tooling overlays) — removed; no replacement tooling planned in this spec.
- Old boss-PNG assets at `assets/rooms/<biome>/boss_arena_*.png` and elite-PNG assets at `assets/rooms/<biome>/elite_chest_*.png` if present from earlier implementation work. Replaced by composition resources.

### 5.4 Explicit manual work (user-owned)

Everything in this list is your responsibility, not Claude's:

**Sprites / scene assets** (Godot `.tscn` with sprite + collider + behavior script):
- `scenes/props/explosive_barrel.tscn` — keep existing if present.
- `scenes/props/gas_vent.tscn` — new, simple emitter (existing gas material).
- `scenes/props/wooden_pillar.tscn` — new, solid prop with destructible behavior.
- Boss enemy scenes — at minimum one boss per biome (5 total). Existing if already authored, else new.
- Elite enemy scenes — used by elite compositions; existing if already authored.

**Sprite art (PNG)** — at least placeholder art is acceptable; final polish later:
- Explosive barrel sprite (existing if present).
- Gas vent sprite.
- Wooden pillar sprite (or in-engine drawing of solid `background_material` blob suffices for v1).
- Boss sprites per biome.

**Composition review:**
- After Claude authors the 20 boss + 15 elite `.tres` files, you read them and adjust feature counts / regions / variant concepts as desired. Compositions are plain `.tres` so direct editing is fine.

**Biome resource edits:**
- Remove `perimeter_material` from each `assets/biomes/*.tres`.
- Add `boss_compositions: Array[ArenaComposition]` and `elite_compositions: Array[ArenaComposition]` references to the new files. (Or whatever shape the biome registry expects.)

**Out of your queue (Claude does it):**
- Authoring all 35 composition `.tres` files.
- Deleting `addons/level_preview`.
- Writing the carve shader, dispatcher, and feature/region classes.

---

## 6. Testing

- **Boss carve geometry:** for 100 seeds × 5 biomes, sample the inner disc (radius 256) at every boss sector; assert 100% `MAT_AIR`.
- **Boss carve organic outline:** for 100 seeds, compute carved-air radius at 64 angles per boss; std dev across angles in [60, 200] px (lobing exists, bounded).
- **Boss ring spacing:** for any world seed, the chosen boss sectors are exactly 10 in count, all at Chebyshev 10, all pairwise ≥ 7 ring positions apart.
- **Sector claiming:** for each boss sector, all 48 neighbors at Chebyshev distance ≤ 3 resolve to `is_empty=true, is_claimed=true`.
- **Elite carve geometry:** inner disc radius 48 all air; nominal radius 224 ± 48 across 64 angles.
- **Composition determinism:** generate a chunk with a given world seed twice; same feature positions both times.
- **Composition rejection survival:** for each boss variant × biome, average across 100 seeds, ≥ 75% of authored features successfully spawn (rest rejected by carve mask after retries).
- **Boss spawn guarantee:** for 1000 seeded boss arenas, exactly one boss entity spawns per arena at the inner-disc center.
- **Walkability invariant unchanged:** existing walkability tests still pass with the carve + composition stages in the pipeline.
- **Entrance presence:** for 100 seeded boss arenas, flood-fill from inner disc; at least one cave-noise tunnel reaches beyond the 7×7 footprint.
- **No PNG dependency:** grep the repo for `boss_arena_*.png` and `elite_chest_*.png` references — none should remain.
- **level_preview removed:** `addons/level_preview` directory absent; `project.godot` does not list it; no source file imports from it.

---

## 7. Out of Scope (Deferred)

- `MAT_OIL`, `MAT_EXPLODE_WAVE`, oil-burning behavior, explode-wave sim. These feature types appear in the composition schema as named values but resolve to no-op stubs. Wire-up is a future spec.
- Ambient-prop dispatcher for normal cave chunks (Part 3 rewrite).
- World boundary (wardstone ring, void-stone wall) — Part 3 rewrite.
- Powder sim, destruction debris tables — Part 3 rewrite.
- Secret chest design — already covered by 2026-05-14 set-piece spec §4, unchanged.
- Authoring tooling / visualization — no replacement for the deleted `level_preview`. If needed later, a screenshot-on-demand or print-arena CLI command can be added.

---

## 8. Open Risks

- **Composition authoring quality.** Claude writes 35 `.tres` files in the implementation pass. Quality bar is "playable, recognizably distinct per variant, fits the biome." Likely several iterations after first review. The data-driven format makes revision cheap (edit a number, not a pixel).
- **Readability without architectural framing.** A purely-organic cavern at 2048² should read as "huge cave" from a distance. Scale and density (15–25 features per arena) carry the landmark feel. If playtesting shows the rim is too subtle, fallback is to scatter biome-flavored debris (rubble blobs, not a wall) in the soft band — added as a `RimDebris` feature type in a follow-up, not a re-spec.
- **Spaced boss ring affects pacing.** 10 boss arenas per floor instead of "every ring sector" means more cave between bosses. That's the intended effect (bosses are landmarks), but if it makes the ring feel sparse, the spacing constant (8) becomes a tunable.
