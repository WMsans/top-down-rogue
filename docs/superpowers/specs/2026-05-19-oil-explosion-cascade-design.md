# Oil Explosion Cascade: Spectacle & Impact

**Date:** 2026-05-19
**Status:** approved
**Context:** The oil explosion simulation works mechanically but lacks spectacle — the chain reaction is too slow, waves are too small, there is no entity damage, and no juice (screen shake, particles).

---

## 1. Goals

1. **Rapid popcorn cascade** — Once ignited, oil cells pop in rapid succession. Each explosion wave pre-burns adjacent oil, creating an accelerating chain reaction.
2. **Entity damage** — Burning oil and explosion waves deal damage to both the player and enemies standing in them.
3. **Juice** — Screen shake and spark particles sell the impact of explosions.

Oil remains console-spawned only (`spawn_mat oil`) — no natural arena placement in this change.

---

## 2. Shader Constant Tuning

File: `shaders/include/sim/common.glslinc`

| Constant | Old | New | Rationale |
|---|---|---|---|
| `OIL_BURN_END_POWER` | 18 | **30** | Each oil pop creates ~7-cell radius wave (was ~4) |
| `WAVE_DECAY` | 4 | **2** | Waves travel ~15 cells before fading (was ~4.5) |
| `SPREAD_PROB_MAX` | 0.7 | **0.9** | Fire spreads between oil cells 90% reliably (was 70%) |

---

## 3. Wave Pre-Burns Oil (Core Cascade Mechanic)

File: `shaders/include/sim/explode_wave.glslinc`, Branch C (oil contact block, lines 74-78)

**Current behavior:** When `MAT_EXPLODE_WAVE` contacts `MAT_OIL`, it adds `max_neighbor_power` to the oil's temperature but leaves density untouched. The oil then needs `burn_health` ticks of burning before it pops.

**New behavior:** In addition to heating, the wave **reduces the oil's density** by `max_neighbor_power`. This means:

1. A wave with power 30 hitting a fresh oil cell (density 20 with new burn_health) drops it to 0 immediately → pops that tick
2. Even partial pre-burn reduces the remaining burn ticks → cascade accelerates as more waves hit more oil

**Implementation sketch (lines 74-78 of explode_wave.glslinc):**
```glsl
if (material == MAT_OIL) {
    int density = get_density_oil(pixel);
    int temperature = get_temperature_oil(pixel);
    int new_density = max(0, density - max_neighbor_power);
    int new_temp = min(255, temperature + max_neighbor_power);
    imageStore(chunk_tex, pos, pack_oil(new_density, new_temp, unpack_velocity_oil(pixel)));
    return true;
}
```

This replaces the heat-only write with a density-reducing write.

---

## 4. Oil Burn Health

File: `src/autoload/material_registry.gd`, line 179

`burn_health` for MAT_OIL: **60 → 20**

Combined with wave pre-burning (power 30), fresh oil cells detonate on first wave contact. This is what creates the "popcorn" feel — each pop immediately triggers neighbors.

Requires regenerating the GPU material header via:
```
godot --headless --script res://tools/generate_material_glsl.gd
```

---

## 5. Entity Damage

File: `src/autoload/material_registry.gd`

| Material | Old damage | New damage | Reasoning |
|---|---|---|---|
| `MAT_OIL` | 0 | **5** | Standing in oil (especially burning oil) is dangerous |
| `MAT_EXPLODE_WAVE` | 0 | **20** | Being near an active explosion is lethal |

The existing `LavaDamageChecker` already samples terrain cells each frame and applies `MaterialRegistry.get_damage()` — no code change needed for player damage.

For enemies, a new lightweight node `TerrainDamageReceiver` will be created following the same pattern as `LavaDamageChecker`. It will be attached to enemies and sample terrain damage each physics frame.

### TerrainDamageReceiver

