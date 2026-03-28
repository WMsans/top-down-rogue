# Noita-Like 2D Pixel Terrain System — Design Spec

## Overview

A cellular automata-based pixel simulation system for Godot 4.6, where each pixel holds material properties and reacts with neighbors via compute shaders. The world is infinitely expandable through a chunk system. Initial implementation: a world of wood pixels with the ability to place fire.

## Data Model

Each pixel is stored as a single RGBA8 texel in a GPU texture:

| Channel | Purpose         | Values                                          |
|---------|-----------------|-------------------------------------------------|
| R       | Material type   | 0=air, 1=wood, 2=fire                           |
| G       | Health/fuel     | 0-255 (wood starts at 255, burns down)          |
| B       | Temperature     | 0-255 (fire emits heat, heat spreads, hot wood ignites) |
| A       | Reserved        | 0 (future use)                                  |

**Chunk dimensions:** 256x256 pixels per chunk.

World pixel `(x, y)` maps to:
- Chunk coordinate: `(floor(x / 256), floor(y / 256))`
- Local pixel: `(x % 256, y % 256)`

### Simulation Constants (tunable)

- Wood ignition threshold: temperature > 180
- Fire temperature output: 255
- Heat dissipation per tick: -2 per pixel
- Heat spread to neighbors: +10 per adjacent fire pixel
- Fire fuel consumption: -1 health per tick
- Fire with 0 health becomes air

## Architecture

### Scene Tree

```
Main (Node2D)
├── WorldManager (Node2D) — scripts/world_manager.gd
│   └── ChunkContainer (Node2D) — holds chunk MeshInstance2D nodes
├── Camera2D — scripts/camera_controller.gd (WASD movement)
├── InputHandler (Node) — scripts/input_handler.gd (mouse click -> fire placement)
└── DebugManager (Node2D) — scripts/debug_manager.gd, starts hidden
    └── ChunkGridOverlay (Node2D) — scripts/chunk_grid_overlay.gd
```

### Key Classes

**WorldManager** (`world_manager.gd`) — Owns the RenderingDevice, chunk dictionary (`Dictionary[Vector2i, Chunk]`), and simulation dispatch. Each frame:
1. Check camera position, load/unload chunks (visible + 1 chunk border)
2. Dispatch even-cell compute pass for all active chunks
3. GPU barrier
4. Dispatch odd-cell compute pass for all active chunks
5. GPU barrier

**Chunk** (`chunk.gd`) — A RefCounted resource (not a Node), holds:
- RD texture RID (the RGBA8 storage texture)
- RD uniform set RIDs (for compute and rendering)
- A MeshInstance2D added to ChunkContainer, positioned at `chunk_coord * 256` world pixels
- ShaderMaterial on the mesh that reads the texture and maps material to color

**CameraController** (`camera_controller.gd`) — Reads WASD input each `_process` frame. Moves Camera2D at a configurable speed (default 400 px/sec). Exposes viewport rect for chunk activation.

**InputHandler** (`input_handler.gd`) — On left mouse click, converts screen position to world position. Tells WorldManager to place fire in a circle (radius 5 pixels) at that coordinate. CPU-side texture update (fire placement is infrequent and small).

**DebugManager** (`debug_manager.gd`) — A Node2D that toggles visibility on F3 via `_unhandled_input`. Starts hidden. Exists in world space so children follow the camera naturally.

**ChunkGridOverlay** (`chunk_grid_overlay.gd`) — Child of DebugManager. Each frame, queries WorldManager for active chunk coordinates. In `_draw()`, draws wireframe rectangles for each chunk (256x256, semi-transparent green).

## Compute Shader: Simulation

**File:** `shaders/simulation.glsl`

### Checkerboard Pattern

Each frame, the compute shader is dispatched twice:
1. **Even pass** — processes pixels where `(x + y) % 2 == 0`
2. **Odd pass** — processes pixels where `(x + y) % 2 == 1`

A push constant tells the shader which phase is active.

