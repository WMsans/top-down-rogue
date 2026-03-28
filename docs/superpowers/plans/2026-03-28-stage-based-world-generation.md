# Stage-Based World Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor world generation into a stage-based pipeline where each stage is a separate GLSL file, all orchestrated by a single shader dispatch.

**Architecture:** Create a GenerationContext struct in GDScript, move wood-fill logic to a stage file, and modify generation.glsl to include stages and receive context via push constants.

**Tech Stack:** GDScript 4.x, GLSL compute shaders, Godot RenderingDevice API

---

### Task 1: Create GenerationContext Struct

**Files:**
- Create: `scripts/generation_context.gd`

- [ ] **Step 1: Write GenerationContext class**

```gdscript
class_name GenerationContext
extends RefCounted

var chunk_coord: Vector2i
var world_seed: int
var stage_params: Dictionary = {}
```

- [ ] **Step 2: Commit**

```bash
git add scripts/generation_context.gd
git commit -m "feat: add GenerationContext struct for stage-based generation"
```

---

### Task 2: Create Stages Directory and Wood Fill Stage

**Files:**
- Create: `stages/wood_fill_stage.glsl`

- [ ] **Step 1: Create stages directory**

```bash
mkdir -p stages
```

- [ ] **Step 2: Write wood fill stage shader**

```glsl
#version 450

struct Context {
    ivec2 chunk_coord;
    uint world_seed;
};

void stage_wood_fill(Context ctx, layout(rgba8, set = 0, binding = 0) image2D chunk_tex) {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= 256 || pos.y >= 256) return;

    // Wood: material=1, health=255, temperature=0, reserved=0
    vec4 pixel = vec4(1.0 / 255.0, 1.0, 0.0, 0.0);
    imageStore(chunk_tex, pos, pixel);
}
```

- [ ] **Step 3: Commit**

```bash
git add stages/wood_fill_stage.glsl
git commit -m "feat: add wood_fill_stage.glsl"
```

---

### Task 3: Refactor generation.glsl to Use Stage

**Files:**
- Modify: `shaders/generation.glsl`

- [ ] **Step 1: Replace generation.glsl content with stage-based approach**

```glsl
#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(push_constant) uniform PushConstants {
    ivec2 chunk_coord;
    uint world_seed;
    uint padding;
} push_ctx;

layout(rgba8, set = 0, binding = 0) uniform image2D chunk_tex;

#include "res://stages/wood_fill_stage.glsl"

struct Context {
    ivec2 chunk_coord;
    uint world_seed;
};

void main() {
    Context ctx;
    ctx.chunk_coord = push_ctx.chunk_coord;
    ctx.world_seed = push_ctx.world_seed;

    stage_wood_fill(ctx, chunk_tex);
}
```

- [ ] **Step 2: Commit**

```bash
git add shaders/generation.glsl
git commit -m "refactor: generation.glsl to use stage-based pipeline"
```

---

### Task 4: Update WorldManager to Use Context and Push Constants

**Files:**
- Modify: `scripts/world_manager.gd:128-141`

- [ ] **Step 1: Add push constant buffer in world_manager.gd**

In the generation dispatch section (around line 128-141), modify the dispatch loop to add push constants:

```gdscript
# In _update_chunks(), inside the new_chunks dispatch loop (around line 131):
for coord in new_chunks:
    var chunk: Chunk = chunks[coord]
    var gen_uniform := RDUniform.new()
    gen_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
    gen_uniform.binding = 0
    gen_uniform.add_id(chunk.rd_texture)
    var uniform_set := rd.uniform_set_create([gen_uniform], gen_shader, 0)
    _gen_uniform_sets_to_free.append(uniform_set)
    rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)

    # Add push constants: chunk_coord + world_seed + padding
    var push_data := PackedByteArray()
    push_data.resize(16)
    push_data.encode_s32(0, coord.x)
    push_data.encode_s32(4, coord.y)
    push_data.encode_u32(8, 0)  # world_seed (TODO: implement seed system)
    push_data.encode_u32(12, 0)  # padding
    rd.compute_list_set_push_constant(compute_list, push_data, push_data.size())rd.compute_list_dispatch(compute_list, NUM_WORKGROUPS, NUM_WORKGROUPS, 1)
```

- [ ] **Step 2: Commit**

```bash
git add scripts/world_manager.gd
git commit -m "refactor: world_manager to use push constants for generation context"
```

---

### Task 5: Verify Generation Works

- [ ] **Step 1: Run the project and test**

Run the project in Godot and verify:
- Chunks generate correctly with wood fill
- No shader compilation errors
- No runtime errors

- [ ] **Step 2: Commit if needed**

If any fixes were required:
```bash
git add -A
git commit -m "fix: resolve generation issues"
```

---

## Files Summary

| File | Action |
|------|--------|
| `scripts/generation_context.gd` | Create |
| `stages/wood_fill_stage.glsl` | Create |
| `shaders/generation.glsl` | Modify |
| `scripts/world_manager.gd` | Modify |