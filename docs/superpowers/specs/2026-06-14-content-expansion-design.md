# Content Expansion — Weapons & Modifiers (Design Spec)

**Date:** 2026-06-14
**Branch:** feat/content-expansion
**Goal:** Expand build variation by documenting **~74 new entries** (46 modifiers + 28 weapons)
into `docs/design_docs/modifiers.csv` and `docs/design_docs/weapons.csv`.

**Scope:** *Documentation only.* No GDScript, no `.tres`, no sprites this session. New rows are
design-of-record for the existing Phase 7 (Content Expansion) implementation track. Each entry
below carries an **Impl** note precise enough to build from.

Research anchors: **Noita** (material/element interaction), **Dead Cells** (weapon variety +
stat affixes), **Balatro** (conditional "joker" multipliers and economy effects).

---

## 1. Why

`gameplay.md` makes modifiers the core build-crafting block, but only 11 modifiers and 24
weapons exist — too few for meaningful run-to-run variation. This spec adds a modifier-heavy
batch and the schema to support data-driven modifiers.

---

## 2. Modifier CSV — schema change

### 2.1 Parser facts (verified)
- The game reads both CSVs via `CsvTable.parse()` (see `src/autoload/weapon_registry.gd`),
  which returns **header-keyed dict rows**. Adding columns is **non-breaking**: existing code
  uses `row.get("name"/"description"/"suppresses_base_use")` and ignores unknown columns.
- The `.import` / `.translation` sidecar files are Godot auto-import artifacts the game logic
  does **not** consume. They will regenerate on import; cosmetic only.

### 2.2 New header

```
id,name,description,rarity,category,trigger,condition,effect,element,magnitude,magnitude2,suppresses_base_use
```

`suppresses_base_use` stays the **last** column so current code keeps working. The 11 existing
modifiers are backfilled with structured values (below).

### 2.3 Controlled vocabulary

| Column | Allowed values |
|---|---|
| `rarity` | `Common` `Uncommon` `Rare` |
| `category` | `emitter` `status` `stat` `trigger` `projectile` `terrain` `utility` |
| `trigger` | `on_swing` `on_hit` `on_crit` `on_kill` `every_n_hits` `on_charge` `on_combo_step` `on_tick` `passive` |
| `condition` (optional) | `target_status:<id>` `target_low_hp` `self_full_hp` `self_low_hp` (blank = always) |
| `effect` | `spawn_material` `apply_status` `stat_add` `stat_mult` `spawn_projectile` `carve` `explode` `pull` `knockback` `heal` `lifesteal` `stun` `bounty` |
| `element` | a material/status id, a stat name, or blank |
| `magnitude` / `magnitude2` | numbers (amount, multiplier, stain, radius, duration, stacks, chance) |

**Element ids** — materials: `oil water gas ice blood coal dust lava` · statuses:
`on_fire poisoned chilly frozen wet bloody` · **new (flagged, need status defs later):**
`lightning steam` · stat names: `damage cooldown crit_chance crit_multiplier reach arc
carve_depth move_speed projectile_count`.

### 2.4 Implementation conventions (read once, applies to every modifier)

A future data-driven `Modifier` subclass should dispatch on `category`/`effect`/`trigger`.
Unless an entry's **Impl** note overrides, these defaults hold:

- **Trigger timing.** `on_swing` = once when an attack starts. `on_hit` = once per enemy the
  attack damages. `on_crit` = when the crit roll succeeds on a hit. `on_kill` = when a hit
  reduces an enemy to 0 hp. `every_n_hits` = counts *successful hits* on this weapon, fires on
  the Nth (N = `magnitude2`), then resets. `on_charge` = on full-charge release (charge weapons
  only; no-op otherwise). `on_combo_step` = on the combo step index in `magnitude2` (combo
  weapons only). `passive` = folded into stat recompute every frame; never "fires".
- **`effect=spawn_material`.** Place a blob of the `element` material via `terrain_modifier` at
  the swing-arc midpoint (melee) or the projectile/impact point (ranged). `magnitude` = blob
  radius in pixels. `magnitude2` > 0 overrides material lifetime in seconds. Spawned materials
  obey the existing sim (flammability, fluid flow, hazard bits), so they auto-participate in
  chain reactions — that *is* the feature.
