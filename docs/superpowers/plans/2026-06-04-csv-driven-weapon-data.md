# CSV-Driven Weapon & Modifier Data Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Source universal weapon/modifier data (name, rarity, cooldown, damage, slots, texture, pre-attached modifiers) from `docs/design_docs/weapons.csv` and `docs/design_docs/modifiers.csv`, while `.tres` files retain only type-specific tuning.

**Architecture:** A tiny static CSV parser feeds the existing `WeaponRegistry` autoload, which loads each weapon's `.tres` (for type-specific data), overlays the CSV's universal fields onto a duplicate, and attaches pre-attached modifiers. Modifiers are built from their GDScript classes with CSV-supplied metadata overlaid. Direct `.tres` preloads in the spawners are migrated to a new `get_weapon_by_id` accessor.

**Tech Stack:** Godot 4 / GDScript, gdUnit4 test framework.

---

## Reference: project conventions

- **Run a test file:** `./addons/gdUnit4/runtest.sh -a tests/unit/test_foo.gd`
- **Run all unit tests:** `./addons/gdUnit4/runtest.sh -a tests/unit`
- Test files extend `GdUnitTestSuite`, live in `tests/unit/`, named `test_*.gd`.
- Autoloads (e.g. `WeaponRegistry`, `DropTable`) are available inside tests by name.
- Indentation is **tabs**, not spaces (GDScript).

## Reference: CSV contents (already authored, except the new texture column)

`docs/design_docs/weapons.csv` current header:
```
id,name,description,type,rarity,cooldown,damage,modifier_slots,pre_attached_modifier1,pre_attached_modifier2,pre_attached_modifier3
```
A new `weapon_texture` column is added in Task 6.

`docs/design_docs/modifiers.csv`:
```
id,name,description,suppresses_base_use
lava_emitter,Lava Emitter,Spawns lava around the user when the weapon is used.,No
```

## File structure

- **Create** `src/util/csv_table.gd` — generic CSV → `Array[Dictionary]` parser.
- **Create** `tests/unit/test_csv_table.gd` — parser tests.
- **Create** `tests/unit/test_csv_weapon_data.gd` — registry overlay + modifier tests.
- **Create** `tests/fixtures/csv_sample.csv` — fixture for parser tests.
- **Modify** `src/weapons/weapon.gd` — add `description` field.
- **Modify** `src/autoload/weapon_registry.gd` — CSV parse + overlay + `get_weapon_by_id` + `_make_modifier`.
- **Modify** `resources/weapons/*.tres` (all 8) — trim universal fields; remove flame_blade's modifier sub-resource.
- **Modify** `docs/design_docs/weapons.csv` — add `weapon_texture` column + values.
- **Modify** `src/core/spawn_dispatcher.gd`, `src/core/cave_spawner.gd` — replace `.tres` preload consts with `get_weapon_by_id`.
- **Modify** `tests/unit/test_weapon_resources.gd` — read universal fields via registry.

---

## Task 1: CSV parser

**Files:**
- Create: `src/util/csv_table.gd`
- Create: `tests/fixtures/csv_sample.csv`
- Test: `tests/unit/test_csv_table.gd`

- [ ] **Step 1: Create the test fixture**

Create `tests/fixtures/csv_sample.csv` with exactly these lines (the second data row exercises a quoted field containing a comma, and a blank trailing cell):

```
id,name,note,extra
alpha,Alpha,plain note,x
beta,Beta,"a note, with comma",
```

- [ ] **Step 2: Write the failing test**

Create `tests/unit/test_csv_table.gd`:

