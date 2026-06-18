# SP-D — Native Melee Mechanics + 18 Melee Weapons

**Date:** 2026-06-17
**Branch:** feat/content-expansion
**Phase 7 sub-project:** D (8) — native melee mechanics + the 18 content-expansion melee weapons.
**Depends on:** SP-A (data-driven factory, `resolve_hit` chokepoint, effective-stats pipeline —
all built), SP-B (`apply_knockback`, `PlayerInventory.heal`).
**Data of record:** `docs/design_docs/weapons.csv`,
`2026-06-15-weapon-modifier-separation-design.md`, `2026-06-14-content-expansion-design.md`.

## 1. Problem

The weapon/modifier-separation redesign stripped pre-attached modifiers from the
content-expansion weapons and re-cast their signature behavior as **native, intrinsic weapon
identity** (the `archetype` column), freeing all 3 modifier slots for emergent player choices.
SP-A made every pure-stat weapon droppable, but the weapons whose identity is a *behavior* — not
just a stat shape — are inert: their archetypes are unregistered, so the factory skips the rows
with a warning.

SP-D supplies the native mechanics those weapons need, plus the small shared plumbing they hang
off, and wires all 18 SP-D melee weapons to drop and function.

## 2. Scope

The 18 SP-D melee weapons split into three buckets.

**Bucket 1 — already playable from SP-A, no new code (8).** Pure stat-niche + crit on the
`melee` archetype; SP-D only confirms they feel right in play:
`iron_mace`, `rapier`, `cleaver` (its "wide front arc" is a 120° melee arc — already works),
`venom_fang_blade`, `tide_caller`, `cinder_brand`, `glacier_edge`, `thunder_katana`.

**Bucket 2 — new archetype script (8).** Section 4.

**Bucket 3 — free-carve flag (2).** `obsidian_greatsword` + `gravedigger_spade` stay on the
`melee` archetype and gain native carve-through-any-terrain via a data flag (Section 3.2).

**Out of scope:** SP-E ranged natives + 10 ranged weapons; any new *modifier* (the
modifiers.csv entries are unchanged — `vampiric`/`bloodlust`/`adrenaline`/`deep_cut`/
`tunnel_borer` remain available to slot on *other* weapons; SP-D weapons own equivalent
behavior natively without consuming a slot).

## 3. Shared plumbing

### 3.1 Native hook seams on `Weapon`

Two overridable virtuals, default-inert, so archetypes inject native behavior through the single
hit chokepoint instead of duplicating it:

```gdscript
func _native_modify_hit_damage(_user: Node, _target: Node, dmg: float) -> float:
    return dmg

func _native_on_kill(_user: Node, _target: Node) -> void:
    pass
```

Wired into `Weapon.resolve_hit()`:
- after the modifier `modify_hit_damage` fold and before `on_hit_impact`, apply
  `dmg = _native_modify_hit_damage(user, target, dmg)`;
- inside the existing kill branch (`had_hp and pre_hp > 0.0 and target.health <= 0.0`), after the
  modifier `on_kill` loop, call `_native_on_kill(user, target)`.

`_seed_effective_stats()` is already an override seam (used by `MeleeWeapon` for reach/arc);
soul_reaver overrides it to fold its stacking damage so the value shows in the weapon UI.

Per-instance trait state (stacks, timers) lives on the archetype instance — the established
bespoke-weapon pattern (`void_sword`, `willowblade`).

### 3.2 Free-carve flag

- `MeleeWeapon` gains `@export var free_carve: bool = false`
  (`@export` is mandatory so `duplicate(true)` preserves it — see
  `[[weapon-csv-fields-must-be-export]]`).
- New `weapons.csv` column `free_carve` (`Yes`/blank). `weapon_registry._apply_tuning()` sets it
  for `MeleeWeapon` rows.
- `MeleeWeapon._carve_and_push()`: when `free_carve` is true, the solids-clearing call passes an
  effectively-infinite carve strength (`INF`) so every solid (dirt, wood, **stone**, coal, ice)
  clears within reach regardless of hardness. When false, behavior is unchanged (current
  `dmg`-gated carve).

### 3.3 `PlayerInventory.get_health_fraction()`

