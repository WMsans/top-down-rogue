# Low-Res World, High-Res UI — Performance Fix

## Problem

On the user's old laptop (1200×1600 screen), the game runs at 25–50 FPS. Target is 60–90 FPS.

The Visual Profiler captured during gameplay shows the frame is **GPU-bound**, with cost concentrated in canvas rendering:

| Stage | GPU time |
|---|---|
| Render Viewport 0 (root) | **22.38 ms** |
| ├── Render Canvas → Render CanvasItems | **15.77 ms** |
| ├── Tonemap | 2.45 ms |
| ├── Glow | 1.95 ms |
| └── Other (lights, 3D scaffolding, occluder culling) | <0.2 ms each |

22.38 ms GPU → ~45 FPS hard ceiling, matching observed behavior.

## Root cause

`project.godot` `[display]` sets `viewport_width=192`, `viewport_height=108` but **no `window/stretch/mode`**. Godot's default is `stretch/mode = "disabled"`, which expands the *root viewport itself* to match the OS window. On a 1200×1600 laptop screen running fullscreen, the viewport renders at the full screen resolution — roughly **150× the intended pixel count** — so the chunk-render fragment shader, glow pass, and tonemap pass all run over a much larger framebuffer than the 192×108 the project was designed for.

The user verified the diagnosis by setting `stretch/mode = "viewport"`: FPS jumped immediately, but the side effect was that all UI also rendered at 192×108 and appeared extremely low-res once upscaled.

## Goal

- World renders at low resolution (192×108) for bounded GPU cost.
- UI renders at native screen resolution for crispness.
- HDR-2D and glow on the world stay enabled (art-direction requirement).
- Old-laptop FPS reaches **≥60 sustained, ideally 90+**.

## Out of scope

- The chunk render shader (`shaders/visual/render_chunk.gdshader`) — not modified.
- Cellular sim, collision rebuild, chunk streaming logic — not modified.
- Missing wall textures in exported builds — separate session.
- Non-game scenes (`main_menu.tscn`, etc.) — only the global stretch-mode change affects them; no restructure.

## Approach: SubViewport for the world, UI on the root

The canonical Godot 4 pattern for low-res-pixel games with high-res UI: the world lives in a `SubViewport` at fixed 192×108, and UI lives directly on the root viewport (which runs at native screen resolution). Two alternatives were considered and rejected:

- **Reauthor UI assets at larger logical sizes within `stretch/mode = "viewport"`.** Cheap, but UI is permanently capped at the upscaled 192×108 grid. Doesn't satisfy the high-res UI requirement.
- **`stretch/mode = "canvas_items"` + render world to per-chunk render targets.** Equivalent perf result, but more invasive on the rendering pipeline (per-chunk RT management, redo glow/HDR through a custom path) for no clear win.

## Design

### Scene tree restructure (`scenes/game.tscn`)

**Before:**

```
Main (Node2D)
├── WorldManager
│   ├── ChunkContainer
│   └── WorldPreview
├── Player
├── DebugManager
│   ├── ChunkGridOverlay
│   └── CollisionOverlay
├── WorldEnvironment       ; glow + HDR
├── DirectionalLight2D
├── PauseMenu
├── HealthUI
├── DeathScreen
├── CurrencyHUD
├── WeaponPopup
└── WeaponButton
```

**After:**

```
Main (Node2D)
├── WorldViewportContainer (SubViewportContainer, stretch=true, fills screen)
│   └── WorldSubViewport (SubViewport, size=Vector2i(192,108),
│                         render_target_update_mode=ALWAYS,
│                         hdr_2d=true)
│       ├── WorldEnvironment        ; glow stays enabled here
│       ├── DirectionalLight2D
│       ├── WorldManager
│       │   ├── ChunkContainer
│       │   └── WorldPreview
│       ├── Player                  ; Camera2D inside Player remains inside SubViewport
│       └── DebugManager
│           ├── ChunkGridOverlay
│           └── CollisionOverlay
├── PauseMenu                       ; CanvasLayer on root
├── HealthUI                        ; CanvasLayer on root
├── DeathScreen                     ; CanvasLayer on root
├── CurrencyHUD                     ; CanvasLayer on root
├── WeaponPopup                     ; CanvasLayer on root
├── WeaponButton                    ; CanvasLayer on root
└── FPSHud                          ; CanvasLayer on root (must NOT move into SubViewport)
```

**Rules enforced by this layout:**

- Everything in world coordinates (camera, lights, chunks, player, debug overlays, world-space FX) lives in the SubViewport.
- All UI (CanvasLayers, Control trees) lives on the root.
- `WorldSubViewport.size = Vector2i(192, 108)` is the hard cap on world fragment-shader cost. Window resizing does not change it.
- `SubViewportContainer.stretch = true` upscales the rendered SubViewport texture to fill its rect. With `default_texture_filter=0` (nearest), upscaling is crisp pixel-art.
- Mouse input through `SubViewportContainer` with `stretch = true` is forwarded into the SubViewport with correct coordinate translation; world-space scripts using `get_global_mouse_position()` continue to work.

### Project settings (`project.godot`)

```ini
[display]

window/size/viewport_width=320            ; logical UI design size
window/size/viewport_height=180
window/size/window_width_override=1280    ; initial window size; tune to taste
window/size/window_height_override=720
window/stretch/mode="canvas_items"        ; UI renders at native res, logical 320×180
window/stretch/aspect="keep"              ; preserve aspect; revisit if letterboxing is unwanted

[rendering]

textures/canvas_textures/default_texture_filter=0   ; unchanged — keeps pixel-art crisp
viewport/hdr_2d=false                                ; OFF on root; enabled on SubViewport instead
rendering_device/driver.windows="d3d12"              ; unchanged
```