```gdscript
extends GdUnitTestSuite

const CsvTable = preload("res://src/util/csv_table.gd")

func test_parses_rows_keyed_by_header() -> void:
	var rows := CsvTable.parse("res://tests/fixtures/csv_sample.csv")
	assert_that(rows.size()).is_equal(2)
	assert_that(rows[0]["id"]).is_equal("alpha")
	assert_that(rows[0]["name"]).is_equal("Alpha")
	assert_that(rows[0]["extra"]).is_equal("x")

func test_handles_quoted_comma_and_blank_cell() -> void:
	var rows := CsvTable.parse("res://tests/fixtures/csv_sample.csv")
	assert_that(rows[1]["note"]).is_equal("a note, with comma")
	assert_that(rows[1]["extra"]).is_equal("")

func test_missing_file_returns_empty() -> void:
	var rows := CsvTable.parse("res://tests/fixtures/does_not_exist.csv")
	assert_that(rows.size()).is_equal(0)
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_csv_table.gd`
Expected: FAIL — `csv_table.gd` does not exist / parse not found.

- [ ] **Step 4: Implement the parser**

Create `src/util/csv_table.gd`:

```gdscript
class_name CsvTable
extends RefCounted

# Parses a CSV file into an Array of Dictionaries keyed by the header row.
# Uses FileAccess.get_csv_line() so quoted fields containing commas parse
# correctly. Blank lines are skipped. Missing file -> empty array + warning.
static func parse(path: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		push_warning("CsvTable: file not found: %s" % path)
		return rows
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("CsvTable: could not open: %s" % path)
		return rows
	var headers: PackedStringArray = file.get_csv_line()
	while not file.eof_reached():
		var values: PackedStringArray = file.get_csv_line()
		if values.size() == 1 and values[0] == "":
			continue
		var row: Dictionary = {}
		for i in range(headers.size()):
			row[headers[i]] = values[i] if i < values.size() else ""
		rows.append(row)
	return rows
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_csv_table.gd`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add src/util/csv_table.gd tests/unit/test_csv_table.gd tests/fixtures/csv_sample.csv
git commit -m "feat: add generic CSV table parser"
```

---

## Task 2: Add `description` field to Weapon

**Files:**
- Modify: `src/weapons/weapon.gd`

- [ ] **Step 1: Add the field**

In `src/weapons/weapon.gd`, directly below the existing line `@export var name: String = "Weapon"`, add:

```gdscript
@export var description: String = ""
```

- [ ] **Step 2: Run the existing weapon suite to confirm nothing breaks**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_weapon_resources.gd`
Expected: PASS (still passing; field addition is backward-compatible).

- [ ] **Step 3: Commit**

```bash
git add src/weapons/weapon.gd
git commit -m "feat: add description field to Weapon"
```

---

## Task 3: Add `weapon_texture` column to weapons.csv

**Files:**
- Modify: `docs/design_docs/weapons.csv`

- [ ] **Step 1: Rewrite the CSV with the new column**

Replace the entire contents of `docs/design_docs/weapons.csv` with (note the new `weapon_texture` column inserted before `modifier_slots`, and `flame_blade` now lists `lava_emitter` as its pre-attached modifier):

```
id,name,description,type,rarity,cooldown,damage,weapon_texture,modifier_slots,pre_attached_modifier1,pre_attached_modifier2,pre_attached_modifier3
rusty_sword,Rusty Sword,To be written,Melee,Common,0.5,3.0,res://textures/Weapons/sword_01c.png,3,,,
bone_dagger,Bone Dagger,To be written,Melee,Common,0.25,2.0,res://textures/Weapons/sword_01c.png,3,,,
broad_axe,Broad Axe,To be written,Melee,Common,0.7,6.0,res://textures/Weapons/sword_01c.png,3,,,
flame_blade,Flame Blade,To be written,Melee,Common,0.4,5.0,res://textures/Weapons/sword_01c.png,3,lava_emitter,,
throwing_knife,Throwing Knife,To be written,Ranged,Uncommon,1.0,3.0,res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/16x16/bow_01a.png,3,,,
fire_orb,Fire Orb,To be written,Ranged,Uncommon,1.5,4.0,res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/16x16/bow_01e.png,3,,,
spread_shot,Spread Shot,To be written,Ranged,Uncommon,1.2,2.0,res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/16x16/bow_02a.png,3,,,
boss_staff,Boss Staff,To be written,Ranged,Rare,1.0,3.0,res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/16x16/bow_03a.png,3,,,
```

