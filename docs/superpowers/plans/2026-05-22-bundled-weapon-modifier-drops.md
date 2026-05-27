# Bundled Weapon + Modifier Drops Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Roll a modifier at enemy spawn so it is active during combat and rides with the enemy's weapon when it drops on death. Regular enemies no longer drop standalone weapons/modifiers from random pools; boss is unchanged.

**Architecture:** Two new static helpers on `DropTable` (`roll_modifier_for_enemy`, `roll_should_drop_weapon`) own the dice. `Enemy._ready()` calls the modifier roll and attaches via `Weapon.add_modifier`. `Enemy._spawn_drops()` uses the weapon-drop roll to decide whether to spawn a `WeaponDrop`. `BossEnemy` overrides both hooks to keep prior behavior (no spawn-time modifier, always drop weapon, separate guaranteed RARE modifier).

**Tech Stack:** Godot 4 / GDScript, gdUnit4 for tests.

**Spec:** `docs/superpowers/specs/2026-05-22-bundled-weapon-modifier-drops-design.md`

---

## File Map

- Modify: `src/enemies/drop_table.gd` — gut `from_enemy_tier` to gold-only; add `roll_modifier_for_enemy` and `roll_should_drop_weapon` static helpers; keep `_resolve_modifier_pool` for boss; drop `_resolve_weapon_pool` and `WEAPON_DROP_SCENE`.
- Modify: `src/enemies/enemy.gd` — add `_roll_weapon_modifier()` virtual; call from `_ready()`; gate weapon drop in `_spawn_drops()` on `roll_should_drop_weapon`.
- Modify: `src/enemies/boss_enemy.gd` — override `_roll_weapon_modifier()` to no-op; override `_spawn_drops()` to always drop weapon while still calling `drop_table.resolve()`.
- Modify: `tests/unit/test_drop_table.gd` — remove the stale weapon-pool entry test; add tests for the two new helpers; fix entry-count assertions to match new gold-only output.

---

## Task 1: New DropTable helpers (`roll_modifier_for_enemy`, `roll_should_drop_weapon`)

**Files:**
- Modify: `src/enemies/drop_table.gd`
- Test: `tests/unit/test_drop_table.gd`

- [ ] **Step 1: Write failing tests for the two helpers**

Append to `tests/unit/test_drop_table.gd`:

```gdscript
func test_roll_should_drop_weapon_always_true_at_full_weight() -> void:
	# Force RNG so randf() returns 0.0; with EASY weight 0.3 the check passes.
	seed(1)
	var got_true: bool = false
	for i in 50:
		if _DropTable.roll_should_drop_weapon(_DropTable.EnemyTier.EASY):
			got_true = true
			break
	assert_that(got_true).is_true()


func test_roll_should_drop_weapon_can_return_false() -> void:
	seed(2)
	var got_false: bool = false
	for i in 50:
		if not _DropTable.roll_should_drop_weapon(_DropTable.EnemyTier.EASY):
			got_false = true
			break
	assert_that(got_false).is_true()


func test_roll_modifier_for_enemy_can_return_null() -> void:
	seed(3)
	var got_null: bool = false
	for i in 50:
		if _DropTable.roll_modifier_for_enemy(_DropTable.EnemyTier.EASY) == null:
			got_null = true
			break
	assert_that(got_null).is_true()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_drop_table.gd`
Expected: FAIL — `roll_should_drop_weapon` / `roll_modifier_for_enemy` are not defined.

- [ ] **Step 3: Add the helpers in `src/enemies/drop_table.gd`**

Insert after `resolve_item_tier` (around line 79):

```gdscript
static func roll_modifier_for_enemy(enemy_tier: int) -> Modifier:
	var chance: float = _TIER_MODIFIER_WEIGHT[enemy_tier]
	if randf() > chance:
		return null
	var tier := resolve_item_tier(enemy_tier)
	return WeaponRegistry.get_random_modifier(tier)


static func roll_should_drop_weapon(enemy_tier: int) -> bool:
	return randf() <= _TIER_WEAPON_WEIGHT[enemy_tier]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_drop_table.gd`
Expected: the three new tests PASS. Existing tests still fail (we fix those in Task 2).

