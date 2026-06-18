# Charge Bar + Full-Charge Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Charge weapons only fire their charged attack when fully charged, and a charge bar appears below the player's status icons while charging — turning gold and vibrating when full.

**Architecture:** Add a generic `is_chargeable()`/`is_charging()` query API to the `Weapon` base class so the `WeaponManager` can drive a UI element uniformly. `AdvancedMeleeWeapon` overrides them and changes its release gate from a tiny tap-threshold to a full-charge check. A new world-space `ChargeBar` `Node2D` (child of the player, owned by `WeaponManager`) renders the bar each frame from the active weapon's charge ratio. The player's status-icon anchor is raised so the bar sits beneath it without overlap.

**Tech Stack:** Godot 4 / GDScript, gdUnit4 for unit tests.

**Spec:** `docs/superpowers/specs/2026-06-06-charge-bar-design.md`

**Running tests:** All test commands use:
`GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a <test-file>`

---

## File Structure

- **`src/weapons/weapon.gd`** (modify) — base `Weapon`: add `is_chargeable()` / `is_charging()` defaults (`get_charge_ratio()` default already exists).
- **`src/weapons/advanced_melee_weapon.gd`** (modify) — override `is_chargeable()` / `is_charging()`; replace the `tap_threshold` gate in `on_release` with a full-charge gate.
- **`src/ui/charge_bar.gd`** (create) — `ChargeBar` `Node2D`: draws background + fill, gold + jitter at full.
- **`src/weapons/weapon_manager.gd`** (modify) — create the `ChargeBar` under the player and drive it each `_process`.
- **`src/player/player_controller.gd`** (modify) — raise the status-icon anchor so the bar fits below it.
- **`tests/unit/test_weapon_charge_api.gd`** (modify) — cover the new base-class defaults.
- **`tests/unit/test_advanced_melee_charge.gd`** (modify) — replace the partial-charge expectation (was single spin → now light slash) and cover the query API.
- **`tests/unit/test_charge_bar.gd`** (create) — cover ratio clamping and active toggle.

---

## Task 1: Base `Weapon` charge-query API

**Files:**
- Modify: `src/weapons/weapon.gd:46-47` (next to existing `get_charge_ratio`)
- Test: `tests/unit/test_weapon_charge_api.gd`

- [ ] **Step 1: Write the failing tests**

Add these two tests to `tests/unit/test_weapon_charge_api.gd` (after `test_get_charge_ratio_default_zero`, before the final newline):

```gdscript
func test_is_chargeable_default_false() -> void:
	var w := WeaponScript.new()
	assert_bool(w.is_chargeable()).is_false()

func test_is_charging_default_false() -> void:
	var w := WeaponScript.new()
	assert_bool(w.is_charging()).is_false()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_weapon_charge_api.gd`
Expected: FAIL — `is_chargeable` / `is_charging` are not declared on `Weapon` (invalid call / parse).

- [ ] **Step 3: Add the default methods**

In `src/weapons/weapon.gd`, immediately after the existing `get_charge_ratio` method (currently lines 46-47):

```gdscript
func is_chargeable() -> bool:
	return false


func is_charging() -> bool:
	return false
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_weapon_charge_api.gd`
Expected: PASS (all tests in the suite green).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/weapon.gd tests/unit/test_weapon_charge_api.gd
git commit -m "feat: add is_chargeable/is_charging query API to Weapon base"
```

---

## Task 2: Full-charge gate + query overrides on `AdvancedMeleeWeapon`

The release behavior changes: a charged attack fires only at a full charge ratio (`>= 1.0`); any earlier release performs the light attack. The existing `tap_threshold` field stays declared but is no longer used for branching.

**Files:**
- Modify: `src/weapons/advanced_melee_weapon.gd:107-116` (`on_release`)
- Modify: `src/weapons/advanced_melee_weapon.gd` (add `is_chargeable`/`is_charging` overrides)
- Test: `tests/unit/test_advanced_melee_charge.gd`

- [ ] **Step 1: Update the existing partial-charge test and add query tests**

In `tests/unit/test_advanced_melee_charge.gd`, **replace** the whole `test_half_charge_plays_single_spin` function (currently lines 51-57):

```gdscript
func test_half_charge_plays_light() -> void:
	var w := _make()
	w.on_press(null)
	w._tick_impl(0.2)             # ratio 0.4 => below full => light slash
	w.on_release(null)
	assert_int(w.played.size()).is_equal(1)
	assert_int(w.played[0].shape).is_equal(AdvancedMeleeWeapon.MoveShape.SLASH)
