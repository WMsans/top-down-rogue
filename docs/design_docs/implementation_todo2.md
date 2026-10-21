# Implementation Todo List — Content Expansion & Polish

Based on gameplay.md design document. Companion to implementation_todo1.md (core systems).

---

## Phase 0: Combat Rework (Katana ZERO offense / Soul Knight defense)

See gameplay.md §2 for the rules. Weapon and modifier descriptions in `weapons.csv` / `modifiers.csv` already describe the new behavior; code and stat columns still need to catch up.

### Player Armor & Health
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P0 | Medium | Armor + HP model | `player_inventory.gd`: replace `max_health = 100` with 3 HP + 3 armor. A hit costs 1 point, armor first. Keep 1.0s i-frames. Emit `armor_changed` alongside `health_changed`. |
| x | P0 | Medium | Armor regeneration | After 3s with no hit or tick, regen +1 armor per 1s until full. Any hit or DoT tick resets the 3s timer. HP never regenerates. |
| x | P0 | Medium | DoT routing | `take_status_damage` costs 1 point per tick, armor first, bypassing i-frames. Tick rates: fire 1/1s, poison 1/1.5s, steam 1/1s. Shorten player-side status durations so a typical burn costs ~2 points. |
|  | P1 | Low | Healing sources | Boss kill: +1 HP and full armor. `heal()` works in whole HP points. Remove any heal path not listed in gameplay.md §2. |
|  | P1 | Medium | Shop "Mend" service | Restore 1 HP. Cost curve like the removal service (base + per-use increment). Unavailable at full HP. |
|  | P1 | Low | Max armor modifiers | Support max-armor changes from modifiers (`glass_cannon`: −2 max armor). Clamp current armor on change. |

### Enemy Hit Model
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P0 | Medium | Hit-count health | `enemy.gd`: replace `max_health`/damage with a hit count. Normal = 1, elite = 2, TANK elite = 3. Any hit source (swing, projectile, explosion, status tick) = 1 hit. Remove `_apply_elite_scaling` HP multipliers. |
| x | P0 | Low | Unified post-hit invulnerability | Elites and bosses ignore further hits for 0.3s after taking one. Elite flashes + staggers on the first hit. |
| x | P0 | Medium | Boss hit pools | `boss_enemy.gd`: replace 200 HP with 3 phases × 10 hits (baseline). Phase transitions trigger on hit count, not HP thresholds, and cleanse statuses. |
| x | P0 | Medium | Remove enemy damage stats | Every enemy attack costs the player exactly 1 point. Drop damage scaling (`_apply_damage_scale`) and per-floor HP/damage curves. Note: keystone's "+100%" amplification is gone with the damage model (its dead `DAMAGE_MULT` was dropped) — only the slot-focus behaviour remains; Plan 3 must restore it. |
| x | P1 | Medium | Elite abilities under hit counts | ENRAGE triggers after the first hit (was <30% HP). TANK = 3 hits (was 2× HP). FAST / TELEPORT unchanged. |
|  | P1 | Medium | Behavior-based difficulty | EASY / NORMAL / HARD tiers become behavior profiles (telegraph length, attack cadence, projectile count). Floor scaling raises these and enemy count, not stats. |

### Damage & Crit Removal
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P0 | Medium | Rename `damage` → `dig_power` | CSV column + `Weapon` resource + registry. Dig power only drives terrain carving. Re-assign values by archetype: daggers/rapiers low; axes/maces/hammers/greatswords high; Gravedigger's Spade and Obsidian Greatsword highest. Note: modifiers whose CSV `element` is still `damage` match no stat and are inert — `bloodlust`, `frostbreaker`, `pyroclast`, `coup_de_grace`, `rampage`, `glass_cannon`, `momentum`, `greedy_edge`; Plan 3 must re-point them. |
| x | P0 | Medium | Remove crit | Drop `crit_chance`, `crit_multiplier`, `crit_status` from CSV, `Weapon`, and hit resolution. Weapons that used `crit_status` now use `hit_status` or their new trait (see `weapons.csv`). Delete/rewrite crit tests (`test_weapon_crit*.gd`). Note: `honed_point` and `executioners_mark` still name the deleted crit stats (`crit_chance`, `crit_multiplier`) and are inert; Plan 3 must re-point them. |
| x | P1 | Low | Remove damage numbers | Floating damage numbers no longer apply. Replace with hit feedback only (flash, stagger, elite first-hit marker). |
|  | P1 | Low | Rename weapons | `thunder_katana` → display name "Katana", `twin_daggers` → "Jack and Mary" (done in CSV; keep ids). Update any hard-coded names/tests. |

