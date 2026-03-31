# Collision Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Optimize collision shape generation during wood burning by moving marching squares algorithm to GPU and adding time-based throttling.

**Architecture:** A compute shader runs marching squares on the GPU terrain texture, outputting segment vertices to a storage buffer. WorldManager reads back only the segment list (<8KB) instead of the full texture (256KB). Throttling limits rebuilds to every 0.3 seconds per chunk.

**Tech Stack:** Godot 4.x, GLSL compute shaders, RenderingDevice API

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `shaders/collider.glsl` | Create | GPU marching squares compute shader |
| `scripts/chunk.gd` | Modify | Add `last_collision_time` field |
| `scripts/terrain_collider.gd` | Modify | Add `build_from_segments()` function |
| `scripts/world_manager.gd` | Modify | Add collider pipeline, throttling, cleanup |

---

### Task 1: Add Timing Field to Chunk

**Files:**
- Modify: `scripts/chunk.gd:10`

- [ ] **Step 1: Add last_collision_time field**

Add a new field to track when collision was last rebuilt:

```gdscript
class_name Chunk
extends RefCounted

var coord: Vector2i
var rd_texture: RID
var texture_2d_rd: Texture2DRD
var mesh_instance: MeshInstance2D
var sim_uniform_set: RID
var static_body: StaticBody2D
var collision_dirty: bool = true
var last_collision_time: float = 0.0
```

- [ ] **Step 2: Commit**

```bash
git add scripts/chunk.gd
git commit -m "feat: add last_collision_time field for throttling"
```

---

### Task 2: Create GPU Marching Squares Shader

**Files:**
- Create: `shaders/collider.glsl`

- [ ] **Step 1: Create compute shader file**

Create `shaders/collider.glsl` with the GPU marching squares implementation:

