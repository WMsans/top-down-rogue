# Juicy UI Refactor — Design

**Status:** approved (brainstorm)
**Date:** 2026-05-11
**Owner:** jeremyzhao

## Problem

UI panels in `src/ui/` show and hide instantly (or with minimal animation). They feel flat next to `src/ui/card.gd`, which has elastic hover, idle tilt, click squash, and shadow lift. The biggest gap is **show/hide transitions** — panels appear/disappear without weight, momentum, or polish. The goal is a focused refactor that makes every modal panel open and close juicily, with a consistent feel, via a shared base class.

## Goals

- Every modal panel opens with a "drop-in with weight" animation and closes by dropping out downward.
- Inside panels, content elements stagger-fade in after the panel lands.
- The juice is packaged so all panels share it — adding a new panel later is one `extends JuicyPanel` away.
- Pause-time panels (`pause_menu`, `settings_popup`) animate correctly while the game is paused.
- No regression to existing button hover/press feedback or HUD behavior.

## Non-goals

- HUD juice (health bar shake, currency tick, damage flashes). Separate follow-up.
- Per-button polish beyond what `ui_animations.gd` already does.
- Sound effects on open/close (signal hooks exist; no audio wired in this pass).
- Changes to `card.gd` itself — already juicy, stays as-is.
- Any change to `currency_hud.gd`, `health_ui.gd`, `weapon_button.gd`, `ui_theme.gd`.

## Architecture

### New: `src/ui/juicy_panel.gd`

`class_name JuicyPanel extends Control`. Base class every modal panel root extends.

**Public API:**
- `open()` — animates the panel in. Idempotent: safe to call when already open or opening.
- `close()` — animates the panel out. Idempotent.
- Signals: `opened`, `closed` — emitted after the respective animation completes.

**Inspector exports:**
| name | type | default | purpose |
| --- | --- | --- | --- |
| `has_backdrop` | `bool` | `true` | Create/fade a full-screen dim behind the panel. |
| `backdrop_color` | `Color` | `Color(0, 0, 0, 0.55)` | Target backdrop color when open. |
| `close_on_backdrop_click` | `bool` | `true` | Left-click on backdrop triggers `close()`. |
| `content_root` | `NodePath` | `""` | If set, immediate `Control` children of this node stagger-fade in. |
| `drop_distance` | `float` | `80.0` | Pixels above start for entry; pixels below for exit. |
| `enter_duration` | `float` | `0.45` | Total open animation length. |
| `exit_duration` | `float` | `0.35` | Total close animation length. |
| `stagger_delay` | `float` | `0.05` | Delay between each content child's entry tween. |

**Internal state:**
- `_is_animating: bool` — gates input during transitions.
- `_is_open: bool` — current logical state.
- `_rest_position: Vector2` — captured panel position; entry/exit offsets are relative to this.
- `_content_rest_positions: Dictionary[Control, Vector2]` — cached per-child positions for stagger.
- `_backdrop: ColorRect` — lazily created or adopted (see Backdrop section).
- `_open_tween`, `_close_tween: Tween` — kept so the opposite call can cancel them.

**Behavior contract:**
- Calling `open()` while opening: no-op.
- Calling `open()` while closing: kill close tween, restore cached positions, start open from current visual state.
- Calling `close()` while closing: no-op.
- Calling `close()` while opening: kill open tween, start close from current visual state.
- `opened` and `closed` only emit when the animation completes (not when interrupted).

### Files refactored

Each becomes `extends JuicyPanel`:
- `src/ui/chest_ui.gd`
- `src/ui/death_screen.gd`
- `src/ui/pause_menu.gd`
- `src/ui/settings_popup.gd`
- `src/ui/weapon_popup.gd`
- `src/ui/main_menu.gd` *(if it acts as a modal layer; confirm during implementation — may instead stay as-is or only adopt the drop-in motion)*

### Files untouched

