# Cheat Command System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace hardcoded debug inputs in `input_handler.gd` with a backtick-toggled cheat console supporting hierarchical commands, tab autocomplete, command history, and dynamic type discovery via registries.

**Architecture:** A `ConsoleManager` autoload (CanvasLayer) provides the console UI overlay (LineEdit input, RichTextLabel output, suggestion panel). `CommandRegistry` manages a tree of `ConsoleCommand` nodes, populated by command files. Types are queried dynamically from `WeaponRegistry` (auto-generated) and `MaterialRegistry` (existing).

**Tech Stack:** Godot 4.6 GDScript, bash for code generation

---

## File Map

| File | Responsibility |
|------|---------------|
| `src/console/console_command.gd` | Base `RefCounted` command tree node (name, description, subcommands, execute) |
| `src/console/command_registry.gd` | Root command tree, `register()`, `parse()`, `get_suggestions()` |
| `src/autoload/console_manager.gd` | Autoload CanvasLayer — UI, input capture, history, autocomplete, context building, execution |
| `src/console/commands/spawn_command.gd` | `spawn weapon/mod/enemy/gold` registration |
| `src/console/commands/spawn_mat_command.gd` | `spawn_mat` dynamic fluid material subcommand registration |
| `src/console/commands/shop_command.gd` | `shop` command registration |
| `tools/generate_weapon_registry.sh` | Shell script: scans `src/weapons/` for weapon/modifier scripts, generates registry |
| `src/autoload/weapon_registry.gd` | **Generated** — centralized weapon/modifier script dictionaries |
| `src/input/input_handler.gd` | **Deleted** — all debug functionality migrated to commands |
| `scenes/game.tscn` | **Modified** — remove InputHandler node reference |
| `project.godot` | **Modified** — add `ConsoleManager` and `WeaponRegistry` to autoload |

---

### Task 1: Create `src/console/` directory structure

**Files:**
- Create: `src/console/` (directory)
- Create: `src/console/commands/` (directory)

- [ ] **Step 1: Create directories**

```bash
mkdir -p src/console/commands
```

---

### Task 2: ConsoleCommand base class

**Files:**
- Create: `src/console/console_command.gd`

- [ ] **Step 1: Write ConsoleCommand**

```gdscript
class_name ConsoleCommand
extends RefCounted

var name: String
var description: String
var subcommands: Dictionary = {}  # String -> ConsoleCommand
var execute: Callable              # func(args: Array[String], ctx: Dictionary) -> String
```

- [ ] **Step 2: Commit**

```bash
git add src/console/console_command.gd
git commit -m "feat: add ConsoleCommand base class"
```

---

### Task 3: CommandRegistry — tree management, parsing, suggestions

**Files:**
- Create: `src/console/command_registry.gd`

- [ ] **Step 1: Write CommandRegistry**