- [ ] **Step 2: Commit**

```bash
git add docs/design_docs/weapons.csv
git commit -m "data: add weapon_texture column and flame_blade pre-attached modifier"
```

---

## Task 4: WeaponRegistry — modifier builder from modifiers.csv

This task adds CSV-driven modifier construction. We do it before weapon overlay because pre-attached modifiers depend on it.

**Files:**
- Modify: `src/autoload/weapon_registry.gd`
- Test: `tests/unit/test_csv_weapon_data.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_csv_weapon_data.gd`:

```gdscript
extends GdUnitTestSuite

func test_make_modifier_overlays_csv_metadata() -> void:
	var mod = WeaponRegistry._make_modifier("lava_emitter")
	assert_that(mod).is_not_null()
	assert_that(mod.name).is_equal("Lava Emitter")
	assert_that(mod.description).is_equal("Spawns lava around the user when the weapon is used.")
	assert_that(mod.suppresses_base_use).is_false()

func test_make_modifier_unknown_id_returns_null() -> void:
	var mod = WeaponRegistry._make_modifier("does_not_exist")
	assert_that(mod).is_null()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_csv_weapon_data.gd`
Expected: FAIL — `_make_modifier` does not exist.

- [ ] **Step 3: Add modifier CSV parsing + builder**

In `src/autoload/weapon_registry.gd`:

(a) Add these constants near the top, just after the existing `const WEAPON_RESOURCE_DIR := "res://resources/weapons"` line:

```gdscript
const WEAPON_CSV_PATH := "res://docs/design_docs/weapons.csv"
const MODIFIER_CSV_PATH := "res://docs/design_docs/modifiers.csv"
```

(b) Add a member to hold parsed modifier metadata, next to the existing `var _all_weapons: Array = []` line:

```gdscript
var _modifier_data: Dictionary = {}  # id -> { name, description, suppresses_base_use }
```

(c) In `_ready()`, add a line to parse the modifier CSV immediately after the `modifier_scripts["lava_emitter"] = ...` line and before `_load_weapon_resources()`:

```gdscript
	_load_modifier_data()
```

(d) Add these two methods at the end of the file:

```gdscript
func _load_modifier_data() -> void:
	_modifier_data.clear()
	for row in CsvTable.parse(MODIFIER_CSV_PATH):
		var id: String = row.get("id", "")
		if id == "":
			continue
		_modifier_data[id] = {
			"name": row.get("name", ""),
			"description": row.get("description", ""),
			"suppresses_base_use": row.get("suppresses_base_use", "No").strip_edges() == "Yes",
		}


func _make_modifier(id: String) -> _Modifier:
	var script: GDScript = modifier_scripts.get(id)
	if script == null:
		push_warning("WeaponRegistry: unknown modifier id '%s'" % id)
		return null
	var mod: _Modifier = script.new()
	var data: Dictionary = _modifier_data.get(id, {})
	if data.has("name"):
		mod.name = data["name"]
	if data.has("description"):
		mod.description = data["description"]
	if data.has("suppresses_base_use"):
		mod.suppresses_base_use = data["suppresses_base_use"]
	return mod
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_csv_weapon_data.gd`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/autoload/weapon_registry.gd tests/unit/test_csv_weapon_data.gd
git commit -m "feat: build modifiers from modifiers.csv metadata"
```

---

## Task 5: WeaponRegistry — weapon overlay from weapons.csv

**Files:**
- Modify: `src/autoload/weapon_registry.gd`
- Test: `tests/unit/test_csv_weapon_data.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_csv_weapon_data.gd`:

```gdscript
func test_weapon_universal_fields_from_csv() -> void:
	var w = WeaponRegistry.get_weapon_by_id("rusty_sword")
	assert_that(w).is_not_null()
	assert_that(w.name).is_equal("Rusty Sword")
	assert_that(w.damage).is_equal(3.0)
	assert_that(w.cooldown).is_equal(0.5)

