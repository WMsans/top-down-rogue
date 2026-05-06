# Balatro-Style Card Effects — Design Spec

**Date:** 2026-05-05
**Project:** Top-Down Rogue (Godot 4.6)

## Overview

Apply Balatro-style card effects to all selection cards in the game: 3D perspective tilt following the mouse cursor, a holographic/metallic frame that shifts its reflection with rotation, and springy bounce animations on hover/leave.

**Goal:** Make cards feel alive and premium, matching the juice-rich aesthetic of the rest of the game.

---

## Scope

All card-based selection UI:

- **WeaponPopup cards** — weapon swap, pickup, modifier equip/remove, transfer cards
- **ChestUI cards** — weapon selection from chests
- **ShopUI cards** — modifier offers in the shop

One universal holographic style across all card types.

---

## Architecture

### New Files

| File | Purpose |
|------|---------|
| `shaders/ui/card_holo.gdshader` | Custom `canvas_item` shader: vertex 3D tilt + fragment holographic border |
| `src/ui/card_effects.gd` | Static utility (`class_name CardEffects`) — wires shader, mouse tracking, and hover tweens onto any card |

### Modified Files

| File | Change |
|------|--------|
| `src/ui/weapon_popup.gd` | `_create_card()`, `_create_transfer_card()`, `_create_remove_modifier_card()` — call `CardEffects.setup_card()` instead of manual material/signal setup |
| `src/ui/chest_ui.gd` | `_create_weapon_card()` — same replacement |
| `src/ui/shop_ui.gd` | `_create_offer_card()`, `_create_remove_card()` — same replacement |

### Files NOT Modified

- `src/ui/ui_animations.gd` — CardEffects is additive, existing tween utilities remain for non-card UI
- `src/ui/ui_theme.gd` — unchanged

---

## Component Design

### 1. Shader: `card_holo.gdshader`

#### Uniforms

| Uniform | Type | Default | Purpose |
|---------|------|---------|---------|
| `tilt_x` | float | 0.0 | Rotation around X axis (-0.15..0.15), driven by cursor Y offset |
| `tilt_y` | float | 0.0 | Rotation around Y axis (-0.15..0.15), driven by cursor X offset |
| `holo_time` | float | 0.0 | Scrolling time for rainbow sweep, updated each frame |
| `holo_intensity` | float | 0.0 | 0.0–1.0, ramps up on hover for springy pop feel |
| `border_width` | float | 0.06 | Width of the holographic border region in UV space |

#### Vertex Shader

3D perspective tilt on card vertices:

1. Translate vertex to card center (0.5, 0.5 in UV coordinates)
2. Apply rotation matrix: `R_x(tilt_x) * R_y(tilt_y)`
3. Perspective projection: `z' = rotated.z + perspective_distance` (perspective_distance = 2.0)
4. Project back: `screen_x = rotated.x * perspective_distance / z'`
5. Translate back to local origin

#### Fragment Shader

1. **Distance field** — signed distance from UV to the nearest edge, smoothstep to produce a border mask
2. **Holographic color** — sample a 1D rainbow gradient at position `(uv.x * cos(tilt_angle) + uv.y * sin(tilt_angle) + holo_time)`, multiply by border mask
3. **Metallic sheen** — compute specular highlight direction from tilt angles, add a bright streak along the border edge
4. **Inner dim** — darken card center slightly (tinted by holo_intensity) so the border pops

The effect is driven by tilt angles: as the card tilts, the reflection shifts, creating the illusion of a physical holographic surface.

### 2. Utility: `card_effects.gd`

#### API

```gdscript
class_name CardEffects

static func setup_card(card: Control, tilt_strength := 0.08, hover_scale := 1.05) -> void
```

#### Behavior

**One-time setup (called once per card):**
1. Create `ShaderMaterial` with `card_holo.gdshader`, set initial uniforms
2. Assign material to card
3. Store card reference + config in a static dictionary
4. Connect `mouse_entered`, `mouse_exited`, `tree_exiting` signals

**Per-frame (`_process`):**
- Read `card.get_local_mouse_position()`
- Normalize to center-relative (-1..1):
  ```
  delta = (mouse_pos - card.size / 2.0) / (card.size / 2.0)
  ```
- Set shader uniforms:
  - `tilt_x = delta.y * tilt_strength`
  - `tilt_y = -delta.x * tilt_strength`
  - `holo_time = fmod(Time.get_ticks_msec() / 1000.0, 1.0)`

**Hover enter (mouse_entered):**
```
t=0.00s: scale → hover_scale (1.05),  rotation → 2°,   holo_intensity → 1.0   (TRANS_BACK, EASE_OUT, 0.15s)
t=0.15s: scale → 1.03,                 rotation → 0°                            (TRANS_BACK, EASE_IN_OUT, 0.12s)
```
Springy pop: overshoots then settles at a slightly elevated scale.

**Hover leave (mouse_exited):**
```
t=0.00s: scale → 1.0,  rotation → 0°,  holo_intensity → 0.0                    (TRANS_CIRC, EASE_OUT, 0.2s)
```
Smooth settle back to rest.

**Cleanup (tree_exiting):**
- Remove card from tracking dictionary
- Kill any active tweens for this card

All tweens use `TWEEN_PAUSE_PROCESS` to match existing animation conventions (UI runs during game pause).

---

## Integration Details

### `weapon_popup.gd` Changes

In `_create_card()` (line ~211):
- **Remove:** `glow_mat` creation, `card.material = glow_mat` assignment, `card.mouse_entered.connect(...)`, `card.mouse_exited.connect(...)`
- **Add:** `CardEffects.setup_card(card)` at end of function
- **Keep:** `gui_input` connection and `_on_card_input()` — click handling unchanged

Same pattern for `_create_transfer_card()` and `_create_remove_modifier_card()`.

### `chest_ui.gd` Changes

In `_create_weapon_card()` (line ~136):
- **Remove:** glow material creation, hover signal connections
- **Add:** `CardEffects.setup_card(card)` at end

Skip button and grid layout unchanged.

### `shop_ui.gd` Changes

In `_create_offer_card()` (line ~263):
- **Remove:** hover signal connections and glow material
- **Add:** `CardEffects.setup_card(card)` at end
- **Keep:** jitter-on-unaffordable logic, `sold` dim effect — these are separate concerns

Same for `_create_remove_card()`.

---

## Error Handling

- If `card_holo.gdshader` fails to load, `CardEffects.setup_card()` logs an error and returns early — card renders without effects but game continues
- Mouse tracking gracefully handles cards at screen edges (normalized delta clamped implicitly by card bounds)
- Active tweens are killed on card removal to prevent dangling tween errors

---

## Testing

- Manual verification: hover over cards in WeaponPopup, ChestUI, ShopUI — observe 3D tilt, holographic border shift, springy pop
- Edge cases: rapid mouse movement across multiple cards, pause menu interaction (tweens should work during pause), cards near screen edges
- Regression: click behavior unchanged (weapon swap, modifier equip, chest selection, shop purchase all work as before)
