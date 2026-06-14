# Content Expansion — Weapons & Modifiers (Design Spec)

**Date:** 2026-06-14
**Branch:** feat/content-expansion
**Goal:** Expand build variation by documenting **~74 new entries** (46 modifiers + 28 weapons)
into `docs/design_docs/modifiers.csv` and `docs/design_docs/weapons.csv`.

**Scope:** *Documentation only.* No GDScript, no `.tres`, no sprites this session. New rows are
design-of-record for the existing Phase 7 (Content Expansion) implementation track.

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

> **Convention for tradeoff/dual-effect modifiers:** the prose `description` is authoritative;
> `magnitude2` carries the secondary value (e.g. Heavy Head: `magnitude`=damage add,
> `magnitude2`=cooldown multiplier). Flagged in the description.

### 2.4 Backfill of existing 11 modifiers

```
lava_emitter,Lava Emitter,...,Common,emitter,on_swing,,spawn_material,lava,16,0,No
green_crescent,Green Crescent,...,Uncommon,projectile,on_combo_step,,spawn_projectile,,1,0,No
fireball_fan,Fireball Fan,...,Common,projectile,on_swing,,spawn_projectile,on_fire,5,0,No
icicle_volley,Icicle Volley,...,Common,projectile,on_swing,,spawn_projectile,chilly,5,0,No
gleaming_projectile,Gleaming Projectile,...,Uncommon,projectile,on_swing,,spawn_projectile,,1,0,No
lightning_bolt,Lightning Bolt,...,Rare,projectile,on_hit,,spawn_projectile,lightning,1,0,No
arc_volley,Arc Volley,...,Rare,projectile,on_combo_step,,spawn_projectile,,7,0,No
triangular_volley,Triangular Volley,...,Rare,projectile,on_combo_step,,spawn_projectile,,13,0,No
bouncing_bullets,Bouncing Bullets,...,Uncommon,projectile,on_combo_step,,spawn_projectile,,4,0,No
splitting_rounds,Splitting Rounds,...,Uncommon,projectile,on_combo_step,,spawn_projectile,,3,4,No
penetrating_shockwave,Penetrating Shockwave,...,Rare,projectile,on_charge,,spawn_projectile,,1,0,No
```
(Existing descriptions preserved verbatim; only the new columns are appended.)

---

## 3. New modifiers (46)

### A. Emitters — spawn material on swing (7)
| id | name | rarity | element | mag |
|---|---|---|---|---|
| oil_emitter | Oil Emitter | Common | oil | 24 |
| water_emitter | Aqua Font | Common | water | 24 |
| gas_emitter | Miasma Vent | Uncommon | gas | 20 |
| frost_emitter | Frost Emitter | Uncommon | ice | 18 |
| blood_emitter | Sanguine Spray | Common | blood | 20 |
| coal_seeder | Coal Seeder | Uncommon | coal | 12 |
| dust_veil | Dust Veil | Common | dust | 20 |

### B. Status appliers on hit (6)
| id | name | rarity | status | stain |
|---|---|---|---|---|
| venom_edge | Venom Edge | Common | poisoned | 2.0 |
| soaking_strike | Soaking Strike | Common | wet | 2.0 |
| greased_edge | Greased Edge | Common | oiled | 2.0 |
| frostbite_edge | Frostbite Edge | Uncommon | chilly | 2.0 |
| ember_edge | Ember Edge | Uncommon | on_fire | 2.0 |
| rending_edge | Rending Edge | Common | bloody | 2.0 |

### C. Stat affixes (9)
| id | name | rarity | effect | element | mag | mag2 |
|---|---|---|---|---|---|---|
| sharpened | Sharpened | Common | stat_add | damage | 3 | 0 |
| heavy_head | Heavy Head | Common | stat_add | damage | 5 | 1.25 |
| honed_point | Honed Point | Uncommon | stat_add | crit_chance | 0.15 | 0 |
| executioners_mark | Executioner's Mark | Uncommon | stat_add | crit_multiplier | 0.5 | 0 |
| quickdraw | Quickdraw | Uncommon | stat_mult | cooldown | 0.8 | 0 |
| long_reach | Long Reach | Common | stat_mult | reach | 1.3 | 0 |
| wide_arc | Wide Arc | Common | stat_mult | arc | 1.4 | 0 |
| deep_cut | Deep Cut | Uncommon | stat_mult | carve_depth | 1.8 | 0 |
| fleetfoot | Fleetfoot | Uncommon | stat_mult | move_speed | 1.15 | 0 |

