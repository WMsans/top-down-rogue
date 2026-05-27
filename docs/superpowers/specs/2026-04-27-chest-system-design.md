# Chest System Design

## Overview

Chests are world objects the player interacts with to receive a choice of 3 random weapons. The player picks one, goes through the WeaponDelivery equip flow, and the chest is consumed.

## Architecture

### Components

1. **`Chest` (`src/drops/chest.gd`)** — `Area2D` world object
   - Detected by `PickupContext` via `get_pickup_type()` / `should_auto_pickup()` interface
   - On `interact()`, generates 3 random weapons from `WeaponRegistry` (weighted by configurable tier)
   - Opens `ChestUI` popup, pauses game
   - Has closed/open sprite states with outline highlight shader
   - Destroyed after player makes a selection or declines

2. **`ChestUI` (`src/ui/chest_ui.gd`)** — `CanvasLayer` popup
   - Shows 3 weapon cards side by side
   - Player clicks a card to select that weapon
   - Selected weapon goes through `WeaponDelivery.offer()` → `WeaponPopup` for equip slot choice
   - After equip flow completes (accepted or declined), closes and destroys chest
   - Follows `UiTheme` / `UiAnimations` styling (matching ShopUI)
   - Closeable via overlay click or pause key

3. **`spawn chest` console command** — Registration in `spawn_command.gd`
   - Spawns a chest at the player's world position
   - Configurable tier parameter (default: COMMON)

### Data Flow

```
Player presses interact near Chest
  → Chest.interact(player)
    → generates 3 weapons via WeaponRegistry.get_random_weapon(tier)
    → ChestUI.open(weapons, callback)
      → player clicks a card
        → WeaponDelivery.offer(WeaponOfferSpec with chosen weapon, callback)
          → WeaponPopup shows slot selection
            → player accepts/declines
        → callback(accepted, slot)
  → Chest._on_delivery_result(accepted, slot)
    → if accepted: chest consumed
    → ChestUI closes, game unpaused
```

### Weapon Generation

- 3 weapons generated using `WeaponRegistry.get_random_weapon(tier)` 
- Default tier: `DropTable.ItemTier.COMMON` (configurable)
- Each of the 3 choices is independently rolled from the weighted pool
- Duplicate re-roll: if the same weapon script is rolled twice, re-roll for variety

### Chest Tier (Future)

The `Chest` class has a `tier` export property defaulting to `COMMON`. Higher tiers roll from rarer weapon pools. This is extensible for future level generation spawn integration.

### Visuals

- Closed state: chest sprite with outline shader (reusing the same `outline.gdshader` as drops)
- Open state: sprite swap on interact, before UI appears
- Highlight on proximity via `set_highlighted()` (same pattern as `Drop`)
- No custom textures needed initially — will use a simple colored rectangle sprite generated in code

### PickupContext Integration

`Chest` implements the same `get_pickup_type()` / `should_auto_pickup()` / `interact()` / `set_highlighted()` interface as `Drop`. `PickupContext` already handles any body that has these methods, so no changes needed there.

**Important difference from Drop**: Chest extends `Area2D` (not `RigidBody2D`) because chests don't move — they're stationary world objects.

### Scene Structure

**`scenes/chest.tscn`**:
- `Chest` (Area2D) — root, script `chest.gd`
  - `Sprite2D` — chest sprite, with `outline.gdshader` material
  - `CollisionShape2D` — rectangle shape for interaction detection

**`scenes/ui/chest_ui.tscn`**:
- `ChestUI` (CanvasLayer) — root, script `chest_ui.gd`
  - `Overlay` (ColorRect) — semi-transparent backdrop, click to close
  - `ShopPanel` (PanelContainer) — main container with header + card row
    - `HeaderBar` (PanelContainer) — "Choose a Weapon" title
    - `CardContainer` (HBoxContainer) — holds 3 weapon cards
  - Each card: `PanelContainer` → `VBoxContainer` → icon + name + stats (damage, cooldown)

### Files to Create

- `src/drops/chest.gd` — Chest world object logic
- `scenes/chest.tscn` — Chest scene
- `src/ui/chest_ui.gd` — ChestUI popup logic
- `scenes/ui/chest_ui.tscn` — ChestUI scene

### Files to Modify

- `src/console/commands/spawn_command.gd` — Add `spawn chest` command

## Design Decisions

- **Area2D vs RigidBody2D**: Chest is stationary, so `Area2D` is correct (unlike `Drop` which uses `RigidBody2D` for scatter physics)
- **Reuse WeaponDelivery**: The equip flow is identical to weapon drops, so we reuse `WeaponDelivery` entirely
- **Reuse outline shader**: Same visual language as drops for consistency
- **No gold/modifier from chest**: Per the design doc, chests specifically drop weapons. Modifiers come from shops.