```gdscript
func get_health_fraction() -> float:
    return float(_current_health) / float(maxi(1, max_health))
```

Read live by `berserker_axe`. (`is_full_health()` already exists; this is the graded analog.)

### 3.4 Shared radial-knockback helper

`quake_hammer`'s shockwave reuses the radial-knockback pattern already in
`DataModifier._do_knockback` / `_radial_targets`. Factor that loop into a static helper both call
(e.g. `CombatUtil.radial_knockback(origin_node, radius, strength)`), so the logic lives in one
place. (Pure refactor of existing behavior; no behavior change for SP-B modifiers.)

## 4. The 8 new archetype scripts

All extend `MeleeWeapon` or `AdvancedMeleeWeapon`, are placed under `src/weapons/`, and are
registered in `weapon_registry._ready()` under their CSV `archetype` key. `reach`/`arc` come from
the CSV columns (Section 5); values below are the intended data.

### 4.1 `twin_daggers` — `TwinDaggersWeapon extends AdvancedMeleeWeapon`
Double-hit. `_setup_moves()`: `combo_mode = AUTO_FLURRY`, `light_moves = [_slash(), _slash()]`,
`flurry_step_time ≈ 0.05`. Two near-instant hitbox passes per attack; low base damage. On-hit
edges proc twice. Data: reach 22, arc 60°.

### 4.2 `war_scythe` — `WarScytheWeapon extends MeleeWeapon`
Surround/rear reaping sweep. Sets `arc_angle = deg_to_rad(300)` (hit detection: flanks + behind,
~60° blind spot directly behind) and `half_arc = deg_to_rad(150)` so the **cosmetic** swing wraps
to match (the default `half_arc` only sweeps ~100° visually). Long reach. Data: reach 44, arc 300°.

### 4.3 `whirlwind_blade` — `WhirlwindBladeWeapon extends AdvancedMeleeWeapon`
`_setup_moves()`: `light_moves = [_slash()]`, `charged_moves = [_spin()]`, `charged_flurry_max = 1`.
Tap = normal arc; full charge = the existing `_spin()` move (arc `TAU`, full-revolution
animation) striking all surrounders. Data: reach 30, arc 90°.

### 4.4 `quake_hammer` — `QuakeHammerWeapon extends AdvancedMeleeWeapon`
Heavy/slow. `light_moves = [_slash()]`; charged release = a heavy slam: the charged move's hit
**plus** `CombatUtil.radial_knockback(user, shockwave_radius, knockback_strength)` over surrounding
attackables. Implemented by overriding the charged-attack path (`_do_charged_attack`) to fire the
move and then the radial knockback. Highest base damage, slowest. Data: reach 32, arc 110°;
shockwave radius ≈ 70 px.

### 4.5 `mirror_blade` — `MirrorBladeWeapon extends MeleeWeapon`
Reflect, not destroy. Every melee swing already deletes enemy projectiles in-arc
(`MeleeWeapon._destroy_projectiles_in_arc`). Mirror Blade overrides that pass to **reflect**: for
each enemy `Projectile` in the swing arc, instead of `queue_free()`:
- `p.is_enemy_projectile = false`,
- `p.direction = -p.direction` (fly back outward),
- `p.source_weapon = self` (reflected hits route through `resolve_hit`, so player damage/crit/
  modifiers apply),
- rotate the sprite to match the new heading; keep `ProjectileBlockFX` for feedback.
The projectile's `collision_mask` already includes the attackable layer, so a reflected bolt
damages enemies via the existing non-enemy `_on_hit` branch. Data: reach 30, arc 100°.

