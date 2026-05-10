# Material Hardness & Carve Scaling Design

## Overview

Add a `hardness` property to each terrain material. When melee weapons or projectiles carve terrain, scale the carve radius based on weapon damage vs material hardness: harder materials carve a smaller area with the same weapon. Attach material-specific impact particles and sounds at each carve site.

## Problem

Currently, all solid materials carve identically — a melee swing clears the same radius in dirt as in stone. There is no differentiation between soft and hard terrain, and no feedback when terrain is broken. This flattens the exploration feel and removes a potential progression lever (stronger weapons = more terrain carved = more map revealed).

## Solution

### 1. Hardness Field in MaterialDef

Add `hardness: float` to the `MaterialDef` inner class in `material_registry.gd`. Default `0.0`. Set values for solid materials:

| Material | Hardness | Rationale |
|----------|----------|-----------|
| AIR | 0.0 | Not carved |
| DIRT | 0.5 | Soft, largest carve |
| WOOD | 2.0 | Moderate |
| COAL | 3.0 | Dense, slightly softer than stone |
| ICE | 4.0 | Brittle but hard |
| STONE | 5.0 | Hardest solid, smallest carve |
| GAS | 0.0 | Fluid, not carved |
| LAVA | 0.0 | Fluid, not carved |
| WATER | 0.0 | Fluid, not carved |
| BLOOD | 0.0 | Fluid, not carved |

Fluids have `hardness = 0.0` — they are pushed/dispersed via the existing fluid mechanics, not carved. The carve scale formula evaluates to `1.0` for fluids, but they are handled by a separate push path.

Add accessor:

```gdscript
func get_hardness(material_id: int) -> float:
    if material_id < 0 or material_id >= materials.size():
        return 1.0  # safe default for unknown materials
    return materials[material_id].hardness
```

### 2. Carve Radius Scaling Formula

**Formula**: `effective_radius = base_radius * clamp(damage / (damage + hardness), 0.1, 1.0)`

Where:
- `base_radius` — the current carve radius a weapon uses (e.g., melee arc radius, projectile impact radius)
- `damage` — the weapon's current damage stat (after modifiers)
- `hardness` — the material's hardness from `MaterialRegistry.get_hardness()`
- Floor at 10% — even a 0-damage "weapon" carves a minimal amount
- Ceiling at 100% — no over-carve beyond base radius

**Per-cell application**: Each cell in the carve arc computes its own effective radius from the material at that position. A swing spanning dirt and stone carves wider in dirt and narrower in stone — no special handling needed for mixed-material boundaries.

**Damage clamping**: If `damage <= 0`, use `max(damage, 0.1)` in the formula to prevent divide-by-zero.

### 3. Integration Points

#### Melee (melee_weapon.gd → terrain_modifier.gd)

`MeleeWeapon._hit_attackables_in_arc()` already calls `TerrainSurface.clear_and_push_materials_in_arc()` with the arc parameters. Pass `weapon.damage` through:

```
TerrainModifier.clear_and_push_materials_in_arc(user, origin, dir, arc_angle, radius, damage)
```

Inside the per-cell loop, after reading `material_id`, compute the hardness-based scale and apply to `radius` before the distance check.

Conversely, `TerrainModifier.disperse_materials_in_arc()` is used for fluids (push path). Fluids maintain their existing behavior — hardness does not gate fluid dispersion.

Return a list of `{world_pos, material_id, effective_radius}` tuples from the carve function for feedback consumption.

#### Projectile (projectile.gd)

When a projectile collides with a `StaticBody2D` (terrain), it currently destroys itself. Replace with:
1. Query the terrain cell at the impact point via `TerrainPhysical.query()`
2. Compute effective carve radius from projectile damage vs material hardness
3. Call `TerrainModifier.place_material()` with `MAT_AIR` at the impact point with effective radius
4. Trigger impact feedback
5. Destroy the projectile

Projectiles use a small default `base_radius` (pixel-scale, e.g., 2.0 units) so they carve a tiny crater rather than a full arc.

### 4. Impact Feedback

New file: `src/core/juice/terrain_impact.gd` (autoload `TerrainImpact`)

Maps `material_id → {particle_color: Color, particle_count: int, sound_path: String}`.

