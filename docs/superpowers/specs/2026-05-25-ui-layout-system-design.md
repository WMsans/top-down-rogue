# UI Layout System — Design

**Date:** 2026-05-25
**Status:** Draft, awaiting implementation plan
**Builds on:** `2026-05-23-ui-consistency-and-crt-design.md` (palette, font, CRT)

## Problem

The earlier UI-consistency pass unified typography, palette, and post-process, but **layout** was left untouched. The result is a UI that uses the right colors and font yet still feels incoherent because every scene reinvents its own structure:

- **Three different modal sizing idioms.** `PauseMenu` uses `CenterContainer` with an auto-sized panel; `SettingsPopup` hardcodes `offset_left=-200, offset_top=-220, …` for a fixed 400×440 box; `DeathPanel` uses `custom_minimum_size = (520, 0)`; `MainMenu.MenuCard` uses hardcoded 280×160 offsets; the in-pause confirmation uses 240×80 offsets.
- **No spacing scale.** VBox separations across scenes are 4, 8, 12, 20, 32, 48 — chosen ad hoc.
- **Inconsistent inner padding.** `DeathPanel` wraps content in `MarginContainer(40/32)`; `ChestUI` uses `MarginContainer(24/28)`; `PauseMenu` relies on stylebox padding only; `SettingsPopup` has no padding at all between its VBox and the panel border.
- **Ad-hoc HUD placement.** `HealthUI` anchors at 12 px from the top-left; `WeaponButton` anchors at 8 px from the top-right; the two never share a coordinate system or a frame.
- **No standard header/footer pattern.** Settings has an HBox(Title, X) plus `HSeparator`; `ChestUI` builds its own `HeaderBar` `PanelContainer`; `PauseMenu` has a bare title `Label` as the first VBox child.
- **Mixed corner radii and stylebox families.** `HealthUI` radius=4, `DeathPanel` radius=10, `Card` radius=0, others derive from the shared theme. All use `StyleBoxFlat` despite the project shipping the DawnLike `GUI0.png` sheet of 9-slice frames.

## Goals

1. One set of layout tokens (spacing, modal widths, padding, button sizes) used by every UI scene.
2. One standard modal composition — title bar, body, footer — instantiated by every modal in the project.
3. One HUD scene with two corner clusters (TL = health + gold, TR = weapon) framed by 9-slice panels from `GUI0.png`.
4. Pixel-art-textured panels using 9-slice from `GUI0.png` instead of `StyleBoxFlat`, with biome accent applied via a border-only overlay so the dark fill stays dark.
5. Zero changes to gameplay, world art, the CRT shader, the palette/font theme, or the `juicy_panel` animation behaviour.

## Non-Goals

- Animation, timing, easing, juice — covered by `juicy_panel.gd`, untouched.
- Theme colours, font, font sizes — set by `main_theme.tres` and `2026-05-23-ui-consistency-and-crt-design.md`, untouched.
- CRT shader and global post-process — untouched.
- Card flip / `fake_3d.gdshader` and card visuals — untouched apart from swapping its `StyleBoxFlat` for the shared 9-slice frame.
- New iconography, new fonts, accessibility / high-contrast modes, resolution-responsive scaling.
- Per-row redesign inside the settings panel (sliders, key-binding rows) beyond inheriting the new theme variations.

## Design

### Subsystem 1 — Layout tokens

**File (new):** `src/ui/ui_layout.gd`

```gdscript
class_name UILayout
extends RefCounted

# Spacing scale (px). XS only for inline gaps.
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

# Inner padding for every ModalPanel.
const PANEL_PAD_X := 24
const PANEL_PAD_Y := 24

# HUD gutter from screen edge.
const HUD_GUTTER := 16

# Buttons.
const BUTTON_MIN_HEIGHT       := 40
const BUTTON_COMPACT_MIN_WIDTH := 96
const BUTTON_ICON_SIZE         := 32

# Title bar + separators.
const TITLE_BAR_HEIGHT := 48
const SEPARATOR_PAD    := 8
```

