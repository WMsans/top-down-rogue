# UI Consistency Pass + CRT Post-Process — Design

**Date:** 2026-05-23
**Status:** Draft, awaiting implementation plan

## Problem

The game's world art is consistent (pulled from DawnLike / Kyrise packs at native scale), but the UI is visually incoherent:

- **Mixed pixel scales.** The "PAUSED" title renders at ~4–5× source pixels; pause-menu buttons at ~3×; settings body text at ~2×; the top-left HUD "100 / 100" at ~1–2×.
- **Mixed apparent fonts.** No custom font is assigned anywhere in `scenes/ui/*.tscn` — every label uses Godot's default Noto Sans at arbitrary sizes (28 / 48 / 64), which hints and aliases differently at each size, producing the illusion of different fonts. The chunky "PAUSED" is the one exception (separate title sprite/font).
- **Off-theme palette.** UI panels are dark maroon with orange borders and yellow headers. The palette is generic and ignores the rich biome palettes already defined in `assets/biomes/*.tres` (caves / frozen / magma / mines / vault).
- **No global post-process.** There is nothing tying world rendering and UI together visually (cf. Balatro, where a single CRT pass unifies everything).

## Goals

1. One pixel scale, one font, one StyleBox vocabulary across the entire UI.
2. UI palette derived from the art packs, with biome-reactive accents.
3. Single global CRT shader covering world + UI + every overlay.
4. Zero changes to world sprites, gameplay, or scene graph beyond UI scenes.

## Non-Goals

- Redrawing or rescaling any world art.
- Redesigning UI layouts (Balatro-style card UI etc. is out of scope — covered by separate specs).
- Bloom, chromatic aberration, phosphor mask, or other CRT effects beyond the three picked below.
- Theming for accessibility (high-contrast mode, font scaling) — separate concern.

## Design

### Subsystem 1 — UI theme

**Files (new):**
- `resources/ui/main_theme.tres` — single Godot `Theme` resource referenced by every UI scene.
- `src/autoload/ui_palette.gd` — autoload that mutates the theme's accent colors when the active biome changes.

**Files (modified):**
- Every `scenes/ui/*.tscn` — strip per-control `theme_override_font_*`, `theme_override_colors/*`, `theme_override_styles/*` and assign `theme = ExtResource("main_theme")` on the root.
- `src/core/biome_def.gd` — add field `@export var ui_accent: Color`.
- Each `assets/biomes/*.tres` — set `ui_accent` (see palette table below).
- `project.godot` — register `UIPalette` autoload.

#### Pixel scale

World sprites render at ~4× source pixels (16px DawnLike tile shown ~64px on screen). UI base unit = **2× source pixels** — sharper than world but still unambiguously pixel art. All UI dimensions are integer multiples of 8 screen pixels.

#### Typography

Single font: **`textures/Assets/DawnLike/GUI/SDS_8x8.ttf`**, configured as a bitmap-rendered `FontFile` (no antialiasing, no hinting).

Two sizes, no others:
- **Body / buttons / HUD numbers / slider values** — `font_size = 16` (8×8 source pixels × 2).
- **Titles** ("PAUSED", "SETTINGS" panel header, future screen titles) — `font_size = 32` (2× body).

No outlines. No drop shadows. The current separately-rendered "PAUSED" title sprite is removed and replaced with a plain `Label` at title size.

#### StyleBoxes

All `StyleBoxFlat` (no nine-patch textures in v1):
- Border width: **2px** on all sides for panels, buttons, sliders, input boxes.
- Corner radius: **0**.
- Padding: multiples of 8px only (8 / 16 / 24).
- Button states: `normal` / `hover` / `pressed` / `disabled` distinguished by border color and font color (accent vs. dim), not by border thickness or padding.

#### Palette

Neutral base — constant across biomes, sampled from DawnLike GUI assets:

| Slot     | Hex      | Use                              |
|----------|----------|----------------------------------|
| bg_deep  | `#1a1410`| Panel fill                       |
| bg_mid   | `#2a201a`| Inset backgrounds, disabled fill |
| ink      | `#e8d8b8`| Primary text                     |
| ink_dim  | `#8a7860`| Secondary text, disabled         |

Biome accent — drives panel borders, title color, button hover/pressed font color, slider fill:

| Biome  | Accent    | Notes               |
|--------|-----------|---------------------|
| caves  | `#d97742` | Warm orange         |
| magma  | `#ff5030` | Hot red             |
| frozen | `#6ec6e8` | Ice cyan            |
| mines  | `#c89858` | Brass               |
| vault  | `#c8a040` | Gold                |