- **`effect=apply_status`.** On hit, `target.status_component.add_stain(element, magnitude)`.
  `magnitude` is stain units. Recall active thresholds from `status_registry.gd`: `on_fire` 1.0,
  `wet` 1.0, `oiled` 1.0, `chilly` 1.0 (auto-freezes once stain ≥ 4.0), `poisoned` 0.3,
  `bloody` 1.0, `frozen` 3.0. So `magnitude` 2.0 = roughly two "active" applications. Reaction
  rules already in `status_registry.apply_reactions` then take over.
- **`effect=stat_add` / `stat_mult`.** Modify the named `element` stat when the weapon computes
  its effective value. `stat_add` adds `magnitude`; `stat_mult` multiplies by `magnitude`.
  Stack rule: sum all `stat_add` first, then apply each `stat_mult`. `cooldown` < 1.0 multiplier
  = faster; `crit_chance` is a 0..1 fraction.
- **`effect=spawn_projectile`.** Spawn `magnitude` projectile instances. `magnitude2` carries a
  behavior count when relevant (bounces, splits). Reuse the existing projectile archetypes
  (`projectile.gd`, sniper/penetration/split/bounce behaviors) where possible; per-entry Impl
  notes name the behavior.
- **`condition` gate.** Evaluated before the effect. `target_status:<id>` true when the target's
  stain for `<id>` ≥ that status's active threshold. `target_low_hp` true when target hp fraction
  ≤ `magnitude2` (default 0.3 if `magnitude2` = 0). `self_full_hp` true at player max hp.
  `self_low_hp` true when player hp fraction ≤ 0.3.
- **Stacking.** Two copies of the same modifier stack additively on their primary `magnitude`
  unless the Impl note says otherwise.

---

## 3. New modifiers (46)

Format: **id — Name** *(rarity · category · trigger[/condition] · effect element · mag/mag2)*.
The quoted line is the CSV `description` (player-facing). **Impl** is implementor detail.

### A. Emitters — spawn material on swing (7)

- **oil_emitter — Oil Emitter** *(Common · emitter · on_swing · spawn_material oil · 24/0)*
  > "Each swing leaves a slick of flammable oil — ignite it for a firestorm."
  **Impl:** Drop a 24px `MAT_OIL` blob at the arc midpoint each swing. Oil is flammable
  (ignition 200) and a fluid, so it pools, spreads `oiled` stain on contact, and ignites from
  any fire/lava into a spreading burn. Default oil lifetime.

- **water_emitter — Aqua Font** *(Common · emitter · on_swing · spawn_material water · 24/0)*
  > "Swings spray water, dousing flames and soaking the ground for freeze combos."
  **Impl:** 24px `MAT_WATER` blob per swing. Water applies `wet`, extinguishes `on_fire` via
  the existing wet→fire reaction, and with `chilly` present converts to `frozen`. Counters
  oil/fire builds; enables freeze builds.

- **gas_emitter — Miasma Vent** *(Uncommon · emitter · on_swing · spawn_material gas · 20/0)*
  > "Belches a cloud of toxic gas with each swing, poisoning anything inside."
  **Impl:** 20px `MAT_GAS` cloud per swing. Gas applies `poisoned` (DoT, burn_dps 2.0) to
  anything standing in it. Gas is flammable-adjacent: fire passing through ignites it (Noita
  flammable-gas behavior) — document as desired interaction.

- **frost_emitter — Frost Emitter** *(Uncommon · emitter · on_swing · spawn_material ice · 18/0)*
  > "Lays a patch of ice underfoot — slick footing that chills the careless."
  **Impl:** 18px `MAT_ICE` (a *solid* material) at the arc midpoint. Unlike fluids this builds
  walkable/standable ice terrain; standing on it tops up `chilly`. Note: ice is solid, so this
  also lightly reshapes terrain — keep blob small to avoid griefing the player's own pathing.

- **blood_emitter — Sanguine Spray** *(Common · emitter · on_swing · spawn_material blood · 20/0)*
  > "Sprays blood across the floor, fuel for blood-soaked synergies."
  **Impl:** 20px `MAT_BLOOD` fluid per swing, applying `bloody`. `bloody` dampens fire (weaker
  than wet) and is the fuel any future blood-synergy modifiers/weapons key off.

