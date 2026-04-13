# Bouncy Melee Swing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace mechanical swing with elastic overshoot and smooth return animation

**Architecture:** Two-phase animation in WeaponVisual - swing phase uses elastic easing to overshoot past end angle, return phase smoothly eases back to idle position near player facing direction

**Tech Stack:** GDScript, Godot 4.x

---

### Task 1: Add Animation Constants

**Files:**
- Modify: `src/player/weapon_visual.gd:7-16`

- [ ] **Step 1: Add constants for overshoot and phase timing**

Add after the existing constants (after line 16):

```gdscript
const OVERSHOOT_ANGLE: float = PI / 6.0
const SWING_PHASE_RATIO: float = 0.65
const RETURN_EASE_POWER: float = 2.5
```

- [ ] **Step 2: Verify constants are correct**

The constants should be:
- `OVERSHOOT_ANGLE`: How far past end_angle the swing overshoots (~30 degrees)
- `SWING_PHASE_RATIO`: What portion of SWING_DURATION is the swing-out phase (65%)
- `RETURN_EASE_POWER`: Easing power for smooth return animation

- [ ] **Step 3: Commit**

```bash
git add src/player/weapon_visual.gd
git commit -m "feat: add animation constants for bouncy swing"
```

---

### Task 2: Create Elastic Easing Function

**Files:**
- Modify: `src/player/weapon_visual.gd:123-125`

- [ ] **Step 1: Add elastic ease-out function**

Add after `_get_position_at_angle` function:

```gdscript
func _elastic_out(t: float) -> float:
    if t <= 0.0:
        return 0.0
    if t >= 1.0:
        return 1.0
    var p := 0.3
    return pow(2.0, -10.0 * t) * sin((t - p / 4.0) * (2.0 * PI) / p) + 1.0
```

- [ ] **Step 2: Commit**

```bash
git add src/player/weapon_visual.gd
git commit -m "feat: add elastic easing function for bouncy swing"
```

---

### Task 3: Implement Two-Phase Swing Animation

**Files:**
- Modify: `src/player/weapon_visual.gd:54-72`

- [ ] **Step 1: Replace `_process_swing` with two-phase logic**

Replace the entire `_process_swing` function:

```gdscript
func _process_swing(delta: float) -> void:
    _elapsed += delta
    
    var t := _elapsed / SWING_DURATION
    if t >= 1.0:
        _is_swinging = false
        _clear_trails()
        _process_idle()
        return
    
    if t < SWING_PHASE_RATIO:
        var swing_t := t / SWING_PHASE_RATIO
        var eased_t := _elastic_out(swing_t)
        var overshoot_end := _end_angle + OVERSHOOT_ANGLE * sign(_end_angle - _start_angle)
        var current_angle := lerpf(_start_angle, overshoot_end, eased_t)
        
        position = Vector2.ZERO
        rotation = 0.0
        _sprite.position = _get_position_at_angle(current_angle, PIVOT_DISTANCE)
        _sprite.rotation = current_angle + PI / 2.0
    else:
        var return_t := (t - SWING_PHASE_RATIO) / (1.0 - SWING_PHASE_RATIO)
        var eased_return := ease(return_t, RETURN_EASE_POWER)
        var overshoot_end := _end_angle + OVERSHOOT_ANGLE * sign(_end_angle - _start_angle)
        var current_angle := lerpf(overshoot_end, _facing_angle, eased_return)
        
        position = Vector2(cos(_facing_angle), sin(_facing_angle)) * PIVOT_DISTANCE
        rotation = _facing_angle + PI / 2.0
        _sprite.position = _get_position_at_angle(current_angle, PIVOT_DISTANCE)
        _sprite.rotation = current_angle + PI / 2.0
    
    _update_trails(t)
```

- [ ] **Step 2: Commit**

```bash
git add src/player/weapon_visual.gd
git commit -m "feat: implement two-phase bouncy swing animation"
```

---

### Task 4: Update Trail Behavior for Return Phase

**Files:**
- Modify: `src/player/weapon_visual.gd:107-121`

- [ ] **Step 1: Update `_update_trails` for smoother fade**

Replace the `_update_trails` function:

```gdscript
func _update_trails(t: float) -> void:
    var fade_alpha := 1.0
    
    if t >= SWING_PHASE_RATIO:
        var return_t := (t - SWING_PHASE_RATIO) / (1.0 - SWING_PHASE_RATIO)
        fade_alpha = 1.0 - return_t * return_t
    
    for i in range(TRAIL_COUNT):
        var trail := _trails[i]
        var trail_t: float = max(0.0, t - TRAIL_DELAY * float(i + 1))
        if trail_t > 0:
            if trail_t < SWING_PHASE_RATIO:
                var swing_t := trail_t / SWING_PHASE_RATIO
                var trail_eased := _elastic_out(swing_t)
                var overshoot_end := _end_angle + OVERSHOOT_ANGLE * sign(_end_angle - _start_angle)
                var trail_angle := lerpf(_start_angle, overshoot_end, trail_eased)
                trail.position = _get_position_at_angle(trail_angle, PIVOT_DISTANCE)
                trail.rotation = trail_angle + PI / 2.0
            else:
                var overshoot_end := _end_angle + OVERSHOOT_ANGLE * sign(_end_angle - _start_angle)
                var return_t := (trail_t - SWING_PHASE_RATIO) / (1.0 - SWING_PHASE_RATIO)
                var eased_return := ease(return_t, RETURN_EASE_POWER)
                var trail_angle := lerpf(overshoot_end, _facing_angle, eased_return)
                trail.position = _get_position_at_angle(trail_angle, PIVOT_DISTANCE)
                trail.rotation = trail_angle + PI / 2.0
        
        var base_color := TRAIL_COLORS[i]
        trail.modulate = Color(base_color.r, base_color.g, base_color.b, base_color.a * fade_alpha)
```

- [ ] **Step 2: Commit**

```bash
git add src/player/weapon_visual.gd
git commit -m "feat: update trail behavior for two-phase animation"
```

---

### Task 5: Test and Verify

**Files:**
- None (manual testing in Godot editor)

- [ ] **Step 1: Run the game and test melee swing**

Run in Godot editor and test:
1. Swing the melee weapon
2. Verify overshoot past end angle
3. Verify smooth return to idle
4. Verify trails follow correctly
5. Verify trails fade during return phase

- [ ] **Step 2: Final commit if adjustments needed**

If any parameter tuning is needed, commit with:
```bash
git add src/player/weapon_visual.gd
git commit -m "tweak: adjust bouncy swing parameters"
```