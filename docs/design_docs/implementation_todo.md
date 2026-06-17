# Implementation Todo List

Based on gameplay.md design document.

---

## Phase 1: Core Infrastructure

### Terrain & Physics System
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P0 | High | Pixel-based terrain rendering | Implement destructible pixel-terrain similar to Noita |
| x | P0 | High | Terrain carving system | Allow melee swings to modify/cut through terrain |
| x | P0 | High | Material system foundation | Create base material types (solid, liquid, gas) |
| x | P1 | Medium | Terrain generation (caves) | Procedural cave generation for levels |
| x | P1 | High | Fluid simulation | Water, lava, and other liquid dynamics |
| x | P1 | High | Gas simulation | Toxic gas and other atmospheric effects |
| x | P2 | High | Material interaction chains | Fire burns gas, lava melts terrain, etc. |

### Player Foundation
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P0 | Medium | Player movement | Top-down character controller |
| x | P0 | Medium | Melee swing mechanics | Basic attack with arc-based hitbox |
| x | P0 | Medium | Camera system | Follow player with appropriate zoom level |
| x | P1 | Low | Player health/hitbox | Damage receiving and death handling |
| x | P1 | Medium | Swing interaction with fluids | Swings can part/displace fluids and gases |

---

## Phase 2: Build System

### Weapon System
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P0 | Medium | Weapon base stats | Damage, swing speed, reach, base damage type |
| x | P0 | Medium | 3-slot modifier system | Weapon holds up to 3 modifier slots |
| x | P1 | Medium | Weapon pickup/drops | Enemies and chests drop weapons |
| x | P1 | High | Modifier transfer on pickup | Choose 1 modifier to carry to new weapon |
| x | P1 | Medium | Modifier permanence | Once slotted, cannot be removed |

### Modifiers
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P0 | Medium | Modifier framework | Base class and slot system for all modifiers |
| x | P1 | Medium | Material generation modifiers | Oil trail, fire trail, poison gas on swing |
| x | P1 | Medium | Elemental modifiers | Fire damage, ice slow, electric chain |
| x | P1 | Low | Stat modifiers | Damage increase, cooldown reduction, range |
| x | P2 | Medium | Terrain modifiers | Deeper carving, wider swing arc |

---

## Phase 3: Economy & Progression

### Shops
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P1 | Medium | Shop UI | Buy/sell interface |
| x | P1 | Medium | Currency system | Gold/credits dropped by enemies |
| x | P1 | Medium | Shop spawning | Generate shops in levels |
| x | P1 | Low | Modifier inventory | Track owned but unequipped modifiers |

### Loot
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P1 | Medium | Enemy drop tables | Define what enemies can drop |
| x | P1 | Medium | Chest system | Random weapon drops from chests |
| x | P1 | Low | Pickup interaction | Player collects dropped items |

---

## Phase 4: Enemies & Combat

### Enemy Foundation
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P1 | Medium | Enemy base class | Shared behavior for all enemies |
| x | P1 | Medium | Basic melee enemies | Simple AI for melee attackers |
| x | P1 | Medium | Enemy spawning | Place enemies in procedural levels |
| x | P2 | Medium | Ranged enemies | Projectile-based enemies |
| x | P2 | High | Elite enemies | Stronger variants with special abilities |

### Bosses
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P2 | High | Boss generation | Spawn boss in each level |
| x | P2 | High | Boss defeat logic | Trigger portal on boss death |
| x | P2 | Medium | Boss abilities | Unique attack patterns per boss type |

---

## Phase 5: Level System

### Procedural Generation
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P1 | High | Cave generation algorithm | Procedural cave layouts |
| x | P1 | Medium | Room placement | Shops, secrets, boss arenas |
| x | P1 | Medium | Enemy population | Distribute enemies appropriately |
| x | P2 | Medium | Secret areas | Hidden rooms requiring terrain carving |

### Progression
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P1 | Low | Portal system | Transition to next level after boss |
| x | P2 | Low | Level tracking | Current depth/floor counter |
| x | P2 | Medium | Difficulty scaling | Enemies scale with depth |

---

## Phase 6: Polish & Systems Integration

| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| | P2 | Medium | Visual feedback | Swing effects, material particles |
| | P2 | Medium | Sound design | Swing sounds, material interactions |
| x | P2 | Medium | UI/UX | HUD, inventory, modifier display |
| | P2 | Low | Save/Run persistence | Track run state for meta-progression |
| | P3 | Medium | Meta-progression | Persistent unlocks (if applicable) |

---

## Phase 7: Weapon & Modifier Content Expansion

Implementing all weapons in `weapons.csv` and modifiers in `modifiers.csv`. CSV data and
`.tres` files already exist; this phase builds the *behavior* the descriptions promise.
Approach: **foundations first** — build each shared combat system, folding in the
stat-dependent weapons so every cycle is independently playable. Each sub-project gets its
own design → plan → build cycle.

