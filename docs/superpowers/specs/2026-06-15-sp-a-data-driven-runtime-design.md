# SP-A — Data-Driven Runtime (Weapons + Modifiers)

**Date:** 2026-06-15
**Branch:** feat/content-expansion
**Phase 7 sub-project:** A (5) — the keystone of the content-expansion build-out.
**Depends on / supersedes data-of-record:** `docs/design_docs/weapons.csv`,
`docs/design_docs/modifiers.csv`, `2026-06-14-content-expansion-design.md`,
`2026-06-15-weapon-modifier-separation-design.md`.

## 1. Problem

The content-expansion specs documented 28 new weapons and 46 new modifiers as CSV data, but
none have behavior. Two structural gaps block them:

1. **Weapons are only half data-driven.** Every weapon needs both a CSV row *and* a
   hand-authored `resources/weapons/<id>.tres` that pins its archetype script and the tuning
   the CSV has no columns for (`weapon_reach`/`arc_angle`; `projectile_speed`/`lifetime`/
   `spread`/`count`/`texture`). No `.tres` → `weapon_registry` skips the row. The 28 new
   weapons are inert for lack of a `.tres`.
2. **Modifiers are one hand-written GDScript each.** The 11 existing modifiers are registered
   individually in `weapon_registry.gd`; the 46 new ones have no script. There is no
   data-driven runtime, and — critically — **no per-hit `on_hit` hook, no `on_kill` signal,
   and no effective-stats layer** for the stat affixes and conditional multipliers to use.

SP-A closes both gaps with one keystone: a fully data-driven weapon factory, a `DataModifier`
runtime, an effective-stats pipeline, and a single hit-resolution chokepoint shared by melee
and ranged. SP-B/C/D/E hang their on-hit/on-kill/charge effects off the same chokepoint.

## 2. Scope

**In scope**
- Fully data-driven weapon factory; **delete all 23 `.tres`** (and `.uid`/`.import` sidecars).
- `DataModifier` class building the 46 new modifiers from CSV columns. The 11 bespoke modifier
  scripts (projectile/combo behaviors) are **kept** and take precedence by id.
- Effective-stats pipeline on `Weapon`.
- `Weapon.resolve_hit()` chokepoint threaded through **both** melee and projectiles.
- The 32 data-expressible modifiers: 7 emitters, 6 status-edges, 9 stat affixes, 10 conditional
  triggers (those reusing existing hooks only).
- The ~10 new weapons that are pure data (stats/arc/crit/pre-attached) become droppable.

**Out of scope (deferred, unchanged from Phase 7 decomposition)**
- New statuses `lightning`/`steam`/`stun`, economy `bounty`, enemy knockback/stun, and the
  modifiers needing them (chain_spark, steam_burst, concussive_edge, repulsor_nova,
  shockwave_stomp, magnet_field, midas_touch) → **SP-B**.
- New projectile behaviors `homing`/`return` and the projectile modifiers (homing_hex,
  boomerang_arc, ricochet_shard, piercing_lance, cluster_bomb, spectral_echo) → **SP-C**.
- Native melee/ranged mechanics and the weapons needing them (twin_daggers double-hit,
  whirlwind spin, mirror deflect, quake/soul/berserker/reaper native traits, obsidian/
  gravedigger free-carve, heavy_crossbow pierce, arc_railgun rail, tesla chain, chakram return,
  seeker homing, hailstorm volley, lob-splat) → **SP-D / SP-E**.

Rows whose `archetype` script isn't registered yet are skipped gracefully (today's
missing-`.tres` behavior) and light up when their script lands.

## 3. Weapon factory (fully data-driven, zero `.tres`)

### 3.1 CSV schema extension
Append to `weapons.csv` (non-breaking — existing code reads columns by name and ignores
unknowns; mirrors the modifiers.csv extension precedent):

```
... ,crit_status,archetype,reach,arc,projectile_speed,projectile_lifetime,spread,projectile_count,projectile_texture
```

- `archetype` — key into `weapon_scripts`. Blank defaults from `type`: `Melee`→`melee`,
  `Ranged`→`ranged`.
- `reach` (px), `arc` (**degrees**, converted to radians in the factory) — melee.
- `projectile_speed`, `projectile_lifetime`, `spread` (degrees), `projectile_count`,
  `projectile_texture` (res path) — ranged.
