# Weapon Icon Hover Tooltip — Design

**Date:** 2026-07-04

## Problem

Hovering over a modifier icon on a weapon card (in the weapon popup) shows its name + description in a tooltip. But hovering over the weapon's own sprite/icon shows nothing. The weapon has a `description` field loaded from CSV — it should be surfaced the same way.

## Goals

- Hover over weapon icon → tooltip with name (gold) + description (secondary text)
- Works on any Card showing a weapon, anywhere (weapon popup, chest UI, pickup screens)
- Self-contained in the Card class — consumers just call one line to opt in

## Non-goals

- Modifier tooltip refactoring (stays as-is in weapon_popup.gd)
- World-space weapon info popup changes (the floating card near drops already works differently)

## Architecture

### Card.gd — new tooltip capability

The Card already detects hover over its entire bounding box in `_process`. We add a finer-grained check for the icon sub-region.

**New members:**

```
signal icon_mouse_entered
signal icon_mouse_exited

var _tooltip_title: String = ""
var _tooltip_description: String = ""
var _weapon_tooltip: PanelContainer = null
var _icon_hovered: bool = false
```

**New public method:**

```gdscript
func set_tooltip_text(title: String, description: String) -> void
```

Stores the title/description. If both are empty, the tooltip is disabled for this card.

**Tooltip lifecycle:**

- In `_process`, after the card-level hover check, compute the icon bounding rect. The SubViewport maps 1:1 to the Card, so `_icon.global_position` + `_icon.size` gives card-local coordinates.
- If mouse is within the icon rect, `_icon.visible == true`, and `_tooltip_title != ""`, create/show the tooltip panel.
- If mouse exits or `_tooltip_title` is empty, destroy the tooltip.

**Tooltip panel:**

- `PanelContainer` as top-level (`MOUSE_FILTER_IGNORE`, z-index 100)
- VBox with name label (gold, center-aligned)
- If description is non-empty: HSeparator + desc label (secondary color, 14pt, 180px max width, word-wrap smart)
- Positioned above the Card's top edge, horizontally centered, clamped to viewport edges (mirrors the existing `_position_tooltip_near` logic)

### Consumers

**weapon_popup.gd** — in `_create_card`, after `set_rarity`:

```gdscript
card.set_tooltip_text(weapon.name, weapon.description)
```

**chest_ui.gd** — in card creation path, after populate/set_rarity:

```gdscript
card.set_tooltip_text(weapon.name, weapon.description)
```

## Data Flow

```
CSV → weapon_registry.gd → Weapon.description
     → Card.set_tooltip_text()
     → Card._process() detects icon hover
     → Card creates/destroys tooltip PanelContainer
```

## Empty / edge cases

- Empty weapon slot: `create_card` receives `null` weapon, never calls `set_tooltip_text`. No tooltip.
- Weapon with no description: `set_tooltip_text(name, "")` — shows name only, no separator/desc.
- Card used for modifier-only display (transfer cards, remove-modifier cards): `set_tooltip_text` not called, no tooltip.

## Testing

- Hover weapon icon in inventory popup → tooltip shows name + description
- Hover weapon icon in chest screen → same behavior
- Move mouse off icon → tooltip disappears
- Empty weapon slot → no tooltip
- Weapon with `description == ""` → shows name only
