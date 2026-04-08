# Gas Material Design

## Overview

A new `MAT_GAS` material that behaves as part of the pixel-terrain simulation
but exhibits fluid-like motion (advection, diffusion, wall reflection) and
reacts to rigidbody movement. Inspired by the Unity `FluidPlayGround`
implementation (Stam-style 2D solver), but reworked so the gas lives inside
the existing chunk texture and simulation compute shader rather than as a
screen-space overlay.

## Problem

The existing terrain simulation supports discrete materials (air, wood,
stone) with per-cell health and temperature. There is no material that
flows, disperses, or reacts to moving physics bodies. The desired behavior
is a "gas" that:

- Lives as a first-class material in the chunk texture (part of terrain).
- Spreads like a fluid — density diffuses, velocity advects, walls reflect.
- Is pushed around by rigidbodies (starting with the player).
- Renders as a translucent tint over whatever is behind it.
- Does not burn, does not block collision, is not flammable.

## Solution

### Data layout

Gas reuses the existing `rgba8` chunk texture — **no new textures, no new
render targets, no new compute passes**. For cells whose R-channel holds
`MAT_GAS`, the other channels are reinterpreted:

| Channel | Non-gas cells   | Gas cells                                     |
|---------|-----------------|-----------------------------------------------|
| R       | material id     | `MAT_GAS`                                     |
| G       | health          | **density** (0–255)                           |
| B       | temperature     | 0 (unused — gas is inert)                     |
| A       | 0 (unused)      | **packed velocity** `(vx+8)<<4 \| (vy+8)`     |

Velocity range is `vx, vy ∈ [-8, 7]` per axis (4 bits each). Speeds above
this clamp. `V_MAX_OUTFLOW = 8` is the normalizer used throughout the
advection math.

**Shader helpers (added to `simulation.glsl`):**

```glsl
int get_density(vec4 p) { return int(round(p.g * 255.0)); }

ivec2 unpack_velocity(vec4 p) {
    uint a = uint(round(p.a * 255.0));
    return ivec2(int(a >> 4) - 8, int(a & 15u) - 8);
}

vec4 pack_gas(int density, ivec2 vel) {
    uint a = uint(clamp(vel.x + 8, 0, 15)) << 4
           | uint(clamp(vel.y + 8, 0, 15));
    return vec4(float(MAT_GAS) / 255.0,
                float(density) / 255.0,
                0.0,
                float(a) / 255.0);
}
```

### Registry entry

`MaterialDef` gains a new optional `tint_color: Color` field (defaults to
`Color(0,0,0,0)` for non-tinted materials). The gas entry:

```gdscript
materials.append(MaterialDef.new(
    "GAS", "",               # no texture — flat color tint
    false, 0, 0,             # not flammable
    false, false,            # no collider, no wall extension
    Color(0.4, 0.9, 0.3, 1.0)))   # tint_color (green, example)
```

The GLSL generator emits a new `MATERIAL_TINT[]` array in
`materials.glslinc`:

```glsl
const vec4 MATERIAL_TINT[MAT_COUNT] = vec4[MAT_COUNT](
    vec4(0.0, 0.0, 0.0, 0.0),   // AIR
    vec4(0.0, 0.0, 0.0, 0.0),   // WOOD
    vec4(0.0, 0.0, 0.0, 0.0),   // STONE
    vec4(0.4, 0.9, 0.3, 1.0)    // GAS
);
```

### Simulation — pull-based advection

`simulation.glsl` is already pull-based (each invocation reads neighbors
and writes only its own pixel), so gas fits in without atomics or races.
The shader's `main()` is restructured as:

```glsl
void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= CHUNK_SIZE || pos.y >= CHUNK_SIZE) return;

    vec4 pixel = imageLoad(chunk_tex, pos);
    int material = get_material(pixel);

    // 1. Rigidbody AABB injection — writes and returns if injected.
    if (try_inject_rigidbody_velocity(pos, material, pixel)) return;

    // 2. Gas advection — runs every frame, pull-based, no phase guard.
    vec4 n_up    = read_neighbor(pos + ivec2(0, -1));
    vec4 n_down  = read_neighbor(pos + ivec2(0,  1));
    vec4 n_left  = read_neighbor(pos + ivec2(-1, 0));
    vec4 n_right = read_neighbor(pos + ivec2( 1, 0));

    if (material == MAT_GAS || material == MAT_AIR) {
        gas_advect_pull(pos, pixel, n_up, n_down, n_left, n_right);
        return;
    }

    // 3. Existing checkerboard burning logic (unchanged).
    if ((pos.x + pos.y) % 2 != pc.phase) return;
    // ... existing heat/burning code ...
}
```

Burning still uses the checkerboard phase guard. Gas does not.

**Heat dissipation for air cells.** The current shader decrements
temperature on `MAT_AIR` cells each frame. Since air cells now go down
the gas path and early-return, `gas_advect_pull` is responsible for
preserving this behavior: if C remains `MAT_AIR` after advection (i.e.,
no AIR → GAS transition), the function still writes back the air pixel
with `temperature = max(0, temperature - HEAT_DISSIPATION)`. Gas cells
keep B = 0 (inert) as specified.

#### Pull advection math

For a cell `C` with current density `d_C` and velocity `v_C = (vx, vy)`:

**Outflow (only if C is gas).** For each cardinal direction `d ∈
{up,down,left,right}`, the outward component is `comp_d = max(0, v_C · d)`.
The raw outflow amount toward direction `d` is:

    out_d = (d_C * comp_d) / V_MAX_OUTFLOW     // integer divide

If the neighbor in direction `d` is solid (neither `MAT_AIR` nor
`MAT_GAS`), that component is **not redistributed** — the flow is
cancelled and the corresponding component of `v_C` is **reflected**
(sign-flipped) for next frame. This simulates gas bouncing off walls.

Total outflow `out_total = sum of out_d over non-solid directions`,
capped at `d_C`.

**Inflow.** For each neighbor `N` at offset `d` from C, look at `N`'s
velocity `v_N`. The component of `v_N` pointing toward C is
`in_comp = max(0, v_N · (-d))`. Pull:

    in_from_N = (d_N * in_comp) / V_MAX_OUTFLOW

Sum across all four non-solid neighbors → `in_total`.

**New density.**

    d_C_new = d_C - out_total + in_total

**Velocity advection.** The new velocity at C is a density-weighted
average of the velocities that remain in/flowed into C, then damped:

    v_sum       = v_C * (d_C - out_total)
                + v_up * in_from_up + v_down * in_from_down
                + v_left * in_from_left + v_right * in_from_right
    v_weight    = max(1, d_C - out_total + in_total)
    v_C_new     = v_sum / v_weight
    v_C_new     = (v_C_new * 15) / 16    // 1/16 damping per frame

After damping, apply wall reflection: for each direction whose neighbor is
solid, flip the corresponding velocity component if it points into the
wall.

**AIR → GAS transition.** If C was `MAT_AIR` and `in_total >
THRESHOLD_BECOME_GAS` (e.g., 4), C becomes `MAT_GAS` with density
`in_total` and the weighted-average velocity of the incoming flow.

**GAS → AIR transition.** If C was `MAT_GAS` and `d_C_new <
THRESHOLD_DISSIPATE` (e.g., 4), C becomes `MAT_AIR` with cleared alpha.
Gas dissipates solely via diffusion — no timer-based decay.

#### Stochastic rounding for low-density flows

Integer division truncates sub-unit flows to zero (a cell with density 3
and velocity 1 would never lose mass otherwise). To keep gas moving, the
shader uses the existing `hash()` function for stochastic rounding:

```glsl
int raw = d * comp;                         // units of density * comp
int base = raw / V_MAX_OUTFLOW;
int rem  = raw % V_MAX_OUTFLOW;
uint rng = hash(uint(pos.x) ^ hash(uint(pos.y) ^ uint(pc.frame_seed) ^ salt));
int amount = base + (int(rng % uint(V_MAX_OUTFLOW)) < rem ? 1 : 0);
```

