# Per-weapon Rarity + Full-pool Chests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let each weapon declare its own rarity, and make chests draw from the full weapon pool with per-slot tier-weighted rolls that reuse the existing enemy-drop weight table.

**Architecture:** Add a `rarity` field to the `Weapon` base class so each subclass owns its tier. Refactor `WeaponRegistry` from hard-coded per-tier buckets to a single flat registration list that builds tier buckets at startup by probing each weapon's `rarity`. Change `Chest.tier` from `ItemTier` (weapon-rarity) to `EnemyTier` (difficulty) and roll a tier for each of the three chest slots via the existing `DropTable.resolve_item_tier(enemy_tier)`. Update the two chest spawn callers (`feature_chest_spawn.gd`, `spawn_dispatcher.gd`) to set `chest.tier` to an `EnemyTier` value.

**Tech Stack:** Godot 4, GDScript, GdUnit4 for tests.

**Spec:** `docs/superpowers/specs/2026-05-22-per-weapon-rarity-design.md`

---

## File Structure

**Modify:**

- `src/weapons/weapon.gd` — add `@export var rarity: int = DropTable.ItemTier.COMMON` to the base class.
- `src/weapons/melee_weapon.gd` — set `rarity = DropTable.ItemTier.COMMON` in `_init()`.
- `src/weapons/test_weapon.gd` — set `rarity = DropTable.ItemTier.COMMON` in `_init()`.
- `src/weapons/ranged_weapon.gd` — set `rarity = DropTable.ItemTier.UNCOMMON` in `_init()`.
- `src/autoload/weapon_registry.gd` — replace `_populate_tiers()` with a flat `_all_weapons` list + `_build_tier_buckets()` that probes each script's `rarity`.
- `src/drops/chest.gd` — change `tier` default to `DropTable.EnemyTier.NORMAL`; rewrite `_generate_weapons()` to roll a tier per slot via `DropTable.resolve_item_tier(tier)`.
- `src/core/features/feature_chest_spawn.gd` — translate the `rare` flag into an `EnemyTier` value set on the spawned chest.
- `src/core/spawn_dispatcher.gd` — translate `is_secret_loot` into an `EnemyTier` value set on the spawned chest (replaces the existing `rare_drop` write, which targets a field that doesn't exist on `Chest`).

**Test:**

- `tests/unit/test_weapon_registry_pools.gd` — keep existing tests passing; add assertions for the new per-weapon-rarity bucketing.
- `tests/unit/test_chest_weapon_pool.gd` — new test file; verify `Chest._generate_weapons()` can reach every weapon across many rolls.

`DropTable.resolve_item_tier(enemy_tier)` already exists (`src/enemies/drop_table.gd:79`) and does exactly the weighted-tier roll the spec calls for, so no new helper is needed.

---

## Task 1: Add `rarity` field to `Weapon` base class

**Files:**

- Modify: `src/weapons/weapon.gd:1-13`

- [ ] **Step 1: Add the rarity field**

Open `src/weapons/weapon.gd`. After the existing `@export var name: String = "Weapon"` line (line 4), add a new exported field. The full top of the file should look like:

```gdscript
class_name Weapon
extends Resource

@export var name: String = "Weapon"
@export var rarity: int = DropTable.ItemTier.COMMON
var cooldown: float = 0.8
var damage: float = 0.0
var icon_texture: Texture2D = null
var visual: Node2D = null
var _sprite: Sprite2D = null
var modifier_slot_count: int = 3
var modifiers: Array = []
var _cooldown_timer: float = 0.0
```

`DropTable` is an autoloaded class (`class_name DropTable`), so it's available here without a `preload`.

- [ ] **Step 2: Verify the project still loads**

Run the project to make sure nothing breaks parsing:

```bash
godot --headless --quit --path .
```

Expected: clean exit (exit code 0), no parser errors mentioning `weapon.gd`.

- [ ] **Step 3: Commit**

```bash
git add src/weapons/weapon.gd
git commit -m "feat(weapons): add rarity field to Weapon base class"
```

---

## Task 2: Set per-subclass rarity defaults

**Files:**

- Modify: `src/weapons/melee_weapon.gd:76-82` (`_init`)
- Modify: `src/weapons/test_weapon.gd` (`_init`)
- Modify: `src/weapons/ranged_weapon.gd:17-22` (`_init`)

- [ ] **Step 1: Set MeleeWeapon rarity**

In `src/weapons/melee_weapon.gd`, update `_init()` to include the rarity assignment. Replace:

```gdscript
func _init() -> void:
	cooldown = 0.35
	damage = 5.0
	icon_texture = weapon_texture
	modifier_slot_count = 3
	modifiers.resize(modifier_slot_count)
```

with:

```gdscript
func _init() -> void:
	cooldown = 0.35
	damage = 5.0
	icon_texture = weapon_texture
	modifier_slot_count = 3
	modifiers.resize(modifier_slot_count)
	rarity = DropTable.ItemTier.COMMON
```

- [ ] **Step 2: Set RangedWeapon rarity**

In `src/weapons/ranged_weapon.gd`, update `_init()` to:

```gdscript
func _init() -> void:
	cooldown = 1.0
	damage = 3.0
	modifier_slot_count = 3
	modifiers.resize(modifier_slot_count)
	rarity = DropTable.ItemTier.UNCOMMON
```

- [ ] **Step 3: Set TestWeapon rarity**

Open `src/weapons/test_weapon.gd` and find its `_init()` function (it exists — `TestWeapon` extends `Weapon`). Add `rarity = DropTable.ItemTier.COMMON` at the end of `_init()`. If `_init()` does not exist on `TestWeapon`, add this new function near the top of the file (after the `var` declarations):

```gdscript
func _init() -> void:
	rarity = DropTable.ItemTier.COMMON
```

- [ ] **Step 4: Verify the project still loads**

```bash
godot --headless --quit --path .
```

Expected: clean exit, no parser errors.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/melee_weapon.gd src/weapons/ranged_weapon.gd src/weapons/test_weapon.gd
git commit -m "feat(weapons): set rarity defaults per weapon subclass"
```

---

## Task 3: Refactor `WeaponRegistry` to build tier buckets from `rarity`

**Files:**

- Modify: `src/autoload/weapon_registry.gd` (whole file, but only `_ready` and `_populate_tiers` change shape)
- Test: `tests/unit/test_weapon_registry_pools.gd`

- [ ] **Step 1: Add a failing test for per-weapon bucketing**

Append to `tests/unit/test_weapon_registry_pools.gd`:

```gdscript
func test_ranged_weapon_lives_in_uncommon_bucket() -> void:
	var entries: Array = WeaponRegistry.weapon_tiers.get(DropTable.ItemTier.UNCOMMON, [])
	var found := false
	for entry in entries:
		var probe: Weapon = entry.weapon_script.new()
		if probe is RangedWeapon:
			found = true
			break
	assert_that(found).is_true()


func test_melee_weapon_lives_in_common_bucket() -> void:
	var entries: Array = WeaponRegistry.weapon_tiers.get(DropTable.ItemTier.COMMON, [])
	var found := false
	for entry in entries:
		var probe: Weapon = entry.weapon_script.new()
		if probe is MeleeWeapon:
			found = true
			break
	assert_that(found).is_true()
```

- [ ] **Step 2: Run the test and verify failure**

Run the existing test suite to see the new tests fail (the current registry hard-codes `ranged_weapon` under UNCOMMON only because `_populate_tiers` does so, but the test exercise should still pass today — verify both pass before refactoring):

```bash
./addons/gdUnit4/runtest.sh -a tests/unit/test_weapon_registry_pools.gd
```

Expected: tests pass under the old registry too (the assertions describe the desired end state, which happens to overlap with current behavior). This is the safety net for the refactor — if the refactor breaks bucketing, these will fail.

- [ ] **Step 3: Replace `_populate_tiers` with flat list + bucket builder**

In `src/autoload/weapon_registry.gd`, replace the existing `_ready()` and `_populate_tiers()` (lines 27-49) with:

```gdscript
var _all_weapons: Array = [
	{ "script": preload("res://src/weapons/melee_weapon.gd"),  "weight": 1.0 },
	{ "script": preload("res://src/weapons/test_weapon.gd"),   "weight": 0.5 },
	{ "script": preload("res://src/weapons/ranged_weapon.gd"), "weight": 1.0 },
]


func _ready() -> void:
	weapon_scripts["melee"] = preload("res://src/weapons/melee_weapon.gd")
	weapon_scripts["test"] = preload("res://src/weapons/test_weapon.gd")
	weapon_scripts["ranged"] = preload("res://src/weapons/ranged_weapon.gd")
	modifier_scripts["lava_emitter"] = preload("res://src/weapons/lava_emitter_modifier.gd")

	_build_tier_buckets()
	_populate_modifier_tiers()


func _build_tier_buckets() -> void:
	weapon_tiers.clear()
	for entry in _all_weapons:
		var script: GDScript = entry.script
		var probe: Weapon = script.new()
		var tier: int = probe.rarity
		if not weapon_tiers.has(tier):
			weapon_tiers[tier] = []
		weapon_tiers[tier].append(WeaponDropEntry.new(script, entry.weight))


func _populate_modifier_tiers() -> void:
	modifier_tiers[DropTable.ItemTier.COMMON] = [
		ModifierDropEntry.new(preload("res://src/weapons/lava_emitter_modifier.gd"), 1.0),
	]
	modifier_tiers[DropTable.ItemTier.UNCOMMON] = []
	modifier_tiers[DropTable.ItemTier.RARE] = []
```

Leave `get_random_weapon` and `get_random_modifier` untouched — their signatures and fallback-to-COMMON behavior stay the same.

Note the `weapon_scripts["ranged"]` entry — it's a new line because the old registry never exposed ranged via the script-lookup map. Adding it keeps the script map consistent with the now-fully-listed `_all_weapons`.

- [ ] **Step 4: Run the registry tests and verify they pass**

```bash
./addons/gdUnit4/runtest.sh -a tests/unit/test_weapon_registry_pools.gd
```

Expected: all tests pass, including the two new bucketing tests.

- [ ] **Step 5: Commit**

```bash
git add src/autoload/weapon_registry.gd tests/unit/test_weapon_registry_pools.gd
git commit -m "refactor(registry): build weapon tier buckets from per-weapon rarity"
```

---

## Task 4: Switch `Chest.tier` to `EnemyTier` and roll per slot

**Files:**

- Modify: `src/drops/chest.gd:8` and `src/drops/chest.gd:54-73` (`_generate_weapons`)
- Test: `tests/unit/test_chest_weapon_pool.gd` (new)

- [ ] **Step 1: Write a failing test for full-pool reachability**

Create `tests/unit/test_chest_weapon_pool.gd` with this content:

```gdscript
extends GdUnitTestSuite

const ChestScript = preload("res://src/drops/chest.gd")


func test_chest_can_roll_all_weapon_classes() -> void:
	# Force RNG variety by sampling many times. Across enough draws, a HARD chest
	# (which weights more toward UNCOMMON/RARE) must produce at least one melee
	# and one ranged weapon — proving the chest is no longer confined to COMMON.
	var saw_melee := false
	var saw_ranged := false
	for _i in range(500):
		var chest: Chest = ChestScript.new()
		chest.tier = DropTable.EnemyTier.HARD
		chest._generate_weapons()
		for weapon in chest._weapons:
			if weapon is MeleeWeapon:
				saw_melee = true
			elif weapon is RangedWeapon:
				saw_ranged = true
		if saw_melee and saw_ranged:
			break
	assert_that(saw_melee).is_true()
	assert_that(saw_ranged).is_true()


func test_chest_default_tier_is_enemy_tier_normal() -> void:
	var chest: Chest = ChestScript.new()
	assert_that(chest.tier).is_equal(DropTable.EnemyTier.NORMAL)
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
./addons/gdUnit4/runtest.sh -a tests/unit/test_chest_weapon_pool.gd
```

Expected: `test_chest_default_tier_is_enemy_tier_normal` FAILS (default is currently `ItemTier.COMMON` which is `0`, and `EnemyTier.NORMAL` is `1`). `test_chest_can_roll_all_weapon_classes` may also fail because today's chest is locked to the COMMON bucket.

- [ ] **Step 3: Change the default tier**

In `src/drops/chest.gd`, change line 8 from:

```gdscript
@export var tier: int = DropTable.ItemTier.COMMON
```

to:

```gdscript
@export var tier: int = DropTable.EnemyTier.NORMAL
```

- [ ] **Step 4: Rewrite `_generate_weapons` to roll a tier per slot**

In `src/drops/chest.gd`, replace `_generate_weapons` (lines 54-73) with:

```gdscript
func _generate_weapons() -> void:
	_weapons.clear()
	var seen_scripts: Dictionary = {}
	for i in CHOICE_COUNT:
		var weapon: Weapon = null
		for _attempt in range(5):
			var rolled_tier: int = DropTable.resolve_item_tier(tier)
			var candidate: Weapon = WeaponRegistry.get_random_weapon(rolled_tier)
			if candidate == null:
				continue
			var script_key = candidate.get_script()
			if script_key == null:
				script_key = candidate
			if not seen_scripts.has(script_key):
				seen_scripts[script_key] = true
				weapon = candidate
				break
		if weapon == null:
			var fallback_tier: int = DropTable.resolve_item_tier(tier)
			weapon = WeaponRegistry.get_random_weapon(fallback_tier)
		if weapon != null:
			_weapons.append(weapon)
```

The only changes vs. the original: each `get_random_weapon(tier)` call is replaced with a fresh `DropTable.resolve_item_tier(tier)` → `get_random_weapon(rolled_tier)` pair. The dedup-by-script logic and 5-attempt retry are unchanged. `tier` is now an `EnemyTier` (input to `resolve_item_tier`), not an `ItemTier`.

- [ ] **Step 5: Run the chest test and verify it passes**

```bash
./addons/gdUnit4/runtest.sh -a tests/unit/test_chest_weapon_pool.gd
```

Expected: both tests pass.

- [ ] **Step 6: Run the full unit suite to catch regressions**

```bash
./addons/gdUnit4/runtest.sh -a tests/unit
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add src/drops/chest.gd tests/unit/test_chest_weapon_pool.gd
git commit -m "feat(chest): roll per-slot item tier from EnemyTier, full weapon pool"
```

---

## Task 5: Update chest spawn callers to set `EnemyTier`

**Files:**

- Modify: `src/core/features/feature_chest_spawn.gd`
- Modify: `src/core/spawn_dispatcher.gd:184-189`

- [ ] **Step 1: Update FeatureChestSpawn**

Replace the entire contents of `src/core/features/feature_chest_spawn.gd` with:

```gdscript
class_name FeatureChestSpawn
extends ArenaFeature

@export var rare: bool = false


func apply(ctx) -> void:
	ctx.dispatcher.spawn_chest(ctx.anchor_world_pos, rare)
```

(No structural change to this file — it already delegates to `dispatcher.spawn_chest`. The behavior change lives in the dispatcher in the next step.)

- [ ] **Step 2: Update SpawnDispatcher._spawn_chest**

In `src/core/spawn_dispatcher.gd`, replace `_spawn_chest` (lines 184-189) with:

```gdscript
func _spawn_chest(world_pos: Vector2, is_secret_loot: bool) -> void:
	var chest := CHEST_SCENE.instantiate()
	chest.global_position = world_pos
	chest.tier = DropTable.EnemyTier.HARD if is_secret_loot else DropTable.EnemyTier.NORMAL
	_spawn_parent.add_child(chest)
```

This replaces the previous `chest.rare_drop = true` write (which targeted a property that doesn't exist on `Chest`) with an explicit `EnemyTier` assignment. `HARD` for secret/rare chests biases per-slot rolls toward UNCOMMON/RARE; `NORMAL` is the default difficulty.

- [ ] **Step 3: Verify the project still loads**

```bash
godot --headless --quit --path .
```

Expected: clean exit, no parser errors.

- [ ] **Step 4: Verify in-game (manual)**

Run the game and, via the in-game console, spawn a chest (`spawn chest`) several times. Open each and confirm:
- The three offered weapons include weapons besides melee/test (you should see ranged appear over multiple rolls).
- Opening still delivers a chosen weapon to the player.

- [ ] **Step 5: Run the full unit suite again**

```bash
./addons/gdUnit4/runtest.sh -a tests/unit
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/core/features/feature_chest_spawn.gd src/core/spawn_dispatcher.gd
git commit -m "feat(chest): map spawn callers' rare flag to EnemyTier"
```

---

## Self-Review Notes

- **Spec coverage:** rarity-on-weapon (Tasks 1-2), registry refactor (Task 3), chest per-slot tier roll (Task 4), caller updates (Task 5). The spec's "expose `_TIER_ITEM_WEIGHTS` via helper" item is satisfied by the existing `DropTable.resolve_item_tier(enemy_tier)` at `src/enemies/drop_table.gd:79`, so no new helper task is needed.
- **Placeholder scan:** no TBDs; all code blocks are concrete.
- **Type consistency:** `tier` on `Chest` is consistently treated as an `EnemyTier` everywhere it appears after Task 4. `rarity` on `Weapon` is consistently an `ItemTier`.
- **Pre-existing inconsistency surfaced:** `spawn_dispatcher.gd` previously wrote `chest.rare_drop = true`, but `Chest` has no such property — that write was a silent no-op. Task 5 replaces it with a real `tier` assignment.