```gdscript
class_name CommandRegistry
extends RefCounted

var root: ConsoleCommand


func _init() -> void:
	root = ConsoleCommand.new()
	root.name = ""


func register(path: String, description: String, execute: Callable) -> ConsoleCommand:
	var parts := path.split(" ")
	var current := root
	for i in range(parts.size() - 1):
		var part := parts[i]
		if not current.subcommands.has(part):
			var cmd := ConsoleCommand.new()
			cmd.name = part
			current.subcommands[part] = cmd
		current = current.subcommands[part]
	var leaf_name := parts[-1]
	var leaf := ConsoleCommand.new()
	leaf.name = leaf_name
	leaf.description = description
	leaf.execute = execute
	current.subcommands[leaf_name] = leaf
	return leaf


func parse(input: String) -> Dictionary:
	# Returns { "command": ConsoleCommand|null, "args": Array[String], "error": String }
	var parts := input.strip_edges().split(" ", false)
	if parts.is_empty():
		return {"command": null, "args": [], "error": ""}

	var current := root
	var consumed := 0
	for i in range(parts.size()):
		var token := parts[i]
		if current.subcommands.has(token):
			current = current.subcommands[token]
			consumed += 1
		else:
			# Token not a subcommand — might be an arg for a leaf we already reached
			break

	if current.subcommands.is_empty():
		# Leaf node reached — remaining tokens are args
		var remaining: Array[String] = []
		for j in range(consumed, parts.size()):
			remaining.append(parts[j])
		return {"command": current, "args": remaining, "error": ""}

	if consumed < parts.size():
		# Unconsumed tokens remain but current node has subcommands — unknown
		return {"command": null, "args": [], "error": "unknown command '" + input.strip_edges() + "'"}

	# All tokens consumed but current node has subcommands — incomplete
	return {"command": null, "args": [], "error": "incomplete: '" + input.strip_edges() + "' requires more arguments. Available: " + ", ".join(current.subcommands.keys())}


func get_suggestions(input: String, cursor_pos: int) -> Array[String]:
	# Walk the command tree to find the node at the current input position,
	# then return its subcommand names as autocomplete suggestions.
	var before_cursor := input.substr(0, cursor_pos)
	var parts := before_cursor.split(" ")
	if parts.is_empty():
		return root.subcommands.keys()

	var current := root
	var suggestions_node: ConsoleCommand = root

	for i in range(parts.size()):
		var token := parts[i]
		if current.subcommands.has(token):
			current = current.subcommands[token]
			suggestions_node = current
		else:
			# Partial match on the last token — filter subcommands of current node
			var matches: Array[String] = []
			for key in current.subcommands:
				if key.begins_with(token):
					matches.append(key)
			return matches

	# We completed all tokens — show subcommands of the current node
	return suggestions_node.subcommands.keys()
```

- [ ] **Step 2: Commit**

```bash
git add src/console/command_registry.gd
git commit -m "feat: add CommandRegistry with tree parse and suggestions"
```

---

### Task 4: WeaponRegistry generation script

**Files:**
- Create: `tools/generate_weapon_registry.sh`

- [ ] **Step 1: Write the generation script**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WEAPONS_DIR="$PROJECT_ROOT/src/weapons"
OUTPUT="$PROJECT_ROOT/src/autoload/weapon_registry.gd"

echo "# Auto-generated by tools/generate_weapon_registry.sh — DO NOT EDIT" > "$OUTPUT"
echo "extends Node" >> "$OUTPUT"
echo "" >> "$OUTPUT"
echo "var weapon_scripts: Dictionary = {}" >> "$OUTPUT"
echo "var modifier_scripts: Dictionary = {}" >> "$OUTPUT"
echo "" >> "$OUTPUT"

declare -a WEAPON_LINES=()
declare -a MODIFIER_LINES=()

while IFS= read -r -d '' file; do
    rel="${file#$PROJECT_ROOT/}"
    class_line=$(head -5 "$file" | grep -m1 "^extends " || true)
    base=$(basename "$file" .gd)

    # Derive key: strip trailing _weapon / _modifier suffix
    key="$base"
    key="${key%_weapon}"
    key="${key%_modifier}"

    if echo "$class_line" | grep -q "extends Weapon"; then
        WEAPON_LINES+=("	weapon_scripts[\"$key\"] = preload(\"res://$rel\")")
    elif echo "$class_line" | grep -q "extends Modifier"; then
        MODIFIER_LINES+=("	modifier_scripts[\"$key\"] = preload(\"res://$rel\")")
    fi
done < <(find "$WEAPONS_DIR" -name "*.gd" -print0)

echo "func _ready() -> void:" >> "$OUTPUT"
for line in "${WEAPON_LINES[@]}"; do
    echo "$line" >> "$OUTPUT"
done
for line in "${MODIFIER_LINES[@]}"; do
    echo "$line" >> "$OUTPUT"
done

echo "Generated $OUTPUT with ${#WEAPON_LINES[@]} weapons and ${#MODIFIER_LINES[@]} modifiers."
```

- [ ] **Step 2: Make executable and run**

```bash
chmod +x tools/generate_weapon_registry.sh
bash tools/generate_weapon_registry.sh
```

- [ ] **Step 3: Verify generated output**

Read `src/autoload/weapon_registry.gd` and confirm it contains:
- `weapon_scripts["melee"]` and `weapon_scripts["test"]`
- `modifier_scripts["lava_emitter"]`

- [ ] **Step 4: Commit**

```bash
git add tools/generate_weapon_registry.sh src/autoload/weapon_registry.gd
git commit -m "feat: add WeaponRegistry autoload with auto-generation script"
```

---

### Task 5: Spawn commands (`spawn weapon`, `spawn mod`, `spawn enemy`, `spawn gold`)

**Files:**
- Create: `src/console/commands/spawn_command.gd`

- [ ] **Step 1: Write spawn command file**

```gdscript
extends RefCounted

