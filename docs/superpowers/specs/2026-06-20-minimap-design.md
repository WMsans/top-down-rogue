# Minimap — Design Spec

Date: 2026-06-20
Status: Approved (pending implementation plan)

## Goal

Add an always-on minimap to the top-right of the HUD that shows a large area of
the world (≥ 6×6 chunks), with persistent fog of war, real terrain, and markers
for shops, boss arenas, and elite arenas. The existing weapon button moves below
the minimap.

## Requirements (settled)

1. **Placement** — Minimap in the top-right corner; weapon button moves directly
   below it, in its own framed cluster.
2. **Large view** — At least 6×6 chunks visible; default view is 7 chunks across.
3. **POIs** — Highlight shops, boss arenas, and elite arenas.
   - **Bosses**: always visible. When a boss is outside the minimap window it is
     shown clamped to the window edge as an arrow pointing toward it.
   - **Shops / elite arenas**: revealed on discovery (gated by fog) — hidden until
     the player has explored near them.
4. **Fog of war** — Persistent: once a chunk is generated it stays revealed for the
   rest of the floor, even after it unloads. Fog covers only never-visited areas.
   The revealed boundary is **naturally circular** (soft overlapping circles that
   merge into organic blobs), not square chunk borders.
5. **Real terrain** — The revealed area shows actual wall/floor terrain, sourced
   from CPU collider/passability data (no GPU readback, no new compute shader).
6. **Performance** — GDScript implementation; heavy work is incremental and
   event-driven, per-frame cost is minimal.

## Key facts about the codebase this builds on

- **World is deterministic** from `LevelManager.world_seed` + `SectorGrid`. Any
  sector's contents (boss / shop / elite arena / empty) can be queried via
  `SectorGrid.resolve_sector(coord)` **without** generating the chunk.
- **Sectors** = 384px; **chunks** = 256px. Bedrock wall bounds the floor at
  `SectorGrid.WALL_INNER_SECTORS` (= 8 sectors ≈ ±3072px). Boss arenas sit on a
  ring at sector Chebyshev distance 8 — 12 anchors (`SectorGrid.is_boss_anchor`).
- **Per-chunk passability is already on the CPU.** The GPU collider dispatch reads
  back a passability tile per chunk: `ComputeDevice.read_collider_buffer_coalesced()`
  → `TerrainCollisionHelper._consume_readback()` → `nav_field.grid.set_tile(coord, tile)`.
  `PassabilityGrid` (`src/core/nav/passability_grid.gd`) stores a **32×32 byte tile
  per chunk** (cell = 8px, 1 = solid/wall, 0 = floor). It is **dropped on unload**,
  so the minimap snapshots tiles into its own persistent images on reveal.
- **Fog signal source**: `WorldManager` emits `chunks_generated(coords)` and
  `chunk_unloaded(coord)`. `WorldManager.chunks` is the live loaded-chunk dict;
  `WorldManager.tracking_position` is the player position.
- **HUD** is a full-resolution `CanvasLayer` (`scenes/ui/hud.tscn`, `src/ui/hud.gd`),
  separate from the low-res 320×180 game SubViewport. The weapon cluster lives in
  a right-anchored `TopRight` frame using the `inset_frame.tres` style.
- **Shop marker** type is `4` (see `spawn_dispatcher._spawn_entity`); markers come
  from `BiomeRegistry.template_pack.collect_markers(size, idx)`.
- **Elite arena** = a sector whose resolved slot has a `composition` with
  `arena_kind == &"elite"` (see `tools/generate_arena_compositions.gd`).

## Rendering approach (chosen: A)

Two persistent CPU `Image`s for the whole bounded floor plus a shader window.
Heavy work (building the images) is incremental and event-driven; per-frame cost
is one shader sampling two small textures plus a few `_draw()` calls. Rejected
alternatives: per-frame `_draw()` over all visible cells (too many draw ops), and
per-chunk minimap sprites (node churn, awkward fog seams).

## Components

### `MinimapModel` (`src/ui/minimap/minimap_model.gd`, `RefCounted`)

World-data layer; no rendering; headless-testable.

- **Cell size**: 16px (a 2×2 downsample of the native 8px passability cells).
- **World images** sized to the bounded floor derived from
  `SectorGrid.WALL_INNER_SECTORS` (+1 chunk margin) → fixed `WORLD_CELLS` (~400).
  Image origin maps to world `(-half, -half)`.
  - `terrain_img` (+ `terrain_tex`): wall vs floor.
  - `reveal_img` (+ `reveal_tex`): fog mask, 0 = unexplored … 255 = revealed.
- **POI list** computed once per floor.
- **API**:
  - `reset()` — clear both images, recompute POIs for the current seed/biome.
  - `reveal_chunk(coord)` — stamp a soft **circle** into `reveal_img` centered on
    the chunk, radius ≈ 1.2 chunks so neighbors merge into organic blobs.
  - `stamp_terrain(coord, tile)` — downsample the 32×32 passability tile 2×2 into
    16px cells and blit into `terrain_img`.
  - `world_to_uv(world_pos) -> Vector2`.
  - `is_revealed_world(world_pos) -> bool` — samples `reveal_img` above a threshold.
  - `get_pois() -> Array` — each `{type, world_pos, always_visible}`.
  - Texture accessors for the widget shader.

### `Minimap` (`scenes/ui/minimap.tscn` + `src/ui/minimap/minimap.gd`, `Control`)

Thin view over the model. Fixed **180×180**, `clip_contents`, mouse-transparent
(`MOUSE_FILTER_IGNORE`).

