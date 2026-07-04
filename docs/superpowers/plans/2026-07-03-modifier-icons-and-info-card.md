# Modifier Placeholder Icons + Modifier Drop Info Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every iconless modifier a `wall.png` placeholder icon and make modifier drops show a floating info card (icon + name + description + rarity) just like weapon drops.

**Architecture:** Add a one-place icon fallback and a rarity field at the modifier factory (`WeaponRegistry._make_modifier`). Give each `Drop` a polymorphic `populate_info_card(card)` method so the existing `WeaponInfoPopup` becomes payload-agnostic. Widen `PickupContext`'s popup gate from a `WeaponDrop` type-check to a capability check. Make `Card` stat labels auto-wrap so long descriptions fit.

**Tech Stack:** Godot 4 / GDScript, gdUnit4 test framework.

## Global Constraints

- **Test framework:** gdUnit4. Test suites `extends GdUnitTestSuite`; assertions use `assert_that(x).is_true()/.is_not_null()/.is_equal(...)`.
- **Run a single test suite:**
  ```bash
  godot --headless --path . --import && \
  godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/<file>.gd
  ```
  The `--import` step is required in fresh worktrees (the `.godot/` cache is gitignored per worktree). It is idempotent; safe to always prepend.
- **Rarity scale:** `DropTable.ItemTier { COMMON, UNCOMMON, RARE }` (`src/enemies/drop_table.gd:5`) — the same int scale `Card.set_rarity` / `UiTheme.get_rarity_color` expect for weapons.
- **Placeholder texture path:** `res://textures/wall.png`.
- **After code changes:** run `graphify update .` before the final commit of the last task (AST-only, no API cost).
- **Reference spec:** `docs/superpowers/specs/2026-07-03-modifier-icons-and-info-card-design.md`.

---

### Task 1: Rarity field on the Modifier resource

**Files:**
- Modify: `src/weapons/modifier.gd` (add field near the other vars, lines 1-11)
- Test: `tests/unit/test_modifier_rarity.gd` (create)

**Interfaces:**
- Consumes: `DropTable.ItemTier` enum.
- Produces: `Modifier.rarity: int` (defaults to `DropTable.ItemTier.COMMON`). Consumed by Tasks 2, 5.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_modifier_rarity.gd`:

```gdscript
extends GdUnitTestSuite


func test_modifier_has_rarity_defaulting_to_common() -> void:
	var mod := Modifier.new()
	assert_that(mod.rarity).is_equal(DropTable.ItemTier.COMMON)


func test_modifier_rarity_is_assignable() -> void:
	var mod := Modifier.new()
	mod.rarity = DropTable.ItemTier.RARE
	assert_that(mod.rarity).is_equal(DropTable.ItemTier.RARE)
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_modifier_rarity.gd
```
Expected: FAIL — `Invalid access to property or key 'rarity'` on `Modifier`.

- [ ] **Step 3: Add the field**

In `src/weapons/modifier.gd`, after `var is_disabled: bool = false` (line 11), add:

```gdscript
var rarity: int = DropTable.ItemTier.COMMON
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_modifier_rarity.gd
```
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/modifier.gd tests/unit/test_modifier_rarity.gd
git commit -m "feat(modifier): add rarity field to Modifier resource"
```

---

### Task 2: Icon fallback + rarity population in the factory

**Files:**
- Modify: `src/autoload/weapon_registry.gd` (add `PLACEHOLDER_ICON` const near other consts; rewrite `_make_modifier`, lines 307-319)
- Test: `tests/unit/test_modifier_icon_fallback.gd` (create)

**Interfaces:**
- Consumes: `Modifier.rarity` (Task 1), `_map_rarity(word) -> int` (`weapon_registry.gd:161`), `_modifier_data`, `modifier_scripts`, `_DataModifier`.
- Produces: every modifier returned by `WeaponRegistry._make_modifier(id)` has non-null `icon_texture` and a `rarity` matching its CSV `rarity` column.

**Fixture ids used by tests** (verified against `docs/design_docs/modifiers.csv`):
- `"adrenaline"` — pure data-driven (no entry in `modifier_scripts`), so its icon is `null` before this change.
- `"lava_emitter"` — script-backed with a real (non-`wall.png`) icon; must be left untouched.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_modifier_icon_fallback.gd`:

```gdscript
extends GdUnitTestSuite

