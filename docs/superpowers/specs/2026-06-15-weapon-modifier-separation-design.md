# Weapon / Modifier Separation Redesign

**Date:** 2026-06-15
**Branch:** feat/content-expansion
**Scope:** `docs/design_docs/weapons.csv` (data) + native weapon mechanics (code, designed ahead)

## Problem

~22 of the content-expansion weapons are `generic blade + one welded modifier`. Strip
the pre-attached modifier and the weapon has no identity of its own. This defeats the
modifier system: a weapon should be interesting *bare*, and a modifier should create an
*emergent* reaction with the weapon's shape — the way `bone_dagger` (fastest + weakest)
turns an emitter modifier into a stream of material.

Two failure modes are mixed together:

- **Type 1 — the modifier IS the fantasy.** e.g. `chakram_launcher`+`boomerang_arc`,
  `seeker_launcher`+`homing_hex`, `arc_railgun`+`penetrating_shockwave`. The weapon name
  literally describes the modifier; nothing remains if removed.
- **Type 2 — the modifier is a flavor coat.** e.g. `venom_fang_blade`+`venom_edge`,
  `cleaver`+`rending_edge`. Removing it leaves a plain stat-stick.

## Design principle: two levers

Each reworked weapon is fixed by pulling exactly one lever.

### Lever 1 — Fold native (for Type 1)

The signature behavior becomes an **intrinsic, hard-coded weapon property** and the
pre-attached modifier slot is **freed**. The chakram returns natively; the seeker homes
natively; the hailstorm fires a volley natively.