### Weapon Behavior Rework
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P0 | High | Implement reworked weapon traits | Make each weapon match its new `weapons.csv` description: Fire Orb (AoE explosion), Willowblade (charged blade wave), Flame/Frost Sword + Tide Caller (status on every hit), Heavenly Sword (frost burst on kill), Glacier Edge (chill → freeze), Cinder Brand (kills burst into flame), Caliburn (sword beam every 3rd swing), Katana (dash-slash, kill refunds cooldown), Rapier (line pierce), Iron Mace (stun on hit), Jack and Mary (front + back strike), Reaper's Glaive (1/10 heal on kill), Berserker's Axe (faster at low armor), Soul Reaver (stacking reach/arc), Arc Railgun (charge → beam size). |
|  | P0 | Medium | Charge = shape, not hits | Charged attacks change arc/reach/pierce/shockwave/pull only. Never count as more than 1 hit. |

### Modifier Effect Rework
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P0 | High | Stat modifiers | sharpened (+3 dig), heavy_head (stun + knockback, −25% swing speed), honed_point (+30% projectile speed/lifetime), glass_cannon (−2 max armor, +40% swing speed, +30% reach), slot_harmony (+20% swing speed). |
|  | P0 | High | On-kill modifiers | chain_spark (1/4 lightning arc), hemophilia (1/5 bloody burst), pyroclast (1/10 fire patch), combo_keeper (kill streak shockwave), overkill (piercing shard), headsman (50% cooldown refund), bloodlust (stacking swing speed), vampiric (skip armor-regen delay), executioners_mark (mark → armor). See `modifiers.csv` for final text. |
|  | P0 | High | Consume modifiers | combustion (+30% reach 1s), necrosis (+30% swing speed 1s), frostshatter (+30% move speed 1s), rupture (+50% dig 1s). Each consumes its status on hit. |
|  | P0 | Medium | Conditional modifiers | frostbreaker (spread Chilly), coup_de_grace (finishing elite/boss phase refunds swing + 1 armor), rampage (hit streak → reach), momentum (move speed → swing speed), greedy_edge (gold → reach), adrenaline (armor break → +40% move speed 2s), last_stand (1/2 shockwave after being hit). |
|  | P1 | Medium | Chance system + Executioner's Mark | Central chance helper for all chance-based weapon/modifier effects. Executioner's Mark adds +1/4 to every chance on its weapon, capped at 1. |

### HUD & Tests
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P0 | Medium | Hearts + shields HUD | Replace the health bar with 3 heart icons (HP) and 3 shield icons (armor). Shields refill visibly as armor regenerates. Supports changed max armor. |
|  | P0 | Medium | Update unit tests | Rewrite tests that assume HP/damage/crit (`test_player_health_fraction`, `test_weapon_crit*`, `test_weapon_balance`, `test_charge_weapon_ratio`, `test_boss_phase_transition`, `test_modifier_stacking`, etc.). Add tests for armor regen, DoT routing, hit counts and 0.3s invulnerability. |
|  | P2 | Low | Resync Chinese CSVs | `weapons-chinese.csv` / `modifiers-chinese.csv` are already stale (fewer rows). Resync names and descriptions once English text settles. |

---

## Phase 1: Balancing & Tuning

### Economy Balancing
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P0 | Medium | Shop modifier pricing audit | Set per-rarity baseline, based on playtesting. |
| x | P0 | Medium | Shop weapon pricing audit | Set per-rarity baseline, based on playtesting. |
| x | P0 | Medium | Removal service cost curve | Tune `remove_cost = 60 + 30*uses`. Verify against 5-floor economy so ~2–3 removals feel painful but reachable. |
| x | P1 | Medium | Gold drop rates | Enemy kill gold: calibrate tier weights based on playtesting. Chest gold: calibrate per-rarity fixed amounts. |
| x | P1 | Medium | Floor-scaling economy | Tune gold multiplier per floor depth (1.0×, 1.15×, 1.3×, …). Ensure floor-1 shops are affordable; floor-5 shops require saving. |
| x | P2 | Low | Per-biome economy skew | Balance biome-specific gold adjustments (e.g., vault +20% gold, magma -10% but more enemies). |

