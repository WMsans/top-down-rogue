# UI Consistency Pass + CRT Post-Process — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify the UI (one font, two sizes, biome-reactive accent palette, consistent 2px borders, no corner radius) and overlay a global CRT shader (scanlines, curvature, vignette) covering world and UI alike.

**Architecture:**
- Extend the existing programmatic theme `src/ui/ui_theme.gd` (a `class_name` static helper that builds a `Theme` returned by `UiTheme.get_theme()`). Make accent colors mutable, add a `palette_changed` signal, and have it listen to `LevelManager.floor_changed` to swap accents per biome. Strip per-control overrides from UI scenes that conflict with the new theme.
- Add a global CRT post-process as an autoloaded `CanvasLayer` at layer 128 holding a full-rect `ColorRect` running `shaders/post/crt.gdshader`. Toggleable via settings.

**Tech Stack:** Godot 4 (GDScript), gdUnit4 for unit tests, existing `LevelManager` autoload for biome state.

**Spec deviation:** The spec assumed UI scenes had no centralized theme and proposed creating `resources/ui/main_theme.tres` + a new `UIPalette` autoload. Reality: `src/ui/ui_theme.gd` already exists and is read by most scripts via `UiTheme.get_theme()`. The plan therefore extends `UiTheme` in place rather than creating parallel theme/autoload files. Spec intent (one font, two sizes, biome-reactive accents, CRT overlay) is preserved.

---

## File map

**Modified:**
- `src/core/biome_def.gd` — add `@export var ui_accent: Color`.
- `assets/biomes/{caves,magma,frozen,mines,vault}.tres` — set `ui_accent`.
- `src/ui/ui_theme.gd` — convert to autoload, rebuild palette/sizes/styleboxes per design, add `palette_changed` signal, react to `LevelManager.floor_changed`.
- `project.godot` — register `UiTheme` autoload and `CrtOverlay` autoload.
- `scenes/ui/main_menu.tscn` — strip per-control `theme_override_font_sizes` and `theme_override_colors/font_color`.
- `scenes/ui/pause_menu.tscn` — strip per-control `theme_override_font_sizes` and `theme_override_colors/font_color`.
- `scenes/ui/card.tscn` — strip per-control `theme_override_colors/font_color`.
- `scenes/ui/settings_popup.tscn` — add CRT toggle row.
- `src/ui/settings_popup.gd` — load/save `crt_enabled`, wire toggle, drop the manual `font_size = 14` overrides on section headers.
- `src/ui/main_menu.gd` / `src/ui/death_screen.gd` / `src/ui/weapon_popup.gd` / `src/ui/weapon_button.gd` / `src/ui/currency_hud.gd` — adjust to the autoload form (replace `const _UiTheme = preload(...)` + `UiTheme.get_theme()` with the autoload). The constants stay accessible because `UiTheme` is still a script class.

**Created:**
- `shaders/post/crt.gdshader` — fragment shader.
- `scenes/ui/crt_overlay.tscn` — autoloaded `CanvasLayer` + `ColorRect` running the shader.
- `tests/unit/test_ui_theme.gd` — unit tests for theme building + accent swapping.

---

## Task 1: Add `ui_accent` field to BiomeDef

**Files:**
- Modify: `src/core/biome_def.gd`

- [ ] **Step 1: Add the field**

Open `src/core/biome_def.gd`. After the existing `@export var tint: Color = Color.WHITE` line, add:

```gdscript
@export var ui_accent: Color = Color(0.85, 0.46, 0.26, 1)  # default = caves orange
```

- [ ] **Step 2: Verify project still loads**

Run: `godot --headless --check-only project.godot`
Expected: no errors. (If `--check-only` is unavailable, open the editor briefly and confirm no parse errors in the Output panel.)

- [ ] **Step 3: Commit**

```bash
git add src/core/biome_def.gd
git commit -m "feat(biome): add ui_accent color field to BiomeDef"
```

---

## Task 2: Set `ui_accent` on every biome resource