- New file: `src/enemies/terrain_damage_receiver.gd`
- Mirrors `LavaDamageChecker` pattern: 3x3 grid sampling
- Attaches itself to `TerrainPhysical` via WorldManager lookup
- Applies damage to `EnemyHealth` node on parent
- Must check for death state before applying damage

---

## 6. Explosion Juice

### 6.1 Explosion Detection (WorldManager._process)

Added to `WorldManager._process()` — WorldManager already has access to `terrain_physical`, player position (`tracking_position`), and runs a per-frame loop dispatching terrain probes.

Logic added:
1. Each physics frame, sample up to 16 points in a grid around `tracking_position`
2. Query `TerrainPhysical` (via direct `terrain_physical.query()`) for each point
3. Track which cells contain `MAT_EXPLODE_WAVE` in a `Dictionary[Vector2i, int]` with frame-based TTL of 8
4. When **new** wave cells are detected (position not in tracked dict):
   - Triggers screen shake via `HitReaction` autoload — amplitude proportional to new wave count (1–4 px base, 0.12s duration)
   - Spawns 3–6 orange/white spark particles per wave cell at the cell's world position, using the same `ColorRect` pattern as `HitReaction._spawn_sparks()`

The `tracking_position` is the player's position (or camera center), updated each frame in `WorldManager._process()`. This ensures explosion juice is only triggered for waves near the player — not for off-screen waves in distant chunks.

### 6.2 Screen Shake Integration

Uses the existing `HitReaction` screen shake system (`_shake_amount`, `_shake_duration`). Explosion shakes use a shorter duration (0.12s) and lower amplitude (1.5–4px) than combat hits, since they happen in rapid succession during a cascade.

### 6.3 Spark Particles

Sparks are fire-colored `ColorRect` instances spawned at the wave cell's world position, following the same pattern as `HitReaction._spawn_sparks()`:
- Color: orange to white gradient (random per spark)
- Count: 3–6 per wave cell
- Speed: 40–100 px/s
- Lifetime: 0.12–0.2s
- Direction: random 360°

---

## 7. Files Modified

| File | Change |
|---|---|
| `shaders/include/sim/common.glslinc` | Tune `OIL_BURN_END_POWER`, `WAVE_DECAY`, `SPREAD_PROB_MAX` |
| `shaders/include/sim/explode_wave.glslinc` | Branch C: wave pre-burns oil density |
| `src/autoload/material_registry.gd` | MAT_OIL: burn_health=20, damage=5; MAT_EXPLODE_WAVE: damage=20 |
| `src/core/world_manager.gd` | Add explosion wave polling + juice triggering in `_process()` |
| `shaders/generated/materials.glslinc` | Regenerate after material_registry changes |
| `shaders/generated/materials.gdshaderinc` | Regenerate after material_registry changes |

### Files Added

| File | Purpose |
|---|---|
| `src/enemies/terrain_damage_receiver.gd` | Enemy terrain damage sampling (mirrors LavaDamageChecker) |

---

## 8. No-Go Decisions

- No natural oil placement in arenas (console-only for now)
- No barrel destruction / oil spilling (barrels remain visual stubs)
- No sound effects (audio system not yet built)
- No explosion damage to terrain (wave already chews solids — unchanged)
- No changes to burn rate per tick (stays at 1 density/tick; the pre-burn + reduced health achieves the speed goal instead)

---

## 9. Testing

- **gdUnit test:** Update `test_oil_and_explode_wave_registry.gd` to verify new damage and burn_health values
- **Playtest checklist:**
  1. `spawn_mat oil` at player position
  2. Place `fire` nearby (or use Flame Blade's lava emitter)
  3. Verify oil ignites and cascade propagates rapidly (popcorn)
  4. Verify screen shakes during cascade
  5. Verify spark particles spawn at wave cells
  6. Stand in burning oil / explosion wave → verify player takes damage
  7. Lure enemies into oil → verify they take damage
