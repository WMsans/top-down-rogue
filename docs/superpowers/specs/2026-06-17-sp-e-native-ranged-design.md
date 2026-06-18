# SP-E — Native Ranged Mechanics + 10 Ranged Weapons

**Date:** 2026-06-17
**Branch:** feat/content-expansion
**Phase 7 sub-project:** E (9) — native ranged mechanics + the 10 content-expansion ranged weapons.
**Depends on:** SP-A (data-driven factory, `resolve_hit` chokepoint, effective-stats pipeline),
SP-B (`lightning`/`stun` statuses, `LightningArcFX`), SP-C (`PenetrateBehavior`,
`ReturnBehavior`, `HomingBehavior`). All built.
**Sibling of:** `2026-06-17-sp-d-native-melee-design.md` (same shape, melee side).
**Data of record:** `docs/design_docs/weapons.csv`,
`2026-06-15-weapon-modifier-separation-design.md`, `2026-06-14-content-expansion-design.md`.

## 1. Problem

The weapon/modifier-separation redesign re-cast each content-expansion weapon's signature
behavior as **native, intrinsic weapon identity** (the `archetype` column), freeing all 3
modifier slots for emergent player choices. SP-A made every pure-stat weapon droppable, but the
ranged weapons whose identity is a *behavior* — pierce-line, charged rail, lob-splat, chaining,
homing, return, area-volley — are inert: their archetypes are unregistered, so the factory skips
the rows with a warning.

SP-E supplies the native mechanics those weapons need, plus the small shared plumbing they hang
off, and wires all 10 SP-E ranged weapons to drop and function. Most of the heavy lifting already
exists: `RangedWeapon` has clean `_configure()` / `_make_behaviors()` override seams, and SP-C
already shipped the `Penetrate` / `Return` / `Homing` behaviors three of these weapons fold in.

## 2. Scope

The 10 SP-E ranged weapons split into two buckets (SP-D had three; SP-E has no free-carve
equivalent).

**Bucket 1 — data-only on the `ranged` archetype, no new script (2):**
- `scatter_blunderbuss` — already a pure-stat row (count 8, spread 60°, lifetime 0.5);
  devastating point-blank, useless at range. Confirmed working via SP-A.
- `frost_repeater` — fast/weak stream; gains frost-on-hit purely from the new `hit_status` CSV
  column (§3.1). Stays `archetype=ranged`, no script.

**Bucket 2 — new archetype script (8).** Section 4.

**Out of scope:** SP-D melee natives (done); any new *modifier* (modifiers.csv is unchanged);
new VFX beyond reusing `LightningArcFX` and material placement; the SP-A generic data-driven
`spawn_projectile` dispatch (these stay bespoke archetype scripts, consistent with SP-C);
refactoring `chain_spark_modifier` onto the new shared helper (left as-is).

## 3. Shared plumbing

Four pieces. Two new behavior classes (§3.3); three reused from SP-C.

### 3.1 `hit_status` CSV column → projectile status

`Projectile` already has `@export var hit_status: String` and applies it on hit
(`projectile.gd` — `hs.add_stain(hit_status, HIT_STATUS_STAIN)`), but `RangedWeapon._spawn_projectile`
never sets it. Add:

- New `weapons.csv` column `hit_status` (status id or blank). `freeze` for `frost_repeater`,
  blank elsewhere.
- `RangedWeapon` gains `@export var hit_status: String = ""`
  (`@export` mandatory so `duplicate(true)` preserves it — see
  `[[weapon-csv-fields-must-be-export]]`). `_spawn_projectile` sets
  `proj.hit_status = hit_status`.
- `weapon_registry._apply_tuning()` reads the `hit_status` column onto `RangedWeapon` rows.

Generic: any future ranged row can apply a status with no script.

### 3.2 `ChargedRangedWeapon extends RangedWeapon` — charge-to-fire base

The charge-input loop currently lives only in `AdvancedMeleeWeapon`. `Weapon` exposes
`get_charge_ratio()` / `is_chargeable()` as default-inert virtuals, and `weapon_manager` already
routes `on_press` / `on_release` generically. `ChargedRangedWeapon` implements the same loop for
ranged, mirroring `AdvancedMeleeWeapon`:

