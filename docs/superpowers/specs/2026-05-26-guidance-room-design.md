# Guidance Room — Design Spec

**Date:** 2026-05-26
**Status:** Approved for planning

## Problem

New players don't know the goal of the game or the basic controls. The top-down procgen cave has no inherent direction, which compounds the problem — players spawn into open terrain and feel lost. They need a clear, low-friction onramp that teaches:

1. **The goal:** fight outward → defeat a boss → enter the portal that appears → descend to the next level.
2. **The controls:** Move (WASD), Attack (mouse), Interact (E).

The fix is a small, lit, hand-authored "safe-house" chamber the player always spawns inside, decorated with pictographic signs that convey the goal and controls. A single doorway leads out into the procgenerated cave.

Crucially, the implementation must be a **reusable authored-room capability**, not a one-off. Future hand-authored rooms (shops, treasure vaults, story rooms) must flow through the same system with no new infrastructure code per room.

## Goals

- New players who spawn into the world understand within ~5 seconds: "I'm safe here. I should go through that door and head outward to fight."
- Veterans walk through the room in 1–2 seconds without friction (no forced steps, no gates).
- The room appears every run at the player's spawn point.
- The system used to build it generalizes cleanly to future authored rooms.

## Non-goals

- Teaching the modifier/build system, terrain destruction, parry, dash, or other mechanics. These are learned organically in the cave.
- Adding navigation HUD (minimap, compass) or world beacons. The boss-ring world structure means "go outward in any direction" is sufficient guidance — the existing geometry does the navigation work.
- Localized text or written tutorial copy. Signs are pictographic only.
- Save-state tracking to skip the room for returning players. Room appears every run.

## Player-facing design

### Room concept

A small **circular chamber** (~500 px radius, with slight lobing for a natural-looking edge) centered on the world origin `(0, 0)`. The carve uses the existing `cavern_carve` system (`nominal_radius` + `lobing_amplitude`), so the room is a clean air pocket inside the surrounding procgen cave. The player spawns at the room's center. The room contains no enemies, no chests, no shops, no hazards — purely informational and safe.

Visual style: lit safe-house. Four wooden sign plaques placed at compass points inside the chamber, four lantern props arranged near the chamber edge, and a circular wooden-plank floor overlay visually distinct from the cave's biome floor. Aesthetically reads as "base camp."

### Walls and exit

The chamber is surrounded by normal procgen cave — fully destructible terrain like everywhere else in the game. There is no explicit doorway: the cave around the chamber has its own natural air pockets and connections, and the player can walk through any natural opening or carve through any wall. The boss ring (distance 10 sectors) bounds the world, so the player can't escape into the void.

This destructibility-everywhere rule is a hard project invariant: never propose non-destructible walls, even for tutorial spaces.

### Signs (four wooden plaques)

All four are wall-mounted Sprite2D plaques displaying PNG art (user-supplied). No text on the plaques.

- **Goal sign** — largest, placed *north* of spawn so the player faces it as the camera orients on spawn. Pictogram: player icon at center → radial outward arrows → boss skull → portal swirl. Reads as "from here, go outward in any direction → boss → portal."
- **Move sign** — *west* of spawn. WASD glyphs in physical layout.
- **Attack sign** — *east* of spawn. Mouse icon with left button highlighted + swing arc.
- **Interact sign** — *south* of spawn. `E` key glyph with a hand/pickup icon. Primes the player to press E on drops, chests, and the portal.

### Lighting and floor

- **Lanterns:** four prop sprites arranged near the chamber's edge (NE/NW/SE/SW), each with a child `PointLight2D` (warm amber, energy ~1.2, radius covering ~half the chamber). Their overlap fully lights the chamber. A small random flicker on each light's energy sells live flame.
- **Floor overlay:** a single Sprite2D child of the room scene, "wooden planks" texture sized to cover the chamber's footprint (~1024×1024 px), z-indexed above the biome floor (`z = -10`) and below terrain walls and props. The biome floor still tiles underneath but is hidden inside the chamber.
- **No simulated materials** spawn inside the room — no gas, lava, blood, fire. The room is a clean, controlled space.
- **No audio** in this implementation (deferred to a future pass).

## Technical design — Authored Room System

The guidance room is the first instance of a general **authored-room capability** built on top of the existing `RoomTemplate` + `ArenaComposition` infrastructure. The system has three new pieces of generality, all reusable by future authored rooms (shops, vaults, story rooms).

### Piece 1 — Fixed-location anchor map

`SectorGrid.resolve_sector()` currently picks rooms via the boss-ring special case or weighted random from the biome's `room_templates`. Add a third case **before** both: a `fixed_anchors` map of sector coord → `RoomTemplate`.

