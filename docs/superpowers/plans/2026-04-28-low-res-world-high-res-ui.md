# Low-Res World, High-Res UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cap world rendering cost at 192×108 by routing it through a `SubViewport`, while UI renders at native screen resolution on the root viewport. Lift the GPU-bound 22.4 ms/frame ceiling to ≥60 FPS (target 90+) on the user's old laptop.

**Architecture:** Restructure `scenes/game.tscn` so the world (WorldManager, Player, DirectionalLight2D, WorldEnvironment, DebugManager) lives inside a `SubViewport` of fixed size `Vector2i(192, 108)` with `own_world_2d = true`. UI nodes (CanvasLayers) stay on the root. Update `project.godot` to use `stretch/mode = "canvas_items"` with a logical viewport of 320×180 so UI is crisp at native res. Move HDR-2D and glow off the root and onto the SubViewport. Patch three autoload-side scripts (`hit_reaction.gd`, `console_manager.gd`, `debug_manager.gd`) that previously assumed the camera and FPS HUD lived on the root viewport.

**Tech Stack:** Godot 4.6, GDScript, Forward+ renderer, d3d12 (Windows), gdUnit4 for unit tests, compute-shader cellular sim (unchanged by this plan).

**Spec:** [`docs/superpowers/specs/2026-04-28-low-res-world-high-res-ui-design.md`](../specs/2026-04-28-low-res-world-high-res-ui-design.md)

---

## Files to be modified

| File | Change |
|---|---|
| `project.godot` | Set `stretch/mode = "canvas_items"`, viewport 320×180, `viewport/hdr_2d = false` (off on root) |
| `scenes/game.tscn` | Insert `SubViewportContainer` + `SubViewport`; reparent world children into SubViewport |
| `src/debug/debug_manager.gd` | FPS-HUD `CanvasLayer` reparents to `get_tree().root` so it renders on root viewport |
| `src/core/juice/hit_reaction.gd` | `_process` looks up Camera2D via `"player"` group instead of `get_viewport().get_camera_2d()` |
| `src/autoload/console_manager.gd` | `_build_context` looks up camera + viewport via `"player"` group |

No file creation. All changes are surgical edits.

---

## Task 1: Capture baseline measurement

**Files:**
- Read-only

- [ ] **Step 1: Boot the game in editor and record FPS**

Run the game from the Godot editor (F5). Play for 10 seconds. Note FPS displayed (or check Debugger → Monitor → "Time/FPS"). Expected: **25–50 FPS** (matches the user-reported baseline).

- [ ] **Step 2: Capture Visual Profiler GPU breakdown**

In Godot: Debugger → Visual Profiler → Start. Play for ~5 seconds. Stop. Note these row totals:

- `Render Viewport 0` (expected ~22 ms)
- `Render Canvas` → `Render CanvasItems` (expected ~15 ms)
- `Tonemap` (expected ~2 ms)
- `Glow` (expected ~2 ms)

Save these numbers — used as the before/after comparison in Task 11.

- [ ] **Step 3: No commit**

This is a measurement task. Nothing to commit.

---

## Task 2: Update `project.godot` — stretch mode, viewport size, HDR off root

**Files:**
- Modify: `project.godot` — `[display]` and `[rendering]` sections

- [ ] **Step 1: Update the `[display]` section**

Replace the existing `[display]` block:

```ini
[display]

window/size/viewport_width=192
window/size/viewport_height=108
window/size/window_width_override=192
window/size/window_height_override=108
```

with:

```ini
[display]

window/size/viewport_width=320
window/size/viewport_height=180
window/size/window_width_override=1280
window/size/window_height_override=720
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"
```

- [ ] **Step 2: Update the `[rendering]` section**

In the existing `[rendering]` section, change:

```ini
viewport/hdr_2d=true
```

to:

```ini
viewport/hdr_2d=false
```

Leave `textures/canvas_textures/default_texture_filter=0` and `rendering_device/driver.windows="d3d12"` unchanged.

- [ ] **Step 3: Verify project loads**

Close and re-open the project in Godot, or run the editor. The project should load without errors. The game scene will render incorrectly at this point (world at native res, UI at logical 320×180) — that's expected; Task 3 fixes it.

- [ ] **Step 4: Commit**

```bash
git add project.godot
git commit -m "chore: switch to canvas_items stretch, 320x180 logical viewport, HDR off root"
```

---

## Task 3: Restructure `scenes/game.tscn` to put world inside a SubViewport

This task is done in the Godot editor (not by editing the .tscn text).

**Files:**
- Modify: `scenes/game.tscn`

