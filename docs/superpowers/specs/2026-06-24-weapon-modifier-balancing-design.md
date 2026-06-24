# Weapon & Modifier Balancing — Design

**Date:** 2026-06-24
**Scope:** All 6 "Weapon Balance" rows + all 7 "Modifier Balance" rows in `docs/design_docs/implementation_todo2.md` (Phase 1), **plus** a new modifier **Resonance & Catalyst** system (Part C) that adds a nonlinear power ceiling.
**Status:** Approved design, ready for implementation plan.
**Companion to:** `2026-06-20-economy-balancing-design.md` (same Phase-1 balancing pass).

---

## 1. Problem

Two problems, one spec because they're coupled (weapons carry pre-attached modifiers; both share the effective-DPS frame).

**Weapons** — current effective DPS (damage × avg-crit × archetype-hits ÷ cooldown) shows the rarity bands are violated and **tiers are compressed**:

- Several **Commons exceed the Common band** and out-DPS Rares: `flame_blade` 12.5, `tao_sword` 9.2, `broadsword` 9.1 vs Rare `berserker_axe`/`soul_reaver` at 10.0.
- **Outliers:** `dragon_fang` **32.7** (Uncommon — 3 auto-thrusts × 6 dmg), `caliburn` 18.4, `thunder_katana` 14.2, `phantom_blade` 14.0, `twin_daggers` 12.9.
- **Ranged is on a different (lower) nominal scale** — 1.1–5.0 single-projectile DPS — because the per-shot numbers ignore projectile count / pierce / chain. Needs its own effective model.

**Modifiers** — the 57 modifiers are *mostly* in a reasonable solo range, but they are **flat and non-interacting**. Power scales linearly (+3 dmg, +15% crit, ×1.5 conditional). There is no build-craft, so the player's curve is a straight line — which makes future enemy balancing a treadmill rather than a set of interesting walls.

## 2. Goals & decisions

- **Weapon bands (effective single-target DPS):** Common **5–8**, Uncommon **7–11**, Rare **9–14**. Utility/status/AoE weapons sit at the **low end** of band (they pay for the utility).
- **Ranged premium:** ranged target = melee × **0.82** (safety premium). Multi-projectile/pierce/chain/AoE is a *trait tax* (sit low in band) — not a license to multiply single-target burst.
- **Effective-DPS normalization:** all bands measured as `damage × (1 + crit·(critMult−1)) × hits_per_activation ÷ cooldown`, where `hits_per_activation` is a **per-archetype single-target multiplier** (§A1).
- **Cooldown preserved:** re-tune solves for **damage at fixed cooldown** — cooldown defines a weapon's feel/identity; we don't churn it.
- **Modifier solo bands describe the NO-RESONANCE state.** Resonance/catalysts (Part C) are a deliberate ceiling *above* band.
- **Combos are A LOT stronger than band.** This is the design intent: a naked loadout = linear floor; an assembled tag/catalyst build = multiplicative spike (Balatro philosophy). The Part C "cap" (§C5) exists only to kill *infinite/degenerate loops*, **not** to cap finite combo power.
- **Status magnitudes are NOT retuned** — `apply_status` mods keep their current `2.0` stain (near-instant trigger). B5 becomes verify-thresholds-only.
- **Caps already exist:** `weapon.gd` has `COOLDOWN_FLOOR = 0.1` (`maxf` at aggregation) and crit `clampf(0,1)`. The stacking row is verification + tests, not new code.
- **Unit tests are in scope** (§7).
- **Phased implementation:** Phase 1 = baseline re-tune (A+B). Phase 2 = resonance/catalyst layer (C). Floor ships independent of ceiling.

> **Pre-playtest estimates.** Like the economy spec, every number here is a tuning *starting point* anchored to the bands above, not a final value. The bands and the per-archetype taxes are the knobs to turn once real data exists.

---

## Part A — Weapon Balance

### A1 — Effective-DPS model (the spine)

```
effective_dps = damage × (1 + crit_chance·(crit_multiplier − 1)) × hits_per_activation ÷ cooldown
```

`hits_per_activation` = single-target effective hits per cooldown. Derived from archetype scripts:

| Archetype pattern | Examples | Mult | Rationale |
|---|---|---|---|
| Single swing / TAP_CHAIN combo | most melee, all combo weapons | **1.0** | combo spans *multiple* cooldowns; each tap = 1 hit |
| AUTO_FLURRY | `dragon_fang` (3 thrusts), `twin_daggers` (2) | **3.0 / 2.0** | one activation auto-fires N moves into one target |
| Double-pass projectile | `chakram_launcher` (out + back) | **2.0** | hits same target twice |
| Multi-projectile-on-target | `spread_shot` (2), `scatter_blunderbuss` (4), `hailstorm_bow` (2.5) | **2–4** | expected pellets landing on one clustered target |
| Single projectile / pierce / homing / chain | `throwing_knife`, `heavy_crossbow`, `tesla_gun`, `seeker_launcher` | **1.0** | pierce/chain is multi-*target* (a trait tax), not single-target burst |

> **Implementation must verify each multiplier against the archetype script.** These are derived from descriptions + a code scan; the plan confirms exact move counts and per-move `damage_mult`.

### A2 — Rarity-to-power curve (melee anchor)

Mid-band targets used by the re-tune: Common **6.5**, Uncommon **9.0**, Rare **11.5** effective DPS. A per-weapon **trait tax** (§A4) scales the target down for AoE/utility/sustain/pre-attached-emitter weapons.

### A3 — Melee vs ranged

Ranged mid-band target = melee × **0.82**: Uncommon **7.4**, Rare **9.4**. Projectile multipliers from §A1 fold in so per-projectile damage stays sane. **Projectile lifetime tuning** (implementation): set lifetimes so shots reach typical engagement range (~1.5–2.5 s) without becoming infinite-range lasers — re-check the ranged AoE/pierce weapons against *crowds* in playtest (single-target band can understate crowd clear).

### A4 — Archetype power budget (trait tax)

Each weapon's target DPS = band × tax. Tax pays for native traits:

| Tax | Applies to | Why |
|---|---|---|
| **1.00** | clean single-target melee (`rusty_sword`, `iron_mace`, `rapier`, `venom_fang_blade`, `thunder_katana`, `blood_blade`, `qinggang`) | no extra trait |
| **0.95** | mild AoE / crit-status / combo (`broad_axe`, `frost_sword`, `tao_sword`, combos, `tide_caller`, `cinder_brand`, `glacier_edge`) | small bonus |
| **0.90** | wide-arc / pull / terrain / pre-attached emitter (`broadsword`, `cleaver`, `void_sword`, `caliburn`, `obsidian_greatsword`, `flame_blade`, `flame_sword`, `mirror_blade`, `gravedigger_spade`, `heavenly_sword`, `dragon_fang`) | real utility |
| **0.85** | sustain / ramp / full-AoE / pierce-ranged (`reaper_glaive`, `berserker_axe`, `whirlwind_blade`, `quake_hammer`, `soul_reaver`, `heavy_crossbow`, `scatter_blunderbuss`, `arc_railgun`, `venom_spitter`) | strong trait |
| **0.80** | full-surround / chain / volley (`war_scythe` 300°, `tesla_gun` chain, `flame_lobber` AoE+emitter, `hailstorm_bow` volley) | dominant trait |

### A5 — Pre-attached modifier valuation

Each pre-slotted modifier costs the weapon a stat penalty, **already folded into the 0.90 tax** for `flame_blade`/`flame_sword`/`flame_lobber` (each carries `lava_emitter`). Rule for any future pre-attached weapon: **−1.0 dmg or +0.05 s cooldown per pre-attached Common; −1.5/+0.07 for Uncommon+.** `flame_blade` is the poster child: 12.5 → **6.2** DPS (Common band) *and* it pays the emitter tax.

### A6 — Charge weapons

`willowblade`, `executioner`, `void_sword`, `quake_hammer`, `blood_blade`, `arc_railgun`. The **tap** swing is balanced to band (table below). Implementation tunes the **charged release** so: charged damage = **1.8–2.5×** an equivalent tap swing, and charge time is set so charge-DPS ≈ tap-DPS (burst, not free power). Verified per-weapon against the archetype's charge move.

### A7 — Full weapon re-tune table (51 weapons)

`damage` solved for the band target at the existing cooldown; rounded to 0.5. `newDPS` = resulting effective DPS.

**Melee — Common (band 5–8)**