- `@export var charge_time_full: float = 0.7`; state `_charge_time`, `_charging`.
- `on_press(user)`: begin charging (`_charge_time = 0`, `_charging = true`); tick `_charge_time`
  up in `_tick_impl`.
- `on_release(user)`: if `get_charge_ratio() >= 1.0`, fire a charged shot
  (`_fire_charged(user, ratio)` → default `_emit_shot`); otherwise nothing (a partial charge
  fizzles — keeps the weapon "wind-up then loose" rather than tap-fire). `_charging = false`.
- `get_charge_ratio()` = `clampf(_charge_time / charge_time_full, 0, 1)`; `is_charging()` returns
  `_charging`; `is_chargeable()` returns `true` (so the charge bar shows — `weapon_manager`
  already reads these).
- Subclasses read `get_charge_ratio()` (cached into the emit path) to scale the shot.

Only `arc_railgun` uses this base in SP-E.

### 3.3 New `ProjectileBehavior.on_expire` hook

`Projectile._process` calls `queue_free()` on lifetime expiry with no behavior callback, so a
projectile that flies past everything and expires mid-air can't react. Add:

- `ProjectileBehavior.on_expire(_proj) -> void: pass` (default-inert).
- In `Projectile._process`, when `_age >= lifetime`: call `b.on_expire(self)` for each behavior
  **before** `queue_free()`.

This is the seam the lob-splat needs (the hit paths already have `on_terrain_hit` /
`on_enemy_hit`). No change to existing behaviors (default-inert).

### 3.4 `CombatUtil.nearest_attackables` static helper

Factor chain_spark's nearest-scan into a reusable static so `ChainBehavior` (§3.5) doesn't
duplicate it (mirrors SP-D factoring `radial_knockback` into `CombatUtil`):

```gdscript
static func nearest_attackables(tree: SceneTree, from_pos: Vector2, exclude: Array,
        count: int, range_px: float) -> Array:
    # scan group "attackable"; skip nodes in `exclude` / invalid / non-Node2D;
    # keep those within range_px; sort by squared distance; return up to `count`.
```

`chain_spark_modifier` is **not** refactored onto it in this sub-project (out of scope; it fans
from the player, a different shape).

## 4. The 8 new archetype scripts

All extend `RangedWeapon` (or `ChargedRangedWeapon`), placed under `src/weapons/`, registered in
`weapon_registry._ready()` under their CSV `archetype` key. Stat columns
(`projectile_speed` / `projectile_lifetime` / `spread` / `projectile_count`) come from the CSV;
values below are the intended data. Each overrides `_configure()` and/or `_make_behaviors()`.

### 4.1 `heavy_crossbow` — `HeavyCrossbowWeapon extends RangedWeapon`
Line-pierce. `_make_behaviors()` → one `PenetrateBehavior` (SP-C, reuse) with a high `pierces`
(e.g. 99 — skewers everyone in the line). Single heavy fast bolt. Data: speed ~280, count 1.

### 4.2 `arc_railgun` — `ArcRailgunWeapon extends ChargedRangedWeapon`
Charged piercing rail. Fires only on full charge (§3.2). On release, `_emit_shot` spawns a
piercing bolt whose `pierces`, `speed`, and damage scale with `get_charge_ratio()` (full charge =
deepest bite). Implemented by reading the ratio in `_make_behaviors()` / the emit path and seeding
the `PenetrateBehavior.pierces` + projectile speed accordingly. Data: charge_time ~0.7, base
damage 8.

### 4.3 `flame_lobber` — `FlameLobberWeapon extends RangedWeapon`
Lob-splat. `_make_behaviors()` → `SplatBehavior(material="lava", radius≈6)` (§3.5). Short
lifetime so the pot "lands" and shatters into a lava pool whether it hits terrain, an enemy, or
expires mid-air. Data: speed ~110, lifetime ~0.6.

### 4.4 `venom_spitter` — `VenomSpitterWeapon extends RangedWeapon`
Lob-splat, toxic. `_make_behaviors()` → `SplatBehavior(material="gas", radius≈6, gas_density)`.
Spawns a lingering toxic-gas pool on impact; damage comes from the gas simulation eating anything
that lingers. Data: speed ~120, lifetime ~0.6.

