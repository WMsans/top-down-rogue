# Parry & Projectile Block — Design

**Date:** 2026-05-12
**Status:** Spec — awaiting plan

## Summary

Two related combat behaviors layered onto the existing `MeleeWeapon` swing:

1. **Projectile block (Soul Knight style)** — the player's melee swing destroys enemy projectiles inside its arc during the swing's active phase. Light feedback: sparks + small flash.
2. **Nail-clash parry (Hollow Knight style)** — the player's melee swing has a short "parry-active" window at its start. Enemy melee attacks that land on the player during that window are negated; both combatants are knocked back and the attacker is briefly stunned. Dramatic feedback: hitstop, radial sparks, white flash, expanding shockwave ring, screen shake.

The same swing performs both. They are differentiated by window (parry is the first ~0.1s; block runs the whole swing active phase) and by what they react to (parry → enemy melee; block → enemy projectiles).

## Goals

- Make melee combat feel reactive against ranged enemies (no longer forced to dodge every projectile).
- Reward well-timed melee swings against enemy melee attackers with a clearly readable, satisfying clash.
- Keep the implementation isolated: do not entangle parry/block logic with the existing swing animation, modifier system, or terrain code.
- Keep the feedback layer (FX) callable from one line at the call site.

## Non-goals

- Reflecting projectiles back at the attacker (decided: projectiles are destroyed, not reflected).
- Player-controlled parry button or stance — there is no separate parry input; the melee swing IS the parry.
- Enemies parrying the player (not implemented in this spec).
- Audio hooks (deferred — no sound wiring in this spec).

## Architecture

Three isolated pieces:

### 1. `MeleeWeapon` — swing-phase exposure

New exported fields on `MeleeWeapon`:

- `parry_window: float = 0.1` — seconds from swing start during which the swing can parry enemy melee.
- `parryable: bool = true` — when an enemy wields a `MeleeWeapon` resource with this false, its attacks cannot be parried.

New methods:

- `is_swing_active() -> bool` — true during PREP + ACTION + HOLD; false in NONE and RETURN. Used by projectile-block scan and as a precondition for swing-driven hitboxes.
- `is_parry_active() -> bool` — true for the first `parry_window` seconds after `_start_swing`. Used only by the player's parry path.

Internal: `_swing_elapsed: float` accumulates total elapsed time since swing start; reset in `_start_swing`, advanced in `_process_swing`.

### 2. Projectile destruction (Soul Knight)

In `MeleeWeapon._process_swing`, while `is_swing_active()`, call a new helper `_destroy_projectiles_in_arc(user, pos, dir)` once per frame:

- Iterate `user.get_tree().get_nodes_in_group("projectile")`.
- Filter: only nodes with `is_enemy_projectile == true`.
- Arc-distance/angle test using the same math as `_hit_attackables_in_arc` (`weapon_reach`, `arc_angle`).
- For each match: `ProjectileBlockFX.play(p.global_position, -p.direction)` then `p.queue_free()`.
- Cap at 8 destroyed projectiles per frame to bound FX spam.

`Projectile._ready` adds `self` to the `"projectile"` group. No other changes to `Projectile`.

### 3. Enemy-melee parry (HK nail clash)

`MeleeWeapon._hit_attackables_in_arc` is wielded by both player and enemies. When an enemy wields it and a target has a `try_parry` method, call it before dealing damage:

```
if node.has_method("try_parry"):
    if node.try_parry(user, node.global_position, hit_dir):
        continue  # parried — damage skipped for this target
node.on_hit_impact(node.global_position, hit_dir, dmg)
```

`PlayerController.try_parry(attacker, hit_pos, hit_dir) -> bool`:

- Returns false if the player has no melee weapon equipped.
- Returns false if `player_weapon.is_parry_active() == false`.
- Returns false if `attacker`'s active weapon is a `MeleeWeapon` with `parryable == false`.
- Otherwise: returns true, and as a side effect:
  - Applies knockback to the player (~40px impulse along `-hit_dir`).
  - Applies knockback to the attacker (~40px impulse along `hit_dir`).
  - Sets `attacker._parry_stun_remaining = 0.25` (no-op if the attacker doesn't have the field — guard with `"_parry_stun_remaining" in attacker`).
  - Calls `NailClashFX.play(midpoint(player, attacker), hit_dir.orthogonal())`.

`Enemy` base gets a `_parry_stun_remaining: float = 0.0` field. The AI tick / `_physics_process` early-returns while it's > 0 and decrements by `delta` each frame. The attack cooldown timer is extended to at least the stun remaining so a stunned enemy can't immediately re-attack on stun end.

## Feedback

### `NailClashFX` — dramatic parry

Located at `src/player/feedback/nail_clash_fx.gd`. Single static method:

```
static func play(pos: Vector2, normal: Vector2) -> void
```

It instantiates `scenes/fx/nail_clash.tscn` at `pos` and triggers:

- **Hitstop:** `Engine.time_scale = 0.0` for `120ms` real time. Restore via `SceneTree.create_timer(0.12, true, false, true)` (process_always = true, ignore_time_scale = true) `timeout` callback.
- **Radial spark burst:** GPUParticles2D one-shot, 16–24 particles, 360° emission fan, lifetime ~0.25s, fast outward velocity, white→cyan color ramp.
- **White flash sprite:** additive star/cross sprite. Tween scale 0.0 → 1.6 over 60ms (ease-out), then alpha 1 → 0 over 180ms.
- **Shockwave ring:** quad with `shaders/fx/shockwave_ring.gdshader`. Tween radius 0 → 48px over 200ms; alpha 1 → 0 over same.
- **Screen shake:** sharp impulse — amplitude 6px, duration 180ms, decay-out. Hooked into the existing camera (find current camera shake utility; if none, add a minimal `CameraShake` helper).
- **Knockback:** handled by the caller (player + attacker), NOT by the FX scene.
- **No SFX in this spec.**

### `ProjectileBlockFX` — block tier

Located at `src/player/feedback/projectile_block_fx.gd`. Single static method:

```
static func play(pos: Vector2, dir: Vector2) -> void
```

Instantiates `scenes/fx/projectile_block.tscn` at `pos`:

- **Sparks:** GPUParticles2D one-shot, 6–10 particles, lifetime ~0.12s, emission along `dir` ±30°.
- **Small flash:** additive white sprite. Tween scale 0 → 1 over 30ms; alpha 1 → 0 over 80ms.
- No hitstop, no shake, no SFX.

## Data flow

### Player swings → projectile destroyed

1. Player presses attack. `MeleeWeapon._use_impl` runs once at swing start (existing path).
2. Each frame during `is_swing_active()`, `_process_swing` calls `_destroy_projectiles_in_arc(user, pos, dir)`.
3. Helper iterates `"projectile"` group, filters by `is_enemy_projectile`, runs arc test, calls `ProjectileBlockFX.play` and `queue_free` on matches (capped at 8/frame).
4. `Projectile._ready` registers itself in the `"projectile"` group.

### Enemy swings → parry attempt

1. Enemy's `MeleeWeapon._hit_attackables_in_arc` iterates candidates.
2. For each target with `try_parry`, call it. If true → skip damage on that target; continue.
3. `PlayerController.try_parry` checks parry window + attacker `parryable`; on success applies knockback to both, sets attacker stun, plays `NailClashFX`.
4. Enemy's `_parry_stun_remaining` gates AI tick and extends cooldown.

## Edge cases & decisions

- **Multiple projectiles same frame:** all destroyed; FX caps at 8/frame.
- **Mid-flight enemy swing meeting player parry:** damage call is the relevant moment; if it lands while player's parry window is active, it parries.
- **No weapon equipped:** `try_parry` returns false; no crash.
- **Friendly fire:** only `is_enemy_projectile == true` projectiles destroyed; the player's own projectiles pass through.
- **Unparryable enemies:** `MeleeWeapon.parryable = false` on the enemy's weapon resource skips parry path; damage applies normally.
- **Stun extends cooldown:** prevents stun-end → immediate-attack exploit.
- **Enemies parrying player:** not implemented — `try_parry` lives only on the player.

## File layout

**New:**

- `src/player/feedback/nail_clash_fx.gd`
- `src/player/feedback/projectile_block_fx.gd`
- `scenes/fx/nail_clash.tscn`
- `scenes/fx/projectile_block.tscn`
- `shaders/fx/shockwave_ring.gdshader`
- `tests/test_parry_window.gd`
- `tests/test_projectile_block.gd`
- `tests/test_parry_intercept.gd`
- `tests/test_unparryable.gd`

**Modified:**

- `src/weapons/melee_weapon.gd` — phase getters (`is_swing_active`, `is_parry_active`), `parry_window` + `parryable` exports, `_swing_elapsed` tracking, per-frame projectile scan, `try_parry` call in `_hit_attackables_in_arc`.
- `src/weapons/projectile.gd` — one-line group add in `_ready`.
- `src/player/player_controller.gd` — `try_parry` method, knockback application.
- `src/enemies/enemy.gd` — `_parry_stun_remaining` field, AI gate, cooldown extension.

## Tests

- `test_parry_window.gd` — start a swing; assert `is_parry_active()` true for the first 0.1s and false after; assert `is_swing_active()` true through HOLD and false in RETURN.
- `test_projectile_block.gd` — place an enemy projectile inside the player's arc, start a swing, tick one frame; assert projectile is freed and `ProjectileBlockFX` was invoked.
- `test_parry_intercept.gd` — simulate an enemy `MeleeWeapon` calling `try_parry` on a player whose weapon is in its parry window with `parryable = true`; assert player health unchanged and `attacker._parry_stun_remaining > 0`.
- `test_unparryable.gd` — same setup with `parryable = false`; assert player took damage and no stun on attacker.