const WEAPON_DROP_SCENE := preload("res://scenes/weapon_drop.tscn")
const MODIFIER_DROP_SCENE := preload("res://scenes/modifier_drop.tscn")
const GOLD_DROP_SCENE := preload("res://scenes/gold_drop.tscn")
const DUMMY_ENEMY_SCENE := preload("res://scenes/dummy_enemy.tscn")


static func register(registry: CommandRegistry) -> void:
	for key in WeaponRegistry.weapon_scripts:
		var type := key
		registry.register("spawn weapon " + type, "Spawn a " + type + " weapon drop", _spawn_weapon.bind(type))

	for key in WeaponRegistry.modifier_scripts:
		var type := key
		registry.register("spawn mod " + type, "Spawn a " + type + " modifier drop", _spawn_mod.bind(type))

	registry.register("spawn enemy dummy", "Spawn a dummy enemy", _spawn_enemy)
	registry.register("spawn gold", "Spawn a gold drop (default 10)", _spawn_gold)


static func _spawn_weapon(type: String, _args: Array[String], ctx: Dictionary) -> String:
	var script: GDScript = WeaponRegistry.weapon_scripts.get(type)
	if script == null:
		return "error: unknown weapon type '" + type + "'"
	var scene := ctx.get("scene")
	if scene == null:
		return "error: no scene available"
	var drop: WeaponDrop = WEAPON_DROP_SCENE.instantiate()
	drop.weapon = script.new()
	scene.add_child(drop)
	drop.global_position = ctx.get("world_pos", Vector2.ZERO)
	return "Spawned " + type + " weapon"


static func _spawn_mod(type: String, _args: Array[String], ctx: Dictionary) -> String:
	var script: GDScript = WeaponRegistry.modifier_scripts.get(type)
	if script == null:
		return "error: unknown modifier type '" + type + "'"
	var scene := ctx.get("scene")
	if scene == null:
		return "error: no scene available"
	var drop: ModifierDrop = MODIFIER_DROP_SCENE.instantiate()
	drop.modifier = script.new()
	scene.add_child(drop)
	drop.global_position = ctx.get("world_pos", Vector2.ZERO)
	return "Spawned " + type + " modifier"


static func _spawn_enemy(_args: Array[String], ctx: Dictionary) -> String:
	var scene := ctx.get("scene")
	if scene == null:
		return "error: no scene available"
	var enemy: CharacterBody2D = DUMMY_ENEMY_SCENE.instantiate()
	scene.add_child(enemy)
	enemy.global_position = ctx.get("world_pos", Vector2.ZERO)
	return "Spawned dummy enemy"


static func _spawn_gold(args: Array[String], ctx: Dictionary) -> String:
	var amount := 10
	if args.size() > 0 and args[0].is_valid_int():
		amount = args[0].to_int()
	var scene := ctx.get("scene")
	if scene == null:
		return "error: no scene available"
	var drop: GoldDrop = GOLD_DROP_SCENE.instantiate()
	drop.set_amount(amount)
	scene.add_child(drop)
	drop.global_position = ctx.get("world_pos", Vector2.ZERO)
	return "Spawned " + str(amount) + " gold"
```

- [ ] **Step 2: Commit**

```bash
git add src/console/commands/spawn_command.gd
git commit -m "feat: add spawn weapon/mod/enemy/gold commands"
```

---

### Task 6: SpawnMat command (`spawn_mat [fluid_type] [radius?]`)

**Files:**
- Create: `src/console/commands/spawn_mat_command.gd`

- [ ] **Step 1: Write spawn_mat command file**

```gdscript
extends RefCounted

const DEFAULT_RADIUS: float = 5.0
const GAS_DENSITY: int = 200


