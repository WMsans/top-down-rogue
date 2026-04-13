# Bouncy Melee Weapon Swing Animation

## Goal
Replace the mechanical swing animation with a bouncy, elastic swing followed by a smooth return to idle position.

## Current State
- WeaponVisual uses linear ease-in (`ease(t, 2.0)`) for the swing
- No return animation - weapon snaps back to idle position after swing completes
- Single phase animation from start_angle to end_angle

## Design

### Animation Phases

**Phase 1: Swing Out (~70% of duration)**
- Weapon swings from start_angle to end_angle with elastic overshoot
- Use custom elastic easing to overshoot ~10-15% past end_angle
- Creates bouncy, energetic feel

**Phase 2: Return to Idle (~30% of duration)**
- Smooth ease-out interpolation from overshoot position to idle
- Weapon settles naturally near player's facing direction
- Trails fade out during this phase

### Implementation Changes

**Constants to add:**
```gdscript
const OVERSHOOT_RATIO: float = 0.15  # How far past end_angle to overshoot
const SWING_PHASE_RATIO: float = 0.7  # Portion of duration for swing-out
```

**Easing function:**
Custom elastic/bounce easing that overshoots and settles:
- Peak at overshoot position
- Returns toward target
- Natural deceleration

**Key changes to weapon_visual.gd:**
1. Split `_process_swing()` into swing-out and return phases
2. Add elastic easing for overshoot effect
3. Track when swinging vs returning
4. Smoothly transition back to idle when complete

### Files Modified
- `src/player/weapon_visual.gd` - Animation logic changes only

### Success Criteria
- Weapon visibly overshoots end angle during swing
- Returns smoothly to idle (near player facing direction)
- Animation feels organic and bouncy, not mechanical
- Trails still display correctly and fade naturally