```

Then append these query tests at the end of the file:

```gdscript
func test_is_chargeable_true_when_charged_moves_exist() -> void:
	var w := _make()
	assert_bool(w.is_chargeable()).is_true()

func test_is_charging_tracks_press_and_release() -> void:
	var w := _make()
	assert_bool(w.is_charging()).is_false()
	w.on_press(null)
	assert_bool(w.is_charging()).is_true()
	w.on_release(null)
	assert_bool(w.is_charging()).is_false()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_advanced_melee_charge.gd`
Expected: FAIL — `test_half_charge_plays_light` still gets a SPIN (old gate fires charged above `tap_threshold`); `is_chargeable`/`is_charging` parse-fail or return the base defaults.

- [ ] **Step 3: Replace the release gate**

In `src/weapons/advanced_melee_weapon.gd`, **replace** the `on_release` body (currently lines 107-115):

```gdscript
func on_release(user: Node) -> void:
	if not _charging:
		return
	_charging = false
	_current_user = user
	if get_charge_ratio() >= 1.0:
		_fire_charged(user, get_charge_ratio())   # full charge: charged attack
	else:
		use(user)                                 # early release: light attack (slash)
```

- [ ] **Step 4: Add the query overrides**

In `src/weapons/advanced_melee_weapon.gd`, add these methods right after `get_charge_ratio` (currently lines 89-90):

```gdscript
func is_chargeable() -> bool:
	_ensure_moves()
	return not charged_moves.is_empty()


func is_charging() -> bool:
	return _charging
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_advanced_melee_charge.gd`
Expected: PASS — `test_quick_tap_plays_light`, `test_half_charge_plays_light`, `test_full_charge_plays_charged_flurry_scaled`, `test_charge_ratio_accrues_and_clamps`, and the two new query tests all green.

- [ ] **Step 6: Run the full unit suite to confirm no regressions**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit`
Expected: PASS (no other suite depends on the old gate).

- [ ] **Step 7: Commit**

```bash
git add src/weapons/advanced_melee_weapon.gd tests/unit/test_advanced_melee_charge.gd
git commit -m "feat: gate charged attack on full charge; add charge query overrides"
```

---

## Task 3: `ChargeBar` node

A self-contained world-space bar. `set_ratio` stores the clamped ratio, applies the full-charge jitter, and requests a redraw; `set_active` toggles visibility and snaps back to the anchor when hidden. `_draw` renders a dark background and an amber (or gold-when-full) fill.

**Files:**
- Create: `src/ui/charge_bar.gd`
- Test: `tests/unit/test_charge_bar.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/unit/test_charge_bar.gd`:

```gdscript
extends GdUnitTestSuite

const ChargeBarScript = preload("res://src/ui/charge_bar.gd")

func test_set_ratio_clamps_high() -> void:
	var bar := auto_free(ChargeBarScript.new())
	bar.set_ratio(2.0)
	assert_float(bar._ratio).is_equal_approx(1.0, 0.001)

func test_set_ratio_clamps_low() -> void:
	var bar := auto_free(ChargeBarScript.new())
	bar.set_ratio(-0.5)
	assert_float(bar._ratio).is_equal_approx(0.0, 0.001)

func test_set_active_toggles_visibility() -> void:
	var bar := auto_free(ChargeBarScript.new())
	bar.set_active(true)
	assert_bool(bar.visible).is_true()
	bar.set_active(false)
	assert_bool(bar.visible).is_false()

func test_inactive_resets_to_anchor() -> void:
	var bar := auto_free(ChargeBarScript.new())
	bar.set_ratio(1.0)            # full => jitter offsets position
	bar.set_active(false)
	assert_vector(bar.position).is_equal(ChargeBarScript.ANCHOR)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_charge_bar.gd`
