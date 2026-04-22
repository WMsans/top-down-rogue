# Balatro-Inspired UI Redesign

## Problem

The current UI uses manually-constructed `Theme.new()` objects in every script, plain default Godot controls, no shared styling, no animations, no visual identity. Health bar is a bare 120x10 ColorRect. Menus are VBoxContainers with no borders, shadows, or personality. The result looks cheap and generic.

## Approach: Hybrid Theme + Tween Animations + Targeted Shaders

A single shared Godot Theme resource (`.tres`) handles 80% of the visual identity — fonts, colors, and rounded/bordered StyleBox panels. Tween-based animations add juice to every interaction. Shaders are reserved for 3 hero moments where they provide disproportionate visual impact.

## Color Palette (Dark/Fire Roguelike)

| Role | Hex | Description |
|------|-----|-------------|
| Deep background | `#1a0f12` | Very dark warm charcoal — fullscreen overlays |
| Surface background | `#2a1519` | Dark charcoal, warm undertone — button fills |
| Panel background | `#361c22` | Slightly lighter — card/panel fills |
| Panel border | `#8b3a2a` | Dark fire red — borders, outlines |
| Accent (primary) | `#ff6b35` | Bright orange — hover, focus, highlights |
| Accent (gold) | `#ffd700` | Gold — titles, important numbers, selected items |
| Text primary | `#f0e6d3` | Warm cream — all readable text |
| Text secondary | `#a89080` | Muted warm gray — secondary labels, tooltips |
| Danger/health | `#cc3333` | Blood red — health bar, death text |
| Success | `#44aa44` | Muted green — positive feedback |

## Typography

All text uses the existing SDS_8x8 pixel font (`res://textures/Assets/DawnLike/GUI/SDS_8x8.ttf`).

