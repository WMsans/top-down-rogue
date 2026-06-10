# Modifiers — Design

**Sub-project 4 of Phase 7 (Weapon & Modifier Content Expansion).**

Implements the ten modifiers in `docs/design_docs/modifiers.csv`. The CSV data and `.tres`
plumbing already exist; only `lava_emitter` has a behavior script today. This cycle builds the
behavior the other nine descriptions promise, reusing the projectile behaviors from Sub-project 3
(`BounceBehavior`, `SplitBehavior`, `PenetrateBehavior`, `ClearBulletsBehavior`).

The ten modifiers collapse onto **one new modifier hook** (`on_attack`), a **cadence-counting
base class** (`ProjectileModifier`), and a **shared projectile-spawn helper** — no combo/weapon
state is queried, so every modifier works on every weapon, combo or not.

---

## Goals

- A per-attack modifier hook, `on_attack`, that fires once per swing / shot / combo step.
- A `ProjectileModifier` base that fires on a self-counted **"every N hits"** cadence — no
  dependency on the weapon exposing combo structure.
- The ten CSV modifiers, each a small focused file, spawning the projectiles / behaviors / status
  effects their descriptions promise.
- Modifiers spawnable in-game for verification via the existing `spawn mod <id>` console path.

## Non-goals

- Changing weapon stats, combo definitions, or the ten pure-stat weapons.
- New projectile behaviors (Sub-project 3 already built the four needed).
- New art — projectile theming is done with sprite `modulate` tinting, not new textures.
- A new "stun" status — `lightning_bolt` reuses `frozen` (already immobilizes) as its stun.

---

## Architecture overview

```
Weapon.notify_attack(user, ctx)  ──loops──>  Modifier.on_attack(weapon, user, ctx)
   ▲ called from:                                   ▲ overridden by:
   ├ MeleeWeapon._use_impl          (plain swing)   ProjectileModifier (base, cadence) ── 8 modifiers
   ├ AdvancedMeleeWeapon._play_move (each move)     LightningBoltModifier  (chance roll)
   └ RangedWeapon._use_impl         (each shot)     PenetratingShockwaveModifier (charge)
                                                    LavaEmitterModifier (unchanged, uses on_use)
```

`ctx` is a Dictionary: `{ direction: Vector2, origin: Vector2, charged: bool, charge_ratio: float }`.
Firing decisions never read combo index, combo length, or move shape, so the weapon never has to
expose that state.

Chosen approach: **per-modifier cadence counter** over **weapon-queried combo position**. The CSV
descriptions phrase the combo modifiers in terms of a weapon's combo ("first two hits of a
three-hit combo"), but tying firing to weapon combo structure would (a) break when a modifier is
transferred to a combo-less weapon, and (b) require the weapon to publish combo internals. A
self-counted cadence reproduces the same rhythm on any weapon and keeps each modifier
self-contained.

---

## Section 1 — Hook API

`src/weapons/modifier.gd` gains one no-op hook alongside the existing `on_equip` / `on_use` /
`on_tick` / `modify_crit_chance`:

```gdscript
func on_attack(_weapon: Weapon, _user: Node, _ctx: Dictionary) -> void:
    pass
```

`on_use` and `suppresses_base_use` are untouched; `lava_emitter` keeps firing from `on_use`.

`src/weapons/weapon.gd` gains the dispatcher:

```gdscript
func notify_attack(user: Node, ctx: Dictionary) -> void:
    for modifier in modifiers:
        if modifier != null:
            modifier.on_attack(self, user, ctx)
```

**Call sites** (each builds `ctx` and calls `notify_attack` once per discrete attack action):

- `MeleeWeapon._use_impl` — plain single swing. `ctx = { direction, origin = user.global_position,
  charged = false, charge_ratio = 0.0 }`.
- `RangedWeapon._use_impl` — one notification per use (a spread shot of 3 projectiles is one
  attack). Same `ctx` shape, `direction` = facing.
- `AdvancedMeleeWeapon._play_move(move, user, ctx)` — gains a `ctx` parameter supplied by its three
  dispatch callers:
  - `_do_light_attack` (tap combo step) and `_advance_flurry` (auto/charged flurry step): `charged
    = false`.
  - `_do_charged_attack`: `charged = true`, `charge_ratio` = the release ratio passed into
    `_fire_charged` / `_do_charged_attack`.
  - `direction = _get_facing_direction(user)`, `origin = user.global_position` (the same values
    `_play_move` already computes).

