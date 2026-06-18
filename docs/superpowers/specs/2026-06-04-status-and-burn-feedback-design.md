# Status Clarity & Burn Feedback — Design

**Date:** 2026-06-04
**Branch:** feat/content-expansion

## Problem

Two feedback gaps in the status-effect system:

1. **Status identity is unclear.** Active statuses show only as tiny 10×10 colored
   chips under the health bar (`hud.gd:153-172`) plus a subtle full-body `modulate`
   tint. A color alone doesn't tell the player *which* status is active, how intense
   it is, or that it's about to lapse.
2. **Burn damage is invisible.** Burn DoT routes through
   `PlayerInventory.take_status_damage()` (`player_inventory.gd:106`), which
   deliberately bypasses the whole `HitReaction` juice stack — no numbers, no flash,
   no shake. Health silently ticks down; the player never *feels* the fire.

## Solution Summary

Move status feedback into world-space, on the afflicted entity:

- **Status identity** → a centered row of icons above each entity's head
  (player **and** enemies), each icon's **alpha = its intensity**.
- **Burn feel** → three layered channels on the burning entity: a flame-particle
  emitter, a per-tick orange throb on the sprite, and (player only) a sustained
  ember screen-edge vignette.

Only `on_fire` gets the burning VFX. Every status gets an icon. No floating damage
numbers, no extra screen shake. The redundant HUD chip strip is removed.

## Icon Assets

Six 60×60 pixel-art PNGs already exist in `textures/ui/status/` (not yet imported —
Godot generates `.import` on next editor load). Status → file mapping:

| status id | file |
|-----------|------|
| `on_fire` | `Effect_on_fire.png` |
| `wet`     | `Effect_wet.png` |
| `oiled`   | `Effect_oiled.png` |
| `chilly`  | `Effect_ingestion_freezing.png` |
| `frozen`  | `Effect_frozen.png` |
| `bloody`  | `Effect_bloody.png` |

## Components

### 1. `StatusVisuals` (new shared node)

`src/status/status_visuals.gd`, extends `Node2D`. Instantiated in code as a child by
both the player and each enemy (the same way each entity already creates its
`StatusComponent`), pointed at that entity's existing `StatusComponent`. One
component, two consumers — icon and particle logic lives in one place.

**Setup:** the owner creates it, sets a `head_offset: Vector2` (player ≈ `-28`,
enemy tuned per sprite), and passes its `StatusComponent`. `StatusVisuals` connects
to `StatusComponent.changed` (already emitted every physics frame).

**Icons:**
- Each active status is a `Sprite2D` child. Source 60×60 → scaled to ≈16px display,
  `texture_filter = NEAREST`, high `z_index` so they render above terrain/entities.
- Laid out in a centered horizontal row at `head_offset` (e.g. `x = i*SPACING -
  (count-1)*SPACING/2`), `SPACING ≈ 18`.
- Sprites live under the entity **root**, not under the squash/flip sprite, so they
  never stretch with squash or mirror with facing.
- On `changed`: **reconcile** the active set — create a sprite when a status becomes
  active, free it when it lapses — then update positions and per-icon alpha. Only
  the create/free path runs when the set changes; alpha updates every frame are cheap.
- **Alpha = intensity:** `alpha = remap(stain, threshold, threshold + RAMP,
  MIN_ALPHA, 1.0)`, clamped to `[MIN_ALPHA, 1.0]`. Icon shows only while
  `has_status(id)` (stain ≥ threshold). Starting constants: `MIN_ALPHA = 0.45`,
  `RAMP = 4.0` (tunable). The remap helper lives in `StatusRegistry` so it's
  testable.

**Flame particles:**
- A `CPUParticles2D` child built in code: small upward-rising orange particles with
  fade-out, modest emission rate.
- `emitting = status.has_status("on_fire")`, updated on `changed`.
- Because it lives in the shared node, player and enemies both emit flames for free.

### 2. Registry & def changes

`src/status/status_def.gd`
- Add `icon_path: String` (default `""`), plus a constructor parameter for it.

`src/autoload/status_registry.gd`
- Pass each status's `icon_path` in `_register_defs()` per the mapping table above.
- `get_icon(id: String) -> Texture2D` — loads and caches the texture (lazy
  `load()` into a `Dictionary`, returns `null` if no path).
- `get_icon_alpha(id: String, stain: float) -> float` — the remap helper described
  above, using each def's `active_threshold`. Returns `0.0` when below threshold.
- Constants: `ICON_MIN_ALPHA := 0.45`, `ICON_ALPHA_RAMP := 4.0`.

### 3. Burn throb (per-tick orange sprite flash)

`src/status/status_component.gd`
- Add `signal burn_tick`. Emit it inside `_apply_effects()` at the point a whole
  point of burn damage is applied (`status_component.gd:124-128`), right alongside
  the existing `apply_status_damage()` call.

