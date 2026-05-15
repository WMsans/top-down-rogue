# Walkable Space — Design

**Status:** Draft
**Date:** 2026-05-14
**Scope:** Part 1 of 3 in the level-generation overhaul (walkable space).
Companion specs (forthcoming): set-piece rooms (boss / elite chest / secret); props & world boundary.

---

## 1. Goal & Invariant

The cave generator keeps its organic "Open Noita" feel — chunk-based FBM noise carving with biome-tinted pool deposits. The change: every chunk that can host combat must satisfy a hard **walkability invariant**, regardless of seed or biome.

**Invariant.** Every cave-type chunk contains a contiguous open pocket of ≥ 150×150 px (≈ 22,500 air cells), reachable from each occupied chunk border via an opening ≥ 24 px wide.

Tunnel chunks are exempt and made rare (~15% of chunks, down from ~45%). The invariant is enforced by a post-noise structural pass — not by parameter tuning alone. Biomes can push pool aggressiveness and visual identity hard; the pass reclaims walkable space where necessary.

**Why this shape:** 150×150 px is roughly an EtG-equivalent fightable arena at this game's scale (player footprint ≈ 13 px; pocket gives ~10 player-widths to dodge / kite / break LoS). Cross-chunk openings of 24 px (≈ 1.8 player-widths) are wide enough that movement never feels pinched. Tunnel chunks remain in the rotation so the world still has the rhythm of "arena → narrow stretch → arena," but rarely enough that no level is dominated by them.

---

## 2. Generation Pipeline Changes

Current per-chunk order (GPU compute, in `cave_stage` and biome stages):

1. `stage_cave` / `stage_biome_cave` — FBM/ridge noise + edge fade + connector boost → carves air
2. `stage_biome_pools` — pool deposits re-fill some air with stone variants
3. `stage_pixel_scene_stamp` — room template stamps (boss, blob, corridor, secret)
4. `stage_secret_ring` — secret-room rings

**New order — two stages inserted at the end:**

5. **NEW: `stage_walkability_probe`** — compute, per air cell, the inscribed-disk radius (jump-flood-style distance transform). Write to a scratch channel.
6. **NEW: `stage_walkability_enforce`** — if the chunk's max inscribed-disk radius < 75 px, fix it: (a) mask out pool deposits inside the largest pocket; (b) if still short, dilate the pocket until it hits 75 px radius.

Both new stages run GPU-side in the same compute pipeline as the rest of gen. No CPU readback, no streaming-latency impact.

The existing inter-chunk connector tunnels (in `carve_tunnel_path`) are widened: `TUNNEL_RADIUS` 10 → 14, ensuring ≥ 28-px cross-chunk passages (above the 24-px invariant).

---

## 3. Structural Pass — Algorithm Detail

Two GPU stages, both per-chunk, no neighbor reads needed.

### 3.1 `stage_walkability_probe`

For each air cell, compute the radius of the largest open disk inscribed at that cell — Chebyshev distance to the nearest solid cell, clamped to 127.

Implementation: **Jump-Flood Algorithm (JFA).** Initialize each cell with its own coords if solid, else "unknown." Run `log2(CHUNK_SIZE) = 8` passes with stride halving (128, 64, 32, …, 1); each pass writes the closest known solid seed seen by its neighbors at that stride. Final radius per cell = distance to its nearest-solid seed.

Output: per-cell inscribed-radius in scratch, plus an atomic-reduced `chunk_max_radius` scalar (with the coords of the argmax).

### 3.2 `stage_walkability_enforce`

If `chunk_max_radius >= 75`, the chunk satisfies the invariant — skip.

Otherwise, using the argmax cell as the centroid of the largest pocket, run a two-step fix:

**Step A — strip pools.** For each cell within `chunk_max_radius + 80` of the centroid, if it was added by `stage_biome_pools` (known via a "pool-origin" bit tagged into a scratch channel during step 2), revert it to air. Re-run JFA. If `chunk_max_radius >= 75` now, done.