`on_attack` fires **once per move** — a three-hit combo produces three notifications, so the
cadence counter advances one step per swing.

---

## Section 2 — `ProjectileModifier` base + spawn helper

### `src/weapons/modifiers/projectile_modifier.gd`

```gdscript
class_name ProjectileModifier
extends Modifier

var period: int = 1          # cadence cycle length N
var fire_on: Array = [0]     # 0-indexed positions in the cycle that fire
var _hits: int = 0

func on_attack(weapon: Weapon, user: Node, ctx: Dictionary) -> void:
    var pos: int = _hits % period
    _hits += 1
    if pos in fire_on:
        _fire(weapon, user, ctx)

func _fire(_weapon: Weapon, _user: Node, _ctx: Dictionary) -> void:
    pass
```

The counter runs continuously with **no idle reset** — predictable and weapon-agnostic. Each
concrete modifier sets `period` / `fire_on` in `_init` and overrides `_fire`.

### `src/weapons/modifiers/modifier_projectile.gd` — shared spawn helper

A static helper that factors out the projectile-spawn recipe currently duplicated between
`RangedWeapon._spawn_projectile` and `spawn_command._spawn_behavior_projectile`. It instantiates
`res://scenes/projectile.tscn` and configures it:

```gdscript
class_name ModifierProjectile
extends RefCounted

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")

# opts keys (all optional): speed, lifetime, behaviors (Array), hit_status (String),
#   tint (Color), texture (Texture2D)
static func spawn_one(user: Node, origin: Vector2, direction: Vector2, damage: float,
        opts: Dictionary = {}) -> Projectile

static func spawn_fan(user: Node, origin: Vector2, base_dir: Vector2, damage: float,
        count: int, spread_deg: float, opts: Dictionary = {}) -> void
```

Behavior:
- `is_enemy_projectile = user.is_in_group("attackable") or user.is_in_group("cave_spawned")`
  (matches `RangedWeapon`), so player weapons fire player projectiles.
- `source_node = user`.
- `behaviors` array is assigned **before** `add_child` so `Projectile._ready` calls `on_spawn`.
  Each `_fire` constructs **fresh** behavior instances per spawn (behaviors are stateful, e.g.
  `BounceBehavior.max_bounces`).
- Sprite `modulate` is set from `opts.tint` for theming; texture defaults to a small existing
  texture (e.g. `res://textures/wall.png`, as `spawn_command` uses) unless `opts.texture` given.
- Parent selection: the world chunk container via
  `user.get_tree().get_first_node_in_group("world_manager").get_chunk_container()`, falling back
  to `user.get_parent()`. The fallback keeps the helper usable in unit tests (no world manager).
- `spawn_fan` distributes `count` projectiles evenly across `spread_deg` centered on `base_dir`
  (single projectile fires straight when `count == 1`), mirroring `RangedWeapon._use_impl`.

### `Projectile` change — on-hit status

`src/weapons/projectile.gd` gains `@export var hit_status: String = ""`. In `_handle_hit`, in the
attackable-enemy branch, after damage is applied (independent of crit), apply the stain:

```gdscript
if hit_status != "":
    var sc = target.get_node_or_null("StatusComponent")
    if sc != null:
        sc.add_stain(hit_status, HIT_STATUS_STAIN)
```

`HIT_STATUS_STAIN` is a small constant (≈ `CRIT_STATUS_STAIN = 2.0`). This is what lets
`fireball_fan` apply `on_fire` and `icicle_volley` apply `chilly` on every hit. A projectile with
`hit_status == ""` behaves exactly as today.

---

## Section 3 — The ten modifiers

All new files live in `src/weapons/modifiers/`. Damage uses **fixed per-modifier values**
(independent of weapon damage); the numbers below are starting values to tune in-game.

### Group A — every swing (`period = 1`, `fire_on = [0]`)

| File / id | Effect |
|---|---|
| `fireball_fan_modifier.gd` / `fireball_fan` | `spawn_fan` 5 projectiles, ~30° spread, ~2 dmg each, `hit_status = "on_fire"`, orange tint |
| `icicle_volley_modifier.gd` / `icicle_volley` | `spawn_fan` 5 projectiles, ~30° spread, ~2 dmg each, `hit_status = "chilly"`, blue tint |
| `gleaming_projectile_modifier.gd` / `gleaming_projectile` | `spawn_one` ~3 dmg, `behaviors = [ClearBulletsBehavior.new()]`, white tint |
| `green_crescent_modifier.gd` / `green_crescent` | `spawn_one` ~5 dmg, `behaviors = [PenetrateBehavior.new()]`, green tint |

