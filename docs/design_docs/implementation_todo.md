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
| | P1 | Medium | Basic melee enemies | Simple AI for melee attackers |
| | P1 | Medium | Enemy spawning | Place enemies in procedural levels |
| | P2 | Medium | Ranged enemies | Projectile-based enemies |
| | P2 | High | Elite enemies | Stronger variants with special abilities |

### Bosses
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| | P2 | High | Boss generation | Spawn boss in each level |
| | P2 | High | Boss defeat logic | Trigger portal on boss death |
| | P2 | Medium | Boss abilities | Unique attack patterns per boss type |

---

## Phase 5: Level System

### Procedural Generation
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| | P1 | High | Cave generation algorithm | Procedural cave layouts |
| | P1 | Medium | Room placement | Shops, secrets, boss arenas |
| | P1 | Medium | Enemy population | Distribute enemies appropriately |
| | P2 | Medium | Secret areas | Hidden rooms requiring terrain carving |

### Progression
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| | P1 | Low | Portal system | Transition to next level after boss |
| | P2 | Low | Level tracking | Current depth/floor counter |
| | P2 | Medium | Difficulty scaling | Enemies scale with depth |

---

## Phase 6: Polish & Systems Integration

| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| | P2 | Medium | Visual feedback | Swing effects, material particles |
| | P2 | Medium | Sound design | Swing sounds, material interactions |
| | P2 | Medium | UI/UX | HUD, inventory, modifier display |
| | P2 | Low | Save/Run persistence | Track run state for meta-progression |
| | P3 | Medium | Meta-progression | Persistent unlocks (if applicable) |

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
