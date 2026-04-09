# Lava Material Design

## Overview

A new `MAT_LAVA` material that flows like gas (velocity-based advection, wall reflection, rigidbody interaction) but does not diffuse, has variable temperature that spreads heat to neighbors, and dissipates to AIR when density drops below threshold.

## Problem

The gas material demonstrates fluid-like behavior with diffusion. Lava should flow with velocity but maintain its density distribution (no diffusion), be hot enough to ignite flammable materials, and behave as a first-class material in the simulation.

## Solution

### Data Layout

Lava reuses the existing `rgba8` chunk texture. For cells whose R-channel holds `MAT_LAVA`, the other channels are:

| Channel | Non-lava cells   | Lava cells                                    |
|---------|------------------|-----------------------------------------------|
| R       | material id      | `MAT_LAVA`                                    |
| G       | health (solids)  | **density** (0–255)                           |
| B       | temperature      | **temperature** (0–255, variable)            |
| A       | 0 (unused)       | **packed velocity** `(vx+8)<<4 \| (vy+8)`    |

Velocity range is `vx, vy ∈ [-8, 7]` peraxis (4 bits each), same as gas.

**Shader helpers (added to `simulation.glsl`):**

```glsl
int get_density_lava(vec4 p) { return int(round(p.g * 255.0)); }
int get_temperature_lava(vec4 p) { return int(round(p.b * 255.0)); }

ivec2 unpack_velocity_lava(vec4 p) {
    uint a = uint(round(p.a * 255.0));
    return ivec2(int(a >> 4) - 8, int(a & 15u) - 8);
}

vec4 pack_lava(int density, int temperature, ivec2 vel) {
    int vx = clamp(vel.x + 8, 0, 15);
    int vy = clamp(vel.y + 8, 0, 15);
    uint a = (uint(vx) << 4) | uint(vy);
    return vec4(
        float(MAT_LAVA) / 255.0,
        float(clamp(density, 0, 255)) / 255.0,
        float(clamp(temperature, 0, 255)) / 255.0,
        float(a) / 255.0
    );
}
```

### Registry Entry

`MaterialDef` entry for lava:

```gdscript
var mat_lava := MaterialDef.new(
    "LAVA", "",
    false, 150, 255,# not flammable, ignition temp (unused), burn health (unused)
    false, false,# no collider, no wall extension
    Color(0.9, 0.4, 0.1, 1.0)  # orange-red tint
)
mat_lava.id = materials.size()
materials.append(mat_lava)
MAT_LAVA = mat_lava.id
```

The `IGNITION_TEMP` and `BURN_HEALTH` values are set but unused since lava is not flammable. Temperature behavior is handled separately in the simulation.

The GLSL generator extends the arrays:

```glsl
const int MAT_COUNT = 5;

const int MAT_LAVA = 4;

const vec4 MATERIAL_TINT[5] = vec4[5](
    vec4(0.0, 0.0, 0.0, 0.0),   // AIR
    vec4(0.0, 0.0, 0.0, 0.0),   // WOOD
    vec4(0.0, 0.0, 0.0, 0.0),   // STONE
    vec4(0.4, 0.9, 0.3, 1.0),   // GAS
    vec4(0.9, 0.4, 0.1, 1.0)    // LAVA
);
```

### Simulation — Unified Fluid Advection

Both GAS and LAVA share a single `fluid_advect_pull` function that runs every frame before the burning phase. The function handles both materials with conditional logic for their differences (diffusion for gas only, temperature for lava only).

**Simulation flow in `main()`:**

Fluid materials (GAS, LAVA) and AIR are handled in a unified `fluid_advect_pull` that dispatches to the appropriate logic based on material type:

```glsl
void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= CHUNK_SIZE || pos.y >= CHUNK_SIZE) return;

    vec4 pixel = imageLoad(chunk_tex, pos);
    int material = get_material(pixel);

    // 1. Rigidbody AABB injection — writes and returns if injected.
    if (try_inject_rigidbody_velocity(pos, material, pixel)) return;

    // 2. Fluid advection (GAS, LAVA, AIR) — runs every frame.
    vec4 n_up= read_neighbor(pos + ivec2(0, -1));
    vec4 n_down  = read_neighbor(pos + ivec2(0,  1));
    vec4 n_left  = read_neighbor(pos + ivec2(-1, 0));
    vec4 n_right = read_neighbor(pos + ivec2( 1, 0));

    if (material == MAT_GAS || material == MAT_LAVA || material == MAT_AIR) {
        fluid_advect_pull(pos, pixel, n_up, n_down, n_left, n_right);
        return;
    }

    // 3. Existing checkerboard burning logic (unchanged).
    if ((pos.x + pos.y) % 2 != pc.phase) return;
    // ... existing heat/burning code ...
}
```
```

**`fluid_advect_pull` function — unified handler:**

Both GAS and LAVA share the advection core (outflow/inflow, wall reflection, velocity damping). The function dispatches based on material type:

1. **Outflow/inflow** — computed for both materials identically
2. **Diffusion** — applies only to GAS, skipped for LAVA
3. **Temperature** — tracked for LAVA only (GAS uses B=0)
4. **Dissipation** — both materials revert to AIR below threshold

```glsl
void fluid_advect_pull(
    ivec2 pos, vec4 pixel,
    vec4 n_up, vec4 n_down, vec4 n_left, vec4 n_right
) {
    int material = get_material(pixel);
    bool is_gas = (material == MAT_GAS);
    bool is_lava = (material == MAT_LAVA);
    bool is_air = (material == MAT_AIR);

    // Neighbor material types
    int n_mat_up    = get_material(n_up);
    int n_mat_down  = get_material(n_down);
    int n_mat_left  = get_material(n_left);
    int n_mat_right = get_material(n_right);

    // Fast path: AIR with no fluid neighbors.
    bool any_fluid_neighbor =
        n_mat_up == MAT_GAS || n_mat_up == MAT_LAVA ||
        n_mat_down == MAT_GAS || n_mat_down == MAT_LAVA ||
        n_mat_left == MAT_GAS || n_mat_left == MAT_LAVA ||
        n_mat_right == MAT_GAS || n_mat_right == MAT_LAVA;

    if (is_air && !any_fluid_neighbor) {
        int health = get_health(pixel);
        int temperature = max(0, get_temperature(pixel) - HEAT_DISSIPATION);
        imageStore(chunk_tex, pos, make_pixel(MAT_AIR, health, temperature));
        return;
    }

    // --- Own state ---
    int density = 0;
    int temperature = 0;
    ivec2 vel = ivec2(0);

    if (is_gas) {
        density = get_density(pixel);
        vel = unpack_velocity(pixel);
    } else if (is_lava) {
        density = get_density_lava(pixel);
        temperature = get_temperature_lava(pixel);
        vel = unpack_velocity_lava(pixel);
    }

    // --- Outflow computation (same for both) ---
    // ... velocity components, wall reflection, outflow calculation ...

    // --- Inflow computation (same for both) ---
    // ... pull density from GAS or LAVA neighbors ...

    // --- Diffusion (GAS ONLY) ---
    int diff_out = 0;
    int diff_in = 0;
    if (is_gas) {
        // ... existing diffusion logic from gas_advect_pull ...
    }

    // --- New density ---
    int new_density = density - total_out + total_in - diff_out + diff_in;
    new_density = clamp(new_density, 0, 255);

    // --- New velocity (same damping for both) ---
    // ... velocity-weighted average, 15/16 damping ...

    // --- Temperature decay (LAVA ONLY) ---
    if (is_lava) {
        temperature = max(0, temperature - HEAT_DISSIPATION);
    }

    // --- Material transitions ---
    if (is_air) {
        // Determine which fluid type "wins" based on inflow composition
        int gas_in = /* sum of inflow from GAS neighbors */;
        int lava_in = /* sum of inflow from LAVA neighbors */;

        if (gas_in >= THRESHOLD_BECOME_GAS || lava_in >= THRESHOLD_BECOME_LAVA) {
            // Material is determined by majority inflow
            if (gas_in >= lava_in) {
                // Become GAS
                imageStore(chunk_tex, pos, pack_gas(gas_in + lava_in, inflow_vel));
            } else {
                // Become LAVA (temperature starts at 0)
                imageStore(chunk_tex, pos, pack_lava(lava_in + gas_in, 0, inflow_vel));
            }
            return;
        }
        // Stay air
        int health = get_health(pixel);
        int temp = max(0, get_temperature(pixel) - HEAT_DISSIPATION);
        imageStore(chunk_tex, pos, make_pixel(MAT_AIR, health, temp));
        return;
    }

    // GAS or LAVA
    if (new_density < THRESHOLD_DISSIPATE) {
        imageStore(chunk_tex, pos, make_pixel(MAT_AIR, 0, 0));
        return;
    }

    if (is_gas) {
        imageStore(chunk_tex, pos, pack_gas(new_density, new_vel));
    } else {
        imageStore(chunk_tex, pos, pack_lava(new_density, temperature, new_vel));
    }
}
```

### Temperature Propagation

Lava cells participate in the existing burning system as heat sources. The burning logic in `main()` is modified to check for lava neighbors in addition to burning neighbors:

```glsl
// In the burning phase, check for hot lava neighbors
if (n_mat_up == MAT_LAVA) {
    int lava_temp = get_temperature_lava(n_up);
    if (lava_temp >IGNITION_TEMP[material]) {
        heat_gain += lava_temp / 4;  // quarter of lava temp spreads
    }
}
// ... same for other neighbors ...
```

Lava temperature decays by `HEAT_DISSIPATION` each frame but is never consumed by burning.

### Rigidbody Injection

Lava participates in the same rigidbody injection system as gas. The `try_inject_rigidbody_velocity` function is extended:

```glsl
bool try_inject_rigidbody_velocity(ivec2 pos, int material, inout vec4 pixel) {
    if (material != MAT_GAS && material != MAT_LAVA) return false;
    // ... existing injection logic, now applied to both gas and lava ...
}
```

### Rendering

Lava renders identically to gas — a density-modulated tint composited over the underlying content (AIR forlava cells). The render shader checks for `MAT_LAVA`:

```glsl
int mat = int(round(pixel.r * 255.0));
float fluid_alpha = 0.0;
vec4 fluid_tint = vec4(0.0);

