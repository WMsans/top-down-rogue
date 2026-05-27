# Enemy Drop Tables Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement tier-based enemy drop tables where enemies drop gold, weapons, and modifiers from rarity pools based on enemy difficulty tier.

**Architecture:** Extend the existing `DropTable` system with `DropKind` enums (GOLD, WEAPON_POOL, MODIFIER_POOL, SCENE) and `ItemTier`/`EnemyTier` enums. `WeaponRegistry` gains tier-organized pools with weighted random selection. Enemies configure drops via `_setup_drop_table()` using either manual entries or `DropTable.from_enemy_tier()`. `DropTable.resolve()` handles all kinds, creating appropriate drop scenes.

**Tech Stack:** GDScript 4, Godot 4.x, gdUnit4 for testing

---

### Task 1: Refactor DropEntry to support multiple drop kinds

**Files:**
- Modify: `src/enemies/drop_table.gd`

- [ ] **Step 1: Rewrite drop_table.gd with new enums, DropEntry kinds, and static constructors**

Replace the entire contents of `src/enemies/drop_table.gd` with:

```gdscript
class_name DropTable
extends Resource

enum DropKind { GOLD, WEAPON_POOL, MODIFIER_POOL, SCENE }
enum ItemTier { COMMON, UNCOMMON, RARE }
enum EnemyTier { EASY, NORMAL, HARD }

class DropEntry:
	var kind: int = DropKind.SCENE
	var weight: float = 1.0
	var min_count: int = 1
	var max_count: int = 1
	var gold_per_drop: int = 0
	var item_tier: int = ItemTier.COMMON
	var scene: PackedScene = null

	func _init(p_kind: int = DropKind.SCENE, p_weight: float = 1.0, p_min: int = 1, p_max: int = 1, p_gold: int = 0, p_item_tier: int = ItemTier.COMMON, p_scene: PackedScene = null) -> void:
		kind = p_kind
		weight = p_weight
		min_count = p_min
		max_count = p_max
		gold_per_drop = p_gold
		item_tier = p_item_tier
		scene = p_scene

	static func gold(p_weight: float, p_min: int, p_max: int, p_gold_per_drop: int) -> DropEntry:
		return DropEntry.new(DropKind.GOLD, p_weight, p_min, p_max, p_gold_per_drop)

	static func weapon_pool(p_weight: float, p_tier: int, p_min: int = 1, p_max: int = 1) -> DropEntry:
		return DropEntry.new(DropKind.WEAPON_POOL, p_weight, p_min, p_max, 0, p_tier)

	static func modifier_pool(p_weight: float, p_tier: int, p_min: int = 1, p_max: int = 1) -> DropEntry:
		return DropEntry.new(DropKind.MODIFIER_POOL, p_weight, p_min, p_max, 0, p_tier)

	static func scene(p_scene: PackedScene, p_weight: float = 1.0, p_min: int = 1, p_max: int = 1) -> DropEntry:
		return DropEntry.new(DropKind.SCENE, p_weight, p_min, p_max, 0, ItemTier.COMMON, p_scene)

const GOLD_DROP_SCENE := preload("res://scenes/gold_drop.tscn")
const WEAPON_DROP_SCENE := preload("res://scenes/weapon_drop.tscn")
const MODIFIER_DROP_SCENE := preload("res://scenes/modifier_drop.tscn")

const _TIER_GOLD_MIN: Dictionary = {EnemyTier.EASY: 2, EnemyTier.NORMAL: 4, EnemyTier.HARD: 8}
const _TIER_GOLD_MAX: Dictionary = {EnemyTier.EASY: 5, EnemyTier.NORMAL: 10, EnemyTier.HARD: 20}
const _TIER_GOLD_PER_DROP: Dictionary = {EnemyTier.EASY: 5, EnemyTier.NORMAL: 5, EnemyTier.HARD: 5}
const _TIER_WEAPON_WEIGHT: Dictionary = {EnemyTier.EASY: 0.3, EnemyTier.NORMAL: 0.3, EnemyTier.HARD: 0.3}
const _TIER_MODIFIER_WEIGHT: Dictionary = {EnemyTier.EASY: 0.1, EnemyTier.NORMAL: 0.1, EnemyTier.HARD: 0.1}
const _TIER_ITEM_WEIGHTS: Dictionary = {
	EnemyTier.EASY: {ItemTier.COMMON: 0.70, ItemTier.UNCOMMON: 0.25, ItemTier.RARE: 0.05},
	EnemyTier.NORMAL: {ItemTier.COMMON: 0.50, ItemTier.UNCOMMON: 0.35, ItemTier.RARE: 0.15},
	EnemyTier.HARD: {ItemTier.COMMON: 0.30, ItemTier.UNCOMMON: 0.40, ItemTier.RARE: 0.30},
}

var entries: Array[DropEntry] = []


func add_entry(entry: DropEntry) -> void:
	entries.append(entry)


static func from_enemy_tier(tier: int, drops_gold: bool = true, drops_weapon: bool = true, drops_modifier: bool = true) -> DropTable:
	var table := DropTable.new()
	if drops_gold:
		table.add_entry(DropEntry.gold(1.0, _TIER_GOLD_MIN[tier], _TIER_GOLD_MAX[tier], _TIER_GOLD_PER_DROP[tier]))
	if drops_weapon:
		var weights: Dictionary = _TIER_ITEM_WEIGHTS[tier]
		for item_tier in weights:
			table.add_entry(DropEntry.weapon_pool(_TIER_WEAPON_WEIGHT[tier] * float(weights[item_tier]), item_tier))
	if drops_modifier:
		var weights: Dictionary = _TIER_ITEM_WEIGHTS[tier]
		for item_tier in weights:
			table.add_entry(DropEntry.modifier_pool(_TIER_MODIFIER_WEIGHT[tier] * float(weights[item_tier]), item_tier))
	return table


static func resolve_item_tier(enemy_tier: int) -> int:
	var weights: Dictionary = _TIER_ITEM_WEIGHTS[enemy_tier]
	var roll := randf()
	var cumulative := 0.0
	for item_tier in [ItemTier.COMMON, ItemTier.UNCOMMON, ItemTier.RARE]:
		cumulative += float(weights[item_tier])
		if roll <= cumulative:
			return item_tier
	return ItemTier.COMMON


func resolve(position: Vector2, parent: Node) -> void:
	for entry in entries:
		var roll := randf()
		if roll > entry.weight:
			continue
		var count := randi_range(entry.min_count, entry.max_count)
		for i in count:
			match entry.kind:
				DropKind.GOLD:
					_resolve_gold(position, parent, entry)
				DropKind.WEAPON_POOL:
					_resolve_weapon_pool(position, parent, entry)
				DropKind.MODIFIER_POOL:
					_resolve_modifier_pool(position, parent, entry)
				DropKind.SCENE:
					_resolve_scene(position, parent, entry)


func _resolve_gold(position: Vector2, parent: Node, entry: DropEntry) -> void:
	var drop: Node = GOLD_DROP_SCENE.instantiate()
	if drop.has_method("set_amount") and entry.gold_per_drop > 0:
		drop.set_amount(entry.gold_per_drop)
	var offset := Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
	parent.add_child(drop)
	drop.global_position = position + offset


func _resolve_weapon_pool(position: Vector2, parent: Node, entry: DropEntry) -> void:
	var weapon := WeaponRegistry.get_random_weapon(entry.item_tier)
	if weapon == null:
		return
	var drop: Node = WEAPON_DROP_SCENE.instantiate()
	drop.weapon = weapon
	var offset := Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
	parent.add_child(drop)
	drop.global_position = position + offset


func _resolve_modifier_pool(position: Vector2, parent: Node, entry: DropEntry) -> void:
	var modifier := WeaponRegistry.get_random_modifier(entry.item_tier)
	if modifier == null:
		return
	var drop: Node = MODIFIER_DROP_SCENE.instantiate()
	drop.modifier = modifier
	var offset := Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
	parent.add_child(drop)
	drop.global_position = position + offset


func _resolve_scene(position: Vector2, parent: Node, entry: DropEntry) -> void:
	if entry.scene == null:
		return
	var drop: Node = entry.scene.instantiate()
	if drop.has_method("set_amount") and entry.gold_per_drop > 0:
		drop.set_amount(entry.gold_per_drop)
	var offset := Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
	parent.add_child(drop)
	drop.global_position = position + offset
```

