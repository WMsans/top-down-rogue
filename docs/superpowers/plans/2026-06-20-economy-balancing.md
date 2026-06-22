# Economy Balancing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebalance the run economy so a floor's combat income buys ~2–3 shop items (not the whole shop), via a moderate per-enemy income trim, higher shop prices, floor-depth scaling, per-biome gold skew, and new chest/boss gold.

**Architecture:** Income lives in `DropTable` (per-tier gold constants + a floor multiplier + a biome multiplier folded into a single `effective_gold()` helper). Sinks live in `ShopPricing` (per-rarity baselines × a floor price multiplier, plus a `remove_cost()` helper). Both floor multipliers read `LevelManager.floor_number`, but every public helper takes an explicit `floor_number` argument (default `0` = "ask LevelManager") so unit tests are deterministic. Chest and boss gold reuse the same `DropTable` helpers.

**Tech Stack:** Godot 4 / GDScript, gdUnit4 for tests. Spec: `docs/superpowers/specs/2026-06-20-economy-balancing-design.md`.

**Run a single test suite:**
```bash
godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/<file>.gd
```

---

## File Structure

**Modify:**
- `src/enemies/drop_table.gd` — new gold constants; `income_mult()`, `effective_gold()`, `biome_gold_mult()`; `resolve()`/`_resolve_gold()` gain a `gold_mult` param.
- `src/core/biome_def.gd` — new `gold_multiplier` export.
- `assets/biomes/magma.tres`, `assets/biomes/vault.tres` — set `gold_multiplier`.
- `src/enemies/enemy.gd` — pass elite gold multiplier into `resolve()`.
- `src/economy/shop_pricing.gd` — new baselines; `price_mult()`, floor-aware `price_for_*`, `remove_cost()`.
- `src/economy/shop_removal.gd` — use `ShopPricing.remove_cost()`.
- `src/enemies/boss_enemy.gd` — add boss bonus gold entry.
- `src/drops/chest.gd` — per-tier chest gold on open.

**Tests modify:**
- `tests/unit/test_drop_table.gd`, `tests/unit/test_shop_pricing.gd`, `tests/unit/test_shop_removal.gd`.

**Tests create:**
- `tests/unit/test_biome_economy.gd`, `tests/unit/test_boss_drops.gd`, `tests/unit/test_chest_drops.gd`.

**Do NOT run** `tools/generate_biome_resources.gd` — it is stale (writes `boss_templates`, while the live `.tres` use `boss_compositions`) and would clobber the biome data. Edit the `.tres` directly.

---

## Task 1: Income constants + floor multiplier + `effective_gold` helper

**Files:**
- Modify: `src/enemies/drop_table.gd:42-44` (constants), add helpers near top.
- Test: `tests/unit/test_drop_table.gd`

- [ ] **Step 1: Update the income tests to the new values (failing)**

In `tests/unit/test_drop_table.gd`, replace the bodies of `test_from_enemy_tier_gold_amounts_easy` and `test_from_enemy_tier_gold_amounts_hard`, and append three new tests:

```gdscript
func test_from_enemy_tier_gold_amounts_easy() -> void:
	var table := _DropTable.from_enemy_tier(_DropTable.EnemyTier.EASY, true, false, false)
	assert_that(table.entries.size()).is_equal(1)
	var entry: _DropTable.DropEntry = table.entries[0]
	assert_that(entry.kind).is_equal(_DropTable.DropKind.GOLD)
	assert_that(entry.min_count).is_equal(1)
	assert_that(entry.max_count).is_equal(3)
	assert_that(entry.gold_per_drop).is_equal(2)


func test_from_enemy_tier_gold_amounts_hard() -> void:
	var table := _DropTable.from_enemy_tier(_DropTable.EnemyTier.HARD, true, false, false)
	var entry: _DropTable.DropEntry = table.entries[0]
	assert_that(entry.min_count).is_equal(3)
	assert_that(entry.max_count).is_equal(7)
	assert_that(entry.gold_per_drop).is_equal(3)


func test_income_mult_floor_one_is_baseline() -> void:
	assert_float(_DropTable.income_mult(1)).is_equal_approx(1.0, 0.0001)


func test_income_mult_scales_with_depth() -> void:
	assert_float(_DropTable.income_mult(3)).is_equal_approx(1.24, 0.0001)


func test_effective_gold_applies_floor_and_biome() -> void:
	assert_int(_DropTable.effective_gold(10, 1, 1.0)).is_equal(10)
	assert_int(_DropTable.effective_gold(10, 3, 1.0)).is_equal(12)
	assert_int(_DropTable.effective_gold(10, 1, 1.2)).is_equal(12)
	assert_int(_DropTable.effective_gold(0, 1, 1.0)).is_equal(1)
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/test_drop_table.gd`
Expected: FAIL — old gold amounts (2/5, 8/20) and missing `income_mult` / `effective_gold` methods.

