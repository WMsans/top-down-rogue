# Terrain Physics & Player Controller Design

## Overview

Add terrain collision and a top-down player controller to the GPU-driven pixel simulation. The core challenge is that all terrain data lives on the GPU (compute shader textures), but collision detection needs CPU access. We solve this with an async CPU shadow grid that mirrors a region of GPU terrain around the player.

## Architecture

```
GPU Compute Shaders (chunk textures, 256x256 RGBA8)
        │
        ▼ async readback (event-driven, max every 3 frames)
CPU Shadow Grid (128x128 bytes, centered on player)
        │
        ▼ direct pixel queries (every physics frame)
Collision Resolution (axis-separated, X then Y)
        │
        ▼ corrected position
Player Controller (Node2D, acceleration/friction model)
```

The player is a plain Node2D — no CharacterBody2D or Godot physics engine involvement. All collision is resolved by querying the shadow grid directly.

## CPU Shadow Grid

**Class:** `ShadowGrid` (Node, in `scripts/shadow_grid.gd`) — needs to be a Node to receive signals from WorldManager for dirty notifications

**Storage:** `PackedByteArray` of 128x128 bytes. Each byte stores the material type for one pixel (0=air, 1=wood, 2=stone). Configurable size via export variable, defaulting to 128.

**Coordinate mapping:** The grid is anchored at a world position (top-left corner). Methods convert between world coordinates and grid indices. The grid is re-centered when the player moves more than 32 pixels from the grid center.

**Chunk spanning:** The 128x128 region may overlap multiple 256x256 chunks. On sync, the grid reads from all overlapping chunks.

**Query API:**
- `is_solid(world_x: int, world_y: int) -> bool` — returns true if the material at that position is solid (not air)
- `get_material(world_x: int, world_y: int) -> int` — returns the material type byte

**Async two-phase sync:**
- Frame N: request readback from GPU via WorldManager
- Frame N+1: copy returned data into the grid array

**Sync triggers:**
- Player moves more than 32px from the last sync center
- Simulation modifies pixels within the shadow grid bounds (detected at chunk granularity)
- Frequency cap: no more than one sync every 3 frames, even if triggers fire continuously

**Unloaded chunks:** If the grid region overlaps a chunk that isn't loaded, those pixels are treated as solid (conservative — prevents walking into unknown terrain).

## Collision Resolution

Runs every physics frame, using the shadow grid (no GPU access needed).

**Axis-separated resolution:**
1. Apply X movement. Check the player's 8x12 footprint against the shadow grid. If any pixel in the leading X edge is solid, clamp position to the solid pixel boundary.
2. Apply Y movement. Same check for the leading Y edge.

This prevents corner-catching and diagonal tunneling.

**Grounding/wall detection:** After resolution, sample pixels adjacent to the player's edges for "on ground" and "touching wall" state, available for future gameplay mechanics.

**No sub-stepping needed:** At 120 px/s max speed and 60fps, the player moves ~2 pixels per frame. Tunneling through walls is not a concern at this scale. If max speed increases significantly later, add sub-stepping then.

## Player Controller

**Scene:** `scenes/player.tscn`

```
Player (Node2D) — player_controller.gd
├── ColorRect (8x12 pixels, visual placeholder)
└── Camera2D (zoom 8x, smoothing enabled)
```

**Input:** WASD via `Input.is_key_pressed()` (matching existing project convention), producing a normalized direction vector.

**Movement model:**
- Acceleration: 800 px/s²
- Friction: 600 px/s² (applied opposing velocity when no input)
- Max speed: 120 px/s
- Each physics frame: apply acceleration in input direction, apply friction opposing velocity, clamp to max speed, pass desired delta to collision resolution

**Spawn:** On ready, asks WorldManager to scan outward from the center chunk origin for a contiguous air pocket that fits 8x12 pixels. Sets initial position there.

**Chunk tracking:** Each frame, reports player position to WorldManager for chunk loading/unloading (replacing the current camera-based tracking).

## WorldManager Integration

Changes to `scripts/world_manager.gd`:

**Readback API:** New method `request_region_readback(world_rect: Rect2i)` that initiates an async GPU texture read for the specified region, spanning multiple chunks if needed. Returns data via signal or callback on the next frame.

**Spawn finder:** New method `find_spawn_position(search_origin: Vector2i, body_size: Vector2i) -> Vector2i` that reads terrain data at the origin chunk and spirals outward looking for a contiguous air pocket fitting the body size.

**Chunk tracking source:** Changes from tracking Camera2D position to tracking the player's position for chunk loading/unloading. The standalone Camera2D and camera_controller.gd are removed; Camera2D becomes a child of the Player node.

**Terrain change notification:** After simulation each frame, WorldManager checks if any modified pixels fall within the shadow grid's bounds. Dirty detection is coarse (chunk granularity). If dirty, it signals the shadow grid to request a re-sync.

## File Organization

**New files:**
- `scripts/shadow_grid.gd` — ShadowGrid class (readback, storage, queries)
- `scripts/player_controller.gd` — Player movement and collision resolution
- `scenes/player.tscn` — Player scene (Node2D + ColorRect + Camera2D)

**Modified files:**
- `scripts/world_manager.gd` — Add readback API, spawn finder, player-based chunk tracking
- `scenes/main.tscn` — Add Player node, remove standalone Camera2D

**Removed files:**
- `scripts/camera_controller.gd` — Replaced by Camera2D as child of Player

**Unchanged:**
- All shaders (generation.glsl, simulation.glsl, render_chunk.gdshader)
- `scripts/input_handler.gd` — stays, but coordinate conversion may need updating since camera moves to player
- `scripts/chunk.gd`, `scripts/generation_context.gd` — no changes

## Edge Cases

- **Shadow grid spans unloaded chunks:** Treat unloaded pixels as solid. WorldManager already loads chunks around the player, so this is transient during initial load only.
- **No valid spawn found:** Spiral search expands to neighboring chunks. After 4 chunks with no valid pocket, log a warning and spawn at chunk center (indicates a generation bug).
- **Stale shadow grid:** If the player moves faster than readbacks arrive, collision uses the stale grid. At worst, the player clips into a newly-solid pixel for one frame and gets pushed out on the next sync.
- **Chunk boundaries during collision:** Abstracted away by the shadow grid. The grid covers a continuous 128x128 world region regardless of underlying chunk boundaries.