- `src/ui/card.gd`
- `src/ui/currency_hud.gd`
- `src/ui/health_ui.gd`
- `src/ui/weapon_button.gd`
- `src/ui/ui_theme.gd`

### `src/ui/ui_animations.gd`

Public API stays. May gain 1–2 internal helpers used by `JuicyPanel` (e.g., a pivot-centering helper extension). No removals.

## Animation specification

### `open()` sequence

Frame 0 setup:
- Panel `visible = true`, `modulate.a = 0`, `position = _rest_position - Vector2(0, drop_distance)`, `scale = Vector2(0.96, 1.04)` (subtle anticipation squash).
- Pivot set to `size * 0.5` (rebound on `resized`).
- Backdrop (if present) `color.a = 0`.

Parallel tweens (all on a single sequenced tween with `parallel()` where noted):
1. **Backdrop fade-in** — `color:a → backdrop_color.a`, duration `0.18s`, linear.
2. **Panel drop** — `position:y → _rest_position.y`, duration `enter_duration`, `TRANS_BACK` / `EASE_OUT`. The back overshoot gives the "lands and settles" feel.
3. **Panel fade-in** — `modulate:a → 1`, duration `enter_duration * 0.4`, linear. Solid before landing.
4. **Panel squash settle** — `scale → Vector2.ONE`, duration `enter_duration * 0.9`, `TRANS_ELASTIC` / `EASE_OUT`.
5. **Content stagger** — starts at `enter_duration * 0.6` (see stagger section).

All tweens use `set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)` so they run while paused.

`_is_animating` is set true at the start, false when the longest tween (panel squash settle + stagger) finishes. `opened` emitted on completion.

### `close()` sequence

1. **Content fade-out** — all stagger children `modulate:a → 0` over `0.12s`, parallel (no stagger on exit).
2. After `~50ms`, **panel drop-out**:
   - `position:y → _rest_position.y + drop_distance`, duration `exit_duration`, `TRANS_CUBIC` / `EASE_IN` (accelerating, gravity-like).
   - In parallel: `scale → Vector2(1.02, 0.94)` (elongation as it falls), `modulate:a → 0` over the last `exit_duration * 0.6`.
3. **Backdrop fade-out** — `color:a → 0`, duration `0.18s`, linear, in parallel with panel drop.
4. On completion: panel `visible = false`, position/scale/modulate restored to entry-ready state, `closed` emitted, `_is_animating` cleared.

### Pivot handling

`pivot_offset = size * 0.5` on `_ready()` and on every `resized` signal. Matches `UiAnimations._update_pivot_center`. Ensures scale animates around the center.

## Content stagger

Triggered only if `content_root` is set to a valid node.

**On every `open()`:**
1. Resolve `content_root` to a node; collect its immediate `Control` children in order.
2. For each child, cache its current position into `_content_rest_positions` (overwrites prior cache — handles dynamically-added children).
3. Pre-state: each child `modulate.a = 0`, `position.y += 12` (small upward drift relative to rest).
4. At `enter_duration * 0.6` after open begins, start staggered tweens. For child `i`:
   - At time `i * stagger_delay`:
     - `modulate:a → 1`, duration `0.22s`, linear.
     - `position:y → cached_rest_y`, duration `0.28s`, `TRANS_BACK` / `EASE_OUT`.

**On `close()`:**
- All children `modulate:a → 0` over `0.12s` parallel. Positions are not tweened; they're reset from cache on next `open()`.

**Edge cases:**
- `content_root` empty or invalid → stagger step is skipped.
- Children added/removed at runtime → cache rebuilt on each `open()`.
- Re-open during close → close tween killed, cache restored, open begins from current visual state.

## Backdrop & input gating

### Backdrop

