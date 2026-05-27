# Shop UI Redesign: Balatro-Style Layout

## Overview

Redesign the shop UI from a bare-bones centered dialog into a polished Balatro-inspired overlay with a header bar, horizontal card row, and bottom action bar. All colors, fonts, and styling use existing `UiTheme` constants — no new assets needed.

## Layout

```
┌──────────────────────────────────────────┐
│  SHOP                          GOLD: 100  │  ← Header bar (SURFACE_BG, ACCENT bottom border)
├──────────────────────────────────────────┤
│                                          │
│   ┌────────┐  ┌────────┐  ┌────────┐     │
│   │ CARD 1 │  │ CARD 2 │  │ CARD 3 │     │  ← 3 offer cards in HBoxContainer
│   │ icon   │  │ icon   │  │ icon   │     │
│   │ name   │  │ name   │  │ name   │     │
│   └────────┘  └────────┘  └────────┘     │
│     $30          $45          $25         │  ← Price labels below each card
│                                          │
├──────────────────────────────────────────┤
│  ⟳ REROLL $10    REMOVE $50       CLOSE  │  ← Action bar (SURFACE_BG, PANEL_BORDER top border)
└──────────────────────────────────────────┘
```

## Structure

The scene tree changes from the current flat `CenterContainer > VBoxContainer` to:

```
ShopUI (CanvasLayer)
├── Overlay (ColorRect) — fullscreen dimmer
└── ShopPanel (PanelContainer) — centered, themed container
    └── VBoxContainer
        ├── HeaderBar (PanelContainer) — "SHOP" + gold counter
        ├── CardsSection (MarginContainer)
        │   └── BuyContainer (HBoxContainer) — 3 offer cards, centered
        └── ActionBar (PanelContainer) — reroll + remove + close
```

Each `OfferCard` keeps its existing structure (PanelContainer with glow shader, icon, name, description, price).

## Components

### Header Bar
- `PanelContainer` with custom StyleBoxFlat: `SURFACE_BG` background, `ACCENT` 2px bottom border only, no corner radius on bottom (flushed with content below).
- Contains an `HBoxContainer` with:
  - **Left:** `Label` "SHOP" in `ACCENT_GOLD`, font_size 28, bold
  - **Right:** `Label` "GOLD: X" in `ACCENT_GOLD`, font_size 22
- RichTextLabel for BBCode-style gold icon if desired (optional, can just use Label)

### Cards Section
- `MarginContainer` wrapping the `BuyContainer` HBoxContainer (padding 20px vertical, 24px horizontal)
- The existing `CARD_MIN_SIZE := Vector2(160, 200)` and glow/scale-on-hover behavior remain unchanged
- Price labels are moved outside the card (below it) — each offer card gets a sibling `Label` in accent orange showing the price, contained in a `VBoxContainer` per slot

### Action Bar
- `PanelContainer` with custom StyleBoxFlat: `SURFACE_BG` background, `PANEL_BORDER` 1px top border only, no corner radius on top.
- Contains an `HBoxContainer` with:
  - **Left group:** Reroll button + Remove button (side by side)
  - **Right group:** Close button (or single close button right-aligned via container sizing)
- Reroll button: "⟳ REROLL $10" — styled as a Button with existing theme
- Remove button: "REMOVE $50" — styled as a Button, disabled state when cannot afford / no mods
- Close button: accent orange bg, "CLOSE" text
- `UiAnimations.setup_button_hover()` on all buttons

### Offer Card Changes
- Remove the price label and buy button from inside the card (they move outside)
- The card itself becomes purely visual: icon + name + description
- Below each card: price label in `ACCENT` orange
- Buy action: clicking anywhere on the card OR its price area triggers purchase

## Scene Node Changes (shop_ui.tscn)

Replace the current:
```
CenterContainer > VBoxContainer [Title, Gold, BuyContainer, RemoveButton, CloseButton]
```

With:
```
PanelContainer (ShopPanel) — centered via CenterContainer or anchor layout
  VBoxContainer
    PanelContainer (HeaderBar)
      HBoxContainer
        Label (ShopTitle) — "SHOP"
        Label (GoldLabel) — "GOLD: {n}"
    PanelContainer (CardsSection) — style: no border, transparent bg
      MarginContainer
        VBoxContainer (per card slot) — wraps card + price
          HBoxContainer (BuyContainer) — <existing card code>
    PanelContainer (ActionBar)
      HBoxContainer
        Button (RerollButton)
        Button (RemoveButton)
        Button (CloseButton)
```

## Script Changes (shop_ui.gd)

- Add `_reroll_button` reference
- Remove `_title_label` (title becomes header bar's label)
- Remove `_remove_button` reference + add to action bar
- Add `_build_header()`, `_build_action_bar()` helper methods
- Keep `_create_offer_card()` but: remove internal price label + buy button; add per-slot VBox wrapping in `_build_buy_grid()`
- Card click → buy: change from button press to card `gui_input` or `pressed` on the PanelContainer itself

## Animation

- Entrance: dimmer fades in, header/action bar slide from edges, cards stagger slide-in up (reuse `UiAnimations.stagger_slide_in`)
- Close: reverse animation or instant hide (consistent with current behavior)
- Hover: existing glow shader + scale(1.03) + accent border on cards

## Files Modified

- `scenes/economy/shop_ui.tscn` — full scene rebuild
- `src/economy/shop_ui.gd` — restructure for new layout, add reroll logic
- `src/economy/shop_offer.gd` — no changes expected
- `src/ui/ui_theme.gd` — no changes needed (all colors/fonts exist)

## Future Considerations (Out of Scope)

- Reroll function implementation (needs a way to re-roll offers, handled separately)
- Remove modifier picker (current behavior removes last modifier; a picker could be added later)
- Animations polish
