# Shop Item Spacing — Design Spec

**Date:** 2026-06-14
**Status:** Approved

## Goal

Spread shop items across the full room interior so they are individually
distinguishable and easy to interact with, instead of being crammed into a
tiny cluster at the center.

## Background

The `ShopStall` position constants were set for a 96px room (per the original
spec example offsets). The actual shop template is **256x256** (size_class
256), giving a **244px interior** (6px wood walls on each edge). Items use
only ~72px of that width, clustering everything in the center.

## Change

Update four position constants in `src/economy/shop_stall.gd` to use ~80% of
the 244px interior. Same 3-row layout — modifiers top, weapons middle, removal
bottom-right — just properly spaced.

### New constants

| Constant | Old value | New value |
|---|---|---|
| `MODIFIER_Y` | `-30.0` | `-80.0` |
| `MODIFIER_XS` | `[-36.0, -18.0, 0.0, 18.0, 36.0]` | `[-100.0, -50.0, 0.0, 50.0, 100.0]` |
| `WEAPON_Y` | `0.0` | `50.0` |
| `WEAPON_XS` | `[-28.0, 0.0, 28.0]` | `[-70.0, 0.0, 70.0]` |
| `REMOVAL_OFFSET` | `(34.0, 32.0)` | `(95.0, 95.0)` |

### Spacing analysis

- 5 modifiers: **50px** center-to-center, spanning ±100px (200px total, 82% of
  244px interior). 34px minimum gap between adjacent 16px collision circles.
- 3 weapons: **70px** center-to-center, spanning ±70px (140px total, 57% of
  interior). 54px between collision circles.
- **130px** vertical gap between modifier row (y=-80) and weapon row (y=50).
- Removal at (95, 95), well clear of weapons and edge walls (6px wall at
  ±122px).

### Visual layout

```
┌──────────────────────────────────────┐
│  ◆       ◆       ◆       ◆       ◆   │  modifiers y=-80
│                                      │
│                                      │  130px gap
│                                      │
│       ▮              ▮              ▮  │  weapons y=50
│                                      │
│                               ✖      │  removal (95, 95)
└──────────────────────────────────────┘
```

## Files changed

- `src/economy/shop_stall.gd` — update 5 constants (MODIFIER_Y, MODIFIER_XS,
  WEAPON_Y, WEAPON_XS, REMOVAL_OFFSET)
- `tests/unit/test_shop_stall.gd` — update expected position assertions

No scene changes, no structural changes, no new files.