### D. Conditional "joker" triggers (10)
| id | name | rarity | trigger | condition | effect | element | mag | mag2 |
|---|---|---|---|---|---|---|---|---|
| frostbreaker | Frostbreaker | Uncommon | on_hit | target_status:frozen | stat_mult | damage | 1.6 | 0 |
| pyroclast | Pyroclast | Uncommon | on_hit | target_status:on_fire | stat_mult | damage | 1.5 | 0 |
| coup_de_grace | Coup de Grace | Uncommon | on_hit | target_low_hp | stat_mult | damage | 2.0 | 0.3 |
| bloodlust | Bloodlust | Rare | on_kill | | stat_add | damage | 1 | 8 |
| rampage | Rampage | Rare | on_hit | | stat_add | damage | 1 | 6 |
| glass_cannon | Glass Cannon | Rare | on_hit | self_full_hp | stat_mult | damage | 1.8 | 0 |
| vampiric | Vampiric | Uncommon | on_kill | | heal | | 3 | 0 |
| momentum | Momentum | Uncommon | on_hit | | stat_mult | damage | 1.5 | 0 |
| adrenaline | Adrenaline | Rare | passive | self_low_hp | stat_mult | cooldown | 0.6 | 0 |
| combo_keeper | Combo Keeper | Uncommon | every_n_hits | | stat_add | crit_chance | 1.0 | 5 |

### E. Projectile / on-swing (7)
| id | name | rarity | trigger | element | mag | mag2 |
|---|---|---|---|---|---|---|
| homing_hex | Homing Hex | Uncommon | on_swing | | 1 | 0 |
| chain_spark | Chain Spark | Rare | on_crit | lightning | 3 | 0 |
| ricochet_shard | Ricochet Shard | Uncommon | on_swing | | 1 | 3 |
| piercing_lance | Piercing Lance | Uncommon | on_swing | | 1 | 0 |
| cluster_bomb | Cluster Bomb | Rare | on_swing | on_fire | 8 | 0 |
| boomerang_arc | Boomerang Arc | Uncommon | on_swing | | 1 | 0 |
| spectral_echo | Spectral Echo | Rare | on_swing | | 1 | 0 |

### F. Terrain & utility (7)
| id | name | rarity | trigger | effect | mag | mag2 |
|---|---|---|---|---|---|---|
| tunnel_borer | Tunnel Borer | Uncommon | on_swing | carve | 32 | 0 |
| shockwave_stomp | Shockwave Stomp | Uncommon | on_swing | knockback | 40 | 0 |
| magnet_field | Magnet Field | Common | on_swing | pull | 48 | 0 |
| repulsor_nova | Repulsor Nova | Rare | on_charge | knockback | 80 | 0 |
| concussive_edge | Concussive Edge | Uncommon | on_hit | stun | 0.5 | 0.2 |
| midas_touch | Midas Touch | Uncommon | on_kill | bounty | 5 | 0 |
| steam_burst | Steam Burst | Rare | on_hit (target_status:wet) | apply_status (steam) | 3 | 0 |

---

## 4. New weapons (28)

Schema unchanged: `id,name,description,type,rarity,cooldown,damage,weapon_texture,
modifier_slots,pre_attached_modifier1..3,crit_chance,crit_multiplier,crit_status`.
Mechanics live in the prose `description`. Textures reuse existing icons (no sprites):
- **MEL** = `res://textures/Weapons/sword_01c.png`
- **RNG** = `res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/16x16/bow_01a.png`

All weapons have 3 modifier slots.

