# Weapon Manager Decoupling Design

## Summary
Create a `WeaponManager` node that handles all weapon-related logic, fully decoupling it from `PlayerController`.

## Current State
`PlayerController` currently:
- Creates weapons in `_ready()` (hard-coded)
- Handles weapon input (Z/X/C keys)
- Ticks weapons in `_physics_process()`
- Provides `get_world_manager()` and `get_facing_direction()` for weapons

## Proposed Changes

### WeaponManager (new file: `src/weapons/weapon_manager.gd`)
A node that handles weapon lifecycle and input:
```gdscript
class_name WeaponManager
extends Node

var weapons: Array[Weapon] = []

func _ready() -> void:
    weapons.resize(3)
    weapons[0] = TestWeapon.new()
    weapons[1] = MeleeWeapon.new()

func _input(event: InputEvent) -> void:
    # Handle Z/X/C key presses to trigger weapons
    # Calls weapon.use(get_parent())

func _physics_process(delta: float) -> void:
    # Tick all weapons
```

### PlayerController Changes
Remove from `src/player/player_controller.gd`:
- `weapons: Array[Weapon]` variable
- Preloads for weapon scripts
- `weapons.resize/create` in `_ready()`
- `_input()` method
- `_tick_weapons()` method
- `_tick_weapons(delta)` call in `_physics_process()`

Keep unchanged:
- `get_world_manager()` method
- `get_facing_direction()` method

### Weapon Base Class
No changes. Weapons continue to receive the user node and call `get_world_manager()` and `get_facing_direction()` on it.

## Scene Update
Update `scenes/player.tscn` to add WeaponManager as a child node of Player.

## Files
- **New:** `src/weapons/weapon_manager.gd`
- **Modified:** `src/player/player_controller.gd`
- **Modified:** `scenes/player.tscn`