- [ ] **Step 5: Commit**

```bash
git add src/enemies/drop_table.gd tests/unit/test_drop_table.gd
git commit -m "feat(drops): add roll_modifier_for_enemy and roll_should_drop_weapon helpers"
```

---

## Task 2: Gut `from_enemy_tier` to gold-only and prune dead code

**Files:**
- Modify: `src/enemies/drop_table.gd`
- Test: `tests/unit/test_drop_table.gd`

- [ ] **Step 1: Update tests to expect the new gold-only behavior**

Replace `test_from_enemy_tier_creates_table_for_easy`, `test_from_enemy_tier_creates_table_for_hard`, and remove `test_from_enemy_tier_weapon_entries_exist`. Final state of those tests:

```gdscript
func test_from_enemy_tier_creates_table_for_easy() -> void:
	var table := _DropTable.from_enemy_tier(_DropTable.EnemyTier.EASY)
	assert_that(table.entries.size()).is_equal(1)
	assert_that(table.entries[0].kind).is_equal(_DropTable.DropKind.GOLD)


func test_from_enemy_tier_creates_table_for_hard() -> void:
	var table := _DropTable.from_enemy_tier(_DropTable.EnemyTier.HARD)
	assert_that(table.entries.size()).is_equal(1)
	assert_that(table.entries[0].kind).is_equal(_DropTable.DropKind.GOLD)
```

Delete `test_from_enemy_tier_weapon_entries_exist` entirely.

- [ ] **Step 2: Run tests to verify the count tests now fail against current code**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_drop_table.gd`
Expected: the two updated tests FAIL (current `from_enemy_tier` still adds 3 entries by default).

- [ ] **Step 3: Strip weapon_pool / modifier_pool entries from `from_enemy_tier`**

Replace the body of `from_enemy_tier` in `src/enemies/drop_table.gd` (lines 60-68) with:

```gdscript
static func from_enemy_tier(tier: int, drops_gold: bool = true, _drops_weapon: bool = true, _drops_modifier: bool = true) -> DropTable:
	var table := DropTable.new()
	if drops_gold:
		table.add_entry(DropEntry.gold(1.0, _TIER_GOLD_MIN[tier], _TIER_GOLD_MAX[tier], _TIER_GOLD_PER_DROP[tier]))
	return table
```

Rename the unused params with a leading underscore so the signature still accepts the boss's `(tier, true, true, true)` call.

- [ ] **Step 4: Remove dead `_resolve_weapon_pool` and the `WEAPON_DROP_SCENE` constant**

In `src/enemies/drop_table.gd`:

- Delete line 39 (`const WEAPON_DROP_SCENE := preload("res://scenes/weapon_drop.tscn")`).
- Delete the `_resolve_weapon_pool` function (lines 109-118).
- In `resolve()`'s `match` block, remove the `DropKind.WEAPON_POOL: _resolve_weapon_pool(...)` arm so the switch only has `GOLD`, `MODIFIER_POOL`, `SCENE`.

Keep `DropKind.WEAPON_POOL` in the enum (avoid renumbering — bosses don't use it, but `DropEntry.weapon_pool` factory remains for any external callers).

- [ ] **Step 5: Run all drop_table tests**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_drop_table.gd`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add src/enemies/drop_table.gd tests/unit/test_drop_table.gd
git commit -m "refactor(drops): from_enemy_tier returns gold-only; drop weapon_pool resolver"
```

---

## Task 3: Enemy rolls modifier on spawn, gates weapon drop on death

**Files:**
- Modify: `src/enemies/enemy.gd`

This task has no unit test — exercised manually and via Task 5 integration. Enemy depends on `_ready()`, scene tree, `WeaponRegistry` autoload, etc., which gdUnit can't easily stage without a scene.

- [ ] **Step 1: Add `_roll_weapon_modifier()` and call it from `_ready()`**

In `src/enemies/enemy.gd`, append this method (place near `_setup_weapon_visual`, around line 485):

```gdscript
func _roll_weapon_modifier() -> void:
	if weapon == null:
		return
	var modifier := DropTable.roll_modifier_for_enemy(enemy_tier)
	if modifier == null:
		return
	var slot := weapon.find_empty_modifier_slot()
	if slot >= 0:
		weapon.add_modifier(slot, modifier)