```glsl
#[compute]
#[x(8), y(8), z(1)]

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba8ui) uniform readonly uimage2D terrain_texture;
layout(set = 0, binding = 1, r32ui) uniform uimage2D segment_buffer;

const uint CELL_SIZE = 2u;

shared uint segment_count;

void main() {
    uint chunk_size = 256u;
    uint cells_per_side = chunk_size / CELL_SIZE;
    
    uint cell_x = gl_GlobalInvocationID.x;
    uint cell_y = gl_GlobalInvocationID.y;
    
    if (cell_x >= cells_per_side || cell_y >= cells_per_side) {
        return;
    }
    
    // Sample 4 corners of the cell
    uint gx = cell_x * CELL_SIZE;
    uint gy = cell_y * CELL_SIZE;
    
    // Border cells are treated as air (outside chunk)
    if (gx == 0 || gy == 0 || gx >= chunk_size - CELL_SIZE || gy >= chunk_size - CELL_SIZE) {
        return;
    }
    
    uvec4 tl_sample = imageLoad(terrain_texture, ivec2(gx, gy));
    uvec4 tr_sample = imageLoad(terrain_texture, ivec2(gx + CELL_SIZE, gy));
    uvec4 br_sample = imageLoad(terrain_texture, ivec2(gx + CELL_SIZE, gy + CELL_SIZE));
    uvec4 bl_sample = imageLoad(terrain_texture, ivec2(gx, gy + CELL_SIZE));
    
    // Material is in R channel, check if solid (non-zero)
    uint tl = (tl_sample.r != 0u) ? 1u : 0u;
    uint tr = (tr_sample.r != 0u) ? 1u : 0u;
    uint br = (br_sample.r != 0u) ? 1u : 0u;
    uint bl = (bl_sample.r != 0u) ? 1u : 0u;
    
    // All air or all solid => no segment
    if (tl + tr + br + bl == 0u || tl + tr + br + bl == 4u) {
        return;
    }
    
    uint case_idx = (tl << 3u) | (tr << 2u) | (br << 1u) | bl;
    
    // Edge midpoints in cell coordinates
    uint half_cell = CELL_SIZE / 2u;
    uvec2 top_edge = uvec2(gx + half_cell, gy);
    uvec2 right_edge = uvec2(gx + CELL_SIZE, gy + half_cell);
    uvec2 bottom_edge = uvec2(gx + half_cell, gy + CELL_SIZE);
    uvec2 left_edge = uvec2(gx, gy + half_cell);
    
    // Get segments for this case
    // Each segment is [p1, p2] encoded as 4 uints
    uint segments[8];
    uint num_segments = 0u;
    
    switch (case_idx) {
        case 1u: // D
            segments[0] = left_edge.x; segments[1] = left_edge.y;
            segments[2] = bottom_edge.x; segments[3] = bottom_edge.y;
            num_segments = 1u;
            break;
        case 2u: // C
            segments[0] = bottom_edge.x; segments[1] = bottom_edge.y;
            segments[2] = right_edge.x; segments[3] = right_edge.y;
            num_segments = 1u;
            break;
        case 3u: // D+C
            segments[0] = left_edge.x; segments[1] = left_edge.y;
            segments[2] = right_edge.x; segments[3] = right_edge.y;
            num_segments = 1u;
            break;
        case 4u: // B
            segments[0] = right_edge.x; segments[1] = right_edge.y;
            segments[2] = top_edge.x; segments[3] = top_edge.y;
            num_segments = 1u;
            break;
        case 5u: // D+B (saddle)
            segments[0] = left_edge.x; segments[1] = left_edge.y;
            segments[2] = bottom_edge.x; segments[3] = bottom_edge.y;
            segments[4] = right_edge.x; segments[5] = right_edge.y;
            segments[6] = top_edge.x; segments[7] = top_edge.y;
            num_segments = 2u;
            break;
        case 6u: // C+B
            segments[0] = bottom_edge.x; segments[1] = bottom_edge.y;
            segments[2] = top_edge.x; segments[3] = top_edge.y;
            num_segments = 1u;
            break;
        case 7u: // D+C+B
            segments[0] = left_edge.x; segments[1] = left_edge.y;
            segments[2] = top_edge.x; segments[3] = top_edge.y;
            num_segments = 1u;
            break;
        case 8u: // A
            segments[0] = top_edge.x; segments[1] = top_edge.y;
            segments[2] = left_edge.x; segments[3] = left_edge.y;
            num_segments = 1u;
            break;
        case 9u: // A+D
            segments[0] = top_edge.x; segments[1] = top_edge.y;
            segments[2] = bottom_edge.x; segments[3] = bottom_edge.y;
            num_segments = 1u;
            break;
        case 10u: // A+C (saddle)
            segments[0] = top_edge.x; segments[1] = top_edge.y;
            segments[2] = left_edge.x; segments[3] = left_edge.y;
            segments[4] = bottom_edge.x; segments[5] = bottom_edge.y;
            segments[6] = right_edge.x; segments[7] = right_edge.y;
            num_segments = 2u;
            break;
        case 11u: // A+C+B
            segments[0] = top_edge.x; segments[1] = top_edge.y;
            segments[2] = right_edge.x; segments[3] = right_edge.y;
            num_segments = 1u;
            break;
        case 12u: // A+B
            segments[0] = right_edge.x; segments[1] = right_edge.y;
            segments[2] = left_edge.x; segments[3] = left_edge.y;
            num_segments = 1u;
            break;
        case 13u: // A+B+D
            segments[0] = bottom_edge.x; segments[1] = bottom_edge.y;
            segments[2] = left_edge.x; segments[3] = left_edge.y;
            num_segments = 1u;
            break;
        case 14u: // A+B+C
            segments[0] = right_edge.x; segments[1] = right_edge.y;
            segments[2] = bottom_edge.x; segments[3] = bottom_edge.y;
            num_segments = 1u;
            break;
        case 15u: // A+B+C+D
            // All solid, no segment
            num_segments = 0u;
            break;
    }
    
    // Atomically reserve space in the buffer and write segments
    for (uint s = 0u; s < num_segments; s++) {
        uint idx = imageAtomicAdd(segment_buffer, ivec2(0, 0), 4u);
        imageStore(segment_buffer, ivec2(idx + 0, 0), uvec4(segments[s * 4 + 0], 0u, 0u, 0u));
        imageStore(segment_buffer, ivec2(idx + 1, 0), uvec4(segments[s * 4 + 1], 0u, 0u, 0u));
        imageStore(segment_buffer, ivec2(idx + 2, 0), uvec4(segments[s * 4 + 2], 0u, 0u, 0u));
        imageStore(segment_buffer, ivec2(idx + 3, 0), uvec4(segments[s * 4 + 3], 0u, 0u, 0u));
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add shaders/collider.glsl
git commit -m "feat: add GPU marching squares compute shader"
```