Expected: FAIL — `res://src/ui/charge_bar.gd` does not exist (load error).

- [ ] **Step 3: Create the `ChargeBar` script**

Create `src/ui/charge_bar.gd`:

```gdscript
class_name ChargeBar
extends Node2D

const BAR_WIDTH := 18.0
const BAR_HEIGHT := 3.0
const ANCHOR := Vector2(0.0, -9.0)          # just above the body, below status icons
const BG_COLOR := Color(0.08, 0.08, 0.08, 0.85)
const FILL_COLOR := Color(0.95, 0.7, 0.2, 1.0)    # amber while charging
const FULL_COLOR := Color(1.0, 0.88, 0.35, 1.0)   # brighter gold when full
const JITTER_PX := 1.0
const Z := 79                               # just below status icons (ICON_Z = 80)

var _ratio: float = 0.0


func _ready() -> void:
	z_index = Z
	z_as_relative = false
	position = ANCHOR
	visible = false


func set_active(on: bool) -> void:
	visible = on
	if not on:
		position = ANCHOR


func set_ratio(r: float) -> void:
	_ratio = clampf(r, 0.0, 1.0)
	if _ratio >= 1.0:
		position = ANCHOR + Vector2(
			randf_range(-JITTER_PX, JITTER_PX),
			randf_range(-JITTER_PX, JITTER_PX))
	else:
		position = ANCHOR
	queue_redraw()


func _draw() -> void:
	var origin := Vector2(-BAR_WIDTH * 0.5, -BAR_HEIGHT * 0.5)
	draw_rect(Rect2(origin, Vector2(BAR_WIDTH, BAR_HEIGHT)), BG_COLOR)
	var fill_w := BAR_WIDTH * _ratio
	var color := FULL_COLOR if _ratio >= 1.0 else FILL_COLOR
	draw_rect(Rect2(origin, Vector2(fill_w, BAR_HEIGHT)), color)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_charge_bar.gd`
Expected: PASS (all four tests green).

- [ ] **Step 5: Commit**

```bash
git add src/ui/charge_bar.gd tests/unit/test_charge_bar.gd
git commit -m "feat: add ChargeBar node with amber/gold fill and full-charge jitter"
```

---

## Task 4: Wire the `ChargeBar` into `WeaponManager`

The manager owns one `ChargeBar` under the player and updates it every frame from the active weapon's charge state. Because `is_charging()` and `get_charge_ratio()` are defined on the `Weapon` base (Task 1), this works for every weapon without type checks.

**Files:**
- Modify: `src/weapons/weapon_manager.gd:1-14` (preload + field), `:33-40` (`_setup_visual`), `:85-87` (`_process`)

- [ ] **Step 1: Add the preload and field**

In `src/weapons/weapon_manager.gd`, after the existing `const LavaEmitterModifierScript` line (line 6) add:

```gdscript
const ChargeBarScript := preload("res://src/ui/charge_bar.gd")
```

Then after the `var _pressed_slot: int = -1` field (line 15) add:

```gdscript
var _charge_bar: ChargeBar = null
```

- [ ] **Step 2: Create the bar in `_setup_visual`**

In `src/weapons/weapon_manager.gd`, at the end of `_setup_visual` (after `_visual.visible = false`, line 40) add:

```gdscript
	_charge_bar = ChargeBarScript.new()
	_charge_bar.name = "ChargeBar"
	_player.add_child(_charge_bar)
```

- [ ] **Step 3: Drive the bar from `_process`**

In `src/weapons/weapon_manager.gd`, **replace** the `_process` method (currently lines 85-87):

