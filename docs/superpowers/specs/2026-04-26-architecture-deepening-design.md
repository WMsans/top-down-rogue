# Architecture Deepening — Top-Down Rogue

**Date**: 2026-04-26
**Status**: Approved

## Overview

Six architecture deepening refactors to increase depth (leverage at the interface) and locality (concentrated responsibility) across the codebase. Each candidate replaces shallow modules and scattered coupling with deep modules behind well-defined seams.

## Execution Order

Steps within tiers can run in parallel. Dependencies listed explicitly.

```
Tier A (parallel-safe):
  1. HitReaction         (no dependencies)
  3. TerrainSurface       (no dependencies on 1-2)

Tier B (depends on Tier A):
  4. TerrainPhysical      (needs TerrainSurface seam from step 3)

Tier C (depends on Tier B for terrain queries):
  5. PlayerInventory      (needs TerrainPhysical for lava damage)

Tier D (depends on steps 2 + 5):
  2. PickupContext        (Pickupable interface on drops, detection only — drops keep existing pickup logic)
  6. WeaponDelivery       (needs Pickupable drops from step 2, PlayerInventory from step 5)
      PickupContext dispatches gold→PlayerInventory, weapon/mod→WeaponDelivery
```

**Intermediate states**: After step 2, drops implement Pickupable but keep their existing `_pickup()` logic (direct WeaponPopup calls). After step 5, gold drops use PlayerInventory. After step 6, weapon/modifier drops use WeaponDelivery, and their `_pickup()` logic simplifies to payload-only.

---

## 1. HitReaction — Consolidated Juice Module

### Problem

Enemy's `on_hit_impact()` in `src/enemies/enemy.gd` calls 5 autoloads directly:
- `HitStopManager`
- `ScreenShakeManager`
- `HitSparkManager`
- `DamageNumberManager`
- `ChromaticFlashManager`

Each is a shallow module (small implementation, complex per-effect interface). Callers must know all 5 exist, their parameter contracts, and when to invoke each. No seam exists to swap juice for a no-op adapter during tests.

**Deletion test**: Delete any one juice manager, and Enemy must change. Delete the concept of "juice" entirely, and complexity reappears across Enemy plus future hit sources.

### Solution

Create a **HitReaction** autoload. Merge the 5 juice manager implementations as internal adapters behind a single interface.

### Interface

```gdscript
# HitSpec — data-driven descriptor of a hit event
class_name HitSpec extends Resource
var position: Vector2
var direction: Vector2
var damage: float
var is_kill: bool
var source_color: Color
var source_radius: float  # size of source for spark spread
```

```gdscript
# HitReaction — autoload, single external seam
extends Node

func play(spec: HitSpec) -> void
```

### Internal Adapters (5 adapters, private to HitReaction)

| Adapter | Reads from HitSpec | Effect |
|---------|-------------------|--------|
| HitSparkAdapter | position, direction, source_color | ColorRect sparks opposite direction |
| DamageNumberAdapter | position, damage | Floating damage label |
| ScreenShakeAdapter | damage, is_kill, direction | Camera shake (kill gets bonus) |
| ChromaticFlashAdapter | damage, is_kill | Chromatic aberration strength |
| HitStopAdapter | damage, is_kill | Time scale freeze |

### What Changes

| File | Change |
|------|--------|
| `src/core/juice/hit_spark_manager.gd` | Moves into HitReaction as internal adapter |
| `src/core/juice/damage_number_manager.gd` | Moves into HitReaction as internal adapter |
| `src/core/juice/screen_shake_manager.gd` | Moves into HitReaction as internal adapter |
| `src/core/juice/chromatic_flash_manager.gd` | Moves into HitReaction as internal adapter |
| `src/core/juice/hit_stop_manager.gd` | Moves into HitReaction as internal adapter |
| `src/enemies/enemy.gd` | `on_hit_impact()` → build HitSpec, call `HitReaction.play(spec)` |
| `project.godot` | Remove 5 autoloads, add 1 HitReaction autoload |

### Benefits

- **Locality**: All hit feedback lives in one module. Add a new effect (screen flash white, audio cue) in one place.
- **Leverage**: Any future hit source (trap, projectile, hazard) gets full juice from one call.
- **Tests**: Enemy test replaces all 5 managers with one no-op HitReaction. HitReaction tested independently via HitSpec inputs.
- **Interface depth**: Interface is 1 method + 1 resource. Implementation is 5 effect systems.

---

## 2. PickupContext + Pickupable — Unified Drop System

