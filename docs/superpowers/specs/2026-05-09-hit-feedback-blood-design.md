# Hit Feedback & Blood Design

## Overview

Add strong visual feedback when enemies take damage: wire the existing hit-flash and squash animations (already implemented but never invoked), and spawn terrain-fluid blood at the impact point that bursts outward with high initial velocity — reusing the existing lava fluid simulation pipeline with `damage=0` and `glow=0`.

## Problem

Currently, hitting an enemy produces no per-enemy feedback. The `HitReaction` autoload creates sparks, damage numbers, screen shake, chromatic flash, and hit-stop at the impact point — but the enemy sprite itself does not react. Additionally, there is no blood or lasting terrain evidence of combat.

The enemy base class already has `_play_hit_flash()` (white modulate tween-back) and `_play_squash()` (horizontal squash → elastic spring-back) implemented, but they are stitched to `_on_hit()` which is defined and never called.

## Solution

### 1. Wire Existing Flash & Squash

In `Enemy.hit()`, add one line calling `_on_hit()` after the `health_changed` emission and before the death check. No new flash/squash code needed.

### 2. New BLOOD Material

Define `MAT_BLOOD` in `MaterialRegistry` following the lava pattern:

| Property | Value | Notes |
|----------|-------|-------|
| name | `"BLOOD"` | |
| flammable | `false` | |
| has_collider | `false` | Fluid only |
| tint_color | `Color(0.8, 0.05, 0.05, 1.0)` | Dark red |
| fluid | `true` | Hooks into sim pipeline |
| damage | `0` | No burning damage |
| glow | `0.0` | No light emission |

Key difference from lava: `damage=0`, `glow=0.0`, and temperature is always 0 at placement. Blood is a pure visual fluid.

### 3. Blood Fluid Simulation (`shaders/include/sim/blood.glslinc`)

New shader include providing pack/unpack helpers and a `simulate_blood()` entry point. Blood uses the same data layout as lava (material in R, density in G, velocity packed in A), but the B channel is unused (temperature = 0 always).

Functions:
- `get_density_blood(p)` — reads density from G channel
- `unpack_velocity_blood(p)` — decodes 2× 4-bit signed velocity from A channel
- `pack_blood(density, vel)` — encodes BLOOD pixel with zero temperature
- `blood_advect_pull(...)` — velocity advection identical to `lava_advect_pull` minus all temperature logic
- `simulate_blood(...)` — entry point: processes `MAT_BLOOD` cells and `MAT_AIR` cells with blood neighbors

Solid collision: treats everything except `MAT_AIR` and `MAT_BLOOD` as solid for blood (same wall-reflection behavior as lava).

### 4. Simulation Integration (`shaders/compute/simulation.glsl`)

Add blood include and dispatch line in priority order (above gas, below lava):

```glsl
#include "res://shaders/include/sim/blood.glslinc"

// In main():
if (simulate_lava(pos, pixel, material, n_up, n_down, n_left, n_right)) return;
if (simulate_blood(pos, pixel, material, n_up, n_down, n_left, n_right)) return;  // NEW
if (simulate_gas(pos, pixel, material, n_up, n_down, n_left, n_right))  return;
```

### 5. Render Integration (`shaders/visual/render_chunk.gdshader`)

Extend the fluid overlay check to include `MAT_BLOOD`:

```glsl
if (mat == MAT_GAS || mat == MAT_LAVA || mat == MAT_BLOOD) {
    vec4 tint = MATERIAL_TINT[mat];
    fluid_tint = vec4(tint.rgb * MATERIAL_GLOW[mat], 1.0);
    fluid_alpha = mix(0.25, tint.a, data.g);
    mat = MAT_AIR;
}
```

Since `MATERIAL_GLOW[MAT_BLOOD] = 0.0`, blood renders with its tint color but without glow multiplication (`tint.rgb * 0.0`) — meaning blood appears as the tint's alpha over the background. We factor the tint alpha through `fluid_alpha` for visibility.

**Correction:** Because `glow=0`, the product `tint.rgb * MATERIAL_GLOW[mat]` would be black. The render shader needs a special case for BLOOD (or glow should be 1.0). Use `glow=1.0` so blood renders at full tint intensity — the word "glow" is a misnomer here; it's the intensity multiplier for fluid tint.

### 6. Blood Placement API

New `place_blood()` API following the `place_lava()` delegation chain:

**`TerrainSurface.place_blood(world_pos, radius, outward_speed)`** — delegates to adapter.

**`WorldManager.place_blood(world_pos, radius, outward_speed)`** — delegates to `TerrainModifier`.

**`TerrainModifier.place_blood(world_pos, radius, outward_speed)`** — core implementation:
- Circle-sweep for air cells (same loop as `place_lava()`)
- Places `MAT_BLOOD` with `density=200`, `temperature=0`
- Per-pixel outward radial velocity from center, scaled by `outward_speed`, encoded as `(vx+8)<<4 | (vy+8)`
- Invalidates terrain physical rect for the affected area

### 7. Spawn Blood on Hit

In `Enemy.on_hit_impact()`, call `TerrainSurface.place_blood(impact_point, 6.0, 120.0)` after `HitReaction.play(spec)` and before `hit(damage)`, so the blood splatter occurs on every hit including killing blows.

### 8. Regenerate Material GLSL

After adding `MAT_BLOOD` to the registry, run the generator tool to update `shaders/generated/materials.glslinc` and `shaders/generated/materials.gdshaderinc`:

```bash
godot --headless --script res://tools/generate_material_glsl.gd
```

This auto-generates `MAT_BLOOD`, `MAT_COUNT`, `MATERIAL_TINT`, `MATERIAL_GLOW`, etc. — no manual GLSL constant editing needed.

### Data Flow

```
Weapon.use(user)
  └─► Enemy.on_hit_impact(impact_point, hit_dir, damage)
        ├─► HitReaction.play(spec)                    # sparks, numbers, shake, flash, hitstop
        ├─► TerrainSurface.place_blood(point, 6.0, 120.0)
        │     └─► WorldManager.place_blood()
        │           └─► TerrainModifier.place_blood()
        │                 ├─ For each air pixel in circle: BLOOD + density=200 + temp=0 + radial_vel
        │                 └─► invalidate terrain physical rect
        └─► hit(damage)
              ├─ health -= damage
              ├─ health_changed.emit(...)
              ├─ _on_hit()                             # ← NEW: flash + squash
              └─ if dead: die()
```

Blood fluid then lives autonomously through the compute shader pipeline: advection spreads it, dissipation fades it, render shader composites it.

## Files Changed

| File | Change |
|---|---|
| `src/autoload/material_registry.gd` | Add `MAT_BLOOD` constant, append BLOOD `MaterialDef` |
| `src/core/terrain_surface.gd` | Add `place_blood(world_pos, radius, outward_speed)` delegate |
| `src/core/terrain_modifier.gd` | Add `place_blood(world_pos, radius, outward_speed)` with per-pixel radial velocity |
| `src/core/world_manager.gd` | Add `place_blood(world_pos, radius, outward_speed)` adapter |
| `src/enemies/enemy.gd` | Call `_on_hit()` in `hit()`, call `TerrainSurface.place_blood()` in `on_hit_impact()` |
| `shaders/include/sim/blood.glslinc` | **New** — blood pack/unpack helpers + `simulate_blood()` advection |
| `shaders/include/sim/common.glslinc` | Add `THRESHOLD_BECOME_BLOOD` constant |
| `shaders/compute/simulation.glsl` | Add blood include + dispatch call |
| `shaders/visual/render_chunk.gdshader` | Add `MAT_BLOOD` to fluid overlay check |
| `shaders/generated/materials.glslinc` | Regenerate after registry change |
| `shaders/generated/materials.gdshaderinc` | Regenerate after registry change |

## Tuning Constants

| Constant | Value | File | Meaning |
|----------|-------|------|---------|
| Blood placement radius | 6.0 | enemy.gd | Circle radius for blood terrain pixels |
| Outward burst speed | 120.0 | enemy.gd | Radial velocity scale on spawn |
| Initial density | 200 | terrain_modifier.gd | Starting blood density (0-255) |
| Initial temperature | 0 | terrain_modifier.gd | Blood has no temperature |
| `THRESHOLD_BECOME_BLOOD` | 1 | common.glslinc | Min inflow for AIR → BLOOD |
| `MATERIAL_GLOW[MAT_BLOOD]` | 1.0 | material_registry.gd | Tint intensity (not actual glow) |

## Out of Scope

- Blood color variation (arterial vs venous)
- Blood pooling/staining on walls
- Blood splatter on player
- Directional blood arc (currently radial burst from point)
- GPU particles complementing terrain fluid
