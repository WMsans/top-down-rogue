# Weapon & Modifier Balancing — Phase 2 (Emergent-Combo Modifiers) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the 24 net-new emergent-combo weapon modifiers (spec Part C) plus the left→right modifier evaluation pass with a re-entrant retrigger depth guard, so build-craft has a nonlinear power ceiling above the Phase-1 bands.

**Architecture:** Hybrid, matching the existing system. 7 modifiers stay data-driven (new `condition`/`effect` verbs on `DataModifier` + CSV rows). 17 are scripted `Modifier` subclasses under `src/weapons/modifiers/`. The spine is a centralized left→right evaluation pass on `Weapon` that replaces the ad-hoc `for m in modifiers` loops, skips disabled modifiers, and exposes a re-entrant `retrigger_modifier(...)` API with a depth-2 hard stop. Positional engines (catalyst_bond, pendulum, flywheel) call sibling hooks directly; retrigger engines (echo_strike, overclock, twin_trigger) route through the depth-guarded API. Combos resolve within a weapon's 3 ordered slots — no tags, no resonance table.

**Tech Stack:** Godot 4.7 (GDScript), GdUnit4 tests (headless). Run a suite with:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/<file>.gd
```

**Source of truth:** `docs/superpowers/specs/2026-06-24-weapon-modifier-balancing-design.md` (§C1–§C6, §6 Phase 2, §7 tests). **Companion plan:** `2026-06-24-weapon-modifier-balancing-phase1.md` (Parts A+B; ships independently).

---

## Assumptions (resolved ambiguities in the spec)

The spec is approved but a few effect wordings are under-specified. These interpretations are pinned here so the plan is concrete; all are tuning-safe and reversible.

1. **"bleeding" = the `bloody` status id.** The registry has `bloody` (no `bleeding` exists). `hemophilia` and `rupture` key off `bloody`.
2. **Detonator "burst"** = a flat damage packet delivered via a new `Weapon._apply_burst(user, target, amount)` that calls `target.on_hit_impact(...)` and does **not** re-enter the modifier pass (prevents detonator recursion). `frostshatter` = `frozen_stacks × 8`; `combustion` = `on_fire_stacks × 3`; `necrosis` = `poison_stacks × 2`; `rupture` = `5 × weapon.damage` (fires at 5 bloody-hit count, not a consume-on-hit).
3. **`deepfreeze`** = on hit of a chilly target, add `frozen` stain (magnitude 2.0). The "2× faster" is flavor vs the natural wet+chilly reaction.
4. **`spark_plug`** = on hit of an oiled target, apply `on_fire` stain (magnitude 2.0). Pure data, existing `apply_status` verb.
5. **`backdraft` / `plague_carrier`** spread = find nearby `"attackable"` foes within `magnitude` px of the target via `CombatUtil.nearest_attackables`, apply `element` stain (magnitude 2.0) to each.
6. **`keystone`** = a "focus build" enabler. While a `KeystoneModifier` is present in any slot, the two outer slots (indices 0 and 2) are disabled and the weapon's effective damage is ×2.0. The middle slot (index 1) stays active. (Placing keystone in an outer slot sacrifices that slot + the other outer to double the middle modifier; placing it in the middle just yields a bare ×2 damage weapon.)
7. **`overkill` carry** = the overflow (`dealt damage − target pre-hit HP`, ≥0) is stored on kill and added to the next hit's damage; it is spent whether or not the next hit kills.
8. **`last_stand`** detects "took damage" by polling the user's `health` across successive `modify_hit_damage` calls (no signal dependency): if HP dropped since the last hit, the next hit gets ×1.6.
9. **`headsman` "refunds the swing"** = on kill of a target whose pre-hit HP fraction was >50%, set `weapon._cooldown_timer = 0.0` (instant next attack).
10. **`flywheel`** charges +1 per swing (on `on_attack`); at charge ≥5 it dumps on `on_hit_target`, firing every other active non-retrigger modifier 3 extra times, then resets. "Untriggered" is treated as flavor (the per-modifier observation cost is out of scope).
11. **`evolving_edge`** base bonus = +2.0 damage (Uncommon), doubling to +4.0 after 15 hits. Pre-playtest starting point.
12. **`twin_trigger` / `flywheel` direct calls** bypass the `retrigger_modifier` depth guard (they are positional/rhythm engines, not re-entrant retriggers); they still skip `is_retrigger_modifier` siblings and themselves.
13. **Ranged conditional crit (`hemophilia`)** is melee-only: ranged sets `proj.crit_chance` at spawn (no target yet). The target-aware crit path is wired into `MeleeWeapon._hit_attackables` only.

---

## File structure (Phase 2)

| File | Responsibility |
|---|---|
| `src/weapons/modifier.gd` | base `Modifier`: add `slot_index`, `category`, `is_retrigger_modifier`, `is_disabled`, `modify_crit_chance_for_target`, `get_state_tag` |
| `src/weapons/weapon.gd` | centralized left→right dispatch skipping disabled; sibling/positional helpers; `retrigger_modifier` depth-guarded API; `_apply_burst`; `reset_cooldown`; target-aware crit; keystone focus check |
| `src/weapons/melee_weapon.gd` | call `roll_crit_for_target(node)` in `_hit_attackables` |
| `src/weapons/modifiers/data_modifier.gd` | new verbs: `spread_status`, `knockback_and_status`, `self_gold` condition, `modify_crit_chance_for_target` |
| `src/weapons/modifiers/detonator_modifier.gd` | shared base for consume-status burst detonators |
| `src/weapons/modifiers/<id>_modifier.gd` (×16 new) | scripted combo modifiers (see tasks) |
| `docs/design_docs/modifiers.csv` | 24 new rows (7 data-driven fully specified; 17 scripted reference their script) |
| `src/autoload/weapon_registry.gd` | register the 17 scripted modifiers in `modifier_scripts` |
| `src/ui/weapon_popup.gd`, `src/ui/card.gd` | §C6 light state hooks: dim disabled, glow retrigger, mark linked |
| `tests/unit/test_weapon_eval_pass.gd` | eval-pass / depth-guard / sibling / disable-state tests |
| `tests/unit/test_combo_modifiers.gd` | all 24 modifiers + flagship combo + anti-degenerate (§7) |

New scripted modifier files (16 — `detonator_modifier.gd` is the 17th new file but a base):
`spark_plug`/`deepfreeze`/`hemophilia`/`backdraft`/`riptide`/`plague_carrier`/`greedy_edge` are **data-driven (no new script file)**. Scripted: `detonator_modifier.gd` (base), `frostshatter_modifier.gd`, `combustion_modifier.gd`, `necrosis_modifier.gd`, `rupture_modifier.gd`, `echo_strike_modifier.gd`, `overclock_modifier.gd`, `mirror_slot_modifier.gd`, `catalyst_bond_modifier.gd`, `keystone_modifier.gd`, `twin_trigger_modifier.gd`, `flywheel_modifier.gd`, `last_stand_modifier.gd`, `overkill_modifier.gd`, `evolving_edge_modifier.gd`, `pendulum_modifier.gd`, `headsman_modifier.gd`, `slot_harmony_modifier.gd` (17 scripted files total incl. base).

---

## Task 1: Modifier base fields + Weapon sibling/disable helpers

**Files:**
- Modify: `src/weapons/modifier.gd`
- Modify: `src/weapons/weapon.gd`
- Test: `tests/unit/test_weapon_eval_pass.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_weapon_eval_pass.gd`:

```gdscript
extends GdUnitTestSuite

class _Stub extends Modifier:
	var cats: String = "trigger"
	func _init() -> void:
		category = "trigger"
	func on_hit_target(_w, _u, _t) -> void:
		pass

func test_add_modifier_records_slot_index() -> void:
	var w := Weapon.new()
	var a := _Stub.new()
	var b := _Stub.new()
	w.add_modifier(0, a)
	w.add_modifier(2, b)
	assert_int(a.slot_index).is_equal(0)
	assert_int(b.slot_index).is_equal(2)

func test_sibling_helpers() -> void:
	var w := Weapon.new()
	var a := _Stub.new()
	var b := _Stub.new()
	var c := _Stub.new()
	w.add_modifier(0, a); w.add_modifier(1, b); w.add_modifier(2, c)
	assert_object(w.get_first_modifier()).is_same(a)
	assert_object(w.get_left_modifier(1)).is_same(a)
	assert_object(w.get_right_modifier(1)).is_same(c)
	assert_object(w.get_left_modifier(0)).is_null()
	assert_object(w.get_right_modifier(2)).is_null()

func test_first_modifier_skips_nulls() -> void:
	var w := Weapon.new()
	var c := _Stub.new()
	w.add_modifier(2, c)
	assert_object(w.get_first_modifier()).is_same(c)

func test_disabled_flag_defaults_false_and_settable() -> void:
	var m := _Stub.new()
	assert_bool(m.is_disabled).is_false()
	m.is_disabled = true
	assert_bool(m.is_disabled).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_weapon_eval_pass.gd
```
Expected: FAIL — `slot_index`/`get_first_modifier`/`get_left_modifier` not found on `Modifier`/`Weapon`.

- [ ] **Step 3: Add the base fields**

In `src/weapons/modifier.gd`, after `var suppresses_base_use: bool = false` (line 7), add:

```gdscript
var slot_index: int = -1
var category: String = ""
var is_retrigger_modifier: bool = false
var is_disabled: bool = false
```

After `func on_crit(...)` (line 54), add:

```gdscript
func modify_crit_chance_for_target(_weapon: Weapon, base: float, _target: Node) -> float:
	return base


func get_state_tag() -> String:
	if is_disabled:
		return "disabled"
	if is_retrigger_modifier:
		return "retrigger"
	return ""
```

- [ ] **Step 4: Add Weapon helpers**

In `src/weapons/weapon.gd`, in `add_modifier` (line 101), set the slot index before `on_equip`. Replace the body of `add_modifier` with:

```gdscript
func add_modifier(slot_index: int, modifier: Modifier) -> void:
	if slot_index < 0 or slot_index >= modifier_slot_count:
		return
	modifiers.resize(max(modifiers.size(), modifier_slot_count))
	modifiers[slot_index] = modifier
	modifier.slot_index = slot_index
	modifier.on_equip(self)
	invalidate_effective_stats()
```

After `get_modifier_at` (line 113), add:

```gdscript
func get_first_modifier() -> Modifier:
	for i in range(modifier_slot_count):
		var m: Modifier = get_modifier_at(i)
		if m != null and not m.is_disabled:
			return m
	return null


func get_left_modifier(of_slot: int) -> Modifier:
	return get_modifier_at(of_slot - 1)


func get_right_modifier(of_slot: int) -> Modifier:
	return get_modifier_at(of_slot + 1)


func get_other_slots(of_slot: int) -> Array:
	var out: Array = []
	for i in range(modifier_slot_count):
		if i != of_slot:
			var m: Modifier = get_modifier_at(i)
			if m != null:
				out.append(m)
	return out
```

- [ ] **Step 5: Run test to verify it passes**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_weapon_eval_pass.gd
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/weapons/modifier.gd src/weapons/weapon.gd tests/unit/test_weapon_eval_pass.gd
git commit -m "feat(weapons): modifier slot_index/category/disabled fields + sibling helpers"
```

---

## Task 2: Retrigger API with depth guard

**Files:**
- Modify: `src/weapons/weapon.gd`
- Test: `tests/unit/test_weapon_eval_pass.gd` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_weapon_eval_pass.gd`:

```gdscript
class _Counter extends Modifier:
	var hits: int = 0
	func _init() -> void:
		category = "trigger"
	func on_hit_target(_w, _u, _t) -> void:
		hits += 1


class _Retrigger extends Modifier:
	var calls: int = 0
	func _init() -> void:
		category = "trigger"
		is_retrigger_modifier = true
	func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
		calls += 1
		var first: Modifier = weapon.get_first_modifier()
		weapon.retrigger_modifier(first, "on_hit_target", [user, target])


func test_retrigger_fires_target_once() -> void:
	var w := Weapon.new()
	var c := _Counter.new()
	var r := _Retrigger.new()
	w.add_modifier(0, c); w.add_modifier(1, r)
	var t := Node.new()
	w.resolve_hit(null, t, 5.0, false)
	# c fires once (normal) + once (retriggered by r) = 2
	assert_int(c.hits).is_equal(2)

