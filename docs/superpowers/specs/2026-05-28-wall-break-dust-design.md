# Wall-break Dust — Design

## Problem

Carving terrain has almost no feedback. Breaking a wall instantly removes
pixels with only a handful of small flying chips (`src/core/juice/terrain_impact.gd`),
which is not "juicy" the way enemy blood bursts are
(`src/enemies/enemy.gd` → `TerrainSurface.place_blood`).

We want breaking walls to throw out **dust**: a GPU-simulated material, similar
to blood but much denser and reluctant to flow, colored like the wall it came
from, that bursts outward and settles in place permanently.

## Goals

- A new GPU-simulated material `MAT_DUST` that bursts outward when walls break.
- Denser and more sluggish than blood — settles quickly, spreads little, piles up.
- Rendered in the **source wall's color** (stone → grey, dirt → brown, wood → tan,
  coal → near-black, ice → pale blue).
- No collider — a visual fluid overlay like blood; does not affect movement.
- Persists indefinitely (no time-based fade); only fully-empty cells are cleared.
- Spawned as an outward burst from destroyed wall pixels; the carved cavity stays
  mostly open.

## Non-goals

- Does **not** replace or modify the existing flying-chip particles in
  `terrain_impact.gd` — that system stays untouched and is entirely separate.
- Dust piles are not solid and do not block movement or pathfinding.
- Only the melee carve path emits dust in this change. Explosions / other
  wall-clears can reuse the same injection later but are out of scope.
- No time-based dissipation or accumulation cleanup.

## Background — how the existing pipeline works

- Per-chunk RGBA8 texture. Channel layout for solids: **R**=material id,
  **G**=health, **B**=temperature, **A**=packed velocity. Fluids reuse the same
  texture with: **R**=id, **G**=density (0–255), **A**=packed velocity nibbles
  (`vx<<4|vy`, each biased by 8), **B** free (lava uses it for temperature).
- Fluids are simulated on the GPU in `shaders/compute/simulation.glsl`, which
  `#include`s one `simulate_*` per fluid from `shaders/include/sim/*.glslinc` and
  calls them in priority order. Each returns `true` if it fully processed the cell.
- `blood.glslinc` is a velocity-advected density fluid using a pull model: each
  cell pulls inflow from blood neighbors and pushes its own density out along its
  velocity. Velocity decays, density below `THRESHOLD_DISSIPATE` clears to air.
- Walls are carved by `shaders/compute/melee_arc.glsl`. The melee weapon makes two
  arc calls (`src/weapons/melee_weapon.gd:117` and `:125`):
  - Fluid push pass (`damage = -1`): pushes fluids (the `else` branch in
    `melee_arc.glsl`), never destroys solids.
  - Solid carve pass (`damage ≥ 0`, `is_solid_pass`): targets
    `[DIRT, WOOD, STONE, COAL, ICE]`, clears matching pixels to air, and appends a
    `HitEntry{world_x, world_y, mat_id, scale}` to a buffer.
  - `is_target(mat)` gates every invocation up front; air and dust are not in the
    solid target list, so they never reach the carve branch.
- `world_manager._drain_terrain_impacts()` reads the hit buffer and plays the
  flying-chip particles (capped at 16/frame). Unchanged by this design.
- Rendering: `shaders/visual/render_chunk.gdshader` composites a fluid overlay for
  `GAS`/`LAVA`/`BLOOD` using `MATERIAL_TINT[mat]`, alpha scaled by density `data.g`,
  then falls through as if the cell were air to preserve wall faces behind it.
- Material metadata lives in `src/autoload/material_registry.gd` and is mirrored
  into two generated includes by `tools/generate_material_glsl.gd`:
  `shaders/generated/materials.glslinc` (compute) and `materials.gdshaderinc`
  (visual). These contain `MAT_*` constants and arrays like `IS_FLUID`,
  `HAS_COLLIDER`, `MATERIAL_TINT`, `MATERIAL_GLOW`.

