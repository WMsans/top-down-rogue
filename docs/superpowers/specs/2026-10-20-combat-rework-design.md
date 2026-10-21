# Combat Rework (Katana ZERO Offense / Soul Knight Defense) — Design

**Date:** 2026-10-20
**Scope:** Phase 0 "Combat Rework" in `docs/design_docs/implementation_todo2.md`. Rules live in `docs/design_docs/gameplay.md` §2 and §4; weapon/modifier text lives in `weapons.csv` / `modifiers.csv` (already rewritten, commit `10687382`).
**Status:** Approved design, ready for implementation plan.
**Supersedes:** `2026-06-24-weapon-modifier-balancing-design.md` Part A (DPS bands, effective-DPS model, crit) and every damage/crit magnitude in Part B/C. Its no-duplicate-effects rule and the slot-meta modifiers (mirror_slot, keystone, …) still stand.

---

## 1. Problem

Combat is HP-and-damage based: enemies have `max_health` (20 base, ×3 elite, ×2 TANK; boss 200), the player has 100 HP, and the whole build system is balanced on DPS and crit. The game is moving to:

- **Offense like Katana ZERO** — every hit is decisive. Normal enemies die in 1 hit, elites in 2.
- **Defense like Soul Knight** — the player has 3 HP + 3 regenerating armor.

Under one-hit kills, damage and crit stop meaning anything, so ~30 modifiers and ~19 weapons lose their purpose. This spec defines the new rules, the code interfaces that carry them, and the per-item rework.

## 2. Decisions

- **Every hit is exactly 1**, from any source: swing, projectile, explosion, lava, status tick. Nothing deals 2 hits — not charges, not combos.
- **No damage, no crit.** `damage` becomes `dig_power` (terrain only). `crit_chance`, `crit_multiplier`, `crit_status` are deleted.
- **Charge changes shape** (arc, reach, pierce, shockwave, pull, projectile), never hit count.
- **Player:** 3 HP, 3 armor. Hits and DoT ticks take armor first, then HP. HP never regenerates.
- **Enemies:** normal 1 hit, elite 2, TANK elite 3, boss 3 phases × 10 hits. Elites and bosses share a **0.3s** post-hit invulnerability.
- **Enemies have no damage stat.** Every enemy hit costs the player 1 point. Difficulty comes from behavior.
- **Weapons are balanced on three axes:** Coverage, Tempo, Utility. Rarity buys behavior, not numbers.
- **Chance-based effects** state their odds; Executioner's Mark adds +1/4 to every chance on its weapon (additive, capped at 1).
- **Item ids are stable.** Renames are display-name only (`thunder_katana` → "Katana", `twin_daggers` → "Jack and Mary").

> **Pre-playtest numbers.** Every number not fixed in §2 (radii, durations, buff sizes) is a tuning starting point.

---

## Part A — Player Defense

### A1. `PlayerInventory` model (`src/player/player_inventory.gd`)

| Field | Value |
|---|---|
| `max_health` | 3 (was 100) |
| `max_armor` | 3 (new) |
| `invincibility_duration` | 1.0s (unchanged) |
| `ARMOR_REGEN_DELAY` | 3.0s |
| `ARMOR_REGEN_INTERVAL` | 1.0s |

New signal `armor_changed(current: int, maximum: int)`. `health_changed`, `damaged`, `player_died` keep their signatures.

**Point loss** — one private helper used by both paths:

```
_lose_point():
    if armor > 0: armor -= 1; armor_changed.emit(...)
    else:         health -= 1; health_changed.emit(...)
    _regen_timer = 0.0          # restarts the 3s delay
    damaged.emit(1)
    if health <= 0: die
```