### Weapon Balance
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P0 | High | Full weapon stat audit (51 weapons) | Re-audit after the combat rework. Verify every weapon's cooldown/reach/arc/dig_power against its rarity and archetype on the Coverage / Tempo / Utility axes (gameplay.md §4). Identify over/underperformers. See `weapons.csv`. |
|  | P0 | Medium | Rarity-to-power curve | Replace DPS ranges with the "rarity buys behavior" rule: Common = plain shape, strong on one axis; Uncommon = + one trait; Rare = signature mechanic, solid on two axes. |
|  | P1 | Medium | Melee vs. ranged balance | Ranged pays for range with tempo: longer cooldowns, projectiles stop at the first enemy unless piercing. Tune cooldowns and projectile lifetimes. |
|  | P1 | Medium | Archetype power budget | Each weapon archetype gets a power budget across Coverage / Tempo / Utility plus native traits. Verify no archetype dominates its tier. |
|  | P1 | Medium | Pre-attached modifier valuation | Weapons with pre-slotted modifiers pay a stat penalty. Audit that penalty is consistent (e.g., −reach/arc or +0.05s cd per pre-attached Uncommon+ mod). |
|  | P2 | Low | Charge weapon balance | Charge weapons trade tempo for attack shape (bigger arc/reach, pierce, shockwave, pull). Verify each charge payoff is worth its wind-up. Hits stay at 1. |

### Modifier Balance
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P0 | High | Full modifier stat audit (80 modifiers) | Re-audit after the combat rework. Verify every modifier's magnitude/magnitude2 against rarity. See `modifiers.csv`. Identify degenerate combos (especially on-kill chains and chance stacking with Executioner's Mark). |
|  | P0 | High | Stacking sanity check | Audit additive vs. multiplicative stacking. `stat_add` sums first, `stat_mult` applies after. Cap cooldown floor at ~0.1s. Cap every chance at 1.0. Cap reach/swing-speed stacks (rampage, greedy_edge, bloodlust, soul_reaver). |
|  | P1 | Medium | Conditional trigger payoff | Conditional modifiers (frostbreaker, pyroclast, coup_de_grace, glass_cannon, last_stand) must make their condition worth setting up. Verify chances and buff magnitudes. |
| x | P1 | Medium | Emitter blob sizing | Oil/water/gas/ice/blood/coal/dust blob radii: verify they create meaningful area effects without griefing player pathing or tanking FPS. |
|  | P1 | Medium | Status stack thresholds | Verify stain thresholds in `status_registry.gd`: on_fire=1.0, wet=1.0, oiled=1.0, chilly=1.0, frozen=3.0, poisoned=0.3, bloody=1.0. Retune for one-hit kills: a single hit on an elite should be able to apply a status whose next tick finishes it. Player-side durations: a typical burn costs ~2 points. |
| x | P2 | Low | Anti-synergy costs | Document and verify anti-synergies: wet douses fire, oiled amplifies fire. Players running conflicting modifiers should feel the cost. |
| x | P2 | Low | Rarity distribution in shops | 5 modifier cards per shop: tune rarity weights so shops feel varied (target ~60% Common, ~30% Uncommon, ~10% Rare). |

### Enemy Balance
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P0 | High | Per-floor behavior curve | Floor scaling via behavior, not stats: enemy count, telegraph length, attack cadence, projectile count, elite frequency. Floor 1 baseline; each floor tightens these. |
|  | P0 | Medium | Enemy tier behavior profiles | EASY / NORMAL / HARD differ in telegraph length, attack cadence and projectile count. Verify each tier reads differently and stays fair against 3 armor + 3 HP. |
|  | P1 | Medium | Elite tuning | Elites: 2 hits (TANK 3), 1.3× speed, plus their ability. Verify elite fights feel like minibosses that demand two clean actions, not a burst. |
|  | P1 | Medium | Boss hit pool tuning | Baseline 3 phases × 10 hits with 0.3s post-hit invulnerability (≥ ~3s minimum per phase). Tune per boss so phases last long enough to show their mechanics. |
|  | P1 | Medium | Player survivability tuning | Tune armor regen delay (3s) and rate (1/s), i-frames (1.0s) and status tick rates against real encounters. Target: a clean room costs 0–2 armor; mistakes cost HP. |
|  | P1 | Medium | Mob density tuning | Per-floor mob cap (25). Per-room enemy counts: calibrate so corridors feel navigable but rooms feel dangerous. |
|  | P1 | Medium | Ranged enemy spacing | Ranged enemies maintain `preferred_distance` 120px. Verify this creates interesting positioning without kiting frustration. |
|  | P2 | Low | Biome enemy difficulty skew | Frozen: slower but tankier. Magma: faster but fragile. Mines: mixed. Vault: elite-heavy. Caves: baseline. |
|  | P2 | Low | Drop rate calibration | Verify ~30% weapon drop, ~10% modifier drop on regular enemies. Bosses: 100% weapon + guaranteed RARE modifier. |

---

## Phase 2: Enemy Design & Variety