**Files:**
- Modify: `assets/biomes/caves.tres`
- Modify: `assets/biomes/magma.tres`
- Modify: `assets/biomes/frozen.tres`
- Modify: `assets/biomes/mines.tres`
- Modify: `assets/biomes/vault.tres`

- [ ] **Step 1: Edit each biome resource**

For each file, find the main `[resource]` section (the one with `script = ExtResource("3_5ujno")` or equivalent BiomeDef script). Add a new line inside that section:

In `caves.tres`:
```
ui_accent = Color(0.851, 0.467, 0.259, 1)
```

In `magma.tres`:
```
ui_accent = Color(1.0, 0.314, 0.188, 1)
```

In `frozen.tres`:
```
ui_accent = Color(0.431, 0.776, 0.910, 1)
```

In `mines.tres`:
```
ui_accent = Color(0.784, 0.596, 0.345, 1)
```

In `vault.tres`:
```
ui_accent = Color(0.784, 0.627, 0.251, 1)
```

- [ ] **Step 2: Verify each resource opens**

Run: `godot --headless --quit project.godot 2>&1 | grep -i error | head`
Expected: no biome-related parse errors. Each resource file should still load.

- [ ] **Step 3: Commit**

```bash
git add assets/biomes/caves.tres assets/biomes/magma.tres assets/biomes/frozen.tres assets/biomes/mines.tres assets/biomes/vault.tres
git commit -m "feat(biome): set ui_accent on all biome resources"
```

---

## Task 3: Refactor UiTheme — new sizes, palette, biome reactivity

The current `UiTheme` uses corner radius 8, scattered font sizes (14, 20), and a fixed maroon palette. This task rewrites the file to match the spec: two font sizes only (16 body, 32 title), 2px borders with corner radius 0, neutral base palette + mutable accent, autoload form with a `palette_changed` signal driven by `LevelManager.floor_changed`.

**Files:**
- Modify: `src/ui/ui_theme.gd`
- Modify: `project.godot`
- Test: `tests/unit/test_ui_theme.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_ui_theme.gd`:

```gdscript
extends GdUnitTestSuite

func test_default_accent_is_caves_orange() -> void:
    var ui := load("res://src/ui/ui_theme.gd").new()
    ui._build_theme()
    assert_that(ui.accent).is_equal(Color(0.851, 0.467, 0.259, 1))

func test_set_accent_updates_button_hover_color() -> void:
    var ui := load("res://src/ui/ui_theme.gd").new()
    ui._build_theme()
    var new_accent := Color(0.431, 0.776, 0.910, 1)
    ui.set_accent(new_accent)
    var hover_color: Color = ui.get_theme().get_color("font_hover_color", "Button")
    assert_that(hover_color).is_equal(new_accent)

func test_set_accent_emits_palette_changed() -> void:
    var ui := load("res://src/ui/ui_theme.gd").new()
    ui._build_theme()
    var monitor := monitor_signals(ui)
    ui.set_accent(Color.MAGENTA)
    await assert_signal(monitor).is_emitted("palette_changed")

func test_theme_uses_pixel_font_at_16px_body() -> void:
    var ui := load("res://src/ui/ui_theme.gd").new()
    ui._build_theme()
    var t := ui.get_theme()
    assert_that(t.default_font_size).is_equal(16)
    assert_that(t.get_font_size("font_size", "Button")).is_equal(16)

func test_panel_stylebox_has_zero_corner_radius() -> void:
    var ui := load("res://src/ui/ui_theme.gd").new()
    ui._build_theme()
    var sb: StyleBoxFlat = ui.get_theme().get_stylebox("panel", "PanelContainer")
    assert_that(sb.corner_radius_top_left).is_equal(0)
    assert_that(sb.border_width_top).is_equal(2)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ui_theme.gd`
Expected: FAIL — `_build_theme`, `accent`, `set_accent`, `palette_changed`, and the new sizes/radii don't exist yet.

- [ ] **Step 3: Rewrite `src/ui/ui_theme.gd`**

Replace the entire file contents with:

```gdscript
extends Node
class_name UiTheme

## Centralized theme for the game's UI. Runs as an autoload so accent colors
## can react to biome changes via LevelManager.floor_changed.

signal palette_changed

const PIXEL_FONT := preload("res://textures/Assets/DawnLike/GUI/SDS_8x8.ttf")

const FONT_SIZE_BODY := 16
const FONT_SIZE_TITLE := 32

# Neutral base palette (constant across biomes).
const BG_DEEP := Color(0.102, 0.078, 0.063, 1)        # #1a1410
const BG_MID := Color(0.165, 0.125, 0.102, 1)         # #2a201a
const INK := Color(0.910, 0.847, 0.722, 1)            # #e8d8b8
const INK_DIM := Color(0.541, 0.471, 0.376, 1)        # #8a7860

# Default accent (caves orange) — used until LevelManager reports a biome.
const DEFAULT_ACCENT := Color(0.851, 0.467, 0.259, 1) # #d97742

# Status colors (palette-independent).
const DANGER := Color(0.85, 0.20, 0.20, 1)
const SUCCESS := Color(0.267, 0.667, 0.267, 1)
const SHADOW := Color(0, 0, 0, 0.5)

# Backward-compatibility aliases for existing callers (death_screen.gd,
# weapon_popup.gd, currency_hud.gd, health_ui.gd, etc.). Map old names to
# the new neutral/accent slots so call sites keep compiling.
const DEEP_BG := BG_DEEP
const SURFACE_BG := BG_MID
const PANEL_BG := BG_DEEP
const TEXT_PRIMARY := INK
const TEXT_SECONDARY := INK_DIM

const RARITY_COMMON := Color(1, 1, 1, 1)
const RARITY_UNCOMMON := Color(0.35, 0.66, 1.0, 1)
const RARITY_RARE := Color(1.0, 0.843, 0.0, 1)

# Mutable accent + derived border color, swapped on biome change.
var accent: Color = DEFAULT_ACCENT
var _theme: Theme = null

# ACCENT / ACCENT_GOLD / PANEL_BORDER are referenced by call sites as constants
# but conceptually they're "current accent". We expose them as static
# read-throughs to a singleton instance. Old code reading UiTheme.ACCENT will
# continue to work because we keep these as static getters via a sentinel.
# To preserve the simplest call-site shape, we also publish them as runtime
# vars on the autoload (see _ready). Callers that need a live value should
# subscribe to palette_changed.
var ACCENT: Color = DEFAULT_ACCENT
var ACCENT_GOLD: Color = DEFAULT_ACCENT
var PANEL_BORDER: Color = DEFAULT_ACCENT

func _ready() -> void:
    _build_theme()
    if Engine.has_singleton("LevelManager") or _has_autoload("LevelManager"):
        LevelManager.floor_changed.connect(_on_floor_changed)
        _on_floor_changed(0)

func _has_autoload(name: String) -> bool:
    return get_tree() != null and get_tree().root.has_node(name)

func get_theme() -> Theme:
    if _theme == null:
        _build_theme()
    return _theme

static func get_rarity_color(rarity: int) -> Color:
    match rarity:
        DropTable.ItemTier.UNCOMMON:
            return RARITY_UNCOMMON
        DropTable.ItemTier.RARE:
            return RARITY_RARE
        _:
            return RARITY_COMMON

func set_accent(c: Color) -> void:
    accent = c
    ACCENT = c
    ACCENT_GOLD = c
    PANEL_BORDER = c
    _apply_accent()
    palette_changed.emit()

func _on_floor_changed(_floor: int) -> void:
    var biome: BiomeDef = LevelManager.get_current_biome()
    if biome == null:
        return
    set_accent(biome.ui_accent)

func _build_theme() -> void:
    var t := Theme.new()
    t.default_font = PIXEL_FONT
    t.default_font_size = FONT_SIZE_BODY
    _set_button_styles(t)
    _set_label_styles(t)
    _set_panel_styles(t)
    _set_slider_styles(t)
    _set_separator_styles(t)
    _set_container_constants(t)
    _theme = t
    _apply_accent()

func _apply_accent() -> void:
    if _theme == null:
        return
    var t := _theme
    # Button hover/focus colors track the accent.
    t.set_color("font_hover_color", "Button", accent)
    t.set_color("font_focus_color", "Button", accent)
    # Stylebox border colors track the accent.
    var btn_hover: StyleBoxFlat = t.get_stylebox("hover", "Button")
    if btn_hover != null:
        btn_hover.border_color = accent
    var btn_focused: StyleBoxFlat = t.get_stylebox("focused", "Button")
    if btn_focused != null:
        btn_focused.border_color = accent
    var panel_sb: StyleBoxFlat = t.get_stylebox("panel", "PanelContainer")
    if panel_sb != null:
        panel_sb.border_color = accent
    var slider_track: StyleBoxFlat = t.get_stylebox("slider", "HSlider")
    if slider_track != null:
        slider_track.border_color = accent
    var slider_grab: StyleBoxFlat = t.get_stylebox("grabber_area", "HSlider")
    if slider_grab != null:
        slider_grab.bg_color = accent
        slider_grab.border_color = accent
    var slider_grab_hi: StyleBoxFlat = t.get_stylebox("grabber_area_highlight", "HSlider")
    if slider_grab_hi != null:
        slider_grab_hi.bg_color = accent
        slider_grab_hi.border_color = accent

func _make_panel_stylebox() -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = BG_DEEP
    s.border_color = accent
    s.set_border_width_all(2)
    s.set_corner_radius_all(0)
    s.set_content_margin_all(16)
    return s

func _make_button_stylebox(normal: bool) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = BG_MID if normal else BG_DEEP
    s.border_color = INK_DIM if normal else accent
    s.set_border_width_all(2)
    s.set_corner_radius_all(0)
    s.set_content_margin_all(8)
    s.content_margin_left = 16
    s.content_margin_right = 16
    return s

func _set_button_styles(t: Theme) -> void:
    var normal := _make_button_stylebox(true)
    var hover := _make_button_stylebox(false)
    var pressed := _make_button_stylebox(true)
    pressed.bg_color = BG_DEEP
    var focused := _make_button_stylebox(false)
    t.set_stylebox("normal", "Button", normal)
    t.set_stylebox("hover", "Button", hover)
    t.set_stylebox("pressed", "Button", pressed)
    t.set_stylebox("focused", "Button", focused)
    t.set_color("font_color", "Button", INK)
    t.set_color("font_hover_color", "Button", accent)
    t.set_color("font_pressed_color", "Button", INK_DIM)
    t.set_color("font_focus_color", "Button", accent)
    t.set_color("font_disabled_color", "Button", INK_DIM)
    t.set_font_size("font_size", "Button", FONT_SIZE_BODY)

func _set_label_styles(t: Theme) -> void:
    t.set_color("font_color", "Label", INK)
    t.set_font_size("font_size", "Label", FONT_SIZE_BODY)
    # Variation "Title" for screen/section headers.
    t.set_type_variation("TitleLabel", "Label")
    t.set_color("font_color", "TitleLabel", accent)
    t.set_font_size("font_size", "TitleLabel", FONT_SIZE_TITLE)

func _set_panel_styles(t: Theme) -> void:
    t.set_stylebox("panel", "PanelContainer", _make_panel_stylebox())

func _set_slider_styles(t: Theme) -> void:
    var track := StyleBoxFlat.new()
    track.bg_color = BG_DEEP
    track.border_color = accent
    track.set_border_width_all(2)
    track.set_corner_radius_all(0)
    track.set_content_margin_all(4)
    track.content_margin_left = 0
    track.content_margin_right = 0
    var fill := StyleBoxFlat.new()
    fill.bg_color = accent
    fill.border_color = accent
    fill.set_border_width_all(2)
    fill.set_corner_radius_all(0)
    fill.set_content_margin_all(4)
    fill.content_margin_left = 0
    fill.content_margin_right = 0
    t.set_stylebox("slider", "HSlider", track)
    t.set_stylebox("grabber_area", "HSlider", fill)
    t.set_stylebox("grabber_area_highlight", "HSlider", fill)
    t.set_font_size("font_size", "HSlider", FONT_SIZE_BODY)

func _set_separator_styles(t: Theme) -> void:
    var sep := StyleBoxFlat.new()
    sep.bg_color = Color(0, 0, 0, 0)
    sep.border_color = INK_DIM
    sep.border_width_top = 1
    sep.set_content_margin_all(4)
    sep.content_margin_left = 0
    sep.content_margin_right = 0
    t.set_stylebox("separator", "HSeparator", sep)

func _set_container_constants(t: Theme) -> void:
    t.set_constant("separation", "VBoxContainer", 8)
    t.set_constant("separation", "HBoxContainer", 8)

static func get_card_shadow_stylebox() -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = Color(0, 0, 0, 0.12)
    s.set_corner_radius_all(0)
    return s
```