```gdscript
func _process(delta: float) -> void:
	if _active_weapon != null and _active_weapon.has_visual():
		_active_weapon.update_visual(delta, _player)
	_update_charge_bar()


func _update_charge_bar() -> void:
	if _charge_bar == null:
		return
	if _active_weapon != null and _active_weapon.is_charging():
		_charge_bar.set_active(true)
		_charge_bar.set_ratio(_active_weapon.get_charge_ratio())
	else:
		_charge_bar.set_active(false)
```

- [ ] **Step 4: Confirm the unit suite still passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit`
Expected: PASS (no test imports `WeaponManager`; this verifies the new code parses and loads cleanly).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/weapon_manager.gd
git commit -m "feat: drive ChargeBar from WeaponManager active-weapon charge state"
```

---

## Task 5: Raise the player's status-icon anchor

With the charge bar at `y ≈ -9` (top edge ≈ `-10.5`), the status icons (anchored at `y = -10`, ~14 px tall) would overlap it. Raise the player's anchor to `-20` so icons span ~`-27` to `-13`, clearing the bar.

**Files:**
- Modify: `src/player/player_controller.gd:78`

- [ ] **Step 1: Change the anchor offset**

In `src/player/player_controller.gd`, **replace** line 78:

```gdscript
	visuals.setup(status, Vector2(BODY_WIDTH / 2.0, -10.0))
```

with:

```gdscript
	visuals.setup(status, Vector2(BODY_WIDTH / 2.0, -20.0))   # above the charge bar
```

- [ ] **Step 2: Confirm the unit suite still passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit`
Expected: PASS (parse/load check; no test asserts the anchor value).

- [ ] **Step 3: Commit**

```bash
git add src/player/player_controller.gd
git commit -m "feat: raise player status-icon anchor above the charge bar"
```

---

## Task 6: Manual in-game verification

Rendering, positioning, and the full-charge cue are visual and not unit-tested (per spec). Verify them by running the game.

- [ ] **Step 1: Launch the project**

Run: `godot --path . ` (or open the project in the Godot editor and press Play).

- [ ] **Step 2: Get a chargeable weapon**

Open the console (the in-game dev console) and run `spawn weapon willowblade`, then walk over the drop and equip it into a weapon slot.

- [ ] **Step 3: Verify charging behavior**

- Press and hold the equipped weapon's key. Confirm: a small bar appears just above the player's body and fills from left to right over ~0.5s.
- Confirm the status icons (if any active — e.g. set yourself on fire near lava) sit **above** the charge bar with no overlap.
- When the bar fills, confirm it turns a brighter gold and visibly vibrates.

- [ ] **Step 4: Verify the gate**

- Release **before** the bar is full → the weapon performs the light **slash** (not the thrust). A quick tap also slashes.
- Hold until the bar is **full**, then release → the weapon performs the charged **thrust**.
- Confirm the bar disappears immediately on release.

- [ ] **Step 5: No commit needed** (verification only). If any visual value needs tuning (bar size/position/colors in `src/ui/charge_bar.gd`, or the anchor in `src/player/player_controller.gd`), adjust, re-verify, and commit with `fix: tune charge bar visuals`.

---

## Self-Review Notes

- **Spec coverage:** full-charge gate (Task 2) ✓; early-release light attack (Task 2) ✓; charge bar node + amber→gold + jitter (Task 3) ✓; WeaponManager drives it (Task 4) ✓; query API on base + override (Tasks 1–2) ✓; bar below raised status icons (Tasks 3 anchor + 5) ✓; tests for gate + API (Tasks 1–3) ✓; manual visual verification (Task 6) ✓.
- **Type consistency:** `set_ratio` / `set_active` / `ANCHOR` / `_ratio` used identically in `charge_bar.gd`, its tests, and `WeaponManager`. `is_chargeable` / `is_charging` / `get_charge_ratio` signatures match across base and subclass. `ChargeBarScript` preload path consistent.
- **Note on `tap_threshold`:** intentionally left declared on `AdvancedMeleeWeapon` (and still set by the `ProbeWeapon` test fixture) but no longer read in `on_release`. Removing the field is out of scope and would only churn the test fixture.