### Enemy Visual Identity
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | High | Enemy sprite art — melee set | Commission/create distinct sprites for ~5 melee enemy variants (grunt, brute, fast skirmisher, armored, cultist). Currently colored rects. |
|  | P1 | High | Enemy sprite art — ranged set | Distinct sprites for ~3 ranged enemy variants (archer, mage, lobber). Must read as "ranged" at a glance. |
|  | P2 | Medium | Enemy sprite art — elite set | Visually-upgraded variants of base enemies: glowing outlines, larger scale, distinct color palette. |
|  | P2 | Medium | Per-biome enemy palettes | Caves: earthy browns. Magma: reds/oranges. Frozen: blues/whites. Mines: greys. Vault: golds/metallics. Skin existing sprites per biome. |
|  | P2 | Low | Enemy death animations | Sprites scale-to-zero over 0.3s (exists). Add: directional knockback rotation, dissolve-to-particles for elites/bosses. |

### Enemy Behavior Depth
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | High | Melee enemy sub-behaviors | Add 2–3 distinct melee AI patterns beyond CHASE→WINDUP: flanker (strafes before engaging), rusher (shorter settle timer), ambusher (no wander, waits then lunges). |
|  | P1 | Medium | Ranged enemy sub-behaviors | Add: kiter (retreats more aggressively), turret (stops moving to fire faster), skirmisher (fires then repositions). |
|  | P1 | Medium | Exclamation telegraph polish | "!" popup on WINDUP: ensure it's visible through terrain/VFX. Tune scale/fade timing to feel consistent with Soul Knight / Dead Cells. |
|  | P2 | Medium | Enemy-environment interaction | Enemies react to hazards: avoid lava/fire, path around gas clouds, get slowed in ice. |
|  | P2 | Medium | Enemy separation steering tuning | Min gap 16px. Tune repulsion force to prevent stacking without pushing enemies through walls. |
|  | P2 | Low | Wander behavior variety | Wander patterns vary by enemy type: patrols (grunt), random drift (skirmisher), stationary guard (turret). |
|  | P3 | Low | Enemy hurt reactions | Enemies stagger/knockback on hit (exists). Add: directional knockback based on hit angle, a clear "one hit left" read on elites after their first hit. |

### Enemy Content Expansion
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | High | 5+ melee enemy variants | Author behaviors for grunt (balanced), brute (slow, long telegraph, wide attack), skirmisher (fast, short telegraph), armored (anti-knockback, frontal guard), cultist (poison-on-hit). All die in one hit. |
|  | P1 | High | 3+ ranged enemy variants | Author stats + behaviors for archer (straight projectile), mage (slow homing orb), lobber (arcing AoE shot). |
|  | P2 | Medium | Per-biome enemy roster | Each biome gets 2–4 unique enemy types. Caves: bats + crawlers. Magma: fire imps + lava slugs. Frozen: ice wraiths + frost giants. Mines: constructs + miners. Vault: guardians + sentinels. |
|  | P2 | Medium | Elite ability variants | Author + balance the 5 elite abilities (FAST, TANK, TELEPORT, ENRAGE). Add 2 more: SUMMONER (spawns minions on hit), SHIELD (periodic invuln bubble). |
|  | P3 | Low | Rare spawn enemies | 1–2 special enemies per biome with unique drops (e.g., Golden Slime drops extra gold, Crystal Golem drops guaranteed modifier). |

---

## Phase 3: Boss Design

### Boss Mechanics & Phases
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | High | 3-phase boss system polish | Phases advance on hit count. Verify no skipped phases when several hits land together (0.3s invulnerability, status cleanse on transition). Ensure each phase escalates visually and mechanically. |
|  | P1 | High | Phase 1 — Single threat | Boss fires basic projectiles at player. ~1 attack pattern. Player learns the rhythm. |
|  | P1 | High | Phase 2 — Spread/area | Boss adds spread fire (3-projectile fan, 30°). Arena becomes hazardous. Player must reposition. |
|  | P1 | High | Phase 3 — Arena hazard | Boss spawns lava pools / gas clouds at random arena positions every `hazard_interval` (5s). Player fights boss AND environment. |
|  | P2 | High | Per-boss unique phase mechanics | Each boss archetype gets 1 unique phase ability beyond the default 3-phase template: summon minions, terrain-warp, bullet-hell spiral, charge-dash, arena-wide pulse. |