- **coal_seeder — Coal Seeder** *(Uncommon · emitter · on_swing · spawn_material coal · 12/0)*
  > "Scatters lumps of flammable coal that smolder into lingering fire."
  **Impl:** 12px `MAT_COAL` (solid, flammable, high burn_health 200) per swing. Coal ignites
  slowly and burns long, creating persistent fire zones — a delayed-area-denial emitter rather
  than instant like oil. Small blob: coal is solid terrain.

- **dust_veil — Dust Veil** *(Common · emitter · on_swing · spawn_material dust · 20/0)*
  > "Kicks up a concealing cloud of dust on every swing."
  **Impl:** 20px `MAT_DUST` cloud per swing. Dust is a non-damaging fluid; primary use is
  vision/concealment (and future "enemies miss while in dust"). No status. Cheap defensive
  emitter.

### B. Status appliers on hit (6)

All: `on_hit`, `effect=apply_status`, `magnitude` 2.0 stain. The element differs.

- **venom_edge — Venom Edge** *(Common · status · on_hit · apply_status poisoned · 2.0)*
  > "Strikes coat foes in venom, poisoning them over time."
  **Impl:** `add_stain("poisoned", 2.0)` per hit. Poisoned threshold is low (0.3) so one hit
  starts the DoT; stacks ramp duration. Pairs with anything that keeps enemies alive longer.

- **soaking_strike — Soaking Strike** *(Common · status · on_hit · apply_status wet · 2.0)*
  > "Blows leave enemies drenched, priming them for freezing or shock."
  **Impl:** `add_stain("wet", 2.0)`. Wet extinguishes fire on the target and is the setup half
  of wet+chilly→frozen. Anti-synergy with fire builds (will douse your own ignites).

- **greased_edge — Greased Edge** *(Common · status · on_hit · apply_status oiled · 2.0)*
  > "Coats struck foes in oil — one spark sets them ablaze."
  **Impl:** `add_stain("oiled", 2.0)`. Oiled feeds fire (oil→fire reaction): if the target later
  catches fire, oiled is consumed to amplify burn. Strong combo with any fire source.

- **frostbite_edge — Frostbite Edge** *(Uncommon · status · on_hit · apply_status chilly · 2.0)*
  > "Each hit saps warmth, chilling foes toward a deep freeze."
  **Impl:** `add_stain("chilly", 2.0)`. `chilly` slows (slow_multiplier 0.6) and auto-converts
  to `frozen` once stain ≥ 4.0 — so ~2 hits freeze. Core of control/freeze builds.

- **ember_edge — Ember Edge** *(Uncommon · status · on_hit · apply_status on_fire · 2.0)*
  > "Strikes ignite foes, setting them burning."
  **Impl:** `add_stain("on_fire", 2.0)`. Burn DoT (burn_dps 4.0). Ignites oiled/gas on the
  target or nearby flammables. Anti-synergy with wet.

- **rending_edge — Rending Edge** *(Common · status · on_hit · apply_status bloody · 2.0)*
  > "Wounds bleed freely, leaving enemies bloody and weakened."
  **Impl:** `add_stain("bloody", 2.0)`. `bloody` is currently neutral (no DoT); treat as a
  marker for blood-synergy and minor fire-dampening. If a "bleed deals damage" rule is wanted,
  add it as a status tweak (flagged follow-up).

### C. Stat affixes (9) — all `passive`

- **sharpened — Sharpened** *(Common · stat · passive · stat_add damage · 3/0)*
  > "+3 flat damage to every hit."
  **Impl:** `damage += 3` at compute. Applies before any `stat_mult`.

- **heavy_head — Heavy Head** *(Common · stat · passive · stat_add damage · 5 / 1.25)*
  > "+5 damage, but swings land 25% slower."
  **Impl:** Dual-stat tradeoff. `damage += 5`; **and** `cooldown *= 1.25` (the `magnitude2`).
  Document: this is the one stat affix that reads `magnitude2` as a cooldown multiplier.

- **honed_point — Honed Point** *(Uncommon · stat · passive · stat_add crit_chance · 0.15/0)*
  > "+15% critical strike chance."
  **Impl:** `crit_chance += 0.15` (clamp ≤ 1.0). Also wire `modify_crit_chance()` so the
  existing crit hook sees it.

- **executioners_mark — Executioner's Mark** *(Uncommon · stat · passive · stat_add crit_multiplier · 0.5/0)*
  > "Critical hits deal an extra +0.5× damage."
  **Impl:** `crit_multiplier += 0.5`. No effect on non-crit weapons unless paired with a
  crit-chance source.

