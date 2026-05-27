# Floor Background — Design

## Problem

The game world currently has no floor. Where terrain chunks have transparent
pixels (and beyond the active chunk radius), the player sees Godot's default
viewport background colour. We want a tiled floor visible beneath terrain, with
sparse decoration sprites scattered on top, varying by biome.

## Goals

- A visible floor everywhere a chunk is loaded.
- Per-biome floor and decoration art driven from each `BiomeDef` resource.
- Deterministic placement: same world seed + chunk coord → same decoration layout.
- Per-chunk lifecycle that mirrors the existing terrain chunk lifecycle (load,
  unload, floor change).
- Zero impact on physics, collision, lighting, or the compute-shader terrain
  pipeline.

## Non-goals

- Biome-blended floors at chunk boundaries. The game has one biome per floor; no
  blending exists or is planned here.
- Walkable-area-aware decoration placement. Decorations sit beneath terrain;
  ones hidden behind walls are acceptable.
- Authoring tools for slicing `Floor.png` / `Ground1.png`. Textures referenced
  by biomes are either standalone 16×16 PNGs or `AtlasTexture` resources
  pointing into the source sheets — authored in the Godot editor.
- Animated floor tiles (water, lava frames). The chosen texture-per-biome
  approach renders a single static 16×16 image; animated floors are out of scope
  and can be revisited later.

## Architecture

A new `FloorChunk` Node2D mirrors each terrain chunk:

```
WorldManager (Node2D)
├── ChunkContainer        (existing, terrain chunks, higher z)
├── FloorContainer        (NEW, floor chunks, lower z)
│   └── FloorChunk[coord] (NEW, one per loaded chunk)
│       ├── FloorSprite   (Sprite2D, 256×256, tiled biome.floor_texture)
│       └── DecorSprite × N (Sprite2D children, 16×16 each)
├── CollisionContainer
└── LightsContainer
```

`FloorContainer` is created in `WorldManager._ready()` as a sibling of
`ChunkContainer`, with a z-index lower than the terrain chunks so terrain always
draws on top.

`FloorChunk` is purely visual — no `StaticBody2D`, no collision shapes, no
`PointLight2D` interaction.

## Components

### `BiomeDef` additions (`src/core/biome_def.gd`)

```gdscript
@export var floor_texture: Texture2D = null
@export var decor_textures: Array[Texture2D] = []
@export var decor_chance: float = 0.02
```

- `floor_texture`: 16×16 image used as the tiled floor for every chunk on this
  biome's floor.
- `decor_textures`: 16×16 images; one is picked per decoration placement.
  Empty array means "no decorations".
- `decor_chance`: probability per 16×16 cell that a decoration spawns there.
  Default `0.02` → ~5 decorations per 16×16 chunk on average.

### `src/terrain/floor_chunk.gd` (new)

```gdscript
class_name FloorChunk
extends Node2D

func populate(coord: Vector2i, biome: BiomeDef, world_seed: int) -> void
```

- On `populate`:
  1. If `biome.floor_texture == null`, log a one-time warning and return.
  2. Create a `Sprite2D` `FloorSprite` covering 256×256 with
     `biome.floor_texture` set to tile (via `region_enabled` + `region_rect` +
     `texture.repeat`). One draw call covers the whole chunk floor.
  3. If `biome.decor_textures` is non-empty and `biome.decor_chance > 0`:
     - Initialize a deterministic `RandomNumberGenerator` seeded from
       `(world_seed, coord.x, coord.y)`.
     - For each cell in the 16×16 grid: roll vs `decor_chance`; on hit, add a
       `Sprite2D` child at the cell's local position with a texture picked
       uniformly from `biome.decor_textures`.

### `src/terrain/floor_container.gd` (new)

```gdscript
class_name FloorContainer
extends Node2D

var _chunks: Dictionary = {}  # Vector2i → FloorChunk
```