- [ ] **Step 1: Open `scenes/game.tscn` in the Godot editor**

Open the scene. Confirm the current structure has these direct children of `Main`: `WorldManager`, `Player`, `DebugManager`, `WorldEnvironment`, `DirectionalLight2D`, `PauseMenu`, `HealthUI`, `DeathScreen`, `CurrencyHUD`, `WeaponPopup`, `WeaponButton`.

- [ ] **Step 2: Add `WorldViewportContainer` node**

Right-click `Main` → Add Child Node → `SubViewportContainer`. Rename to `WorldViewportContainer`.

In the Inspector, set:
- `Stretch` = **on** (true)
- Layout → Anchors Preset = **Full Rect** (so it fills the screen)

Move it to the **top** of the children list (above all UI) using the up-arrow in the Scene tree, so it draws beneath UI CanvasLayers.

- [ ] **Step 3: Add `WorldSubViewport` child**

Right-click `WorldViewportContainer` → Add Child Node → `SubViewport`. Rename to `WorldSubViewport`.

In the Inspector, set:
- `Size` = `Vector2i(192, 108)`
- `Own World 2D` = **on** (isolates world rendering from root's CanvasLayers)
- `Use Hdr 2D` = **on** (the world keeps HDR-2D after we turned it off on the root)
- `Render Target Update Mode` = `When Visible` or `Always` (default is fine; `Always` is safest)
- `Handle Input Locally` = **off** (input is forwarded by the parent container)

- [ ] **Step 4: Reparent world nodes into `WorldSubViewport`**

For each of these nodes, drag them in the Scene tree from `Main` onto `WorldSubViewport`:
- `WorldEnvironment`
- `DirectionalLight2D`
- `WorldManager` (with its children `ChunkContainer` and `WorldPreview`)
- `Player` (with its `Camera2D` and `PointLight2D`)
- `DebugManager` (with `ChunkGridOverlay` and `CollisionOverlay`)

Confirm UI nodes (`PauseMenu`, `HealthUI`, `DeathScreen`, `CurrencyHUD`, `WeaponPopup`, `WeaponButton`) remain as direct children of `Main`.

- [ ] **Step 5: Save the scene**

Ctrl+S. The .tscn file will change significantly. If Godot reports any broken NodePaths in the Output panel, note them — they are addressed in later tasks (the `Player` NodePath assumption in `debug_manager.gd:12` `get_node("../Player")` still works because Player and DebugManager are now siblings under `WorldSubViewport`).

- [ ] **Step 6: Quick smoke test — run the scene**

Run with F6 (or set as main scene and F5). Expected:
- World renders inside the SubViewport, upscaled crisply.
- UI renders on the root at native resolution (it will look different from before — that's the point).
- The FPS HUD (F3 to toggle) renders at low-res inside the world view (BUG — fixed in Task 4).
- Camera shake on hits silently does nothing (BUG — fixed in Task 5).
- Console world_pos is wrong (BUG — fixed in Task 6).

Do NOT fix any of these now. Just verify the world renders and UI is crisp.

- [ ] **Step 7: Commit**

```bash
git add scenes/game.tscn
git commit -m "feat: route world rendering through 192x108 SubViewport"
```

---

## Task 4: Move FPS-HUD CanvasLayer onto the root viewport

`DebugManager` lives inside `WorldSubViewport` (correct — its world-space overlays need to be there). But the FPS HUD is a `CanvasLayer` it creates at runtime; that CanvasLayer inherits the SubViewport's World2D and ends up rendering at 192×108 instead of native res.

**Files:**
- Modify: `src/debug/debug_manager.gd`

- [ ] **Step 1: Replace the file contents**

Replace `src/debug/debug_manager.gd` with:

```gdscript
extends Node2D

var _debug_label: Label
var _hud_canvas: CanvasLayer

func _ready() -> void:
	visible = false
	_build_hud()
	_hud_canvas.visible = false

func _process(_delta: float) -> void:
	if not _hud_canvas.visible:
		return
	var player := get_node("../Player") as Node2D
	var pos := player.global_position if player else Vector2.ZERO
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	_debug_label.text = "FPS: %d\nX: %.0f\nY: %.0f" % [fps, pos.x, pos.y]

func _build_hud() -> void:
	_hud_canvas = CanvasLayer.new()
	_hud_canvas.layer = 100
	get_tree().root.add_child.call_deferred(_hud_canvas)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	_hud_canvas.add_child(margin)

	var bg := PanelContainer.new()
	margin.add_child(bg)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	style.border_color = Color(1, 1, 1, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	bg.add_theme_stylebox_override("panel", style)

	_debug_label = Label.new()
	_debug_label.add_theme_color_override("font_color", Color.LIME_GREEN)
	_debug_label.add_theme_font_size_override("font_size", 14)
	_debug_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	bg.add_child(_debug_label)

func _exit_tree() -> void:
	if is_instance_valid(_hud_canvas):
		_hud_canvas.queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		visible = !visible
		_hud_canvas.visible = visible
```

What changed:
- The CanvasLayer is now stored in `_hud_canvas` and parented to `get_tree().root` via `call_deferred` so it renders in the root's World2D (native resolution).
- `_unhandled_input` toggles both `visible` (for ChunkGridOverlay/CollisionOverlay world-space children) and `_hud_canvas.visible` (for the FPS HUD).
- `_exit_tree` cleans up the canvas because it's no longer auto-freed with `DebugManager`.

- [ ] **Step 2: Run the scene and toggle the FPS HUD**

Press F5 → in-game press F3. Expected:
- FPS HUD appears at native resolution (crisp text), top-left of screen.
- Press F3 again — FPS HUD disappears and any visible chunk-grid / collision overlays in the world also disappear.

- [ ] **Step 3: Commit**

```bash
git add src/debug/debug_manager.gd
git commit -m "fix: render FPS HUD on root viewport, not inside world SubViewport"
```

---

## Task 5: Fix camera-shake lookup in `hit_reaction.gd`

`HitReaction` is an autoload; its `_process` calls `get_viewport().get_camera_2d()`, which now returns null because the root viewport has no Camera2D after the restructure.

**Files:**
- Modify: `src/core/juice/hit_reaction.gd:150-165`

- [ ] **Step 1: Add a private helper for looking up the world Camera2D**

Open `src/core/juice/hit_reaction.gd`. Find the `_process(delta: float)` function (around line 150). Replace it (and add the helper above it):

```gdscript
func _get_world_camera() -> Camera2D:
	var player := get_tree().get_first_node_in_group("player") as Node
	if player == null:
		return null
	return player.get_node_or_null("Camera2D") as Camera2D


func _process(delta: float) -> void:
	if _shake_duration > 0.0:
		_shake_elapsed += delta
		if _shake_elapsed >= _shake_duration:
			var cam := _get_world_camera()
			if cam:
				cam.offset = Vector2.ZERO
			_shake_duration = 0.0
		else:
			var t: float = 1.0 - (_shake_elapsed / _shake_duration)
			var current: float = _shake_amount * t
			var rand_offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * current
			var bias := _shake_dir_bias * 0.5 * current
			var cam := _get_world_camera()
			if cam:
				cam.offset = rand_offset + bias
```

This relies on the `Player` scene having its `CharacterBody2D` root in the `"player"` group. Verify by opening `scenes/player.tscn` in the editor → Player node → Node → Groups panel. If `player` is **not** present, add it (Add to Group → "player").

- [ ] **Step 2: Verify the player is in the `"player"` group**

In the Godot editor, open `scenes/player.tscn`. Click the root `Player` node. In the right panel, switch from the Inspector tab to the Node tab → Groups. If `player` is listed, no change. If absent, type `player` into the field and click "Add". Save scene.

(If a change was needed here, include `scenes/player.tscn` in the Step 4 commit.)

- [ ] **Step 3: Run game, hit an enemy, verify camera shake works**

F5 → spawn or find an enemy → hit it. Expected: camera shake briefly, then settles. If camera does not shake, something else broke — re-check the group membership.

- [ ] **Step 4: Run unit tests**

Run gdUnit4 tests for hit_reaction:

```bash
godot --headless --script addons/gdUnit4/bin/GdUnitCmdTool.gd -- -a tests/unit/test_hit_reaction.gd
```

(Or use Godot's test runner UI.) Expected: all tests pass — `test_hit_reaction.gd` only covers `HitSpec`, which is unchanged.

- [ ] **Step 5: Commit**

```bash
git add src/core/juice/hit_reaction.gd
# include scenes/player.tscn if Step 2 required a group addition
git commit -m "fix: hit_reaction looks up world camera via player group"
```

---

## Task 6: Fix world-mouse coord lookup in `console_manager.gd`

`ConsoleManager._build_context` builds `world_pos` from `get_viewport()` (root) — but the camera and the visible game world are inside the SubViewport. After restructure, this returns the wrong viewport.

**Files:**
- Modify: `src/autoload/console_manager.gd:180-193`

- [ ] **Step 1: Update `_build_context`**

Open `src/autoload/console_manager.gd`. Replace the `_build_context` function:

```gdscript
func _build_context() -> Dictionary:
	var ctx: Dictionary = {}
	var camera := _find_world_camera()
	if camera:
		var viewport := camera.get_viewport()
		var screen_pos := viewport.get_mouse_position()
		var view_size := viewport.get_visible_rect().size
		ctx["world_pos"] = (screen_pos - view_size * 0.5) / camera.zoom + camera.global_position
	else:
		ctx["world_pos"] = Vector2.ZERO
	ctx["player"] = get_tree().get_first_node_in_group("player")
	ctx["world_manager"] = get_tree().current_scene.get_node_or_null("WorldManager") if get_tree().current_scene else null
	ctx["scene"] = get_tree().current_scene
	return ctx


func _find_world_camera() -> Camera2D:
	var player := get_tree().get_first_node_in_group("player") as Node
	if player == null:
		return null
	return player.get_node_or_null("Camera2D") as Camera2D
```

What changed: the camera is looked up via the `"player"` group (same pattern as Task 5). Then `camera.get_viewport()` returns the SubViewport (because the camera lives inside it), and `viewport.get_mouse_position()` returns the SubViewport-translated mouse position automatically (thanks to `SubViewportContainer.stretch = true`).

Note: `ctx["world_manager"] = ... .get_node_or_null("WorldManager")` previously assumed `WorldManager` was a direct child of the current scene. After the restructure, `WorldManager` is at `WorldViewportContainer/WorldSubViewport/WorldManager`. To preserve console-command behavior, change that line to:

```gdscript
ctx["world_manager"] = get_tree().get_first_node_in_group("world_manager")
```

(`world_manager.gd:_ready` already calls `add_to_group("world_manager")`, so the group is populated.)

- [ ] **Step 2: Verify in-game**

F5 → open the console (whatever key/binding the console uses; check `console_manager.gd` for binding). Run a command that uses `world_pos` (e.g. `spawn` at cursor, if any such command exists). Expected: object spawns at the cursor location in the world, not at origin.

If no console command uses `world_pos`, sanity-check that the console still opens and accepts input.

- [ ] **Step 3: Commit**

```bash
git add src/autoload/console_manager.gd
git commit -m "fix: console world_pos uses world camera's SubViewport"
```

---

## Task 7: Verify Visual Profiler shows GPU cost dropped

**Files:**
- Read-only

- [ ] **Step 1: Run game with Visual Profiler**

F5 → Debugger → Visual Profiler → Start. Play 5 seconds. Stop.

- [ ] **Step 2: Compare against Task 1 baseline**

Expected after restructure:
- `Render Viewport 0` (root): **<1 ms** (only compositing the SubViewport texture and UI)
- `Render Viewport 1` (SubViewport): **~0.5–1 ms** (chunks + glow + tonemap at 192×108)
- Combined GPU frame time: **<11 ms (≥90 FPS)** on a desktop class GPU; **<16 ms (≥60 FPS)** is the must-pass threshold on the old laptop.

If `Render Viewport 0` is still high (>5 ms), check that:
- `WorldSubViewport.own_world_2d` is on (otherwise root may be drawing the world too).
- No CanvasLayer is accidentally inside the SubViewport rendering UI at low res.
- `viewport/hdr_2d` is `false` in `project.godot` (Task 2).

- [ ] **Step 3: No commit**

Measurement only.

---

## Task 8: Manual verification sweep — UI, input, debug overlays

**Files:**
- Read-only

- [ ] **Step 1: UI flows**

Run game (F5) and exercise each UI flow:

- Pause menu (Esc) — opens, looks crisp at native res, resumes correctly
- Health UI — visible, updates on damage
- Currency HUD — visible at top-right
- Weapon popup — opens and closes
- Weapon button — clickable, opens popup
- Chest UI — interact with a chest (E), UI opens crisp
- Death screen — die intentionally (e.g. console kill if available, or stand in lava); screen renders crisp
- FPS HUD (F3) — toggles on/off; renders at native res

Note any visual layout breakage caused by the 192×108 → 320×180 logical viewport change. If a UI element is mispositioned (e.g. anchored to center but offset wrong, or using percent-based sizes), record the file path; it will be fixed in Task 9.

- [ ] **Step 2: World input + mouse aim**

- Player movement (WASD / arrows) works
- Melee attack works (whatever the bound key is)
- If any weapon uses mouse aim/click, verify the targeted point matches the cursor

- [ ] **Step 3: Debug overlays**

Press F3 (toggle DebugManager visibility):
- ChunkGridOverlay draws on world chunks (inside SubViewport)
- CollisionOverlay draws on world (inside SubViewport)
- FPS HUD shows at top-left (on root)

All three should appear and disappear together.

- [ ] **Step 4: Window resize / fullscreen**

Resize the game window to multiple sizes (small, large) and toggle fullscreen if there's a binding (or use Alt+F4 / Settings popup if available — `settings_popup.gd` has fullscreen toggle code). Expected:
- World image scales but stays crisp (nearest-neighbor upscale of 192×108)
- UI stays at native resolution at every window size
- FPS does not change with window size (the SubViewport cap is what bounds GPU cost)

- [ ] **Step 5: No commit**

Verification only. If issues are found, file them as follow-ups in Task 9.

---

## Task 9: Address any UI-layout regressions from the 192×108 → 320×180 logical viewport scale

This task is conditional on Task 8 findings. If no UI scenes broke, skip to Task 10.

**Files:**
- Modify: any of `scenes/ui/*.tscn`, `scenes/economy/shop_ui.tscn`, etc., as discovered

- [ ] **Step 1: For each broken UI scene, identify the root cause**

Common causes:
- Anchors set to "Full Rect" — works automatically, no change needed
- Anchors set to a corner with absolute pixel offsets — those pixel offsets no longer match the 1.667× larger logical viewport
- `position` set in code based on `get_viewport().get_visible_rect().size` — recalculates correctly on its own, no change

For each broken scene, open in editor → fix anchors / sizes / offsets so the layout reads correctly at 320×180. Save scene.

- [ ] **Step 2: Re-run game, verify each fixed scene**

For every scene fixed in Step 1, re-run the game and exercise the flow that uses it.

- [ ] **Step 3: Commit each fix individually or as a batch**

If only one scene was fixed:

```bash
git add scenes/ui/<scene>.tscn
git commit -m "fix: re-anchor <scene> for 320x180 logical viewport"
```

If multiple scenes:

```bash
git add scenes/ui/*.tscn scenes/economy/*.tscn
git commit -m "fix: re-anchor UI scenes for 320x180 logical viewport"
```

---

## Task 10: Verify on the target old laptop

**Files:**
- Read-only

- [ ] **Step 1: Pull the branch on the old laptop**

```bash
git pull
git checkout feat/prototype  # or whatever branch this is being implemented on
```

- [ ] **Step 2: Boot the editor, run the game, measure FPS**

Open project. F5. Play 30 seconds across various rooms / enemy spawns / weapon uses. Note FPS range.

Pass criterion: **≥60 FPS sustained**, target **90+ FPS**.

If under 60 FPS:
- Re-confirm `WorldSubViewport.size = Vector2i(192, 108)` (not larger)
- Re-confirm `viewport/hdr_2d = false` in `project.godot`
- Re-capture Visual Profiler — find what's dominating the frame now (likely no longer Render Canvas; possibly the cellular sim or chunk streaming)
- Defer further optimization to a separate session — this plan's scope ends here

- [ ] **Step 3: Optional — exported build measurement**

If the user wants to verify the exported build (the original baseline was also exported, so this is the apples-to-apples comparison):

Project → Export → Windows desktop → Export project → run the .exe → measure FPS. Pass criterion same as Step 2.

- [ ] **Step 4: No commit**

Measurement only.

---

## Task 11: Final cleanup commit

**Files:**
- None — this is a documentation step.

- [ ] **Step 1: Update CHANGELOG / commit message summary if the project has one**

Check for a `CHANGELOG.md` or similar at project root. If present, add a one-line entry:

```
- perf: render world through 192x108 SubViewport, UI on root at native res (was 25-50 FPS, now 60+ on low-end hardware)
```

If no CHANGELOG exists, skip this step.

- [ ] **Step 2: If a CHANGELOG was updated, commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog entry for SubViewport perf fix"
```

- [ ] **Step 3: Mark plan complete**

Done. The branch is ready for review / merge.

---

## Out of scope (parked for follow-ups)

- Missing wall textures in exported builds (user flagged at session start; tracked separately).
- Cellular sim / chunk streaming optimizations (none needed if Task 10 passes; revisit only if the old laptop falls short of 60 FPS after this plan).
- `chunk_manager.gd:25-26` — uses `world_manager.get_viewport()` which now returns the SubViewport; this is *correct* behavior (chunks stream based on the 192×108 view, not screen size) and benefits performance on top of the SubViewport change. No edit needed.
- Logical viewport size beyond 320×180 — the spec lists 640×360 / 1920×1080 as future upgrade paths; not in this plan.
