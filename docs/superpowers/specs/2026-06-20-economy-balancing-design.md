# Economy Balancing — Design

**Date:** 2026-06-20
**Scope:** All 6 "Economy Balancing" rows in `docs/design_docs/implementation_todo2.md` (Phase 1).
**Status:** Approved design, ready for implementation plan.

---

## 1. Problem

The current economy feels far too cheap. A single NORMAL kill (20–50g) nearly buys a Common modifier (30g), and the continuous spawner (`mob_cap = 70`, ~1 enemy/sec) means a floor easily nets several hundred gold — enough to buy the entire shop. Income (enemies fought × gold/enemy) vastly outweighs sinks.

Reference anchor (Slay the Spire): a *whole act* of combat (6–8 fights) yields ~80–140g while one shop card costs 45–150g and the first removal is 75g, so a "floor" of income buys ~1–3 shop items — never the whole shelf. Balatro keeps cash tight via interest-banking; Noita lets gold be abundant but gates it behind few shops; Enter the Gungeon raises shop prices per floor. We are missing that income→sink ratio.

## 2. Goals & decisions

- **Tightness:** STS-like — a floor's combat income buys **~2–3 shop items**, forcing real choices.
- **Run length:** ~3 floors. Curves tuned for floors 1–3 but linear/extensible so longer runs stay sane.
- **Levers:** moderate per-enemy income trim + raise shop prices + floor-scaling multipliers + per-biome skew + new chest/boss gold. (We trim income moderately so the *numbers* stay readable — a price-only fix would push a Common modifier to ~300g, incoherent next to mob drops.)
- **Scope:** all 6 economy rows — shop modifier pricing, shop weapon pricing, removal curve, gold drop rates, floor-scaling, biome skew.

### Anchor

The entire economy derives from one tunable anchor:

> **Expected floor-1 combat income ≈ 330g**, and the rule **a floor's income buys ~2–3 shop items.**

Every number below traces back to that ratio. When real playtest data arrives, retune the anchor and the rest follows.

> **Documented assumption (validate in playtest):** a non-grindy floor engages ~40 enemies (≈50% EASY / 40% NORMAL / 10% HARD). The continuous spawner (`mob_cap = 70`) means a *grinding* player can exceed this — see §8 Risks.

## 3. Income side (floor-1 baseline)

Lower `gold_per_drop` (5 → 2/3) and tighten drop counts. Fewer gold pickups means less entity spam and visual clutter while keeping totals readable.

| Tier   | drop count | gold/drop | total range | avg  |
|--------|-----------|-----------|-------------|------|
| EASY   | 1–3       | 2         | 2–6         | ~4   |
| NORMAL | 2–5       | 2         | 4–10        | ~7   |
| HARD   | 3–7       | 3         | 9–21        | ~15  |

- **Elites:** ×2.5 gold (mirrors their ~3× HP multiplier — killing one should feel rewarding).
- **Chest gold (new):** added *alongside* the existing weapon/modifier offer.
  - NORMAL chest: 25–40g
  - HARD / secret chest: 60–100g
- **Boss gold (new):** 50–80g, on top of the guaranteed weapon + Rare modifier drop.

Floor-1 income reconciliation (reference floor, ~40 enemies, 50/40/10 mix):

- EASY: 20 × ~4g = ~80g
- NORMAL: 16 × ~7g = ~112g
- HARD: 4 × ~15g = ~60g
- Combat subtotal ≈ **252g** + 1 chest (~30g) + boss (~50g) ≈ **~330g/floor-1.** ✓

## 4. Sink side (floor-1 baseline prices)

| Item     | Common        | Uncommon      | Rare           |
|----------|---------------|---------------|----------------|
| Modifier | 50 (was 30)   | 90 (was 60)   | 150 (was 100)  |
| Weapon   | 130 (was 120) | 220 (was 200) | 350 (was 320)  |

- **Removal service:** `80 + 40×uses` → 80 / 120 / 160 / 200 (was `60 + 30×uses`).