- [ ] **Step 3: Update the gold constants**

In `src/enemies/drop_table.gd`, replace lines 42-44:

```gdscript
const _TIER_GOLD_MIN: Dictionary = {EnemyTier.EASY: 1, EnemyTier.NORMAL: 2, EnemyTier.HARD: 3}
const _TIER_GOLD_MAX: Dictionary = {EnemyTier.EASY: 3, EnemyTier.NORMAL: 5, EnemyTier.HARD: 7}
const _TIER_GOLD_PER_DROP: Dictionary = {EnemyTier.EASY: 2, EnemyTier.NORMAL: 2, EnemyTier.HARD: 3}
```

- [ ] **Step 4: Add the income helpers**

In `src/enemies/drop_table.gd`, immediately after the `var entries: Array[DropEntry] = []` line (currently line 53), add:

```gdscript

const INCOME_FLOOR_COEFF := 0.12


static func income_mult(floor_number: int) -> float:
	var n: int = floor_number if floor_number > 0 else LevelManager.floor_number
	return 1.0 + INCOME_FLOOR_COEFF * float(maxi(n, 1) - 1)


static func effective_gold(base_per_drop: int, floor_number: int, biome_mult: float) -> int:
	return maxi(1, int(round(float(base_per_drop) * income_mult(floor_number) * biome_mult)))
```

- [ ] **Step 5: Run the tests, verify they pass**

Run: `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/test_drop_table.gd`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/enemies/drop_table.gd tests/unit/test_drop_table.gd
git commit -m "balance: trim per-enemy gold + add floor income multiplier"
```

---

## Task 2: Per-biome gold multiplier (`BiomeDef` + `.tres` + `DropTable.biome_gold_mult`)

**Files:**
- Modify: `src/core/biome_def.gd:20` (after `cave_spawn_rate`)
- Modify: `src/enemies/drop_table.gd` (add static helper)
- Modify: `assets/biomes/magma.tres`, `assets/biomes/vault.tres`
- Test: `tests/unit/test_biome_economy.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_biome_economy.gd`:

```gdscript
extends GdUnitTestSuite

const _BiomeDef = preload("res://src/core/biome_def.gd")


func test_biome_def_default_gold_multiplier() -> void:
	var b: BiomeDef = _BiomeDef.new()
	assert_float(b.gold_multiplier).is_equal_approx(1.0, 0.0001)


func test_magma_biome_gold_multiplier() -> void:
	var b: BiomeDef = load("res://assets/biomes/magma.tres")
	assert_float(b.gold_multiplier).is_equal_approx(0.9, 0.0001)


func test_vault_biome_gold_multiplier() -> void:
	var b: BiomeDef = load("res://assets/biomes/vault.tres")
	assert_float(b.gold_multiplier).is_equal_approx(1.2, 0.0001)
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/test_biome_economy.gd`
Expected: FAIL — `gold_multiplier` property does not exist.

- [ ] **Step 3: Add the export to `BiomeDef`**

In `src/core/biome_def.gd`, after line 20 (`@export var cave_spawn_rate: float = 1.0`), add:

```gdscript
@export var gold_multiplier: float = 1.0
```

- [ ] **Step 4: Set the values in the two biome resources**

In `assets/biomes/magma.tres`, inside the `[resource]` block, add a line directly after `display_name = "Magma Caverns"`:

```
gold_multiplier = 0.9
```

In `assets/biomes/vault.tres`, inside the `[resource]` block, add a line directly after `display_name = "Vault"`:

```
gold_multiplier = 1.2
```

(Caves, Mines, Frozen keep the default 1.0 and need no edit.)

- [ ] **Step 5: Add the `biome_gold_mult` helper**

In `src/enemies/drop_table.gd`, after the `effective_gold` function from Task 1, add:

```gdscript