**Step B — dilate.** While `chunk_max_radius < 75`: turn every solid cell adjacent to an air cell within the pocket-bounded region into air. One iteration ≈ +1 to inscribed radius. Cap at 30 iterations. Re-run JFA between iterations.

**Worst-case cost per chunk:** ~270 compute passes ≈ ~2 ms on a modest GPU at 256² resolution. Streaming generates <10 chunks/sec under normal play → <20 ms/sec budget. Comfortably within frame.

---

## 4. Biome Retuning & Chunk-Type Redistribution

Parameter changes that reduce how often the structural pass does hard work, and let biomes lean harder into visual identity.

### 4.1 Chunk-type redistribution

In `cave_utils.glslinc`:
- `TYPE_CAVE_THRESHOLD: 55u → 85u` — cave/multi-cave chunks rise from ~55% to ~85% of chunks; tunnel chunks fall to ~15%.
- Multi-cave share within "cave" stays proportional.

### 4.2 Biome `cave_threshold` floor

All biomes (`caves.tres`, `mines.tres`, `magma.tres`, `frozen.tres`, `vault.tres`) get `cave_threshold` clamped to ≤ 0.42. Lower threshold = more air. Expected open ratio per cave chunk rises to ~65%, so the structural pass becomes a safety net rather than the primary mechanism.

### 4.3 Pool deposit policy

Biomes keep their `pool_materials` as designed for visual identity. The structural pass's strip-pools step handles overpopulation. No biome data changes — this is intentional. Biome authors push pool aggressiveness without worrying about playability.

### 4.4 Tunnel widening

In `cave_stage.glslinc`: `TUNNEL_RADIUS: 10.0 → 14.0`. Cross-chunk tunnels become ≥ 28 px wide.

---

## 5. Implementation Surface

**New files:**
- `shaders/include/walkability_probe_stage.glslinc` — JFA distance transform + atomic max-radius reduction
- `shaders/include/walkability_enforce_stage.glslinc` — strip-pools + dilation passes
- `tests/unit/test_walkability_invariant.gd` — invariant + connectivity tests

**Modified:**
- `shaders/compute/generation.glsl` / `generation_simplex_cave.glsl` — wire the two new stages after pools/stamps
- `shaders/include/cave_utils.glslinc` — `TYPE_CAVE_THRESHOLD: 55u → 85u`
- `shaders/include/cave_stage.glslinc` — `TUNNEL_RADIUS: 10.0 → 14.0`
- `shaders/include/biome_pools_stage.glslinc` — tag each pool-deposited cell with a "pool-origin" bit in the scratch channel
- `assets/biomes/*.tres` — clamp `cave_threshold` ≤ 0.42 where above
- `src/core/world_manager.gd` — no functional change; new stages slot into the existing `compute_device.dispatch_generation` call
- `gdextension/src/...` (compute_device setup) — allocate scratch channel usage for inscribed-radius + pool-origin bit

**Scratch channel layout.** `chunk_tex` is RGBA8 (R=material, G=health, B=temperature, A=reserved). Reuse `A` during gen for: bit 7 = pool-origin flag; bits 0–6 = inscribed-disk radius (clamped to 127). Reset to 0 before gen finishes so downstream readers see clean A.

---

## 6. Testing

- **Invariant test** (`tests/unit/test_walkability_invariant.gd`): for 100 seeds × 5 biomes, generate a 5×5 chunk region, assert every cave/multi chunk has max inscribed-disk radius ≥ 75 px.
- **Connectivity test:** in the same regions, flood-fill the union of all air cells; assert ≥ 95% of air cells belong to the largest connected component.
- **Visual regression:** extend `addons/level_preview` to render the inscribed-radius heatmap alongside the cave. Eyeball-check that biome identity (pool patterns, ridges, tints) is preserved on easy seeds.
- **Perf:** log per-chunk gen time before/after; assert mean increase ≤ 3 ms/chunk on the dev GPU.

---

## 7. Out of Scope (Handled in Companion Specs)

- Boss room / elite chest room set-piece design and secret-chest occlusion → Part 2.
- Environmental props (lava, gas, pillars, water, explosive boxes, powders, oil barrels) and world boundary → Part 3.
