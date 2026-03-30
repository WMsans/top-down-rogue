# Terrain Physics & Player Controller Design

## Overview

Add terrain collision and a top-down player controller to the pixel simulation. The player is a small CharacterBody2D (~10px) that walks through air and collides with solid terrain (stone, wood). Collision is derived from GPU terrain data via a low-resolution marching squares approach.

## Terrain Collision System

### Read-back and Downsampling

- Read a **64x64 pixel region** centered on the player from GPU chunk textures via `RenderingDevice.texture_get_data()`
- When the player is near a chunk border, read from adjacent chunks to cover the full region
- **Downsample to a 16x16 grid** (4:1 ratio) — each cell represents a 4x4 pixel block
- A cell is "solid" if **any** pixel in the 4x4 block is non-air (material != 0). This is conservative: the player won't clip through thin walls

### Marching Squares

- Run marching squares on the 16x16 binary (solid/air) grid to produce polygon contours
- Each contiguous solid region becomes one `CollisionPolygon2D`
- Vertex positions are scaled back to world coordinates (multiply by 4)
- Typical output: ~20-60 vertices for cave terrain at this resolution

### Collision Node Structure

- `TerrainCollider` node lives as a child of the Player
- Contains one `StaticBody2D` with N `CollisionPolygon2D` children
- Polygons are cleared and rebuilt on each update

### Rebuild Triggers

- Player moves more than **~8 pixels** from the last rebuild center
- Terrain changes nearby (burning/destruction), triggered by the simulation tick

### Collision Layer

- Terrain collision on **layer 1** ("terrain")

### Downsample Trade-off

- Collision boundaries are ~4px coarser than the visual terrain
- At player size 8-16px with large cave corridors, this rounding is imperceptible
- Can be tightened to 2:1 (32x32 grid) later if needed

## Player Controller

### Scene Structure

```
Player (CharacterBody2D)
├── CollisionShape2D (RectangleShape2D, ~10x10 px)
├── Sprite2D (placeholder colored rectangle or DawnLike sprite)
└── Camera2D (replaces current free camera)
```

### Movement Model

- `move_and_slide()` on CharacterBody2D
- WASD input produces a normalized direction vector
- Direction vector is multiplied by acceleration to change velocity
- Friction is applied when no input, causing a short slide to stop
- Velocity is clamped to `max_speed`

### Tunable Parameters (exported)

| Parameter      | Default   |
|---------------|-----------|
| `max_speed`    | 120 px/s  |
| `acceleration` | 800 px/s² |
| `friction`     | 600 px/s² |

### Collision Setup

- Player on **layer 2** ("player"), mask includes **layer 1** ("terrain")
- 10x10 px `RectangleShape2D` — small enough to fit through cave corridors

### Camera

- `Camera2D` as a child of Player, follows automatically
- `position_smoothing_enabled` for smooth follow
- Zoom level set so pixel terrain is clearly visible at the player's scale
- Replaces the current standalone `camera_controller.gd`

### Input

- Reuses existing WASD input actions
- Fire placement (left click) continues to work via `input_handler.gd`, using cursor position relative to the player camera

## Integration & Spawn

### Spawning

- `WorldManager` gains a `spawn_player()` method, called after initial chunks generate
- Spawn location: scan the center chunk's terrain data for a valid air pocket (search from center of chunk until an air pixel cluster large enough for the player is found)
- Player scene instantiated and positioned at the found air coordinates

### WorldManager Changes

- Chunk loading follows the **player's position** instead of the free camera
- Expose `get_terrain_material_at(world_pos: Vector2) -> int` — reads from the GPU read-back cache so TerrainCollider and other systems can query terrain without redundant GPU reads
- `place_fire()` logic remains, using cursor position relative to the player camera

### Scene Tree

```
Main (Node2D)
├── WorldManager
├── Player (CharacterBody2D)
│   ├── CollisionShape2D
│   ├── Sprite2D
│   ├── Camera2D
│   └── TerrainCollider
│       └── StaticBody2D
│           ├── CollisionPolygon2D (rebuilt dynamically)
│           └── ...
├── InputHandler
├── DebugManager
└── ChunkGridOverlay
```

### Removed/Replaced

- `camera_controller.gd` — replaced by Camera2D on the Player node
- Free-camera WASD movement removed from the main scene; WASD now drives the player

## Performance Notes

- 64x64 GPU read-back is negligible (<0.1ms)
- 16x16 marching squares produces few vertices, fast to compute
- Collision rebuilds happen every few frames (on movement threshold), not every frame
- Single StaticBody2D with ~20-60 polygon children is well within Godot's physics budget