static func biome_gold_mult() -> float:
	if LevelManager.current_biome != null:
		return LevelManager.current_biome.gold_multiplier
	return 1.0
```

- [ ] **Step 6: Run the test, verify it passes**

Run: `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/test_biome_economy.gd`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/core/biome_def.gd src/enemies/drop_table.gd assets/biomes/magma.tres assets/biomes/vault.tres tests/unit/test_biome_economy.gd
git commit -m "balance: add per-biome gold multiplier (magma 0.9, vault 1.2)"
```

---

## Task 3: Wire income scaling into gold resolution + elite multiplier

**Files:**
- Modify: `src/enemies/drop_table.gd:90-113` (`resolve` + `_resolve_gold`)
- Modify: `src/enemies/enemy.gd:359-363` (`_spawn_drops`)
- Test: `tests/unit/test_drop_table.gd`

- [ ] **Step 1: Write the failing integration test**

Append to `tests/unit/test_drop_table.gd`:

```gdscript
func test_resolve_gold_spawns_scaled_pickup() -> void:
	var parent := Node2D.new()
	add_child(parent)
	auto_free(parent)
	var table := _DropTable.new()
	table.add_entry(_DropTable.DropEntry.gold(1.0, 1, 1, 10))
	table.resolve(Vector2.ZERO, parent, 2.0)
	var golds := parent.get_children().filter(func(n): return n is GoldDrop)
	assert_int(golds.size()).is_equal(1)
	assert_int((golds[0] as GoldDrop).amount).is_equal(20)
```

(At test time `LevelManager.floor_number == 1` and the current biome is Caves with `gold_multiplier == 1.0`, so the expected amount is `10 × 1.0 × 1.0 × 2.0 = 20`.)

- [ ] **Step 2: Run the test, verify it fails**

Run: `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/test_drop_table.gd`
Expected: FAIL — `resolve()` takes no third argument / amount is unscaled (10, not 20).

- [ ] **Step 3: Add the `gold_mult` parameter to `resolve` and `_resolve_gold`**

In `src/enemies/drop_table.gd`, replace the `resolve` function (currently lines 90-103):

```gdscript
func resolve(position: Vector2, parent: Node, gold_mult: float = 1.0) -> void:
	for entry in entries:
		var roll := randf()
		if roll > entry.weight:
			continue
		var count := randi_range(entry.min_count, entry.max_count)
		for i in count:
			match entry.kind:
				DropKind.GOLD:
					_resolve_gold(position, parent, entry, gold_mult)
				DropKind.MODIFIER_POOL:
					_resolve_modifier_pool(position, parent, entry)
				DropKind.SCENE:
					_resolve_scene(position, parent, entry)
```

Then replace `_resolve_gold` (currently lines 106-112):

```gdscript
func _resolve_gold(position: Vector2, parent: Node, entry: DropEntry, gold_mult: float = 1.0) -> void:
	var drop: Node = GOLD_DROP_SCENE.instantiate()
	if drop.has_method("set_amount") and entry.gold_per_drop > 0:
		drop.set_amount(effective_gold(entry.gold_per_drop, 0, biome_gold_mult() * gold_mult))
	var offset := Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
	parent.add_child(drop)
	drop.global_position = position + offset
```

- [ ] **Step 4: Pass the elite multiplier from enemies**

In `src/enemies/enemy.gd`, replace `_spawn_drops` (currently lines 359-363):

```gdscript
func _spawn_drops() -> void:
	if drop_table:
		drop_table.resolve(global_position, get_parent(), 2.5 if is_elite else 1.0)
	if weapon and DropTable.roll_should_drop_weapon(enemy_tier):
		_spawn_weapon_drop()
```

- [ ] **Step 5: Run the tests, verify they pass**