const PLACEHOLDER := preload("res://textures/wall.png")


func test_data_modifier_gets_placeholder_icon() -> void:
	var mod: Modifier = WeaponRegistry._make_modifier("adrenaline")
	assert_that(mod).is_not_null()
	assert_that(mod.icon_texture).is_equal(PLACEHOLDER)


func test_script_modifier_keeps_its_own_icon() -> void:
	var mod: Modifier = WeaponRegistry._make_modifier("lava_emitter")
	assert_that(mod).is_not_null()
	assert_that(mod.icon_texture).is_not_null()
	assert_that(mod.icon_texture).is_not_equal(PLACEHOLDER)


func test_data_modifier_carries_csv_rarity() -> void:
	# "adrenaline" is Rare in modifiers.csv
	var mod: Modifier = WeaponRegistry._make_modifier("adrenaline")
	assert_that(mod.rarity).is_equal(DropTable.ItemTier.RARE)
```

> Before running, confirm the rarity column for `adrenaline` in `docs/design_docs/modifiers.csv`. If it is not `Rare`, set the expected value in `test_data_modifier_carries_csv_rarity` to `_map_rarity` of that word (Common→COMMON, Uncommon→UNCOMMON, Rare→RARE).

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_modifier_icon_fallback.gd
```
Expected: FAIL — `test_data_modifier_gets_placeholder_icon` fails because the icon is `null`, and `test_data_modifier_carries_csv_rarity` fails (rarity is COMMON default).

- [ ] **Step 3: Add the const and rewrite the factory**

In `src/autoload/weapon_registry.gd`, add the const alongside the other file-level consts (near `MODIFIER_CSV_PATH`):

```gdscript
const PLACEHOLDER_ICON := preload("res://textures/wall.png")
```

Replace `_make_modifier` (lines 307-319) with:

```gdscript
func _make_modifier(id: String) -> _Modifier:
	var data: Dictionary = _modifier_data.get(id, {})
	var script: GDScript = modifier_scripts.get(id)
	if script != null:
		var mod: _Modifier = script.new()
		mod.name = data.get("name", mod.name)
		mod.description = data.get("description", mod.description)
		mod.suppresses_base_use = String(data.get("suppresses_base_use", "No")).strip_edges() == "Yes"
		mod.rarity = _map_rarity(data.get("rarity", "Common"))
		if mod.icon_texture == null:
			mod.icon_texture = PLACEHOLDER_ICON
		return mod
	if data.is_empty():
		push_warning("WeaponRegistry: unknown modifier id '%s'" % id)
		return null
	var dmod: _Modifier = _DataModifier.new(data)
	dmod.rarity = _map_rarity(data.get("rarity", "Common"))
	if dmod.icon_texture == null:
		dmod.icon_texture = PLACEHOLDER_ICON
	return dmod
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_modifier_icon_fallback.gd
```
Expected: PASS (3 tests).

- [ ] **Step 5: Regression-check the existing registry suite**

Run:
```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_weapon_registry_pools.gd
```
Expected: PASS (all existing tests unchanged).

- [ ] **Step 6: Commit**

```bash
git add src/autoload/weapon_registry.gd tests/unit/test_modifier_icon_fallback.gd
git commit -m "feat(weapons): placeholder icon + rarity for factory-built modifiers"
```

---

### Task 3: Card stat labels auto-wrap to card width

**Files:**
- Modify: `src/ui/card.gd` (`populate`, stat-label loop lines 73-79; add `CONTENT_INSET` const near top)
- Test: `tests/unit/test_card_autowrap.gd` (create)

**Interfaces:**
- Consumes: `Card.populate(icon, name, stats, modifier_icons)`, `Card.card_size`.
- Produces: stat `Label`s created by `populate` have `autowrap_mode == TextServer.AUTOWRAP_WORD_SMART` and a bounded `custom_minimum_size.x`, so long description text wraps and the label grows vertically. Used by Task 5.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_card_autowrap.gd`:

```gdscript
extends GdUnitTestSuite

const CARD_SCENE := preload("res://scenes/ui/card.tscn")


func _make_card() -> Card:
	var card: Card = CARD_SCENE.instantiate()
	add_child(card)  # runs _ready so @onready nodes resolve
	return card


