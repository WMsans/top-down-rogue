# Juicy UI Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every modal UI panel open/close with the same juicy "drop-in with weight" feel via a shared `JuicyPanel` base class, with content stagger and a unified backdrop.

**Architecture:** A new `JuicyPanel` (extends `Control`) provides `open()`/`close()` plus inspector-configurable backdrop, drop animation, and content stagger. Each existing panel script changes its `extends` line to `JuicyPanel` and removes its hand-rolled show/hide animation. An `animated_root: NodePath` export accommodates panels where the visual element being moved is an inner node (the common case in this codebase).

**Tech Stack:** Godot 4 (GDScript), `Tween` with `TRANS_BACK`/`TRANS_ELASTIC`/`TRANS_CUBIC`, existing `UiAnimations` helpers.

**Spec:** `docs/superpowers/specs/2026-05-11-juicy-ui-refactor-design.md`

**Testing model:** This is feel work in a Godot project with no automated UI tests. Every task ends with a manual smoke test (launch the editor, exercise the panel, observe). Be ruthless about reverting if a feel regression appears — animation values are tuned, not derived.

---

## File Structure

**New files:**
- `src/ui/juicy_panel.gd` — base class, ~180 lines target. Single responsibility: open/close animation + backdrop + content stagger.

**Modified files (each loses hand-rolled show/hide, changes `extends`):**
- `src/ui/settings_popup.gd`
- `src/ui/pause_menu.gd` (script stays on `CanvasLayer`; the inner `PauseCard` and `ConfirmationPanel` get `JuicyPanel` scripts attached in their scenes)
- `src/ui/chest_ui.gd` (same pattern — `CanvasLayer` wrapper, inner `ShopPanel` becomes `JuicyPanel`)
- `src/ui/death_screen.gd`
- `src/ui/weapon_popup.gd`
- `src/ui/main_menu.gd` (decide during Task 11)

**Modified scenes:**
- `scenes/ui/settings_popup.tscn`, `scenes/ui/pause_menu.tscn`, `scenes/ui/chest_ui.tscn`, `scenes/ui/death_screen.tscn`, `scenes/ui/weapon_popup.tscn` — set inspector exports on the `JuicyPanel` root(s); remove now-orphaned `Dimmer` nodes or rename to `_Backdrop`.

**Untouched:**
- `src/ui/card.gd`, `src/ui/currency_hud.gd`, `src/ui/health_ui.gd`, `src/ui/weapon_button.gd`, `src/ui/ui_theme.gd`, `src/ui/ui_animations.gd` (public API).

---

## Task 1: Scaffold `JuicyPanel` with exports, signals, state

**Files:**
- Create: `src/ui/juicy_panel.gd`

- [ ] **Step 1: Write the file skeleton**

```gdscript
class_name JuicyPanel
extends Control

signal opened
signal closed

@export var has_backdrop: bool = true
@export var backdrop_color: Color = Color(0, 0, 0, 0.55)
@export var close_on_backdrop_click: bool = true
@export var content_root: NodePath = NodePath("")
@export var animated_root: NodePath = NodePath("")
@export var drop_distance: float = 80.0
@export var enter_duration: float = 0.45
@export var exit_duration: float = 0.35
@export var stagger_delay: float = 0.05

var _is_open: bool = false
var _is_animating: bool = false
var _rest_position: Vector2 = Vector2.ZERO
var _animated_node: Control = null
var _content_node: Node = null
var _content_rest_positions: Dictionary = {}
var _backdrop: ColorRect = null
var _open_tween: Tween = null
var _close_tween: Tween = null
var _original_mouse_filter: int = MOUSE_FILTER_STOP

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_original_mouse_filter = mouse_filter
	_resolve_nodes()
	_update_pivot()
	resized.connect(_update_pivot)
	if _animated_node:
		_rest_position = _animated_node.position
	visible = false
	_is_open = false

func _resolve_nodes() -> void:
	if animated_root.is_empty():
		_animated_node = self
	else:
		_animated_node = get_node_or_null(animated_root) as Control
		if _animated_node == null:
			push_warning("JuicyPanel: animated_root resolved to null; falling back to self.")
			_animated_node = self
	if not content_root.is_empty():
		_content_node = get_node_or_null(content_root)

func _update_pivot() -> void:
	if _animated_node:
		_animated_node.pivot_offset = _animated_node.size * 0.5

func open() -> void:
	pass # implemented in Task 2

func close() -> void:
	pass # implemented in Task 3
```