Run: `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/test_drop_table.gd`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/enemies/drop_table.gd src/enemies/enemy.gd tests/unit/test_drop_table.gd
git commit -m "balance: apply floor/biome/elite scaling to dropped gold"
```

---

## Task 4: Shop pricing baselines + floor price multiplier + removal cost helper

**Files:**
- Modify: `src/economy/shop_pricing.gd:5-24` (constants + functions)
- Test: `tests/unit/test_shop_pricing.gd`

- [ ] **Step 1: Update / add the pricing tests (failing)**

In `tests/unit/test_shop_pricing.gd`, replace `test_weapon_price_by_rarity` and `test_modifier_price_by_tier`, and append two new tests:

```gdscript
func test_weapon_price_by_rarity() -> void:
	var w := Weapon.new()
	w.rarity = DropTable.ItemTier.COMMON
	assert_that(ShopPricing.price_for_weapon(w, 1)).is_equal(130)
	w.rarity = DropTable.ItemTier.UNCOMMON
	assert_that(ShopPricing.price_for_weapon(w, 1)).is_equal(220)
	w.rarity = DropTable.ItemTier.RARE
	assert_that(ShopPricing.price_for_weapon(w, 1)).is_equal(350)


func test_modifier_price_by_tier() -> void:
	assert_that(ShopPricing.price_for_modifier_tier(DropTable.ItemTier.COMMON, 1)).is_equal(50)
	assert_that(ShopPricing.price_for_modifier_tier(DropTable.ItemTier.UNCOMMON, 1)).is_equal(90)
	assert_that(ShopPricing.price_for_modifier_tier(DropTable.ItemTier.RARE, 1)).is_equal(150)


func test_price_scales_with_floor() -> void:
	# price_mult(3) = 1 + 0.18*2 = 1.36
	assert_that(ShopPricing.price_for_modifier_tier(DropTable.ItemTier.COMMON, 3)).is_equal(68)
	assert_that(ShopPricing.price_for_weapon_tier_test(3)).is_equal(177)


func test_remove_cost_escalates_and_scales() -> void:
	assert_that(ShopPricing.remove_cost(0, 1)).is_equal(80)
	assert_that(ShopPricing.remove_cost(1, 1)).is_equal(120)
	assert_that(ShopPricing.remove_cost(2, 1)).is_equal(160)
	assert_that(ShopPricing.remove_cost(0, 3)).is_equal(109)
```

Replace the `test_price_scales_with_floor` weapon assertion helper call by using a real weapon instead (no extra helper needed). Use this version of that test:

```gdscript
func test_price_scales_with_floor() -> void:
	# price_mult(3) = 1 + 0.18*2 = 1.36
	assert_that(ShopPricing.price_for_modifier_tier(DropTable.ItemTier.COMMON, 3)).is_equal(68)
	var w := Weapon.new()
	w.rarity = DropTable.ItemTier.COMMON
	assert_that(ShopPricing.price_for_weapon(w, 3)).is_equal(177)
```

(130 × 1.36 = 176.8 → round → 177; 50 × 1.36 = 68; 80 × 1.36 = 108.8 → 109.)

- [ ] **Step 2: Run the test, verify it fails**

Run: `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/test_shop_pricing.gd`
Expected: FAIL — old baselines (120/30) and no `floor_number` arg / no `remove_cost`.

- [ ] **Step 3: Update the constants and functions**

In `src/economy/shop_pricing.gd`, replace lines 5-24 (the two price dicts, `REMOVE_BASE`/`REMOVE_STEP`, and the two `price_for_*` functions):

```gdscript
# Prices keyed by DropTable.ItemTier. Floor-1 baselines; scaled by price_mult().
const WEAPON_PRICE := {
	DropTable.ItemTier.COMMON: 130,
	DropTable.ItemTier.UNCOMMON: 220,
	DropTable.ItemTier.RARE: 350,
}
const MODIFIER_PRICE := {
	DropTable.ItemTier.COMMON: 50,
	DropTable.ItemTier.UNCOMMON: 90,
	DropTable.ItemTier.RARE: 150,
}
const REMOVE_BASE := 80
const REMOVE_STEP := 40
const PRICE_FLOOR_COEFF := 0.18


# Floor-depth price multiplier. floor_number <= 0 means "use LevelManager".
static func price_mult(floor_number: int) -> float:
	var n: int = floor_number if floor_number > 0 else LevelManager.floor_number
	return 1.0 + PRICE_FLOOR_COEFF * float(maxi(n, 1) - 1)


static func price_for_weapon(weapon: Weapon, floor_number: int = 0) -> int:
	var base: int = WEAPON_PRICE.get(weapon.rarity, WEAPON_PRICE[DropTable.ItemTier.COMMON])
	return int(round(float(base) * price_mult(floor_number)))