- [ ] **Step 4: Register UiTheme as an autoload**

Open `project.godot`. In the `[autoload]` section, append (order matters — UiTheme must load AFTER LevelManager because it connects to its signal):

```
UiTheme="*res://src/ui/ui_theme.gd"
```

The existing `LevelManager="*res://src/autoload/level_manager.gd"` line already appears above where the new line goes — confirm before saving.

- [ ] **Step 5: Update callers from static `UiTheme.get_theme()` to autoload form**

In each of these files, remove the line `const _UiTheme = preload("res://src/ui/ui_theme.gd")` (it's no longer needed — `UiTheme` is an autoload). Calls to `UiTheme.get_theme()`, `UiTheme.ACCENT`, etc. continue to work unchanged because `UiTheme` resolves to the autoload instance.

Files to edit (remove the `const _UiTheme = preload(...)` line, if present):
- `src/ui/main_menu.gd`
- `src/ui/settings_popup.gd`
- `src/ui/death_screen.gd`
- `src/ui/weapon_popup.gd`
- `src/ui/weapon_button.gd`
- `src/ui/currency_hud.gd`
- `src/ui/health_ui.gd`

If any file has a callsite like `UiTheme.PANEL_BG` and a different file has `_UiTheme.PANEL_BG`, normalize all to `UiTheme.*`.

- [ ] **Step 6: Replace `static func get_rarity_color` callers**

Search and confirm: `grep -rn "get_rarity_color" src/ scenes/`. All callers should be reached as `UiTheme.get_rarity_color(...)` — same as before, no change needed (still a static func on the script class).

- [ ] **Step 7: Run the unit test — expect pass**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ui_theme.gd`
Expected: 5 tests pass.

- [ ] **Step 8: Run the full test suite to catch regressions**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit`
Expected: all green.

- [ ] **Step 9: Smoke-test the editor**

Run: `godot --editor --path . --quit` (opens then quits)
Expected: no parse errors in the Output log.

- [ ] **Step 10: Commit**

```bash
git add src/ui/ui_theme.gd project.godot tests/unit/test_ui_theme.gd src/ui/main_menu.gd src/ui/settings_popup.gd src/ui/death_screen.gd src/ui/weapon_popup.gd src/ui/weapon_button.gd src/ui/currency_hud.gd src/ui/health_ui.gd
git commit -m "refactor(ui): unify theme to two sizes + biome-reactive accent"
```

---

## Task 4: Strip per-control overrides from UI scenes

The new theme provides correct sizes and colors centrally. Per-control overrides in `.tscn` files conflict with it. This task removes them.

**Files:**
- Modify: `scenes/ui/main_menu.tscn`
- Modify: `scenes/ui/pause_menu.tscn`
- Modify: `scenes/ui/card.tscn`

- [ ] **Step 1: Edit `scenes/ui/main_menu.tscn`**

Delete the following lines (lines 36, 39, 55, 58, 86 per the audit — line numbers may shift after edits; match by content):

```
theme_override_colors/font_color = Color(1, 0.843, 0, 1)
theme_override_colors/font_outline_color = Color(0, 0, 0, 1)
theme_override_font_sizes/font_size = 64
theme_override_colors/font_color = Color(1, 0.42, 0.208, 1)
theme_override_colors/font_outline_color = Color(0, 0, 0, 1)
theme_override_font_sizes/font_size = 28
theme_override_colors/font_color = Color(1, 0.42, 0.208, 1)
```

Remove all matching lines. For the title `Label` node that had `font_size = 64`, also add `theme_type_variation = "TitleLabel"` on the same node so it picks up the new 32px title size + accent color from the theme.

- [ ] **Step 2: Edit `scenes/ui/pause_menu.tscn`**

Delete:
```
theme_override_font_sizes/font_size = 48
theme_override_colors/font_color = Color(1, 0.843, 0, 1)
theme_override_colors/font_color = Color(0.8, 0.2, 0.2, 1)
theme_override_colors/font_color = Color(0.8, 0.2, 0.2, 1)
theme_override_colors/font_color = Color(1, 0.843, 0, 1)
```

For the "PAUSED" title `Label` (where `font_size = 48` lived), add `theme_type_variation = "TitleLabel"`.

- [ ] **Step 3: Edit `scenes/ui/card.tscn`**

Delete:
```
theme_override_colors/font_color = Color(1, 0.843, 0, 1)
```

- [ ] **Step 4: Strip the manual `font_size = 14` from settings popup**

Open `src/ui/settings_popup.gd`. In `_style_section_headers()` (around line 34), delete the line:
```gdscript
child.add_theme_font_size_override("font_size", 14)
```
Keep the `add_theme_color_override("font_color", gold)` — that one is now redundant but harmless; remove it as well:
```gdscript
child.add_theme_color_override("font_color", gold)
```
Then also remove `title_label.add_theme_color_override("font_color", gold)`. Replace the whole `_style_section_headers()` body with:
```gdscript
    var content := panel.get_node("VBoxContainer/ScrollContainer/Content")
    for child in content.get_children():
        if child is Label and child.text.begins_with("--"):
            child.theme_type_variation = "TitleLabel"
    var title_label: Label = panel.get_node("VBoxContainer/Header/TitleLabel")
    title_label.theme_type_variation = "TitleLabel"
```

Also in `_rebuild_key_bindings()` (around line 158), delete:
```gdscript
name_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
name_label.add_theme_font_size_override("font_size", 14)
```
The label will pick up `INK` + 16px from the theme defaults.

- [ ] **Step 5: Launch the game and visually verify**

Run: `godot --path .`
Walk through: main menu → start → pause → settings → close. Confirm:
- All text is the SDS_8x8 pixel font.
- Body text is one size; titles ("PAUSED", "SETTINGS") are exactly 2× body size.
- All panel borders are 2px with sharp corners (no rounding).
- Border / title / button-hover colors are the same shade of orange (caves accent) on floor 0.

- [ ] **Step 6: Commit**

```bash
git add scenes/ui/main_menu.tscn scenes/ui/pause_menu.tscn scenes/ui/card.tscn src/ui/settings_popup.gd
git commit -m "refactor(ui): remove per-control overrides; rely on theme variations"
```

---

## Task 5: Add `crt_enabled` setting

**Files:**
- Modify: `src/ui/settings_popup.gd`
- Modify: `scenes/ui/settings_popup.tscn`

- [ ] **Step 1: Add CRT toggle row to the settings scene**

Open `scenes/ui/settings_popup.tscn` in the Godot editor. Under the Display section (where the Fullscreen row lives), duplicate the Fullscreen row's `HBoxContainer` and rename the duplicate node to `CrtRow`. Inside it:
- The label's text becomes `CRT`.
- The button's unique-name (`%FullscreenButton` style) becomes `%CrtButton`.

Save the scene.

- [ ] **Step 2: Wire the toggle in `src/ui/settings_popup.gd`**

Add a constant near the other section constants:
```gdscript
const SECTION_VIDEO := "video"
```

Add a node reference under the other `@onready`s:
```gdscript
@onready var crt_button: Button = %CrtButton
```

In `_connect_signals()`, append:
```gdscript
crt_button.pressed.connect(_on_crt_toggled)
```

In `_apply_loaded_settings()`, after the `_update_fullscreen_text()` line, add:
```gdscript
var crt_enabled: bool = config.get_value(SECTION_VIDEO, "crt_enabled", true)
_set_crt_enabled(crt_enabled)
_update_crt_text()
```

And in the early-return branch (where `config.load` fails), add the same two `_set_crt_enabled(true)` and `_update_crt_text()` calls.

Add three new functions at the bottom of the file:
```gdscript
func _on_crt_toggled() -> void:
    var current: bool = CrtOverlay.visible
    _set_crt_enabled(not current)
    _update_crt_text()

func _set_crt_enabled(enabled: bool) -> void:
    CrtOverlay.visible = enabled

func _update_crt_text() -> void:
    crt_button.text = "ON" if CrtOverlay.visible else "OFF"
```

In `_save_settings()`, before `config.save`, append:
```gdscript
config.set_value(SECTION_VIDEO, "crt_enabled", CrtOverlay.visible)
```

- [ ] **Step 3: Note the dependency**

`CrtOverlay` is referenced here but created in Task 6. Until Task 6 lands, settings will fail to load with "Identifier not declared". That's fine — we commit per-task, and the next task supplies it. Do NOT run the game between Task 5 commit and Task 6 commit; run the test suite instead:

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit`
Expected: passes (these tests don't touch settings_popup).

- [ ] **Step 4: Commit**

```bash
git add src/ui/settings_popup.gd scenes/ui/settings_popup.tscn
git commit -m "feat(settings): add CRT toggle (overlay arrives in next commit)"
```

---

## Task 6: CRT shader

**Files:**
- Create: `shaders/post/crt.gdshader`

- [ ] **Step 1: Create the shader**

Create `shaders/post/crt.gdshader` with this content (full file):

```glsl
shader_type canvas_item;

uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.15;
uniform float scanline_count : hint_range(100.0, 2000.0) = 540.0;
uniform float curvature : hint_range(0.0, 0.3) = 0.08;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;
uniform float vignette_softness : hint_range(0.05, 1.0) = 0.45;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

const float PI = 3.14159265;

vec2 barrel(vec2 uv, float amount) {
    vec2 cc = uv - 0.5;
    float dist = dot(cc, cc);
    return uv + cc * dist * amount;
}

void fragment() {
    vec2 uv = barrel(SCREEN_UV, curvature);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        COLOR = vec4(0.0, 0.0, 0.0, 1.0);
    } else {
        vec3 col = texture(screen_tex, uv).rgb;
        float scan = 0.5 + 0.5 * sin(uv.y * scanline_count * PI);
        float scan_factor = mix(1.0, scan, scanline_intensity);
        col *= scan_factor;
        vec2 vc = uv - 0.5;
        float vd = length(vc);
        float vig = smoothstep(0.5 + vignette_softness * 0.5, 0.5 - vignette_softness * 0.5, vd);
        col *= mix(1.0, vig, vignette_strength);
        COLOR = vec4(col, 1.0);
    }
}
```

- [ ] **Step 2: Smoke-check the shader compiles**

The shader compiles on first use. Run the editor briefly:
Run: `godot --editor --path . --quit`
Expected: no shader compile errors in Output. If errors appear, they'll point to the exact line in `crt.gdshader`.

- [ ] **Step 3: Commit**

```bash
git add shaders/post/crt.gdshader
git commit -m "feat(shader): add CRT post-process shader (scanlines+curvature+vignette)"
```

---

## Task 7: CRT overlay autoload

**Files:**
- Create: `scenes/ui/crt_overlay.tscn`
- Create: `src/ui/crt_overlay.gd`
- Modify: `project.godot`

- [ ] **Step 1: Create the overlay script**

Create `src/ui/crt_overlay.gd`:

```gdscript
extends CanvasLayer

