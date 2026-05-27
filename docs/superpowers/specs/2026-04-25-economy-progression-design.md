# Economy & Progression Design

## Overview

Phase 3 implementation: Currency system, enemy drop tables, modifier inventory, shop UI, and a dummy enemy to test the loot loop.

---

## 1. Enemy Base & Dummy Enemy

### Enemy Base (`src/enemies/enemy.gd`)

Node2D with:
- `health: int`, `max_health: int`
- `drop_table: DropTable` resource
- `hit(damage, source)` — reduces health, calls `_on_hit()`, dies at 0
- `die()` — resolves drop_table, spawns drops as children of root, queues free
- `_on_hit()` / `_on_death()` — virtual hooks

### Dummy Enemy (`src/enemies/dummy_enemy.gd`)

Extends `Enemy`:
- Green circle drawn via `draw_circle()` (no external asset)
- Simple `_process`: moves toward player at slow speed (20 px/s)
- `_on_hit()`: modulate flash white 0.1s
- `_on_death()`: no extra behavior

### Scenes
- `scenes/enemy.tscn`: Node2D + CollisionShape2D (CircleShape2D) + Sprite2D
- `scenes/dummy_enemy.tscn`: inherits enemy.tscn, script = dummy_enemy.gd

---

## 2. Drop Table

### `src/enemies/drop_table.gd` (Resource)

```gdscript
class DropEntry:
    var scene: PackedScene   # e.g. weapon_drop, gold_drop
    var weight: float
    var min_count: int = 1
    var max_count: int = 1
    # For gold_drop specifically: sets drop.amount
    var gold_per_drop: int = 0

func resolve(position: Vector2, parent: Node) -> Array[Node]:
    # roll weighted random for each entry
    # instantiate scene * count
    # for gold drops: set drop.amount = gold_per_drop
    # position scattered around position, add_child to parent
```

The drop table is resolved at death time. `resolve()` receives the death position and world parent node.

---

## 3. Currency System

### Wallet Component (`src/player/wallet_component.gd`)

Node on player:
- `gold: int = 0`
- `add_gold(amount: int)` — adds, emits `gold_changed`
- `spend_gold(amount: int) -> bool` — checks sufficient, deducts, emits signal, returns true; returns false if insufficient
- `gold_changed(new_amount: int)` signal

### Gold Drop (`src/drops/gold_drop.gd`)

Extends `Drop`:
- Exposes `amount: int` (how much gold it gives)
- `_pickup(player)`: finds `WalletComponent` on player, calls `add_gold(amount)`, queues free

### Scene
- `scenes/gold_drop.tscn`: inherits drop.tscn, gold coin sprite (reuse textures/Assets/coin.png or draw procedural)

---

## 4. Currency HUD

### `src/ui/currency_hud.gd` (CanvasLayer)

- Added to `scenes/game.tscn`, anchored top-right
- Gold coin icon + Label showing gold amount
- Connects to `WalletComponent.gold_changed` on player ready
- Uses `UiTheme` colors and font

---

## 5. Modifier Inventory

### `src/player/modifier_inventory.gd` (Node)

On player:
- `modifiers: Array[Modifier]` — unequipped modifier instances
- `add_modifier(m: Modifier)` — appends, emits `modifier_added`
- `remove_modifier(m: Modifier) -> bool` — removes, emits `modifier_removed`, returns success
- `get_modifiers() -> Array[Modifier]` — returns copy
- Signals: `modifier_added(modifier)`, `modifier_removed(modifier)`

Used by:
- Shop buy → `add_modifier()`
- Shop remove → `remove_modifier()` (destroy for gold cost)
- WeaponPopup modifier equip → `remove_modifier()` then `weapon.add_modifier()`

---

## 6. Shop UI

### `src/economy/shop_offer.gd` (Resource)

```gdscript
class_name ShopOffer
extends Resource

var modifier: Modifier
var price: int
```

### `src/economy/shop_ui.gd` (CanvasLayer)

Pattern follows `weapon_popup.gd`:

- `open(offerings: Array[ShopOffer])` — called by future shop Interactable
- **Buy tab**: grid of modifier cards. Each shows modifier name, description, icon, price. Click = buy → validate gold → spend gold → add to inventory → refresh
- **Remove section**: below the buy grid, a button "Remove Modifier (X gold)". Click = opens a picker of owned modifiers from `ModifierInventory`. Selecting one destroys it and deducts gold. Cost increases per removal (50/75/100/125...).
- Close button or E key to close
- Pauses game via `SceneManager.set_paused(true)`
- Uses `UiTheme` for consistent styling, `UiAnimations` for card effects

---

## 7. Integration Points

### `scenes/game.tscn` changes
- Add `CurrencyHUD` as child of UI CanvasLayer

### `scenes/player.tscn` changes
- Add `WalletComponent` node
- Add `ModifierInventory` node

### `src/ui/weapon_popup.gd` changes
- On modifier equip: pull from `ModifierInventory.remove_modifier()` instead of only from other weapon slots

### `src/input/input_handler.gd` changes
- Add dev key (e.g. G) to spawn gold drop at mouse position
- Add dev key (e.g. H) to spawn dummy enemy at mouse position
- Add dev key (e.g. U) to open shop UI with test offerings

---

## 8. Testing

- Kill dummy enemy → verify gold drop + weapon drop appear
- Pick up gold drop → verify HUD updates
- Dev-open shop → verify buy adds to inventory, sell removes, gold updates
- Equip modifier from inventory via weapon_popup → verify it leaves inventory

---

## 9. File Manifest

```
NEW:
  src/enemies/enemy.gd
  src/enemies/dummy_enemy.gd
  src/enemies/drop_table.gd
  src/economy/shop_offer.gd
  src/economy/shop_ui.gd
  src/player/wallet_component.gd
  src/player/modifier_inventory.gd
  src/drops/gold_drop.gd
  src/ui/currency_hud.gd
  scenes/enemy.tscn
  scenes/dummy_enemy.tscn
  scenes/gold_drop.tscn

MODIFIED:
  scenes/game.tscn
  scenes/player.tscn
  src/ui/weapon_popup.gd
  src/input/input_handler.gd
```