Already functional (pure stat variants, no new code): rusty_sword, bone_dagger, broad_axe,
tao_sword, broadsword, throwing_knife, fire_orb, spread_shot, boss_staff, lava_emitter.

### Sub-project 1: Crit + Status Effects
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P1 | Medium | Crit system | Per-weapon crit chance/damage + on-crit hook |
| x | P1 | High | Status effects: burn & freeze | Burn DoT and freeze/immobilize on enemies |
| x | P1 | Medium | Wire crit weapons | caliburn, flame_sword, frost_sword, heavenly_sword |

### Sub-project 2: Charge + Combos
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P1 | High | Charge input | Hold-to-charge attack input + Weapon charge API |
| x | P1 | High | Combo sequencing | Sequential multi-step attacks (slashes/thrusts/spins) |
| x | P1 | High | Wire charge/combo weapons | willowblade, blood_blade, executioner, void_sword, dragon_fang, grand_knight, deep_dark, phantom_blade, qinggang |

### Sub-project 3: Projectile Behaviors
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P2 | Medium | Bouncing projectiles | Projectiles that ricochet off terrain |
| x | P2 | Medium | Splitting projectiles | Projectiles that split into shards on impact |
| x | P2 | Medium | Penetrating projectiles | Pass-through shockwaves that delete enemy bullets |
| x | P2 | Medium | Bullet-clearing projectiles | Shatter incoming enemy projectiles |

### Sub-project 4: Modifiers
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P2 | Medium | Swing-triggered projectile modifiers | fireball_fan, icicle_volley, gleaming_projectile, green_crescent |
| x | P2 | Medium | Combo-step modifiers | arc_volley, triangular_volley, splitting_rounds, bouncing_bullets |
| x | P2 | Medium | Charge & chance modifiers | penetrating_shockwave, lightning_bolt |

---

The 46 new modifiers (`modifiers.csv`) and 28 new weapons (`weapons.csv`, redesigned per
`2026-06-15-weapon-modifier-separation-design.md`) remain unbuilt. They ride on ~5 new
subsystems, split into the sub-projects below. Foundations-first ordering: each cycle ships
playable content. SP-A is the keystone (a data-driven modifier runtime) and is built first.

### Sub-project A (5): Data-driven runtime (weapons + modifiers)
See `docs/superpowers/specs/2026-06-15-sp-a-data-driven-runtime-design.md`.
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
|  | P1 | High | Fully data-driven weapon factory | Build every weapon from its CSV row alone; delete all 23 `.tres`; `archetype` column selects script; new `reach/arc/projectile_*` columns; `.tres`-free |
|  | P1 | High | `DataModifier` dispatch class | One Modifier subclass that reads `category/trigger/condition/effect/element/magnitude` from the CSV row and dispatches behavior; 11 bespoke modifier scripts kept |
|  | P1 | Medium | Effective-stats pipeline | `Weapon.get_effective_stats()` folds passive `stat_add`/`stat_mult`; melee/ranged read effective values |
|  | P1 | High | Hit-resolution chokepoint | `Weapon.resolve_hit()` applies conditional multipliers, status-edges, on-kill; melee + projectile (`source_weapon` ref) both route through it |
|  | P1 | Medium | CSV → registry | Build weapons + all 57 modifiers from CSV; register every entry in tiered drop tables |
|  | P1 | Medium | Emitters (7) | oil/water/gas/frost/blood/coal/dust `spawn_material` on swing |
|  | P1 | Medium | Status edges (6) | venom/soaking/greased/frostbite/ember/rending `apply_status` on hit |
|  | P1 | Medium | Stat affixes (9) | sharpened, heavy_head, honed_point, executioners_mark, quickdraw, long_reach, wide_arc, deep_cut, fleetfoot |
|  | P1 | Medium | Conditional triggers (10) | frostbreaker, pyroclast, coup_de_grace, bloodlust, rampage, glass_cannon, vampiric, momentum, adrenaline, combo_keeper (reuse existing hooks only) |
|  | P1 | Low | Data-only new weapons | rapier, iron_mace, bone_cleaver, venom_fang_blade, tide_caller, cinder_brand, glacier_edge, thunder_katana, scatter_blunderbuss, frost_repeater (obsidian/gravedigger playable sans native carve) |

### Sub-project B (6): New statuses & combat hooks
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P2 | High | `lightning`/`steam`/`stun` statuses | StatusDefs + reaction rules (wet→steam, neutral stun) |
| x | P2 | Medium | Enemy stun + knockback hooks | Immobilize + radial impulse verbs |
| x | P2 | Medium | Player heal + economy bounty hooks | `heal` verb; `bounty` extra-gold on kill |
| x | P2 | Medium | Modifiers using new hooks | chain_spark, steam_burst, concussive_edge, repulsor_nova, shockwave_stomp, magnet_field, midas_touch |