### Cross-Chunk Boundaries

Each dispatch binds:
- The chunk's own texture (read/write)
- Up to 4 neighbor textures (read-only: top, bottom, left, right)

If a neighbor chunk isn't loaded, those edge pixels are treated as air.

### Dispatch Details

- Workgroup size: 8x8
- Dispatch: 32x32 workgroups per chunk (256/8 = 32)
- Each invocation:
  1. Read current pixel
  2. Read 4 cardinal neighbors (own texture or neighbor texture if on edge)
  3. Skip if not this phase's parity
  4. Apply CA rules:
     - **Air:** If temperature > 0, dissipate by -2
     - **Wood:** Accumulate temperature from adjacent fire pixels (+10 each). If temperature > 180, become fire with health=255
     - **Fire:** Set temperature=255. Health -= 1. If health == 0, become air
  5. Write result back

## Compute Shader: Generation

**File:** `shaders/generation.glsl`

Dispatched once per chunk on creation. Fills every pixel with wood (R=1, G=255, B=0, A=0). Workgroup size 8x8, 32x32 dispatch. Later extensible with noise-based terrain generation.

## Rendering

**File:** `shaders/render_chunk.gdshader`

A canvas_item fragment shader. Receives the chunk's RGBA8 texture as a `sampler2D` uniform (shared with compute via `RenderingServer.texture_rd_create()`).

Fragment shader logic:
1. Sample texel at current UV
2. Read R channel for material type
3. Map to color:
   - Air (0): transparent `vec4(0.0)`
   - Wood (1): brown `vec4(0.55, 0.35, 0.17, 1.0)`
   - Fire (2): orange-to-red blend based on health (G channel)
4. Tint wood pixels toward red based on temperature (B channel) for heat glow

Texture filtering: `NEAREST` (no interpolation).

## Chunk Lifecycle

**Loading:** Each frame, WorldManager calculates desired chunks (visible + 1 border from camera viewport). New chunks:
1. Create RGBA8 RD texture (256x256)
2. Dispatch `generation.glsl` to fill with wood
3. Create MeshInstance2D with QuadMesh (256x256), position at `chunk_coord * 256`
4. Attach ShaderMaterial with render shader + texture uniform
5. Add to chunk dictionary and ChunkContainer

**Unloading:** Chunks no longer in the desired set are freed (RD texture, MeshInstance2D removed). State is discarded — no persistence. Returning to a location creates fresh wood chunks. Persistence can be added later by serializing texture data before freeing.

**Active set size:** At 1920x1080 with 256px chunks, roughly 6x5 = 30 chunks including border.

## Input

**Fire placement:** On left mouse click:
1. Convert screen position to world position via `get_global_mouse_position()`
2. Calculate which chunk(s) a circle of radius 5 pixels overlaps
3. CPU-side texture update: read texture region, set pixels within radius to fire (R=2, G=255, B=255), re-upload via `texture_update()`

## GPU Data Flow

```
[generation.glsl] --writes--> [RGBA8 Texture (RD)] --shared via texture_rd_create()--> [render_chunk.gdshader]
                                      ^    |
                                      |    v
                              [simulation.glsl] reads/writes each frame
```

No CPU-GPU round-trip for simulation or rendering. Only fire placement involves a small CPU-side texture update.

## File Structure

```
project.godot
scripts/
  world_manager.gd        — chunk lifecycle, simulation dispatch, RD setup
  chunk.gd                — RefCounted, holds RD texture RID, MeshInstance2D, uniform sets
  camera_controller.gd    — WASD movement
  input_handler.gd        — mouse click -> fire placement
  debug_manager.gd        — F3 toggle visibility
  chunk_grid_overlay.gd   — draws chunk boundary lines
shaders/
  simulation.glsl         — compute shader (CA rules, checkerboard)
  generation.glsl         — compute shader (chunk initialization)
  render_chunk.gdshader   — canvas_item shader (material -> color)
scenes/
  main.tscn               — root scene with all nodes
```
