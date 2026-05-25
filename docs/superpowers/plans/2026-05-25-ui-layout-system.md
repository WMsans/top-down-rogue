# UI Layout System — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every UI scene in the game share one layout system — one spacing scale, one modal composition, one HUD scene with 9-slice DawnLike frames, so the UI finally feels like part of the game.

**Architecture:** Add a `UILayout` static-constant class for layout tokens. Add a reusable `ModalPanel` scene + script that every modal embeds. Extract two `StyleBoxTexture` resources from `textures/Assets/DawnLike/GUI/GUI0.png` (via `AtlasTexture` regions — no PNG editing). Extend the existing `UiTheme` autoload with button-size defaults, two button theme variations, and a registry of "accent overlay" NinePatchRects retinted on biome change. Replace `health_ui.tscn` and `weapon_button.tscn` with one `hud.tscn` (TL = health+gold frame, TR = weapon frame). Migrate eight UI scenes to instance `ModalPanel`.

**Tech Stack:** Godot 4, GDScript, gdUnit4 (`extends GdUnitTestSuite`).

**Spec:** `docs/superpowers/specs/2026-05-25-ui-layout-system-design.md`.

**Naming note.** The spec uses the abstract name `UIPalette`; the actual project autoload is `UiTheme` (`src/ui/ui_theme.gd`). All tasks below interact with `UiTheme`. The spec's `panel_frame.tres` / `inset_frame.tres` are written under `resources/ui/styles/`.

**TDD note.** Pure-script logic (tokens, overlay registration, ModalPanel API) gets gdUnit4 tests. Scene-structure migrations cannot be meaningfully unit-tested in Godot; they get **manual verification steps** in the Godot editor plus runtime smoke checks (open the scene, no errors in output panel).

---

## Task 1: `UILayout` token class

**Files:**
- Create: `src/ui/ui_layout.gd`
- Test: `tests/unit/test_ui_layout.gd`

- [ ] **Step 1: Write the failing test**

`tests/unit/test_ui_layout.gd`:

```gdscript
extends GdUnitTestSuite

const UILayout = preload("res://src/ui/ui_layout.gd")

func test_spacing_scale_values() -> void:
	assert_that(UILayout.XS).is_equal(4)
	assert_that(UILayout.S).is_equal(8)
	assert_that(UILayout.M).is_equal(16)
	assert_that(UILayout.L).is_equal(24)
	assert_that(UILayout.XL).is_equal(32)

func test_modal_widths() -> void:
	assert_that(UILayout.MODAL_SM).is_equal(320)
	assert_that(UILayout.MODAL_MD).is_equal(480)
	assert_that(UILayout.MODAL_LG).is_equal(640)

func test_modal_width_for_enum() -> void:
	assert_that(UILayout.modal_width_for(UILayout.ModalWidth.SM)).is_equal(320)
	assert_that(UILayout.modal_width_for(UILayout.ModalWidth.MD)).is_equal(480)
	assert_that(UILayout.modal_width_for(UILayout.ModalWidth.LG)).is_equal(640)

func test_button_and_panel_constants() -> void:
	assert_that(UILayout.PANEL_PAD_X).is_equal(24)
	assert_that(UILayout.PANEL_PAD_Y).is_equal(24)
	assert_that(UILayout.HUD_GUTTER).is_equal(16)
	assert_that(UILayout.BUTTON_MIN_HEIGHT).is_equal(40)
	assert_that(UILayout.BUTTON_COMPACT_MIN_WIDTH).is_equal(96)
	assert_that(UILayout.BUTTON_ICON_SIZE).is_equal(32)
	assert_that(UILayout.TITLE_BAR_HEIGHT).is_equal(48)
	assert_that(UILayout.SEPARATOR_PAD).is_equal(8)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ui_layout.gd`
Expected: FAIL with "Could not load res://src/ui/ui_layout.gd".

- [ ] **Step 3: Write the class**

`src/ui/ui_layout.gd`:

```gdscript
class_name UILayout
extends RefCounted

## Single source of truth for UI layout magic numbers. Referenced by
## ModalPanel, HUD, and theme variations in UiTheme. No .tscn file
## should hardcode layout integers that exist here.

# Spacing scale (px). XS only for inline gaps inside rows.
const XS := 4
const S  := 8
const M  := 16
const L  := 24
const XL := 32

# Modal widths.
const MODAL_SM := 320
const MODAL_MD := 480
const MODAL_LG := 640
enum ModalWidth { SM, MD, LG }

static func modal_width_for(w: ModalWidth) -> int:
	match w:
		ModalWidth.SM: return MODAL_SM
		ModalWidth.MD: return MODAL_MD
		ModalWidth.LG: return MODAL_LG
	return MODAL_MD

# Inner padding for every ModalPanel.
const PANEL_PAD_X := 24
const PANEL_PAD_Y := 24

# HUD gutter from screen edge.
const HUD_GUTTER := 16

# Buttons.
const BUTTON_MIN_HEIGHT        := 40
const BUTTON_COMPACT_MIN_WIDTH := 96
const BUTTON_ICON_SIZE         := 32

# Title bar + separators.
const TITLE_BAR_HEIGHT := 48
const SEPARATOR_PAD    := 8
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ui_layout.gd`
Expected: PASS, 4 tests green.

- [ ] **Step 5: Commit**

```bash
git add src/ui/ui_layout.gd tests/unit/test_ui_layout.gd
git commit -m "feat(ui): add UILayout token class"
```

---

## Task 2: 9-slice frame textures from `GUI0.png`

**Files:**
- Create: `textures/ui/panel_frame_atlas.tres`
- Create: `textures/ui/inset_frame_atlas.tres`
- Create: `textures/ui/panel_frame_border_atlas.tres`
- Create: `resources/ui/styles/panel_frame.tres`
- Create: `resources/ui/styles/inset_frame.tres`

The DawnLike `GUI0.png` bottom-grid contains 9-slice frame cells. We extract them with `AtlasTexture` (no PNG editing). The grid is 8 cells wide × 4 cells tall starting below the icon/bar strips. Each cell is **24×24 px** in the source.