### Per-Biome Boss Design
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | High | Caves boss "Burrower" | Giant burrowing worm/beetle. Phase 1: charges at player. Phase 2: spawns dust clouds. Phase 3: creates collapsing floor pits. |
|  | P1 | High | Magma boss "Pyrelord" | Fire elemental. Phase 1: fire orbs. Phase 2: lava trail. Phase 3: arena ignites in ring pattern. |
|  | P1 | High | Frozen boss "Glacier Titan" | Ice construct. Phase 1: ice shards. Phase 2: freeze patches (chilly zones). Phase 3: summons ice pillars as cover/walls. |
|  | P2 | High | Mines boss "Drill Construct" | Mechanical boss. Phase 1: drill charge. Phase 2: explosive mine scatter. Phase 3: arena walls reconfigure (pillars rise/fall). |
|  | P2 | High | Vault boss "Golden Warden" | Armored guardian. Phase 1: ricochet shots. Phase 2: magnet pull (drags player closer). Phase 3: spawns elite adds + gold rain. |

### Boss Presentation
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | High | Boss sprite art (5 biomes) | Distinct, large sprites for each boss. Must read as "boss" at a glance — 2–3× normal enemy size, unique silhouette. |
|  | P1 | Medium | Boss name + hit bar HUD | Large boss bar at top of screen with boss name, segmented by remaining hits. Phase indicators and phase-gate markers visible on bar. |
|  | P1 | Medium | Boss intro animation | Brief entrance sequence when player enters arena: camera zoom/pan, boss emerges, name banner. |
|  | P2 | Medium | Boss death sequence | Explosive death, camera shake, portal appears in center of boss remains. Weapon drop flies out. |
|  | P2 | Medium | Boss arena music sting | Unique boss music theme or layer that kicks in when boss fight starts (FMOD). |
|  | P2 | Low | Boss telegraph variety | Each unique attack gets a distinct telegraph: ground-crack line for charge, expanding circle for AoE pulse, flashing projectiles for bullet patterns. |

---

## Phase 4: Audio (FMOD)

### FMOD Integration
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | High | FMOD Studio integration | Set up FMOD Engine for Godot 4. Build FMOD banks pipeline: Master Bank, Music Bank, SFX Bank. |
|  | P1 | High | FMOD Studio project | Create FMOD Studio project with event hierarchy: Music, SFX_UI, SFX_Combat, SFX_Environment, SFX_Materials. |
|  | P1 | Medium | Bank loading/unloading | Implement dynamic bank loading per floor/biome. Preload common banks; stream per-biome content. |
|  | P2 | Medium | FMOD autoload/manager | Create `FmodManager` autoload: expose `play_event(path)`, `set_parameter(name, value)`, `stop_event(path)`. |

### Music
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | High | Main menu theme | Ambient/dark fantasy vibe. Loops. Sets game tone. Reference: Dead Cells menu. |
|  | P1 | High | Per-biome floor music (5 tracks) | Caves: ambient/drone. Magma: driving percussion. Frozen: ethereal/piano. Mines: industrial/rhythmic. Vault: regal/tense. |
|  | P1 | Medium | Boss music layer | FMOD parameter-driven intensity: normal floor music → boss intro sting → boss combat layer (higher BPM, more percussion). |
|  | P2 | Medium | Shop room music | Short, calm loop distinct from floor music. Plays when player enters shop room. |
|  | P2 | Low | Death screen music | Somber short piece (not a loop). 8–16 bars. |
|  | P2 | Low | Victory/floor-clear jingle | Short fanfare (3–5 seconds) when boss dies and portal appears. |

### Sound Effects
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | High | Melee swing SFX set | 3–4 variants per weapon type (light blade, heavy blade, blunt). Swoosh + impact layers. |
|  | P1 | High | Ranged fire SFX set | Bow twang, gun blast, magic cast, projectile whoosh. Per weapon archetype. |
|  | P1 | High | Enemy hit/death SFX | Distinct hit sounds per material (flesh, bone, metal, ice). Death sounds per enemy type. |
|  | P1 | Medium | UI SFX set | Button hover, click, panel open/close, card flip, purchase complete, purchase fail, modifier slot. |
|  | P2 | Medium | Material interaction SFX | Fire crackle (loop), water splash, ice crack, gas hiss, lava bubble, oil ignite, explosion boom. |
|  | P2 | Medium | Pickup SFX | Weapon pickup, modifier pickup, gold collect, chest open. |
|  | P2 | Medium | Player SFX | Footsteps (per terrain), hurt grunts, death. |
|  | P2 | Low | Environment ambience | Per-biome ambient loops: cave drips, magma rumble, frozen wind, mine echoes, vault hum. |

---

## Phase 5: Art & Visuals

