# Modifier Full-Slots Visual Feedback — Design Spec

**Date:** 2026-04-19  
**Status:** Approved

## Problem

When a player tries to pick up a `ModifierDrop` while all modifier slots on all weapons are full, `_pickup()` silently returns with no feedback. The player has no indication of why the interaction did nothing.

## Goal

Show a red outline on the weapon button icon and play a bouncy jitter animation when pickup is blocked by full slots.

## Scope

Three files touched:
- `src/drops/modifier_drop.gd` — trigger the feedback
- `src/ui/weapon_button.gd` — implement the feedback
- `src/ui/ui_animations.gd` — add reusable jitter animation

## Design

### 1. modifier_drop.gd

In `_pickup()`, replace the silent `return` with a call to `flash_slots_full()` on the `WeaponButton` node:

```gdscript
func _pickup(player: Node) -> void:
    var weapon_manager: WeaponManager = player.get_node("WeaponManager")
    if not _has_weapon_with_empty_slot(weapon_manager):
        var weapon_button = player.get_parent().get_node_or_null("WeaponButton")
        if weapon_button and weapon_button.has_method("flash_slots_full"):
            weapon_button.flash_slots_full()
        return
    ...
```

Follows existing pattern: `player.get_parent().get_node("WeaponPopup")`.

### 2. weapon_button.gd

**Red outline:** A `Panel` created programmatically in `_ready()` as a full-rect child of `_icon_button`. Uses a `StyleBoxFlat` with transparent fill, red border (2px), and `MOUSE_FILTER_IGNORE`. Hidden by default.

**`flash_slots_full()` method:**
1. Show the outline panel (if not already animating)
2. Call `UiAnimations.jitter_bounce(_icon_button)` for the animation
3. Hide the outline after 0.8s via tween callback

Guard against re-entrancy: kill any existing flash tween before starting a new one.

### 3. ui_animations.gd

Add `jitter_bounce(control: Control, duration: float = 0.35) -> Tween`:

Squash-and-stretch scale sequence on `control` with `TRANS_BACK`/`EASE_OUT` for bouncy feel:
- `scale → (1.12, 0.88)` — squash horizontal
- `scale → (0.88, 1.12)` — squash vertical  
- `scale → (1.06, 0.94)` — smaller bounce
- `scale → (1.0, 1.0)` — settle

Each step ~`duration / 4`. Uses `pivot_offset` centered via `_update_pivot_center()`.

## Visual Result

- Player interacts with a modifier drop while all slots full
- Weapon button icon briefly gets a red 2px border
- Icon squashes and stretches with a bouncy jitter (~0.35s)
- Red border disappears after ~0.8s
- No effect on layout or tooltip behavior