### 4.5 `tesla_gun` — `TeslaGunWeapon extends RangedWeapon`
Chain/fork. `_make_behaviors()` → `ChainBehavior(jumps=3, range_px=160)` (§3.5). Fires a fast
single bolt; on the first enemy hit it forks foe-to-foe through nearby enemies. Data: speed ~220,
count 1.

### 4.6 `chakram_launcher` — `ChakramLauncherWeapon extends RangedWeapon`
Return. `_make_behaviors()` → one `ReturnBehavior` (SP-C, reuse). Flies out, loops back to the
wielder, hits foes on both legs. Data: speed ~160, `out_time ≈ 0.5`.

### 4.7 `seeker_launcher` — `SeekerLauncherWeapon extends RangedWeapon`
Homing. `_make_behaviors()` → one `HomingBehavior` (SP-C, reuse) with a capped `turn_rate_rad`
(≈PI). Missiles curve and chase. Data: speed ~140, lifetime longer (chase time).

### 4.8 `hailstorm_bow` — `HailstormBowWeapon extends RangedWeapon`
Area-volley. Overrides `_emit_shot(user, base_dir)` to loose a single wide jittered volley:
~12 projectiles across a wide spread (~120°) with **per-shot random angle and speed jitter** so
they scatter across a swath of ground (rather than the even fan the base `_emit_shot` produces).
One `notify_attack` for the volley. Data: count 12, spread 120°.

## 5. New behavior classes

Both under `src/weapons/projectile_behaviors/`, extend `ProjectileBehavior`.

### 5.1 `SplatBehavior` (`splat_behavior.gd`)
Generic impact-material. Fields: `material: String` (`"lava"` / `"gas"`), `radius: float`,
`gas_density: int`. A single private `_splat(proj)` places the material at `proj.global_position`
via `TerrainSurface.place_lava(pos, radius)` or `TerrainSurface.place_gas(pos, radius, density)`.
- `on_terrain_hit(proj)` → `_splat(proj)`; return `false` (projectile dies — base `_carve_terrain`
  / `queue_free` follows).
- `on_enemy_hit(proj, _t)` → `_splat(proj)`; return `false` (die after the hit).
- `on_expire(proj)` → `_splat(proj)` (mid-air landing).
Idempotency guard (`_done: bool`) so a hit-then-expire can't double-splat.