### Player Character
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | Medium | Player sprite — idle | 4-directional sprite (or single sprite + rotation). Dark fantasy adventurer look. ~16×16 or ~32×32 native px. |
|  | P1 | Medium | Player sprite — attack | Per-weapon-type swing frames (1–3 frames). Blade arc vfx overlay during swing. |
|  | P1 | Medium | Player sprite — hurt | Damage flash (exists: white modulate). Add: stagger pose frame, directional knockback lean. |
|  | P2 | Low | Player sprite — walk | 2–4 frame walk cycle per direction. |
|  | P2 | Low | Player sprite customization | Future hook: weapon visible on player, modifier vfx trails (lava drip, ice mist, etc.). |

### Enemy Art (expansion of Phase 2 content)
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | High | Melee enemy sprite sheets | 3–5 melee types × walk/attack/hurt/death frames × biome variation. |
|  | P1 | High | Ranged enemy sprite sheets | 3 ranged types × walk/attack/hurt/death frames × biome variation. |
|  | P2 | Medium | Boss sprite sheets | 5 bosses × unique frames for each phase transition + attack patterns. |
|  | P2 | Medium | Elite visual overlays | Glow outline shader, larger scale, distinct color tint per elite ability. |

### Weapon & Item Icons
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | Medium | Weapon icon set (51 weapons) | Currently reused DawnLike/Kyrise icons. Create custom 16×16 or 32×32 icons for all 51 weapons. Distinct silhouette per weapon. |
|  | P1 | Medium | Modifier icon set (80 modifiers) | Per-modifier icon: element symbols, status icons, stat icons. Currently missing for most modifiers. |
|  | P2 | Low | Item pickup sprites | Visible world-space sprites for weapon drops and modifier drops on the ground. Distinct shape per rarity. |

### Biome & Environment Art
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | Medium | Biome wall textures | Caves: rough stone. Mines: brick/timber. Magma: obsidian/cracked lava. Frozen: ice/snow. Vault: metal/tile. Already partial via `background_material`. |
|  | P2 | Medium | Biome floor textures | Distinct floor tile per biome. Subtle enough to not distract from gameplay readability. |
|  | P2 | Medium | Decor sprites — per biome | Caves: glowing flora (exists). Magma: ember vents, charred stumps. Frozen: ice crystals, frozen grass. Mines: support beams, crates. Vault: gold inlays, ornate pillars. |
|  | P2 | Medium | Prop sprites | Explosive barrel, oil barrel, gas vent, wooden pillar, chest (open/closed), portal. |
|  | P3 | Low | Biome ambient particles | Floating embers (magma), snow flurry (frozen), dust motes (caves/mines), gold sparkle (vault). |

### Visual Feedback & Juice
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | Medium | Wall-break dust polish | Existing `MAT_DUST` system. Tune: burst density, spread, color match to source wall, settle speed. Visual check each wall type. |
|  | P1 | Medium | Hit blood polish | Existing `MAT_BLOOD` system. Tune: splatter radius, burst speed, density decay. Directional splatter based on hit angle. |
|  | P2 | Medium | Combat VFX — fire/ice/lightning | Per-element impact vfx: fire bloom, ice shatter particles, lightning arc sprite, poison cloud puff, steam burst. |
|  | P2 | Medium | Status effect overlays on enemies | On-fire: flame sprite overlay. Frozen: ice shell overlay. Poisoned: green tint. Wet: water drip particles. Oiled: dark sheen. |
|  | P2 | Low | Screen shake tuning | Calibrate shake intensity per event: light hit (0.5), heavy hit (1.5), explosion (3.0), boss death (5.0). |
|  | P2 | Low | Hit-stop tuning | Very brief freeze-frame (0.02–0.05s) on kills, elite first hits and boss phase transitions. |
|  | P3 | Low | Kill feedback style | Replaces floating damage numbers. Tune kill flash, elite first-hit marker, and kill-streak readability. |

---

## Phase 6: UI Polish

### UI System Foundation
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | Medium | UI layout system | Implement `UILayout` tokens (spacing S/M/L/XL, modal widths SM/MD/LG, panel padding, HUD gutter, button sizes). Single source of truth for all layout constants. See `2026-05-25-ui-layout-system-design.md`. |
|  | P1 | Medium | `ModalPanel` reusable scene | One modal base: title bar + body + footer + backdrop. Used by all 8+ modal scenes. Consistent open/close animation via `JuicyPanel`. |
|  | P1 | Low | 9-slice textured panels | Replace `StyleBoxFlat` with `StyleBoxTexture` sourced from `GUI0.png`. Biome-accent overlay via `AccentOverlay.modulate`. |
|  | P2 | Medium | Per-scene modal migration | Migrate: pause_menu, settings, death_screen, weapon_popup, chest_ui, shop, main_menu. Each installs a `ModalPanel` with scene-specific content in Body/Footer. |
|  | P2 | Low | HUD consolidation | Fold `HealthUI` + `WeaponButton` into single `HUD.tscn`. Top-left: hearts + shields + gold. Top-right: weapon icon + tooltip. Both in matching 9-slice frames. |