- `take_damage(amount, hit_direction)` → `take_hit(hit_direction)`. Ignored while invincible. Calls `_lose_point()` once, starts i-frames, plays the existing hit reaction. `amount` is dropped; enemy callers stop passing damage.
- `take_status_damage(amount)` → `take_status_tick()`. Bypasses i-frames, no heavy hit reaction, calls `_lose_point()`.
- **Regen** in `_process`: `_regen_timer += delta`; once `≥ ARMOR_REGEN_DELAY`, add 1 armor every `ARMOR_REGEN_INTERVAL` until full.
- `heal(amount)` keeps its signature; heals whole HP points, clamped to `max_health`.
- `set_max_armor(value)` clamps current armor down; raising max does not grant armor (it regenerates).
- `get_health_fraction()` stays (HP only). Add `get_armor()`, `get_max_armor()`, `skip_armor_regen_delay()` (for vampiric).

### A2. Status ticks on the player (`src/status/status_component.gd`, `src/autoload/status_registry.gd`)

Today burn and poison share one `_burn_accum` driven by `burn_dps` (on_fire 4.0, poisoned 2.0, steam 3.0). Replace with **per-status tick intervals**:

| Status | Tick interval |
|---|---|
| on_fire | 1.0s |
| poisoned | 1.5s |
| steam | 1.0s |

Each active ticking status keeps its own timer; each tick calls the owner's `apply_status_damage(1)` (player → `take_status_tick()`, enemy → one hit). Rename `burn_dps` in `StatusDef` to `tick_interval` (0 = does not tick). Player-side stain decay is tuned so a typical burn lasts ~2 ticks. `burn_tick` signal stays.

### A3. Lava

Lava currently reaches the player only as On Fire stain. `LavaDamageChecker` (`src/player/lava_damage_checker.gd`, currently a no-op) becomes active: while any body sample point is in lava, call `take_hit(Vector2.ZERO)`. I-frames (1.0s) give ~1 point per second. Lava still applies On Fire stain as today.

### A4. Healing sources

Only three sources restore HP:

1. **Boss kill** — +1 HP and full armor (hook in `boss_enemy.gd` death).
2. **Mend** shop service — Part G.
3. **Reaper's Glaive** — 1/10 chance per kill, +1 HP.

`data_modifier.gd:198` (`inv.heal(int(magnitude))`, the old vampiric path) is removed; vampiric becomes `skip_armor_regen_delay()`.

---

## Part B — Enemy Hit Model

### B1. `Enemy` (`src/enemies/enemy.gd`)

| Old | New |
|---|---|
| `max_health: int = 20`, `health` | `max_hits: int = 1`, `hits_remaining` |
| `_apply_elite_scaling()` ×3 HP, TANK ×2 | elite `max_hits = 2`, TANK `max_hits = 3` |
| `_apply_damage_scale()` | removed |
| `hit(damage)` | `take_hit()` |
| `apply_status_damage(amount)` | one hit per call |
| `health_changed(current, max)` | `hits_changed(remaining, max)` |

- `take_hit()`: if `_hit_invuln_timer > 0` → ignore. Else `hits_remaining -= 1`, emit, die at 0. If `max_hits > 1`, set `_hit_invuln_timer = HIT_INVULN = 0.3` and play stagger + flash.
- Creative mode keeps instant kill (`hits_remaining = 0`).
- `on_hit_impact(impact_point, hit_dir, damage)` drops `damage`; `lethal` = `hits_remaining <= 1`.
- **ENRAGE** triggers on the first hit taken (was `< 30%` HP).
- **Enemy attacks** call `player.on_hit_impact(point, dir)` with no damage. Remove damage fields from enemy weapons/projectiles; enemy projectile hit = 1 player hit.
- Elite `1.3×` speed stays. FAST / TELEPORT unchanged.

### B2. `BossEnemy` (`src/enemies/boss_enemy.gd`)

- `max_hits = phase_count × HITS_PER_PHASE` (3 × 10). Shares `HIT_INVULN = 0.3`.
- `_phase_threshold(p)` becomes hit-count based: phase `p` begins when `hits_remaining <= HITS_PER_PHASE × (phase_count − p + 1)`. The existing `while` loop already prevents skipped phases.
- `_transition_phase()` also clears the boss's `StatusComponent`.
- Status ticks count as hits.

