# Modifier Placeholder Icons + Modifier Drop Info Card

**Date:** 2026-07-03
**Branch:** feat/weapon-modifier-balancing
**Status:** Design approved

## Summary

Two related gaps in modifier presentation:

1. **Missing icons.** Pure data-driven modifiers render with no icon on their world
   drop, because the `DataModifier` construction path never assigns `icon_texture`.
2. **No info card.** Weapon drops show a floating info card when the player stands near
   them (`WeaponInfoPopup`), but modifier drops show nothing.

This design gives every iconless modifier a `wall.png` placeholder and makes modifier
drops display an info card — icon + name + description, with rarity coloring — reusing
the existing weapon-card infrastructure.

## Part 1 — Placeholder icons for iconless modifiers

### Problem

`WeaponRegistry._make_modifier(id)` (`src/autoload/weapon_registry.gd:307`) builds
modifiers two ways:

- **Script-backed** (`script.new()`): each script sets its own `icon_texture` in
  `_init` — mostly `preload("res://textures/wall.png")`, one uses a real texture
  (`lava_emitter.png`).
- **Pure data** (`_DataModifier.new(data)`): `DataModifier._init` sets name,
  description, trigger, etc. but **never** sets `icon_texture`, so it stays `null`.

The `null`-icon modifiers are exactly the pure data-driven ones. `Card.populate` and
`Drop._ready` both `hide()`/skip the sprite when the texture is `null`, so these drops
appear icon-less.

### Fix

Add a single fallback at the factory chokepoint. In `_make_modifier`, immediately
before each `return`, if the built modifier's `icon_texture == null`, assign the
placeholder:

```gdscript
const PLACEHOLDER_ICON := preload("res://textures/wall.png")

func _make_modifier(id: String) -> _Modifier:
    var data: Dictionary = _modifier_data.get(id, {})
    var script: GDScript = modifier_scripts.get(id)
    if script != null:
        var mod: _Modifier = script.new()
        mod.name = data.get("name", mod.name)
        mod.description = data.get("description", mod.description)
        mod.suppresses_base_use = String(data.get("suppresses_base_use", "No")).strip_edges() == "Yes"
        mod.rarity = _map_rarity(data.get("rarity", "Common"))   # Part 2
        if mod.icon_texture == null:
            mod.icon_texture = PLACEHOLDER_ICON
        return mod
    if data.is_empty():
        push_warning("WeaponRegistry: unknown modifier id '%s'" % id)
        return null
    var dmod := _DataModifier.new(data)
    dmod.rarity = _map_rarity(data.get("rarity", "Common"))       # Part 2
    if dmod.icon_texture == null:
        dmod.icon_texture = PLACEHOLDER_ICON
    return dmod
```

**Why the factory, not `DataModifier._init`:** the factory is the one place both
construction paths converge, so a fallback here also catches any script modifier that
forgets to set an icon. Putting it in `DataModifier._init` would cover only the data
path.

**Scope note:** This does not touch modifiers already carrying `wall.png` — they keep
it. The user is aware most existing icons are placeholder `wall.png`; replacing those
with real art is out of scope.

## Part 2 — Modifier drop info card

### Approved content

Icon + name + description, with rarity name-color and glow matching weapon cards.
No sub-modifier slots.

### 2a. Rarity on the modifier resource

The `Modifier` resource (`src/weapons/modifier.gd`) has no rarity field today; rarity
lives only in the CSV and is consumed by `_populate_modifier_tiers` for drop-table
weighting. To color the card, rarity must travel with the modifier instance.

- Add `var rarity: int = DropTable.ItemTier.COMMON` to `Modifier`.
- Populate it in `_make_modifier` (both branches, shown above) via the existing
  `_map_rarity(row.get("rarity", "Common"))` helper — the same mapping
  `_populate_modifier_tiers` already uses, so tier semantics stay consistent.

`ItemTier` is `{ COMMON, UNCOMMON, RARE }` (`src/enemies/drop_table.gd:5`), the same
scale `Card.set_rarity` / `UiTheme.get_rarity_color` expect for weapons.

### 2b. Per-drop card population (deep-module boundary)

Rather than teach the popup about payload types, each drop describes itself. Add a
polymorphic method to the drop classes:

```gdscript
# Drop base — default no-op so the popup can call it on any highlighted drop.
func populate_info_card(_card: Card) -> void:
    pass
```

**WeaponDrop.populate_info_card** — moves today's logic out of
`WeaponInfoPopup._populate` verbatim: build cooldown/damage stat strings (honoring
`get_base_stats` when present), gather `mod_icons` from the weapon's slots, call
`card.populate(weapon.icon_texture, weapon.name, stats, mod_icons)` then
`card.set_rarity(weapon.rarity)`.

**ModifierDrop.populate_info_card** — icon + name + description, no sub-slots:

```gdscript
func populate_info_card(card: Card) -> void:
    if modifier == null:
        return
    card.populate(modifier.icon_texture, modifier.name, [modifier.description])
    card.set_rarity(modifier.rarity)
```

Shop subclasses (`ShopWeaponDrop`, `ShopModifierDrop`) inherit these automatically.

