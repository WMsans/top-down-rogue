# Baked Per-Chunk Decor Lighting

**Date:** 2026-06-03
**Status:** Approved design

## Problem

The first level carries dense glowing decor. Each glowing decoration currently
spawns its own `PointLight2D` (a `FlickerLight`) as a child of its sprite in
`src/terrain/floor_chunk.gd`. In dense decor, far more than ~16 of these lights
overlap a single canvas item (the player, a floor quad), exceeding Godot 4.6's
hardcoded per-canvas-item 2D light cap (`MAX_LIGHTS_PER_ITEM`, ~15–16). The
renderer then drops a churning subset each frame, so the lights **flicker as the
player/camera moves**.

Decor is static (deterministic from seed; never moves or changes), so its
lighting can be baked. This is the same class of problem already solved for
terrain glow in `src/core/chunk_lights.gd`, which composites one chunk-spanning
`PointLight2D` per chunk from CPU-side radial splats.

## Decisions

- **Flicker:** dropped entirely. Decor lighting becomes fully static. The
  candle/torch animation is sacrificed for a steady, cap-safe bake.
- **Scope:** all decor in all biomes. The per-decor `FlickerLight` spawn is
  removed from `floor_chunk.gd` globally; no per-biome special-casing.
- **Approach:** per-`FloorChunk` baked light (Approach A). Self-contained in
  `floor_chunk.gd`, mirroring the proven `chunk_lights.gd` radial-splat pattern.
  Rejected: folding decor into `chunk_lights` (Approach B — couples a static
  system to the live terrain-glow path with different grids, lifecycles, and
  color models for marginal benefit) and a level-wide texture (Approach C —
  incompatible with streamed per-chunk world).

## Architecture

All changes are contained in `src/terrain/floor_chunk.gd`. The decor *placement*
loop in `_add_decorations` is unchanged; only what `_spawn_decor` produces
changes.

Today `_spawn_decor` adds a `FlickerLight` child per glowing decor. Instead:

1. During placement, the sprite is still added as before. For each glowing
   decor, collect its light contribution — `{center, color, energy, radius}` —
   into a local array instead of spawning a light.
2. After the placement loop, if any contributions exist, composite them into a
   single CPU `ImageTexture` and add **one** chunk-spanning additive
   `PointLight2D` to the chunk.

Net result per `FloorChunk`: at most **one** decor light, regardless of how many
glowing decorations it holds. Combined with the existing terrain-glow light from
`chunk_lights.gd`, any canvas item sees ~2 lights per overlapping chunk —
comfortably under the ~16-light cap, so no flicker.

## Compositing

Mirrors the radial-splat technique in `chunk_lights.gd`, with two deliberate
differences:

- **Colored accumulation.** Decor lights carry a per-`DecorDef` `light_color`,
  so contributions accumulate into RGB float buffers
  (`r/g/b += kernel · energy · color.{r,g,b}`) rather than intensity × one global
  color. After accumulation, each texel is clamped to `[0,1]` and packed to
  `RGBA8` with alpha `255`.
- **Linear falloff kernel** (`f = clamp(1 − t, 0, 1)`, where `t` is normalized
  distance from the splat center) to match the current decor look. The existing
  `FlickerLight` uses a *linear* radial `GradientTexture2D`, so the kernel must
  be linear, not the quadratic (`f*f`) kernel `chunk_lights` uses.

Geometry:

- The light texture spans the chunk (`CHUNK_SIZE = 256`) plus a `MARGIN` overhang
  (≈64px) on every side, so decor near a chunk edge bleeds correctly into the
  neighbor. Each chunk bakes **only its own** decor; the overhang covers the
  spill. The single `PointLight2D` is centered over the chunk (`texture` centered
  on the node), exactly as `chunk_lights` positions its light.
- **Constraint:** a decor's `light_radius` must stay ≤ `MARGIN`, otherwise its
  splat clips at the texture edge and produces a hard seam at the chunk boundary.
  The default radius is 56 (< 64). The radius is clamped defensively to `MARGIN`
  at bake time, and the constraint is documented in code.
- Resolution ≈4px/texel (sharper than terrain glow's 6px/texel, since decor
  lights are small). With `LIGHT_WORLD = CHUNK_SIZE + 2·MARGIN = 384`, this is a
  texture of ~96×96.

Brightness:

- Per-decor `light_energy` is baked into the texture. The `PointLight2D.energy`
  carries a tunable `DECOR_ENERGY` global multiplier, mirroring the `ENERGY`
  knob in `chunk_lights.gd` for easy overall tuning.

Splat anchor: contributions are stamped at the decor's light anchor — the sprite
position — to preserve the current appearance (the existing `FlickerLight` is a
child at the sprite's origin). Centering on the sprite is noted as a possible
later refinement but is out of scope here to avoid changing the look.

## Lifecycle & cleanup

- The bake runs **once** inside `populate()`. `populate()` already
  `queue_free`s all children on entry, so a rebuild produces no stale lights.
- **No `_process`.** This removes the per-decor `FlickerLight._process` work that
  previously ran every frame for every glowing decoration — a net performance
  win on top of the fix.
- `FlickerLight` (`src/core/flicker_light.gd`) **stays** in the codebase:
  `scenes/props/lantern.tscn` is a placed prop (not floor scatter) and still
  uses it directly. Only floor-scatter decor stops spawning it.

## Testing

gdUnit4 unit tests on `FloorChunk`:

- Populated with a fixed seed and a biome containing emitting decor → exactly
  **one** `PointLight2D` child exists (proves consolidation), and the baked image
  has non-zero pixels near a known emitting decor cell.
- Biome whose decor has `emits_light = false` → **no** light node is added.
- Determinism: the same seed produces the same light presence and texture
  contents.

Manual check: walk the first level and confirm the flicker is gone and decor
glow looks consistent with the previous (pre-bake) appearance.

## Out of scope

- Animated/flicker decor lighting (explicitly dropped).
- Refactoring `chunk_lights.gd` or extracting a shared compositor. The small
  amount of radial-splat logic duplicated between the two files is accepted to
  keep the static decor path decoupled from the live terrain-glow path.
- Re-centering decor light anchors on the sprite.