func test_stat_label_autowraps() -> void:
	var card := _make_card()
	var long_desc := "Arcs to a nearby foe on hit, chaining lightning between clustered enemies and applying a shock stain."
	card.populate(null, "Chain Spark", [long_desc])
	var stats_container: VBoxContainer = card.get_node(
		"SubViewportContainer/SubViewport/CardPanel/ContentVBox/StatsContainer")
	assert_that(stats_container.get_child_count()).is_equal(1)
	var label := stats_container.get_child(0) as Label
	assert_that(label.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)
	assert_that(label.custom_minimum_size.x > 0.0).is_true()
	assert_that(label.custom_minimum_size.x < card.card_size.x).is_true()
	card.queue_free()
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_card_autowrap.gd
```
Expected: FAIL — `autowrap_mode` is `AUTOWRAP_OFF` and `custom_minimum_size.x` is `0`.

- [ ] **Step 3: Add the inset const**

In `src/ui/card.gd`, after the `@export` block (near line 20), add:

```gdscript
const CONTENT_INSET: float = 16.0
```

- [ ] **Step 4: Set autowrap on stat labels**

In `src/ui/card.gd` `populate`, inside the `for stat_text in stats:` loop (lines 73-79), after `label.add_theme_font_size_override("font_size", 14)` add:

```gdscript
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size.x = card_size.x - CONTENT_INSET
```

(Match the existing tab indentation of the surrounding loop body.)

- [ ] **Step 5: Run test to verify it passes**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_card_autowrap.gd
```
Expected: PASS (1 test).

- [ ] **Step 6: Commit**

```bash
git add src/ui/card.gd tests/unit/test_card_autowrap.gd
git commit -m "feat(ui): auto-wrap card stat labels within card width"
```

---

### Task 4: `populate_info_card` on drops (base + weapon + modifier)

**Files:**
- Modify: `src/drops/drop.gd` (add default no-op method)
- Modify: `src/drops/weapon_drop.gd` (add method — logic moved from popup)
- Modify: `src/drops/modifier_drop.gd` (add method)
- Test: `tests/unit/test_drop_info_card.gd` (create)

**Interfaces:**
- Consumes: `Card.populate(icon, name, stats, modifier_icons)`, `Card.set_rarity(int)`, `Weapon.get_base_stats()`/`cooldown`/`damage`/`modifier_slot_count`/`get_modifier_at(i)`, `Modifier.name`/`description`/`icon_texture`/`rarity` (Task 1).
- Produces: `Drop.populate_info_card(card: Card) -> void` — default no-op; overridden by `WeaponDrop` (weapon stats + mod icons + rarity) and `ModifierDrop` (icon + name + [description] + rarity). Consumed by Task 5 (popup) and Task 6 (PickupContext gate via `has_method("populate_info_card")`).

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_drop_info_card.gd`. This uses a lightweight stub `Card` that records the arguments, so the test does not depend on the real card scene:

```gdscript
extends GdUnitTestSuite


class CardStub:
	extends Control
	var populate_icon: Texture2D = null
	var populate_name: String = ""
	var populate_stats: Array = []
	var populate_mods: Array = []
	var rarity_set: int = -999

	func populate(icon: Texture2D, card_name: String, stats: Array = [], mods: Array = []) -> void:
		populate_icon = icon
		populate_name = card_name
		populate_stats = stats
		populate_mods = mods

	func set_rarity(r: int) -> void:
		rarity_set = r


func test_base_drop_populate_is_noop() -> void:
	var drop := Drop.new()
	var stub := CardStub.new()
	# Should not throw and should leave the stub untouched.
	drop.populate_info_card(stub)
	assert_that(stub.populate_name).is_equal("")
	drop.free()


func test_modifier_drop_populates_icon_name_description_rarity() -> void:
	var mod := Modifier.new()
	mod.name = "Chain Spark"
	mod.description = "Arcs to a nearby foe."
	mod.rarity = DropTable.ItemTier.UNCOMMON
	var drop := ModifierDrop.new()
	drop.modifier = mod
	var stub := CardStub.new()
	drop.populate_info_card(stub)
	assert_that(stub.populate_name).is_equal("Chain Spark")
	assert_that(stub.populate_stats).is_equal(["Arcs to a nearby foe."])
	assert_that(stub.populate_mods.is_empty()).is_true()
	assert_that(stub.rarity_set).is_equal(DropTable.ItemTier.UNCOMMON)
	drop.free()