### 4.6 `reaper_glaive` — `ReaperGlaiveWeapon extends MeleeWeapon`
Long reach + small native heal-on-kill. `_native_on_kill(user, _t)` →
`user.get_node_or_null("PlayerInventory").heal(REAP_HEAL)` (`REAP_HEAL = 2`, lighter than
`vampiric`'s 3). Stacks on top of a slotted `vampiric`/`bloodlust`. Data: reach 44, arc 100°.

### 4.7 `berserker_axe` — `BerserkerAxeWeapon extends MeleeWeapon`
Native low-HP damage ramp. `_native_modify_hit_damage(user, _t, dmg)` →
`dmg * lerpf(1.0, MAX_RAMP, 1.0 - hp_fraction)` where `hp_fraction =
PlayerInventory.get_health_fraction()` (default 1.0 if absent) and `MAX_RAMP = 1.6` (×1.0 at full
HP → ×1.6 near death). Data: reach 34, arc 110°.

### 4.8 `soul_reaver` — `SoulReaverWeapon extends MeleeWeapon`
Native per-kill damage stacking, decays out of combat. State `_kill_stacks: float`.
- `_native_on_kill` → `_kill_stacks = minf(_kill_stacks + STACK_GAIN, STACK_CAP)`; reset a
  `_decay_timer`; `invalidate_effective_stats()`. (`STACK_GAIN = 0.5`, `STACK_CAP = 8.0`.)
- `_seed_effective_stats()` → `super` then `s["damage"] += _kill_stacks`.
- `_tick_impl(delta)` → after `DECAY_DELAY = 3.0`s without a kill, drop 1 stack/3s toward 0,
  invalidating the cache each step (mirrors `DataModifier` Bloodlust decay).
Data: reach 34, arc 100°.

## 5. CSV & registry changes

- **`weapon_registry._ready()`**: register the 8 archetypes —
  `war_scythe`, `twin_daggers`, `whirlwind_blade`, `quake_hammer`, `mirror_blade`,
  `reaper_glaive`, `berserker_axe`, `soul_reaver`.
- **`weapons.csv`**: fill `reach`/`arc` for the 8 archetype rows per Section 4; append a
  `free_carve` column with `Yes` for `obsidian_greatsword` and `gravedigger_spade` (blank
  elsewhere). Bucket-1 rows are untouched.
- **`weapon_registry._apply_tuning()`**: read the `free_carve` column onto `MeleeWeapon`.

No `modifiers.csv` change. No `.tres` (the system is `.tres`-free post-SP-A).

## 6. Testing (gdUnit4, under `tests/unit/`)

- `twin_daggers`: one `use()` resolves **two** hits on an in-arc target.
- `war_scythe`: a target behind the player (within the ~300° arc) is hit; a target in the ~60°
  rear blind spot is not.
- `whirlwind_blade`: full-charge release uses a 360° arc (hits a target behind); a tap uses the
  normal front arc.
- `quake_hammer`: charged release calls `apply_knockback` on surrounding attackables; a tap does
  not.
- `mirror_blade`: an enemy projectile in the swing arc becomes player-owned
  (`is_enemy_projectile == false`), direction reversed, `source_weapon == weapon` — and is not
  freed.
- `reaper_glaive`: `_native_on_kill` calls `PlayerInventory.heal` (mock inventory).
- `berserker_axe`: `_native_modify_hit_damage` returns base at full HP and ≈×1.6 near 0 HP.
- `soul_reaver`: a kill raises effective damage by `STACK_GAIN`; stacks cap at `STACK_CAP`;
  decay reduces them after `DECAY_DELAY`.
- `free_carve`: an obsidian/gravedigger swing clears `MAT_STONE` within reach where a plain
  `melee` swing of equal damage does not.
- `duplicate(true)` round-trip preserves `free_carve` and per-archetype tuning (regression for the
  `@export` requirement).

Manual: launch; spawn each of the 8 Bucket-2 weapons + obsidian/gravedigger via the cheat
console; confirm the reflect, the surround sweep, the charged spin/shockwave, the sustain/ramp/
stack traits, and carve-through-stone behave as described, with all 3 modifier slots free.

## 7. Acceptance

- The 8 Bucket-2 archetypes are registered; all 18 SP-D melee weapons build from CSV and drop.
- `obsidian_greatsword` / `gravedigger_spade` carve any terrain (incl. stone) natively.
- Native traits route through `resolve_hit` / effective-stats via the two new seams; no
  duplication of the chokepoint.
- Existing test suite green; the Section 6 tests added and green.

## 8. Out-of-scope follow-ups
SP-E: native ranged mechanics (line-pierce, charged rail, lob-splat, chain/fork, return, homing,
area volley) + the 10 ranged weapons.
