# Soul Knight-Style Melee Weapon with Trail Design

## Summary

Implement a persistent visible weapon on the player that creates a trail of tinted sprite copies during attack swings. The weapon follows the player's facing direction when idle and sweeps through an arc during attacks, leaving distinct colored trail copies behind.

## Motivation

The current melee attack uses a Line2D arc that appears briefly - a "shock wave" effect. Soul Knight's melee attacks feature a visible weapon sprite that's always shown on the player, and during attacks the weapon swings through an arc leaving a trail of tinted copies behind. This provides better visual feedback and a more satisfying attack feel.

## Requirements

### Functional Requirements
- Weapon sprite is always visible on the player, following facing direction
- During attack, weapon swings through a 90-degree arc
- 3-5 trail copies spawn during swing with distinct colors
- Trail copies remain stationary (don't follow player movement)
- Material dispersal happens instantly at swing start (current behavior preserved)
- Weapon returns to rest position after swing (aligned with facing direction)

### Non-Functional Requirements
- Simple implementation using existing Godot nodes
- Each weapon loads its own texture (not managed by WeaponManager)
- Trail colors use distinct values for visual impact
- Easy to adjust swing speed, arc angle, and trail count via constants

## Architecture

### Component Overview

```
Player (CharacterBody2D)
├── ColorRect (player body)
├── Camera2D
├── CollisionShape2D
├── PointLight2D
├── WeaponVisual (NEW)
│   └── Sprite2D (weapon.png, rotates based on facing direction)
└── WeaponManager
    └── Weapons[] (MeleeWeapon, etc.)

MeleeWeapon (Resource)
├── Loads own texture: preload("res://textures/weapon.png")
├── Calls world_manager.disperse_materials_in_arc() instantly
├── Spawns MeleeSwingEffect with direction + texture reference
└── Manages cooldown

MeleeSwingEffect (Node2D - spawned during attack)
├── Trails (Node2D container)
│   ├── Trail Sprite 1 (cyan tint)
│   ├── Trail Sprite 2 (blue tint)
│   ├── Trail Sprite 3 (purple tint)
│   └── Trail Sprite 4 (white tint)
└── Swing animation logic
```

## Component Details

### WeaponVisual

**File:** `src/player/weapon_visual.gd`

**Scene:** `scenes/weapon_visual.tscn`

**Purpose:** Persistent weapon display that follows player's facing direction.

**Constants:**
- `WEAPON_TEXTURE: Texture2D = preload("res://textures/weapon.png")`
- `PIVOT_DISTANCE: float = 15.0` - distance from player center to weapon handle

**Instance Variables:**
- `_sprite: Sprite2D` - reference to the weapon sprite node

**Methods:**

1. `_ready() -> void`
   - Get reference to Sprite2D child
   - Set sprite texture to WEAPON_TEXTURE
   - Set sprite offset so handle pivots correctly (offset = half sprite width)

2. `_process(delta: float) -> void`
   - Get facing direction from parent PlayerController via `get_facing_direction()`
   - Calculate weapon position: `Vector2(cos(angle), sin(angle)) * PIVOT_DISTANCE`
   - Rotate weapon sprite to point in facing direction (angle + PI/2 for perpendicular alignment)

**Scene Structure:**
```
WeaponVisual (Node2D)
└── Sprite2D
    └── offset: Vector2(half_width, 0)  // so handle is at origin
```

### MeleeSwingEffect

**File:** `src/effects/melee_swing_effect.gd` (modified)

**Scene:** `scenes/melee_swing_effect.tscn` (modified)

**Purpose:** Visual swing animation with trail copies.

**Constants:**
- `SWING_DURATION: float = 0.25` - total swing time in seconds
- `HALF_ARC: float = PI / 4.0` - 45 degrees each side (90-degree arc)
- `BLADE_DISTANCE: float = 20.0` - distance from player center to weapon pivot
- `TRAIL_COUNT: int = 4` - number of trail copies
- `TRAIL_COLORS: Array[Color] = [Color(0.3, 0.9, 1.0, 0.7), Color(0.4, 0.6, 1.0, 0.5), Color(0.7, 0.4, 1.0, 0.35), Color(1.0, 1.0, 1.0, 0.2)]` - cyan, blue, purple, white

**Instance Variables:**
- `_elapsed: float = 0.0`
- `_start_angle: float` - angle where swing begins
- `_end_angle: float` - angle where swing ends
- `_weapon_texture: Texture2D` - weapon sprite texture
- `_trails: Array[Sprite2D] = []` - spawned trail sprites

**Methods:**

1. `setup(direction: Vector2, texture: Texture2D) -> void`
   - Store `_weapon_texture = texture`
   - Calculate `_start_angle = direction.angle() - HALF_ARC`
   - Calculate `_end_angle = direction.angle() + HALF_ARC`
   - Spawn trail sprites at start position, each with own tint

2. `_process(delta: float) -> void`
   - Increment `_elapsed` by delta
   - Calculate progress `t = _elapsed / SWING_DURATION`
   - If `t >= 1.0`: `queue_free()`
   - Apply ease-out curve: `t_eased = ease(t, 2.0)`
   - Calculate current angle: `lerp(_start_angle, _end_angle, t_eased)`
   - Update last trail sprite position to current swing position
   - Update all trail alphas based on remaining swing time

**Trail Spawning:**
- All trail sprites created in `setup()`
- Position all at start position initially
- Each frame, move the last trail (most recent) to current swing position
- Previous trails stay stationary, only update alpha

### MeleeWeapon

**File:** `src/weapons/melee_weapon.gd` (modified)

**Purpose:** Weapon logic that triggers attack and spawns visual effect.

**Constants:**
- `WEAPON_TEXTURE: Texture2D = preload("res://textures/weapon.png")`
- `RANGE: float = 40.0` (existing)
- `ARC_ANGLE: float = PI / 2.0` (existing)
- `COOLDOWN: float = 0.5` (existing)
- `PUSH_SPEED: float = 60.0` (existing)

**Modified Method:**

```gdscript
func _spawn_effect(user: Node, direction: Vector2) -> void:
    var effect_scene := preload("res://scenes/melee_swing_effect.tscn")
    var effect := effect_scene.instantiate()
    effect.global_position = user.global_position
    effect.setup(direction, WEAPON_TEXTURE)
    user.get_tree().current_scene.add_child(effect)
```

### MeleeSwingEffect Scene

**File:** `scenes/melee_swing_effect.tscn` (modified)

**Structure:**
```
MeleeSwingEffect (Node2D)
└── Trails (Node2D)
    └── (trail sprites spawned dynamically)
```

The Line2D node is removed; replaced with dynamically spawned Sprite2D nodes.

## Data Flow

```
Player presses attack key (Z/X/C)
    │
    ▼
WeaponManager._input()
    └─ weapons[slot].use(player)
        │
        ▼
MeleeWeapon.use()
    ├─ Check cooldown
    ├─ Call world_manager.disperse_materials_in_arc() (instant)
    └─ Spawn MeleeSwingEffect
        │
        ▼
MeleeSwingEffect.setup(direction, texture)
    ├─ Calculate start/end angles
    ├─ Create trail sprites with tints
    └─ Position all at start
        │
        ▼
MeleeSwingEffect._process() (each frame)
    ├─ Ease-out interpolate angle
    ├─ Update last trail position
    ├─ Fade all trail alphas
    └─ queue_free() when complete

WeaponVisual._process() (every frame)
    ├─ Get facing direction from PlayerController
    ├─ Calculate weapon position from angle
    └─ Update sprite position and rotation
```

## Implementation Notes

### Weapon Sprite Asset

User will provide `weapon.png` to be placed at `textures/weapon.png`.

### Trail Visual Design

- Trail copies use the same texture as the main weapon
- Each copy has a distinct semi-transparent color
- Colors progress from cyan (most recent) to white (oldest)
- Creates a stylized "motion blur" effect with color gradient

### Positioning

- Weapon pivot is at the handle (near player)
- Blade extends outward in facing direction
- During swing, blade sweeps through arc centered on player position
- Trail copies are spawned in world space (not relative to player)

## Files Changed

| File | Change |
|------|--------|
| `src/player/weapon_visual.gd` | NEW - WeaponVisual component |
| `scenes/weapon_visual.tscn` | NEW - WeaponVisual scene |
| `src/effects/melee_swing_effect.gd` | MODIFIED - Add trail logic |
| `scenes/melee_swing_effect.tscn` | MODIFIED - Remove Line2D, add Trails container |
| `src/weapons/melee_weapon.gd` | MODIFIED - Add texture constant, pass to effect |
| `scenes/player.tscn` | MODIFIED - Add WeaponVisual node |
| `textures/weapon.png` | NEW - Provided by user |

## Testing Plan

1. **Visual Tests:**
   - Verify weapon sprite visible on player when idle
   - Verify weapon rotates to follow facing direction
   - Attack while facing right: weapon sweeps downward
   - Attack while facing up: weapon sweeps left-to-right
   - Attack while moving: trail copies stay in world space
   - All trail colors visible with correct tints

2. **Timing Tests:**
   - Swing completes in ~0.25 seconds
   - Effect cleans up after animation
   - Cooldown respected (0.5 seconds between attacks)

3. **Functional Tests:**
   - Materials still pushed away correctly
   - Multiple rapid attacks work correctly
   - Weapon returns to facing direction after swing