```

Then in `_ready()`, immediately after the existing `_setup_weapon_visual.call_deferred()` line (line 107), add:

```gdscript
	_roll_weapon_modifier()
```

- [ ] **Step 2: Replace unconditional weapon drop with a tier-gated roll**

Replace the body of `_spawn_drops()` (currently lines 292-300) with:

```gdscript
func _spawn_drops() -> void:
	if drop_table:
		drop_table.resolve(global_position, get_parent())
	if weapon and DropTable.roll_should_drop_weapon(enemy_tier):
		_spawn_weapon_drop()


func _spawn_weapon_drop() -> void:
	var drop_scene := preload("res://scenes/weapon_drop.tscn")
	var drop: Node = drop_scene.instantiate()
	drop.weapon = weapon
	drop.global_position = global_position + Vector2(randf_range(-8, 8), randf_range(-8, 8))
	get_parent().add_child(drop)
```

Extract `_spawn_weapon_drop` as a separate method so `BossEnemy` (Task 4) can reuse it without copy-pasting the preload.

- [ ] **Step 3: Run the project to smoke-check it boots**

Run: `godot --headless --path . --quit`
Expected: clean exit, no parse errors.

- [ ] **Step 4: Commit**

```bash
git add src/enemies/enemy.gd
git commit -m "feat(enemies): roll modifier on spawn; gate weapon drop on tier weight"
```

---

## Task 4: Boss overrides — plain weapon, always drops it

**Files:**
- Modify: `src/enemies/boss_enemy.gd`

- [ ] **Step 1: Override `_roll_weapon_modifier()` to no-op and `_spawn_drops()` to force the weapon drop**

In `src/enemies/boss_enemy.gd`, append:

```gdscript
func _roll_weapon_modifier() -> void:
	pass


func _spawn_drops() -> void:
	if drop_table:
		drop_table.resolve(global_position, get_parent())
	if weapon:
		_spawn_weapon_drop()
```

Note: `_spawn_weapon_drop` is the protected helper added on `Enemy` in Task 3. The boss already adds an explicit `DropEntry.modifier_pool(1.0, RARE, 1, 1)` in `_setup_drop_table()` — that line stays as-is.

- [ ] **Step 2: Boot-check**

Run: `godot --headless --path . --quit`
Expected: clean exit.

- [ ] **Step 3: Commit**

```bash
git add src/enemies/boss_enemy.gd
git commit -m "feat(boss): keep plain weapon and unconditional weapon drop"
```

---

## Task 5: Manual verification

**Files:** none

These checks confirm the runtime behavior the spec promises. Run them in the editor, not headless.

- [ ] **Step 1: Modifier active during combat**

Open the project in Godot editor. Use the in-game console to spawn ~10 melee enemies (`spawn melee_enemy` or similar — see `src/console/commands/spawn_command.gd`). Observe at least one enemy's weapon visibly carrying a modifier effect (e.g. lava emitter trails coming from the enemy as it attacks). Expected: ~10% of enemies with EASY/NORMAL tier should show an effect; spawn more if needed to confirm the roll fires.

- [ ] **Step 2: Drop hint shows modifier icon**

Kill a modded enemy. When the `WeaponDrop` appears, walk near it. The info popup card should render a modifier icon in one of the modifier slots.

- [ ] **Step 3: Pickup preserves modifier**

Press the interact key on a modded weapon drop. After accepting it through `WeaponDelivery`, fire the weapon and confirm the modifier's effect now fires on the player.

- [ ] **Step 4: No standalone modifier drops from regulars**

Kill ~20 regular enemies. Confirm no `ModifierDrop` ever spawns (gold + occasionally a weapon should be the only outputs).

- [ ] **Step 5: Boss behavior unchanged**

Spawn and kill the boss. Confirm:
- A `WeaponDrop` always spawns and the boss weapon has no modifier in its card preview.
- A separate `ModifierDrop` (RARE) also spawns.

- [ ] **Step 6: Commit a notes file only if regressions are found**

If everything passes, no commit. If anything regresses, file a follow-up note in the spec or open an issue rather than patching blindly.
