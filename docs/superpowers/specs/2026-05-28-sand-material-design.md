# Sand Material — Wall Destruction Debris

## Goal

When walls (stone, dirt, coal, ice, wood) are destroyed by melee or explosions, they should produce dense sand that spreads outward in a short burst, then quickly settles into static piles. This gives visual feedback that a wall was broken and leaves debris on the ground.

## Behavior

Sand is a **fluid** in the simulation pipeline (like blood, lava, oil, gas) but tuned to behave like a dense, sticky granular material:

| Property | Blood | Sand |
|---|---|---|
| Velocity damping | 15/16 per frame (~6% loss) | 1/2 per frame (50% loss) |
| Max outflow factor | density/2 | density/4 |
| Gravity bias | None | None (top-down) |
| Threshold to become | 1 | 1 |
| Dissipation | Below density 1 → AIR | **Never dissipates** |
| Spawn density | 150-240 (random) | Always 255 |
| Initial velocity | From hit direction, 200-280 px/s | From destruction direction, similar burst speed |
| `is_solid_for_*` | Everything except AIR + BLOOD | Everything except AIR + SAND + WATER |
| `fluid` flag | true | true |
| `has_collider` | false | false |
| Tint color | Dark red (0.8, 0.05, 0.05) | Sandy beige (0.6, 0.55, 0.45) |

Sand spreads when kicked by melee/explosion, but the 50% per-frame velocity damping and quartered outflow rate mean it barely travels — a few pixels of burst, then it sits still as a persistent pile.

## Spawning: destruction distribution

When `melee_arc.glsl` or `explode_wave.glslinc` destroys a solid cell, instead of writing pure AIR (vec4(0,0,0,0)), it should look up the destruction distribution for the destroyed material and write the result material with full density and a velocity derived from the destruction direction.

### Simple per-material distribution

For now, use a hardcoded mapping in the shader and CPU-side:

| Material | Distribution |
|---|---|
| STONE | 40% → MAT_SAND, 60% → MAT_AIR |
| DIRT | 40% → MAT_SAND, 60% → MAT_AIR |
| WOOD | 100% → MAT_AIR (wood splinters into nothing) |
| COAL | 30% → MAT_SAND, 70% → MAT_AIR |
| ICE | 100% → MAT_AIR (ice shatters cleanly) |

The distribution is resolved using the hash already available in `common.glslinc`:
```glsl
uint rng = hash(uint(pos.x) ^ hash(uint(pos.y) ^ uint(pc.frame_seed)));
int result_mat = (rng % 100u < 40u) ? MAT_SAND : MAT_AIR;  // for stone/dirt
```

### Velocity on spawn

Destroyed cells that become sand receive an initial velocity pointing away from the destruction origin (melee center or explosion center), packed into the alpha channel using the same encoding as blood (vx+8 << 4 | vy+8). Speed should be similar to blood's outward speed (~200-300 px/s scaled to the velocity encoding).

## GPU simulation (sand.glslinc)

A new `shaders/include/sim/sand.glslinc` file, forked from `blood.glslinc` with these changes:

1. **`THRESHOLD_DISSIPATE` removed** — sand never dissipates. If `new_density < 1`, clamp to 1 instead of converting to AIR. Actually, skip the dissipation check entirely; sand at density 0 (all outflow, no inflow) stays at 0. Since we spawn at 255 and it spreads slowly, it will rarely reach 0. But to be safe: if new_density == 0, convert to AIR (empty cell). If new_density >= 1, always stay as sand.
2. **Velocity damping**: change `(new_vel * 15) / 16` to `(new_vel * 1) / 2` (i.e. halve each frame).
3. **Max outflow**: change `max(1, density / 2)` to `max(1, density / 4)`.
4. **`is_solid_for_sand`**: returns true for everything except AIR, SAND, and WATER (sand can flow into water cells, water can push into sand cells).
5. **Threshold become**: `THRESHOLD_BECOME_SAND = 1` (same as blood).
6. **`simulate_sand`** dispatch: called in `main()` **before** `simulate_blood` but after `simulate_oil`. Heavier/stickier fluids claim space first: explode_wave > lava > oil > **sand** > blood > gas.

## CPU-side: melee_arc.glsl changes

The solid-pass in `melee_arc.glsl` currently writes `vec4(0,0,0,0)` (AIR) for destroyed cells. Change to:
1. Hash the pixel position to decide AIR vs SAND based on the material's destruction distribution.
2. If SAND is chosen, write `pack_sand(255, vel)` with velocity pointing away from the melee origin.
3. If AIR is chosen, write `vec4(0,0,0,0)` as before.

The melee_arc shader already has `origin` and `direction` in push constants, so computing an outward velocity is straightforward.

## CPU-side: place_sand function

Add `TerrainSurface.place_sand()` and `TerrainModifier.place_sand()` mirroring `place_blood`, but:
- Spawns `MAT_SAND` with density 255
- Uses a lighter burst speed (sand is heavier, so maybe ~150-200 px/s outward)
- Same velocity encoding as blood

## CPU-side: MaterialRegistry changes

Add `MAT_SAND` to `_init_materials()`:
```gdscript
var mat_sand := MaterialDef.new(
    "SAND", "",
    false, 0, 0,
    false, false,
    Color(0.6, 0.55, 0.45, 1.0),
    true,
    0,
    1.0,
    0.0
)
```

- `fluid = true` (enters simulation pipeline)
- `has_collider = false` (sand doesn't block movement)
- `flammable = false`
- `glow = 1.0` (no glow)

## CPU-side: terrain_impact.gd changes

Add a sand color (sandy beige) to the impact particle colors so melee hits on materials that produce sand show appropriate debris particles.

## Files to create/modify

| File | Action |
|---|---|
| `shaders/include/sim/sand.glslinc` | **Create** — sand simulation, forked from blood |
| `shaders/compute/simulation.glsl` | **Modify** — include sand.glslinc, add `simulate_sand()` call |
| `shaders/include/sim/common.glslinc` | **Modify** — add `THRESHOLD_BECOME_SAND` |
| `shaders/compute/melee_arc.glsl` | **Modify** — destruction distribution, spawn sand with velocity |
| `shaders/include/sim/explode_wave.glslinc` | **Modify** — destruction distribution for explode wave |
| `src/autoload/material_registry.gd` | **Modify** — add MAT_SAND |
| `tools/generate_material_glsl.gd` | **Modify** — regenerate with MAT_SAND |
| `shaders/generated/materials.glslinc` | **Regenerate** |
| `shaders/generated/materials.gdshaderinc` | **Regenerate** |
| `src/core/terrain_surface.gd` | **Modify** — add `place_sand()` |
| `src/core/terrain_modifier.gd` | **Modify** — add `place_sand()` |
| `src/core/world_manager.gd` | **Modify** — add `place_sand()` passthrough |
| `src/core/juice/terrain_impact.gd` | **Modify** — add sand impact particles |
| `src/weapons/melee_weapon.gd` | **Modify** — post-melee sand spawning call (if CPU-side spawning is needed in addition to GPU) |