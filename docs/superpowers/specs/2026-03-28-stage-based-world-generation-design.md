# Stage-Based World Generation Design

## Overview

Refactor world generation from a single shader to a stage-based pipeline where each stage is defined in a separate GLSL file, but all stages are executed by a single shader dispatch from GDScript.

## Goals

- Modularize generation logic into separate stage files
- Maintain GPU performance (single dispatch)
- Enable easy addition of new generation stages
- Pass context between stages via push constants

## Architecture

### File Structure

```
scripts/
  generation_context.gd      # Context struct definition
stages/
  wood_fill_stage.glsl       # Wood filling stage (initial stage)
shaders/
  generation.glsl            # Main shader including all stages
```

### Components

#### 1. GenerationContext (GDScript)

**File:** `scripts/generation_context.gd`

Context struct passed to the shader via push constants:

```gdscript
class_name GenerationContext
var chunk_coord: Vector2i
var world_seed: int
var stage_params: Dictionary  # Reserved for future stage parameters
```

#### 2. Stage Files (GLSL)

**Directory:** `stages/`

Each stage is a separate GLSL file defining a function that modifies the chunk texture:

- `wood_fill_stage.glsl` - Fills chunk with wood material

Stage function signature:
```glsl
void stage_<name>(Context ctx);
```

#### 3. Main Generation Shader

**File:** `shaders/generation.glsl`

Includes all stage files and calls them in sequence:

```glsl
#[compute]
#version 450

#include "stages/wood_fill_stage.glsl"

// Push constants for context
layout(push_constant) uniform PushConstants {
    ivec2 chunk_coord;
    uint world_seed;
    uint padding;
} ctx;

void main() {
    stage_wood_fill(ctx);
}
```

## Implementation Details

### Push Constant Layout

| Offset | Type | Field |
|--------|------|-------|
| 0 | ivec2 | chunk_coord |
| 8 | uint | world_seed |
| 12 | uint | padding (alignment) |

Size: 16 bytes

### Stage Execution Order

Stages execute in the order they are called in `generation.glsl`:
1. `stage_wood_fill` (current, only stage)

Future stages would be added to this sequence.

### Adding New Stages

1. Create new `stages/<name>_stage.glsl` file
2. Define `stage_<name>` function
3. Add `#include` statement to `generation.glsl`
4. Call the stage function in `main()`

## Migration Path

### Current State

- Single shader `shaders/generation.glsl` with inline wood fill logic
- No context struct
- Hardcoded parameters

### Target State

- `scripts/generation_context.gd` defines context
- `stages/wood_fill_stage.glsl` contains wood fill logic
- `shaders/generation.glsl` includes and orchestrates stages
- `world_manager.gd` creates context and dispatches shader

## Testing

- Verify generated chunks match original wood-fill behavior
- Confirm single shader dispatch (performance unchanged)
- Test chunk coordinate correctly via push constants