### Problem

Pickup flow is split across 5 files with inconsistent patterns:
- `InteractionController` handles detection/highlighting
- `Interactable` is a shallow pass-through (`interact()` delegates to parent)
- `GoldDrop` is an Area2D (not RigidBody2D like other drops), has its own auto-pickup physics
- `WeaponDrop` and `ModifierDrop` extend Drop/RigidBody2D but duplicate pickup orchestration

**Deletion test**: Delete Interactable, its 33 lines of delegation appear in InteractionController. Delete GoldDrop's auto-pickup physics, and you'd reimplement it in any new auto-pickup drop.

### Solution

Create **PickupContext** (player child node) that owns detection and dispatch. Define a **Pickupable** interface that drops implement.

### Interface

```gdscript
# Pickupable — contract that drop nodes implement
enum PickupType { GOLD, WEAPON, MODIFIER }

func get_pickup_type() -> PickupType    # abstract
func get_pickup_payload() -> Variant    # abstract (int for gold, Weapon for weapon drop, Modifier for mod drop)
func should_auto_pickup() -> bool       # gold returns true, weapons/modifiers return false
```

```gdscript
# PickupContext — player child node
extends Node

var _detection_area: Area2D
var _highlighted: Node2D

func _ready() -> void
func _physics_process(_delta: float) -> void
```

### What Changes

| File | Change |
|------|--------|
| `src/player/interaction_controller.gd` | **Deleted** — merged into PickupContext |
| `src/interactables/interactable.gd` | **Deleted** — drops implement Pickupable directly |
| `src/drops/drop.gd` | Implements Pickupable for weapon/modifier drops (base class) |
| `src/drops/gold_drop.gd` | Implements Pickupable, keeps auto-pickup physics and existing gold-add logic |
| `src/drops/weapon_drop.gd` | Adds Pickupable, keeps existing `_pickup()` logic (refactored to WeaponDelivery in step 6) |
| `src/drops/modifier_drop.gd` | Adds Pickupable, keeps existing `_pickup()` logic (refactored to WeaponDelivery in step 6) |

### Benefits

- **Locality**: All pickup detection, highlighting, and input dispatch lives in PickupContext. Adding a new drop type requires only implementing Pickupable.
- **Leverage**: One Pickupable interface for all drop types. Drops don't know about UI or player internals.
- **Tests**: PickupContext testable with mock Pickupable objects. Individual drops testable for correct payload generation.

---

## 3. TerrainSurface — WorldManager Seam

### Problem

Nearly every gameplay module accesses WorldManager via fragile scene-tree traversal:
- Weapons: `user.get_world_manager()` → `get_parent().get_node("WorldManager")`
- Debug overlays: `get_parent().get_parent().get_node("WorldManager")`
- Player: `get_parent().get_node("WorldManager")`

WorldManager is a God Node — everything routes through it but it adds no depth (delegates to sub-managers). Changing the scene-tree position of WorldManager breaks every caller.

**Deletion test**: Delete WorldManager, and every terrain-writing caller must learn about chunks, compute shaders, and texture RIDs.

### Solution

Create a **TerrainSurface** autoload. WorldManager registers as its adapter on `_ready()`. Callers reference TerrainSurface, not WorldManager.

### Interface

```gdscript
# TerrainSurface — autoload, seam for terrain modification
extends Node

var _adapter: TerrainSurfaceAdapter

func register_adapter(adapter: TerrainSurfaceAdapter) -> void

# Terrain modification
func place_gas(world_pos: Vector2, radius: float, density: float, velocity: Vector2) -> void
func place_lava(world_pos: Vector2, radius: float) -> void
func place_fire(world_pos: Vector2, radius: float) -> void
func clear_and_push_materials_in_arc(center: Vector2, facing: Vector2, arc_half: float, inner_r: float, outer_r: float) -> void

# Terrain reading
func read_region(rect: Rect2i) -> PackedByteArray
func find_spawn_position(origin: Vector2, body_size: Vector2, max_radius: float) -> Vector2
```

### What Changes