`salt` differentiates the four directional outflows so they use
independent random streams.

#### Conservation note

Pull-based advection with independently computed outflow and inflow
fractions is **not exactly mass-conserving** — tiny numerical drift is
possible. Because both sides use the same `V_MAX_OUTFLOW` constant and
identical `comp` formulas, drift is bounded and imperceptible in practice.
Proper Eulerian back-trace advection would eliminate drift but is overkill
for integer density on a 4-neighbor grid.

### Rigidbody injection

**CPU side.** A helper `scripts/gas_injector.gd` collects rigidbodies each
frame and builds a per-chunk SSBO payload:

```gdscript
# scripts/gas_injector.gd
const MAX_INJECTIONS_PER_CHUNK := 32
const MIN_SPEED_SQ := 0.1

static func collect_injections(chunk: Chunk) -> PackedByteArray:
    var bodies: Array = []
    for body in chunk.get_tree().get_nodes_in_group("gas_interactors"):
        if not body is RigidBody2D: continue
        var linvel: Vector2 = body.linear_velocity
        if linvel.length_squared() < MIN_SPEED_SQ: continue
        var aabb := _world_aabb_of(body)
        if not chunk.world_rect.intersects(aabb): continue
        bodies.append({
            "min": chunk.world_to_cell(aabb.position),
            "max": chunk.world_to_cell(aabb.end),
            "vel": _encode_velocity(linvel),
        })
        if bodies.size() == MAX_INJECTIONS_PER_CHUNK: break
    return _pack_ssbo(bodies)
```

- Only bodies in the `"gas_interactors"` group are considered (opt-in). The
  player is added to this group in `player_controller.gd` `_ready()`.
  Initially only the player participates.
- AABBs are converted to chunk-local integer cell coordinates on CPU and
  clamped to chunk bounds.
