# Juicy Melee Hit — Design

## Problem

`MeleeWeapon._use_impl` only pushes fluids via `world_manager.clear_and_push_materials_in_arc`. It never queries enemies in the swing arc and never calls `Enemy.hit()`. As a result, the player cannot damage enemies with the melee weapon.

Additionally, even once damage is wired up, hits will feel weightless. We want an "extremely juicy" impact feel.

## Goals

1. Fix the bug: melee swings damage enemies inside the swing arc.
2. Make each hit feel meaty via layered juice effects.

## Non-goals

- Sound effects (no SFX assets yet).
- Slow-motion on kill (excluded by user).
- Reworking the swing animation itself.
- Reworking enemy AI beyond accepting knockback.

## Bug Fix

In `Enemy._ready`, join the `attackable` group.

In `MeleeWeapon._use_impl`:
- After the existing fluid push, scan `user.get_tree().get_nodes_in_group("attackable")`.
- For each enemy, compute `to_enemy = enemy.global_position - pos`.
  - Reject if `to_enemy.length() > RANGE`.
  - Reject if `abs(angle_difference(direction.angle(), to_enemy.angle())) > ARC_ANGLE / 2.0`.
- For surviving enemies: call `enemy.on_hit_impact(pos, direction, int(damage))`. The new method handles damage application + per-enemy juice; the weapon does not call `hit()` directly (so juice can react to the contact point/dir).

## Per-Enemy Juice (in `Enemy`)

Add `on_hit_impact(impact_point: Vector2, hit_dir: Vector2, damage: int)`:
1. Apply knockback velocity.
2. Apply hit flash.
3. Apply squash-stretch.
4. Trigger global juice via `JuiceManager` (sparks at impact_point, damage number above enemy, hit-stop, shake, chromatic flash).
5. Call `hit(damage)` last, so juice runs even on the lethal hit before `queue_free`.

### Knockback

- New fields: `_knockback_velocity: Vector2`, `_knockback_decay: float = 12.0`.
- `on_hit_impact` adds `hit_dir.normalized() * KNOCKBACK_SPEED` (180 px/s) to `_knockback_velocity`.
- In `_process(delta)`: exponential decay `_knockback_velocity *= exp(-_knockback_decay * delta)`; zero out below 1 px/s.
- `DummyEnemy._process` adds `_knockback_velocity * delta` to `global_position` BEFORE the existing chase movement, so knockback can briefly out-pace chase speed.

### Hit Flash

- Modulate sprite to `Color(3, 3, 3)` instantly.
- Tween back to base color over `FLASH_DECAY = 0.12s`.
- Replaces the existing simpler flash in `DummyEnemy._on_hit`. Move the implementation up to `Enemy` so it applies to all enemy subtypes; `DummyEnemy` overrides only the base color (green).

### Squash-Stretch

- On hit, set sprite scale to `(1.4, 0.7)`.
- Tween back to `(1, 1)` over `0.18s` with `Tween.TRANS_ELASTIC`, `Tween.EASE_OUT`.
- Kill any in-flight squash tween before starting a new one.

## Global Juice (one autoload per effect)

Each effect is its own focused autoload. This keeps each manager small, single-purpose, independently testable, and easy to reuse from other systems (projectile hits, environmental damage, etc.) without dragging unrelated state along. All managers use `PROCESS_MODE_ALWAYS` so hit-stop (which sets `Engine.time_scale = 0`) doesn't freeze them.

| Autoload | File | Responsibility |
|---|---|---|
| `HitSparkManager` | `src/core/juice/hit_spark_manager.gd` | Spawn radial spark bursts |
| `DamageNumberManager` | `src/core/juice/damage_number_manager.gd` | Pop floating damage numbers |
| `HitStopManager` | `src/core/juice/hit_stop_manager.gd` | Freeze `Engine.time_scale` briefly |
| `ScreenShakeManager` | `src/core/juice/screen_shake_manager.gd` | Drive active `Camera2D` offset |
| `ChromaticFlashManager` | `src/core/juice/chromatic_flash_manager.gd` | Owns the chromatic CanvasLayer + shader |

APIs:
```
HitSparkManager.spawn(point: Vector2, dir: Vector2) -> void
DamageNumberManager.spawn(pos: Vector2, amount: int) -> void
HitStopManager.stop(duration: float) -> void
ScreenShakeManager.shake(amount: float, duration: float, dir: Vector2 = Vector2.ZERO) -> void
ChromaticFlashManager.flash(strength: float = 0.6, duration: float = 0.12) -> void
```

Each manager owns its own constants (listed under "Tuning Constants" below). Re-entrant calls: latest call wins (not stacked) for `HitStopManager`, `ScreenShakeManager`, `ChromaticFlashManager`. `HitSparkManager` and `DamageNumberManager` always spawn fresh instances.

### Hit Sparks (`HitSparkManager`)

- Spawn 6–8 small `Sprite2D`s (or `ColorRect`s, 2x2 white) at `point`.
- Each gets velocity `dir.rotated(rand ±30°) * rand(80..160)`.
- Updated each frame in a small `Node2D` controller; lifetime `0.15s`; alpha fades to 0; queue_free at end.
- Added to the current scene root.

### Damage Number (`DamageNumberManager`)