if (mat == MAT_GAS || mat == MAT_LAVA) {
    fluid_tint = MATERIAL_TINT[mat];
    fluid_alpha = fluid_tint.a * pixel.g;  // density in G
    mat = MAT_AIR;  // fall through as if cell were air
}

vec4 base_color = /* existing path */;
frag_color = mix(base_color, vec4(fluid_tint.rgb, 1.0), fluid_alpha);
```

## Behavior Summary

- `MAT_LAVA` is a first-class material stored in R, with density in G, temperature in B, velocity packed in A.
- Pull-based advection moves density between lava and air cells each frame.
- **No diffusion** — lava maintains its density distribution.
- Velocity reflects off solid walls (same as gas).
- Cells become lava when enough density flows in and revert to air when density drops below threshold.
- **Temperature** variable per cell, decays over time, spreads heat to neighbors.
- **Hot lava ignites flammable materials** (WOOD, etc.) in neighboring cells.
- Rigidbody AABBs inject velocity into overlapping lava cells each frame.
- Rendered as an orange-red density-modulated tint.

## Files Changed

**Modified:**
- `scripts/material_registry.gd` — add `MAT_LAVA` constant, append LAVA entry
- `tools/generate_material_glsl.gd` — extend `MATERIAL_TINT` array for lava
- `shaders/simulation.glsl` — rename `gas_advect_pull` to `fluid_advect_pull`, add lava pack/unpack helpers, extend `try_inject_rigidbody_velocity` to handle both GAS and LAVA, modify burning phase to check lava neighbors as heat sources
- `shaders/render_chunk.gdshader` — check for `MAT_LAVA` in addition to `MAT_GAS` for fluid tint rendering

**Not added:** no new textures, no new render targets, no new compute shaders. Lava fits within the existing simulation dispatch.

## Tuning Constants

Same threshold constants for both fluids:

| Constant| Value | Meaning|
|---------|-------|--------|
| `THRESHOLD_BECOME_GAS` | 1| Min inflow for AIR → GAS |
| `THRESHOLD_BECOME_LAVA` | 1| Min inflow for AIR → LAVA (same value) |
| `THRESHOLD_DISSIPATE` | 1| Min density to stay as fluid |
| `HEAT_SPREAD` | 10| Heat transferred per frame (existing) |
| `HEAT_DISSIPATION` | 2| Temperature decay per frame (existing) |

## Out of Scope

- Lava solidification into stone (cooling)
- Multiple fluid types in one cell
- Lava → rigidbody force-back
- Viscosity differences from gas (same velocity damping)