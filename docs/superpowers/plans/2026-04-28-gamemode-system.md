# GameMode System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add survival/creative gamemode toggleable via console command `gamemode 0`/`gamemode 1`, with noclip, undeath, and instant kill in creative mode.

**Architecture:** New `GameModeManager` autoload stores current mode. Console command registers in `ConsoleManager._register_commands()`. PlayerController checks mode each frame for noclip (zeroes collision layers). PlayerInventory skips death when creative. Enemy `hit()` overrides damage to `max_health` when creative.

**Tech Stack:** Godot 4.6, GDScript, existing autoload/console infrastructure

---

### Task 1: Create GameModeManager Autoload

**Files:**
- Create: `src/autoload/game_mode_manager.gd`
- Modify: `project.godot` autoload section

- [ ] **Step 1: Write the autoload script**

```gdscript
extends Node

enum Mode { SURVIVAL = 0, CREATIVE = 1 }

var current_mode: Mode = Mode.SURVIVAL


func is_creative() -> bool:
    return current_mode == Mode.CREATIVE


func set_mode(mode: Mode) -> void:
    current_mode = mode


func get_mode() -> Mode:
    return current_mode
```

- [ ] **Step 2: Register autoload in project.godot**

In `project.godot`, add after the last autoload entry (after `TerrainSurface`):

```ini
GameModeManager="*res://src/autoload/game_mode_manager.gd"
```

- [ ] **Step 3: Commit**

```bash
git add src/autoload/game_mode_manager.gd project.godot
git commit -m "feat: add GameModeManager autoload"
```

---

### Task 2: Create gamemode Console Command

**Files:**
- Create: `src/console/commands/gamemode_command.gd`
- Modify: `src/autoload/console_manager.gd:36-44` (register in `_register_commands`)

- [ ] **Step 1: Write the command script**

```gdscript
extends RefCounted


static func register(registry: CommandRegistry) -> void:
    registry.register("gamemode", "Switch gamemode (0=survival, 1=creative)", _gamemode)


static func _gamemode(args: Array[String], _ctx: Dictionary) -> String:
    if args.is_empty():
        var current := GameModeManager.get_mode()
        return "Current gamemode: %d (%s)" % [current, GameModeManager.Mode.keys()[current]]
    if not args[0].is_valid_int():
        return "Usage: gamemode <0|1>"
    var mode_int := args[0].to_int()
    if mode_int < 0 or mode_int > 1:
        return "Unknown gamemode %d. Use 0 (survival) or 1 (creative)." % mode_int
    var mode: GameModeManager.Mode = mode_int as GameModeManager.Mode
    GameModeManager.set_mode(mode)
    return "Set gamemode to %s" % GameModeManager.Mode.keys()[mode]
```

- [ ] **Step 2: Register command in ConsoleManager**

In `src/autoload/console_manager.gd`, in `_register_commands()`, add after the existing `preload`/`register` lines:

```gdscript
    var GamemodeCommands := preload("res://src/console/commands/gamemode_command.gd")
    GamemodeCommands.register(_registry)
```

- [ ] **Step 3: Commit**

```bash
git add src/console/commands/gamemode_command.gd src/autoload/console_manager.gd
git commit -m "feat: add gamemode console command"
```

---

### Task 3: Noclip — PlayerController

**Files:**
- Modify: `src/player/player_controller.gd:22-37` (`_ready`) and `:40-57` (`_physics_process`)

- [ ] **Step 1: Add collision saving in `_ready()`**

After `collision_mask = 3` on line 25, add:

```gdscript
    _original_collision_layer = collision_layer
    _original_collision_mask = collision_mask
```

Add `var _original_collision_layer: int` and `var _original_collision_mask: int` to the member variables (near line 11-12, alongside `_last_facing` and `_facing_left`).

- [ ] **Step 2: Add noclip check in `_physics_process()`**

At the top of `_physics_process()` (after the `var inventory` but before the dead check), insert:

```gdscript
    if GameModeManager.is_creative():
        collision_layer = 0
        collision_mask = 0
    else:
        collision_layer = _original_collision_layer
        collision_mask = _original_collision_mask
```

Note: The existing dead check on lines 42-45 is fine — if the player dies in survival and is dead, noclip won't apply. But since undeath prevents death in creative, this is correct.

- [ ] **Step 3: Commit**

```bash
git add src/player/player_controller.gd
git commit -m "feat: noclip in creative gamemode"
```

---

### Task 4: Undeath — PlayerInventory

**Files:**
- Modify: `src/player/player_inventory.gd:76-87` (`take_damage`)

- [ ] **Step 1: Add creative undeath in `take_damage()`**

Change the `if _current_health <= 0:` block (lines 83-87) from:

```gdscript
    if _current_health <= 0:
        _is_dead = true
        if _color_rect:
            _color_rect.visible = true
        player_died.emit()
```

To:

```gdscript
    if _current_health <= 0:
        if GameModeManager.is_creative():
            _current_health = max_health
            health_changed.emit(_current_health, max_health)
        else:
            _is_dead = true
            if _color_rect:
                _color_rect.visible = true
            player_died.emit()
```

- [ ] **Step 2: Commit**

```bash
git add src/player/player_inventory.gd
git commit -m "feat: undeath in creative gamemode"
```

---

### Task 5: Instant Kill — Enemy

**Files:**
- Modify: `src/enemies/enemy.gd:31-38` (`hit`)

- [ ] **Step 1: Add instant kill in `hit()`**

Change `hit()` from:

```gdscript
func hit(damage: int) -> void:
    if damage <= 0:
        return
    health -= damage
    health_changed.emit(health, max_health)
    _on_hit()
    if health <= 0:
        die()
```

To:

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

- [ ] **Step 2: Commit**

```bash
git add src/enemies/enemy.gd
git commit -m "feat: instant kill in creative gamemode"
```

---

### Task 6: Verification

- [ ] **Step 1: Verify project loads without errors**

```bash
echo "Check that project.godot autoload list is valid — open project in Godot editor"
```

Open the project in Godot. Confirm no errors in the Output panel about missing autoload files.

- [ ] **Step 2: Manual test — creative mode**

1. Run the game
2. Press `` ` `` (backtick) to open console
3. Type `gamemode 1` and press Enter
4. Confirm output: "Set gamemode to CREATIVE"
5. Walk into a wall — player should pass through
6. Walk into an enemy — player should pass through
7. Let enemy hit you until HP reaches 0 — HP should refill to 100, player stays alive
8. Attack an enemy — enemy should die in one hit

- [ ] **Step 3: Manual test — survival mode**

1. With console open, type `gamemode 0` and press Enter
2. Confirm output: "Set gamemode to SURVIVAL"
3. Walk into a wall — player should collide normally
4. Let enemy hit you — player should take damage normally and die

- [ ] **Step 4: Manual test — console error handling**

1. Type `gamemode 2` → output: "Unknown gamemode 2. Use 0 (survival) or 1 (creative)."
2. Type `gamemode abc` → output: "Usage: gamemode <0|1>"
3. Type `gamemode` → output: "Current gamemode: 0 (SURVIVAL)"

- [ ] **Step 5: Commit any fixes if needed**

```bash
git status
```