### 5.2 `ChainBehavior` (`chain_behavior.gd`)
Lightning fork. Fields: `jumps: int = 3`, `range_px: float = 160`, `tint: Color`. State: none
persisted (resolved in one pass). `on_enemy_hit(proj, target)`:
- `host = world chunk container` (resolve as chain_spark does), `visited = [proj.source_node, target]`.
- `from = target`; loop up to `jumps`: `next = CombatUtil.nearest_attackables(tree, from.global_position,
  visited, 1, range_px)`; stop if empty. For `next`:
  `proj.source_weapon.resolve_hit(proj.source_node, next, proj.damage, is_crit)` (crit rolled from
  `proj.crit_chance` — so weapon crit/modifiers apply, unlike chain_spark's flat `on_hit_impact`);
  `next.StatusComponent.add_timed_status("lightning", …)`; `LightningArcFX.play(host,
  from.global_position, next.global_position, tint)`; append `next` to `visited`; `from = next`.
- Return `false` (the bolt is spent after delivering the chain). The base hit on `target` itself
  is the projectile's normal `resolve_hit` (already handled in `Projectile._handle_hit`); the
  chain adds the *forks*.

## 6. CSV & registry changes

- **`weapon_registry._ready()`**: register the 8 archetypes — `heavy_crossbow`, `arc_railgun`,
  `flame_lobber`, `venom_spitter`, `tesla_gun`, `chakram_launcher`, `seeker_launcher`,
  `hailstorm_bow`.
- **`weapons.csv`**: append a `hit_status` column (`freeze` for `frost_repeater`, blank
  elsewhere); fill `projectile_speed` / `projectile_lifetime` / `spread` / `projectile_count` for
  the 8 archetype rows per §4. Bucket-1 rows otherwise untouched.
- **`weapon_registry._apply_tuning()`**: read the `hit_status` column onto `RangedWeapon`.

No `.tres` (the system is `.tres`-free post-SP-A). No `modifiers.csv` change.

## 7. Testing (gdUnit4, under `tests/unit/`)

- `heavy_crossbow`: a single shot's `PenetrateBehavior` keeps the projectile alive through ≥2
  in-line enemies (`on_enemy_hit` returns `true` until pierces exhausted).
- `arc_railgun`: a partial-charge release emits **no** shot; a full-charge release emits one; the
  full-charge bolt has more `pierces` / higher speed than the minimum.
- `SplatBehavior`: `on_terrain_hit`, `on_enemy_hit`, and `on_expire` each call
  `place_lava` / `place_gas` on a mock `TerrainSurface`; the `_done` guard prevents a double-splat
  across hit-then-expire.
- `ChainBehavior`: with 3 stub enemies in range, `on_enemy_hit` resolves `jumps` forks via
  `source_weapon.resolve_hit`, never revisits `target` / `source_node`, and stops when no
  unvisited target remains.
- `chakram_launcher` / `seeker_launcher`: `_make_behaviors()` returns a `ReturnBehavior` /
  `HomingBehavior` respectively.
- `hailstorm_bow`: one `_emit_shot` spawns 12 projectiles spread across ~120° with non-uniform
  (jittered) angles.
- `hit_status`: a `RangedWeapon` with `hit_status="freeze"` spawns a projectile whose
  `hit_status == "freeze"`; `duplicate(true)` round-trip preserves `hit_status` and per-archetype
  tuning (regression for the `@export` requirement).
- Registry: all 8 SP-E archetypes resolve to non-null weapons via the factory.

Manual: launch; spawn each of the 8 Bucket-2 weapons + scatter_blunderbuss / frost_repeater via
the cheat console; confirm the pierce-line, charged rail (with charge bar), lava/gas splat,
lightning fork, return arc, homing curve, area-volley scatter, and frost-on-hit behave as
described, with all 3 modifier slots free.

## 8. Acceptance

- The 8 Bucket-2 archetypes are registered; all 10 SP-E ranged weapons build from CSV and drop.
- Native traits route through `resolve_hit` (ChainBehavior) / projectile status (`hit_status`)
  without duplicating the chokepoint; reused SP-C behaviors are unchanged.
- The `on_expire` hook and `ChargedRangedWeapon` base are default-inert for everything else.
- Existing test suite green; the Section 7 tests added and green.

## 9. Files

New:
- `src/weapons/charged_ranged_weapon.gd`
- `src/weapons/heavy_crossbow_weapon.gd`
- `src/weapons/arc_railgun_weapon.gd`
- `src/weapons/flame_lobber_weapon.gd`
- `src/weapons/venom_spitter_weapon.gd`
- `src/weapons/tesla_gun_weapon.gd`
- `src/weapons/chakram_launcher_weapon.gd`
- `src/weapons/seeker_launcher_weapon.gd`
- `src/weapons/hailstorm_bow_weapon.gd`
- `src/weapons/projectile_behaviors/splat_behavior.gd`
- `src/weapons/projectile_behaviors/chain_behavior.gd`

Modified:
- `src/weapons/ranged_weapon.gd` (`hit_status` field + set on spawn)
- `src/weapons/projectile.gd` (`on_expire` call before lifetime free)
- `src/weapons/projectile_behaviors/projectile_behavior.gd` (`on_expire` virtual)
- `src/weapons/combat_util.gd` (`nearest_attackables` helper)
- `src/autoload/weapon_registry.gd` (register 8 archetypes; `hit_status` in `_apply_tuning`)
- `docs/design_docs/weapons.csv` (`hit_status` column; archetype-row stat fills)
- `tests/unit/` (new/extended tests per §7)
- `docs/design_docs/implementation_todo.md` (mark SP-E done)

## 10. Out-of-scope follow-ups
None remaining in Phase 7 content expansion after SP-E. Phase 8 SP-3 (collision-helper readback
reduction) is the next open work.
