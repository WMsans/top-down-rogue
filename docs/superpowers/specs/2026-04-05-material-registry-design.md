# Material Registry System Design

## Overview

A centralized material definition system that makes adding new materials easy. Materials are defined once in a GDScript registry, and shader constants are auto-generated from it.

## Problem

Currently, materials are hardcoded across multiple files:
- `world_manager.gd`: constants `MAT_AIR=0`, `MAT_WOOD=1`, `MAT_STONE=2`
- `simulation.glsl`: hardcoded `MAT_WOOD` burning logic
- `render_chunk.gdshader`: hardcoded material IDs
- Generation stages: hardcoded material IDs
- Texture paths hardcoded in `_init_material_textures()`
- No per-material configurability (flammable, collider, wall extension)

Adding a new material requires editing 5+ files and coordinating IDs manually.

## Solution

### Architecture

Three components:

1. **MaterialRegistry.gd** (Autoload singleton)
   - Array-based material definitions where array index = material ID
   - Properties: `name`, `texture_path`, `flammable`, `has_collider`, `has_wall_extension`, `ignition_temp`, `burn_health`
   - Exports constants for GDScript: `MAT_WOOD`, `MAT_AIR`, etc.
   - Helper methods: `is_flammable(id)`, `get_ignition_temp(id)`

2. **generate_material_glsl.gd** (Editor script)
   - Reads registry, generates `shaders/generated/materials.glslinc`
   - Outputs constants and property arrays

3. **materials.glslinc** (Generated file, committed to repo)
   - Included by shaders
   - Provides `MAT_*` constants and `IS_FLAMMABLE[]`, `HAS_COLLIDER[]`, etc.

### Material Registry Structure

```gdscript
# scripts/material_registry.gd
extends Node

class MaterialDef:
    var id: int                    # Index in array (auto-assigned)
    var name: String               # "WOOD", "STONE", "AIR"
    var texture_path: String       # Path to texture or empty
    var flammable: bool            # Can catch fire
    var ignition_temp: int         # 0-255 temperature threshold
    var burn_health: int           # Frames until consumed
    var has_collider: bool         # Generates collision
    var has_wall_extension: bool   # Shows vertical face

var materials: Array[MaterialDef] = []

func _ready():
    _init_materials()

func _init_materials():
    materials.append(MaterialDef.new(
        "AIR", "", false, 0, 0, false, false))
    materials.append(MaterialDef.new(
        "WOOD", "res://textures/PixelTextures/plank.png",
        true, 180, 255, true, true))
    materials.append(MaterialDef.new(
        "STONE", "res://textures/PixelTextures/stone.png",
        false, 0, 0, true, true))
    
    for m in materials:
        set("MAT_" + m.name, m.id)
```

### Generated GLSL Output

```glsl
// shaders/generated/materials.glslinc
// Auto-generated from MaterialRegistry. DO NOT EDIT.

const int MAT_AIR = 0;
const int MAT_WOOD = 1;
const int MAT_STONE = 2;
const int MAT_COUNT = 3;

const bool IS_FLAMMABLE[MAT_COUNT] = bool[MAT_COUNT](
    false, true, false
);

const bool HAS_COLLIDER[MAT_COUNT] = bool[MAT_COUNT](
    false, true, true
);

const bool HAS_WALL_EXTENSION[MAT_COUNT] = bool[MAT_COUNT](
    false, true, true
);

const int IGNITION_TEMP[MAT_COUNT] = int[MAT_COUNT](
    0, 180, 0
);

const int BURN_HEALTH[MAT_COUNT] = int[MAT_COUNT](
    0, 255, 0
);
```

### Shader Usage

**simulation.glsl:**
```glsl
#include "res://shaders/generated/materials.glslinc"

// Replace: if (material == MAT_WOOD && temperature > IGNITION_TEMP)
if (IS_FLAMMABLE[material] && temperature > IGNITION_TEMP[material]) {
    health = health - 1;
    temperature = FIRE_TEMP;
    if (health <= 0) {
        material = MAT_AIR;
    }
}
```