- **quickdraw — Quickdraw** *(Uncommon · stat · passive · stat_mult cooldown · 0.8/0)*
  > "Swings come 20% faster."
  **Impl:** `cooldown *= 0.8`. Floor cooldown at a sane minimum (e.g. 0.1s) to avoid degenerate
  stacking.

- **long_reach — Long Reach** *(Common · stat · passive · stat_mult reach · 1.3/0)*
  > "Extends weapon reach by 30%."
  **Impl:** `reach *= 1.3`. For melee, scales the swing-arc hitbox length; for ranged, scales
  projectile range/lifetime.

- **wide_arc — Wide Arc** *(Common · stat · passive · stat_mult arc · 1.4/0)*
  > "Widens the swing arc by 40%, sweeping more foes."
  **Impl:** `arc_degrees *= 1.4` on melee weapons. No-op on ranged (document).

- **deep_cut — Deep Cut** *(Uncommon · stat · passive · stat_mult carve_depth · 1.8/0)*
  > "Carves 80% deeper into terrain — dig and tunnel with ease."
  **Impl:** Scale the terrain-carve radius/depth applied by swings by 1.8×. Pure terrain-mobility
  affix; no damage change.

- **fleetfoot — Fleetfoot** *(Uncommon · stat · passive · stat_mult move_speed · 1.15/0)*
  > "Move 15% faster while attacking."
  **Impl:** While an attack is in progress, `player.move_speed *= 1.15`. Reverts when idle.

### D. Conditional "joker" triggers (10)

- **frostbreaker — Frostbreaker** *(Uncommon · trigger · on_hit/target_status:frozen · stat_mult damage · 1.6/0)*
  > "Deal +60% damage to chilled or frozen foes."
  **Impl:** If target stain `frozen` ≥ 3.0 **or** `chilly` ≥ threshold, multiply this hit's
  damage ×1.6. (Condition checks `frozen`; also honor `chilly` per the description.)

- **pyroclast — Pyroclast** *(Uncommon · trigger · on_hit/target_status:on_fire · stat_mult damage · 1.5/0)*
  > "Deal +50% damage to burning foes."
  **Impl:** If target `on_fire` ≥ 1.0, this hit's damage ×1.5.

- **coup_de_grace — Coup de Grace** *(Uncommon · trigger · on_hit/target_low_hp · stat_mult damage · 2.0 / 0.3)*
  > "+100% damage to foes below 30% health."
  **Impl:** If target hp fraction ≤ `magnitude2` (0.3), this hit's damage ×2.0. Execute-style.

- **bloodlust — Bloodlust** *(Rare · trigger · on_kill · stat_add damage · 1 / 8)*
  > "Each kill grants stacking damage that fades when the killing stops."
  **Impl:** On kill, +1 stacking bonus damage, max `magnitude2` (8) stacks. Stacks decay (e.g.
  lose 1 every ~3s without a kill, or all on taking damage — implementor's call, document
  chosen rule). Bonus added at `stat_add` stage.

- **rampage — Rampage** *(Rare · trigger · on_hit · stat_add damage · 1 / 6)*
  > "Consecutive hits ramp damage; missing resets the streak."
  **Impl:** Each consecutive successful hit +1 damage, capped at `magnitude2` (6). Reset the
  ramp if no hit lands within ~1.5s (a swing that connects with nothing breaks it).

- **glass_cannon — Glass Cannon** *(Rare · trigger · on_hit/self_full_hp · stat_mult damage · 1.8/0)*
  > "+80% damage while at full health; drops the moment you're hurt."
  **Impl:** While player hp == max, every hit ×1.8. Recompute the condition each hit.

- **vampiric — Vampiric** *(Uncommon · trigger · on_kill · heal · — · 3/0)*
  > "Heal a sliver of health on each kill."
  **Impl:** On kill, heal the player by `magnitude` (3) hp, clamped to max. `element` blank.

- **momentum — Momentum** *(Uncommon · trigger · on_hit · stat_mult damage · 1.5/0)*
  > "The faster you move, the harder you hit — up to +50%."
  **Impl:** Scale this hit's damage by `lerp(1.0, magnitude, speed_fraction)` where
  `speed_fraction` = current/max move speed. Standing still = ×1.0; full sprint = ×1.5.

