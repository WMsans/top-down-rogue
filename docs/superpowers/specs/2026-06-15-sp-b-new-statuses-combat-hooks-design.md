# SP-B — New Statuses & Combat Hooks

**Date:** 2026-06-15
**Branch:** feat/content-expansion
**Phase 7 sub-project:** B (6) — new statuses, combat verbs, entity hooks
**Depends on:** SP-A (DataModifier dispatch, resolve_hit chokepoint) for modifier wiring in SP-B.1
**Restructured into:** SP-B (6) = core infrastructure; SP-B.1 (6.5) = 7 modifier scripts

## 1. Problem

The existing status system (7 stain-based statuses, 6 reaction rules) covers fire/water/oil/cold
interactions but lacks three statuses the content expansion needs: `lightning`, `steam`, and
`stun`. Two of these need a different model (flat-duration, not stain accumulation). The combat
system also lacks parameterized verbs for knockback, stun, heal, and bounty that the 7 new
modifiers (chain_spark, steam_burst, concussive_edge, repulsor_nova, shockwave_stomp,
magnet_field, midas_touch) require.

## 2. Approach: Parallel timed dict in StatusComponent

Add timed statuses alongside the existing stain system in `StatusComponent`. A new
`_timed_statuses` dictionary stores flat-duration effects. This avoids refactoring the stain
model and keeps all status queries in one component.

The two models coexist:
- **Stain statuses** (existing): accumulate, decay per second, "active" above threshold
- **Timed statuses** (new): flat duration, tick down, expire, no accumulation

Cross-model reactions (lightning + wet → steam) naturally live in `tick()` where both are visible.

## 3. New Status Definitions

### 3.1 `steam` (stain-based)