- [ ] **Step 2: Verify no syntax errors by checking the scene loads**

Run: Open the Godot project and confirm no parse errors in `src/enemies/drop_table.gd`.

- [ ] **Step 3: Commit**

```bash
git add src/enemies/drop_table.gd
git commit -m "feat: refactor DropEntry with kind enum and pool-based drop kinds"
```

---

### Task 2: Add tier pools and weighted selection to WeaponRegistry

**Files:**
- Modify: `src/autoload/weapon_registry.gd`

- [ ] **Step 1: Update WeaponRegistry with tier pools and random selection**

Replace the entire contents of `src/autoload/weapon_registry.gd` with:

```gdscript
extends Node

const _Weapon = preload("res://src/weapons/weapon.gd")
const _Modifier = preload("res://src/weapons/modifier.gd")

class WeaponDropEntry:
	var script: GDScript
	var weight: float

	func _init(p_script: GDScript, p_weight: float = 1.0) -> void:
		script = p_script
		weight = p_weight

class ModifierDropEntry:
	var script: GDScript
	var weight: float

	func _init(p_script: GDScript, p_weight: float = 1.0) -> void:
		script = p_script
		weight = p_weight

var weapon_scripts: Dictionary = {}
var modifier_scripts: Dictionary = {}
var weapon_tiers: Dictionary = {}
var modifier_tiers: Dictionary = {}

func _ready() -> void:
	weapon_scripts["melee"] = preload("res://src/weapons/melee_weapon.gd")
	weapon_scripts["test"] = preload("res://src/weapons/test_weapon.gd")
	modifier_scripts["lava_emitter"] = preload("res://src/weapons/lava_emitter_modifier.gd")

	_populate_tiers()


func _populate_tiers() -> void:
	weapon_tiers[DropTable.ItemTier.COMMON] = [
		WeaponDropEntry.new(preload("res://src/weapons/melee_weapon.gd"), 1.0),
		WeaponDropEntry.new(preload("res://src/weapons/test_weapon.gd"), 0.5),
	]
	weapon_tiers[DropTable.ItemTier.UNCOMMON] = []
	weapon_tiers[DropTable.ItemTier.RARE] = []

	modifier_tiers[DropTable.ItemTier.COMMON] = [
		ModifierDropEntry.new(preload("res://src/weapons/lava_emitter_modifier.gd"), 1.0),
	]
	modifier_tiers[DropTable.ItemTier.UNCOMMON] = []
	modifier_tiers[DropTable.ItemTier.RARE] = []


func get_random_weapon(tier: int) -> _Weapon:
	var entries: Array = weapon_tiers.get(tier, [])
	if entries.is_empty():
		entries = weapon_tiers.get(DropTable.ItemTier.COMMON, [])
	if entries.is_empty():
		return null
	var total_weight := 0.0
	for entry in entries:
		total_weight += entry.weight
	var roll := randf() * total_weight
	var cumulative := 0.0
	for entry in entries:
		cumulative += entry.weight
		if roll <= cumulative:
			return entry.script.new()
	return entries[0].script.new()


func get_random_modifier(tier: int) -> _Modifier:
	var entries: Array = modifier_tiers.get(tier, [])
	if entries.is_empty():
		entries = modifier_tiers.get(DropTable.ItemTier.COMMON, [])
	if entries.is_empty():
		return null
	var total_weight := 0.0
	for entry in entries:
		total_weight += entry.weight
	var roll := randf() * total_weight
	var cumulative := 0.0
	for entry in entries:
		cumulative += entry.weight
		if roll <= cumulative:
			return entry.script.new()
	return entries[0].script.new()
```

