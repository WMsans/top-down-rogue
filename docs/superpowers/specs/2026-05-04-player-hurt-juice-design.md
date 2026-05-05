# Player Hurt Juice Design

## Overview

Wire the player damage path into the existing `HitReaction` juice autoload and add player-specific visual feedback: knockback, hit flash, squash/stretch, camera zoom punch, and a red damage vignette with persistent low-health pulse. Currently enemies receive all five `HitReaction` effects (screen shake, chromatic flash, hit sparks, damage numbers, hit-stop) but the player receives none — only a `visible` toggle blink and health bar flash.

## Architecture

```
Enemy Weapon → on_hit_impact(impact_point, hit_dir, damage)
                                    │
                                hit_dir ──────┐
                                    │          │
LavaDamageChecker → take_damage(damage, Vector2.ZERO)
                          │
                          ├─ HitReaction.play(spec)          [5 effects]
                          ├─ HitReaction.vignette.pulse(amount)  [damage vignette]
                          ├─ Player knockback
                          ├─ Player hit flash + squash/stretch
                          └─ Camera zoom punch (damage ≥ 10)
```

## Files

| File | Action |
|------|--------|
| `src/player/player_inventory.gd` | Modify: `hit_direction` param, `HitReaction.play()` call |
| `src/player/player_controller.gd` | Modify: knockback, flash, squash/stretch, zoom punch |
| `src/player/lava_damage_checker.gd` | Modify: pass `Vector2.ZERO` direction |
| `src/core/juice/hit_reaction.gd` | Modify: damage vignette integration |
| `src/core/juice/damage_vignette.gd` | **New**: CanvasLayer + vignette logic |
| `shaders/ui/damage_vignette.gdshader` | **New**: Vignette shader |

## Components

### 1. `PlayerInventory.take_damage()` — HitReaction Integration

```gdscript
const DAMAGE_COLOR := Color(1.0, 0.25, 0.08)

func take_damage(amount: int, hit_direction: Vector2 = Vector2.ZERO) -> void:
    if _is_dead or _is_invincible:
        return
    _current_health = maxi(_current_health - amount, 0)
    _is_invincible = true
    _invincible_timer = invincibility_duration

    var spec := HitSpec.new()
    spec.position = get_parent().global_position
    spec.direction = hit_direction
    spec.damage = float(amount)
    spec.is_kill = _current_health <= 0
    spec.source_color = DAMAGE_COLOR
    HitReaction.play(spec)
    HitReaction.vignette.pulse(float(amount))

    health_changed.emit(_current_health, max_health)
    if _current_health <= 0:
        if GameModeManager.is_creative():
            _current_health = max_health
            health_changed.emit(_current_health, max_health)
        else:
            _is_dead = true
            if _color_rect:
                _color_rect.visible = true
            player_died.emit()
```

### 2. Player Knockback (`PlayerController`)

```gdscript
const KNOCKBACK_SPEED := 200.0
const KNOCKBACK_DECAY := 12.0
var _knockback_velocity: Vector2 = Vector2.ZERO
```

- `on_hit_impact`: set `_knockback_velocity = -hit_dir.normalized() * KNOCKBACK_SPEED` when dir is non-zero
- `_physics_process`: `_knockback_velocity *= exp(-KNOCKBACK_DECAY * delta)`, add to velocity before `move_and_slide()`
- Zero-direction hits (lava) produce no knockback

### 3. Player Hit Flash (`PlayerController`)

On damage in `on_hit_impact`:
- Kill any existing flash tween
- Set `_color_rect.modulate = Color(2.5, 0.3, 0.1)`  # bright red-orange, HDR for bloom pop
- Tween back to `Color.WHITE` over 0.12s

Orthogonal to invincibility blink (which toggles `visible`). The two compose naturally.

### 4. Player Squash/Stretch (`PlayerController`)

On damage in `on_hit_impact`:
- Kill any existing squash tween
- `var sgn := -1.0 if _facing_left else 1.0`
- Tween `_color_rect.scale` from current to `Vector2(sgn * 1.3, 0.7)` over 0.06s
- Then elastic back to `Vector2(sgn, 1.0)` over 0.12s