| File | Change |
|------|--------|
| `src/core/world_manager.gd` | Implements TerrainSurfaceAdapter, registers in `_ready()`, delegates to TerrainModifier/TerrainReader |
| `src/weapons/melee_weapon.gd` | `TerrainSurface.clear_and_push_materials_in_arc(...)` instead of `world_manager.clear_and_push_materials_in_arc(...)` |
| `src/weapons/test_weapon.gd` | `TerrainSurface.place_gas(...)` instead of `world_manager.place_gas(...)` |
| `src/weapons/lava_emitter_modifier.gd` | `TerrainSurface.place_lava(...)` instead of `world_manager.place_lava(...)` |
| `src/player/player_controller.gd` | `TerrainSurface.find_spawn_position(...)` instead of `world_manager.find_spawn_position(...)` |
| `src/player/lava_damage_checker.gd` | Will use TerrainPhysical (see Candidate 4) |
| `src/debug/chunk_grid_overlay.gd` | Access via TerrainSurface if needed, or stay direct for debug-only |
| `src/debug/collision_overlay.gd` | Same as above |
| `project.godot` | Add TerrainSurface autoload |

### Benefits

- **Locality**: Terrain-writing interface is the seam. WorldManager's chunk lifecycle, GPU dispatch, and simulation tick are implementation details behind the seam.
- **Leverage**: 6+ callers get terrain access through one static reference, decoupled from scene-tree position.
- **Tests**: Weapons tested with a fake TerrainSurface adapter (in-memory grid). WorldManager's chunk management tested independently.

---

## 4. TerrainPhysical — Unified Terrain Query

### Problem

Three separate systems independently read terrain data:
1. **ShadowGrid** (`src/core/shadow_grid.gd`): Maintains a 128×128 CPU-side cache around the player, async two-phase GPU readback, used by LavaDamageChecker for material/damage queries
2. **TerrainReader** (`src/core/terrain_reader.gd`): GPU-to-CPU readback for arbitrary rects, used by TerrainModifier for write-prep and by CollisionManager
3. **CollisionManager**: Reads texture data to build physics shapes via GPU collider shader or CPU marching squares fallback

Each has its own readback contract, timing, and data format. Understanding "what's at position (x,y)?" requires knowing which system to ask and its async quirks.

**Deletion test**: Delete ShadowGrid, and lava damage queries need their own readback path. Delete TerrainReader, and each modifier operation needs inline readback logic.

### Solution

Create **TerrainPhysical** — a module behind the TerrainSurface seam that answers a single question: "what's at this position?" with a cached, unified interface.

### Interface

```gdscript
# TerrainCell — query result
class_name TerrainCell extends Resource
var material_id: int
var is_solid: bool
var is_fluid: bool
var damage: float
```

```gdscript
# TerrainPhysical — internal module, created by WorldManager
extends Node

func query(world_pos: Vector2) -> TerrainCell
func invalidate_rect(rect: Rect2i) -> void
```

### Internal Architecture

```
TerrainPhysical
  │
  ├─ Cache Layer: CPU-side grid of TerrainCell, invalidated on terrain write
  │    ├─ covers viewport-centered region, recenters as player moves
  │    └─ lazy backfill: async GPU readback for uncached cells
  │
  ├─ Collision Build: triggered on cache update, builds ConcavePolygonShape2D
  │    └─ uses TerrainCollider.build_collision() or GPU collider shader
  │
  └─ Query: O(1) lookup from cache, sync
```

### What Changes

| File | Change |
|------|--------|
| `src/core/shadow_grid.gd` | **Deleted** — cache layer absorbed into TerrainPhysical |
| `src/core/terrain_reader.gd` | Readback logic absorbed into TerrainPhysical's lazy backfill |
| `src/core/collision_manager.gd` | Collision build absorbed into TerrainPhysical's collision layer |
| `src/core/world_manager.gd` | Creates TerrainPhysical instead of CollisionManager + TerrainReader separately |
| `src/player/player_controller.gd` | Removes ShadowGrid creation, PlayerInventory creation instead |
| `src/player/lava_damage_checker.gd` | `TerrainPhysical.query(pos)` instead of `shadow_grid.get_material(pos)` |
| `src/physics/gas_injector.gd` | `TerrainPhysical.query(pos)` instead of direct texture reads |
| `src/core/terrain_modifier.gd` | Calls `TerrainPhysical.invalidate_rect()` after writes |

### Benefits

- **Locality**: All terrain querying is one module. Changing readback strategy (buffer size, caching policy) happens in one place.
- **Leverage**: Lava damage, gas injection, spawn finding, pathfinding (future), and physics all query through the same interface.
- **Tests**: TerrainPhysical testable with a pre-populated in-memory grid. Callers don't need GPU.
- **Interface depth**: Interface is 2 methods (`query`, `invalidate_rect`) + 1 resource (`TerrainCell`). Implementation is cache + async readback + collision building.