Data-driven definition on `BiomeDef` (or a new `WorldLayoutDef` resource if biome feels too narrow):

```
fixed_anchors: Dictionary[Vector2i, RoomTemplate]
# Example for the starter biome:
#   Vector2i(0, 0): guidance_room_template
```

In `resolve_sector(coord)`:

1. If `coord in biome.fixed_anchors`: return a slot using `fixed_anchors[coord]` (bypassing both boss-ring and random selection).
2. Else if boss-anchor: existing logic.
3. Else: existing weighted-random selection.

This single hook handles every future hand-placed room. Boss-ring logic is untouched.

### Piece 2 — Reusable composition features

Three new `ArenaFeature` subclasses live alongside the existing features in `src/core/features/`. None are guidance-specific.

- **`FeatureFloorOverlay`** — exported params: `texture: Texture2D`, `size: Vector2`, `offset: Vector2`. Spawns one Sprite2D at `anchor + offset`, z-indexed between biome floor and terrain visuals. Used by guidance (wooden planks); future shop could use a different texture (e.g., brick).
- **`FeatureLanternCluster`** — exported params: array of `LanternSpec` resources, each with `offset: Vector2`, `prop_scene: PackedScene`, `light_color: Color`, `light_energy: float`, `light_radius: float`, `flicker_amplitude: float`. Spawns one lantern (prop sprite + child `PointLight2D`) per spec. Reused by any lit authored space.
- **`FeaturePlaqueSet`** — exported params: array of `PlaqueSpec` resources, each with `offset: Vector2`, `texture: Texture2D`, `size: Vector2`. Spawns one wall-mounted Sprite2D per spec at `anchor + offset`. Guidance uses it for the four signs; a shop could reuse it for "wares for sale" placards.

All three are pure data-driven Resources configurable in the inspector. New authored rooms are built by composing features in editor — no per-room code.

### Piece 3 — Guidance room as data

- **`guidance_room_template.tres`** — `RoomTemplate` with `cavern_carve = true` and a stamp pattern for a rectangular chamber (~3–4 sectors wide) bordered by cave stone with a single south doorway. Points to `guidance_room_composition.tres`.
- **`guidance_room_composition.tres`** — `ArenaComposition` with three features in order:
  1. `FeatureFloorOverlay` — wooden-plank texture sized to the room footprint.
  2. `FeatureLanternCluster` — four `LanternSpec` entries at the corner offsets.
  3. `FeaturePlaqueSet` — four `PlaqueSpec` entries (goal, move, attack, interact) at their fixed offsets.
- **Biome registration** — the starter biome's `fixed_anchors` includes `Vector2i(0,0): guidance_room_template`.

### Player spawn integration

`player_controller.gd:61` already calls `TerrainSurface.find_spawn_position(Vector2i.ZERO, ...)`, which searches outward from origin for the first air pocket. With the guidance room carved at `(0,0)`, the search finds a pocket inside the room immediately. **No change to player spawn logic.**

### Boss/portal integration

Unchanged. Bosses spawn on the ring at distance 10. Portals appear at boss arenas when a boss dies (`composition_dispatcher.gd:111`). The guidance room contains no portal.

## Future room examples (sanity check that the system generalizes)

- **Shop room** — new `shop_template.tres` with a different wall stamp, new `shop_composition.tres` reusing `FeatureFloorOverlay` (e.g., brick texture) + `FeatureLanternCluster` + a new `FeatureShopkeeper` (out of scope here). Either registered as a fixed anchor for a guaranteed shop sector, or added to the biome's `room_templates` for weighted random placement.
- **Treasure vault** — new template + composition reusing the overlay/lantern features + a new `FeatureChestCluster` (or the existing `feature_chest_spawn` adapted).
- **Story/lore room** — new template + composition reusing all three generic features with different art assets. No code changes required.

## What stays untouched

- Chunk generation, GPU compute pipeline.
- Terrain rendering, materials, destruction.
- Existing `FloorContainer` / `FloorChunk` (overlay sits on top — no engine surgery).
- GPU chunk-light system (standard `PointLight2D` is enough for lanterns).
- Player spawn, controller, input.
- Boss spawning, portal spawning, level transition.

## Open implementation questions (deferred to planning)

- Stamp-pattern authoring: how the rectangular wall layout with a doorway is expressed in the `RoomTemplate` stamp format (existing templates may already cover this — to be verified during planning).
- Exact pixel size of the room and offsets of the four lanterns / four plaques inside it.
- Whether `fixed_anchors` belongs on `BiomeDef` or on a separate `WorldLayoutDef` resource.
- Lantern art and ambient audio source (out of MVP scope; deferred).