This file is the **sole** source for these magic numbers. Scenes reference them via the `ModalPanel` script or via theme variations defined in `main_theme.tres`; raw integers do not appear in `.tscn` files for layout-related properties.

### Subsystem 2 — `ModalPanel` reusable scene

**Files (new):**
- `scenes/ui/components/modal_panel.tscn`
- `src/ui/modal_panel.gd`

**Structure:**

```
ModalPanel : Control                              (full-rect, transparent)
├── Backdrop : ColorRect                          (full-rect, color = (0,0,0,0.65), blocks mouse)
└── CenterContainer                               (full-rect)
    └── Root : PanelContainer                     (style = panel_frame.tres)
        custom_minimum_size = (width_from_export, 0)
        ├── AccentOverlay : NinePatchRect         (anchors full, modulate = biome accent,
        │                                          texture = panel_frame_border.png)
        └── Margin : MarginContainer              (PANEL_PAD_X / PANEL_PAD_Y all sides)
            └── VBox                              (separation = M=16)
                ├── TitleBar : HBoxContainer      (custom_minimum_size.y = TITLE_BAR_HEIGHT=48)
                │   ├── TitleLabel : Label        (size_flags_h = EXPAND_FILL, h_align = CENTER,
                │   │                              theme_type_variation = "TitleLabel")
                │   └── CloseButton : Button      (theme_type_variation = "IconButton",
                │                                  custom_minimum_size = (32,32),
                │                                  text = "X", optional)
                ├── HeaderSeparator : HSeparator
                ├── Body : VBoxContainer          (separation = S=8,
                │                                  size_flags_v = EXPAND_FILL)
                ├── FooterSeparator : HSeparator
                └── Footer : HBoxContainer        (separation = M=16, alignment = CENTER,
                                                   size_flags_h = EXPAND_FILL)
```

**`modal_panel.gd` API:**

```gdscript
class_name ModalPanel
extends Control

@export var width: UILayout.ModalWidth = UILayout.ModalWidth.MD
@export var title: String = "":
    set(value): title = value; _refresh_title()
@export var show_close_button: bool = true
@export var show_header_separator: bool = true
@export var show_footer_separator: bool = true
@export var has_backdrop: bool = true
@export var close_on_backdrop_click: bool = true

signal close_requested

# Read-only access for host scenes to inject content.
func get_body() -> VBoxContainer
func get_footer() -> HBoxContainer
```

Behaviour:

- On `_ready`, sets `Root.custom_minimum_size.x` to one of `MODAL_SM / MODAL_MD / MODAL_LG`.
- `Backdrop.visible = has_backdrop`. `CloseButton.visible = show_close_button`. Emits `close_requested` on close-button press and on backdrop click (when `close_on_backdrop_click`).
- If `Body.get_child_count() == 0`, hides `HeaderSeparator` (no point separating title from empty space).
- If `Footer.get_child_count() == 0`, hides `Footer` and `FooterSeparator`.
- Re-evaluates the two checks above on `child_entered_tree` / `child_exiting_tree` of `Body` and `Footer` so host scenes that add children at runtime stay correct.

**Animation compatibility.** `juicy_panel.gd` is currently attached to per-modal Controls with `animated_root` / `content_root` paths. `ModalPanel` exposes those same node paths through script properties (`animated_root = Root`, `content_root = Body`) so host scenes that previously instanced `juicy_panel` can attach it to the `ModalPanel` root with no behavioural change.

### Subsystem 3 — 9-slice frames from `GUI0.png`

**Files (new):**
- `resources/ui/styles/panel_frame.tres` — `StyleBoxTexture`, sampled from the cleanest neutral cell in the bottom-grid of `GUI0.png` (final cell selection during implementation; the top-right "light-bevel on dark fill" cell is the current pick). Used by `ModalPanel.Root`, `Card.CardPanel`, and any other large panel.
- `resources/ui/styles/inset_frame.tres` — `StyleBoxTexture`, sampled from the dark-on-dark variant (top-left cell). Used by HUD `Frame` containers and any inset row (slider track background, key-binding row).
- `textures/ui/panel_frame_border.png` — same source frame as `panel_frame.tres` but with the centre fill made transparent, used as the `AccentOverlay.texture` so border-only tinting is possible.

