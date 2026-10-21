# Gameplay Mechanics

## 1. Core Vision & Pacing

The game is a top-down, real-time action roguelike that heavily prioritizes **tactical build-crafting** and **environmental manipulation** over twitch reflexes.

The primary referencing game is **Noita**, especially the feel of chaos.

**Decisive Combat:** Offense plays like **Katana ZERO** — every hit is decisive. Normal enemies die in one hit, elites in two. There are no damage numbers to grind down; a fight is won by positioning, reading telegraphs and landing the hit.

**Fragile Player:** Defense plays like **Soul Knight** — the player has a tiny pool of **3 HP and 3 armor**. Armor absorbs hits and regenerates; HP does not. Every hit taken matters.

**Build-Driven Chaos:** As the player progresses and their build evolves, the pacing can shift dramatically to resemble the systemic, screen-filling chaos of Noita. The player effectively controls the tempo of the game; a player can choose a build that requires careful, methodical wall-carving, or one that unleashes cascading elemental chain reactions.

---

## 2. Combat Rules

### Player: Armor & Health

- The player has **3 HP** and **3 armor**.
- Every **hit** from an enemy costs **1 point**: armor first, then HP once armor is empty. Enemy attacks have no damage values — a hit is a hit.
- After a hit the player is invulnerable for **1.0s**.
- **Damage-over-time** (fire, poison, steam, …) also costs 1 point per tick, armor first. Ticks ignore invulnerability frames. Tick rates: fire 1 / 1s, poison 1 / 1.5s, steam 1 / 1s. Status durations are short — a typical burn costs ~2 points, not the whole pool.
- **Lava contact** counts as a hit (respects invulnerability frames): ~1 point per second of standing in it.
- **Armor regeneration:** after **3s** without taking any hit or tick, armor regenerates **+1 per 1s** until full.
- **HP never regenerates.** It is restored only by specific sources: killing a boss (+1 HP and full armor), the shop's **Mend** service (1 HP, cost rises with each use), and specific weapons/modifiers.
- Max armor can be changed by items/modifiers; max HP increases are very rare.
- The player dies at 0 HP.

### Enemies: Hit Counts

- **Every hit counts as exactly 1**, whatever its source: swing, projectile, explosion, lava, or a status tick. There is no damage and no critical hit.
- **Normal enemies** die to their first hit. A single burn tick kills them.
- **Elites** take **2 hits** (TANK elites take 3). They flash and stagger on the first hit.
- **Bosses** have a hit pool split across phases (baseline **3 phases × 10 hits**, tuned per boss). A phase transition cleanses the boss's statuses.
- Elites and bosses share the same **0.3s post-hit invulnerability**, so multi-projectile fans and multi-strike weapons can't delete them in one action.
- Charging an attack changes its **shape** (arc, reach, pierce, shockwave, pull), never the number of hits it deals.
- **Difficulty and floor scaling come from behavior**, not stats: more enemies, shorter telegraphs, faster attack cadence, more projectiles, and elite abilities. Enemy tiers (EASY / NORMAL / HARD) are behavior profiles.

### Statuses Under One-Hit Kills

- An on-hit status rarely matters on a normal enemy — it is already dead. Statuses matter against **elites and bosses** (one burning hit plus one burn tick kills an elite) and for **spreading**: fire, gas and oil that reach a crowd kill it.
- **On-kill** effects are the main way builds clear crowds: kills that chain lightning, burst into flame, fire shards, refund cooldown, and so on.

---

## 3. Combat & Environmental Interaction

Combat is intrinsically tied to the game's fully simulated, pixel-physics environment. The player's primary method of interaction is through **melee swings**, which do far more than simply kill.

- **Material Generation:** Weapon swings can emit physical substances into the world. For example, a weapon equipped with specific modifiers might leave a trail of burning oil on the floor, creating a persistent environmental hazard for enemies.