---

### Task 3: Add build_from_segments to TerrainCollider

**Files:**
- Modify: `scripts/terrain_collider.gd:197`

- [ ] **Step 1: Add build_from_segments function**

Add a new static function after `build_collision`:

```gdscript
static func build_from_segments(
    segments: PackedVector2Array,
    static_body: StaticBody2D,
    world_offset: Vector2i
) -> CollisionShape2D:
    if segments.size() < 4:
        return null
    
    var shape := ConcavePolygonShape2D.new()
    shape.segments = segments
    var collision_shape := CollisionShape2D.new()
    collision_shape.shape = shape
    static_body.position = Vector2(world_offset.x, world_offset.y)
    return collision_shape
```

- [ ] **Step 2: Commit**

```bash
git add scripts/terrain_collider.gd
git commit -m "feat: add build_from_segments for GPU-generated segments"
```

---

### Task 4: Initialize Collider Pipeline in WorldManager

**Files:**
- Modify: `scripts/world_manager.gd:21`
- Modify: `scripts/world_manager.gd:28`

- [ ] **Step 1: Add collider shader fields**

Add new fields after the existing shader RIDs:

```gdscript
var rd: RenderingDevice
var chunks: Dictionary = {}  # Vector2i -> Chunk

var gen_shader: RID
var gen_pipeline: RID
var sim_shader: RID
var sim_pipeline: RID
var collider_shader: RID
var collider_pipeline: RID
var collider_storage_buffer: RID
var dummy_texture: RID
```

- [ ] **Step 2: Add collider shader initialization**

In `_init_shaders()`, add collider pipeline initialization after the sim pipeline:

```gdscript
func _init_shaders() -> void:
    var gen_file: RDShaderFile = load("res://shaders/generation.glsl")
    var gen_spirv := gen_file.get_spirv()
    gen_shader = rd.shader_create_from_spirv(gen_spirv)
    gen_pipeline = rd.compute_pipeline_create(gen_shader)

    var sim_file: RDShaderFile = load("res://shaders/simulation.glsl")
    var sim_spirv := sim_file.get_spirv()
    sim_shader = rd.shader_create_from_spirv(sim_spirv)
    sim_pipeline = rd.compute_pipeline_create(sim_shader)

    var collider_file: RDShaderFile = load("res://shaders/collider.glsl")
    var collider_spirv := collider_file.get_spirv()
    collider_shader = rd.shader_create_from_spirv(collider_spirv)
    collider_pipeline = rd.compute_pipeline_create(collider_shader)
```

- [ ] **Step 3: Add collider storage buffer creation**

Add a new function to create the storage buffer:

```gdscript
func _init_collider_storage_buffer() -> void:
    var max_segments := 4096
    var buffer_size := (1 + max_segments * 4) * 4  # count + segments, 4 uints per segment
    var bf := RDBufferFormat.new()
    bf.usage_bits = RenderingDevice.STORAGE_BUFFER_USAGE_READ_WRITE
    bf.buffer_size = buffer_size
    collider_storage_buffer = rd.storage_buffer_create(bf)
```

- [ ] **Step 4: Initialize buffer in _ready**

Call the buffer initialization in `_ready()`:

```gdscript
func _ready() -> void:
    rd = RenderingServer.get_rendering_device()
    _init_shaders()
    _init_dummy_texture()
    _init_collider_storage_buffer()
    render_shader = preload("res://shaders/render_chunk.gdshader")
    _init_material_textures()
    
    collision_container = Node2D.new()
    collision_container.name = "CollisionContainer"
    add_child(collision_container)
```

