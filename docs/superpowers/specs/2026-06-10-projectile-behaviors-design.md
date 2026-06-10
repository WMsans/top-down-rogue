# Projectile Behaviors — Design

**Sub-project 3 of Phase 7 (Weapon & Modifier Content Expansion).**

Builds four reusable, composable **projectile behaviors** — bounce, split, penetrate, and
bullet-clear — as the foundation that Sub-project 4's projectile modifiers (`bouncing_bullets`,
`splitting_rounds`, `penetrating_shockwave`, `gleaming_projectile`, etc.) will consume.

No weapon in `weapons.csv` uses these behaviors directly; they exist only to be attached by
modifiers. To keep this cycle independently playable, a console command fires each behavior live.

Builds on the existing `Projectile` (`src/weapons/projectile.gd`) and the console command system.

---

## Goals

- A **behavior-component** system on `Projectile`: a projectile carries an array of
  `ProjectileBehavior` objects, each hooking the projectile's lifecycle through semantic,
  no-op-by-default callbacks.
- Four behaviors, each in its own focused, unit-testable file: **bounce**, **split**,
  **penetrate**, **clear-bullets**.
- Behaviors **compose**: `penetrating_shockwave` = penetrate + clear-bullets.
- A plain projectile with no behaviors behaves **identically to today**.
- A console command to fire each behavior in-game for verification.

## Non-goals

- Wiring real modifiers onto weapons — that is Sub-project 4.
- Changing `RangedWeapon` or any of the ten stat-only weapons.
- Reflecting enemy projectiles back at attackers (clear destroys them, matching the existing
  parry/block decision).
- Mouse aiming — direction stays the player's facing direction.
- True physics collision normals for bounce — terrain is pixel/Area2D-based, so bounce uses
  axis-aligned solidity probing instead.

---

## Architecture overview

```
Projectile (Area2D)  — existing damage / crit / carve logic UNCHANGED
   │  holds: behaviors: Array[ProjectileBehavior]
   │  _ready  -> behavior.on_spawn
   │  _process-> behavior.on_process
   │  _handle_hit (restructured): classify target, dispatch semantic hook,
   │              free only if no behavior voted keep-alive
   ▼
ProjectileBehavior (RefCounted base, no-op hooks)
   ▲
BounceBehavior   SplitBehavior   PenetrateBehavior   ClearBulletsBehavior
```

New folder: `src/weapons/projectile_behaviors/`.

Chosen approach: **behavior components**, not config flags or projectile subclasses. The four
behaviors are genuinely independent and one modifier (`penetrating_shockwave`) needs two of them
at once, so composition via an array beats both a single growing `if/else` (flags) and an
awkward multiple-inheritance subclass.

---

## Section 1 — Behavior contract

`src/weapons/projectile_behaviors/projectile_behavior.gd`:

```gdscript
class_name ProjectileBehavior
extends RefCounted

# Called once when the projectile enters the tree.
func on_spawn(_proj) -> void:
    pass

# Called every frame, after the projectile has moved.
func on_process(_proj, _delta: float) -> void:
    pass

# Called when the projectile's damage has been applied to an attackable enemy.
# Return true to keep the projectile alive (suppress the default destroy).
func on_enemy_hit(_proj, _target) -> bool:
    return false

# Called when the projectile overlaps a solid wall (StaticBody2D), BEFORE carving.
# Return true to keep the projectile alive (suppress carve + destroy).
func on_terrain_hit(_proj) -> bool:
    return false

# Called when a PLAYER projectile overlaps an ENEMY projectile. Informational —
# does not affect this projectile's own death policy.
func on_enemy_projectile_overlap(_proj, _enemy_proj) -> void:
    pass
```

**Keep-alive contract:** after the projectile runs its existing per-hit logic (damage + crit
for enemy hits, carve for terrain), it polls every behavior's matching hook and frees itself
only if **no** behavior returned `true`. Votes are OR-ed: any single `true` keeps it alive. A
projectile with an empty `behaviors` array therefore destroys on every hit exactly as today.

---

## Section 2 — `Projectile` changes

`src/weapons/projectile.gd`. The damage, crit, status, and carve code is preserved; only
lifecycle dispatch is added.

- **New field:** `var behaviors: Array = []` (elements are `ProjectileBehavior`).
- **`_ready`:** after existing setup, `for b in behaviors: b.on_spawn(self)`.
- **`_process`:** after the existing move + sprite-rotation block, `for b in behaviors:
  b.on_process(self, delta)`. (Lifetime/age check stays first.)
- **`_handle_hit` restructure** — classify the target and dispatch, honoring keep-alive:

  ```
  player projectile path:
    target is attackable enemy (not source):
        apply damage + crit + crit-status   (existing code, unchanged)
        keep = false
        for b in behaviors: keep = b.on_enemy_hit(self, target) or keep
        if not keep: queue_free()
    target is StaticBody2D (wall):
        keep = false
        for b in behaviors: keep = b.on_terrain_hit(self) or keep
        if keep: return
        _carve_terrain(); queue_free()        (existing code)
    target is enemy projectile (group "projectile", is_enemy_projectile, not self):
        for b in behaviors: b.on_enemy_projectile_overlap(self, target)
        (no self death from this)
  ```

  The enemy-projectile branch is new: today a player projectile passing an enemy bullet does
  nothing (bullets are neither `attackable` nor `StaticBody2D`), so this only adds an opt-in
  hook and changes nothing for plain projectiles.

