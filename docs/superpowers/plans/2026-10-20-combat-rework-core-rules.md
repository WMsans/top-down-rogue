# Combat Rework — Plan 1: Core Rules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace HP/damage/crit combat with the hit-count model: the player has 3 HP + 3 regenerating armor, enemies die in hits (1 / 2 / 3 / boss 3×10), `damage` becomes terrain-only `dig_power`, and crit is gone.

**Architecture:** The player and enemies share one hit pipeline (`Weapon.resolve_hit` → `target.on_hit_impact`). We change it in layers so each task leaves the game runnable: status ticks first, then the player and enemy receivers, then the pipeline itself (crit out, damage out), then the `damage → dig_power` rename, then the HUD. Weapon/modifier *traits* (spec Parts D/E) are Plans 2 and 3; until then, damage/crit-based modifiers are inert.

**Tech Stack:** Godot 4.7, GDScript, gdUnit4 (headless).

**Spec:** `docs/superpowers/specs/2026-10-20-combat-rework-design.md` (Parts A1–A2, B, C, F). Rules summary: `docs/design_docs/gameplay.md` §2.

## Global Constraints

- Every hit is exactly 1, from any source: swing, projectile, explosion, status tick. Nothing deals 2 hits.
- No damage, no crit. `damage` becomes `dig_power` (terrain only). `crit_chance`, `crit_multiplier`, `crit_status` are deleted.
- Player: 3 HP, 3 armor. Hits and DoT ticks take armor first, then HP. HP never regenerates.
- Player i-frames 1.0s (hits only; DoT ticks bypass them). Armor regen: after 3.0s with no hit/tick, +1 armor per 1.0s.
- Enemies: normal 1 hit, elite 2, TANK elite 3, boss 3 phases × 10 hits. Elites and bosses share a 0.3s post-hit invulnerability.
- Status tick intervals: on_fire 1.0s, poisoned 1.5s, steam 1.0s. Each tick = 1 point / 1 hit.
- Item ids are stable. Do not rename `thunder_katana` or `twin_daggers` ids.
- `LavaDamageChecker` (`src/player/lava_damage_checker.gd`) is a debug tool. Do not touch it. Lava reaches the player only as On Fire.
- Match surrounding code style: tabs, typed GDScript, comment density of the file you're in.
- **Running tests:** the whole-directory run crashes Godot during suite scanning, so always run suites individually:
  ```bash
  godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/<suite>.gd
  ```
  Task 1 adds `tools/run_unit_suites.sh` to run many suites one by one.
- **Pre-existing failures** (fail on `master` before this work; not ours to fix unless a task says so): see `docs/superpowers/plans/2026-10-20-combat-rework-baseline.txt`, created in Task 1. A task is done when every suite it touches passes, except failures listed in the baseline for reasons unrelated to that task.

## Review Focus

1. **A hit landing during an elite's/boss's 0.3s invulnerability** must do nothing at all: no hit count change, no blood, no knockback, no on-kill, no on-hit status. (Task 4 test `test_invulnerable_hit_plays_no_reaction`, Task 6 test `test_resolve_hit_during_invuln_applies_no_status`.)
2. **Creative mode** must still make every hit lethal on enemies and refill the player instead of dying. (Task 3 `test_creative_mode_refills_instead_of_dying`, Task 4 `test_creative_mode_kills_in_one_hit`.)
3. **A large `delta` frame** (hitch, hit-stop) must still grant the correct number of status ticks and armor points, not one. (Task 2 `test_large_delta_delivers_multiple_ticks`, Task 3 `test_large_delta_grants_multiple_armor`.)
4. **Weapons and modifiers still loaded from CSV** after columns are renamed/removed: every weapon id must load with a `dig_power > 0` and no crit fields. (Task 7 `test_every_weapon_has_dig_power`.)
5. **HUD with changed max armor** (glass_cannon in Plan 3 drops it to 1): icon count must follow the maximum, not stay at 3. (Task 8 `test_shields_follow_max_armor`.)

---

## File Structure

| File | Change | Responsibility after this plan |
|---|---|---|
| `tools/run_unit_suites.sh` | Create | Run gdUnit suites one Godot process each; print a summary line per suite |
| `src/weapons/weapon.gd` | Modify | Hit pipeline: `resolve_hit(user, target)`, `hit_status`, `dig_power`; no crit |
| `src/status/status_def.gd` | Modify | `tick_interval` replaces `burn_dps` |
| `src/autoload/status_registry.gd` | Modify | Tick intervals, `get_tick_interval`, `get_ticking_ids` |
| `src/status/status_component.gd` | Modify | Per-status tick timers, stain caps, `clear_all()` |
| `src/player/player_inventory.gd` | Modify | 3 HP + 3 armor, `take_hit`, `take_status_tick`, regen |
| `src/player/player_controller.gd` | Modify | `on_hit_impact(point, dir)`, player stain caps |
| `src/enemies/enemy.gd` | Modify | `max_hits` / `hits_remaining` / `take_hit()` / 0.3s invuln |
| `src/enemies/boss_enemy.gd` | Modify | Hit pool, hit-count phases, status cleanse |
| `src/enemies/{melee,ranged,dummy,lunge}_enemy.gd` | Modify | Drop HP/damage fields |
| `src/core/spawn_dispatcher.gd` | Modify | Drop HP/damage floor scaling |
| `src/weapons/melee_weapon.gd`, `advanced_melee_weapon.gd`, `ranged_weapon.gd`, `projectile.gd`, `projectile_behaviors/*.gd`, `modifier.gd`, `modifiers/*.gd` | Modify | No crit, no damage in hits |
| `src/autoload/weapon_registry.gd` | Modify | Read `dig_power`, `hit_status`; no crit columns |
| `docs/design_docs/weapons.csv`, `modifiers.csv` | Modify | Column changes, dig values |
| `src/core/juice/hit_spec.gd`, `hit_reaction.gd`, `damage_vignette.gd` | Modify | No damage numbers / amounts |
| `src/ui/hud.gd`, `scenes/ui/hud.tscn` | Modify | Hearts + shields rows |
| `src/drops/weapon_drop.gd`, `src/ui/weapon_popup.gd`, `src/ui/chest_ui.gd` | Modify | "Dig" instead of "Damage"/"Crit" |

---

### Task 1: Per-suite test runner, baseline, and pre-attached modifier fix

`test_pre_attached_modifier_applied` and `test_flame_sword_has_lava_emitter` fail on `master` with `Invalid access to property or key 'name' on a base object of type 'Nil'`: weapons from the CSV come back with no modifier in slot 0. Suspected cause: `Weapon.find_empty_modifier_slot()` indexes `modifiers[i]` while `modifiers` is still an empty array, so it never returns a slot and `_apply_pre_attached_modifiers` skips the modifier.

**Files:**
- Create: `tools/run_unit_suites.sh`
- Create: `docs/superpowers/plans/2026-10-20-combat-rework-baseline.txt`
- Modify: `src/weapons/weapon.gd` (`find_empty_modifier_slot`, ~line 190)
- Test: `tests/unit/test_csv_weapon_data.gd`, `tests/unit/test_new_swords_load.gd`, `tests/unit/test_weapon_effective_stats.gd`

**Interfaces:**
- Produces: `tools/run_unit_suites.sh <out_file> <suite paths...>` — writes one line per suite: `<path> | <gdUnit "Overall Summary" line or "NO SUMMARY (crash/parse error)"> | <comma-separated failing test names>`; exits 1 if any suite has failures, errors, or no summary.

- [ ] **Step 1: Create the runner**

```bash
#!/bin/bash
# Runs gdUnit4 suites one Godot process at a time. A whole-directory run crashes
# Godot during suite scanning, so suites must be run individually.
# Usage: tools/run_unit_suites.sh <out_file> <suite.gd>...
set -u
out=$1; shift
: > "$out"
status=0
for f in "$@"; do
	r=$(timeout 120 godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
		--ignoreHeadlessMode -a "res://$f" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
	summ=$(echo "$r" | grep "Overall Summary" | tail -1)
	fails=$(echo "$r" | grep " FAILED" | sed 's/.*> //; s/ FAILED.*//' | tr '\n' ',')
	echo "$f | ${summ:-NO SUMMARY (crash/parse error)} | $fails" >> "$out"
	if [ -z "$summ" ] || ! echo "$summ" | grep -q "0 errors | 0 failures"; then
		status=1
	fi
done
exit $status
```

Run: `chmod +x tools/run_unit_suites.sh`

- [ ] **Step 2: Record the baseline**

Run (takes several minutes):
```bash
tools/run_unit_suites.sh docs/superpowers/plans/2026-10-20-combat-rework-baseline.txt $(ls tests/unit/test_*.gd)
grep -v "0 errors | 0 failures" docs/superpowers/plans/2026-10-20-combat-rework-baseline.txt
```
Expected: a list of failing suites that includes `test_csv_weapon_data.gd` (`test_pre_attached_modifier_applied`) and `test_new_swords_load.gd` (`test_flame_sword_has_lava_emitter`).

- [ ] **Step 3: Confirm the root cause**

Add this test to `tests/unit/test_weapon_effective_stats.gd`:

```gdscript
func test_find_empty_modifier_slot_on_fresh_weapon() -> void:
	var w := Weapon.new()
	assert_int(w.find_empty_modifier_slot()).is_equal(0)
```

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_weapon_effective_stats.gd`
Expected: FAIL (index out of bounds, or -1). If it passes, the cause is elsewhere: stop and use superpowers:systematic-debugging on `test_pre_attached_modifier_applied` before changing code.

- [ ] **Step 4: Fix `find_empty_modifier_slot`**

In `src/weapons/weapon.gd`:

```gdscript
func find_empty_modifier_slot() -> int:
	for i in range(modifier_slot_count):
		if i >= modifiers.size() or modifiers[i] == null:
			return i
	return -1
```

- [ ] **Step 5: Run the three suites**

Run `tools/run_unit_suites.sh /tmp/t1.txt tests/unit/test_weapon_effective_stats.gd tests/unit/test_csv_weapon_data.gd tests/unit/test_new_swords_load.gd; cat /tmp/t1.txt`
Expected: all three `0 errors | 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add tools/run_unit_suites.sh docs/superpowers/plans/2026-10-20-combat-rework-baseline.txt src/weapons/weapon.gd tests/unit/test_weapon_effective_stats.gd
git commit -m "fix: find empty modifier slot on unsized array; add per-suite test runner"
```

---

### Task 2: Per-status tick intervals

Today burn and poison share one `_burn_accum` driven by `burn_dps` (on_fire 4/s, poisoned 2/s; steam's 3/s is never applied). Replace with one timer per ticking status; each tick calls the owner's `apply_status_damage(1)`.

**Files:**
- Modify: `src/status/status_def.gd`
- Modify: `src/autoload/status_registry.gd`
- Modify: `src/status/status_component.gd`
- Test: `tests/unit/test_status_component.gd`, `tests/unit/test_status_registry.gd`, `tests/unit/test_poisoned_status.gd`

**Interfaces:**
- Produces:
  - `StatusDef.tick_interval: float` (0 = does not tick). Constructor parameter 7 is renamed `p_tick_interval`.
  - `StatusRegistry.get_tick_interval(id: String) -> float`, `StatusRegistry.get_ticking_ids() -> Array` (ids with `tick_interval > 0`, registration order).
  - `StatusComponent.set_stain_cap(id: String, cap: float) -> void`, `StatusComponent.clear_all() -> void`.
  - Owner contract unchanged: `apply_status_damage(amount: int)`, now always called with `1`, once per tick.
- Removes: `StatusDef.burn_dps`, `StatusRegistry.get_burn_dps()`, `StatusComponent._burn_accum`.

- [ ] **Step 1: Write the failing tests**

In `tests/unit/test_status_component.gd`, replace `test_burn_calls_owner_damage` and `test_burn_tick_emitted_on_whole_damage` with the tests below, and add the rest (`FakeOwner` and `_make_comp` already exist in the file):

```gdscript
func test_burn_calls_owner_damage() -> void:
	var owner: FakeOwner = auto_free(FakeOwner.new())
	add_child(owner)
	var c: StatusComponent = _make_comp(owner)
	c.add_stain("on_fire", 5.0)
	c.tick(1.0)  # on_fire ticks every 1.0s -> exactly one tick
	assert_that(owner.taken).is_equal(1)

func test_burn_tick_emitted_on_tick() -> void:
	var owner: FakeOwner = auto_free(FakeOwner.new())
	add_child(owner)
	var c: StatusComponent = _make_comp(owner)
	var flag := [false]
	c.burn_tick.connect(func() -> void: flag[0] = true)
	c.add_stain("on_fire", 5.0)
	c.tick(1.0)
	assert_bool(flag[0]).is_true()

func test_poison_ticks_every_one_and_a_half_seconds() -> void:
	var owner: FakeOwner = auto_free(FakeOwner.new())
	add_child(owner)
	var c: StatusComponent = _make_comp(owner)
	c.add_stain("poisoned", 5.0)
	c.tick(1.0)
	assert_that(owner.taken).is_equal(0)
	c.tick(0.5)
	assert_that(owner.taken).is_equal(1)

