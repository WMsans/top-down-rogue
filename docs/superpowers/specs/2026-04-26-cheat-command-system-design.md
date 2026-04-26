# Cheat Command System Design

## Summary

Replace hardcoded debug inputs in `input_handler.gd` with a cheat console system (Slay the Spire / Skyrim style). The console opens with backtick, supports hierarchical commands with tab autocomplete, command history, error feedback, and dynamic type discovery via registries.

---

## Architecture

### New Files

| File | Purpose |
|------|---------|
| `src/autoload/console_manager.gd` | Autoload CanvasLayer – console UI overlay (LineEdit input, RichTextLabel output log, VBoxContainer suggestion panel) |
| `src/console/console_command.gd` | Base `RefCounted` class – name, description, subcommands dict, execute callable |
| `src/console/commands/spawn_command.gd` | `spawn weapon`, `spawn mod`, `spawn enemy`, `spawn gold` subcommands |
| `src/console/commands/spawn_mat_command.gd` | `spawn_mat` material placement commands |
| `src/console/commands/shop_command.gd` | `shop` command – opens test shop |
| `src/console/command_registry.gd` | Root command tree plus registration helper |
| `src/autoload/weapon_registry.gd` | **Auto-generated** – centralized weapon/modifier script dictionaries |
| `tools/generate_weapon_registry.sh` | Shell script that scans `src/weapons/` for `.gd` files, detects `extends Weapon` / `extends Modifier`, and generates `weapon_registry.gd` |

### Modified Files

| File | Change |
|------|--------|
| `src/input/input_handler.gd` | Remove all debug spawning code. If empty after removal, delete file |
| `scenes/game.tscn` | Remove InputHandler node reference |
| `project.godot` | Add `ConsoleManager` and `WeaponRegistry` to autoload list |

### Existing Systems Used (Unchanged)

| System | How used |
|--------|----------|
| `MaterialRegistry` (autoload) | `spawn_mat` queries `MaterialRegistry.materials`, filters for `fluid == true`, uses `MaterialDef.name.to_lower()` as subcommand names. No material types hardcoded in command code |
| `WeaponRegistry` (autoload, generated) | `spawn weapon` / `spawn mod` query `WeaponRegistry.weapon_scripts.keys()` and `modifier_scripts.keys()`. No weapon/modifier types hardcoded in command code |

---

## ConsoleManager (Autoload CanvasLayer)

### UI Layout (bottom of screen)

```
┌─────────────────────────────────────────────┐
│  > spawn weapon melee                       │  ← RichTextLabel output log
│  Spawned MeleeWeapon                        │    (gray echo, white success, red errors)
│  > spawn gold 50                            │
│  Spawned 50 gold                            │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │
│  melee  test                                │  ← VBoxContainer suggestion panel
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │
│  spawn weapon _                             │  ← LineEdit input field
└─────────────────────────────────────────────┘
```

### Input Handling

| Key | Action |
|-----|--------|
| `` ` `` (backtick) | Toggle console open/closed. Clear input on open |
| Enter | Parse command, execute, echo to output, add to history, clear input |
| Tab | Autocomplete current word. If cursor on empty parameter and no partial match, show all available subcommands/options in suggestion panel |
| Up/Down | Cycle command history |
| Escape | Close console |
| All other keys | Normal text input into LineEdit |

### Behavior

- When open: console captures all keyboard input (consumes events so gameplay does not fire). Game logic continues running (not paused).
- When closed: normal input flow restored. Suggestion panel hidden.
- Output log is scrollable and auto-scrolls to bottom on new output.
- Output format:
  - Echo: `"> command text"` in gray
  - Success: plain white text
  - Error: `"error: message"` in red

---

## Command System

### ConsoleCommand class (RefCounted)

```
name: String          # subcommand name, e.g. "weapon"
description: String   # help text for suggestions, e.g. "Spawn a weapon drop"
subcommands: Dictionary  # { "child_name": ConsoleCommand }
execute: Callable     # func(args: Array[String], ctx: CommandContext) -> String
                      # returns "" on success, "error: ..." on failure
