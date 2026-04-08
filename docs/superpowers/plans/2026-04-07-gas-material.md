# Gas Material Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `MAT_GAS` pixel-terrain material that advects like a fluid, reflects off solid walls, and is pushed around by the player's AABB using a per-chunk SSBO injection pass.

**Architecture:** Gas reuses the existing `rgba8` chunk texture with reinterpreted channels for gas cells (G=density, A=packed ±8/±7 velocity). `simulation.glsl` gains a rigidbody-injection pass plus a pull-based advection path that runs every frame outside the existing checkerboard guard. Rendering composites a density-driven tint over the air-treated base render path. A new `GasInjector` helper collects movement-imparting bodies from the `gas_interactors` group each frame and uploads them to a per-chunk SSBO.

**Tech Stack:** Godot 4.6 (GDScript + `RenderingDevice` compute), GLSL 450 compute shader, canvas_item fragment shader.

**Spec reference:** `docs/superpowers/specs/2026-04-07-gas-material-design.md`

---

## File Structure

**Added:**
- `scripts/gas_injector.gd` — static helper: collects `gas_interactors` nodes, filters by chunk overlap, packs `std430` payload bytes.

**Modified:**
- `scripts/material_registry.gd` — `MaterialDef` gains `tint_color: Color`, appends `GAS` entry, `get_tint_color()` helper.
- `tools/generate_material_glsl.gd` — emits `MATERIAL_TINT[]` into generated includes.
- `shaders/simulation.glsl` — gas pack/unpack, injection SSBO, `gas_advect_pull`, restructured `main()`.
- `shaders/render_chunk.gdshader` — gas tint composite pass.
- `scripts/chunk.gd` — stores per-chunk `injection_buffer: RID`.
- `scripts/world_manager.gd` — allocates/frees injection buffer, binds it at `set=0 binding=5`, updates it per frame via `GasInjector`.
- `scripts/player_controller.gd` — adds player to `gas_interactors` group in `_ready`.
- `scripts/input_handler.gd` — right-click places a gas blob (debug harness).
- `shaders/generated/materials.glslinc` / `materials.gdshaderinc` — regenerated.

---

## Tuning Constants (locked in)

| Constant                 | Value | Location                    |
|--------------------------|-------|-----------------------------|
| `MAT_GAS` id             | 3     | registry (auto-assigned)    |
| `V_MAX_OUTFLOW`          | 8     | `simulation.glsl` const     |
| `THRESHOLD_BECOME_GAS`   | 4     | `simulation.glsl` const     |
| `THRESHOLD_DISSIPATE`    | 4     | `simulation.glsl` const     |
| Velocity damping         | 15/16 | `simulation.glsl` const     |
| `MAX_INJECTIONS_PER_CHUNK` | 32  | `world_manager.gd` / shader |
| `MIN_SPEED_SQ`           | 0.25  | `gas_injector.gd`           |
| Gas tint color           | `Color(0.4, 0.9, 0.3, 1.0)` | registry |
| Velocity-to-cell scale `k` | `1.0 / 60.0` | `gas_injector.gd` (px/s ≈ cell/frame at 60 fps) |

**SSBO layout per chunk (bytes):**

```
offset 0..3   : int32 count
offset 4..15  : 12 bytes padding (std430 16-byte header alignment)
offset 16+i*32 .. 16+(i+1)*32 : InjectionAABB[i]
  0..7   : ivec2 aabb_min (i32, i32)
  8..15  : ivec2 aabb_max (i32, i32)
  16..23 : ivec2 velocity (i32, i32)
  24..31 : 8 bytes padding
```

Total buffer size: `16 + 32 * MAX_INJECTIONS_PER_CHUNK = 16 + 1024 = 1040` bytes.

**Verification Strategy (no test framework in this project):** Each task uses **runtime smoke tests** — launch the project (or a dedicated debug scene), perform a defined action, and visually verify the outcome against stated expectations. Task-level commits allow bisection if a later task breaks an earlier guarantee.

---

## Task 1: Add `tint_color` to MaterialDef and the GAS entry

**Files:**
- Modify: `scripts/material_registry.gd`

- [ ] **Step 1: Add `tint_color` field and constructor arg to `MaterialDef`**

Replace the `MaterialDef` class block in `scripts/material_registry.gd` with:

```gdscript
class MaterialDef:
    var id: int
    var name: String
    var texture_path: String
    var flammable: bool
    var ignition_temp: int
    var burn_health: int
    var has_collider: bool
    var has_wall_extension: bool
    var tint_color: Color

    func _init(
        p_name: String,
        p_texture_path: String,
        p_flammable: bool,
        p_ignition_temp: int,
        p_burn_health: int,
        p_has_collider: bool,
        p_has_wall_extension: bool,
        p_tint_color: Color = Color(0, 0, 0, 0)
    ):
        name = p_name
        texture_path = p_texture_path
        flammable = p_flammable
        ignition_temp = p_ignition_temp
        burn_health = p_burn_health
        has_collider = p_has_collider
        has_wall_extension = p_has_wall_extension
        tint_color = p_tint_color
```

- [ ] **Step 2: Add `MAT_GAS` variable and append a GAS entry in `_init_materials`**

Find the existing `var MAT_STONE: int` line near the top and add after it:

```gdscript
var MAT_GAS: int
```

Find the end of `_init_materials()` (after the `MAT_STONE = mat_stone.id` block) and append:

```gdscript
    var mat_gas := MaterialDef.new(
        "GAS", "",
        false, 0, 0,
        false, false,
        Color(0.4, 0.9, 0.3, 1.0)
    )
    mat_gas.id = materials.size()
    materials.append(mat_gas)
    MAT_GAS = mat_gas.id
```

- [ ] **Step 3: Add `get_tint_color` helper**

Append after `has_wall_extension` helper at the end of the file:

```gdscript
func get_tint_color(material_id: int) -> Color:
    if material_id < 0 or material_id >= materials.size():
        return Color(0, 0, 0, 0)
    return materials[material_id].tint_color
```

- [ ] **Step 4: Smoke test — launch editor to confirm script parses**

Run:

```bash
cd /home/jeremy/Development/Godot/top-down-rogue
godot --headless --check-only scripts/material_registry.gd
```