### 2c. Description label must auto-size

`Card.populate` renders each stats string as a fixed `Label` (font size 14, no wrap).
A one-line weapon stat fits, but a full modifier description will overflow the card
width.

**Change:** use an auto-sizing label for description lines. Every stats `Label`
created in `Card.populate` gets:

```gdscript
label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
# clamp width to the card interior; derive the inset from the CardPanel /
# ContentVBox theme margins already applied in the scene (fall back to a small
# fixed inset, e.g. 16px, if no margin is queryable).
label.custom_minimum_size.x = card_size.x - CONTENT_INSET
```

so the label wraps within the card and grows vertically to fit its text. The
`ContentVBox` and `CardPanel` already size to their children, so the card body expands
to contain the wrapped description. Single-line weapon stats are unaffected (short text
does not wrap). This keeps one populate path for both card kinds.

### 2d. Generalize the popup to any drop

`WeaponInfoPopup` (`src/ui/weapon_info_popup.gd`) is hard-typed to `WeaponDrop` in
`show_for`, `_update_viewport_scale`, `update_position`, and `_current_drop`, but the
only weapon-specific code is `_populate`. Everything else (viewport-scale tracking,
per-frame screen positioning, show/hide tweens) is payload-agnostic.

Changes:

- Retype `WeaponDrop` → `Drop` in `_current_drop`, `show_for`, `_update_viewport_scale`,
  `update_position`.
- `show_for` guard changes from `drop.weapon == null` to a generic validity check
  (`not is_instance_valid(drop)`); each drop decides its own content.
- Replace the body of `_populate(weapon)` with `drop.populate_info_card(_card)` (rename
  to `_populate(drop: Drop)`), deleting the weapon-specific stat code now living in
  `WeaponDrop`.

The class keeps its name `WeaponInfoPopup` to avoid a rename churn across `PickupContext`
and scene references; its role is now "drop info popup." (A later rename is optional and
out of scope.)

### 2e. PickupContext dispatch

`src/player/pickup_context.gd:45` gates the popup on `_highlighted is WeaponDrop`.
Change to a capability check:

```gdscript
if _highlighted and _highlighted.has_method("populate_info_card"):
    _info_popup.show_for(_highlighted)
    _info_popup.update_position(_highlighted, _player)
else:
    _info_popup.dismiss()
```

Because `ModifierDrop`, `ShopWeaponDrop`, and `ShopModifierDrop` all inherit
`populate_info_card` (real or default no-op), this shows the card for weapon and
modifier drops (and their shop variants) with one branch, preserving current
shop-weapon behavior.

## Data flow

```
Enemy/chest/shop spawn
  └─ drop.modifier = WeaponRegistry.get_random_modifier(tier)
        └─ _make_modifier(id)
              ├─ builds modifier (script or data)
              ├─ sets .rarity from CSV               (Part 2a)
              └─ fills .icon_texture with wall.png if null   (Part 1)

Player nears drop
  └─ PickupContext._process
        └─ _highlighted.has_method("populate_info_card")     (Part 2e)
              └─ WeaponInfoPopup.show_for(drop)
                    └─ drop.populate_info_card(card)          (Part 2b)
                          └─ Card.populate(icon, name, [description])  (auto-wrap)  (Part 2c)
                          └─ Card.set_rarity(modifier.rarity)
```

## Files touched

| File | Change |
|------|--------|
| `src/autoload/weapon_registry.gd` | `PLACEHOLDER_ICON` const; icon fallback + rarity set in `_make_modifier` |
| `src/weapons/modifier.gd` | add `var rarity: int = DropTable.ItemTier.COMMON` |
| `src/drops/drop.gd` | add default no-op `populate_info_card(_card: Card)` |
| `src/drops/weapon_drop.gd` | add `populate_info_card` (moved from popup) |
| `src/drops/modifier_drop.gd` | add `populate_info_card` |
| `src/ui/weapon_info_popup.gd` | retype `WeaponDrop`→`Drop`; `_populate` delegates |
| `src/ui/card.gd` | stats labels auto-wrap within card width |
| `src/player/pickup_context.gd` | capability-based popup dispatch |

## Testing

- **Icon fallback:** unit-style check that `WeaponRegistry._make_modifier` returns a
  non-null `icon_texture` for a pure-data modifier id and for a script modifier id.
- **Rarity carry:** `_make_modifier` sets `.rarity` matching `_map_rarity(csv rarity)`.
- **Card population:** `ModifierDrop.populate_info_card` on a stub `Card` sets icon,
  name, one description line, and calls `set_rarity`.
- **Dispatch:** `PickupContext` shows the popup for a `ModifierDrop` and dismisses when
  none is highlighted (can reuse existing weapon-popup test harness if present).
- **Manual:** in-editor, spawn a data modifier via console, confirm the world sprite
  shows `wall.png` and the info card appears with a wrapped description sized to fit.

## Out of scope

- Replacing existing `wall.png` placeholders with real modifier art.
- Renaming `WeaponInfoPopup` to a generic name.
- Any change to modifier drop-rate weighting or CSV schema.
