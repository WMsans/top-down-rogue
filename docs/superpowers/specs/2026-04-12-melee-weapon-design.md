# Melee Weapon with Arc Hitbox Design

## Summary

Implement a melee weapon that disperses GAS and LAVA fluids within a frontal arc when the player attacks. The weapon features an instant hitbox check, cooldown-based usage, and visual swing effect feedback.

## Requirements

### Functional Requirements
- Melee weapon with short range (32-48 pixels) and 90° arc coverage
- Instant hitbox that clears GAS and LAVA materials within the arc
- Disperses fluids by pushing them away from the player (not destroying)
- Visual swing effect during attack
- Cooldown system (0.4-0.6 seconds between attacks)

### Non-Functional Requirements
- Minimal performance impact (small arc size allows CPU iteration)
- Reusable pattern for future melee weapons

## Architecture

### Component Overview

```
MeleeWeapon (extends Weapon)
├── Uses WorldManager.disperse_materials_in_arc()
├── Spawns MeleeSwingEffect (animated visual)
└── Tracks cooldown timer

WorldManager (existing)
├── New method: disperse_materials_in_arc()
└── Iterates chunks/cells in arc, updates velocities for GAS/LAVA

MeleeSwingEffect (Node2D scene)
├── Animated arc trail sprite
├── Auto-destroys after animation
└── Rotates to match attack direction
```

## Component Details

### MeleeWeapon

**File:** `src/weapons/melee_weapon.gd`

**Class:** `MeleeWeapon extends Weapon`

**Constants:**
- `RANGE: float = 40.0` - attack radius in pixels
- `ARC_ANGLE: float = PI / 2` - 90° arc in radians
- `COOLDOWN: float = 0.5` - seconds between attacks
- `PUSH_SPEED: float = 60.0` - velocity magnitude for dispersed fluids

**Instance Variables:**
- `_cooldown_timer: float` - tracks remaining cooldown time

**Methods:**

1. `_init() -> void`
   - Set `name = "Melee Weapon"`

2. `use(user: Node) -> void`
   - Check if `_cooldown_timer > 0`, return early if on cooldown
   - Get `WorldManager` reference from user
   - Get player position: `user.global_position`
   - Get player facing direction: call `user.get_facing_direction()` or use velocity normalized
   - Call `world_manager.disperse_materials_in_arc(pos, direction, RANGE, ARC_ANGLE, PUSH_SPEED, [MaterialRegistry.MAT_GAS, MaterialRegistry.MAT_LAVA])`
   - Spawn `MeleeSwingEffect` at position with rotation matching direction
   - Set `_cooldown_timer = COOLDOWN`

3. `tick(delta: float) -> void`
   - If `_cooldown_timer > 0`: decrement by `delta`

4. `is_ready() -> bool`
   - Return `_cooldown_timer <= 0`

### WorldManager Extension

**File:** `src/core/world_manager.gd` (add method to existing file)

**New Method:**

```gdscript
func disperse_materials_in_arc(
    origin: Vector2,
    direction: Vector2,
    radius: float,
    arc_angle: float,
    push_speed: float,
    materials: Array[int]
) -> void:
```

**Implementation:**

1. Calculate arc angular bounds:
   - `direction_angle = direction.angle()`
   - `half_arc = arc_angle / 2`
   - `start_angle = direction_angle - half_arc`
   - `end_angle = direction_angle + half_arc`

2. Calculate bounding box of arc:
   - Iterate corners of arc to find min/max x, y

3. For each pixel position in bounding box:
   - Calculate distance from origin
   - If distance > radius, skip
   - Calculate angle from origin to pixel
   - Normalize angle to [-PI, PI] range
   - If angle not within [start_angle, end_angle], skip
   - Get chunk coord: `Vector2i(floor(x / CHUNK_SIZE), floor(y / CHUNK_SIZE))`
   - If chunk not loaded, skip
   - Get local pixel coord: `Vector2i(posmod(x, CHUNK_SIZE), posmod(y, CHUNK_SIZE))`
   - Read material at pixel
   - If material in materials array:
     - Calculate push direction: `(pixel_pos - origin).normalized()`
     - Convert push_speed to velocity: `push_direction * push_speed`
     - Pack velocity into texture format:
       - `vx_encoded = clamp(int(round(push_vel.x / 60.0 + 8)), 0, 15)`
       - `vy_encoded = clamp(int(round(push_vel.y / 60.0 + 8)), 0, 15)`
       - `packed = (vx_encoded << 4) | vy_encoded`
     - Update pixel data: `data[idx + 3] = packed`
   - Mark chunk as modified

