# Weapon Modifier System Design

## Overview

A modifier system for weapons that allows modifiers to be socketed into weapon slots. Modifiers add effects on top of a weapon's base behavior, can modify stats on equip, and can optionally suppress the weapon's base `use()` behavior. The first concrete modifier is **Lava Emitter**, which spawns lava at the weapon's use position.

## Decisions

- **Additive + suppress**: Modifiers add effects alongside base weapon behavior. A modifier can set `suppresses_base_use = true` to skip the weapon's own `use()` logic.
- **Slot count**: Each weapon has an integer `modifier_slot_count` property set in `_init()`. Default is 3 for all weapons.
- **Stat application**: Stats are modified directly on equip (`on_equip()` modifies `weapon.damage`, `weapon.cooldown`, etc.).
- **Permanence**: Modifiers cannot be removed once placed. Replacing a slot destroys the old modifier.
- **Lava Emitter timing**: Spawns lava on `on_use()` (same trigger as the weapon's `use()`).

## Architecture

### Modifier Base Class (`src/weapons/modifier.gd`)

```gdscript
class_name Modifier
extends RefCounted

var name: String = "Modifier"
var description: String = ""
var icon_texture: Texture2D = null
var suppresses_base_use: bool = false

func on_equip(weapon: Weapon) -> void:
    pass

func on_use(_weapon: Weapon, _user: Node) -> void:
    pass

func on_tick(_weapon: Weapon, _delta: float) -> void:
    pass

func get_description() -> String:
    return description
```

Lifecycle hooks:
- `on_equip(weapon)` — called when the modifier is placed into a weapon slot. Used for direct stat modifications.
- `on_use(weapon, user)` — called each time the weapon is used (before the base behavior). Receives weapon and user references.
- `on_tick(weapon, delta)` — called every physics frame for continuous effects.
- `suppresses_base_use` — if any modifier sets this to `true`, the weapon's own `_use_impl()` is skipped.
- `get_description()` — returns description text for tooltip display.

### Weapon Changes (`src/weapons/weapon.gd`)

New properties:
```gdscript
var modifier_slot_count: int = 3
var modifiers: Array = []
var _cooldown_timer: float = 0.0
```

`_cooldown_timer` is moved from TestWeapon/MeleeWeapon into the base class since both use it identically. This allows the base `use()` to check cooldown before firing modifiers.

Template method pattern for `use()`:
```gdscript
func use(user: Node) -> void:
    if not is_ready():
        return
    for modifier in modifiers:
        if modifier != null:
            modifier.on_use(self, user)
    var suppress: bool = false
    for modifier in modifiers:
        if modifier != null and modifier.suppresses_base_use:
            suppress = true
            break
    if not suppress:
        _use_impl(user)
    _cooldown_timer = cooldown
```

Cooldown check is in the base `use()`, so `_use_impl()` no longer needs it. Cooldown timer is set in base `use()` after both modifiers and `_use_impl()` run — this ensures cooldown applies even if base use is suppressed.

`tick()` handles cooldown and iterates modifiers:
```gdscript
func tick(delta: float) -> void:
    if _cooldown_timer > 0.0:
        _cooldown_timer -= delta
    for modifier in modifiers:
        if modifier != null:
            modifier.on_tick(self, delta)
    _tick_impl(delta)

func _tick_impl(_delta: float) -> void:
    pass
```

`is_ready()` is moved to base class:
```gdscript
func is_ready() -> bool:
    return _cooldown_timer <= 0.0
```

Helper methods:
```gdscript
func add_modifier(slot_index: int, modifier: Modifier) -> void:
    if slot_index < 0 or slot_index >= modifier_slot_count:
        return
    modifiers[slot_index] = modifier
    modifier.on_equip(self)

func get_modifier_at(slot_index: int) -> Modifier:
    if slot_index < 0 or slot_index >= modifiers.size():
        return null
    return modifiers[slot_index]
```

`get_base_stats()` remains unchanged (returns pre-modifier stats). New `get_stats()` returns post-modifier stats:
```gdscript
func get_stats() -> Dictionary:
    return get_base_stats()
```

(For now, stats modified via `on_equip` are already written to the weapon's properties, so `get_stats()` just returns the same as `get_base_stats()`. This distinction exists for future display purposes.)

### Existing Weapon Refactoring

Each weapon's `use()` method is renamed to `_use_impl()`. The cooldown check (`if _cooldown_timer > 0.0: return`) and cooldown timer setting (`_cooldown_timer = cooldown`) are **removed** from `_use_impl()` — they're now handled by the base class. Each weapon's `_use_impl()` only contains the weapon-specific effect logic.

Each weapon's `tick()` method body (minus the cooldown decrement) is moved into `_tick_impl()`. The cooldown decrement is now in the base `Weapon.tick()`.

Each weapon's `is_ready()` override is **removed** — the base class now provides `is_ready()` returning `_cooldown_timer <= 0.0`.

Each weapon's `_init()` must call `modifiers.resize(modifier_slot_count)` after setting `modifier_slot_count` to initialize the modifier slot array.

`_get_world_manager()` and `_get_facing_direction()` helpers remain in each weapon subclass. `_cooldown_timer` is removed from subclasses (now on base class).

### Lava Emitter Modifier (`src/weapons/lava_emitter_modifier.gd`)

```gdscript
class_name LavaEmitterModifier
extends Modifier

const LAVA_RADIUS: float = 6.0

func _init() -> void:
    name = "Lava Emitter"
    description = "Spawns lava around the user when the weapon is used."
    icon_texture = preload("res://textures/Modifiers/lava_emitter.png")

func on_use(_weapon: Weapon, user: Node) -> void:
    var world_manager = _get_world_manager(user)
    if world_manager == null:
        return
    var pos: Vector2 = _weapon._sprite.global_position if _weapon._sprite else user.global_position
    world_manager.place_lava(pos, LAVA_RADIUS)

func _get_world_manager(user: Node) -> Node:
    if user.has_method("get_world_manager"):
        return user.get_world_manager()
    var parent = user.get_parent()
    if parent:
        return parent.get_node_or_null("WorldManager")
    return null
```

Follows the same duck-typing pattern as `TestWeapon._get_world_manager()`. Does not suppress base behavior.

### WeaponManager Changes

New method for adding modifiers from external call sites (drops, shop, etc.):
```gdscript
func add_modifier_to_weapon(weapon_slot: int, modifier_slot: int, modifier: Modifier) -> void:
    if weapon_slot < 0 or weapon_slot >= weapons.size():
        return
    var weapon := weapons[weapon_slot]
    if weapon == null:
        return
    weapon.add_modifier(modifier_slot, modifier)
```

In `_ready()`, test integration:
```gdscript
weapons[0] = TestWeaponScript.new()
weapons[0].add_modifier(0, LavaEmitterModifier.new())
weapons[1] = MeleeWeaponScript.new()
```

### UI: Weapon Popup Modifier Display

In `_create_card()`, below the weapon stats (cooldown, damage), add an `HBoxContainer` with one icon per modifier slot:

- **Filled slot**: `TextureRect` displaying the modifier's `icon_texture`. Size ~32x32. On `mouse_entered`, shows a tooltip `PanelContainer` with the modifier name and description. On `mouse_exited`, hides the tooltip.
- **Empty slot**: `ColorRect` with dark color (matches existing EMPTY/placeholder style). Size ~32x32.

The tooltip is a `PanelContainer` created dynamically, positioned near the hovered icon, containing a `VBoxContainer` with:
- `Label` for modifier name
- `Label` for modifier description

### UI: Weapon Button Modifier Icons

In the existing weapon button tooltip (which shows name, cooldown, damage), add an `HBoxContainer` below the damage label containing small icons (~16x16) for each modifier slot. Filled slots show the modifier icon; empty slots show a small dark square. No hover interaction on this compact display.

## File Changes

### New Files
- `src/weapons/modifier.gd` — Modifier base class
- `src/weapons/lava_emitter_modifier.gd` — Lava Emitter concrete modifier
- `textures/Modifiers/lava_emitter.png` — Icon for Lava Emitter (placeholder)

### Modified Files
- `src/weapons/weapon.gd` — Add modifier_slot_count, modifiers array, template method pattern for use/tick, add_modifier/get_modifier_at helpers
- `src/weapons/test_weapon.gd` — Rename use() to _use_impl(), rename tick() to _tick_impl(), set modifier_slot_count
- `src/weapons/melee_weapon.gd` — Rename use() to _use_impl(), rename tick() to _tick_impl(), set modifier_slot_count
- `src/weapons/weapon_manager.gd` — Add add_modifier_to_weapon(), wire LavaEmitterModifier on TestWeapon in _ready()
- `src/ui/weapon_popup.gd` — Add modifier slot icons and hover tooltips to weapon cards
- `src/ui/weapon_button.gd` — Add modifier icon row to tooltip

## Out of Scope

- Shop system for purchasing modifiers
- Modifier transfer on weapon pickup
- Drag-and-drop UI for modifier placement
- Additional modifier types (fire, ice, stat boosts) — these are future work
- Removing modifiers from weapons (permanent per design doc)