| Field | Value |
|---|---|
| `id` | `"steam"` |
| `display_name` | `"Steamed"` |
| `tint_color` | `(0.85, 0.85, 0.85)` — white-gray |
| `decay_rate` | 1.2 |
| `active_threshold` | 1.0 |
| `category` | `HARMFUL` |
| `burn_dps` | 3.0 (scalding — less than fire's 4.0) |
| `blocks_movement` | `false` |
| `slow_multiplier` | 0.8 (light slow) |
| `mode` | `STAIN` |

Source: `MAT_STEAM` via `stain_for_material()` terrain polling. Reaction: lightning + wet →
spawns MAT_STEAM, which terrain-polls into the stain.

### 3.2 `lightning` (timed)

| Field | Value |
|---|---|
| `id` | `"lightning"` |
| `display_name` | `"Shocked"` |
| `tint_color` | `(0.9, 0.95, 1.0)` — electric blue-white |
| `default_duration` | 0.4 |
| `category` | `HARMFUL` |
| `mode` | `TIMED` |

Effect: visual flash; reaction with wet → spawns MAT_STEAM. No DoT, no slow on its own.

### 3.3 `stun` (timed)

| Field | Value |
|---|---|
| `id` | `"stun"` |
| `display_name` | `"Stunned"` |
| `tint_color` | `(1.0, 1.0, 0.5)` — yellow flash |
| `default_duration` | 0.2 |
| `category` | `HARMFUL` |
| `mode` | `TIMED` |

Effect: blocks movement AND blocks attack input. Replaces `_parry_stun_remaining` on Enemy.

### 3.4 StatusDef schema change

Add two fields to `StatusDef`:

```gdscript
var mode: int = STAIN          # STAIN = 0, TIMED = 1
var default_duration: float = 0.0  # 0 for stain; used for timed
```

Existing 7 statuses keep `mode = STAIN`, `default_duration = 0.0` — no behavior change.

## 4. New Reaction Rules

Added after existing rule 6 in `StatusRegistry.apply_reactions()`:

### Rule 7: Lightning + wet → spawn MAT_STEAM

When `lightning` timed status is active **and** `wet` stain ≥ threshold:
- Spawn a MAT_STEAM blob (radius ~12px, density ~180) around the entity via
  `TerrainSurface.place_steam(entity.global_position, 12.0, 180)`
- Drain `wet` at rate 3.0/sec
- Consume `lightning` (remove the timed status)

**Architectural note:** `apply_reactions()` currently takes `(component, delta)` and only
modifies stain amounts. Rule 7 needs to: (a) place terrain material at the entity's position,
and (b) remove a timed status. Two changes:

1. Pass the entity's `global_position` to `apply_reactions()`. The caller (`tick()`) has
   `owner.global_position`.
2. `apply_reactions()` returns an array of side-effect actions (e.g., `{action: "spawn_steam",
   position: Vector2}`). The caller executes them after. This keeps reactions pure-ish and
   avoids `StatusRegistry` needing a TerrainSurface reference. Alternatively, `apply_reactions`
   can directly call `TerrainSurface.place_steam()` since TerrainSurface is a globally
   accessible adapter — **prefer this simpler approach**.

### Rule 8: Steam smothers fire (bidirectional)

- Drain `on_fire` at rate 3.0/sec (faster than wet's 4.0 but compensated by steam's faster decay)
- Drain `steam` at rate 2.0/sec

### Rule 9: No special rule for fire + lightning

Fire and lightning do not interact beyond normal damage application. No chain rule needed.

## 5. MAT_STEAM Material

### 5.1 Material definition

In `material_registry.gd`, add after `MAT_BEDROCK`:

- `MAT_STEAM`: `fluid = true`, tint `(0.9, 0.9, 0.9, 0.7)` (semi-transparent white), no collider,
  no wall extension, no damage, no glow, hardness 0.

Physics: identical to gas — rises, diffuses, dissipates below density threshold. Shares the
`gas_advect_pull` simulation function in the compute shader. `MAT_STEAM` is dispatched to the
same advection code path as `MAT_GAS`.

### 5.2 Shader changes

Option A (recommended): Add `MAT_STEAM` as a case in the simulation dispatch that calls the same
`gas_advect_pull` function. No new `.glslinc` file needed — just a branch in the existing
dispatch.

Option B: Copy `gas.glslinc` → `steam.glslinc`. Same behavior, separate file. Simpler to
diverge later but redundant now.

**Choose option A.** Add a dispatch branch:

```glsl
if (mat_id == MAT_GAS || mat_id == MAT_STEAM) {
    gas_advect_pull(...);
}
```

### 5.3 TerrainModifier

Add `place_steam(world_pos: Vector2, radius: float, density: int)` method in
`terrain_modifier.gd`. Delegates to `place_material_blob()` with `MAT_STEAM` — same pattern as
`place_gas()`. Referenced by `steam_burst` modifier and the lightning+wet reaction.

### 5.4 stain_for_material mapping

In `status_registry.gd`, add:

```gdscript
if material_id == MaterialRegistry.MAT_STEAM:
    return "steam"
```

### 5.5 Regenerate shader constants

Run `godot --headless --script res://tools/generate_material_glsl.gd` to regenerate
`shaders/generated/materials.glslinc` and `materials.gdshaderinc` with `MAT_STEAM` constants.

## 6. Combat Verbs

### 6.1 Stun

**StatusComponent additions:**

```gdscript
var _timed_statuses: Dictionary = {}

func add_timed_status(id: String, duration: float) -> void:
    _timed_statuses[id] = {"remaining": duration, "duration": duration}
    changed.emit()

func has_timed_status(id: String) -> bool:
    return id in _timed_statuses and _timed_statuses[id]["remaining"] > 0

func get_timed_remaining(id: String) -> float:
    if id in _timed_statuses:
        return _timed_statuses[id]["remaining"]
    return 0.0

func is_stunned() -> bool:
    return has_timed_status("stun")

func can_attack() -> bool:
    return not is_stunned()
```

In `tick()`, after stain reactions, add timed decay. Must iterate a copy of keys since
entries are erased during iteration:

```gdscript
var _expired: Array = []
for id in _timed_statuses:
    _timed_statuses[id]["remaining"] -= delta
    if _timed_statuses[id]["remaining"] <= 0:
        _expired.append(id)
for id in _expired:
    _timed_statuses.erase(id)
```

`is_movement_blocked()` now also checks `is_stunned()`. `can_attack()` is queried by enemy
attack states and player weapon use.

**Enemy changes:**
- Remove `_parry_stun_remaining` field. Replace all usages with
  `status.add_timed_status("stun", PARRY_STUN_DURATION)` where `PARRY_STUN_DURATION = 0.25`.
- In attack states (WINDUP, ATTACK): if `_status_component.is_stunned()`, cancel back to CHASE
  (or re-evaluate).
- Movement gating already checks `is_movement_blocked()` which now includes stun.

**Player changes:**
- Weapon use gated by `_status_component.can_attack()`.
- Parry stun: player applies `enemy.status.add_timed_status("stun", 0.25)` instead of setting
  `_parry_stun_remaining`.

### 6.2 Knockback

**`apply_knockback(direction: Vector2, strength: float)`**:

Enemy:
```gdscript
func apply_knockback(direction: Vector2, strength: float) -> void:
    _knockback_velocity += direction.normalized() * strength
```

Player:
```gdscript
func apply_knockback(direction: Vector2, strength: float) -> void:
    _knockback_velocity = direction.normalized() * strength
```

**Refactor `on_hit_impact()`**: both Enemy and PlayerController replace their hardcoded
knockback with `apply_knockback(hit_dir, KNOCKBACK_SPEED)`. This unifies the verb so
modifiers can call it directly.

Radial knockback (repulsor_nova, shockwave_stomp): modifier computes direction per target as
`(target.global_position - source.global_position).normalized()` and calls
`target.apply_knockback(dir, magnitude)`.

### 6.3 Heal

`PlayerInventory.heal(amount: int)` already exists (line 127). No changes needed. Modifiers
call `inventory.heal(magnitude)` directly via the user's inventory reference.

### 6.4 Bounty

`PlayerInventory.add_gold(amount: int)` already exists. Modifiers call
`inventory.add_gold(magnitude)` directly. No changes needed.

### 6.5 Pull (magnet_field)

On each swing, the modifier queries all `Drop` and `GoldDrop` nodes within `magnitude` (48) px
of the player. For each found drop, temporarily widen its magnet attraction range toward the
player position (set a `_pull_target: Node2D` and `_pull_timer: float = 0.5`) so the existing
magnet logic in `GoldDrop._process()` handles movement. After 0.5s, the drop resumes normal
magnet behavior.

## 7. StatusVisuals Changes

Render timed status icons alongside stain icons:
- Same `Sprite2D` icon pattern, tinted by the timed status's `tint_color`.
- Alpha ramps based on `remaining / duration` instead of `stain / threshold`.
- Stun: brief yellow-white flash overlay on the entity sprite while active.
- Lightning: brief electric blue tint on the entity sprite.

`get_blended_tint()` in `StatusComponent` now blends both stain tints (weighted by stain ratio)
and timed status tints (weighted by remaining/duration ratio), clamped to max alpha 1.0.

## 8. Entity Changes Summary

| Entity | Changes |
|---|---|
| **StatusDef** | Add `mode` (STAIN/TIMED), `default_duration` fields |
| **StatusRegistry** | Register `steam`, `lightning`, `stun` defs; add reaction rules 7–9; add `MAT_STEAM` → `"steam"` mapping; expose `place_steam` on `TerrainSurface` |
| **StatusComponent** | Add `_timed_statuses` dict; `add_timed_status`, `has_timed_status`, `get_timed_remaining`, `is_stunned`, `can_attack`; extend `tick()` for timed decay; extend `get_blended_tint()` and `is_movement_blocked()` |
| **Enemy** | Add `apply_knockback()`; refactor `on_hit_impact()` to use it; remove `_parry_stun_remaining`; gate attack states on `!is_stunned()` |
| **PlayerController** | Add `apply_knockback()`; refactor `on_hit_impact()`; gate weapon use on `can_attack()`; parry applies stun via StatusComponent |
| **MaterialRegistry** | Add `MAT_STEAM` definition (fluid, gas physics, white tint) |
| **TerrainModifier** | Add `place_steam()` method |
| **Shader** | Add `MAT_STEAM` dispatch branch to gas simulation; regenerate `materials.glslinc` |
| **StatusVisuals** | Render timed status icons; blend timed tints |

## 9. Sub-project Restructuring

**Original SP-B (6): New statuses & combat hooks + 7 modifier scripts**

Split into:

- **SP-B (6)**: Core infrastructure — status defs, reaction rules, MAT_STEAM, combat verbs,
  StatusComponent timed model, entity changes. Shown in this document.
- **SP-B.1 (6.5)**: 7 modifier scripts — chain_spark, steam_burst, concussive_edge,
  repulsor_nova, shockwave_stomp, magnet_field, midas_touch. Depends on both SP-A
  (DataModifier dispatch, resolve_hit) and SP-B (verbs, statuses). Separate spec.

## 10. Testing

gdUnit4, matching existing patterns:

- `test_status_component.gd`: add tests for `add_timed_status`, `has_timed_status`,
  tick-down, expiry, `is_stunned`, `can_attack`, simultaneous stain + timed.
- `test_status_registry.gd`: add tests for steam/lightning/stun defs, new reaction rules
  (lightning+wet→steam spawn, steam+fire→extinguish).
- `test_status_reactions.gd`: extend with reaction rules 7–8.
- `test_enemy.gd` (or integration): verify knockback verb, stun blocks movement + attack,
  parry stun migration.
- Manual: confirm stun visually halts enemy/player; lightning visual flash on enemy;
  lightning+wet reaction spawns steam cloud; steam cloud applies scalding DoT.

## 11. Acceptance

- Three new statuses (`steam`, `lightning`, `stun`) registered and functionally correct.
- Two new reaction rules (lightning+wet→steam, steam+fire).
- MAT_STEAM material spawns, simulates like gas, terrain-polls into steam stain.
- Stun blocks movement **and** attack (not just movement like frozen).
- `apply_knockback(dir, strength)` on both Enemy and PlayerController.
- Parry stun migrated from `_parry_stun_remaining` to timed StatusComponent.
- `StatusVisuals` renders timed status icons.
- All existing tests green; new tests added and green.