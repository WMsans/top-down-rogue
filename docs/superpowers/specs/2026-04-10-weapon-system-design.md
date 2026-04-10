# Weapon System Design

## Summary

A script-based weapon system where each weapon is a GDScript class with a `use(user: Node)` method. The player has 3 weapon slots (extensible) triggered by Z/X/C keys. Weapons manage their own cooldowns internally.

## Architecture

```
src/
├── weapons/
│   ├── weapon.gd           # Base class
│   └── test_weapon.gd      # Implementation
└── player/
    └── player_controller.gd  # Weapon slots + input
```

## Weapon Base Class

`src/weapons/weapon.gd`:
- `class_name Weapon extends RefCounted`
- `var name: String` - for debugging/UI
- `func use(_user: Node) -> void` - abstract, must be overridden
- RefCounted base (no scene tree dependency)

## Weapon Implementation Pattern

Each weapon:
1. Extends `Weapon`
2. Sets `name` in `_init()`
3. Overrides `use(user: Node)`
4. Manages own cooldown via internal timer
5. Exposes `tick(delta: float)` for frame updates
6. Exposes `is_ready() -> bool` for cooldown queries
7. Extracts needed data from `user` node (position, world_manager, etc.)

### Test Weapon

`TestWeapon` spawns gas around the player:
- `GAS_RADIUS: float = 6.0`
- `GAS_DENSITY: int = 200`
- `COOLDOWN: float = 0.5` seconds
- Calls `world_manager.place_gas(position, radius, density)`
- Finds WorldManager via `user.get_world_manager()` or parent traversal

## Player Controller Integration

Add to `src/player/player_controller.gd`:

### Properties
- `var weapons: Array[Weapon]` - weapon slot array
- `const TestWeaponScript := preload(...)` - weapon preload

### Methods
- `_ready()`: Initialize 3-slot array, put TestWeapon in slot 0
- `_physics_process(delta)`: Call `_tick_weapons(delta)`
- `_input(event)`: Handle Z/X/C key presses, invoke `weapons[slot].use(self)`
- `_tick_weapons(delta)`: Iterate weapons, call `tick(delta)` if exists
- `get_world_manager() -> Node`: Return `_world_manager` for weapon access

### Key Bindings
| Key | Slot |
|-----|------|
| Z   | 0    |
| X   | 1    |
| C   | 2    |

## Adding New Weapons

1. Create `src/weapons/my_weapon.gd` extending `Weapon`
2. Implement `use(user: Node)`
3. Add `tick(delta)` if cooldown needed
4. In `player_controller.gd`:
   - Add preload constant
   - Add instance to `weapons` array in `_ready()`

## Extending Slots

The `weapons` array can be resized:
```gdscript
weapons.resize(5)  # 5 slots
```

Add more key bindings in `_input()` as needed.

## File Changes

### New Files
- `src/weapons/weapon.gd`
- `src/weapons/test_weapon.gd`

### Modified Files
- `src/player/player_controller.gd` - Add weapon system