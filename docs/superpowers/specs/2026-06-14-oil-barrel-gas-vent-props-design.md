# Oil Barrel & Gas Vent Props + Poisoned Status

**Date:** 2026-06-14

## Problem

Two props (`barrel.tscn`, `vent.tscn`) are placed in rooms as inert stubs with placeholder textures and no scripts. The underlying oil and gas GPU simulations are fully functional, but there is no gameplay mechanism to deposit these materials. Gas is completely inert — no status effect, no damage, no interactions.

## Solution

Make both props functional by adding scripts that interact with the terrain system, and add a `poisoned` status effect so gas creates a real gameplay hazard.

## 1. Oil Barrel

**File:** `src/props/oil_barrel.gd`

A destructible prop with 3 HP. Each hit splashes a small oil patch. On destruction, dumps a large oil pool.

### Behavior

- **HP:** 3
- **On hit:** reduce HP by 1, call `TerrainSurface.place_material(impact_pos, 4, MAT_OIL)` to splash oil at the impact point
- **On destroy (HP reaches 0):** call `TerrainSurface.place_material(global_position, 8, MAT_OIL)` for the main dump, then `queue_free()`
- **Hittable by:** player attacks, enemy attacks, projectiles (both factions)
- **Visual feedback:** sprite flash on hit, optional screen shake on destroy

### Implementation

- `extends Node2D`
- `@onready var _sprite: Sprite2D = $Sprite2D`
- `var _hp: int = 3`
- `signal destroyed`
- `func hit(hit_pos: Vector2)`: reduce HP, flash sprite, splash oil. If HP <= 0, dump oil and destroy.
- `func _flash()`: modulate sprite to white, tween back
- Enemies and player weapons call `hit()` when their attack overlaps the barrel (via `area_entered` or `body_entered` signal)

### Scene Changes (`scenes/props/barrel.tscn`)

- Add `CollisionShape2D` child (CircleShape2D, radius ~6px) under an `Area2D` or `StaticBody2D` for hit detection
- Add script reference to `oil_barrel.gd`
- Keep existing `Sprite2D` with brown tint

## 2. Gas Vent

**File:** `src/props/gas_vent.gd`

An indestructible prop that periodically emits gas clouds.

### Behavior

- **Emit cycle:** every 5 seconds, call `TerrainSurface.place_gas(global_position, 6, 80)`
- **Indestructible:** no HP, not hittable, always active
- **Visual feedback:** optional pulse animation when emitting

### Implementation

- `extends Node2D`
- `var _timer: float = 0.0`
- `const EMIT_INTERVAL: float = 5.0`
- `const EMIT_RADIUS: float = 6.0`
- `const EMIT_DENSITY: int = 80`
- `func _process(delta)`: accumulate timer, when >= EMIT_INTERVAL, emit gas and reset

### Scene Changes (`scenes/props/vent.tscn`)

- Add script reference to `gas_vent.gd`
- No collision shape needed (indestructible, always on)

## 3. Poisoned Status Effect

### StatusRegistry Entry

```
"poisoned", "Poisoned", Color(0.3, 0.85, 0.25, 1.0),
decay_rate: 0.4,
active_threshold: 0.3,
category: HARMFUL,
burn_dps: 2.0,
blocks_movement: false,
slow_multiplier: 0.6,
icon: "res://textures/ui/status/Effect_poisoned.png"
```

### Material Mapping

Add to `StatusRegistry.stain_for_material()`:
- `MAT_GAS → "poisoned"`

This means any entity (player or enemy) standing on gas terrain accumulates the `poisoned` stain at the standard `TERRAIN_STAIN_RATE` (6.0/sec).

### Effects

- **DoT:** 2 damage per second while poisoned (via `burn_dps`)
- **Slow:** movement speed reduced to 60% while poisoned (via `slow_multiplier`)
- **Decay:** stain decays at 0.4/sec when not in gas, so it lingers briefly after leaving
- **No reactions** with other statuses (no wet-cures-poison or gas+fire combos in this scope)

### Icon

A poisoned status icon at `textures/ui/status/Effect_poisoned.png`. Can use a placeholder green droplet until real art is available.

## 4. TerrainSurface Convenience Method

Add `place_oil()` to `TerrainSurface` alongside existing `place_lava()`, `place_gas()`, etc.:

```gdscript
func place_oil(world_pos: Vector2, radius: float) -> void:
    if adapter:
        adapter.place_material(world_pos, radius, MaterialRegistry.MAT_OIL)
```

This mirrors `place_lava()` and gives a clean API for the oil barrel script.

## 5. SpawnDispatcher

No changes needed. Both barrel and vent are already placed in rooms via existing spawn markers. The stub `.tscn` files just need scripts and collision shapes added.

## 6. Enemy Interaction

- Enemies can hit oil barrels (triggering oil splashes)
- Enemies standing in gas accumulate `poisoned` stain and take DoT + slow
- Enemies standing in oil accumulate `oiled` stain (already works via terrain polling)
- The barrel's `hit()` method is callable by any damage source

## Files Summary

| Action | File |
|--------|------|
| Create | `src/props/oil_barrel.gd` |
| Create | `src/props/gas_vent.gd` |
| Create | `textures/ui/status/Effect_poisoned.png` (placeholder) |
| Modify | `scenes/props/barrel.tscn` — add script + Area2D + CollisionShape2D |
| Modify | `scenes/props/vent.tscn` — add script |
| Modify | `src/autoload/status_registry.gd` — add `poisoned` status + `stain_for_material` mapping |
| Modify | `src/core/terrain_surface.gd` — add `place_oil()` method |