**Important:** folding native does **not** remove the corresponding modifier from
`modifiers.csv`. The modifier still exists in the drop pool and can be applied to *other*
weapons. The weapon simply owns its behavior in code rather than borrowing it from a
removable modifier. (e.g. `tunnel_borer` and `deep_cut` remain available modifiers even
though Gravedigger's Spade and Obsidian Greatsword carve natively.)

The freed slot now invites emergent choices — a native-volley bow + `ember_edge` = a wall
of burning arrows.

### Lever 2 — Stat-niche (for Type 2)

Give the weapon a distinct stat *shape* — a speed/reach/arc/crit extreme — that elevates a
whole *category* of modifier, exactly like `bone_dagger`. The weapon plays differently bare,
and the old baked modifier becomes the obvious-but-optional pairing.

### Signature exceptions

`flame_blade` and `flame_lobber` intentionally keep `lava_emitter` — "I make lava" is their
entire fantasy. These are the only weapons that retain a pre-attached modifier.

## Melee niche taxonomy (Lever 2)

| Niche | Stat shape | Modifier category it elevates |
|---|---|---|
| **Flurry** | fast, low dmg, short reach | on-hit edges & emitters (spam/stack fast) |
| **Crowd-sweep** | wide arc, low-mid dmg, multi-target | on-hit status (spreads to pack), knockback |
| **Heavy-hit** | slow, huge single dmg, high crit-mult | crit-mult, execute, conditional multipliers |
| **Crit-engine** | very high crit-chance, low crit-mult | on-crit mods (`chain_spark`) proc constantly |
| **Attrition** | sustain / per-kill scaling | on-kill mods (`bloodlust`, `vampiric`, `midas`) |

## Per-weapon redesign

Stats are `cooldown / damage`, plus crit fields where relevant. "Slot" = state of the
pre-attached modifier slot after the change.

### Melee

| Weapon | Lever | Native identity | Stats | Slot | Emergent synergy |
|---|---|---|---|---|---|
| Bone Cleaver | L2 Crowd-sweep | Wide 120° front arc, low per-hit, hits front pack | 0.5 / 4.0 | freed | any on-hit edge spreads to the whole pack |
| War Scythe | L2 Crowd-sweep (surround) | Long reach, hits flanks **and behind** | 0.62 / 5.0 | freed | on-hit edges + `shockwave_stomp` / `magnet_field` |
| Obsidian Greatsword | L2 Heavy-hit **+ native free carve (all terrain)** | Slowest, biggest blow; tiny crit chance, crits delete; carves any terrain | 0.85 / 9.5, crit 0.05 / x3.0 | freed | `executioners_mark`, `coup_de_grace`, fire mods; `deep_cut` deepens carve further |
| Venom Fang Blade | L2 Flurry+reach | Fast serpent lunge, long thrust reach, low dmg | 0.32 / 2.5 | freed | `venom_edge` and any status stack fast; `rampage` / `momentum` |
| Tide Caller | L2 (native crit-status) | Crits **soak** foes (wet) — reaction enabler | 0.45 / 3.5, crit 0.15 / x2.0, crit=wet | freed | frost mods (wet+chilly = freeze), lightning (wet = shock) |
| Cinder Brand | L2 Crit-engine (fire) | High crit chance ignites often; crits burn | 0.4 / 3.5, crit 0.25 / x2.0, crit=on_fire | freed | `pyroclast`, oil/lava emitters, `chain_spark` |
| Glacier Edge | L2 Heavy/control | Slow control blade; crits freeze | 0.5 / 4.0, crit 0.20 / x2.0, crit=chilly | freed | `frostbreaker`, water/frost emitters |
| Thunder Katana | L2 Crit-engine (melee crit king) | Fastest precise katana, highest melee crit chance | 0.38 / 4.0, crit 0.35 / x2.0 | freed | `chain_spark` fires nonstop; `combo_keeper`, `executioners_mark` |
| Gravedigger's Spade | L1 fold-native | Native **free carve of all terrain**; slow blunt hit | 0.6 / 4.5 | freed | `concussive_edge`, `midas`; `tunnel_borer` still attachable elsewhere |
| Reaper's Glaive | L1 fold-native | Long reach + small native heal on kill | 0.55 / 6.0 | freed | `bloodlust` / `vampiric` stack on top |
| Berserker's Axe | L1 fold-native | Native damage ramp as HP drops | 0.6 / 6.0 | freed | `adrenaline` (speed ramp) stacks; `coup_de_grace` |
| Quake Hammer | L1 fold-native | Charged slam shockwave intrinsic | 0.85 / 9.5 | freed | `repulsor_nova`, `concussive_edge` |
| Soul Reaver | L1 fold-native | Native per-kill damage stacking (this fight) | 0.5 / 5.0 | freed | `rampage`, `vampiric`, `midas` |

### Ranged

| Weapon | Lever | Native identity | Stats | Slot | Emergent synergy |
|---|---|---|---|---|---|
| Heavy Crossbow | L1 fold-native | Heavy bolt pierces the whole line natively | 1.2 / 5.0 | freed | on-hit edges hit everyone in line |
| Arc Railgun | L1 fold-native | Charge-to-fire piercing rail intrinsic | 1.6 / 8.0 | freed | on-charge mods, projectile adds |
| Flame Lobber | **signature keep** | Arcing lob; lava is its signature payload | 1.5 / 3.0 | `lava_emitter` | `oil` / `coal` emitters, `greased_edge` |
| Frost Repeater | L2 Flurry (ranged) | Fastest-firing bow, low dmg | 0.6 / 1.8 | freed | rapid fire stacks any status fast |
| Venom Spitter | L1 fold-native | Globs burst into a lingering ground hazard | 1.3 / 2.5 | freed | stack `venom_edge`, water/frost combos |
| Tesla Gun | L1 fold-native | Bolts fork/chain between foes natively | 1.1 / 3.0 | freed | `chain_spark` adds arcs on crit; edges spread along chain |
| Chakram Launcher | L1 fold-native | Chakram returns, hits coming and going | 1.2 / 3.5 | freed | on-hit edges apply twice |
| Seeker Launcher | L1 fold-native | Missiles home natively | 1.5 / 4.0 | freed | reliable status delivery |
| Hailstorm Bow | L1 fold-native | Fires a volley across an area natively | 1.4 / 2.5 | freed | per-projectile edges = a wall of status |

### Untouched

Hand-designed originals and already-native weapons stay as-is: rusty_sword, bone_dagger,
broad_axe, flame_blade (signature), throwing_knife, fire_orb, spread_shot, boss_staff,
willowblade, flame_sword, frost_sword, qinggang_sword, blood_blade, tao_sword, dragon_fang,
heavenly_sword, grand_knight_sword, deep_dark_blade, broadsword, executioner, void_sword,
caliburn, phantom_blade, iron_mace, rapier, twin_daggers, mirror_blade, whirlwind_blade,
scatter_blunderbuss.

## CSV changes

For each reworked weapon, update `weapons.csv`:

- Clear `pre_attached_modifier1..3` (except `flame_lobber`, which keeps `lava_emitter`).
- Apply the new `cooldown` / `damage` values.
- Set `crit_chance` / `crit_multiplier` / `crit_status` where the redesign specifies them
  (Obsidian, Tide Caller, Cinder Brand, Glacier Edge, Thunder Katana).
- Rewrite the `description` so the native identity reads clearly and the emergent modifier
  synergy is implied (not stated as a built-in).

`modifiers.csv` is **not** modified.

## Native mechanics to implement later (designed ahead)

These behaviors are described in the weapon data but require engine work. Listed so they are
not lost:

- **Free terrain carving** as a native weapon flag (Obsidian Greatsword: all terrain;
  Gravedigger's Spade: all terrain). Distinct from `deep_cut` / `tunnel_borer` modifiers.
- **Native heal-on-kill** (Reaper's Glaive, lighter than `vampiric`).
- **Native low-HP damage ramp** (Berserker's Axe).
- **Native per-kill damage stacking** (Soul Reaver, resets per fight).
- **Native charged shockwave** (Quake Hammer).
- **Native projectile behaviors:** line-pierce (Heavy Crossbow), charged piercing rail
  (Arc Railgun), area-denial splat (Venom Spitter), chain/fork (Tesla Gun), return
  (Chakram Launcher), homing (Seeker Launcher), area volley (Hailstorm Bow).
- **Surround/rear arc** (War Scythe) and **wide front arc** (Bone Cleaver) as native arc
  shapes.

## Open follow-ups

- Cinder Brand / Glacier Edge sit near hand-designed `flame_sword` / `frost_sword`;
  differentiated by stat-shape (fast crit-engine vs slow control). Revisit if they feel
  redundant in play.