---

## 5. PlayerInventory — Unified Player State

### Problem

Player state is scattered across 4 shallow modules, each accessed via fragile node-name lookups:
- `WalletComponent` (24 lines): wraps an int with `gold_changed` signal
- `ModifierInventory` (30 lines): wraps an array with signals
- `HealthComponent` (64 lines): health + invincibility + death state
- `WeaponManager` weapon slots: 3-slot array with equip/swap/remove

Every UI script and drop knows the exact node name (`"WalletComponent"`, `"ModifierInventory"`, `"WeaponManager"`) and drills into the Player scene:
```
get_tree().get_first_node_in_group("player").get_node("WalletComponent")
```

**Deletion test**: Delete WalletComponent, its logic moves to PlayerController in 2 lines. Delete ModifierInventory, same. These are pass-through wrappers that add node-crawling complexity without depth.

### Solution

Create **PlayerInventory** — a single player child node that owns all player resource state behind typed signals.

### Interface

```gdscript
# PlayerInventory — player child node
extends Node

# Signals
signal gold_changed(new_amount: int)
signal health_changed(new_health: int, max_health: int)
signal weapon_changed(slot: int, weapon: Weapon)
signal modifier_changed(weapon_slot: int, modifier_slot: int, modifier: Modifier)
signal player_died()

# Gold
func add_gold(amount: int) -> void
func spend_gold(amount: int) -> bool
func get_gold() -> int

# Health
func take_damage(amount: float) -> void
func heal(amount: float) -> void
func get_health() -> float
func get_max_health() -> float
func is_dead() -> bool

# Weapons
func equip_weapon(slot: int, weapon: Weapon) -> void
func remove_weapon(slot: int) -> Weapon
func get_weapon(slot: int) -> Weapon
func get_weapon_count() -> int
func get_active_weapon_slot() -> int

# Modifiers
func can_equip_modifier(weapon_slot: int) -> bool
func add_modifier(weapon_slot: int, modifier_slot: int, modifier: Modifier) -> void
func remove_modifier(weapon_slot: int, modifier_slot: int) -> Modifier
func get_free_modifier_slot(weapon_slot: int) -> int  # -1 if full
func get_all_modifiers() -> Array[Modifier]
```

### What Changes

| File | Change |
|------|--------|
| `src/player/wallet_component.gd` | **Deleted** — merged into PlayerInventory |
| `src/player/modifier_inventory.gd` | **Deleted** — merged into PlayerInventory |
| `src/player/health_component.gd` | **Deleted** — merged into PlayerInventory |
| `src/player/weapon_manager.gd` | Weapon slot management moves into PlayerInventory; input handling stays in WeaponManager (thinner) |
| `src/player/player_controller.gd` | Creates PlayerInventory child instead of 4 separate component children |
| `src/ui/currency_hud.gd` | Listens to `PlayerInventory.gold_changed` instead of `WalletComponent.gold_changed` |
| `src/ui/health_ui.gd` | Listens to `PlayerInventory.health_changed` instead of `HealthComponent.health_changed` |
| `src/ui/death_screen.gd` | Listens to `PlayerInventory.player_died` instead of `HealthComponent...` |
| `src/drops/gold_drop.gd` | Calls `PlayerInventory.add_gold()` instead of `WalletComponent.add_gold()` |
| `src/drops/weapon_drop.gd` | Uses WeaponDelivery (Candidate 6), which reads PlayerInventory |
| `src/drops/modifier_drop.gd` | Uses WeaponDelivery (Candidate 6), which reads PlayerInventory |
| `src/economy/shop_ui.gd` | Calls `PlayerInventory.spend_gold/add_gold` instead of `WalletComponent` |
| `src/ui/weapon_button.gd` | Listens to `PlayerInventory.weapon_changed` etc. |
| `src/console/commands/gold_command.gd` | Calls `PlayerInventory.add_gold()` |

### Benefits