func test_weapon_keeps_type_specific_tres_fields() -> void:
	var w = WeaponRegistry.get_weapon_by_id("rusty_sword")
	assert_that(w.weapon_reach).is_equal(28.0)

func test_rarity_word_mapped_to_enum() -> void:
	var w = WeaponRegistry.get_weapon_by_id("boss_staff")
	assert_that(w.rarity).is_equal(DropTable.ItemTier.RARE)

func test_pre_attached_modifier_applied() -> void:
	var w = WeaponRegistry.get_weapon_by_id("flame_blade")
	var mod = w.get_modifier_at(0)
	assert_that(mod).is_not_null()
	assert_that(mod.name).is_equal("Lava Emitter")

func test_unknown_weapon_id_returns_null() -> void:
	assert_that(WeaponRegistry.get_weapon_by_id("nope")).is_null()
```

- [ ] **Step 2: Run to verify failure**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_csv_weapon_data.gd`
Expected: FAIL — `get_weapon_by_id` not found.

- [ ] **Step 3: Add the rarity map and `_weapons_by_id` member**

In `src/autoload/weapon_registry.gd`, add next to the other member declarations (near `var _all_weapons: Array = []`):

```gdscript
var _weapons_by_id: Dictionary = {}  # id -> overlaid Weapon (canonical copy)

const _RARITY_WORDS := {
	"Common": DropTable.ItemTier.COMMON,
	"Uncommon": DropTable.ItemTier.UNCOMMON,
	"Rare": DropTable.ItemTier.RARE,
}
```

- [ ] **Step 4: Replace `_load_weapon_resources` with the CSV-driven version**

Replace the entire existing `_load_weapon_resources()` function body with:

```gdscript
func _load_weapon_resources() -> void:
	_all_weapons.clear()
	_weapons_by_id.clear()
	for row in CsvTable.parse(WEAPON_CSV_PATH):
		var id: String = row.get("id", "")
		if id == "":
			continue
		var path := "%s/%s.tres" % [WEAPON_RESOURCE_DIR, id]
		var res := load(path)
		if not (res is Weapon):
			push_warning("WeaponRegistry: missing or invalid .tres for '%s' (%s)" % [id, path])
			continue
		var weapon: Weapon = res.duplicate(true)
		_apply_csv_fields(weapon, row)
		_weapons_by_id[id] = weapon
		_all_weapons.append({ "id": id, "resource": weapon, "weight": 1.0 })


func _apply_csv_fields(weapon: Weapon, row: Dictionary) -> void:
	weapon.name = row.get("name", weapon.name)
	weapon.description = row.get("description", "")
	weapon.cooldown = float(row.get("cooldown", weapon.cooldown))
	weapon.damage = float(row.get("damage", weapon.damage))
	weapon.modifier_slot_count = int(row.get("modifier_slots", weapon.modifier_slot_count))
	weapon.rarity = _map_rarity(row.get("rarity", ""))
	_validate_type(weapon, row.get("type", ""))
	_apply_weapon_texture(weapon, row.get("weapon_texture", ""))
	_apply_pre_attached_modifiers(weapon, row)


func _map_rarity(word: String) -> int:
	if _RARITY_WORDS.has(word):
		return _RARITY_WORDS[word]
	push_warning("WeaponRegistry: unknown rarity '%s', defaulting to COMMON" % word)
	return DropTable.ItemTier.COMMON


func _validate_type(weapon: Weapon, type_word: String) -> void:
	var is_ranged: bool = weapon is RangedWeapon
	if type_word == "Ranged" and not is_ranged:
		push_warning("WeaponRegistry: '%s' CSV type Ranged but script is not RangedWeapon" % weapon.name)
	elif type_word == "Melee" and is_ranged:
		push_warning("WeaponRegistry: '%s' CSV type Melee but script is RangedWeapon" % weapon.name)


func _apply_weapon_texture(weapon: Weapon, tex_path: String) -> void:
	if tex_path == "":
		return
	var tex := load(tex_path)
	if tex is Texture2D:
		weapon.weapon_texture = tex
	else:
		push_warning("WeaponRegistry: could not load texture '%s'" % tex_path)


func _apply_pre_attached_modifiers(weapon: Weapon, row: Dictionary) -> void:
	for i in range(1, 4):
		var mod_id: String = row.get("pre_attached_modifier%d" % i, "")
		if mod_id == "":
			continue
		var mod := _make_modifier(mod_id)
		if mod == null:
			continue
		var slot := weapon.find_empty_modifier_slot()
		if slot >= 0:
			weapon.add_modifier(slot, mod)
```