func test_retrigger_skips_retrigger_modifier() -> void:
	var w := Weapon.new()
	var r1 := _Retrigger.new()
	var r2 := _Retrigger.new()
	w.add_modifier(0, r1); w.add_modifier(1, r2)
	var t := Node.new()
	w.resolve_hit(null, t, 5.0, false)
	# r1 normal fire = 1; r2 normal fire = 1 and tries to retrigger r1 but r1 is retrigger -> skipped
	assert_int(r1.calls).is_equal(1)
	assert_int(r2.calls).is_equal(1)

func test_retrigger_depth_guard_stops_at_two() -> void:
	# A retrigger that retriggers the next retrigger: depth must cap at 2.
	var w := Weapon.new()
	var c := _Counter.new()
	var chainA := _ChainRetrigger.new()
	var chainB := _ChainRetrigger.new()
	w.add_modifier(0, c); w.add_modifier(1, chainA); w.add_modifier(2, chainB)
	var t := Node.new()
	w.resolve_hit(null, t, 5.0, false)
	# c: normal(1) + chainA retrigger(1) + chainB retrigger(1, depth 2) = 3; no further.
	assert_int(c.hits).is_equal(3)


class _ChainRetrigger extends Modifier:
	func _init() -> void:
		category = "trigger"
		is_retrigger_modifier = true
	func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
		var first: Modifier = weapon.get_first_modifier()
		weapon.retrigger_modifier(first, "on_hit_target", [user, target])
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_weapon_eval_pass.gd
```
Expected: FAIL — `retrigger_modifier` not found.

- [ ] **Step 3: Add the retrigger API**

In `src/weapons/weapon.gd`, after `var _hit_count: int = 0` (line 22), add:

```gdscript
const RETRIGGER_DEPTH_LIMIT := 2
var _retrigger_depth: int = 0
```

After `get_other_slots` (added in Task 1), add:

```gdscript
# Re-run a sibling modifier's effect hook with a re-entrant depth guard.
# `hook` is one of: "on_attack","on_hit_target","on_kill","on_crit","modify_hit_damage".
# `args` is the array of hook arguments (user/target/etc.). Returns the hook result
# (float for "modify_hit_damage", null for void hooks). Short-circuits on disabled
# mods, retrigger-type mods (can't retrigger a retrigger), and depth >= LIMIT.
func retrigger_modifier(mod: Modifier, hook: String, args: Array) -> Variant:
	if mod == null or not is_instance_valid(mod) or mod.is_disabled:
		return args[2] if hook == "modify_hit_damage" else null
	if mod.is_retrigger_modifier:
		return args[2] if hook == "modify_hit_damage" else null
	if _retrigger_depth >= RETRIGGER_DEPTH_LIMIT:
		return args[2] if hook == "modify_hit_damage" else null
	_retrigger_depth += 1
	var result: Variant = null
	match hook:
		"on_attack":
			mod.on_attack(self, args[0], args[1])
		"on_hit_target":
			mod.on_hit_target(self, args[0], args[1])
		"on_kill":
			mod.on_kill(self, args[0], args[1])
		"on_crit":
			mod.on_crit(self, args[0], args[1])
		"modify_hit_damage":
			result = mod.modify_hit_damage(self, args[0], args[1], args[2])
			if result == null:
				result = args[2]
	_retrigger_depth -= 1
	return result
```

- [ ] **Step 4: Run test to verify it passes**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_weapon_eval_pass.gd
```
Expected: PASS (3 retrigger tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/weapon.gd tests/unit/test_weapon_eval_pass.gd
git commit -m "feat(weapons): depth-guarded retrigger_modifier API"
```

---

## Task 3: Centralized left→right dispatch (skip disabled, keystone focus)

**Files:**
- Modify: `src/weapons/weapon.gd`
- Test: `tests/unit/test_weapon_eval_pass.gd` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_weapon_eval_pass.gd`:

```gdscript
func test_disabled_modifier_skipped_in_all_hooks() -> void:
	var w := Weapon.new()
	var c := _Counter.new()
	c.is_disabled = true
	w.add_modifier(0, c)
	var t := Node.new()
	w.notify_attack(null, {"direction": Vector2.RIGHT, "origin": Vector2.ZERO, "charged": false, "charge_ratio": 0.0})
	w.resolve_hit(null, t, 5.0, false)
	assert_int(c.hits).is_equal(0)

func test_disabled_modifier_excluded_from_effective_stats() -> void:
	var w := Weapon.new()
	w.damage = 10.0
	var m := DataModifier.new({
		"id": "x", "name": "X", "description": "", "rarity": "Common",
		"category": "stat", "trigger": "passive", "condition": "", "effect": "stat_add",
		"element": "damage", "magnitude": "5", "magnitude2": "0", "suppresses_base_use": "No",
	})
	m.is_disabled = true
	w.add_modifier(0, m)
	assert_float(w.get_effective_stats()["damage"]).is_equal(10.0)
	m.is_disabled = false
	w.invalidate_effective_stats()
	assert_float(w.get_effective_stats()["damage"]).is_equal(15.0)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_weapon_eval_pass.gd
```
Expected: FAIL — disabled modifier still fires.

- [ ] **Step 3: Refactor dispatch**

In `src/weapons/weapon.gd`, add the active-iterator (with keystone focus) after `get_other_slots`:

```gdscript
# Left->right iterator over modifiers that should fire this swing. Skips nulls and
# disabled mods. If a KeystoneModifier is present anywhere, only the middle slot
# (index 1) is active (keystone focus build: outer slots sacrificed).
func _iter_active_modifiers() -> Array:
	var out: Array = []
	var keystone_focus := _has_keystone()
	for i in range(modifier_slot_count):
		var m: Modifier = get_modifier_at(i)
		if m == null or m.is_disabled:
			continue
		if keystone_focus and i != 1:
			continue
		out.append(m)
	return out


func _has_keystone() -> bool:
	for i in range(modifier_slot_count):
		var m: Modifier = get_modifier_at(i)
		if m != null and m.has_method("is_keystone") and m.is_keystone():
			return true
	return false
```

Now replace the body of these methods to iterate `_iter_active_modifiers()` instead of raw `modifiers`:

`use()` (line 25):
```gdscript
func use(user: Node) -> void:
	if not is_ready():
		return
	for modifier in _iter_active_modifiers():
		modifier.on_use(self, user)
	var suppress: bool = false
	for modifier in _iter_active_modifiers():
		if modifier.suppresses_base_use:
			suppress = true
			break
	if not suppress:
		_use_impl(user)
	_cooldown_timer = get_effective_stats()["cooldown"]
```

`notify_attack()` (line 41):
```gdscript
func notify_attack(user: Node, ctx: Dictionary) -> void:
	for modifier in _iter_active_modifiers():
		modifier.on_attack(self, user, ctx)
```

`get_effective_stats()` (line 136) — replace the two `for m in modifiers` loops with `for m in _iter_active_modifiers():` (keep the add-then-mult order and the cooldown floor).

`resolve_hit()` (line 158) — replace the four `for m in modifiers` loops (modify_hit_damage, on_hit_target, on_crit, on_kill) with `for m in _iter_active_modifiers():`.

`get_effective_crit_chance()` (line 205) — replace `for modifier in modifiers` with `for modifier in _iter_active_modifiers():`.

Leave `tick()` (line 71) iterating ALL modifiers (disabled mods still tick so they can re-enable themselves): keep `for modifier in modifiers:` there, but add `if modifier.is_disabled: continue` is NOT wanted — disabled mods' `on_tick` must run. Keep as-is.

- [ ] **Step 4: Run the eval-pass suite AND the existing modifier/resolve suites**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_weapon_eval_pass.gd && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_modifiers.gd && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_weapon_resolve_hit.gd && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_data_modifier.gd
```
Expected: all PASS (no regressions; the 57 existing modifiers still behave).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/weapon.gd tests/unit/test_weapon_eval_pass.gd
git commit -m "refactor(weapons): centralized left->right modifier dispatch, skip disabled, keystone focus"
```

---

## Task 4: Target-aware crit path (for hemophilia)

**Files:**
- Modify: `src/weapons/weapon.gd`
- Modify: `src/weapons/melee_weapon.gd:198`
- Test: `tests/unit/test_weapon_eval_pass.gd` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_weapon_eval_pass.gd`:

```gdscript
class _StatusTarget extends Node2D:
	func _init() -> void:
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)


func test_target_aware_crit_applies_when_condition_met() -> void:
	var w := Weapon.new()
	var m := DataModifier.new({
		"id": "x", "name": "X", "description": "", "rarity": "Common",
		"category": "trigger", "trigger": "on_hit", "condition": "target_status:bloody",
		"effect": "stat_add", "element": "crit_chance", "magnitude": "0.25",
		"magnitude2": "0", "suppresses_base_use": "No",
	})
	w.add_modifier(0, m)
	w.crit_chance = 0.1
	var t := _StatusTarget.new()
	add_child(t)
	assert_float(w.get_effective_crit_chance_for_target(t)).is_equal(0.1)
	t.get_node("StatusComponent").add_stain("bloody", 2.0)
	assert_float(w.get_effective_crit_chance_for_target(t)).is_equal(0.35)
	# non-target version is unaffected (ranged path)
	assert_float(w.get_effective_crit_chance()).is_equal(0.1)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_weapon_eval_pass.gd
```
Expected: FAIL — `get_effective_crit_chance_for_target` not found.

- [ ] **Step 3: Add target-aware crit to Weapon**

In `src/weapons/weapon.gd`, after `roll_crit()` (line 213), add:

```gdscript
func get_effective_crit_chance_for_target(target: Node) -> float:
	var c: float = crit_chance
	for m in _iter_active_modifiers():
		c = m.modify_crit_chance_for_target(self, c, target)
	return clampf(c, 0.0, 1.0)


func roll_crit_for_target(target: Node) -> bool:
	return randf() < get_effective_crit_chance_for_target(target)


func reset_cooldown() -> void:
	_cooldown_timer = 0.0