Rationale:
- `stretch/mode = "canvas_items"` makes the root viewport render at native screen resolution (UI is crisp) while UI Control nodes use a stable logical 320×180 coordinate system.
- HDR-2D moves off the root (UI doesn't need it; saves bandwidth) and onto the SubViewport (where the world lives).
- The logical UI canvas (320×180) is decoupled from the world SubViewport (192×108). The two coordinate systems do not need to match — the SubViewportContainer handles scaling between them.

**Logical UI viewport: 320×180.** Existing UI scenes were authored against 192×108, so this is a uniform 1.667× scale-up. Anchored-from-edge layouts continue to work with no change; centered or percent-based layouts may need a one-pass review. This logical size is large enough to author finer-grained UI without the cost or layout shock of jumping to 640×360 or 1920×1080.

### Post-FX placement

`WorldEnvironment` (currently with `glow_enabled = true`) and `hdr_2d` are per-viewport. After the move:

- `WorldEnvironment` node lives inside `WorldSubViewport`.
- `WorldSubViewport.hdr_2d = true`.
- Root viewport: no `WorldEnvironment`, no HDR, no glow. UI is unaffected.

Glow + tonemap continue to run, but only at 192×108 → trivial cost (<0.2 ms expected).

### Code touch-points

The change is mostly tscn-level. Code touch-points:

1. **`scenes/game.tscn`** — restructured per the diagram above. Property edits on the new SubViewport: `size = Vector2i(192, 108)`, `render_target_update_mode = ALWAYS`, `hdr_2d = true`. Container: `stretch = true`, anchors filling screen.
2. **`src/core/world_manager.gd`** — no logic changes required. `RenderingServer.get_rendering_device()` is global. `add_to_group("world_manager")` and `get_first_node_in_group(...)` work across viewport boundaries (groups are tree-global). The existing `if Engine.is_editor_hint(): return` guard in `_process` is preserved.
3. **`src/autoload/scene_manager.gd`** — review scene-transition paths to ensure no assumption that game-scene children are flat siblings. (Current code switches whole scenes via the SceneTree, which is unaffected.)
4. **`src/debug/*`** — overlays move into the SubViewport with the rest of the world. The recently added FPS HUD (commit `affcb8c`) is UI and stays on the root.
5. **Mouse/input audit** — search for `get_viewport().get_mouse_position()`, `get_viewport_rect()`, `get_viewport_transform()`, and any manual screen→world conversion. With `SubViewportContainer.stretch = true`, world-space nodes calling `get_global_mouse_position()` get correct results automatically. UI-side mouse reads are unaffected (they're on the root).
6. **`src/terrain/world_preview.gd`** — child of `WorldManager`, moves with it. No change.

## Verification plan

1. **Game scene boots.** World renders inside SubViewport at 192×108, upscaled crisply via nearest filtering. UI renders at native screen resolution.
2. **Visual Profiler targets:**
   - Root `Render Viewport 0` total: <1 ms (compositing SubViewport texture + UI).
   - `Render Viewport 1` (SubViewport) total: ~0.5–1 ms (chunks + glow + tonemap at 192×108).
   - **Combined GPU frame time: <11 ms (≥90 FPS).**
3. **In-game functional checks:**
   - Player movement, mouse-aimed attacks, world mouse position correct.
   - All UI flows render crisp on the root: pause menu, weapon popup, weapon button, chest UI, death screen, currency HUD, FPS HUD.
   - Debug overlays (chunk grid, collision overlay) toggle correctly and align to world.
   - World preview functionality intact.
   - Glow visible on world; not bleeding onto UI.
4. **Window resize / fullscreen test.** World scales but stays crisp; UI stays at native res; **GPU time does not climb with window size** (the SubViewport cap is the entire point).
5. **Old-laptop re-measure.** ≥60 FPS sustained in-game; ideally 90+.

## Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| UI layouts shift when logical viewport scales from 192×108 to 320×180 | Medium | Anchored-from-edge layouts are unaffected. Sweep each UI scene (PauseMenu, HealthUI, DeathScreen, CurrencyHUD, WeaponPopup, WeaponButton, ChestUI, ShopUI, FPSHud, MainMenu, SettingsPopup) for centered or percent-based positioning that needs adjustment. |
| A script does manual screen→world coord math via the root viewport | Low–Medium | Audit `get_viewport()` / `get_viewport_rect()` / `get_viewport_transform()` callers. |
| `DirectionalLight2D` left outside SubViewport stops lighting world | Certain if missed | Move into SubViewport per Section 1; verify visually. |
| `WorldEnvironment` glow disappears | Certain if missed | Move into SubViewport; enable `hdr_2d` on SubViewport; verify visually. |
| Cross-viewport node-group lookups fail | Low | Groups are tree-global in Godot 4. Spot-check `get_first_node_in_group(...)` callers. |
| FPS HUD ends up inside SubViewport (low-res) | Low | Explicit rule: FPS HUD is UI, on the root. |

## Definition of done

- `scenes/game.tscn` restructured per Section 1.
- `project.godot` updated per Section 2.
- `WorldEnvironment` + `DirectionalLight2D` inside SubViewport; `hdr_2d` on SubViewport.
- All UI flows manually verified: pause, death, weapon popup/button, chest, shop, currency HUD, FPS HUD, health UI.
- Visual Profiler confirms world `Render Canvas` ≪ 1 ms (down from 15.77 ms).
- Old-laptop measurement: ≥60 FPS sustained during gameplay.
- No regression in input, mouse coords, debug overlays, scene transitions, glow look.