- [ ] **Step 5: Add cleanup in _exit_tree**

Add collider resource cleanup:

```gdscript
func _exit_tree() -> void:
    for coord in chunks:
        var chunk: Chunk = chunks[coord]
        _free_chunk_resources(chunk)
    chunks.clear()
    if dummy_texture.is_valid():
        rd.free_rid(dummy_texture)
    if collider_storage_buffer.is_valid():
        rd.free_rid(collider_storage_buffer)
    if gen_pipeline.is_valid():
        rd.free_rid(gen_pipeline)
    if gen_shader.is_valid():
        rd.free_rid(gen_shader)
    if sim_pipeline.is_valid():
        rd.free_rid(sim_pipeline)
    if sim_shader.is_valid():
        rd.free_rid(sim_shader)
    if collider_pipeline.is_valid():
        rd.free_rid(collider_pipeline)
    if collider_shader.is_valid():
        rd.free_rid(collider_shader)
```

- [ ] **Step 6: Commit**

```bash
git add scripts/world_manager.gd
git commit -m "feat: add collider shader pipeline and storage buffer"
```

---

### Task 5: Add GPU Collision Dispatch and Parsing

**Files:**
- Modify: `scripts/world_manager.gd:424`

- [ ] **Step 1: Add constants**

Add the throttling constant after the existing constants:

```gdscript
const CHUNK_SIZE := 256
const WORKGROUP_SIZE := 8
const NUM_WORKGROUPS := CHUNK_SIZE / WORKGROUP_SIZE  # 32

const MAT_AIR := 0
const MAT_WOOD := 1
const MAT_STONE := 2
const MAX_TEMPERATURE := 255
const IGNITION_TEMP := 180

const COLLISION_UPDATE_INTERVAL := 0.3
const MAX_COLLISION_SEGMENTS := 4096
```

- [ ] **Step 2: Add segment parsing function**

Add a function to parse GPU buffer output:

```gdscript
func _parse_segment_buffer(data: PackedByteArray, max_offset: int) -> PackedVector2Array:
    var segments := PackedVector2Array()
    var offset := 0
    while offset + 16 <= data.size() and offset < max_offset:
        var x1 := data.decode_float(offset)
        var y1 := data.decode_float(offset + 4)
        var x2 := data.decode_float(offset + 8)
        var y2 := data.decode_float(offset + 12)
        if x1 == 0.0 and y1 == 0.0 and x2 == 0.0 and y2 == 0.0:
            break
        segments.append(Vector2(x1, y1))
        segments.append(Vector2(x2, y2))
        offset += 16
    return segments
```

- [ ] **Step 3: Add GPU collision rebuild function**

Add the GPU dispatch function:

```gdscript
func _rebuild_chunk_collision_gpu(chunk: Chunk) -> bool:
    var buffer_data := PackedByteArray()
    buffer_data.resize(4)
    buffer_data.encode_u32(0, 0)
    rd.buffer_update(collider_storage_buffer, 0, buffer_data)
    
    var uniforms: Array[RDUniform] = []
    
    var u0 := RDUniform.new()
    u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
    u0.binding = 0
    u0.add_id(chunk.rd_texture)
    uniforms.append(u0)
    
    var u1 := RDUniform.new()
    u1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    u1.binding = 1
    u1.add_id(collider_storage_buffer)
    uniforms.append(u1)
    
    var uniform_set := rd.uniform_set_create(uniforms, collider_shader, 0)
    
    var compute_list := rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(compute_list, collider_pipeline)
    rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
    rd.compute_list_dispatch(compute_list, 16, 16, 1)
    rd.compute_list_end()
    
    rd.free_rid(uniform_set)
    
    var result_data := rd.buffer_get_data(collider_storage_buffer)
    if result_data.size() < 4:
        return false
    
    var segment_count := result_data.decode_u32(0)
    if segment_count == 0:
        return true
    
    var segments := _parse_segment_buffer(result_data.slice(4), segment_count * 4)
    
    var world_offset := chunk.coord * CHUNK_SIZE
    if chunk.static_body.get_child_count() > 0:
        for child in chunk.static_body.get_children():
            child.queue_free()
    
    if segments.size() >= 4:
        var collision_shape := TerrainCollider.build_from_segments(
            segments, chunk.static_body, world_offset
        )
        if collision_shape != null:
            chunk.static_body.add_child(collision_shape)
    
    return true
```