- **adrenaline — Adrenaline** *(Rare · trigger · passive/self_low_hp · stat_mult cooldown · 0.6/0)*
  > "Swings get faster as your health drops, up to 40% faster."
  **Impl:** Continuous: `cooldown *= lerp(1.0, magnitude, 1 - hp_fraction)`. At full hp no
  change; near death ×0.6 (40% faster). `passive` recompute.

- **combo_keeper — Combo Keeper** *(Uncommon · trigger · every_n_hits · stat_add crit_chance · 1.0 / 5)*
  > "Every 5th hit is a guaranteed critical."
  **Impl:** Count successful hits; on the `magnitude2`-th (5th), force `crit_chance` = 1.0 for
  that hit, then reset the counter. Stacks with other crit sources (still just guarantees).

### E. Projectile / on-swing (7)

- **homing_hex — Homing Hex** *(Uncommon · projectile · on_swing · spawn_projectile · 1/0)*
  > "Every swing looses a bolt that curves toward the nearest foe."
  **Impl:** Spawn 1 projectile with homing steering toward the nearest enemy (cap turn rate so
  it can miss). New behavior: `homing` steering on `projectile.gd`.

- **chain_spark — Chain Spark** *(Rare · projectile · on_crit · spawn_projectile lightning · 3/0)*
  > "Critical hits arc lightning to nearby enemies, with a chance to stun."
  **Impl:** On crit, arc to up to `magnitude` (3) nearest enemies within a radius, dealing a
  fraction of hit damage and a stun chance per arc. Uses new `lightning` element (needs status
  def for the brief stun). Reuse `lightning_bolt_modifier` patterns where possible.

- **ricochet_shard — Ricochet Shard** *(Uncommon · projectile · on_swing · spawn_projectile · 1 / 3)*
  > "Swings fling a shard that ricochets off walls, striking again."
  **Impl:** Spawn 1 projectile using the existing **bounce** behavior with `magnitude2` (3)
  bounces off solid terrain. Reuse `bouncing_bullets` projectile logic.

- **piercing_lance — Piercing Lance** *(Uncommon · projectile · on_swing · spawn_projectile · 1/0)*
  > "Looses a lance that skewers every foe in a line."
  **Impl:** Spawn 1 projectile with the **penetration** behavior (`sniper_penetration_behavior`)
  — passes through all enemies in a line, does not delete on first hit.

- **cluster_bomb — Cluster Bomb** *(Rare · projectile · on_swing · spawn_projectile on_fire · 8/0)*
  > "Hurls a bomb that bursts into a ring of fragments."
  **Impl:** Spawn 1 lobbed projectile; on impact spawn `magnitude` (8) radial fragment
  projectiles and a small fire/`MAT_EXPLODE_WAVE` burst (the `on_fire` element). Area burst.

- **boomerang_arc — Boomerang Arc** *(Uncommon · projectile · on_swing · spawn_projectile · 1/0)*
  > "Throws a blade-arc that returns, hitting foes both ways."
  **Impl:** Spawn 1 projectile that travels out to max range, then reverses to the player,
  damaging on both legs. New `return` behavior on `projectile.gd`.

- **spectral_echo — Spectral Echo** *(Rare · projectile · on_swing · spawn_projectile · 1/0)*
  > "A ghostly copy repeats your swing a moment later."
  **Impl:** After a short delay (~0.25s), replay the same attack (same arc/projectile) at reduced
  damage (~50%). Effectively a delayed second swing; reuse the weapon's own attack call.

### F. Terrain & utility (7)