### Card UI
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | Medium | `Card` reusable scene | SubViewport + fake_3D shader for Balatro-style perspective tilt. Elastic hover scale, shadow offset. Shared by weapon/modifier cards. See `2026-05-06-balatro-card-ui-design.md`. |
|  | P2 | Low | Card integration | Replace inline `_create_card()` in weapon_popup, chest_ui, shop with `Card` instantiation. |
|  | P3 | Low | Card select/deselect animations | Golden border + subtle pulse on selected. Fade to grey on unselected. |

### CRT & Post-Processing
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P2 | Low | CRT post-process shader | Barrel distortion + scanlines + vignette. CanvasLayer 128. Settings toggle. See `2026-05-23-ui-consistency-and-crt-design.md`. |
|  | P3 | Low | Per-biome CRT tint | Subtle color cast per biome (caves: warm, frozen: cool blue, etc.) as CRT shader uniform. |

### Shop Room Polish
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | Low | Shop room template tuning | Verify 256×256 room with 6px wood walls. Non-rotatable, high weight in all biomes. Multiple shops/floor possible. |
|  | P2 | Low | Shop item spacing | 5 modifiers grid (50px spacing), 3 weapons row (70px spacing), removal service bottom-right. Verify pickups don't overlap interact radii. See `2026-06-14-shop-item-spacing-design.md`. |
|  | P2 | Low | Affordability feedback | Unaffordable items: jitter bounce + gold flash. Affordable items: normal pickup flow. |
|  | P2 | Low | Price label readability | World-space gold price labels clear at gameplay zoom. Color-coded (white=affordable, red=unaffordable). |

### UI Consistency & Theme
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P2 | Low | Font unification | Single pixel font `SDS_8x8.ttf` at 16px (body) and 32px (titles). Remove all remaining Godot default font references. See `2026-05-23-ui-consistency-and-crt-design.md`. |
|  | P2 | Low | Palette unification | Neutral base (dark brown panels, parchment text) + biome-reactive accents (border color, button hover, title). `UIPalette` autoload handles biome transitions. |
|  | P2 | Low | Juicy panel migration | All modals extend `JuicyPanel` for drop-in open / drop-out close animations. Content stagger fade-in. See `2026-05-11-juicy-ui-refactor-design.md`. |
|  | P3 | Low | UI pixel scale consistency | All UI at 2× source pixels. Integer multiples of 8px for all dimensions. No fractional scaling. |

---

## Phase 7: Biome & Arena Polish

### Arena Compositions
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | Medium | Boss arena compositions (20 total) | 4 variants × 5 biomes. Each: ~15–25 features (pillars, pools, barrels, vents, enemy packs, boss). Distinct variant identity (Pillar Hall, Pool Trap, Vent Maze, Open Field). See `2026-05-17-organic-set-piece-rooms-design.md`. |
|  | P1 | Medium | Elite arena compositions (15 total) | 3 variants × 5 biomes. Each: ~5–8 features (chest, 2–3 elite packs, 0–1 hazard). |
|  | P2 | Low | Arena feature placement tuning | Rejection-sampled positions (8 retries). Tune to hit ≥75% feature placement rate. Adjust region radii/spacing if features consistently fail to place. |
|  | P2 | Low | Arena rim blending | Organic carve soft band preserves cave noise → natural entrances emerge. Tune lobe amplitude so arenas feel connected, not isolated. |
|  | P3 | Low | Per-biome arena material flavor | Caves: stone pillars. Magma: obsidian + lava. Frozen: ice pillars + water pools. Mines: wood pillars + gas vents. Vault: metal pillars, no pools. |

### Biome Distinctiveness
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | Medium | Biome lighting profiles | Caves: dim + glowing flora. Magma: warm/orange ambient + lava glow. Frozen: cool/blue ambient + ice shimmer. Mines: neutral + lantern-lit. Vault: bright + gold reflections. |
|  | P2 | Medium | Biome hazard identity | Each biome has a dominant hazard: caves=gas, magma=lava, frozen=ice powder, mines=oil+explosive barrels, vault=traps (future). |
|  | P2 | Medium | Biome enemy + boss identity | Each biome's roster feels unified. Frozen: chill/freeze mechanics. Magma: burn/ignite mechanics. Mines: stun/knockback. Vault: high gold, elite-heavy. |
|  | P2 | Low | Biome color grading | Post-process tint per biome: caves=warm amber, magma=red-orange, frozen=blue-cyan, mines=desaturated, vault=golden. |

