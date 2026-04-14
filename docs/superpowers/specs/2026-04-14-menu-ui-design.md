# Main Menu, Settings Popup, and Pause Menu Design

## Overview

Add a main menu screen, a shared settings popup, and an in-game pause menu to the TopDownRogue project. All UI uses a retro pixel-art style with a pixel/bitmap font matching the game's aesthetic.

## Architecture: Scene-per-Menu

Each menu is its own scene. A `SceneManager` autoload handles transitions between scenes and pause state. The Settings popup is a reusable scene instanced into both the Main Menu and Pause Menu.

### Scene Structure

```
scenes/
  ui/
    main_menu.tscn       # Startup scene, set as project main_scene
    pause_menu.tscn       # CanvasLayer overlay, instanced into game scene
    settings_popup.tscn   # Shared popup, instanced by MainMenu and PauseMenu
  game.tscn               # Renamed from main.tscn (gameplay scene)

src/
  ui/
    main_menu.gd          # Main menu logic
    pause_menu.gd          # Pause menu logic
    settings_popup.gd      # Settings popup logic
  autoload/
    scene_manager.gd       # Scene transitions and pause management
```

### Autoloads

Add `SceneManager` as an autoload in `project.godot`:
- Manages transitions between `main_menu` and `game` scenes
- Handles soft pause (gameplay nodes paused, ambient/effects can continue)
- Provides methods: `go_to_game()`, `go_to_main_menu()`, `set_paused(bool)`

## Components

### 1. Main Menu (`scenes/ui/main_menu.tscn`)

- **Project startup scene** — set as `run/main_scene` in `project.godot`
- Title is a **Sprite2D** (pixel-art image asset), not a font label
- All other text uses a pixel/bitmap font
- Three buttons: **Play**, **Settings**, **Quit**
- Centered layout with pixel-art bordered panels
- Dark background fills the screen
- Keyboard-navigable (Up/Down arrows + Enter)
- Play → `SceneManager.go_to_game()` with fade-to-black transition
- Settings → instances `settings_popup.tscn` as a child
- Quit → `get_tree().quit()`

### 2. Pause Menu (`scenes/ui/pause_menu.tscn`)

- **CanvasLayer** overlay, instanced into `game.tscn`
- Toggled by **ESC** key
- **Soft pause**: gameplay stops but ambient animations/effects can continue (uses `process_mode` filtering)
- Semi-transparent dark backdrop over the game world
- Header styled as a pixel-art bordered frame reading "PAUSED"
- Three buttons: **Resume**, **Settings**, **Main Menu**
- Resume → closes menu, unpauses game (same effect as pressing ESC)
- Settings → instances `settings_popup.tscn` as a child on top
- Main Menu → shows confirmation ("All progress will be lost!"), then `SceneManager.go_to_main_menu()`
- Closing Settings returns to the pause menu (not directly to game)
- Keyboard-navigable (Up/Down arrows + Enter, ESC to close/go back)

### 3. Settings Popup (`scenes/ui/settings_popup.tscn`)

- **Shared, reusable scene** — instanced by both MainMenu and PauseMenu
- Centered popup panel with pixel-art border frame
- Header bar with title "SETTINGS" and close button (X)
- Three sections separated by pixel-art dividers:

#### Audio
- **Master** volume slider (HSlider, 0–100%, default 80%)
- **Music** volume slider (HSlider, 0–100%, default 60%)
- **SFX** volume slider (HSlider, 0–100%, default 80%)

#### Display
- **Fullscreen** toggle (ON/OFF, default based on current state)

#### Key Bindings
- Move Up: W (click to rebind)
- Move Left: A (click to rebind)
- Move Down: S (click to rebind)
- Move Right: D (click to rebind)
- Clicking a binding row enters "Press a key..." mode, captures next key input
- ESC during rebinding cancels the rebind

- **Back** button closes the popup
- ESC closes settings, returns to parent menu
- When opened from pause menu, game stays paused
- **Persists** settings to `user://settings.cfg` via `ConfigFile`
- Loads saved settings on startup

### 4. SceneManager Autoload (`src/autoload/scene_manager.gd`)

- Registered as autoload in `project.godot`
- Manages scene transitions with fade-to-black (`AnimationPlayer` or `Tween`)
- `go_to_game()` — transitions from main menu to game scene
- `go_to_main_menu()` — transitions from game to main menu
- `set_paused(paused: bool)` — soft pause (sets `process_mode` on gameplay nodes, not the whole tree)
- Emits signals: `scene_changed`, `pause_toggled`

### 5. Scene Rename: `main.tscn` → `game.tscn`

- Current `scenes/main.tscn` renamed to `scenes/game.tscn`
- Update `project.godot` main_scene to point to `scenes/ui/main_menu.tscn`
- Update any references to the old path

## Visual Style

- **Pixel/bitmap font** for all UI text
- **Title** on main menu is a Sprite2D (pixel-art image)
- Dark color palette: deep purples (#1a0a2e, #2d1b4e), accent pinks (#ff79c6), accent cyan (#8be9fd), borders in violet (#bd93f9)
- Button styling: bordered panels with pixel-art frames
- Consistent padding and spacing throughout all menus
- "PAUSED" header uses same bordered panel style as buttons

## Soft Pause Implementation

Use Godot's built-in pause system with `get_tree().paused = true`:
- Set `process_mode = PROCESS_MODE_WHEN_PAUSED` on the pause menu CanvasLayer so it runs during pause
- Set `process_mode = PROCESS_MODE_ALWAYS` on any ambient effects that should continue during pause
- Default nodes inherit `PROCESS_MODE_INHERIT` and are paused automatically
- SceneManager toggles `get_tree().paused` and emits `pause_toggled` signal

## File Changes Summary

1. **New files**: `scenes/ui/main_menu.tscn`, `scenes/ui/pause_menu.tscn`, `scenes/ui/settings_popup.tscn`, `src/ui/main_menu.gd`, `src/ui/pause_menu.gd`, `src/ui/settings_popup.gd`, `src/autoload/scene_manager.gd`
2. **Rename**: `scenes/main.tscn` → `scenes/game.tscn`
3. **Modify**: `project.godot` — update main_scene, add SceneManager autoload
4. **Modify**: `scenes/player.tscn` or game scene — instance pause_menu, adjust process_mode
5. **Asset**: Pixel/bitmap font resource, title sprite asset (if not already available)