**Stylebox configuration (both):**

```
texture_margin_left  = 6
texture_margin_top   = 6
texture_margin_right = 6
texture_margin_bottom = 6
axis_stretch_horizontal = AXIS_STRETCH_TILE
axis_stretch_vertical   = AXIS_STRETCH_TILE
```

Exact pixel margins are confirmed against the source sheet during implementation; 6 px is the visible bevel width in the DawnLike cells.

### Subsystem 4 — Theme additions

**File (modified):** `resources/ui/main_theme.tres`

Add three theme type variations on top of the existing `Theme`:

- `"TitleLabel"` — already referenced by `pause_menu.tscn` and `main_menu.tscn`. No layout change; this spec only formalises its existence.
- `"CompactButton"` — `Button` variation with `custom_minimum_size = (BUTTON_COMPACT_MIN_WIDTH, BUTTON_MIN_HEIGHT) = (96, 40)`.
- `"IconButton"` — `Button` variation with `custom_minimum_size = (BUTTON_ICON_SIZE, BUTTON_ICON_SIZE) = (32, 32)` and reduced content margins.

Default `Button` gets `custom_minimum_size = (0, BUTTON_MIN_HEIGHT) = (0, 40)` so any unvariationed button is at least 40 px tall.

Default `HSeparator` gets `theme_override_constants/separation = SEPARATOR_PAD = 8` (Godot uses the `separation` constant as vertical padding around the line).

Default `PanelContainer` style set to `panel_frame.tres`. Any scene wanting `inset_frame.tres` overrides per-node (HUD frames do this).

### Subsystem 5 — Biome-accent overlay

**File (modified):** `src/autoload/ui_palette.gd`

The current `UIPalette` autoload rewrites `border_color` on the theme's `PanelContainer` `StyleBoxFlat`. With 9-slice textures the equivalent is to set `modulate` on every `AccentOverlay : NinePatchRect`.

New mechanism:

1. `ModalPanel._ready` registers its `AccentOverlay` with `UIPalette.register_overlay(overlay)`.
2. `UIPalette` tracks all registered overlays (weak references) and on biome change writes `overlay.modulate = current_accent` to each.
3. `_exit_tree` deregisters.

The HUD frames register the same way via a thin `accented_panel.gd` helper attached to the HUD `Frame` `PanelContainer` (or, equivalently, the `ModalPanel` script generalised — implementation chooses one).

This replaces the `StyleBoxFlat.border_color` rewrite from the earlier spec; nothing else in `UIPalette` changes.

### Subsystem 6 — HUD scene

**Files (new):**
- `scenes/ui/hud.tscn`
- `src/ui/hud.gd`

**Files (deleted):**
- `scenes/ui/health_ui.tscn` (folded into `hud.tscn`)
- `src/ui/health_ui.gd` (folded into `hud.gd`)
- `scenes/ui/weapon_button.tscn` (folded into `hud.tscn`)
- `src/ui/weapon_button.gd` (folded into `hud.gd`)

**Structure:**

```
HUD : CanvasLayer (layer = 5)
├── TopLeft : MarginContainer                      (anchor TL,
│                                                   theme_override_constants/margin_*
│                                                   = HUD_GUTTER = 16)
│   └── Frame : PanelContainer                     (style = inset_frame.tres)
│       └── Margin : MarginContainer               (12 px all sides)
│           └── VBox : VBoxContainer               (separation = XS = 4)
│               ├── HealthBar (Panel + ColorRect + RichTextLabel,
│               │              transplanted from health_ui.tscn)
│               └── GoldRow : HBoxContainer        (separation = S = 8)
│                   ├── GoldIcon : TextureRect     (16×16, coin from GUI0.png)
│                   └── GoldLabel : Label          (text = "0")
└── TopRight : MarginContainer                     (anchor TR, margins = 16)
    └── Frame : PanelContainer                     (style = inset_frame.tres)
        └── Margin : MarginContainer               (8 px all sides)
            └── VBox : VBoxContainer               (separation = XS = 4)
                └── WeaponSlot                     (transplanted from weapon_button.tscn:
                                                    IconButton, FallbackIcon, FallbackLabel)
```