func test_steam_ticks() -> void:
	var owner: FakeOwner = auto_free(FakeOwner.new())
	add_child(owner)
	var c: StatusComponent = _make_comp(owner)
	c.add_stain("steam", 5.0)
	c.tick(1.0)
	assert_that(owner.taken).is_equal(1)

func test_statuses_tick_independently() -> void:
	var owner: FakeOwner = auto_free(FakeOwner.new())
	add_child(owner)
	var c: StatusComponent = _make_comp(owner)
	c.add_stain("on_fire", 5.0)
	c.add_stain("poisoned", 5.0)
	c.tick(1.5)  # fire: 1 tick (at 1.0); poison: 1 tick (at 1.5)
	assert_that(owner.taken).is_equal(2)

func test_large_delta_delivers_multiple_ticks() -> void:
	var owner: FakeOwner = auto_free(FakeOwner.new())
	add_child(owner)
	var c: StatusComponent = _make_comp(owner)
	c.add_stain("on_fire", 10.0)
	c.tick(3.0)
	assert_that(owner.taken).is_equal(3)

func test_tick_timer_restarts_after_status_ends() -> void:
	var owner: FakeOwner = auto_free(FakeOwner.new())
	add_child(owner)
	var c: StatusComponent = _make_comp(owner)
	c.add_stain("on_fire", 1.5)
	c.tick(0.6)  # decays to 0.9 -> below threshold 1.0, timer discarded
	c.add_stain("on_fire", 5.0)
	c.tick(0.6)  # fresh timer at 0.6 -> no tick yet
	assert_that(owner.taken).is_equal(0)

func test_stain_cap_clamps_added_stain() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.set_stain_cap("on_fire", 3.0)
	c.add_stain("on_fire", 10.0)
	assert_float(c.get_stain("on_fire")).is_equal_approx(3.0, 0.001)

func test_stain_cap_clamps_existing_stain() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("on_fire", 10.0)
	c.set_stain_cap("on_fire", 3.0)
	assert_float(c.get_stain("on_fire")).is_equal_approx(3.0, 0.001)

func test_clear_all_removes_stains_and_timed() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("on_fire", 5.0)
	c.add_timed_status("stun", 1.0)
	c.clear_all()
	assert_float(c.get_stain("on_fire")).is_equal(0.0)
	assert_bool(c.is_stunned()).is_false()
```

In `tests/unit/test_status_registry.gd`:
- In `test_on_fire_def_values`, replace `assert_float(StatusRegistry.get_burn_dps("on_fire")).is_equal_approx(4.0, 0.001)` with `assert_float(StatusRegistry.get_tick_interval("on_fire")).is_equal_approx(1.0, 0.001)`.
- In `test_steam_status_def`, replace `assert_float(def.burn_dps).is_equal(3.0)` with `assert_float(def.tick_interval).is_equal(1.0)`.
- In `test_lightning_status_def`, replace `assert_float(def.burn_dps).is_equal(0.0)` with `assert_float(def.tick_interval).is_equal(0.0)`.
- Add:

```gdscript
func test_ticking_ids_are_fire_poison_steam() -> void:
	assert_array(StatusRegistry.get_ticking_ids()).contains_exactly(["on_fire", "poisoned", "steam"])
```

In `tests/unit/test_poisoned_status.gd`:
- In `test_poisoned_properties`, replace `assert_that(def.burn_dps).is_equal(2.0)` with `assert_that(def.tick_interval).is_equal(1.5)`.
- Rename `test_poisoned_burn_dps` to `test_poisoned_tick_interval` and make its body:

```gdscript
	assert_float(StatusRegistry.get_tick_interval("poisoned")).is_equal_approx(1.5, 0.001)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `tools/run_unit_suites.sh /tmp/t2.txt tests/unit/test_status_component.gd tests/unit/test_status_registry.gd tests/unit/test_poisoned_status.gd; cat /tmp/t2.txt`
