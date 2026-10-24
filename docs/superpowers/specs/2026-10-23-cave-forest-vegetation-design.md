# Cave Forest Vegetation — Design

**Date:** 2026-10-23
**Status:** Awaiting approval

## Intent

Cave vegetation today is a set of random sprites scattered on the floor. Each 16px floor cell has a 5% chance of
getting one of three tiny glowing sprites (`floor_chunk.gd`), so there are no main features, no groups, no contrast
between dense and empty areas, and no variation in size.

Replace it with a **forest growing inside the cave**, dressed according to the composition philosophy in
`docs/【像素画】怎样让游戏场景变好看 地图编辑与优化思路详解 - Original.mp4` (transcript:
`docs/bilibili_BV1rm421779Z.md`). The approved target look is mockup **B**
(`.superpowers/brainstorm/42182-1792789549/content/forest-composition.html`).

## The look

- **Trees stay dark. The light comes from glowing plants, mushrooms and crystals.** *(User.)* The cave keeps its
  existing darkness setup (DirectionalLight2D SUB, glow). Trees are toned down (darker and less saturated) so they
  read as silhouettes. Glowing flora clusters at the roots, so the light comes in pools instead of evenly.
- **Video rules, applied procedurally:**
  1. **Big pieces first, in groups.** A forest area has a *main group*: a triangle of three trees made up of one
     bright tree, one odd-colour tree and one dark tree, with two close together and one further off. It also has
     smaller *secondary groups* that use a different shape or colour family (for example a pine pair).
  2. **Colour variety within harmony.** Mix the five colour sets of NaturalDecorsTreesAndRocksv1 (green, deep
     green, autumn, teal, olive). Within a group, vary hue and brightness, but avoid over-saturated outliers and
     don't repeat the same shape at the same size side by side.
  3. **Wall-edge breakers.** Rocks from the new rock pack sit along the line where floor meets wall, to break up
     the blocky pixel-grid edge (the video's "stone pillars").
  4. **Dense vs. empty.** Areas full of trees contrast with open clearings. Some trees may extend past the edge of
     the screen.
  5. **Small fillers last.** Glowing mushrooms, ferns, grass and crystals go into the remaining gaps, mostly around
     tree roots, with attention to colour, density and rhythm.
- **Patches, not everywhere.** *(User.)* Forest grows in patches with bare cave rock in between. The bare rock only
  gets a light sprinkle of glowing flora so it isn't pitch black.
- **Native sprite scale.** Trees are 96×128 and 160×160, roughly 10 times the player's height, as in mockup B,
  which the user picked. *(My call, based on that choice.)*
- **Canopies never fade.** *(User.)* Actors behind a canopy are simply hidden behind it.
- **Trees draw in front of walls they stand in front of.** *(User.)* A tree is always on open floor, which puts it
  in front of (south of) the wall behind it, so its canopy overhangs the rock, as in mockup B, instead of being
  cut off by the wall layer.

### Assets

- Trees: `textures/Assets/NaturalDecorsTreesAndRocksv1/Trees/Colour1..5`, which come in two sizes, 160x160 and
  96x128, covering round, leafy, dead, pine and tall-pine shapes. `PixelTreeSet` and `Treeeeeeeeeeeeeeeeeeeeeeee` are
  also available; the builder decides whether they fit the palette.
- Rocks: `textures/Assets/NaturalDecorsTreesAndRocksv1/Rocks/Colour1..5` (32, 64 and 96px).
- Glowing flora: the existing `textures/Environments/Decors/*` plus `textures/Assets/db32/blocks/plants/`
  (mushroom_red, mushroom_brown, fern, amethyst_crystal, grass_tall, …).
- Which tree in each colour set counts as "bright", "odd colour" or "dark" is left to the builder's eye.

## Gameplay

### Trees are breakable props, not terrain pixels

*(User.)* Trees work like the oil barrel (`src/props/oil_barrel.gd`), not like simulated terrain:

- **Collision only at the trunk.** A small solid shape at the base of the trunk blocks the player, enemies and
  projectiles. The canopy blocks nothing. *(User approved.)*
- **Hits:** every weapon hit (melee and projectile), **from the player or from enemies** *(user)*, damages the tree and plays the **wood dig feedback**: the same
  `TerrainImpact.play_impact(..., MaterialRegistry.MAT_WOOD, ...)` particles you get from digging wood, plus a
  burst of simulated dust thrown into the terrain sim. The tree also gets a hit flash. It should feel juicy.
- **Destruction:** when its HP runs out, the whole tree sprite disappears in a bigger burst of the same particles
  and dust. *(User.)* The sprite stays intact while it is being damaged.
- **HP scales with tree size, and the weapon's dig stat adds to the damage**, so dig-focused weapons fell trees
  faster. *(User approved.)* The numbers are the builder's call. A big tree should take a handful of ordinary hits,
  not dozens.
- **Never flammable.** *(User.)* Trees never ignite and have no interaction with the fire simulation.
  Fire, lava and explosions pass them by. (An explosion that counts as a weapon hit can still damage them.)

### Big rocks

*(User approved.)* The 64px and 96px rocks are solid and breakable in the same way, but take more hits and burst
into **stone** impact particles (`MAT_STONE`).

### Walk-through decor

Mushrooms, ferns, grass, crystals, small (32px) rocks and stumps are visual only. They have no collision and can't
be hit. *(User approved.)*

### Placement must not hurt gameplay

*(User: forest patches "should not affect the gameplay significantly", e.g. trees blocking the player's way.)*
The rules below are my proposal and were approved:

- **Never inside walls.** Solid props are placed only where their whole trunk footprint, plus a margin, is open floor
  (`MAT_AIR`) in the generated terrain. *(User.)*
- **Never seal a passage.** Trees and big rocks prefer to sit near walls and need open floor all around their trunk,
  so they never close off a corridor or a narrow gap.
- **Room centres stay open.** These are the clearings where fights happen.
- **Keep-out zones:** no solid props in shop, boss or elite arenas, in the guidance room at the start (fixed anchor
  `(0,0)`), or next to chests and spawn points. Walk-through glowing flora is still fine there.
- Floor dug out later doesn't grow new vegetation. Placement happens once, at chunk generation.

## Constraints and things the builder must handle

- **Scope:** caves biome only. Keep the system data-driven per biome, like `BiomeDef.decor_defs` today, so other
  biomes can opt in later.
- **Replace the old scatter.** The uniform 5% random scatter goes away. Keep the baked per-chunk decor lighting
  (`_bake_decor_lights`) and feed it from the new glowing flora.
- **Deterministic per world seed,** the same way decor placement is today (`_hash_seed(world_seed, coord)`).
- **Chunk streaming:** floor chunks are created and freed as the camera moves (`floor_container.gd`). Trees and
  groups can be bigger than a chunk border allows (160px sprites in 256px chunks). Avoid seams and double-spawns
  across chunk borders.
- **Destroyed stays destroyed:** a tree or rock that was cut down must not come back when its chunk unloads and
  reloads on the same floor. *(My call.)*
- **Enemy navigation:** enemies don't collide physically (`collision_mask = 0`). They steer using the 8px
  `PassabilityGrid` / `NavField`, which is built from terrain materials. Solid props must be marked as blocked in the
  navigation data while they stand, and cleared when they're destroyed. Otherwise enemies walk through trunks.
- **Physics layers:** the player collides with layers 1 and 3 (mask 5). Melee and projectile hits find targets on
  layer 8 (`ATTACKABLE_HIT_LAYER = 1 << 7`). Projectiles should stop when they hit a trunk.
- **Draw order:** an actor standing north of a trunk is drawn behind the canopy, and an actor standing south of it
  is drawn in front. The floor container currently sits at `z_index = -10`, under everything. Trees need to be
  y-sorted with actors at the base of the trunk, while ground decor stays under actors. On top of that, canopies
  must draw **over the wall layer**. The wall quad sits at `z_index = 1`, above actors at z 0
  (`src/core/chunk_manager.gd:101`), and Godot only y-sorts within one z level, so this needs a layering rework.
  Don't change how walls cover actors today.
- **Enemy fire clears forests:** because enemy attacks damage props, ranged and sniper enemies will wear trees down
  during fights. Keep particle, dust and navigation-update costs bounded when many shots land in a short time.
  Homing and auto-aim should not target props. *(My call.)*
- **Performance:** lights stay baked per chunk with no new per-object `PointLight2D`. Keep the node count per chunk
  reasonable on an integrated GPU.
- **Tests (gdUnit4):** `tests/unit/test_caves_biome_decor.gd`, `test_floor_chunk.gd`,
  `test_floor_chunk_decor_lights.gd` and `test_biome_def.gd` cover the current system. Update or replace them. At
  minimum, cover these: solid props never overlap non-air terrain, nothing is placed in keep-out zones, placement is
  deterministic for a given seed, and a destroyed prop doesn't reappear after a chunk reload.

## Non-goals

- Fading or hiding canopies.
- Fire spread or burning trees.
- Trees as simulated terrain pixels.
- Vegetation regrowing on floor that has been dug out.
- New hand-drawn art. Use the imported packs, plus colour or tint tweaks if needed.
- Other biomes.

## Anti-goals (failures even if it technically works)

- Still reads as an even random scatter, just with bigger sprites.
- Trees blocking corridors, choking fights, or pushing players into fights they can't avoid.
- Bright, saturated trees that make the cave look like a sunny surface forest.
- Identical trees repeated side by side.
- A visible grid or seams at chunk borders.

## Left to the builder

- The data model: extending `DecorDef`, or new resources for groups, solid props and filler sets.
- The placement algorithm that produces patches, groups, breakers, clearings and fillers within the rules above.
- Patch frequency and density, HP and damage numbers, the amount of dust and the particle scale, and the exact
  trunk collision sizes for each sprite.
- Which tree sprite plays which role (bright, odd colour or dark), and whether to use the PixelTreeSet and birch
  sprites.
