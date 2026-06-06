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
| | P1 | Medium | Crit system | Per-weapon crit chance/damage + on-crit hook |
| | P1 | High | Status effects: burn & freeze | Burn DoT and freeze/immobilize on enemies |
| | P1 | Medium | Wire crit weapons | caliburn, flame_sword, frost_sword, heavenly_sword |

### Sub-project 2: Charge + Combos
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P1 | High | Charge input | Hold-to-charge attack input + Weapon charge API |
| x | P1 | High | Combo sequencing | Sequential multi-step attacks (slashes/thrusts/spins) |
| x | P1 | High | Wire charge/combo weapons | willowblade, blood_blade, executioner, void_sword, dragon_fang, grand_knight, deep_dark, phantom_blade, qinggang |

### Sub-project 3: Projectile Behaviors
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| | P2 | Medium | Bouncing projectiles | Projectiles that ricochet off terrain |
| | P2 | Medium | Splitting projectiles | Projectiles that split into shards on impact |
| | P2 | Medium | Penetrating projectiles | Pass-through shockwaves that delete enemy bullets |
| | P2 | Medium | Bullet-clearing projectiles | Shatter incoming enemy projectiles |

### Sub-project 4: Modifiers
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| | P2 | Medium | Swing-triggered projectile modifiers | fireball_fan, icicle_volley, gleaming_projectile, green_crescent |
| | P2 | Medium | Combo-step modifiers | arc_volley, triangular_volley, splitting_rounds, bouncing_bullets |
| | P2 | Medium | Charge & chance modifiers | penetrating_shockwave, lightning_bolt |

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
| | P0 | Low | Solid-aware dirty filtering | Only dirty nav/collision when a change adds/removes a *solid* material |
| | P0 | Low | NavField tile change-detection | Hash the downsampled tile; skip rebuild when solidity unchanged (mirrors collision helper) |
| | P0 | Low | Measure & verify | Confirm steady-state NavField + collision drop to ~0 ms for non-solid effects |

### Sub-project 2: GPU passability buffer (NavField structural)
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| | P1 | High | GPU 32×32 solidity grid | Collider compute pass emits per-chunk passability grid; read back ~1 KB not 262 KB |
| | P1 | Medium | NavField consumes GPU grid | Drop `read_region` + GDScript downsample from nav entirely |

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