```

### CommandContext

Computed fresh on each execution:

```
world_pos: Vector2     # mouse position converted to world coords via camera zoom/offset
player: Node           # get_tree().get_first_node_in_group("player"), may be null
world_manager: Node2D  # get_tree().current_scene.get_node_or_null("WorldManager"), may be null
```

### Command Tree

```
root
├── spawn
│   ├── weapon [type]           # spawn weapon drop at mouse
│   ├── mod [type]              # spawn modifier drop at mouse
│   ├── enemy [type]            # spawn enemy at mouse
│   └── gold [amount?]          # spawn gold drop at mouse (default 10)
├── spawn_mat
│   ├── lava [radius?]          # place lava at mouse (default 5)
│   └── gas [radius?]           # place gas at mouse (default 6)
└── shop                        # open test shop
```

`spawn_mat` subcommands are **dynamic** – one per fluid material from `MaterialRegistry.materials` where `fluid == true`.

`spawn weapon [type]` types come from `WeaponRegistry.weapon_scripts.keys()`.

`spawn mod [type]` types come from `WeaponRegistry.modifier_scripts.keys()`.

### Registration

Commands register via a helper on the root node:

```
func register(path: String, description: String, execute: Callable) -> void
```

Example: `register("spawn weapon melee", "Spawn a Melee weapon drop", _spawn_weapon.bind("melee"))`

This builds the tree automatically from dotted paths.

### Execution Flow

1. User types `spawn weapon melee` and presses Enter
2. Tokenize by spaces: `["spawn", "weapon", "melee"]`
3. Walk the command tree: root → `spawn` → `weapon` → `melee` (leaf)
4. If leaf has subcommands but no more args → show error listing required type
5. If node not found → error: `"error: unknown command 'spam'"`
6. If leaf found, call `execute([], ctx)` passing remaining args
7. If leaf is not a leaf (has subcommands) → error: `"error: 'spawn weapon' requires a type. Available: melee, test"`

---

## WeaponRegistry (Autoload, Auto-Generated)

### Generation Script: `tools/generate_weapon_registry.sh`

1. Scan `src/weapons/` recursively for all `.gd` files
2. For each file, check first content line after `extends`:
   - `extends Weapon` → derive key from filename (strip `_weapon.gd` suffix if present, or use full stem)
   - `extends Modifier` → derive key from filename (strip `_modifier.gd` suffix if present, or use full stem)
3. Generate `src/autoload/weapon_registry.gd` with preloads and populated dictionaries

### Generated Output Example

```gdscript
extends Node

var weapon_scripts: Dictionary = {}
var modifier_scripts: Dictionary = {}

func _ready() -> void:
	weapon_scripts["melee"] = preload("res://src/weapons/melee_weapon.gd")
	weapon_scripts["test"] = preload("res://src/weapons/test_weapon.gd")
	modifier_scripts["lava_emitter"] = preload("res://src/weapons/lava_emitter_modifier.gd")
```

### Usage by Commands

`spawn weapon [type]` validates `type` against `WeaponRegistry.weapon_scripts.has(type)`.

`spawn mod [type]` validates against `WeaponRegistry.modifier_scripts.has(type)`.

---

## Command Implementations

### `spawn weapon [type]`

- Validate type against `WeaponRegistry.weapon_scripts`
- Instantiate `WEAPON_DROP_SCENE`, assign weapon script, add to scene tree, position at `ctx.world_pos`
- Output: `"Spawned [type] weapon"`

### `spawn mod [type]`

- Validate type against `WeaponRegistry.modifier_scripts`
- Instantiate `MODIFIER_DROP_SCENE`, assign modifier script, add to scene tree, position at `ctx.world_pos`
- Output: `"Spawned [type] modifier"`

### `spawn enemy [type]`

- Validate `type` against known set (currently `"dummy"`)
- Instantiate `DUMMY_ENEMY_SCENE`, add to scene tree, position at `ctx.world_pos`
- Output: `"Spawned [type] enemy"`

### `spawn gold [amount?]`

- Parse optional amount arg (default 10)
- Instantiate `GOLD_DROP_SCENE`, set amount, add to scene tree, position at `ctx.world_pos`
- Output: `"Spawned [amount] gold"`

### `spawn_mat [type] [radius?] [density?]`

- Subcommands registered **dynamically at runtime** by iterating `MaterialRegistry.materials`, filtering for `fluid == true`, and registering each `MaterialDef.name.to_lower()` as a leaf subcommand. No fluid material names are hardcoded.
- Validate type against the dynamically registered subcommands
- Parse optional radius arg (default: 5)
- Gas accepts optional density arg (default 200)
- Call `ctx.world_manager.call("place_" + type, ctx.world_pos, radius)` (with density arg for gas)
- Error if `world_manager` is null: `"error: no world manager in scene"`
- Output: `"Placed [type] at mouse"`

### `shop`

- If no player in scene → `"error: no player found"`
- Instantiate `SHOP_UI_SCENE`, create offers using `WeaponRegistry.modifier_scripts` (not hardcoded LavaEmitter), random prices, call `shop.open()`
- Output: `"Opened test shop"`

---

## Edge Cases & Error Handling

| Scenario | Behavior |
|----------|----------|
| Empty input + Enter | No-op |
| Unknown command | `"error: unknown command 'X'"` |
| Partial command with subcommands | `"error: 'spawn weapon' requires a type. Available: a, b, c"` |
| Invalid argument | `"error: unknown type 'X'. Available: a, b, c"` |
| No camera available | `"error: no camera available"` (ctx.world_pos is Vector2.ZERO) |
| No WorldManager in scene | `"error: no world manager in scene"` (for `spawn_mat` and enemy spawns) |
| No player in scene | `"error: no player found"` (for player-dependent commands like `shop`) |
| Console open while dead | Commands still work if player-independent |
| Tab with no partial match on empty param | Show all options in suggestion panel |
| Very long output log | Scrollable RichTextLabel, auto-scroll to bottom |

---

## Migration from input_handler.gd

| Old Input | New Command |
|-----------|-------------|
| Left click → spawn random weapon | `spawn weapon [type]` |
| Right click → place lava radius 5 | `spawn_mat lava 5` |
| Middle click → spawn dummy enemy | `spawn enemy dummy` |
| G key → spawn gold 10 | `spawn gold 10` |
| H key → spawn dummy enemy | `spawn enemy dummy` |
| U key → open test shop | `shop` |

After migration, `input_handler.gd` will have no remaining functionality and will be deleted. The InputHandler node reference in `game.tscn` will be removed.
