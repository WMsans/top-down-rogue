# Fog of War — Design Spec

**Date:** 2026-05-06
**Type:** Feature
**Status:** Design approved

---

## Overview

Full-screen fog of war that hides entities (enemies, chests, drops, projectiles, and all future entities) in dark areas. The player's `PointLight2D` and terrain glow materials (existing chunk `PointLight2D` instances from the light pack system) clear the fog in their radius. Fog is dynamic — it returns when the light source moves away. Implementation uses a `Sprite2D` with a custom shader layered above entities in the SubViewport.

---

## Architecture

### Scene Tree Placement

The fog components live as children of the SubViewport root `Node2D` in `scenes/game.tscn`, created in code by `WorldManager`:

```
SubViewport (root Node2D / Main)
├── WorldManager (terrain chunks — rendered first)
├── BackBufferCopy           ← NEW — copies terrain to screen texture (copy_mode = VIEWPORT_RECT)
├── Player (CharacterBody2D)
│   └── PointLight2D         (player light, existing)
├── ChunkContainer           ← entities (enemies, chests, drops, projectiles) render here
├── FogSprite (Sprite2D)     ← NEW — renders above entities, shader blends terrain + fog tint
└── FogManager (Node2D)      ← NEW — collects light data, stamps fog texture
```

**Tree order is critical:** terrain renders first, `BackBufferCopy` captures it, then entities render, then `FogSprite` sits on top. In foggy areas, the shader samples the back buffer (terrain only) and tints it dark — terrain stays visible but entities are hidden. In clear areas, the shader outputs transparent — entities show through normally.

### Components

#### 1. FogSprite (`shaders/fog_of_war.gdshader` + scene node)

A full-viewport `Sprite2D` with `z_index`/tree order ensuring it renders above all game entities but below UI `CanvasLayer` nodes (which are already outside the SubViewport). Uses a custom `canvas_item` shader.

**Shader:**
```glsl
shader_type canvas_item;
uniform vec4 fog_color : source_color = vec4(0.05, 0.02, 0.08, 1.0);
uniform sampler2D fog_map : hint_default_black;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

void fragment() {
    float fog_mask = texture(fog_map, UV).r;
    if (fog_mask < 0.01) {
        // Clear area — transparent, entities show normally
        COLOR = vec4(0.0);
    } else {
        // Fog area — sample back buffer (terrain only, pre-entities), tint dark
        vec4 terrain = texture(screen_texture, SCREEN_UV);
        COLOR.rgb = mix(terrain.rgb, fog_color.rgb, fog_mask);
        COLOR.a = 1.0;
    }
}
```
- `fog_map`: single-channel vision texture — **white (1.0) = full fog**, **black (0.0) = clear**
- `fog_color`: dark near-black tint (customizable)
- `screen_texture`: `hint_screen_texture` samples the `BackBufferCopy` — captures terrain before entities rendered

#### 2. FogManager (`src/core/fog_manager.gd`)

A `Node2D` that drives the fog texture. Runs each frame:

```
_ready():
  - create fog Image + ImageTexture at viewport resolution (320×180)
  - create radial gradient light stamp texture (ImageTexture)
  - pass texture to FogSprite shader uniform
  - hold reference to Camera2D (for world→screen transforms)

_process(delta):
  1. fill fog_image with Color.WHITE (full fog)
  2. stamp player light — get player PointLight2D global_position,
     convert to screen position (global_pos - camera_offset + viewport_half_size),
     blend_rect(light_stamp, rect, screen_pos)
  3. stamp terrain glow lights — iterate terrain light data arrays
     (screen positions + energies from ChunkManager),
     blend_rect each with scale based on energy
  4. fog_texture.update(fog_image)
  5. push to FogSprite material shader uniform
```

**Data held:**
- `light_stamp`: radial gradient `ImageTexture` (64×64, white center fading to black edges)
- `fog_image`: `Image` at viewport size
- `fog_texture`: `ImageTexture`
- Camera reference for coordinate transform
- Fog color

#### 3. Terrain Light Data Exposure

**Modified files:**

| File | Change |
|---|---|
| `src/core/chunk_lights.gd` | After light pack readback, compute screen-space positions for each light cell. Store in arrays accessible to `FogManager`. |
| `src/core/chunk_manager.gd` | New method `get_visible_light_data() -> Dictionary{positions: PackedVector2Array, energies: PackedFloat32Array}` — aggregates screen-space light positions and energies from all visible chunks. |
| `src/core/world_manager.gd` | `_ready()`: create `FogSprite` and `FogManager` nodes. Pass viewport dims and camera reference. |

**Data flow:**
```
GPU light_pack compute shader
  → readback to ChunkLights
      ├──→ PointLight2D nodes (existing, shadow casting)
      └──→ screen_pos + energy arrays (new, fog stamping)
```

### Entity Visibility via BackBufferCopy

**No per-entity changes required.** The fog solution works as follows:

1. `BackBufferCopy` (placed after terrain render, before entities) captures a texture of the terrain-only framebuffer
2. Entities render on top of terrain normally
3. `FogSprite` renders last with the shader above:
   - **Foggy pixels** (`fog_mask > 0`): shader samples the back buffer (terrain pixels, no entities), dark-tints via `mix(terrain, fog_color, fog_mask)`, outputs opaque → terrain visible through fog, entities occluded
   - **Clear pixels** (`fog_mask ≈ 0`): shader outputs transparent → entities and terrain both show through normally

This ensures terrain is always visible (tinted in fog), while entities are only visible in lit areas.

---

## File Manifest

### New Files
| File | Purpose |
|---|---|
| `shaders/fog_of_war.gdshader` | Fog masking shader |
| `src/core/fog_manager.gd` | Fog texture management and light stamping |
| `textures/fog/light_stamp.png` | Radial gradient texture for blend_rect stamping |

### Modified Files
| File | Change |
|---|---|
| `src/core/world_manager.gd` | Create BackBufferCopy, FogSprite + FogManager in `_ready()` |
| `src/core/chunk_lights.gd` | Compute and store screen-space light positions |
| `src/core/chunk_manager.gd` | Expose `get_visible_light_data()` |
| `scenes/game.tscn` | Move ChunkContainer after Player in tree order (entities render after BackBufferCopy); or restructure in code |

---

## Key Design Decisions

1. **Single-texture, no persistence** — fog clears to white each frame. Dynamic visibility radius only. No accumulation/averaging.
2. **Terrain glow lights only** — only the existing chunk `PointLight2D` instances from the light pack system clear fog (plus player light). Entity-attached lights do not.
3. **BackBufferCopy for terrain preservation** — a `BackBufferCopy` node captures terrain before entities render. The fog shader samples this back buffer in foggy pixels, so terrain remains visible (dark-tinted) while entities are hidden. No per-entity visibility toggling needed.
4. **blend_rect stamping** — per-light stamping of a radial gradient into the fog image each frame, iterating the terrain light data array.
5. **Light data reused from light pack** — the fog system reads the already-computed light pack readback data (positions + energies), avoiding duplicate GPU computation.

---

## Verification Criteria

- [ ] Terrain is always visible (dark-tinted in fog, normal in clear areas)
- [ ] Enemies, chests, drops, and projectiles are hidden inside fog
- [ ] Player light clears fog in a radius around the player
- [ ] Terrain glow materials (lava, glowing walls) clear fog at their positions
- [ ] Fog returns when the player/light source moves away
- [ ] UI elements (health, currency, weapons) render normally above fog
- [ ] No frame drops introduced (fog stays within performance budget of blend_rect + single stamp loop)
- [ ] Works with the 5-frame light dispatch cycle (lights update smoothly)