**collider.glsl:**
```glsl
#include "res://shaders/generated/materials.glslinc"

uint tl_mat = tl_sample.r;
uint tl = HAS_COLLIDER[tl_mat] ? 1u : 0u;
// Same for tr, br, bl
```

**render_chunk.gdshader:**
```glsl
#include "res://shaders/generated/materials.glslinc"

// Use HAS_WALL_EXTENSION[] for wall face rendering
```

**generation stages:**
```glsl
#include "res://shaders/generated/materials.glslinc"
vec4 pixel = vec4(float(MAT_STONE) / 255.0, 1.0, 0.0, 0.0);
```

### Code Generator

```gdscript
# tools/generate_material_glsl.gd
extends SceneTree

func _init():
    var registry = preload("res://scripts/material_registry.gd").new()
    registry._ready()
    
    var output := "# Auto-generated from MaterialRegistry. DO NOT EDIT.\n\n"
    output += "const int MAT_COUNT = %d;\n\n" % registry.materials.size()
    
    for m in registry.materials:
        output += "const int MAT_%s = %d;\n" % [m.name, m.id]
    output += "\n"
    
    # Generate property arrays...
    
    var file = FileAccess.open(
        "res://shaders/generated/materials.glslinc", FileAccess.WRITE)
    file.store_string(output)
    print("Generated materials.glslinc")
```

### Build Script

```bash
#!/bin/bash
# generate_materials.sh
godot --headless --script tools/generate_material_glsl.gd
```

### Texture Loading

```gdscript
# world_manager.gd
func _init_material_textures() -> void:
    var images: Array[Image] = []
    for m in MaterialRegistry.materials:
        if m.texture_path.is_empty():
            images.append(TextureArrayBuilder.create_placeholder_image(
                Vector2i(16, 16), Color.TRANSPARENT))
        else:
            images.append(Image.load_from_file(m.texture_path))
    material_textures = TextureArrayBuilder.build_from_images(images)
```

### Texture Convention

- Textures named by material in lowercase: `wood.png`, `stone.png`
- Registry paths: `res://textures/PixelTextures/{name}.png`
- Empty `texture_path` for materials without textures (AIR)

### world_manager.gd Changes

**Remove:**
- Constants `MAT_AIR`, `MAT_WOOD`, `MAT_STONE`
- Hardcoded texture paths
- Hardcoded `IGNITION_TEMP`, `MAX_TEMPERATURE`

**Replace with:**
- Reference `MaterialRegistry.MAT_*` constants
- Iterate `MaterialRegistry.materials` for flammability checks
- Use registry values for ignition temperature

### Adding a New Material

1. Add entry to `MaterialRegistry._init_materials()`:
   ```gdscript
   materials.append(MaterialDef.new(
       "IRON", "res://textures/PixelTextures/iron.png",
       false, 0, 0, true, true))
   ```

2. Add texture to `textures/PixelTextures/iron.png`

3. Run `./generate_materials.sh`

4. Shaders automatically include updated constants

## Files Changed/Added

**Added:**
- `scripts/material_registry.gd` — Autoload singleton
- `tools/generate_material_glsl.gd` — Code generator
- `generate_materials.sh` — Build script
- `shaders/generated/materials.glslinc` — Generated output

**Modified:**
- `project.godot` — Register MaterialRegistry as autoload
- `scripts/world_manager.gd` — Remove hardcoded materials, use registry
- `shaders/simulation.glsl` — Use `IS_FLAMMABLE[]`, `IGNITION_TEMP[]`
- `shaders/collider.glsl` — Use `HAS_COLLIDER[]`
- `shaders/render_chunk.gdshader` — Use `HAS_WALL_EXTENSION[]`
- `stages/stone_fill_stage.glslinc` — Use `MAT_STONE`
- `stages/wood_fill_stage.glslinc` — Use `MAT_WOOD`

## Benefits

1. **Single source of truth** — Materials defined in one place
2. **Per-material properties** — Flammability, collision, wall extension configurable
3. **Type-safe shader constants** — Generated file ensures GDScript/shader sync
4. **Easy addition** — Add material in registry, run generator, done
5. **Backwards compatible** — Existing MAT_AIR, MAT_WOOD constants still available via registry