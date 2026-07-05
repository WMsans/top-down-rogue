# Enemy Behavior Depth & Content Expansion

**Date:** 2026-07-05
**Branch:** feat/enemy-balance
**Status:** Approved (design)

## Problem

`implementation_todo2.md` calls for two related pieces of work:

- **Enemy Behavior Depth** (Phase 2): melee/ranged AI sub-patterns beyond the current
  CHASE→WINDUP→ATTACK loop, telegraph polish, separation tuning, wander variety, hurt
  reactions.
- **Enemy Content Expansion** (Phase 2): 5 named melee variants (grunt, brute,
  skirmisher, armored, cultist) and 3 named ranged variants (archer, mage, lobber).

Today only two melee classes (`MeleeEnemy`, `LungeEnemy`) and two ranged classes
(`RangedEnemy`, `SniperEnemy`) exist. None of the named variants exist as distinct
types — "archer" and "lobber" are currently just sprite-texture swaps on `RangedEnemy`
keyed off which weapon class it happened to roll. There is no heal/support enemy
behavior. Sprite art for all 8 named variants already exists under
`textures/Enemies/caves/{grunt,brute,skirmisher,armored,cultist,archer,mage,lobber}/`,
unused.

Per-biome roster and rare spawn enemies (also listed under Enemy Content Expansion)
are out of scope for this spec — separate future work. Enemy-environment hazard
interaction (avoid lava/gas, slow in ice) is also out of scope: no per-tile material
query exists yet outside the coarse solid/non-solid `PassabilityGrid`, and ice-zone
terrain only exists in the excluded frozen biome.

## Goals

1. Eight genuinely distinct enemy archetypes (5 melee + 3 ranged), each combining a
   named content variant with one of the AI sub-behavior patterns from the todo list,
   rather than treating "behavior depth" and "content expansion" as separate work.
2. Reconcile the existing weapon-randomization spawn logic with the new archetypes so
   neither system fights the other.
3. Elite stagger resistance (directional knockback itself already exists).
4. Wander variety, telegraph polish, and separation tuning as small follow-on passes.

## Non-goals

- Per-biome roster, rare spawn enemies, enemy-environment hazard interaction (out of
  scope, see Problem).
- New weapon or projectile-behavior scripts — every projectile shape this design needs
  (straight, spread, arc/AoE, homing) already exists as a registered CSV weapon.
- Changes to `SniperEnemy` or the boss spawn path.

## Prior art check (Enter the Gungeon, Noita, Soul Knight, Dead Cells)

Enter the Gungeon — the closest genre match — differentiates enemies with a *modest*
set of movement archetypes (shambler, kiter, turret, teleporter, rusher) crossed with
attack-pattern variety, then multiplies the roster via stat/skin variants of those
archetypes. Devs stagger enemy fire timing so bullet-hell stays readable. Noita's
healer (Parantajahiisi) uses dead-simple logic — follow allies, heal whichever is
damaged, no threat-prioritization — validating a simple proximity+cooldown Cultist
rather than complex targeting AI. Cross-genre consensus on telegraphing healers: a
strong always-on visual tell plus an audio/particle cue, which we approximate with
floating text + VFX since FMOD isn't wired up yet. Critics reward genuinely distinct
archetypes over palette-swap reskins — this validates one-subclass-per-archetype over
a shared parametrized class.

## Architecture

One new `.gd` subclass per new named variant (matches the existing `LungeEnemy` /
`SniperEnemy` precedent), plus matching `.tscn` scenes. Grunt needs no new file — it
**is** the existing `MeleeEnemy` baseline. Archer is a thin marker subclass of
`RangedEnemy` (own sprite set, kiting tweak only). No new `ProjectileBehavior`
subclasses are needed: `seeker_launcher_weapon.gd` (homing) and
`flame_lobber_weapon.gd` (arc AoE) already exist and are fully CSV/`WeaponRegistry`
driven.

Each archetype folds together: (a) stat multipliers relative to Grunt/Archer
baseline, (b) one AI sub-behavior pattern, (c) a wander mode, (d) a weapon pool drawn
from existing `weapons.csv` entries.

## Melee variants