- Scene `scenes/fx/damage_number.tscn`: `Label` with `LabelSettings` (outline 2px black, font white, size 12).
- On spawn: position = enemy `global_position + Vector2(0, -8)`.
- Initial scale 0.5 → 1.2 → 1.0 punch over first 0.12s.
- Velocity = `Vector2(rand(-30..30), -80)`, gravity 200 px/s² applied via `_process`.
- Alpha 1.0 hold for 0.4s then linear fade to 0 over 0.2s. Total lifetime 0.6s.

### Hit-Stop (`HitStopManager`)

- Set `Engine.time_scale = 0.0`.
- `get_tree().create_timer(duration, true, false, true)` (process always, ignore time scale) → restore `Engine.time_scale = 1.0`.
- Latest-call-wins: a new `stop()` cancels any in-flight restore and starts a fresh timer. Default duration 0.06s; +0.04s on killing hits (passed in by caller).

### Screen Shake (`ScreenShakeManager`)

- Find active `Camera2D` via `get_viewport().get_camera_2d()`.
- Each tick while shake active: `camera.offset = random_in_circle() * current_amount + dir * 0.5 * current_amount`.
- `current_amount` decays linearly to 0 over `duration`. Restore `camera.offset = Vector2.ZERO` when done.
- Defaults: amount 3px, duration 0.18s.

### Chromatic Flash (`ChromaticFlashManager`)

- New shader `shaders/chromatic_flash.gdshader`: samples `SCREEN_TEXTURE` 3x with R/G/B channel offsets along a horizontal vector scaled by uniform `strength`.
- New scene `scenes/fx/chromatic_flash.tscn`: `CanvasLayer` (layer = 100) + `ColorRect` covering full rect with the shader as material.
- The manager instances this scene once at `_ready` and keeps it as a child of itself (autoloads persist across scene changes). `flash(strength, duration)` tweens the shader's `strength` uniform `strength → 0` over `duration`. Latest-call-wins: a new flash kills the existing tween.

## Order of Operations on Hit

In `Enemy.on_hit_impact`:
1. Knockback velocity applied.
2. Flash + squash started.
3. `HitSparkManager.spawn(impact_point, hit_dir)`.
4. `DamageNumberManager.spawn(global_position, damage)`.
5. `ScreenShakeManager.shake(3, 0.18, hit_dir)`.
6. `ChromaticFlashManager.flash(0.6, 0.12)`.
7. `HitStopManager.stop(0.06 + (0.04 if lethal else 0.0))` — last, freezes the visible frame after all visuals are spawned.
8. `hit(damage)`.

Lethality is computed by the caller before step 7: `lethal = damage >= health`.

## Tuning Constants

In `HitStopManager`:
- `HIT_STOP_BASE = 0.06`
- `HIT_STOP_KILL_BONUS = 0.04`

In `ScreenShakeManager`:
- `SHAKE_AMOUNT = 3.0`, `SHAKE_DURATION = 0.18`

In `HitSparkManager`:
- `SPARK_COUNT_MIN = 6`, `SPARK_COUNT_MAX = 8`
- `SPARK_SPEED_MIN = 80`, `SPARK_SPEED_MAX = 160`
- `SPARK_LIFETIME = 0.15`

In `DamageNumberManager`:
- `DAMAGE_NUMBER_LIFETIME = 0.6`

In `ChromaticFlashManager`:
- `CHROMATIC_STRENGTH = 0.6`, `CHROMATIC_DURATION = 0.12`

In `Enemy`:
- `KNOCKBACK_SPEED = 180.0`
- `KNOCKBACK_DECAY = 12.0`
- `FLASH_COLOR = Color(3, 3, 3)`
- `FLASH_DECAY = 0.12`
- `SQUASH_SCALE = Vector2(1.4, 0.7)`
- `SQUASH_DURATION = 0.18`

## Files

**New**
- `src/core/juice/hit_spark_manager.gd` — autoload
- `src/core/juice/damage_number_manager.gd` — autoload
- `src/core/juice/hit_stop_manager.gd` — autoload
- `src/core/juice/screen_shake_manager.gd` — autoload
- `src/core/juice/chromatic_flash_manager.gd` — autoload
- `scenes/fx/damage_number.tscn`
- `scenes/fx/chromatic_flash.tscn`
- `shaders/chromatic_flash.gdshader`

**Edited**
- `src/weapons/melee_weapon.gd` — enemy scan + `on_hit_impact` calls
- `src/enemies/enemy.gd` — group join, `on_hit_impact`, knockback, flash, squash; base color tracked so subtypes can override
- `src/enemies/dummy_enemy.gd` — apply `_knockback_velocity` in movement; declare base color = green for the new shared flash logic
- `project.godot` — register all five juice manager autoloads

## Testing

- Spawn dummy enemy via console command, swing into it: HP decreases, all juice fires.
- Swing past it (outside arc): no damage.
- Swing at edge of `RANGE`: hits if inside, misses if outside.
- Kill blow: hit-stop is slightly longer; enemy still drops loot via existing `die()` path.
- Multiple enemies in arc: all take damage on a single swing; each gets its own knockback/flash; only one hit-stop / shake / chromatic flash queues (re-entrant safe).
