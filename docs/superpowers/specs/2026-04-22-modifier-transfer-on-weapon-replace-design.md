# Modifier Transfer on Weapon Replace

## Overview

When picking up a weapon drop and all weapon slots are filled, the player chooses a weapon to replace, then chooses one modifier from the replaced weapon to transfer to the new weapon. A "Skip" option is available (Slay the Spire style) to decline transferring a modifier.

## Flow

1. Player picks up a `WeaponDrop` when all 3 weapon slots are full.
2. **Weapon Selection** (existing): `WeaponPopup` opens in pickup mode showing 3 weapon cards with title "Replace a slot:". Player clicks a card.
3. **Modifier Selection** (new):
   - If the replaced weapon has at least one modifier, the popup transitions to modifier selection:
     - The modifier icons from the selected weapon card animate upward and scale up into larger selection cards.
     - Each card shows the modifier's icon, name, and description.
     - A "Skip" button is shown below the cards.
   - If the replaced weapon has no modifiers, skip this step entirely and complete the swap immediately.
4. Player selects a modifier → it is placed in the first empty modifier slot on the new weapon, then the swap completes and the popup closes.
5. Player selects "Skip" → the swap completes without transferring any modifier, and the popup closes.

## Animation Detail

When transitioning from weapon selection to modifier selection:

1. Record the global positions and sizes of the modifier icon `Control` nodes on the selected weapon card.
2. Clear the weapon cards from `_cards_container`.
3. Create modifier selection cards in `_cards_container`. Each card initially:
   - Is positioned at the recorded global position of the corresponding modifier icon.
   - Has its scale set to match the ratio of the small icon size (32x32) to the final card size.
   - Starts with only the icon visible (name and description labels are transparent).
4. Animate each modifier card:
   - Move to its final centered position within `_cards_container`.
   - Scale up to full size.
   - Fade in name and description labels.
5. Cards use the existing stagger animation pattern (slight delay between cards) for a polished feel.
6. The "Skip" button fades in after the cards finish animating.

## Files to Modify

### `src/ui/weapon_popup.gd`
- Add state variables: `_pickup_transfer_mode: bool`, `_pickup_replace_slot: int`, `_pickup_replace_weapon: Weapon`
- In `_on_card_input` for pickup mode: instead of immediately calling the callback, check if the replaced weapon has modifiers. If yes, enter transfer mode and transition to modifier selection. If no, proceed with swap immediately.
- Add `_build_modifier_transfer_cards()` method to create modifier selection cards with animation.
- Add `_on_modifier_transfer_selected(modifier: Modifier)` to handle picking a modifier.
- Add `_on_modifier_transfer_skip()` to handle skipping.
- Change `_pickup_callback` signature from `(slot_index: int)` to `(slot_index: int, modifier: Modifier)` so the callback includes the chosen modifier (or null for skip).
- Add a "Skip" button to the modifier selection view.

### `src/drops/weapon_drop.gd`
- Update `_on_slot_selected` to accept `(slot_index: int, modifier: Modifier, player: Node)`.
- Before calling `swap_weapon`, if `modifier != null`, find the first empty modifier slot on the new weapon and call `add_modifier` on it.
- Then proceed with `swap_weapon` and `queue_free` as before.

### `src/weapons/weapon_manager.gd`
- Add a helper method `find_empty_modifier_slot(weapon: Weapon) -> int` (or this could be on `Weapon` itself). Currently `_find_empty_modifier_slot` is a private method on `weapon_popup.gd`. A public version on `Weapon` would be cleaner.
- Actually, `Weapon.get_modifier_at()` and `Weapon.modifier_slot_count` are already public, so the `weapon_drop.gd` can do the lookup directly. No change needed to `weapon_manager.gd`.

### `src/weapons/weapon.gd`
- Add `find_empty_modifier_slot() -> int` convenience method. This is optional but keeps the logic encapsulated.

## Card Layout for Modifier Selection

Each modifier card is a `PanelContainer` containing:
- Icon (96x96, same as weapon card icon size for consistency)
- Name label (gold accent color)
- Description label (secondary text color, wrapped)

Cards are arranged in an `HBoxContainer` (the existing `_cards_container`).
A `Button` labeled "Skip" is added below the cards in the parent `VBoxContainer`.

## Edge Cases

- **Replaced weapon has no modifiers**: Skip the modifier selection step entirely. Proceed with swap immediately.
- **New weapon has no empty modifier slots**: The transfer still proceeds — the modifier is placed via `add_modifier` which replaces whatever is in the first empty slot. If all modifier slots on the new weapon are full, the transferred modifier replaces the modifier in the first slot. Actually, this shouldn't typically happen since weapons have 3 modifier slots and only 1 modifier is common. But to handle it: `add_modifier` already overwrites slots blindly, so we should find the first empty slot, and if none exists, overwrite slot 0. Or: only transfer if there's an empty slot. Let's use the same logic as `ModifierDrop`: only transfer to an empty slot. If there's no empty slot, transfer is not possible and the "Skip" flow is mandatory — but we should just not show the modifier selection in that case, or show it with a note. For simplicity: transfer to the first empty slot. If no empty slot exists on the new weapon, the selected modifier replaces slot 0.