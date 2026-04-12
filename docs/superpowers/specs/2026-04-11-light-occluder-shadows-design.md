# Light Occluder Shadow System Design

**Date**: 2026-04-11
**Status**: Draft

## Overview

Implement shadow casting for the player's PointLight2D so that light stops at terrain walls instead of shining through them. The system will use Godot's built-in LightOccluder2D nodes attached to each terrain chunk, reusing the existing polygon segment data generated for collisions.

## Goal

Make the player's point light cast shadows on terrain, creating a more realistic lighting effect where light does not penetrate solid walls.

## Architecture

### System Components

```
Chunk Mesh Rendering (existing)
        ↓
Terrain GPU Simulation (existing)
        ↓
Collision Rebuild Timer (every 0.2s)
        ↓
Segment Generation (marching squares)
        ↓
    ├── CollisionShape2D update (existing)
        └── LightOccluder2D update (NEW)
```

### Chunk Structure

Each chunk will now contain:
1. `MeshInstance2D` - terrain floor rendering (existing)
2. `MeshInstance2D` - wall top rendering (existing)
3. `StaticBody2D` with `CollisionShape2D` - physics collision (existing)
4. `LightOccluder2D` - shadow occluder polygon (NEW)

## Implementation Details

### 1. Chunk Class Extension

**File**: `src/core/world_manager.gd` (Chunk class defined inline)

Add field:
```gdscript
var occluder_instance: LightOccluder2D
```

Lifecycle:
- Create in `_create_chunk()`
- Free in `_free_chunk_resources()`

### 2. Occluder Generation

**File**: `src/physics/terrain_collider.gd`

Add new static function:
```gdscript
static func build_occluder(
    segments: PackedVector2Array,
    chunk_coord: Vector2i
) -> LightOccluder2D
```

Implementation:
- Create LightOccluder2D node
- Create OccluderPolygon2D from segments
- Set occluder position to chunk offset (chunk_coord * CHUNK_SIZE)
- Return null if segments < 4 (need at least 2 line segments)

### 3. Light Configuration

**File**: `scenes/player.tscn`

Configure PointLight2D:
- `shadow_enabled = true`
- `shadow_filter = Light2D.SHADOW_FILTER_PCF5`
- `shadow_filter_smooth = 2.0`
- `shadow_color = Color(0, 0, 0, 0.5)`

### 4. Shadow Update Integration

**File**: `src/core/world_manager.gd`

Modify collision rebuild functions:
- `_rebuild_chunk_collision_gpu()`: After building collision shape, call `build_occluder()` with same segments
- `_rebuild_chunk_collision_cpu()`: Same pattern as GPU version
- `_create_chunk()`: Create initial occluder instance
- `_free_chunk_resources()`: Queue free the occluder

Segment source:
- GPU path: Parse segments from collider shader buffer (already done in `_parse_segment_buffer()`)
- CPU path: Generate segments from `build_collision()` return value

## Error Handling

1. **Empty chunks**: If segment generation returns < 4 segments, skip occluder creation (chunk is all air or all solid)
2. **Occluder creation failure**: Log warning and continue - light will shine through but game remains playable
3. **Performance**: Occluder polygons use ConvexPolygonShape2D internally, which is efficient for Godot's shadow casting

## File Changes Summary

| File | Change |
|------|--------|
| `src/core/chunk.gd` | Add `occluder_instance` field |
| `src/physics/terrain_collider.gd` | Add `build_occluder()` function |
| `src/core/world_manager.gd` | Create/update/free occluders in chunk lifecycle |
| `scenes/player.tscn` | Enable shadows on PointLight2D |

## Performance Considerations

- Occluder updates happen at 5 Hz (every 0.2s), matching collision rebuild rate
- Same segment generation as collision (no additional marching squares computation)
- LightOccluder2D nodes are cheap - they're just polygon containers for Godot's shadow system
- Shadow rendering is handled by Godot's optimized 2D light renderer

## Testing Plan

1. **Visual verification**: Walk through terrain, verify light stops at walls
2. **Dynamic updates**: Destroy terrain, verify shadows update within 0.2s
3. **Empty chunks**: Verify no crash when chunk has no solid terrain
4. **Performance**: Monitor frame rate with many chunks visible
5. **Edge cases**: Test at chunk boundaries, rapid terrain changes

## Future Enhancements (Out of Scope)

- Different occluder settings for different material types
- Optimized occluder polygon simplification
- Shadow casting for other light sources (enemies, projectiles)
- Shadow-only layer for more complex lighting setups