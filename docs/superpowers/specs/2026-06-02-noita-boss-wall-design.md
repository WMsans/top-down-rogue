# Noita-Style Boss Wall Arena — Design

**Date:** 2026-06-02
**Branch:** fix/boss-density
**Status:** Approved (design), pending implementation plan

## Problem

Boss rooms are missable. The world is a top-down radial cave field; bosses sit on
concentric square rings at sector-distance 8 / 10 / 12 (`SectorGrid`), each carved as
a small (~300px radius) organic cavern via `stage_cavern_carve`. Everything else —
including the space *between* boss caverns and everything beyond ring 12 — is open,
navigable cave noise (`stage_biome_cave`).

Because killing **any** boss spawns the portal to the next floor
(`spawn_dispatcher.gd:_on_boss_died`), bosses *are* the level exit. But a player can
walk straight through the gaps between the small boss clearings and out into open void
— e.g. reaching `(-500, -8376)` (~22 sectors north, past the ring-12 world edge)
without ever entering a boss room. The rings don't actually block anything.

In Noita, boss areas are impossible to miss because they're huge, solid-walled rooms
that physically block passage. We want the same guarantee.

## Goal

Make boss rooms **physically unmissable**: the player cannot leave the central play
area or reach the level-exit portal without entering a boss chamber.

## Approach (chosen)

A **walled arena with boss-gate pockets** (hybrid: solid barrier + big enclosed
chambers), single boss ring, indestructible wall.

```
########( B )#############( B )######
###  BEDROCK  (indestructible, world edge)
##                                    ##
( B )      central cave area          ( B )
##         (normal rooms, player           ##
##          spawns at center .S.)          ##
( B )                                  ( B )
##                                         ##
########( B )#############( B )#########
( B ) = huge boss chamber carved into the inner wall face.
        Portal appears here on boss death.
```

- **Central play area** — sector-distance `< 8` from origin. Unchanged: normal rooms,
  cave noise, player spawn at origin.
- **Bedrock wall** — everything at sector-distance `>= 8` is filled with a new
  indestructible `BEDROCK` material, extending to the world edge. This removes the open
  void entirely (kills the `-8376` wander).
- **Boss chambers** — ~10–12 huge (~600px radius) chambers carved into the inner face
  of the wall, on a **single** ring at distance 8. Each opens into the central area;
  its outer portion is a dead-end pocket inside the bedrock where the boss and (on
  death) the portal sit. These chambers are the **only** openings in the wall.

The player explores out from center, meets the bedrock wall, follows it, and reaches a
boss chamber within a short walk (chambers are spread across ~10–12 angles for full
coverage). Enter, fight, portal, descend. Cannot be missed; cannot be bypassed.

### Why a single ring (not 3)

Keeping rings 8/10/12 inside one solid wall would bury the r=10 and r=12 bosses in
bedrock with no opening to the central area (a 600px chamber at r=12 ≈ 4600px cannot
reach the r=8 ≈ 3072px inner face). Collapsing to a single ring at the wall face — the
"1 boss to break out" model — avoids buried chambers cleanly. The interspersed
3-ring system is retired.

## Components / Changes

### 1. New `BEDROCK` material (indestructible)

- Add to `MaterialRegistry`: non-flammable, `has_collider = true`,
  `has_wall_extension = true`, dark tint, reuse `stone.png` texture for now.
  Hardness value is irrelevant (it is never a dig target) — set high (e.g. 999).
- Regenerate `shaders/generated/materials.glslinc` (and `.gdshaderinc`) via
  `tools/generate_material_glsl.gd`.
- **Indestructibility is enforced by exclusion + one guard:**
  - *Melee / projectile digging* is opt-in via a material target mask
    (`terrain_modifier.clear_and_push_materials_in_arc` builds `target_mask` only from
    the passed material list; weapons pass DIRT/STONE/etc). BEDROCK is simply never in
    any weapon's list → automatically undiggable. No change needed beyond *not* adding
    it.
  - *Explosions* (`explode_wave.glslinc` Branch D) chew **any** colliding solid by
    health. Add an explicit guard: `if (material == MAT_BEDROCK) return false;` so the
    wave does not erode bedrock.