- [ ] **Step 4: Commit**

```bash
git add scripts/world_manager.gd
git commit -m "feat: add GPU collision dispatch and segment parsing"
```

---

### Task 6: Integrate Throttling into Collision Rebuild Loop

**Files:**
- Modify: `scripts/world_manager.gd:355`

- [ ] **Step 1: Update _rebuild_dirty_collisions**

Replace the existing function with throttled GPU version:

```gdscript
func _rebuild_dirty_collisions() -> void:
    var now := Time.get_ticks_msec() / 1000.0
    for coord in chunks:
        var chunk: Chunk = chunks[coord]
        if not chunk.collision_dirty:
            continue
        if now - chunk.last_collision_time < COLLISION_UPDATE_INTERVAL:
            continue
        
        var success := _rebuild_chunk_collision_gpu(chunk)
        if not success:
            _rebuild_chunk_collision_cpu(chunk)
        
        chunk.last_collision_time = now
```

- [ ] **Step 2: Rename existing function to CPU fallback**

Rename `_rebuild_chunk_collision` to `_rebuild_chunk_collision_cpu`:

```gdscript
func _rebuild_chunk_collision_cpu(chunk: Chunk) -> void:
    var chunk_data := rd.texture_get_data(chunk.rd_texture, 0)
    var material_data := PackedByteArray()
    material_data.resize(CHUNK_SIZE * CHUNK_SIZE)
    var has_burning := false
    for y in CHUNK_SIZE:
        for x in CHUNK_SIZE:
            var src_idx := (y * CHUNK_SIZE + x) * 4
            var mat := chunk_data[src_idx]
            var temp := chunk_data[src_idx + 2]
            material_data[y * CHUNK_SIZE + x] = mat
            if mat == MAT_WOOD and temp > IGNITION_TEMP:
                has_burning = true
    chunk.collision_dirty = has_burning

    var world_offset := chunk.coord * CHUNK_SIZE
    if chunk.static_body.get_child_count() > 0:
        for child in chunk.static_body.get_children():
            child.queue_free()

    var collision_shape := TerrainCollider.build_collision(material_data, CHUNK_SIZE, chunk.static_body, world_offset)
    if collision_shape != null:
        chunk.static_body.add_child(collision_shape)
```

- [ ] **Step 3: Commit**

```bash
git add scripts/world_manager.gd
git commit -m "feat: integrate throttling with GPU collision rebuild"
```

---

### Task 7: Test and Verify

- [ ] **Step 1: Run the game in Godot editor**

Launch the project and verify it compiles without errors.

- [ ] **Step 2: Test fire ignition**

Place fire on wood and verify:
- Collision updates occur (player can't walk through burned areas)
- FPS remains at 60 during burning
- No errors in console

- [ ] **Step 3: Verify throttling**

Monitor collision rebuilds - they should only occur every 0.3 seconds during burning, not every frame.

- [ ] **Step 4: Test chunk unloading**

Move away from burning chunks and verify no memory leaks or crashes.

- [ ] **Step 5: Commit (if fixes needed)**

If any issues are found and fixed, commit them:

```bash
git add <files>
git commit -m "fix: <description>"
```

---

## Verification Checklist

After all tasks complete:

- [ ] GPU shader compiles without errors
- [ ] Collider pipeline initializes successfully
- [ ] Storage buffer created and cleaned up properly
- [ ] Collision shapes update when wood burns
- [ ] FPS stays at 60 during burning
- [ ] No memory leaks when chunks unload
- [ ] Edge cases handled (empty chunks, borders)