- Linear velocity is scaled and clamped to `[-8, 7]` per axis via
  `_encode_velocity(linvel)` which does
  `clamp(round(linvel * k), -8, 7)`. The scale `k` is a tunable constant
  (starting guess: world-units-per-second scaled so a body moving "one
  cell per frame" produces packed velocity 1).

**GPU side.** An `std430` SSBO at `set = 0, binding = 5`:

```glsl
struct InjectionAABB {
    ivec2 aabb_min;    // inclusive, chunk-local cell coords
    ivec2 aabb_max;    // exclusive
    ivec2 velocity;    // cells/frame, per-axis in [-8, 7]
    int _pad0, _pad1;  // std430 alignment
};

layout(set = 0, binding = 5, std430) readonly buffer InjectionBuffer {
    int count;
    int _pad[3];
    InjectionAABB bodies[];
} injections;
```

**Injection pass** (runs first in `main()`, adds body velocity into
overlapping gas cells; does not create gas from thin air):

```glsl
bool try_inject_rigidbody_velocity(ivec2 pos, int material, inout vec4 pixel) {
    if (material != MAT_GAS) return false;   // injection only affects gas
    bool wrote = false;
    for (int i = 0; i < injections.count; i++) {
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

Injection **only touches existing gas cells**. Air cells that a rigidbody
passes through are not written — no spontaneous gas generation. Subsequent
advection frames carry the imparted velocity through nearby gas naturally.

The injection loop runs once per compute invocation (cheap; up to 32 AABB
tests). Chunks with no overlapping bodies get `count = 0` and the loop is
a no-op.

**Dispatch flow (`world_manager.gd` per frame):**

1. For each active chunk, call `GasInjector.collect_injections(chunk)`
   and upload the resulting bytes into a persistent SSBO (per-chunk or
   pooled).
2. Dispatch `simulation.glsl` as usual, with the SSBO bound at
   `binding = 5`.

### Rendering

Gas renders as a density-driven tint **composited over** whatever the
existing renderer would draw if the cell were air. This preserves
fake-wall extensions and any other per-pixel effects behind the gas.

**Render shader change (`render_chunk.gdshader`):**

```glsl
int mat = int(round(pixel.r * 255.0));
float gas_alpha = 0.0;
vec4 gas_tint = vec4(0.0);

if (mat == MAT_GAS) {
    gas_tint = MATERIAL_TINT[mat];
    gas_alpha = gas_tint.a * pixel.g;   // density in G
    mat = MAT_AIR;                       // fall through as if cell were air
}

// ... existing textured / wall-extension path runs with mat possibly
// rewritten to MAT_AIR. Wall faces from neighboring solids draw
// into this cell normally.
vec4 base_color = /* existing path */;

frag_color = mix(base_color, vec4(gas_tint.rgb, 1.0), gas_alpha);
```

`HAS_WALL_EXTENSION[MAT_GAS]` is `false` in the registry, so neighbors
treat gas cells the same as air when deciding whether to draw their wall
face. No other render-shader changes are required.

## Behavior summary

- `MAT_GAS` is a first-class material stored in R, with density in G,
  velocity packed in A.
- Pull-based advection moves density between gas and air cells each frame.
  Gas **reflects** off solid walls (velocity component normal to the wall
  flips sign).
- Cells become gas when enough density flows in (`in_total > 4`) and
  revert to air when density drops below threshold (`< 4`). No timer-based
  decay; dissipation is purely diffusive.
- The player's AABB injects linear velocity into overlapping gas cells
  every frame. Bigger/faster bodies cause bigger disturbances.
- Gas is rendered as a flat density-modulated tint composited over the
  underlying (air-treated) render path.
- Gas is **inert**: no temperature participation, no burning, no collider,
  no wall extension.

## Files changed / added

**Added:**
- `scripts/gas_injector.gd` — helper that collects rigidbodies in the
  `gas_interactors` group, converts to per-chunk AABB lists, packs SSBO
  bytes.

**Modified:**
- `scripts/material_registry.gd` — add `tint_color: Color` field to
  `MaterialDef`, append `GAS` entry.
- `tools/generate_material_glsl.gd` — emit `MATERIAL_TINT[]` array.
- `shaders/simulation.glsl` — add velocity pack/unpack helpers, add
  injection loop, add gas pull-advection block, reorder so gas logic runs
  before the checkerboard phase-skip.
- `shaders/render_chunk.gdshader` — composite density-driven tint over
  the air-treated base color path for gas cells.
- `scripts/world_manager.gd` — allocate/upload per-chunk injection SSBO
  each frame, bind to simulation dispatch at `binding = 5`.
- `scripts/player_controller.gd` — add player to `gas_interactors` group
  in `_ready`.

**Not added:** no new textures, no new render targets, no new compute
shaders, no CPU-side fluid solver. The whole feature sits on top of the
existing simulation dispatch.

## Tuning constants

Starting values; expect to tweak during implementation:

| Constant                 | Value | Meaning                                         |
|--------------------------|-------|-------------------------------------------------|
| `V_MAX_OUTFLOW`          | 8     | Velocity-to-outflow normalizer                  |
| `THRESHOLD_BECOME_GAS`   | 4     | Min inflow for AIR → GAS transition             |
| `THRESHOLD_DISSIPATE`    | 4     | Min density to stay GAS                         |
| Damping per frame        | 15/16 | Velocity decay when not replenished             |
| `MAX_INJECTIONS_PER_CHUNK` | 32  | SSBO cap for rigidbody AABBs per chunk          |
| `MIN_SPEED_SQ`           | 0.1   | Ignore barely-moving bodies                     |

## Out of scope (possible future work)

- Buoyancy: hot gas rising (would need to reclaim the B-channel or add
  temperature coupling).
- Multiple gas types in one cell (would need density summing and a second
  gas material).
- Gas → rigidbody force-back (sample field at body center, apply impulse).
- Proper mass-conserving advection (Eulerian back-trace).
- Gas creation from moving bodies (injection currently only affects
  existing gas cells).
- Gas leaking through porous materials.
