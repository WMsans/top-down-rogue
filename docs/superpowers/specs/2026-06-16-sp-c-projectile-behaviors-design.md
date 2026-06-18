# SP-C: New Projectile Behaviors + Projectile Modifiers

**Date:** 2026-06-16
**Phase:** 7, Sub-project C (7)
**Status:** Approved, ready for planning

## Goal

Ship the six remaining `projectile`-category modifiers from `modifiers.csv`
(`homing_hex`, `boomerang_arc`, `ricochet_shard`, `piercing_lance`, `cluster_bomb`,
`spectral_echo`) by adding two new steering behaviors (`homing`, `return`) and reusing the
existing SP-3 projectile-behavior foundations for the rest.

## Existing foundations (SP-3, already built)

- `ProjectileBehavior` (`src/weapons/projectile_behaviors/projectile_behavior.gd`) base with
  hooks: `on_spawn`, `on_process`, `on_enemy_hit`, `on_terrain_hit`,
  `on_enemy_projectile_overlap`. Concrete: `BounceBehavior`, `SplitBehavior`,
  `PenetrateBehavior`, `ClearBulletsBehavior`.
- `Projectile` (`src/weapons/projectile.gd`) runs behaviors each frame and at each hit; exposes
  `direction`, `speed`, `damage`, `hit_status`, `source_node`, `is_solid_at(pos)`.
- `ModifierProjectile.spawn_one` / `spawn_fan` (`src/weapons/modifiers/modifier_projectile.gd`)
  accept `behaviors` / `make_behaviors`, `tint`, `speed`, `lifetime`, `hit_status` opts.
- `ProjectileModifier` (`src/weapons/modifiers/projectile_modifier.gd`) base fires `_fire()`
  on swing per `period` / `fire_on`.
- `weapon_registry.gd` maps modifier id → bespoke script in `modifier_scripts[...]`;
  unmapped ids fall back to `DataModifier`. SP-3/SP-4 projectile modifiers are all bespoke
  scripts. SP-A's generic `spawn_projectile` dispatch is **not** built, so bespoke is the
  only working path today.

## Architecture

### New behavior: `HomingBehavior`

File: `src/weapons/projectile_behaviors/homing_behavior.gd`, extends `ProjectileBehavior`.

- `var turn_rate_rad: float = PI * 2.0` — max steering rate (rad/s).
- `on_process(proj, delta)`: find nearest valid enemy, compute desired heading, rotate
  `proj.direction` toward it clamped to `turn_rate_rad * delta`. If no target, fly straight.
- Target selection: continuous (re-evaluated each tick — no stale-target state). For player
  projectiles, scan the `attackable` group (mirrors `DataModifier._radial_targets`), skip
  `proj.source_node` and invalid nodes, pick nearest by squared distance.

### New behavior: `ReturnBehavior`

File: `src/weapons/projectile_behaviors/return_behavior.gd`, extends `ProjectileBehavior`.

- `var out_time: float = 0.5` — outbound duration before reversing.
- `var return_catch_radius: float = 14.0` — frees on return when within this of source.
- `on_spawn(proj)`: cache `source_node`, reset elapsed.
- `on_process(proj, delta)`: accumulate elapsed. Phase 1 (`elapsed < out_time`): unchanged
  outbound flight. Phase 2: steer `proj.direction` toward `source_node.global_position`
  (recomputed each tick so it tracks a moving player); when within `return_catch_radius` on
  the return leg, `proj.queue_free()`. Lifetime still bounds it as a fallback.
- `on_enemy_hit(proj, target)` returns `true` (pass-through) so foes are hit on both legs.
  A foe straddling the turnaround may be hit twice; accepted as thematic.

### Six bespoke `ProjectileModifier` scripts

