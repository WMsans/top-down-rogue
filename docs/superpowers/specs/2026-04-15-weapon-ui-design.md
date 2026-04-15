# Weapon UI Design

## Overview

Add a weapon UI to the right side of the game screen showing the active weapon, with a hover tooltip for base stats and a full-screen popup for inspecting and rearranging all 3 weapon slots. This also includes refactoring the `Weapon` base class to standardize base stats across all weapons.

## 1. Standardized Base Stats Refactor

### Problem

Weapon subclasses hardcode their own constants with different names. `TestWeapon` has `COOLDOWN`, `GAS_RADIUS`, `GAS_DENSITY`. `MeleeWeapon` has `COOLDOWN`, `RANGE`, `ARC_ANGLE`, `PUSH_SPEED`. Neither has `damage` or `icon_texture`. Stats are inaccessible to UI without knowing each weapon's internals.

### Solution

Add standardized base properties to `Weapon` base class (`src/weapons/weapon.gd`):

```gdscript
class_name Weapon
extends RefCounted

var name: String = "Weapon"
var cooldown: float = 0.5
var damage: float = 0.0
var icon_texture: Texture2D = null

func get_base_stats() -> Dictionary:
    return { "name": name, "cooldown": cooldown, "damage": damage }
```

- **`name`** — already exists on `Weapon`, no change needed
- **`cooldown`** — promoted from subclass `const` to base class `var` with default `0.5`
- **`damage`** — new property, default `0.0`. Each weapon overrides in `_init()`
- **`icon_texture`** — new property, default `null` (falls back to a debug/placeholder texture in UI). Each weapon sets it in `_init()`
- **`get_base_stats()`** — convenience method for the UI to read stats without knowing weapon internals

Weapon-specific constants (like `GAS_RADIUS`, `ARC_ANGLE`, `RANGE`, `PUSH_SPEED`) remain as subclass `const` values — they are implementation details, not base stats shown in UI.

### Subclass Updates

**TestWeapon** (`src/weapons/test_weapon.gd`):
```
_init():
    cooldown = 0.5
    damage = 1.0
    icon_texture = load("res://textures/DawnLike/Items/Wand.png")
```

**MeleeWeapon** (`src/weapons/melee_weapon.gd`):
```
_init():
    cooldown = 0.5
    damage = 5.0
    icon_texture = load("res://textures/weapon.png")
```

(The existing `const COOLDOWN` in each subclass is removed, replaced by the inherited `var cooldown`.)

### Fallback Icon

When `icon_texture` is null, UI components fall back to a `ColorRect` (dark gray) with a white "?" `Label` centered inside it. No external placeholder image needed.

## 2. Weapon Button (HUD Element)

### New Files

- `scenes/ui/weapon_button.tscn`
- `src/ui/weapon_button.gd`

### Structure

A `CanvasLayer` at layer 5 (same as `HealthUI`).anchored to the right side of the screen, vertically centered. Contains:

- A `ColorRect` dark panel background (dark purple, matching existing UI theme)
- A `TextureButton` (48x48 px) showing the active weapon's `icon_texture`
- A `Control` tooltip panel (hidden by default)

### Hover Tooltip

On mouse enter over the `TextureButton`:
- Show a tooltip panel positioned below/beside the button
- Tooltip displays the weapon's base stats from `get_base_stats()`:
  - Name
  - Cooldown (formatted as seconds, e.g., "0.5s")
  - Damage (formatted as number, e.g., "5")

On mouse exit:
- Hide the tooltip panel

### Active Weapon Tracking

- `WeaponManager` emits a `weapon_activated(slot_index: int)` signal when Z/X/C is pressed
- `WeaponButton` listens to this signal and updates the displayed weapon icon
- Tracks `active_slot` to know which weapon to display
- If no weapon has been used yet, shows the first slotted weapon (slot 0)

### Click Behavior

Clicking the `TextureButton` opens the `WeaponPopup` scene.

## 3. Weapon Popup (Full-Screen Overlay)

### New Files

- `scenes/ui/weapon_popup.tscn`
- `src/ui/weapon_popup.gd`

### Structure

A `CanvasLayer` at layer 15 (above PauseMenu at 10, below DeathScreen at 20). Has `process_mode = PROCESS_MODE_ALWAYS` so it functions while paused.

