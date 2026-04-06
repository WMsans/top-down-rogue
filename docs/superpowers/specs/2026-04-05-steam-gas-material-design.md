# Steam Gas Material - Design Specification

**Date:** 2026-04-05  
**Status:** Draft  
**Purpose:** Proof of concept for gas physics in the chunk-based world system

---

## Overview

Add a new material type `STEAM_GAS` to the existing material system with GPU-based cellular automata simulation. Gas spreads through the world, is blocked by solid materials, and is displaced by moving rigidbodies. This serves as a proof of concept for future gas types (hazards, visual effects, strategic elements).

---

## Goals

- Gas simulation runs in all loaded chunks (full-world active)
- Maintains 60+ FPS performance
- Gas interacts with rigidbodies (blocked by position, displaced by movement)
- Multiple rigidbodies with different shapes supported
- Extensible to future gas types with different behaviors

---

## Architecture

### Data Storage

Gas is stored in the existing chunk texture system alongside other materials.

#### Material Texture (RGBA8, 256x256 per chunk)

| Channel | Solid Materials | Gas Materials |
|---------|-----------------|---------------|
| R | Material ID | Material ID (MAT_STEAM_GAS) |
| G | Health | Density (0-255) |
| B | Temperature | Temperature |
| A | Unused | Packed velocity |

#### Occupancy Texture (R8, 256x256 per chunk)

| Channel | Value |
|---------|-------|
| R | 0 = free, 255 = blocked by rigidbody |

Updated each frame to reflect rigidbody positions.

---

### Velocity Packing

Packed into a single byte (channel A):

```
vx: [-8, +8] → encoded as 0-15 (4 bits)
vy: [-8, +8] → encoded as 0-15 (4 bits)
packed = (encoded_vx << 4) | encoded_vy
```

---

### Components

#### 1. Material Registry Extension

Add `STEAM_GAS` to `MaterialRegistry`:
- `id`: auto-assigned
- `is_gas`: true
- `has_collider`: false
- `flammable`: false

#### 2. Occupancy Manager

GDScript node that tracks rigidbodies and updates occupancy textures:
- Maintains list of registered rigidbodies
- Each frame: rasterize rigidbody shapes to occupancy textures
- Upload to GPU via `RenderingDevice.texture_update()`

#### 3. Gas Simulation Shader

GLSL compute shader similar to existing `simulation.glsl`:
- Runs on all loaded chunks
- Even/odd phase dispatch (checkerboard pattern)
- Reads: material texture, occupancy texture, neighbor textures
- Operations: advection, diffusion, occupancy blocking, velocity decay
- Writes: updated material texture

#### 4. Gas Renderer

Extend `render_chunk.gdshader` to render gas materials:
- Density drives opacity
- Velocity drives flow animation
- Temperature tint overlay
- Layer ordering: above ground, below wall faces

---

## Data Flow

```
Frame N:
  1. Physics Update
     └─ Godot physics updates rigidbody positions

  2. Occupancy Update (parallel)
     └─ OccupancyManager rasterizes rigidbody shapes
     └─ Upload occupancy textures to GPU

  3. Gas Simulation (GPU compute)
     └─ Even phase: update checkerboard pixels
     └─ Odd phase: update remaining pixels
     └─ Advection: move gas by velocity
     └─ Diffusion: spread to neighbors
     └─ Blocking: can't enter solid/occupied cells
     └─ Displacement: push gas from occupied cells
     └─ Decay: reduce velocity over time

  4. Fire/Other Simulation (GPU compute)
     └─ Existing simulation continues for non-gas materials

  5. Rendering
     └─ Gas rendered with density-based opacity
     └─ Flow animation based on velocity + TIME
```

---

## Gas Simulation Algorithm

### Simulation Pass (per gas pixel)

