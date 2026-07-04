# Lunge Enemy: Weaponless, Larger, Fire Dash VFX — Design

Follow-up to `2026-06-14-melee-lunge-variant-design.md`, which shipped `LungeEnemy` as a
`MeleeEnemy` subclass carrying a normal melee weapon purely for `weapon.damage`, the
held-weapon visual, and the weapon drop on death. This sub-project removes that weapon
entirely, makes the lunge visually bigger, and adds a fire VFX during the dash.

## Problem

The lunge enemy currently looks and behaves like a melee grunt that happens to dash: it
holds a visible weapon sprite, drops a weapon on death like any other melee enemy, and is
the same size as a normal melee enemy. This undersells it as a distinct threat — a
charging brute shouldn't be equipped like the enemies it dashes past, and its size should
telegraph "this one hits harder" before the windup even starts. The dash itself is also
visually flat: a fast repositioning with no feedback beyond the existing windup flash.

## Goals

- `LungeEnemy` never holds or drops a weapon.
- `LungeEnemy` is visually larger than a standard melee enemy (1.6x scale).
- The dash gets a fire-like VFX ahead of the enemy, in its dash direction, for the
  duration of the dash.
- The "no weapon" mechanism is reusable by future weaponless enemy types (more dash
  variants are planned), not a one-off hack buried in `LungeEnemy`.
- The sprite swap for a future dedicated dash-enemy asset stays a one-line texture change
  (already true today — no regression here).

## Non-goals

- No new dedicated sprite/art asset — reuses the current placeholder texture. Swapping in
  real art later is out of scope for this change.
- No changes to dash movement, damage timing, telegraph, or state flow — those are
  unchanged from the original lunge design.
- No changes to `MeleeEnemy`/`Enemy` behavior for any enemy that still carries a weapon —
  `carries_weapon` must default to `true` and be a no-op for every existing enemy type.
- No AnimatedSprite2D / animation system work — still a single `Sprite2D`.

## Architecture

```
Enemy (CharacterBody2D)
 ├─ carries_weapon: bool = true   [NEW export, default true]
 └─ MeleeEnemy
      ├─ _ready(): only builds/assigns `weapon` if carries_weapon
      └─ LungeEnemy
           - carries_weapon = false
           - dash_damage: float  [NEW export, replaces weapon.damage read]
           - scale = Vector2(1.6, 1.6)
           - DashFireVFX child node, started/stopped around the dash window
```

`carries_weapon` lives on `Enemy` (not `MeleeEnemy`) so any future enemy subclass —
ranged or melee — can opt out the same way. Existing weapon-visual setup
(`if weapon and weapon.has_visual(): ...`) and drop logic
(`if weapon and DropTable.roll_should_drop_weapon(...): ...`) already gate on `weapon`
being non-null — leaving `weapon` as `null` when `carries_weapon` is `false` is
sufficient for "never shows, never drops a weapon." No changes needed to the drop table
or weapon-visual code paths themselves.

Because `LungeEnemy` no longer has a `weapon` object, `weapon.damage` (currently read at
dash-contact time) is replaced with a plain `dash_damage` export local to `LungeEnemy`.

### Fire VFX

New self-contained scene + script pair, following the existing `scenes/fx/*.tscn` +
`*_fx.gd` convention (e.g. `nail_clash_fx.gd`), but built to persist and travel with the
enemy rather than fire-and-forget in world space:

- `scenes/fx/dash_fire_vfx.tscn`: a `Node2D` root containing a `GPUParticles2D`
  configured for a forward-facing cone, additive blend, orange/red gradient (reusing the
  `on_fire` status color palette from `status_visuals.gd` for visual consistency across
  the game's fire-themed effects).
- `src/enemies/feedback/dash_fire_vfx.gd`: exposes `start(direction: Vector2)` and
  `stop()`. `start()` rotates the node to face `direction`, sets `emitting = true`.
  `stop()` sets `emitting = false` — already-emitted particles finish their lifetime
  naturally instead of vanishing abruptly.

`LungeEnemy` instances `DashFireVFX` once as a child in `_ready()` (so it moves with the
enemy automatically via normal parenting) and offsets it a fixed distance ahead of the
enemy's origin along `_lock_dir` each dash. `_begin_dash()` calls
`_fire_vfx.start(_lock_dir)`; when `_dash_timer` expires (dash end), it calls
`_fire_vfx.stop()`.

## Components

### 1. `src/enemies/enemy.gd`

- Add `@export var carries_weapon: bool = true`.

### 2. `src/enemies/melee_enemy.gd`

- Guard the existing weapon construction/duplication in `_ready()` behind
  `if carries_weapon`; otherwise leave `weapon` as `null` (its declared default).

### 3. `src/enemies/lunge_enemy.gd`

- Set `carries_weapon = false` (either in the exported scene default or in `_ready()`
  before `super._ready()` runs, whichever the base `_ready()` ordering requires).
- Add `@export var dash_damage: float` and use it in place of `weapon.damage` at the
  existing dash-contact damage call.
- Set `scale = Vector2(1.6, 1.6)` in `_ready()`.
- Add `_fire_vfx: DashFireVfx` — instanced in `_ready()`, parented under the enemy.
- In `_begin_dash()`: position `_fire_vfx` ahead of the enemy along `_lock_dir` and call
  `_fire_vfx.start(_lock_dir)`.
- Where the dash currently ends (timer expiry / `_dash_done = true`): call
  `_fire_vfx.stop()`.

### 4. `scenes/enemies/lunge_enemy.tscn`

- Remove/leave-null `weapon_resource` (already null today).
- Set `dash_damage` to whatever value preserves current damage output (i.e. whatever the
  previous bare `MeleeWeapon.new()` was giving it — a tuning pass confirms parity, not a
  design decision).
- Add the `DashFireVfx` child instance if not created purely in code.

### 5. New files

- `scenes/fx/dash_fire_vfx.tscn`
- `src/enemies/feedback/dash_fire_vfx.gd`

## Edge cases & handling

- **Dash interrupted by HURT mid-flight**: the fire VFX should stop when the dash stops.
  Since `_dash_done`/state transition already handles the HURT-interrupt case for
  movement, the same transition point calling `_fire_vfx.stop()` covers this — no separate
  HURT-specific handling needed.
- **Enemy dies mid-dash**: `_state == DEATH` short-circuits before `_process_attack`, same
  as today; the VFX node is freed along with the enemy (child node), so no leaked
  particles.
- **`carries_weapon = false` but `_roll_weapon_modifier()` still runs**: that path is
  already implicitly guarded — modifier rolling attaches to `weapon`, and calling into a
  null `weapon` would error. Confirm at implementation time that modifier-rolling is
  skipped when `weapon` is null (either already guarded, or add a guard) — this is a
  correctness check, not a new mechanism.
- **Existing enemies unaffected**: `carries_weapon` defaults to `true`, so every other
  `MeleeEnemy`/subclass keeps building its weapon exactly as before.

## Testing

Extend `tests/unit/test_lunge_enemy.gd` (GdUnit4 headless):

- `LungeEnemy.weapon` is `null` after `_ready()`.
- `LungeEnemy` never spawns a weapon drop on death (mock/stub `_spawn_weapon_drop` or
  assert it's never called since `weapon` is null).
- Dash-contact damage uses `dash_damage`, not a weapon's damage value.
- A plain `MeleeEnemy`/other subclass still builds a non-null `weapon` (regression check
  that `carries_weapon` defaulting to `true` doesn't break anything).
- `LungeEnemy.scale == Vector2(1.6, 1.6)` after `_ready()`.
- `DashFireVfx.start()`/`stop()` toggle `emitting` correctly (unit-testable without
  rendering).

Manual playtest checklist: enemy reads as visually distinct (size) before it attacks; no
weapon sprite visible at any point; no weapon drop on death across several kills; the fire
VFX is clearly visible ahead of the dash direction and reads as "charging," not
distracting from the telegraph.

## Risks

- **Tuning `dash_damage`**: must be set to match the effective damage the old bare
  `MeleeWeapon.new()` was dealing, or the enemy's threat level silently changes. Flagged
  for a tuning pass during manual playtest.
- **VFX offset tuning**: how far ahead of the enemy the fire cone sits needs a playtest
  pass — too close reads as attached to the body, too far disconnects it from the enemy.
- **Particle cost**: one more `GPUParticles2D` per lunge enemy; not expected to be an
  issue at current enemy-count scales, but worth a quick perf sanity check if many lunge
  enemies can be on screen at once.