### Melee (18)
| id | name | rarity | cd | dmg | pre-attached | crit |
|---|---|---|---|---|---|---|
| iron_mace | Iron Mace | Common | 0.7 | 6.0 | — | |
| rapier | Rapier | Uncommon | 0.3 | 2.5 | — | 0.3 / 2.0 |
| cleaver | Bone Cleaver | Common | 0.55 | 5.0 | rending_edge | |
| war_scythe | War Scythe | Uncommon | 0.6 | 5.5 | wide_arc | |
| twin_daggers | Twin Daggers | Uncommon | 0.28 | 1.8 | — | |
| obsidian_greatsword | Obsidian Greatsword | Rare | 0.8 | 9.0 | deep_cut | |
| venom_fang_blade | Venom Fang Blade | Uncommon | 0.45 | 3.5 | venom_edge | |
| tide_caller | Tide Caller | Uncommon | 0.45 | 3.5 | soaking_strike | |
| cinder_brand | Cinder Brand | Uncommon | 0.42 | 3.5 | ember_edge | 0.15 / 2.0 / on_fire |
| glacier_edge | Glacier Edge | Uncommon | 0.45 | 3.5 | frostbite_edge | 0.15 / 2.0 / chilly |
| thunder_katana | Thunder Katana | Rare | 0.4 | 4.0 | chain_spark | 0.25 / 2.0 |
| gravedigger_spade | Gravedigger's Spade | Common | 0.6 | 4.5 | tunnel_borer | |
| reaper_glaive | Reaper's Glaive | Rare | 0.55 | 6.0 | vampiric | |
| berserker_axe | Berserker's Axe | Rare | 0.6 | 6.0 | adrenaline | |
| mirror_blade | Mirror Blade | Uncommon | 0.45 | 4.0 | — | |
| whirlwind_blade | Whirlwind Blade | Uncommon | 0.55 | 4.5 | — | |
| quake_hammer | Quake Hammer | Rare | 0.85 | 9.5 | shockwave_stomp | |
| soul_reaver | Soul Reaver | Rare | 0.5 | 5.0 | bloodlust | |

### Ranged (10)
| id | name | rarity | cd | dmg | pre-attached |
|---|---|---|---|---|---|
| heavy_crossbow | Heavy Crossbow | Uncommon | 1.2 | 5.0 | piercing_lance |
| scatter_blunderbuss | Scatter Blunderbuss | Uncommon | 1.4 | 1.5 | — |
| arc_railgun | Arc Railgun | Rare | 1.6 | 8.0 | penetrating_shockwave |
| flame_lobber | Flame Lobber | Uncommon | 1.5 | 3.0 | lava_emitter |
| frost_repeater | Frost Repeater | Uncommon | 0.8 | 2.0 | frostbite_edge |
| venom_spitter | Venom Spitter | Uncommon | 1.3 | 2.5 | gas_emitter |
| tesla_gun | Tesla Gun | Rare | 1.1 | 3.0 | chain_spark |
| chakram_launcher | Chakram Launcher | Uncommon | 1.2 | 3.5 | boomerang_arc |
| seeker_launcher | Seeker Launcher | Rare | 1.5 | 4.0 | homing_hex |
| hailstorm_bow | Hailstorm Bow | Rare | 1.4 | 2.5 | icicle_volley |

---

## 5. Known follow-ups (out of scope this session)
1. **New modifiers have no behavior code** — `weapon_registry.gd` `modifier_scripts` has no
   entries for them; pre-attached references will warn/skip until a data-driven modifier
   runtime (reading the new columns) or per-modifier scripts exist.
2. **New weapons have no `.tres`** — `weapon_registry.gd` skips ids lacking
   `resources/weapons/<id>.tres`; rows are inert design data until those + scripts are added.
3. **New statuses** `lightning`/`steam` need `StatusDef` entries + reaction rules.
4. **No sprites** — textures reuse existing icon paths.
5. Phase 7 of `implementation_todo.md` is the home for building these out.

---

## 6. Acceptance for this session
- `modifiers.csv`: header extended; 11 existing rows backfilled; 46 new rows appended (57 total).
- `weapons.csv`: 28 new rows appended (52 total).
- This spec committed.