Note: `weapon.weapon_texture` exists on both `MeleeWeapon` and `RangedWeapon`. The base `Weapon` class has no such property, but every `.tres` uses one of those two scripts, so the assignment is always valid. If a future weapon script lacks the property this will error loudly — acceptable.

- [ ] **Step 5: Add the `get_weapon_by_id` accessor**

Add this method to `src/autoload/weapon_registry.gd` (e.g. right after `get_random_weapon`):

```gdscript
func get_weapon_by_id(id: String) -> _Weapon:
	var weapon: Weapon = _weapons_by_id.get(id)
	if weapon == null:
		push_warning("WeaponRegistry: unknown weapon id '%s'" % id)
		return null
	return weapon.duplicate(true)
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_csv_weapon_data.gd`
Expected: PASS (all 7 tests).

- [ ] **Step 7: Commit**

```bash
git add src/autoload/weapon_registry.gd tests/unit/test_csv_weapon_data.gd
git commit -m "feat: overlay weapons.csv universal fields onto .tres resources"
```

---

## Task 6: Trim universal fields from .tres files

The `.tres` files must keep only type-specific tuning. The registry now supplies `name`, `rarity`, `cooldown`, `damage`, and `weapon_texture`. Removing them avoids a second, stale source of truth.

**Files:**
- Modify: all 8 files in `resources/weapons/`

- [ ] **Step 1: Trim melee .tres files**

For `resources/weapons/rusty_sword.tres`, remove the `name`, `cooldown`, and `damage` lines from the `[resource]` block, leaving:

```
[gd_resource type="Resource" script_class="MeleeWeapon" load_steps=2 format=3 uid="uid://brustysword"]

[ext_resource type="Script" path="res://src/weapons/melee_weapon.gd" id="1"]

[resource]
script = ExtResource("1")
weapon_reach = 28.0
arc_angle = 1.5707963268
```

Apply the same trimming (remove `name`/`cooldown`/`damage`) to:
- `resources/weapons/bone_dagger.tres` (keep `weapon_reach = 20.0`, `arc_angle = 1.0471975512`)
- `resources/weapons/broad_axe.tres` (keep `weapon_reach = 36.0`, `arc_angle = 2.0943951024`)

- [ ] **Step 2: Trim and de-modifier flame_blade.tres**

Replace the entire contents of `resources/weapons/flame_blade.tres` with (the lava-emitter sub-resource is removed — it now comes from the CSV; `weapon_reach`/`arc_angle` are kept):

```
[gd_resource type="Resource" script_class="MeleeWeapon" load_steps=2 format=3 uid="uid://bflameblade"]

[ext_resource type="Script" path="res://src/weapons/melee_weapon.gd" id="1"]

[resource]
script = ExtResource("1")
weapon_reach = 32.0
arc_angle = 1.5707963268
```

- [ ] **Step 3: Trim ranged .tres files**

For each ranged file, remove `name`, `cooldown`, `damage`, `rarity`, and `weapon_texture` from the `[resource]` block, keeping the projectile tuning and `projectile_texture`. Because `weapon_texture` is dropped, its `[ext_resource]` for the bow icon is no longer referenced — remove that ext_resource line too and renumber remaining ids if needed.