## Full-screen CRT post-process. Sits at the highest CanvasLayer so its
## ColorRect samples everything below via hint_screen_texture in the shader.

const CRT_SHADER := preload("res://shaders/post/crt.gdshader")

func _ready() -> void:
    layer = 128
    follow_viewport_enabled = true
    var rect := ColorRect.new()
    rect.anchor_right = 1.0
    rect.anchor_bottom = 1.0
    rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var mat := ShaderMaterial.new()
    mat.shader = CRT_SHADER
    rect.material = mat
    add_child(rect)
```

- [ ] **Step 2: Create the overlay scene**

Create `scenes/ui/crt_overlay.tscn` (a minimal scene whose root is the script above). Easiest path: in the editor, create a new scene → Other Node → CanvasLayer → attach `res://src/ui/crt_overlay.gd` → save as `res://scenes/ui/crt_overlay.tscn`. If editing the `.tscn` by hand:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/ui/crt_overlay.gd" id="1"]

[node name="CrtOverlay" type="CanvasLayer"]
script = ExtResource("1")
```

- [ ] **Step 3: Register as autoload**

Open `project.godot`. In `[autoload]`, after the `UiTheme` line added in Task 3, append:
```
CrtOverlay="*res://scenes/ui/crt_overlay.tscn"
```

- [ ] **Step 4: Verify no other CanvasLayer uses layer 128 or higher**

Run: `grep -rE "^layer = " scenes/ | grep -vE "= [0-9]$|= [0-9][0-9]$|= 1[0-1][0-9]$"`
Expected: empty output (no layer ≥ 120 anywhere). If anything matches, raise the CRT overlay's `layer` in `crt_overlay.gd` to one above the highest existing layer.

- [ ] **Step 5: Launch the game and confirm**

Run: `godot --path .`
Expected:
- Main menu shows scanlines, slight curvature, vignette over the whole window.
- Pause and settings menus inherit the same effect.
- Settings → CRT toggle flips the effect on/off live.
- World gameplay remains pixel-recognizable (text in HUD is still readable).

- [ ] **Step 6: Confirm input passes through**

In game: click the "RESUME" button in the pause menu. It should respond normally — the CRT ColorRect must not absorb input.

- [ ] **Step 7: Commit**

```bash
git add src/ui/crt_overlay.gd scenes/ui/crt_overlay.tscn project.godot
git commit -m "feat(crt): add global CRT overlay autoload covering world + UI"
```

---

## Task 8: Verify biome-reactive accent end-to-end

**Files:**
- (No code changes — pure verification.)

- [ ] **Step 1: Use the cheat console to jump between floors**

The project has `ConsoleManager` (autoload). Launch the game and use whatever command sets the floor (commonly `/floor <n>` or similar — check `src/autoload/console_manager.gd` if unsure). Jump to a magma floor.

Run: `godot --path .`

Expected: UI accent color (panel border, button hover, title color, slider fill) shifts from caves orange → magma red without restart. Repeat for frozen (cyan), mines (brass), vault (gold).

- [ ] **Step 2: If the accent doesn't update**

Most likely cause: a UI scene was instantiated before `UiTheme._ready()` connected to `floor_changed`. Fix: in `UiTheme._ready()`, after connecting the signal, force `_on_floor_changed(0)` (already in the code from Task 3) — and confirm the autoload order in `project.godot` has `LevelManager` BEFORE `UiTheme`.

- [ ] **Step 3: Commit (if any fixes were needed)**

```bash
git add -p
git commit -m "fix(ui): ensure UiTheme picks up active biome accent on startup"
```

---

## Done

End state:
- One pixel font (SDS_8x8), two sizes (16, 32), 2px borders with sharp corners across every UI scene.
- Panel borders / titles / button-hover / slider fill all shift with the active biome's `ui_accent`.
- A single CRT shader covers world + UI, toggleable from settings.
- World sprites untouched; gameplay behavior unchanged.