| Variant | File | Stats (vs. Grunt: HP15, spd60) | Behavior pattern | Wander |
|---|---|---|---|---|
| **Grunt** | existing `melee_enemy.gd` | unchanged | baseline CHASE→WINDUP→ATTACK | patrol (persisted direction, occasional turns — existing wander) |
| **Brute** | `brute_enemy.gd` | HP 27 (1.8×), spd 42 (0.7×), dmg +30% | **rusher** — claims the attack commit from farther out (larger effective commit radius), no hesitation once in range; windup 1.3× longer (heavier tell) | stationary guard (minimal wander, holds position) |
| **Skirmisher** | `skirmisher_enemy.gd` | HP 9 (0.6×), spd 84 (1.4×), dmg −30% | **flanker** — during CHASE, offsets movement tangentially (±45–60°) around the player instead of straight-in, until inside a closer commit range, then attacks normally | random drift (frequent short-timer turns) |
| **Armored** | `armored_enemy.gd` | HP 21 (1.4×), spd 51 (0.85×), dmg unchanged, knockback ×0.25 | **ambusher** — does not wander, holds a guard spot until the player enters detection radius, then a heavier telegraphed windup (1.3×) | none (guard stance) |
| **Cultist** | `cultist_enemy.gd` | HP 12 (0.8×), spd 60, dmg −40% (weak fallback melee) | **support/follower** — stays within `heal_radius` (~100px) of the swarm via the existing `swarm_grid` query; on a `heal_cooldown` (~6s) heals the nearest wounded ally for ~20% of its max HP, showing a floating "Caw cawww" text bubble (reuses the existing "!" label/Tween pattern) plus a small heal-pulse VFX; falls back to normal melee if the player closes in and no ally needs healing | none (follows swarm, not independent) |

## Ranged variants

| Variant | File | Stats (vs. `RangedEnemy`: HP12, spd50, range180) | Behavior pattern | Weapon category |
|---|---|---|---|---|
| **Archer** | `archer_enemy.gd` (thin subclass, own sprite) | unchanged | **kiter** — reacts to closing distance earlier (1.3× preferred_distance) and retreats faster (1.2× speed while retreating) | straight/spread, aimed |
| **Mage** | `mage_enemy.gd` | HP 11 (0.9×), spd 30 (0.6×), range 220, windup 0.8s | **turret** — stops moving entirely once in range + LoS; only resumes on LoS break or range loss | homing/slow-caster |
| **Lobber** | `lobber_enemy.gd` | HP 13 (~1.0×), spd 45 (0.9×), range 200, windup 0.5s | **skirmisher-reposition** — immediately after firing, picks a new spot biased away from the player and relocates before re-engaging | arc/AoE lob |

## Weapon pooling

The existing spawn logic randomizes weapons independently of enemy type
(`_pick_melee_weapon()` rolls `rusty_sword`/`bone_dagger` 50/50; `_pick_ranged_weapon()`
rolls raw `AimedBurstWeapon`/`SplitShotWeapon`/`FanWeapon` classes, and
`ranged_enemy.gd`'s sprite selection currently infers archer/lobber texture from
*which weapon type got rolled*). Once archetypes are dedicated subclasses owning their
own sprite and movement AI, that inference direction is backwards. The fix: each
archetype gets its own weapon **pool** (to maximize per-instance variety), and picks a
weapon from CSV data by ID via `WeaponRegistry.get_weapon_by_id()` — the same
mechanism melee spawns already use, now extended to ranged spawns too.

### Melee pool — rule, not a hardcoded list

Every melee weapon in `weapons.csv` is evaluated against a small pure predicate at
pool-build time, so newly-added weapons auto-classify without touching spawn code:

| Archetype | Rule | Coverage (of 37 melee weapons) |
|---|---|---|
| Skirmisher | `cooldown <= 0.40` | 11 |
| Grunt | `0.40 <= cooldown <= 0.60 AND 26 <= reach <= 34` | 16 |
| Brute | `cooldown >= 0.60 OR damage >= 6.0` | 12 |
| Armored | `reach >= 34` | 17 |
| Cultist | `damage <= 3.0` | 14 |

All 37 Common/Uncommon/Rare melee weapons land in at least one pool (most in two);
boundary overlap between adjacent bands (e.g. a weapon qualifying for both Skirmisher
and Grunt) is intentional, not a bug.

### Ranged pool — explicit lists

No single numeric CSV axis captures "trajectory shape," so ranged pools are grouped
by archetype/script identity instead:

| Archetype | Pool | Why |
|---|---|---|
| Archer | `throwing_knife`, `frost_repeater`, `heavy_crossbow`, `spread_shot`, `scatter_blunderbuss`, `tesla_gun`, `arc_railgun`, `chakram_launcher` | straight-line/aimed, single or multi-shot, no arc or homing |
| Mage | `seeker_launcher`, `fire_orb` | `seeker_launcher` is true homing; `fire_orb` is a slow single caster orb, thematically paired |
| Lobber | `flame_lobber`, `venom_spitter`, `hailstorm_bow` | arc/AoE-lob delivery |

`boss_staff` is excluded — reserved for `BossEnemy`, already hardcoded there.

### Rarity weighting within a pool