`src/player/player_controller.gd` and `src/enemies/enemy.gd` (parallel ~5-line edits,
mirroring how each already duplicates the tint write):
- Add `var _burn_flash: float = 0.0`.
- Connect `StatusComponent.burn_tick` → set `_burn_flash = 1.0`.
- Each frame, decay `_burn_flash` toward 0 (`_burn_flash = maxf(0.0, _burn_flash -
  delta * BURN_FLASH_DECAY)`, `BURN_FLASH_DECAY ≈ 6.0`).
- In the existing per-frame modulate write (`player_controller.gd:112-116`,
  `enemy.gd:184-190`), fold it in: `var m = blended_tint; if _burn_flash > 0.0: m =
  m.lerp(BURN_FLASH_COLOR, _burn_flash * BURN_FLASH_MAX)`, then assign `m` where the
  blended tint is currently assigned.
- Constants: `BURN_FLASH_COLOR` ≈ bright orange `Color(1.0, 0.55, 0.15)`,
  `BURN_FLASH_MAX ≈ 0.7`.

This rides the existing tint path, so it is automatically skipped while a hit-flash
tween is active (the existing `if not (_flash_tween and _flash_tween.is_valid())`
guard) and resumes after. Result: a rhythmic ≈4/sec orange throb synced to actual
burn ticks.

### 4. Ember vignette (player only)

`src/core/juice/damage_vignette.gd`
- Add a **second** `ColorRect` + `ShaderMaterial` instance using the same
  `shaders/ui/damage_vignette.gdshader`, with an ember `vignette_color`
  (≈ `Color(1.0, 0.4, 0.05)`). Independent of the existing red hit/low-health
  channel so burning never reads as taking a hit.
- Add `set_burn_intensity(t: float)` — maps a normalized burn intensity to the ember
  material's `intensity` uniform, smoothed toward the target (e.g. `lerp` per frame
  in `_process`, or a short tween) so it ramps up and fades out rather than snapping.

`src/player/player_controller.gd`
- Each frame, read the player's `on_fire` stain via its `StatusComponent`, normalize
  to `[0, 1]` (reuse `StatusRegistry.get_icon_alpha("on_fire", stain)` or an
  equivalent remap), and call `HitReaction.vignette.set_burn_intensity(...)`.
- Enemies never touch the vignette.

### 5. HUD cleanup

`src/ui/hud.gd`
- Remove `_build_status_strip()` and `_refresh_status_strip()`, the `_status_strip`
  field, and their wiring in `_ready()` (the `_status.changed.connect(...)` and
  build/refresh calls). The `_status` lookup can go too if otherwise unused. World-
  space icons fully replace the chip strip.

## Data Flow

```
StatusComponent (per entity, already exists)
  ├─ tick() every physics frame → changed.emit()
  │     └─ StatusVisuals.on changed:
  │           reconcile icon sprites (active set)
  │           set each alpha = get_icon_alpha(id, stain)
  │           CPUParticles2D.emitting = has_status("on_fire")
  ├─ _apply_effects(): whole burn point applied
  │     ├─ owner.apply_status_damage(whole)   (existing)
  │     └─ burn_tick.emit()  (new)
  │           └─ entity: _burn_flash = 1.0
  │                 (folded into per-frame modulate as orange throb)
  └─ player only, per frame:
        vignette.set_burn_intensity(norm(on_fire stain))  → ember edge glow
```

## Tuning Constants (all adjustable)

- `StatusRegistry.ICON_MIN_ALPHA = 0.45`, `ICON_ALPHA_RAMP = 4.0`
- `StatusVisuals`: icon display size ≈16px, `SPACING ≈ 18`, `head_offset` per owner,
  particle emission rate/lifetime
- Entity: `BURN_FLASH_COLOR = Color(1.0, 0.55, 0.15)`, `BURN_FLASH_MAX = 0.7`,
  `BURN_FLASH_DECAY = 6.0`
- `DamageVignette`: ember `vignette_color = Color(1.0, 0.4, 0.05)`, burn-intensity
  smoothing rate

## Testing

- **Unit (`tests/unit/`, gdUnit4):** alongside existing `test_status_*` companions —
  - `StatusRegistry.get_icon_alpha()`: below threshold → 0; at threshold →
    `ICON_MIN_ALPHA`; at/above `threshold + RAMP` → 1.0; monotonic between.
  - `StatusRegistry.get_icon()`: returns a non-null texture for every defined status
    id and `null` for an unknown id.
- **Visual (run the game):** icons appear above player and enemies, fade with
  intensity, and vanish on lapse; burning entities emit flame particles and throb
  orange in time with damage; the player screen gains an ember vignette while burning
  that fades out after; the old HUD chip strip is gone.

## Out of Scope

- Floating burn damage numbers and burn-driven screen shake (explicitly declined).
- Non-fire status VFX beyond the icon (frost/oil auras, etc.).
- Sourcing icons from the DawnLike effect sheet (dedicated PNGs already provided).
