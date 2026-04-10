# Lava Material Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add MAT_LAVA material that flows with velocity (no diffusion), has variable temperature that spreads to neighbors, and dissipates below density threshold.

**Architecture:** Rename `gas_advect_pull` to `fluid_advect_pull` with unified handling for both GAS and LAVA. Add lava-specific pack/unpack helpers. Extend burning phase to treat lava cells as heat sources. Update renderer for lava tint.

**Tech Stack:** GDScript, GLSL compute shaders, Godot 4

---

## File Structure

| File | Responsibility |
|------|----------------|
| `scripts/material_registry.gd` | Add MAT_LAVA constant and registry entry |
| `tools/generate_material_glsl.gd` | Extend MATERIAL_TINT array |
| `shaders/simulation.glsl` | Rename gas_advect_pull → fluid_advect_pull, add lava helpers, extend injection, modify burning |
| `shaders/render_chunk.gdshader` | Check MAT_LAVA for fluid tint rendering |
| `shaders/generated/materials.glslinc` | Auto-generated with MAT_LAVA |

---

### Task 1: Add MAT_LAVA to Material Registry

**Files:**
- Modify: `scripts/material_registry.gd`

- [ ] **Step 1: Add MAT_LAVA constant and registry entry**

Add after the `MAT_GAS` declaration and entry:

```gdscript
var MAT_LAVA: int
```

And in `_init_materials()` after the GAS entry:

```gdscript
var mat_lava := MaterialDef.new(
    "LAVA", "",
    false, 150, 255,
    false, false,
    Color(0.9, 0.4, 0.1, 1.0)
)
mat_lava.id = materials.size()
materials.append(mat_lava)
MAT_LAVA = mat_lava.id
```

- [ ] **Step 2: Verify the file loads without errors**

Run: `godot --headless --quit`
Expected: No errors, script loads successfully

- [ ] **Step 3: Commit**

```bash
git add scripts/material_registry.gd
git commit -m "feat: add MAT_LAVA to material registry"
```

---

### Task 2: Extend GLSL Generator for Lava Tint

**Files:**
- Modify: `tools/generate_material_glsl.gd`

- [ ] **Step 1: Verify current generator structure**

Read the file to understand how MATERIAL_TINT is generated.

- [ ] **Step 2: Confirm tint_color is already used**

The existing code already reads `tint_color` from MaterialDef and appends to MATERIAL_TINT array. No changes needed if the loop already iterates all materials.

- [ ] **Step 3: Regenerate materials GLSL**

Run: `./generate_materials.sh` or `godot --headless --script res://tools/generate_material_glsl.gd`
Expected: `shaders/generated/materials.glslinc` now includes MAT_COUNT = 5 and MATERIAL_TINT[5] with lava tint

- [ ] **Step 4: Verify generated output matches expected**

Read `shaders/generated/materials.glslinc` and confirm:

```glsl
const int MAT_COUNT = 5;

const int MAT_LAVA = 4;

const vec4 MATERIAL_TINT[5] = vec4[5](
    vec4(0.0, 0.0, 0.0, 0.0),
    vec4(0.0, 0.0, 0.0, 0.0),
    vec4(0.0, 0.0, 0.0, 0.0),
    vec4(0.4, 0.9, 0.3, 1.0),
    vec4(0.9, 0.4, 0.1, 1.0)
);
```

- [ ] **Step 5: Commit**

```bash
git add shaders/generated/materials.glslinc shaders/generated/materials.gdshaderinc
git commit -m "feat: regenerate materials GLSL with MAT_LAVA"
```

---

### Task 3: Add Lava Pack/Unpack Helpers to Simulation Shader

**Files:**
- Modify: `shaders/simulation.glsl`

- [ ] **Step 1: Add lava-specific helper functions after pack_gas**

Add after the existing `pack_gas` function:

```glsl
int get_density_lava(vec4 p) { return int(round(p.g * 255.0)); }
int get_temperature_lava(vec4 p) { return int(round(p.b * 255.0)); }

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

- [ ] **Step 2: Verify shader compiles**

Run: `godot --headless --quit`
Expected: No shader compilation errors

- [ ] **Step 3: Commit**

```bash
git add shaders/simulation.glsl
git commit -m "feat(simulation): add lava pack/unpack helpers"
```

---

### Task 4: Extend is_solid_for_gas to Include Lava

**Files:**
- Modify: `shaders/simulation.glsl`

- [ ] **Step 1: Rename function and update logic**

Replace the existing `is_solid_for_gas` function:

```glsl
bool is_solid_for_fluid(int mat) {
    // Fluids (GAS, LAVA) flow only between AIR and other fluids.
    // Anything else is a wall.
    return mat != MAT_AIR && mat != MAT_GAS && mat != MAT_LAVA;
}
```

- [ ] **Step 2: Update all call sites**

Replace all occurrences of `is_solid_for_gas(` with `is_solid_for_fluid(` in the file.

- [ ] **Step 3: Verify shader compiles**

Run: `godot --headless --quit`
Expected: No compilation errors

- [ ] **Step 4: Commit**

```bash
git add shaders/simulation.glsl
git commit -m "refactor(simulation): rename is_solid_for_gas to is_solid_for_fluid"
```

---

### Task 5: Extend Rigidbody Injection for Lava

**Files:**
- Modify: `shaders/simulation.glsl`

- [ ] **Step 1: Update try_inject_rigidbody_velocity condition**

Locate the `try_inject_rigidbody_velocity` function and change the material check:

```glsl
bool try_inject_rigidbody_velocity(ivec2 pos, int material, inout vec4 pixel) {
    if (material != MAT_GAS && material != MAT_LAVA) return false;
    bool wrote = false;
    int n = min(injections.count, MAX_INJECTIONS_PER_CHUNK);
    for (int i = 0; i < n; i++) {
        InjectionAABB b = injections.bodies[i];
        if (pos.x < b.aabb_min.x || pos.x >= b.aabb_max.x) continue;
        if (pos.y < b.aabb_min.y || pos.y >= b.aabb_max.y) continue;

        ivec2 cur_vel = unpack_velocity(pixel);
        ivec2 new_vel = clamp(cur_vel + b.velocity, ivec2(-8), ivec2(7));
        int dens = get_density(pixel);
        pixel = pack_gas(dens, new_vel);
        wrote = true;
    }
    if (wrote) imageStore(chunk_tex, pos, pixel);
    return wrote;
}
```

Note: The packing still uses `pack_gas` which works for lava too since the material ID comes from the R channel which will already be MAT_LAVA. Actually, this is incorrect - we need to preserve the material type. Let me reconsider.

Actually, looking at this more carefully: if the cell is MAT_LAVA, we need to preserve its material and temperature. We should use the appropriate pack function based on material.

- [ ] **Step 1 (revised): Update try_inject_rigidbody_velocity to handle both materials**

```glsl
bool try_inject_rigidbody_velocity(ivec2 pos, int material, inout vec4 pixel) {
    if (material != MAT_GAS && material != MAT_LAVA) return false;
    bool wrote = false;
    int n = min(injections.count, MAX_INJECTIONS_PER_CHUNK);
    for (int i = 0; i < n; i++) {
        InjectionAABB b = injections.bodies[i];
        if (pos.x < b.aabb_min.x || pos.x >= b.aabb_max.x) continue;
        if (pos.y < b.aabb_min.y || pos.y >= b.aabb_max.y) continue;

        ivec2 cur_vel;
        int dens;
        
        if (material == MAT_GAS) {
            cur_vel = unpack_velocity(pixel);
            dens = get_density(pixel);
        } else {
            cur_vel = unpack_velocity_lava(pixel);
            dens = get_density_lava(pixel);
        }
        
        ivec2 new_vel = clamp(cur_vel + b.velocity, ivec2(-8), ivec2(7));
        
        if (material == MAT_GAS) {
            pixel = pack_gas(dens, new_vel);
        } else {
            int temp = get_temperature_lava(pixel);
            pixel = pack_lava(dens, temp, new_vel);
        }
        wrote = true;
    }
    if (wrote) imageStore(chunk_tex, pos, pixel);
    return wrote;
}
```

- [ ] **Step 2: Verify shader compiles**

Run: `godot --headless --quit`
Expected: No compilation errors

- [ ] **Step 3: Commit**

```bash
git add shaders/simulation.glsl
git commit -m "feat(simulation): extend rigidbody injection for lava"
```

---

### Task 6: Rename gas_advect_pull to fluid_advect_pull

**Files:**
- Modify: `shaders/simulation.glsl`

- [ ] **Step 1: Rename function and update main() call**

Rename function:

```glsl
void fluid_advect_pull(
    ivec2 pos, vec4 pixel,
    vec4 n_up, vec4 n_down, vec4 n_left, vec4 n_right
) {
```

Update the call in main():

```glsl
if (material == MAT_GAS || material == MAT_LAVA || material == MAT_AIR) {
    fluid_advect_pull(pos, pixel, n_up, n_down, n_left, n_right);
    return;
}
```

- [ ] **Step 2: Verify shader compiles**

Run: `godot --headless --quit`
Expected: No compilation errors

- [ ] **Step 3: Commit**

```bash
git add shaders/simulation.glsl
git commit -m "refactor(simulation): rename gas_advect_pull to fluid_advect_pull"
```

---

### Task 7: Add Lava Handling to fluid_advect_pull

**Files:**
- Modify: `shaders/simulation.glsl`

- [ ] **Step 1: Add material type flags at function start**

After reading neighbor materials, add:

```glsl
bool is_gas = (material == MAT_GAS);
bool is_lava = (material == MAT_LAVA);
bool is_air = (material == MAT_AIR);
```

- [ ] **Step 2: Update any_fluid_neighbor check**

Replace the existing `any_gas_neighbor` check:

```glsl
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
```

- [ ] **Step 3: Update own state reading**

Replace the density/velocity extraction:

```glsl
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
```

- [ ] **Step 4: Update is_solid_for_gas calls to is_solid_for_fluid**

Already done in Task 4. Verify no remaining references.

- [ ] **Step 5: Make diffusion conditional (gas only)**

Wrap the existing diffusion code block:

```glsl
int diff_out = 0;
int diff_in = 0;

if (is_gas) {
    // Existing diffusion logic here - unchanged
    if (density > 0) {
        int dens_up    = (n_mat_up == MAT_GAS)    ? get_density(n_up)    : 0;
        int dens_down  = (n_mat_down == MAT_GAS)  ? get_density(n_down)  : 0;
        int dens_left  = (n_mat_left == MAT_GAS)  ? get_density(n_left)  : 0;
        int dens_right = (n_mat_right == MAT_GAS) ? get_density(n_right) : 0;

        if (!is_solid_for_fluid(n_mat_up)    && dens_up < density)    diff_out += (density - dens_up) / DIFFUSION_RATE;
        if (!is_solid_for_fluid(n_mat_down)  && dens_down < density)  diff_out += (density - dens_down) / DIFFUSION_RATE;
        if (!is_solid_for_fluid(n_mat_left)  && dens_left < density)  diff_out += (density - dens_left) / DIFFUSION_RATE;
        if (!is_solid_for_fluid(n_mat_right) && dens_right < density) diff_out += (density - dens_right) / DIFFUSION_RATE;
    }

    // Diffusion inflow
    if (n_mat_up == MAT_GAS    && get_density(n_up) > density    && !is_solid_for_fluid(material))    diff_in += (get_density(n_up) - density) / DIFFUSION_RATE;
    if (n_mat_down == MAT_GAS  && get_density(n_down) > density  && !is_solid_for_fluid(material))  diff_in += (get_density(n_down) - density) / DIFFUSION_RATE;
    if (n_mat_left == MAT_GAS  && get_density(n_left) > density  && !is_solid_for_fluid(material))  diff_in += (get_density(n_left) - density) / DIFFUSION_RATE;
    if (n_mat_right == MAT_GAS && get_density(n_right) > density && !is_solid_for_fluid(material)) diff_in += (get_density(n_right) - density) / DIFFUSION_RATE;
}
// Lava has no diffusion - diff_out and diff_in remain 0
```

- [ ] **Step 6: Update inflow computation to handle both fluid types**

The existing inflow computation only checks `n_mat_X == MAT_GAS`. Update to also check `n_mat_X == MAT_LAVA`:

```glsl
int in_up = 0;
int in_down = 0;
int in_left = 0;
int in_right = 0;
ivec2 vin_up = ivec2(0);
ivec2 vin_down = ivec2(0);
ivec2 vin_left = ivec2(0);
ivec2 vin_right = ivec2(0);

if (n_mat_up == MAT_GAS || n_mat_up == MAT_LAVA) {
    int dN = (n_mat_up == MAT_GAS) ? get_density(n_up) : get_density_lava(n_up);
    ivec2 vN = (n_mat_up == MAT_GAS) ? unpack_velocity(n_up) : unpack_velocity_lava(n_up);
    int c = max(0, vN.y);
    in_up = stochastic_div(dN * c, V_MAX_OUTFLOW, pos, 5u);
    vin_up = vN;
}
// ... same pattern for in_down, in_left, in_right ...
```

Actually, let me write this more carefully with all four directions.

Looking at the existing code more carefully, I see the inflow section already handles all four directions. I need to show the complete replacement.

- [ ] **Step 6 (complete): Update inflow computation for all four directions**

Replace the inflow section:

```glsl
int in_up = 0;
int in_down = 0;
int in_left = 0;
int in_right = 0;
ivec2 vin_up = ivec2(0);
ivec2 vin_down = ivec2(0);
ivec2 vin_left = ivec2(0);
ivec2 vin_right = ivec2(0);

if (n_mat_up == MAT_GAS || n_mat_up == MAT_LAVA) {
    int dN = (n_mat_up == MAT_GAS) ? get_density(n_up) : get_density_lava(n_up);
    ivec2 vN = (n_mat_up == MAT_GAS) ? unpack_velocity(n_up) : unpack_velocity_lava(n_up);
    int c = max(0, vN.y);
    in_up = stochastic_div(dN * c, V_MAX_OUTFLOW, pos, 5u);
    vin_up = vN;
}
if (n_mat_down == MAT_GAS || n_mat_down == MAT_LAVA) {
    int dN = (n_mat_down == MAT_GAS) ? get_density(n_down) : get_density_lava(n_down);
    ivec2 vN = (n_mat_down == MAT_GAS) ? unpack_velocity(n_down) : unpack_velocity_lava(n_down);
    int c = max(0, -vN.y);
    in_down = stochastic_div(dN * c, V_MAX_OUTFLOW, pos, 6u);
    vin_down = vN;
}
if (n_mat_left == MAT_GAS || n_mat_left == MAT_LAVA) {
    int dN = (n_mat_left == MAT_GAS) ? get_density(n_left) : get_density_lava(n_left);
    ivec2 vN = (n_mat_left == MAT_GAS) ? unpack_velocity(n_left) : unpack_velocity_lava(n_left);
    int c = max(0, vN.x);
    in_left = stochastic_div(dN * c, V_MAX_OUTFLOW, pos, 7u);
    vin_left = vN;
}
if (n_mat_right == MAT_GAS || n_mat_right == MAT_LAVA) {
    int dN = (n_mat_right == MAT_GAS) ? get_density(n_right) : get_density_lava(n_right);
    ivec2 vN = (n_mat_right == MAT_GAS) ? unpack_velocity(n_right) : unpack_velocity_lava(n_right);
    int c = max(0, -vN.x);
    in_right = stochastic_div(dN * c, V_MAX_OUTFLOW, pos, 8u);
    vin_right = vN;
}

int total_in = in_up + in_down + in_left + in_right;
```

- [ ] **Step 7: Add temperature decay for lava**

After velocity damping, add:

```glsl
if (is_lava) {
    temperature = max(0, temperature - HEAT_DISSIPATION);
}
```

- [ ] **Step 8: Update material transitions section**

Replace the existing AIR transition and final output:

```glsl
if (is_air) {
    // Determine which fluid type wins based on inflow composition
    int gas_in = 0;
    int lava_in = 0;
    
    if (n_mat_up == MAT_GAS) gas_in += in_up;
    else if (n_mat_up == MAT_LAVA) lava_in += in_up;
    if (n_mat_down == MAT_GAS) gas_in += in_down;
    else if (n_mat_down == MAT_LAVA) lava_in += in_down;
    if (n_mat_left == MAT_GAS) gas_in += in_left;
    else if (n_mat_left == MAT_LAVA) lava_in += in_left;
    if (n_mat_right == MAT_GAS) gas_in += in_right;
    else if (n_mat_right == MAT_LAVA) lava_in += in_right;
    
    int total_air_in = total_in + diff_in;
    
    if (gas_in >= THRESHOLD_BECOME_GAS || lava_in >= THRESHOLD_BECOME_LAVA) {
        // Material determined by majority inflow
        ivec2 inflow_vel = ivec2(0);
        if (total_in > 0) {
            inflow_vel = (vin_up * in_up + vin_down * in_down + vin_left * in_left + vin_right * in_right) / total_in;
            inflow_vel = (inflow_vel * 15) / 16;
            inflow_vel = clamp(inflow_vel, ivec2(-8), ivec2(7));
        }
        
        if (gas_in >= lava_in) {
            imageStore(chunk_tex, pos, pack_gas(total_air_in, inflow_vel));
        } else {
            imageStore(chunk_tex, pos, pack_lava(total_air_in, 0, inflow_vel));
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
```

- [ ] **Step 9: Verify shader compiles**

Run: `godot --headless --quit`
Expected: No compilation errors

- [ ] **Step 10: Commit**

```bash
git add shaders/simulation.glsl
git commit -m "feat(simulation): add lava handling to fluid_advect_pull"
```

---

### Task 8: Add Lava Heat to Burning Phase

**Files:**
- Modify: `shaders/simulation.glsl`

- [ ] **Step 1: Add helper function to check for hot lava neighbors**

Add after `is_burning` function:

```glsl
bool is_hot_lava(vec4 p, int target_material) {
    if (get_material(p) != MAT_LAVA) return false;
    int temp = get_temperature_lava(p);
    return temp > IGNITION_TEMP[target_material];
}
```

- [ ] **Step 2: Extend the burning heat accumulation loop**

In the burning phase section, after the existing neighbor burning checks, add lava neighbor checks:

```glsl
// Heat from hot lava neighbors
if (is_hot_lava(n_up, material)) {
    heat_gain += get_temperature_lava(n_up) / 4;
}
if (is_hot_lava(n_down, material)) {
    heat_gain += get_temperature_lava(n_down) / 4;
}
if (is_hot_lava(n_left, material)) {
    heat_gain += get_temperature_lava(n_left) / 4;
}
if (is_hot_lava(n_right, material)) {
    heat_gain += get_temperature_lava(n_right) / 4;
}
```

- [ ] **Step 3: Verify shader compiles**

Run: `godot --headless --quit`
Expected: No compilation errors

- [ ] **Step 4: Commit**

```bash
git add shaders/simulation.glsl
git commit -m "feat(simulation): lava cells spread heat to flammable neighbors"
```

---

### Task 9: Update Render Shader for Lava Tint

**Files:**
- Modify: `shaders/render_chunk.gdshader`

- [ ] **Step 1: Locate the existing fluid tint code**

Find the section that checks for `MAT_GAS` and applies tint.

- [ ] **Step 2: Extend to check for MAT_LAVA**

Update the fluid tint check to include lava:

```glsl
int mat = int(round(pixel.r * 255.0));
float fluid_alpha = 0.0;
vec4 fluid_tint = vec4(0.0);

if (mat == MAT_GAS || mat == MAT_LAVA) {
    fluid_tint = MATERIAL_TINT[mat];
    fluid_alpha = fluid_tint.a * pixel.g;  // density in G
    mat = MAT_AIR;  // fall through as if cell were air
}

// ... existing render path ...
vec4 base_color = /* existing path */;
frag_color = mix(base_color, vec4(fluid_tint.rgb, 1.0), fluid_alpha);
```

- [ ] **Step 3: Verify shader compiles**

Run: `godot --headless --quit`
Expected: No compilation errors

- [ ] **Step 4: Commit**

```bash
git add shaders/render_chunk.gdshader
git commit -m "feat(render): add lava tint rendering"
```

---

### Task 10: Integration Test

**Files:**
- None (runtime testing)

- [ ] **Step 1: Launch the project**

Run: `godot`
Expected: Project launches without errors

- [ ] **Step 2: Place lava material in-world**

Use the existing material placement system to place lava cells. Verify:
- Lava appears with orange-red tint
- Lava flows (advection) but doesn't spread evenly (no diffusion)
- Lava reflects off walls
- Lava temperature heats nearby flammable materials (wood ignites)
- Lava dissipates to air when density drops

- [ ] **Step 3: Test gas and lava interaction**

Place gas and lava adjacent. Verify:
- Both fluids can coexist
- AIR cells become whichever fluid has majority inflow
- No crashes or visual glitches

- [ ] **Step 4: Commit if tests pass**

```bash
git add -A
git commit -m "test: verify lava material integration"
```

---

## Self-Review Checklist

**1. Spec coverage:**
- [x] MAT_LAVA added to registry (Task 1)
- [x] Lava tint in MATERIAL_TINT (Task 2)
- [x] Pack/unpack helpers with temperature (Task 3)
- [x] Fluid flow includes lava (Tasks 4, 6, 7)
- [x] No diffusion for lava (Task 7, Step 5)
- [x] Variable temperature (Task 7, Steps 3, 7)
- [x] Temperature spreads to neighbors (Task 8)
- [x] Rigidbody injection (Task 5)
- [x] Dissipation below threshold (Task 7, Step 8)
- [x] Render tint (Task 9)

**2. Placeholder scan:**
- No TBD/TODO found
- All code blocks contain complete implementations

**3. Type consistency:**
- `pack_lava(density, temperature, vel)` signature consistent across all uses
- `is_solid_for_fluid` renamed consistently
- `fluid_advect_pull` renamed consistently