`resources/weapons/throwing_knife.tres` becomes:

```
[gd_resource type="Resource" script_class="RangedWeapon" load_steps=3 format=3 uid="uid://bthrowingknife"]

[ext_resource type="Script" path="res://src/weapons/ranged_weapon.gd" id="1"]
[ext_resource type="Texture2D" path="res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/16x16/arrow_01a.png" id="3"]

[resource]
script = ExtResource("1")
projectile_speed = 180.0
projectile_lifetime = 2.0
spread_angle = 0.0
projectile_count = 1
projectile_texture = ExtResource("3")
```

`resources/weapons/fire_orb.tres` becomes:

```
[gd_resource type="Resource" script_class="RangedWeapon" load_steps=3 format=3 uid="uid://bfireorb"]

[ext_resource type="Script" path="res://src/weapons/ranged_weapon.gd" id="1"]
[ext_resource type="Texture2D" path="res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/16x16/fish_01a.png" id="3"]

[resource]
script = ExtResource("1")
projectile_speed = 90.0
projectile_lifetime = 1.5
spread_angle = 0.0
projectile_count = 1
projectile_texture = ExtResource("3")
```

`resources/weapons/spread_shot.tres` becomes:

```
[gd_resource type="Resource" script_class="RangedWeapon" load_steps=3 format=3 uid="uid://bspreadshot"]

[ext_resource type="Script" path="res://src/weapons/ranged_weapon.gd" id="1"]
[ext_resource type="Texture2D" path="res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/16x16/arrow_02a.png" id="3"]

[resource]
script = ExtResource("1")
projectile_speed = 150.0
projectile_lifetime = 2.0
spread_angle = 30.0
projectile_count = 3
projectile_texture = ExtResource("3")
```

`resources/weapons/boss_staff.tres` becomes (drop `name`/`rarity`/`weapon_texture`, keep `spread_angle` and `projectile_texture`):

```
[gd_resource type="Resource" script_class="RangedWeapon" format=3 uid="uid://bbossstaff"]

[ext_resource type="Script" uid="uid://b08b3cytaotsb" path="res://src/weapons/ranged_weapon.gd" id="1"]
[ext_resource type="Texture2D" uid="uid://bcl2afruwt8hv" path="res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/16x16/arrow_03a.png" id="3"]

[resource]
script = ExtResource("1")
spread_angle = 10.0
projectile_texture = ExtResource("3")
```

- [ ] **Step 4: Run the CSV weapon-data tests**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_csv_weapon_data.gd`
Expected: PASS — universal fields now come solely from CSV; `weapon_reach`/`spread_angle`/`projectile_count` still come from the trimmed `.tres`.

- [ ] **Step 5: Commit**

```bash
git add resources/weapons
git commit -m "refactor: trim CSV-owned fields from weapon .tres files"
```

---

## Task 7: Migrate spawner call sites to get_weapon_by_id

The spawners preload `.tres` as `const`s and assign them directly. Those resources no longer carry universal fields, so route through the registry. (Bonus: `get_weapon_by_id` returns a duplicate, fixing the existing latent bug where boss damage scaling mutates the shared `BOSS_STAFF` resource.)

**Files:**
- Modify: `src/core/spawn_dispatcher.gd`
- Modify: `src/core/cave_spawner.gd`

- [ ] **Step 1: Update spawn_dispatcher.gd**

In `src/core/spawn_dispatcher.gd`, delete these `const` lines (15-19):

```gdscript
const RUSTY_SWORD := preload("res://resources/weapons/rusty_sword.tres")
const BONE_DAGGER := preload("res://resources/weapons/bone_dagger.tres")
const THROWING_KNIFE := preload("res://resources/weapons/throwing_knife.tres")
const FIRE_ORB := preload("res://resources/weapons/fire_orb.tres")
const BOSS_STAFF := preload("res://resources/weapons/boss_staff.tres")
```

Replace `enemy.weapon_resource = BOSS_STAFF` with:

```gdscript
		enemy.weapon_resource = WeaponRegistry.get_weapon_by_id("boss_staff")