- Blank = archetype script default.

### 3.2 Archetype registry
`weapon_registry._ready()` registers all archetype scripts in `weapon_scripts`, including the
nine bespoke melee scripts currently referenced only by `.tres`:

| archetype key | script |
|---|---|
| `melee` | `melee_weapon.gd` |
| `ranged` | `ranged_weapon.gd` |
| `willowblade` | `willowblade_weapon.gd` |
| `blood_blade` | `blood_blade_weapon.gd` |
| `void_sword` | `void_sword_weapon.gd` |
| `dragon_fang` | `dragon_fang_weapon.gd` |
| `executioner` | `executioner_weapon.gd` |
| `grand_knight` | `grand_knight_weapon.gd` |
| `deep_dark` | `deep_dark_weapon.gd` |
| `phantom_blade` | `phantom_blade_weapon.gd` |
| `qinggang` | `qinggang_weapon.gd` |

(`aimed_burst`, `fan`, `split_shot`, `sniper`, `test` remain registered for enemy/other use.)

### 3.3 Build path
Replace `_load_weapon_resources()`'s `load(<id>.tres)` with construction from the row:
1. resolve `archetype` → script; if unregistered, warn + skip (graceful).
2. `var weapon = script.new()`.
3. `_apply_csv_fields(weapon, row)` (unchanged for the existing columns) **plus** the new
   tuning columns: set `weapon_reach`, `arc_angle = deg_to_rad(arc)`, and the ranged
   `projectile_*` fields when present.
4. store canonical in `_weapons_by_id` / `_all_weapons`.

### 3.4 `duplicate(true)` constraint
`get_weapon_by_id()` / `get_random_weapon()` hand out `canonical.duplicate(true)`. Plain `var`
fields are dropped by `duplicate()` (see `[[weapon-csv-fields-must-be-export]]`). Therefore
every field the factory sets must be `@export`:
- Tuning fields already are (`weapon_reach`, `arc_angle`, `projectile_*`).
- **Promote `Weapon.cooldown` and `Weapon.damage` to `@export`** (currently plain `var`).

### 3.5 No behavior change for existing weapons
Transcribe each deleted `.tres`'s `weapon_reach`/`arc_angle`/`projectile_*` verbatim into the
CSV (arc converted rad→deg). The 23 existing weapons must behave **identically** after removal.

| weapon | archetype | reach | arc° | weapon | archetype | reach | arc° |
|---|---|---|---|---|---|---|---|
| rusty_sword | melee | 28 | 90 | flame_blade | melee | 32 | 90 |
| bone_dagger | melee | 20 | 60 | flame_sword | melee | 28 | 90 |
| broad_axe | melee | 36 | 120 | frost_sword | melee | 28 | 90 |
| broadsword | melee | 34 | 140 | heavenly_sword | melee | 40 | 120 |
| caliburn | melee | 34 | 140 | tao_sword | melee | 40 | 120 |
| blood_blade | blood_blade | 28 | 90 | willowblade | willowblade | 28 | 90 |
| deep_dark_blade | deep_dark | 40 | 120 | void_sword | void_sword | 34 | 140 |
| dragon_fang | dragon_fang | 40 | 120 | phantom_blade | phantom_blade | 34 | 140 |
| executioner | executioner | 34 | 140 | qinggang_sword | qinggang | 28 | 90 |
| grand_knight_sword | grand_knight | 40 | 120 | | | | |

Ranged (`projectile_speed`/`lifetime`/`spread`/`count`/`texture`):
- throwing_knife: 180 / 2.0 / 0 / 1 / arrow_01a
- spread_shot: 150 / 2.0 / 30 / 3 / arrow_02a
- fire_orb: 90 / 1.5 / 0 / 1 / fish_01a
- boss_staff: default / default / 10 / default / arrow_03a

## 4. `DataModifier` runtime

### 4.1 Class
`src/weapons/modifiers/data_modifier.gd extends Modifier`. Constructed from the CSV row dict;
stores `category, trigger, condition, effect, element, magnitude, magnitude2` (plus the
name/description/suppresses already handled). Dispatches by `trigger` into the new/existing
Modifier virtuals:

| trigger | dispatches into |
|---|---|
| `on_swing` | `on_attack(weapon, user, ctx)` |
| `on_hit` | `on_hit_target()` and/or `modify_hit_damage()` (new) |
| `on_kill` | `on_kill()` (new) |
| `every_n_hits` | hit counter → `modify_crit_chance()` |
| `passive` | `modify_stat()` (new) |
| `on_crit`/`on_charge`/`on_combo_step` | no-op in SP-A (SP-B+ scope) |

### 4.2 Registry integration
- `_load_modifier_data()` keeps the **full row** per id (not just name/description/suppresses).
- `_make_modifier(id)`: if `modifier_scripts` has the id (the 11 bespoke), use it; else build
  `DataModifier.new(row)`.
- `_populate_modifier_tiers()`: replace the hand-listed buckets with a loop over every CSV row,
  bucketed by `rarity`, so all 57 modifiers are droppable.

### 4.3 The 32 SP-A modifiers

**Emitters (7)** — `on_attack`, `effect=spawn_material`. Place an `element` blob of radius
`magnitude` px at the swing-arc midpoint (melee) or impact point (ranged) via `TerrainSurface`/
`terrain_modifier`. `magnitude2>0` overrides lifetime. Spawned material obeys the live sim.
ids: oil_emitter, water_emitter, gas_emitter, frost_emitter, blood_emitter, coal_seeder,
dust_veil. (The bespoke `lava_emitter` script is **kept** for its tuned 3-blob splash on the
signature flame weapons.)

**Status-edges (6)** — `on_hit_target`, `effect=apply_status`:
`target.StatusComponent.add_stain(element, magnitude)`. ids: venom_edge(poisoned),
soaking_strike(wet), greased_edge(oiled), frostbite_edge(chilly), ember_edge(on_fire),
rending_edge(bloody).

**Stat affixes (9)** — `modify_stat` into effective-stats (Section 5):
- sharpened `damage +3`; heavy_head `damage +5` **and** `cooldown ×1.25` (reads magnitude2);
- honed_point `crit_chance +0.15` (also via `modify_crit_chance`);
- executioners_mark `crit_multiplier +0.5`; quickdraw `cooldown ×0.8` (floor 0.1s);
- long_reach `reach ×1.3`; wide_arc `arc ×1.4` (no-op ranged); deep_cut `carve_depth ×1.8`;
- fleetfoot `move_speed ×1.15` (queried by player while attacking).

**Conditional triggers (10)** — reuse existing hooks only:
- frostbreaker `on_hit/target frozen≥3 or chilly active → ×1.6` (`modify_hit_damage`);
- pyroclast `on_hit/target on_fire → ×1.5`;
- coup_de_grace `on_hit/target hp ≤ magnitude2(0.3) → ×2.0`;
- glass_cannon `on_hit/self full hp → ×1.8`;
- momentum `on_hit → ×lerp(1, 1.5, speed_fraction)`;
- rampage `on_hit → +1/streak, cap 6; reset if no hit lands within 1.5s`;
- bloodlust `on_kill → +1/stack, cap 8; decay 1 every 3s without a kill`;
- vampiric `on_kill → player.heal(3)`;
- adrenaline `passive → cooldown ×lerp(1, 0.6, 1-hp_fraction)`;
- combo_keeper `every_n_hits(5) → force crit_chance=1.0 that hit, reset counter`.

Decay/streak rules above are the implementor decisions the content-expansion spec left open.

**Counter timing.** The crit roll happens in the caller (`roll_crit()` via
`get_effective_crit_chance()`) *before* `resolve_hit`. So `every_n_hits` must be evaluated at
crit-roll time: combo_keeper's `modify_crit_chance` returns 1.0 when the successful-hit counter
is one short of `magnitude2` (the upcoming hit is the Nth). `resolve_hit` step 7 increments the
counter only on a landed hit and resets it after the forced crit. This keeps the guarantee
aligned with the roll that actually decides the crit.

## 5. Effective-stats pipeline

`Weapon.get_effective_stats() -> Dictionary` returns cached
`{damage, cooldown, crit_chance, crit_multiplier, reach, arc, move_speed, carve_depth}`:
1. seed from base fields (reach/arc/carve_depth seeded by the archetype; move_speed seed 1.0);
2. sum every modifier's passive `stat_add`;
3. apply each passive `stat_mult` (spec stack rule: add-then-mult).