**Cell selection (final, confirmed against the sheet shown in chat):**
- `panel_frame` — bottom-grid, **column 7, row 0** (zero-indexed) — light-cream bevel on dark fill, the cleanest neutral.
- `inset_frame` — bottom-grid, **column 6, row 0** — grey bevel on dark fill, for HUD and inset rows.
- `panel_frame_border` — identical region to `panel_frame`. Used as an overlay; tinting via `modulate` recolours only the visible bevel (the centre is opaque dark, so `modulate` darkens it but the outer NinePatchRect is layered above the PanelContainer's filled stylebox — the dark tint is hidden by the underlying fill).

Open `GUI0.png` once in the Godot editor and use the Inspector to verify the bottom-grid origin. Expected: bottom grid starts at `y = 56` (the top three rows are hearts / bars / icons; mini-icon strip; coloured swatch strip / icon-button strip). The 24×24 cells then begin. If exact pixel origin differs by a few px (sheet may have transparent padding), adjust the `region` offsets below by the same delta — the relative cell positions are unchanged.

Bottom-grid origin: `(x0, y0) = (0, 56)`. Cell stride: 24 px both axes.

- [ ] **Step 1: Create panel-frame atlas texture**

Create `textures/ui/panel_frame_atlas.tres`:

```
[gd_resource type="AtlasTexture" load_steps=2 format=3]

[ext_resource type="Texture2D" path="res://textures/Assets/DawnLike/GUI/GUI0.png" id="1"]

[resource]
atlas = ExtResource("1")
region = Rect2(168, 56, 24, 24)
```

`168 = 7 * 24` (column 7), `56` = bottom-grid `y0`.

- [ ] **Step 2: Create inset-frame atlas texture**

Create `textures/ui/inset_frame_atlas.tres`:

```
[gd_resource type="AtlasTexture" load_steps=2 format=3]

[ext_resource type="Texture2D" path="res://textures/Assets/DawnLike/GUI/GUI0.png" id="1"]

[resource]
atlas = ExtResource("1")
region = Rect2(144, 56, 24, 24)
```

- [ ] **Step 3: Create border-overlay atlas texture**

Create `textures/ui/panel_frame_border_atlas.tres`:

```
[gd_resource type="AtlasTexture" load_steps=2 format=3]

[ext_resource type="Texture2D" path="res://textures/Assets/DawnLike/GUI/GUI0.png" id="1"]

[resource]
atlas = ExtResource("1")
region = Rect2(168, 56, 24, 24)
```

(Same region as `panel_frame` — a NinePatchRect using this and `modulate = accent` will recolour the bevel; see Task 6 for how the overlay is layered so the modulated centre doesn't darken the interior.)

- [ ] **Step 4: Create panel-frame stylebox**

Create `resources/ui/styles/panel_frame.tres`:

```
[gd_resource type="StyleBoxTexture" load_steps=2 format=3]

[ext_resource type="Texture2D" path="res://textures/ui/panel_frame_atlas.tres" id="1"]

[resource]
texture = ExtResource("1")
texture_margin_left = 6.0
texture_margin_top = 6.0
texture_margin_right = 6.0
texture_margin_bottom = 6.0
content_margin_left = 6.0
content_margin_top = 6.0
content_margin_right = 6.0
content_margin_bottom = 6.0
axis_stretch_horizontal = 1
axis_stretch_vertical = 1
```

`axis_stretch = 1` is `AXIS_STRETCH_TILE`. 6-px texture margin matches the visible bevel in the DawnLike cell.

- [ ] **Step 5: Create inset-frame stylebox**

Create `resources/ui/styles/inset_frame.tres`:

```
[gd_resource type="StyleBoxTexture" load_steps=2 format=3]

[ext_resource type="Texture2D" path="res://textures/ui/inset_frame_atlas.tres" id="1"]

[resource]
texture = ExtResource("1")
texture_margin_left = 6.0
texture_margin_top = 6.0
texture_margin_right = 6.0
texture_margin_bottom = 6.0
content_margin_left = 6.0
content_margin_top = 6.0
content_margin_right = 6.0
content_margin_bottom = 6.0
axis_stretch_horizontal = 1
axis_stretch_vertical = 1
```

- [ ] **Step 6: Visual verification in editor**

Open Godot editor, create a temporary test scene (`scenes/ui/_frame_preview.tscn`, do not commit) containing:

```
Control (full-rect)
├── PanelContainer (custom_minimum_size = 320 × 160,
│                   theme_override_styles/panel = panel_frame.tres)
│   └── Label "panel_frame"
└── PanelContainer (anchor below first,
                   custom_minimum_size = 320 × 80,
                   theme_override_styles/panel = inset_frame.tres)
    └── Label "inset_frame"
```

Run the scene (F6). Expected:
- Both panels show a continuous bevelled border with no stretched/blurred corners — corner 6-px regions stay crisp; edges tile cleanly; centre fill is dark.
- If bevel looks pinched: bottom-grid `y0` is off — re-measure the source PNG in an image viewer and adjust `region.position.y` in steps 1–3.
- If bevel is stretched/blurred at corners: `texture_margin` is wrong — try 5 or 7 px.

Delete `scenes/ui/_frame_preview.tscn` before committing.

- [ ] **Step 7: Commit**

```bash
git add textures/ui/ resources/ui/styles/
git commit -m "feat(ui): add 9-slice frame textures from DawnLike GUI0"
```

---

## Task 3: Extend `UiTheme` with button-size defaults and theme variations

**Files:**
- Modify: `src/ui/ui_theme.gd`
- Test: `tests/unit/test_ui_theme_layout.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_ui_theme_layout.gd`:

```gdscript
extends GdUnitTestSuite

const UILayout = preload("res://src/ui/ui_layout.gd")

func test_default_button_min_height_is_button_min_height() -> void:
	var t := UiTheme.get_theme()
	var size: Vector2 = t.get_constant_list("Button").size()
	# Default Button stylebox content margins should produce >= 40 px tall.
	# Easier: check the theme exposes a custom minimum via stylebox content margins.
	var sb: StyleBox = t.get_stylebox("normal", "Button")
	assert_that(sb).is_not_null()

func test_compact_button_variation_registered() -> void:
	var t := UiTheme.get_theme()
	assert_that(t.has_type_variation("CompactButton")).is_true()
	assert_that(t.get_type_variation_base("CompactButton")).is_equal(&"Button")

func test_icon_button_variation_registered() -> void:
	var t := UiTheme.get_theme()
	assert_that(t.has_type_variation("IconButton")).is_true()
	assert_that(t.get_type_variation_base("IconButton")).is_equal(&"Button")

func test_separator_separation_constant() -> void:
	var t := UiTheme.get_theme()
	assert_that(t.get_constant("separation", "HSeparator")).is_equal(UILayout.SEPARATOR_PAD)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ui_theme_layout.gd`
Expected: FAIL — `has_type_variation("CompactButton")` returns false.

- [ ] **Step 3: Add variations + defaults to `ui_theme.gd`**

Open `src/ui/ui_theme.gd`. At the top, after the existing `const` block, add:

```gdscript
const UILayout = preload("res://src/ui/ui_layout.gd")
const PANEL_FRAME_STYLEBOX := preload("res://resources/ui/styles/panel_frame.tres")
const INSET_FRAME_STYLEBOX := preload("res://resources/ui/styles/inset_frame.tres")
```

In `_set_button_styles(t)`, append at the end (after the existing default-Button block):

```gdscript
	# Default min height for every Button.
	t.set_constant("button_min_height_marker", "Button", UILayout.BUTTON_MIN_HEIGHT)
	# CompactButton variation — fixed min width + min height.
	t.set_type_variation("CompactButton", "Button")
	t.set_constant("compact_min_width_marker", "CompactButton", UILayout.BUTTON_COMPACT_MIN_WIDTH)
	# IconButton variation — square min size, reduced content margins.
	t.set_type_variation("IconButton", "Button")
	var icon_normal: StyleBoxFlat = _make_button_stylebox(true)
	icon_normal.content_margin_left = 4
	icon_normal.content_margin_right = 4
	icon_normal.content_margin_top = 4
	icon_normal.content_margin_bottom = 4
	t.set_stylebox("normal", "IconButton", icon_normal)
	t.set_stylebox("hover", "IconButton", _make_button_stylebox(false))
	t.set_stylebox("pressed", "IconButton", _make_button_stylebox(false))
	t.set_stylebox("focused", "IconButton", _make_button_stylebox(false))
```

(The `*_marker` constants are read by `modal_panel.gd` and `compact_button.gd` helpers — see Task 4. Godot themes can't carry `custom_minimum_size` directly, so the helper script reads these constants and applies them to the control.)

In `_set_separator_styles(t)`, change the line `sep.set_content_margin_all(4)` to:

```gdscript
	sep.set_content_margin_all(UILayout.SEPARATOR_PAD)
```

In `_set_container_constants(t)`, leave the existing `separation = 8` for `VBoxContainer` / `HBoxContainer` (matches `UILayout.S`).

Add a new line at the bottom of `_set_container_constants`:

```gdscript
	t.set_constant("separation", "HSeparator", UILayout.SEPARATOR_PAD)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ui_theme_layout.gd`
Expected: PASS, 4 tests green.

- [ ] **Step 5: Add a tiny helper for size constants**

Create `src/ui/min_size_applier.gd`:

```gdscript
class_name MinSizeApplier
extends Node

## Attach to a Button to apply min-size constants from the theme.
## Buttons read theme variations but Godot has no built-in min-size theme
## property, so we apply them at runtime from theme constants.

func _ready() -> void:
	var btn := get_parent() as Button
	if btn == null:
		return
	await btn.ready
	var t := btn.get_theme() if btn.get_theme() != null else UiTheme.get_theme()
	# Default min height for any Button.
	var min_h := t.get_constant("button_min_height_marker", "Button") \
		if t.has_constant("button_min_height_marker", "Button") else 0
	var min_w := 0
	var variation := str(btn.theme_type_variation)
	if variation == "CompactButton":
		min_w = t.get_constant("compact_min_width_marker", "CompactButton") \
			if t.has_constant("compact_min_width_marker", "CompactButton") else 0
	elif variation == "IconButton":
		min_w = UILayout.BUTTON_ICON_SIZE
		min_h = UILayout.BUTTON_ICON_SIZE
	if min_h > 0 or min_w > 0:
		btn.custom_minimum_size = Vector2(max(min_w, btn.custom_minimum_size.x),
		                                  max(min_h, btn.custom_minimum_size.y))
```

(This script will be added as a child of every button via the migration tasks. It is a one-shot — autofree on completion.)

Append to `min_size_applier.gd`:

```gdscript
	queue_free()
```

…just before the implicit end of `_ready`. The final `_ready` should set sizes then free itself.

- [ ] **Step 6: Commit**

```bash
git add src/ui/ui_theme.gd src/ui/min_size_applier.gd tests/unit/test_ui_theme_layout.gd
git commit -m "feat(ui): add button size variations and separator constant"
```

---

## Task 4: `ModalPanel` reusable scene + script

**Files:**
- Create: `src/ui/modal_panel.gd`
- Create: `scenes/ui/components/modal_panel.tscn`
- Test: `tests/unit/test_modal_panel.gd`

- [ ] **Step 1: Write the failing test**

`tests/unit/test_modal_panel.gd`:

```gdscript
extends GdUnitTestSuite

const UILayout = preload("res://src/ui/ui_layout.gd")
const ModalPanelScene = preload("res://scenes/ui/components/modal_panel.tscn")

var _root: Control

func before_test() -> void:
	_root = ModalPanelScene.instantiate()
	add_child(_root)
	await _root.ready

func after_test() -> void:
	_root.queue_free()

func test_default_width_is_md() -> void:
	var panel: PanelContainer = _root.get_node("CenterContainer/Root")
	assert_that(panel.custom_minimum_size.x).is_equal(UILayout.MODAL_MD)

func test_set_width_updates_min_size() -> void:
	_root.width = UILayout.ModalWidth.LG
	# `width` is exported with a setter that updates immediately.
	var panel: PanelContainer = _root.get_node("CenterContainer/Root")
	assert_that(panel.custom_minimum_size.x).is_equal(UILayout.MODAL_LG)

func test_set_title_updates_label() -> void:
	_root.title = "HELLO"
	var label: Label = _root.get_node("CenterContainer/Root/Margin/VBox/TitleBar/TitleLabel")
	assert_that(label.text).is_equal("HELLO")

func test_close_button_hidden_when_disabled() -> void:
	_root.show_close_button = false
	var close: Button = _root.get_node("CenterContainer/Root/Margin/VBox/TitleBar/CloseButton")
	assert_that(close.visible).is_false()

func test_close_requested_emitted_on_close_button() -> void:
	var fired := [false]
	_root.close_requested.connect(func(): fired[0] = true)
	var close: Button = _root.get_node("CenterContainer/Root/Margin/VBox/TitleBar/CloseButton")
	close.pressed.emit()
	assert_that(fired[0]).is_true()

func test_footer_hidden_when_empty() -> void:
	await get_tree().process_frame
	var footer: HBoxContainer = _root.get_node("CenterContainer/Root/Margin/VBox/Footer")
	var sep: HSeparator = _root.get_node("CenterContainer/Root/Margin/VBox/FooterSeparator")
	assert_that(footer.visible).is_false()
	assert_that(sep.visible).is_false()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_modal_panel.gd`
Expected: FAIL — scene file does not exist.

- [ ] **Step 3: Write `modal_panel.gd`**

`src/ui/modal_panel.gd`:

```gdscript
class_name ModalPanel
extends Control

## Reusable modal composition: backdrop + centred panel with title bar,
## body, and footer. Host scenes set `title`, `width`, and add children
## to `get_body()` / `get_footer()`.

const UILayout = preload("res://src/ui/ui_layout.gd")

signal close_requested

@export var width: UILayout.ModalWidth = UILayout.ModalWidth.MD:
	set(value):
		width = value
		_refresh_width()

@export var title: String = "":
	set(value):
		title = value
		_refresh_title()

@export var show_close_button: bool = true:
	set(value):
		show_close_button = value
		_refresh_close_button()

@export var has_backdrop: bool = true:
	set(value):
		has_backdrop = value
		_refresh_backdrop()

@export var close_on_backdrop_click: bool = true

@onready var _backdrop: ColorRect = $Backdrop
@onready var _root: PanelContainer = $CenterContainer/Root
@onready var _title_label: Label = $CenterContainer/Root/Margin/VBox/TitleBar/TitleLabel
@onready var _close_button: Button = $CenterContainer/Root/Margin/VBox/TitleBar/CloseButton
@onready var _header_separator: HSeparator = $CenterContainer/Root/Margin/VBox/HeaderSeparator
@onready var _body: VBoxContainer = $CenterContainer/Root/Margin/VBox/Body
@onready var _footer: HBoxContainer = $CenterContainer/Root/Margin/VBox/Footer
@onready var _footer_separator: HSeparator = $CenterContainer/Root/Margin/VBox/FooterSeparator

func _ready() -> void:
	_close_button.pressed.connect(_on_close_pressed)
	_backdrop.gui_input.connect(_on_backdrop_gui_input)
	_body.child_entered_tree.connect(_on_children_changed)
	_body.child_exiting_tree.connect(_on_children_changed)
	_footer.child_entered_tree.connect(_on_children_changed)
	_footer.child_exiting_tree.connect(_on_children_changed)
	_refresh_width()
	_refresh_title()
	_refresh_close_button()
	_refresh_backdrop()
	_refresh_section_visibility()

func get_body() -> VBoxContainer:
	return _body

func get_footer() -> HBoxContainer:
	return _footer

func _refresh_width() -> void:
	if _root == null:
		return
	_root.custom_minimum_size.x = UILayout.modal_width_for(width)

func _refresh_title() -> void:
	if _title_label == null:
		return
	_title_label.text = title

func _refresh_close_button() -> void:
	if _close_button == null:
		return
	_close_button.visible = show_close_button

func _refresh_backdrop() -> void:
	if _backdrop == null:
		return
	_backdrop.visible = has_backdrop

func _refresh_section_visibility() -> void:
	if _body == null:
		return
	var has_body := _body.get_child_count() > 0
	var has_footer := _footer.get_child_count() > 0
	_header_separator.visible = has_body
	_footer_separator.visible = has_footer
	_footer.visible = has_footer

func _on_children_changed(_node: Node) -> void:
	call_deferred("_refresh_section_visibility")

func _on_close_pressed() -> void:
	close_requested.emit()

func _on_backdrop_gui_input(event: InputEvent) -> void:
	if not close_on_backdrop_click:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_requested.emit()
```

- [ ] **Step 4: Write `modal_panel.tscn`**

`scenes/ui/components/modal_panel.tscn`:

```
[gd_scene load_steps=4 format=3 uid="uid://modalpanel0001"]

[ext_resource type="Script" path="res://src/ui/modal_panel.gd" id="1"]
[ext_resource type="StyleBox" path="res://resources/ui/styles/panel_frame.tres" id="2"]
[ext_resource type="Texture2D" path="res://textures/ui/panel_frame_border_atlas.tres" id="3"]

[node name="ModalPanel" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
script = ExtResource("1")

[node name="Backdrop" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(0, 0, 0, 0.65)
mouse_filter = 0

[node name="CenterContainer" type="CenterContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2

[node name="Root" type="PanelContainer" parent="CenterContainer"]
layout_mode = 2
custom_minimum_size = Vector2(480, 0)
theme_override_styles/panel = ExtResource("2")

[node name="AccentOverlay" type="NinePatchRect" parent="CenterContainer/Root"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("3")
patch_margin_left = 6
patch_margin_top = 6
patch_margin_right = 6
patch_margin_bottom = 6
modulate = Color(1, 1, 1, 1)

[node name="Margin" type="MarginContainer" parent="CenterContainer/Root"]
layout_mode = 2
theme_override_constants/margin_left = 24
theme_override_constants/margin_right = 24
theme_override_constants/margin_top = 24
theme_override_constants/margin_bottom = 24

[node name="VBox" type="VBoxContainer" parent="CenterContainer/Root/Margin"]
layout_mode = 2
theme_override_constants/separation = 16

[node name="TitleBar" type="HBoxContainer" parent="CenterContainer/Root/Margin/VBox"]
layout_mode = 2
custom_minimum_size = Vector2(0, 48)
theme_override_constants/separation = 8

[node name="TitleLabel" type="Label" parent="CenterContainer/Root/Margin/VBox/TitleBar"]
layout_mode = 2
size_flags_horizontal = 3
size_flags_vertical = 5
theme_type_variation = "TitleLabel"
text = ""
horizontal_alignment = 1
vertical_alignment = 1

[node name="CloseButton" type="Button" parent="CenterContainer/Root/Margin/VBox/TitleBar"]
layout_mode = 2
size_flags_vertical = 5
custom_minimum_size = Vector2(32, 32)
theme_type_variation = "IconButton"
text = "X"

[node name="HeaderSeparator" type="HSeparator" parent="CenterContainer/Root/Margin/VBox"]
layout_mode = 2

[node name="Body" type="VBoxContainer" parent="CenterContainer/Root/Margin/VBox"]
layout_mode = 2
size_flags_horizontal = 3
size_flags_vertical = 3
theme_override_constants/separation = 8

[node name="FooterSeparator" type="HSeparator" parent="CenterContainer/Root/Margin/VBox"]
layout_mode = 2

[node name="Footer" type="HBoxContainer" parent="CenterContainer/Root/Margin/VBox"]
layout_mode = 2
size_flags_horizontal = 3
alignment = 1
theme_override_constants/separation = 16
```

- [ ] **Step 5: Run test to verify it passes**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_modal_panel.gd`
Expected: PASS, 6 tests green.

- [ ] **Step 6: Commit**

```bash
git add scenes/ui/components/modal_panel.tscn src/ui/modal_panel.gd tests/unit/test_modal_panel.gd
git commit -m "feat(ui): add reusable ModalPanel composition"
```

---

## Task 5: `UiTheme` accent-overlay registry

**Files:**
- Modify: `src/ui/ui_theme.gd`
- Modify: `src/ui/modal_panel.gd`
- Test: `tests/unit/test_ui_theme_overlay.gd`

- [ ] **Step 1: Write the failing test**

`tests/unit/test_ui_theme_overlay.gd`:

```gdscript
extends GdUnitTestSuite

func test_register_overlay_applies_current_accent() -> void:
	var rect := NinePatchRect.new()
	add_child(rect)
	UiTheme.set_accent(Color(1, 0, 0, 1))
	UiTheme.register_overlay(rect)
	assert_that(rect.modulate).is_equal(Color(1, 0, 0, 1))
	rect.queue_free()

func test_accent_change_updates_registered_overlay() -> void:
	var rect := NinePatchRect.new()
	add_child(rect)
	UiTheme.register_overlay(rect)
	UiTheme.set_accent(Color(0, 1, 0, 1))
	assert_that(rect.modulate).is_equal(Color(0, 1, 0, 1))
	rect.queue_free()

func test_freed_overlay_does_not_break_apply() -> void:
	var rect := NinePatchRect.new()
	add_child(rect)
	UiTheme.register_overlay(rect)
	rect.queue_free()
	await get_tree().process_frame
	# Should not error.
	UiTheme.set_accent(Color(0, 0, 1, 1))
	assert_that(true).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ui_theme_overlay.gd`
Expected: FAIL — `register_overlay` doesn't exist on `UiTheme`.

- [ ] **Step 3: Add the registry to `ui_theme.gd`**

In `src/ui/ui_theme.gd`, change the existing `static var accent: Color = DEFAULT_ACCENT` block area to instance scope. Above `_ready`, add:

```gdscript
var _overlays: Array[WeakRef] = []
```

After `_apply_accent()`, add:

```gdscript
func register_overlay(rect: NinePatchRect) -> void:
	_overlays.append(weakref(rect))
	rect.modulate = accent

func _apply_overlay_modulate() -> void:
	var alive: Array[WeakRef] = []
	for w in _overlays:
		var node = w.get_ref()
		if node != null and is_instance_valid(node):
			node.modulate = accent
			alive.append(w)
	_overlays = alive
```

In `set_accent(c)`, append `_apply_overlay_modulate()` after the existing `_apply_accent()` call:

```gdscript
func set_accent(c: Color) -> void:
	accent = c
	ACCENT = c
	ACCENT_GOLD = c
	PANEL_BORDER = c
	_apply_accent()
	_apply_overlay_modulate()
	palette_changed.emit()
```

- [ ] **Step 4: Wire `ModalPanel` to register its overlay**

In `src/ui/modal_panel.gd`, inside `_ready` add at the end:

```gdscript
	var overlay: NinePatchRect = $CenterContainer/Root/AccentOverlay
	UiTheme.register_overlay(overlay)
```

- [ ] **Step 5: Run tests**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ui_theme_overlay.gd tests/unit/test_modal_panel.gd`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add src/ui/ui_theme.gd src/ui/modal_panel.gd tests/unit/test_ui_theme_overlay.gd
git commit -m "feat(ui): register NinePatchRect overlays for biome retint"
```

---

## Task 6: Migrate `pause_menu.tscn`

**Files:**
- Modify: `scenes/ui/pause_menu.tscn`
- Verify: `src/ui/pause_menu.gd` (may need node-path updates)

- [ ] **Step 1: Read the existing pause_menu.gd**

Run: `cat src/ui/pause_menu.gd`

Identify any `$NodePath` references to `PausePanel/CenterContainer/PauseCard/VBoxContainer/...` and to `ConfirmationPanel/ConfirmationBox/...`. These will need updating in step 4.

- [ ] **Step 2: Replace `PausePanel` with a `ModalPanel` instance**

Rewrite `scenes/ui/pause_menu.tscn`. Final form:

```
[gd_scene load_steps=4 format=3 uid="uid://dc5am8wxl3knp"]

[ext_resource type="Script" path="res://src/ui/pause_menu.gd" id="1_pm"]
[ext_resource type="PackedScene" path="res://scenes/ui/components/modal_panel.tscn" id="2_mp"]
[ext_resource type="PackedScene" path="res://scenes/ui/settings_popup.tscn" id="3_sp"]

[node name="PauseMenu" type="CanvasLayer"]
process_mode = 3
layer = 10
script = ExtResource("1_pm")

[node name="PausePanel" parent="." instance=ExtResource("2_mp")]
unique_name_in_owner = true
title = "PAUSED"
show_close_button = false
width = 0   ; UILayout.ModalWidth.SM

[node name="ResumeButton" type="Button" parent="PausePanel" index="0"]
text = "RESUME"
size_flags_horizontal = 3

[node name="SettingsButton" type="Button" parent="PausePanel" index="0"]
text = "SETTINGS"
size_flags_horizontal = 3

[node name="MainMenuButton" type="Button" parent="PausePanel" index="0"]
text = "MAIN MENU"
size_flags_horizontal = 3

[node name="ConfirmationPanel" parent="." instance=ExtResource("2_mp")]
unique_name_in_owner = true
title = "QUIT?"
show_close_button = false
width = 0
close_on_backdrop_click = false

[node name="MessageLabel" type="Label" parent="ConfirmationPanel"]
text = "All progress will be lost!"
horizontal_alignment = 1

[node name="ConfirmYesButton" type="Button" parent="ConfirmationPanel"]
theme_type_variation = "CompactButton"
text = "YES"
size_flags_horizontal = 3

[node name="ConfirmNoButton" type="Button" parent="ConfirmationPanel"]
theme_type_variation = "CompactButton"
text = "NO"
size_flags_horizontal = 3

[node name="SettingsPopup" parent="." instance=ExtResource("3_sp")]
unique_name_in_owner = true
visible = false
```

**Important:** Godot's `.tscn` format does not actually support `parent="PausePanel" index="0"` to redirect into the modal's body container — children of an instanced scene are added to the root of that instance. To properly inject buttons into `ModalPanel.get_body()`, we set them as children of the instance and then have `pause_menu.gd` re-parent them on `_ready` into the body. Implementation: add an `__inject_into = "body"` meta to the children below, and the `pause_menu.gd` script will move them. See step 3.

Actually, simpler: **use `editable_children = true` on the instance** so the body container is directly addressable in the scene tree:

```
[node name="PausePanel" parent="." instance=ExtResource("2_mp")]
editable_children = true
...
```

Then children can be authored under the body explicitly:

```
[node name="ResumeButton" type="Button"
       parent="PausePanel/CenterContainer/Root/Margin/VBox/Body"]
...
```

Use the `editable_children = true` form throughout this plan.

Final corrected scene:

```
[gd_scene load_steps=4 format=3 uid="uid://dc5am8wxl3knp"]

[ext_resource type="Script" path="res://src/ui/pause_menu.gd" id="1_pm"]
[ext_resource type="PackedScene" path="res://scenes/ui/components/modal_panel.tscn" id="2_mp"]
[ext_resource type="PackedScene" path="res://scenes/ui/settings_popup.tscn" id="3_sp"]

[node name="PauseMenu" type="CanvasLayer"]
process_mode = 3
layer = 10
script = ExtResource("1_pm")

[node name="PausePanel" parent="." instance=ExtResource("2_mp")]
unique_name_in_owner = true
editable_instance = true
title = "PAUSED"
show_close_button = false
width = 0

[node name="ResumeButton" type="Button" parent="PausePanel/CenterContainer/Root/Margin/VBox/Body"]
unique_name_in_owner = true
text = "RESUME"
size_flags_horizontal = 3

[node name="SettingsButton" type="Button" parent="PausePanel/CenterContainer/Root/Margin/VBox/Body"]
unique_name_in_owner = true
text = "SETTINGS"
size_flags_horizontal = 3

[node name="MainMenuButton" type="Button" parent="PausePanel/CenterContainer/Root/Margin/VBox/Body"]
unique_name_in_owner = true
text = "MAIN MENU"
size_flags_horizontal = 3

[node name="ConfirmationPanel" parent="." instance=ExtResource("2_mp")]
unique_name_in_owner = true
editable_instance = true
title = "QUIT?"
show_close_button = false
width = 0
close_on_backdrop_click = false
visible = false

[node name="MessageLabel" type="Label" parent="ConfirmationPanel/CenterContainer/Root/Margin/VBox/Body"]
text = "All progress will be lost!"
horizontal_alignment = 1

[node name="ConfirmYesButton" type="Button" parent="ConfirmationPanel/CenterContainer/Root/Margin/VBox/Footer"]
unique_name_in_owner = true
theme_type_variation = "CompactButton"
text = "YES"
size_flags_horizontal = 3

[node name="ConfirmNoButton" type="Button" parent="ConfirmationPanel/CenterContainer/Root/Margin/VBox/Footer"]
unique_name_in_owner = true
theme_type_variation = "CompactButton"
text = "NO"
size_flags_horizontal = 3

[node name="SettingsPopup" parent="." instance=ExtResource("3_sp")]
unique_name_in_owner = true
visible = false
```

The previously-used `juicy_panel` script on `PausePanel` is removed — `ModalPanel` doesn't have animation yet; if animation is needed it's added later as a separate concern (juicy_panel takes any Control as `animated_root`, so it can be re-attached to the modal's `Root` node in a follow-up).

- [ ] **Step 3: Update `pause_menu.gd`**

Buttons retain `unique_name_in_owner = true`, so `%ResumeButton`, `%SettingsButton`, `%MainMenuButton`, `%ConfirmYesButton`, `%ConfirmNoButton` continue to work.

Open `src/ui/pause_menu.gd`. Replace any `$"PausePanel/CenterContainer/PauseCard/..."` reference with `%ResumeButton` etc. Replace any reference to the old `MessageLabel` path with `%PausePanel.get_node("CenterContainer/Root/Margin/VBox/Body/MessageLabel")` if needed, or give that label `unique_name_in_owner = true` and use `%MessageLabel`.

If the script previously connected to a backdrop or dim layer to dismiss, replace with:

```gdscript
%PausePanel.close_requested.connect(_on_pause_panel_close)
%ConfirmationPanel.close_requested.connect(_on_confirm_close)
```

If the script previously toggled `PausePanel.visible`, that still works — `ModalPanel` is a `Control` so `visible` is a built-in property.

- [ ] **Step 4: Manual verification in editor**

1. Open `scenes/ui/pause_menu.tscn` in Godot. No load errors in the bottom panel.
2. Run the project (F5), enter a game, press Esc.
3. Expected: a small modal (~320 px) appears with title "PAUSED", three full-width buttons of equal height (≥40 px tall), framed by the DawnLike 9-slice with accent-tinted border.
4. Click MAIN MENU. Expected: confirmation modal appears with title "QUIT?", label, two compact YES/NO buttons in a footer row separated from the body by a horizontal line.

- [ ] **Step 5: Commit**

```bash
git add scenes/ui/pause_menu.tscn src/ui/pause_menu.gd
git commit -m "refactor(ui): pause menu uses ModalPanel"
```

---

## Task 7: Migrate `settings_popup.tscn`

**Files:**
- Modify: `scenes/ui/settings_popup.tscn`
- Verify: `src/ui/settings_popup.gd`

- [ ] **Step 1: Rewrite `settings_popup.tscn`**

Replace the whole file with:

```
[gd_scene load_steps=2 format=3 uid="uid://bqx7kc3no7exp"]

[ext_resource type="Script" path="res://src/ui/settings_popup.gd" id="1"]
[ext_resource type="PackedScene" path="res://scenes/ui/components/modal_panel.tscn" id="2"]

[node name="SettingsPopup" instance=ExtResource("2")]
editable_instance = true
script = ExtResource("1")
title = "SETTINGS"
show_close_button = true
width = 1   ; UILayout.ModalWidth.MD

[node name="ScrollContainer" type="ScrollContainer" parent="CenterContainer/Root/Margin/VBox/Body"]
unique_name_in_owner = true
custom_minimum_size = Vector2(0, 320)
size_flags_horizontal = 3
size_flags_vertical = 3
horizontal_scroll_mode = 0

[node name="Content" type="VBoxContainer" parent="CenterContainer/Root/Margin/VBox/Body/ScrollContainer"]
unique_name_in_owner = true
size_flags_horizontal = 3
size_flags_vertical = 3
theme_override_constants/separation = 8

[node name="AudioLabel" type="Label" parent="CenterContainer/Root/Margin/VBox/Body/ScrollContainer/Content"]
text = "-- AUDIO --"

[node name="MasterRow" type="HBoxContainer" parent="CenterContainer/Root/Margin/VBox/Body/ScrollContainer/Content"]

[node name="MasterLabel" type="Label" parent="CenterContainer/Root/Margin/VBox/Body/ScrollContainer/Content/MasterRow"]
size_flags_horizontal = 3
text = "Master"

[node name="MasterSlider" type="HSlider" parent="CenterContainer/Root/Margin/VBox/Body/ScrollContainer/Content/MasterRow"]
unique_name_in_owner = true
size_flags_horizontal = 3
value = 80.0

[node name="MusicRow" type="HBoxContainer" parent="CenterContainer/Root/Margin/VBox/Body/ScrollContainer/Content"]

[node name="MusicLabel" type="Label" parent="CenterContainer/Root/Margin/VBox/Body/ScrollContainer/Content/MusicRow"]
size_flags_horizontal = 3
text = "Music"

[node name="MusicSlider" type="HSlider" parent="CenterContainer/Root/Margin/VBox/Body/ScrollContainer/Content/MusicRow"]
unique_name_in_owner = true
size_flags_horizontal = 3
value = 60.0

[node name="SfxRow" type="HBoxContainer" parent="CenterContainer/Root/Margin/VBox/Body/ScrollContainer/Content"]

[node name="SfxLabel" type="Label" parent="CenterContainer/Root/Margin/VBox/Body/ScrollContainer/Content/SfxRow"]
size_flags_horizontal = 3
text = "SFX"

[node name="SfxSlider" type="HSlider" parent="CenterContainer/Root/Margin/VBox/Body/ScrollContainer/Content/SfxRow"]
unique_name_in_owner = true
size_flags_horizontal = 3
value = 80.0

[node name="HSeparator2" type="HSeparator" parent="CenterContainer/Root/Margin/VBox/Body/ScrollContainer/Content"]

[node name="DisplayLabel" type="Label" parent="CenterContainer/Root/Margin/VBox/Body/ScrollContainer/Content"]
text = "-- DISPLAY --"

[node name="FullscreenRow" type="HBoxContainer" parent="CenterContainer/Root/Margin/VBox/Body/ScrollContainer/Content"]

[node name="FullscreenLabel" type="Label" parent="CenterContainer/Root/Margin/VBox/Body/ScrollContainer/Content/FullscreenRow"]
size_flags_horizontal = 3
text = "Fullscreen"

[node name="FullscreenButton" type="Button" parent="CenterContainer/Root/Margin/VBox/Body/ScrollContainer/Content/FullscreenRow"]
unique_name_in_owner = true
theme_type_variation = "CompactButton"
text = "OFF"

[node name="CrtRow" type="HBoxContainer" parent="CenterContainer/Root/Margin/VBox/Body/ScrollContainer/Content"]

[node name="CrtLabel" type="Label" parent="CenterContainer/Root/Margin/VBox/Body/ScrollContainer/Content/CrtRow"]
size_flags_horizontal = 3
text = "CRT"

[node name="CrtButton" type="Button" parent="CenterContainer/Root/Margin/VBox/Body/ScrollContainer/Content/CrtRow"]
unique_name_in_owner = true
theme_type_variation = "CompactButton"
text = "OFF"

[node name="HSeparator3" type="HSeparator" parent="CenterContainer/Root/Margin/VBox/Body/ScrollContainer/Content"]

[node name="KeysLabel" type="Label" parent="CenterContainer/Root/Margin/VBox/Body/ScrollContainer/Content"]
text = "-- KEY BINDINGS --"

[node name="KeyBindingsContainer" type="VBoxContainer" parent="CenterContainer/Root/Margin/VBox/Body/ScrollContainer/Content"]
unique_name_in_owner = true

[node name="BackButton" type="Button" parent="CenterContainer/Root/Margin/VBox/Footer"]
unique_name_in_owner = true
text = "BACK"
size_flags_horizontal = 3
```

`size_flags_horizontal = 3` (EXPAND_FILL) on BackButton makes it stretch across the footer for a full-width feel; if a compact look is preferred swap `size_flags_horizontal = 4` (SHRINK_CENTER) and add `theme_type_variation = "CompactButton"`.

- [ ] **Step 2: Update `settings_popup.gd`**

The script currently uses `%MasterSlider`, `%MusicSlider`, `%SfxSlider`, `%FullscreenButton`, `%CrtButton`, `%KeyBindingsContainer`, `%CloseButton`, `%BackButton` (or absolute paths). Open `src/ui/settings_popup.gd` and:

- Replace `%CloseButton` references with the `ModalPanel.close_requested` signal:
  ```gdscript
  func _ready() -> void:
      close_requested.connect(_on_close_pressed)
      # ... rest
  ```
  Remove any direct `%CloseButton.pressed.connect(...)` lines.
- Verify other `%name` lookups still resolve — they do, because `unique_name_in_owner = true` is preserved.

- [ ] **Step 3: Manual verification**

1. Open Settings from the pause menu and from the main menu.
2. Expected: 480-px-wide modal, title "SETTINGS" centred with an X close button to its right, body scrolls if content overflows, BACK button in a footer row.

- [ ] **Step 4: Commit**

```bash
git add scenes/ui/settings_popup.tscn src/ui/settings_popup.gd
git commit -m "refactor(ui): settings popup uses ModalPanel"
```

---

## Task 8: Migrate `main_menu.tscn`

**Files:**
- Modify: `scenes/ui/main_menu.tscn`
- Verify: `src/ui/main_menu.gd`

- [ ] **Step 1: Rewrite `main_menu.tscn`**

```
[gd_scene load_steps=4 format=3 uid="uid://c7y2m8wx1knpj"]

[ext_resource type="Script" path="res://src/ui/main_menu.gd" id="1_mn"]
[ext_resource type="PackedScene" path="res://scenes/ui/components/modal_panel.tscn" id="2_mp"]
[ext_resource type="PackedScene" path="res://scenes/ui/settings_popup.tscn" id="3_sp"]

[node name="MainMenu" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_mn")

[node name="Background" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(0.102, 0.078, 0.063, 1)

[node name="MenuCard" parent="." instance=ExtResource("2_mp")]
unique_name_in_owner = true
editable_instance = true
title = "TOP DOWN ROGUE"
show_close_button = false
has_backdrop = false
width = 0

[node name="PlayButton" type="Button" parent="MenuCard/CenterContainer/Root/Margin/VBox/Body"]
unique_name_in_owner = true
text = "PLAY"
size_flags_horizontal = 3

[node name="SettingsButton" type="Button" parent="MenuCard/CenterContainer/Root/Margin/VBox/Body"]
unique_name_in_owner = true
text = "SETTINGS"
size_flags_horizontal = 3

[node name="QuitButton" type="Button" parent="MenuCard/CenterContainer/Root/Margin/VBox/Body"]
unique_name_in_owner = true
text = "QUIT"
size_flags_horizontal = 3

[node name="SettingsPopup" parent="." instance=ExtResource("3_sp")]
unique_name_in_owner = true
visible = false
```

The freestanding `TitleTop` / `TitleBottom` labels are removed; the title is now in the modal's title bar. If "TOP DOWN ROGUE" doesn't fit the 320-px width on one line at title font size, change `width = 1` (MD = 480) — verify visually in step 2.

- [ ] **Step 2: Manual verification**

1. Run with the main menu as starting scene (it already is per `project.godot`).
2. Expected: dark background, one centred SM modal titled "TOP DOWN ROGUE", three full-width buttons. No floating title labels above the card.
3. If title overflows: set `width = 1` in the scene and re-verify.

- [ ] **Step 3: Update `main_menu.gd` if needed**

`%PlayButton`, `%SettingsButton`, `%QuitButton`, `%SettingsPopup` continue to resolve. No changes expected; if the previous script touched `%TitleTop` or `%TitleBottom`, delete those lines.

- [ ] **Step 4: Commit**

```bash
git add scenes/ui/main_menu.tscn src/ui/main_menu.gd
git commit -m "refactor(ui): main menu uses ModalPanel"
```

---

## Task 9: Migrate `death_screen.tscn`

**Files:**
- Modify: `scenes/ui/death_screen.tscn`
- Verify: `src/ui/death_screen.gd`

- [ ] **Step 1: Rewrite `death_screen.tscn`**

Keep the `RedFlash` and `VignetteOverlay` ColorRects as siblings (FX, unrelated to layout). Replace the panel.

```
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://src/ui/death_screen.gd" id="1"]
[ext_resource type="Shader" path="res://shaders/ui/death_vignette.gdshader" id="2"]
[ext_resource type="PackedScene" path="res://scenes/ui/components/modal_panel.tscn" id="3"]

[sub_resource type="ShaderMaterial" id="ShaderMaterial_vignette"]
shader = ExtResource("2")
shader_parameter/pulse_speed = 0.5
shader_parameter/vignette_intensity = 0.9
shader_parameter/vignette_color = Color(0.18, 0.0, 0.0, 1)

[node name="DeathScreen" type="CanvasLayer"]
layer = 20
script = ExtResource("1")

[node name="RedFlash" type="ColorRect" parent="."]
unique_name_in_owner = true
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(1, 0, 0, 0)

[node name="VignetteOverlay" type="ColorRect" parent="."]
unique_name_in_owner = true
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(0, 0, 0, 0)
material = SubResource("ShaderMaterial_vignette")

[node name="DeathPanel" parent="." instance=ExtResource("3")]
unique_name_in_owner = true
editable_instance = true
title = "DEFEATED"
show_close_button = false
width = 1
close_on_backdrop_click = false

[node name="FlavorLabel" type="Label" parent="DeathPanel/CenterContainer/Root/Margin/VBox/Body"]
unique_name_in_owner = true
text = "Your journey ends here..."
horizontal_alignment = 1

[node name="StatsLabel" type="RichTextLabel" parent="DeathPanel/CenterContainer/Root/Margin/VBox/Body"]
unique_name_in_owner = true
custom_minimum_size = Vector2(0, 40)
bbcode_enabled = true
fit_content = true
scroll_active = false

[node name="ContinueButton" type="Button" parent="DeathPanel/CenterContainer/Root/Margin/VBox/Footer"]
unique_name_in_owner = true
theme_type_variation = "CompactButton"
text = "RETURN TO MENU"
size_flags_horizontal = 4
```

The `juicy_panel` script that was attached to `DeathPanel` is dropped from this migration; if the death-screen punch animation is critical, attach `juicy_panel.gd` to `DeathPanel` after migration with `animated_root` and `content_root` pointing at the modal's `Root` and `Body` nodes in a follow-up.

- [ ] **Step 2: Verify `death_screen.gd`**

`%FlavorLabel`, `%StatsLabel`, `%ContinueButton`, `%RedFlash`, `%VignetteOverlay` all continue to resolve. The script's `_ready` should not reference removed nodes (e.g. the old `DiedLabel` is now the modal title).

If the script set `%DiedLabel.text = "DEFEATED"`, replace with `%DeathPanel.title = "DEFEATED"`.

- [ ] **Step 3: Manual verification**

1. Run the game, take fatal damage (use debug command if available, e.g. through `ConsoleManager`).
2. Expected: red flash + vignette as before; death modal is MD (480) wide; title bar shows "DEFEATED"; flavor text + stats in body; one centred RETURN-TO-MENU button in footer.

- [ ] **Step 4: Commit**

```bash
git add scenes/ui/death_screen.tscn src/ui/death_screen.gd
git commit -m "refactor(ui): death screen uses ModalPanel"
```

---

## Task 10: Migrate `weapon_popup.tscn`

**Files:**
- Modify: `scenes/ui/weapon_popup.tscn`
- Verify: `src/ui/weapon_popup.gd`

- [ ] **Step 1: Rewrite `weapon_popup.tscn`**

```
[gd_scene load_steps=3 format=3 uid="uid://bq5fx8kwbtn7r"]

[ext_resource type="Script" path="res://src/ui/weapon_popup.gd" id="1"]
[ext_resource type="PackedScene" path="res://scenes/ui/components/modal_panel.tscn" id="2"]

[node name="WeaponPopup" type="CanvasLayer"]
layer = 17
script = ExtResource("1")

[node name="MainPanel" parent="." instance=ExtResource("2")]
unique_name_in_owner = true
editable_instance = true
title = "WEAPONS"
show_close_button = true
width = 2
close_on_backdrop_click = true

[node name="CardsContainer" type="HBoxContainer" parent="MainPanel/CenterContainer/Root/Margin/VBox/Body"]
unique_name_in_owner = true
theme_override_constants/separation = 24
alignment = 1
size_flags_horizontal = 3
```

(Cards are populated at runtime by `weapon_popup.gd`. `width = 2` is `UILayout.ModalWidth.LG = 640`.)

- [ ] **Step 2: Update `weapon_popup.gd`**

Replace any reference to the old `CenterContainer/VBoxContainer/CardsContainer` path. Cards are now added to `%CardsContainer`. The dismiss handler:

```gdscript
%MainPanel.close_requested.connect(close)
```

(or whatever the existing close method is named.)

- [ ] **Step 3: Manual verification**

1. Pick up a weapon in-game so the popup triggers.
2. Expected: LG modal, title "WEAPONS", row of cards centred horizontally with 24-px separation, X close button works, clicking backdrop closes.

- [ ] **Step 4: Commit**

```bash
git add scenes/ui/weapon_popup.tscn src/ui/weapon_popup.gd
git commit -m "refactor(ui): weapon popup uses ModalPanel"
```

---

## Task 11: Migrate `chest_ui.tscn`

**Files:**
- Modify: `scenes/ui/chest_ui.tscn`
- Verify: `src/ui/chest_ui.gd`

- [ ] **Step 1: Rewrite `chest_ui.tscn`**

```
[gd_scene load_steps=3 format=3 uid="uid://dvhvibginfyur"]

[ext_resource type="Script" path="res://src/ui/chest_ui.gd" id="1"]
[ext_resource type="PackedScene" path="res://scenes/ui/components/modal_panel.tscn" id="2"]

[node name="ChestUI" type="CanvasLayer"]
process_mode = 4
layer = 16
script = ExtResource("1")

[node name="ShopPanel" parent="." instance=ExtResource("2")]
unique_name_in_owner = true
editable_instance = true
title = "CHEST"
show_close_button = true
width = 2

[node name="CardContainer" type="HBoxContainer" parent="ShopPanel/CenterContainer/Root/Margin/VBox/Body"]
unique_name_in_owner = true
theme_override_constants/separation = 24
alignment = 1
size_flags_horizontal = 3
```

The old `Overlay` ColorRect (extra dim layer) is removed — `ModalPanel` already provides a backdrop. `HeaderBar` is removed — the modal title bar replaces it.

- [ ] **Step 2: Update `chest_ui.gd`**

If the script set `%TitleLabel.text = chest_name`, replace with `%ShopPanel.title = chest_name`.
Replace any old `%CardContainer` path (still works — same name).
Remove any code referencing `%Overlay` or `%HeaderBar`.

- [ ] **Step 3: Manual verification**

1. Open a chest in-game.
2. Expected: LG modal, title shows chest name, card row in body, dim backdrop, X close works.

- [ ] **Step 4: Commit**

```bash
git add scenes/ui/chest_ui.tscn src/ui/chest_ui.gd
git commit -m "refactor(ui): chest ui uses ModalPanel"
```

---

## Task 12: Migrate `economy/shop_ui.tscn`

**Files:**
- Modify: `scenes/economy/shop_ui.tscn`
- Verify: `src/economy/shop_ui.gd` (or wherever the controller lives)

- [ ] **Step 1: Inspect existing scene + script**

Run: `cat scenes/economy/shop_ui.tscn`. Note its current structure (likely similar to `chest_ui.tscn` with its own header).

- [ ] **Step 2: Rewrite using the same pattern as Task 11**

Structure mirrors `chest_ui.tscn`: `CanvasLayer` root, one `ModalPanel` instance at LG width with `title = "SHOP"`, a `CardContainer` (or matching node name from the existing script) inside the body, plus any shop-specific controls (e.g. price labels) added as additional Body children or inside the card subtree.

Use `editable_instance = true` and the same `parent="ShopPanel/CenterContainer/Root/Margin/VBox/Body"` path pattern. Set `theme_override_constants/separation = 24` on the card row.

If the shop UI has a "Refresh" or "Leave" button, place it in the modal's `Footer` as a `CompactButton` variation.

- [ ] **Step 3: Update the controller script**

Resolve any node-path references the same way as Task 11. Preserve `unique_name_in_owner = true` on every node the script references.

- [ ] **Step 4: Manual verification**

1. Enter a shop in-game.
2. Expected: LG modal, "SHOP" title, card row matches chest UI's visual treatment.

- [ ] **Step 5: Commit**

```bash
git add scenes/economy/shop_ui.tscn src/economy/shop_ui.gd
git commit -m "refactor(ui): shop ui uses ModalPanel"
```

---

## Task 13: Build `hud.tscn` and remove `health_ui.tscn` + `weapon_button.tscn`

**Files:**
- Create: `scenes/ui/hud.tscn`
- Create: `src/ui/hud.gd`
- Delete: `scenes/ui/health_ui.tscn`
- Delete: `src/ui/health_ui.gd`
- Delete: `scenes/ui/weapon_button.tscn`
- Delete: `src/ui/weapon_button.gd`
- Modify: `scenes/game.tscn`
- Modify: any GDScript that references `$HealthUI` / `$WeaponButton`

- [ ] **Step 1: Discover all callers**

Run:
```bash
rg "HealthUI|WeaponButton|health_ui|weapon_button" src/ scenes/ tests/
```

Note every file that touches these node names. Each will need an update.

- [ ] **Step 2: Write `hud.gd`**

`src/ui/hud.gd`:

```gdscript
extends CanvasLayer

## Single HUD: TL = health + gold (one framed cluster), TR = weapon
## (matching framed cluster). Replaces health_ui.gd + weapon_button.gd.

const UILayout = preload("res://src/ui/ui_layout.gd")

@onready var _health_bar_fill: ColorRect = %BarFill
@onready var _health_label: RichTextLabel = %HealthLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _weapon_icon: TextureButton = %WeaponIconButton
@onready var _weapon_fallback: ColorRect = %WeaponFallback
@onready var _weapon_tooltip: PanelContainer = %WeaponTooltip
@onready var _weapon_tooltip_name: Label = %WeaponTooltipName
@onready var _weapon_tooltip_cd: Label = %WeaponTooltipCooldown
@onready var _weapon_tooltip_dmg: Label = %WeaponTooltipDamage

func set_health(current: int, max_value: int) -> void:
	var ratio := 0.0 if max_value <= 0 else clampf(float(current) / float(max_value), 0.0, 1.0)
	_health_bar_fill.anchor_right = ratio
	_health_label.text = "%d / %d" % [current, max_value]

func set_gold(amount: int) -> void:
	_gold_label.text = str(amount)

func set_weapon_icon(texture: Texture2D) -> void:
	if texture == null:
		_weapon_icon.texture_normal = null
		_weapon_fallback.visible = true
	else:
		_weapon_icon.texture_normal = texture
		_weapon_fallback.visible = false

func set_weapon_tooltip(name: String, cooldown: float, damage: int) -> void:
	_weapon_tooltip_name.text = name
	_weapon_tooltip_cd.text = "Cooldown: %.1fs" % cooldown
	_weapon_tooltip_dmg.text = "Damage: %d" % damage

func show_weapon_tooltip(show: bool) -> void:
	_weapon_tooltip.visible = show
```

Confirm the actual method signatures expected by callers (from step 1) and rename methods if they differ. The bodies above mirror what `health_ui.gd` and `weapon_button.gd` currently expose.

- [ ] **Step 3: Write `hud.tscn`**

```
[gd_scene load_steps=4 format=3 uid="uid://hud00000001"]

[ext_resource type="Script" path="res://src/ui/hud.gd" id="1"]
[ext_resource type="StyleBox" path="res://resources/ui/styles/inset_frame.tres" id="2"]
[ext_resource type="Shader" path="res://shaders/ui/health_bar_shimmer.gdshader" id="3"]

[sub_resource type="ShaderMaterial" id="ShaderMaterial_shimmer"]
shader = ExtResource("3")

[node name="HUD" type="CanvasLayer"]
layer = 5
script = ExtResource("1")

;========== TOP LEFT CLUSTER ==========
[node name="TopLeft" type="MarginContainer" parent="."]
anchors_preset = -1
anchor_left = 0.0
anchor_top = 0.0
theme_override_constants/margin_left = 16
theme_override_constants/margin_top = 16
theme_override_constants/margin_right = 16
theme_override_constants/margin_bottom = 16

[node name="Frame" type="PanelContainer" parent="TopLeft"]
theme_override_styles/panel = ExtResource("2")

[node name="InnerMargin" type="MarginContainer" parent="TopLeft/Frame"]
theme_override_constants/margin_left = 12
theme_override_constants/margin_top = 12
theme_override_constants/margin_right = 12
theme_override_constants/margin_bottom = 12

[node name="VBox" type="VBoxContainer" parent="TopLeft/Frame/InnerMargin"]
theme_override_constants/separation = 4

[node name="HealthBar" type="Panel" parent="TopLeft/Frame/InnerMargin/VBox"]
unique_name_in_owner = true
custom_minimum_size = Vector2(220, 32)
clip_contents = true

[node name="BarFill" type="ColorRect" parent="TopLeft/Frame/InnerMargin/VBox/HealthBar"]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 12
anchor_top = 0.0
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 0
grow_vertical = 2
color = Color(1, 0.42, 0.208, 1)
material = SubResource("ShaderMaterial_shimmer")

[node name="HealthLabel" type="RichTextLabel" parent="TopLeft/Frame/InnerMargin/VBox/HealthBar"]
unique_name_in_owner = true
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
bbcode_enabled = true
fit_content = true
scroll_active = false
text = "100 / 100"

[node name="GoldRow" type="HBoxContainer" parent="TopLeft/Frame/InnerMargin/VBox"]
theme_override_constants/separation = 8

[node name="GoldIcon" type="TextureRect" parent="TopLeft/Frame/InnerMargin/VBox/GoldRow"]
texture_filter = 1
custom_minimum_size = Vector2(16, 16)

[node name="GoldLabel" type="Label" parent="TopLeft/Frame/InnerMargin/VBox/GoldRow"]
unique_name_in_owner = true
size_flags_horizontal = 3
text = "0"

;========== TOP RIGHT CLUSTER ==========
[node name="TopRight" type="MarginContainer" parent="."]
anchors_preset = -1
anchor_left = 1.0
anchor_top = 0.0
anchor_right = 1.0
anchor_bottom = 0.0
offset_left = -120.0
offset_top = 0.0
offset_right = 0.0
offset_bottom = 120.0
grow_horizontal = 0
theme_override_constants/margin_left = 16
theme_override_constants/margin_top = 16
theme_override_constants/margin_right = 16
theme_override_constants/margin_bottom = 16

[node name="Frame" type="PanelContainer" parent="TopRight"]
theme_override_styles/panel = ExtResource("2")

[node name="InnerMargin" type="MarginContainer" parent="TopRight/Frame"]
theme_override_constants/margin_left = 8
theme_override_constants/margin_top = 8
theme_override_constants/margin_right = 8
theme_override_constants/margin_bottom = 8

[node name="VBox" type="VBoxContainer" parent="TopRight/Frame/InnerMargin"]
theme_override_constants/separation = 4

[node name="WeaponIconButton" type="TextureButton" parent="TopRight/Frame/InnerMargin/VBox"]
unique_name_in_owner = true
custom_minimum_size = Vector2(64, 64)
stretch_mode = 5

[node name="WeaponFallback" type="ColorRect" parent="TopRight/Frame/InnerMargin/VBox/WeaponIconButton"]
unique_name_in_owner = true
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(0.212, 0.110, 0.133, 1)

[node name="WeaponFallbackLabel" type="Label" parent="TopRight/Frame/InnerMargin/VBox/WeaponIconButton/WeaponFallback"]
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -8.0
offset_top = -8.0
offset_right = 8.0
offset_bottom = 8.0
grow_horizontal = 2
grow_vertical = 2
text = "?"

;========== WEAPON TOOLTIP (right of weapon, hidden by default) ==========
[node name="WeaponTooltip" type="PanelContainer" parent="."]
unique_name_in_owner = true
visible = false
anchors_preset = -1
anchor_left = 1.0
anchor_top = 0.0
anchor_right = 1.0
anchor_bottom = 0.0
offset_left = -310.0
offset_top = 16.0
offset_right = -130.0
offset_bottom = 96.0
grow_horizontal = 0

[node name="TooltipMargin" type="MarginContainer" parent="WeaponTooltip"]
theme_override_constants/margin_left = 8
theme_override_constants/margin_right = 8
theme_override_constants/margin_top = 8
theme_override_constants/margin_bottom = 8

[node name="TooltipVBox" type="VBoxContainer" parent="WeaponTooltip/TooltipMargin"]
theme_override_constants/separation = 4

[node name="WeaponTooltipName" type="Label" parent="WeaponTooltip/TooltipMargin/TooltipVBox"]
unique_name_in_owner = true
text = "Weapon"

[node name="WeaponTooltipCooldown" type="Label" parent="WeaponTooltip/TooltipMargin/TooltipVBox"]
unique_name_in_owner = true
text = "Cooldown: 0.5s"

[node name="WeaponTooltipDamage" type="Label" parent="WeaponTooltip/TooltipMargin/TooltipVBox"]
unique_name_in_owner = true
text = "Damage: 0"
```

The gold icon texture is set in step 4 (from a region of GUI0.png).

- [ ] **Step 4: Add gold icon atlas**

Create `textures/ui/gold_icon_atlas.tres`:

```
[gd_resource type="AtlasTexture" load_steps=2 format=3]

[ext_resource type="Texture2D" path="res://textures/Assets/DawnLike/GUI/GUI0.png" id="1"]

[resource]
atlas = ExtResource("1")
region = Rect2(0, 40, 16, 16)
```

(The small coin/gem swatch row sits just below the heart/bar strip — confirm `region` against the source PNG; expected x=0, y=40 for the first 16×16 swatch. Adjust if the chosen swatch isn't a gold coin visually.)

In `hud.tscn`, set the `GoldIcon` node's `texture` property to `res://textures/ui/gold_icon_atlas.tres` (add as `ext_resource` in the header and reference).

- [ ] **Step 5: Update `scenes/game.tscn`**

Open `scenes/game.tscn`. Find lines 9, 12, 62, 72 (per the grep earlier):

```
[ext_resource type="PackedScene" uid="uid://bwg73brg2igl1" path="res://scenes/ui/health_ui.tscn" id="10"]
[ext_resource type="PackedScene" uid="uid://bq3fx8kwbtn7q" path="res://scenes/ui/weapon_button.tscn" id="13"]
...
[node name="HealthUI" parent="." instance=ExtResource("10")]
...
[node name="WeaponButton" parent="." instance=ExtResource("13")]
```

Replace with:

```
[ext_resource type="PackedScene" uid="uid://hud00000001" path="res://scenes/ui/hud.tscn" id="10"]
...
[node name="HUD" parent="." instance=ExtResource("10")]
```

Remove the now-unused `ExtResource("13")` declaration and the `WeaponButton` node. Save.

- [ ] **Step 6: Update callers**

For every file from step 1's grep that called `$HealthUI.set_health(...)` or similar, change to `$HUD.set_health(...)`. Same for `$WeaponButton.set_icon(...)` → `$HUD.set_weapon_icon(...)`.

If the names differed previously (e.g. `set_max(x)` then `set_value(y)`), preserve those by adding matching shim methods to `hud.gd` rather than changing every caller.

- [ ] **Step 7: Delete old scenes/scripts**

```bash
git rm scenes/ui/health_ui.tscn src/ui/health_ui.gd
git rm scenes/ui/weapon_button.tscn src/ui/weapon_button.gd
```

- [ ] **Step 8: Manual verification**

1. Run a game.
2. Expected: TL of the screen shows one DawnLike-framed cluster with the health bar above a gold readout; TR shows a matching framed cluster with the weapon icon. Both frames have identical 9-slice texture and sit 16 px from their respective screen edges.
3. Taking damage updates the health bar fill width and label.
4. Picking up gold updates `GoldLabel`.
5. Picking up a weapon updates `WeaponIconButton.texture_normal`.
6. Hovering the weapon icon shows the tooltip to its left.

- [ ] **Step 9: Commit**

```bash
git add scenes/ui/hud.tscn src/ui/hud.gd textures/ui/gold_icon_atlas.tres scenes/game.tscn src/
git commit -m "feat(ui): unify HUD into single hud.tscn with framed clusters"
```

---

## Task 14: Update `card.tscn` to use shared frame

**Files:**
- Modify: `scenes/ui/card.tscn`

- [ ] **Step 1: Replace `StyleBox_card_panel` with `panel_frame.tres`**

In `scenes/ui/card.tscn`, find the existing inline `StyleBoxFlat` sub_resource `StyleBox_card_panel`. Delete it. In `CardPanel`'s `theme_override_styles/panel`, change from `SubResource("StyleBox_card_panel")` to:

```
[ext_resource type="StyleBox" path="res://resources/ui/styles/panel_frame.tres" id="3_panel_frame"]
...
[node name="CardPanel" ...]
theme_override_styles/panel = ExtResource("3_panel_frame")
```

Keep all other card properties (160×240 size, fake_3d shader, ContentVBox layout) unchanged.

- [ ] **Step 2: Manual verification**

1. Open the weapon popup, chest UI, or shop UI in-game.
2. Expected: each card now uses the same 9-slice frame as modals (the texture is shared) — cards visually feel like part of the modal family.

- [ ] **Step 3: Commit**

```bash
git add scenes/ui/card.tscn
git commit -m "refactor(ui): card uses shared panel_frame stylebox"
```

---

## Task 15: Acceptance grep + final cleanup

**Files:**
- Verify: all `scenes/**/*.tscn`

- [ ] **Step 1: Hardcoded-width check**

Run:
```bash
rg "custom_minimum_size = Vector2\((320|480|640|520|400|280|240)," scenes/ui/ scenes/economy/
```

Expected output: zero hits outside `scenes/ui/components/modal_panel.tscn`. If any hit appears, locate the scene and confirm whether the value should come from `ModalPanel.width` instead.

- [ ] **Step 2: Separation values check**

Run:
```bash
rg "theme_override_constants/separation = " scenes/ui/ scenes/economy/
```

Expected: every value is in `{4, 8, 16, 24, 32}`. Any 12, 20, 48 etc. is a leftover — open that scene and round to the nearest scale value.

- [ ] **Step 3: Margin values check**

Run:
```bash
rg "theme_override_constants/margin_(left|top|right|bottom) = " scenes/ui/ scenes/economy/
```

Expected: each value in `{4, 8, 12, 16, 24}` (12 is allowed only inside HUD `InnerMargin`). Anything else (28, 32, 40) is a leftover — fix.

- [ ] **Step 4: Stylebox check**

Run:
```bash
rg "StyleBoxFlat" scenes/ui/ scenes/economy/
```

Expected: zero hits in modal/HUD scenes. `StyleBoxFlat` may still appear for purely-decorative sub-elements; review each remaining occurrence and decide whether it should also use a `StyleBoxTexture` from `resources/ui/styles/`.

- [ ] **Step 5: Run all UI-related tests**

Run:
```bash
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_ui_layout.gd -a tests/unit/test_ui_theme_layout.gd -a tests/unit/test_ui_theme_overlay.gd -a tests/unit/test_modal_panel.gd
```

Expected: all green.

- [ ] **Step 6: Manual end-to-end pass**

1. Launch the game.
2. Main menu → settings → back → play.
3. Take damage; pick up gold; pick up a weapon; open weapon popup; open chest; open shop.
4. Esc → pause menu → settings → back; main-menu confirmation.
5. Die; confirm death screen looks right; return to menu.
6. For every modal listed above, eyeball: same title-bar height, same inner padding (24 px), same panel frame texture, same accent-tinted border.
7. Switch biomes (or simulate via console) and confirm panel borders and HUD frames retint together while interior fills stay dark.

- [ ] **Step 7: Final commit (only if anything was tweaked in steps 1–6)**

```bash
git add -u
git commit -m "chore(ui): final layout-pass cleanup"
```

---

## Self-Review

- **Spec coverage:**
  - Subsystem 1 (tokens) → Task 1.
  - Subsystem 2 (ModalPanel) → Tasks 4, 6–12.
  - Subsystem 3 (9-slice frames) → Task 2.
  - Subsystem 4 (theme additions) → Task 3.
  - Subsystem 5 (biome-accent overlay) → Task 5.
  - Subsystem 6 (HUD scene) → Task 13.
  - Subsystem 7 (per-scene migration table) → Tasks 6–12, 14.
  - Subsystem 8 (cleanups) → Task 15.
  - Acceptance criteria → Task 15 steps 1–4 and step 6.

- **Placeholder scan:** no TBDs. The shop_ui structure note in Task 12 is a "verify existing controls and mirror Task 11" instruction, not a placeholder — it preserves any controls the engineer finds without me inventing names I cannot confirm.

- **Type consistency:** `ModalPanel.width: UILayout.ModalWidth`, the `modal_width_for(...)` helper, `register_overlay(rect: NinePatchRect)` and `_apply_overlay_modulate()` are referenced consistently across Tasks 1, 4, 5. `set_health(current, max_value)` / `set_gold(amount)` / `set_weapon_icon(texture)` in Task 13 are documented as the HUD API.

- **Plan structural risk:** Task 13 depends on accurate inventory of `$HealthUI` / `$WeaponButton` callers; the grep step (13.1) gates this discovery before code changes. If a caller uses unusual method names, step 13.6 instructs adding shims rather than mass-renaming.
