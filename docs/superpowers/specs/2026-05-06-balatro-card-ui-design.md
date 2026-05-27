# Balatro-Style Card UI Design

**Date**: 2026-05-06
**Topic**: Give option buttons (weapon/modifier cards) a Balatro-style card effect

---

## Goal

Refactor all card-based UI components (WeaponPopup, ChestUI, ShopUI) to use a shared `Card.tscn` scene that renders content into a SubViewport with a `fake_3D` perspective-tilt shader, elastic hover animations, and offset drop shadow — matching Balatro's card feel.

---

## Card Scene Hierarchy

```
Card (Control root)
├── Shadow (ColorRect, StyleBoxFlat with bg=black 12% alpha, rounded corners,
│           offset (+6,+6) relative to card)
├── SubViewportContainer (anchors full, stretch=true, material=fake_3D shader)
│   └── SubViewport (transparent_bg=true, update_mode=ONCE / DISABLED)
│       └── CardPanel (PanelContainer, uses existing UiTheme panel style)
│           └── VBoxContainer
│               ├── Icon (TextureRect, stretch_keep_aspect, adjustable size)
│               ├── NameLabel (gold accent font_color)
│               ├── StatsLabel(s) (cooldown, damage, description)
│               └── ModifierSlots (HBox of small 32x32 modifier icons)
└── HoverDetector (Area2D + CollisionShape2D, tracks mouse for tilt)
```

### Exports

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `card_size` | Vector2 | (160, 220) | Total card dimensions |
| `icon_size` | Vector2 | (96, 96) | Weapon/modifier icon size |
| `mod_icon_size` | Vector2 | (32, 32) | Modifier slot icon size |
| `tilt_max` | float | 12.0 | Max tilt angle in degrees |
| `hover_scale` | float | 1.12 | Hover scale target |
| `is_selectable` | bool | true | Whether card shows selection feedback |

### Public Methods

| Method | Description |
|--------|-------------|
| `populate(icon, name, stats, modifiers)` | Inject content into the card |
| `set_selected(selected: bool)` | Show/hide golden selection border |
| `set_highlighted(on: bool)` | Enable/disable glow (for transfer/special modes) |
| `play_click_feedback()` | Brief scale-down tween on click |

### Hover/Select Signals (exposed to caller for convenience)

| Signal | Description |
|--------|-------------|
| `card_clicked` | Emitted when card is pressed |
| `card_hovered(card)` | Alternative to connecting gui_input per instance |

---

## Animations

### Hover Enter
- Scale: 1.0 → 1.15 → settle 1.12 (0.5s, `EASE_OUT` + `TRANS_ELASTIC`)
- Shadow offset: (6,6) → (10,10) (0.4s, `EASE_OUT`)
- Tilt tracking enabled (read mouse pos in `_process`)

### Hover Exit
- Scale: back to 1.0 (0.55s, `EASE_OUT` + `TRANS_ELASTIC`)
- Shadow offset: back to (6,6) (0.4s)
- Tilt angles: tween to 0.0 (0.3s, `EASE_IN_OUT`)
- Tilt tracking disabled

### Mouse Move (Tilt)
- Map local mouse position to [0, 1] across card bounds
- `x_rot = lerp(-tilt_max, tilt_max, mouse_y_ratio)`
- `y_rot = lerp(-tilt_max, tilt_max, mouse_x_ratio)`
- Set `fake_3D` shader params each frame when hovered

### Click Feedback
- Scale to 0.97 then back to hover scale (0.15s, `EASE_IN_OUT`)

### Selection (caller-managed)
- Golden border via stylebox override on CardPanel
- Existing pulsing modulate animation stays in caller code

---

## Shaders

### `fake_3D.gdshader` (new)

Copied from the Balatro reference project (`shaders/shared/fake_3D.gdshader`), adjusted:
- Default `rect_size` = card dimensions from export
- Default `fov` = 90.0
- `x_rot` and `y_rot` driven by mouse position
- Applied as material on `SubViewportContainer`

### Card Hover Glow (existing, retained)

`card_hover_glow.gdshader` — kept for compatibility, but may become redundant with the new tilt/shadow. Not removed (still used by some UI elements).

---

## Theme Update (`src/ui/ui_theme.gd`)

Add `_make_card_shadow_stylebox()`:
- `StyleBoxFlat` with `bg_color = Color(0, 0, 0, 0.12)`
- `corner_radius` = 8 (matches panel style)
- No border, no content margin

Expose via `UiTheme.get_card_shadow_stylebox()`.

---

## Integration Plan

Each existing UI replaces its inline `_create_card()` body with scene instantiation:

```gdscript
var card = preload("res://scenes/ui/card.tscn").instantiate()
card.populate(icon, name, stats, modifiers)
card.card_clicked.connect(func(): _on_card_pressed(card))
container.add_child(card)
```

### Files Modified

| File | Change |
|------|--------|
| `src/ui/weapon_popup.gd` | Replace `_create_card()`, `_add_pickup_header()`, transfer/remove card creation with `Card` scene |
| `src/ui/chest_ui.gd` | Replace `_create_weapon_card()` with `Card` scene |
| `src/economy/shop_ui.gd` | Replace `_create_offer_card()`, `_create_remove_card()` with `Card` scene |
| `src/ui/ui_theme.gd` | Add shadow stylebox |
| `src/ui/weapon_button.gd` | Optional: wrap tooltip icons in card style (low priority) |

### Files Added

| File | Purpose |
|------|---------|
| `scenes/ui/card.tscn` | Reusable card scene |
| `src/ui/card.gd` | Card controller script (populate, animations, tilt) |
| `shaders/ui/fake_3d.gdshader` | 3D perspective tilt shader |

### SubViewport Update Strategy

1. On `populate()`: build children inside SubViewport, set `render_target_update_mode = UPDATE_ONCE`
2. After one frame (via `await get_tree().process_frame` or `_ready`): set back to `UPDATE_DISABLED`
3. Card content is static — no need for continuous viewport rendering
4. The `fake_3D` shader on the `SubViewportContainer` operates on the captured texture

---

## What's NOT Included

- **Dissolve/burn destruction** — explicitly excluded
- **Drag physics** — cards are selection buttons, not draggable objects
- **VHS post-processing** — thematically mismatched with dark fantasy pixel aesthetic

---

## Non-Goals

- No changes to Weapon/Modifier/Inventory data classes
- No changes to WeaponDelivery or pickup flow
- No changes to the overlay background or layout structure of any UI screen
- No new font or asset imports (uses existing pixel font and textures)