### Group B — cadence-gated

| File / id | period | fire_on | Effect |
|---|---|---|---|
| `arc_volley_modifier.gd` / `arc_volley` | 3 | [0,1] | `spawn_fan` 7 projectiles, ~45° spread, ~1.5 dmg each |
| `triangular_volley_modifier.gd` / `triangular_volley` | 3 | [2] | 13 projectiles in a triangular pattern (three rows of widening fan; ~1.5 dmg each) |
| `splitting_rounds_modifier.gd` / `splitting_rounds` | 2 | [1] | `spawn_fan` 3 projectiles, ~3 dmg, each `behaviors = [SplitBehavior.new()]` (→ 4 shards on impact) |
| `bouncing_bullets_modifier.gd` / `bouncing_bullets` | 3 | [2] | `spawn_fan` 4 projectiles, ~3 dmg, each `behaviors = [BounceBehavior.new()]` |

`arc_volley` + `triangular_volley` together tile a three-hit cycle (hits 1&2, then hit 3),
preserving their CSV theme even on a combo-less weapon. Cadence numbers are tunable constants.

"Triangular pattern" for `triangular_volley`: three sub-fans fired at slightly increasing reach
offsets (e.g. 5 + 4 + 4 bolts, or evenly across a wider arc) to read as a triangle. The exact
layout is a tuning detail; 13 total bolts at ~1.5 dmg is the contract.

### Group C — charge & chance (weapon-agnostic, not hit-counted)

| File / id | Trigger | Effect |
|---|---|---|
| `penetrating_shockwave_modifier.gd` / `penetrating_shockwave` | `ctx.charged and ctx.charge_ratio >= 1.0` | `spawn_one` ~8 dmg, large, `behaviors = [PenetrateBehavior.new(), ClearBulletsBehavior.new()]`, fast/long-lived. No-ops on non-chargeable weapons. |
| `lightning_bolt_modifier.gd` / `lightning_bolt` | ~25% `randf()` roll per `on_attack` | Find nearest node in group `attackable` within range of the user; deal ~6 damage via `on_hit_impact`; apply `frozen` stain (the "stun") to its `StatusComponent`; play a brief flash FX at the target. No-ops if no target in range. |

`penetrating_shockwave` and `lightning_bolt` override `on_attack` directly (they don't use the
`period`/`fire_on` cadence). They still read only `ctx` and global node groups — never weapon combo
state.

`lightning_bolt` FX: a lightweight, short-lived visual at the target (e.g. a brief `Sprite2D` /
`Line2D` flash added to the spawn parent, self-freeing via a timer). No new art required; reuse an
existing texture with a tint or a simple drawn line. The damage + `frozen` application is the
gameplay contract; the FX is cosmetic.

### `lava_emitter` (existing)

Relocated to `src/weapons/modifiers/lava_emitter_modifier.gd` for folder consistency; behavior
unchanged (fires from `on_use`). The only references are the two `preload` paths in
`weapon_registry.gd` (`modifier_scripts["lava_emitter"]` in `_ready` and the entry in
`_populate_modifier_tiers`); update both plus the moved `.uid`. `spawn_command.gd` reaches it only
through the registry, so it needs no change.

---

## Section 4 — Registration & demoability

`src/autoload/weapon_registry.gd`:

- In `_ready`, register all ten scripts in `modifier_scripts` keyed by CSV id, e.g.
  `modifier_scripts["fireball_fan"] = preload("res://src/weapons/modifiers/fireball_fan_modifier.gd")`.
  This is the single source that drives both `_make_modifier` (CSV name/description/`suppresses`
  overlay) and the console `spawn mod <id>` registration.
- `_populate_modifier_tiers` assigns drop tiers:
  - **Common:** `lava_emitter`, `fireball_fan`, `icicle_volley`
  - **Uncommon:** `gleaming_projectile`, `green_crescent`, `splitting_rounds`, `bouncing_bullets`
  - **Rare:** `arc_volley`, `triangular_volley`, `penetrating_shockwave`, `lightning_bolt`