```

Replace the two picker functions with:

```gdscript
func _pick_melee_weapon() -> Weapon:
	if randf() < 0.5:
		return WeaponRegistry.get_weapon_by_id("rusty_sword")
	return WeaponRegistry.get_weapon_by_id("bone_dagger")


func _pick_ranged_weapon() -> Weapon:
	if randf() < 0.7:
		return WeaponRegistry.get_weapon_by_id("throwing_knife")
	return WeaponRegistry.get_weapon_by_id("fire_orb")
```

(Return type widened from `MeleeWeapon`/`RangedWeapon` to `Weapon` because `get_weapon_by_id` is typed `-> Weapon`. Callers assign to `enemy.weapon_resource`, which is a `Weapon`, so this is safe.)

- [ ] **Step 2: Update cave_spawner.gd**

In `src/core/cave_spawner.gd`, delete these `const` lines (8-14):

```gdscript
const RUSTY_SWORD := preload("res://resources/weapons/rusty_sword.tres")
const BONE_DAGGER := preload("res://resources/weapons/bone_dagger.tres")
const THROWING_KNIFE := preload("res://resources/weapons/throwing_knife.tres")
const FIRE_ORB := preload("res://resources/weapons/fire_orb.tres")
const BROAD_AXE := preload("res://resources/weapons/broad_axe.tres")
const FLAME_BLADE := preload("res://resources/weapons/flame_blade.tres")
const SPREAD_SHOT := preload("res://resources/weapons/spread_shot.tres")
```

Replace the three picker functions with:

```gdscript
func _pick_melee_weapon() -> Weapon:
	if randf() < 0.5:
		return WeaponRegistry.get_weapon_by_id("rusty_sword")
	return WeaponRegistry.get_weapon_by_id("bone_dagger")


func _pick_ranged_weapon() -> Weapon:
	if randf() < 0.7:
		return WeaponRegistry.get_weapon_by_id("throwing_knife")
	return WeaponRegistry.get_weapon_by_id("fire_orb")


func _pick_elite_melee_weapon() -> Weapon:
	if randf() < 0.5:
		return WeaponRegistry.get_weapon_by_id("broad_axe")
	return WeaponRegistry.get_weapon_by_id("flame_blade")
```

Note: `spread_shot` had a preload const but no picker referenced it in the inspected code. If a usage of `SPREAD_SHOT` remains after deleting the const, replace it with `WeaponRegistry.get_weapon_by_id("spread_shot")`. Verify with: `rg -n "SPREAD_SHOT" src/core/cave_spawner.gd` — expect no matches after this step.

- [ ] **Step 3: Verify no stale references remain**

Run: `rg -n "RUSTY_SWORD|BONE_DAGGER|THROWING_KNIFE|FIRE_ORB|BOSS_STAFF|BROAD_AXE|FLAME_BLADE|SPREAD_SHOT" src/core/`
Expected: no output (all references migrated).

- [ ] **Step 4: Run the full unit suite**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit`
Expected: PASS (no parse errors from the spawners; existing spawn/weapon tests still pass).

- [ ] **Step 5: Commit**

```bash
git add src/core/spawn_dispatcher.gd src/core/cave_spawner.gd
git commit -m "refactor: spawners fetch weapons via WeaponRegistry.get_weapon_by_id"
```

---

## Task 8: Update test_weapon_resources.gd for the new data source

`tests/unit/test_weapon_resources.gd` preloads `.tres` directly and asserts universal fields that no longer live there. Universal fields now come via the registry; type-specific fields still come from the `.tres`.

**Files:**
- Modify: `tests/unit/test_weapon_resources.gd`

- [ ] **Step 1: Rewrite the test file**

