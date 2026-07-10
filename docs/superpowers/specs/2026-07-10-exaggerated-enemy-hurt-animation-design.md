# Exaggerated Enemy Hurt Animation — Design

## Problem

The enemy's on-hit body reaction is subtle. `Enemy._on_hit()` (`src/enemies/enemy.gd:875`)
plays a quick white flash, a single `(1.4, 0.7)` squash that elastic-eases back to
`(1, 1)` over `0.18s`, and a spark burst. Hits don't read as *painful* — the body
barely deforms and never reacts to the direction it was struck from.

We want the enemy's own sprite to react in an exaggerated, cartoon-physics way:
a big jelly squash-stretch and a directional snap that springs back like 1940s
animation.

## Goals

1. Amplify the squash-stretch into a big, jelly (elastic-spring) deformation.
2. Add a directional recoil: the sprite snaps/leans in the hit direction, then
   springs back to rest with a decaying elastic oscillation.

## Non-goals

- Flash, knockback, hurt sparks, blood splatter, and the global `HitReaction`
  juice stack (screen shake, chromatic flash, hit sparks, damage numbers,
  hit-stop) are **unchanged**.
- No sound effects.
- No new nodes/components: the work stays in `enemy.gd` (Approach A). The
  flash↔status-tint coupling in `_physics_process` and the transform↔death
  coupling in `_process_death` already live here and are coordinated here.
- Only the `Sprite2D` child is animated. No physics body, collision, or
  `global_position` changes — so AI, movement, and knockback are untouched.

## Scope decision (Approach A)

Extend the hurt reaction in place in `enemy.gd` rather than extracting a
`HurtReactionVfx` component. The animation is small, and the sprite transform is
also written every frame by `_process_death` (`enemy.gd:473`) and the sprite
modulate by `_physics_process` (`enemy.gd:284`). Keeping the hurt motion beside
the code that already coordinates those writes is lower-risk than splitting the
coordination across two files.

## Animation Spec

All animation targets the `Sprite2D` child (`get_node_or_null("Sprite2D")`).
Base transform is captured once in `_ready()`:

- `_sprite_base_position: Vector2` — the sprite's local `position` at `_ready`
- `_sprite_base_rotation: float` — the sprite's local `rotation` at `_ready`

Base `scale` is treated as `Vector2.ONE`, consistent with the existing
`_play_squash` and `_process_death` code.

### 1. Squash-stretch (elastic spring) — replaces `_play_squash()`

- On hit, `sprite.scale` snaps instantly to `SQUASH_STRETCH = Vector2(1.65, 0.6)`
  (bigger than the old `(1.4, 0.7)`).
- Tween back to `Vector2.ONE` with `Tween.TRANS_ELASTIC`, `Tween.EASE_OUT` over
  `SETTLE_DURATION = 0.32s`. Elastic ease-out is a decaying harmonic
  oscillation, so the scale overshoots and jellies back on its own — no manual
  keyframes.
- Latest-wins: kill any in-flight `_squash_tween` and re-snap before starting a
  new one (same as today).

### 2. Directional snap + spring settle — new `_play_recoil(hit_dir: Vector2)`

Non-directional fallback: if `hit_dir.length_squared() <= 0.0001`, do nothing
(no snap, nothing to spring from). The squash-stretch above still plays because
it is direction-independent.

Otherwise, one tween (`_recoil_tween`) drives `sprite.rotation` and
`sprite.position` in parallel:

**Snap (instant):**
- `sprite.rotation = _sprite_base_rotation + signf_nonzero(hit_dir.x) * RECOIL_ANGLE`
  where `RECOIL_ANGLE = 0.4` rad (~23° lean into the hit). `signf_nonzero`
  returns `+1.0` when `hit_dir.x >= 0.0`, else `-1.0` (so a purely vertical hit
  still leans a consistent direction rather than snapping to 0).
- `sprite.position = _sprite_base_position + hit_dir.normalized() * RECOIL_OFFSET`
  where `RECOIL_OFFSET = 5.0` px — a sharp body jolt in the push direction,
  distinct from the smoother physics knockback on the body.

**Spring settle (jelly / 1940s):**
- Tween `sprite.rotation` back to `_sprite_base_rotation` and `sprite.position`
  back to `_sprite_base_position`, both with `Tween.TRANS_ELASTIC`,
  `Tween.EASE_OUT` over `SETTLE_DURATION = 0.32s`, run in parallel.
- Elastic ease-out overshoots past base and oscillates back with shrinking
  amplitude: rotation swings past upright and settles; offset jellies back and
  forth along the recoil axis. Deterministic, no randomness.
- Both properties end exactly at base.
- Latest-wins: kill any in-flight `_recoil_tween` and re-snap before starting a
  new one.

## Direction Plumbing

`_on_hit()` currently receives no direction, but `on_hit_impact(impact_point,
hit_dir, damage)` (`enemy.gd:769`) does and calls `hit(damage)` → `_on_hit()`.

- Add member `_last_hit_dir: Vector2 = Vector2.ZERO`.
- In `on_hit_impact`, set `_last_hit_dir = hit_dir` immediately before calling
  `hit(damage)`.
- In `_on_hit()`: play flash (unchanged), play squash-stretch, call
  `_play_recoil(_last_hit_dir)`, burst hurt VFX (unchanged), then reset
  `_last_hit_dir = Vector2.ZERO`.
- Direct `hit()` calls that don't go through `on_hit_impact` leave
  `_last_hit_dir` at `Vector2.ZERO`, so `_play_recoil` no-ops and only the
  squash plays. (`apply_status_damage` is unchanged — it deliberately calls only
  `_play_hit_flash`, never `_on_hit`.)

## Death Coordination