- Subscribes to `WorldManager.chunks_generated` for spawn events.
- Subscribes to whichever existing signal/hook unloads terrain chunks (verified
  during implementation; if no clean signal exists, reconcile `_chunks` against
  `WorldManager.chunks` on each chunk event).
- On floor change (`LevelManager.set_floor`), the existing terrain teardown
  triggers the unload path for every chunk, which naturally clears
  `FloorContainer` too. No special hook required.

### Biome resource updates

Each of `assets/biomes/{caves,frozen,magma,mines,vault}.tres` gets its three
new fields populated. The textures themselves are either standalone 16×16 PNGs
or `AtlasTexture` resources pointing into `textures/Assets/DawnLike/Objects/Floor.png`
and `Ground1.png`. Authoring the textures is a manual step done in the Godot
editor as part of implementation.

## Data flow

1. **Floor start.** `LevelManager.set_floor(n)` sets `current_biome` as today.
2. **`WorldManager._ready()`** creates `ChunkContainer` then `FloorContainer`
   (sibling, lower z-index).
3. **Chunk loaded.** `ChunkManager` finishes generating chunk at coord C;
   `WorldManager` emits `chunks_generated([C, ...])`. `FloorContainer` creates a
   `FloorChunk`, positions it at `C * 256`, calls
   `populate(C, LevelManager.current_biome, LevelManager.world_seed)`, registers
   it in `_chunks`.
4. **Chunk unloaded.** `FloorContainer` frees the matching `FloorChunk` and
   removes it from `_chunks`.
5. **Floor change (descend).** Existing terrain teardown unloads every chunk;
   `FloorContainer` frees every `FloorChunk` via the per-chunk unload path. New
   chunks spawn with the new biome's textures.
6. **Determinism.** Decoration RNG seeded from
   `(world_seed, coord.x, coord.y)` — same seed + coord always yields the same
   layout, even after unload/reload.

## Error handling

- **Missing `floor_texture`.** `populate()` early-returns with a one-time
  warning naming the biome. Visual result: Godot default background, same as
  today.
- **Empty `decor_textures` with `decor_chance > 0`.** Decoration pass skipped
  silently. Valid configuration.
- **Spurious unload of unknown coord.** `FloorContainer` checks dict membership
  and `is_instance_valid` before freeing; no-op otherwise.
- **`chunks_generated` fires before `FloorContainer` exists.**
  `FloorContainer` is added in `WorldManager._ready()` before `ChunkManager` is
  constructed, mirroring `ChunkContainer`.
- **Texture filtering.** Inherits the SubViewport's
  `canvas_item_default_texture_filter = 0` (nearest). No per-sprite override
  needed.
- **Decoration overflow.** All decor textures are 16×16 placed on the 16-aligned
  grid; they fit inside the chunk by construction.

## Testing

- **Unit (`tests/unit/test_floor_chunk.gd`):**
  - Deterministic placement: `populate(coord, biome, seed)` called twice
    produces identical child positions and textures.
  - Different coords produce different placements.
  - `decor_chance = 0.0` → zero decoration sprites.
  - `decor_chance = 1.0` → exactly 256 decoration sprites in a chunk.
- **Manual:**
  - Walk around in each of the five biomes; floor shows under terrain.
  - Descend a floor; floor textures swap cleanly with no leftover sprites.
  - No visible artefacts at floor/wall edges (decorations hidden by walls are
    expected and fine).

## Files touched

- `src/core/biome_def.gd` (extend)
- `src/terrain/floor_chunk.gd` (new)
- `src/terrain/floor_container.gd` (new)
- `src/core/world_manager.gd` (instantiate `FloorContainer`)
- `scenes/game.tscn` (no edit if `FloorContainer` is created in code; may need
  z-index adjustment on `ChunkContainer` — TBD during implementation)
- `assets/biomes/*.tres` (populate new fields)
- `tests/unit/test_floor_chunk.gd` (new)