static func register(registry: CommandRegistry) -> void:
	for mat in MaterialRegistry.materials:
		if mat.fluid:
			var type := mat.name.to_lower()
			registry.register("spawn_mat " + type, "Place " + type + " at mouse", _spawn_mat.bind(type))


static func _spawn_mat(type: String, args: Array[String], ctx: Dictionary) -> String:
	var world_manager := ctx.get("world_manager")
	if world_manager == null:
		return "error: no world manager in scene"

	var radius: float = DEFAULT_RADIUS
	if args.size() > 0 and args[0].is_valid_float():
		radius = args[0].to_float()

	var density := GAS_DENSITY
	if args.size() > 1 and args[1].is_valid_int():
		density = args[1].to_int()

	var world_pos: Vector2 = ctx.get("world_pos", Vector2.ZERO)

	if type == "gas":
		world_manager.place_gas(world_pos, radius, density)
	else:
		world_manager.call("place_" + type, world_pos, radius)

	return "Placed " + type + " at mouse"
```

- [ ] **Step 2: Commit**

```bash
git add src/console/commands/spawn_mat_command.gd
git commit -m "feat: add spawn_mat command with dynamic fluid registration"
```

---

### Task 7: Shop command

**Files:**
- Create: `src/console/commands/shop_command.gd`

- [ ] **Step 1: Write shop command file**

```gdscript
extends RefCounted

const SHOP_UI_SCENE := preload("res://scenes/economy/shop_ui.tscn")
const ShopOfferScript := preload("res://src/economy/shop_offer.gd")


static func register(registry: CommandRegistry) -> void:
	registry.register("shop", "Open the test shop", _shop)


static func _shop(_args: Array[String], ctx: Dictionary) -> String:
	var player := ctx.get("player")
	if player == null:
		return "error: no player found"
	var scene := ctx.get("scene")
	if scene == null:
		return "error: no scene available"
	var shop: ShopUI = SHOP_UI_SCENE.instantiate()
	scene.add_child(shop)

	var offerings: Array[ShopOffer] = []
	var mod_keys := WeaponRegistry.modifier_scripts.keys()
	var prices: Array[int] = [35, 55, 80]
	prices.shuffle()
	for i in min(mod_keys.size(), 3):
		var script: GDScript = WeaponRegistry.modifier_scripts[mod_keys[i]]
		offerings.append(ShopOfferScript.new(script.new(), prices[i]))
	shop.open(offerings)
	return "Opened test shop"
```

- [ ] **Step 2: Commit**

```bash
git add src/console/commands/shop_command.gd
git commit -m "feat: add shop command"
```

---

### Task 8: ConsoleManager autoload — UI, input, execution

**Files:**
- Create: `src/autoload/console_manager.gd`

- [ ] **Step 1: Write ConsoleManager**

```gdscript
extends CanvasLayer

const OUTPUT_FONT_SIZE := 14
const INPUT_FONT_SIZE := 14
const MAX_HISTORY := 50
const MAX_OUTPUT_LINES := 200

var _registry: CommandRegistry
var _history: Array[String] = []
var _history_index: int = -1
var _console_visible: bool = false

var _panel: PanelContainer
var _output: RichTextLabel
var _suggestions: VBoxContainer
var _input: LineEdit


func _ready() -> void:
	_registry = CommandRegistry.new()
	_register_commands()
	_build_ui()
	_process_mode = PROCESS_MODE_ALWAYS
	hide()


func _register_commands() -> void:
	var SpawnCommands := preload("res://src/console/commands/spawn_command.gd")
	SpawnCommands.register(_registry)
	var SpawnMatCommands := preload("res://src/console/commands/spawn_mat_command.gd")
	SpawnMatCommands.register(_registry)
	var ShopCommands := preload("res://src/console/commands/shop_command.gd")
	ShopCommands.register(_registry)