### 2. New generation stage `stage_boss_wall`

- New include `shaders/include/boss_wall_stage.glslinc`, called from
  `generation.glsl` **after** `stage_secret_ring` and **before** `stage_cavern_carve`.
- For each cell: compute Chebyshev distance from origin in pixels. If
  `cheb_px >= WALL_INNER_SECTORS * SECTOR_SIZE_PX` (8 * 384 = 3072), store `MAT_BEDROCK`.
- Because it runs before `stage_cavern_carve`, the boss-chamber carve then punches those
  pockets back to AIR — the wall stage needs no per-pocket awareness.
- The wall is a square (Chebyshev) band, consistent with the sector grid. Blockiness at
  384px granularity is acceptable; using pixel distance keeps the inner face crisp.

### 3. Single boss ring in `SectorGrid`

- `BOSS_RING_DISTANCES := [8]`, `BOSS_RING_PHASES := [0.0]`,
  `BOSS_RING_ANCHOR_COUNT := 12` (tune for coverage; perimeter at d=8 is 64 sectors so
  12 chambers fit without overlap).
- Rename/repurpose `BOSS_WORLD_EDGE` → `WALL_INNER_SECTORS := 8`. In `resolve_sector`,
  sectors at distance `>= WALL_INNER_SECTORS` that are not boss anchors return
  `is_empty` (they become bedrock in the shader); no room generation past the wall.
- `is_boss_anchor` already supports a single ring via the existing loop; verify with the
  new constants.

### 4. Bigger boss chambers

- In the boss `ArenaComposition` resources (`assets/arenas/boss/*.tres`), raise
  `nominal_radius` 300 → ~600 and scale `inner_disc_radius` / `lobing_amplitude`
  proportionally so the guaranteed clear area and feature regions still fit. (Boss
  feature regions use radii up to ~290px today; the chamber must comfortably contain
  them.)

### 5. Enemy tier scaling

- `spawn_dispatcher.gd:148` scales enemy tier by `sector_dist / BOSS_WORLD_EDGE * 2`.
  With the playable area now `< 8`, repoint the divisor to `WALL_INNER_SECTORS` (8) so
  the 3 tiers still spread across the central area.

### 6. Tests

- `test_boss_ring_coverage.gd` and `test_sector_grid.gd` reference the old ring
  constants — repoint to the single-ring layout.
- Add coverage assertion: following the inner wall face (the d=8 square perimeter), the
  angular gap between consecutive boss anchors is bounded (no arc large enough to feel
  like a dead wall). I.e. the ~12 anchors give full perimeter coverage.

## What stays the same

- Central cave generation, room templates, pools, secret rings, props.
- Boss-death → portal → `advance_floor` flow.
- Falling-sand simulation, collider generation (bedrock gets a collider like any solid).

## Out of scope (YAGNI)

- Dedicated bedrock art/texture (reuse stone with a dark tint).
- Multi-ring / tiered boss progression (explicitly collapsed to one ring).
- Corridors to buried chambers (the rejected 3-ring variant).
- Anything beyond the wall — it is solid to the world edge; there is no outer area.

## Risks / Open considerations

- **Lava / other terrain ops vs bedrock.** Lava melting or `place_material` could in
  principle alter bedrock. Player weapons don't target it, but verify no biome hazard
  erodes the wall (frozen/magma biomes). If found, apply the same guard pattern.
- **Chamber-to-center opening.** With anchors on a square ring, corner anchors are
  farther (euclidean ~4616px) than edge anchors (~3264px). Confirm a ~600px chamber at
  every anchor still breaches the central area at its angle (corner square boundary is
  ~4344px, so a 600px inward reach to ~4016px opens in — holds, but verify in preview).
- **Chamber overlap / spacing.** With 12 anchors the chambers shouldn't overlap; verify
  in the level-preview tool.