- [ ] **Step 2: Verify the script compiles**

Open Godot editor. Confirm no parse errors in the Output panel for `src/ui/juicy_panel.gd`. The class should appear in the "Inherits" search when creating a new script.

- [ ] **Step 3: Commit**

```bash
git add src/ui/juicy_panel.gd
git commit -m "feat: scaffold JuicyPanel base class with exports and state"
```

---

## Task 2: Implement `open()` animation (without backdrop or stagger)

**Files:**
- Modify: `src/ui/juicy_panel.gd`

- [ ] **Step 1: Replace the `open()` stub**

```gdscript
func open() -> void:
	if _is_open and not _is_animating:
		return
	if _is_animating and _open_tween and _open_tween.is_running():
		return
	if _close_tween and _close_tween.is_running():
		_close_tween.kill()
		_close_tween = null
	_is_open = true
	_is_animating = true
	visible = true
	mouse_filter = MOUSE_FILTER_IGNORE
	_prepare_open_state()
	_open_tween = create_tween()
	_open_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_open_tween.set_parallel(true)
	var target_pos := _rest_position
	_open_tween.tween_property(_animated_node, "position:y", target_pos.y, enter_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_open_tween.tween_property(_animated_node, "modulate:a", 1.0, enter_duration * 0.4).set_trans(Tween.TRANS_LINEAR)
	_open_tween.tween_property(_animated_node, "scale", Vector2.ONE, enter_duration * 0.9).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_open_tween.finished.connect(_on_open_finished, CONNECT_ONE_SHOT)

func _prepare_open_state() -> void:
	if _animated_node == null:
		return
	if _rest_position == Vector2.ZERO:
		_rest_position = _animated_node.position
	_animated_node.position = _rest_position - Vector2(0, drop_distance)
	_animated_node.modulate.a = 0.0
	_animated_node.scale = Vector2(0.96, 1.04)
	_update_pivot()

func _on_open_finished() -> void:
	_is_animating = false
	mouse_filter = _original_mouse_filter
	opened.emit()
```

- [ ] **Step 2: Manual smoke test**

Create a temporary throwaway scene to test in isolation:
- Make a new scene, root `Control`, attach `juicy_panel.gd` as script.
- Add a `PanelContainer` child with some sized content (just a Label is fine), set its `custom_minimum_size = (300, 200)`, anchor centered.
- In the editor, set the `JuicyPanel` root's `animated_root` export to point to the `PanelContainer`.
- Add a Button to the scene that calls `open()` in its `pressed` handler.
- Run scene. Click button. Observe: panel drops from above, lands with elastic settle, fades in. No backdrop yet (next task adds it).

Tune `enter_duration` / `drop_distance` only if the motion feels broken, not just to taste — that's per-panel later.

- [ ] **Step 3: Commit**

```bash
git add src/ui/juicy_panel.gd
git commit -m "feat: implement JuicyPanel open() drop-in animation"
```

---

## Task 3: Implement `close()` animation

**Files:**
- Modify: `src/ui/juicy_panel.gd`

- [ ] **Step 1: Replace the `close()` stub**