Expected: failures / parse errors (`get_tick_interval`, `set_stain_cap`, `clear_all`, `tick_interval` don't exist).

- [ ] **Step 3: Rename the field in `StatusDef`**

In `src/status/status_def.gd`, rename `burn_dps` to `tick_interval` (field, comment, constructor parameter `p_burn_dps` → `p_tick_interval`, assignment):

```gdscript
var tick_interval: float    # > 0 means costs 1 point every tick_interval seconds while active
```

- [ ] **Step 4: Update the registry**

In `src/autoload/status_registry.gd`, `_register_defs()`: the 7th constructor argument becomes the tick interval. Change on_fire `4.0` → `1.0`, poisoned `2.0` → `1.5`, steam `3.0` → `1.0`. Every other def already passes `0.0`. Then replace `get_burn_dps`:

```gdscript
var _ticking_ids: Array = []  # ids with tick_interval > 0, registration order


func _add(def: StatusDef) -> void:
	_defs[def.id] = def
	if def.tick_interval > 0.0:
		_ticking_ids.append(def.id)


func get_tick_interval(id: String) -> float:
	var d: StatusDef = _defs.get(id, null)
	return d.tick_interval if d != null else 0.0


func get_ticking_ids() -> Array:
	return _ticking_ids
```

(Put `_ticking_ids` next to `_defs`; replace the existing `_add`.)

Run `grep -rn "burn_dps\|get_burn_dps" src tests` — expected: no results.

- [ ] **Step 5: Rewrite ticking in `StatusComponent`**

In `src/status/status_component.gd`:

1. Update the header comment line "applies effects (burn DoT, ...)" to "applies effects (status ticks, ...)".
2. Replace `var _burn_accum: float = 0.0` with:

```gdscript
var _tick_timers: Dictionary = {}  # ticking status id -> seconds active since its last tick
var _stain_caps: Dictionary = {}   # id -> max stain (absent = uncapped)
```

3. Change `add_stain`:

```gdscript
func add_stain(id: String, amount: float) -> void:
	if amount == 0.0:
		return
	_stains[id] = clampf(get_stain(id) + amount, 0.0, _stain_caps.get(id, INF))
	changed.emit()
```

4. Add after `clear(id)`:

```gdscript
func clear_all() -> void:
	_stains.clear()
	_timed_statuses.clear()
	_tick_timers.clear()
	changed.emit()


func set_stain_cap(id: String, cap: float) -> void:
	_stain_caps[id] = cap
	if get_stain(id) > cap:
		_stains[id] = cap
		changed.emit()
```

5. In `tick()`, change the idle fast path condition to `if _stains.is_empty() and _tick_timers.is_empty() and _timed_statuses.is_empty():` and update its comment ("no burn in flight" → "no tick in flight").
6. Replace `_apply_effects`:

```gdscript
func _apply_effects(delta: float) -> void:
	for id in StatusRegistry.get_ticking_ids():
		if not has_status(id):
			_tick_timers.erase(id)
			continue
		var interval: float = StatusRegistry.get_tick_interval(id)
		var t: float = _tick_timers.get(id, 0.0) + delta
		while t >= interval:
			t -= interval
			burn_tick.emit()
			if _owner_node != null and _owner_node.has_method("apply_status_damage"):
				_owner_node.apply_status_damage(1)
		_tick_timers[id] = t
```

7. Update the `burn_tick` signal comment to `# emitted on every status tick (fire, poison, steam)`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `tools/run_unit_suites.sh /tmp/t2.txt tests/unit/test_status_component.gd tests/unit/test_status_registry.gd tests/unit/test_poisoned_status.gd tests/unit/test_status_reactions.gd tests/unit/test_status_thresholds.gd tests/unit/test_status_visuals.gd; cat /tmp/t2.txt`
Expected: all `0 errors | 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add src/status src/autoload/status_registry.gd tests/unit/test_status_component.gd tests/unit/test_status_registry.gd tests/unit/test_poisoned_status.gd
git commit -m "feat(status): per-status tick intervals, stain caps, clear_all"
```

---

### Task 3: Player armor + HP

**Files:**
- Modify: `src/player/player_inventory.gd` (health section, `_ready`, `_physics_process`, signals)
- Modify: `src/player/player_controller.gd` (`on_hit_impact`, `apply_status_damage`, `_play_zoom_punch`, status setup in `_ready` ~line 84)
- Test: `tests/unit/test_player_inventory.gd`, `tests/unit/test_player_health_fraction.gd`, `tests/unit/test_player_controller.gd`

**Interfaces:**
- Consumes: `StatusComponent.set_stain_cap(id, cap)` (Task 2).
- Produces (`PlayerInventory`):
  - `signal armor_changed(current: int, maximum: int)`
  - `@export var max_health: int = 3`, `@export var max_armor: int = 3`
  - `const ARMOR_REGEN_DELAY := 3.0`, `const ARMOR_REGEN_INTERVAL := 1.0`
  - `take_hit(hit_direction: Vector2 = Vector2.ZERO) -> void` — respects i-frames, costs 1 point, plays hit reaction.
  - `take_status_tick() -> void` — bypasses i-frames, costs 1 point, no hit reaction.
  - `get_armor() -> int`, `get_max_armor() -> int`, `set_max_armor(value: int) -> void`, `skip_armor_regen_delay() -> void`
  - Unchanged: `heal(amount)`, `get_health()`, `get_max_health()`, `get_health_fraction()`, `is_dead()`, `health_changed`, `damaged(amount)` (always 1), `player_died`.
- Produces (`PlayerController`): `on_hit_impact(impact_point: Vector2, hit_dir: Vector2, _damage: int = 0)` — the damage parameter is ignored and is removed in Task 6. `apply_status_damage(amount: int)` calls `take_status_tick()` `amount` times.
- Removes: `PlayerInventory.take_damage`, `PlayerInventory.take_status_damage`.

- [ ] **Step 1: Write the failing tests**

Replace the four health tests in `tests/unit/test_player_inventory.gd` (`test_take_damage_reduces_health`, `test_take_damage_does_not_go_below_zero`, `test_invincibility_prevents_double_damage`, `test_heal_restores_health`) and `test_take_status_damage_emits_damaged_signal` with:

```gdscript
func _inv() -> PlayerInventory:
	var inv: PlayerInventory = auto_free(PlayerInventory.new())
	add_child(inv)  # _ready fills health and armor
	return inv


func test_starts_with_three_hp_and_three_armor() -> void:
	var inv := _inv()
	assert_int(inv.get_health()).is_equal(3)
	assert_int(inv.get_armor()).is_equal(3)


func test_hit_takes_armor_first() -> void:
	var inv := _inv()
	inv.take_hit()
	assert_int(inv.get_armor()).is_equal(2)
	assert_int(inv.get_health()).is_equal(3)


func test_hit_takes_hp_when_armor_empty() -> void:
	var inv := _inv()
	for i in range(3):
		inv.take_status_tick()
	inv.take_hit()
	assert_int(inv.get_armor()).is_equal(0)
	assert_int(inv.get_health()).is_equal(2)


func test_invincibility_blocks_second_hit() -> void:
	var inv := _inv()
	inv.take_hit()
	inv.take_hit()
	assert_int(inv.get_armor()).is_equal(2)


func test_status_tick_ignores_invincibility() -> void:
	var inv := _inv()
	inv.take_hit()
	inv.take_status_tick()
	assert_int(inv.get_armor()).is_equal(1)


func test_dies_after_six_points() -> void:
	var inv := _inv()
	var monitor = monitor_signals(inv)
	for i in range(6):
		inv.take_status_tick()
	assert_int(inv.get_health()).is_equal(0)
	assert_bool(inv.is_dead()).is_true()
	await assert_signal(monitor).is_emitted("player_died")


func test_creative_mode_refills_instead_of_dying() -> void:
	var inv := _inv()
	GameModeManager.set_mode(GameModeManager.Mode.CREATIVE)
	for i in range(6):
		inv.take_status_tick()
	GameModeManager.set_mode(GameModeManager.Mode.SURVIVAL)
	assert_bool(inv.is_dead()).is_false()
	assert_int(inv.get_health()).is_equal(3)
	assert_int(inv.get_armor()).is_equal(3)


func test_armor_regen_waits_for_delay() -> void:
	var inv := _inv()
	inv.take_status_tick()
	inv._physics_process(2.9)
	assert_int(inv.get_armor()).is_equal(2)
	inv._physics_process(0.1)
	assert_int(inv.get_armor()).is_equal(3)


func test_armor_regen_one_point_per_interval() -> void:
	var inv := _inv()
	for i in range(3):
		inv.take_status_tick()
	inv._physics_process(3.0)
	assert_int(inv.get_armor()).is_equal(1)
	inv._physics_process(0.99)
	assert_int(inv.get_armor()).is_equal(1)
	inv._physics_process(0.01)
	assert_int(inv.get_armor()).is_equal(2)


func test_large_delta_grants_multiple_armor() -> void:
	var inv := _inv()
	for i in range(3):
		inv.take_status_tick()
	inv._physics_process(5.0)  # points at 3.0, 4.0, 5.0
	assert_int(inv.get_armor()).is_equal(3)


func test_any_point_loss_resets_regen_delay() -> void:
	var inv := _inv()
	inv.take_status_tick()
	inv._physics_process(2.5)
	inv.take_status_tick()
	inv._physics_process(2.9)
	assert_int(inv.get_armor()).is_equal(1)
	inv._physics_process(0.1)
	assert_int(inv.get_armor()).is_equal(2)


func test_hp_never_regenerates() -> void:
	var inv := _inv()
	for i in range(4):
		inv.take_status_tick()
	inv._physics_process(20.0)
	assert_int(inv.get_health()).is_equal(2)
	assert_int(inv.get_armor()).is_equal(3)


func test_skip_armor_regen_delay() -> void:
	var inv := _inv()
	inv.take_status_tick()
	inv.skip_armor_regen_delay()
	inv._physics_process(0.01)
	assert_int(inv.get_armor()).is_equal(3)


func test_set_max_armor_clamps_current() -> void:
	var inv := _inv()
	inv.set_max_armor(1)
	assert_int(inv.get_max_armor()).is_equal(1)
	assert_int(inv.get_armor()).is_equal(1)


func test_heal_restores_hp_clamped() -> void:
	var inv := _inv()
	for i in range(5):
		inv.take_status_tick()
	inv.heal(5)
	assert_int(inv.get_health()).is_equal(3)


func test_point_loss_emits_damaged_one() -> void:
	var inv := _inv()
	var monitor = monitor_signals(inv)
	inv.take_status_tick()
	await assert_signal(monitor).is_emitted("damaged", [1])
	await assert_signal(monitor).is_emitted("armor_changed", [2, 3])
```

Replace `tests/unit/test_player_health_fraction.gd` with:

```gdscript
# tests/unit/test_player_health_fraction.gd
extends GdUnitTestSuite


func test_full_health_is_one() -> void:
	var inv: PlayerInventory = auto_free(PlayerInventory.new())
	add_child(inv)
	assert_float(inv.get_health_fraction()).is_equal_approx(1.0, 0.001)


func test_fraction_ignores_armor() -> void:
	var inv: PlayerInventory = auto_free(PlayerInventory.new())
	add_child(inv)
	inv.take_status_tick()  # armor 3 -> 2, HP untouched
	assert_float(inv.get_health_fraction()).is_equal_approx(1.0, 0.001)


func test_fraction_scales_with_hp() -> void:
	var inv: PlayerInventory = auto_free(PlayerInventory.new())
	add_child(inv)
	for i in range(4):
		inv.take_status_tick()  # 3 armor, then 1 HP
	assert_float(inv.get_health_fraction()).is_equal_approx(2.0 / 3.0, 0.01)
```

In `tests/unit/test_player_controller.gd`, `test_on_hit_impact_delegates_to_inventory`: change the call to `controller.on_hit_impact(Vector2.ZERO, Vector2.RIGHT)` and the assertion to `assert_that(inventory.get_armor()).is_equal(2)`. Read the test first: if it builds the inventory without `_ready`, add it to the tree (`add_child`) so armor starts at 3.

- [ ] **Step 2: Run tests to verify they fail**

Run: `tools/run_unit_suites.sh /tmp/t3.txt tests/unit/test_player_inventory.gd tests/unit/test_player_health_fraction.gd tests/unit/test_player_controller.gd; cat /tmp/t3.txt`
Expected: failures (`take_hit`, `get_armor` missing).

- [ ] **Step 3: Rewrite the health section of `PlayerInventory`**

In `src/player/player_inventory.gd`:

Signals and exports:

```gdscript
signal health_changed(current: int, maximum: int)
signal armor_changed(current: int, maximum: int)
```

```gdscript
@export var max_health: int = 3
@export var max_armor: int = 3
@export var invincibility_duration: float = 1.0

const BLINK_INTERVAL := 0.08
const DAMAGE_COLOR := Color(1.0, 0.25, 0.08)
const MAX_WEAPON_SLOTS := 3
# Armor comes back after ARMOR_REGEN_DELAY seconds without losing a point,
# then +1 every ARMOR_REGEN_INTERVAL. HP never regenerates.
const ARMOR_REGEN_DELAY := 3.0
const ARMOR_REGEN_INTERVAL := 1.0
```

State (next to `_current_health`):

```gdscript
var _current_armor: int
var _regen_timer: float = 0.0  # seconds since the last point was lost
var _regen_next_at: float = ARMOR_REGEN_DELAY  # _regen_timer value that grants the next armor point
```

In `_ready()`, after `_current_health = max_health`, add `_current_armor = max_armor`.

At the end of `_physics_process(delta)` (after the invincibility block), add `_tick_armor_regen(delta)`, and add:

```gdscript
func _tick_armor_regen(delta: float) -> void:
	if _is_dead:
		return
	if _current_armor >= max_armor:
		_regen_timer = 0.0
		_regen_next_at = ARMOR_REGEN_DELAY
		return
	_regen_timer += delta
	while _regen_timer >= _regen_next_at and _current_armor < max_armor:
		_current_armor += 1
		_regen_next_at += ARMOR_REGEN_INTERVAL
		armor_changed.emit(_current_armor, max_armor)
```

Replace everything from `func take_damage(` through the end of `func take_status_damage(...)` with:

```gdscript
func take_hit(hit_direction: Vector2 = Vector2.ZERO) -> void:
	if _is_dead or _is_invincible:
		return
	_is_invincible = true
	_invincible_timer = invincibility_duration
	var player := get_parent()
	if player is Node2D:
		var spec := HitSpec.new()
		spec.position = (player as Node2D).global_position
		spec.direction = hit_direction
		spec.damage = 1.0
		spec.is_kill = _current_armor == 0 and _current_health <= 1
		spec.source_color = DAMAGE_COLOR
		HitReaction.play(spec)
		if HitReaction.vignette:
			HitReaction.vignette.pulse(1.0)
	_lose_point()


func take_status_tick() -> void:
	# Damage-over-time path: bypasses invincibility frames and the heavy hit
	# reaction. Still takes armor first and still triggers death.
	if _is_dead:
		return
	_lose_point()


func _lose_point() -> void:
	if _current_armor > 0:
		_current_armor -= 1
		armor_changed.emit(_current_armor, max_armor)
	else:
		_current_health = maxi(_current_health - 1, 0)
		health_changed.emit(_current_health, max_health)
	_regen_timer = 0.0
	_regen_next_at = ARMOR_REGEN_DELAY
	damaged.emit(1)
	if _current_health <= 0:
		_on_health_depleted()


func _on_health_depleted() -> void:
	if GameModeManager.is_creative():
		_current_health = max_health
		_current_armor = max_armor
		health_changed.emit(_current_health, max_health)
		armor_changed.emit(_current_armor, max_armor)
		return
	_is_dead = true
	if _color_rect:
		_color_rect.visible = true
	player_died.emit()
```

(`spec.damage` and `pulse(1.0)` are removed in Task 8.)

After `get_max_health()`, add:

```gdscript
func get_armor() -> int:
	return _current_armor


func get_max_armor() -> int:
	return max_armor


func set_max_armor(value: int) -> void:
	max_armor = maxi(0, value)
	_current_armor = mini(_current_armor, max_armor)
	armor_changed.emit(_current_armor, max_armor)


func skip_armor_regen_delay() -> void:
	_regen_timer = maxf(_regen_timer, _regen_next_at)
```

Change `heal` to ignore non-positive amounts:

```gdscript
func heal(amount: int) -> void:
	if _is_dead or amount <= 0:
		return
	_current_health = mini(_current_health + amount, max_health)
	health_changed.emit(_current_health, max_health)
```

- [ ] **Step 4: Update `PlayerController`**

In `src/player/player_controller.gd`:

```gdscript
func on_hit_impact(impact_point: Vector2, hit_dir: Vector2, _damage: int = 0) -> void:
	if hit_dir.length_squared() > 0.0001:
		apply_knockback(hit_dir, KNOCKBACK_SPEED)

	_play_hit_flash()
	_play_squash()
	_play_zoom_punch()

	var inventory := get_node_or_null("PlayerInventory")
	if inventory:
		inventory.take_hit(hit_dir)


func apply_status_damage(amount: int) -> void:
	var inventory := get_node_or_null("PlayerInventory")
	if inventory:
		for _i in range(amount):
			inventory.take_status_tick()
```

Every hit now matters, so the zoom punch always plays. Delete `const ZOOM_PUNCH_THRESHOLD := 10.0`, change the signature to `func _play_zoom_punch() -> void:`, and delete its two-line threshold guard (`if damage < ZOOM_PUNCH_THRESHOLD: return`).

Cap the player's harmful stains so a typical burn costs ~2 points. Add near the other constants:

```gdscript
# Max stain per ticking status on the player: on_fire (decay 1.0/s, threshold 1.0)
# stays active ~2s from cap; poisoned (0.4/s, 0.3) ~3s; steam (1.2/s, 1.0) ~2s.
# Each is ~2 ticks.
const PLAYER_STAIN_CAPS := {"on_fire": 3.0, "poisoned": 1.5, "steam": 3.4}
```

In `_ready()`, right after `add_child(status)` (~line 86):

```gdscript
	for id in PLAYER_STAIN_CAPS:
		status.set_stain_cap(id, PLAYER_STAIN_CAPS[id])
```

- [ ] **Step 5: Fix remaining callers**

Run: `grep -rn "take_damage\|take_status_damage" src tests`
Expected: no results. Any hit is a production caller that must call `take_hit(dir)` or `take_status_tick()` instead.

- [ ] **Step 6: Run tests to verify they pass**

Run: `tools/run_unit_suites.sh /tmp/t3.txt tests/unit/test_player_inventory.gd tests/unit/test_player_health_fraction.gd tests/unit/test_player_controller.gd tests/unit/test_player_dash.gd tests/unit/test_damage_vignette.gd tests/unit/test_berserker_axe_weapon.gd; cat /tmp/t3.txt`
Expected: all `0 errors | 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add src/player tests/unit/test_player_inventory.gd tests/unit/test_player_health_fraction.gd tests/unit/test_player_controller.gd
git commit -m "feat(player): 3 HP + 3 regenerating armor; hits and ticks cost one point"
```

---

### Task 4: Enemy hit model

**Files:**
- Modify: `src/enemies/enemy.gd`
- Modify: `src/enemies/boss_enemy.gd`
- Modify: `src/enemies/melee_enemy.gd`, `src/enemies/ranged_enemy.gd`, `src/enemies/dummy_enemy.gd`, `src/enemies/lunge_enemy.gd`
- Modify: `src/core/spawn_dispatcher.gd` (~lines 228–241)
- Modify: `src/weapons/weapon.gd` (`resolve_hit` kill detection only)
- Test: `tests/unit/test_enemy_state_machine.gd`, `tests/unit/test_boss_phase_transition.gd`, plus fake-target migration (Step 6)

**Interfaces:**
- Consumes: `StatusComponent.clear_all()` (Task 2).
- Produces (`Enemy`):
  - `signal hits_changed(remaining: int, maximum: int)` (replaces `health_changed`)
  - `@export var max_hits: int = 1`, `var hits_remaining: int`
  - `const HIT_INVULN := 0.3`, `var _hit_invuln_timer: float`
  - `take_hit() -> void` (replaces `hit(damage)`), `is_hit_invulnerable() -> bool`, `_tick_hit_invuln(delta: float) -> void`
  - `apply_status_damage(amount: int)` — each call spends one hit (quiet: no HURT state).
  - `on_hit_impact(impact_point: Vector2, hit_dir: Vector2, _damage: int = 0)` — damage ignored; parameter removed in Task 6.
- Produces (`BossEnemy`): `const HITS_PER_PHASE := 10`; `_phase_threshold(p: int) -> int` returns a remaining-hits threshold.
- Produces (`Weapon.resolve_hit`): `on_kill` fires when `target.hits_remaining` goes from > 0 to <= 0.
- Removes: `Enemy.max_health`, `Enemy.health`, `Enemy.damage_scale`, `Enemy._apply_damage_scale()`, `Enemy.hit()`, `LungeEnemy.dash_damage`.

- [ ] **Step 1: Write the failing enemy tests**

In `tests/unit/test_enemy_state_machine.gd`, replace `test_hurt_re_staggerable`, `test_death_on_zero_health`, `test_elite_stat_scaling`, `test_elite_tank_speed`, `test_elite_fast_windup_floor` and delete `test_damage_scale_multiplies_weapon_damage_on_ready`. Add:

```gdscript
func test_hurt_re_staggerable() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.max_hits = 3
	e.hits_remaining = 3
	e._state = Enemy.State.CHASE
	e._state_timer = 0.1
	e.take_hit()
	assert_that(e._state).is_equal(Enemy.State.HURT)
	e._hit_invuln_timer = 0.0
	e._state_timer = 0.05
	e.take_hit()
	assert_that(e._state_timer).is_equal(e.hurt_duration)

func test_normal_enemy_dies_to_one_hit() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.hits_remaining = 1
	e.take_hit()
	assert_that(e._state).is_equal(Enemy.State.DEATH)

func test_creative_mode_kills_in_one_hit() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.max_hits = 3
	e.hits_remaining = 3
	GameModeManager.set_mode(GameModeManager.Mode.CREATIVE)
	e.take_hit()
	GameModeManager.set_mode(GameModeManager.Mode.SURVIVAL)
	assert_that(e._state).is_equal(Enemy.State.DEATH)

func test_elite_takes_two_hits() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.speed = 100.0
	e.is_elite = true
	e._apply_elite_scaling()
	assert_int(e.max_hits).is_equal(2)
	assert_int(e.hits_remaining).is_equal(2)
	assert_that(e.speed).is_greater(100.0)

func test_elite_tank_takes_three_hits_and_is_slow() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.speed = 100.0
	e._speed_base = 100.0
	e.is_elite = true
	e.elite_ability = Enemy.EliteAbility.TANK
	e._apply_elite_scaling()
	assert_int(e.max_hits).is_equal(3)
	assert_that(e.speed).is_equal(70.0)

func test_elite_fast_windup_floor() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.windup_duration = 0.3
	e.is_elite = true
	e.elite_ability = Enemy.EliteAbility.FAST
	e._apply_elite_scaling()
	assert_that(e.windup_duration).is_equal(0.2)

func test_elite_invulnerable_after_first_hit() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.max_hits = 2
	e.hits_remaining = 2
	e.take_hit()
	e.take_hit()  # inside the 0.3s window: ignored
	assert_int(e.hits_remaining).is_equal(1)
	e._tick_hit_invuln(0.31)
	e.take_hit()
	assert_that(e._state).is_equal(Enemy.State.DEATH)

func test_invulnerable_hit_plays_no_reaction() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.max_hits = 2
	e.hits_remaining = 2
	e.take_hit()
	e._knockback_velocity = Vector2.ZERO
	e.on_hit_impact(Vector2.ZERO, Vector2.RIGHT)
	assert_int(e.hits_remaining).is_equal(1)
	assert_that(e._knockback_velocity).is_equal(Vector2.ZERO)

func test_status_tick_spends_a_hit_without_hurt() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.max_hits = 2
	e.hits_remaining = 2
	e._state = Enemy.State.CHASE
	e.apply_status_damage(1)
	assert_int(e.hits_remaining).is_equal(1)
	assert_that(e._state).is_equal(Enemy.State.CHASE)

func test_status_tick_respects_invuln() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.max_hits = 2
	e.hits_remaining = 2
	e.take_hit()
	e.apply_status_damage(1)
	assert_int(e.hits_remaining).is_equal(1)

func test_enrage_triggers_on_first_hit() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.is_elite = true
	e.elite_ability = Enemy.EliteAbility.ENRAGE
	e.max_hits = 2
	e.hits_remaining = 2
	e.speed = 100.0
	e._apply_enrage_if_needed()
	assert_that(e.speed).is_equal(100.0)
	e.take_hit()
	e._apply_enrage_if_needed()
	e._apply_enrage_if_needed()  # applies once
	assert_that(e.speed).is_equal(150.0)
```

- [ ] **Step 2: Write the failing boss tests**

Replace `test_boss_phase_threshold_values` and `test_phase_chaining_on_burst_damage` in `tests/unit/test_boss_phase_transition.gd` and add the rest:

```gdscript
func test_boss_phase_threshold_values() -> void:
	var b := auto_free(TestBoss.new())
	b.phase_count = 3
	assert_that(b._phase_threshold(2)).is_equal(20)
	assert_that(b._phase_threshold(3)).is_equal(10)

func test_phase_chaining_on_burst() -> void:
	var b := auto_free(TestBoss.new())
	b.phase_count = 3
	b.max_hits = 30
	b.current_phase = 1
	b.hits_remaining = 5
	b._check_phase_transition()
	assert_that(b.current_phase).is_equal(3)
	assert_that(b.transition_log).is_equal([2, 3])

func test_take_hit_advances_phase() -> void:
	var b := auto_free(TestBoss.new())
	b.phase_count = 3
	b.max_hits = 30
	b.hits_remaining = 21
	b.current_phase = 1
	b.weapon = RangedWeapon.new()
	b.take_hit()
	assert_int(b.hits_remaining).is_equal(20)
	assert_that(b.current_phase).is_equal(2)

func test_status_tick_advances_phase() -> void:
	var b := auto_free(TestBoss.new())
	b.phase_count = 3
	b.max_hits = 30
	b.hits_remaining = 21
	b.current_phase = 1
	b.weapon = RangedWeapon.new()
	b.apply_status_damage(1)
	assert_that(b.current_phase).is_equal(2)

func test_phase_transition_clears_statuses() -> void:
	var b := auto_free(TestBoss.new())
	var sc: StatusComponent = auto_free(StatusComponent.new())
	b._status_component = sc
	sc.add_stain("on_fire", 5.0)
	b.weapon = RangedWeapon.new()
	b.current_phase = 2
	b._transition_phase()
	assert_float(sc.get_stain("on_fire")).is_equal(0.0)
```

`TestBoss` overrides `_ready()` with `pass`, so these tests set `max_hits` themselves.

- [ ] **Step 3: Run tests to verify they fail**

Run: `tools/run_unit_suites.sh /tmp/t4.txt tests/unit/test_enemy_state_machine.gd tests/unit/test_boss_phase_transition.gd; cat /tmp/t4.txt`
Expected: failures / parse errors (`max_hits`, `take_hit` don't exist). `test_boss_phase_transition.gd` is `NO SUMMARY` in the baseline; after this task it must pass.

- [ ] **Step 4: Implement the hit model in `Enemy`**

In `src/enemies/enemy.gd`:

1. `signal health_changed(current: int, maximum: int)` → `signal hits_changed(remaining: int, maximum: int)`.
2. `@export var max_health: int = 20` → `@export var max_hits: int = 1`. Delete `@export var damage_scale: float = 1.0`.
3. After the `PASSIVE_COOLDOWN_MULT` const, add:

```gdscript
# Multi-hit enemies (elites, bosses) ignore further hits for this long after
# taking one, so fans and multi-strikes can't spend several hits at once.
const HIT_INVULN: float = 0.3
```

4. `var health: int` → `var hits_remaining: int`, and add `var _hit_invuln_timer: float = 0.0` below it.
5. In `_ready()`: `health = max_health` → `hits_remaining = max_hits`; delete the `_apply_damage_scale()` call.
6. Replace `_apply_elite_scaling()`:

```gdscript
func _apply_elite_scaling() -> void:
	max_hits = 3 if elite_ability == EliteAbility.TANK else 2
	hits_remaining = max_hits
	speed *= 1.3
	scale *= 1.3

	match elite_ability:
		EliteAbility.FAST:
			windup_duration = maxf(0.2, windup_duration * 0.5)
			cooldown_duration *= 0.5
		EliteAbility.TANK:
			speed = _speed_base * 0.7
		EliteAbility.ENRAGE:
			pass  # applied in _apply_enrage_if_needed after the first hit
```

7. Delete `_apply_damage_scale()`.
8. Replace `_apply_enrage_if_needed()`:

```gdscript
func _apply_enrage_if_needed() -> void:
	if not is_elite or elite_ability != EliteAbility.ENRAGE:
		return
	if _elite_enraged or hits_remaining >= max_hits:
		return
	_elite_enraged = true
	speed *= 1.5
```

9. At the top of `_process(delta)` (before the DEATH check), add `_tick_hit_invuln(delta)`, and add the function after `_process`:

```gdscript
func _tick_hit_invuln(delta: float) -> void:
	if _hit_invuln_timer > 0.0:
		_hit_invuln_timer = maxf(0.0, _hit_invuln_timer - delta)


func is_hit_invulnerable() -> bool:
	return _hit_invuln_timer > 0.0
```

10. Replace `hit(damage)` and `apply_status_damage(amount)`:

```gdscript
func take_hit() -> void:
	if not _consume_hit():
		return
	_on_hit()
	if _state == State.DEATH:
		return
	if _state != State.HURT:
		_prev_state = _state
	_state = State.HURT
	_state_timer = hurt_duration


func apply_status_damage(amount: int) -> void:
	# Quiet DoT path: spends hits without forcing HURT state.
	for _i in range(amount):
		if not _consume_hit():
			return
		_play_hit_flash()


# Spends one hit. Returns false when the hit is ignored (already dead or
# inside the post-hit invulnerability window).
func _consume_hit() -> bool:
	if _state == State.DEATH or hits_remaining <= 0 or is_hit_invulnerable():
		return false
	hits_remaining = 0 if GameModeManager.is_creative() else hits_remaining - 1
	hits_changed.emit(hits_remaining, max_hits)
	if hits_remaining <= 0:
		_change_state(State.DEATH)
		die()
	elif max_hits > 1:
		_hit_invuln_timer = HIT_INVULN
	return true
```

11. Replace the head of `on_hit_impact` (up to and including the `HitReaction.play(spec)` line) with the block below, and change the final `hit(damage)` call to `take_hit()`:

```gdscript
func on_hit_impact(impact_point: Vector2, hit_dir: Vector2, _damage: int = 0) -> void:
	if _state == State.DEATH or is_hit_invulnerable():
		return
	if hit_dir.length_squared() > 0.0001:
		apply_knockback(hit_dir, KNOCKBACK_SPEED)
	var lethal: bool = hits_remaining <= 1 or GameModeManager.is_creative()
	var spec := HitSpec.new()
	spec.position = impact_point
	spec.direction = hit_dir
	spec.damage = 1.0
	spec.is_kill = lethal
	spec.source_color = Color.WHITE
	spec.source_radius = 8.0
	HitReaction.play(spec)
```

(The blood splatter and TELEPORT blocks in between stay unchanged. `spec.damage` is removed in Task 8.)

12. Run `grep -n "health\|damage_scale\|weapon.damage" src/enemies/enemy.gd`. Expected: no matches except `_play_hit_flash` / comments. Fix any leftovers.

- [ ] **Step 5: Update subclasses, spawning, and lunge contact**

- `src/enemies/melee_enemy.gd`: delete both `max_health = 15` lines.
- `src/enemies/ranged_enemy.gd`: delete `max_health = 12`.
- `src/enemies/dummy_enemy.gd`: the training dummy should survive hits. Replace `max_health = 30` / `health = max_health` with:

```gdscript
	max_hits = 9999
	hits_remaining = max_hits
```

- `src/enemies/lunge_enemy.gd`: delete `@export var dash_damage: float = 5.0`. In `_check_body_contact`, replace the two lines computing `dmg` and calling `on_hit_impact` with `_player_ref.on_hit_impact(global_position, _lock_dir, 1)`.
- `src/core/spawn_dispatcher.gd` (~lines 228–241): delete `health_mult`, `damage_mult`, the `enemy.max_health = ...` line, the `damage_scale` block, and the `weapon_resource.damage *= damage_mult` block. Keep `speed_mult` and `enemy.speed = ...` (speed is behavior). If an `is_elite` flag is set nearby, leave it: elite hit counts come from `_apply_elite_scaling`.
- `src/enemies/boss_enemy.gd`:

```gdscript
const HITS_PER_PHASE := 10
```

In `_ready()`, delete `weapon.damage = 6.0` and replace `max_health = 200` with `max_hits = phase_count * HITS_PER_PHASE`. Replace `hit(damage)`, `_check_phase_transition`, `_phase_threshold` and the head of `_transition_phase`:

```gdscript
func take_hit() -> void:
	super.take_hit()
	if _state != State.DEATH:
		_check_phase_transition()


func apply_status_damage(amount: int) -> void:
	super.apply_status_damage(amount)
	if _state != State.DEATH:
		_check_phase_transition()


func _check_phase_transition() -> void:
	while current_phase < phase_count and hits_remaining <= _phase_threshold(current_phase + 1):
		current_phase += 1
		_transition_phase()


# Phase p begins once this many hits (or fewer) remain.
func _phase_threshold(p: int) -> int:
	return HITS_PER_PHASE * (phase_count - p + 1)


func _transition_phase() -> void:
	if _status_component != null:
		_status_component.clear_all()
	match current_phase:
```

(keep the existing `match` arms). `hazard_damage` stays as is (unused).

- [ ] **Step 6: Switch `resolve_hit` kill detection and migrate fake targets**

In `src/weapons/weapon.gd`, `resolve_hit`, replace the two `had_hp` / `pre_hp` lines and the final `if had_hp ...` condition:

```gdscript
	var tracks_hits: bool = ("hits_remaining" in target)
	var pre_hits: int = target.hits_remaining if tracks_hits else 1
```

```gdscript
	if tracks_hits and pre_hits > 0 and target.hits_remaining <= 0:
```

Fake targets in tests that model enemy health must now model hits. In each of `test_combo_data.gd`, `test_combo_detonator.gd`, `test_combo_flagship.gd`, `test_combo_rhythm.gd`, `test_combo_states.gd`, `test_data_modifier.gd`, `test_melee_resolve_hit.gd`, `test_native_weapon_hooks.gd`, `test_projectile.gd`, `test_weapon_resolve_hit.gd`, `test_war_scythe_weapon.gd`:
- `var health: float = X` → `var hits_remaining: int = 1` when the test expects one hit to kill, or `= 2` when the test checks a non-lethal hit (read the test that uses it).
- `var max_health: float = X` → delete, unless the test reads it (only `target_low_hp` tests in `test_data_modifier.gd` do; delete those test functions — `coup_de_grace` is reworked in Plan 3).
- `health -= dmg` → `hits_remaining -= 1`.
- Assertions on `.health` → assertions on `.hits_remaining`.

Leave the `on_hit_impact(_p, _d, dmg)` signatures and damage assertions alone; Task 6 handles those.

Run: `grep -rln "\.health\b\|var health\|max_health" tests/unit src`
Expected: only `src/player/player_inventory.gd`, `src/ui/death_screen.gd`, `src/ui/hud.gd`, `src/core/juice/damage_vignette.gd`, the modifier scripts handled in Task 6 (`headsman_modifier.gd`, `overkill_modifier.gd`, `last_stand_modifier.gd`, `data_modifier.gd`), and player tests.

- [ ] **Step 7: Run tests to verify they pass**

Run:
```bash
tools/run_unit_suites.sh /tmp/t4.txt tests/unit/test_enemy_state_machine.gd tests/unit/test_boss_phase_transition.gd tests/unit/test_boss_drops.gd tests/unit/test_lunge_enemy.gd tests/unit/test_melee_enemy.gd tests/unit/test_sniper_enemy.gd tests/unit/test_enemy_*.gd tests/unit/test_spawn_dispatcher.gd tests/unit/test_combo_*.gd tests/unit/test_data_modifier.gd tests/unit/test_melee_resolve_hit.gd tests/unit/test_native_weapon_hooks.gd tests/unit/test_projectile.gd tests/unit/test_weapon_resolve_hit.gd tests/unit/test_war_scythe_weapon.gd; cat /tmp/t4.txt
```
Expected: all `0 errors | 0 failures`, apart from baseline failures unrelated to hits (compare with the baseline file).

- [ ] **Step 8: Commit**

```bash
git add src/enemies src/core/spawn_dispatcher.gd src/weapons/weapon.gd tests/unit
git commit -m "feat(enemies): hit-count model with 0.3s multi-hit invulnerability; boss phases by hits"
```

---

### Task 5: Remove crit; move `hit_status` to every weapon

Crit goes away entirely. Three weapons used `crit_status` as their identity (Flame Sword, Frost Sword, Tide Caller), so `hit_status` moves from `RangedWeapon` up to `Weapon` and is applied by `resolve_hit` on every hit, melee included.

**Files:**
- Modify: `src/weapons/weapon.gd`, `src/weapons/melee_weapon.gd`, `src/weapons/advanced_melee_weapon.gd`, `src/weapons/willowblade_weapon.gd`, `src/weapons/ranged_weapon.gd`, `src/weapons/projectile.gd`, `src/weapons/projectile_behaviors/chain_behavior.gd`, `src/weapons/modifier.gd`, `src/weapons/modifiers/data_modifier.gd`, `src/weapons/modifiers/chain_spark_modifier.gd`, `src/autoload/weapon_registry.gd`, `src/drops/weapon_drop.gd`
- Modify: `docs/design_docs/weapons.csv` (drop 3 columns, set 3 `hit_status` values)
- Delete: `tests/unit/test_weapon_crit.gd`, `tests/unit/test_weapon_crit_csv.gd`
- Test: `tests/unit/test_weapon_resolve_hit.gd`, `tests/unit/test_csv_weapon_data.gd`, and every suite that greps positive for `crit` (Step 6)

**Interfaces:**
- Produces: `Weapon.hit_status: String` (export) and `const HIT_STATUS_STAIN := 2.0`; `resolve_hit(user, target, base_dmg)` (crit parameter removed; damage removed in Task 6). `MeleeWeapon._hit_attackables(user, origin, direction, reach, arc, dmg_mult, ignore_parry)` (no `force_crit`). `AdvancedMeleeWeapon._thrust(ignore_parry: bool = false, dash: float = 0.0)`.
- Removes: `Weapon.crit_chance`, `crit_multiplier`, `crit_status`, `CRIT_STATUS_STAIN`, `get_effective_crit_chance()`, `roll_crit()`, `get_effective_crit_chance_for_target()`, `roll_crit_for_target()`, `_on_crit()`; `"crit_chance"`/`"crit_multiplier"` effective stats; `Modifier.modify_crit_chance()`, `modify_crit_chance_for_target()`, `on_crit()`; `Projectile.crit_*`; `Move.force_crit`; the `on_crit` retrigger hook.

- [ ] **Step 1: Write the failing tests**

In `tests/unit/test_weapon_resolve_hit.gd`, delete `test_crit_multiplier_applied`, `test_on_crit_hook_fires_on_crit`, `test_on_crit_hook_silent_on_non_crit` and the `_CritCounter` class. Change every remaining `w.resolve_hit(u, t, X, false)` / `true` call to `w.resolve_hit(u, t, X)`. Add:

```gdscript
func test_hit_status_applied_on_every_hit() -> void:
	var w := Weapon.new()
	w.hit_status = "on_fire"
	var t := _target()
	t.hits_remaining = 2
	w.resolve_hit(null, t, 1.0)
	assert_float(t.get_node("StatusComponent").get_stain("on_fire")).is_equal_approx(Weapon.HIT_STATUS_STAIN, 0.001)

func test_no_hit_status_by_default() -> void:
	var w := Weapon.new()
	var t := _target()
	t.hits_remaining = 2
	w.resolve_hit(null, t, 1.0)
	assert_float(t.get_node("StatusComponent").get_stain("on_fire")).is_equal(0.0)
```

In `tests/unit/test_csv_weapon_data.gd`, add:

```gdscript
func test_crit_status_weapons_now_use_hit_status() -> void:
	assert_str(WeaponRegistry.get_weapon_by_id("flame_sword").hit_status).is_equal("on_fire")
	assert_str(WeaponRegistry.get_weapon_by_id("frost_sword").hit_status).is_equal("chilly")
	assert_str(WeaponRegistry.get_weapon_by_id("tide_caller").hit_status).is_equal("wet")

func test_weapons_have_no_crit_fields() -> void:
	var w = WeaponRegistry.get_weapon_by_id("caliburn")
	assert_bool("crit_chance" in w).is_false()
	assert_bool("crit_multiplier" in w).is_false()
	assert_bool("crit_status" in w).is_false()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `tools/run_unit_suites.sh /tmp/t5.txt tests/unit/test_weapon_resolve_hit.gd tests/unit/test_csv_weapon_data.gd; cat /tmp/t5.txt`
Expected: failures (`Weapon.hit_status` missing, crit fields still present).

- [ ] **Step 3: Strip crit from `Weapon` and add `hit_status`**

In `src/weapons/weapon.gd`:
- Replace `const CRIT_STATUS_STAIN := 2.0` with `const HIT_STATUS_STAIN := 2.0`.
- Replace the three `@export var crit_*` lines with `@export var hit_status: String = ""`.
- In `_seed_effective_stats()`, delete the `"crit_chance"` and `"crit_multiplier"` entries.
- Delete `get_effective_crit_chance`, `roll_crit`, `get_effective_crit_chance_for_target`, `roll_crit_for_target`, `_on_crit`.
- In `retrigger_modifier`, delete the `"on_crit":` match arm.
- Replace `resolve_hit` with:

```gdscript
func resolve_hit(user: Node, target: Node, base_dmg: float) -> void:
	var dmg: float = base_dmg
	for m in _iter_active_modifiers():
		dmg = m.modify_hit_damage(self, user, target, dmg)
	dmg = _native_modify_hit_damage(user, target, dmg)
	var tracks_hits: bool = ("hits_remaining" in target)
	var pre_hits: int = target.hits_remaining if tracks_hits else 1
	if target.has_method("on_hit_impact"):
		var hit_dir: Vector2 = Vector2.ZERO
		if target is Node2D and user is Node2D:
			var raw_dir: Vector2 = target.global_position - user.global_position
			var rlen_sq: float = raw_dir.length_squared()
			if rlen_sq > 0.0001:
				hit_dir = raw_dir / sqrt(rlen_sq)
		target.on_hit_impact(target.global_position if target is Node2D else Vector2.ZERO, hit_dir, int(dmg))
	_apply_hit_status(target)
	for m in _iter_active_modifiers():
		m.on_hit_target(self, user, target)
	_hit_count += 1
	if tracks_hits and pre_hits > 0 and target.hits_remaining <= 0:
		for m in _iter_active_modifiers():
			m.on_kill(self, user, target)
		_native_on_kill(user, target)


func _apply_hit_status(target: Node) -> void:
	if hit_status == "":
		return
	var sc = target.get_node_or_null("StatusComponent")
	if sc != null:
		sc.add_stain(hit_status, HIT_STATUS_STAIN)
```

- In `src/weapons/ranged_weapon.gd`, delete `@export var hit_status: String = ""` (now inherited) and the `proj.crit_chance`, `proj.crit_multiplier`, `proj.crit_status` lines in `_spawn_projectile`. Keep `proj.hit_status = hit_status`.

- [ ] **Step 4: Strip crit from melee, projectiles, and modifiers**

- `src/weapons/melee_weapon.gd`: remove the `force_crit: bool` parameter from `_hit_attackables`; replace its last two lines with `resolve_hit(user, node, damage * dmg_mult)`. Fix the caller in `_use_impl`: `_hit_attackables(user, pos, direction, reach, arc, 1.0, false)`. Run `grep -rn "_hit_attackables(" src` and drop the `force_crit` argument from every call.
- `src/weapons/advanced_melee_weapon.gd`: delete `var force_crit: bool = false` from `Move`; `_thrust(force_crit: bool = false, ignore_parry: bool = false, dash: float = 0.0)` → `_thrust(ignore_parry: bool = false, dash: float = 0.0)` and delete `m.force_crit = force_crit`; in the move executor, `_hit_attackables(user, pos, direction, move.reach, move.arc, move.damage_mult, move.ignore_parry)`. Run `grep -rn "_thrust(" src` and drop the first argument from every call that passes one (e.g. `willowblade_weapon.gd`: `_thrust(true, false, 0.0)` → `_thrust(false, 0.0)`; update its comment `# guaranteed-crit thrust` → `# charged thrust`).
- `src/weapons/projectile.gd`: delete `crit_chance`, `crit_multiplier`, `crit_status` exports and `CRIT_STATUS_STAIN`. In `_handle_hit`: `source_weapon.resolve_hit(source_node, target, damage)` (delete the `is_crit` line). In `_legacy_apply_hit`:

```gdscript
func _legacy_apply_hit(target: Node) -> void:
	target.on_hit_impact(global_position, direction, int(damage))
	if hit_status != "":
		var hs = target.get_node_or_null("StatusComponent")
		if hs != null:
			hs.add_stain(hit_status, HIT_STATUS_STAIN)
```

- `src/weapons/projectile_behaviors/chain_behavior.gd`: delete the `is_crit` line; `proj.source_weapon.resolve_hit(proj.source_node, nxt, proj.damage)`.
- `src/weapons/modifier.gd`: delete `modify_crit_chance`, `on_crit`, `modify_crit_chance_for_target`.
- `src/weapons/modifiers/data_modifier.gd`: delete `modify_crit_chance` and `modify_crit_chance_for_target`. (honed_point, combo_keeper and hemophilia become inert until Plan 3.)
- `src/weapons/modifiers/chain_spark_modifier.gd`: rename `func on_crit(` to `func on_kill(`. The spec's 1/4 chance comes in Plan 3; for now it arcs on every kill. Leave the description string (the CSV text overrides it).
- `src/autoload/weapon_registry.gd`: delete the `crit_chance` / `crit_multiplier` / `crit_status` parsing (~lines 147–153). Move the `hit_status` read out of the ranged-only block (~line 218) to the universal-fields section, next to `damage`:

```gdscript
	weapon.hit_status = row.get("hit_status", "")
```

and delete the old ranged-only `hs` lines.
- `src/drops/weapon_drop.gd`: delete the two crit `stats.append` blocks (~lines 41–44).

- [ ] **Step 5: Update `weapons.csv`**

Run this one-off script from the repo root. It drops the three crit columns, moves the identity statuses to `hit_status`, and checks the result:

```bash
python3 - <<'EOF'
import csv
p = "docs/design_docs/weapons.csv"
rows = list(csv.DictReader(open(p, encoding="utf-8")))
fields = [f for f in rows[0].keys() if f not in ("crit_chance", "crit_multiplier", "crit_status")]
hit = {"flame_sword": "on_fire", "frost_sword": "chilly", "tide_caller": "wet"}
for r in rows:
    if r["id"] in hit:
        r["hit_status"] = hit[r["id"]]
with open(p, "w", encoding="utf-8", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore", lineterminator="\n")
    w.writeheader()
    w.writerows(rows)
check = list(csv.DictReader(open(p, encoding="utf-8")))
assert len(check) == 51 and "crit_chance" not in check[0]
print("ok", len(check))
EOF
git diff --stat docs/design_docs/weapons.csv
```

Expected: `ok 51`. (DictWriter quotes only fields that need it. That is valid CSV for Godot's parser; the diff will show quoting changes.)

- [ ] **Step 6: Delete crit tests and migrate the rest**

```bash
git rm tests/unit/test_weapon_crit.gd tests/unit/test_weapon_crit_csv.gd
grep -rln "crit" tests/unit src
```

For each test file listed, delete test functions whose subject is crit (their names contain `crit`, or they assert crit chance/multiplier/status), and drop `is_crit`/`force_crit` arguments from calls that remain. In `src`, expected: no matches except the word "critical" in comments/descriptions. Fix any code match.

- [ ] **Step 7: Run tests to verify they pass**

Run:
```bash
tools/run_unit_suites.sh /tmp/t5.txt $(grep -rl "crit\|resolve_hit\|hit_status\|_thrust\|_hit_attackables" tests/unit | sort -u) tests/unit/test_csv_weapon_data.gd tests/unit/test_weapon_registry_pools.gd tests/unit/test_new_swords_load.gd; cat /tmp/t5.txt
```
Expected: all `0 errors | 0 failures`, apart from unrelated baseline failures.

- [ ] **Step 8: Commit**

```bash
git add -A src tests docs/design_docs/weapons.csv
git commit -m "feat(weapons): remove crit; hit_status applies on every hit for all weapons"
```

---

### Task 6: Damage-free hit API

Hits stop carrying a number. `on_hit_impact(point, dir)` and `resolve_hit(user, target)` lose their damage parameters, and every damage-modifying hook goes away. The projectile/weapon `damage` field is still used for carving until Task 7.

**Files:**
- Modify: `src/weapons/weapon.gd` (`resolve_hit`, `retrigger_modifier`, `_native_modify_hit_damage`, `_apply_burst`)
- Modify: `src/weapons/modifier.gd`, `src/weapons/modifiers/{data,mirror_slot,echo_strike,headsman,last_stand,overkill,slot_harmony,rupture,chain_spark,lightning_bolt,frostshatter}_modifier.gd`, `src/weapons/modifiers/detonator_modifier.gd`
- Modify: `src/weapons/berserker_axe_weapon.gd`, `src/weapons/melee_weapon.gd`, `src/weapons/projectile.gd`, `src/weapons/projectile_behaviors/chain_behavior.gd`
- Modify: `src/enemies/enemy.gd`, `src/enemies/parry_dummy.gd`, `src/enemies/lunge_enemy.gd`, `src/player/player_controller.gd`, `src/props/oil_barrel.gd`
- Test: every suite that declares or calls `on_hit_impact` / `resolve_hit` (Step 5)

**Interfaces:**
- Consumes: `Enemy.is_hit_invulnerable()` (Task 4).
- Produces:
  - Receivers: `on_hit_impact(impact_point: Vector2, hit_dir: Vector2) -> void` on `Enemy`, `PlayerController`, `ParryDummy`, `oil_barrel.gd`.
  - `Weapon.resolve_hit(user: Node, target: Node) -> void`. A hit on a target where `is_hit_invulnerable()` is true does nothing (no status, no on_hit_target, no on_kill, no hit count).
  - `Weapon._apply_burst(user: Node, target: Node) -> void` (one hit).
  - `MeleeWeapon._hit_attackables(user, origin, direction, reach, arc, ignore_parry)`. `Move.damage_mult` stays (scales carving only; renamed in Task 7).
- Removes: `Modifier.modify_hit_damage()`, `Weapon._native_modify_hit_damage()`, the `modify_hit_damage` retrigger hook, `DetonatorModifier.burst_per_stack` usage of damage (Step 3), the `DAMAGE` consts in chain_spark / lightning_bolt.

- [ ] **Step 1: Write the failing tests**

In `tests/unit/test_weapon_resolve_hit.gd`:
- Make `_Target` count hits instead of damage:

```gdscript
class _Target extends Node2D:
	var hits_remaining: int = 1
	var hit_count: int = 0
	var invulnerable: bool = false
	func _init() -> void:
		add_to_group("attackable")
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)
	func is_hit_invulnerable() -> bool:
		return invulnerable
	func on_hit_impact(_p: Vector2, _d: Vector2) -> void:
		hit_count += 1
		hits_remaining -= 1
```

- Delete `_DoubleDmg` and `test_conditional_multiplier_folds`.
- Change every `w.resolve_hit(u, t, X)` call to `w.resolve_hit(u, t)`.
- Add:

```gdscript
func test_resolve_hit_lands_exactly_one_hit() -> void:
	var w := Weapon.new()
	var t := _target()
	t.hits_remaining = 2
	w.resolve_hit(null, t)
	assert_int(t.hit_count).is_equal(1)
	assert_int(t.hits_remaining).is_equal(1)

func test_resolve_hit_during_invuln_applies_no_status() -> void:
	var w := Weapon.new()
	w.hit_status = "on_fire"
	var kills := _KillCounter.new()
	w.add_modifier(0, kills)
	var t := _target()
	t.invulnerable = true
	w.resolve_hit(null, t)
	assert_int(t.hit_count).is_equal(0)
	assert_float(t.get_node("StatusComponent").get_stain("on_fire")).is_equal(0.0)
	assert_int(kills.kills).is_equal(0)
```

In `tests/unit/test_native_weapon_hooks.gd`, delete `test_native_modify_hit_damage_folds_into_resolve_hit`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `tools/run_unit_suites.sh /tmp/t6.txt tests/unit/test_weapon_resolve_hit.gd tests/unit/test_native_weapon_hooks.gd; cat /tmp/t6.txt`
Expected: failures (`resolve_hit` expects 3 args; `on_hit_impact` called with 3 args).

- [ ] **Step 3: Change the pipeline**

`src/weapons/weapon.gd`:

```gdscript
func resolve_hit(user: Node, target: Node) -> void:
	if target.has_method("is_hit_invulnerable") and target.is_hit_invulnerable():
		return
	var tracks_hits: bool = ("hits_remaining" in target)
	var pre_hits: int = target.hits_remaining if tracks_hits else 1
	if target.has_method("on_hit_impact"):
		var hit_dir: Vector2 = Vector2.ZERO
		if target is Node2D and user is Node2D:
			var raw_dir: Vector2 = target.global_position - user.global_position
			var rlen_sq: float = raw_dir.length_squared()
			if rlen_sq > 0.0001:
				hit_dir = raw_dir / sqrt(rlen_sq)
		target.on_hit_impact(target.global_position if target is Node2D else Vector2.ZERO, hit_dir)
	_apply_hit_status(target)
	for m in _iter_active_modifiers():
		m.on_hit_target(self, user, target)
	_hit_count += 1
	if tracks_hits and pre_hits > 0 and target.hits_remaining <= 0:
		for m in _iter_active_modifiers():
			m.on_kill(self, user, target)
		_native_on_kill(user, target)
```

- Delete `_native_modify_hit_damage`.
- `retrigger_modifier`: delete the `"modify_hit_damage":` arm, and change the three early returns `return args[2] if hook == "modify_hit_damage" else null` to `return null`.
- `_apply_burst(user, target, amount)` → `_apply_burst(user: Node, target: Node)`; its final call becomes `target.on_hit_impact(<same position expr>, dir)`.
- `src/weapons/modifier.gd`: delete `modify_hit_damage`.
- `src/weapons/berserker_axe_weapon.gd`: delete `MAX_RAMP` and `_native_modify_hit_damage` (Plan 3 adds the low-armor swing speed).
- `src/weapons/modifiers/mirror_slot_modifier.gd`, `echo_strike_modifier.gd`: delete their `modify_hit_damage` overrides.
- `headsman_modifier.gd`: delete `HIGH_HP_FRACTION`, `_last_frac`, `modify_hit_damage`; `on_kill` now calls `weapon.reset_cooldown()` unconditionally when not disabled (Plan 3 changes it to a 50% refund).
- `last_stand_modifier.gd`, `overkill_modifier.gd`, `slot_harmony_modifier.gd`: delete `modify_hit_damage` and the state it used. Keep `_init` and (slot_harmony) `_all_different`. They are inert until Plan 3.
- `data_modifier.gd`: delete `modify_hit_damage`, `_self_gold_mult`, `_speed_fraction`, `_self_full_hp`, `GOLD_STEP`, the `target_low_hp` branch in `_condition_met`, the `Rampage` streak code (`_hit_streak` var, its update in `on_hit_target`, its reset in `on_tick`), and the `heal` branch in `on_kill` (spec A4: vampiric no longer heals). Keep the on_kill `stat_add` stacking and `bounty`.
- `rupture_modifier.gd`: `weapon._apply_burst(user, target, weapon.damage * BURST_MULT)` → `weapon._apply_burst(user, target)`; delete `BURST_MULT`.
- `frostshatter_modifier.gd`: `weapon._apply_burst(user, foe, SHATTER_BURST)` → `weapon._apply_burst(user, foe)`; delete `SHATTER_BURST`.
- `detonator_modifier.gd`: read it. Every `_apply_burst(user, target, <amount>)` call becomes `_apply_burst(user, target)`. Keep `consumed_status` / stack consumption; `burst_per_stack` stays as a field (Plan 3 replaces detonators), but stop passing it to `_apply_burst`.
- `chain_spark_modifier.gd`, `lightning_bolt_modifier.gd`: delete `const DAMAGE := 6`; drop the third argument from their `on_hit_impact` calls.
- `src/weapons/melee_weapon.gd` `_hit_attackables`: delete the `dmg_mult` parameter, the `base_dmg` line and the `if int(base_dmg) <= 0: return` guard (hits no longer depend on damage); the last line becomes `resolve_hit(user, node)`. Fix callers: `melee_weapon.gd` `_use_impl` → `_hit_attackables(user, pos, direction, reach, arc, false)`; `advanced_melee_weapon.gd` → `_hit_attackables(user, pos, direction, move.reach, move.arc, move.ignore_parry)`. Run `grep -rn "_hit_attackables(" src` and fix every other call the same way.
- `src/weapons/projectile.gd`: every `target.on_hit_impact(global_position, direction, int(damage))` → `target.on_hit_impact(global_position, direction)`; `source_weapon.resolve_hit(source_node, target, damage)` → `source_weapon.resolve_hit(source_node, target)`; in `_legacy_apply_hit`, `target.on_hit_impact(global_position, direction)`.
- `chain_behavior.gd`: `proj.source_weapon.resolve_hit(proj.source_node, nxt)`.

- [ ] **Step 4: Change the receivers**

- `src/enemies/enemy.gd`: `func on_hit_impact(impact_point: Vector2, hit_dir: Vector2) -> void:`.
- `src/player/player_controller.gd`: `func on_hit_impact(impact_point: Vector2, hit_dir: Vector2) -> void:`.
- `src/enemies/parry_dummy.gd`: `func on_hit_impact(_pos: Vector2, _dir: Vector2) -> void:`.
- `src/props/oil_barrel.gd`: `func on_hit_impact(impact_point: Vector2, hit_dir: Vector2) -> void:`.
- `src/enemies/lunge_enemy.gd`: `_player_ref.on_hit_impact(global_position, _lock_dir)`.

Run: `grep -rn "on_hit_impact(" src | grep -v "func on_hit_impact"`
Expected: every call has exactly two arguments. Check each line by eye.

- [ ] **Step 5: Migrate tests**

Run: `grep -rln "on_hit_impact\|resolve_hit\|modify_hit_damage\|_native_modify_hit_damage\|_apply_burst\|_hit_attackables" tests/unit`

For each file:
- Fake receivers: `func on_hit_impact(_p: Vector2, _d: Vector2, dmg: int)` → `func on_hit_impact(_p: Vector2, _d: Vector2)`. If the fake recorded `dmg` into an array, record `1` instead (`hits.append(1)`), so "a hit landed" assertions keep working.
- Delete test functions whose subject is a damage amount: damage multipliers, `damage_mult` per combo move, modify_hit_damage folding, burst amounts, berserker/last_stand/overkill/slot_harmony/greedy/momentum/glass_cannon damage. Keep and adapt tests about whether a hit landed, how many targets were hit, statuses, kills, combos advancing, parry.
- Drop the damage argument from `resolve_hit` / `_apply_burst` / `_hit_attackables` calls.
- `test_lunge_enemy.gd` builds a fake player from a source string (line ~51). Update the string to `"func on_hit_impact(_pos: Vector2, _dir: Vector2) -> void:"`, and change any assertion on the received damage to assert that a hit was received.

Run: `grep -rn "dmg: int\|, dmg)" tests/unit`
Expected: no `on_hit_impact` matches remain.

- [ ] **Step 6: Run tests to verify they pass**

Run:
```bash
tools/run_unit_suites.sh /tmp/t6.txt $(grep -rl "on_hit_impact\|resolve_hit\|_apply_burst\|_hit_attackables\|Modifier\|Weapon" tests/unit | sort -u); grep -v "0 errors | 0 failures" /tmp/t6.txt
```
Expected: only suites that are in the baseline failing list, with the same failing test names as in the baseline.

- [ ] **Step 7: Commit**

```bash
git add -A src tests
git commit -m "refactor(combat): hits carry no damage; drop damage-modifying hooks"
```

---

### Task 7: Rename `damage` → `dig_power`

After Task 6, `damage` only controls how hard swings and projectiles carve terrain. Rename it, re-assign values by archetype, and relabel the UI.

**Files:**
- Modify: `src/weapons/weapon.gd`, `melee_weapon.gd`, `advanced_melee_weapon.gd`, `willowblade_weapon.gd`, `ranged_weapon.gd`, `charged_ranged_weapon.gd`, `projectile.gd`, `soul_reaver_weapon.gd`, every `src/weapons/*_weapon.gd` that sets `damage = X` in `_init`
- Modify: `src/weapons/modifiers/modifier_projectile.gd`, `evolving_edge_modifier.gd`, `data_modifier.gd`, every `src/weapons/modifiers/*.gd` that passes damage to `ModifierProjectile.spawn_*`
- Modify: `src/weapons/projectile_behaviors/split_behavior.gd`, `src/console/commands/spawn_command.gd`
- Modify: `src/autoload/weapon_registry.gd`, `src/drops/weapon_drop.gd`, `src/ui/weapon_popup.gd`, `src/ui/chest_ui.gd`, `src/ui/hud.gd` (tooltip only), `scenes/ui/hud.tscn` (tooltip node name only)
- Modify: `docs/design_docs/weapons.csv` (column rename + values), `docs/design_docs/modifiers.csv` (`element` for sharpened, heavy_head)
- Test: `tests/unit/test_csv_weapon_data.gd`, `tests/unit/test_free_carve_flag.gd`, and every suite matching `damage` (Step 6)

**Interfaces:**
- Produces: `Weapon.dig_power: float` (export); effective-stat key `"dig_power"`; `Projectile.dig_power: float`; `ModifierProjectile.spawn_one(user, origin, direction, dig_power, opts)` / `spawn_fan(user, origin, base_dir, dig_power, count, spread_deg, opts)` (same positions, renamed); `AdvancedMeleeWeapon.Move.dig_mult`; `SplitBehavior.dig_factor`; `get_base_stats()` returns `{"name", "cooldown", "dig_power"}`.
- Removes: `Weapon.damage`, `"damage"` effective stat, `Projectile.damage`, `ChargedRangedWeapon.charge_damage_mult` (unused), the keystone `s["damage"] *= 2.0` line.
- Not renamed (unrelated systems): `MaterialRegistry` material `damage`, `TerrainCell.damage`, `ComputeDevice` / `terrain_modifier.gd` `damage` parameters.

- [ ] **Step 1: Write the failing tests**

In `tests/unit/test_csv_weapon_data.gd`, add:

```gdscript
const ALL_WEAPON_IDS := [
	"rusty_sword", "bone_dagger", "broad_axe", "flame_blade", "throwing_knife", "fire_orb",
	"spread_shot", "boss_staff", "willowblade", "flame_sword", "frost_sword", "qinggang_sword",
	"blood_blade", "tao_sword", "dragon_fang", "heavenly_sword", "grand_knight_sword",
	"deep_dark_blade", "broadsword", "executioner", "void_sword", "caliburn", "phantom_blade",
	"iron_mace", "rapier", "cleaver", "war_scythe", "twin_daggers", "obsidian_greatsword",
	"venom_fang_blade", "tide_caller", "cinder_brand", "glacier_edge", "thunder_katana",
	"gravedigger_spade", "reaper_glaive", "berserker_axe", "mirror_blade", "whirlwind_blade",
	"quake_hammer", "soul_reaver", "heavy_crossbow", "scatter_blunderbuss", "arc_railgun",
	"flame_lobber", "frost_repeater", "venom_spitter", "tesla_gun", "chakram_launcher",
	"seeker_launcher", "hailstorm_bow",
]

func test_every_weapon_has_dig_power() -> void:
	for id in ALL_WEAPON_IDS:
		var w = WeaponRegistry.get_weapon_by_id(id)
		assert_that(w).override_failure_message("missing weapon '%s'" % id).is_not_null()
		assert_float(w.dig_power).override_failure_message("'%s' dig_power" % id).is_greater(0.0)
		assert_bool("damage" in w).override_failure_message("'%s' still has damage" % id).is_false()

func test_dig_power_by_archetype() -> void:
	assert_float(WeaponRegistry.get_weapon_by_id("bone_dagger").dig_power).is_equal(1.5)
	assert_float(WeaponRegistry.get_weapon_by_id("rusty_sword").dig_power).is_equal(3.0)
	assert_float(WeaponRegistry.get_weapon_by_id("iron_mace").dig_power).is_equal(5.0)
	assert_float(WeaponRegistry.get_weapon_by_id("quake_hammer").dig_power).is_equal(7.0)
	assert_float(WeaponRegistry.get_weapon_by_id("gravedigger_spade").dig_power).is_equal(9.0)
	assert_float(WeaponRegistry.get_weapon_by_id("heavy_crossbow").dig_power).is_equal(2.0)

func test_sharpened_adds_dig_power() -> void:
	var w = WeaponRegistry.get_weapon_by_id("rusty_sword")
	w.add_modifier(w.find_empty_modifier_slot(), WeaponRegistry._make_modifier("sharpened"))
	assert_float(w.get_effective_stats()["dig_power"]).is_equal_approx(6.0, 0.001)
```

Check `sharpened`'s current `magnitude` in `modifiers.csv` (expected `3`). If it differs, use base 3.0 + that magnitude in the last assertion.

In `tests/unit/test_free_carve_flag.gd`, read the file, then change any `damage` set or assertion to `dig_power`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `tools/run_unit_suites.sh /tmp/t7.txt tests/unit/test_csv_weapon_data.gd tests/unit/test_free_carve_flag.gd; cat /tmp/t7.txt`
Expected: failures (`dig_power` doesn't exist).

- [ ] **Step 3: Rename in weapon code**

- `src/weapons/weapon.gd`: `@export var damage: float = 0.0` → `@export var dig_power: float = 0.0`; `_seed_effective_stats` key `"damage": damage` → `"dig_power": dig_power`; `get_base_stats` `"damage": damage` → `"dig_power": dig_power`; delete the keystone block (`if _has_keystone(): s["damage"] *= 2.0`, 2 lines). If `_has_keystone()` has no other caller afterwards (`grep -n "_has_keystone" src -r`), leave it; Plan 3 decides.
- `src/weapons/melee_weapon.gd`: `damage = 5.0` → `dig_power = 5.0`; in `_use_impl`, `var dmg: float = eff["damage"]` → `var dig: float = eff["dig_power"]` and pass `dig` to `_carve_and_push`; rename `_carve_and_push(..., dmg: float)` parameter to `dig: float`, and `_solid_carve_strength(dmg)` to `_solid_carve_strength(dig: float) -> float: return FREE_CARVE_STRENGTH if free_carve else dig`.
- `src/weapons/advanced_melee_weapon.gd`: `Move.damage_mult` → `Move.dig_mult`; builder parameters named `dmg_mult` → `dig_mult`; the carve call → `_carve_and_push(pos, direction, move.reach, move.arc, dig_power * move.dig_mult)`.
- `src/weapons/willowblade_weapon.gd`: `th.damage_mult = 2.0` → `th.dig_mult = 2.0`. Run `grep -rn "damage_mult" src` and rename every remaining `Move` use the same way.
- `src/weapons/ranged_weapon.gd`: `damage = 3.0` → `dig_power = 3.0`; `_get_projectile_damage()` → `_get_projectile_dig_power()` returning `get_effective_stats()["dig_power"]`; `proj.damage = ...` → `proj.dig_power = _get_projectile_dig_power()`. Run `grep -rn "_get_projectile_damage" src` and rename overrides.
- `src/weapons/charged_ranged_weapon.gd`: delete `@export var charge_damage_mult` (unused; first confirm with `grep -rn charge_damage_mult src tests`).
- `src/weapons/projectile.gd`: `@export var damage` → `@export var dig_power: float = 0.0`; `_carve_terrain` passes `dig_power`.
- `src/weapons/soul_reaver_weapon.gd`: `s["damage"] += _kill_stacks` → `s["dig_power"] += _kill_stacks` (Plan 3 replaces it with reach/arc stacks).
- Every weapon subclass `_init` with `damage = X`: `grep -rln "^\s*damage = " src/weapons` → change each to `dig_power = X` (the CSV overrides these values for registry weapons).

- [ ] **Step 4: Rename in modifiers, behaviors, console**

- `modifier_projectile.gd`: rename the `damage: float` parameter of `spawn_one` and `spawn_fan` to `dig_power: float`; `proj.damage = damage` → `proj.dig_power = dig_power`; `spawn_fan` passes `dig_power` through.
- Callers passing a damage value to `spawn_one` / `spawn_fan`: `grep -rn "spawn_one\|spawn_fan" src`. If a caller passes `weapon.damage` or `eff["damage"]`, change it to `weapon.dig_power` / `eff["dig_power"]`; leave literal numbers as they are.
- `split_behavior.gd`: `damage_factor` → `dig_factor`; `shard.damage = proj.damage * damage_factor` → `shard.dig_power = proj.dig_power * dig_factor`. Update any `damage_factor` setters (`grep -rn damage_factor src`).
- `evolving_edge_modifier.gd`: `if stat != "damage":` → `if stat != "dig_power":`.
- `data_modifier.gd`: in `on_kill` and `get_stat_mult`, `element == "damage"` → `element == "dig_power"`.
- `spawn_command.gd`: `proj.damage = 10.0` / `5.0` → `proj.dig_power = 10.0` / `5.0`.
- `docs/design_docs/modifiers.csv`: in the `element` column, change `damage` → `dig_power` for `sharpened` and `heavy_head` only. Leave other rows' `element` values unchanged (those modifiers are reworked in Plan 3).

- [ ] **Step 5: Rename the CSV column, set dig values, relabel UI**

- `src/autoload/weapon_registry.gd`: `weapon.damage = float(row.get("damage", weapon.damage))` → `weapon.dig_power = float(row.get("dig_power", weapon.dig_power))`.
- Run this from the repo root to rename the column and set the archetype values (spec C1):

```bash
python3 - <<'EOF'
import csv
p = "docs/design_docs/weapons.csv"
rows = list(csv.DictReader(open(p, encoding="utf-8")))
dig = {
    # daggers / thrusters
    "bone_dagger": 1.5, "dragon_fang": 1.5, "rapier": 1.5, "twin_daggers": 1.5, "venom_fang_blade": 1.5,
    # axes / maces / greatswords
    "broad_axe": 5.0, "tao_sword": 5.0, "grand_knight_sword": 5.0, "deep_dark_blade": 5.0,
    "executioner": 5.0, "iron_mace": 5.0, "glacier_edge": 5.0, "berserker_axe": 5.0,
    # hammer
    "quake_hammer": 7.0,
    # dig specialists
    "gravedigger_spade": 9.0, "obsidian_greatsword": 9.0,
}
fields = ["dig_power" if f == "damage" else f for f in rows[0].keys()]
for r in rows:
    if r["type"] == "Ranged":
        v = 2.0
    else:
        v = dig.get(r["id"], 3.0)  # every other melee weapon is a sword: 3
    r["dig_power"] = ("%g" % v)
    del r["damage"]
with open(p, "w", encoding="utf-8", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
    w.writeheader()
    w.writerows(rows)
check = list(csv.DictReader(open(p, encoding="utf-8")))
assert len(check) == 51 and "damage" not in check[0] and all(float(r["dig_power"]) > 0 for r in check)
print("ok")
EOF
```

- UI labels:
  - `src/drops/weapon_drop.gd`: `stats.append("Damage: %.0f" % weapon.damage)` → `stats.append("Dig: %g" % weapon.dig_power)`.
  - `src/ui/weapon_popup.gd` (2 places) and `src/ui/chest_ui.gd`: `"Damage: %.0f" % base_stats["damage"]` → `"Dig: %g" % base_stats["dig_power"]`.
  - `src/ui/hud.gd`: rename `_weapon_tooltip_dmg` → `_weapon_tooltip_dig` with `%WeaponTooltipDig`; `set_weapon_tooltip(name, cooldown, damage: int)` → `set_weapon_tooltip(name: String, cooldown: float, dig_power: float)` with text `"Dig: %g" % dig_power`; in `_on_weapon_mouse_entered`, `"Dig: %g" % stats["dig_power"]`.
  - `scenes/ui/hud.tscn`: rename node `WeaponTooltipDamage` to `WeaponTooltipDig` (the `[node name=...]` line only).

- [ ] **Step 6: Sweep and migrate tests**

Run: `grep -rn "\bdamage\b" src --include=*.gd | grep -v "material_registry\|terrain_cell\|terrain_modifier\|compute_device\|hit_spec\|hit_reaction\|damage_vignette\|player_inventory\|enemy.gd\|lava_damage_checker\|#"`
Expected: no weapon/projectile/modifier hits. Fix any that remain. (`hit_spec`, `hit_reaction`, `damage_vignette`, `spec.damage` are Task 8.)

Then: `grep -rln "\.damage\b\|\"damage\"\|damage_mult\|damage_factor" tests/unit`. For each file, rename weapon/projectile `damage` → `dig_power`, `damage_mult` → `dig_mult`, `damage_factor` → `dig_factor`. Delete assertions that still check damage *as damage*: the archetype DPS bands in `test_weapon_balance.gd` and the charge damage ratio in `test_charge_weapon_ratio.gd`. If a suite has nothing left, delete the file with `git rm`. Spec §3 lists those two as superseded.

- [ ] **Step 7: Run tests to verify they pass**

Run:
```bash
tools/run_unit_suites.sh /tmp/t7.txt $(ls tests/unit/test_*.gd); diff <(grep -v "0 errors | 0 failures" docs/superpowers/plans/2026-10-20-combat-rework-baseline.txt | cut -d'|' -f1) <(grep -v "0 errors | 0 failures" /tmp/t7.txt | cut -d'|' -f1)
```
Expected: the diff lists only suites removed from the baseline failures (fixed by this plan: `test_csv_weapon_data.gd`, `test_new_swords_load.gd`, `test_boss_phase_transition.gd`) and suites deleted in this plan. No suite may appear on the right side only.

- [ ] **Step 8: Commit**

```bash
git add -A src tests scenes/ui/hud.tscn docs/design_docs/weapons.csv docs/design_docs/modifiers.csv
git commit -m "refactor(weapons): rename damage to dig_power; assign dig by archetype"
```

---

### Task 8: Hearts + shields HUD, no damage numbers

**Files:**
- Modify: `src/core/juice/hit_spec.gd`, `src/core/juice/hit_reaction.gd`, `src/core/juice/damage_vignette.gd`
- Modify: `src/player/player_inventory.gd`, `src/enemies/enemy.gd` (drop `spec.damage`, `pulse(1.0)`)
- Modify: `src/ui/hud.gd`, `scenes/ui/hud.tscn`
- Test: `tests/unit/test_hit_reaction.gd`, `tests/unit/test_damage_vignette.gd`, Create `tests/unit/test_hud_pips.gd`

**Interfaces:**
- Consumes: `PlayerInventory.armor_changed`, `get_armor()`, `get_max_armor()` (Task 3).
- Produces: `HitSpec` without `damage`; `HitReaction.play(spec)` spawns no number; `DamageVignette.pulse() -> void`; HUD `set_pips(container: HBoxContainer, current: int, maximum: int, color: Color) -> void` and nodes `%Hearts`, `%Shields`.
- Removes: `HitSpec.damage`, `HitReaction._spawn_damage_number`, `_drive_damage_motion`, the `DAMAGE_NUMBER_*` / `HOLD_FRACTION` / `POP_*` / `INITIAL_VELOCITY_*` / `GRAVITY` / `SPAWN_OFFSET` consts, `DAMAGE_NUMBER_SCENE`; HUD `%HealthBar`, `%BarFill`, `%HealthLabel`.

- [ ] **Step 1: Write the failing tests**

Create `tests/unit/test_hud_pips.gd`:

```gdscript
extends GdUnitTestSuite

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")


func _hud() -> CanvasLayer:
	var hud: CanvasLayer = auto_free(HUD_SCENE.instantiate())
	add_child(hud)
	return hud


func _lit(container: HBoxContainer) -> int:
	var n := 0
	for c in container.get_children():
		if c.modulate.a > 0.5:
			n += 1
	return n


func test_hearts_show_current_and_max() -> void:
	var hud := _hud()
	hud._on_health_changed(2, 3)
	var hearts: HBoxContainer = hud.get_node("%Hearts")
	assert_int(hearts.get_child_count()).is_equal(3)
	assert_int(_lit(hearts)).is_equal(2)


func test_shields_show_current_and_max() -> void:
	var hud := _hud()
	hud._on_armor_changed(1, 3)
	var shields: HBoxContainer = hud.get_node("%Shields")
	assert_int(shields.get_child_count()).is_equal(3)
	assert_int(_lit(shields)).is_equal(1)


func test_shields_follow_max_armor() -> void:
	var hud := _hud()
	hud._on_armor_changed(1, 1)
	assert_int(hud.get_node("%Shields").get_child_count()).is_equal(1)
	hud._on_armor_changed(3, 4)
	assert_int(hud.get_node("%Shields").get_child_count()).is_equal(4)
```

In `tests/unit/test_hit_reaction.gd` and `tests/unit/test_damage_vignette.gd`, read each file and then: delete `spec.damage = ...` lines; delete tests about damage numbers (they reference `_spawn_damage_number` / `DAMAGE_NUMBER`); change `pulse(<x>)` calls to `pulse()`. If the vignette tests assert the low-health threshold with 100-HP numbers, rewrite them for 3 HP: `_on_health_changed(1, 3)` → low health on; `_on_health_changed(2, 3)` → off.

- [ ] **Step 2: Run tests to verify they fail**

Run: `tools/run_unit_suites.sh /tmp/t8.txt tests/unit/test_hud_pips.gd tests/unit/test_hit_reaction.gd tests/unit/test_damage_vignette.gd; cat /tmp/t8.txt`
Expected: failures (`%Hearts` missing, `pulse()` arity).

- [ ] **Step 3: Remove damage from hit feedback**

- `hit_spec.gd`: delete `var damage: float = 0.0`.
- `hit_reaction.gd`: delete the DamageNumber constants block, `DAMAGE_NUMBER_SCENE`, `_spawn_damage_number`, `_drive_damage_motion`. `play()` becomes:

```gdscript
func play(spec: HitSpec) -> void:
	_spawn_sparks(spec.position, spec.direction, spec.source_color)
	_do_screen_shake(spec.is_kill, spec.direction)
	_do_chromatic_flash(spec.is_kill)
	_do_hit_stop(spec.is_kill)
```

  and drop the unused `damage: float` first parameter from `_do_screen_shake`, `_do_chromatic_flash`, `_do_hit_stop`.
- `damage_vignette.gd`: `func pulse(damage: float) -> void:` → `func pulse() -> void:` (the body never used it). The player now has 3 HP, so low health is "1 HP left": replace the ratio check in `_on_health_changed` with `current <= 1`, and delete `LOW_HEALTH_RATIO` if nothing else uses it.
- `player_inventory.gd` `take_hit`: delete `spec.damage = 1.0`; `HitReaction.vignette.pulse(1.0)` → `HitReaction.vignette.pulse()`.
- `enemy.gd` `on_hit_impact`: delete `spec.damage = 1.0`.
- Run `grep -rn "spec.damage\|pulse(.\|_spawn_damage_number" src tests`. Expected: no results.
- If `scenes/fx/damage_number.tscn` has no other references (`grep -rn damage_number scenes src`), delete it with `git rm scenes/fx/damage_number.tscn` (and its `.uid` file if present).

- [ ] **Step 4: Replace the health bar with hearts and shields**

In `scenes/ui/hud.tscn`, delete the `[node name="HealthBar" ...]`, `[node name="BarFill" ...]` and `[node name="HealthLabel" ...]` blocks (every line from `[node name="HealthBar"` up to the blank line before `[node name="GoldRow"`). Insert in their place:

```
[node name="Hearts" type="HBoxContainer" parent="TopLeft/Frame/InnerMargin/VBox"]
unique_name_in_owner = true
layout_mode = 2
theme_override_constants/separation = 4

[node name="Shields" type="HBoxContainer" parent="TopLeft/Frame/InnerMargin/VBox"]
unique_name_in_owner = true
layout_mode = 2
theme_override_constants/separation = 4

```

Then delete the now-unused `[sub_resource type="ShaderMaterial" id="ShaderMaterial_shimmer"]` block and the `[ext_resource ... health_bar_shimmer.gdshader ... id="3"]` line. If the RichTextLabel font ext_resource `4_136eg` is still referenced by another node (`grep -n 4_136eg scenes/ui/hud.tscn`), keep it; otherwise delete it too.

In `src/ui/hud.gd`:

```gdscript
## Single HUD: TL = hearts + shields + gold (one framed cluster), TR = weapon
## (matching framed cluster).

const PIP_SIZE := Vector2(12, 12)
const HEART_COLOR := Color(0.9, 0.2, 0.2)
const SHIELD_COLOR := Color(0.35, 0.65, 1.0)
const PIP_EMPTY_ALPHA := 0.2

@onready var _hearts: HBoxContainer = %Hearts
@onready var _shields: HBoxContainer = %Shields
```

(replace the doc comment and the `_health_bar_fill` / `_health_label` onready vars). In `_ready()`, after connecting `health_changed`, add:

```gdscript
			_inventory.armor_changed.connect(_on_armor_changed)
			_on_armor_changed(_inventory.get_armor(), _inventory.get_max_armor())
```

Replace `_on_health_changed` and add the pip helpers:

```gdscript
func _on_health_changed(current: int, maximum: int) -> void:
	set_pips(_hearts, current, maximum, HEART_COLOR)


func _on_armor_changed(current: int, maximum: int) -> void:
	set_pips(_shields, current, maximum, SHIELD_COLOR)


# One square per point of `maximum`; the first `current` are lit, the rest dimmed.
func set_pips(container: HBoxContainer, current: int, maximum: int, color: Color) -> void:
	while container.get_child_count() < maximum:
		var pip := ColorRect.new()
		pip.custom_minimum_size = PIP_SIZE
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(pip)
	while container.get_child_count() > maximum:
		var last: Node = container.get_child(container.get_child_count() - 1)
		container.remove_child(last)
		last.queue_free()
	for i in range(container.get_child_count()):
		var pip: ColorRect = container.get_child(i)
		pip.color = color
		pip.modulate.a = 1.0 if i < current else PIP_EMPTY_ALPHA
```

`set_health(current, max_value)` stays (it calls `_on_health_changed`). `_on_died` stays.

- [ ] **Step 5: Run tests to verify they pass**

Run: `tools/run_unit_suites.sh /tmp/t8.txt tests/unit/test_hud_pips.gd tests/unit/test_hit_reaction.gd tests/unit/test_damage_vignette.gd tests/unit/test_player_inventory.gd tests/unit/test_enemy_state_machine.gd tests/unit/test_ui_theme_overlay.gd tests/unit/test_minimap_model.gd; cat /tmp/t8.txt`
Expected: all `0 errors | 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add -A src scenes tests
git commit -m "feat(hud): hearts and shields; drop damage numbers"
```

---

### Task 9: Full verification, smoke run, and todo update

**Files:**
- Modify: `docs/design_docs/implementation_todo2.md` (Phase 0 checkboxes)
- Modify: `docs/superpowers/plans/2026-10-20-combat-rework-baseline.txt` (append a post-plan section)

- [ ] **Step 1: Full suite run**

Run:
```bash
tools/run_unit_suites.sh /tmp/final.txt $(ls tests/unit/test_*.gd)
diff <(grep -v "0 errors | 0 failures" docs/superpowers/plans/2026-10-20-combat-rework-baseline.txt | cut -d'|' -f1) <(grep -v "0 errors | 0 failures" /tmp/final.txt | cut -d'|' -f1)
```
Expected: no suite fails now that didn't fail in the baseline. For suites failing in both, compare the failing test names (third column). They must be the same or fewer. Any new failure is a bug from this plan: fix it before continuing.

- [ ] **Step 2: Grep for leftovers**

```bash
grep -rn "crit_chance\|crit_multiplier\|crit_status\|roll_crit\|on_crit\|modify_hit_damage\|take_damage\|take_status_damage\|burn_dps\|max_health" src | grep -v "player_inventory\|hud.gd\|death_screen"
grep -rn "\.health\b" src | grep -v "player_inventory"
```
Expected: no results.

- [ ] **Step 3: Headless smoke run**

Run: `timeout 60 godot --headless --path . --quit-after 600 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|Invalid call|Invalid access" | head -20`
Expected: no output. If the project's main scene needs a display, run without `--headless` instead, and play one floor by hand: an enemy dies in one swing, an elite in two, a hit drains a shield, shields come back after ~3s, standing in lava drains points through fire ticks.

- [ ] **Step 4: Update the todo**

In `docs/design_docs/implementation_todo2.md`, Phase 0, mark `x` in the Done column for: Armor + HP model, Armor regeneration, DoT routing, Hit-count health, Unified post-hit invulnerability, Boss hit pools, Remove enemy damage stats, Rename `damage` → `dig_power`, Remove crit, Remove damage numbers, Hearts + shields HUD. Also mark Elite abilities under hit counts if TANK/ENRAGE were done in Task 4 (they were). Leave Update unit tests unchecked (Plans 2–3 add more).

- [ ] **Step 5: Record the post-plan state and commit**

```bash
{ echo; echo "# After Plan 1 (core rules)"; cat /tmp/final.txt; } >> docs/superpowers/plans/2026-10-20-combat-rework-baseline.txt
git add docs/design_docs/implementation_todo2.md docs/superpowers/plans/2026-10-20-combat-rework-baseline.txt
git commit -m "docs: mark combat rework core rules done; record test state"
```

---

## Plans 2 and 3 (written after Plan 1 lands)

- **Plan 2 — Infrastructure (spec E1, A4, G):** `Weapon.roll_chance` + Executioner's Mark bonus, on-kill dispatch with target, `PlayerBuffs`, `modifiers.csv` `chance` column, boss-kill heal, Mend shop service.
- **Plan 3 — Content (spec D, E2):** the 19 weapon traits and ~27 modifier behaviors. These are built on Plan 2's interfaces and replace the modifiers this plan left inert.