func _build_ui() -> void:
	layer = 128  # Render above other UI

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 4.0
	_panel.offset_right = -4.0
	_panel.offset_top = -200.0
	_panel.offset_bottom = -4.0
	add_child(_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.75)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_output = RichTextLabel.new()
	_output.add_theme_font_size_override("normal_font_size", OUTPUT_FONT_SIZE)
	_output.add_theme_color_override("default_color", Color.WHITE)
	_output.bbcode_enabled = true
	_output.scroll_following = true
	_output.selection_enabled = true
	_output.context_menu_enabled = false
	_output.fit_content = true
	scroll.add_child(_output)

	_suggestions = VBoxContainer.new()
	vbox.add_child(_suggestions)
	_suggestions.hide()

	_input = LineEdit.new()
	_input.add_theme_font_size_override("font_size", INPUT_FONT_SIZE)
	_input.add_theme_color_override("font_color", Color.WHITE)
	_input.placeholder_text = "Type command... (Tab to autocomplete)"
	_input.add_theme_color_override("placeholder_color", Color(0.5, 0.5, 0.5))
	_input.text_submitted.connect(_on_input_submitted)
	_input.text_changed.connect(_on_text_changed)
	vbox.add_child(_input)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_QUOTELEFT:
			_toggle()
		elif _console_visible:
			match event.keycode:
				KEY_ESCAPE:
					_close()
				KEY_UP:
					_cycle_history(-1)
				KEY_DOWN:
					_cycle_history(1)
				KEY_TAB:
					_autocomplete()
			get_viewport().set_input_as_handled()


func _toggle() -> void:
	if _console_visible:
		_close()
	else:
		_open()


func _open() -> void:
	_console_visible = true
	show()
	_input.clear()
	_input.grab_focus()
	_history_index = _history.size()
	_suggestions.hide()


func _close() -> void:
	_console_visible = false
	hide()
	_input.release_focus()
	_suggestions.hide()