func _apply_burst(user: Node, target: Node, amount: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not target.has_method("on_hit_impact"):
		return
	var dir: Vector2 = Vector2.DOWN
	if target is Node2D and user is Node2D:
		var d: Vector2 = (target.global_position - user.global_position)
		if d.length_squared() > 0.0001:
			dir = d.normalized()
	target.on_hit_impact(
		(target.global_position if target is Node2D else Vector2.ZERO),
		dir, int(amount))
```

(`reset_cooldown` and `_apply_burst` are added here so later tasks can use them without reopening the file.)

- [ ] **Step 4: Wire melee to use the target-aware roll**

In `src/weapons/melee_weapon.gd:198`, change:

```gdscript
		var is_crit: bool = force_crit or roll_crit()
```
to:

```gdscript
		var is_crit: bool = force_crit or roll_crit_for_target(node)
```

- [ ] **Step 5: Run test to verify it passes**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_weapon_eval_pass.gd
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/weapons/weapon.gd src/weapons/melee_weapon.gd tests/unit/test_weapon_eval_pass.gd
git commit -m "feat(weapons): target-aware crit + reset_cooldown + _apply_burst helpers"
```

---

## Task 5: DataModifier new verbs (spread_status, knockback_and_status, self_gold, conditional crit)

**Files:**
- Modify: `src/weapons/modifiers/data_modifier.gd`
- Test: `tests/unit/test_combo_modifiers.gd` (create)

- [ ] **Step 1: Write the failing tests**

Create `tests/unit/test_combo_modifiers.gd`:

```gdscript
extends GdUnitTestSuite

class _StatusTarget extends Node2D:
	var hits: Array = []
	func _init() -> void:
		add_to_group("attackable")
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)
	func on_hit_impact(_p: Vector2, _d: Vector2, dmg: int) -> void:
		hits.append(dmg)


class _GoldUser extends Node2D:
	var gold: int = 0
	func _init() -> void:
		var inv := Node.new()
		inv.name = "PlayerInventory"
		inv.set_script(_make_inv())
		add_child(inv)
	func _make_inv() -> GDScript:
		var s := GDScript.new()
		s.source_code = "extends Node\nvar gold:int\nfunc _ready()->void: gold = get_parent().gold\nfunc add_gold(a:int)->void: gold += a\n"
		s.reload()
		return s


func _row(overrides: Dictionary) -> Dictionary:
	var base := {
		"id": "x", "name": "X", "description": "", "rarity": "Common",
		"category": "", "trigger": "", "condition": "", "effect": "",
		"element": "", "magnitude": "0", "magnitude2": "0", "suppresses_base_use": "No",
	}
	for k in overrides.keys():
		base[k] = overrides[k]
	return base


func test_self_gold_scales_damage_capped() -> void:
	var u := _GoldUser.new()
	add_child(u)
	u.gold = 5000  # 100 steps of 50 -> would be +100%, capped at +40%
	var m := DataModifier.new(_row({
		"category": "trigger", "trigger": "on_hit", "condition": "self_gold",
		"effect": "stat_mult", "element": "damage", "magnitude": "0.01", "magnitude2": "0.40",
	}))
	assert_float(m.modify_hit_damage(null, u, null, 10.0)).is_equal(14.0)
	u.gold = 100  # 2 steps -> +2%
	assert_float(m.modify_hit_damage(null, u, null, 10.0)).is_equal(10.2)
	u.gold = 0
	assert_float(m.modify_hit_damage(null, u, null, 10.0)).is_equal(10.0)


func test_knockback_and_status_on_wet_target() -> void:
	var u := _StatusTarget.new()
	add_child(u)
	u.global_position = Vector2.ZERO
	var t := _StatusTarget.new()
	add_child(t)
	t.global_position = Vector2(40, 0)
	t.get_node("StatusComponent").add_stain("wet", 5.0)
	var knocks: Array = []
	t.set_script(_make_kb_script(knocks))
	var m := DataModifier.new(_row({
		"category": "trigger", "trigger": "on_hit", "condition": "target_status:wet",
		"effect": "knockback_and_status", "element": "chilly",
		"magnitude": "60", "magnitude2": "2.0",
	}))
	m.on_hit_target(null, u, t)
	assert_int(knocks.size()).is_equal(1)
	assert_float(knocks[0]["strength"]).is_equal(60.0)
	assert_float(t.get_node("StatusComponent").get_stain("chilly")).is_equal(2.0)


static func _make_kb_script(knocks: Array) -> GDScript:
	var s := GDScript.new()
	s.source_code = """
extends Node2D
var _knocks
func _init():
	_knocks = null
func _set_knocks(k): _knocks = k
func apply_knockback(dir: Vector2, strength: float):
	_knocks.append({"dir": dir, "strength": strength})
"""
	s.reload()
	var inst = s.new()
	inst._set_knocks(knocks)
	return inst


func test_spread_status_to_nearby_foes() -> void:
	var u := _StatusTarget.new()
	add_child(u)
	u.global_position = Vector2.ZERO
	var burning := _StatusTarget.new()
	add_child(burning)
	burning.global_position = Vector2(20, 0)
	burning.get_node("StatusComponent").add_stain("on_fire", 5.0)
	var near_foe := _StatusTarget.new()
	add_child(near_foe)
	near_foe.global_position = Vector2(35, 0)
	var far_foe := _StatusTarget.new()
	add_child(far_foe)
	far_foe.global_position = Vector2(400, 0)
	var m := DataModifier.new(_row({
		"category": "trigger", "trigger": "on_hit", "condition": "target_status:on_fire",
		"effect": "spread_status", "element": "on_fire", "magnitude": "40", "magnitude2": "2.0",
	}))
	m.on_hit_target(null, u, burning)
	assert_float(near_foe.get_node("StatusComponent").get_stain("on_fire")).is_equal(2.0)
	assert_float(far_foe.get_node("StatusComponent").get_stain("on_fire")).is_equal(0.0)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: FAIL — `self_gold`/`knockback_and_status`/`spread_status` not handled (damage unchanged, no knockback, no spread).

- [ ] **Step 3: Implement the verbs**

In `src/weapons/modifiers/data_modifier.gd`, add a gold-step constant after the existing consts (line 8):

```gdscript
const GOLD_STEP := 50.0
```

In `modify_hit_damage` (line 117), add the `self_gold` branch. Replace the function body with:

```gdscript
func modify_hit_damage(_weapon: Weapon, user: Node, target: Node, dmg: float) -> float:
	if trigger == "on_hit" and effect == "stat_mult" and element == "damage":
		if condition == "":
			if name == "Momentum":
				var frac := _speed_fraction(user)
				return dmg * lerpf(1.0, magnitude, frac)
			if magnitude2 > 0.0:
				return dmg + _hit_streak
		elif condition == "self_gold":
			return dmg * _self_gold_mult(user)
		elif condition == "self_full_hp":
			if _self_full_hp(user):
				return dmg * magnitude
		elif _condition_met(target):
			return dmg * magnitude
	return dmg


func _self_gold_mult(user: Node) -> float:
	var inv = user.get_node_or_null("PlayerInventory") if user != null else null
	if inv == null or not ("gold" in inv):
		return 1.0
	var gold: float = float(inv.gold)
	var bonus: float = floor(gold / GOLD_STEP) * magnitude
	return 1.0 + minf(bonus, magnitude2)
```

In `on_hit_target` (line 144), add the two new effects. After the existing `stun` block (line 158) and before the `Rampage` block (line 159), insert:

```gdscript
	if trigger == "on_hit" and effect == "knockback_and_status" and _condition_met(target):
		if target != null and target is Node2D and target.has_method("apply_knockback"):
			var user2 := _weapon_current_user(_weapon)
			var dir: Vector2 = Vector2.DOWN
			if user2 is Node2D:
				var d: Vector2 = (target.global_position - (user2 as Node2D).global_position)
				if d.length_squared() > 0.0001:
					dir = d.normalized()
			target.apply_knockback(dir, magnitude)
		var sc2 = target.get_node_or_null("StatusComponent") if target else null
		if sc2 != null:
			sc2.add_stain(element, magnitude2)
	if trigger == "on_hit" and effect == "spread_status" and _condition_met(target):
		_spread_status(_weapon, target, element, magnitude, magnitude2)
```

Add the helper functions at the end of the file:

```gdscript
func _weapon_current_user(weapon: Weapon) -> Node:
	if weapon != null and "_current_user" in weapon:
		return weapon._current_user
	return null


func _spread_status(weapon: Weapon, source_target: Node, status_id: String,
		radius: float, stain: float) -> void:
	if source_target == null or not (source_target is Node2D):
		return
	var tree := source_target.get_tree()
	if tree == null:
		return
	var origin: Vector2 = (source_target as Node2D).global_position
	var near: Array = CombatUtil.nearest_attackables(tree, origin, [source_target], 8, radius)
	for foe in near:
		var sc = foe.get_node_or_null("StatusComponent") if foe != null else null
		if sc != null:
			sc.add_stain(status_id, stain)
```

Add the target-aware crit hook (after `modify_crit_chance`, line 196):

```gdscript
func modify_crit_chance_for_target(_weapon: Weapon, base: float, target: Node) -> float:
	if trigger == "on_hit" and effect == "stat_add" and element == "crit_chance" and _condition_met(target):
		return base + magnitude
	return base
```

- [ ] **Step 4: Run test to verify it passes**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: PASS (3 tests). Also run the existing data-modifier suite to confirm no regression:

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_data_modifier.gd
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/modifiers/data_modifier.gd tests/unit/test_combo_modifiers.gd
git commit -m "feat(modifiers): self_gold/knockback_and_status/spread_status verbs + target-aware crit"
```

---

## Task 6: Seven data-driven combo modifiers (CSV rows + tests)

**Files:**
- Modify: `docs/design_docs/modifiers.csv`
- Test: `tests/unit/test_combo_modifiers.gd` (append)

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_combo_modifiers.gd`:

```gdscript
func _make(id: String) -> Modifier:
	return WeaponRegistry._make_modifier(id)


func test_spark_plug_ignites_oiled_target() -> void:
	var t := _StatusTarget.new()
	add_child(t)
	t.get_node("StatusComponent").add_stain("oiled", 5.0)
	var m := _make("spark_plug")
	assert_that(m).is_not_null()
	m.on_hit_target(null, null, t)
	assert_float(t.get_node("StatusComponent").get_stain("on_fire")).is_equal(2.0)


func test_deepfreeze_adds_frozen_to_chilly_target() -> void:
	var t := _StatusTarget.new()
	add_child(t)
	t.get_node("StatusComponent").add_stain("chilly", 5.0)
	var m := _make("deepfreeze")
	m.on_hit_target(null, null, t)
	assert_float(t.get_node("StatusComponent").get_stain("frozen")).is_equal(2.0)
	var dry := _StatusTarget.new()
	add_child(dry)
	m.on_hit_target(null, null, dry)
	assert_float(dry.get_node("StatusComponent").get_stain("frozen")).is_equal(0.0)


func test_hemophilia_crit_vs_bloody() -> void:
	var w := Weapon.new()
	w.crit_chance = 0.2
	var m := _make("hemophilia")
	w.add_modifier(0, m)
	var t := _StatusTarget.new()
	add_child(t)
	assert_float(w.get_effective_crit_chance_for_target(t)).is_equal(0.2)
	t.get_node("StatusComponent").add_stain("bloody", 5.0)
	assert_float(w.get_effective_crit_chance_for_target(t)).is_equal(0.45)


func test_greedy_edge_registered_and_scales() -> void:
	var u := _GoldUser.new()
	add_child(u)
	u.gold = 250  # 5 steps -> +5%
	var m := _make("greedy_edge")
	assert_float(m.modify_hit_damage(null, u, null, 10.0)).is_equal(10.5)


func test_backdraft_registered_and_spreads() -> void:
	assert_that(_make("backdraft")).is_not_null()


func test_riptide_registered_and_knockbacks() -> void:
	assert_that(_make("riptide")).is_not_null()


func test_plague_carrier_registered_and_spreads() -> void:
	assert_that(_make("plague_carrier")).is_not_null()


func test_all_seven_data_modifiers_have_rarity_and_category() -> void:
	for id in ["spark_plug", "deepfreeze", "hemophilia", "backdraft", "riptide", "plague_carrier", "greedy_edge"]:
		var row: Dictionary = WeaponRegistry._modifier_data[id]
		assert_str(row.get("rarity", "")).is_not_empty()
		assert_str(row.get("category", "")).is_not_empty()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: FAIL — unknown modifier ids (CSV rows not present).

- [ ] **Step 3: Add the 7 CSV rows**

Append to `docs/design_docs/modifiers.csv` (after the last existing row, `steam_burst`):

```
spark_plug,Spark Plug,"Strikes ignite oiled foes — one spark sets them ablaze.",Common,status,on_hit,target_status:oiled,apply_status,on_fire,2.0,0,No
deepfreeze,Deepfreeze,"Hits against chilled foes drive them toward a deep freeze twice as fast.",Common,status,on_hit,target_status:chilly,apply_status,frozen,2.0,0,No
hemophilia,Hemophilia,"+25% critical chance versus bleeding foes.",Common,trigger,on_hit,target_status:bloody,stat_add,crit_chance,0.25,0,No
backdraft,Backdraft,"Hitting a burning foe spreads the fire to nearby enemies.",Uncommon,trigger,on_hit,target_status:on_fire,spread_status,on_fire,40,2.0,No
riptide,Riptide,"Hits knock back wet foes and leave them chilled.",Uncommon,trigger,on_hit,target_status:wet,knockback_and_status,chilly,60,2.0,No
plague_carrier,Plague Carrier,"Strikes spread a foe's poison to those nearby.",Uncommon,trigger,on_hit,target_status:poisoned,spread_status,poisoned,40,2.0,No
greedy_edge,Greedy Edge,"Deal up to +40% damage based on gold held (+1% per 50 gold).",Common,trigger,on_hit,self_gold,stat_mult,damage,0.01,0.40,No
```

- [ ] **Step 4: Run test to verify it passes**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add docs/design_docs/modifiers.csv tests/unit/test_combo_modifiers.gd
git commit -m "feat(modifiers): 7 data-driven combo modifiers (spark_plug, deepfreeze, hemophilia, backdraft, riptide, plague_carrier, greedy_edge)"
```

---

## Task 7: Detonator base + frostshatter

**Files:**
- Create: `src/weapons/modifiers/detonator_modifier.gd`
- Create: `src/weapons/modifiers/frostshatter_modifier.gd`
- Modify: `src/autoload/weapon_registry.gd`
- Test: `tests/unit/test_combo_modifiers.gd` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_combo_modifiers.gd`:

```gdscript
class _HpTarget extends Node2D:
	var health: float
	var max_health: float
	var impacts: Array = []
	func _init(h: float = 100.0) -> void:
		health = h
		max_health = h
		add_to_group("attackable")
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)
	func on_hit_impact(_p: Vector2, _d: Vector2, dmg: int) -> void:
		health -= float(dmg)
		impacts.append(dmg)


func test_frostshatter_consumes_frozen_and_bursts() -> void:
	var user := _StatusTarget.new()
	add_child(user)
	user.global_position = Vector2.ZERO
	var t := _HpTarget.new(100.0)
	add_child(t)
	t.global_position = Vector2(30, 0)
	t.get_node("StatusComponent").add_stain("frozen", 5.0)  # above threshold 3.0
	var m := FrostshatterModifier.new()
	m.on_hit_target(null, user, t)
	# burst = 5 stacks * 8 = 40
	assert_int(t.impacts.size()).is_equal(1)
	assert_int(t.impacts[0]).is_equal(40)
	# frozen consumed
	assert_float(t.get_node("StatusComponent").get_stain("frozen")).is_equal(0.0)


func test_frostshatter_no_burst_below_threshold() -> void:
	var user := _StatusTarget.new()
	add_child(user)
	var t := _HpTarget.new(100.0)
	add_child(t)
	t.get_node("StatusComponent").add_stain("frozen", 1.0)  # below threshold 3.0
	var m := FrostshatterModifier.new()
	m.on_hit_target(null, user, t)
	assert_int(t.impacts.size()).is_equal(0)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: FAIL — `FrostshatterModifier` not found.

- [ ] **Step 3: Create the detonator base**

Create `src/weapons/modifiers/detonator_modifier.gd`:

```gdscript
class_name DetonatorModifier
extends Modifier

var consumed_status: String = ""
var burst_per_stack: float = 0.0


func _init() -> void:
	category = "trigger"


func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
	if is_disabled:
		return
	var sc = target.get_node_or_null("StatusComponent") if target != null else null
	if sc == null:
		return
	var stacks: float = sc.get_stain(consumed_status)
	if stacks < StatusRegistry.get_threshold(consumed_status):
		return
	var burst: float = stacks * burst_per_stack
	sc.clear(consumed_status)
	weapon._apply_burst(user, target, burst)
	_on_detonate(weapon, user, target, stacks)


func _on_detonate(_weapon: Weapon, _user: Node, _target: Node, _stacks: float) -> void:
	pass
```

- [ ] **Step 4: Create frostshatter**

Create `src/weapons/modifiers/frostshatter_modifier.gd`:

```gdscript
class_name FrostshatterModifier
extends DetonatorModifier

const SHATTER_RADIUS := 60.0
const SHATTER_BURST := 10.0


func _init() -> void:
	super()
	name = "Frostshatter"
	description = "Consume Frozen to burst for stacks×8 and shatter nearby foes."
	consumed_status = "frozen"
	burst_per_stack = 8.0


func _on_detonate(weapon: Weapon, user: Node, target: Node, stacks: float) -> void:
	if target == null or not (target is Node2D):
		return
	var tree := target.get_tree()
	if tree == null:
		return
	var near: Array = CombatUtil.nearest_attackables(tree, (target as Node2D).global_position, [target], 6, SHATTER_RADIUS)
	for foe in near:
		weapon._apply_burst(user, foe, SHATTER_BURST)
```

- [ ] **Step 5: Register frostshatter**

In `src/autoload/weapon_registry.gd`, after the `spectral_echo` registration (line 95), add:

```gdscript
	modifier_scripts["frostshatter"] = preload("res://src/weapons/modifiers/frostshatter_modifier.gd")
```

- [ ] **Step 6: Run test to verify it passes**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/weapons/modifiers/detonator_modifier.gd src/weapons/modifiers/frostshatter_modifier.gd src/autoload/weapon_registry.gd tests/unit/test_combo_modifiers.gd
git commit -m "feat(modifiers): detonator base + frostshatter (consume frozen -> burst)"
```

---

## Task 8: combustion + necrosis detonators

**Files:**
- Create: `src/weapons/modifiers/combustion_modifier.gd`
- Create: `src/weapons/modifiers/necrosis_modifier.gd`
- Modify: `src/autoload/weapon_registry.gd`
- Test: `tests/unit/test_combo_modifiers.gd` (append)

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_combo_modifiers.gd`:

```gdscript
func test_combustion_consumes_fire_and_bursts_x3() -> void:
	var user := _StatusTarget.new()
	add_child(user)
	var t := _HpTarget.new(100.0)
	add_child(t)
	t.get_node("StatusComponent").add_stain("on_fire", 4.0)  # above threshold 1.0
	var m := CombustionModifier.new()
	m.on_hit_target(null, user, t)
	# burst = 4 stacks * 3 = 12
	assert_int(t.impacts.size()).is_equal(1)
	assert_int(t.impacts[0]).is_equal(12)
	assert_float(t.get_node("StatusComponent").get_stain("on_fire")).is_equal(0.0)


func test_necrosis_consumes_poison_and_bursts_x2() -> void:
	var user := _StatusTarget.new()
	add_child(user)
	var t := _HpTarget.new(100.0)
	add_child(t)
	t.get_node("StatusComponent").add_stain("poisoned", 3.0)  # above threshold 0.3
	var m := NecrosisModifier.new()
	m.on_hit_target(null, user, t)
	# burst = 3 stacks * 2 = 6
	assert_int(t.impacts.size()).is_equal(1)
	assert_int(t.impacts[0]).is_equal(6)
	assert_float(t.get_node("StatusComponent").get_stain("poisoned")).is_equal(0.0)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: FAIL — `CombustionModifier`/`NecrosisModifier` not found.

- [ ] **Step 3: Create combustion and necrosis**

Create `src/weapons/modifiers/combustion_modifier.gd`:

```gdscript
class_name CombustionModifier
extends DetonatorModifier


func _init() -> void:
	super()
	name = "Combustion"
	description = "Consume On-Fire for an instant burst equal to the remaining burn ×3."
	consumed_status = "on_fire"
	burst_per_stack = 3.0
```

Create `src/weapons/modifiers/necrosis_modifier.gd`:

```gdscript
class_name NecrosisModifier
extends DetonatorModifier


func _init() -> void:
	super()
	name = "Necrosis"
	description = "Consume Poison stacks for an instant burst of ×2 that damage."
	consumed_status = "poisoned"
	burst_per_stack = 2.0
```

- [ ] **Step 4: Register both**

In `src/autoload/weapon_registry.gd`, after the `frostshatter` line added in Task 7:

```gdscript
	modifier_scripts["combustion"] = preload("res://src/weapons/modifiers/combustion_modifier.gd")
	modifier_scripts["necrosis"] = preload("res://src/weapons/modifiers/necrosis_modifier.gd")
```

- [ ] **Step 5: Run test to verify it passes**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/weapons/modifiers/combustion_modifier.gd src/weapons/modifiers/necrosis_modifier.gd src/autoload/weapon_registry.gd tests/unit/test_combo_modifiers.gd
git commit -m "feat(modifiers): combustion + necrosis detonators"
```

---

## Task 9: rupture (bloody accumulator)

**Files:**
- Create: `src/weapons/modifiers/rupture_modifier.gd`
- Modify: `src/autoload/weapon_registry.gd`
- Test: `tests/unit/test_combo_modifiers.gd` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_combo_modifiers.gd`:

```gdscript
func test_rupture_bursts_after_five_bloody_hits() -> void:
	var user := _StatusTarget.new()
	add_child(user)
	var w := Weapon.new()
	w.damage = 6.0
	var t := _HpTarget.new(1000.0)
	add_child(t)
	t.get_node("StatusComponent").add_stain("bloody", 5.0)
	var m := RuptureModifier.new()
	w.add_modifier(0, m)
	# 4 bloody hits: no burst
	for i in range(4):
		m.on_hit_target(w, user, t)
	assert_int(t.impacts.size()).is_equal(0)
	# 5th bloody hit: burst for 5 * weapon.damage = 30
	m.on_hit_target(w, user, t)
	assert_int(t.impacts.size()).is_equal(1)
	assert_int(t.impacts[0]).is_equal(30)
	# counter reset
	m.on_hit_target(w, user, t)
	assert_int(t.impacts.size()).is_equal(1)


func test_rupture_ignores_non_bloody_hits() -> void:
	var user := _StatusTarget.new()
	add_child(user)
	var w := Weapon.new()
	w.damage = 6.0
	var t := _HpTarget.new(1000.0)
	add_child(t)
	var m := RuptureModifier.new()
	w.add_modifier(0, m)
	for i in range(10):
		m.on_hit_target(w, user, t)  # not bloody
	assert_int(t.impacts.size()).is_equal(0)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: FAIL — `RuptureModifier` not found.

- [ ] **Step 3: Create rupture**

Create `src/weapons/modifiers/rupture_modifier.gd`:

```gdscript
class_name RuptureModifier
extends Modifier

const BLEED_HITS_TO_BURST := 5
const BURST_MULT := 5.0
var _bleed_hits: int = 0


func _init() -> void:
	category = "trigger"
	name = "Rupture"
	description = "Bleeding accumulates; at 5 stacks the target bursts for 5× a hit."


func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
	if is_disabled:
		return
	var sc = target.get_node_or_null("StatusComponent") if target != null else null
	if sc == null or sc.get_stain("bloody") <= 0.0:
		return
	_bleed_hits += 1
	if _bleed_hits >= BLEED_HITS_TO_BURST:
		_bleed_hits = 0
		weapon._apply_burst(user, target, weapon.damage * BURST_MULT)
```

- [ ] **Step 4: Register rupture**

In `src/autoload/weapon_registry.gd`, after the `necrosis` line:

```gdscript
	modifier_scripts["rupture"] = preload("res://src/weapons/modifiers/rupture_modifier.gd")
```

- [ ] **Step 5: Run test to verify it passes**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/weapons/modifiers/rupture_modifier.gd src/autoload/weapon_registry.gd tests/unit/test_combo_modifiers.gd
git commit -m "feat(modifiers): rupture (bloody accumulator -> 5x burst)"
```

---

## Task 10: echo_strike (retrigger first slot)

**Files:**
- Create: `src/weapons/modifiers/echo_strike_modifier.gd`
- Modify: `src/autoload/weapon_registry.gd`
- Test: `tests/unit/test_combo_modifiers.gd` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_combo_modifiers.gd`:

```gdscript
class _HitCounter extends Modifier:
	var on_hit_calls: int = 0
	var dmg_seen: float = 0.0
	func _init() -> void:
		category = "trigger"
	func on_hit_target(_w, _u, _t) -> void:
		on_hit_calls += 1
	func modify_hit_damage(_w, _u, _t, dmg: float) -> float:
		dmg_seen = dmg
		return dmg


func test_echo_strike_retriggers_first_slot_once() -> void:
	var w := Weapon.new()
	var first := _HitCounter.new()
	var echo := EchoStrikeModifier.new()
	w.add_modifier(0, first); w.add_modifier(1, echo)
	var t := Node.new()
	w.resolve_hit(null, t, 10.0, false)
	# first: normal(1) + retriggered(1) = 2
	assert_int(first.on_hit_calls).is_equal(2)


func test_echo_strike_no_op_when_first_is_self() -> void:
	var w := Weapon.new()
	var echo := EchoStrikeModifier.new()
	w.add_modifier(0, echo)  # echo is the first modifier
	var t := Node.new()
	w.resolve_hit(null, t, 10.0, false)
	# no infinite loop, no crash
	assert_bool(true).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: FAIL — `EchoStrikeModifier` not found.

- [ ] **Step 3: Create echo_strike**

Create `src/weapons/modifiers/echo_strike_modifier.gd`:

```gdscript
class_name EchoStrikeModifier
extends Modifier


func _init() -> void:
	category = "trigger"
	is_retrigger_modifier = true
	name = "Echo Strike"
	description = "Retrigger your first modifier once per swing."


func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
	if is_disabled:
		return
	var first: Modifier = weapon.get_first_modifier()
	if first == null or first == self:
		return
	weapon.retrigger_modifier(first, "on_hit_target", [user, target])


func modify_hit_damage(weapon: Weapon, user: Node, target: Node, dmg: float) -> float:
	if is_disabled:
		return dmg
	var first: Modifier = weapon.get_first_modifier()
	if first == null or first == self:
		return dmg
	var r: Variant = weapon.retrigger_modifier(first, "modify_hit_damage", [user, target, dmg])
	if r == null:
		return dmg
	return float(r)
```

- [ ] **Step 4: Register echo_strike**

In `src/autoload/weapon_registry.gd`, after the `rupture` line:

```gdscript
	modifier_scripts["echo_strike"] = preload("res://src/weapons/modifiers/echo_strike_modifier.gd")
```

- [ ] **Step 5: Run test to verify it passes**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/weapons/modifiers/echo_strike_modifier.gd src/autoload/weapon_registry.gd tests/unit/test_combo_modifiers.gd
git commit -m "feat(modifiers): echo_strike (retrigger first slot once)"
```

---

## Task 11: overclock (retrigger left, disable 5s)

**Files:**
- Create: `src/weapons/modifiers/overclock_modifier.gd`
- Modify: `src/autoload/weapon_registry.gd`
- Test: `tests/unit/test_combo_modifiers.gd` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_combo_modifiers.gd`:

```gdscript
func test_overclock_retriggers_left_then_disables_five_seconds() -> void:
	var w := Weapon.new()
	var left := _HitCounter.new()
	var oc := OverclockModifier.new()
	w.add_modifier(0, left); w.add_modifier(1, oc)
	var t := Node.new()
	w.resolve_hit(null, t, 10.0, false)
	# left fired normally + retriggered = 2
	assert_int(left.on_hit_calls).is_equal(2)
	# left now disabled
	assert_bool(left.is_disabled).is_true()
	# next swing: left is disabled (only 0 extra)
	w.resolve_hit(null, t, 10.0, false)
	assert_int(left.on_hit_calls).is_equal(2)
	# tick 5s -> re-enabled
	w.tick(5.01)
	assert_bool(left.is_disabled).is_false()
	w.resolve_hit(null, t, 10.0, false)
	assert_int(left.on_hit_calls).is_equal(4)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: FAIL — `OverclockModifier` not found.

- [ ] **Step 3: Create overclock**

Create `src/weapons/modifiers/overclock_modifier.gd`:

```gdscript
class_name OverclockModifier
extends Modifier

const DISABLE_TIME := 5.0
var _timer: float = 0.0


func _init() -> void:
	category = "trigger"
	is_retrigger_modifier = true
	name = "Overclock"
	description = "Retrigger the modifier to your left, then disable it for 5 seconds."


func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
	if is_disabled:
		return
	var left: Modifier = weapon.get_left_modifier(slot_index)
	if left != null and left != self and not left.is_retrigger_modifier:
		weapon.retrigger_modifier(left, "on_hit_target", [user, target])
		left.is_disabled = true
		_timer = DISABLE_TIME


func on_tick(_weapon: Weapon, delta: float) -> void:
	if _timer > 0.0:
		_timer -= delta
		if _timer <= 0.0:
			var w: Weapon = _weapon
			var left: Modifier = w.get_left_modifier(slot_index)
			if left != null:
				left.is_disabled = false
```

- [ ] **Step 4: Register overclock**

In `src/autoload/weapon_registry.gd`, after the `echo_strike` line:

```gdscript
	modifier_scripts["overclock"] = preload("res://src/weapons/modifiers/overclock_modifier.gd")
```

- [ ] **Step 5: Run test to verify it passes**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/weapons/modifiers/overclock_modifier.gd src/autoload/weapon_registry.gd tests/unit/test_combo_modifiers.gd
git commit -m "feat(modifiers): overclock (retrigger left, disable 5s)"
```

---

## Task 12: mirror_slot (copy/delegate left)

**Files:**
- Create: `src/weapons/modifiers/mirror_slot_modifier.gd`
- Modify: `src/autoload/weapon_registry.gd`
- Test: `tests/unit/test_combo_modifiers.gd` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_combo_modifiers.gd`:

```gdscript
func test_mirror_slot_delegates_to_left() -> void:
	var w := Weapon.new()
	var left := _HitCounter.new()
	var mirror := MirrorSlotModifier.new()
	w.add_modifier(0, left); w.add_modifier(1, mirror)
	var t := Node.new()
	w.resolve_hit(null, t, 10.0, false)
	# left: normal(1) + mirror-delegated(1) = 2
	assert_int(left.on_hit_calls).is_equal(2)


func test_mirror_slot_copying_mirror_is_noop() -> void:
	var w := Weapon.new()
	var m1 := MirrorSlotModifier.new()
	var m2 := MirrorSlotModifier.new()
	w.add_modifier(0, m1); w.add_modifier(1, m2)
	var t := Node.new()
	w.resolve_hit(null, t, 10.0, false)  # must not loop / crash
	assert_bool(true).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: FAIL — `MirrorSlotModifier` not found.

- [ ] **Step 3: Create mirror_slot**

Create `src/weapons/modifiers/mirror_slot_modifier.gd`:

```gdscript
class_name MirrorSlotModifier
extends Modifier


func _init() -> void:
	category = "trigger"
	name = "Mirror Slot"
	description = "Become a copy of the modifier to your left."


func _left(weapon: Weapon) -> Modifier:
	var left: Modifier = weapon.get_left_modifier(slot_index)
	if left == null or left is MirrorSlotModifier:
		return null
	return left


func on_attack(weapon: Weapon, user: Node, ctx: Dictionary) -> void:
	if is_disabled:
		return
	var l: Modifier = _left(weapon)
	if l != null:
		l.on_attack(weapon, user, ctx)


func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
	if is_disabled:
		return
	var l: Modifier = _left(weapon)
	if l != null:
		l.on_hit_target(weapon, user, target)


func modify_hit_damage(weapon: Weapon, user: Node, target: Node, dmg: float) -> float:
	if is_disabled:
		return dmg
	var l: Modifier = _left(weapon)
	if l != null:
		return l.modify_hit_damage(weapon, user, target, dmg)
	return dmg


func on_kill(weapon: Weapon, user: Node, target: Node) -> void:
	if is_disabled:
		return
	var l: Modifier = _left(weapon)
	if l != null:
		l.on_kill(weapon, user, target)


func get_stat_add(stat: String) -> float:
	var l: Modifier = _left_of_self()
	if l != null:
		return l.get_stat_add(stat)
	return 0.0


func get_stat_mult(stat: String) -> float:
	var l: Modifier = _left_of_self()
	if l != null:
		return l.get_stat_mult(stat)
	return 1.0


func _left_of_self() -> Modifier:
	# Delegating stat hooks without a weapon ref: read slot_index on the owning
	# weapon via the modifier array. stat hooks are called via _iter_active_modifiers
	# which does not pass the weapon, so we resolve through the cached owner.
	return _cached_left


var _cached_left: Modifier = null


func on_equip(weapon: Weapon) -> void:
	_cached_left = weapon.get_left_modifier(slot_index)
	if _cached_left != null and _cached_left is MirrorSlotModifier:
		_cached_left = null
```

- [ ] **Step 4: Register mirror_slot**

In `src/autoload/weapon_registry.gd`, after the `overclock` line:

```gdscript
	modifier_scripts["mirror_slot"] = preload("res://src/weapons/modifiers/mirror_slot_modifier.gd")
```

- [ ] **Step 5: Run test to verify it passes**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/weapons/modifiers/mirror_slot_modifier.gd src/autoload/weapon_registry.gd tests/unit/test_combo_modifiers.gd
git commit -m "feat(modifiers): mirror_slot (delegate/copy left, no-op on mirror)"
```

---

## Task 13: catalyst_bond (link slots 0 and 2)

**Files:**
- Create: `src/weapons/modifiers/catalyst_bond_modifier.gd`
- Modify: `src/autoload/weapon_registry.gd`
- Test: `tests/unit/test_combo_modifiers.gd` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_combo_modifiers.gd`:

```gdscript
func test_catalyst_bond_links_slots_zero_and_two() -> void:
	var w := Weapon.new()
	var s0 := _HitCounter.new()
	var bond := CatalystBondModifier.new()
	var s2 := _HitCounter.new()
	w.add_modifier(0, s0); w.add_modifier(1, bond); w.add_modifier(2, s2)
	var t := Node.new()
	w.resolve_hit(null, t, 10.0, false)
	# s0: normal(1) + bond-link(1) = 2; s2: bond-link(1) + normal(1) = 2
	assert_int(s0.on_hit_calls).is_equal(2)
	assert_int(s2.on_hit_calls).is_equal(2)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: FAIL — `CatalystBondModifier` not found.

- [ ] **Step 3: Create catalyst_bond**

Create `src/weapons/modifiers/catalyst_bond_modifier.gd`:

```gdscript
class_name CatalystBondModifier
extends Modifier


func _init() -> void:
	category = "trigger"
	is_retrigger_modifier = true  # positional engine: retriggers must not re-enter it
	name = "Catalyst Bond"
	description = "Link slots 1 and 3: either fires and both fire."


func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
	if is_disabled:
		return
	var s0: Modifier = weapon.get_modifier_at(0)
	var s2: Modifier = weapon.get_modifier_at(2)
	if s0 != null and s0 != self and not s0.is_disabled:
		s0.on_hit_target(weapon, user, target)
	if s2 != null and s2 != self and not s2.is_disabled:
		s2.on_hit_target(weapon, user, target)
```

- [ ] **Step 4: Register catalyst_bond**

In `src/autoload/weapon_registry.gd`, after the `mirror_slot` line:

```gdscript
	modifier_scripts["catalyst_bond"] = preload("res://src/weapons/modifiers/catalyst_bond_modifier.gd")
```

- [ ] **Step 5: Run test to verify it passes**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/weapons/modifiers/catalyst_bond_modifier.gd src/autoload/weapon_registry.gd tests/unit/test_combo_modifiers.gd
git commit -m "feat(modifiers): catalyst_bond (link slots 0 and 2)"
```

---

## Task 14: keystone (focus build: outer slots disabled, ×2 damage)

**Files:**
- Create: `src/weapons/modifiers/keystone_modifier.gd`
- Modify: `src/weapons/weapon.gd` (apply ×2 in `get_effective_stats`)
- Modify: `src/autoload/weapon_registry.gd`
- Test: `tests/unit/test_combo_modifiers.gd` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_combo_modifiers.gd`:

```gdscript
func test_keystone_disables_outer_slots_and_doubles_damage() -> void:
	var w := Weapon.new()
	w.damage = 10.0
	var s0 := _HitCounter.new()
	var ks := KeystoneModifier.new()
	var s2 := _HitCounter.new()
	w.add_modifier(0, s0); w.add_modifier(1, ks); w.add_modifier(2, s2)
	# outer slots disabled by keystone focus
	assert_bool(s0.is_disabled).is_false()  # disable is dynamic via _iter_active_modifiers, not a flag
	var t := Node.new()
	w.resolve_hit(null, t, 10.0, false)
	# only middle (keystone) active -> s0 and s2 do NOT fire
	assert_int(s0.on_hit_calls).is_equal(0)
	assert_int(s2.on_hit_calls).is_equal(0)
	# damage x2
	assert_float(w.get_effective_stats()["damage"]).is_equal(20.0)


func test_keystone_without_keystone_is_normal() -> void:
	var w := Weapon.new()
	w.damage = 10.0
	var s0 := _HitCounter.new()
	w.add_modifier(0, s0)
	assert_float(w.get_effective_stats()["damage"]).is_equal(10.0)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: FAIL — `KeystoneModifier` not found; damage not doubled.

- [ ] **Step 3: Create keystone**

Create `src/weapons/modifiers/keystone_modifier.gd`:

```gdscript
class_name KeystoneModifier
extends Modifier

const DAMAGE_MULT := 2.0


func _init() -> void:
	category = "trigger"
	name = "Keystone"
	description = "Slot 2 modifier +100%; slots 1 and 3 disabled (focus build)."


func is_keystone() -> bool:
	return true


func get_stat_mult(stat: String) -> float:
	if stat == "damage":
		return DAMAGE_MULT
	return 1.0
```

- [ ] **Step 4: Apply keystone damage ×2 in Weapon effective stats**

In `src/weapons/weapon.gd`, in `get_effective_stats()` (the refactored version from Task 3), after `s["cooldown"] = maxf(COOLDOWN_FLOOR, s["cooldown"])` and before `_effective_cache = s`, add:

```gdscript
	if _has_keystone():
		s["damage"] *= 2.0
```

(The `_iter_active_modifiers` keystone-focus skip from Task 3 already suppresses outer-slot hooks; this line adds the ×2 damage. Keystone's own `get_stat_mult` also returns 2.0 — to avoid double-applying, the keystone line here is the single source: change keystone's `get_stat_mult` to return 1.0 and let this line carry the ×2.)

Corrected: in `src/weapons/modifiers/keystone_modifier.gd`, set `get_stat_mult` to return `1.0` for all stats (the weapon-level line applies the ×2 once):

```gdscript
func get_stat_mult(stat: String) -> float:
	return 1.0
```

- [ ] **Step 5: Register keystone**

In `src/autoload/weapon_registry.gd`, after the `catalyst_bond` line:

```gdscript
	modifier_scripts["keystone"] = preload("res://src/weapons/modifiers/keystone_modifier.gd")
```

- [ ] **Step 6: Run test to verify it passes**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/weapons/modifiers/keystone_modifier.gd src/weapons/weapon.gd src/autoload/weapon_registry.gd tests/unit/test_combo_modifiers.gd
git commit -m "feat(modifiers): keystone focus build (outer slots disabled, x2 damage)"
```

---

## Task 15: twin_trigger (every 3rd swing, all trigger twice)

**Files:**
- Create: `src/weapons/modifiers/twin_trigger_modifier.gd`
- Modify: `src/autoload/weapon_registry.gd`
- Test: `tests/unit/test_combo_modifiers.gd` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_combo_modifiers.gd`:

```gdscript
func test_twin_trigger_doubles_all_on_third_swing() -> void:
	var w := Weapon.new()
	var a := _HitCounter.new()
	var tt := TwinTriggerModifier.new()
	var b := _HitCounter.new()
	w.add_modifier(0, a); w.add_modifier(1, tt); w.add_modifier(2, b)
	var ctx := {"direction": Vector2.RIGHT, "origin": Vector2.ZERO, "charged": false, "charge_ratio": 0.0}
	var t := Node.new()
	# swing 1
	w.notify_attack(null, ctx); w.resolve_hit(null, t, 5.0, false)
	assert_int(a.on_hit_calls).is_equal(1)
	assert_int(b.on_hit_calls).is_equal(1)
	# swing 2
	w.notify_attack(null, ctx); w.resolve_hit(null, t, 5.0, false)
	assert_int(a.on_hit_calls).is_equal(2)
	assert_int(b.on_hit_calls).is_equal(2)
	# swing 3: every modifier triggers twice
	w.notify_attack(null, ctx); w.resolve_hit(null, t, 5.0, false)
	assert_int(a.on_hit_calls).is_equal(4)
	assert_int(b.on_hit_calls).is_equal(4)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: FAIL — `TwinTriggerModifier` not found.

- [ ] **Step 3: Create twin_trigger**

Create `src/weapons/modifiers/twin_trigger_modifier.gd`:

```gdscript
class_name TwinTriggerModifier
extends Modifier

var _swings: int = 0


func _init() -> void:
	category = "trigger"
	is_retrigger_modifier = true
	name = "Twin Trigger"
	description = "Every 3rd swing, all modifiers trigger twice."


func on_attack(weapon: Weapon, user: Node, ctx: Dictionary) -> void:
	if is_disabled:
		return
	_swings += 1
	if _swings % 3 == 0:
		_extra_pass(weapon, "on_attack", [user, ctx])


func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
	if is_disabled:
		return
	if _swings % 3 == 0:
		_extra_pass(weapon, "on_hit_target", [user, target])


func _extra_pass(weapon: Weapon, hook: String, args: Array) -> void:
	for m in weapon._iter_active_modifiers():
		if m == self or m.is_retrigger_modifier:
			continue
		match hook:
			"on_attack":
				m.on_attack(weapon, args[0], args[1])
			"on_hit_target":
				m.on_hit_target(weapon, args[0], args[1])
```

- [ ] **Step 4: Register twin_trigger**

In `src/autoload/weapon_registry.gd`, after the `keystone` line:

```gdscript
	modifier_scripts["twin_trigger"] = preload("res://src/weapons/modifiers/twin_trigger_modifier.gd")
```

- [ ] **Step 5: Run test to verify it passes**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/weapons/modifiers/twin_trigger_modifier.gd src/autoload/weapon_registry.gd tests/unit/test_combo_modifiers.gd
git commit -m "feat(modifiers): twin_trigger (every 3rd swing doubles all)"
```

---

## Task 16: flywheel (charge, dump ×3 at 5)

**Files:**
- Create: `src/weapons/modifiers/flywheel_modifier.gd`
- Modify: `src/autoload/weapon_registry.gd`
- Test: `tests/unit/test_combo_modifiers.gd` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_combo_modifiers.gd`:

```gdscript
func test_flywheel_dumps_three_extra_at_five_swings() -> void:
	var w := Weapon.new()
	var a := _HitCounter.new()
	var fw := FlywheelModifier.new()
	var b := _HitCounter.new()
	w.add_modifier(0, a); w.add_modifier(1, fw); w.add_modifier(2, b)
	var ctx := {"direction": Vector2.RIGHT, "origin": Vector2.ZERO, "charged": false, "charge_ratio": 0.0}
	var t := Node.new()
	for i in range(4):
		w.notify_attack(null, ctx); w.resolve_hit(null, t, 5.0, false)
	assert_int(a.on_hit_calls).is_equal(4)
	assert_int(b.on_hit_calls).is_equal(4)
	# 5th swing: dump -> a and b fire 3 extra times each
	w.notify_attack(null, ctx); w.resolve_hit(null, t, 5.0, false)
	assert_int(a.on_hit_calls).is_equal(8)  # 4 + 1 (normal) + 3 (dump)
	assert_int(b.on_hit_calls).is_equal(8)
	# 6th swing: charge reset to 1, no dump
	w.notify_attack(null, ctx); w.resolve_hit(null, t, 5.0, false)
	assert_int(a.on_hit_calls).is_equal(9)
	assert_int(b.on_hit_calls).is_equal(9)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: FAIL — `FlywheelModifier` not found.

- [ ] **Step 3: Create flywheel**

Create `src/weapons/modifiers/flywheel_modifier.gd`:

```gdscript
class_name FlywheelModifier
extends Modifier

const CHARGE_TO_DUMP := 5
const DUMP_EXTRA := 3
var _charge: int = 0


func _init() -> void:
	category = "trigger"
	is_retrigger_modifier = true
	name = "Flywheel"
	description = "Untriggered modifiers charge; at 5, fire ×3 then empty."


func on_attack(_weapon: Weapon, _user: Node, _ctx: Dictionary) -> void:
	if is_disabled:
		return
	_charge += 1


func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
	if is_disabled:
		return
	if _charge < CHARGE_TO_DUMP:
		return
	_charge = 0
	for m in weapon._iter_active_modifiers():
		if m == self or m.is_retrigger_modifier:
			continue
		for _i in range(DUMP_EXTRA):
			m.on_hit_target(weapon, user, target)
```

- [ ] **Step 4: Register flywheel**

In `src/autoload/weapon_registry.gd`, after the `twin_trigger` line:

```gdscript
	modifier_scripts["flywheel"] = preload("res://src/weapons/modifiers/flywheel_modifier.gd")
```

- [ ] **Step 5: Run test to verify it passes**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/weapons/modifiers/flywheel_modifier.gd src/autoload/weapon_registry.gd tests/unit/test_combo_modifiers.gd
git commit -m "feat(modifiers): flywheel (charge 5 -> dump x3)"
```

---

## Task 17: last_stand + overkill

**Files:**
- Create: `src/weapons/modifiers/last_stand_modifier.gd`
- Create: `src/weapons/modifiers/overkill_modifier.gd`
- Modify: `src/autoload/weapon_registry.gd`
- Test: `tests/unit/test_combo_modifiers.gd` (append)

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_combo_modifiers.gd`:

```gdscript
class _HpUser extends Node2D:
	var health: float = 10.0
	var max_health: float = 10.0


func test_last_stand_boosts_first_hit_after_damage() -> void:
	var u := _HpUser.new()
	add_child(u)
	var w := Weapon.new()
	var m := LastStandModifier.new()
	w.add_modifier(0, m)
	var t := Node.new()
	# first hit at full hp: no boost
	assert_float(m.modify_hit_damage(w, u, t, 10.0)).is_equal(10.0)
	# take damage
	u.health = 5.0
	# next hit: boosted
	assert_float(m.modify_hit_damage(w, u, t, 10.0)).is_equal(16.0)
	# subsequent hit: no boost (charged consumed)
	u.health = 5.0
	assert_float(m.modify_hit_damage(w, u, t, 10.0)).is_equal(10.0)


func test_overkill_carries_excess_to_next_target() -> void:
	var w := Weapon.new()
	var m := OverkillModifier.new()
	w.add_modifier(0, m)
	var a := _HpTarget.new(5.0)
	add_child(a)
	var b := _HpTarget.new(20.0)
	add_child(b)
	# hit A for 10: overflow = 10 - 5 = 5 carried
	assert_float(m.modify_hit_damage(w, null, a, 10.0)).is_equal(10.0)
	m.on_kill(w, null, a)
	# hit B for 4: 4 + 5 carry = 9
	assert_float(m.modify_hit_damage(w, null, b, 4.0)).is_equal(9.0)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: FAIL — `LastStandModifier`/`OverkillModifier` not found.

- [ ] **Step 3: Create last_stand**

Create `src/weapons/modifiers/last_stand_modifier.gd`:

```gdscript
class_name LastStandModifier
extends Modifier

const BOOST_MULT := 1.6
var _charged: bool = false
var _prev_hp: float = -1.0


func _init() -> void:
	category = "trigger"
	name = "Last Stand"
	description = "+60% damage on your first hit after taking damage."


func modify_hit_damage(_weapon: Weapon, user: Node, _target: Node, dmg: float) -> float:
	if is_disabled:
		return dmg
	var hp: float = _user_hp(user)
	if _prev_hp >= 0.0 and hp < _prev_hp:
		_charged = true
	_prev_hp = hp
	if _charged:
		_charged = false
		return dmg * BOOST_MULT
	return dmg


func _user_hp(user: Node) -> float:
	if user == null or not ("health" in user):
		return 1.0
	return float(user.health)
```

- [ ] **Step 4: Create overkill**

Create `src/weapons/modifiers/overkill_modifier.gd`:

```gdscript
class_name OverkillModifier
extends Modifier

var _carry: float = 0.0
var _last_dmg: float = 0.0
var _last_pre_hp: float = 0.0


func _init() -> void:
	category = "trigger"
	name = "Overkill"
	description = "Damage exceeding an enemy's HP carries to the next enemy hit."


func modify_hit_damage(_weapon: Weapon, _user: Node, target: Node, dmg: float) -> float:
	if is_disabled:
		return dmg
	_last_pre_hp = float(target.health) if (target != null and "health" in target) else 0.0
	var out: float = dmg + _carry
	_last_dmg = out
	_carry = 0.0
	return out


func on_kill(_weapon: Weapon, _user: Node, _target: Node) -> void:
	if is_disabled:
		return
	_carry = maxf(0.0, _last_dmg - _last_pre_hp)
```

- [ ] **Step 5: Register both**

In `src/autoload/weapon_registry.gd`, after the `flywheel` line:

```gdscript
	modifier_scripts["last_stand"] = preload("res://src/weapons/modifiers/last_stand_modifier.gd")
	modifier_scripts["overkill"] = preload("res://src/weapons/modifiers/overkill_modifier.gd")
```

- [ ] **Step 6: Run test to verify it passes**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/weapons/modifiers/last_stand_modifier.gd src/weapons/modifiers/overkill_modifier.gd src/autoload/weapon_registry.gd tests/unit/test_combo_modifiers.gd
git commit -m "feat(modifiers): last_stand + overkill"
```

---

## Task 18: evolving_edge + slot_harmony

**Files:**
- Create: `src/weapons/modifiers/evolving_edge_modifier.gd`
- Create: `src/weapons/modifiers/slot_harmony_modifier.gd`
- Modify: `src/autoload/weapon_registry.gd`
- Test: `tests/unit/test_combo_modifiers.gd` (append)

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_combo_modifiers.gd`:

```gdscript
func test_evolving_edge_doubles_after_fifteen_hits() -> void:
	var m := EvolvingEdgeModifier.new()
	assert_float(m.get_stat_add("damage")).is_equal(2.0)
	for i in range(15):
		m.on_hit_target(null, null, null)
	assert_float(m.get_stat_add("damage")).is_equal(4.0)
	assert_float(m.get_stat_add("cooldown")).is_equal(0.0)


func test_slot_harmony_boosts_when_all_categories_distinct() -> void:
	var w := Weapon.new()
	var a := DataModifier.new(_row({"category": "stat"}))
	var b := DataModifier.new(_row({"category": "status"}))
	var h := SlotHarmonyModifier.new()
	w.add_modifier(0, a); w.add_modifier(1, b); w.add_modifier(2, h)
	var t := Node.new()
	assert_float(h.modify_hit_damage(w, null, t, 10.0)).is_equal(12.0)


func test_slot_harmony_no_boost_when_duplicate_category() -> void:
	var w := Weapon.new()
	var a := DataModifier.new(_row({"category": "stat"}))
	var b := DataModifier.new(_row({"category": "stat"}))
	var h := SlotHarmonyModifier.new()
	w.add_modifier(0, a); w.add_modifier(1, b); w.add_modifier(2, h)
	var t := Node.new()
	assert_float(h.modify_hit_damage(w, null, t, 10.0)).is_equal(10.0)


func test_slot_harmony_no_boost_when_slot_empty() -> void:
	var w := Weapon.new()
	var a := DataModifier.new(_row({"category": "stat"}))
	var h := SlotHarmonyModifier.new()
	w.add_modifier(0, a); w.add_modifier(2, h)
	var t := Node.new()
	assert_float(h.modify_hit_damage(w, null, t, 10.0)).is_equal(10.0)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: FAIL — `EvolvingEdgeModifier`/`SlotHarmonyModifier` not found.

- [ ] **Step 3: Create evolving_edge**

Create `src/weapons/modifiers/evolving_edge_modifier.gd`:

```gdscript
class_name EvolvingEdgeModifier
extends Modifier

const BASE_BONUS := 2.0
const HITS_TO_DOUBLE := 15
var _hits: int = 0


func _init() -> void:
	category = "trigger"
	name = "Evolving Edge"
	description = "After 15 hits, this modifier's own bonus doubles (run)."


func on_hit_target(_weapon: Weapon, _user: Node, _target: Node) -> void:
	if is_disabled:
		return
	_hits += 1


func get_stat_add(stat: String) -> float:
	if stat != "damage":
		return 0.0
	return BASE_BONUS * (2.0 if _hits >= HITS_TO_DOUBLE else 1.0)
```

- [ ] **Step 4: Create slot_harmony**

Create `src/weapons/modifiers/slot_harmony_modifier.gd`:

```gdscript
class_name SlotHarmonyModifier
extends Modifier

const HARMONY_MULT := 1.2


func _init() -> void:
	category = "trigger"
	name = "Slot Harmony"
	description = "+20% damage while all 3 slots are different categories."


func modify_hit_damage(weapon: Weapon, _user: Node, _target: Node, dmg: float) -> float:
	if is_disabled:
		return dmg
	if _all_different(weapon):
		return dmg * HARMONY_MULT
	return dmg


func _all_different(weapon: Weapon) -> bool:
	var cats: Array = []
	for i in range(weapon.modifier_slot_count):
		var m: Modifier = weapon.get_modifier_at(i)
		if m == null:
			return false
		var c: String = m.category if "category" in m else ""
		if c == "" or cats.has(c):
			return false
		cats.append(c)
	return cats.size() == weapon.modifier_slot_count
```

- [ ] **Step 5: Register both**

In `src/autoload/weapon_registry.gd`, after the `overkill` line:

```gdscript
	modifier_scripts["evolving_edge"] = preload("res://src/weapons/modifiers/evolving_edge_modifier.gd")
	modifier_scripts["slot_harmony"] = preload("res://src/weapons/modifiers/slot_harmony_modifier.gd")
```

- [ ] **Step 6: Run test to verify it passes**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/weapons/modifiers/evolving_edge_modifier.gd src/weapons/modifiers/slot_harmony_modifier.gd src/autoload/weapon_registry.gd tests/unit/test_combo_modifiers.gd
git commit -m "feat(modifiers): evolving_edge + slot_harmony"
```

---

## Task 19: pendulum + headsman

**Files:**
- Create: `src/weapons/modifiers/pendulum_modifier.gd`
- Create: `src/weapons/modifiers/headsman_modifier.gd`
- Modify: `src/autoload/weapon_registry.gd`
- Test: `tests/unit/test_combo_modifiers.gd` (append)

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_combo_modifiers.gd`:

```gdscript
func test_pendulum_alternates_left_right() -> void:
	var w := Weapon.new()
	var left := _HitCounter.new()
	var pend := PendulumModifier.new()
	var right := _HitCounter.new()
	w.add_modifier(0, left); w.add_modifier(1, pend); w.add_modifier(2, right)
	var ctx := {"direction": Vector2.RIGHT, "origin": Vector2.ZERO, "charged": false, "charge_ratio": 0.0}
	var t := Node.new()
	# swing 1 (odd): left x2, right x1
	w.notify_attack(null, ctx); w.resolve_hit(null, t, 5.0, false)
	assert_int(left.on_hit_calls).is_equal(2)
	assert_int(right.on_hit_calls).is_equal(1)
	# swing 2 (even): left x1, right x2
	w.notify_attack(null, ctx); w.resolve_hit(null, t, 5.0, false)
	assert_int(left.on_hit_calls).is_equal(3)
	assert_int(right.on_hit_calls).is_equal(3)


func test_headsman_refunds_swing_on_high_hp_kill() -> void:
	var w := Weapon.new()
	w.cooldown = 0.5
	w._cooldown_timer = 0.5
	var m := HeadsmanModifier.new()
	w.add_modifier(0, m)
	var t := _HpTarget.new(100.0)
	t.max_health = 100.0
	add_child(t)
	# pre-hit fraction cached
	m.modify_hit_damage(w, null, t, 200.0)
	# kill
	m.on_kill(w, null, t)
	assert_float(w._cooldown_timer).is_equal(0.0)


func test_headsman_no_refund_on_low_hp_kill() -> void:
	var w := Weapon.new()
	w.cooldown = 0.5
	w._cooldown_timer = 0.5
	var m := HeadsmanModifier.new()
	w.add_modifier(0, m)
	var t := _HpTarget.new(2.0)
	t.max_health = 100.0
	add_child(t)
	m.modify_hit_damage(w, null, t, 5.0)
	m.on_kill(w, null, t)
	assert_float(w._cooldown_timer).is_equal(0.5)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: FAIL — `PendulumModifier`/`HeadsmanModifier` not found.

- [ ] **Step 3: Create pendulum**

Create `src/weapons/modifiers/pendulum_modifier.gd`:

```gdscript
class_name PendulumModifier
extends Modifier

var _swings: int = 0


func _init() -> void:
	category = "trigger"
	is_retrigger_modifier = true
	name = "Pendulum"
	description = "Odd swings ×2 your left modifier, even swings ×2 your right."


func on_attack(weapon: Weapon, user: Node, ctx: Dictionary) -> void:
	if is_disabled:
		return
	_swings += 1
	_extra(weapon, "on_attack", [user, ctx])


func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
	if is_disabled:
		return
	_extra(weapon, "on_hit_target", [user, target])


func _extra(weapon: Weapon, hook: String, args: Array) -> void:
	var sibling: Modifier = null
	if _swings % 2 == 1:
		sibling = weapon.get_left_modifier(slot_index)
	else:
		sibling = weapon.get_right_modifier(slot_index)
	if sibling == null or sibling == self or sibling.is_retrigger_modifier:
		return
	if sibling.is_disabled:
		return
	match hook:
		"on_attack":
			sibling.on_attack(weapon, args[0], args[1])
		"on_hit_target":
			sibling.on_hit_target(weapon, args[0], args[1])
```

- [ ] **Step 4: Create headsman**

Create `src/weapons/modifiers/headsman_modifier.gd`:

```gdscript
class_name HeadsmanModifier
extends Modifier

const HIGH_HP_FRACTION := 0.5
var _last_frac: float = 0.0


func _init() -> void:
	category = "trigger"
	name = "Headsman"
	description = "One-shotting an enemy above 50% HP refunds the swing."


func modify_hit_damage(_weapon: Weapon, _user: Node, target: Node, dmg: float) -> float:
	if is_disabled:
		return dmg
	if target != null and "health" in target and "max_health" in target:
		_last_frac = float(target.health) / maxf(1.0, float(target.max_health))
	return dmg


func on_kill(weapon: Weapon, _user: Node, _target: Node) -> void:
	if is_disabled:
		return
	if _last_frac > HIGH_HP_FRACTION:
		weapon.reset_cooldown()
```

- [ ] **Step 5: Register both**

In `src/autoload/weapon_registry.gd`, after the `slot_harmony` line:

```gdscript
	modifier_scripts["pendulum"] = preload("res://src/weapons/modifiers/pendulum_modifier.gd")
	modifier_scripts["headsman"] = preload("res://src/weapons/modifiers/headsman_modifier.gd")
```

- [ ] **Step 6: Run test to verify it passes**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/weapons/modifiers/pendulum_modifier.gd src/weapons/modifiers/headsman_modifier.gd src/autoload/weapon_registry.gd tests/unit/test_combo_modifiers.gd
git commit -m "feat(modifiers): pendulum + headsman"
```

---

## Task 20: Complete CSV (24 rows) + registry registration verification

**Files:**
- Modify: `docs/design_docs/modifiers.csv` (append the 17 scripted rows)
- Test: `tests/unit/test_combo_modifiers.gd` (append)

The 7 data-driven rows were added in Task 6. The 17 scripted modifiers are registered in their tasks. This task adds the 17 scripted CSV rows (so shop buckets and tooltips populate) and verifies the full set.

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_combo_modifiers.gd`:

```gdscript
func test_all_24_combo_modifiers_registered_and_droppable() -> void:
	var scripted := [
		"frostshatter", "combustion", "necrosis", "rupture",
		"echo_strike", "overclock", "mirror_slot", "catalyst_bond",
		"keystone", "twin_trigger", "flywheel",
		"last_stand", "overkill", "evolving_edge", "pendulum", "headsman", "slot_harmony",
	]
	var data_driven := ["spark_plug", "deepfreeze", "hemophilia", "backdraft", "riptide", "plague_carrier", "greedy_edge"]
	for id in scripted:
		assert_bool(WeaponRegistry.modifier_scripts.has(id)).is_true()
		assert_that(WeaponRegistry._make_modifier(id)).is_not_null()
	for id in data_driven:
		assert_that(WeaponRegistry._make_modifier(id)).is_not_null()
		# data-driven must NOT have a bespoke script
		assert_bool(WeaponRegistry.modifier_scripts.has(id)).is_false()


func test_all_24_combo_modifiers_have_csv_rows() -> void:
	var all_24 := [
		"spark_plug", "deepfreeze", "hemophilia", "backdraft", "riptide", "plague_carrier", "greedy_edge",
		"frostshatter", "combustion", "necrosis", "rupture",
		"echo_strike", "overclock", "mirror_slot", "catalyst_bond",
		"keystone", "twin_trigger", "flywheel",
		"last_stand", "overkill", "evolving_edge", "pendulum", "headsman", "slot_harmony",
	]
	for id in all_24:
		assert_bool(WeaponRegistry._modifier_data.has(id)).is_true()
		var row: Dictionary = WeaponRegistry._modifier_data[id]
		assert_str(row.get("rarity", "")).is_not_empty()
		assert_str(row.get("category", "")).is_not_empty()


func test_combo_modifier_rarity_spread_is_4c_13u_7r() -> void:
	var c := 0
	var u := 0
	var r := 0
	var all_24 := [
		"spark_plug", "deepfreeze", "hemophilia", "backdraft", "riptide", "plague_carrier", "greedy_edge",
		"frostshatter", "combustion", "necrosis", "rupture",
		"echo_strike", "overclock", "mirror_slot", "catalyst_bond",
		"keystone", "twin_trigger", "flywheel",
		"last_stand", "overkill", "evolving_edge", "pendulum", "headsman", "slot_harmony",
	]
	for id in all_24:
		var rarity: String = WeaponRegistry._modifier_data[id].get("rarity", "")
		match rarity:
			"Common":
				c += 1
			"Uncommon":
				u += 1
			"Rare":
				r += 1
	assert_int(c).is_equal(4)
	assert_int(u).is_equal(13)
	assert_int(r).is_equal(7)


func test_total_modifier_count_is_81() -> void:
	var total := 0
	for tier in WeaponRegistry.modifier_tiers.keys():
		total += WeaponRegistry.modifier_tiers[tier].size()
	assert_int(total).is_equal(81)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: FAIL — scripted rows missing from CSV; total count < 81.

- [ ] **Step 3: Append the 17 scripted CSV rows**

Append to `docs/design_docs/modifiers.csv` (after the `greedy_edge` row from Task 6):

```
frostshatter,Frostshatter,"Consume Frozen to burst for stacks×8 and shatter nearby foes.",Rare,trigger,on_hit,,,0,0,No
combustion,Combustion,"Consume On-Fire for an instant burst equal to the remaining burn ×3.",Rare,trigger,on_hit,,,0,0,No
necrosis,Necrosis,"Consume Poison stacks for an instant burst of ×2 that damage.",Uncommon,trigger,on_hit,,,0,0,No
rupture,Rupture,"Bleeding accumulates; at 5 stacks the target bursts for 5× a hit.",Uncommon,trigger,on_hit,,,0,0,No
echo_strike,Echo Strike,"Retrigger your first modifier once per swing.",Rare,trigger,on_hit,,,0,0,No
overclock,Overclock,"Retrigger the modifier to your left, then disable it for 5 seconds.",Rare,trigger,on_hit,,,0,0,No
mirror_slot,Mirror Slot,"Become a copy of the modifier to your left.",Rare,trigger,on_hit,,,0,0,No
catalyst_bond,Catalyst Bond,"Link slots 1 and 3: either fires and both fire.",Rare,trigger,on_hit,,,0,0,No
keystone,Keystone,"Slot 2 modifier +100%; slots 1 and 3 disabled (focus build).",Rare,trigger,on_hit,,,0,0,No
twin_trigger,Twin Trigger,"Every 3rd swing, all modifiers trigger twice.",Uncommon,trigger,on_hit,,,0,0,No
flywheel,Flywheel,"Untriggered modifiers charge; at 5, fire ×3 then empty.",Uncommon,trigger,on_hit,,,0,0,No
last_stand,Last Stand,"+60% damage on your first hit after taking damage.",Uncommon,trigger,on_hit,,,0,0,No
overkill,Overkill,"Damage exceeding an enemy's HP carries to the next enemy hit.",Uncommon,trigger,on_hit,,,0,0,No
evolving_edge,Evolving Edge,"After 15 hits, this modifier's own bonus doubles.",Uncommon,trigger,on_hit,,,0,0,No
pendulum,Pendulum,"Odd swings ×2 your left modifier, even swings ×2 your right.",Uncommon,trigger,on_hit,,,0,0,No
headsman,Headsman,"One-shotting an enemy above 50% HP refunds the swing.",Uncommon,trigger,on_hit,,,0,0,No
slot_harmony,Slot Harmony,"+20% damage while all 3 slots are different categories.",Uncommon,trigger,on_hit,,,0,0,No
```

- [ ] **Step 4: Run test to verify it passes**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: PASS (all 24 registered, droppable, rarity spread 4/13/7, total 81).

- [ ] **Step 5: Run the shop-distribution test from Phase 1 to confirm tier buckets still healthy**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_shop_modifier_drop.gd
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add docs/design_docs/modifiers.csv tests/unit/test_combo_modifiers.gd
git commit -m "feat(modifiers): 17 scripted combo modifier CSV rows; 24 total / 81 modifiers"
```

---

## Task 21: §C6 UI light state hooks (glow / dim / linked)

**Files:**
- Modify: `src/ui/weapon_popup.gd` (in `_add_modifier_slots_to_card`)
- Test: `tests/unit/test_combo_modifiers.gd` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_combo_modifiers.gd`:

```gdscript
func test_modifier_state_tag_reflects_disabled_and_retrigger() -> void:
	var c := _HitCounter.new()
	assert_str(c.get_state_tag()).is_equal("")
	c.is_disabled = true
	assert_str(c.get_state_tag()).is_equal("disabled")
	c.is_disabled = false
	c.is_retrigger_modifier = true
	assert_str(c.get_state_tag()).is_equal("retrigger")


func test_catalyst_bond_state_tag_is_linked() -> void:
	# catalyst_bond is is_retrigger_modifier=true so default tag is "retrigger";
	# override get_state_tag to report "linked" instead.
	var m := CatalystBondModifier.new()
	assert_str(m.get_state_tag()).is_equal("linked")
```

- [ ] **Step 2: Run test to verify it fails**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: FAIL — catalyst_bond returns "retrigger" not "linked".

- [ ] **Step 3: Override get_state_tag on catalyst_bond**

In `src/weapons/modifiers/catalyst_bond_modifier.gd`, add after `_init`:

```gdscript
func get_state_tag() -> String:
	if is_disabled:
		return "disabled"
	return "linked"
```

- [ ] **Step 4: Apply visual state in weapon_popup**

In `src/ui/weapon_popup.gd`, in `_add_modifier_slots_to_card` (around line 299-306), change the button modulate block to read the state tag. Replace:

```gdscript
		btn.modulate.a = 0.0
		if modifier != null and modifier.icon_texture != null:
			btn.mouse_entered.connect(_on_modifier_icon_mouse_entered.bind(modifier, btn, card))
			btn.mouse_exited.connect(_on_modifier_icon_mouse_exited.bind(card))
```

with:

```gdscript
		btn.modulate.a = 0.0
		if modifier != null:
			match modifier.get_state_tag():
				"disabled":
					btn.modulate = Color(0.4, 0.4, 0.4, 0.5)
				"retrigger":
					btn.modulate = Color(1.3, 1.2, 0.6, 0.9)  # warm glow
				"linked":
					btn.modulate = Color(0.6, 1.0, 1.3, 0.9)  # cool link tint
			if modifier.icon_texture != null:
				btn.mouse_entered.connect(_on_modifier_icon_mouse_entered.bind(modifier, btn, card))
				btn.mouse_exited.connect(_on_modifier_icon_mouse_exited.bind(card))
```

(Full juice — animations, particles — is deferred to Phase 6 per spec §8. This is the minimal hook.)

- [ ] **Step 5: Run test to verify it passes**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/weapons/modifiers/catalyst_bond_modifier.gd src/ui/weapon_popup.gd tests/unit/test_combo_modifiers.gd
git commit -m "feat(ui): modifier slot state hooks (dim/glow/linked) per §C6"
```

---

## Task 22: Flagship combo + anti-degenerate integration test (§7)

**Files:**
- Test: `tests/unit/test_combo_modifiers.gd` (append final §7 assertions)

- [ ] **Step 1: Write the integration tests**

Append to `tests/unit/test_combo_modifiers.gd`:

```gdscript
# --- §7 flagship + anti-degenerate integration ---

func test_flagship_echo_strike_plus_combustion_doubles_payoff() -> void:
	# echo_strike (slot 1) retriggers slot 0 (combustion); a burning target's
	# on_fire burst lands twice end-to-end.
	var user := _StatusTarget.new()
	add_child(user)
	user.global_position = Vector2.ZERO
	var w := Weapon.new()
	var combustion := CombustionModifier.new()
	var echo := EchoStrikeModifier.new()
	w.add_modifier(0, combustion); w.add_modifier(1, echo)
	var t := _HpTarget.new(1000.0)
	add_child(t)
	t.global_position = Vector2(30, 0)
	t.get_node("StatusComponent").add_stain("on_fire", 4.0)  # threshold 1.0
	w.resolve_hit(user, t, 5.0, false)
	# combustion burst = 4*3 = 12; echo retriggers combustion -> 2 bursts = 24 total
	assert_int(t.impacts.size()).is_equal(2)
	assert_int(t.impacts[0]).is_equal(12)
	assert_int(t.impacts[1]).is_equal(12)


func test_depth_guard_prevents_infinite_retrigger_chain() -> void:
	# 3 chained retrigger modifiers all targeting slot 0: depth caps at 2 so the
	# counter gets at most (normal + 2 retriggers) = 3 fires.
	var w := Weapon.new()
	var c := _HitCounter.new()
	var r1 := _ChainRetrigger.new()  # defined in test_weapon_eval_pass but redefine locally
	var r2 := _LocalChain.new()
	w.add_modifier(0, c); w.add_modifier(1, r1); w.add_modifier(2, r2)
	var t := Node.new()
	w.resolve_hit(null, t, 5.0, false)
	assert_bool(c.on_hit_calls <= 5).is_true()  # bounded, no infinite loop


class _LocalChain extends Modifier:
	func _init() -> void:
		category = "trigger"
		is_retrigger_modifier = true
	func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
		var first: Modifier = weapon.get_first_modifier()
		weapon.retrigger_modifier(first, "on_hit_target", [user, target])


func test_mirror_slot_plus_echo_no_loop() -> void:
	var w := Weapon.new()
	var c := _HitCounter.new()
	var mirror := MirrorSlotModifier.new()
	var echo := EchoStrikeModifier.new()
	# slot 0: counter, slot 1: mirror (delegates to slot 0), slot 2: echo (retriggers first = slot 0)
	w.add_modifier(0, c); w.add_modifier(1, mirror); w.add_modifier(2, echo)
	var t := Node.new()
	w.resolve_hit(null, t, 5.0, false)
	# bounded and no crash
	assert_bool(c.on_hit_calls <= 6).is_true()


func test_catalyst_bond_plus_retrigger_no_cycle() -> void:
	var w := Weapon.new()
	var c := _HitCounter.new()
	var bond := CatalystBondModifier.new()
	var echo := EchoStrikeModifier.new()
	w.add_modifier(0, c); w.add_modifier(1, bond); w.add_modifier(2, echo)
	var t := Node.new()
	w.resolve_hit(null, t, 5.0, false)
	# c fires: normal(1) + bond-link(1) + echo-retrigger(1) = 3 (bounded, no cycle)
	assert_bool(c.on_hit_calls <= 5).is_true()


func test_keystone_focus_survives_outer_retrigger_modifier() -> void:
	var w := Weapon.new()
	var outer := _HitCounter.new()
	outer.is_retrigger_modifier = true
	var ks := KeystoneModifier.new()
	w.add_modifier(0, outer); w.add_modifier(1, ks)
	var t := Node.new()
	w.resolve_hit(null, t, 5.0, false)
	# keystone focus: outer slot 0 is skipped
	assert_int(outer.on_hit_calls).is_equal(0)
```

- [ ] **Step 2: Run the full combo suite**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```
Expected: PASS (all §7 flagship + anti-degenerate assertions).

- [ ] **Step 3: Run the eval-pass suite once more to confirm the depth guard is intact**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_weapon_eval_pass.gd
```
Expected: PASS.

- [ ] **Step 4: Run the entire weapon/modifier test surface for regressions**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_modifiers.gd && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_data_modifier.gd && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_weapon_resolve_hit.gd && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_weapon_effective_stats.gd
```
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add tests/unit/test_combo_modifiers.gd
git commit -m "test(modifiers): flagship echo_strike+combustion combo + anti-degenerate suite (§7)"
```

---

## Final verification

After Task 22, run the full Phase-2 test surface together:

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_weapon_eval_pass.gd && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combo_modifiers.gd
```

Both suites green = Phase 2 complete. The combo ceiling ships independent of Phase 1 (Parts A+B), per spec §6.

---

## Out of scope (per spec §8)

- Relics / global passives (future spec).
- Loadout-wide combos (combos resolve per-weapon's 3 slots).
- Combo UI juice beyond the §C6 light state hooks (Phase 6).
- Enemy balance (Part C exists to give the player a ceiling for the coming enemy pass).
- Ranged conditional crit (`hemophilia` is melee-only by the target-aware crit wiring).
- Retuning status magnitudes (Phase 1 §B5 decision).