- [ ] **Step 2: Verify no parse errors**

Run: Open the Godot project and confirm no parse errors in `src/autoload/weapon_registry.gd`.

- [ ] **Step 3: Commit**

```bash
git add src/autoload/weapon_registry.gd
git commit -m "feat: add tier pools and weighted random selection to WeaponRegistry"
```

---

### Task 3: Add enemy_tier to Enemy base class

**Files:**
- Modify: `src/enemies/enemy.gd`

- [ ] **Step 1: Add enemy_tier export to Enemy**

In `src/enemies/enemy.gd`, after the existing `@export` variables (line 8), add:

```gdscript
@export var enemy_tier: int = DropTable.EnemyTier.NORMAL
```

- [ ] **Step 2: Commit**

```bash
git add src/enemies/enemy.gd
git commit -m "feat: add enemy_tier export to Enemy base class"
```

---

### Task 4: Update DummyEnemy to use new drop table API

**Files:**
- Modify: `src/enemies/dummy_enemy.gd`

- [ ] **Step 1: Rewrite DummyEnemy._setup_drop_table() to use from_enemy_tier()**

Replace `src/enemies/dummy_enemy.gd` contents with:

```gdscript
class_name DummyEnemy
extends Enemy

var _player: Node = null


func _ready() -> void:
	super._ready()
	_sprite_modulate_green()
	_setup_drop_table()
	_player = get_tree().get_first_node_in_group("player")


func _sprite_modulate_green() -> void:
	_set_base_modulate(Color(0.2, 0.8, 0.2))


func _setup_drop_table() -> void:
	drop_table = DropTable.from_enemy_tier(enemy_tier)


func _process(delta: float) -> void:
	global_position += _knockback_velocity * delta
	_tick_knockback(delta)
	if _player == null or not is_instance_valid(_player):
		return
	var dir: Vector2 = _player.global_position - global_position
	if dir.length() < 4.0:
		return
	global_position += dir.normalized() * speed * delta


func _on_hit() -> void:
	super._on_hit()
```

