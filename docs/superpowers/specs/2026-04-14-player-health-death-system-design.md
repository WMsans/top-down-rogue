# Player Health & Death System

## Overview

A component-based health and death system. A `HealthComponent` node manages HP and i-frames, a `LavaDamageChecker` applies damage from hazardous materials, a `HealthUI` displays current/max HP as a bar with numbers, and a `DeathScreen` shows a dramatic overlay on death before sending the player to the main menu.

**Approach:** HealthComponent as a child node of Player (Approach A) — follows the project's component pattern (like `WeaponManager`), keeps responsibilities separate, and is reusable for enemies later.

---

## 1. Health Component (`src/player/health_component.gd`)

A child node on the Player scene, same pattern as `WeaponManager`.

**Properties:**
- `max_health: int` — export, default 100
- `_current_health: int` — initialized to `max_health` on ready
- `_invincible_timer: float` — counts down each physics frame
- `invincibility_duration: float` — export, default 1.0 seconds
- `_is_dead: bool` — prevents further damage/healing after death
- `_is_invincible: bool` — true while timer is active

**Signals:**
- `health_changed(current: int, max: int)` — emitted on any HP change
- `died` — emitted once when health reaches 0

**Public methods:**
- `take_damage(amount: int)` — reduces HP by amount (clamped to 0). Starts i-frames. Emits `health_changed`. If HP hits 0 and not already dead, sets `_is_dead = true` and emits `died`. No-op if dead or invincible.
- `heal(amount: int)` — increases HP (clamped to max). Emits `health_changed`. No-op if dead.
- `is_dead() -> bool`

**_physics_process:**
- Counts down `_invincible_timer`. When it reaches 0, sets `_is_invincible = false`.

---

## 2. Material Damage Property (`material_registry.gd`) + Lava Damage Checker (`src/player/lava_damage_checker.gd`)

### MaterialDef changes in `material_registry.gd`

- Add `var damage: int` property — damage dealt per i-frame contact period (0 = harmless)
- Add `p_damage: int = 0` parameter to `_init()`
- LAVA gets `damage = 10`, all other materials default to 0
- Add lookup method: `get_damage(material_id: int) -> int`

### LavaDamageChecker

A child node on the Player scene (alongside HealthComponent and WeaponManager).

**Behavior:**
- Each physics frame, samples a 3x3 grid of points within the player's 8x12 bounding box
- Queries `WorldManager` for the material at each pixel
- Accumulates total damage from materials with `damage > 0` (via `MaterialRegistry.get_damage()`)
- Calls `health_component.take_damage(total_damage)` — i-frames in HealthComponent prevent double-tapping
- No hardcoded material references — purely data-driven via MaterialRegistry

**Properties:**
- References to `health_component` and the player's `shadow_grid` acquired via sibling nodes on ready

**Material querying:**
- Uses `shadow_grid.get_material(world_x, world_y)` to read material IDs at sampled pixel positions
- `ShadowGrid` is already a child of the Player node and synced each frame, so it provides an efficient local lookup
- For each sampled point, calls `MaterialRegistry.get_damage(material_id)` to get the damage value

---

## 3. Health UI (`src/ui/health_ui.gd`)

A CanvasLayer scene (`scenes/ui/health_ui.tscn`) anchored to the top-left corner.

**Visual layout:**
```
HealthUI (CanvasLayer, layer=5)
  └─ MarginContainer (anchors: top-left, margins: 8px)
       └─ VBoxContainer
            └─ HealthBar (TextureProgressBar or ColorRect-based bar)
            └─ HealthLabel (Label, e.g. "100 / 100")
```

**Bar style:**
- Simple ColorRect-based bar: dark gray background rect + foreground rect that scales width proportionally to HP ratio. Solid red color for the fill. Matches the pixel-art aesthetic without requiring custom textures.

**Behavior:**
- On `_ready()`, finds the `HealthComponent` via the player node path and connects to `health_changed` signal
- On `health_changed(current, max)`: updates bar width and label text
- On `died`: bar drops to 0, label shows "0 / max"
- Uses `SDS_8x8.ttf` pixel font, consistent with main_menu and pause_menu theming
- Theme applied via `_apply_theme()` following the existing pattern (white text, purple hover color)

---

## 4. Death Screen (`src/ui/death_screen.gd`)

A CanvasLayer scene (`scenes/ui/death_screen.tscn`) that appears when the player dies.

**Structure:**
```
DeathScreen (CanvasLayer, layer=20, process_mode=ALWAYS, initially hidden)
  └─ ColorRect (full-screen dim overlay, black, alpha animated)
  └─ CenterContainer (full-screen anchor)
       └─ VBoxContainer
            └─ "YOU DIED" Label (large pixel font)
            └─ ContinueButton (Button, "CONTINUE")
```

**Death sequence (triggered by `HealthComponent.died` signal):**

1. **Freeze** — `SceneManager.set_paused(true)` so physics stops
2. **Red flash** — Brief full-screen red tint that fades out over 0.3s (using Tween)
3. **Slow-motion zoom** — Subtle camera zoom effect over ~0.5s, scaling the player's Camera2D zoom slightly inward (uses Tween with TWEEN_PAUSE_PROCESS so it animates during pause)
4. **Dim overlay fades in** — Black overlay animates from alpha 0 → 0.7 over 0.8s
5. **"YOU DIED" text fades in** — Appears after the dim overlay, with a 0.3s fade-in after a 0.5s delay
6. **Continue button appears** — Fades in 0.3s after the text, grabs focus

**On Continue pressed:**
- `SceneManager.set_paused(false)`
- `SceneManager.go_to_main_menu()` — uses the existing fade-to-black transition

**Wiring:**
- Instantiated in `game.tscn` alongside PauseMenu
- On `_ready()`, connects to `HealthComponent.died` signal via the player node
- Has `_show_death_screen()` method that runs the sequence above
- Process mode: `PROCESS_MODE_ALWAYS` (same pattern as PauseMenu) so it animates during pause

---

## Files to Create/Modify

| Action | File |
|--------|------|
| Create | `src/player/health_component.gd` |
| Create | `scenes/player.tscn` (add HealthComponent + LavaDamageChecker nodes) |
| Create | `src/player/lava_damage_checker.gd` |
| Create | `src/ui/health_ui.gd` |
| Create | `scenes/ui/health_ui.tscn` |
| Create | `src/ui/death_screen.gd` |
| Create | `scenes/ui/death_screen.tscn` |
| Modify | `src/autoload/material_registry.gd` (add `damage` property to MaterialDef) |
| Modify | `scenes/game.tscn` (add HealthUI and DeathScreen instances) |

---

## Future Considerations

- Enemy health: HealthComponent is reusable — enemies can have their own instances
- Healing pickups: can call `health_component.heal()` from any source
- Damage numbers: can be triggered by connecting to `health_changed` and comparing delta
- Additional hazardous materials: just add `damage > 0` to MaterialDef entries (e.g., poison gas)