```
READ PHASE:
  density = pixel.g
  temp = pixel.b
  packed_vel = pixel.a
  (vx, vy) = unpack_velocity(packed_vel)

ADVECTION:
  prev_pos = pos - vec2(vx, vy) * dt
  sampled = bilinear_sample_previous(prev_pos)
  new_density = sampled.g
  new_packed_vel = sampled.a

DIFFUSION:
  diffusion_rate = 0.1
  for neighbor in [up, down, left, right]:
    if not blocked(occupancy, material):
      transfer = density * diffusion_rate * dt
      neighbor_density += transfer
      density -= transfer

DISPLACEMENT:
  if occupancy_changed:
    push_dir = calculate_push_direction(occupancy_delta)
    vx += push_dir.x * push_force
    vy += push_dir.y * push_force

VELOCITY DECAY:
  vx *= 0.98
  vy *= 0.98

WRITE PHASE:
  pixel.g = clamp(new_density + density, 0, 255)
  pixel.a = pack_velocity(vx, vy)
```

---

## Rendering

### Fragment Shader

```glsl
if (mat == MAT_STEAM_GAS) {
  float density = data.g;
  float temp = data.b;
  vec2 velocity = unpack_velocity(data.a);
  
  float opacity = density / 255.0 * 0.7;
  float flow_distortion = sin(TIME * 2.0 + px.x * 0.1 + velocity.x * 5.0) * 0.05;
  
  vec3 base_color = vec3(0.85, 0.87, 0.9);
  vec3 color = base_color + get_temperature_tint(temp, px);
  
  COLOR = vec4(color, opacity);
}
```

### Layer Ordering

| Layer | Z-index | Position |
|-------|---------|----------|
| Ground (wall tops) | 0 | Solid material tops |
| Gas | - | Overlay, above ground |
| Wall Faces | 1 | Vertical extensions, obscure gas |

Gas is visible above wall tops but behind wall faces.

---

## Edge Cases

### Chunk Boundaries
- Gas at chunk edges samples from neighbor textures
- Velocity carries gas across chunk boundaries naturally
- No special handling needed (same as fire simulation)

### Gas vs Material Boundaries
- Gas cannot enter cells where `HAS_COLLIDER[material] == true`
- Gas can only occupy AIR cells
- When gas hits solid material, it accumulates and velocity reflects/reverses

### Density Limits
- Max density: 255 (saturation)
- Min density: 0 (dissipates to AIR)
- When density reaches 0, material reverts to AIR

---

## Implementation

### Modified Files

| File | Changes |
|------|---------|
| `scripts/material_registry.gd` | Add STEAM_GAS material, is_gas flag |
| `tools/generate_material_glsl.gd` | Generate is_gas array in GLSL |
| `shaders/simulation.glsl` | Add gas simulation pass |
| `shaders/render_chunk.gdshader` | Render gas material |
| `scripts/world_manager.gd` | Add occupancy textures, place_gas(), occupancy manager |
| `scripts/chunk.gd` | Add occupancy_texture field |
| `scripts/input_handler.gd` | Replace fire placement with gas placement |

### New Files

| File | Purpose |
|------|---------|
| `scripts/occupancy_manager.gd` | Track rigidbodies, rasterize to occupancy textures |

### Implementation Notes

- Gas simulation is integrated into existing `simulation.glsl` (not a separate shader)
- Occupancy rasterization implemented in GDScript initially (can optimize to compute shader later ifneeded)
- Follows existing pattern: even/odd phase dispatch for all simulations together

---

## Testing

### Unit Tests
- Velocity packing/unpacking: round-trip accuracy
- Occupancy update: AABB correctly marks cells

### Integration Tests
- Gas placed in empty space: spreads outward, slows down
- Gas placed near wall: blocked by solid material
- Gas with initial velocity: moves in direction before spreading
- Rigidbody moves through gas: displaced to sides
- Gas crosses chunk boundaries smoothly

### Visual Verification
- Gas opacity matches density
- Gas flows visibly based on velocity
- Gas blocked by walls and wall faces
- No visible seams at chunk edges

---

## Future Extensions

- **Multiple gas types**: Different densities, spread rates, colors
- **Gas emitters**: Scene nodes that spawn gas continuously
- **Gas interactions**: Different gases react (e.g., fire + steam = water)
- **Temperature effects**: Hot gas rises, cold gas sinks
- **GPU occupancy**: Use compute shader for faster rasterization