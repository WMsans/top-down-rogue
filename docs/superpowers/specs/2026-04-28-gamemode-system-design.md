# GameMode System Design

## Summary

Add a gamemode system with survival (default) and creative modes. Switch via console command `gamemode 0`/`gamemode 1`. Creative mode grants noclip (walk through walls/enemies), undeath (refill HP to full when reaching 0), and instant kill (any player attack kills enemies in one hit).

---

## Architecture

### New Files

| File | Purpose |
|------|---------|
| `src/autoload/game_mode_manager.gd` | Autoload singleton — holds current mode, provides `is_creative()` / `set_mode()` API |
| `src/console/commands/gamemode_command.gd` | Console command — parses `gamemode 0`/`gamemode 1`, calls `GameModeManager.set_mode()` |

### Modified Files

| File | Change |
|------|--------|
| `project.godot` | Add `GameModeManager` to autoload list |
| `src/console/command_registry.gd` | Register `gamemode` command in `_register_all()` |
| `src/player/player_controller.gd` | Save/restore collision layers; disable when creative |
| `src/player/player_inventory.gd` | In `take_damage()`, refill HP instead of dying when creative |
| `src/enemies/enemy.gd` | In `hit()`, set damage to `max_health` when creative (instant kill) |

### Existing Systems Used (Unchanged)

| System | How used |
|--------|----------|
| `ConsoleManager` (autoload) | Console UI already renders command output; gamemode command prints mode change confirmation |
| `CommandRegistry` | New command registered via existing `register()` tree API |

---

## GameModeManager (Autoload)

### API

```gdscript
enum Mode { SURVIVAL = 0, CREATIVE = 1 }

var current_mode: Mode = Mode.SURVIVAL

func is_creative() -> bool
func set_mode(mode: Mode) -> void
func get_mode() -> Mode
```

- No signals needed — components poll `is_creative()` on the relevant code path (per-frame for noclip, on-damage for undeath/instant-kill). No signal overhead for hot paths.
- `set_mode()` stores the mode. The console command handles printing feedback.

---

## Console Command: `gamemode`

### Registration

Registered in `CommandRegistry._register_all()`:

```gdscript
register("gamemode", execute_func, "Switch gamemode (0=survival, 1=creative)")
```

Single command, no subcommands. Accepts one integer argument.

### Execution

```
> gamemode 1
Set gamemode to CREATIVE (noclip, undeath, instant kill)

> gamemode 0
Set gamemode to SURVIVAL

> gamemode 2
Unknown gamemode 2. Use 0 (survival) or 1 (creative).
```

---

## Noclip (`PlayerController`)

### Current State

`player_controller.gd` line 25 sets `collision_layer = 3` and line 24 adds to `"player"` group. The `CharacterBody2D.move_and_slide()` call in `_apply_movement()` (line 86) handles collision resolution against `collision_mask`.

### Change

```gdscript
# _ready()
var _original_collision_layer: int
var _original_collision_mask: int
_original_collision_layer = collision_layer
_original_collision_mask = collision_mask

# _physics_process() — before movement calculation
if GameModeManager.is_creative():
    collision_layer = 0
    collision_mask = 0
else:
    collision_layer = _original_collision_layer
    collision_mask = _original_collision_mask
```

Setting both to 0 disables all collision detection for the player — they pass through terrain walls (layer 1), other enemies, and everything. No need to touch individual collision layers; zeroing out is simplest and most complete.

---

## Undeath (`PlayerInventory`)

### Current State

`player_inventory.gd` lines 76-105: `take_damage(amount)` checks `_is_dead` and `_is_invincible` before applying damage. When `health <= 0`, it emits `player_died` after a short timer. `_is_invincible` is set for 1.0s after taking damage (no stacking invincibility). The death flow ultimately leads to `DeathScreen` showing and the player being removed.

### Change

```gdscript
func take_damage(amount: int) -> void:
    if _is_dead:
        return
    if _is_invincible:
        return
    health = max(0, health - amount)
    _is_invincible = true
    health_changed.emit(health)
    if health <= 0:
        if GameModeManager.is_creative():
            health = max_health
            health_changed.emit(health)
        else:
            player_died.emit()
            _is_dead = true
    var timer := get_tree().create_timer(invincibility_duration)
    timer.timeout.connect(func(): _is_invincible = false)
```

In creative mode: HP hits 0 → instantly refills to `max_health` → no `player_died` signal → invincibility still applies for the duration to prevent flickering. The player functionally cannot die.

---

## Instant Kill (`Enemy`)

### Current State

`enemy.gd` lines 31-39: `hit(damage: int)` subtracts damage from `health`, then checks `if health <= 0:` → `die()`. Call chain: melee weapon → `enemy.on_hit_impact()` → `enemy.hit(damage)`. Only the player attacks enemies in this game, so no attacker identity tracking needed.

### Change

```gdscript
func hit(damage: int) -> void:
    if damage <= 0:
        return
    if GameModeManager.is_creative():
        damage = max_health
    health -= damage
    health_changed.emit(health, max_health)
    _on_hit()
    if health <= 0:
        die()
```

No weapon scripts need modification. The gamemode check lives entirely inside `hit()`.

---

## Project Registration

### `project.godot` Autoload Order

Add `GameModeManager` to the autoload list. It has no dependencies on other autoloads, so position is flexible. Place after existing autoloads:

```
GameModeManager="*res://src/autoload/game_mode_manager.gd"
```

---

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Switch to creative while invincibility is active | No change; invincibility timer continues. Next hit after timer expires triggers undeath |
| Switch to survival while inside a wall | On next frame, collision layers restore; player is pushed out of wall by Godot physics |
| Console uses gamemode with non-integer argument | Print: "Usage: gamemode <0|1>" |
| Player attacks an enemy in survival mode | Existing behavior unchanged — `attacker=null` default, gamemode check passes |
| Lava/environmental damage in creative | Undeath handles it — HP drops to 0, refills. Player effectively immune to all damage |

---

## Implementation Order

1. Create `GameModeManager` autoload
2. Register in `project.godot`
3. Create `gamemode_command.gd` and register in `CommandRegistry`
4. Modify `PlayerController` — noclip
5. Modify `PlayerInventory` — undeath
6. Modify `Enemy.hit()` — instant kill
7. Test: `gamemode 1`, walk through walls, take damage, attack enemy