func _on_input_submitted(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		_input.clear()
		return
	_execute(trimmed)
	_history.append(trimmed)
	if _history.size() > MAX_HISTORY:
		_history.pop_front()
	_history_index = _history.size()
	_input.clear()


func _execute(input: String) -> void:
	_append_output("> " + input, Color.GRAY)
	var result := _registry.parse(input)

	if result.error != "":
		var is_incomplete := result.error.begins_with("incomplete:")
		var color := Color(1.0, 0.7, 0.3) if is_incomplete else Color.RED
		_append_output(result.error, color)
		return

	var command: ConsoleCommand = result.command
	if command == null:
		return

	var ctx := _build_context()
	var output := command.execute.call(result.args, ctx)
	if output != "":
		var is_error := output.begins_with("error:")
		_append_output(output, Color.RED if is_error else Color.WHITE)


func _build_context() -> Dictionary:
	var ctx: Dictionary = {}
	var viewport := get_viewport()
	var camera := viewport.get_camera_2d()
	if camera:
		var screen_pos := viewport.get_mouse_position()
		var view_size := viewport.get_visible_rect().size
		ctx["world_pos"] = (screen_pos - view_size * 0.5) / camera.zoom + camera.global_position
	else:
		ctx["world_pos"] = Vector2.ZERO
	ctx["player"] = get_tree().get_first_node_in_group("player")
	ctx["world_manager"] = get_tree().current_scene.get_node_or_null("WorldManager") if get_tree().current_scene else null
	ctx["scene"] = get_tree().current_scene
	return ctx


func _autocomplete() -> void:
	var text := _input.text
	var cursor := _input.caret_column
	var suggestions := _registry.get_suggestions(text, cursor)

	if suggestions.is_empty():
		return

	if suggestions.size() == 1:
		# Single match — replace the current word
		var before := text.substr(0, cursor)
		var after := text.substr(cursor)
		var parts := before.rsplit(" ", true, 1)
		if parts.size() == 1:
			_input.text = suggestions[0] + " " + after
			_input.caret_column = suggestions[0].length() + 1
		else:
			_input.text = parts[0] + " " + suggestions[0] + " " + after
			_input.caret_column = parts[0].length() + 1 + suggestions[0].length() + 1
	else:
		# Multiple matches — show suggestion panel
		_show_suggestions(suggestions)


func _show_suggestions(list: Array[String]) -> void:
	for child in _suggestions.get_children():
		child.queue_free()
	for item in list:
		var label := Label.new()
		label.text = item
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		_suggestions.add_child(label)
	_suggestions.show()


func _on_text_changed(_new_text: String) -> void:
	_suggestions.hide()


func _cycle_history(direction: int) -> void:
	if _history.is_empty():
		return
	_history_index = clampi(_history_index + direction, 0, _history.size())
	if _history_index < _history.size():
		_input.text = _history[_history_index]
		_input.caret_column = _input.text.length()
	else:
		_input.clear()
	_history_index = clampi(_history_index, 0, _history.size())


func _append_output(text: String, color: Color) -> void:
	_output.append_text("[color=#" + color.to_html(false) + "]" + text + "[/color]\n")

	# Enforce output line limit
	if _output.get_paragraph_count() > MAX_OUTPUT_LINES:
		_output.remove_paragraph(0)
```

- [ ] **Step 2: Commit**

```bash
git add src/autoload/console_manager.gd
git commit -m "feat: add ConsoleManager autoload with UI, history, autocomplete"
```

---

### Task 9: Register autoloads in project.godot and remove InputHandler

**Files:**
- Modify: `project.godot`
- Modify: `scenes/game.tscn`

- [ ] **Step 1: Add autoloads to project.godot**

In `project.godot`, change the `[autoload]` section from:
```
MaterialRegistry="*res://src/autoload/material_registry.gd"
SceneManager="*res://src/autoload/scene_manager.gd"
```
to:
```
MaterialRegistry="*res://src/autoload/material_registry.gd"
SceneManager="*res://src/autoload/scene_manager.gd"
ConsoleManager="*res://src/autoload/console_manager.gd"
WeaponRegistry="*res://src/autoload/weapon_registry.gd"
```

```gdscript
# Use edit tool:
old: MaterialRegistry="*res://src/autoload/material_registry.gd"
SceneManager="*res://src/autoload/scene_manager.gd"

new: MaterialRegistry="*res://src/autoload/material_registry.gd"
SceneManager="*res://src/autoload/scene_manager.gd"
ConsoleManager="*res://src/autoload/console_manager.gd"
WeaponRegistry="*res://src/autoload/weapon_registry.gd"
```

- [ ] **Step 2: Remove InputHandler node from game.tscn**

In `scenes/game.tscn`, remove the `[ext_resource]` line for InputHandler:
```
[ext_resource type="Script" uid="uid://crukmd5fv0uvt" path="res://src/input/input_handler.gd" id="3"]
```

Remove the InputHandler node reference line:
```
[node name="InputHandler" type="Node" parent="." unique_id=924507179]
```

- [ ] **Step 3: Delete input_handler.gd**

```bash
rm src/input/input_handler.gd
```

- [ ] **Step 4: Commit**

```bash
git add project.godot scenes/game.tscn
git rm src/input/input_handler.gd
git commit -m "feat: register autoloads, remove migrated InputHandler"
```

---

### Task 10: Verification

- [ ] **Step 1: Verify the project opens in Godot without errors**

Open the project in Godot editor. Check the Output panel for any script errors or autoload errors. Expected: clean startup with no new errors.

- [ ] **Step 2: Launch the game scene and test commands**

Run the game scene (`scenes/game.tscn`) and test each command:

| Command | Expected Result |
|---------|----------------|
| `` ` `` (backtick) | Console opens at bottom of screen |
| `spawn weapon melee` | Melee weapon drop appears at mouse position |
| `spawn mod lava_emitter` | Lava emitter modifier drop appears at mouse |
| `spawn enemy dummy` | Dummy enemy appears at mouse |
| `spawn gold 50` | Gold drop (amount 50) appears at mouse |
| `spawn_mat lava 5` | Lava placed at mouse position |
| `spawn_mat gas 10 300` | Gas placed at mouse (radius 10, density 300) |
| `shop` | Test shop UI opens |
| `spam` | Red error: "unknown command 'spam'" |
| `spawn weapon` | Orange warning: incomplete, shows available types |
| Tab (partial match) | Autocompletes word |
| Tab (empty param) | Shows suggestion panel with available subcommands |
| Up/Down arrow | Cycles command history |
| Escape | Closes console |

- [ ] **Step 3: Verify old debug keys no longer work**

Confirm that left-click, right-click, middle-click, G, H, U keys do NOT spawn anything in the game scene.

- [ ] **Step 4: Commit any final tweaks**

```bash
git add -A
git commit -m "chore: final verification tweaks for cheat console"
```