- **Terrain Modification:** The environment is fully destructible and moldable. Each weapon has a **dig power** stat (the old "damage" stat) that controls how much terrain a swing carves — it has no effect on enemies. Players can use their swings to literally carve through the map. This can be used defensively (digging a trench to catch and funnel incoming lava) or offensively (cutting through a wall to create a tactical flanking route against an entrenched enemy).

- **Fluid & Gas Dynamics:** Weapon swings physically interact with the air and fluids around them. A well-timed swing will part or completely remove toxic gas from the arc of the swing.

- **Elemental Chain Reactions:** Elements interact logically. The fire released from a "Flaming Sword" burns enemies, ignites flammable gases, and melts or modifies certain terrain types, turning the battlefield into a dynamic puzzle.

---

## 4. The Build System

The core hook of the game lies in the **build system**, which shifts the focus away from finding the perfect weapon and toward **crafting the perfect synergy**.

Each weapon has **3 slots**, and each slot can fill in a **modifier** (the building element). The modifiers serve as the building blocks. These are powerful modifiers that dictate what the weapon does. They include effects like spawning fire, generating gas, drastically altering cooldowns, or increasing terrain-carving depth. **Modifiers** are primarily purchased from Shops. The modifier can be acquired primarily from the shops (frequently spawned), and weapons can be acquired directly from enemy drops or chests.

When picking up a new weapon, the player can choose **one of the modifiers** in the slots of the current weapon to replace to bring to the new one.

**Once a modifier is filled into a weapon, it cannot be taken out.** As a result, players must weigh the benefits of a new weapon's base stats against the loss of two of their synergistic modifers, forcing them to rebuild and improvise their tactics run-after-run.

### Weapon Power Axes

Since every hit kills, weapons are not balanced on damage. Each weapon is judged on three axes:

1. **Coverage** — how much space an attack controls: reach × arc, pierce, projectile count, area.
2. **Tempo** — cooldown, and whether attacking slows or roots the player.
3. **Utility** — status application, dig power, crowd control (knockback, pull, stun), deflection, mobility.

**Rarity buys behavior, not bigger numbers:**

- **Common** — a plain swing/shot shape, strong on one axis.
- **Uncommon** — a plain shape plus one trait (status on hit, deflect, pierce, charge variant).
- **Rare** — a signature mechanic (combo chain, kill trigger, multi-part attack), solid on two axes.

**Ranged vs. melee:** ranged weapons pay for their range with tempo (longer cooldowns), and their projectiles stop at the first enemy unless the weapon pierces. A melee arc hits everything inside it.

### Modifier Design

Modifiers never add damage or critical chance. They change **what an attack does**: emit materials, apply or consume statuses, spawn projectiles, trigger on kill, or buff reach, swing speed, move speed, dig power and armor. Chance-based effects state their odds explicitly (e.g. 1/4), and Executioner's Mark raises every chance on its weapon by +1/4.

Weapon and modifier descriptions are maintained in `weapons.csv` and `modifiers.csv`.

---

## 5. The Core Gameplay Loop

1. **Explore & Shape:** Navigate procedurally generated levels. Carve through walls to find secrets or avoid dangerous chokepoints.

2. **Tactical Combat:** Read enemy telegraphs and land decisive hits — normal enemies drop in one, elites in two. Use swings to disperse hazardous gases or trap whole groups in elemental reactions (fire, oil, water). Every hit taken eats into 3 armor and 3 HP, so positioning matters more than trading blows.

3. **Loot & Decide:** Defeat enemies or find chests to discover new base Weapons. Decide whether the new weapon's base stats are worth sacrificing your current modifier setup, choosing the single best modifer to carry forward.

4. **Shop & Synthesize:** Spend gathered currency at shops to buy new modifer to fill out your 3 slots in each weapon, constantly redefining playstyle and pushing the game's physics engine to its limits. Shops also offer **Mend** (restore 1 HP) at a cost that rises with each use.

5. **Levels:** Each level is procedually generated caves. Enemies, shopes, structures, and elites spawns in the caves. There would also generate bosses. After defeating bosses, the player can enter the next level through a portal generated.
