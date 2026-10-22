# Dash — Default Weapon in Slot 3 — Design

## Intent

The player starts every run with two filled weapon slots (gas test weapon in slot 0, plain
melee in slot 1) and one empty. Give slot 2 a fixed mobility tool: press `C`, dash in the
direction you are moving, invincible for the dash. It is starting equipment, not loot — no
enemy carries it, no chest or shop produces it, and it never appears in the drop pool.

## Goals

- `Dash` lives in slot 2 from the first frame of every run, alongside the existing defaults.
- Using it dashes the player in the held movement direction (falling back to facing when
  standing still) and grants invincibility for the dash.
- It is unreachable from loot by construction, not by remembering to filter it out.
- It has no modifier slots: shops and the modifier UI cannot offer it a slot.

## Non-goals

- No dedicated icon/art. No dash trail VFX.
- No damage, carving, or enemy interaction during the dash — it is movement plus i-frames.
- Not obtainable, sold, dropped, or spawnable from the debug console.
- No changes to other weapons, the registry, the CSVs, drop tables, chests, or shops.

## Approach (chosen: script-only default weapon)

`DashWeapon extends Weapon`, constructed directly in
`WeaponManager._setup_weapons` for slot 2 — the same way the test weapon and melee default
are built today. It has no `weapons.csv` row and no `weapon_registry.gd` archetype, so every
loot path (`chest.gd`, `shop_stall.gd`, `cave_spawner.gd`, `spawn_dispatcher.gd`, spawn
console) is excluded by construction. The rejected alternative — a CSV row plus an
"unlootable" flag — needs exclusion checks in six call sites and a missed one leaks the
weapon back into loot.

## Pieces

| File | Change |
|------|--------|
| `src/weapons/dash_weapon.gd` | NEW. `DashWeapon extends Weapon`, `modifier_slot_count = 0`. `_use_impl` dashes and grants i-frames. |
| `src/player/player_controller.gd` | NEW public `get_move_direction()`; wraps the existing private `_get_input_direction()`. |
| `src/player/player_inventory.gd` | NEW public `grant_invincibility(duration)` + `is_invincible()`. Existing i-frame timer/blink does the work; nothing else changes. |
| `src/weapons/weapon_manager.gd` | Preload the script; `equip_weapon(2, DashWeaponScript.new())` in `_setup_weapons`. `KEY_C` already maps to slot 2. |

## Numbers (my calls; tune later)

- `cooldown = 0.35` s, paced by the existing weapon cooldown timer.
- Dash impulse `810` px/s. `PlayerController` decays dash velocity at 9/s, so travel is
  `speed / 9 ≈ 90` px, most of it in the first 0.15 s.
- Invincibility `0.25` s — covers the dash plus the decaying tail, leaving ~0.1 s vulnerable
  between dashes.
- Direction: `get_move_direction()`, falling back to `get_facing_direction()` (which
  auto-targets the nearest enemy) when no movement key is held.
- Icon: none. The HUD shows its existing fallback glyph rather than borrowing another
  weapon's art.

## Rules kept honest

- Damage-over-time still ticks through dash i-frames, matching today's rule that
  `take_status_tick()` bypasses invincibility.
- `modifier_slot_count = 0` makes `find_empty_modifier_slot()` return `-1` and
  `add_modifier()` a no-op, so the shop's `can_equip_modifier()` path already refuses it.
- The dash is an impulse through the existing `request_dash()`, so terrain collision,
  overlap recovery, and velocity sanitising are unchanged.

## Verification

New `tests/unit/test_dash_weapon.gd`:

- use with a held direction dashes that way at the expected speed;
- use with no input dashes along facing;
- use grants invincibility, and it expires after the duration;
- the weapon reports zero modifier slots;
- `WeaponManager._setup_weapons` leaves a `DashWeapon` in slot 2.

Existing `test_player_dash`, `test_player_inventory`, and `test_weapon_manager`-adjacent
suites must still pass.
