# Weapon Drop Info Popup — Design

**Status:** approved (brainstorm)
**Date:** 2026-05-11
**Owner:** jeremyzhao

## Problem

When the player is near a weapon drop, there is no way to preview its stats without pressing E and opening the full `WeaponPopup` modal (which pauses the game). This makes quick comparisons between ground loot tedious. Noita handles this with a floating tooltip near the staff: the player sees damage, cooldown, and modifiers at a glance just by standing near it.

## Goals

- When the player is near a weapon drop AND that drop is the closest/highlighted one, a small floating info popup appears above the drop.
- The popup shows: weapon name, damage, cooldown, and modifier icons (same card-like layout as existing weapon cards).
- The popup animates in with JuicyPanel-style bouncy transitions (slide up + elastic settle), and animates out with a short gravity-like drop.
- Smooth crossfade when switching attention between two adjacent drops.
- The popup tracks the drop in world space (handles RigidBody2D settling).
- Only weapon drops trigger this popup (modifier drops excluded for now).
- The popup does NOT pause the game — it's a passive HUD overlay, not a modal.

## Non-goals

- No popup for modifier drops, gold drops, or chests.
- No interactivity on the popup (no clicking/hovering) — it's read-only.
- No stats comparison between the popup and the player's currently equipped weapon.
- No sound effects.
- No changes to the existing E-key pickup flow — the popup is supplemental, not a replacement.

## Architecture

### New: `src/ui/weapon_info_popup.gd` + scene

`class_name WeaponInfoPopup extends CanvasLayer`. A single floating info card that repositions each frame to follow the highlighted drop.

**Why CanvasLayer?** Ensures the popup renders above the game world (and below the WeaponPopup modal, layer 15 vs 17). Positions in screen space (not world space) so it's immune to camera zoom/offset.

**Owner:** `PickupContext` — which already tracks the highest-priority drop, highlights it, and processes every frame. Adding popup management here is minimal.

**Public API:**
- `show_for(drop: WeaponDrop)` — populate card data and animate in. If already showing for a different drop, crossfade.
- `hide()` — animate out.
- `is_visible() -> bool`

**Internal structure:**
- `_card_root: Control` — anchored center, `mouse_filter = IGNORE`
- `_panel: PanelContainer` — UiTheme-styled, small padding
- `_name_label: Label` — bold, weapon name
- `_damage_label: Label` — damage stat
- `_cooldown_label: Label` — cooldown stat
- `_modifier_container: HBoxContainer` — modifier icon slots
- `_show_tween: Tween`, `_hide_tween: Tween`
- `_current_drop: WeakRef` — for debouncing/switching

### Scene: `scenes/ui/weapon_info_popup.tscn`

```
CanvasLayer (WeaponInfoPopup, layer=15)
  └─ Control (_card_root)
       └─ PanelContainer (_panel, UiTheme)
            └─ VBoxContainer
                 ├─ Label (_name_label)
                 ├─ HSeparator
                 ├─ Label (_damage_label)
                 ├─ Label (_cooldown_label)
                 └─ HBoxContainer (_modifier_container)
```

### PickupContext changes (`src/player/pickup_context.gd`)

In `_ready()`:
- Create `WeaponInfoPopup` as a child: `_info_popup = WeaponInfoPopup.new()`

In `_process()` after highlight resolution:
- If `_highlighted is WeaponDrop` → `_info_popup.show_for(_highlighted)`
- If `_highlighted is ModifierDrop` → `_info_popup.hide()` (reserved for future)
- Otherwise → `_info_popup.hide()`
- After showing, reposition the popup each frame to track the drop

### Data flow

```
Player (CharacterBody2D)
  └─ PickupContext (Area2D, child)
       ├─ _highlighted: Drop   ← already tracked
       └─ WeaponInfoPopup (CanvasLayer, child)   ← NEW
            ├─ show_for(drop)   ← called each frame when highlighted
            │    ├─ drop_invalid? → hide()
            │    ├─ same_drop?   → reposition only
            │    ├─ different_drop? → crossfade
            │    └─ was_hidden? → animate in
            └─ hide()           ← called each frame when not highlighted
```

## Animation specification

All tweens use `Tween.TWEEN_PAUSE_PROCESS` so popup works correctly if game is paused via another source.

### Show sequence

Triggers when popup was hidden or showing a different drop.