| id | dmg → new | cd | newDPS |
|---|---|---|---|
| rusty_sword | 3.0 → 3.0 | 0.5 | 6.0 |
| bone_dagger | 2.0 → 1.5 | 0.25 | 6.0 |
| broad_axe | 6.0 → 4.5 | 0.7 | 6.4 |
| broadsword | 5.0 → 3.0 | 0.55 | 5.5 |
| cleaver | 4.0 → 3.0 | 0.5 | 6.0 |
| flame_blade* | 5.0 → 2.5 | 0.4 | 6.2 |
| gravedigger_spade | 4.5 → 3.5 | 0.6 | 5.8 |
| iron_mace | 6.0 → 4.5 | 0.7 | 6.4 |
| tao_sword | 6.0 → 4.0 | 0.65 | 6.2 |
| willowblade | 3.0 → 2.5 | 0.42 | 6.0 |

**Melee — Uncommon (band 7–11)**

| id | dmg → new | cd | newDPS |
|---|---|---|---|
| cinder_brand | 3.5 → 2.5 | 0.4 | 7.8 |
| dragon_fang | 6.0 → 1.5 | 0.55 | 8.2 |
| executioner | 6.5 → 5.0 | 0.6 | 8.3 |
| flame_sword* | 3.5 → 3.0 | 0.4 | 8.6 |
| frost_sword | 3.5 → 3.0 | 0.4 | 8.6 |
| glacier_edge | 4.0 → 3.5 | 0.5 | 8.4 |
| heavenly_sword | 6.5 → 4.5 | 0.65 | 8.0 |
| mirror_blade | 4.0 → 3.5 | 0.45 | 7.8 |
| rapier | 2.5 → 2.0 | 0.3 | 8.7 |
| tide_caller | 3.5 → 3.5 | 0.45 | 8.9 |
| twin_daggers | 1.8 → 1.0 | 0.28 | 7.1 |
| venom_fang_blade | 2.5 → 3.0 | 0.32 | 9.4 |
| void_sword | 6.0 → 4.5 | 0.58 | 7.8 |
| war_scythe | 5.0 → 4.5 | 0.62 | 7.3 |
| whirlwind_blade | 4.5 → 4.0 | 0.55 | 7.3 |

**Melee — Rare (band 9–14)**

| id | dmg → new | cd | newDPS |
|---|---|---|---|
| berserker_axe | 6.0 → 6.0 | 0.6 | 10.0 |
| blood_blade | 4.0 → 4.0 | 0.35 | 11.4 |
| caliburn | 7.5 → 4.0 | 0.55 | 9.8 |
| deep_dark_blade | 8.5 → 7.5 | 0.7 | 10.7 |
| grand_knight_sword | 8.0 → 7.5 | 0.7 | 10.7 |
| obsidian_greatsword | 9.5 → 8.0 | 0.85 | 10.4 |
| phantom_blade | 7.0 → 5.5 | 0.5 | 11.0 |
| qinggang_sword | 4.5 → 4.5 | 0.38 | 11.8 |
| quake_hammer | 9.5 → 8.5 | 0.85 | 10.0 |
| reaper_glaive | 6.0 → 5.5 | 0.55 | 10.0 |
| soul_reaver | 5.0 → 5.0 | 0.5 | 10.0 |
| thunder_katana | 4.0 → 3.0 | 0.38 | 10.7 |

**Ranged — Uncommon (band ~6–9, ×0.82)**

| id | dmg → new | cd | newDPS | mult |
|---|---|---|---|---|
| chakram_launcher | 3.5 → 4.0 | 1.2 | 6.7 | 2.0 |
| fire_orb | 4.0 → 11.0 | 1.5 | 7.3 | 1.0 |
| flame_lobber* | 3.0 → 9.0 | 1.5 | 6.0 | 1.0 |
| frost_repeater | 1.8 → 4.5 | 0.6 | 7.5 | 1.0 |
| heavy_crossbow | 5.0 → 7.5 | 1.2 | 6.2 | 1.0 |
| scatter_blunderbuss | 1.5 → 2.0 | 1.4 | 5.7 | 4.0 |
| spread_shot | 2.0 → 4.0 | 1.2 | 6.7 | 2.0 |
| throwing_knife | 3.0 → 7.5 | 1.0 | 7.5 | 1.0 |
| venom_spitter | 2.5 → 8.0 | 1.3 | 6.2 | 1.0 |

