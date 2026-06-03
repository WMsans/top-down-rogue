# Shop Room Redesign — Design Spec

**Date:** 2026-06-03
**Status:** Approved, ready for implementation plan

## Goal

Replace the current full-screen `ShopUI` with a physical **shop room** the
player walks through. Items sit on the ground as pickups; **picking one up is
paying for it** (Soul Knight style). Stock follows a Slay the Spire layout:
mostly modifier cards, three weapons (relics), no potions, plus a card-removal
service in the bottom-right corner. Shops appear frequently across all biomes.

## Background — current systems

- **Old shop:** `src/economy/shop_ui.gd` (`ShopUI`, a paused full-screen
  `CanvasLayer`) with a card grid, reroll button, and remove-modifier card.
  Spawned by `spawn_dispatcher._spawn_shop()` (marker `G=4`), which just adds the
  UI canvas to the scene.
- **Drops:** `src/drops/drop.gd` (`Drop`, RigidBody2D) → `WeaponDrop`,
  `ModifierDrop`. They expose `interact(player)` → `_pickup(player)`. The player's
  `PickupContext` detects nearby drops (collision layer/mask 2), highlights the
  closest, and on the `interact` action calls `interact()`. Pickups route through
  `WeaponDelivery.offer(spec, callback)`, which shows the slot-selection popup
  (`WeaponPopup`) for weapons/modifiers and a remove flow for
  `OfferType.REMOVE_MODIFIER`. On an accepted result the drop `queue_free`s.
- **Rooms:** Templates are PNGs. Channels: **R = material id**, **G = marker
  type**, **A = 255 = write this cell** (A=0 leaves native cave). `R=255` is the
  "biome-native wall" sentinel. Markers: `1` enemy, `2` elite, `3` chest,
  `4` shop, `5` secret loot, `6` boss. `spawn_dispatcher` reads markers from the
  template and spawns entities at their world positions.
  `sector_grid` selects templates per sector by weight.
- **Materials:** `MAT_AIR = 0`, `MAT_WOOD = 1`, `MAT_STONE = 2`, … (see
  `material_registry.gd`). Wood walls = pixels with `R = 1`.
- **Mob-free guarantee:** rooms only get enemies from enemy markers baked into
  the template. The spawn room (a `fixed_anchor` at sector `(0,0)`) has none. The
  shop room will likewise carry **only** the shop marker.

## Decisions (locked)

| Topic | Decision |
|-------|----------|
| Spawn frequency | Shop template added to **every biome** at **high weight**; non-rotatable. Multiple shops per floor possible. |
| Pay model | **Press E** (reuses weapon-drop interact). Pay = pickup. |
| Unaffordable | **Reject + feedback**: item stays, jitter/shake + gold flash; nothing charged. |
| Reroll | **Removed.** Stock is fixed when the room generates. |
| Stock | **5 modifiers + 3 weapons + 1 removal service.** |
| Layout | **A — Storefront rows** (see below). |
| Walls | **Sealed, thick (~4px) wood walls.** No doorway; player digs in, mobs can't. |
| Old UI | **Delete** `shop_ui.gd` + scene. |

## Layout A — Storefront rows (top-down, door-less)

```
┌──────────────────────────┐   ← thick wood wall ring (sealed)
│  ◆   ◆   ◆   ◆   ◆        │   5 modifier cards along the back/top
│                          │
│      ▮     ▮     ▮        │   3 weapons across the middle
│                          │
│                       ✖  │   removal service, bottom-right
└──────────────────────────┘
```

Items are placed at fixed offsets from the shop marker's world position
(see ShopStall below). The room is **non-rotatable** so this orientation is
always consistent.

## Components

### 1. Shop room template

Rewrite `tools/room_generators/shop_chamber.gd` and regenerate
`assets/rooms/<biome>/shop_a.png` (via `tools/generate_room_templates.gd`):