| Step | Property | Duration | Easing | Notes |
|---|---|---|---|---|
| 1 | `position.y` slides up from `+12px` below target | 0.35s | `TRANS_BACK` / `EASE_OUT` | Overshoot for "lands and settles" |
| 2 | `modulate.a` fades 0 → 1 | 0.22s | Linear | Quick solid appearance |
| 3 | `scale` goes 0.9 → 1.08 → 1.0 | 0.35s | `TRANS_ELASTIC` / `EASE_OUT` | Elastic bounce settle |

Steps 1-3 run in parallel. `visible = true` set at frame 0.

### Hide sequence

Triggers when player moves out of range of all drops.

| Step | Property | Duration | Easing | Notes |
|---|---|---|---|---|
| 1 | `modulate.a` fades 1 → 0 | 0.15s | Linear | Quick fade |
| 2 | `position.y` drops +8px | 0.20s | `TRANS_CUBIC` / `EASE_IN` | Gravity-like fall |

Steps 1-2 run in parallel. `visible = false` set on completion.

### Crossfade (switch between drops)

1. Fade out current content: `modulate.a → 0`, duration 0.10s
2. On fade-out complete: populate new data, reposition
3. Play full show sequence

### Per-frame position tracking

While visible, each frame the `_card_root` position is updated:
```gdscript
var screen_pos := get_viewport().get_camera_2d().get_canvas_transform() * drop.global_position
screen_pos.y -= 24  # offset above drop
_card_root.position = screen_pos
```

If drop is no longer valid (freed), trigger hide immediately.

## Content layout

```
┌──────────────────────────┐
│  Flame Lash              │  ← name (bold, accent color)
│──────────────────────────│
│  Damage: 15              │  ← stat row
│  Cooldown: 1.2s          │  ← stat row
│  [ 🔥 ] [ ❄️ ] [   ]     │  ← modifier icons (up to 3 slots)
└──────────────────────────┘
```

Matches the existing card.gd information density. Modifier icons use the modifier's `icon_texture` if available; empty slots show a dimmed placeholder or nothing.

## Styling

Uses `UiTheme` constants for colors:
- Panel background: `UiTheme.PANEL_BG`
- Panel border: `UiTheme.PANEL_BORDER`
- Name label: `UiTheme.ACCENT` (orange emphasis)
- Stat labels: white
- Font: DawnLike/GUI/SDS_8x8.ttf (pixel font, same as rest of UI)

## Edge cases

| Scenario | Handling |
|---|---|
| Drop freed while popup visible | `is_instance_valid` check in per-frame update; immediate hide |
| Player walks between two drops | Crossfade: fade out (0.10s), reposition, animate in |
| Drop still bouncing (RigidBody2D settling) | Per-frame position tracking follows it naturally |
| Game paused by another modal (WeaponPopup, pause menu) | Popup tweens use `TWEEN_PAUSE_PROCESS`; popup also hides when game is paused |
| Popup would appear off-screen | Clamp `_card_root.position` to viewport rect with margin |
| Player re-hovers same drop after brief walkaway | Show animation re-plays from hidden state |
| Weapon has no modifiers | `_modifier_container` hidden |
| Weapon has no icon_texture | Popup works fine — icon is not shown in popup (card shape, not icon-based) |

## Testing & success criteria

Manual checklist:

- [ ] Standing near a weapon drop shows the popup with name, damage, cooldown, and modifiers.
- [ ] Popup appears above the drop (not overlapping the sprite).
- [ ] Show animation: slides up, fades in, bounces elastically.
- [ ] Walking away hides the popup with a short fade + drop animation.
- [ ] Walking from one drop to another crossfades smoothly.
- [ ] Popup tracks a moving drop (RigidBody2D settling).
- [ ] Popup disappears if the drop is picked up or despawns.
- [ ] Pressing E still works normally (opens WeaponPopup for pickup).
- [ ] Modifier drops do NOT show the popup.
- [ ] Popup hides when game is paused.
- [ ] Popup does not clip off-screen edges.
- [ ] No tween errors on spammy show/hide (rapid movement between drops).

## Risks

- **PickupContext coupling** — adding popup logic to PickupContext increases its responsibility. Mitigation: popup is self-contained (`show_for`/`hide`), PickupContext only forwards the highlighted drop reference.
- **Performance** — per-frame canvas transform calculation and tween reconciliation. Negligible (single Control, single Tween).
- **Z-ordering with other UI** — layer 15 sits below WeaponPopup (17) and ChestUI (16), above game world. Verified no conflicts.