- [ ] **Step 2: Verify the game loads and DummyEnemy still drops loot on death**

Run: Start the game, kill a dummy enemy, confirm gold and weapon drops still appear.

- [ ] **Step 3: Commit**

```bash
git add src/enemies/dummy_enemy.gd
git commit -m "feat: update DummyEnemy to use tier-based drop table"
```

---

### Task 5: Write unit tests for DropTable and WeaponRegistry

**Files:**
- Create: `tests/unit/test_drop_table.gd`
- Create: `tests/unit/test_weapon_registry_pools.gd`

- [ ] **Step 1: Write tests for DropTable**

Create `tests/unit/test_drop_table.gd`:

```gdscript
extends GdUnitTestSuite

const _DropTable = preload("res://src/enemies/drop_table.gd")


func test_drop_entry_gold_constructor() -> void:
	var entry := _DropTable.DropEntry.gold(0.8, 2, 5, 10)
	assert_that(entry.kind).is_equal(_DropTable.DropKind.GOLD)
	assert_that(entry.weight).is_equal(0.8)
	assert_that(entry.min_count).is_equal(2)
	assert_that(entry.max_count).is_equal(5)
	assert_that(entry.gold_per_drop).is_equal(10)


func test_drop_entry_weapon_pool_constructor() -> void:
	var entry := _DropTable.DropEntry.weapon_pool(0.3, _DropTable.ItemTier.UNCOMMON)
	assert_that(entry.kind).is_equal(_DropTable.DropKind.WEAPON_POOL)
	assert_that(entry.weight).is_equal(0.3)
	assert_that(entry.item_tier).is_equal(_DropTable.ItemTier.UNCOMMON)
	assert_that(entry.min_count).is_equal(1)
	assert_that(entry.max_count).is_equal(1)


func test_drop_entry_modifier_pool_constructor() -> void:
	var entry := _DropTable.DropEntry.modifier_pool(0.15, _DropTable.ItemTier.RARE, 1, 2)
	assert_that(entry.kind).is_equal(_DropTable.DropKind.MODIFIER_POOL)
	assert_that(entry.weight).is_equal(0.15)
	assert_that(entry.item_tier).is_equal(_DropTable.ItemTier.RARE)
	assert_that(entry.min_count).is_equal(1)
	assert_that(entry.max_count).is_equal(2)


func test_drop_entry_scene_constructor() -> void:
	var entry := _DropTable.DropEntry.scene(null, 0.5, 1, 3)
	assert_that(entry.kind).is_equal(_DropTable.DropKind.SCENE)
	assert_that(entry.weight).is_equal(0.5)
	assert_that(entry.min_count).is_equal(1)
	assert_that(entry.max_count).is_equal(3)


func test_from_enemy_tier_creates_table_for_easy() -> void:
	var table := _DropTable.from_enemy_tier(_DropTable.EnemyTier.EASY)
	assert_that(table.entries.size()).is_equal(5)


func test_from_enemy_tier_creates_table_for_hard() -> void:
	var table := _DropTable.from_enemy_tier(_DropTable.EnemyTier.HARD)
	assert_that(table.entries.size()).is_equal(5)


func test_from_enemy_tier_gold_only() -> void:
	var table := _DropTable.from_enemy_tier(_DropTable.EnemyTier.NORMAL, true, false, false)
	assert_that(table.entries.size()).is_equal(1)
	assert_that(table.entries[0].kind).is_equal(_DropTable.DropKind.GOLD)


func test_from_enemy_tier_weapon_pool_entry_weights() -> void:
	var table := _DropTable.from_enemy_tier(_DropTable.EnemyTier.EASY, false, true, false)
	assert_that(table.entries.size()).is_equal(3)
	assert_that(table.entries[0].kind).is_equal(_DropTable.DropKind.WEAPON_POOL)
	assert_that(table.entries[0].item_tier).is_equal(_DropTable.ItemTier.COMMON)


func test_resolve_item_tier_returns_valid_tier() -> void:
	var tier := _DropTable.resolve_item_tier(_DropTable.EnemyTier.NORMAL)
	assert_that(tier >= _DropTable.ItemTier.COMMON).is_true()
	assert_that(tier <= _DropTable.ItemTier.RARE).is_true()


func test_add_entry_and_entries_count() -> void:
	var table := _DropTable.new()
	table.add_entry(_DropTable.DropEntry.gold(1.0, 1, 3, 5))
	table.add_entry(_DropTable.DropEntry.weapon_pool(0.3, _DropTable.ItemTier.COMMON))
	assert_that(table.entries.size()).is_equal(2)
```