### Environmental Props
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P2 | Medium | Prop placement per biome | Lava pools (magma), oil pools (mines), water ponds (caves), gas vents (mines/caves), ice powder (frozen). See `2026-05-14-props-and-boundary-design.md`. |
|  | P2 | Medium | Entity prop scenes | Explosive barrel, oil barrel, gas vent, wooden pillar. Proper destruction behavior, colliders, sprites. |
|  | P3 | Low | Prop → modifier interaction | Barrels ignite from fire swings, gas vents feed fire, oil pools amplify burn. Verify these chain reactions work and look good. |

### World Boundary
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P2 | Medium | Wardstone warning ring | Glowing biome-tinted ring at sector-distance ~10.5. Indestructible. Reads as "this floor's ward." |
|  | P2 | Medium | Void-stone outer wall | Solid black wall at sector-distance ≥11. Indestructible. No outer void to wander into. |
|  | P2 | Low | Boundary generation | `stage_world_boundary` runs first in gen pipeline. Void chunks early-out. Wardstone protected from cave overwrite. |

---

## Phase 8: Playtest Plans

### Playtest Preparation
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | Medium | Build checklist | One-command build for testers. Platform: Windows (primary), Linux (secondary). Include FMOD banks in build. |
|  | P1 | Medium | Playtest build stability | Ensure no crash-on-launch, no missing dependencies, graceful error handling. Run through all 5 biomes at least once. |
|  | P1 | Low | Cheat/console commands for testers | Testers can: `spawn_weapon <id>`, `spawn_modifier <id>`, `give_gold <n>`, `set_floor <n>`, `god`, `kill_all`. |
|  | P2 | Low | Feedback form | Simple Google Form: what felt good/bad, what was confusing, balance notes, bugs encountered, 1–10 fun rating. |
|  | P2 | Low | Playtest guide | 1-page doc: controls, game concept, what to try, what feedback you want. |

### Internal Playtest (Self)
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P0 | High | Full run playtest x50 | Play through floor 1→boss→portal→floor N 50+ times. Document: every death cause, every confusing moment, every "this feels bad" moment. |
|  | P0 | Medium | Weapon-by-weapon playtest | Equip each of 51 weapons for at least one floor. Note: weapons that feel bad, weapons that trivialize content, weapons with buggy behavior. |
|  | P0 | Medium | Modifier-by-modifier playtest | Equip each of 80 modifiers. Note: broken interactions, useless modifiers, OP combos, modifiers that don't work as described. |
|  | P1 | Medium | Biome-specific playtest | 5 runs per biome. Note: biome identity feel, hazard fairness, enemy variety within biome, arena quality. |
|  | P1 | Medium | Edge case stress test | Mob cap 25 + heavy VFX + all modifiers active. Profile FPS. Test with worst-case weapon combos. |

### Friend Playtest (Round 1)
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | Medium | Recruit 3–5 testers | Friends who play action games / roguelikes. Mix of skill levels. |
|  | P1 | Medium | Observe (don't explain) | Watch them play without guidance. Note: where they get stuck, what they don't understand, what excites them. |
|  | P1 | Medium | Post-session interview | 15 min talk: what was fun, what was frustrating, would you play again, what one thing would you change. |
|  | P2 | Low | Collect & triage feedback | Categorize feedback: bug, balance, UX, content request, nice-to-have. Prioritize for next iteration. |

### Iteration Cycles
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | Medium | Playtest → fix → playtest loop | 2-week cycles: playtest, triage top 5 issues, fix, playtest again. Target 3 cycles before round 2. |
|  | P2 | Medium | Friend playtest (Round 2) | After fixes from Round 1. New build. Same testers or 2–3 fresh testers. Compare feedback delta. |
|  | P2 | Low | Balance spreadsheet | Maintain spreadsheet: weapon axis ratings (Coverage / Tempo / Utility), enemy behavior curves, boss hit pools, gold economy per floor, modifier magnitudes and chances. Update each cycle. |
|  | P3 | Low | Playtest video recording | Record playtest sessions (with permission). Review later for subtle issues (UI confusion, pathing problems, animation readability). |

---

## Difficulty Legend

- **Low**: Straightforward implementation, well-documented patterns
- **Medium**: Requires design decisions, some complexity
- **High**: Complex systems, significant engineering effort

## Priority Legend

- **P0**: Must have for vertical slice / core gameplay feel
- **P1**: Essential for complete experience
- **P2**: Important for polish
- **P3**: Nice-to-have / can ship without
