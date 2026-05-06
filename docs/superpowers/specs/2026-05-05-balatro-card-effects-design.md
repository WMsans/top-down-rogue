# Balatro-Style Card Effects — Design Spec

**Date:** 2026-05-05
**Project:** Top-Down Rogue (Godot 4.6)

## Overview

Apply Balatro-style card effects to all selection cards in the game: 3D perspective tilt following the mouse cursor, a holographic/metallic frame that shifts its reflection with rotation, and springy bounce animations on hover/leave.

**Goal:** Make cards feel alive and premium, matching the juice-rich aesthetic of the rest of the game.

---

## Scope

All card-based selection UI:

- **WeaponPopup cards** — weapon swap, pickup, modifier equip/remove, transfer cards
- **ChestUI cards** — weapon selection from chests
- **ShopUI cards** — modifier offers in the shop

One universal holographic style across all card types.

---

## Architecture

**Key insight:** A `canvas_item` vertex shader on a `PanelContainer`'s material would only tilt the card's background draw calls — child nodes (TextureRect, Label, VBoxContainer) render with independent draw calls and would remain flat. The card must be rendered as a single unified texture for the vertex tilt to apply to the entire card visual.

**Solution:** Wrap each card in a `SubViewport` → `ViewportTexture` → `TextureRect` pipeline. The `TextureRect` displays the flattened card image with the vertex shader applied. Interaction (mouse enter/leave, gui_input) remains on the original `PanelContainer`, which does NOT receive the shader.

### New Files

| File | Purpose |
|------|---------|
| `shaders/ui/card_holo.gdshader` | Custom `canvas_item` shader applied to TextureRect: vertex 3D tilt + fragment holographic border |
| `src/ui/card_effects.gd` | `class_name CardEffects` with static `setup_card()` that wraps a card in the SubViewport pipeline, plus inner `CardEffectController` node for per-frame updates, signal handling, and hover tweens |

### Modified Files

| File | Change |
|------|--------|
| `src/ui/weapon_popup.gd` | `_create_card()`, `_create_transfer_card()`, `_create_remove_modifier_card()` — call `CardEffects.setup_card()` instead of manual material/signal setup. Modifier icon tooltip logic (`_on_modifier_icon_mouse_entered/exited`) delegates hover-zone queries to `CardEffectController`. |
| `src/ui/chest_ui.gd` | `_create_weapon_card()` — same replacement |
| `src/ui/shop_ui.gd` | `_create_offer_card()`, `_create_remove_card()` — same replacement |

### Files NOT Modified

- `src/ui/ui_animations.gd` — CardEffects is additive, existing tween utilities remain for non-card UI
- `src/ui/ui_theme.gd` — unchanged

---

## Component Design

### Node Structure After `setup_card(card)`

`setup_card()` transforms the card panel at construction time:

```
card (PanelContainer, original node — receives mouse_entered/exited/gui_input)
  ├── SubViewport (size tracks card.size, transparent_bg=true)
  │   └── inner_container (VBoxContainer) ← all original card children reparented here
  ├── TextureRect (anchors_preset=FULL_RECT, mouse_filter=IGNORE, has shader material)
  └── CardEffectController (Node, handles _process, tweens, cleanup)
```

1. **SubViewport:** Size is set to `card.custom_minimum_size` and updated if the card resizes. `transparent_bg = true` so the card's theme background remains visible. Original card children are reparented into a VBoxContainer inside the SubViewport.
2. **TextureRect:** Set to `MOUSE_FILTER_IGNORE` so all mouse events pass through to the card behind it. Its `texture` property is set to the SubViewport's render texture. The shader material is assigned here.
3. **CardEffectController:** Added as a child of the card. Has its own `_process()` for per-frame shader uniform updates. Connects to `card.mouse_entered`, `card.mouse_exited`, and `card.tree_exiting`.

All mouse interaction (hover, gui_input) flows through the original card `PanelContainer` — the TextureRect is purely visual.