## Design

### 1. Material registration

Add `MAT_DUST` in `material_registry.gd`:

- `fluid = true` (simulated like the other fluids; also makes it pushable by the
  melee fluid pass and by the rigidbody injector — bodies/swings nudge settled
  dust, but never create new dust).
- `has_collider = false`, `flammable = false`, `hardness = 0`, `damage = 0`.
- A neutral fallback `tint_color` (e.g. light grey) for safety; the renderer
  overrides the visible color per source material, so this is rarely used.

Re-run `tools/generate_material_glsl.gd` to regenerate `materials.glslinc` and
`materials.gdshaderinc`. This updates `MAT_COUNT`, adds `MAT_DUST`, and extends
`IS_FLUID`/`HAS_COLLIDER`/`MATERIAL_TINT`/etc.

### 2. Pixel layout for dust

Same channels as blood, with **B repurposed to carry the source wall id**:

| Channel | Meaning |
|---------|---------|
| R | `MAT_DUST` |
| G | density 0–255 |
| B | source material id (the wall it came from: DIRT/WOOD/STONE/COAL/ICE) |
| A | packed velocity `vx<<4 | vy`, each biased by 8 |

The source id must be propagated through advection so flying/settling dust keeps
the right color.

### 3. Simulation — `shaders/include/sim/dust.glslinc`

New file mirroring `blood.glslinc`'s pull-based advection, with these differences:

- **Helpers:** `get_density_dust`, `unpack_velocity_dust`, `pack_dust(density, vel, source)`,
  `is_solid_for_dust(mat)` (solid = anything that is not air and not dust).
- **Source propagation:** `pack_dust` writes the source id into B. An existing dust
  cell keeps its own source. An air cell that becomes dust inherits the source id
  of its **dominant inflow neighbor** (the dust neighbor contributing the most
  inflow this step).