All in `src/weapons/modifiers/`, all `on_swing` (`period=1, fire_on=[0]`), all registered in
`weapon_registry.gd` `_ready()` via `modifier_scripts[id] = preload(...)`. Each follows the
`gleaming_projectile_modifier.gd` / `bouncing_bullets_modifier.gd` pattern: set
`name`/`description`/`icon_texture` in `_init()`, spawn in `_fire(weapon, user, ctx)` using
`ModifierProjectile`. Damage uses small per-modifier constants (these fire free on every
swing, consistent with existing 3.0 / 8.0 values).

| id | file | behavior | key params |
|---|---|---|---|
| `homing_hex` | `homing_hex_modifier.gd` | `HomingBehavior` (new) | 1 projectile, purple tint |
| `boomerang_arc` | `boomerang_arc_modifier.gd` | `ReturnBehavior` (new) | 1 projectile, blade tint |
| `ricochet_shard` | `ricochet_shard_modifier.gd` | `BounceBehavior` (reuse) | 1 shard, `max_bounces = 3` (mag2) |
| `piercing_lance` | `piercing_lance_modifier.gd` | `PenetrateBehavior` (reuse) | 1 lance, longer lifetime for line travel |
| `cluster_bomb` | `cluster_bomb_modifier.gd` | `SplitBehavior` (reuse) | 1 bomb; on impact `shard_count = 8`, `spread_deg = 360`, shards carry `hit_status = "burn"` |
| `spectral_echo` | `spectral_echo_modifier.gd` | none | delayed ghost projectile (see below) |

### `spectral_echo` delayed spawn

Modifiers are `RefCounted`, so the delay is scheduled via
`user.get_tree().create_timer(ECHO_DELAY).timeout` (≈0.3s), connected to a callable that
captures `user`, a snapshot of `ctx["origin"]` / `ctx["direction"]`, and the echo damage,
then calls `ModifierProjectile.spawn_one`. The echo deals ½ the base damage, uses a
translucent tint, and travels in the snapshotted swing direction (so it fires from where the
swing happened even if the player has moved). No new behavior class required.

### `SplitBehavior` change for `cluster_bomb`

Add an optional `var shard_hit_status: String = ""` field to `SplitBehavior`. When non-empty,
set `shard.hit_status = shard_hit_status` on each spawned shard. Default `""` leaves the
existing `splitting_rounds` behavior unchanged.

## Testing

Extend `tests/unit/test_projectile_behaviors.gd`:

- **Homing:** with a stubbed target node, one `on_process` step rotates `proj.direction`
  toward the target, bounded by `turn_rate_rad * delta`; with no target, `direction` is
  unchanged.
- **Return:** before `out_time` direction is unchanged; after `out_time` it steers toward the
  source position; `on_enemy_hit` returns `true`.
- **SplitBehavior:** `shard_hit_status` propagates to spawned shards; empty default leaves
  shards with no status.
- **Registry:** all six ids (`homing_hex`, `boomerang_arc`, `ricochet_shard`,
  `piercing_lance`, `cluster_bomb`, `spectral_echo`) resolve to non-null modifiers via
  `WeaponRegistry._make_modifier`.

## Out of scope

- SP-A generic data-driven `spawn_projectile` dispatch (these stay bespoke).
- Native ranged/melee mechanics (SP-D, SP-E).
- New VFX beyond tint/translucency.

## Files

New:
- `src/weapons/projectile_behaviors/homing_behavior.gd`
- `src/weapons/projectile_behaviors/return_behavior.gd`
- `src/weapons/modifiers/homing_hex_modifier.gd`
- `src/weapons/modifiers/boomerang_arc_modifier.gd`
- `src/weapons/modifiers/ricochet_shard_modifier.gd`
- `src/weapons/modifiers/piercing_lance_modifier.gd`
- `src/weapons/modifiers/cluster_bomb_modifier.gd`
- `src/weapons/modifiers/spectral_echo_modifier.gd`

Modified:
- `src/weapons/projectile_behaviors/split_behavior.gd` (add `shard_hit_status`)
- `src/autoload/weapon_registry.gd` (register six ids)
- `tests/unit/test_projectile_behaviors.gd`
- `docs/design_docs/implementation_todo.md` (mark SP-C done)