```gdscript
func close() -> void:
	if not _is_open and not _is_animating:
		return
	if _is_animating and _close_tween and _close_tween.is_running():
		return
	if _open_tween and _open_tween.is_running():
		_open_tween.kill()
		_open_tween = null
	_is_open = false
	_is_animating = true
	mouse_filter = MOUSE_FILTER_IGNORE
	_close_tween = create_tween()
	_close_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_close_tween.tween_interval(0.05)
	_close_tween.set_parallel(true)
	var fall_y := _rest_position.y + drop_distance
	_close_tween.tween_property(_animated_node, "position:y", fall_y, exit_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_close_tween.tween_property(_animated_node, "scale", Vector2(1.02, 0.94), exit_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_close_tween.chain().tween_interval(exit_duration * 0.4)
	_close_tween.tween_property(_animated_node, "modulate:a", 0.0, exit_duration * 0.6).set_trans(Tween.TRANS_LINEAR)
	_close_tween.finished.connect(_on_close_finished, CONNECT_ONE_SHOT)

func _on_close_finished() -> void:
	_is_animating = false
	visible = false
	mouse_filter = _original_mouse_filter
	if _animated_node:
		_animated_node.position = _rest_position
		_animated_node.scale = Vector2.ONE
		_animated_node.modulate.a = 1.0
	closed.emit()
```

- [ ] **Step 2: Manual smoke test**

Reuse the throwaway scene from Task 2. Add a second button that calls `close()`. Verify:
- Panel falls downward, fading out as it falls.
- Final state: panel `visible = false`.
- Click open again — panel re-opens cleanly from the top, no stuck state.
- Spam open/close rapidly — no flicker, panel ends in a sensible state (either fully open or fully closed).

- [ ] **Step 3: Commit**

```bash
git add src/ui/juicy_panel.gd
git commit -m "feat: implement JuicyPanel close() drop-out animation"
```

---

## Task 4: Backdrop creation + fade + click-to-close

**Files:**
- Modify: `src/ui/juicy_panel.gd`

- [ ] **Step 1: Add backdrop lifecycle**

Add this method called from `_ready()` after `_resolve_nodes()`:

```gdscript
func _setup_backdrop() -> void:
	if not has_backdrop:
		return
	var existing := get_node_or_null("_Backdrop") as ColorRect
	if existing:
		_backdrop = existing
	else:
		_backdrop = ColorRect.new()
		_backdrop.name = "_Backdrop"
		_backdrop.color = Color(backdrop_color.r, backdrop_color.g, backdrop_color.b, 0.0)
		_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
		_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_backdrop)
		move_child(_backdrop, 0)
	if close_on_backdrop_click:
		if not _backdrop.gui_input.is_connected(_on_backdrop_input):
			_backdrop.gui_input.connect(_on_backdrop_input)

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()
```

In `_ready()`, after `_resolve_nodes()`, add:

```gdscript
	_setup_backdrop()
```

- [ ] **Step 2: Tween backdrop alpha in `open()` and `close()`**

In `open()`, after `_open_tween.set_parallel(true)` and before the existing tweens, add:

```gdscript
	if _backdrop:
		_open_tween.tween_property(_backdrop, "color:a", backdrop_color.a, 0.18).set_trans(Tween.TRANS_LINEAR)
```

In `_prepare_open_state()`, before `_update_pivot()`, add:

```gdscript
	if _backdrop:
		_backdrop.color.a = 0.0
```

In `close()`, after `_close_tween.set_parallel(true)` and before the existing tweens, add:

```gdscript
	if _backdrop:
		_close_tween.tween_property(_backdrop, "color:a", 0.0, 0.18).set_trans(Tween.TRANS_LINEAR)
```

- [ ] **Step 3: Manual smoke test**

Reuse the throwaway scene. The `_Backdrop` child should auto-appear at runtime. Open: backdrop dims to ~55% alpha behind the panel. Click backdrop: panel closes. Close button: backdrop fades out together with panel.

Edge case: set `has_backdrop = false` in the inspector → no backdrop appears, no error. Set `close_on_backdrop_click = false` → backdrop appears but clicking it does nothing.

- [ ] **Step 4: Commit**

```bash
git add src/ui/juicy_panel.gd
git commit -m "feat: add JuicyPanel backdrop with fade and click-to-close"
```

---

## Task 5: Content stagger

**Files:**
- Modify: `src/ui/juicy_panel.gd`

- [ ] **Step 1: Add stagger methods**

Add these methods to `juicy_panel.gd`:

```gdscript
func _get_content_children() -> Array[Control]:
	var out: Array[Control] = []
	if _content_node == null:
		return out
	for child in _content_node.get_children():
		var c := child as Control
		if c:
			out.append(c)
	return out

func _cache_content_positions() -> void:
	_content_rest_positions.clear()
	for child in _get_content_children():
		_content_rest_positions[child] = child.position

func _prepare_content_for_stagger() -> void:
	for child in _get_content_children():
		child.modulate.a = 0.0
		var rest: Vector2 = _content_rest_positions.get(child, child.position)
		child.position = rest + Vector2(0, 12)

func _stagger_in_content() -> void:
	var children := _get_content_children()
	for i in children.size():
		var child := children[i]
		var rest: Vector2 = _content_rest_positions.get(child, child.position)
		var tw := create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_interval(i * stagger_delay)
		tw.set_parallel(true)
		tw.tween_property(child, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_LINEAR)
		tw.tween_property(child, "position:y", rest.y, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _fade_out_content() -> void:
	for child in _get_content_children():
		var tw := create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(child, "modulate:a", 0.0, 0.12).set_trans(Tween.TRANS_LINEAR)
```

- [ ] **Step 2: Wire stagger into `open()`**

In `open()`, replace the `_prepare_open_state()` call site with:

```gdscript
	_cache_content_positions()
	_prepare_open_state()
	_prepare_content_for_stagger()
```

After `_open_tween.finished.connect(...)`, add (before the function ends):

```gdscript
	if _content_node:
		var stagger_delay_total := enter_duration * 0.6
		var delay_tween := create_tween()
		delay_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		delay_tween.tween_interval(stagger_delay_total)
		delay_tween.tween_callback(_stagger_in_content)
```

- [ ] **Step 3: Wire content fade into `close()`**

At the very start of `close()`, before any tween setup but after the early-return guards, add:

```gdscript
	_fade_out_content()
```

- [ ] **Step 4: Restore content positions on close-finish**

In `_on_close_finished()`, before `closed.emit()`, add:

```gdscript
	for child in _get_content_children():
		if _content_rest_positions.has(child):
			child.position = _content_rest_positions[child]
		child.modulate.a = 1.0
```

- [ ] **Step 5: Manual smoke test**

Reuse the throwaway scene. Add a `VBoxContainer` named `Content` inside the `PanelContainer`, with 3–5 Label children. Set `content_root` export on the JuicyPanel root to point to that `Content` VBox.

Open: panel lands, then children fade and rise into place one after another. Close: children all fade out fast (no positional motion), then panel drops. Re-open: positions are clean.

Try also: `content_root` empty → no stagger, panel just drops. No errors.

- [ ] **Step 6: Commit**

```bash
git add src/ui/juicy_panel.gd
git commit -m "feat: add JuicyPanel content stagger animation"
```

---

## Task 6: Migrate `settings_popup`

**Files:**
- Modify: `src/ui/settings_popup.gd`
- Modify: `scenes/ui/settings_popup.tscn` (inspector edits)

- [ ] **Step 1: Change `extends` and remove hand-rolled animation**

Open `src/ui/settings_popup.gd`. Replace lines 1–6:

```gdscript
extends JuicyPanel

const _UiTheme = preload("res://src/ui/ui_theme.gd")
const _UiAnimations = preload("res://src/ui/ui_animations.gd")
```

Remove the local `signal closed` declaration (the base class provides it).

Replace the entire existing `open()` function (lines 62–73) with:

```gdscript
func open() -> void:
	_apply_loaded_settings()
	super.open()
	back_button.grab_focus()
```

Replace the existing `close()` function (lines 76–82) with:

```gdscript
func close() -> void:
	_save_settings()
	_rebinding_action = ""
	_rebinding_label = null
	super.close()
```

Delete the `@onready var dimmer: ColorRect = %Dimmer` line — `JuicyPanel` manages the backdrop now.

- [ ] **Step 2: Update the scene**

