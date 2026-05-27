# Bundled Weapon + Modifier Drops

## Problem

Killing a regular enemy currently produces up to three independent drops:

1. A guaranteed `WeaponDrop` carrying the enemy's equipped weapon (no modifier), spawned by `Enemy._spawn_drops()`.
2. A random `weapon_pool` `WeaponDrop` from `DropTable.from_enemy_tier()` (~30% per kill), unrelated to the enemy's weapon.
3. A random standalone `ModifierDrop` from the same table (~10% per kill).

Two issues:

- **Loot clutter.** Modifiers and weapons are decoupled at drop time even though the player will almost always pair them.
- **Combat/loot mismatch.** Modifiers exist only as pickups; enemies never actually wield them, so the player can't preview the effect by fighting the enemy and the drop hint can't promise what's inside.

## Solution

Move modifier rolling from death-time loot to enemy spawn. The enemy's weapon gets a possibly-attached modifier on `_ready()`, fights with that modifier's effect active, and drops with the modifier bundled when it dies.

- Modifier roll happens once, at enemy spawn, using existing tier weights.
- The same `Weapon` resource (duplicated per enemy) is reused at drop time — no re-rolling.
- The drop hint card already reads `weapon.modifiers` and renders modifier-slot icons, so no UI changes are needed.
- Bosses are excluded: their weapon stays plain, and their existing guaranteed `modifier_pool(RARE)` drop is unchanged.

## Architecture

### Current Flow

```
spawn → Enemy._ready() → weapon = weapon_resource.duplicate()  (no modifier)
combat → weapon.use()/tick() → no modifier effect
death → _spawn_drops():
          drop_table.resolve() → maybe gold + maybe random weapon + maybe random modifier
          unconditionally drop enemy's weapon
```

### New Flow

```
spawn → Enemy._ready() → weapon = weapon_resource.duplicate()
                      → DropTable.roll_modifier_for_enemy(tier) → maybe attach
combat → weapon.use()/tick() → modifier on_use / on_tick fires (existing iteration)
death → _spawn_drops():
          drop_table.resolve() → gold only (for regular enemies)
          if DropTable.roll_should_drop_weapon(tier): drop enemy's weapon
                                                      (carries attached modifier)
```

## Components

### 1. `src/enemies/drop_table.gd`

**Changes:**

- `from_enemy_tier(tier, drops_gold, drops_weapon, drops_modifier)` — drop the `weapon_pool` and `modifier_pool` `add_entry` calls. For regular enemies the table now returns gold-only. The `drops_weapon` / `drops_modifier` parameters are kept (default `true`) to preserve the signature for existing callers (boss + tests) but become no-ops. Optional follow-up cleanup: remove the unused params and update callers/tests.
- Add static helper:

  ```gdscript
  static func roll_modifier_for_enemy(enemy_tier: int) -> Modifier:
      var chance: float = _TIER_MODIFIER_WEIGHT[enemy_tier]
      if randf() > chance:
          return null
      var item_tier := resolve_item_tier(enemy_tier)
      return WeaponRegistry.get_random_modifier(item_tier)
  ```

- Add static helper:

  ```gdscript
  static func roll_should_drop_weapon(enemy_tier: int) -> bool:
      return randf() <= _TIER_WEAPON_WEIGHT[enemy_tier]
  ```

- Remove `_resolve_weapon_pool` and the `WEAPON_DROP_SCENE` constant (no caller left — boss does not use them).
- Keep `_resolve_modifier_pool`, `MODIFIER_DROP_SCENE`, and `DropKind.MODIFIER_POOL`: boss explicitly adds a `modifier_pool(RARE)` entry.
- Keep `DropKind.WEAPON_POOL` enum value to avoid renumbering, but it is no longer producible. (Optional follow-up cleanup; not required.)

### 2. `src/enemies/enemy.gd`

**Changes:**

- After the existing `_setup_weapon_visual.call_deferred()` block in `_ready()`, call `_roll_weapon_modifier()`.
- Add virtual method:

  ```gdscript
  func _roll_weapon_modifier() -> void:
      if weapon == null:
          return
      var modifier := DropTable.roll_modifier_for_enemy(enemy_tier)
      if modifier == null:
          return
      var slot := weapon.find_empty_modifier_slot()
      if slot >= 0:
          weapon.add_modifier(slot, modifier)
  ```