- [ ] **Step 2: Write tests for WeaponRegistry pools**

Create `tests/unit/test_weapon_registry_pools.gd`:

```gdscript
extends GdUnitTestSuite


func test_get_random_weapon_common_returns_weapon() -> void:
	var weapon := WeaponRegistry.get_random_weapon(DropTable.ItemTier.COMMON)
	assert_that(weapon).is_not_null()
	assert_that(weapon is Weapon).is_true()


func test_get_random_weapon_fallback_to_common() -> void:
	var weapon := WeaponRegistry.get_random_weapon(DropTable.ItemTier.RARE)
	assert_that(weapon).is_not_null()


func test_get_random_modifier_common_returns_modifier() -> void:
	var modifier := WeaponRegistry.get_random_modifier(DropTable.ItemTier.COMMON)
	assert_that(modifier).is_not_null()
	assert_that(modifier is Modifier).is_true()


func test_get_random_modifier_fallback_to_common() -> void:
	var modifier := WeaponRegistry.get_random_modifier(DropTable.ItemTier.RARE)
	assert_that(modifier).is_not_null()


func test_weapon_tiers_populated() -> void:
	assert_that(WeaponRegistry.weapon_tiers.has(DropTable.ItemTier.COMMON)).is_true()
	assert_that(WeaponRegistry.weapon_tiers[DropTable.ItemTier.COMMON].size() > 0).is_true()


func test_modifier_tiers_populated() -> void:
	assert_that(WeaponRegistry.modifier_tiers.has(DropTable.ItemTier.COMMON)).is_true()
	assert_that(WeaponRegistry.modifier_tiers[DropTable.ItemTier.COMMON].size() > 0).is_true()
```

- [ ] **Step 3: Run the tests**

Run: `godot --headless --script addons/gdUnit4/bin/GdUnitCmdTool.gd --run-tests tests/unit/ -c`

- [ ] **Step 4: Fix any test failures**

If any tests fail, fix the implementation and re-run.

- [ ] **Step 5: Commit**

```bash
git add tests/unit/test_drop_table.gd tests/unit/test_weapon_registry_pools.gd
git commit -m "test: add unit tests for DropTable and WeaponRegistry pools"
```

---

### Task 6: Update implementation_todo.md to mark task complete

**Files:**
- Modify: `docs/design_docs/implementation_todo.md`

- [ ] **Step 1: Mark enemy drop tables as done**

In `docs/design_docs/implementation_todo.md`, change line 66 from `| | P1 | Medium | Enemy drop tables | Define what enemies can drop |` to `| x | P1 | Medium | Enemy drop tables | Define what enemies can drop |`

- [ ] **Step 2: Commit**

```bash
git add docs/design_docs/implementation_todo.md
git commit -m "docs: mark enemy drop tables as complete"
```