func test_modifier_drop_with_null_modifier_is_safe() -> void:
	var drop := ModifierDrop.new()
	var stub := CardStub.new()
	drop.populate_info_card(stub)  # must not throw
	assert_that(stub.populate_name).is_equal("")
	drop.free()
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_drop_info_card.gd
```
Expected: FAIL — `Invalid call. Nonexistent function 'populate_info_card'`.

- [ ] **Step 3: Add the default no-op on the base Drop**

In `src/drops/drop.gd`, after `set_highlighted` (end of file), add:

```gdscript

func populate_info_card(_card) -> void:
	pass
```

(Untyped `_card` on the base keeps `drop.gd` free of a `Card` dependency; overrides in the leaf drops type it as `Card`.)

- [ ] **Step 4: Add the weapon override (logic moved from popup)**

In `src/drops/weapon_drop.gd`, after `_on_delivery_result` (end of file), add:

```gdscript

func populate_info_card(card: Card) -> void:
	if weapon == null:
		return
	var stats: Array[String] = []
	if weapon.has_method("get_base_stats"):
		var base_stats: Dictionary = weapon.get_base_stats()
		stats.append("Cooldown: %.2fs" % float(base_stats.get("cooldown", weapon.cooldown)))
		stats.append("Damage: %.0f" % float(base_stats.get("damage", weapon.damage)))
	else:
		stats.append("Cooldown: %.2fs" % weapon.cooldown)
		stats.append("Damage: %.0f" % weapon.damage)

	var mod_icons: Array[Texture2D] = []
	for i in range(weapon.modifier_slot_count):
		var mod: Modifier = weapon.get_modifier_at(i)
		mod_icons.append(mod.icon_texture if mod else null)

	card.populate(weapon.icon_texture, weapon.name, stats, mod_icons)
	card.set_rarity(weapon.rarity)
```

- [ ] **Step 5: Add the modifier override**

In `src/drops/modifier_drop.gd`, after `_on_delivery_result` (end of file), add:

```gdscript

func populate_info_card(card: Card) -> void:
	if modifier == null:
		return
	var stats: Array[String] = [modifier.description]
	card.populate(modifier.icon_texture, modifier.name, stats)
	card.set_rarity(modifier.rarity)
```

- [ ] **Step 6: Run test to verify it passes**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_drop_info_card.gd
```
Expected: PASS (3 tests).

- [ ] **Step 7: Commit**

```bash
git add src/drops/drop.gd src/drops/weapon_drop.gd src/drops/modifier_drop.gd tests/unit/test_drop_info_card.gd
git commit -m "feat(drops): per-drop populate_info_card for weapon and modifier cards"
```

---

### Task 5: Generalize WeaponInfoPopup to any Drop

**Files:**
- Modify: `src/ui/weapon_info_popup.gd` (retype `WeaponDrop`→`Drop`; replace `_populate` body)

**Interfaces:**
- Consumes: `Drop.populate_info_card(card)` (Task 4), `Drop.get_viewport()`, `Drop.global_position`.
- Produces: `WeaponInfoPopup.show_for(drop: Drop)` and `update_position(drop: Drop, player)` accept any `Drop` and render via `drop.populate_info_card`. Consumed by Task 6.