Cache invalidated on modifier equip/change. **Conditional (non-passive) multipliers are not
here** — they live in `resolve_hit`. Consumers:
- `Weapon.use()` → `_cooldown_timer = effective.cooldown` (quickdraw, heavy_head, adrenaline).
- `MeleeWeapon._use_impl` → effective `damage`/`reach`/`arc`; `carve_depth` scales the carve.
- `RangedWeapon._spawn_projectile` → effective `damage`; crit already flows through
  `get_effective_crit_chance()` (honed_point/combo_keeper hook there).
- `move_speed` exposed via a getter the player queries while an attack is active (fleetfoot);
  the weapon never mutates player state.

## 6. Hit-resolution chokepoint

`Weapon.resolve_hit(user, target, base_dmg, is_crit) -> void` — the single damage path:
1. `dmg = base_dmg * (is_crit ? crit_multiplier : 1)`;
2. fold conditional multipliers: each modifier's `modify_hit_damage(weapon, user, target, dmg)`
   (gated by its `condition`);
3. read `target.health` (pre-hit), call `target.on_hit_impact(pos, dir, int(dmg))`;
4. status-edges: each modifier's `on_hit_target(weapon, user, target)`;
5. on-crit: existing `_on_crit(target)` (crit_status stain) preserved;
6. kill detect: `"health" in target and target.health <= 0` → each modifier's
   `on_kill(weapon, user, target)`; update streak/stack state;
7. advance the weapon's successful-hit counter (combo_keeper / `every_n_hits`).

Integration:
- **Melee** `_hit_attackables`: replace the inline crit/damage/`on_hit_impact` block with a
  `resolve_hit` call (keeps parry + arc filtering as-is).
- **Ranged** `projectile.gd`: add `source_weapon: Weapon` set at spawn. The attackable branch
  routes through `source_weapon.resolve_hit(...)` instead of inlining crit/`hit_status`/
  `crit_status`; the existing flattened path is subsumed. Projectile keeps its own
  spawn/lifetime/behavior logic. (`source_weapon` is a player-owned Resource — stable lifetime;
  guard for null in case a projectile outlives a swap.)
- Per-hit modifier **state** (ramps, counters, stacks) lives on the `Weapon` instance, so it is
  shared across that weapon's melee swings and its in-flight projectiles.

## 7. Testing

gdUnit4, matching existing patterns under `tests/`:
- factory builds a valid weapon from a row with no `.tres`; unregistered archetype → skipped;
  `arc` deg→rad conversion correct.
- effective-stats fold order: `(base + Σadd) × Πmult`; heavy_head touches both damage+cooldown.
- `resolve_hit`: conditional multiplier applies only when condition holds; on-kill fires exactly
  once; status-edge stains target; crit path unchanged.
- emitter places the declared material at the arc midpoint.
- `duplicate(true)` round-trip preserves cooldown/damage/tuning (regression guard for the
  `@export` promotion).

Manual: launch; confirm the 23 existing weapons behave identically (no `.tres` regression) and
the ~10 new data weapons drop and function; spot-check one emitter, one status-edge, one
conditional, one stat affix in play.

## 8. Acceptance
- `resources/weapons/` contains **zero** `.tres` (and no orphan `.uid`/`.import`).
- Every `weapons.csv` row with a registered archetype is built from data and droppable;
  unregistered-archetype rows are skipped with a warning.
- All 57 modifiers are instantiable and bucketed into drop tiers; the 32 SP-A modifiers behave
  per Section 4.3.
- Melee and ranged both honor on-hit / on-kill / passive-stat / conditional modifiers via
  `resolve_hit` and the effective-stats pipeline.
- New SP-A weapons playable: rapier, iron_mace, bone_cleaver, venom_fang_blade, tide_caller,
  cinder_brand, glacier_edge, thunder_katana, scatter_blunderbuss, frost_repeater
  (obsidian/gravedigger playable minus native carve).
- Existing test suite green; new tests above added and green.

## 9. Out-of-scope follow-ups (tracked in implementation_todo Phase 7)
SP-B statuses/economy/knockback; SP-C homing/return projectiles; SP-D native melee mechanics +
remaining melee weapons; SP-E native ranged mechanics + remaining ranged weapons.