**Tooltip.** The weapon tooltip currently lives as a sibling `PanelContainer` at the `CanvasLayer` root of `weapon_button.tscn`. In `hud.tscn` it becomes a sibling of `TopRight` (so it can extend left past the cluster) anchored to the top-right with `offset_left = -(HUD_GUTTER + frame_width + tooltip_width)`. Its `PanelContainer` adopts `panel_frame.tres` so it visually matches the modal family.

**Game integration.** `scenes/game.tscn` currently instances `HealthUI` and `WeaponButton` separately; this spec changes those two instance lines to one `HUD` instance. The `hud.gd` script re-exports the same signals/methods the prior two scripts exposed (e.g. `set_health(current, max)`, `set_weapon_icon(texture)`, `set_gold(amount)`) so callers in `player.gd`, `economy/*`, etc. don't need to change.

### Subsystem 7 — Per-scene migration

Every existing UI scene is rewritten to host a `ModalPanel` instance whose `Body` (and optionally `Footer`) is populated with the scene-specific content. Width and content mapping:

| Scene | Today | After |
|---|---|---|
| `pause_menu.tscn` `PausePanel` | `CenterContainer` + auto-sized `PanelContainer` | `ModalPanel` **SM**, `title = "PAUSED"`, `show_close_button = false`, Body = VBox of 3 full-width buttons (RESUME, SETTINGS, MAIN MENU), no Footer. |
| `pause_menu.tscn` `ConfirmationPanel` | 240×80 hardcoded offsets | `ModalPanel` **SM**, `title = "QUIT?"`, `show_close_button = false`, Body = `Label` ("All progress will be lost!"), Footer = compact YES / NO buttons. |
| `settings_popup.tscn` `Panel` | 400×440 hardcoded offsets | `ModalPanel` **MD**, `title = "SETTINGS"`, `show_close_button = true`, Body = `ScrollContainer` containing the existing audio / display / key-bindings VBox, Footer = full-width BACK. |
| `main_menu.tscn` `MenuCard` + floating titles | hardcoded 280×160 + free-floating `TitleTop` / `TitleBottom` | `ModalPanel` **SM**, `title = "TOP DOWN ROGUE"` (single-line; if two-line look is desired, title bar grows for this one scene by setting `TitleBar.custom_minimum_size.y = 96` and using `BB-code` in the label), Body = PLAY / SETTINGS / QUIT full-width buttons, no Footer. `TitleTop` and `TitleBottom` deleted. `Background` `ColorRect` kept (fills the screen behind the modal). |
| `death_screen.tscn` `DeathPanel` | 520-min custom stylebox, MarginContainer(40/32) | `ModalPanel` **MD**, `title = "DEFEATED"`, `show_close_button = false`, Body = flavor `Label` + stats `RichTextLabel`, Footer = compact RETURN-TO-MENU. `RedFlash` and `VignetteOverlay` `ColorRect`s kept as siblings (FX layer, unrelated to layout). |
| `weapon_popup.tscn` | auto-size HBox, separation 48 | `ModalPanel` **LG**, `title = "WEAPONS"`, Body = HBox of cards (`separation = L = 24`), no Footer. `has_backdrop = true`, `close_on_backdrop_click = true` (preserves current behaviour). |
| `chest_ui.tscn` `ShopPanel` | custom `HeaderBar` `PanelContainer` + `CardArea` MarginContainer(24/28) | `ModalPanel` **LG**, `title = <chest_name>`, Body = existing HBox of cards, no Footer. `HeaderBar` deleted (title bar replaces it). |
| `economy/shop_ui.tscn` | (currently uses its own header pattern — verify during implementation) | `ModalPanel` **LG**, `title = "SHOP"`, Body = shop card row, no Footer. |
| `health_ui.tscn` | standalone TL HUD | **Deleted**, folded into `hud.tscn`. |
| `weapon_button.tscn` | standalone TR HUD | **Deleted**, folded into `hud.tscn`. |
| `card.tscn` | StyleBoxFlat panel, separation 8 | StyleBoxTexture using `panel_frame.tres`, dimensions kept (160×240), separation unchanged (already `S = 8`). |

