# Collision Optimization for Burning Wood

## Problem

When wood burns, collision shapes are rebuilt every frame, causing severe FPS drops. The current implementation:

1. Reads 256KB texture from GPU to CPU every frame per burning chunk
2. Runs marching squares algorithm on65,536 pixels on CPU
3. Creates and destroys CollisionShape2D nodes every frame

This process takes ~5-15ms per chunk during burning, making 60 FPS impossible with multiple burning chunks.

## Solution

Combine GPU-based marching squares with time-based throttling:

1. **GPU Marching Squares**: Run the marching squares algorithm on the GPU via compute shader, eliminating the 256KB texture readback. Only read back the resulting segment list (<8KB).

2. **Time-Based Throttling**: Rebuild collision every 0.3 seconds instead of every frame while burning. This reduces collision shape creation frequency by 200×at 60 FPS.

## Architecture

### Current Flow
```
Every frame (while burning):
  GPU texture → 256KB readback → CPU copy → CPU marching squares → CollisionShape2D
```

### New Flow
```
Every 0.3 seconds (while burning):
  GPU texture → GPU marching squares → <8KB segment readback → CollisionShape2D
```

## Components

### 1. GPU Marching Squares Shader

**File:** `shaders/collider.glsl`

**Inputs:**
- Binding 0: Terrain texture (R8G8B8A8_UNORM)
- Push constant: `chunk_size: uint` (256)

**Outputs:**
- Binding 1: Storage buffer for segments
- Format: R32UI atomic buffer
- Layout: `[segment_count, x1, y1, x2, y2, x1, y1, x2, y2, ...]`

**Algorithm:**
1. Each thread processes one cell (CELL_SIZE × CELL_SIZE pixels)
2. Sample 4 corner pixels from texture
3. Compute 4-bit case index from corner states
4. Write segment endpoints to storage buffer using atomic counter

**Cell Size:** 2 pixels (same as current implementation)
**Dispatch:** 16×16 workgroups of 8×8 threads = 128×128 cells for 256×256 chunk

**Buffer Sizing:**
- Maximum 4096 segments per chunk
- Storage buffer: 1 + (4096 × 4) = 16,385 uints = ~64KB

**Edge Cases:**
- Border cells sample outside texture → return air (mat= 0)
- All-air cells → no segment output
- Saddle points → consistent resolution (cases 5 and 10 use diagonal split)

### 2. Chunk Class Updates

**File:** `scripts/chunk.gd`

Add timing field:
```gdscript
var last_collision_time: float = 0.0
```

### 3. TerrainCollider Updates

**File:** `scripts/terrain_collider.gd`

Add new function:
```gdscript
static func build_from_segments(
    segments: PackedVector2Array,
    static_body: StaticBody2D,
    world_offset: Vector2i
) -> CollisionShape2D:
```

This function receives pre-computed segments from GPU and creates the collision shape.

**Retain existing function:**
- `build_collision()` kept for fallback scenarios
- Used for initial chunk load if GPU path fails

###4. WorldManager Integration

**File:** `scripts/world_manager.gd`

**New constants:**
```gdscript
const COLLISION_UPDATE_INTERVAL := 0.3
```

**New fields:**
```gdscript
var collider_shader: RID
var collider_pipeline: RID
var collider_storage_buffer: RID
var collider_uniform_set: RID
```

**New functions:**

1. **`_init_collider_shader()`** - Initialize compute pipeline
2. **`_rebuild_chunk_collision_gpu(chunk: Chunk)`** - Dispatch GPU compute and read results
3. **`_parse_segment_buffer(data: PackedByteArray)`** - Convert GPU buffer to PackedVector2Array

**Modified function:**

`_rebuild_dirty_collisions()` now:
- Checks time since `last_collision_time`
- Uses GPU path for burning chunks
- Falls back to CPU if GPU fails

**Cleanup:**
- Free collider resources in `_exit_tree()`

## Throttling Behavior

```
Time 0.0s: Fire starts → collision_dirty = true, last_collision_time = 0.0
Time 0.0s: First GPU rebuild (interval satisfied)
Time 0.1s: Skip (0.1 < 0.3)
Time 0.2s: Skip (0.2 < 0.3)
Time 0.3s: GPU rebuild (0.3 >= 0.3)
Time 0.4s: Skip
Time 0.6s: GPU rebuild
... burning continues ...
Time 30.0s: Burning stops → collision_dirty = false
Time 30.0s: Final rebuild (dirty still true, interval satisfied)
Time 30.0s+: No more rebuilds (dirty = false)
```

## Error Handling

| Scenario | Handling |
|----------|----------|
| GPU buffer read failure | Fall back to CPU `build_collision()`, log warning once |
| Segment count overflow | Truncate to buffer limit, log warning |
| Empty chunk (all air) | Return null, no collision shape created |
| Border cell sampling | Treat out-of-bounds as air (mat= 0) |
| First-time chunk load | Use GPU path directly |

## Performance Expectations

**Before:**
- ~5-15ms per chunk per frame during burning
- 60 FPS impossible with 2+ burning chunks

**After:**
- GPU compute: ~0.5-1ms per chunk
- Buffer readback: ~0.1ms (<8KB)
- CollisionShape creation: ~0.5-1ms
- Per-update total: ~1-2ms
- With 0.3s throttling: effective cost ~3-6μs per frame
- 60 FPS maintained with multiple burning chunks

## Implementation Order

1. Create `shaders/collider.glsl` compute shader
2. Add `last_collision_time` to `Chunk` class
3. Add `build_from_segments()` to `TerrainCollider`
4. Add collider initialization to `WorldManager._init_shaders()`
5. Add GPU dispatch and readback to `WorldManager`
6. Update `_rebuild_dirty_collisions()` with throttling
7. Add cleanup in `_exit_tree()`
8. Test with burning scenarios

## Testing Scenarios

1. Single chunk burning - verify GPU path works
2. Multiple adjacent chunks burning - verify throttling spreads load
3. Edge-chunks with borders - verify edge sampling
4. Rapid fire ignite/extinguish - verify dirty flag handling
5. Long burns (30+ seconds) - verify sustained performance
6. Chunk load/unload during burn - verify resource cleanup