### B3. Difficulty

`EnemyTier` EASY / NORMAL / HARD stop scaling stats. They become behavior profiles (telegraph length, attack cadence, projectile count) — tuned in Phase 1, not here. Phase 0 only removes the stat scaling and leaves current behavior identical across tiers.

### B4. Statuses on enemies

Unchanged application. A tick = 1 hit, so on_fire / poisoned / steam kill normal enemies on the first tick and finish elites on the second. Non-ticking statuses (wet, oiled, chilly, frozen, bloody, stun, lightning) keep their current control/reaction behavior.

---

## Part C — Damage → Dig Power, Crit Removal

### C1. `dig_power`

`melee_weapon.gd` already carves with `_solid_carve_strength(dmg)` where `dmg` is the swing damage. The rename keeps that behavior:

- CSV column `damage` → `dig_power`; `Weapon.damage` → `Weapon.dig_power`; `weapon_registry.gd` reads the new column.
- `eff["damage"]` → `eff["dig_power"]` in effective-stat aggregation; `stat_add`/`stat_mult` targeting `damage` retarget to `dig_power`.
- `resolve_hit(user, node, damage * dmg_mult, is_crit)` → `resolve_hit(user, node)`. Per-move `damage_mult` in combo data scales dig only.
- Ranged/projectile hits carry no damage.
- `terrain_modifier.gd:601` `damage` param (used for destructible terrain/props) becomes `dig_power`.

**Dig values** (re-assigned by archetype, starting points): dagger/rapier/twin 1.5, sword 3, axe/mace/greatsword 5, hammer 7, Gravedigger's Spade and Obsidian Greatsword 9 (plus `free_carve`).

### C2. Crit removal

Delete from `weapon.gd`, `melee_weapon.gd`, `ranged_weapon.gd`, `projectile.gd`, `chain_behavior.gd`, `modifier.gd`, `data_modifier.gd`, `weapon_registry.gd`, `weapon_drop.gd`: all `crit_chance`, `crit_multiplier`, `crit_status`, `is_crit` plumbing and the crit clamp. Weapons that used `crit_status` move it to `hit_status` (Flame Sword `on_fire`, Frost Sword `chilly`, Tide Caller `wet`); the rest get their new trait (Part D). The three CSV columns are dropped.

### C3. Damage numbers

`hit_reaction.gd` floating damage numbers are removed. Kills, elite first hits and boss hits use flash + stagger + hit-stop only.

---

## Part D — Weapons

Descriptions in `weapons.csv` are the source of truth. Implementation per weapon:

| Weapon (id) | Behavior to implement |
|---|---|
| Fire Orb (`fire_orb`) | On impact: 1 hit to every enemy within 24px. |
| Willowblade (`willowblade`) | Full-charge thrust spawns a piercing blade-wave projectile (speed 200, lifetime 0.35s). |
| Flame Sword (`flame_sword`) | `hit_status = on_fire`; keeps pre-attached lava_emitter. |
| Frost Sword (`frost_sword`) | `hit_status = chilly`. |
| Heavenly Sword (`heavenly_sword`) | On kill: apply chilly stain to enemies within 32px. |
| Glacier Edge (`glacier_edge`) | On hit: if target is chilly, apply frozen; else apply chilly. |
| Tide Caller (`tide_caller`) | `hit_status = wet`. |
| Cinder Brand (`cinder_brand`) | On kill: apply on_fire to enemies within 32px. |
| Caliburn (`caliburn`) | Swing counter; every 3rd swing also fires a piercing sword-beam projectile (speed 220, lifetime 0.4s). |
| Katana (`thunder_katana`) | Each swing dashes the player 40px along the aim (reuse player dash velocity). A kill during the dash resets the cooldown. |
| Rapier (`rapier`) | Thrust hits every enemy in a narrow line (reach × 8px). |
| Iron Mace (`iron_mace`) | On hit: apply `stun`. High dig. |
| Obsidian Greatsword (`obsidian_greatsword`) | Highest dig, `free_carve` (already set). No combat trait. |
| Jack and Mary (`twin_daggers`) | The two AUTO_FLURRY passes aim front and back (second pass direction rotated 180°). |
| Reaper's Glaive (`reaper_glaive`) | On kill: 1/10 chance `inv.heal(1)` via the chance helper (E1). |
| Berserker's Axe (`berserker_axe`) | Cooldown × (1 − 0.15 × missing armor) → −45% at 0 armor. HP has no effect. |
| Soul Reaver (`soul_reaver`) | Kills stack +5% reach and +5% arc (max 6 stacks); stacks clear 3s after the last kill. |
| Arc Railgun (`arc_railgun`) | Charge fraction scales beam length (1×→2×) and width (1×→2×). |
| Scatter Blunderbuss, Bone Dagger, Broad Axe, Spread Shot, Grand Knight's Sword, Bone Cleaver, Venom Fang Blade, Frost Repeater | Text-only changes; no behavior change. |

All other weapons are unchanged apart from Part C.

---

## Part E — Modifiers