- Replace `_spawn_drops()` body:

  ```gdscript
  func _spawn_drops() -> void:
      if drop_table:
          drop_table.resolve(global_position, get_parent())
      if weapon and DropTable.roll_should_drop_weapon(enemy_tier):
          var drop_scene := preload("res://scenes/weapon_drop.tscn")
          var drop: Node = drop_scene.instantiate()
          drop.weapon = weapon
          drop.global_position = global_position + Vector2(randf_range(-8, 8), randf_range(-8, 8))
          get_parent().add_child(drop)
  ```

- Modifier attachment runs *after* `_apply_elite_scaling()` (which lives inside `_ready()` before this point). Elite scaling multiplies `weapon.damage`; modifiers attach afterward and may further mutate stats via `on_equip`. Acceptable ordering — no current modifier reads pre-scaled damage.

### 3. `src/enemies/boss_enemy.gd`

**Changes:**

- Override `_roll_weapon_modifier()` to no-op (boss weapon stays plain).
- Keep existing `drop_table.add_entry(DropTable.DropEntry.modifier_pool(1.0, DropTable.ItemTier.RARE, 1, 1))` line — boss continues to drop one guaranteed RARE standalone modifier.
- Boss weapon must continue to drop unconditionally (matches prior behavior). Override `_spawn_drops()` in `boss_enemy.gd` to skip the `roll_should_drop_weapon` gate and always spawn the weapon drop, while still letting `drop_table.resolve()` run so the explicit RARE modifier_pool entry fires.

### 4. Drop preview — `src/ui/weapon_info_popup.gd`

**No changes.** `_populate()` already iterates `weapon.modifier_slot_count` and reads `weapon.get_modifier_at(i).icon_texture`. Any modifier attached at spawn renders automatically.

### 5. Pickup — `src/drops/weapon_drop.gd` and `WeaponDelivery`

**No changes expected.** `WeaponDrop.weapon` is passed by reference into `WeaponOfferSpec.weapon`; the player's `WeaponDelivery` accepts the full `Weapon` resource with its `modifiers` array intact. Verify during implementation that no path strips modifiers (e.g. a second `duplicate()` without `true` for subresources).

## Edge Cases

- **Empty modifier slot**: `find_empty_modifier_slot()` returns `-1` if full. Default weapons have `modifier_slot_count = 3` and start empty, so slot 0 is always available at spawn. Guard is defensive.
- **Enemy without `weapon_resource`**: melee/ranged/boss enemies fall back to constructing a default `MeleeWeapon`/`RangedWeapon`. Modifier roll still applies — that's fine.
- **Resource duplication**: enemies already call `weapon_resource.duplicate()`. Attaching a modifier mutates the duplicate, not the shared `.tres` asset.
- **Pooled drops**: `WeaponDrop` is instantiated fresh per drop (no pool currently). If pooling is added later, ensure `weapon` is reassigned per-use.

## Testing

**Unit (`tests/unit/`):**

- `DropTable.roll_modifier_for_enemy` returns `null` when RNG forces miss; returns a `Modifier` of plausible tier on hit. Use seeded RNG.
- `DropTable.roll_should_drop_weapon` honors `_TIER_WEAPON_WEIGHT` distribution under seeded RNG.
- Update `tests/unit/test_drop_table.gd`:
  - Remove `test_from_enemy_tier_weapon_entries_exist` (weapon_pool entries no longer generated).
  - Keep gold-related tests; they should still pass since gold entry is unchanged.

**Manual:**

- Spawn a `MeleeEnemy` via console; over ~20 spawns, ~10% should fight with a visibly modded weapon (e.g. lava emitter trail emitting from the enemy).
- Kill a modded enemy; confirm `WeaponDrop` hint card shows the modifier icon in a slot.
- Pick up the modded weapon; confirm the modifier remains attached in the player's loadout and its effect fires when the player uses it.
- Kill 10 regular enemies; confirm no standalone `ModifierDrop` spawns (only gold + possibly a weapon).
- Kill a boss; confirm weapon drops plain and a separate RARE `ModifierDrop` still spawns.

## Out of Scope

- Modifier balance changes (test_modifier remains intentionally test-only).
- Rolling more than one modifier per enemy weapon.
- Bundling modifiers into `weapon_pool` random drops (no longer used for regular enemies).
- Chest / loot-room drops (untouched).