Every other UI-adjacent scene (`damage_number.tscn`, `chromatic_flash.tscn`, etc.) is FX, not layout — untouched.

### Subsystem 8 — Cleanups carried in this pass

- All `theme_override_constants/separation`, `theme_override_constants/margin_*`, `theme_override_styles/panel`, `custom_minimum_size` (modal-sized) overrides removed from `scenes/ui/*.tscn` wherever the new theme + `ModalPanel` provides the same value. Per-row overrides inside settings (slider min width etc.) stay.
- All `MarginContainer` instances with arbitrary 24/28/32/40 paddings inside modals are removed — `ModalPanel.Margin` (24/24) is the only inner padding inside a modal.
- All hand-rolled `HSeparator` overrides removed; rely on theme default `SEPARATOR_PAD = 8`.

## Risks & open questions

- **9-slice texture margins.** The 6-px margin assumption needs visual verification against `GUI0.png` at native scale. If the bevel is actually 5 or 7 px, the value is updated in both stylebox `.tres` files; no scene changes needed.
- **AccentOverlay vs pre-tinted frames.** Border-only overlay via `modulate` is the chosen path. If border colour distorts under HDR + CRT (the project has `viewport/hdr_2d = true`), fallback is to ship 5 pre-tinted border textures (one per biome) and have `UIPalette` swap the `AccentOverlay.texture` instead of its `modulate`. Decided during implementation visual check.
- **MainMenu title.** "TOP DOWN ROGUE" on one line at title-bar height 48 may be too cramped at the project's font size. If so, this one scene gets a 96-px title bar (`TitleBar.custom_minimum_size.y = 96`) and a two-line label. The exception is documented in the scene comment.
- **Existing `juicy_panel` paths.** Several scenes drive `juicy_panel` with explicit `animated_root` / `content_root` `NodePath`s. The migration must update those paths so they still point at the new `ModalPanel`'s `Root` and `Body` nodes; this is mechanical but easy to overlook.
- **Game scene integration.** `scenes/game.tscn` references `HealthUI` and `WeaponButton` by node name. The migration to `hud.tscn` must update any GDScript that calls `$HealthUI` / `$WeaponButton` to call `$HUD` (and the corresponding API methods). Implementation grep pass required.
- **Gold readout source.** The HUD spec assumes a gold value is already exposed by the economy system. If gold currently has no UI at all, this spec adds the HUD slot and `hud.gd` reads from whatever autoload exposes gold (verified during implementation; likely `Economy` or `Player`).

## Acceptance

- `rg "custom_minimum_size = Vector2\((320|480|640|520|400|280|240),"` in `scenes/ui/` returns zero hits outside `modal_panel.gd` — i.e. no scene hardcodes its own modal width.
- `rg "theme_override_constants/separation"` in `scenes/ui/*.tscn` returns hits only with values in `{4, 8, 16, 24, 32}`.
- `rg "MarginContainer"` in `scenes/ui/*.tscn`: every occurrence inside a modal scene is either the `ModalPanel`'s inner `Margin` or the HUD frame's inner `Margin`.
- All Buttons in UI scenes (apart from those with `theme_type_variation = "IconButton"`) render at ≥ 40 px tall.
- HUD top-left frame visibly contains both the health bar and a gold readout inside one 9-slice panel; HUD top-right frame contains the weapon icon inside a matching 9-slice panel; both frames share the same texture and a 16-px gutter from the screen edge.
- Every modal in the game (pause, settings, confirmation, death, weapon popup, chest, shop, main menu) shows the same title-bar height (48 px), same inner padding (24 px), same separator style, and same panel frame texture.
- Switching biome (or simulating a biome-accent change via `UIPalette`) visibly retints the panel borders of every visible modal and the HUD frames, with the interior dark fill unchanged.
- World sprites and gameplay are pixel-identical to before this change.