- **Sluggish tuning constants (local to this file):**
  - `DUST_MAX_OUTFLOW ≈ 4` (vs blood's `V_MAX_OUTFLOW = 8`) — divides outflow more,
    so less moves per step.
  - Per-cell outflow cap `≈ density / 4` (blood uses `density / 2`).
  - `THRESHOLD_BECOME_DUST ≈ 8` (vs blood's `1`) — an air cell only becomes dust
    under substantial inflow, producing tight piles instead of a spreading haze.
  - Strong velocity friction each step (≈ `vel * 12 / 16`) and **snap to zero when
    `max(|vx|,|vy|) ≤ 1`**, so dust locks in place within a few frames.
- **Solid interaction:** dust **dampens** at solids (zero the velocity component
  pointing into the solid) rather than reflecting like blood — it piles against
  walls instead of bouncing off.
- **Persistence:** no time-based decay. A cell clears to air only when its density
  reaches 0 (i.e. it has fully drained into neighbors). Settled dust stays forever.

`simulate_dust(pos, pixel, material, n_up, n_down, n_left, n_right)` follows the
same signature/contract as `simulate_blood`: handles `material == MAT_DUST` and
`material == MAT_AIR` (for inflow pull), returns `true` when the cell is dust after
processing.

Wire it into `shaders/compute/simulation.glsl`:

```glsl
#include "res://shaders/include/sim/dust.glslinc"
...
if (simulate_blood(...)) return;
if (simulate_dust(pos, pixel, material, n_up, n_down, n_left, n_right)) return;
if (simulate_gas(...))  return;
```

Priority relative to blood/gas is not critical (they occupy distinct cells); place
dust adjacent to blood for readability.

### 4. Injection — `shaders/compute/melee_arc.glsl`

In the `is_solid_pass` branch, **after** the existing
`imageStore(..., vec4(0))` clear and hit-buffer append, replace the cleared pixel
with dust for a hashed fraction of destroyed pixels:

- Compute a hash from world coordinates (a small inline integer hash; no
  `common.glslinc` dependency and **no new push-constant fields**, preserving the
  16-byte alignment of the existing push constant).
- If `hash % 100 < DUST_SPAWN_PERCENT` (≈ 35):
  - `outward = normalize(world_pos - pc.origin)` (fall back to `pc.direction` if
    near-zero).
  - Encode an outward burst velocity (`outward * DUST_BURST_SPEED / 60.0`, biased
    by 8, clamped to nibbles) into A.
  - Write `vec4(MAT_DUST/255, DUST_BURST_DENSITY/255, mat/255, packedVel)` — note
    `mat` (the destroyed wall id) goes into **B** as the source color.
- Otherwise leave the pixel as air (already cleared).

Because the carve pass only targets the five solid wall types, dust is created
**only** by destroying walls. Swinging through air or through existing dust never
reaches this branch. The fraction keeps the carved cavity mostly open while dust
sprays outward and settles on the rim and nearby floor.

### 5. Rendering — `shaders/visual/render_chunk.gdshader`

Add a `MAT_DUST` case to the fluid-overlay block (near the `GAS/LAVA/BLOOD` case):

```glsl
if (mat == MAT_DUST) {
    int src = int(round(data.b * 255.0));
    vec3 dust_rgb = get_material_top_color(src, px.x); // the wall's own color
    dust_rgb = mix(dust_rgb, vec3(1.0), 0.25);          // lighten so it reads as dust
    fluid_tint = vec4(dust_rgb, 1.0);
    fluid_alpha = mix(0.4, 0.95, data.g);
    mat = MAT_AIR;                                       // fall through like other fluids
}
```

`get_material_top_color` is already defined above `fragment()` and samples the
material texture array, so dust inherits the exact wall palette. The lighten factor
and alpha range are tuning knobs.

## Components & data flow

```
melee swing (solid pass)
  └─ melee_arc.glsl: destroy wall pixel → (35%) write MAT_DUST (B=source id, A=outward vel)
        │
        ▼  (next frame, every active chunk)
  simulation.glsl → simulate_dust (dust.glslinc)
        └─ advect density outward, friction → settle, propagate source id, persist
        │
        ▼  (every frame)
  render_chunk.gdshader → MAT_DUST overlay tinted by source id, alpha by density
```

Unchanged in parallel: `melee_arc` hit buffer → `world_manager._drain_terrain_impacts()`
→ `terrain_impact.gd` flying chips.

## Testing

- Re-run `tests/unit/test_material_hardness.gd` and
  `tests/unit/test_material_hazard_bits.gd` to confirm adding `MAT_DUST` does not
  break registry expectations. Add a small assertion that `MAT_DUST` is registered
  as a fluid with no collider and zero hardness.
- GPU simulation behavior and feel are visual; verify by running the game and
  carving each wall type:
  - Dust bursts outward in the wall's color; cavity stays mostly clear.
  - Dust settles quickly (sluggish) and stays put indefinitely.
  - Swinging at air or at settled dust creates no new dust.
  - Dust does not block movement.
- Tuning knobs if feel is off: `DUST_SPAWN_PERCENT`, `DUST_BURST_SPEED`,
  `DUST_BURST_DENSITY`, `DUST_MAX_OUTFLOW`, the per-cell outflow cap,
  `THRESHOLD_BECOME_DUST`, the friction factor, and the render lighten/alpha.

## Risks / notes

- Adding a material shifts `MAT_COUNT` and array lengths; the generator must be
  run and the game restarted so compute/visual shaders pick up the new includes.
- `MAT_DUST` being a fluid means `get_fluids()` includes it, so the melee fluid
  push pass and the rigidbody injector will nudge settled dust. This is intended
  (juice), and does not create new dust. If undesired, exclude dust from the push
  effect later.
- Persisting indefinitely with no cleanup means a very long session slowly covers
  the floor in dust. Accepted per requirements.