Preserves the facing sign on `scale.x` throughout the squash so the sprite does not visually flip. Pivot offset already centered to body in `_ready()`. After the tween completes, `_physics_process` continues setting `scale.x = sgn` each frame (line 66) — no conflict.

### 5. Camera Zoom Punch (`PlayerController`)

```gdscript
const ZOOM_PUNCH_THRESHOLD := 10.0
const ZOOM_PUNCH_AMOUNT := 0.92
const ZOOM_PUNCH_DURATION := 0.15
```

Triggered in `on_hit_impact` when `damage >= ZOOM_PUNCH_THRESHOLD`:
- `var default_zoom := camera.zoom`  # snapshot current zoom
- Kill prior zoom tween
- Tween `camera.zoom` from `default_zoom` to `default_zoom * ZOOM_PUNCH_AMOUNT` over 0.07s (`TRANS_CUBIC`)
- Then back to `default_zoom` over 0.08s

Camera zoom (`zoom`) and screen shake (`offset`) are orthogonal — no conflict.

### 6. Damage Vignette

**`shaders/ui/damage_vignette.gdshader`**:

```glsl
shader_type canvas_item;
uniform float intensity : hint_range(0.0, 2.0) = 0.0;
uniform vec4 vignette_color : source_color = vec4(0.8, 0.05, 0.0, 1.0);
uniform float radius : hint_range(0.1, 1.5) = 0.55;
void fragment() {
    vec2 uv = UV;
    float dist = distance(uv, vec2(0.5));
    // max corner distance ≈ 0.707, so outer edge must be ≤ 0.707 for full opacity
    float vignette = smoothstep(radius, 0.70, dist);
    COLOR = vec4(vignette_color.rgb, vignette * intensity * vignette_color.a);
}
```

No built-in `TIME` pulse — intensity is driven externally via tween/signal for sharper control.

**`src/core/juice/damage_vignette.gd`**:

```gdscript
extends CanvasLayer

const DAMAGE_PULSE_STRENGTH := 0.5
const DAMAGE_PULSE_UP := 0.07
const DAMAGE_PULSE_DOWN := 0.18
const LOW_HEALTH_STRENGTH := 0.18
const LOW_HEALTH_RATIO := 0.25
const LOW_HEALTH_PULSE_SPEED := 1.2
const LOW_HEALTH_TRANSITION := 0.4
```

Managed as a child of the `HitReaction` autoload (always present).

**On damage (via `take_damage` → `vignette.pulse()`):**
- Tween `intensity` to `DAMAGE_PULSE_STRENGTH` over `DAMAGE_PULSE_UP`
- Then to `current_baseline` over `DAMAGE_PULSE_DOWN`
- `current_baseline` = `LOW_HEALTH_STRENGTH` if in low-health state, else 0

**Persistent low-health:**
- Triggered when `health_ratio <= LOW_HEALTH_RATIO` and player is not dead
- Transition to `LOW_HEALTH_STRENGTH` over `LOW_HEALTH_TRANSITION`
- While active, `_process` oscillates intensity ±30% via `sin(TIME * LOW_HEALTH_PULSE_SPEED)`
- On heal above threshold, tween to 0 over 0.3s
- On death, release — death screen provides its own vignette

**Integration:**

- `HitReaction` instantiates the `DamageVignette` CanvasLayer as a child in `_ready()` and exposes it via `HitReaction.vignette`.
- `PlayerInventory.take_damage()` calls `HitReaction.vignette.pulse(damage)` on every hit — player-only trigger.
- `DamageVignette` subscribes to `PlayerInventory.health_changed` signal using `call_deferred("_connect_to_player")` to handle timing: the autoload tree is ready before the player scene exists. `_connect_to_player` finds the player via group, gets the `PlayerInventory` node, and connects. If the player is not found yet, retries with a short timer.

## Invariants

- Lava damage uses `Vector2.ZERO` direction — zero knockback, no directional shake bias
- Enemy attack direction preserved end-to-end from weapon to `take_damage`
- All new effects compose without conflicting with existing invincibility blink
- Camera zoom punch and screen shake operate on orthogonal camera properties
- Death vignette takes precedence over damage vignette — not active simultaneously
