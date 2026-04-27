# Enemy Drop Tables Design

## Overview

Define what enemies can drop using a tier-based pool system. Enemies are grouped by difficulty tier (EASY, NORMAL, HARD), and each tier determines the probability distribution across weapon/modifier rarity tiers (COMMON, UNCOMMON, RARE) as well as gold drop amounts.

## Enemy Tiers

```gdscript
enum EnemyTier { EASY, NORMAL, HARD }
```

Each enemy has an `enemy_tier` export that controls its drop behavior. Enemies in higher tiers have higher chances of dropping rarer weapons and modifiers, and drop more gold.

### Drop Tier Distributions

| Enemy Tier | COMMON wt | UNCOMMON wt | RARE wt | Gold min | Gold max | Gold per drop | Weapon drop chance | Modifier drop chance |
|------------|-----------|-------------|---------|----------|----------|---------------|--------------------|---------------------|
| EASY       | 0.70      | 0.25        | 0.05    | 2        | 5        | 5             | 0.30               | 0.10                |
| NORMAL     | 0.50      | 0.35        | 0.15    | 4        | 10       | 5             | 0.30               | 0.10                |
| HARD        | 0.30      | 0.40        | 0.30    | 8        | 20       | 5             | 0.30               | 0.10                |

The weapon/modifier drop chance is the probability that *at least one* weapon or modifier drops. Given a drop, the tier weights determine which rarity is selected.

## Item Tiers

```gdscript
enum ItemTier { COMMON, UNCOMMON, RARE }
```

Weapons and modifiers are organized into these tiers in the WeaponRegistry. Within each tier, items have a `drop_weight` for weighted random selection (default 1.0).

## DropEntry Kinds

The existing `DropEntry` is extended to support multiple drop kinds:

```gdscript
enum DropKind { GOLD, WEAPON_POOL, MODIFIER_POOL, SCENE }
```

| Kind | Fields | Behavior |
|------|--------|----------|
| GOLD | weight, min_count, max_count, gold_per_drop | Spawns gold drops with specified amount |
| WEAPON_POOL | weight, item_tier, min_count, max_count | Picks random weapon from tier pool, creates WeaponDrop |
| MODIFIER_POOL | weight, item_tier, min_count, max_count | Picks random modifier from tier pool, creates ModifierDrop |
| SCENE | weight, scene, min_count, max_count | Direct PackedScene instantiation (backward compat) |

## Weapon Registry Pool Access

`WeaponRegistry` gains tier-organized pools and weighted random selection:

- `weapon_tiers: Dictionary` — maps `ItemTier` to `Array[WeaponDropEntry]`
- `modifier_tiers: Dictionary` — maps `ItemTier` to `Array[ModifierDropEntry]`
- `get_random_weapon(tier: int) -> Weapon` — weighted random selection from tier pool, returns instantiated weapon
- `get_random_modifier(tier: int) -> Modifier` — weighted random selection from tier pool, returns instantiated modifier

`WeaponDropEntry` and `ModifierDropEntry` are lightweight structs holding a script reference and a drop weight for within-tier weighting.

## Drop Table Construction

### Manual (code-defined)

Enemy subclasses continue to build drop tables in `_setup_drop_table()`, now using the new DropEntry kinds:

```gdscript
func _setup_drop_table() -> void:
    drop_table = DropTable.new()
    drop_table.add_entry(DropTable.DropEntry.gold(1.0, 2, 5, 5))
    drop_table.add_entry(DropTable.DropEntry.weapon_pool(0.3, DropTable.ItemTier.COMMON))
    drop_table.add_entry(DropTable.DropEntry.modifier_pool(0.1, DropTable.ItemTier.COMMON))
```

### Auto-generated from enemy tier

A helper on DropTable generates entries from an enemy tier:

```gdscript
static func from_enemy_tier(
    tier: int,
    drops_gold: bool = true,
    drops_weapon: bool = true,
    drops_modifier: bool = true
) -> DropTable
```

This uses the tier distributions defined above to auto-populate gold, weapon, and modifier entries. Enemy subclasses can either use this helper or manually construct if they need custom behavior.

## Drop Resolution

`DropTable.resolve()` checks each entry's `kind`:

1. **GOLD**: Instantiate `GOLD_DROP_SCENE`, call `set_amount(gold_per_drop)`, spawn with offset
2. **WEAPON_POOL**: Call `WeaponRegistry.get_random_weapon(item_tier)`, instantiate `WEAPON_DROP_SCENE`, set `.weapon`, spawn with offset
3. **MODIFIER_POOL**: Call `WeaponRegistry.get_random_modifier(item_tier)`, instantiate `MODIFIER_DROP_SCENE`, set `.modifier`, spawn with offset
4. **SCENE**: Direct PackedScene instantiation (current behavior)

For WEAPON_POOL and MODIFIER_POOL with min_count > 1, each item in the count is independently drawn from the pool (can roll duplicates).

## Files to Change

| File | Change |
|------|--------|
| `src/enemies/drop_table.gd` | Refactor: add DropKind enum, ItemTier enum, EnemyTier enum, rework DropEntry with kind/item_tier fields, add static constructors (gold(), weapon_pool(), modifier_pool(), scene()), add `from_enemy_tier()` helper, update `resolve()` to handle all kinds |
| `src/autoload/weapon_registry.gd` | Add tier pools (weapon_tiers, modifier_tiers), add WeaponDropEntry/ModifierDropEntry inner classes, add get_random_weapon() and get_random_modifier() methods, populate pools in _ready() |
| `src/enemies/enemy.gd` | Add `@export var enemy_tier: int = EnemyTier.NORMAL` |
| `src/enemies/dummy_enemy.gd` | Update `_setup_drop_table()` to use new API (auto-generated from tier or manual) |

## Current Weapon/Modifier Tiers

For launch, existing items are placed into tiers based on their power level:

- **COMMON**: MeleeWeapon (weight 1.0)
- **UNCOMMON**: (none yet, ready for expansion)
- **RARE**: (none yet, ready for expansion)

Modifier tiers:

- **COMMON**: LavaEmitterModifier (weight 1.0)
- **UNCOMMON**: (none yet)
- **RARE**: (none yet)

As more weapons and modifiers are added, they're simply registered in the appropriate tier pool in `WeaponRegistry._ready()`.