Affordability check (floor-1, ~330g):
- Buys ~2–3 Common modifiers, *or* a Common + an Uncommon, *or* roughly half a Rare weapon (save across floors). ✓ STS-tight.
- One removal (80) + a Common modifier (50) = 130g, leaving ~200g — reasonable.
- Over a 3-floor run, 2–3 removals (80 + 120 [+160]) ≈ one floor's income — "painful but reachable." ✓
- Weapons barely move; they also drop from enemies/chests/bosses, so shop weapons stay a backup option rather than the main source.

## 5. Floor-scaling

Two multipliers keyed on `LevelManager.floor_number`, with **prices outpacing income** so deeper floors require saving (the todo's "floor-1 affordable; floor-5 requires saving"):

- `income_mult(n) = 1 + 0.12·(n−1)` → 1.00 / 1.12 / 1.24
- `price_mult(n)  = 1 + 0.18·(n−1)` → 1.00 / 1.18 / 1.36

Applied to **all income** (enemy / chest / boss) and **all sinks** (shop prices + removal service). Tuned for the ~3-floor run but linear, so it stays sane if runs grow longer. Single coefficient each — easy to retune.

Floor-3 spot check: Common mod 50×1.36 ≈ 68g, Rare weapon 350×1.36 ≈ 476g; income ~252×1.24 ≈ 312g + chest/boss. Still buys ~2–3 items, but Rares need cross-floor saving. ✓

## 6. Per-biome skew

New `gold_multiplier` export on `BiomeDef` (income only — keeps it simple; prices unaffected by biome).

| Biome  | Gold mult | Note                                              |
|--------|-----------|---------------------------------------------------|
| Caves  | 1.0       | baseline                                          |
| Magma  | 0.9       | but higher spawn rate → more kills, nets ~even    |
| Frozen | 1.0       | —                                                 |
| Mines  | 1.0       | —                                                 |
| Vault  | 1.2       | gold-rich, elite-heavy                            |

## 7. Implementation surface

- **`src/enemies/drop_table.gd`** — retune `_TIER_GOLD_MIN/MAX/PER_DROP` constants; apply `income_mult(floor) × biome_gold_mult` in `_resolve_gold`; add chest, boss, and elite gold paths.
- **`src/economy/shop_pricing.gd`** — keep `WEAPON_PRICE` / `MODIFIER_PRICE` / `REMOVE_BASE` / `REMOVE_STEP` as floor-1 baselines; have `price_for_weapon`, `price_for_modifier_tier`, and the removal cost multiply by `price_mult(floor)`. Add the `income_mult` / `price_mult` helpers (in `ShopPricing` or a small shared economy helper, both reading `LevelManager.floor_number`).
- **`src/economy/shop_stall.gd` / `shop_removal.gd`** — bake the floor-scaled price at spawn / compute removal cost via the floor-aware helper.
- **`src/core/biome_def.gd`** + **`tools/generate_biome_resources.gd`** — add and populate `gold_multiplier` per biome.
- **`src/enemies/boss_enemy.gd`** — add gold to boss drop resolution.
- **Chest spawn path** (`src/core/spawn_dispatcher.gd` + chest resolution) — add the per-tier chest gold.
- **Elite gold** — apply the ×2.5 multiplier where elite enemies resolve their drops.
- **Tests:** update `tests/unit/test_shop_pricing.gd`, `test_drop_table.gd`, `test_shop_removal.gd` for the new constants, floor multipliers, and chest/boss/elite gold.

## 8. Risks / out of scope

- **`mob_cap = 70` + continuous spawn** is the real lever on grindability. The todo references `25`. Lowering it (or adding a per-floor income soft-cap) would tighten the economy far more than pricing alone, but that is an enemy-spawn change, not one of the 6 economy rows. **Flagged, not changed** in this spec.
- All numbers are **pre-playtest estimates** anchored to the ~330g floor-1 income. They are tuning starting points, not final values; the anchor and the two floor coefficients are the knobs to turn once real data exists.

## 9. Out-of-scope (explicitly not in this spec)

- Weapon / modifier / enemy stat balance (separate todo sections).
- Shop rarity *distribution* weights (lives under Modifier Balance, not Economy).
- Any change to spawn cadence or `mob_cap`.