Expected: no parse errors. (If `--check-only` isn't recognized on your Godot version, fall back to `godot --headless --quit` at the project root and confirm no errors on stderr.)

- [ ] **Step 5: Commit**

```bash
git add scripts/material_registry.gd
git commit -m "feat(gas): add tint_color to MaterialDef and GAS entry"
```

---

## Task 2: Emit `MATERIAL_TINT[]` from the GLSL generator

**Files:**
- Modify: `tools/generate_material_glsl.gd`
- Modify (regenerated): `shaders/generated/materials.glslinc`, `shaders/generated/materials.gdshaderinc`

- [ ] **Step 1: Add tint array emission to the generator**

In `tools/generate_material_glsl.gd`, after the `BURN_HEALTH` block and before the file-write block, insert:

```gdscript
    output += "const vec4 MATERIAL_TINT[%d] = vec4[%d](\n" % [mat_count, mat_count]
    for i in registry.materials.size():
        var m = registry.materials[i]
        var c: Color = m.tint_color
        output += "    vec4(%f, %f, %f, %f)" % [c.r, c.g, c.b, c.a]
        if i < registry.materials.size() - 1:
            output += ","
        output += "\n"
    output += ");\n"
```

- [ ] **Step 2: Regenerate the include files**

Run:

```bash
cd /home/jeremy/Development/Godot/top-down-rogue
./generate_materials.sh
```

Expected stdout:
```
Generated shaders/generated/materials.glslinc
Generated shaders/generated/materials.gdshaderinc
```

- [ ] **Step 3: Verify the generated files have 4 materials and the tint array**

Run:

```bash
grep -E "^const int MAT_" /home/jeremy/Development/Godot/top-down-rogue/shaders/generated/materials.glslinc
grep "MATERIAL_TINT" /home/jeremy/Development/Godot/top-down-rogue/shaders/generated/materials.glslinc
```

Expected output:
```
const int MAT_AIR = 0;
const int MAT_WOOD = 1;
const int MAT_STONE = 2;
const int MAT_GAS = 3;
const vec4 MATERIAL_TINT[4] = vec4[4](
```

Also confirm `MAT_COUNT = 4` appears in the file.

- [ ] **Step 4: Commit**

```bash
git add tools/generate_material_glsl.gd shaders/generated/materials.glslinc shaders/generated/materials.gdshaderinc
git commit -m "feat(gas): emit MATERIAL_TINT[] from generator; regenerate"
```

---

## Task 3: Add velocity pack/unpack helpers and stub gas functions in simulation.glsl

Goal: land structural scaffolding that compiles and runs without changing behavior, so later tasks can focus on one piece at a time.

**Files:**
- Modify: `shaders/simulation.glsl`

- [ ] **Step 1: Insert helpers + constants near the top of simulation.glsl**

Find this block in `shaders/simulation.glsl`:

```glsl
const int CHUNK_SIZE = 256;
const int FIRE_TEMP = 255;
const int HEAT_DISSIPATION = 2;
const int HEAT_SPREAD = 10;
const float SPREAD_PROB_MAX = 0.7;
```

Append after it:

```glsl
// --- Gas simulation constants ---
const int V_MAX_OUTFLOW = 8;
const int THRESHOLD_BECOME_GAS = 4;
const int THRESHOLD_DISSIPATE = 4;
const int MAX_INJECTIONS_PER_CHUNK = 32;
```

- [ ] **Step 2: Add injection SSBO declaration at `set=0 binding=5`**

After the existing `layout(push_constant, ...)` block, insert:

```glsl
struct InjectionAABB {
    ivec2 aabb_min;
    ivec2 aabb_max;
    ivec2 velocity;
    int _pad0;
    int _pad1;
};

layout(set = 0, binding = 5, std430) readonly buffer InjectionBuffer {
    int count;
    int _pad[3];
    InjectionAABB bodies[];
} injections;
```

- [ ] **Step 3: Add gas pack/unpack helpers alongside the existing `get_material` / `make_pixel` helpers**

Find the existing block:

```glsl
int get_material(vec4 p) { return int(round(p.r * 255.0)); }
int get_health(vec4 p) { return int(round(p.g * 255.0)); }
int get_temperature(vec4 p) { return int(round(p.b * 255.0)); }

vec4 make_pixel(int mat, int hp, int temp) {
    return vec4(float(mat) / 255.0, float(hp) / 255.0, float(temp) / 255.0, 0.0);
}
```

Append after it:

```glsl
int get_density(vec4 p) { return int(round(p.g * 255.0)); }

ivec2 unpack_velocity(vec4 p) {
    uint a = uint(round(p.a * 255.0));
    return ivec2(int(a >> 4) - 8, int(a & 15u) - 8);
}

vec4 pack_gas(int density, ivec2 vel) {
    int vx = clamp(vel.x + 8, 0, 15);
    int vy = clamp(vel.y + 8, 0, 15);
    uint a = (uint(vx) << 4) | uint(vy);
    return vec4(
        float(MAT_GAS) / 255.0,
        float(clamp(density, 0, 255)) / 255.0,
        0.0,
        float(a) / 255.0
    );
}

// Returns true if this cell was overwritten by an injection and main() should return.
bool try_inject_rigidbody_velocity(ivec2 pos, int material, inout vec4 pixel) {
    return false;  // stub — Task 5
}

// Gas advection for gas AND air cells. Writes pixel via imageStore and returns.
void gas_advect_pull(
    ivec2 pos, vec4 pixel,
    vec4 n_up, vec4 n_down, vec4 n_left, vec4 n_right
) {
    // Stub — Task 4 replaces this body. For now, preserve existing behavior:
    int material = get_material(pixel);
    int health = get_health(pixel);
    int temperature = get_temperature(pixel);
    if (material == MAT_AIR) {
        temperature = max(0, temperature - HEAT_DISSIPATION);
    }
    imageStore(chunk_tex, pos, make_pixel(material, health, temperature));
}
```

- [ ] **Step 4: Replace `main()` wholesale**

Find the existing `void main() { ... }` in `shaders/simulation.glsl` and replace the entire function with this complete body:

```glsl
void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= CHUNK_SIZE || pos.y >= CHUNK_SIZE) return;

    vec4 pixel = imageLoad(chunk_tex, pos);
    int material = get_material(pixel);

    // 1. Rigidbody AABB injection — returns if the cell was written.
    if (try_inject_rigidbody_velocity(pos, material, pixel)) return;

    // 2. Neighbor reads used by both gas and burning.
    vec4 n_up    = read_neighbor(pos + ivec2(0, -1));
    vec4 n_down  = read_neighbor(pos + ivec2(0,  1));
    vec4 n_left  = read_neighbor(pos + ivec2(-1, 0));
    vec4 n_right = read_neighbor(pos + ivec2( 1, 0));

    // 3. Gas + air path — runs every frame, pull-based, no phase guard.
    if (material == MAT_GAS || material == MAT_AIR) {
        gas_advect_pull(pos, pixel, n_up, n_down, n_left, n_right);
        return;
    }

    // 4. Checkerboard burning logic for solids.
    if ((pos.x + pos.y) % 2 != pc.phase) return;

    int health = get_health(pixel);
    int temperature = get_temperature(pixel);

    // Accumulate random heat from each burning neighbor (with probability).
    int heat_gain = 0;
    uint base_rng = hash(uint(pos.x) ^ hash(uint(pos.y) ^ uint(pc.frame_seed)));
    if (is_burning(n_up)) {
        int n_mat = get_material(n_up);
        int n_temp = get_temperature(n_up);
        float prob = float(n_temp - IGNITION_TEMP[n_mat]) / float(FIRE_TEMP - IGNITION_TEMP[n_mat]) * SPREAD_PROB_MAX;
        uint rng = hash(base_rng ^ 1u);
        if (rng % 100 < uint(prob * 100.0)) {
            heat_gain += HEAT_SPREAD / 2 + int(rng % uint(HEAT_SPREAD));
        }
    }
    if (is_burning(n_down)) {
        int n_mat = get_material(n_down);
        int n_temp = get_temperature(n_down);
        float prob = float(n_temp - IGNITION_TEMP[n_mat]) / float(FIRE_TEMP - IGNITION_TEMP[n_mat]) * SPREAD_PROB_MAX;
        uint rng = hash(base_rng ^ 2u);
        if (rng % 100 < uint(prob * 100.0)) {
            heat_gain += HEAT_SPREAD / 2 + int(rng % uint(HEAT_SPREAD));
        }
    }
    if (is_burning(n_left)) {
        int n_mat = get_material(n_left);
        int n_temp = get_temperature(n_left);
        float prob = float(n_temp - IGNITION_TEMP[n_mat]) / float(FIRE_TEMP - IGNITION_TEMP[n_mat]) * SPREAD_PROB_MAX;
        uint rng = hash(base_rng ^ 3u);
        if (rng % 100 < uint(prob * 100.0)) {
            heat_gain += HEAT_SPREAD / 4 + int(rng % uint(HEAT_SPREAD));
        }
    }
    if (is_burning(n_right)) {
        int n_mat = get_material(n_right);
        int n_temp = get_temperature(n_right);
        float prob = float(n_temp - IGNITION_TEMP[n_mat]) / float(FIRE_TEMP - IGNITION_TEMP[n_mat]) * SPREAD_PROB_MAX;
        uint rng = hash(base_rng ^ 4u);
        if (rng % 100 < uint(prob * 100.0)) {
            heat_gain += HEAT_SPREAD / 2 + int(rng % uint(HEAT_SPREAD));
        }
    }

    if (IS_FLAMMABLE[material]) {
        temperature = min(255, temperature + heat_gain);
        temperature = max(0, temperature - HEAT_DISSIPATION);
        if (temperature > IGNITION_TEMP[material]) {
            health = health - 1;
            temperature = FIRE_TEMP;
            if (health <= 0) {
                material = MAT_AIR;
                health = 0;
                temperature = 0;
            }
        }
    }

    imageStore(chunk_tex, pos, make_pixel(material, health, temperature));
}
```

Note what changed from the original:
- The `// Checkerboard: skip if not this phase` guard moved from the top to section 4 (solids-only).
- The pixel/material read moved up above the old position so that injection + gas paths can use them.
- The four `read_neighbor` calls moved above the phase guard so both gas and burning code can share them.
- The old `if (material == MAT_AIR) { temperature = max(0, temperature - HEAT_DISSIPATION); } else if (IS_FLAMMABLE[material]) { ... }` chain is gone — air handling moved to `gas_advect_pull` (Task 5 Step 2 preserves heat dissipation), non-flammable solids simply fall through to `imageStore` unchanged (same as before).

- [ ] **Step 5: Smoke test — compile the shader**

Launch the editor once so Godot recompiles the compute shader. Run:

```bash
cd /home/jeremy/Development/Godot/top-down-rogue
godot --headless --quit 2>&1 | grep -iE "(error|shader)" | head
```

Expected: no shader compile errors. Because the shader now declares binding 5 but `world_manager.gd` doesn't bind it yet, **do not run the game scene** at this point — the uniform set build will fail at runtime. The static check above is sufficient.

- [ ] **Step 6: Commit**

```bash
git add shaders/simulation.glsl
git commit -m "feat(gas): scaffold gas helpers and restructure simulation main"
```

---

## Task 4: Wire per-chunk injection buffer (without populating it)

Goal: bind the SSBO at `binding = 5` so the restructured simulation shader from Task 3 can run. Content is zeroed for now; the shader's injection pass is still a stub.

**Files:**
- Modify: `scripts/chunk.gd`
- Modify: `scripts/world_manager.gd`

- [ ] **Step 1: Add `injection_buffer` RID to `Chunk`**

Replace the contents of `scripts/chunk.gd` with:

```gdscript
class_name Chunk
extends RefCounted

var coord: Vector2i
var rd_texture: RID
var texture_2d_rd: Texture2DRD
var mesh_instance: MeshInstance2D
var wall_mesh_instance: MeshInstance2D
var sim_uniform_set: RID
var injection_buffer: RID
var static_body: StaticBody2D
var collision_dirty: bool = true
var last_collision_time: float = 0.0
```

- [ ] **Step 2: Add constants and buffer allocation in `world_manager.gd`**

Near the top of `scripts/world_manager.gd`, after the existing `MAX_COLLISION_SEGMENTS` line, add:

```gdscript
const MAX_INJECTIONS_PER_CHUNK := 32
# Header: int count + 12 bytes padding (std430 16-byte alignment).
# Each InjectionAABB is 32 bytes (ivec2 min + ivec2 max + ivec2 vel + 2x i32 pad).
const INJECTION_BUFFER_SIZE := 16 + 32 * MAX_INJECTIONS_PER_CHUNK
```

In `_create_chunk()`, after `chunk.rd_texture = rd.texture_create(...)` and before `chunk.texture_2d_rd = ...`, insert:

```gdscript
    chunk.injection_buffer = rd.storage_buffer_create(INJECTION_BUFFER_SIZE)
    # Zero-initialize (count = 0, no bodies) so the first dispatch is a no-op loop.
    var zero_data := PackedByteArray()
    zero_data.resize(INJECTION_BUFFER_SIZE)
    zero_data.fill(0)
    rd.buffer_update(chunk.injection_buffer, 0, zero_data.size(), zero_data)
```

In `_free_chunk_resources()`, add before the `sim_uniform_set` free:

```gdscript
    if chunk.injection_buffer.is_valid():
        rd.free_rid(chunk.injection_buffer)
```

- [ ] **Step 3: Bind the injection buffer in `_build_sim_uniform_set`**

In `_build_sim_uniform_set`, after the existing neighbor-binding loop (which adds uniforms at bindings 1–4) and before `chunk.sim_uniform_set = rd.uniform_set_create(...)`, insert:

```gdscript
    # Binding 5: rigidbody injection SSBO (per chunk)
    var u5 := RDUniform.new()
    u5.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    u5.binding = 5
    u5.add_id(chunk.injection_buffer)
    uniforms.append(u5)
```

- [ ] **Step 4: Smoke test — run the game scene briefly**

Run:

```bash
cd /home/jeremy/Development/Godot/top-down-rogue
timeout 3 godot --headless 2>&1 | tail -40
```

Expected: the project launches, no "uniform set mismatch" or "invalid RID" errors related to binding 5. The simulation runs with the injection buffer present but unused by the stub. Air cells dissipate heat as before (handled by the `gas_advect_pull` stub).

If you see errors about `storage_buffer` being incompatible with the shader binding, confirm `uniform_type` is `UNIFORM_TYPE_STORAGE_BUFFER` and that the shader declares the buffer as `std430` (it should, from Task 3).

- [ ] **Step 5: Commit**

```bash
git add scripts/chunk.gd scripts/world_manager.gd
git commit -m "feat(gas): per-chunk injection SSBO bound at set=0 binding=5"
```

---

## Task 5: Implement `gas_advect_pull` — density transfer with wall reflection

Goal: replace the stub from Task 3 with real pull-based advection. Heat dissipation for air cells must be preserved.

**Files:**
- Modify: `shaders/simulation.glsl`

- [ ] **Step 1: Add helper forward-utilities**

In `shaders/simulation.glsl`, immediately above the existing `gas_advect_pull` stub, insert these helpers:

```glsl
bool is_solid_for_gas(int mat) {
    // Gas flows only between AIR and GAS. Anything else is a wall.
    return mat != MAT_AIR && mat != MAT_GAS;
}

// Integer divide with hash-based stochastic rounding for the remainder.
// `salt` differentiates independent random streams (e.g., 1..4 for four directions).
int stochastic_div(int numerator, int denom, ivec2 pos, uint salt) {
    if (denom <= 0) return 0;
    int base = numerator / denom;
    int rem = numerator - base * denom;
    if (rem <= 0) return base;
    uint rng = hash(uint(pos.x) ^ hash(uint(pos.y) ^ uint(pc.frame_seed) ^ salt));
    return base + (int(rng % uint(denom)) < rem ? 1 : 0);
}
```

- [ ] **Step 2: Replace the `gas_advect_pull` body with pull-based advection**

Replace the full `gas_advect_pull` function in `shaders/simulation.glsl` with:

```glsl
void gas_advect_pull(
    ivec2 pos, vec4 pixel,
    vec4 n_up, vec4 n_down, vec4 n_left, vec4 n_right
) {
    int material = get_material(pixel);

    // --- Fast path: AIR cell with no neighboring gas. Preserve heat decay. ---
    int n_mat_up    = get_material(n_up);
    int n_mat_down  = get_material(n_down);
    int n_mat_left  = get_material(n_left);
    int n_mat_right = get_material(n_right);

    bool any_gas_neighbor =
        n_mat_up == MAT_GAS || n_mat_down == MAT_GAS ||
        n_mat_left == MAT_GAS || n_mat_right == MAT_GAS;

    if (material == MAT_AIR && !any_gas_neighbor) {
        int health = get_health(pixel);
        int temperature = max(0, get_temperature(pixel) - HEAT_DISSIPATION);
        imageStore(chunk_tex, pos, make_pixel(MAT_AIR, health, temperature));
        return;
    }

    // --- Own state ---
    int density = (material == MAT_GAS) ? get_density(pixel) : 0;
    ivec2 vel = (material == MAT_GAS) ? unpack_velocity(pixel) : ivec2(0);

    // --- Compute outflow components (only meaningful if density > 0) ---
    // Directions: up = (0,-1), down = (0,1), left = (-1,0), right = (1,0)
    // Outward component toward neighbor N is max(0, v · unit_dir_to_N).
    int comp_up    = max(0, -vel.y);
    int comp_down  = max(0,  vel.y);
    int comp_left  = max(0, -vel.x);
    int comp_right = max(0,  vel.x);

    // Cancel components that point into a solid (no flow into walls).
    if (is_solid_for_gas(n_mat_up))    comp_up    = 0;
    if (is_solid_for_gas(n_mat_down))  comp_down  = 0;
    if (is_solid_for_gas(n_mat_left))  comp_left  = 0;
    if (is_solid_for_gas(n_mat_right)) comp_right = 0;

    int out_up    = stochastic_div(density * comp_up,    V_MAX_OUTFLOW, pos, 1u);
    int out_down  = stochastic_div(density * comp_down,  V_MAX_OUTFLOW, pos, 2u);
    int out_left  = stochastic_div(density * comp_left,  V_MAX_OUTFLOW, pos, 3u);
    int out_right = stochastic_div(density * comp_right, V_MAX_OUTFLOW, pos, 4u);

    int total_out = out_up + out_down + out_left + out_right;
    if (total_out > density) {
        // Rare due to component clamping; cap to prevent negative density.
        total_out = density;
    }

    // --- Compute inflow from each neighbor toward this cell ---
    // For neighbor N at direction d from this cell, inflow = density_N * comp(v_N, -d)
    int in_up    = 0;
    int in_down  = 0;
    int in_left  = 0;
    int in_right = 0;
    ivec2 vin_up    = ivec2(0);
    ivec2 vin_down  = ivec2(0);
    ivec2 vin_left  = ivec2(0);
    ivec2 vin_right = ivec2(0);

    if (n_mat_up == MAT_GAS) {
        int dN = get_density(n_up);
        ivec2 vN = unpack_velocity(n_up);
        // Up-neighbor is above us; it flows toward us along +y (i.e., vy > 0).
        int c = max(0, vN.y);
        in_up = stochastic_div(dN * c, V_MAX_OUTFLOW, pos, 5u);
        vin_up = vN;
    }
    if (n_mat_down == MAT_GAS) {
        int dN = get_density(n_down);
        ivec2 vN = unpack_velocity(n_down);
        int c = max(0, -vN.y);
        in_down = stochastic_div(dN * c, V_MAX_OUTFLOW, pos, 6u);
        vin_down = vN;
    }
    if (n_mat_left == MAT_GAS) {
        int dN = get_density(n_left);
        ivec2 vN = unpack_velocity(n_left);
        int c = max(0, vN.x);
        in_left = stochastic_div(dN * c, V_MAX_OUTFLOW, pos, 7u);
        vin_left = vN;
    }
    if (n_mat_right == MAT_GAS) {
        int dN = get_density(n_right);
        ivec2 vN = unpack_velocity(n_right);
        int c = max(0, -vN.x);
        in_right = stochastic_div(dN * c, V_MAX_OUTFLOW, pos, 8u);
        vin_right = vN;
    }

    int total_in = in_up + in_down + in_left + in_right;

    // --- Wall reflection: any velocity component pointing into a solid flips sign ---
    if (is_solid_for_gas(n_mat_up)    && vel.y < 0) vel.y = -vel.y;
    if (is_solid_for_gas(n_mat_down)  && vel.y > 0) vel.y = -vel.y;
    if (is_solid_for_gas(n_mat_left)  && vel.x < 0) vel.x = -vel.x;
    if (is_solid_for_gas(n_mat_right) && vel.x > 0) vel.x = -vel.x;

    // --- New density ---
    int new_density = density - total_out + total_in;
    new_density = clamp(new_density, 0, 255);

    // --- New velocity: density-weighted average, then 1/16 damping ---
    int stayed = max(0, density - total_out);
    int weight = max(1, stayed + total_in);

    ivec2 vsum = vel * stayed
               + vin_up    * in_up
               + vin_down  * in_down
               + vin_left  * in_left
               + vin_right * in_right;

    ivec2 new_vel = vsum / weight;
    new_vel = (new_vel * 15) / 16;
    new_vel = clamp(new_vel, ivec2(-8), ivec2(7));

    // --- Material transitions ---
    if (material == MAT_AIR) {
        // AIR -> GAS only if enough flow arrived.
        if (total_in >= THRESHOLD_BECOME_GAS) {
            // Use purely-inflow-weighted velocity (there's no pre-existing velocity for air).
            int w = max(1, total_in);
            ivec2 inflow_vel = (
                vin_up * in_up + vin_down * in_down +
                vin_left * in_left + vin_right * in_right
            ) / w;
            inflow_vel = (inflow_vel * 15) / 16;
            inflow_vel = clamp(inflow_vel, ivec2(-8), ivec2(7));
            imageStore(chunk_tex, pos, pack_gas(total_in, inflow_vel));
            return;
        }
        // Not enough flow — stay air, but keep heat dissipation.
        int health = get_health(pixel);
        int temperature = max(0, get_temperature(pixel) - HEAT_DISSIPATION);
        imageStore(chunk_tex, pos, make_pixel(MAT_AIR, health, temperature));
        return;
    }

    // material == MAT_GAS from here on.
    if (new_density < THRESHOLD_DISSIPATE) {
        // Dissipate — revert to air with cleared alpha/velocity.
        imageStore(chunk_tex, pos, make_pixel(MAT_AIR, 0, 0));
        return;
    }
    imageStore(chunk_tex, pos, pack_gas(new_density, new_vel));
}
```

- [ ] **Step 3: Add a debug `place_gas` to `world_manager.gd` (harness for Step 4)**

At the bottom of `scripts/world_manager.gd`, after `place_fire`, add:

```gdscript
## Debug: spawn a circular blob of gas at world_pos with given density.
func place_gas(world_pos: Vector2, radius: float, density: int) -> void:
    var center_x := int(floor(world_pos.x))
    var center_y := int(floor(world_pos.y))
    var r := int(ceil(radius))
    var affected: Dictionary = {}  # Vector2i -> Array[Vector2i]
    for dx in range(-r, r + 1):
        for dy in range(-r, r + 1):
            if dx * dx + dy * dy > r * r:
                continue
            var wx := center_x + dx
            var wy := center_y + dy
            var chunk_coord := Vector2i(floori(float(wx) / CHUNK_SIZE), floori(float(wy) / CHUNK_SIZE))
            if not chunks.has(chunk_coord):
                continue
            var local := Vector2i(posmod(wx, CHUNK_SIZE), posmod(wy, CHUNK_SIZE))
            if not affected.has(chunk_coord):
                affected[chunk_coord] = []
            affected[chunk_coord].append(local)
    var clamped_density: int = clampi(density, 0, 255)
    for chunk_coord in affected:
        var chunk: Chunk = chunks[chunk_coord]
        var data := rd.texture_get_data(chunk.rd_texture, 0)
        var modified := false
        for pixel_pos: Vector2i in affected[chunk_coord]:
            var idx := (pixel_pos.y * CHUNK_SIZE + pixel_pos.x) * 4
            if data[idx] != MaterialRegistry.MAT_AIR:
                continue
            data[idx] = MaterialRegistry.MAT_GAS
            data[idx + 1] = clamped_density
            data[idx + 2] = 0
            data[idx + 3] = (8 << 4) | 8  # packed velocity (0, 0)
            modified = true
        if modified:
            rd.texture_update(chunk.rd_texture, 0, data)
```

- [ ] **Step 4: Wire right-click in `input_handler.gd` to call `place_gas`**

Replace the contents of `scripts/input_handler.gd` with:

```gdscript
extends Node

const FIRE_RADIUS := 5.0
const GAS_RADIUS := 6.0
const GAS_DENSITY := 200

@onready var world_manager: Node2D = get_parent().get_node("WorldManager")

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed:
        var world_pos := world_manager.get_global_mouse_position()
        if event.button_index == MOUSE_BUTTON_LEFT:
            world_manager.place_fire(world_pos, FIRE_RADIUS)
        elif event.button_index == MOUSE_BUTTON_RIGHT:
            world_manager.place_gas(world_pos, GAS_RADIUS, GAS_DENSITY)
```

- [ ] **Step 5: Smoke test — run the game and spawn gas**

Launch the project (not headless):

```bash
cd /home/jeremy/Development/Godot/top-down-rogue
godot
```

In-game:
1. Right-click in an open air area. Expected: **opaque black blobs** appear where you clicked. This is a temporary artifact of the render shader sampling the placeholder texture for `MAT_GAS` and returning black via the "solid, not near air" branch. Task 6 replaces this with proper tinted compositing — the black blob is a useful "gas is actually there" signal for now.
2. Stand still next to the blob. Expected: it **does not spread on its own**. Pull-based advection is velocity-driven; a blob placed with zero initial velocity has zero outflow and zero inflow, so it sits in place. This is correct per the spec — diffusion is entirely advective. The blob will only move/dissipate once something injects velocity into it (Task 9).
3. Left-click somewhere else. Expected: fire (left-click) still works exactly as before. Wood still burns, air still cools.

To verify gas is actually in the chunk data (not just visible due to render bug), temporarily add `print("placed gas cells: ", affected[chunk_coord].size())` inside the `place_gas` modification loop in `world_manager.gd`. Remove after verifying.

Note: you cannot yet verify AIR → GAS transitions or the dissipation threshold because no velocity source exists yet. That verification comes in Task 9 after the player pushes gas around.

- [ ] **Step 6: Commit**

```bash
git add shaders/simulation.glsl scripts/world_manager.gd scripts/input_handler.gd
git commit -m "feat(gas): pull-based advection + wall reflection + debug place_gas"
```

---

## Task 6: Gas tint compositing in `render_chunk.gdshader`

Goal: make gas cells visible so Task 5 can be verified visually, and subsequent tasks can be tuned by eye.

**Files:**
- Modify: `shaders/render_chunk.gdshader`

- [ ] **Step 1: Rewrite the `fragment()` path to treat gas as air-plus-tint**

In `shaders/render_chunk.gdshader`, replace the entire `void fragment()` body with:

```glsl
void fragment() {
    ivec2 px = ivec2(UV * float(CHUNK_SIZE));
    px = clamp(px, ivec2(0), ivec2(CHUNK_SIZE - 1));

    vec4 data = read_pixel(px);
    int mat = get_material(data);

    // --- Gas overlay: remember the tint and fall through as if this cell were air. ---
    vec4 gas_tint = vec4(0.0);
    float gas_alpha = 0.0;
    if (mat == MAT_GAS) {
        vec4 tint = MATERIAL_TINT[MAT_GAS];
        gas_tint = vec4(tint.rgb, 1.0);
        gas_alpha = tint.a * data.g;  // density in G, 0..1
        mat = MAT_AIR;
    }

    vec4 base_color = vec4(0.0);

    if (mat == MAT_AIR) {
        if (layer_mode == 0) {
            base_color = vec4(0.0);
        } else {
            bool found_wall = false;
            for (int d = 1; d <= wall_height; d++) {
                if (found_wall) break;
                ivec2 check_pos = ivec2(px.x, px.y + d);
                vec4 src_data = read_pixel_extended(check_pos);
                if (is_solid_extended(check_pos)) {
                    base_color = vec4(sample_material_texture(get_material(src_data), px.x, d, src_data, px), 1.0);
                    found_wall = true;
                }
            }
            if (!found_wall) {
                base_color = vec4(0.0);
            }
        }
    } else {
        if (layer_mode == 1) {
            base_color = vec4(0.0);
        } else {
            if (near_air(px)) {
                base_color = vec4(material_color(data, px), 1.0);
            } else {
                base_color = vec4(0.0, 0.0, 0.0, 1.0);
            }
        }
    }

    // --- Composite gas tint over base color. Preserves wall faces behind gas. ---
    if (gas_alpha > 0.0) {
        // Straight-alpha over: out.rgb = mix(base.rgb, tint.rgb, gas_alpha);
        //                     out.a   = base.a + (1 - base.a) * gas_alpha
        //                             = max(base.a, gas_alpha) for our base.a ∈ {0,1}
        vec3 rgb = mix(base_color.rgb, gas_tint.rgb, gas_alpha);
        float a = max(base_color.a, gas_alpha);
        COLOR = vec4(rgb, a);
    } else {
        COLOR = base_color;
    }
}
```

- [ ] **Step 2: Smoke test — right-click to spawn a visible green cloud**

Launch the project:

```bash
cd /home/jeremy/Development/Godot/top-down-rogue
godot
```

In-game:
1. Move to an open air area surrounded by solid walls (stone/wood).
2. Right-click to spawn a gas blob.
3. Expected: a translucent green cloud appears. Wall face extensions from neighboring solids should still be visible *through* the green. Over several seconds the cloud slowly spreads and dissipates (density drops < 4 at the edges and those cells become air again).
4. Spawn a blob right next to a wall. Expected: gas does not pass through the wall. Any velocity that had it flowing into the wall flips (reflection); watch for brief rebounds.
5. Left-click should still place fire and work identically to before.

If the gas appears but obliterates wall faces behind it, re-verify the `mat = MAT_AIR;` line and that `base_color` is computed using the rewritten `mat` (not the original).

- [ ] **Step 3: Commit**

```bash
git add shaders/render_chunk.gdshader
git commit -m "feat(gas): composite density-tinted gas over air base path"
```

---

## Task 7: `GasInjector` helper + per-frame SSBO upload

Goal: convert players/bodies in the `gas_interactors` group into per-chunk AABB payloads, and upload them each frame.

**Files:**
- Create: `scripts/gas_injector.gd`
- Modify: `scripts/world_manager.gd`

- [ ] **Step 1: Create `scripts/gas_injector.gd`**

Create `scripts/gas_injector.gd` with:

```gdscript
class_name GasInjector
extends RefCounted

const MAX_INJECTIONS_PER_CHUNK := 32
const MIN_SPEED_SQ := 0.25
# Velocity-to-cell-per-frame scale. A body moving 60 px/s -> 1 cell/frame at 60 fps.
const VELOCITY_SCALE := 1.0 / 60.0

const CHUNK_SIZE := 256
const HEADER_BYTES := 16
const BODY_BYTES := 32
const BUFFER_BYTES := HEADER_BYTES + BODY_BYTES * MAX_INJECTIONS_PER_CHUNK


## Returns per-frame injection bytes for the chunk at `coord`.
## `scene` is used to look up nodes in the `gas_interactors` group.
static func build_payload(scene: SceneTree, coord: Vector2i) -> PackedByteArray:
    var out := PackedByteArray()
    out.resize(BUFFER_BYTES)
    out.fill(0)

    var chunk_world_rect := Rect2(
        Vector2(coord) * CHUNK_SIZE,
        Vector2(CHUNK_SIZE, CHUNK_SIZE)
    )

    var count := 0
    for node in scene.get_nodes_in_group("gas_interactors"):
        if count >= MAX_INJECTIONS_PER_CHUNK:
            break
        if not node is Node2D:
            continue

        var linvel := _get_node_velocity(node)
        if linvel.length_squared() < MIN_SPEED_SQ:
            continue

        var aabb_world := _world_aabb_of(node)
        if not chunk_world_rect.intersects(aabb_world):
            continue

        # Convert to chunk-local *inclusive min / exclusive max* integer cell coords.
        var min_local := Vector2i(
            floori(aabb_world.position.x - chunk_world_rect.position.x),
            floori(aabb_world.position.y - chunk_world_rect.position.y)
        )
        var max_local := Vector2i(
            ceili(aabb_world.end.x - chunk_world_rect.position.x),
            ceili(aabb_world.end.y - chunk_world_rect.position.y)
        )
        min_local = min_local.clamp(Vector2i.ZERO, Vector2i(CHUNK_SIZE, CHUNK_SIZE))
        max_local = max_local.clamp(Vector2i.ZERO, Vector2i(CHUNK_SIZE, CHUNK_SIZE))
        if max_local.x <= min_local.x or max_local.y <= min_local.y:
            continue

        var vx := clampi(int(round(linvel.x * VELOCITY_SCALE)), -8, 7)
        var vy := clampi(int(round(linvel.y * VELOCITY_SCALE)), -8, 7)
        if vx == 0 and vy == 0:
            continue

        var offset := HEADER_BYTES + count * BODY_BYTES
        out.encode_s32(offset + 0,  min_local.x)
        out.encode_s32(offset + 4,  min_local.y)
        out.encode_s32(offset + 8,  max_local.x)
        out.encode_s32(offset + 12, max_local.y)
        out.encode_s32(offset + 16, vx)
        out.encode_s32(offset + 20, vy)
        # offset +24, +28 are pad bytes, already zero.
        count += 1

    out.encode_s32(0, count)
    return out


static func _get_node_velocity(node: Node2D) -> Vector2:
    if node is CharacterBody2D:
        return (node as CharacterBody2D).velocity
    if node is RigidBody2D:
        return (node as RigidBody2D).linear_velocity
    # Any Node2D exposing a `velocity` property.
    if "velocity" in node:
        var v = node.get("velocity")
        if v is Vector2:
            return v
    return Vector2.ZERO


static func _world_aabb_of(node: Node2D) -> Rect2:
    # Try CollisionObject2D.get_shape_owners for a proper AABB.
    if node is CollisionObject2D:
        var co := node as CollisionObject2D
        var rect := Rect2()
        var first := true
        for owner_id in co.get_shape_owners():
            var owner_id_int: int = owner_id
            var transform: Transform2D = co.shape_owner_get_transform(owner_id_int)
            for i in range(co.shape_owner_get_shape_count(owner_id_int)):
                var shape: Shape2D = co.shape_owner_get_shape(owner_id_int, i)
                var shape_rect := _shape_aabb(shape, transform)
                if first:
                    rect = shape_rect
                    first = false
                else:
                    rect = rect.merge(shape_rect)
        if not first:
            rect.position += node.global_position
            return rect
    # Fallback: treat the node as a 1-pixel point at its position.
    return Rect2(node.global_position - Vector2(0.5, 0.5), Vector2(1, 1))


static func _shape_aabb(shape: Shape2D, xform: Transform2D) -> Rect2:
    if shape is RectangleShape2D:
        var half: Vector2 = (shape as RectangleShape2D).size * 0.5
        var local := Rect2(-half, half * 2.0)
        return xform * local
    if shape is CircleShape2D:
        var r: float = (shape as CircleShape2D).radius
        var local := Rect2(Vector2(-r, -r), Vector2(r * 2.0, r * 2.0))
        return xform * local
    if shape is CapsuleShape2D:
        var cs := shape as CapsuleShape2D
        var h := cs.height * 0.5 + cs.radius
        var local := Rect2(Vector2(-cs.radius, -h), Vector2(cs.radius * 2.0, h * 2.0))
        return xform * local
    # Fallback: small box centered on origin.
    return xform * Rect2(Vector2(-1, -1), Vector2(2, 2))
```

- [ ] **Step 2: Call `GasInjector.build_payload` each frame in `_run_simulation`**

In `scripts/world_manager.gd`, in `_run_simulation()`, **immediately before** the `var compute_list := rd.compute_list_begin()` line, insert:

```gdscript
    # Upload per-chunk injection payloads before dispatch.
    var tree := get_tree()
    for coord in chunks:
        var chunk: Chunk = chunks[coord]
        if not chunk.injection_buffer.is_valid():
            continue
        var payload := GasInjector.build_payload(tree, coord)
        rd.buffer_update(chunk.injection_buffer, 0, payload.size(), payload)
```

- [ ] **Step 3: Smoke test — verify payload is being built without errors**

Launch the project:

```bash
cd /home/jeremy/Development/Godot/top-down-rogue
godot
```

Expected: no shader or GDScript errors, gas placement still works as before (from Task 6), simulation framerate roughly unchanged. The player is not yet in the `gas_interactors` group (Task 8), so the payload count is always 0 and no visible change should occur.

To validate payload construction, temporarily add `print("payload count: ", payload.decode_s32(0))` inside the upload loop and confirm it prints 0 every frame. Remove after verifying.

- [ ] **Step 4: Commit**

```bash
git add scripts/gas_injector.gd scripts/world_manager.gd
git commit -m "feat(gas): GasInjector helper + per-frame SSBO upload"
```

---

## Task 8: Implement the shader injection pass

Goal: replace the `try_inject_rigidbody_velocity` stub from Task 3 so the SSBO bytes actually affect gas cells.

**Files:**
- Modify: `shaders/simulation.glsl`

- [ ] **Step 1: Replace the `try_inject_rigidbody_velocity` stub**

Find the stub in `shaders/simulation.glsl`:

```glsl
bool try_inject_rigidbody_velocity(ivec2 pos, int material, inout vec4 pixel) {
    return false;  // stub — Task 5
}
```

Replace it with:

```glsl
bool try_inject_rigidbody_velocity(ivec2 pos, int material, inout vec4 pixel) {
    if (material != MAT_GAS) return false;
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

- [ ] **Step 2: Smoke test — still no visible change until player joins group**

Launch the project:

```bash
cd /home/jeremy/Development/Godot/top-down-rogue
godot
```

Expected: no errors. Placing gas still works. Player still doesn't affect it (Task 9 adds the player to the group).

- [ ] **Step 3: Commit**

```bash
git add shaders/simulation.glsl
git commit -m "feat(gas): implement AABB injection pass in simulation shader"
```

---

## Task 9: Add the player to the `gas_interactors` group

**Files:**
- Modify: `scripts/player_controller.gd`

- [ ] **Step 1: Join the group in `_ready`**

In `scripts/player_controller.gd`, inside `_ready()`, **after** the existing `motion_mode = CharacterBody2D.MOTION_MODE_FLOATING` line and **before** the `await get_tree().process_frame` lines, insert:

```gdscript
    add_to_group("gas_interactors")
```

- [ ] **Step 2: Smoke test — player disturbs gas clouds**

Launch the project:

```bash
cd /home/jeremy/Development/Godot/top-down-rogue
godot
```

In-game:
1. Spawn a gas cloud via right-click in an open area.
2. Walk into the cloud (WASD). Expected: the cloud visibly deforms in the direction of player movement — denser streaks appear on the trailing edge, gas "parts" in front of the player. The effect strength scales with `max_speed` (120 px/s in `player_controller.gd`) and `VELOCITY_SCALE` (1/60) in `gas_injector.gd`. At 120 px/s you get `round(120 / 60) = 2` cells/frame — visible but not overwhelming.
3. Stand still inside gas. Expected: nothing changes — `MIN_SPEED_SQ = 0.25` filters out a stationary player. (If the velocity oscillates due to friction, tiny unwanted injections may occur; if that happens, tune `MIN_SPEED_SQ` up.)
4. Push gas against a wall. Expected: it reflects and does not pass through.

If injection never seems to trigger, the most likely culprit is velocity rounding — the player's per-frame velocity in cells is < 1. Temporarily widen the window: spawn a larger, denser cloud and move at full speed across it.

- [ ] **Step 3: Commit**

```bash
git add scripts/player_controller.gd
git commit -m "feat(gas): add player to gas_interactors group"
```

---

## Task 10: End-to-end verification + tuning pass

Goal: verify the spec requirements are met as a whole and flag any tuning gaps for the user.

**Files:** none (verification only)

- [ ] **Step 1: Spec checklist walk-through**

Run through each behavior from `docs/superpowers/specs/2026-04-07-gas-material-design.md` §"Behavior summary" and confirm it holds in-game:

- [ ] `MAT_GAS` stores density in G, velocity in A. Confirm by placing gas and inspecting a chunk via `rd.texture_get_data` in a debug print.
- [ ] Pull-based advection visibly spreads gas.
- [ ] Gas reflects off walls (no bleed-through).
- [ ] Density below 4 converts back to air (clouds dissipate, not stay forever).
- [ ] Player AABB injection visibly deforms clouds when moving.
- [ ] Injection only affects existing gas — walking through empty space does not create gas.
- [ ] Gas renders as green tint; wall face extensions visible through gas.
- [ ] Gas is inert: no temperature spread, no collider, no wall extension. Walk through gas freely; place fire next to gas and confirm it doesn't ignite.

- [ ] **Step 2: Cross-chunk boundary test**

Spawn a gas blob straddling two chunks (near a chunk boundary — chunks are 256 px wide). Push it so the velocity points across the boundary. Expected: gas flows continuously into the neighbor chunk without a visible seam.

If a seam appears, verify `_build_sim_uniform_set` binds the injection buffer at binding 5 for both chunks and that `read_neighbor` in the shader correctly handles the cardinal neighbor offsets.

- [ ] **Step 3: Fire interaction regression check**

Confirm the existing burning logic still works end-to-end:

1. Place wood (via existing generation).
2. Left-click to set fire.
3. Fire spreads through wood as before.
4. Air cells still dissipate heat (watch flame trails cooling off).

If heat dissipation stopped working for air cells, re-check Task 5 Step 2 — the AIR branch of `gas_advect_pull` must still compute `temperature = max(0, get_temperature(pixel) - HEAT_DISSIPATION)` in the "no gas neighbor" fast path and in the "not enough inflow" fallback.

- [ ] **Step 4: Performance check**

Open the debug overlay (if one exists; otherwise watch `Engine.get_frames_per_second()` via a temporary HUD print). Baseline framerate with no gas should be unchanged. With a single 6-radius blob onscreen, framerate should drop negligibly. With ten 10-radius blobs, framerate should remain > 30 fps on a modest GPU.

If performance is bad, the most likely culprit is the inner injection loop being per-cell even when `count == 0` — confirm the shader emits an early branch on `count <= 0` (the `int n = min(injections.count, MAX_INJECTIONS_PER_CHUNK)` plus `for (int i = 0; i < n; i++)` is already cheap for n=0, so this should not be an issue).

- [ ] **Step 5: Commit any final tuning you applied (if any)**

If Steps 1–4 uncovered a tuning change (e.g., adjusted `VELOCITY_SCALE`, `MIN_SPEED_SQ`, or `GAS_DENSITY`), commit it:

```bash
git add -u
git commit -m "feat(gas): tune constants after end-to-end verification"
```

Otherwise, no commit is needed here.

---

## Out-of-scope (confirmed in spec)

These are explicitly not part of this plan:
- Buoyancy (hot gas rising)
- Multiple gas species
- Gas → rigidbody force-back
- Mass-conserving advection via back-trace
- Spontaneous gas creation by moving bodies
- Gas leaking through porous materials

If any of those are later desired, add a new spec and a new plan.