- **tunnel_borer — Tunnel Borer** *(Uncommon · terrain · on_swing · carve · 32/0)*
  > "Swings blast a wide tunnel through soft terrain."
  **Impl:** On swing, carve a `magnitude` (32px) radius of non-bedrock terrain ahead of the
  swing. Respects hardness (won't cut bedrock; slower through stone). Mobility/utility.

- **shockwave_stomp — Shockwave Stomp** *(Uncommon · utility · on_swing · knockback · 40/0)*
  > "Each swing emits a shockwave that knocks foes back."
  **Impl:** On swing, apply a radial knockback impulse to enemies within `magnitude` (40px) of
  the player, scaled by distance. No damage by itself.

- **magnet_field — Magnet Field** *(Common · utility · on_swing · pull · 48/0)*
  > "Pulls loose gold and drops toward you on every swing."
  **Impl:** On swing, pull pickup/drop entities within `magnitude` (48px) toward the player.
  Quality-of-life economy modifier; does not affect enemies.

- **repulsor_nova — Repulsor Nova** *(Rare · utility · on_charge · knockback · 80/0)*
  > "A full charge releases a nova that flings enemies away."
  **Impl:** On full-charge release (charge weapons only), strong radial knockback within
  `magnitude` (80px). On non-charge weapons, no-op (document) — pairs with charge weapons.

- **concussive_edge — Concussive Edge** *(Uncommon · trigger · on_hit · stun · 0.5 / 0.2)*
  > "Hits have a chance to stun, briefly halting foes."
  **Impl:** Each hit has `magnitude2` (0.2 = 20%) chance to stun the target for `magnitude`
  (0.5s). Needs a stun/immobilize on enemies (reuse `frozen.blocks_movement` mechanism with a
  neutral stun status, flagged follow-up).

- **midas_touch — Midas Touch** *(Uncommon · utility · on_kill · bounty · 5/0)*
  > "Slain enemies spill extra gold."
  **Impl:** On kill, drop `magnitude` (5) extra gold/currency. `effect=bounty` is a new effect
  verb for economy modifiers (Balatro-style). Hooks the enemy death/drop path.

- **steam_burst — Steam Burst** *(Rare · trigger · on_hit/target_status:wet · apply_status steam · 3/0)*
  > "Striking a wet foe erupts in scalding steam, spreading the burn."
  **Impl:** If target is `wet`, consume some wet and apply new `steam` status (3 stain) — a
  short scalding DoT that also spreads to nearby enemies. Needs new `steam` status def + a
  wet→steam reaction (flagged follow-up). Rewards a wet-application setup (e.g. with
  `soaking_strike`).

---

## 4. New weapons (28)

Schema unchanged: `id,name,description,type,rarity,cooldown,damage,weapon_texture,
modifier_slots,pre_attached_modifier1..3,crit_chance,crit_multiplier,crit_status`.
Player-facing mechanics go in the prose `description`; the **Impl** note tells the implementor
which archetype/script to build (textures reuse existing icons, no sprites):
- **MEL** = `res://textures/Weapons/sword_01c.png`
- **RNG** = `res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/16x16/bow_01a.png`

All weapons have 3 modifier slots. Format below: **id — Name** *(rarity · cd · dmg · pre-attached
· crit)*; quoted = CSV description; **Impl** = build notes.

### Melee (18)

- **iron_mace — Iron Mace** *(Common · 0.7 · 6.0 · — )*
  > "A blunt iron head that crushes armor and stuns on impact. Slow, but every hit rattles bone."
  **Impl:** Stat melee (heavy/slow). New trait: small built-in stun chance on hit (or leave as
  flavor and rely on `concussive_edge`). Wide-ish arc, short reach.

- **rapier — Rapier** *(Uncommon · 0.3 · 2.5 · — · crit 0.30/2.0)*
  > "A slender thrusting blade — lightning-fast, narrow reach, and a high crit chance that rewards precise jabs."
  **Impl:** Stat melee with crit. Narrow arc (~45°), fastest cooldown tier, low base damage,
  high crit_chance. Pure existing crit system.

- **cleaver — Bone Cleaver** *(Common · 0.55 · 5.0 · rending_edge)*
  > "A wide butcher's blade that opens deep, bleeding wounds with every chop."
  **Impl:** Stat melee, wide arc, pre-attached `rending_edge` (applies bloody). Slot 1 filled.

- **war_scythe — War Scythe** *(Uncommon · 0.6 · 5.5 · wide_arc)*
  > "A sweeping reaper's blade with a broad arc that catches foes to the flanks and behind."
  **Impl:** Stat melee with a very wide arc; pre-attached `wide_arc`. Emphasize the arc-degrees
  stat. Good crowd weapon.

- **twin_daggers — Twin Daggers** *(Uncommon · 0.28 · 1.8 · — )*
  > "Paired blades that strike twice per swing — low damage each, brutal in sum."
  **Impl:** New mechanic: each attack executes **two** quick hitbox passes (double-hit). Reuse
  a 2-step combo with near-zero delay. Low per-hit damage, high effective DPS, great with
  on-hit modifiers (procs twice).

- **obsidian_greatsword — Obsidian Greatsword** *(Rare · 0.8 · 9.0 · deep_cut)*
  > "A massive volcanic blade that cleaves through stone as easily as flesh."
  **Impl:** Heavy stat melee; pre-attached `deep_cut` (terrain carving). Highest base damage,
  slow. Showcases terrain-shaping melee.

- **venom_fang_blade — Venom Fang Blade** *(Uncommon · 0.45 · 3.5 · venom_edge)*
  > "A serpentine edge that injects venom on contact, poisoning foes that survive the cut."
  **Impl:** Stat melee; pre-attached `venom_edge`. DoT-oriented.

- **tide_caller — Tide Caller** *(Uncommon · 0.45 · 3.5 · soaking_strike)*
  > "A coral blade that weeps seawater, soaking foes and the ground for freeze combos."
  **Impl:** Stat melee; pre-attached `soaking_strike`. Setup weapon for freeze/anti-fire builds.

- **cinder_brand — Cinder Brand** *(Uncommon · 0.42 · 3.5 · ember_edge · crit 0.15/2.0/on_fire)*
  > "A smoldering sword that sets struck foes ablaze."
  **Impl:** Crit+status melee (mirrors `flame_sword`): crit applies `on_fire`; also pre-attached
  `ember_edge` for on-hit ignite. Fire build core.

- **glacier_edge — Glacier Edge** *(Uncommon · 0.45 · 3.5 · frostbite_edge · crit 0.15/2.0/chilly)*
  > "A blade of eternal ice that chills foes toward a killing freeze."
  **Impl:** Crit+status melee (mirrors `frost_sword`): crit applies `chilly`; pre-attached
  `frostbite_edge`. Freeze build core.

- **thunder_katana — Thunder Katana** *(Rare · 0.4 · 4.0 · chain_spark · crit 0.25/2.0)*
  > "A storm-forged katana whose critical cuts arc lightning between foes."
  **Impl:** Crit melee; pre-attached `chain_spark` (lightning arcs on crit). Needs `lightning`
  status (follow-up). High crit_chance to feed the arc.

- **gravedigger_spade — Gravedigger's Spade** *(Common · 0.6 · 4.5 · tunnel_borer)*
  > "A heavy spade that doubles as a tunneling tool, blasting through soft earth."
  **Impl:** Stat melee; pre-attached `tunnel_borer`. Mobility/utility starter that leans into
  terrain carving.

- **reaper_glaive — Reaper's Glaive** *(Rare · 0.55 · 6.0 · vampiric)*
  > "A soul-drinking glaive that mends its wielder with each life it reaps."
  **Impl:** Stat melee; pre-attached `vampiric` (heal on kill). Sustain weapon. Wide reach.

- **berserker_axe — Berserker's Axe** *(Rare · 0.6 · 6.0 · adrenaline)*
  > "The closer to death you swing, the harder it bites."
  **Impl:** Stat melee; pre-attached `adrenaline` (cooldown scales down as hp drops). High-risk
  weapon. Pairs with low-hp/glass builds.

- **mirror_blade — Mirror Blade** *(Uncommon · 0.45 · 4.0 · — )*
  > "A polished blade whose swing deflects incoming projectiles."
  **Impl:** New mechanic: the swing hitbox destroys/reflects enemy projectiles in its arc
  (extend the swing to test against enemy bullets, like `gleaming_projectile` but on the melee
  arc itself). Defensive melee.

- **whirlwind_blade — Whirlwind Blade** *(Uncommon · 0.55 · 4.5 · — )*
  > "A charged spin sweeps a full circle, striking every foe around the wielder."
  **Impl:** Charge weapon: tap = normal arc; full charge = 360° spin hitbox hitting all
  surrounding enemies. Reuse the charge API + a full-circle arc.

- **quake_hammer — Quake Hammer** *(Rare · 0.85 · 9.5 · shockwave_stomp)*
  > "A colossal maul whose charged slam sends a knockback shockwave through the ground."
  **Impl:** Heavy charge melee; pre-attached `shockwave_stomp`. Charged slam = big knockback +
  highest base damage, very slow.

- **soul_reaver — Soul Reaver** *(Rare · 0.5 · 5.0 · bloodlust)*
  > "A cursed blade that grows stronger with every soul it claims this fight."
  **Impl:** Stat melee; pre-attached `bloodlust` (stacking damage on kill). Snowball weapon for
  dense rooms.

### Ranged (10)

- **heavy_crossbow — Heavy Crossbow** *(Uncommon · 1.2 · 5.0 · piercing_lance)*
  > "Fires a single heavy bolt that punches through the first foe it meets."
  **Impl:** Single-shot ranged; pre-attached `piercing_lance` (penetration behavior). High
  per-shot damage, slow.

- **scatter_blunderbuss — Scatter Blunderbuss** *(Uncommon · 1.4 · 1.5 · — )*
  > "Belches a wide cone of pellets — devastating point-blank, near useless at range."
  **Impl:** Fan/spread ranged (reuse `fan_weapon`/`spread_shot`): many low-damage pellets in a
  wide cone, short projectile lifetime so damage falls off with range.

- **arc_railgun — Arc Railgun** *(Rare · 1.6 · 8.0 · penetrating_shockwave)*
  > "A charged rail-shot that pierces everything in a line."
  **Impl:** Charge ranged; pre-attached `penetrating_shockwave`. Full charge = high-damage
  line-piercing shot that also deletes enemy bullets. Reuse sniper/penetration.

- **flame_lobber — Flame Lobber** *(Uncommon · 1.5 · 3.0 · lava_emitter)*
  > "Lobs clay pots that shatter into pools of lava on impact."
  **Impl:** Lobbed/arcing projectile; on impact, spawn `MAT_LAVA` (the pre-attached
  `lava_emitter` fires at impact rather than swing — note the on-impact retrigger). Area denial.

- **frost_repeater — Frost Repeater** *(Uncommon · 0.8 · 2.0 · frostbite_edge)*
  > "A rapid bow that peppers foes with chilling icicles."
  **Impl:** Fast low-damage single-shot ranged; pre-attached `frostbite_edge` so each icicle
  applies `chilly`. Stacking chill → freeze at range.

- **venom_spitter — Venom Spitter** *(Uncommon · 1.3 · 2.5 · gas_emitter)*
  > "Spits globs that burst into clouds of poison gas."
  **Impl:** Single-shot ranged; on impact spawn `MAT_GAS` (pre-attached `gas_emitter` at impact).
  Lingering poison zones.

- **tesla_gun — Tesla Gun** *(Rare · 1.1 · 3.0 · chain_spark)*
  > "Fires forking bolts of lightning that leap between foes."
  **Impl:** Ranged; pre-attached `chain_spark` (arcs to nearby enemies on hit). Needs `lightning`
  status (follow-up).

- **chakram_launcher — Chakram Launcher** *(Uncommon · 1.2 · 3.5 · boomerang_arc)*
  > "Hurls a returning chakram that slices foes coming and going."
  **Impl:** Ranged; pre-attached `boomerang_arc` (return projectile). Hits on out + back legs.

- **seeker_launcher — Seeker Launcher** *(Rare · 1.5 · 4.0 · homing_hex)*
  > "Looses homing missiles that chase down fleeing foes."
  **Impl:** Ranged; pre-attached `homing_hex` (homing projectile). Strong vs mobile enemies.

- **hailstorm_bow — Hailstorm Bow** *(Rare · 1.4 · 2.5 · icicle_volley)*
  > "Rains a volley of icicles across a wide area."
  **Impl:** Ranged; pre-attached `icicle_volley` (existing: fires 5 icicles). Area chill.

---

## 5. Known follow-ups (out of scope this session)
1. **New modifiers have no behavior code** — `weapon_registry.gd` `modifier_scripts` has no
   entries for them; pre-attached references will warn/skip until a data-driven modifier
   runtime (reading the new columns) or per-modifier scripts exist.
2. **New weapons have no `.tres`** — `weapon_registry.gd` skips ids lacking
   `resources/weapons/<id>.tres`; rows are inert design data until those + scripts are added.
3. **New statuses** `lightning`/`steam` and a neutral **stun** status need `StatusDef` entries +
   reaction rules. `bounty` is a new economy `effect` verb; `concussive_edge`/`midas_touch`
   need hooks on the enemy stun and death/drop paths.
4. **New projectile behaviors** — `homing` and `return` steering on `projectile.gd`; the rest
   reuse existing bounce/penetration/split behaviors.
5. **No sprites** — textures reuse existing icon paths.
6. Phase 7 of `implementation_todo.md` is the home for building these out.

---

## 6. Acceptance for this session
- `modifiers.csv`: header extended; 11 existing rows backfilled; 46 new rows appended (57 total).
- `weapons.csv`: 28 new rows appended (51 total; 23 pre-existing).
- This spec committed.