**Ranged — Rare (band ~7.5–11, ×0.82)**

| id | dmg → new | cd | newDPS | mult |
|---|---|---|---|---|
| arc_railgun | 8.0 → 13.0 | 1.6 | 8.1 | 1.0 |
| boss_staff | 3.0 → 9.5 | 1.0 | 9.5 | 1.0 |
| hailstorm_bow | 2.5 → 4.0 | 1.4 | 7.1 | 2.5 |
| seeker_launcher | 4.0 → 12.5 | 1.5 | 8.3 | 1.0 |
| tesla_gun | 3.0 → 8.5 | 1.1 | 7.7 | 1.0 |

`*` carries a pre-attached `lava_emitter` (§A5). **Single-projectile ranged with high per-shot damage** (`fire_orb`, `throwing_knife`, `boss_staff`, `seeker_launcher`, `arc_railgun`) — verify `projectile_count` in the script; if any fire >1 projectile, fold that into `mult` and re-solve (their per-shot numbers assume exactly one projectile on target).

---

## Part B — Modifier Balance

### B1 — Per-category magnitude bands

`magnitude` means something different per category, so the audit is keyed **by category × rarity**:

| Category | `magnitude` is | Rule |
|---|---|---|
| `stat` | the stat delta | Common ≈ +3 dmg / ×1.3 util; Uncommon ≈ +15% crit / ×0.8 cd; Rare ≈ strongest single stat |
| `trigger` (conditional) | damage multiplier | **≥ 1.5×** payoff for its condition |
| `trigger` (ramp/kill) | per-stack + cap | total bonus pays off without unbounded snowball |
| `projectile` | projectile count | **costed as bonus DPS** — count × proj-dmg must fit rarity budget |
| `emitter` | blob radius | hazard (lava/gas/coal) ≤ 16; neutral (water/oil/blood/dust/ice) ≤ 24 |
| `status` | stain per hit | **not retuned** (kept at current values per decision) |
| `utility` | effect strength | flat per-rarity, no DPS contribution |

### B2 — Full modifier audit (57 modifiers)

Most are already in-band; the audit confirms values, assigns **resonance tags** (Part C), and changes only the flagged few. `tags` is a new CSV column (§C1).