| Material | Particle Color | Count | Sound Description |
|----------|---------------|-------|-------------------|
| DIRT | `Color(0.45, 0.32, 0.18)` brown | 6 | Soft thud / earthy crumble |
| WOOD | `Color(0.55, 0.42, 0.25)` tan | 8 | Medium crack / woody splinter |
| COAL | `Color(0.12, 0.12, 0.14)` dark | 8 | Sharp crack / rocky crumble |
| ICE | `Color(0.7, 0.85, 0.95)` light blue | 10 | High-pitched glassy shatter |
| STONE | `Color(0.5, 0.5, 0.5)` gray | 6 | Loud clink / metallic ring |

**Implementation**: `play_impact(world_pos: Vector2, material_id: int, intensity: float)` — spawns a short-lived `GPUParticles2D` node at `world_pos` with the material's color and count scaled by `intensity` (the carve scale), and plays a one-shot `AudioStreamPlayer2D` with the material's sound path. Unknown `material_id` defaults to generic gray particles with no sound.

**Intensity scaling**: `intensity = effective_radius / base_radius` — so a full-radius carve produces full particles, while a 10% carve produces minimal debris.

### 5. Modifier Integration (Automatic)

Modifiers that alter `weapon.damage` at use-time (via `on_use()` hooks) automatically affect carve power since the live damage stat is read at carve time. No extra wiring needed. Future modifiers could explicitly add carve bonuses (e.g., "Shattering" modifier that treats hardness as halved), but this is out of scope for the initial implementation.

## Architecture

| Layer | File | Change |
|-------|------|--------|
| Material definition | `material_registry.gd` | Add `hardness: float` and `get_hardness()` |
| Carve scaling | `terrain_modifier.gd` | Accept `damage` parameter, scale radius per-cell by hardness |
| Melee carve call | `melee_weapon.gd` | Pass `weapon.damage` to carve calls |
| Projectile carve | `projectile.gd` | Replace destroy-self with terrain query + carve + feedback |
| Impact feedback | `terrain_impact.gd` (new) | Autoload. Register in project.godot. Particle + sound per material |

## Data Flow

```
Weapon.use() or Projectile collision
  ├─ damage = weapon.damage
  └─ carve_fn(origin, dir, arc, base_radius, damage)

TerrainModifier.clear_and_push_materials_in_arc(...)
  ├─ For each cell in arc:
  │   ├─ material_id = read from terrain texture
  │   ├─ hardness = MaterialRegistry.get_hardness(material_id)
  │   ├─ scale = clamp(damage / (damage + max(hardness, 0.1)), 0.1, 1.0)
  │   ├─ effective = radius * scale
  │   └─ clear if distance < effective
  └─ Return impact_data: [{pos, material_id, scale}]

TerrainImpact.play_impact(world_pos, material_id, intensity)
  └─ Spawn particles + play sound
```

## Edge Cases & Error Handling

- **Zero/negative damage**: Clamp `damage` floor to `0.1` in the formula — prevents division by zero, produces 10% carve.
- **Unknown material_id**: `get_hardness()` returns `1.0` (medium). `TerrainImpact` falls back to generic gray particles with no sound.
- **Fluids in carve arc**: `hardness = 0.0` → scale = 1.0. Fluids are handled by the `disperse` push path (unchanged). If accidentally processed by the clear path, they clear at full radius — harmless since fluids clear instantly anyway.
- **Mixed-material carve edges**: Per-cell scaling naturally produces asymmetric carve shapes across material boundaries — no special handling.
- **Rapid carving of same spot**: Since carving sets cells to AIR, repeated hits on the same spot hit AIR (hardness 0) and carve at full radius — wasted but harmless.

## Testing

- **Unit**: Verify `damage/(damage+hardness)` formula for known inputs: `(5, 0.5) → 0.91`, `(5, 5.0) → 0.50`, `(1, 5.0) → 0.167`, `(0, 5.0) → 0.1`.
- **Unit**: Verify `MaterialRegistry.get_hardness()` returns correct values per material.
- **Integration**: Spawn wall of known material, equip weapon with known damage, perform melee swing, query carved region via `TerrainPhysical.query()` — assert carved radius within tolerance of computed effective radius.
- **Integration**: Fire projectile at stone wall — assert small crater carved at impact point, not full arc.
- **Integration**: Swing through dirt+stone boundary — assert dirt region carved larger than stone region.