### Opening

- Triggered by clicking the weapon button
- Pauses the game via `SceneManager.set_paused(true)`
- Shows a dark semi-transparent overlay (`ColorRect` with alpha ~0.7) covering the full screen
- On top of the overlay: centered content panel

### Layout

Centered content panel:
- Title: "WEAPONS" in SDS_8x8 pixel font, matching existing UI style
- 3 weapon card slots arranged horizontally, evenly spaced
- Each card contains:
  - Large weapon icon (~96x96 px, scaled from `icon_texture`)
  - Weapon name label
  - Cooldown value label
  - Damage value label
- If a slot is empty, the card shows an empty border with "EMPTY" text
- Dark purple background panels with pixel font, matching existing UI

### Drag-Drop Rearranging

- Weapons can be dragged from one card slot to another
- On drag start: weapon card slightly lifts (opacity/scale change)
- Target slot highlights its border when a drag hovers over it
- On drop: the two weapons swap positions in `WeaponManager.weapons` array
- Z/X/C key mapping follows slot position (slot 0 = Z, slot 1 = X, slot 2 = C)

### Closing

- Click the overlay background (outside the cards)
- Press Escape
- Either action calls `SceneManager.set_paused(false)` and hides the popup

### Visual Style

Matches existing UI:
- Dark purple backgrounds (`Color(0.102, 0.039, 0.18)`)
- SDS_8x8 pixel font
- ColorRect-based panels with consistent padding
- Button/panel borders matching existing pause menu and settings popup

## 4. Integration & Wiring

### Changes to WeaponManager (`src/weapons/weapon_manager.gd`)

- Add `signal weapon_activated(slot_index: int)` — emitted when Z/X/C activates a weapon
- Add `var active_slot: int = 0` — tracks which slot was last used
- Add `func swap_weapons(slot_a: int, slot_b: int)` — swaps two weapons in the `weapons` array
- Update `_input` / `_physics_process` to emit `weapon_activated` when a weapon slot key is pressed

### Changes to Game Scene (`scenes/game.tscn`)

Add two new scene instances to the Main node:

```
Main (Node2D)
├── ... (existing nodes)
├── HealthUI (CanvasLayer, layer 5)
├── PauseMenu (CanvasLayer, layer 10)
├── WeaponPopup (CanvasLayer, layer 15)    ← NEW
├── DeathScreen (CanvasLayer, layer 20)
└── WeaponButton (CanvasLayer, layer 5)    ← NEW
```

### Scene Wiring

- `WeaponButton` has an `@export var weapon_popup: WeaponPopup` set in the editor (drag the WeaponPopup node instance into this field)
- On button click: `weapon_popup.open(weapon_manager)` is called, which pauses the game and shows the overlay
- `WeaponPopup.open()` takes a `WeaponManager` parameter (found via `get_node("/root/Main/Player/WeaponManager")`) and stores it for the duration the popup is open
- On weapon swap: `WeaponPopup` calls `WeaponManager.swap_weapons(a, b)` and refreshes display
- On close: `WeaponPopup` calls `SceneManager.set_paused(false)` and hides itself
- `WeaponButton` connects to `WeaponManager.weapon_activated` to update the displayed icon

## File Summary

### New Files
| File | Purpose |
|------|---------|
| `scenes/ui/weapon_button.tscn` | Weapon button scene |
| `src/ui/weapon_button.gd` | Weapon button logic + tooltip |
| `scenes/ui/weapon_popup.tscn` | Weapon popup overlay scene |
| `src/ui/weapon_popup.gd` | Weapon popup logic + drag-drop |

### Modified Files
| File | Changes |
|------|---------|
| `src/weapons/weapon.gd` | Add `cooldown`, `damage`, `icon_texture` properties; add `get_base_stats()` |
| `src/weapons/test_weapon.gd` | Set base stats in `_init()`, remove `const COOLDOWN` |
| `src/weapons/melee_weapon.gd` | Set base stats in `_init()`, remove `const COOLDOWN` |
| `src/weapons/weapon_manager.gd` | Add `weapon_activated` signal, `active_slot`, `swap_weapons()` |
| `scenes/game.tscn` | Add WeaponButton and WeaponPopup nodes |