| id | rarity | cat | mag / mg2 | tags | change |
|---|---|---|---|---|---|
| lava_emitter | C | emitter | 16 | fire | keep |
| green_crescent | U | projectile | 1 | projectile | keep |
| fireball_fan | C | projectile | 5 | fire, projectile | **count 5 → 3** |
| icicle_volley | C | projectile | 5 | ice, projectile | **count 5 → 3** |
| gleaming_projectile | U | projectile | 1 | projectile | keep |
| lightning_bolt | R | projectile | 1 | lightning, projectile | keep |
| arc_volley | R | projectile | 7 | projectile | keep |
| triangular_volley | R | projectile | 13 | projectile | keep |
| bouncing_bullets | U | projectile | 4 | projectile, kinetic | keep |
| splitting_rounds | U | projectile | 3 / 4 | projectile | keep |
| penetrating_shockwave | R | projectile | 1 | projectile, kinetic | keep |
| oil_emitter | C | emitter | 24 | oil | keep |
| water_emitter | C | emitter | 24 | water | keep |
| gas_emitter | U | emitter | 20 | poison | **radius 20 → 16** |
| frost_emitter | U | emitter | 18 | ice | keep |
| blood_emitter | C | emitter | 20 | blood | keep |
| coal_seeder | U | emitter | 12 | fire, earth | keep |
| dust_veil | C | emitter | 20 | earth | keep |
| venom_edge | C | status | 2.0 | poison | keep |
| soaking_strike | C | status | 2.0 | water | keep |
| greased_edge | C | status | 2.0 | oil | keep |
| frostbite_edge | U | status | 2.0 | ice | keep |
| ember_edge | U | status | 2.0 | fire | keep |
| rending_edge | C | status | 2.0 | blood | keep |
| sharpened | C | stat | 3 | power | keep |
| heavy_head | C | stat | 5 / 1.25 | power | keep |
| honed_point | U | stat | 0.15 | crit | keep |
| executioners_mark | U | stat | 0.5 | crit | keep |
| quickdraw | U | stat | 0.8 | power | keep |
| long_reach | C | stat | 1.3 | power | keep |
| wide_arc | C | stat | 1.4 | power | keep |
| deep_cut | U | stat | 1.8 | earth | keep |
| fleetfoot | U | stat | 1.15 | power | keep |
| frostbreaker | U | trigger | 1.6 | ice | keep (≥1.5) |
| pyroclast | U | trigger | 1.5 | fire | keep (≥1.5) |
| coup_de_grace | U | trigger | 2.0 / 0.3 | power | keep |
| bloodlust | R | trigger | 1 / 8 | power | keep |
| rampage | R | trigger | 1 / 6 | power | keep |
| glass_cannon | R | trigger | 1.8 | power | keep |
| vampiric | U | trigger | 3 | blood | keep |
| momentum | U | trigger | 1.5 | kinetic | keep |
| adrenaline | R | trigger | 0.6 | power | keep |
| combo_keeper | U | trigger | 1.0 / 5 | crit | keep |
| homing_hex | U | projectile | 1 | projectile | keep |
| chain_spark | R | projectile | 3 | lightning, projectile, crit | keep |
| ricochet_shard | U | projectile | 1 / 3 | projectile, kinetic | keep |
| piercing_lance | U | projectile | 1 | projectile | keep |
| cluster_bomb | R | projectile | 8 | fire, projectile | keep |
| boomerang_arc | U | projectile | 1 | projectile, kinetic | keep |
| spectral_echo | R | projectile | 1 | projectile | keep |
| tunnel_borer | U | terrain | 32 | earth | keep |
| shockwave_stomp | U | utility | 40 | kinetic | keep |
| magnet_field | C | utility | 48 | greed, kinetic | keep |
| repulsor_nova | R | utility | 80 | kinetic | keep |
| concussive_edge | U | trigger | 0.5 / 0.2 | kinetic | keep |
| midas_touch | U | utility | 5 | greed | keep |
| steam_burst | R | trigger | 3 | water, fire | keep |

Only **3 changes**: `fireball_fan` and `icicle_volley` drop 5 → 3 projectiles (Common free-DPS cap — both fire on every swing and stack onto fast weapons), and `gas_emitter` 20 → 16 (hazard radius cap). Everything else is confirmed in-band; the real modifier work is the resonance layer.

### B3 — Conditional payoff

All four named conditionals already pay ≥1.5× (`frostbreaker` 1.6, `pyroclast` 1.5, `coup_de_grace` 2.0, `glass_cannon` 1.8). Verify-only. Document each condition's setup cost so the payoff is earned.

### B4 — Emitter blob sizing

Audit the 8 radii against (a) player pathing and (b) sim cost ∝ radius². **Hazard tier (lava 16, gas 16↓, coal 12) ≤ 16; neutral tier (water/oil 24, blood/dust 20, ice 18) ≤ 24.** Only `gas_emitter` moves (20 → 16).

### B5 — Status stack thresholds (verify-only)

`StatusDef` constructor is `(…, decay_rate, active_threshold, …)`. The todo's thresholds **match `active_threshold` exactly**: on_fire 1.0, wet 1.0, oiled 1.0, chilly 1.0, frozen 3.0, poisoned 0.3, bloody 1.0. **No discrepancy, no magnitude retune** — `apply_status` mods keep `2.0` stain (near-instant trigger, by decision). Deliverable: a test pinning the threshold values so they don't silently drift.

### B6 — Anti-synergy costs

Reactions already live in `status_registry.apply_reactions` (no new code). Document the table; a test asserts the directions hold:

| Anti-synergy | Reaction | Constant |
|---|---|---|
| wet douses fire | wet drains on_fire | `WET_EXTINGUISH_RATE 4.0` |
| bloody dampens fire | bloody drains on_fire | `BLOODY_DAMPEN_RATE 1.5` |
| oiled amplifies fire | oiled feeds on_fire | `OIL_FIRE_GAIN 1.5` |
| wet + chilly → frozen | converts to frozen | `WET_FREEZE_RATE 2.0` |