### 1. Shader: `card_holo.gdshader`

Shader type: `canvas_item`. Applied to the TextureRect's material.

#### Uniforms

| Uniform | Type | Default | Purpose |
|---------|------|---------|---------|
| `tilt_x` | float | 0.0 | Rotation around X axis, range ±0.08, driven by cursor Y offset |
| `tilt_y` | float | 0.0 | Rotation around Y axis, range ±0.08, driven by cursor X offset |
| `holo_time` | float | 0.0 | Scrolling time for rainbow sweep phase, updated each frame |
| `holo_intensity` | float | 0.0 | 0.0–1.0, ramps up on hover for springy pop feel |
| `border_width` | float | 0.06 | Width of the holographic border region in UV space |
| `card_size` | vec2 | dynamic | Card pixel dimensions, set at setup time from `card.custom_minimum_size`, needed to compute vertex center for tilt math |

#### Vertex Shader

3D perspective tilt on the TextureRect quad. The TextureRect fills the card, so its vertex positions span `(0, 0)` to `card_size`.

```
vec2 center = card_size * 0.5;
vec2 centered = VERTEX - center;

// Simulate 3D rotation of the card plane
vec3 pos = vec3(centered.x, centered.y, 0.0);
// R_x(tilt_x) — rotate around local X axis (tilts top/bottom toward/away from viewer)
pos.yz = pos.yz * cos(tilt_x) + vec2(-pos.z, pos.y) * sin(tilt_x);
// R_y(tilt_y) — rotate around local Y axis (tilts left/right toward/away from viewer)
pos.xz = pos.xz * cos(tilt_y) + vec2(pos.z, -pos.x) * sin(tilt_y);

// Perspective projection
float perspective_distance = 2.0;
float scale = perspective_distance / (perspective_distance + pos.z);
VERTEX = center + vec2(pos.x * scale, pos.y * scale);
```

Note: UV coordinates are interpolated linearly across the distorted quad. For tilt angles ≤ 0.08 rad (~4.6°), affine interpolation artifacts are imperceptible, so no perspective-corrected UV pass is needed.

#### Fragment Shader

```
vec4 base = texture(TEXTURE, UV);

// Border mask
float edge_dist = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
float border_mask = smoothstep(border_width, border_width * 0.7, edge_dist);

// Holographic rainbow sweep — direction follows tilt angle
float tilt_angle = atan(tilt_y, tilt_x);
float sweep_pos = UV.x * cos(tilt_angle) + UV.y * sin(tilt_angle) + holo_time;
vec3 holo_color = rainbow(sweep_pos);  // 1D HSL rainbow lookup, defined in-shader

// Metallic specular highlight on border — tracks tilt direction
float highlight_angle = tilt_angle + 3.14159 * 0.5;  // perpendicular to tilt
float border_angle = atan(UV.y - 0.5, UV.x - 0.5);
float highlight = pow(smoothstep(0.3, 0.0, abs(border_angle - highlight_angle)), 4.0);

// Inner dim — darken card center so border pops
float inner_dim = mix(1.0, 0.85, (1.0 - border_mask) * holo_intensity);

// Composite
vec3 holo_overlay = mix(holo_color, vec3(1.0), highlight) * border_mask * holo_intensity;
vec3 result = base.rgb * inner_dim + holo_overlay;
COLOR = vec4(result, base.a);
```

### 2. Utility: `card_effects.gd`

#### API

```gdscript
class_name CardEffects

static func setup_card(card: Control, tilt_strength := 0.08, hover_scale := 1.05) -> CardEffectController
static func get_controller(card: Control) -> CardEffectController
```

`setup_card` returns the `CardEffectController` for callers that need to register icon zones or connect to zone signals. `get_controller` retrieves a previously-set-up card's controller by card reference.

#### `setup_card(card)` — one-time construction