`src/console/commands/spawn_command.gd` needs **no edits** — its `for key in
WeaponRegistry.modifier_scripts` loop auto-registers a `spawn mod <id>` command for every
registered modifier. Verification flow: `spawn mod <id>` → pick it up → slot it on a weapon →
attack.

---

## Section 5 — Testing

New `tests/unit/test_modifiers.gd`, mirroring `tests/unit/test_projectile_behaviors.gd`
(instantiate the object directly, drive its hooks, assert on results). A test user is a `Node2D`
in groups as needed with a parent node so `ModifierProjectile`'s fallback parent works; no world
manager required.

- **Cadence:** for `ProjectileModifier` with `period = 3`, `fire_on = [0,1]`, calling `on_attack`
  five times fires on calls 1, 2, 4, 5 and skips 3 (positions 0,1,2,0,1). Confirms the counter
  math and that no weapon state is read.
- **Group A spawn:** `fireball_fan.on_attack` spawns 5 child projectiles under the parent, each
  with `hit_status == "on_fire"`; `gleaming_projectile` spawns 1 carrying a `ClearBulletsBehavior`;
  `green_crescent` spawns 1 carrying a `PenetrateBehavior`.
- **Group B gating:** `arc_volley` spawns 7 on hits at positions 0 and 1 and nothing at position
  2; `triangular_volley` spawns 13 only at position 2; `splitting_rounds` projectiles carry
  `SplitBehavior`; `bouncing_bullets` projectiles carry `BounceBehavior`.
- **`penetrating_shockwave`:** fires only when `ctx.charged and charge_ratio >= 1.0`; the spawned
  projectile carries both `PenetrateBehavior` and `ClearBulletsBehavior`; no spawn on a non-charged
  ctx.
- **`lightning_bolt`:** with `randf` forced high → no fire; with a guaranteed roll and a nearby
  `attackable` stub exposing `on_hit_impact` + a `StatusComponent`, it damages the nearest target
  and adds a `frozen` stain; no-ops with no target in range. (Roll determinism via a seeded RNG or
  a probability of 1.0 in the test setup.)
- **`hit_status` on `Projectile`:** a projectile with `hit_status = "on_fire"` hitting an
  attackable stub adds an `on_fire` stain even without a crit; `hit_status == ""` adds nothing.
- **Regression:** a weapon with no modifiers calls `notify_attack` and spawns nothing; existing
  `test_projectile.gd` continues to pass (the `hit_status == ""` default preserves current
  behavior).

---

## File summary

**New**
- `src/weapons/modifiers/projectile_modifier.gd` — cadence base class
- `src/weapons/modifiers/modifier_projectile.gd` — shared spawn helper
- `src/weapons/modifiers/fireball_fan_modifier.gd`
- `src/weapons/modifiers/icicle_volley_modifier.gd`
- `src/weapons/modifiers/gleaming_projectile_modifier.gd`
- `src/weapons/modifiers/green_crescent_modifier.gd`
- `src/weapons/modifiers/arc_volley_modifier.gd`
- `src/weapons/modifiers/triangular_volley_modifier.gd`
- `src/weapons/modifiers/splitting_rounds_modifier.gd`
- `src/weapons/modifiers/bouncing_bullets_modifier.gd`
- `src/weapons/modifiers/penetrating_shockwave_modifier.gd`
- `src/weapons/modifiers/lightning_bolt_modifier.gd`
- `tests/unit/test_modifiers.gd`

**Modified**
- `src/weapons/modifier.gd` — add `on_attack` no-op hook
- `src/weapons/weapon.gd` — add `notify_attack`
- `src/weapons/melee_weapon.gd` — call `notify_attack` from `_use_impl`
- `src/weapons/ranged_weapon.gd` — call `notify_attack` from `_use_impl`
- `src/weapons/advanced_melee_weapon.gd` — thread `ctx` through `_play_move`; call `notify_attack`
- `src/weapons/projectile.gd` — add `hit_status` field + on-hit stain application
- `src/autoload/weapon_registry.gd` — register ten modifier scripts; assign drop tiers; update
  `lava_emitter` preload path
- `docs/design_docs/implementation_todo.md` — mark Sub-project 4 rows done (on completion)

**Moved**
- `src/weapons/lava_emitter_modifier.gd` → `src/weapons/modifiers/lava_emitter_modifier.gd`
  (+ `.uid`)