A player slotting `water_emitter` + `ember_edge` should feel the conflict (water extinguishes their own fire). This is intended texture, surfaced in tooltips later.

### B7 — Shop rarity distribution

5 modifier cards per shop, weights tuned to **~60% Common / 30% Uncommon / 10% Rare**. Locate current weights (shop card-spawn path) and add a test pinning the distribution.

---

## Part C — Modifier Resonance & Catalysts

The nonlinear ceiling. Builds on the **existing** element/status reaction engine rather than a parallel system. Resolves **within a weapon's 3 modifier slots** (bounded, "build around your weapon"). Combos are intended to be **a lot stronger than band** — the floor is linear, the ceiling is multiplicative.

### C1 — Tags

New `tags` column in `modifiers.csv` (comma-separated). Vocabulary (12): `fire, ice, water, oil, lightning, poison, blood, earth, projectile, crit, kinetic, greed`. `power` = no-resonance (pure stat mods). A modifier may carry several. `DataModifier._init` parses it. Tags assigned for all 57 in §B2.

> Modifiers are built via `_init(row)`, **not** `duplicate()`, so the [[weapon-csv-fields-must-be-export]] caveat does not bite — verify during implementation that nothing duplicates a `DataModifier`.

### C2 — Resonance registry

`src/status/resonance_registry.gd` (data-only, mirrors `status_registry`). Each rule = required tag tally → effect, over two **channels** + one flagship **behavior** rule. Magnitudes are large (combos exceed band):

| Resonance | Trigger (tags in slots) | Channel | Effect |
|---|---|---|---|
| **Ignition** | fire × 2 | amplify | on_fire stain & burn DPS **×1.8** |
| **Caustic** | poison × 2, or poison + oil | amplify | poisoned DPS **×2.0** |
| **Permafrost** | water + ice | amplify | wet & chilly stain **×1.6** (faster freeze ramp) |
| **Hemorrhage** | blood + crit | stat | crit damage **+50%** vs bloody targets |
| **Fusillade** | projectile × 2 | stat | weapon damage **×1.3** (dense-projectile build) |
| **Avarice** | greed × 2 | stat | kill gold **×2** + pull radius +50% |
| **Overrun** | kinetic × 2 | behavior | knockback now **deals damage** (= weapon damage) |
| **Conduction** | water/wet + lightning | behavior *(flagship)* | lightning effects **chain +1 target** |

Behavior resonances beyond Conduction/Overrun are documented as the **extensible next layer** (registry data + one handler hook each), not built in this pass.

### C3 — Integration

Weapon gains a `_resonance` cache computed alongside `_effective_cache`, recomputed on `invalidate_effective_stats()` (i.e. whenever a slot changes — no per-frame cost):

1. Tally tags across the ≤3 slotted modifiers.
2. Match registry rules → store active resonances + their channel bonuses.
3. `get_effective_stats()` applies **stat-channel** bonuses (multiplied in after the existing `stat_mult` pass).
4. `DataModifier.on_hit_target` / status application multiplies stain by `weapon.get_resonance_mult(tag_channel)` — the **amplify channel**.
5. **Behavior** resonances expose a flag (`weapon.has_resonance("conduction")`) read by the relevant projectile/status code.

One new query method on `Weapon` (`get_resonance_mult` / `has_resonance`); everything else is cached state.

### C4 — Catalyst modifiers (4 new)

New `catalyst` category. Low solo value, paid for by what they do to slot-mates (read via the already-passed `weapon.modifiers`). Strong by design:

| id | rarity | tags | effect |
|---|---|---|---|
| **resonator** | Uncommon | power | **+25% damage per *other* slotted modifier** (max +50% with 2) |
| **overcharge** | Uncommon | power | sibling status/emitter mods apply **×2 stain**, decay 50% faster (burst) |
| **echo_lens** | Rare | projectile | **retriggers** the first sibling `projectile` modifier each swing (doubles its bolts) |
| **catalyst_core** | Rare | power | rewrites one sibling's resonance-tag to match another's — **forces a resonance** (the enabler) |

These are new CSV rows + a small `catalyst` branch in `DataModifier` (or a `CatalystModifier` subclass) that iterates `weapon.modifiers`. They are the deliberate "I built something" moments.

### C5 — Valuation & anti-degenerate

