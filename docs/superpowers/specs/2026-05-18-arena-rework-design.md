# Elite + Boss Arena Rework

## Problem

Elite and boss arenas currently feel empty and uninteresting:

- **Elite arenas** (`nominal_radius=224`) are too large for their purpose — a small encounter room with a chest and 2-3 elites — and have very few terrain elements (typically 0-2 pillars, maybe one pool).
- **Boss arenas** (`nominal_radius=960`) are massive but sparsely populated — a boss, a handful of pillars, a few enemy packs, optionally one pool. Most of the area is empty floor.

## Goal

Shrink both arenas and pack them with terrain features so each encounter feels deliberate and visually busy ("crammed together" is the desired feel). Give each variant a distinct identity rather than treating variants as parameter shuffles.

## Scope

Single-file change: `tools/generate_arena_compositions.gd`. After edits, re-run the generator to overwrite all `.tres` files in `assets/arenas/{elite,boss}/`.

No changes to feature classes, the composition dispatcher, or the composition resource format.

## Dimensions

| Field | Elite old | Elite new | Boss old | Boss new |
|---|---|---|---|---|
| `nominal_radius` | 224 | **140** | 960 | **300** |
| `lobing_amplitude` | 48 | **30** | 160 | **50** |
| `inner_disc_radius` | 48 | **30** | 256 | **80** |

Pillar params (`pillar_radius_cells=10`, `spacing_min=64`) stay unchanged — current values produce visually small pillars in actual generation.

## Pool sizing for crammed feel

Pool blob radii (in tile cells) scale per arena kind so blobs fit inside the new smaller arenas without dominating:

- **Elite pools**: `size_min_cells=3`, `size_max_cells=6`
- **Boss pools**: `size_min_cells=5`, `size_max_cells=10`

(Old values were 8-16 for both, which would be larger than the new elite arena.)

## Elite variants (r=140, 3 per biome)

All variants share a dense base — every variant has `chest + 1-2 elites + 5-6 pillars + 2 pools (1 in vault biome substitution) + 4-5 barrel clusters`. Variant identity is in arrangement, not counts:

- **`a` "Hazard heart"** — pools concentrated at center (one `pool_patch` with `count=2-3` in inner disc r=0-40); pillars in outer ring (r=80-130); barrels mid-ring (r=50-100); 1-2 elites at the outer ring.
- **`b` "Pillar grove"** — pillars dominate; 6-7 pillars spread r=30-130; 2 pools tucked in one offset pocket (e.g., (60, -40), radius 40); 3-4 barrel clusters scattered; 2 elites near chest.
- **`c` "Barrel field"** — 4-5 barrel clusters across multiple ring bands (inner, mid, outer); 2 pools at opposing offsets ((-50, 0), (50, 0)); 5 pillars near edges; 2 elites mid-ring.

**Vault biome substitution** (no pool material): replace pools with +1 barrel cluster and +1 vent feature (if biome-appropriate) or an extra pillar.

## Boss variants (r=300, 4 per biome)

All variants share: `boss in center + 6-8 pillars + 2 pools + 3-4 barrel clusters + 4-5 enemy packs (mix of regular + elite)`. Variant identity:

- **`a` "Hazard ring"** — pools concentrated mid-ring (one `pool_patch` with `count=2` at ring r=80-160); 7 pillars outer (r=180-280); 4 enemy packs spread inner/mid/outer; one barrel cluster pocket at offset.
- **`b` "Pillar maze"** — 4-pillar pocket at fixed offset (e.g., (-120, 80), radius 60) PLUS 4 ring-distributed pillars (r=150-280); 2 pools at edge offset pocket; 4 barrel clusters scattered; 5 enemy packs.
- **`c` "Explosive yard"** — 4-5 barrel clusters distributed mid + outer (r=80-280); 2 pools at offsets; 6 pillars near edges; one vent feature near center; 4 enemy packs.
- **`d` "Vent crucible"** — 2 vent features at offset pockets ((100, -80), (-100, 80)); pools in inner-mid ring (r=60-150); 6 pillars outer; 3 barrel clusters; 4 enemy packs.

**Vault biome substitution**: pools become +1 barrel cluster + 1 extra pillar.

## Helper changes

New helpers in the generator:

- `_pool(center, radius, mat, count, min_cells, max_cells)` — extend existing `_pool` to accept blob size range, so elite and boss can pass different scales.
- `_barrels(count, r_min, r_max)` — currently no barrel helper; add one wrapping `FeatureBarrelCluster` with biome-default `barrel_scene`.
- `_vent(offset, radius)` — wrap `FeatureVent` for offset-pocket placement.
- Keep `_pillars`, `_enemies` signatures stable.

## Generator structure

Replace existing per-variant builders (`_build_variant_a..d`, `_build_elite_a..c`) with new bodies matching the variant specs above. Top-level `_init()` loop stays the same — same biomes, same variant ids, same file paths.

## Risks

- **Crammed regions may fail placement retries**: features sample air positions with 8 retries. If too many features compete for inner disc r=0-40 (an area of ~5000 sq px), some may silently fail to spawn. We accept this risk for the "crammed" aesthetic; if visible gaps appear in playtest, reduce overlap.
- **Vault biome variants feel different from biome-mates**: with no pools, vault loses a feature category. The substitution rules above keep total feature count comparable.

## Testing

Smoke test by running the generator (`godot --headless -s tools/generate_arena_compositions.gd`) and visually inspecting a few generated arenas in-game. No automated tests for visual composition.

## Out of scope

- New feature types (e.g., breakable walls, decorative props)
- Per-biome variant differences beyond the existing pool material / pillar material rules
- Adjusting feature classes themselves (only their parameters in compositions)