### Sub-project B.1 (6.5): SP-B modifier scripts
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P2 | Medium | chain_spark, steam_burst, concussive_edge | New on_hit/on_crit modifiers |
| x | P2 | Medium | repulsor_nova, shockwave_stomp | Knockback/area modifiers |
| x | P2 | Medium | magnet_field, midas_touch | Pull/bounty utility modifiers |

### Sub-project C (7): New projectile behaviors + projectile modifiers
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P2 | Medium | `homing` steering | Curve toward nearest enemy with capped turn rate |
| x | P2 | Medium | `return` steering | Travel out then reverse to player, hitting both legs |
| x | P2 | Medium | Projectile modifiers | homing_hex, boomerang_arc, ricochet_shard, piercing_lance, cluster_bomb, spectral_echo |

### Sub-project D (8): Native melee mechanics + 18 melee weapons
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P2 | Medium | Native arc shapes | wide front arc (Bone Cleaver), surround/rear arc (War Scythe) |
| x | P2 | Medium | Double-hit + charged spin | twin_daggers double pass; whirlwind 360° charge |
| x | P2 | High | Native attrition/charge traits | free-carve, heal-on-kill, low-HP ramp, per-kill stacking, charged shockwave, melee deflect |
| x | P2 | Medium | Melee `.tres` + stat wiring | iron_mace, rapier, cleaver, war_scythe, twin_daggers, obsidian_greatsword, venom_fang_blade, tide_caller, cinder_brand, glacier_edge, thunder_katana, gravedigger_spade, reaper_glaive, berserker_axe, mirror_blade, whirlwind_blade, quake_hammer, soul_reaver |

### Sub-project E (9): Native ranged mechanics + 10 ranged weapons
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P2 | Medium | Line-pierce + charged rail | heavy_crossbow pierce; arc_railgun charge-to-fire rail |
| x | P2 | Medium | Lob-splat + chain/fork | flame_lobber/venom_spitter impact hazard; tesla_gun chaining |
| x | P2 | Medium | Area-volley + folded-native | hailstorm_bow volley; chakram return, seeker homing fold native |
| x | P2 | Medium | Ranged `.tres` + stat wiring | heavy_crossbow, scatter_blunderbuss, arc_railgun, flame_lobber, frost_repeater, venom_spitter, tesla_gun, chakram_launcher, seeker_launcher, hailstorm_bow |

---

## Phase 8: Steady-State Performance (Nav + Collision Readback)

After the enemy navigation system landed, frame time regressed to ~47–83 ms (12–21 fps).
Profiling shows the cost is **not** chunk-gen spikes but a steady-state floor: NavField
(~24 ms/frame) and TerrainCollisionHelper (~25 ms/frame) together consume the entire frame.

**Shared root cause:** `terrain_modifier` calls `mark_terrain_dirty` for terrain changes
that don't affect solidity (gas/lava/blood/fire placed into air). Both systems then rebuild
every frame. NavField additionally has no change-detection and does a full 262 KB GPU
texture readback + two 65 K-px GDScript loops per dirty chunk. Each sub-project gets its own
design → plan → build cycle; **measure after sub-project 1 before committing to 2 and 3.**

(Noted, deferred: `terrain_modifier` itself does a full `texture_get_data` readback per
placement — same anti-pattern, out of current scope.)

### Sub-project 1: Solid-aware dirtying + NavField change-detection
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P0 | Low | Solid-aware dirty filtering | Only dirty nav/collision when a change adds/removes a *solid* material |
| x | P0 | Low | NavField tile change-detection | Hash the downsampled tile; skip rebuild when solidity unchanged (mirrors collision helper) |
| x | P0 | Low | Measure & verify | Confirm steady-state NavField + collision drop to ~0 ms for non-solid effects |

### Sub-project 2: GPU passability buffer (NavField structural)
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P1 | High | GPU 32×32 solidity grid | Collider compute pass emits per-chunk passability grid; read back ~1 KB not 262 KB |
| x | P1 | Medium | NavField consumes GPU grid | Drop `read_region` + GDScript downsample from nav entirely |

### Sub-project 3: Collision-helper readback reduction
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| | P1 | High | GPU-side segment hash | Read back a small per-chunk hash first; only fetch full segments when changed |
| | P1 | Medium | Skip coalesced readback when idle | Avoid the ~10 ms `buffer_get_data` when no dispatched chunk changed |

---

## Difficulty Legend

- **Low**: Straightforward implementation, well-documented patterns
- **Medium**: Requires design decisions, some complexity
- **High**: Complex systems, significant engineering effort

## Priority Legend

- **P0**: Must have for vertical slice / core gameplay
- **P1**: Essential for full game loop
- **P2**: Important for complete experience
- **P3**: Polish / nice-to-have
