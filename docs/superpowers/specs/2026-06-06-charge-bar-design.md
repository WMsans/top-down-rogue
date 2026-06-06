# Charge Bar + Full-Charge Gate — Design

**Date:** 2026-06-06
**Status:** Approved, ready for implementation plan

## Problem

The willowblade and other `AdvancedMeleeWeapon` charge weapons fire their charged
attack (e.g. the willowblade thrust) on *any* press held longer than
`tap_threshold` (0.12s). That threshold is so small that an ordinary tap delivers
the thrust instead of the light slash. There is also no visible feedback for how
charged the attack is, only a gold tint on the sword sprite.

## Goals

1. The charged attack only fires when the weapon is **fully charged**.
2. A **charge bar** appears above the player's body while a chargeable weapon is
   charging, filling as the charge builds.
3. The bar gives a clear cue when it is full (color change + tiny vibration).

## Behavior

`AdvancedMeleeWeapon.on_release` replaces the `tap_threshold` gate with a
full-charge gate:

| Release condition                  | Result                  |
| ---------------------------------- | ----------------------- |
| `get_charge_ratio() >= 1.0` (full) | Charged attack (thrust) |
| Released before full               | Light attack (slash)    |

- The charge is **hold-to-full, fire-on-release**: the bar fills while held and
  stays full until release; nothing auto-fires at full.
- Any early release performs the light attack (slash), so the weapon stays usable
  for quick attacks. The thrust is reserved for a full charge.
- `tap_threshold` is no longer used for the release decision. Leave the field in
  place (harmless) but drop it from the branching logic.
- The existing gold sprite-tint tell in `_process_idle` stays as-is; it
  complements the bar.

## Architecture

**Approach: world-space `ChargeBar` node, child of the player, driven by
`WeaponManager`.** Chosen over (a) the weapon drawing its own bar inside
`update_visual` — mixes UI into the sword pose animation and must be redone per
weapon — and (b) a HUD/CanvasLayer bar projected to screen — overkill, breaks
under camera zoom, more code. A world-space child of the player follows the body
automatically, scales with the camera, and needs no projection math.

### Components

- **`Weapon` (base) — new query API.** Default methods so the manager can treat
  every weapon uniformly:
  - `is_chargeable() -> bool` — default `false`.
  - `is_charging() -> bool` — default `false`.
  - (`get_charge_ratio() -> float` already exists on `AdvancedMeleeWeapon`; if the
    manager calls it generically, add a default `0.0` on the base too.)
- **`AdvancedMeleeWeapon` — overrides:**
  - `is_chargeable()` → `not charged_moves.is_empty()`.
  - `is_charging()` → `_charging`.
- **`ChargeBar` (new, `src/ui/charge_bar.gd`) — `Node2D`** positioned at
  approximately `(0, -22)` — **above the status-icon row**, not on the body.
  The player's `StatusVisuals` anchors icons at `y = -10` and they are ~14 px
  tall (`ICON_DISPLAY_PX`), so they span roughly y = -17 to -3
  (`src/player/player_controller.gd:78`, `src/status/status_visuals.gd`). The
  bar must clear that: `y = -22` leaves a small gap above the icon row. Use a
  fixed position (do not overlap the icons even when no statuses are active).
  Custom `_draw`:
  - Background: ~18×3 px dark rounded/plain rect.
  - Fill: width = `ratio × bar_width`, drawn over the background.
  - Public setters, e.g. `set_ratio(r: float)` storing the ratio and calling
    `queue_redraw()`; `set_active(on: bool)` toggling `visible`.
  - Hidden by default.
- **`WeaponManager`** creates one `ChargeBar` as a child of the player in
  `_setup_visual`. Each `_process(delta)` frame:
  - If `_active_weapon != null and _active_weapon.is_charging()`: show the bar and
    set its ratio from `_active_weapon.get_charge_ratio()`.
  - Otherwise: hide the bar.

### Full-charge cue

When `ratio >= 1.0` the `ChargeBar`:

- Draws the fill in a brighter/saturated **gold** instead of the filling-state
  amber — a clear "release now for the thrust" signal that matches the existing
  gold sprite tint.
- Applies a **tiny vibration**: a small random per-frame positional jitter (e.g.
  ±1 px on x/y) around the bar's anchor while full, returning to the anchor when
  not full. Keep the amplitude small so it reads as a subtle buzz, not a shake.

## Data flow

```
key held
  -> on_press: _charging = true
  -> _tick_impl(delta): _charge_time advances toward charge_time_full
  -> WeaponManager._process: is_charging() true -> bar.set_active(true),
       bar.set_ratio(get_charge_ratio())
  -> ChargeBar._draw: fill = ratio; at full -> gold + jitter
key released
  -> on_release: ratio >= 1.0 ? charged thrust : light slash
  -> _charging = false
  -> WeaponManager._process: is_charging() false -> bar.set_active(false)
```

## Visual defaults

- Bar size: ~18×3 px.
- Position: `(0, -22)` relative to the player — above the status-icon row (which
  spans ~y = -17 to -3) so the two never overlap.
- Colors: dark background; amber fill while charging; brighter gold when full.
- Full vibration: ±1 px random jitter per frame.

These are starting values; tune by eye when running the game.

## Testing

- **Unit:** `on_release` at a full charge ratio fires the charged thrust;
  released below full fires the light slash. Extends/updates
  `tests/unit/test_advanced_melee_charge.gd` and
  `tests/unit/test_weapon_charge_api.gd`, which currently assert the old
  `tap_threshold` behavior.
- **Unit:** `is_chargeable()` / `is_charging()` return correct values for the
  willowblade (chargeable) versus a non-charge weapon (not chargeable).
- **Visual (manual, in-game):** the bar appears above the body while charging,
  fills smoothly, turns gold and vibrates at full, and hides on release. Not
  unit-tested.

## Out of scope

- Charge mechanics for ranged/other weapon types beyond the existing
  `AdvancedMeleeWeapon` charge weapons.
- Reworking the gold sprite-tint tell.
- Auto-fire at full (explicitly decided against; fire on release).