Default accent (when no biome is active — menus, main menu, between-floor transitions): `#d97742` (caves).

#### Biome reactivity

`UIPalette` autoload:

1. Holds a reference to `main_theme.tres`.
2. Connects to whatever signal the floor/biome controller emits on biome change (TBD during implementation — verify against existing biome-transition code).
3. On change, rewrites these theme slots with the new accent:
   - `PanelContainer/styles/panel` → `border_color`
   - `Button/colors/font_hover_color`, `font_pressed_color`
   - `Label/colors/font_color` (title variation only; body labels stay `ink`)
   - `HSlider/styles/grabber` → `bg_color`
   - `HSlider/styles/grabber_highlight` → `bg_color`
4. No scene rebuild needed — Godot's theme system propagates automatically.

### Subsystem 2 — CRT post-process

**Files (new):**
- `shaders/post/crt.gdshader` — fragment shader.
- `scenes/ui/crt_overlay.tscn` — autoloaded overlay scene.
- `project.godot` — register `CRTOverlay` autoload (set to run after `UIPalette`).

**Files (modified):**
- Settings menu scene — add "CRT" toggle next to existing "Fullscreen".
- Settings resource (existing) — add `crt_enabled: bool = true`.

#### Scene structure

```
CanvasLayer (layer = 128, follow_viewport_enabled = true)
└── ColorRect (anchors = full_rect, mouse_filter = IGNORE)
        material = ShaderMaterial(crt.gdshader)
```

Layer 128 is above all gameplay and UI CanvasLayers in the project (verified during implementation). `mouse_filter = IGNORE` ensures input passes through. The shader reads via `hint_screen_texture` — no SubViewport, no input rerouting.

#### Shader

Uniforms (all tunable in inspector):

| Name                 | Type  | Range   | Default |
|----------------------|-------|---------|---------|
| `scanline_intensity` | float | 0..1    | 0.15    |
| `scanline_count`     | float | —       | 540     |
| `curvature`          | float | 0..0.3  | 0.08    |
| `vignette_strength`  | float | 0..1    | 0.35    |
| `vignette_softness`  | float | —       | 0.45    |

Fragment pipeline:

1. Barrel-distort the input UV by `curvature` (standard radial warp).
2. If distorted UV is outside `[0, 1]`, output opaque black (curved-screen edge).
3. Sample screen texture at distorted UV.
4. Multiply by scanline factor: `mix(1.0, 0.5 + 0.5 * sin(uv.y * scanline_count * PI), scanline_intensity)`.
5. Multiply by radial vignette computed from distance to center, softened by `vignette_softness`.
6. Output.

Defaults tuned for "Balatro-subtle": visible but never dominant; readable text; corners feel curved without fish-eye.

#### Settings toggle

`crt_enabled` defaults to `true`. Toggle in settings panel flips `CRTOverlay.visible`. No shader recompile, no scene reload.

### Out of v1 (deferred)

- Bloom pass (separate shader, requires intermediate buffer).
- Per-biome CRT tint (e.g. greener phosphor in vault) — easy to add later as a uniform.
- Animated scanline jitter / rolling bar.
- Nine-patch textured StyleBoxes using DawnLike GUI sprites — current StyleBoxFlat approach is sufficient for cohesion.

## Risks & open questions

- **Biome-change signal name** — verified during implementation; if no clean signal exists, may need to add one to whatever owns the floor/biome state.
- **Layer 128 collision** — implementation must scan the project for any existing `CanvasLayer.layer >= 128`. None expected, but verify.
- **HDR + screen-texture sampling** — project has `viewport/hdr_2d = true`. Shader writes back to the same color space; should be transparent, but verify visually for color shifts on the first build.
- **Text readability with scanlines** — 16px body text at 15% scanline intensity should remain legible; if not, either lower `scanline_intensity` default or bump body text to 24px (still integer multiple of 8).

## Acceptance

- Open every UI scene in `scenes/ui/`; every label uses SDS_8x8 at 16px or 32px; no `theme_override_font_size` overrides remain.
- Pause menu, settings panel, HUD, main menu all show the same panel border thickness (2px) and same accent color in the current biome.
- Transitioning between biomes visibly shifts UI accent color without restart or scene reload.
- CRT toggle in settings turns the effect on/off live.
- World sprites are pixel-identical to before this change.