Open `scenes/ui/settings_popup.tscn` in the Godot editor.
- Select the root `Control` node.
- In the Inspector, find the JuicyPanel exports (now visible because the script extends `JuicyPanel`).
- Set `animated_root` to the path of the inner `Panel` (`PanelContainer`).
- Set `content_root` to the inner VBox that holds the actual settings rows (look for `VBoxContainer/ScrollContainer/Content` — the same path the existing `_style_section_headers` uses).
- Confirm `has_backdrop = true`, `close_on_backdrop_click = true`.
- Delete the existing `Dimmer` ColorRect node (or rename it to `_Backdrop` if you want to preserve any customization — but the auto-created backdrop is fine for now).
- Save the scene.

- [ ] **Step 3: Manual smoke test**

Run the game. Pause → Settings. Verify:
- Panel drops in with elastic landing.
- Settings rows stagger in after panel lands.
- Backdrop dims behind it.
- Click backdrop: panel closes with downward fall.
- Esc key still closes (handled by `pause_menu`'s `_unhandled_input` calling `settings_popup.close()`).
- Settings still save on close, sliders/keybinds still work.

- [ ] **Step 4: Commit**

```bash
git add src/ui/settings_popup.gd scenes/ui/settings_popup.tscn
git commit -m "refactor: migrate settings_popup to JuicyPanel"
```

---

## Task 7: Migrate `pause_menu` (PauseCard + ConfirmationPanel)

**Files:**
- Modify: `src/ui/pause_menu.gd`
- Modify: `scenes/ui/pause_menu.tscn`

`pause_menu.gd` is on a `CanvasLayer`, so it does not become a `JuicyPanel` itself. Instead, the inner `PausePanel` (containing `PauseCard`) and the `ConfirmationPanel` each become `JuicyPanel`s.

- [ ] **Step 1: Attach `JuicyPanel` to the inner panels in the scene**

Open `scenes/ui/pause_menu.tscn`.

For `PausePanel` (the Control that wraps the pause card):
- Confirm its node type is `Control` (or change to `Control` if it's something compatible).
- Attach script `res://src/ui/juicy_panel.gd` to it via Inspector → Script.
- In Inspector exports:
  - `animated_root` → path to `PauseCard` (the inner `PanelContainer`).
  - `content_root` → path to the VBox inside `PauseCard` that holds the buttons (the immediate parent of `ResumeButton`/`SettingsButton`/`MainMenuButton`).
  - `has_backdrop = true`.
- Delete the existing `Dimmer` ColorRect node under `PausePanel` (JuicyPanel creates `_Backdrop` automatically).

For `ConfirmationPanel`:
- Attach `res://src/ui/juicy_panel.gd`.
- `animated_root` → path to its inner panel container (whatever wraps the Yes/No buttons).
- `content_root` → the container holding the buttons.
- `has_backdrop = true`, `close_on_backdrop_click = false` (we want explicit Yes/No, not backdrop dismiss).

Save scene.

- [ ] **Step 2: Update `pause_menu.gd` to use `open()`/`close()`**

Open `src/ui/pause_menu.gd`. Change the type of `pause_panel` and `confirmation_panel` (no code change needed if you keep `Control`, but functionally these are now `JuicyPanel`).

Remove the `_show_pause()` function's hand-rolled animation (lines 62–75) and replace with:

```gdscript
func _show_pause() -> void:
	visible = true
	SceneManager.set_paused(true)
	pause_panel.open()
	_focus_first_button()
```

Replace `_resume_game()` (lines 78–81) with:

```gdscript
func _resume_game() -> void:
	pause_panel.close()
	await pause_panel.closed
	visible = false
	SceneManager.set_paused(false)
```

Replace `_on_main_menu_pressed()` (lines 92–94) with:

```gdscript
func _on_main_menu_pressed() -> void:
	confirmation_panel.open()
	confirm_no_button.grab_focus()
```

Replace `_on_confirm_yes()` (lines 97–101) with:

```gdscript
func _on_confirm_yes() -> void:
	SceneManager.set_paused(false)
	confirmation_panel.close()
	pause_panel.close()
	await pause_panel.closed
	visible = false
	SceneManager.go_to_main_menu()
```

Replace `_on_confirm_no()` (lines 104–106) with:

```gdscript
func _on_confirm_no() -> void:
	confirmation_panel.close()
	_focus_first_button()
```

Update `_unhandled_input` (line 43–44) — replace `confirmation_panel.visible = false` with `confirmation_panel.close()`. Replace the `settings_popup.visible` check with `settings_popup._is_open` or keep `.visible` (works because JuicyPanel sets visible during open).

Remove the `@onready var dimmer: ColorRect = %Dimmer` line — no longer exists.

In `_ready()` remove `confirmation_panel.visible = false` and `pause_panel.visible = false` (JuicyPanel handles initial visibility).

- [ ] **Step 3: Manual smoke test**

Run the game. Press Esc:
- Pause menu drops in, dim fades, buttons stagger.
- Esc again: pause menu drops out, dim fades, game resumes.
- Main Menu button: confirmation panel drops in over the pause panel.
- No on confirmation: confirmation drops out.
- Yes: confirmation closes, pause closes, scene changes to main menu.
- Settings still opens correctly from pause menu.

- [ ] **Step 4: Commit**

```bash
git add src/ui/pause_menu.gd scenes/ui/pause_menu.tscn
git commit -m "refactor: migrate pause_menu inner panels to JuicyPanel"
```

---

## Task 8: Migrate `chest_ui`

**Files:**
- Modify: `src/ui/chest_ui.gd`
- Modify: `scenes/ui/chest_ui.tscn`

`chest_ui.gd` is a `CanvasLayer`. Same approach as pause_menu: the inner `ShopPanel` becomes a `JuicyPanel`.

- [ ] **Step 1: Attach `JuicyPanel` to `ShopPanel` in the scene**

Open `scenes/ui/chest_ui.tscn`.
- Attach `res://src/ui/juicy_panel.gd` to the `ShopPanel` node.
- Inspector exports:
  - `animated_root` → path to `ShopPanel` itself (or whatever inner panel container holds the visual). If `ShopPanel` IS the visual panel, set `animated_root` empty (defaults to self).
  - `content_root` → path to `CardContainer` (the `HBoxContainer` holding the card slots). Cards stagger in is the killer feature here.
  - `has_backdrop = true`, `close_on_backdrop_click = true`.
- Delete the existing `Overlay` ColorRect (or rename to `_Backdrop`).

Save scene.

- [ ] **Step 2: Update `chest_ui.gd`**

Replace the existing animation code. Replace `open_with_weapons()` (lines 70–78) with:

```gdscript
func open_with_weapons(weapons: Array[Weapon], callback: Callable) -> void:
	_weapons = weapons
	_callback = callback
	_chosen = false
	_title_label.text = "Choose a Weapon"
	_build_cards()
	SceneManager.set_paused(true)
	visible = true
	_panel_container.open()
```

Replace `close()` (lines 81–86) with:

```gdscript
func close() -> void:
	_panel_container.close()
	await _panel_container.closed
	_clear_cards()
	visible = false
	SceneManager.set_paused(false)
	if not _chosen and _callback.is_valid():
		_callback.call(null)
```

Delete the entire `_play_entrance_animation()` function (lines 89–113) — JuicyPanel handles this now via stagger.

Delete the `_overlay.gui_input.connect(_on_overlay_input)` line in `_ready()` (the backdrop handles its own click).
Delete the `_on_overlay_input()` function (lines 163–165).
Delete the `@onready var _overlay: ColorRect = %Overlay` line.

Update `_select_weapon()` (lines 151–161) to use `close()`:

```gdscript
func _select_weapon(index: int) -> void:
	if index < 0 or index >= _weapons.size():
		return
	_chosen = true
	var weapon: Weapon = _weapons[index]
	_panel_container.close()
	await _panel_container.closed
	_clear_cards()
	visible = false
	SceneManager.set_paused(false)
	if _callback.is_valid():
		_callback.call(weapon)
```

- [ ] **Step 3: Manual smoke test**

Trigger a chest in-game. Verify:
- Chest panel drops in.
- Cards stagger in one by one inside the `CardContainer`.
- Hover/click on cards still works (the `Card` script is independent of `JuicyPanel`).
- Skip button closes with drop-out.
- Selecting a weapon closes with drop-out and the callback fires after the close animation.
- Esc closes too (still handled by `_unhandled_input`).

- [ ] **Step 4: Commit**

```bash
git add src/ui/chest_ui.gd scenes/ui/chest_ui.tscn
git commit -m "refactor: migrate chest_ui to JuicyPanel with card stagger"
```

---

## Task 9: Migrate `death_screen`

**Files:**
- Modify: `src/ui/death_screen.gd`
- Modify: `scenes/ui/death_screen.tscn`

- [ ] **Step 1: Read the current file to understand its structure**

```bash
cat src/ui/death_screen.gd
```

Identify the existing show/hide entry point and any current animation code. Look for: `show()`, `appear()`, `display()`, calls to `tween_property`, manual `visible =` toggles.

- [ ] **Step 2: Change `extends` and route through JuicyPanel**

If the root extends `Control` directly, change to `extends JuicyPanel`. If it's a `CanvasLayer` wrapping a Control, do the same inner-panel pattern as `chest_ui` (Task 8).

Replace the existing public "show" function so it calls `super.open()` or the inner panel's `open()`, and any "hide" function so it calls `close()`. Remove inline tweens that animate `modulate` or `position` for show/hide.

- [ ] **Step 3: Update the scene**

In `scenes/ui/death_screen.tscn`:
- Set `animated_root` to the visible panel.
- Set `content_root` to the container holding death-screen rows (title, buttons).
- `has_backdrop = true`. Consider raising `backdrop_color.a` to ~0.75 since death screens typically want a heavier dim.
- `close_on_backdrop_click = false` (death screen shouldn't be dismissable by background click — only via its explicit buttons).
- Delete or rename any existing backdrop node.

- [ ] **Step 4: Manual smoke test**

Trigger player death in-game. Verify:
- Death screen drops in with heavier dim.
- Buttons stagger in.
- Buttons (Restart / Main Menu / whatever exists) still work.
- No click-through to the now-frozen gameplay.

- [ ] **Step 5: Commit**

```bash
git add src/ui/death_screen.gd scenes/ui/death_screen.tscn
git commit -m "refactor: migrate death_screen to JuicyPanel"
```

---

## Task 10: Migrate `weapon_popup`

**Files:**
- Modify: `src/ui/weapon_popup.gd`
- Modify: `scenes/ui/weapon_popup.tscn`

`weapon_popup.gd` is 692 lines — the biggest cleanup. Plan to audit thoroughly.

- [ ] **Step 1: Audit the existing animation code**

```bash
grep -n "tween_property\|create_tween\|visible =\|modulate\|position.y" src/ui/weapon_popup.gd
```

Identify every animation call related to show/hide. Note: not every tween is show/hide — some may be in-panel (e.g., hovering a weapon slot, swapping modifiers). Leave in-panel animations alone; only replace the ones that fire on open/close.

- [ ] **Step 2: Migrate**

If root is `Control`: change to `extends JuicyPanel`.
If root is `CanvasLayer`: attach `JuicyPanel` to the inner main panel node.

Find the existing public open/close functions. Convert them to call `super.open()` / `super.close()` (or inner panel's `open()` / `close()`). Strip out modulate/position tweens that duplicate JuicyPanel's behavior.

Preserve any custom logic that runs on open/close (refresh weapon data, focus a button, save state) — wrap it around the `super` calls.

- [ ] **Step 3: Update the scene**

`scenes/ui/weapon_popup.tscn`:
- Set `animated_root` to the main weapon-popup panel.
- Set `content_root` to the container that holds the weapon slots / rows.
- `has_backdrop = true`, `close_on_backdrop_click = true`.

- [ ] **Step 4: Manual smoke test**

Pick up a weapon (or trigger weapon_popup however the game does). Verify:
- Popup drops in.
- Weapon slots stagger in.
- All existing functionality (drag-drop of modifiers, weapon selection, etc.) still works — this is where regressions are most likely given the file's size.
- Close drops out cleanly.

If anything in-panel feels broken, narrow down to whether `JuicyPanel`'s scale/position changes on the `animated_root` are conflicting with code that touches the same properties. Fix in-panel by switching the in-panel animation to target a child of the animated root instead.

- [ ] **Step 5: Commit**

```bash
git add src/ui/weapon_popup.gd scenes/ui/weapon_popup.tscn
git commit -m "refactor: migrate weapon_popup to JuicyPanel"
```

---

## Task 11: Decide on and (maybe) migrate `main_menu`

**Files:**
- Possibly modify: `src/ui/main_menu.gd`, `scenes/ui/main_menu.tscn`

- [ ] **Step 1: Read the current file**

```bash
cat src/ui/main_menu.gd
```

Decide: does the main menu function as a modal panel that's opened/closed within a running scene, or is it a full-screen scene loaded by `SceneManager`?

If the latter (full-screen scene with no "open/close" transitions in-game), **skip migration**. The juicy treatment is meant for in-game popups, not scene transitions.

If it does open/close within another scene, migrate like the others: `extends JuicyPanel`, set exports, remove hand-rolled animation, `has_backdrop = false`.

- [ ] **Step 2: Migrate (only if Step 1 said yes)**

Follow the same pattern as Task 6 (settings_popup), with `has_backdrop = false`.

- [ ] **Step 3: Manual smoke test**

If migrated: enter and exit main menu. If skipped: no test needed — note the decision in the commit message.

- [ ] **Step 4: Commit**

```bash
git add src/ui/main_menu.gd scenes/ui/main_menu.tscn 2>/dev/null
git commit -m "refactor: migrate main_menu to JuicyPanel" -m "(or: skip main_menu — it's a full-screen scene, not a modal panel)"
```

If nothing changed, skip the commit.

---

## Task 12: Final smoke test pass + tuning

**Files:** none (verification only)

- [ ] **Step 1: Run the full manual checklist from the spec**

For each migrated panel, walk through:
- Opens with: dim fade-in, panel drops from above, elastic settle, content staggers in.
- Closes with: content fades, panel falls downward and out, dim fades.
- Backdrop click closes (where enabled).
- Esc closes panels that previously used it.
- Spam-clicking the toggle: no stuck state, no overlapping animations snapping.
- Calling `close()` mid-open and `open()` mid-close: smooth visuals.
- `pause_menu` and `settings_popup` animate while paused.
- HUDs (`currency_hud`, `health_ui`) unchanged.
- Card hover/click feedback unchanged.
- Button hover/press feedback unchanged.

- [ ] **Step 2: Tune values if needed**

If a specific panel feels off (e.g., `death_screen` feels too floaty), tune that scene's `enter_duration` / `exit_duration` / `drop_distance` in the inspector. Do not change the defaults in `juicy_panel.gd` unless every panel needs the change.

- [ ] **Step 3: Commit any tuning**

```bash
git add scenes/ui/
git commit -m "tune: adjust JuicyPanel timings per panel"
```

If no tuning was needed, skip this commit.

- [ ] **Step 4: Final review**

Read `src/ui/juicy_panel.gd` end-to-end. Confirm:
- No dead code, no commented-out blocks.
- All exports documented or self-explanatory.
- File is under ~250 lines (target ~180). If larger, look for extraction opportunities — but only if it improves clarity.

---

## Self-Review Notes

- **Spec coverage:** Each spec section maps to tasks — base class (1–5), per-panel migration (6–11), testing (12). The `animated_root` export was added in Task 1 to handle the codebase's prevalent CanvasLayer-wrapper pattern (settings_popup is the only panel where the script root is itself the visual panel).
- **Risk acknowledged:** `weapon_popup` is the highest-regression-risk task due to file size. Task 10 explicitly calls out auditing in-panel vs. open/close animations separately.
- **Backdrop layering:** Each migrated panel auto-creates its own `_Backdrop` as a child, so stacking (settings over pause) works because each `JuicyPanel`'s backdrop sits within its own subtree. No global z-order concerns.
- **`main_menu` open question** from spec is resolved by Task 11 making it a decision step rather than a forced migration.