`_process_death` (`enemy.gd:473`) writes `sprite.scale` and `sprite.rotation`
every frame during the death animation. Today the squash tween is **not** killed
on death, so a lethal hit's squash briefly fights the death scaling; the bigger
new animation makes this conflict visible.

On `DEATH` entry in `_change_state` (`enemy.gd:680`, the `State.DEATH` match arm):

- Kill `_squash_tween` and `_recoil_tween` if valid.
- Reset `sprite.scale = Vector2.ONE`, `sprite.rotation = _sprite_base_rotation`,
  `sprite.position = _sprite_base_position` so `_process_death` starts from a
  clean transform and owns it exclusively.

Flash is left as-is: `_physics_process` returns early during `DEATH`
(`enemy.gd:274`), so the flash tween simply finishes fading modulate; the death
dissolve VFX handles the death visual.

## Tuning Constants (on `Enemy`)

Replace the existing `SQUASH_SCALE` / `SQUASH_DURATION`:

- `SQUASH_STRETCH: Vector2 = Vector2(1.65, 0.6)`
- `SETTLE_DURATION: float = 0.32` (shared by squash and recoil elastic settle)
- `RECOIL_ANGLE: float = 0.4`
- `RECOIL_OFFSET: float = 5.0`

The flash constants (`FLASH_COLOR`, `FLASH_DECAY`, burn-flash) and knockback
constants are unchanged.

## New / Changed Members

- `_squash_tween: Tween` — existing, reused.
- `_recoil_tween: Tween` — new.
- `_last_hit_dir: Vector2` — new.
- `_sprite_base_position: Vector2` — new, captured in `_ready`.
- `_sprite_base_rotation: float` — new, captured in `_ready`.

## Files

**Edited**
- `src/enemies/enemy.gd`
  - `_ready`: capture sprite base position/rotation.
  - Constants: replace `SQUASH_SCALE`/`SQUASH_DURATION` with `SQUASH_STRETCH`,
    `SETTLE_DURATION`, `RECOIL_ANGLE`, `RECOIL_OFFSET`.
  - `_play_squash`: elastic-spring return to `ONE` from `SQUASH_STRETCH`.
  - `_play_recoil`: new — directional snap + elastic spring settle.
  - `_on_hit`: call `_play_recoil(_last_hit_dir)`; reset `_last_hit_dir`.
  - `on_hit_impact`: stash `_last_hit_dir` before `hit(damage)`.
  - `_change_state` `State.DEATH` arm: kill hurt tweens, reset sprite transform.
- `tests/unit/test_enemy_visual_identity.gd` — new tests (below).

## Order of Operations on Hit

In `Enemy._on_hit()`:
1. `_play_hit_flash()` (unchanged).
2. `_play_squash()` — snap to `SQUASH_STRETCH`, elastic-spring back.
3. `_play_recoil(_last_hit_dir)` — directional snap + elastic-spring back (or
   no-op if direction is zero).
4. `_hurt_vfx.burst()` (unchanged).
5. Reset `_last_hit_dir = Vector2.ZERO`.

Knockback, blood, and `HitReaction.play(spec)` still happen in `on_hit_impact`
around the `hit()` call, unchanged.

## Testing (gdUnit4, `tests/unit/test_enemy_visual_identity.gd`)

Follow the existing pattern in this file: build a `MockAnimatorEnemy`, add a
`Sprite2D` named `"Sprite2D"` as its child **before** `add_child(e)` (so `_ready`
captures the sprite base transform — same ordering as
`test_enemy_ticks_animator_when_present`), `await get_tree().process_frame`, set
`health = 100`, then drive the hit path directly. Set `e._last_hit_dir` and call
`e.hit(5)` (which calls `_on_hit()`) rather than `on_hit_impact`, avoiding the
`HitReaction`/`TerrainSurface` autoload and blood dependencies — matching
`test_on_hit_bursts_hurt_vfx`.

Tweens are time-based, so assert on the **instant snap state** (set synchronously
before the settle tween advances) and on death cleanup:

1. **Squash snaps on hit:** after `e.hit(5)`, `sprite.scale` equals
   `Enemy.SQUASH_STRETCH` (≠ `Vector2.ONE`).
2. **Recoil leans with hit direction:** set `e._last_hit_dir = Vector2.RIGHT`,
   `e.hit(5)` → `sign(sprite.rotation - e._sprite_base_rotation) > 0`; reset and
   repeat with `Vector2.LEFT` → `< 0`.
3. **Zero-direction hit does not lean:** with `e._last_hit_dir == Vector2.ZERO`,
   `e.hit(5)` leaves `sprite.rotation == e._sprite_base_rotation` and
   `sprite.position == e._sprite_base_position`, while `sprite.scale` still shows
   the squash snap.
4. **Death kills hurt tweens and resets transform:** after a hit, calling
   `e._change_state(Enemy.State.DEATH)` leaves `_squash_tween`/`_recoil_tween`
   invalid/killed and `sprite.scale == Vector2.ONE`,
   `sprite.rotation == e._sprite_base_rotation`,
   `sprite.position == e._sprite_base_position`.

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_enemy_visual_identity.gd`
(import first in a fresh worktree: `godot --headless --path . --import`).

## Invariants

- Only the `Sprite2D` transform is animated; the `CharacterBody2D` and its
  collision/movement are untouched.
- Base sprite scale is `Vector2.ONE`; base position/rotation captured in `_ready`.
- Latest-wins for both `_squash_tween` and `_recoil_tween` (re-hit re-snaps).
- Death owns the sprite transform exclusively (hurt tweens killed + reset on
  `DEATH` entry).
- Elastic ease-out settle is deterministic — no `randf` in the hurt animation.