4. Upload modified chunk textures to GPU

**Velocity Encoding Details:**
- Velocities are packed in the alpha channel of the texture (RGBA8)
- Each velocity component uses 4 bits: `vx` in upper nibble, `vy` in lower nibble
- Encoding: `velocity_value / 60.0 + 8` maps [-480, 480] → [0, 15]
- The simulation shader interprets this as cells/second velocity

### MeleeSwingEffect

**File:** `scenes/melee_swing_effect.tscn` and `src/effects/melee_swing_effect.gd`

**Scene Structure:**
```
MeleeSwingEffect (Node2D)
├── Sprite2D (arc trail texture)
└── AnimationPlayer (play "swing" animation)
```

**Script Behavior:**
- `_ready()`: Play "swing" animation
- Animation handles scale and modulate alpha
- Animation connects "finished" signal to `queue_free()`

**Visual Design:**
- Semi-transparent white arc sprite
- Starts at scale 0.8, scales to 1.2 over animation
- Alpha fades from 1.0 to 0.0
- Duration: ~0.25 seconds

### PlayerController Extension

**File:** `src/player/player_controller.gd` (modify existing)

**Changes:**
1. Add method `get_facing_direction() -> Vector2`:
   - If `velocity.length() > 0.1`: return `velocity.normalized()`
   - Else: return last_facing_direction (track in variable)

2. Update `_ready()` to add melee weapon to weapons array:
   - `weapons[1] = MeleeWeaponScript.new()`

## Data Flow

```
Player presses attack key (Z/X/C)
    │
    ▼
PlayerController._input()
    │ calls weapon.use(self)
    ▼
MeleeWeapon.use()
    ├─ Check cooldown → return if not ready
    ├─ Get player position and facing direction
    ├─ Call world_manager.disperse_materials_in_arc()
    ├─ Spawn MeleeSwingEffect at position
    └─ Set cooldown timer
    │
    ▼
WorldManager.disperse_materials_in_arc()
    ├─ Calculate arc bounds
    ├─ For each chunk overlapping arc:
    │   ├─ Read texture data
    │   ├─ For each pixel in arc:
    │   │   └─ If GAS/LAVA: set velocity to push away
    │   └─ Upload updated texture
    │
    ▼
MeleeSwingEffect
    ├─ Plays swing animation
    └─ Queue_free after 0.25s
```

## Error Handling

| Scenario | Handling |
|----------|----------|
| WorldManager not found | Return early from use(), no effect |
| Chunk not loaded | Skip that region (natural behavior) |
| Player has no velocity | Use Vector2.DOWN as default facing |
| Invalid facing direction | Clamp to unit vector |

## Testing Plan

1. **Unit Tests (if applicable):**
   - Test arc angle calculation for various directions
   - Test velocity encoding/decoding roundtrip

2. **Manual Tests:**
   - Place GAS using TestWeapon (key Z)
   - Equip melee weapon (key X)
   - Face GAS cloud, press attack key
   - Verify GAS pushes away in arc pattern
   - Test at chunk boundaries
   - Test cooldown timing (should be ~0.5s)
   - Test visual effect plays and cleans up

3. **Edge Cases:**
   - Attack at map edge (no crash, graceful skip)
   - Attack while moving vs. stationary
   - Multiple rapid attack inputs (cooldown respected)

## Files Changed

| File | Change |
|------|--------|
| `src/weapons/melee_weapon.gd` | New file |
| `src/effects/melee_swing_effect.gd` | New file |
| `scenes/melee_swing_effect.tscn` | New file |
| `src/core/world_manager.gd` | Add `disperse_materials_in_arc()` method |
| `src/player/player_controller.gd` | Add `get_facing_direction()`, equip melee weapon |

## Future Considerations

- Different melee weapon types (sword, axe, etc.) with different range/arc/cooldown
- Damage to enemies (not just fluid dispersal)
- Knockback effect on enemies
- Combo system for multiple attacks