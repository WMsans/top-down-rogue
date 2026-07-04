# Implementation Todo List — Content Expansion & Polish

Based on gameplay.md design document. Companion to implementation_todo1.md (core systems).

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
| x | P0 | High | Full weapon stat audit (52 weapons) | Verify every weapon's cooldown/damage/reach/arc against its rarity and archetype. Identify over/underperformers. See `weapons.csv`. |
| x | P0 | Medium | Rarity-to-power curve | Standardize damage-per-second ranges: Common 5–8 DPS, Uncommon 7–11 DPS, Rare 9–14 DPS (adjusted for utility/status weapons). |
| x | P1 | Medium | Melee vs. ranged balance | Ranged safety premium: ranged base DPS should trail melee by ~15–20% at same rarity. Tune projectile lifetimes. |
| x | P1 | Medium | Archetype power budget | Each weapon archetype gets a power budget: stats, native traits, crit profile. Verify no archetype dominates its tier. |
| x | P1 | Medium | Pre-attached modifier valuation | Weapons with pre-slotted modifiers pay a stat penalty. Audit that penalty is consistent (e.g., ~1 dmg or +0.05s cd per pre-attached Uncommon+ mod). |
| x | P2 | Low | Charge weapon balance | Charge weapons trade tap DPS for burst. Ensure charge-time-to-damage ratio is ~1.8–2.5× a tap swing at same rarity. |

### Modifier Balance
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P0 | High | Full modifier stat audit (57 modifiers) | Verify every modifier's magnitude/magnitude2 against rarity. See `modifiers.csv`. Identify degenerate combos. |
| x | P0 | High | Stacking sanity check | Audit additive vs. multiplicative stacking. `stat_add` sums first, `stat_mult` applies after. Cap cooldown floor at ~0.1s. Cap crit_chance at 1.0. |
| x | P1 | Medium | Conditional trigger payoff | Conditional modifiers (frostbreaker, pyroclast, coup_de_grace, glass_cannon) must reward their condition with ≥1.5× damage. Verify magnitudes. |
| x | P1 | Medium | Emitter blob sizing | Oil/water/gas/ice/blood/coal/dust blob radii: verify they create meaningful area effects without griefing player pathing or tanking FPS. |
| x | P1 | Medium | Status stack thresholds | Verify stain thresholds in `status_registry.gd`: on_fire=1.0, wet=1.0, oiled=1.0, chilly=1.0, frozen=3.0, poisoned=0.3, bloody=1.0. Tune magnitudes so ~1–3 hits trigger. |
| x | P2 | Low | Anti-synergy costs | Document and verify anti-synergies: wet douses fire, oiled amplifies fire. Players running conflicting modifiers should feel the cost. |
| x | P2 | Low | Rarity distribution in shops | 5 modifier cards per shop: tune rarity weights so shops feel varied (target ~60% Common, ~30% Uncommon, ~10% Rare). |

### Enemy Balance
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P0 | High | Enemy HP/DMG per floor | Standardize enemy stat curve: floor 1 baseline, +20-25% HP/dmg per floor. Bosses scale at +15%. |
|  | P0 | Medium | Enemy tier stat ratios | EASY: 1.0×, NORMAL: 1.5× HP / 1.2× dmg, HARD: 2.5× HP / 1.5× dmg. Verify against weapon DPS so TTK feels right (~3–8 swings per enemy). |
|  | P1 | Medium | Elite stat multipliers | Elite base: 3.0× HP, 1.5× dmg, 1.3× speed. Elite abilities stack further. Verify elite fights feel like minibosses, not bullet sponges. |
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
|  | P3 | Low | Enemy hurt reactions | Enemies stagger/knockback on hit (exists). Add: directional knockback based on hit angle, elite stagger resistance. |

### Enemy Content Expansion
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | High | 5+ melee enemy variants | Author stats + behaviors for grunt (balanced), brute (slow/heavy), skirmisher (fast/weak), armored (tanky/anti-knockback), cultist (poison-on-hit). |
|  | P1 | High | 3+ ranged enemy variants | Author stats + behaviors for archer (straight projectile), mage (slow homing orb), lobber (arcing AoE shot). |
|  | P2 | Medium | Per-biome enemy roster | Each biome gets 2–4 unique enemy types. Caves: bats + crawlers. Magma: fire imps + lava slugs. Frozen: ice wraiths + frost giants. Mines: constructs + miners. Vault: guardians + sentinels. |
|  | P2 | Medium | Elite ability variants | Author + balance the 5 elite abilities (FAST, TANK, TELEPORT, ENRAGE). Add 2 more: SUMMONER (spawns minions on hit), SHIELD (periodic invuln bubble). |
|  | P3 | Low | Rare spawn enemies | 1–2 special enemies per biome with unique drops (e.g., Golden Slime drops extra gold, Crystal Golem drops guaranteed modifier). |

---

## Phase 3: Boss Design

### Boss Mechanics & Phases
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | High | 3-phase boss system polish | Verify phase transition chaining (no skipped phases on burst damage). Ensure each phase escalates visually and mechanically. |
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
|  | P1 | Medium | Boss name + health bar HUD | Large boss health bar at top of screen with boss name. Phase indicators. Health-gate markers visible on bar. |
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
|  | P1 | Medium | Weapon icon set (52 weapons) | Currently reused DawnLike/Kyrise icons. Create custom 16×16 or 32×32 icons for all 52 weapons. Distinct silhouette per weapon. |
|  | P1 | Medium | Modifier icon set (57 modifiers) | Per-modifier icon: element symbols, status icons, stat icons. Currently missing for all 46 new modifiers. |
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
|  | P2 | Low | Hit-stop tuning | Very brief freeze-frame (0.02–0.05s) on heavy hits / crits / boss phase transitions. |
|  | P3 | Low | Damage number style | Floating damage numbers (exists). Tune: font, color per damage type, crit color (yellow), size scaling with damage amount. |

---

## Phase 6: UI Polish

### UI System Foundation
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | Medium | UI layout system | Implement `UILayout` tokens (spacing S/M/L/XL, modal widths SM/MD/LG, panel padding, HUD gutter, button sizes). Single source of truth for all layout constants. See `2026-05-25-ui-layout-system-design.md`. |
|  | P1 | Medium | `ModalPanel` reusable scene | One modal base: title bar + body + footer + backdrop. Used by all 8+ modal scenes. Consistent open/close animation via `JuicyPanel`. |
|  | P1 | Low | 9-slice textured panels | Replace `StyleBoxFlat` with `StyleBoxTexture` sourced from `GUI0.png`. Biome-accent overlay via `AccentOverlay.modulate`. |
|  | P2 | Medium | Per-scene modal migration | Migrate: pause_menu, settings, death_screen, weapon_popup, chest_ui, shop, main_menu. Each installs a `ModalPanel` with scene-specific content in Body/Footer. |
|  | P2 | Low | HUD consolidation | Fold `HealthUI` + `WeaponButton` into single `HUD.tscn`. Top-left: health bar + gold. Top-right: weapon icon + tooltip. Both in matching 9-slice frames. |

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
|  | P0 | Medium | Weapon-by-weapon playtest | Equip each of 52 weapons for at least one floor. Note: weapons that feel bad, weapons that trivialize content, weapons with buggy behavior. |
|  | P0 | Medium | Modifier-by-modifier playtest | Equip each of 57 modifiers. Note: broken interactions, useless modifiers, OP combos, modifiers that don't work as described. |
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
|  | P2 | Low | Balance spreadsheet | Maintain spreadsheet: weapon DPS tiers, enemy HP curves, gold economy per floor, modifier magnitudes. Update each cycle. |
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
