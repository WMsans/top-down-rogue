# Per-weapon rarity + full-pool chests

**Date:** 2026-05-22
**Status:** Draft

## Problem

1. Chests only ever show `melee_weapon` and `test_weapon`. `Chest` defaults
   `tier = DropTable.ItemTier.COMMON` (`src/drops/chest.gd:8`) and
   `_generate_weapons()` pulls exclusively from the COMMON bucket, which is the
   only bucket that contains those two scripts
   (`src/autoload/weapon_registry.gd:35-43`). `ranged_weapon` sits alone in
   UNCOMMON and is never reachable from a normal chest.
2. Rarity is encoded in the registry's hard-coded tier dictionary, so a weapon
   class is "common" only because of where it was registered. There is no way
   for a weapon to declare its own rarity, and adding a weapon requires editing
   `_populate_tiers()` and remembering which bucket it belongs in.

## Goals

- Chests pull from the full weapon pool, with tier-weighted randomness similar
  to enemy drops.
- Each weapon declares its own rarity. Adding a new weapon means one entry in
  a flat registration list — no per-tier bookkeeping.
- Reuse the existing enemy-drop tier-weight table so there is one source of
  truth for "how often does an UNCOMMON show up at this difficulty."

## Non-goals

- Reworking the chest tiering UX (chest sprites, labels, etc.).
- Adding new weapons or new rarity levels.
- Per-instance rarity overrides for already-spawned weapons.

## Design

### Rarity on the weapon

Add to `src/weapons/weapon.gd`:

```gdscript
@export var rarity: int = DropTable.ItemTier.COMMON
```

Subclasses set their own default in `_init()`:

- `melee_weapon` → `DropTable.ItemTier.COMMON`
- `test_weapon` → `DropTable.ItemTier.COMMON`
- `ranged_weapon` → `DropTable.ItemTier.UNCOMMON`

(Values match today's registry layout so behavior at COMMON/UNCOMMON tiers
stays equivalent for those weapons.)

### Registry: flat list, tier buckets built at startup

Replace the hard-coded `_populate_tiers()` buckets in
`src/autoload/weapon_registry.gd` with a single registration list and a build
step:

```gdscript
var _all_weapons: Array = [
    { "script": preload("res://src/weapons/melee_weapon.gd"),  "weight": 1.0 },
    { "script": preload("res://src/weapons/test_weapon.gd"),   "weight": 0.5 },
    { "script": preload("res://src/weapons/ranged_weapon.gd"), "weight": 1.0 },
]

func _build_tier_buckets() -> void:
    weapon_tiers.clear()
    for entry in _all_weapons:
        var probe: Weapon = entry.script.new()
        var tier: int = probe.rarity
        if not weapon_tiers.has(tier):
            weapon_tiers[tier] = []
        weapon_tiers[tier].append(
            WeaponDropEntry.new(entry.script, entry.weight))
```

`get_random_weapon(tier)` keeps its current signature and fallback-to-COMMON
behavior. The modifier path is untouched.

Adding a new weapon = one line in `_all_weapons` + the weapon's own `rarity`
default.

### Chest: per-slot tier roll, reusing `_TIER_ITEM_WEIGHTS`

- Change `Chest.tier`'s meaning from `DropTable.ItemTier` (COMMON/UNCOMMON/RARE)
  to `DropTable.EnemyTier` (EASY/NORMAL/HARD). Default `NORMAL`. This is the
  key that `_TIER_ITEM_WEIGHTS` uses.
- Add a public helper on `DropTable`:

  ```gdscript
  static func roll_item_tier(enemy_tier: int) -> int
  ```

  Weighted random pick over `{COMMON, UNCOMMON, RARE}` using the existing
  `_TIER_ITEM_WEIGHTS` table. (Promote the constant or expose via this helper —
  the helper keeps the table private.)

- In `chest.gd::_generate_weapons()`, for each of `CHOICE_COUNT` slots:
  1. Roll an item tier via `DropTable.roll_item_tier(tier)`.
  2. Call `WeaponRegistry.get_random_weapon(rolled_tier)`.
  3. Apply the existing dedup-by-script logic; existing fallback retry stays.

If `get_random_weapon` returns null because the rolled tier's bucket is empty
(e.g., no RARE weapons exist yet), the registry already falls back to COMMON —
no extra handling needed in the chest.

### Callers to update

- `src/core/features/feature_chest_spawn.gd` — anywhere it sets a chest tier,
  switch the value from `ItemTier.*` to `EnemyTier.*`.
- `src/console/commands/spawn_command.gd` — same, if it accepts a tier
  argument for spawning chests.

## Data flow

1. Game start: `WeaponRegistry._ready()` runs `_build_tier_buckets()`. Each
   weapon script is instantiated once; its `rarity` field decides its bucket.
2. Player opens a chest: `Chest.interact()` → `_generate_weapons()` loops
   `CHOICE_COUNT` times, each iteration rolls a tier then a weapon.
3. UI flow downstream is unchanged.

## Testing

- Manual: spawn an EASY, NORMAL, and HARD chest via console; confirm the mix
  of weapon rarities skews appropriately (HARD shows more UNCOMMON, etc.).
- Manual: verify `ranged_weapon` is now reachable from a default-spawned chest.
- Unit (if a registry test exists): assert each weapon lands in the bucket
  matching its declared `rarity`.

## Tradeoffs

- **Pro:** Rarity lives with the weapon; adding weapons is a one-liner; chests
  draw from the whole pool with tier-weighted randomness consistent with enemy
  drops.
- **Con:** Each weapon script is instantiated once at startup to read its
  `rarity`. Trivial cost at three weapons; still cheap at dozens. If this ever
  becomes a hot path, swap `@export var` for a `const RARITY` read via
  `script.get_script_constant_map()`.

## Open questions

None blocking. `test_weapon` is currently treated as COMMON — keep or move to
a debug-only path later, out of scope here.