- Solo bands (Part B) assume **no resonance**; catalysts are intentionally weak alone (a slot tax).
- The "cap" is **anti-loop, not anti-power**: `echo_lens` may not retrigger another `echo_lens` or itself; resonance recompute is not re-entrant; `overcharge` does not compound with a second `overcharge`. Finite multipliers (e.g. Ignition ×1.8 × Overcharge ×2 = ×3.6 burn) are **allowed and intended**.
- Cooldown floor (0.1) already caps attack-speed stacking; no extra cap needed there.
- **Degenerate combos to watch (documented, not nerfed):** `overcharge` + `ember_edge` + fire weapon (runaway burn — that's the reward); `echo_lens` + `cluster_bomb` (16 fragments); `resonator` + 2 strong mods. These are *features* given the "combos ≫ band" goal; the audit just confirms none cause infinite loops or softlocks.

### C6 — Feedback (light hook)

When slotted mods form an active resonance, the modifier-slot UI shows a **combo glow** + the resonance name on hover. Minimal hook (read `weapon` resonance state in the existing weapon/modifier UI); full juice deferred to Phase 6 UI polish.

---

## 6. Implementation surface (phased)

**Phase 1 — Baseline re-tune (Parts A + B):**
- `docs/design_docs/weapons.csv` — apply the §A7 damage values (51 rows).
- `docs/design_docs/modifiers.csv` — apply the 3 §B2 changes; add the `tags` column populated for all 57.
- Charge-move tuning (§A6) in the charge archetype scripts (`willowblade`, `executioner`, `void_sword`, `quake_hammer`, `blood_blade`, `arc_railgun`).
- Verify A1 archetype multipliers and ranged `projectile_count` against the archetype scripts; re-solve any that differ.

**Phase 2 — Resonance & catalysts (Part C):**
- `src/status/resonance_registry.gd` (new) — the §C2 rules.
- `src/weapons/weapon.gd` — `_resonance` cache + `get_resonance_mult` / `has_resonance`; apply stat-channel in `get_effective_stats`.
- `src/weapons/modifiers/data_modifier.gd` — parse `tags`; multiply stain by resonance amplify channel; `catalyst` branch (or `catalyst_modifier.gd` subclass).
- Behavior hooks: Conduction (lightning chain +1) in the chain/lightning path; Overrun (knockback damage) in `_do_knockback`/CombatUtil.
- `modifiers.csv` — 4 new catalyst rows.
- Modifier-slot UI — combo glow + resonance-name tooltip (light).

## 7. Tests (in scope)

- `test_weapon_balance.gd` — every weapon's computed effective DPS sits in its rarity band (using the A1 model).
- `test_modifier_stacking.gd` — cooldown can't drop below 0.1 with `adrenaline`+`quickdraw`; crit can't exceed 1.0 with `combo_keeper`+`honed_point`; `(base + Σ add) × Π mult` order.
- `test_status_thresholds.gd` — pins the §B5 `active_threshold` values.
- `test_anti_synergy.gd` — asserts §B6 reaction directions (wet drains fire, oil feeds fire, wet+chilly→frozen).
- `test_shop_rarity_distribution.gd` — pins ~60/30/10 over a large sample.
- `test_resonance.gd` — tag parsing; right tags → right resonance; resonance recomputes on slot change; amplify multiplies stain.
- `test_catalysts.gd` — `resonator` scales per other mod; `echo_lens` retrigger count; anti-loop guards (no self-retrigger, no double-overcharge compounding).

## 8. Risks / out of scope

- **All numbers are pre-playtest estimates** anchored to the §2 bands. The bands and per-archetype taxes are the knobs.
- **Ranged single-target band can understate crowd clear** — re-check AoE/pierce/chain ranged (`tesla`, `spread`, `scatter`, `hailstorm`, `flame_lobber`, `venom_spitter`) against packs in playtest.
- **Enemy balance is NOT in this spec.** Part C exists specifically to give the *player* a nonlinear ceiling so the coming enemy-balance pass has something to push against. The enemy curve (HP/dmg per floor, TTK) is a separate todo section.
- **Loadout-wide combos are out of scope** — resonance is per-weapon (3 slots) by decision; a future spec could add loadout auras.
- **Resonance UI juice** beyond the light combo-glow hook is deferred to Phase 6.
