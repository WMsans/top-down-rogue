# Soul Knight-Style Melee Swing Animation Design

## Summary

Replace the current melee attack's semi-circle Line2D effect with a blade sprite that visibly swings through the attack arc. Material dispersal remains instant at swing start, while the visual effect animates the weapon sweeping through the arc.

## Motivation

The current melee attack uses a static semi-circle Line2D that appears briefly - this looks like a "shock wave" rather than a weapon swing. Soul Knight's melee attacks feature a visible blade that sweeps through the arc, giving better visual feedback and a more satisfying attack feel.

## Requirements

### Functional Requirements
- Blade sprite sweeps through attack arc over swing duration
- Material dispersal happens instantly at swing start (current behavior preserved)
- Swing direction based on player facing direction
- Effect auto-cleans up after animation completes

### Non-Functional Requirements
- Simple implementation using single sprite rotation
- Easy to adjust swing speed, arc angle, and range via constants
- No new art assets required (can use simple shape initially)

## Architecture

### Component Overview

```
MeleeSwingEffect (Node2D)
├── Sprite2D node for blade visual
└── Script handles swing animation

MeleeWeapon (unchanged core logic)
├── Calls world_manager.disperse_materials_in_arc() instantly
├── Spawns MeleeSwingEffect with direction
└── Cooldown management
```

## Component Details

### MeleeSwingEffect

**File:** `src/effects/melee_swing_effect.gd`

**Constants:**
- `SWING_DURATION: float = 0.2` - time to complete swing in seconds
- `HALF_ARC: float = PI / 4.0` - half of the 90-degree arc
- `BLADE_DISTANCE: float = 20.0` - distance from player to blade pivot

**Instance Variables:**
- `_elapsed: float = 0.0` - time since swing started
- `_start_angle: float` - starting angle of swing
- `_end_angle: float` - ending angle of swing

**Methods:**

1. `_ready() -> void`
   - Calculate `_start_angle` from current rotation minus `HALF_ARC`
   - Calculate `_end_angle` from current rotation plus `HALF_ARC`
   - Set initial blade position

2. `_process(delta: float) -> void`
   - Increment `_elapsed` by `delta`
   - Calculate progress `t = _elapsed / SWING_DURATION`
   - If `t >= 1.0`: `queue_free()`
   - Calculate current angle: interpolate from `_start_angle` to `_end_angle`
   - Apply ease-out function for natural deceleration
   - Update blade sprite position: `Vector2(cos(current_angle), sin(current_angle)) * BLADE_DISTANCE`
   - Fade out alpha as swing completes

**Scene Structure:** `scenes/melee_swing_effect.tscn`

```
MeleeSwingEffect (Node2D)
└── Sprite2D
    └── (Blade texture, positioned at offset)
```

### Ease Function

Use `ease(t, 2.0)` for ease-out curve, giving the swing a natural deceleration feel.

### Swing Motion

The blade starts at `facing_direction - HALF_ARC` and rotates through to `facing_direction + HALF_ARC`. For a player facing right:
- Start: 45 degrees up from facing direction
- End: 45 degrees down from facing direction
- The blade "sweeps" downward through enemies/materials

## Data Flow

```
Player presses attack key
    │
    ▼
MeleeWeapon.use()
    ├─ Check cooldown
    ├─ Call world_manager.disperse_materials_in_arc() (instant)
    └─ Spawn MeleeSwingEffect with direction
        │
        ▼
MeleeSwingEffect._ready()
    ├─ Calculate start_angle = direction.angle() - HALF_ARC
    ├─ Calculate end_angle = direction.angle() + HALF_ARC
    └─ Position blade at start
        │
        ▼
MeleeSwingEffect._process() (each frame)
    ├─ Interpolate angle toward end_angle
    ├─ Apply ease-out for smooth motion
    ├─ Update blade position
    ├─ Fade alpha
    └─ queue_free() when complete
```

## Implementation Notes

### Blade Visual

Initially use a simple colored polygon or rectangle for the blade:
- Pale color (white/light gray) for visibility
- Size approximately 30-40 pixels long, 4-6 pixels wide
- Can be replaced with proper sprite asset later

### Positioning

The blade is positioned relative to the effect's origin (which is set to player position by MeleeWeapon):
- Blade x = `cos(current_angle) * BLADE_DISTANCE`
- Blade y = `sin(current_angle) * BLADE_DISTANCE`

## Files Changed

| File | Change |
|------|--------|
| `scenes/melee_swing_effect.tscn` | Replace Line2D with Sprite2D |
| `src/effects/melee_swing_effect.gd` | Rewrite for swing animation logic |

## Testing Plan

1. **Visual Tests:**
   - Attack while facing right: blade sweeps downward
   - Attack while facing up: blade sweeps left-to-right
   - Attack while moving vs stationary: correct direction each time

2. **Timing Tests:**
   - Verify swing completes in ~0.2 seconds
   - Verify effect cleans up after animation

3. **Functional Tests:**
   - Materials still pushed away correctly
   - Cooldown still respected
   - Multiple attacks in succession work correctly