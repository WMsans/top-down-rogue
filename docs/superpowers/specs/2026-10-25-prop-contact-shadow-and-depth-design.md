# Prop Contact Shadows and Depth — Design

**Date:** 2026-10-25
**Status:** Approved

## Intent

Trees and rocks look flat, like cut-outs pasted on the cave. Two causes *(user)*:

1. Props have no ambient occlusion. Walls cast a soft dark crease onto the floor at their base
   (`shaders/visual/render_chunk.gdshader`), but `ForestProp` is a bare tinted `Sprite2D`.
2. Grass growing in front of a tree draws behind it. Every prop sits at a fixed `z_index = 2`, and all
   flora lives in the floor chunk at z −10, so root flora on the south side of a trunk is always covered.
   Actors have the same bug (the existing `ponytail:` note at `src/props/forest_prop.gd:50`).

## Goals

- **Contact shadow on the ground** around each tree and rock base, the same look as the wall-to-floor
  crease *(user)*: darkest at the base, fading out over a few pixels. A rock's shadow follows the rock's
  width; a tree's hugs the trunk and does not spread under the canopy *(my call)*.
- **Flora inside the shadow gets darkened too, but its glow stays** *(user)*. A plant's glow is the baked
  per-chunk `PointLight2D` pool. That pool is unchanged; it just reads weaker inside the shadow, exactly
  as it already does in wall creases.
- **One front/behind rule for flora and actors** *(user: "actors too")*: anything whose base is south of a
  trunk base draws in front of the trunk; anything north draws behind it and is covered by the canopy.

## Non-goals / anti-goals

- No shading on the prop sprite itself (darker trunk bottoms, rock undersides). *(User picked ground
  patch.)*
- No glowing-part masks on flora art. Flora textures have no emissive region, so "keep caps bright" is out.
- Canopies must keep drawing over walls, and walls must keep covering actors as they do today
  (2026-10-23 vegetation design). Breaking either is a failure even if sorting "works".

## Approaches considered

- **A. Shadow sprite per prop (picked).** One shared, generated soft-oval gradient texture, scaled per prop
  from its trunk/rock width, drawn as black at partial alpha. It's freed along with the prop.
- B. Feed prop footprints into `render_chunk.gdshader` and compute AO like walls. Pixel-exact match, but
  needs per-chunk footprint data, an update when a prop is destroyed, and chunk-border handling.
  Rejected as too much plumbing for a soft oval.
- Draw order: the only workable way is to split each tree. A full y-sort rework of whole trees was ruled
  out because a whole tree can't both y-sort with actors (z 0) and draw over walls (z 1).

## The how, as decided

- **Shadow:** a child of the prop that draws above the floor and flora but below actors. That's the same
  slot the wall-crease overlay effectively occupies (black at `occ * ao_strength` over the floor), so
  floor and flora darken together with no per-flora work. Strength and falloff should match the walls'
  `ao_strength = 0.6` / `ao_floor_reach = 4` so props and walls read as lit the same way *(my call)*.
- **Tree split:** the canopy stays a sprite at z 2, above walls and actors. The **trunk band** (the bottom
  strip of the sprite, about one actor tall) becomes a separate sprite in a y-sorted layer shared with
  actors, anchored at the trunk base. Both halves share the hit flash, death pop, and canopy fade.
- **Rocks:** a rock never needs to draw over walls, so the whole rock can sort with actors. *(My call; the
  builder can split rocks the same way if a tall rock shows a problem.)*
- **Flora south of a trunk** (within the trunk band's width) moves into the same y-sorted layer at
  placement, so it draws over the trunk. Because it now sits above the shadow, it gets the shadow's
  darkening applied as a `modulate` based on its distance from the base *(my call)*. Side effect, accepted:
  that grass can also cover an actor's feet when the actor stands just north of it.
- **Remove the `ponytail:` fixed-z note** in `forest_prop.gd`; this change resolves it.

## Constraints the builder must handle

- **No y-sort exists anywhere yet.** Enemies, chests and similar nodes are added to `ChunkContainer`
  (`get_chunk_container()`), which also holds the chunk floor/wall `MeshInstance2D`s. Turning on
  `y_sort_enabled` there would sort the chunk quads among the actors. The Player is a sibling of
  `WorldManager` under the `SubViewport`. A dedicated y-sorted node is needed that holds the player,
  spawned actors and trunk bands, while the chunk meshes stay as they are.
- Trunk bands and raised flora are owned by a floor chunk but live in another layer, so they must be freed
  when the floor chunk unloads (`floor_container.gd` streaming) and when the prop dies.
- Keep everything deterministic per seed; nothing here touches placement except tagging south flora.

## Left to the builder

- Exact trunk-band height (≈ player sprite height), shadow oval proportions, and the generated
  gradient curve.
- Which existing nodes (lanterns, barrels, chests, drops) join the y-sorted layer, as long as nothing
  regresses against walls.
- Tests: at least one gdUnit4 check for sort order (actor south of trunk draws in front, north draws
  behind) and one that destroying a prop frees its shadow and trunk band.
