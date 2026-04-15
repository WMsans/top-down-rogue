# Interactable & Drop System Design

## Overview

Implement three systems: an interactable framework, a pushable drop system with topdown physics, and a weapon drop that grants weapons on pickup.

## Architecture

**Approach A: Component Composition** — selected.

- `Interactable` is a `Node` component attached as a child to any interactable scene
- `InteractionController` on the player handles detection and input
- `Drop` is a `RigidBody2D` scene with `Interactable` child
- `WeaponDrop` extends `Drop`

This follows the project's existing composition-over-inheritance pattern (e.g., `HealthComponent`, `WeaponManager` as sibling nodes on Player).

---

## 1. Interactable System

### Interactable Node (`src/interactables/interactable.gd`, `class_name Interactable`)

A `Node` component added as a child to any scene that can be interacted with.

**Properties:**
- `interaction_name: String` — display name for the interactable (for future UI hints)
- `outline_material: ShaderMaterial` — reference to the shader material on the parent sprite

**Signals:**
- `highlighted` — emitted when player enters interaction range and this is the closest
- `unhighlighted` — emitted when player leaves range or another interactable becomes closest

**Methods:**
- `interact(player: PlayerController)` — virtual, override in subclasses. Called when player presses interact key near this interactable.
- `set_highlighted(enabled: bool)` — toggles outline shader on/off

### InteractionController (`src/player/interaction_controller.gd`, `class_name InteractionController`)

A `Node` child of Player with an `Area2D` + `CollisionShape2D` detection radius (~32px).

**Behavior:**
- Tracks all `Interactable` nodes currently in range via `body_entered`/`body_exited` signals on the Area2D
- Each frame, finds the closest interactable and calls `set_highlighted(true)` on it, `set_highlighted(false)` on the previous
- On E key press (`interact` input action), calls `interact(player)` on the highlighted interactable
- If no interactable is in range, E key does nothing

### Outline Shader (`shaders/visual/outline.gdshader`)

A `canvas_item` shader that draws a white outline by sampling neighboring pixels and comparing alpha values.

**Parameters:**
- `outline_width: float` — outline thickness in pixels (default 0 = no outline, set to 1-2 when highlighted)
- `outline_color: Color` — outline color (default white)

Applied as a `ShaderMaterial` on the `Sprite2D` (or any `CanvasItem`) of the interactable object.

### InputMap

Add `interact` action mapped to `E` key in `project.godot`.

---

## 2. Drop System

### Drop (`src/drops/drop.gd`, `class_name Drop`, scene: `scenes/drop.tscn`)

A `RigidBody2D` with physics-based push & slide behavior.

**Scene structure:**
```
Drop (RigidBody2D)
├── Sprite2D              — uses item icon texture
├── CollisionShape2D      — circular shape (~8px radius)
└── Interactable          — child node for interaction
```

**Properties:**
- `mass` — default 1.0 (light, easy to push)
- `linear_damp` — provides deceleration so drops don't slide forever (e.g., 5.0)
- `max_slide_velocity: float` — cap on slide speed

**Physics behavior:**
- When any `PhysicsBody2D` (player, future enemies) collides with the drop, the `RigidBody2D` physics engine naturally applies impulse from contact
- `linear_damp` decelerates the drop over time, creating a friction-like slide
- No custom push code needed — standard physics handles it

**Collision layers:**
- Drop uses collision **layer 2** (`collision_layer = 2`)
- Drop **masks** layers 1 and 2 (`collision_mask = 3`) — collides with terrain and other drops
- Player masks layers 1 and 2 — collides with terrain and pushes drops
- Player stays on collision **layer 1**

**Methods:**
- `interact(player: PlayerController)` — calls `_pickup()` virtual method
- `_pickup(player: PlayerController)` — virtual, override in subclasses. Default implementation frees the node.
- `set_highlighted(enabled: bool)` — delegates to `Interactable` child

---

## 3. Weapon Drop

### WeaponDrop (`src/drops/weapon_drop.gd`, `class_name WeaponDrop`, extends `Drop`, scene: `scenes/weapon_drop.tscn`)

A drop that grants a weapon when picked up.

**Properties:**
- `weapon: Weapon` — the weapon this drop grants

**Sprite:** Uses `weapon.icon_texture` for the `Sprite2D` texture.

**On pickup (`_pickup`):**
1. Get the `WeaponManager` from the player
2. Call `weapon_manager.try_add_weapon(weapon)`
3. If a slot was available:
   - Drop is picked up — node freed
4. If all 3 slots are full:
   - Open the existing `WeaponPopup` UI
   - Player chooses a slot → `weapon_manager.swap_weapon(slot_index, weapon)` returns the old weapon
   - Old weapon spawns as a new `WeaponDrop` at the player's position
   - New weapon goes into the chosen slot
   - Drop is freed
   - Player cancels → nothing happens, drop stays

**Static spawn method:** `WeaponDrop.spawn(weapon: Weapon, position: Vector2) -> WeaponDrop`
1. Instantiates a `WeaponDrop`
2. Sets `weapon` property
3. Sets `Sprite2D` texture to `weapon.icon_texture`
4. Places at given position
5. Adds to the scene tree (as sibling of Player in game.tscn)
6. Returns the instance

---

## 4. WeaponManager Changes

Add to `src/weapons/weapon_manager.gd`:

- `try_add_weapon(weapon: Weapon) -> bool` — finds first empty slot, adds weapon, returns true. Returns false if all slots full.
- `swap_weapon(slot_index: int, weapon: Weapon) -> Weapon` — puts new weapon in slot, returns old weapon (or null if slot was empty).
- `has_empty_slot() -> bool` — checks if any slot is null.

---

## 5. Player Scene Changes

Add to `scenes/player.tscn`:
- `InteractionController` node as child of Player, containing:
  - `Area2D` (detection zone)
  - `CollisionShape2D` (circle, ~32px radius)

---

## 6. Game Scene Changes

Add to `scenes/game.tscn`:
- Drops are added as children of the root `Main` node (same parent as Player)

---

## File Summary

**New files:**
- `src/interactables/interactable.gd` — Interactable component
- `src/player/interaction_controller.gd` — Player interaction detection & input
- `shaders/visual/outline.gdshader` — Outline shader
- `src/drops/drop.gd` — Drop base class
- `scenes/drop.tscn` — Drop scene
- `src/drops/weapon_drop.gd` — WeaponDrop class
- `scenes/weapon_drop.tscn` — WeaponDrop scene

**Modified files:**
- `src/weapons/weapon_manager.gd` — Add try_add_weapon, swap_weapon, has_empty_slot
- `scenes/player.tscn` — Add InteractionController node
- `scenes/game.tscn` — Reference drops container
- `project.godot` — Add `interact` input action (E key)