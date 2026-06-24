# Weapon & Modifier Balancing — Design

**Date:** 2026-06-24
**Scope:** All 6 "Weapon Balance" rows + all 7 "Modifier Balance" rows in `docs/design_docs/implementation_todo2.md` (Phase 1), **plus** 24 new **emergent-combo modifiers** (Part C) that add a nonlinear power ceiling.
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
- **Existing-57 solo magnitudes describe the NO-COMBO state.** The 24 new Part C modifiers are a deliberate ceiling *above* band.
- **Combos are A LOT stronger than band.** Design intent: a naked loadout = linear floor; an assembled combo build = multiplicative spike (Balatro philosophy). The combo lives in how two concretely-worded rules collide, **not** in a tag/resonance lookup table. The Part C "cap" (§C5) exists only to kill *infinite/degenerate loops*, **not** to cap finite combo power.
- **No duplicated effects.** Across the 24 new modifiers *and* the existing 57. Stronger-but-different is allowed; pure magnitude clones are not (§B2 audit).
- **Relics are out of scope.** Global passives (not tied to how a weapon swings) belong in a future relic system — all 24 here stay **weapon-tied** (occupy a weapon's 3 slots).
- **Status magnitudes are NOT retuned** — `apply_status` mods keep their current `2.0` stain (near-instant trigger). B5 becomes verify-thresholds-only.
- **Caps already exist:** `weapon.gd` has `COOLDOWN_FLOOR = 0.1` (`maxf` at aggregation) and crit `clampf(0,1)`. The stacking row is verification + tests, not new code.
- **Unit tests are in scope** (§7).
- **Phased implementation:** Phase 1 = baseline re-tune (A+B). Phase 2 = emergent-combo modifiers (C). Floor ships independent of ceiling.

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

### B2 — Full modifier audit (57 existing modifiers)

Most are already in-band; the audit confirms values and changes only the flagged few. The 57 keep their effects (no `tags` column — the rejected resonance system is gone).

| id | rarity | cat | mag / mg2 | change |
|---|---|---|---|---|
| lava_emitter | C | emitter | 16 | keep |
| green_crescent | U | projectile | 1 | keep |
| fireball_fan | C | projectile | 5 | **count 5 → 3** (free-DPS cap) |
| icicle_volley | C | projectile | 5 | **→ 3 piercing icicles** (de-dup vs fireball_fan) |
| gleaming_projectile | U | projectile | 1 | keep |
| lightning_bolt | R | projectile | 1 | keep |
| arc_volley | R | projectile | 7 | keep |
| triangular_volley | R | projectile | 13 | keep |
| bouncing_bullets | U | projectile | 4 | keep |
| splitting_rounds | U | projectile | 3 / 4 | keep |
| penetrating_shockwave | R | projectile | 1 | keep |
| oil_emitter | C | emitter | 24 | keep |
| water_emitter | C | emitter | 24 | keep |
| gas_emitter | U | emitter | 20 | **radius 20 → 16** (hazard cap) |
| frost_emitter | U | emitter | 18 | keep |
| blood_emitter | C | emitter | 20 | keep |
| coal_seeder | U | emitter | 12 | keep |
| dust_veil | C | emitter | 20 | keep |
| venom_edge | C | status | 2.0 | keep |
| soaking_strike | C | status | 2.0 | keep |
| greased_edge | C | status | 2.0 | keep |
| frostbite_edge | U | status | 2.0 | keep |
| ember_edge | U | status | 2.0 | keep |
| rending_edge | C | status | 2.0 | keep |
| sharpened | C | stat | 3 | keep |
| heavy_head | C | stat | 5 / 1.25 | keep (tradeoff variant of sharpened) |
| honed_point | U | stat | 0.15 | keep |
| executioners_mark | U | stat | 0.5 | keep |
| quickdraw | U | stat | 0.8 | keep |
| long_reach | C | stat | 1.3 | keep |
| wide_arc | C | stat | 1.4 | keep |
| deep_cut | U | stat | 1.8 | keep |
| fleetfoot | U | stat | 1.15 | keep |
| frostbreaker | U | trigger | 1.6 | keep (≥1.5) |
| pyroclast | U | trigger | 1.5 | keep (≥1.5) |
| coup_de_grace | U | trigger | 2.0 / 0.3 | keep |
| bloodlust | R | trigger | 1 / 8 | keep (kill-stack; ≠ rampage) |
| rampage | R | trigger | 1 / 6 | keep (hit-streak; ≠ bloodlust) |
| glass_cannon | R | trigger | 1.8 | keep |
| vampiric | U | trigger | 3 | keep |
| momentum | U | trigger | 1.5 | keep |
| adrenaline | R | trigger | 0.6 | keep |
| combo_keeper | U | trigger | 1.0 / 5 | keep |
| homing_hex | U | projectile | 1 | keep |
| chain_spark | R | projectile | 3 | keep |
| ricochet_shard | U | projectile | 1 / 3 | keep |
| piercing_lance | U | projectile | 1 | keep |
| cluster_bomb | R | projectile | 8 | keep |
| boomerang_arc | U | projectile | 1 | keep |
| spectral_echo | R | projectile | 1 | keep |
| tunnel_borer | U | terrain | 32 | keep |
| shockwave_stomp | U | utility | 40 | keep |
| magnet_field | C | utility | 48 | keep |
| repulsor_nova | R | utility | 80 | keep |
| concussive_edge | U | trigger | 0.5 / 0.2 | keep |
| midas_touch | U | utility | 5 | keep |
| steam_burst | R | trigger | 3 | keep |

**Duplication audit (per the no-dup rule):**
- **Clear duplicate fixed:** `fireball_fan` (5 fire fan) and `icicle_volley` (5 ice fan) were the same effect, element-swapped. `icicle_volley` → **3 *piercing* icicles** (distinct mechanic); `fireball_fan` stays a fire fan at 3.
- **Borderline (kept as meaningful variants, not clones):** `sharpened` vs `heavy_head` (flat dmg vs flat dmg + speed penalty); `bloodlust` vs `rampage` (kill-stack vs hit-streak ramp); `arc_volley` vs `triangular_volley` (combo-step sprays, 7 vs 13, tied to different combo weapons).
- The 8 emitters and 6 status-appliers are **not** duplicates — each material/status behaves differently downstream.

Net changes to the 57: `fireball_fan` 5→3, `icicle_volley` 5→3+pierce, `gas_emitter` 20→16. Everything else confirmed in-band; the real modifier work is the 24 new combo modifiers (Part C).

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

## Part C — Emergent-Combo Modifiers (24 new)

The nonlinear ceiling. **24 net-new weapon modifiers** (→81 total) whose combos *emerge* from how two concretely-worded rules collide — Balatro's actual design (Photograph + Hanging Chad), **not** a tag/resonance lookup table. Resolve **within a weapon's 3 slots**, evaluated **left→right deterministically** (that ordering is what makes positional/retrigger combos legible). Combos are intended to be **a lot stronger than band** — naked loadout = linear floor, assembled build = multiplicative spike.

### C1 — Interaction primitives (the scripted machinery)

Every modifier below is written in this small verb set. These are the only new mechanical capabilities the modifier runtime must gain:

1. **Positional reference** — act on "the first slot / the modifier to my left / right / the other two." (Slots are already an ordered `weapon.modifiers` array.)
2. **Retrigger** — re-run another modifier's effect N extra times.
3. **Target-state conditional** — payoff vs on_fire / frozen / wet / poisoned / bloody / chilly enemies. (`condition: target_status:<id>` already exists in `DataModifier`.)
4. **Self/run-state conditional** — payoff on after-damage / gold held / slot composition.
5. **Detonator / consume** — consume a status' stacks for a burst.
6. **Copy** — become a copy of an adjacent modifier.
7. **Charge / pause rhythm** — trigger then disable a modifier for N seconds; or charge over swings then dump.
8. **Run-scaling transform** — permanently grow on an event.

### C2 — The 24 modifiers

Every effect is mechanically unique (no clones across the 24 or vs the existing 57). Rarity spread **4 C / 13 U / 7 R** (feeds §B7's 60/30/10).

**Status setup / enabler (6)** — distinct status manipulations:

| id | rarity | effect | primitive |
|---|---|---|---|
| spark_plug | C | hits **ignite** oiled enemies (oiled→fire) | target-state |
| deepfreeze | C | hits push chilly→**frozen 2× faster** | target-state |
| hemophilia | C | **+25% crit chance** vs bleeding enemies | target-state |
| backdraft | U | hitting a burning enemy **spreads fire** to nearby foes | target-state |
| riptide | U | hits **knock back** wet enemies and apply chilly | target-state |
| plague_carrier | U | hits **spread** a target's poison to nearby foes | target-state |

**Detonators (4)** — consume a different status, different payoff shape:

| id | rarity | effect | primitive |
|---|---|---|---|
| frostshatter | R | consume Frozen → burst = stacks×8 + AoE shatter | detonator |
| combustion | R | consume On-Fire → instant burst = remaining burn ×3 | detonator |
| rupture | U | bleeding accumulates; at 5 stacks target bursts for 5× a hit | detonator |
| necrosis | U | consume Poison stacks → instant ×2 that damage | detonator |

**Retrigger / positional engines (7)** — distinct retrigger shapes (the combo multipliers):

| id | rarity | effect | primitive |
|---|---|---|---|
| echo_strike | R | retrigger your **first** modifier once per swing *(Hanging Chad)* | retrigger + positional |
| overclock | R | retrigger the **left** modifier, then disable it 5 s | retrigger + pause |
| mirror_slot | R | become a **copy** of the modifier to your left *(Blueprint)* | copy |
| catalyst_bond | R | **link** slots 1 & 3: either fires → both fire | positional |
| keystone | R | slot-2 modifier **+100%**, slots 1 & 3 disabled (focus build) | positional |
| twin_trigger | U | every 3rd swing, **all** modifiers trigger twice | retrigger + rhythm |
| flywheel | U | untriggered modifiers charge; at 5, fire **×3** then empty | charge |

**Conditional / scaler / transform (7)** — distinct conditions, no overlap with existing pyroclast/glass_cannon/etc.:

| id | rarity | effect | primitive |
|---|---|---|---|
| greedy_edge | C | +1% dmg per 50 gold held (cap +40%) | self-state |
| last_stand | U | +60% on your **first hit after taking damage** | self-state |
| overkill | U | damage **exceeding** an enemy's HP carries to the next enemy hit | self-state |
| evolving_edge | U | after 15 hits, this modifier's **own bonus doubles** (run) | run-transform |
| pendulum | U | odd swings ×2 your **left** modifier, even swings ×2 your **right** | positional + rhythm |
| headsman | U | one-shotting an enemy >50% HP **refunds the swing** (instant next attack) | self-state |
| slot_harmony | U | +20% dmg while all 3 slots are **different categories** | self-state |

### C3 — Flagship combos (emergence, not lookup)

- **echo_strike** (slot 1) + **combustion**/**hemophilia**/any setup → echo_strike retriggers slot 1, so the conditional/detonator payoff lands **twice** per swing. Stack **twin_trigger** and the whole engine doubles on the beat. *(Photograph + Hanging Chad, ported — neither modifier names the other.)*
- **deepfreeze** (build frozen) + **frostshatter** (detonate it) + a frost weapon → freeze engine.
- **spark_plug** (ignite oiled) + `oil_emitter`/`greased_edge` (existing) + **backdraft** (spread) → oil-fire chain.
- **catalyst_bond** links two strong on-hit effects in slots 1 & 3 into one paired engine.

### C4 — Implementation

- **Data-driven (stay in `DataModifier`):** the target-state conditionals (`spark_plug`, `deepfreeze`, `hemophilia`, `backdraft`, `riptide`, `plague_carrier`, `greedy_edge`) — extend the existing `condition`/`effect` verbs.
- **Scripted `Modifier` subclasses** (`src/weapons/modifiers/`): everything using retrigger / copy / pause / positional / detonator / transform. They read & invoke siblings via the ordered `weapon.modifiers` (already passed to every hook).
- **New `Weapon` plumbing:** a left→right **modifier evaluation pass** supporting re-entrant retrigger with a **depth guard** (the anti-loop brake). One pass replaces the current ad-hoc `for m in modifiers` loops at each hook.
- **`modifiers.csv`:** 24 new rows (data ones fully specified; scripted ones reference their script).
- **No `tags` column** — the resonance idea is dropped; combos are concrete.

### C5 — Anti-degenerate (loops only, not power)

- The cap is **anti-loop, not anti-power.** Finite multipliers are allowed and intended (echo_strike × twin_trigger × a strong slot-1 = the reward).
- **Guards:** `echo_strike`/`overclock`/`twin_trigger` cannot retrigger a retrigger modifier or themselves; the evaluation pass carries a **depth counter** (hard stop at depth 2); `mirror_slot` copying `mirror_slot` resolves to no-op; `catalyst_bond` + `pendulum` + retrigger can't form a cycle because retriggers don't re-enter the positional pass.
- Cooldown floor (0.1) already caps attack-speed stacking.
- **Big combos to watch (documented, not nerfed):** `echo_strike` + `combustion` on a fire build; `keystone` + a Rare slot-2; `headsman` chains. These are *features* given the "combos ≫ band" goal — the audit confirms none loop infinitely or softlock.

### C6 — Feedback (light hook)

Retrigger/positional/disabled states surface in the modifier-slot UI (a glow on a retriggered slot, a dim on an `overclock`-disabled one, a "linked" marker for `catalyst_bond`). Minimal hook reading weapon/modifier state; full juice deferred to Phase 6 UI polish.

---

## 6. Implementation surface (phased)

**Phase 1 — Baseline re-tune (Parts A + B):**
- `docs/design_docs/weapons.csv` — apply the §A7 damage values (51 rows).
- `docs/design_docs/modifiers.csv` — apply the 3 §B2 changes (`fireball_fan` 5→3, `icicle_volley` 5→3+pierce, `gas_emitter` 20→16).
- Charge-move tuning (§A6) in the charge archetype scripts (`willowblade`, `executioner`, `void_sword`, `quake_hammer`, `blood_blade`, `arc_railgun`).
- Verify A1 archetype multipliers and ranged `projectile_count` against the archetype scripts; re-solve any that differ.

**Phase 2 — Emergent-combo modifiers (Part C):**
- `src/weapons/weapon.gd` — a left→right **modifier evaluation pass** with a re-entrant retrigger **depth guard**, replacing the ad-hoc per-hook `for m in modifiers` loops; positional/sibling access helpers; disable-state tracking (for `overclock`).
- `src/weapons/modifiers/data_modifier.gd` — new `condition`/`effect` verbs for the 7 data-driven conditionals (§C4).
- `src/weapons/modifiers/` — scripted `Modifier` subclasses for the retrigger / copy / pause / positional / detonator / transform modifiers.
- `docs/design_docs/modifiers.csv` — 24 new rows.
- Modifier-slot UI — retrigger/disabled/linked state hooks (light, §C6).

## 7. Tests (in scope)

- `test_weapon_balance.gd` — every weapon's computed effective DPS sits in its rarity band (A1 model).
- `test_modifier_stacking.gd` — cooldown can't drop below 0.1 with `adrenaline`+`quickdraw`; crit can't exceed 1.0 with `combo_keeper`+`honed_point`; `(base + Σ add) × Π mult` order.
- `test_status_thresholds.gd` — pins the §B5 `active_threshold` values.
- `test_anti_synergy.gd` — asserts §B6 reaction directions (wet drains fire, oil feeds fire, wet+chilly→frozen).
- `test_shop_rarity_distribution.gd` — pins ~60/30/10 over a large sample.
- `test_combo_modifiers.gd` — `echo_strike` retriggers the first slot exactly once; `overclock` disables then re-enables after 5 s; detonators consume the right stacks; positional refs resolve correctly; the depth guard stops re-entrant retrigger at depth 2; the flagship `echo_strike`+conditional combo doubles the payoff end-to-end.

## 8. Risks / out of scope

- **All numbers are pre-playtest estimates** anchored to the §2 bands. The bands and per-archetype taxes are the knobs.
- **Ranged single-target band can understate crowd clear** — re-check AoE/pierce/chain ranged (`tesla`, `spread`, `scatter`, `hailstorm`, `flame_lobber`, `venom_spitter`) against packs in playtest.
- **Enemy balance is NOT in this spec.** Part C exists specifically to give the *player* a nonlinear ceiling so the coming enemy-balance pass has something to push against. The enemy curve (HP/dmg per floor, TTK) is a separate todo section.
- **Relics are out of scope** — a parallel global-passive item axis (StS-style) is a known future spec; all 24 here are weapon-tied.
- **Loadout-wide combos are out of scope** — combos resolve per-weapon (3 slots) by decision.
- **Combo UI juice** beyond the light state hooks is deferred to Phase 6.