When `has_backdrop = true`:
- On first `open()`, `JuicyPanel` looks for a child `ColorRect` named `_Backdrop`. If found, it's adopted (lets designers customize). If not, one is created and inserted as a child with anchors set to full rect.
- Backdrop sits *behind* the panel via `z_index = -1` relative to the panel (or via being inserted as the first child — implementation detail).
- `mouse_filter = STOP` so clicks don't fall through to gameplay.
- If `close_on_backdrop_click = true`, `gui_input` connects to call `close()` on `MOUSE_BUTTON_LEFT` press.
- Backdrop fades via `color:a` (not `modulate`) so the panel's own modulate doesn't drag it.

### Input gating

- `_is_animating = true` during both `open()` and `close()`.
- While true, panel's `mouse_filter` is forced to `IGNORE`; original value restored after.
- Prevents button presses mid-animation.

### Pause handling

- All `JuicyPanel` tweens use `set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)`.
- `JuicyPanel.process_mode` defaults to `PROCESS_MODE_ALWAYS`. Subclasses may override.
- Verified working with `get_tree().paused = true` for `pause_menu` and `settings_popup`.

## Per-panel migration

Each panel:
1. Change root script `extends` to `JuicyPanel`.
2. Remove any existing show/hide animation code: manual `tween_property` on `modulate`/`position`, direct `visible = ` toggles wrapped in fades, hand-rolled backdrop fades.
3. Replace external callers of `visible = true/false` (or whatever the current open/close API is) with `open()` / `close()`.
4. In the panel scene's inspector, set `content_root` to the existing inner container (typically the `VBoxContainer` holding rows).
5. Set `has_backdrop` to match current behavior. If the scene has a hand-rolled backdrop, either rename it `_Backdrop` (to let `JuicyPanel` adopt) or delete it.
6. Smoke test (see Testing section).

**Per-panel notes (best guesses; verify during implementation):**
- **`pause_menu`** — pause-aware. `has_backdrop = true`.
- **`settings_popup`** — opens over pause menu. `has_backdrop = true`. Stagger looks especially good on rows.
- **`weapon_popup`** — 692 lines; likely the biggest cleanup. Audit for existing animation code to remove.
- **`chest_ui`** — content stagger reveals items one by one, a clear win.
- **`death_screen`** — `has_backdrop = true`, possibly higher backdrop alpha. Stagger optional.
- **`main_menu`** — `has_backdrop = false` (full-screen scene). May or may not adopt `JuicyPanel`; decide during implementation based on whether it functions as a modal layer.

## Testing & success criteria

Manual checklist (no automated tests; this is feel work):

- [ ] Each refactored panel opens with: dim fade-in, panel drops from above, elastic settle, content staggers in.
- [ ] Each panel closes with: content fades, panel falls downward and out, dim fades.
- [ ] Backdrop click closes the panel (when enabled).
- [ ] Escape key continues to close panels that previously used it (handled by existing per-panel input code, not `JuicyPanel`).
- [ ] Spam-clicking the same toggle does not break state (no stuck panels, no overlapping tweens snapping).
- [ ] Calling `close()` mid-open and `open()` mid-close both produce smooth visuals (no snapping back to start).
- [ ] `pause_menu` and `settings_popup` animate while `get_tree().paused = true`.
- [ ] No regression in button hover/press feedback (`UiAnimations` paths still work).
- [ ] No regression in HUDs (`currency_hud`, `health_ui` unchanged).

## Risks & open questions

- **`main_menu` scope** — confirm during implementation whether it adopts `JuicyPanel` or stays as-is. If it's a full-screen scene without a "container" feel, the drop-in may not fit.
- **`weapon_popup` complexity** — 692 lines may contain animation paths that fight `JuicyPanel`. Plan to audit thoroughly during migration.
- **Backdrop layering** — different panels may currently rely on specific z-ordering with other UI (e.g., `settings_popup` over `pause_menu`). Verify backdrop adoption doesn't break stacking.
- **Cached content positions** — if a panel's layout reflows after `open()` (e.g., dynamic content loaded async), cached rest positions will be wrong. Mitigation: rebuild cache when stagger begins, not when `open()` is called, if this turns out to be an issue.