| Use | Size (px) | Color | Extras |
|-----|-----------|-------|--------|
| Hero title | 48-64 | Gold (#ffd700) or blood red (#cc3333) | Drop shadow (black, 3-4px offset) |
| Section heading | 32 | Warm cream (#f0e6d3) | Drop shadow (black, 2px offset) |
| Body / buttons | 20 | Warm cream (#f0e6d3) | — |
| Small / tooltips | 14 | Muted gray (#a89080) | — |

Current font sizes (16px buttons, 16-24px labels) are too small for the pixel font at typical game resolutions. The new sizes provide the bold, punchy hierarchy Balatro is known for.

## Card-like Panels (StyleBoxFlat)

Text drop shadows use Godot Label's built-in `theme_override_constants/outline_size` and `theme_override_colors/font_outline_color` properties (4px outline with black for hero titles, 2px for headings). All labels with drop shadows set these theme overrides explicitly since the shared theme can't conditionally apply shadows per-label.

All panel-style containers (menus, tooltips, weapon cards, settings) use a shared StyleBoxFlat:

- **Corner radius:** 8px
- **Border width:** 2px
- **Border color:** `#8b3a2a` (default) / `#ff6b35` (hover) / `#ffd700` (selected)
- **Background color:** `#361c22`
- **Content margins:** 12px horizontal, 8px vertical
- **Shadow:** enabled, 4px offset, color `#00000080`
- **Shadow outside margins:** 8px

Buttons use a similar but slightly different StyleBoxFlat:
- **Corner radius:** 6px
- **Border width:** 2px
- **Border color:** `#8b3a2a` (normal) / `#ff6b35` (hover) / `#ffd700` (focus)
- **Background color:** `#2a1519` (normal) / `#361c22` (hover)
- **Content margins:** 10px horizontal, 6px vertical

## Shared Theme Resource

Create `resources/ui_theme.tres` — a single Godot Theme resource that defines:

- Default font = SDS_8x8
- Font sizes per type (Button 20px, Label 20px, HSlider 14px)
- Colors per type (Button text, Label text, hover colors)
- StyleBoxFlat for PanelContainer, Button (normal/hover/pressed/focused)
- StyleBoxFlat for HSlider (track + fill)
- StyleBoxFlat for HSeparator (thin fire-red line)
- VBoxContainer/HBoxContainer separation constants

All 7 UI scripts replace their `_apply_theme()` methods that create `Theme.new()` with a single preload of `res://resources/ui_theme.tres`.

## Screen-by-Screen Design

### Main Menu (`scenes/ui/main_menu.tscn` + `src/ui/main_menu.gd`)

**Layout:**
- Full-screen dark background (`#1a0f12`) — replace the plain ColorRect
- Title "TOP DOWN" in 64px gold, "ROGUE" in 28px orange, centered near top third
- Card-style panel (rounded, bordered, shadow) centered vertically containing the three buttons
- "PLAY" button gets accent treatment: orange text + orange border on default state
- "SETTINGS" and "QUIT" use standard button styling

**Animations:**
- Title text fades in on scene load (0→1 alpha over 0.5s)
- Button panel slides up 20px while fading in (0.4s, ease-out)
- Buttons bounce on hover (1.0→1.05 scale, 0.15s, back ease-out)
- Buttons compress on press (1.0→0.95 scale, 0.1s, ease-in)

### Health Bar (`scenes/ui/health_ui.tscn` + `src/ui/health_ui.gd`)

**Layout:**
- Health text: current HP in gold (20px bold), `/ max` in muted gray (14px)
- Bar: 200px wide × 14px tall (up from 120×10)
- Bar background: `#1a0f12` with 2px border `#8b3a2a`, rounded corners (4px)
- Bar fill: implemented as a ColorRect with a ShaderMaterial using `health_bar_shimmer.gdshader` (which also provides the left-to-right red-to-orange gradient base, plus the shimmer effect on top). The fill ColorRect uses `clip_contents = true` on the parent to respect rounded corners.
- Position: top-left with 12px margin

**Animations:**
- On damage: bar fill flashes white (0.1s), then returns to normal color
- HP number briefly pulses to gold then fades back (0.2s)
- Health bar below 25%: subtle pulsing red border glow (loop tween)

**Hero shader:** Subtle gradient shimmer flows along the health bar fill — a looping animation of a brighter band moving left-to-right across the fill area. Implemented as a ShaderMaterial on the fill ColorRect.

### Pause Menu (`scenes/ui/pause_menu.tscn` + `src/ui/pause_menu.gd`)

**Layout:**
- Full-screen dimmer: `#1a0f12` at 70% opacity
- Centered card panel (same shared StyleBox) containing:
  - "PAUSED" title in 48px gold with drop shadow
  - RESUME, SETTINGS, MAIN MENU buttons (standard button style)
  - "MAIN MENU" button in danger red text `#cc3333`

**Animations:**
- Panel slides up 30px while fading in (0.3s, ease-out)
- Dimmer fades from 0→0.7 (0.25s)
- Buttons bounce on hover, compress on press (same as main menu)

**Confirmation dialog (quit to main menu):**
- Smaller card panel overlay on top of pause menu
- Same card styling, centered
- "YES" in `#cc3333`, "NO" in gold `#ffd700`

### Death Screen (`scenes/ui/death_screen.tscn` + `src/ui/death_screen.gd`)

**Layout:**
- Full-screen overlay + red flash (same as current, enhanced)
- "YOU DIED" in 64px blood red `#cc3333` with dark drop shadow (4px black)
- "CONTINUE" button in gold, card-style panel

**Enhanced death sequence:**
1. Red flash: 0→0.6 alpha in 0.08s, then 0.6→0 over 0.5s
2. Screen shake: 4px amplitude, 0.3s duration (oscillate position on the VBox)
3. Dark overlay: 0→0.8 alpha over 0.8s
4. "YOU DIED" text: scale 0.6→1.0 over 0.5s (back ease-out with overshoot)
5. Continue button: fade in after 0.7s delay, 0.3s duration

**Hero shader:** Red vignette pulse on the overlay — a full-screen ColorRect with a shader that darkens edges with a pulsing red tint. Fades in during the death sequence.

### Settings Popup (`scenes/ui/settings_popup.tscn` + `src/ui/settings_popup.gd`)

**Layout:**
- Same dimmer overlay as pause menu
- Larger card panel (400×500px) with fire-red border
- Section headers in gold: "-- AUDIO --", "-- DISPLAY --", "-- KEY BINDINGS --"
- Sliders: custom styled track (dark fill, orange filled portion, 2px fire-red border)
- "X" close button top-right, "BACK" button bottom
- Key binding buttons use standard button style

**Animations:**
- Panel slides up + fades in (same as pause)
- Sliders already work fine functionally, just need visual style from theme

### Weapon Button (`scenes/ui/weapon_button.tscn` + `src/ui/weapon_button.gd`)

**Layout:**
- Top-right corner, 64px icon area (up from 48px)
- Card-style panel for icon: rounded corners, fire-red border, warm shadow
- Tooltip: card-style panel (same StyleBox), always positioned to the left of the button
  - Weapon name in gold, cooldown in muted gray, damage in orange
  - Modifier row: 32px icons in a row below stats, empty slots as dark squares with dashed borders

**Animations:**
- Button bounces on hover (1.0→1.08 scale, 0.15s)
- Tooltip fades in (0→1 alpha, 0.15s)

### Weapon Popup (`scenes/ui/weapon_popup.tscn` + `src/ui/weapon_popup.gd`)

**Layout:**
- Full-screen dimmer: `#1a0f12` at 87% opacity
- "WEAPONS" title in 28px gold with drop shadow, centered above cards
- Three weapon cards (or 2 + empty) in a horizontal row, centered
- Each card: card-style panel (rounded, bordered, shadow), ~160×220px
  - Icon (96×96 or fallback colored square)
  - Weapon name in gold
  - Cooldown in muted gray, damage in orange
  - Modifier slots row at bottom
- Empty slot card: dashed `#8b3a2a` border, "EMPTY" in muted gray, dimmer background
- Selected card: gold border `#ffd700`, persistent subtle pulse

**Animations:**
- Cards stagger in: each card slides up 20px + fades in with 0.1s delay between cards
- Hover: border transitions `#8b3a2a` → `#ff6b35`, scale 1.0→1.03 (0.15s)
- Selected: border becomes gold `#ffd700`, slight pulse glow

**Hero shader:** Hover glow — a ShaderMaterial on hovered cards that adds an inner orange glow along the card edges. Toggled via `shader_parameter` when mouse enters/exits.

## Animation Spec Summary

| Animation | Duration | Easing | Details |
|-----------|----------|--------|---------|
| Button hover scale | 0.15s | Back ease-out | 1.0→1.05 (weapon button: 1.08) |
| Button press scale | 0.1s | Ease-in | 1.0→0.95 |
| Panel slide-in | 0.3s | Ease-out | 30px up + fade-in |
| Overlay fade | 0.25s | Linear | 0→0.7 alpha |
| Death red flash | 0.08s up, 0.5s down | Linear | 0→0.6→0 alpha |
| Death overlay | 0.8s | Ease-out | 0→0.8 alpha |
| Death text scale | 0.5s | Back ease-out | 0.6→1.0 |
| Death button fade | 0.3s (0.7s delay) | Ease-in | 0→1 alpha |
| Health bar flash | 0.1s | Linear | Fill→white→fill |
| Health bar shimmer | Looping 2s | — | Gradient band flowing left→right |
| Card hover | 0.15s | Ease-out | Border color + scale 1.03 |
| Card stagger-in | Each 0.1s delay | Ease-out | 20px up + fade-in |
| Death vignette pulse | 1.5s loop | Sine | Edge redness oscillates |

## Implementation Structure

1. **Create `resources/ui_theme.tres`** — shared Theme resource with all colors, fonts, StyleBox definitions (including panel, button, card styles as type variations)
2. **Create `resources/cards_style.tres`** — reusable StyleBoxFlat for card panels (if not inline in theme)
3. **Create `shaders/ui/`** — directory for hero shaders:
   - `health_bar_shimmer.gdshader` — flowing gradient on health fill
   - `death_vignette.gdshader` — pulsing red vignette overlay
   - `card_hover_glow.gdshader` — inner orange glow on card edges
8. **Update all 7 UI scene/script pairs** — replace manual theme creation with shared theme reference, add animations, update layouts
9. **New utility: `src/ui/ui_animations.gd`** — autoload or static class with reusable tween helpers (bounce, slide_in, fade_in, pulse) to avoid duplicating animation code across 7 scripts

Note on the separate `cards_style.tres`: all StyleBoxFlat definitions (panel, button, cards) are defined inside `ui_theme.tres` as theme type variations, not as separate resource files. This keeps all styling in one place.

## Files Changed

- `resources/ui_theme.tres` (new — includes all StyleBoxFlat definitions as type variations)
- ~`resources/cards_style.tres`~ (removed — all styles inline in ui_theme.tres)
- `shaders/ui/health_bar_shimmer.gdshader` (new)
- `shaders/ui/death_vignette.gdshader` (new)
- `shaders/ui/card_hover_glow.gdshader` (new)
- `src/ui/ui_animations.gd` (new)
- `scenes/ui/main_menu.tscn` (modify)
- `src/ui/main_menu.gd` (modify)
- `scenes/ui/health_ui.tscn` (modify)
- `src/ui/health_ui.gd` (modify)
- `scenes/ui/death_screen.tscn` (modify)
- `src/ui/death_screen.gd` (modify)
- `scenes/ui/pause_menu.tscn` (modify)
- `src/ui/pause_menu.gd` (modify)
- `scenes/ui/settings_popup.tscn` (modify)
- `src/ui/settings_popup.gd` (modify)
- `scenes/ui/weapon_button.tscn` (modify)
- `src/ui/weapon_button.gd` (modify)
- `scenes/ui/weapon_popup.tscn` (modify)
- `src/ui/weapon_popup.gd` (modify)

## Out of Scope

- Main menu background art (no title sprite exists)
- Sound effects for UI interactions
- Screen transition effects between scenes
- Particle effects on menus
- Mobile/touch-specific sizing adjustments