Replace the entire contents of `tests/unit/test_weapon_resources.gd` with:

```gdscript
extends GdUnitTestSuite

const RUSTY_SWORD := preload("res://resources/weapons/rusty_sword.tres")
const BONE_DAGGER := preload("res://resources/weapons/bone_dagger.tres")
const THROWING_KNIFE := preload("res://resources/weapons/throwing_knife.tres")

# Type-specific tuning still lives in the .tres files.
func test_rusty_sword_type_specific_tres_fields() -> void:
	assert_that(RUSTY_SWORD.weapon_reach).is_equal(28.0)

func test_bone_dagger_type_specific_tres_fields() -> void:
	assert_that(BONE_DAGGER.weapon_reach).is_equal(20.0)

func test_throwing_knife_type_specific_tres_fields() -> void:
	assert_that(THROWING_KNIFE.projectile_speed).is_equal(180.0)
	assert_that(THROWING_KNIFE.projectile_count).is_equal(1)

# Universal fields now come from weapons.csv via the registry.
func test_rusty_sword_universal_fields_from_registry() -> void:
	var w = WeaponRegistry.get_weapon_by_id("rusty_sword")
	assert_that(w.damage).is_equal(3.0)
	assert_that(w.name).is_equal("Rusty Sword")

func test_bone_dagger_cooldown_from_registry() -> void:
	var w = WeaponRegistry.get_weapon_by_id("bone_dagger")
	assert_that(w.cooldown).is_equal(0.25)

func test_boss_staff_universal_and_type_specific() -> void:
	var w = WeaponRegistry.get_weapon_by_id("boss_staff")
	assert_that(w.damage).is_equal(3.0)
	assert_that(w.spread_angle).is_equal(10.0)

func test_weapon_duplication_independent() -> void:
	var original = WeaponRegistry.get_weapon_by_id("rusty_sword")
	var copy = original.duplicate()
	copy.damage = 99.0
	assert_that(original.damage).is_equal(3.0)
	assert_that(copy.damage).is_equal(99.0)
```

Note: the old `test_boss_staff_config` asserted `damage == 6.0`, which was never actually backed by the `.tres` (the script default is `3.0`). The CSV makes `boss_staff` damage authoritative at `3.0`; the rewritten test reflects that.

- [ ] **Step 2: Run the test**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_weapon_resources.gd`
Expected: PASS (7 tests).

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_weapon_resources.gd
git commit -m "test: read universal weapon fields via registry, type-specific via .tres"
```

---

## Task 9: Final verification

- [ ] **Step 1: Run the entire unit suite**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit`
Expected: PASS — all suites green, no GDScript parse warnings/errors in output.

- [ ] **Step 2: Sanity-check no stale `.tres` universal fields remain**

Run: `rg -n "^name|^cooldown|^damage|^rarity|^weapon_texture" resources/weapons/`
Expected: no output (all universal fields removed from `.tres`; `weapon_texture` only appears in the CSV).

- [ ] **Step 3: Final commit if anything is uncommitted**

```bash
git status
# if clean, nothing to do
```

---

## Self-review notes

- **Spec coverage:** CSV parser (T1), `description` field (T2), texture column (T3), modifier overlay (T4), weapon overlay + rarity map + `get_weapon_by_id` + error handling (T5), `.tres` trimming incl. flame_blade sub-resource removal (T6), call-site migration (T7), test updates (T8), verification (T9). All spec sections covered.
- **Type consistency:** `_make_modifier` / `get_weapon_by_id` / `_apply_*` signatures are consistent across tasks; `_weapons_by_id`, `_modifier_data`, `_RARITY_WORDS`, `WEAPON_CSV_PATH`, `MODIFIER_CSV_PATH` all defined in T4/T5 before use.
- **Export caveat** (from spec) is intentionally out of scope; noted here for whoever ships a build: add `*.csv` to the export filter or relocate the CSVs under `res://resources/`.