static func price_for_modifier_tier(tier: int, floor_number: int = 0) -> int:
	var base: int = MODIFIER_PRICE.get(tier, MODIFIER_PRICE[DropTable.ItemTier.COMMON])
	return int(round(float(base) * price_mult(floor_number)))


static func remove_cost(uses: int, floor_number: int = 0) -> int:
	return int(round(float(REMOVE_BASE + uses * REMOVE_STEP) * price_mult(floor_number)))
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/test_shop_pricing.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/economy/shop_pricing.gd tests/unit/test_shop_pricing.gd
git commit -m "balance: raise shop prices + add floor price multiplier and remove_cost"
```

---

## Task 5: Wire removal service to floor-scaled cost

**Files:**
- Modify: `src/economy/shop_removal.gd:32-33` (`_current_cost`)
- Test: `tests/unit/test_shop_removal.gd`

Note: `shop_stall.gd` already calls `ShopPricing.price_for_modifier_tier(tier)` and `price_for_weapon(weapon)` with the default `floor_number = 0`, so shop items pick up floor scaling automatically — no change needed there.

- [ ] **Step 1: Update the removal tests (failing)**

In `tests/unit/test_shop_removal.gd`, replace `test_removal_charges_base_and_escalates`:

```gdscript
func test_removal_charges_base_and_escalates() -> void:
	var player := _make_player(500, true, true)
	var removal := _make_removal()
	removal.interact(player)
	assert_int(player.get_node("PlayerInventory").gold).is_equal(420)
	removal.interact(player)
	assert_int(player.get_node("PlayerInventory").gold).is_equal(300)
```

(At floor 1: first removal 80 → 500−80=420; second removal 120 → 420−120=300. The too-poor test already uses gold 10 < 80, so it still no-ops.)

- [ ] **Step 2: Run the test, verify it fails**

Run: `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/test_shop_removal.gd`
Expected: FAIL — old cost 60/90 gives 440/350, not 420/300.

- [ ] **Step 3: Use the new helper in `_current_cost`**

In `src/economy/shop_removal.gd`, replace `_current_cost` (lines 32-33):

```gdscript
func _current_cost() -> int:
	return ShopPricing.remove_cost(_uses)
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/test_shop_removal.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/economy/shop_removal.gd tests/unit/test_shop_removal.gd
git commit -m "balance: removal cost uses floor-scaled remove_cost helper"
```

---

## Task 6: Boss bonus gold

**Files:**
- Modify: `src/enemies/boss_enemy.gd:41-43` (`_setup_drop_table`)
- Test: `tests/unit/test_boss_drops.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_boss_drops.gd`:

```gdscript
extends GdUnitTestSuite


func test_boss_drop_table_includes_bonus_gold() -> void:
	var boss := BossEnemy.new()
	auto_free(boss)
	boss._setup_drop_table()
	var bonus := boss.drop_table.entries.filter(func(e):
		return e.kind == DropTable.DropKind.GOLD and e.gold_per_drop == 10)
	assert_int(bonus.size()).is_equal(1)
	assert_int(bonus[0].min_count).is_equal(5)
	assert_int(bonus[0].max_count).is_equal(8)
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/test_boss_drops.gd`
Expected: FAIL — no bonus gold entry with `gold_per_drop == 10`.

- [ ] **Step 3: Add the bonus gold entry**

In `src/enemies/boss_enemy.gd`, replace `_setup_drop_table` (lines 41-43):

```gdscript
func _setup_drop_table() -> void:
	drop_table = DropTable.from_enemy_tier(enemy_tier, true, true, true)
	drop_table.add_entry(DropTable.DropEntry.modifier_pool(1.0, DropTable.ItemTier.RARE, 1, 1))
	drop_table.add_entry(DropTable.DropEntry.gold(1.0, 5, 8, 10))  # 50-80g boss bonus (pre-scaling)
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/test_boss_drops.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/enemies/boss_enemy.gd tests/unit/test_boss_drops.gd
git commit -m "balance: add boss bonus gold drop (50-80g pre-scaling)"
```

---

## Task 7: Chest gold

**Files:**
- Modify: `src/drops/chest.gd` (constant, `gold_range`, `_spawn_gold`, `interact`)
- Test: `tests/unit/test_chest_drops.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_chest_drops.gd`:

```gdscript
extends GdUnitTestSuite