Weapons drawn from these pools include Uncommon/Rare player-facing weapons with real
pre-attached modifiers, which would over-tune early floors if rolled uniformly. Roll
a rarity tier first, then uniform-pick a weapon ID from the archetype's pool filtered
to that tier.

**Base weights by floor** (Common / Uncommon / Rare):

| Floor | Common | Uncommon | Rare |
|---|---|---|---|
| 1–2 | 85% | 15% | 0% |
| 3–4 | 65% | 30% | 5% |
| 5+ | 50% | 35% | 15% |

**Modifiers on top of the base weights**, both shifting weight away from Common:

- **New** `EncounterDirector.kill_streak: int` field, range clamped to [-2, 4], +2 per
  kill (called from `Enemy.die()`), -1 per player hit (called from wherever the player
  currently registers taking damage), no decay. Note: an earlier design
  (`2026-06-12-aggressive-surround-and-dynamic-tokens-design.md`) added a similarly-shaped
  `aggression_delta` field for attack-token gating, but it was fully removed one day
  later by `2026-06-13-remove-attack-tokens-design.md` ("Remove Attack Tokens — Infinite
  Enemy Aggression") along with the rest of the token system. Nothing replaced it. This
  spec adds a new, narrowly-scoped `kill_streak` field for the rarity roll only — it
  does not reintroduce token gating or any attack-concurrency limit.
  When positive, `kill_streak` shifts **+2% to Rare** and **+1% to Uncommon** per point
  (e.g. at max +4: +8% Rare, +4% Uncommon, taken from Common).
- `SectorGrid.enemy_tier_for_distance(sector_dist)` (existing EASY/NORMAL/HARD
  tiering, i.e. distance toward the boss/arena edge): HARD shifts **+10% Rare / +5%
  Uncommon**; NORMAL shifts **+5% Rare / +3% Uncommon**; EASY unchanged.

All shifts are clamped so weights stay within [0, 1] and re-normalize before rolling.

## Cross-cutting behavior-depth items

- **Telegraph polish**: verify the "!" label draws above terrain/VFX (z-index/canvas
  layer check); standardize bounce-in/fade timing proportional to each archetype's
  `windup_duration`.
- **Separation steering tuning**: re-verify `separation_radius` (22px) /
  `separation_weight` (1.2) and crowd-overlap spacing against the new archetypes'
  collision radii — Brute and Armored read visually larger and may need larger
  per-body separation to avoid overlap/jitter in packs.
- **Wander variety**: satisfied by the per-archetype wander column above (patrol /
  stationary guard / random drift / none), implemented as per-subclass overrides of
  the base wander parameters (persist-time ranges, direction bias, or disabled).
- **Hurt reactions**: directional knockback already exists (`on_hit_impact` →
  `hit_dir` → `apply_knockback`), so this narrows to **elite stagger resistance**:
  elites take reduced knockback (~0.4× multiplier), stacking multiplicatively with
  Armored's own 0.25× if an Armored enemy rolls elite.

## Spawner integration

`spawn_dispatcher.gd` and `cave_spawner.gd`: replace the flat melee/ranged split with
weighted rolls across the 5 melee / 3 ranged archetypes (e.g. melee: grunt 40 / brute
15 / skirmisher 20 / armored 15 / cultist 10 — ranged: archer 45 / mage 25 / lobber
30). `SniperEnemy` keeps its existing separate roll, untouched. Each archetype scene
assigns its own weapon via the pool + rarity-weighting logic above, replacing
`_pick_melee_weapon()`'s flat 2-weapon roll and `_pick_ranged_weapon()`'s raw-class
roll entirely.

## Testing

- One unit test per new archetype verifying its stat overrides and signature
  behavior: `test_brute_enemy.gd`, `test_skirmisher_enemy.gd`, `test_armored_enemy.gd`
  (reduced knockback), `test_cultist_enemy.gd` (heals in-radius ally on cooldown,
  shows callout), `test_archer_enemy.gd` (kiting threshold), `test_mage_enemy.gd`
  (stops moving while firing), `test_lobber_enemy.gd` (repositions after firing).
- `test_weapon_pool_rules.gd`: verify the melee rule predicate covers all 37 CSV
  weapons in at least one pool, and the ranged explicit lists resolve to valid
  `WeaponRegistry` IDs.
- `test_enemy_rarity_weighting.gd`: verify weight table sums to 1.0 after floor +
  aggression + sector-tier modifiers at representative sample points (floor 1/no
  aggression/EASY; floor 5/+4 aggression/HARD).
- Extend `test_enemy_crowd.gd` / `test_enemy_wall_clamp.gd` if new collision radii
  (Brute, Armored) affect existing crowd/wall-clamp assertions.