Descriptions in `modifiers.csv` are the source of truth. Modifiers are weapon-tied: their effects apply while that weapon is the active weapon (glass_cannon's −2 max armor included).

### E1. Shared infrastructure

- **Chance helper** — `Weapon.roll_chance(base: float) -> bool` returns `randf() < minf(base + chance_bonus, 1.0)`. `chance_bonus` is the sum of +0.25 per Executioner's Mark on the weapon. Every chance below, and every weapon chance, goes through it.
- **On-kill hook** — `data_modifier.gd` already dispatches `trigger = on_kill` (stat_add damage stacks, heal, bounty). Keep that dispatch, drop the damage-stack and heal branches, and pass the killed target so on-kill effects can read its statuses and position.
- **Timed player buffs** — `PlayerBuffs` (component on the player) holding `{stat: [multiplier, remaining]}` for `reach`, `swing_speed`, `move_speed`, `dig_power`. Refreshing a buff resets its timer; same-stat buffs do not stack. Effective-stat aggregation reads it.
- **New `modifiers.csv` column `chance`** (0–1, empty = always) so chance-based data modifiers don't need scripts.

### E2. Per-modifier behavior

| Modifier | Trigger | Behavior |
|---|---|---|
| sharpened | passive | `stat_add dig_power +3` |
| heavy_head | on_hit / passive | apply `stun` + knockback ×2; `stat_mult cooldown ×1.25` |
| honed_point | passive | `stat_mult projectile_speed ×1.3`, `projectile_lifetime ×1.3` |
| executioners_mark | passive | `chance_bonus += 0.25` |
| combo_keeper | on_kill | kill streak (kills ≤2s apart); every 5th streak kill → knockback shockwave r=48px dealing 1 hit |
| chain_spark | on_kill | chance 1/4: lightning arc to up to 3 enemies within 64px, each 1 hit + existing stun chance |
| hemophilia | on_kill | if target bloody, chance 1/5: 1 hit to enemies within 24px |
| frostbreaker | on_hit | if target chilly/frozen: apply chilly to enemies within 32px |
| pyroclast | on_kill | if target on_fire, chance 1/10: spawn fire material patch at target |
| coup_de_grace | on_kill / on_phase | landing an elite's last hit or ending a boss phase: reset cooldown, +1 armor |
| bloodlust | on_kill | +8% swing speed per kill (max 5), clears 3s after last kill |
| rampage | on_hit | +5% reach per consecutive hit (max +30%); a swing that hits nothing resets |
| glass_cannon | passive | max armor −2; swing speed ×1.4; `reach ×1.3` |
| vampiric | on_kill | `inv.skip_armor_regen_delay()` |
| momentum | passive | swing speed + (speed / max_speed) × 30% |
| adrenaline | on armor break | when armor goes 1→0: `move_speed ×1.4` for 2s |
| greedy_edge | passive | reach +1% per 50 gold (max +40%) |
| last_stand | on player hit | next swing: chance 1/2 to emit knockback shockwave r=48px (no hit) |
| overkill | on_kill | spawn piercing shard in swing direction (speed 200, lifetime 0.3s) |
| headsman | on_kill | refund 50% of remaining cooldown |
| slot_harmony | passive | swing speed ×1.2 while 3 slot categories differ |
| combustion | on_hit | if target on_fire: clear it, buff `reach ×1.3` 1s |
| necrosis | on_hit | if target poisoned: clear it, buff `swing_speed ×1.3` 1s |
| frostshatter | on_hit | if target frozen: clear it, buff `move_speed ×1.3` 1s |
| rupture | on_hit | if target bloody: clear it, buff `dig_power ×1.5` 1s |
| rending_edge, keystone | — | text-only |

"Swing speed ×X" means `cooldown ÷ X`. All cooldown changes respect the existing `COOLDOWN_FLOOR = 0.1`.

---

## Part F — HUD

`src/ui/hud.gd` currently draws a health bar (`%BarFill`, `%HealthLabel`). Replace with two icon rows in the same top-left cluster: hearts (HP, from `health_changed`) and shields (armor, from `armor_changed`). Icon count follows max values. A shield refilling plays a short pop. Boss bar (Phase 3 task) becomes segmented by hits — out of Phase 0.

---

## Part G — Mend Service

A shop stall next to the removal service (`src/economy/shop_removal.gd` pattern): restores 1 HP. `mend_cost = 40 + 25 × uses` (per run, starting value). Disabled at full HP. Uses the existing affordability feedback.

---

## 3. Testing

Update or delete tests built on HP/damage/crit: `test_player_health_fraction`, `test_weapon_crit`, `test_weapon_crit_csv`, `test_weapon_balance`, `test_charge_weapon_ratio`, `test_boss_phase_transition`, `test_modifier_stacking`, `test_weapon_resolve_hit`, `test_melee_resolve_hit`, `test_weapon_effective_stats`, `test_csv_weapon_data`, `test_poisoned_status`, `test_status_component`, and any test calling `hit(damage)` / `take_damage(amount)`.

New tests:

- Armor absorbs hits before HP; DoT ticks bypass i-frames; regen waits 3s then +1/s; any hit/tick resets the delay.
- `set_max_armor` clamps; glass_cannon lowers max armor only while active.
- Enemy hit counts (1/2/3), 0.3s invulnerability, ENRAGE on first hit.
- Boss phase advances on hit count without skipping; transition clears statuses.
- Status ticks: per-status intervals; one tick kills a normal enemy.
- `roll_chance` with 0/1/2 Executioner's Marks, capped at 1.
- `dig_power` drives carve strength exactly as `damage` did.
- Each Part D weapon trait and each Part E modifier with a behavior change.

Two pre-existing failures (`test_pre_attached_modifier_applied`, `test_flame_sword_has_lava_emitter`) fail on `master` before this work. Fix or explain them in the first plan task so the suite starts green.

## 4. Implementation order

1. **Core rules** — Part A (A1–A3), Part B, Part C, Part F. The game is playable with the new rules; weapon/modifier traits still behave as before minus damage/crit.
2. **Infrastructure** — E1 (chance helper, on-kill hook, PlayerBuffs, `chance` column), A4, Part G.
3. **Content** — Part D weapons, then Part E modifiers.

Each step leaves the test suite green.

## 5. Out of scope

- Phase 1 tuning (behavior profiles, boss pools per boss, axis audit).
- Chinese CSV resync.
- New enemies, elite abilities SHIELD / SUMMONER, boss bar.