- **Locality**: All player resource state in one module. Add "keys" or "experience" without adding new child nodes.
- **Leverage**: 10+ consumers get a single entry point. Validation (spend-gold-can't-negative, equip-to-full-slot) is enforced in one place.
- **Tests**: PlayerInventory fully testable in isolation. UI tests use a test PlayerInventory rather than a full Player scene.
- **Interface depth**: 16 methods + 5 signals behind one node reference. Previously required knowing 4 node names and their individual signals.

---

## 6. WeaponDelivery — Unified Pickup Flow

### Problem

Three modules independently implement the same flow:
1. **WeaponDrop** (`_pickup()`): check slots → show WeaponPopup (pickup mode) → wait for close → equip weapon
2. **ModifierDrop** (`_pickup()`): check modifier slots → if full, flash weapon button → show WeaponPopup → add modifier
3. **ShopUI** (`_on_buy_pressed()`): deduct gold → show WeaponPopup → add modifier

Each duplicates slot validation, WeaponPopup orchestration, and error/edge-case handling. The deletion test: deleting WeaponPopup would force each of these 3 to reimplement slot-selection UI independently.

### Solution

Create **WeaponDelivery** — a player child node that owns the WeaponPopup interaction, slot validation, and apply/rollback.

### Interface

```gdscript
# WeaponOfferSpec — what is being offered
class_name WeaponOfferSpec extends Resource
enum OfferType { WEAPON, MODIFIER, REMOVE_MODIFIER }
var type: OfferType
var weapon: Weapon
var modifier: Modifier
var suggested_slot: int
```

```gdscript
# WeaponDelivery — player child node
extends Node

func offer(spec: WeaponOfferSpec, callback: Callable) -> void
# callback signature: func(accepted: bool, selected_slot: int) -> void
```

### Internal Flow

```
WeaponDelivery.offer(spec, callback)
  │
  ├─ Validate: can this be equipped? (check PlayerInventory)
  ├─ If can't (e.g., no free slots): notify callback(false, -1), return
  ├─ Show WeaponPopup with appropriate mode
  ├─ Wait for WeaponPopup to close
  ├─ If accepted: apply to PlayerInventory
  └─ Invoke callback(accepted, slot)
```

### What Changes

| File | Change |
|------|--------|
| `src/player/weapon_delivery.gd` | **New** — owns the offer→popup→apply flow |
| `src/drops/weapon_drop.gd` | `_pickup()` constructs WeaponOfferSpec, calls `WeaponDelivery.offer(spec, callback)` |
| `src/drops/modifier_drop.gd` | Same pattern — constructs spec, calls offer |
| `src/economy/shop_ui.gd` | After gold deduction, calls `WeaponDelivery.offer(spec, callback)` instead of directly opening WeaponPopup |
| `src/ui/weapon_popup.gd` | Interface narrows — only needs to display options and report selection, doesn't need to know about wallet, drop sources, or shop state |
| `src/player/weapon_manager.gd` | Thinner — input handling only, slot management in PlayerInventory, delivery in WeaponDelivery |

### Benefits

- **Locality**: Slot-selection protocol (validate, show UI, wait, apply) in one module instead of 3.
- **Leverage**: Future weapon sources (chests, quest rewards, crafting) get the full delivery flow from one call.
- **Tests**: Delivery logic testable without instantiating WeaponPopup (use a test callback). WeaponPopup testable as standalone UI.
- **Interface depth**: Interface is 1 method + 1 resource. Implementation: validation, UI orchestration, error handling, callback dispatch.

---

## Module Dependency Graph (Post-Refactor)

```
TerrainSurface (autoload)
  │
  └─ WorldManager (adapter, registered at _ready)
       ├─ ComputeDevice (GPU pipelines)
       ├─ ChunkManager (chunk lifecycle)
       ├─ TerrainModifier (terrain writes → calls TerrainPhysical.invalidate)
       └─ TerrainPhysical (unified query: cache + collision + readback)

Player
  ├─ PlayerController (movement, input)
  ├─ PlayerInventory (gold, health, weapons, modifiers) ← SIGNALS to UI
  ├─ PickupContext (detection, highlighting, dispatch)
  ├─ WeaponManager (input handling: Z/X/C keys, active weapon tick)
  ├─ WeaponDelivery (offer→popup→apply flow)
  └─ LavaDamageChecker → queries TerrainPhysical

HitReaction (autoload)
  └─ Internal: 5 juice adapters

Gameplay Callers
  ├─ Weapons → TerrainSurface (for terrain writes)
  │          → HitReaction (for hit feedback)
  ├─ Enemies → HitReaction
  ├─ Drops → PickupContext (detection) + WeaponDelivery (weapon/mod) + PlayerInventory (gold)
  ├─ ShopUI → PlayerInventory (gold) + WeaponDelivery (offer)
  └─ UI → PlayerInventory SIGNALS (no node-crawling)
```

---

## Testing Strategy

| Module | Test Adapter | What's Tested |
|--------|-------------|---------------|
| HitReaction | N/A (test HitSpec → effects directly) | HitSpec field interpretation, kill-bonus logic |
| PickupContext | Mock Pickupable nodes | Detection range, highlighting, auto vs manual pickup dispatch |
| TerrainSurface | In-memory TerrainSurfaceAdapter | place_gas/lava/fire write to grid, read_region returns correct bytes |
| TerrainPhysical | Pre-populated cache | query returns correct TerrainCell, invalidation clears cache |
| PlayerInventory | N/A (pure in-memory) | Gold add/subtract, health invincibility, weapon/modifier slot validation |
| WeaponDelivery | Callback-spy (a test flag in WeaponDelivery that skips showing WeaponPopup and invokes callback with a predetermined selection) | Correct slot validation, callback invoked with expected args |

All existing gdUnit4 infrastructure is already installed (`addons/gdUnit4/`). Tests will be written using that framework.

---

## Files to Delete

| File | Reason |
|------|--------|
| `src/player/wallet_component.gd` | Merged into PlayerInventory |
| `src/player/modifier_inventory.gd` | Merged into PlayerInventory |
| `src/player/health_component.gd` | Merged into PlayerInventory |
| `src/player/interaction_controller.gd` | Replaced by PickupContext |
| `src/interactables/interactable.gd` | Replaced by Pickupable interface |
| `src/core/shadow_grid.gd` | Absorbed into TerrainPhysical cache |
| `src/core/terrain_reader.gd` | Absorbed into TerrainPhysical lazy backfill |
| `src/core/collision_manager.gd` | Absorbed into TerrainPhysical collision build |

---

## Files to Create

| File | Type |
|------|------|
| `src/core/juice/hit_reaction.gd` | Autoload — HitReaction |
| `src/core/juice/hit_spec.gd` | Resource — HitSpec |
| `src/core/terrain_surface.gd` | Autoload — TerrainSurface |
| `src/core/terrain_physical.gd` | Node — TerrainPhysical |
| `src/core/terrain_cell.gd` | Resource — TerrainCell |
| `src/drops/pickupable.gd` | Interface — Pickupable (extends Node) |
| `src/player/pickup_context.gd` | Node — PickupContext |
| `src/player/player_inventory.gd` | Node — PlayerInventory |
| `src/player/weapon_delivery.gd` | Node — WeaponDelivery |
| `src/player/weapon_offer_spec.gd` | Resource — WeaponOfferSpec |
| `tests/unit/test_hit_reaction.gd` | Test |
| `tests/unit/test_terrain_surface.gd` | Test |
| `tests/unit/test_terrain_physical.gd` | Test |
| `tests/unit/test_player_inventory.gd` | Test |
| `tests/unit/test_weapon_delivery.gd` | Test |
| `tests/unit/test_pickup_context.gd` | Test |

---

## Scene Changes

### `scenes/levels/game.tscn`

Player child nodes:
- **Remove**: HealthComponent, WalletComponent, ModifierInventory, InteractionController
- **Add**: PlayerInventory, PickupContext, WeaponDelivery
- **Keep**: WeaponManager (thinner), LavaDamageChecker (updated)

WorldManager:
- **Remove**: direct CollisionManager and TerrainReader references
- **Add**: TerrainPhysical child node creation in script

### `scenes/levels/*.tscn` (all level scenes with enemies)

Remove: individual HitStopManager, ScreenShakeManager, etc. scene instances (they're autoloads, not scene instances — but verify no stale references).

---

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| WeaponPopup is 804 lines — refactoring its interface could break subtle interactions | WeaponDelivery wraps WeaponPopup, doesn't modify its internals. WeaponPopup keeps its modes; delivery just picks the right mode. |
| GPU terrain readback unification could regress performance | Keep the existing async two-phase pattern. TerrainPhysical cache is a new layer on top, not a replacement of the existing readback path. |
| Removing 4 player component nodes could break scene instances that reference them by path | Update all `.tscn` scenes to reference PlayerInventory instead. Audit with grep for hardcoded node names. |
| GoldDrop extends Area2D but Drop extends RigidBody2D — unification could break physics | GoldDrop keeps its Area2D inheritance but implements Pickupable. No physics change. |

---

## Non-Goals

- Not changing GPU shader code (generation.glsl, simulation.glsl, collider.glsl)
- Not changing ChunkManager or ComputeDevice internals — they stay behind the TerrainSurface seam
- Not rewriting WeaponPopup's 804 lines — WeaponDelivery wraps it, doesn't replace it
- Not adding save/load — out of scope