1. Create `SubViewport` as child of card, set `size = card.custom_minimum_size` and `transparent_bg = true`. Create a VBoxContainer inside the SubViewport, reparent all of card's existing children into it.
2. Create `TextureRect` as child of card (after SubViewport), set `anchors_preset = Control.PRESET_FULL_RECT`, `mouse_filter = Control.MOUSE_FILTER_IGNORE`, `texture = subviewport.get_texture()`.
3. Create `ShaderMaterial` with `card_holo.gdshader`, set initial uniforms (`card_size`, `border_width`, defaults for others). Assign to `texture_rect.material`.
4. Create a `CardEffectController` node as child of card, passing `card`, `texture_rect`, `tilt_strength`, `hover_scale`. The controller handles everything from this point on.

If the shader fails to preload, log an error and return early — card renders without effects but game continues.

#### `CardEffectController` (inner class / sibling script, not exposed)

Stored at `src/ui/card_effects.gd` alongside the static utility. Extends `Node`.

**Member variables** (set on `_init`):
- `card: Control`
- `texture_rect: TextureRect`
- `tilt_strength: float`
- `hover_scale: float`
- `_hover_tween: Tween` (nullable)
- `_icon_zones: Array[Dictionary]` — for WeaponPopup modifier icon tooltip hit-testing (empty for other card types)

**`_ready()`:**
- Connect `card.mouse_entered` → `_on_hover_enter`
- Connect `card.mouse_exited` → `_on_hover_leave`
- Connect `card.tree_exiting` → `_cleanup`
- Set `set_process(true)`

**`_process(_delta:)`:**
```
var mouse_pos := card.get_local_mouse_position()
var delta := (mouse_pos - card.size * 0.5) / (card.size * 0.5)
var mat := texture_rect.material as ShaderMaterial
if mat:
    mat.set_shader_parameter("tilt_x", delta.y * tilt_strength)
    mat.set_shader_parameter("tilt_y", -delta.x * tilt_strength)
    mat.set_shader_parameter("holo_time", fmod(Time.get_ticks_msec() / 1000.0, 1.0))
```

Since the TextureRect has `MOUSE_FILTER_IGNORE`, `card.get_local_mouse_position()` returns the mouse position in the card's local space, which matches the TextureRect's pixel space. The card's scale changes on hover, but `card.size` is unaffected by scale transforms, so the normalization is stable (the max ~5% scale change produces a ~5% delta perturbation, which on a ±0.08 rad tilt range is ~0.004 rad — imperceptible).

**`_on_hover_enter()`:**
```
# Kill previous leave tween if still running
if _hover_tween and _hover_tween.is_valid():
    _hover_tween.kill()

var t := card.create_tween()
t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

# Springy pop: overshoot then settle
t.tween_property(card, "scale", Vector2(hover_scale, hover_scale), 0.15) \
    .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
t.parallel().tween_property(card, "rotation", deg_to_rad(2.0), 0.15) \
    .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
t.parallel().tween_method(_set_holo_intensity, _get_holo_intensity(), 1.0, 0.15) \
    .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

t.tween_property(card, "scale", Vector2(1.03, 1.03), 0.12) \
    .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
t.parallel().tween_property(card, "rotation", 0.0, 0.12) \
    .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)

_hover_tween = t
```

**`_on_hover_leave()`:**
```
if _hover_tween and _hover_tween.is_valid():
    _hover_tween.kill()

var t := card.create_tween()
t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

t.tween_property(card, "scale", Vector2.ONE, 0.2) \
    .set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
t.parallel().tween_property(card, "rotation", 0.0, 0.2) \
    .set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
t.parallel().tween_method(_set_holo_intensity, _get_holo_intensity(), 0.0, 0.2) \
    .set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)

_hover_tween = t
```

**`_set_holo_intensity(v: float)`, `_get_holo_intensity() -> float:`** — read/write the shader uniform `holo_intensity` on the TextureRect's material.

