# Player Sprite & Attack Lean — Design

## Intent

The player is still a green `ColorRect` placeholder. Replace it with the new
idle/run sprite sheets, and make every attack juicier by briefly shearing and
stretching the sprite toward the attack direction with a tween.

## Goals

- Player draws from `textures/Player/idle_sheet_00002_fixed.png` and
  `run_sheet_00002_fixed.png`, idle when still, run when moving.
- Four facings from the sheet rows: front/back × left/right.
- Each attack that actually fires plays a quick lean toward the attack
  direction, pivoting at the feet.

## Non-goals

- No hitbox change: collision stays 8×12.
- No new animations (attack, hurt, death) — only the two sheets.

## Anti-goals

- Don't scale the sprite down to match the hitbox. A sprite larger than the
  hitbox is intentional: it reads better in chaotic fights.
- Lean and hit squash must not fight over the sprite's transform.

## Constraints / facts

- Frames are 32×32. Idle: 20 frames per row. Run: 18 frames on rows 0 and 2,
  16 on rows 1 and 3. Character art is ~15×29 px with feet at y≈30–31.
- Row read (verify in editor): 0 front-left, 1 back-left, 2 front-right,
  3 back-right.
- All weapons fire through `Weapon.use()` (`src/weapons/weapon.gd`) after the
  cooldown check — the single choke point for "an attack fired".
- Hit flash, hit squash, status tint and burn flash in
  `src/player/player_controller.gd` currently target `_color_rect`;
  `tests/unit/test_player_controller.gd` assigns `_color_rect` directly.

## Approaches

- **A. `Sprite2D` grid, frames advanced in code** — smallest, no resource
  file, but no editor preview of animations.
- **B. `AnimatedSprite2D` + `SpriteFrames` `.tres`** — 8 named animations
  editable/previewable in Godot's SpriteFrames editor; large resource file.
- `AnimationPlayer` ruled out: heaviest, only pays off for frame events.

**Chosen: B** (user's pick), for editor visibility and tuning of the
animations.

## Decided

- `AnimatedSprite2D` replaces `ColorRect` in `scenes/player.tscn`, drawn at
  native size (no scaling).
- Sprite node sits at the hitbox bottom (y = +6); art is lifted with `offset`
  so the node origin is at the feet. Skew/scale therefore pivot at the feet.
- Animations: `idle_front_left`, `idle_back_left`, `idle_front_right`,
  `idle_back_right`, and the same four for `run_*`, looping.
- Attack lean, triggered from `Weapon.use()` on the user (if it supports it),
  toward the attack direction:
  - horizontal attacks: mostly `skew` toward the attack side, slight stretch;
  - vertical attacks: mostly vertical stretch up from the feet, plus a little
    skew toward the attack's side;
  - diagonals blend the two.
- Hit squash overrides an in-progress lean.
- Hit flash, squash, status tint, burn flash and left/right handling move from
  `_color_rect` to the sprite; the unit test is updated accordingly.

## Calls I made (check these)

- Lean timing: ~0.05s out, ~0.15s back with elastic ease (like hit squash).
- Perfectly straight up/down attacks skew toward the current facing side.
- Facing row: back rows when `_last_facing.y < 0`, else front; left/right from
  `_facing_left`. Run when the player is moving (input or velocity), else idle.
- FPS: idle 10, run 15 — tunable in the `.tres`.
- Dash counts as an attack and leans too (it goes through `Weapon.use()`).
- Left/right: use the separate left/right rows rather than `flip_h`, since the
  sheet provides both.

## Left to the builder

- How the `.tres` is produced (hand-authored in the editor or generated once by
  a script) — it is the committed artifact either way.
- Exact skew/stretch magnitudes; tune by eye.