func test_chest_gold_range_by_tier() -> void:
	assert_that(Chest.gold_range(DropTable.EnemyTier.NORMAL)).is_equal(Vector2i(25, 40))
	assert_that(Chest.gold_range(DropTable.EnemyTier.HARD)).is_equal(Vector2i(60, 100))


func test_chest_gold_range_defaults_to_normal() -> void:
	assert_that(Chest.gold_range(_DropTable.EnemyTier.EASY)).is_equal(Vector2i(25, 40))


const _DropTable = preload("res://src/enemies/drop_table.gd")
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/test_chest_drops.gd`
Expected: FAIL — `gold_range` method does not exist.

- [ ] **Step 3: Add the gold constant, scene preload, and `gold_range`**

In `src/drops/chest.gd`, after line 6 (`const CHOICE_COUNT := 3`), add:

```gdscript
const GOLD_DROP_SCENE := preload("res://scenes/gold_drop.tscn")
const _CHEST_GOLD: Dictionary = {
	DropTable.EnemyTier.NORMAL: Vector2i(25, 40),
	DropTable.EnemyTier.HARD: Vector2i(60, 100),
}


static func gold_range(chest_tier: int) -> Vector2i:
	return _CHEST_GOLD.get(chest_tier, Vector2i(25, 40))
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/test_chest_drops.gd`
Expected: PASS.

- [ ] **Step 5: Spawn the gold when the chest opens**

In `src/drops/chest.gd`, add a `_spawn_gold` method (place it after `_generate_weapons`):

```gdscript
func _spawn_gold() -> void:
	var rng := gold_range(tier)
	var base := randi_range(rng.x, rng.y)
	var amount := DropTable.effective_gold(base, 0, DropTable.biome_gold_mult())
	var drop: Node = GOLD_DROP_SCENE.instantiate()
	if drop.has_method("set_amount"):
		drop.set_amount(amount)
	get_parent().add_child(drop)
	drop.global_position = global_position + Vector2(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))
```

Then call it inside `interact`, after `set_collision_layer_value(2, false)` and before `_generate_weapons()`:

```gdscript
func interact(_player: Node) -> void:
	if _opened or _looted:
		return
	_opened = true
	_sprite.texture = CHEST_OPEN_TEXTURE
	set_collision_layer_value(1, false)
	set_collision_layer_value(2, false)
	_spawn_gold()
	_generate_weapons()
	_open_chest_ui()
```

- [ ] **Step 6: Run the full unit suite, verify nothing regressed**

Run: `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit`
Expected: PASS (all suites).

- [ ] **Step 7: Commit**

```bash
git add src/drops/chest.gd tests/unit/test_chest_drops.gd
git commit -m "balance: chests drop floor/biome-scaled gold on open"
```

---

## Final verification

- [ ] **Run the full unit-test directory**

Run: `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit`
Expected: all suites PASS.

- [ ] **Smoke-check in the running game (optional but recommended)**

Launch the game, kill a few floor-1 enemies, confirm gold drops are single-digit-to-low-tens; open the shop and confirm Common modifier ≈ 50g, Common weapon ≈ 130g; use the removal service and confirm 80 → 120 escalation; advance a floor and confirm prices/drops scale up.

---

## Self-Review (completed during authoring)

**Spec coverage:**
- §3 income trim → Task 1 (constants) + Task 3 (resolution). ✓
- §3 elite ×2.5 → Task 3. ✓
- §3 chest gold → Task 7. ✓
- §3 boss gold → Task 6. ✓
- §4 shop modifier/weapon prices → Task 4. ✓
- §4 removal curve → Task 4 (`remove_cost`) + Task 5 (wiring). ✓
- §5 floor income multiplier → Task 1; floor price multiplier → Task 4. ✓
- §6 per-biome skew → Task 2. ✓
- §7 implementation surface → all files covered; `shop_stall` confirmed no-op (default arg). ✓
- §8 `mob_cap` left untouched (flagged, out of scope). ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases"; every code step shows full code. ✓

**Type/name consistency:** `income_mult`, `effective_gold`, `biome_gold_mult` (DropTable); `price_mult`, `price_for_weapon`, `price_for_modifier_tier`, `remove_cost` (ShopPricing); `gold_multiplier` (BiomeDef); `gold_range`, `_spawn_gold` (Chest) — all referenced consistently across tasks. `effective_gold(base, floor_number, biome_mult)` signature identical in Tasks 1, 3, 7. ✓
