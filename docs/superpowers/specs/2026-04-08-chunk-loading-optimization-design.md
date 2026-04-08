# Chunk Loading Optimization Design

## Problem

The game experiences ~500ms lag every time a chunk enters the player's view, even for previously loaded chunks. This stutter disrupts gameplay and makes exploration feel unresponsive.

## Root Cause

Current implementation creates new GPU resources and scene nodes for every chunk entering view:
- `rd.texture_create()` - GPU texture allocation (256x256 pixels)
- `rd.storage_buffer_create()` - Injection buffer allocation
- `MeshInstance2D.new()` + `QuadMesh.new()` - Scene node creation
- `ShaderMaterial.new()` - Material instantiation
- Multiple `add_child()` calls - Scene tree modification
- Compute shader dispatch for chunk generation

These operations are expensive and run synchronously on the main thread, blocking rendering.

## Solution: Three-Pronged Optimization

### 1. Object Pooling

Reuse chunk objects instead of destroying/creating them.

**Implementation:**
- Store unloaded chunks in a pool dictionary keyed by coord
- When a chunk is needed, check pool first
- Pool hits: Reset texture data, reuse GPU resources and scene nodes
- Pool misses: Create new chunk as before
- Limit pool size to prevent unbounded memory growth

**Benefits:**
- Eliminates GPU resource allocation overhead for revisited areas
- Eliminates MeshInstance2D/ShaderMaterial creation overhead
- 70-90% reduction in load time for previously visited chunks

### 2. Asynchronous Chunk Generation

Spread work across multiple frames to avoid single-frame stutter.

**Implementation:**
- Create chunk "stubs" immediately (empty meshes, placeholder visuals)
- Queue actual generation and texture uploading
- Process 2-3 chunks per frame from queue
- Prioritize chunks closer to player

**Benefits:**
- No single frame exceeds ~16ms
- Smooth camera movement during chunk loading
- Visible progress as chunks pop in over 2-3 frames

### 3. Predictive Loading

Load chunks before player reaches them using movement prediction.

**Implementation:**
- Track last N player positions (N=5-10)
- Calculate velocity trend to predict movement direction
- Pre-load 1-2 chunks ahead in predicted direction
- Lower priority for predictive chunks (filled later in queue)

**Benefits:**
- Chunks ready before player needs them
- Reduced perceived load time
- Works synergistically with pooling (predictive loads hit pool)

## Architecture

```
WorldManager
├── ChunkPool
│   ├── inactive_chunks: Dictionary {coord -> Chunk}
│   ├── max_pool_size: int
│   ├── get_chunk(coord) -> Chunk
│   └── return_chunk(coord, chunk)
├── ChunkQueue
│   ├── pending_generation: Array[{coord, priority}]
│   ├── pending_textures: Array[{coord, data}]
│   ├── max_generation_per_frame: int
│   └── max_texture_updates_per_frame: int
└── PredictiveLoader
    ├── movement_history: Array[Vector2]
    ├── predicted_direction: Vector2
    └── get_predictive_chunks(current_view) -> Array[Vector2i]
```

## Data Flow

```
Player Movement
       │
       ▼
PredictiveLoader.get_predictive_chunks()
       │
       ▼
Determine desired chunks (visible + predictive)
       │
       ├─ Unload chunks → return to pool
       │
       └─ Load chunks:
              │
              ├─ Pool hit?
              │      ├─ Yes → Reset texture, queue texture upload
              │      └─ No  → Create stub mesh, queue generation
              │
              ▼
       ChunkQueue processes 2-3 items per frame
              │
              ├─ Generation dispatch (compute shader)
              │
              └─ Texture upload (for pooled chunks)
              │
              ▼
       Chunk fully ready
```

## Implementation Details

### New Files

**scripts/chunk_pool.gd**
- `inactive_chunks: Dictionary` - Pool storage
- `max_pool_size: int` - Memory limit (~64 chunks)
- `get_chunk(coord: Vector2i) -> Chunk` - Retrieve from pool or create new
- `return_chunk(coord: Vector2i, chunk: Chunk)` - Move chunk to pool
- `clear()` - Empty pool, free all resources
- Integration with WorldManager's RD and shader references

**scripts/chunk_queue.gd**
- `pending_generation: Array` - Chunks waiting for compute dispatch
- `pending_texture_reset: Array` - Pooled chunks needing texture zeroing
- `max_per_frame: int = 2` - Processing limit
- `add_generation(coord, priority)` - Queue new chunk generation
- `add_texture_reset(coord)` - Queue pooled chunk reset
- `process_next_frame()` - Called by _process, processes up to limit
- Priority sorting (lower distance to player = higher priority)

**scripts/predictive_loader.gd**
- `position_history: Array[Vector2]` - Last N positions
- `history_size: int = 10` - Positions to track
- `chunks_ahead: int = 1` - How many chunks ahead to predict
- `update(player_pos: Vector2)` - Update position history
- `get_predicted_chunks(current_view: Array[Vector2i]) -> Array[Vector2i]` - Return predictive coords
- Movement prediction: Calculate velocity trend from history, project forward

### Modified Files

**scripts/chunk.gd**
- Add `is_recycled: bool` field
- Add `reset_for_reuse()` method - Clears collision, marks dirty, zero texture data
- Remove resource creation from constructor, move to factory method

**scripts/world_manager.gd**
- Replace direct chunk creation with `chunk_pool.get_chunk(coord)`
- Replace direct chunk destruction with `chunk_pool.return_chunk(coord, chunk)`
- Add `chunk_queue` instance
- Add `predictive_loader` instance
- Modify `_get_desired_chunks()` to include predictive chunks
- Modify `_update_chunks()` to use queue for generation/uploads
- Add per-frame queue processing in `_process()`

### Chunk Lifecycle Changes

**Before:**
```
Enter view → Create all resources → Generate → Ready
Exit view   → Free all resources
```

**After:**
```
Enter view → Check pool
                ├─ Hit  → Reset texture → Queue upload → Ready (1-2 frames)
                └─ Miss → Create stub → Queue generation → Ready (2-3 frames)
Exit view   → Return to pool (or free if pool full)
```

## Configuration Values

```gdscript
const POOL_MAX_SIZE := 64
const MAX_GENERATION_PER_FRAME := 2
const MAX_TEXTURE_UPDATES_PER_FRAME := 4
const PREDICTIVE_CHUNKS_AHEAD := 1
const POSITION_HISTORY_SIZE := 10
```

## Performance Targets

| Metric | Before | After |
|--------|--------|-------|
| First-time chunk load | ~500ms | <16ms per frame, 2-3 frames total |
| Re-visited chunk load | ~500ms | <5ms (pool hit) |
| Frame stutter | 500ms pause | No single frame >20ms |
| Memory overhead | None | ~64 chunk pool (~16MB GPU memory) |

## Edge Cases

1. **Rapid direction changes**: Predictive chunks may be wasted, but pool will recycle them
2. **Pool overflow**: Excess chunks freed normally (current behavior)
3. **Very fast movement**: Queue backlog possible; player may see placeholder meshes briefly
4. **Memory pressure**: Pool size is configurable; reduce if needed

## Testing Strategy

1. Profile before/after with Godot profiler
2. Monitor frame times during chunk loading
3. Test rapid back-and-forth movement (pooling effectiveness)
4. Test sustained forward movement (predictive loading effectiveness)
5. Test rapid direction changes (wasted predictive loads)
6. Monitor GPU memory usage with pool enabled