- **size_class 96** (large enough that 9 pickups don't crowd each other).
- **Sealed wood wall ring**, ~4px thick, painted `Color8(MAT_WOOD=1, 0, 0, 255)`
  on all four edges with no gap.
- Interior filled with AIR (`Color8(0, 0, 0, 255)`).
- **One marker only:** shop `G=4` at the room center
  (`Color8(0, 4, 0, 255)`). No enemy markers ⇒ mob-free, same as spawn room.

Register the template in **every** biome `.tres`
(`assets/biomes/{caves,mines,magma,frozen,vault}.tres`) under `room_templates`
with `size_class = 96`, `rotatable = false`, and a **high weight** (target value
chosen during implementation; high relative to other templates and to
`EMPTY_WEIGHT = 1.5`).

### 2. `ShopStall` — layout + stock spawner

New `src/economy/shop_stall.gd` (a `Node2D`), instanced by
`spawn_dispatcher._spawn_shop(world_pos)` (replacing the old UI-canvas spawn) and
positioned at the marker. On `_ready` it rolls stock and lays out priced
pickups at fixed offsets from its origin, matching layout A:

- 5 `ShopModifierDrop` along the top row.
- 3 `ShopWeaponDrop` across the middle.
- 1 `ShopRemoval` in the bottom-right.

Offsets are named constants (tunable). Spacing must keep pickup centers far
enough apart to read individually; with the player detection radius of 12px and
a 96px room (~88px interior), example offsets:

- Modifiers: `x ∈ {-36,-18,0,18,36}`, `y = -30`.
- Weapons: `x ∈ {-28,0,28}`, `y = 0`.
- Removal: `(+34, +32)`.

(`PickupContext._find_closest_pickup` already disambiguates overlapping
detection ranges by choosing the nearest, so tight spacing is safe.)

**Stock rolling:** modifiers from the modifier tier buckets, weapons from
`WeaponRegistry.get_random_weapon`. Dedupe by script/resource where the pool
allows; fall back to repeats when the pool is too small. (Content note: only one
modifier — `lava_emitter` — exists today, so the 5 cards will repeat until more
modifiers are authored. Out of scope here.)

### 3. Priced pickups (reuse weapon/modifier drop)

Two thin subclasses adding a price and a price label, reusing the parent
`_pickup`/`WeaponDelivery` flow:

- `src/drops/shop_modifier_drop.gd` — `ShopModifierDrop extends ModifierDrop`
- `src/drops/shop_weapon_drop.gd` — `ShopWeaponDrop extends WeaponDrop`

Each adds:
- `price: int`.
- A small **world-space price label** above the sprite (a `Label`/`Label2D`
  child), colored via `UiTheme` — `TEXT_PRIMARY` when affordable, `DANGER` when
  not. Reuses the existing outline highlight on proximity.

Overridden pickup behavior:
1. On `_pickup(player)`, **pre-check** `inventory.gold >= price`.
   - If not affordable → `UiAnimations.jitter_bounce` on the item + flash gold
     (reuse HUD/`currency_hud` feedback); **item stays, nothing charged**. Return.
2. If affordable → call the inherited `WeaponDelivery.offer(...)` (shows the
   slot-selection popup as normal).
3. In the accepted callback only: `inventory.spend_gold(price)` then
   `queue_free()`. On a non-accepted result (slots full, popup cancelled),
   **nothing is charged and the item remains**.

### 4. `ShopRemoval` — card-removal service

New `src/economy/shop_removal.gd` (Area2D, same pickup interface:
`get_pickup_type`, `should_auto_pickup → false`, `interact`, `set_highlighted`),
placed bottom-right by `ShopStall`. A distinct sprite + world-space price label.

On `interact(player)`:
1. Verify the player has at least one equipped modifier and
   `gold >= remove_cost`; otherwise jitter + gold flash, no-op.
2. Route through `WeaponDelivery.offer(spec, callback)` with
   `OfferType.REMOVE_MODIFIER` (reuses existing remove flow + popup).
3. On accepted: `spend_gold(remove_cost)`, then **escalate**
   `remove_cost = 60 + 30 * uses` and update the label in place. The service
   stays in the room (repeatable).

### 5. Pricing model

Prices as named constants (tunable):

- **Modifiers** by tier bucket: common ≈ 30, uncommon ≈ 60, rare ≈ 100 g.
- **Weapons** by `weapon.rarity`: ≈ 120 / 200 / 320 g.
- **Removal:** starts 60, `+30` per use within the room.

### 6. Cleanup

- **Delete** `src/economy/shop_ui.gd` and `scenes/economy/shop_ui.tscn`.
- `src/economy/shop_offer.gd` (`ShopOffer`) is only used by the old UI and the
  console command — remove if unused after the rewrite, or keep only if the new
  code reuses it.
- Repoint the console `shop` command (`src/console/commands/shop_command.gd`) to
  spawn a `ShopStall` next to the player for testing instead of opening `ShopUI`.
- `WeaponDelivery` / `WeaponPopup` (slot selection, remove flow) are **untouched**.

## Data flow

```
sector_grid selects shop template (high weight, all biomes)
   → spawn_dispatcher reads marker G=4
   → _spawn_shop(world_pos) instances ShopStall at marker
       → ShopStall rolls stock, places ShopModifierDrop×5,
         ShopWeaponDrop×3, ShopRemoval×1 at layout-A offsets
   → player presses E on an item (PickupContext)
       → priced _pickup: affordability pre-check
           → unaffordable: feedback, item stays
           → affordable: WeaponDelivery.offer → slot popup
               → accepted: spend_gold(price), queue_free
               → cancelled/full: no charge, item stays
```

## Error / edge handling

- Insufficient gold: feedback only, never charged.
- Full weapon/modifier slots, or popup cancelled: not charged, item stays.
- Removal with no equipped modifiers: no-op with feedback.
- Charge happens exactly once, only in the accepted callback.

## Testing (gdUnit4)

- `ShopStall` spawns exactly 5 modifiers + 3 weapons + 1 removal at expected
  offsets.
- Affordable pickup charges exactly once and only on accept.
- Unaffordable pickup charges nothing and leaves the item.
- Cancelled/slot-full pickup charges nothing and leaves the item.
- Removal escalates price per use and no-ops with no modifiers / insufficient
  gold.
- Manual smoke test via the `shop` console command.

## Out of scope

- Authoring additional modifiers (needed for card variety).
- Reroll, potions, merchant NPC dialogue.
- Tuning final spawn weight / prices beyond sensible starting constants.