- A `ColorRect`/`TextureRect` with `shaders/ui/minimap.gdshader` that samples
  `terrain_tex` + `reveal_tex`, applies the player-centered pan/zoom, `smoothstep`s
  the reveal mask for soft fog edges, and tints wall/floor/fog.
- An overlay child draws (in `_draw()`): POI icons, the player arrow (centered,
  rotated to facing), and boss edge-arrows clamped to the widget border.
- `_process(delta)`:
  - Resolve `world_manager` / `nav_field` lazily; no-op until present.
  - For each loaded chunk in `world_manager.chunks` (~9–25), read its tile from
    `nav_field.grid`; if changed since last stamped (per-chunk version guard),
    call `model.stamp_terrain`.
  - Update shader uniforms: `player_world_pos`, `view_extent_world`, `world_origin`,
    `world_size`.
  - Trigger overlay `queue_redraw()`.
- Connects once to `world_manager.chunks_generated` → `model.reveal_chunk` for each
  new coord. Connects to `LevelManager.floor_changed` → `model.reset()`.

### HUD wiring (`hud.gd` / `hud.tscn`)

- `TopRight` becomes a right-aligned `VBox` with two framed clusters:
  ```
  TopRight (MarginContainer, top-right)
  └─ VBox (separation 8)
     ├─ MinimapFrame (PanelContainer, inset_frame) → Minimap (180×180)
     └─ WeaponFrame  (PanelContainer, inset_frame) → existing weapon cluster (unchanged internals)
  ```
- `WeaponTooltip` is re-anchored so it lines up with the weapon button's new,
  lower position.
- `hud.gd` passes the `WorldManager` (via group `world_manager`) to the minimap.

## Data flow

```
chunks_generated(coords) ─► model.reveal_chunk(c)        // soft circle into reveal_img

Minimap._process(delta):
  for c in world_manager.chunks:                          // ~9–25 loaded chunks
     tile = nav_field.grid tile for c                      // 32×32 bytes, CPU-resident
     if tile present and changed-since-stamped:
        model.stamp_terrain(c, tile)                       // 2×2 downsample → terrain_img
  set shader uniforms (player pos, view extent)
  overlay.queue_redraw()
```

- Reveal (fog) is immediate on chunk generation; terrain is stamped when the
  passability tile lands (a frame or two later, or after digging). A
  revealed-but-unstamped area shows the floor tone until terrain fills in.
- `ImageTexture`s are re-uploaded only on frames where an image actually changed.

## POIs (boss / shop / elite)

Computed once per floor in `model.reset()` by scanning in-bounds sectors via
`SectorGrid` (~256 cheap deterministic lookups):

- **Boss** — walk the boss ring (`is_boss_anchor`, dist 8, 12 anchors).
  `always_visible = true`.
- **Elite arena** — `resolve_sector(s).composition` with `arena_kind == &"elite"`.
- **Shop** — slot's template has a shop marker (`collect_markers` → type `4`).

Each POI: `{type, world_pos, always_visible}`. At draw time:

- Boss icons always drawn; if outside the window, clamped to the window edge as an
  arrow pointing toward the boss.
- Shop/elite icons drawn only if `model.is_revealed_world(pos)` (discovered).

## Coordinate & scale math

- Cell = 16px. World image covers chunk range from `WALL_INNER_SECTORS` (+1 margin)
  → fixed `WORLD_CELLS`. Image origin = world `(-half, -half)`.
- View window: `view_chunks` (default 7 → 1792px) across the 180px widget.
  Configurable; ≥ 6 satisfies the minimum.
- Shader uniforms: `player_world_pos`, `view_extent_world`, `world_origin`,
  `world_size`. Per widget pixel: compute world position → UV into the two images →
  sample → `smoothstep` reveal → output wall/floor/fog color.
- Overlay POI world→widget: `(pos - player) / view_extent * half_widget + center`.
  Player arrow at center (rotated to facing). Boss edge-arrow = clamp that vector to
  the widget rect, draw a triangle on the border.

## Edge cases & error handling

- `world_manager` / `nav_field` / grid null on early frames → widget no-ops.
- Revealed chunk whose passability tile hasn't arrived yet → floor tone until the
  tile lands (handled by the per-frame stamp pass).
- Terrain destruction while a chunk is loaded → tile changes → version guard
  re-stamps that chunk.
- Unloaded chunk → terrain & reveal persist; updates simply stop.
- Floor advance → `model.reset()` clears images and recomputes POIs for the new seed.
- Empty biome data (no boss/room comps) → empty POI lists, no crash.
- Positions outside the bounded floor are clamped; nothing generates beyond the
  bedrock wall.

## Testing

- **gdUnit4 unit tests** on `MinimapModel` (headless):
  - POI scan for a fixed seed yields 12 bosses and finds the expected shop/elite
    sectors.
  - `reveal_chunk` marks the chunk center revealed and a far cell still fogged;
    adjacent reveals overlap (circular blob).
  - `is_revealed_world` returns false for an undiscovered shop, true after revealing
    its sector.
  - World↔image and world↔widget coordinate round-trips.
- **Manual smoke test**: run the game; confirm circular fog carving, terrain matches
  walls, shop/elite icons pop in on discovery, a boss shows as an edge arrow then a
  fixed icon when on-screen, and the weapon button sits below and still opens the
  popup.

## Out of scope (YAGNI)

- Full-screen / expandable map view.
- Minimap zoom controls or click-to-ping interaction.
- Real-time terrain refresh for *unloaded* chunks (frozen at last-seen state).
- Reading actual wall geometry from GPU chunk textures.