**`_cleanup()`:**
- Disconnect all signals
- Kill any active tweens
- Remove `CardEffectController` references from static tracking (if any)

#### Icon Zone Registration (WeaponPopup modifier tooltips)

Modifier icons inside a WeaponPopup card are rendered into the SubViewport and cannot receive mouse events directly. The CardEffectController provides a hit-zone system:

```
func register_zone(zone_id: String, rect: Rect2) -> void
func clear_zones() -> void

signal zone_entered(zone_id: String)
signal zone_exited()
```

**Behavior:** In each `_process` frame, after updating tilt uniforms, the controller checks whether `card.get_local_mouse_position()` falls inside any registered zone rect. When the mouse enters a zone, `zone_entered(zone_id)` emits (only once until the mouse leaves all zones). When the mouse leaves a zone, `zone_exited()` emits.

**Usage in `weapon_popup.gd`:** After `setup_card()`, the card creator computes each modifier icon's rect in card-local space and calls `controller.register_zone(zone_id, rect)`. It then connects `zone_entered` → show tooltip and `zone_exited` → hide tooltip. This replaces the existing `_on_modifier_icon_mouse_entered/exited` handlers.

All tweens use `Tween.TWEEN_PAUSE_PROCESS` to match existing animation conventions.

---

## Integration Details

### `weapon_popup.gd` Changes

In `_create_card()`:
- **Remove:** `glow_mat` creation, `card.material = glow_mat` assignment, `card.mouse_entered.connect(...)`, `card.mouse_exited.connect(...)`
- **Add:** `var controller := CardEffects.setup_card(card)` at end of function (after `position = CARD_POSITIONS[...]`). Then, for each modifier slot icon, compute its rect in card-local space and call `controller.register_zone(zone_id, rect)`. Connect `controller.zone_entered` → show tooltip, `controller.zone_exited` → hide tooltip.
- **Remove:** `_on_modifier_icon_mouse_entered()` and `_on_modifier_icon_mouse_exited()` handlers and their signal connections — replaced by zone registration
- **Keep:** `gui_input` connection and `_on_card_input()` — click handling unchanged

Same pattern for `_create_transfer_card()` and `_create_remove_modifier_card()` (these have no modifier icons, so no zone registration needed).

### `chest_ui.gd` Changes

In `_create_weapon_card()`:
- **Remove:** glow material creation, hover signal connections
- **Add:** `CardEffects.setup_card(card)` at end

Skip button and grid layout unchanged.

### `shop_ui.gd` Changes

In `_create_offer_card()`:
- **Remove:** hover signal connections and glow material
- **Add:** `CardEffects.setup_card(card)` at end
- **Keep:** jitter-on-unaffordable logic, `sold` dim effect — these are separate concerns

Same for `_create_remove_card()`.

---

## Error Handling

- If `card_holo.gdshader` fails to load, `CardEffects.setup_card()` logs an error and returns early — card renders without effects but game continues
- If `card.custom_minimum_size` is zero (card not yet sized), defer SubViewport sizing to next frame via `call_deferred`
- Mouse tracking gracefully handles cards at screen edges (normalized delta clamped implicitly by card bounds)
- Active tweens are killed on card removal (`tree_exiting`) to prevent dangling tween errors
- `card.get_local_mouse_position()` returns `Vector2.ZERO` when the mouse is not over the card — tilt defaults to neutral (0,0) which is correct

---

## Testing

- Manual verification: hover over cards in WeaponPopup, ChestUI, ShopUI — observe 3D tilt, holographic border shift, springy pop
- Edge cases: rapid mouse movement across multiple cards, pause menu interaction (tweens should work during pause), cards near screen edges
- Regression: click behavior unchanged (weapon swap, modifier equip, chest selection, shop purchase all work as before)
- Modifier tooltip: hovering over modifier icon areas inside WeaponPopup cards should still show/hide tooltips correctly via the hit-zone registration system