This task has no new unit test (the popup is animation/viewport UI exercised manually in Task 6's verification and by existing suites). Correctness is enforced by keeping the delegation trivial.

- [ ] **Step 1: Retype the current-drop field**

In `src/ui/weapon_info_popup.gd`, change line 15:

```gdscript
var _current_drop: WeaponDrop = null
```
to:
```gdscript
var _current_drop: Drop = null
```

- [ ] **Step 2: Retype `show_for` and delegate population**

Replace `show_for` (lines 37-49) with:

```gdscript
func show_for(drop: Drop) -> void:
	if not is_instance_valid(drop):
		dismiss()
		return
	if _current_drop == drop and _shown and not _hiding:
		return
	_current_drop = drop
	_update_viewport_scale(drop)
	_populate(drop)
	_shown = true
	_hiding = false
	_card.visible = true
	_animate_show()
```

- [ ] **Step 3: Retype `_update_viewport_scale` and `update_position`**

Change the signature on line 52:
```gdscript
func _update_viewport_scale(drop: WeaponDrop) -> void:
```
to:
```gdscript
func _update_viewport_scale(drop: Drop) -> void:
```

Change the signature on line 77:
```gdscript
func update_position(drop: WeaponDrop, player: Node2D = null) -> void:
```
to:
```gdscript
func update_position(drop: Drop, player: Node2D = null) -> void:
```

- [ ] **Step 4: Replace `_populate` with delegation**

Replace the whole `_populate` function (lines 121-137) with:

```gdscript
func _populate(drop: Drop) -> void:
	drop.populate_info_card(_card)
```

- [ ] **Step 5: Verify the project still loads (script parses)**

Run the drop-card suite from Task 4 plus an import to confirm no parse/type errors in the popup:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_drop_info_card.gd
```
Expected: PASS, and no `SCRIPT ERROR` / parse errors mentioning `weapon_info_popup.gd` in the output.

- [ ] **Step 6: Commit**

```bash
git add src/ui/weapon_info_popup.gd
git commit -m "refactor(ui): make WeaponInfoPopup payload-agnostic via populate_info_card"
```

---

### Task 6: PickupContext shows the card for any info-capable drop

**Files:**
- Modify: `src/player/pickup_context.gd` (popup gate, lines 45-49)

**Interfaces:**
- Consumes: `Drop.populate_info_card` capability (Task 4), `WeaponInfoPopup.show_for`/`update_position`/`dismiss` (Task 5).
- Produces: nothing downstream; final integration point.

- [ ] **Step 1: Widen the popup gate**

In `src/player/pickup_context.gd`, replace lines 45-49:

```gdscript
		if _highlighted is WeaponDrop:
			_info_popup.show_for(_highlighted)
			_info_popup.update_position(_highlighted, _player)
		else:
			_info_popup.dismiss()
```
with:
```gdscript
		if _highlighted and _highlighted.has_method("populate_info_card"):
			_info_popup.show_for(_highlighted)
			_info_popup.update_position(_highlighted, _player)
		else:
			_info_popup.dismiss()
```

- [ ] **Step 2: Manual verification in-editor**

Launch the game and spawn a data-driven modifier drop via the console, then a weapon drop:
```
spawn modifier adrenaline
spawn weapon melee
```
(Use whatever the project's spawn console syntax is — see `src/console/commands/spawn_command.gd`.)

Confirm:
1. The `adrenaline` world drop shows a `wall.png` sprite (placeholder icon).
2. Standing next to it shows an info card with the modifier icon, name, and a wrapped description that fits inside the card.
3. The card is rarity-colored (Rare → the rare name color).
4. Standing next to the weapon drop still shows its card exactly as before (regression).
5. Walking away dismisses the card.

- [ ] **Step 3: Run the full unit suite (regression)**

Run the whole `tests/unit` directory:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit
```
Expected: PASS — no regressions, including `test_shop_modifier_drop.gd` and `test_weapon_registry_pools.gd`.

- [ ] **Step 4: Refresh the knowledge graph**

```bash
graphify update .
```

- [ ] **Step 5: Commit**

```bash
git add src/player/pickup_context.gd graphify-out
git commit -m "feat(pickup): show info card for modifier drops"
```

---

## Self-Review Notes

**Spec coverage:**
- Part 1 (placeholder icons) → Task 2.
- Part 2a (rarity on resource) → Task 1 + Task 2.
- Part 2b (per-drop populate) → Task 4.
- Part 2c (auto-size description label) → Task 3.
- Part 2d (generalize popup) → Task 5.
- Part 2e (PickupContext dispatch) → Task 6.

**Type consistency:** `populate_info_card(card: Card)` signature is identical across Tasks 4, 5, 6. `Modifier.rarity` (Task 1) is read in Tasks 2 and 4. `Card.populate` / `Card.set_rarity` signatures match `src/ui/card.gd`.

**Ordering:** Task 1 → 2 (rarity field before factory uses it); Task 4 before 5 (popup delegates to the method); Task 5 before 6 (gate calls the generalized `show_for`). Task 3 is independent but must land before the Task 6 manual check for the description to wrap.