- **New solidity probe** (for bounce + tests):

  ```gdscript
  var solidity_oracle: Callable = Callable()   # injectable; tests supply a stub

  func is_solid_at(pos: Vector2) -> bool:
      if solidity_oracle.is_valid():
          return solidity_oracle.call(pos)
      var wm := get_tree().get_first_node_in_group("world_manager")
      if wm != null and wm.nav_field != null:
          return wm.nav_field.is_solid_world(pos)
      return false
  ```

  `NavField.is_solid_world(pos)` already exists and reads an 8px-cell `PassabilityGrid` — fine
  granularity for bounce reflection.

---

## Section 3 — The four behaviors

All live in `src/weapons/projectile_behaviors/`.

### `bounce_behavior.gd` — `BounceBehavior`
- Fields: `max_bounces: int = 3`, `probe_step: float = 6.0`.
- `on_terrain_hit(proj)`: if no bounces left, return `false` (default carve + die). Otherwise:
  - **Axis-aligned reflection** via solidity probe. Let `d = proj.direction`, `p =
    proj.global_position`.
    - `hit_x = proj.is_solid_at(p + Vector2(sign(d.x) * probe_step, 0))`
    - `hit_y = proj.is_solid_at(p + Vector2(0, sign(d.y) * probe_step))`
    - Flip `d.x` if `hit_x`; flip `d.y` if `hit_y`; if neither (corner/ambiguous), flip both.
  - Set `proj.direction = d.normalized()`, nudge `proj.global_position += d * probe_step` to
    clear the wall, decrement `max_bounces`, return `true` (keep alive). No carving.
- Dies on enemy hit (does not override `on_enemy_hit`).

### `split_behavior.gd` — `SplitBehavior`
- Fields: `shard_count: int = 4`, `damage_factor: float = 0.5`, `spread_deg: float = 60.0`,
  `shard_speed: float = 140.0`, `shard_lifetime: float = 0.6`.
- Shared `_split(proj)` helper spawns `shard_count` **plain** `Projectile`s (empty `behaviors`
  — no recursion) fanned evenly across `spread_deg` around `proj.direction`, inheriting
  `is_enemy_projectile`, `source_node`, sprite texture, and `damage * damage_factor`. Added to
  the same parent as `proj`.
- `on_enemy_hit(proj, _t)` and `on_terrain_hit(proj)` both call `_split(proj)` then return
  `false` (let the projectile die normally — terrain branch still carves). Splits on **either**
  impact type.

### `penetrate_behavior.gd` — `PenetrateBehavior`
- `on_enemy_hit(_proj, _target)`: return `true` (pass through; damage already applied once on
  Area2D enter, so each enemy is hit once as the projectile sweeps through).
- `on_terrain_hit(_proj)`: return `false` (stopped by a solid wall — default carve + die).

### `clear_bullets_behavior.gd` — `ClearBulletsBehavior`
- `on_enemy_projectile_overlap(_proj, enemy_proj)`: `ProjectileBlockFX.play(enemy_proj.global_position,
  -enemy_proj.direction)` then `enemy_proj.queue_free()`. Does not change own death policy.

**Composition:** `penetrating_shockwave` → `[PenetrateBehavior.new(), ClearBulletsBehavior.new()]`;
`gleaming_projectile` → `[ClearBulletsBehavior.new()]`; `bouncing_bullets` →
`[BounceBehavior.new()]`; `splitting_rounds` → `[SplitBehavior.new()]`. (Wiring is Sub-project 4;
listed here only to validate the contract covers every modifier.)

---

## Section 4 — Console command (demoability)

Extend `src/console/commands/spawn_command.gd` with:

```
spawn projectile bounce
spawn projectile split
spawn projectile penetrate
spawn projectile clear
spawn projectile shockwave      # penetrate + clear
```

Each instantiates `PROJECTILE_SCENE`, sets `is_enemy_projectile = false`, points `direction`
at the player's facing direction (fall back to `Vector2.RIGHT`), attaches the matching
behavior(s), and adds it to the chunk container (reusing `_get_spawn_parent`). Mirrors the
existing `spawn static_projectile` registration.

---

## Section 5 — Testing

New `tests/unit/test_projectile_behaviors.gd`, using the existing pattern (instantiate
`Projectile`, set `behaviors`, drive `_handle_hit` / `_process` directly). A stubbed
`solidity_oracle` removes any dependency on a real terrain grid.

- **Bounce:** projectile heading +X with `solidity_oracle` returning true only ahead-X →
  after `on_terrain_hit`, `direction.x` flips sign, projectile stays alive, `max_bounces`
  decrements. With `max_bounces = 0`, `on_terrain_hit` returns false.
- **Split:** with a `SplitBehavior`, calling `_handle_hit` on an attackable spawns
  `shard_count` projectiles under the parent and the original frees.
- **Penetrate:** `on_enemy_hit` keeps the projectile alive across two enemy hits; `on_terrain_hit`
  lets it die.
- **Clear:** a player projectile overlapping an enemy projectile frees the enemy projectile and
  not itself.
- **Regression:** a behavior-less projectile still dies on enemy hit and on terrain hit (existing
  `test_projectile.gd` continues to pass).

Bounce reflection *feel* is tuned manually, not unit-tested beyond the axis-flip assertion.

---

## File summary

**New**
- `src/weapons/projectile_behaviors/projectile_behavior.gd`
- `src/weapons/projectile_behaviors/bounce_behavior.gd`
- `src/weapons/projectile_behaviors/split_behavior.gd`
- `src/weapons/projectile_behaviors/penetrate_behavior.gd`
- `src/weapons/projectile_behaviors/clear_bullets_behavior.gd`
- `tests/unit/test_projectile_behaviors.gd`

**Modified**
- `src/weapons/projectile.gd` — behaviors array, lifecycle dispatch, `is_solid_at`/`solidity_oracle`
- `src/console/commands/spawn_command.gd` — `spawn projectile <behavior>` commands
- `docs/design_docs/implementation_todo.md` — mark Sub-project 3 rows done (on completion)
