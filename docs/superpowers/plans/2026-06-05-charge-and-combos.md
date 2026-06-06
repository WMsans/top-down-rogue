# Charge + Combos Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement hold-to-charge attacks and multi-step combo sequences for nine melee weapons, with bespoke slash/thrust/spin move animations.

**Architecture:** A new `AdvancedMeleeWeapon extends MeleeWeapon` owns a charge controller, a combo sequencer (tap-chain or auto-flurry), and a move runner. Hits are applied immediately when a move plays (matching the existing melee model where the swing animation is cosmetic); animations run separately in `update_visual`. Each weapon is a tiny pure-script subclass that builds its move list lazily from its `.tres` stats. Input plumbing adds press/release routing so a held slot key charges and release fires.

**Tech Stack:** Godot 4 / GDScript, GdUnit4 for headless unit tests (`addons/gdUnit4/runtest.sh`).

**Spec:** `docs/superpowers/specs/2026-06-05-charge-and-combos-design.md`

**Test runner (use throughout):**
```bash
GODOT_BIN="${GODOT_BIN:-godot}" bash addons/gdUnit4/runtest.sh -a tests/unit/<file>.gd
```
(Substitute your Godot binary via `GODOT_BIN` if `godot` is not on PATH.)

---

## File Structure

**Create:**
- `src/weapons/advanced_melee_weapon.gd` — base: `Move` struct, factory helpers, charge controller, combo sequencer, flurry engine, move runner + animations.
- `src/weapons/willowblade_weapon.gd`, `executioner_weapon.gd`, `blood_blade_weapon.gd`, `void_sword_weapon.gd`, `dragon_fang_weapon.gd`, `grand_knight_weapon.gd`, `deep_dark_weapon.gd`, `phantom_blade_weapon.gd`, `qinggang_weapon.gd` — per-weapon subclasses.
- `tests/unit/test_weapon_charge_api.gd`, `tests/unit/test_advanced_melee_charge.gd`, `tests/unit/test_advanced_melee_combo.gd`, `tests/unit/test_advanced_melee_hit_geometry.gd`, `tests/unit/test_player_dash.gd`, `tests/unit/test_charge_combo_weapons_data.gd`.

**Modify:**
- `src/weapons/weapon.gd` — add `on_press`, `on_release`, `get_charge_ratio` base API.
- `src/weapons/weapon_manager.gd` — route keydown→`on_press`, keyup→`on_release`.
- `src/weapons/melee_weapon.gd` — extract `_carve_and_push` and `_hit_attackables` (parametrized) from `_use_impl`.
- `src/player/player_controller.gd` — add `request_dash` + `_dash_velocity` integration.
- `resources/weapons/{willowblade,executioner,blood_blade,void_sword,dragon_fang,grand_knight_sword,deep_dark_blade,phantom_blade,qinggang_sword}.tres` — repoint `script` to the new subclass.
- `docs/design_docs/implementation_todo.md` — check off Sub-project 2 rows.

---

## Task 1: Weapon base charge API

**Files:**
- Modify: `src/weapons/weapon.gd`
- Test: `tests/unit/test_weapon_charge_api.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_weapon_charge_api.gd`:

```gdscript
extends GdUnitTestSuite

const WeaponScript = preload("res://src/weapons/weapon.gd")

# Records whether the default on_press path fired the attack.
class RecordingWeapon extends Weapon:
	var used := 0
	func _use_impl(_user) -> void:
		used += 1

func test_on_press_default_calls_use() -> void:
	var w := RecordingWeapon.new()
	w.cooldown = 0.5
	w.on_press(null)
	assert_int(w.used).is_equal(1)

func test_on_release_default_is_noop() -> void:
	var w := RecordingWeapon.new()
	w.on_release(null)
	assert_int(w.used).is_equal(0)

func test_get_charge_ratio_default_zero() -> void:
	var w := WeaponScript.new()
	assert_float(w.get_charge_ratio()).is_equal_approx(0.0, 0.001)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN="${GODOT_BIN:-godot}" bash addons/gdUnit4/runtest.sh -a tests/unit/test_weapon_charge_api.gd`
Expected: FAIL — `on_press` / `on_release` / `get_charge_ratio` not found.

- [ ] **Step 3: Add the API to `src/weapons/weapon.gd`**

Insert after `func use(user: Node) -> void:` block (after line 35, before `_use_impl`):

```gdscript
func on_press(user: Node) -> void:
	use(user)


func on_release(_user: Node) -> void:
	pass


func get_charge_ratio() -> float:
	return 0.0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN="${GODOT_BIN:-godot}" bash addons/gdUnit4/runtest.sh -a tests/unit/test_weapon_charge_api.gd`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/weapon.gd tests/unit/test_weapon_charge_api.gd
git commit -m "feat: add charge-aware on_press/on_release/get_charge_ratio to Weapon"
```

---

## Task 2: Route press + release in WeaponManager

**Files:**
- Modify: `src/weapons/weapon_manager.gd:42-60`

No unit test (input/node-bound); verified manually at the end. The change is behavior-preserving because `Weapon.on_press` defaults to `use()`.

- [ ] **Step 1: Replace `_input` to track press and release per slot**

In `src/weapons/weapon_manager.gd`, add a field near the top (after line 14 `var _active_weapon`):

```gdscript
var _pressed_slot: int = -1
```

Replace the whole `_input` function (lines 42-60) with:

```gdscript
func _input(event: InputEvent) -> void:
	if ConsoleManager.is_open():
		return
	if not (event is InputEventKey) or event.echo:
		return
	var slot := _slot_for_keycode(event.keycode)
	if slot < 0 or _inventory == null:
		return
	if event.pressed:
		var weapon = _inventory.get_weapon(slot)
		if slot < PlayerInventory.MAX_WEAPON_SLOTS and weapon != null:
			_activate_weapon(weapon)
			_inventory.active_weapon_slot = slot
			_pressed_slot = slot
			weapon.on_press(_player)
			weapon_activated.emit(slot)
	else:
		# Route the release to whatever weapon received the press for this slot.
		if slot == _pressed_slot:
			var weapon = _inventory.get_weapon(slot)
			if weapon != null:
				weapon.on_release(_player)
			_pressed_slot = -1


func _slot_for_keycode(keycode: int) -> int:
	match keycode:
		KEY_Z: return 0
		KEY_X: return 1
		KEY_C: return 2
	return -1
```

- [ ] **Step 2: Run the full unit suite to confirm nothing regressed**

Run: `GODOT_BIN="${GODOT_BIN:-godot}" bash addons/gdUnit4/runtest.sh -a tests/unit`
Expected: PASS (existing suite unchanged; `on_press`=`use` preserves prior fire-on-keydown behavior).

- [ ] **Step 3: Commit**

```bash
git add src/weapons/weapon_manager.gd
git commit -m "feat: route weapon key press and release in WeaponManager"
```

---

## Task 3: Parametrize melee hit + carve helpers

Extract reusable, parameterized helpers from `MeleeWeapon._use_impl` so `AdvancedMeleeWeapon` moves can hit with their own reach/arc/flags. Behavior of the base melee weapon is unchanged.

**Files:**
- Modify: `src/weapons/melee_weapon.gd`
- Test: `tests/unit/test_advanced_melee_hit_geometry.gd`

- [ ] **Step 1: Write the failing geometry test**

Create `tests/unit/test_advanced_melee_hit_geometry.gd`:

```gdscript
extends GdUnitTestSuite

# A full-circle arc (spin) must include targets behind the origin.
func test_full_circle_arc_includes_behind() -> void:
	assert_bool(MeleeWeapon._is_inside_arc(Vector2.ZERO, Vector2(-10, 0), 0.0, PI, 16.0)).is_true()

# A narrow thrust arc must reject a flank target.
func test_narrow_arc_rejects_flank() -> void:
	var flank := Vector2.from_angle(deg_to_rad(60.0)) * 10.0
	assert_bool(MeleeWeapon._is_inside_arc(Vector2.ZERO, flank, 0.0, deg_to_rad(12.0), 16.0)).is_false()

# A narrow thrust arc accepts a directly-forward target within reach.
func test_narrow_arc_accepts_forward() -> void:
	assert_bool(MeleeWeapon._is_inside_arc(Vector2.ZERO, Vector2(14, 0), 0.0, deg_to_rad(12.0), 16.0)).is_true()
```

- [ ] **Step 2: Run test to verify it passes already (predicate exists) — this pins behavior we depend on**

Run: `GODOT_BIN="${GODOT_BIN:-godot}" bash addons/gdUnit4/runtest.sh -a tests/unit/test_advanced_melee_hit_geometry.gd`
Expected: PASS. (`_is_inside_arc` already supports these; the test documents the contract the move runner relies on. If any case fails, stop — the predicate semantics changed.)

- [ ] **Step 3: Extract parametrized helpers in `src/weapons/melee_weapon.gd`**

Replace the body of `_use_impl` (lines 111-126) so it delegates to the new helpers:

```gdscript
func _use_impl(user: Node) -> void:
	_current_user = user
	var pos: Vector2 = user.global_position
	var direction := _get_facing_direction(user)
	_start_swing(direction)
	_carve_and_push(pos, direction, weapon_reach, arc_angle, damage)
	_hit_attackables(user, pos, direction, weapon_reach, arc_angle, 1.0, false, false)
```

Add these two helpers immediately after `_use_impl` (before the old `_hit_attackables_in_arc`):

```gdscript
func _carve_and_push(pos: Vector2, direction: Vector2, reach: float, arc: float, dmg: float) -> void:
	var fluids: Array[int] = MaterialRegistry.get_fluids()
	TerrainSurface.clear_and_push_materials_in_arc(pos, direction, reach, arc, push_speed, 0.25, fluids)
	var solids: Array[int] = [
		MaterialRegistry.MAT_DIRT,
		MaterialRegistry.MAT_WOOD,
		MaterialRegistry.MAT_STONE,
		MaterialRegistry.MAT_COAL,
		MaterialRegistry.MAT_ICE,
	]
	TerrainSurface.clear_and_push_materials_in_arc(pos, direction, reach, 0.0, 0.0, 0.0, solids, dmg)


func _hit_attackables(user: Node, origin: Vector2, direction: Vector2, reach: float, arc: float, dmg_mult: float, force_crit: bool, ignore_parry: bool) -> void:
	var base_dmg: float = damage * dmg_mult
	if int(base_dmg) <= 0:
		return
	var dir_angle: float = direction.angle()
	var half_arc_angle: float = arc / 2.0

	var space_state: PhysicsDirectSpaceState2D = user.get_world_2d().direct_space_state
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = reach
	var params: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	params.shape = circle
	params.transform = Transform2D(0.0, origin)
	params.collision_mask = ATTACKABLE_HIT_LAYER
	params.collide_with_areas = true
	params.collide_with_bodies = true

	var hits: Array = space_state.intersect_shape(params, 32)
	for hit in hits:
		var node: Node = hit.get("collider", null)
		if node == null or node == user:
			continue
		if not (node is Node2D):
			continue
		if not node.has_method("on_hit_impact"):
			continue
		var node2d := node as Node2D
		if not _is_inside_arc(origin, node2d.global_position, dir_angle, half_arc_angle, reach):
			continue
		var hit_dir: Vector2 = (node2d.global_position - origin).normalized()
		if not ignore_parry and node.has_method("try_parry"):
			if node.try_parry(user, node2d.global_position, hit_dir):
				var tint: Color = trail_color if "trail_color" in self else Color(1, 1, 1, 1)
				NailClashFX.play(node2d.global_position, -hit_dir, tint)
				continue
		var is_crit: bool = force_crit or roll_crit()
		var dmg: int = int(base_dmg * crit_multiplier) if is_crit else int(base_dmg)
		node.on_hit_impact(node2d.global_position, hit_dir, dmg)
		if is_crit:
			_on_crit(node)
```

Now delete the old `_hit_attackables_in_arc` function (the former lines 129-167) — it is fully replaced by `_hit_attackables`.

- [ ] **Step 4: Run the full suite to confirm melee behavior is unchanged**

Run: `GODOT_BIN="${GODOT_BIN:-godot}" bash addons/gdUnit4/runtest.sh -a tests/unit`
Expected: PASS — `test_melee_arc_angle_filter`, `test_parry_window`, `test_unparryable`, `test_new_swords_load`, etc. all green.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/melee_weapon.gd tests/unit/test_advanced_melee_hit_geometry.gd
git commit -m "refactor: parametrize melee carve/hit helpers for reuse by advanced moves"
```

---

## Task 4: AdvancedMeleeWeapon skeleton — Move, factories, charge controller

Build the base class with the `Move` struct, factory helpers, lazy move building, the charge controller, and `get_charge_ratio`. The move-dispatch seam `_play_move` is a stub here (real animation/hits come in Task 6). A protected recording seam makes the logic unit-testable.

**Files:**
- Create: `src/weapons/advanced_melee_weapon.gd`
- Test: `tests/unit/test_advanced_melee_charge.gd`

- [ ] **Step 1: Write the failing charge test**

Create `tests/unit/test_advanced_melee_charge.gd`:

```gdscript
extends GdUnitTestSuite

const AdvancedScript = preload("res://src/weapons/advanced_melee_weapon.gd")

# Subclass that records the moves dispatched, so we can assert charge selection
# without touching physics or animation.
class ProbeWeapon extends AdvancedMeleeWeapon:
	var played: Array = []
	func _setup_moves() -> void:
		charge_time_full = 0.5
		tap_threshold = 0.1
		charged_flurry_max = 2
		light_moves = [_slash()]
		charged_moves = [_spin()]
	func _play_move(move, _user) -> void:
		played.append(move)

func _make() -> ProbeWeapon:
	var w := ProbeWeapon.new()
	w.weapon_reach = 30.0
	w.arc_angle = PI / 2.0
	return w

func test_charge_ratio_accrues_and_clamps() -> void:
	var w := _make()
	w.on_press(null)
	w._tick_impl(0.25)
	assert_float(w.get_charge_ratio()).is_equal_approx(0.5, 0.01)
	w._tick_impl(1.0)
	assert_float(w.get_charge_ratio()).is_equal_approx(1.0, 0.01)

func test_quick_tap_plays_light() -> void:
	var w := _make()
	w.on_press(null)
	w._tick_impl(0.05)            # below tap_threshold
	w.on_release(null)
	assert_int(w.played.size()).is_equal(1)
	assert_int(w.played[0].shape).is_equal(AdvancedMeleeWeapon.MoveShape.SLASH)

func test_full_charge_plays_charged_flurry_scaled() -> void:
	var w := _make()
	w.on_press(null)
	w._tick_impl(1.0)             # full charge => ratio 1 => count 2
	w.on_release(null)
	# Flurry plays the first move immediately; the rest drain on tick.
	assert_int(w.played.size()).is_equal(1)
	assert_int(w.played[0].shape).is_equal(AdvancedMeleeWeapon.MoveShape.SPIN)
	w._tick_impl(1.0)             # drain the second spin
	assert_int(w.played.size()).is_equal(2)

func test_half_charge_plays_single_spin() -> void:
	var w := _make()
	w.on_press(null)
	w._tick_impl(0.2)             # ratio 0.4 => round(0.4*1)=0 => count 1
	w.on_release(null)
	w._tick_impl(1.0)
	assert_int(w.played.size()).is_equal(1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN="${GODOT_BIN:-godot}" bash addons/gdUnit4/runtest.sh -a tests/unit/test_advanced_melee_charge.gd`
Expected: FAIL — `advanced_melee_weapon.gd` does not exist.

- [ ] **Step 3: Create `src/weapons/advanced_melee_weapon.gd`**

```gdscript
class_name AdvancedMeleeWeapon
extends MeleeWeapon

enum MoveShape { SLASH, THRUST, SPIN }
enum ComboMode { TAP_CHAIN, AUTO_FLURRY }

class Move extends RefCounted:
	var shape: int = MoveShape.SLASH
	var reach: float = 36.0
	var arc: float = PI / 2.0
	var damage_mult: float = 1.0
	var dash_distance: float = 0.0
	var force_crit: bool = false
	var ignore_parry: bool = false
	var swing_dir: float = 0.0   # 0 = alternate; +1/-1 = forced swing direction

@export var charge_time_full: float = 0.6
@export var tap_threshold: float = 0.12
@export var combo_mode: int = ComboMode.TAP_CHAIN
@export var combo_reset_time: float = 0.5
@export var charged_flurry_max: int = 1
@export var flurry_step_time: float = 0.16

var light_moves: Array = []
var charged_moves: Array = []

var _moves_built: bool = false
var _charging: bool = false
var _charge_time: float = 0.0
var _combo_index: int = 0
var _combo_reset_timer: float = 0.0
var _flurry_queue: Array = []
var _flurry_timer: float = 0.0
var _flurry_active: bool = false


# ---- Move construction (lazy: runs after .tres stats are applied) ----

func _ensure_moves() -> void:
	if _moves_built:
		return
	_moves_built = true
	_setup_moves()


func _setup_moves() -> void:
	# Subclasses override to populate light_moves / charged_moves.
	light_moves = [_slash()]


func _slash(dir: float = 0.0, dmg_mult: float = 1.0) -> Move:
	var m := Move.new()
	m.shape = MoveShape.SLASH
	m.reach = weapon_reach
	m.arc = arc_angle
	m.swing_dir = dir
	m.damage_mult = dmg_mult
	return m


func _thrust(force_crit: bool = false, ignore_parry: bool = false, dash: float = 0.0) -> Move:
	var m := Move.new()
	m.shape = MoveShape.THRUST
	m.reach = weapon_reach * 1.25
	m.arc = deg_to_rad(20.0)
	m.force_crit = force_crit
	m.ignore_parry = ignore_parry
	m.dash_distance = dash
	return m


func _spin(dmg_mult: float = 1.0, dash: float = 0.0) -> Move:
	var m := Move.new()
	m.shape = MoveShape.SPIN
	m.reach = weapon_reach
	m.arc = TAU
	m.damage_mult = dmg_mult
	m.dash_distance = dash
	return m


# ---- Charge controller ----

func get_charge_ratio() -> float:
	return clampf(_charge_time / charge_time_full, 0.0, 1.0)


func on_press(user: Node) -> void:
	_ensure_moves()
	if _flurry_active:
		return
	if not is_ready():
		return
	if charged_moves.is_empty():
		use(user)            # non-charge weapons: light combo / single move via _use_impl
		return
	_current_user = user
	_charging = true
	_charge_time = 0.0


func on_release(user: Node) -> void:
	if not _charging:
		return
	_charging = false
	_current_user = user
	if _charge_time < tap_threshold:
		use(user)            # tap: reuse base wrapper (modifiers + cooldown + _use_impl)
	else:
		_fire_charged(user, get_charge_ratio())


func _fire_charged(user: Node, ratio: float) -> void:
	for modifier in modifiers:
		if modifier != null:
			modifier.on_use(self, user)
	_do_charged_attack(user, ratio)
	_cooldown_timer = cooldown


# ---- Attack dispatch ----

func _use_impl(user: Node) -> void:
	_ensure_moves()
	_current_user = user
	if _flurry_active:
		return
	_do_light_attack(user)


func _do_light_attack(user: Node) -> void:
	if combo_mode == ComboMode.AUTO_FLURRY:
		_start_flurry(light_moves.duplicate(), user)
		return
	if light_moves.is_empty():
		return
	var move = light_moves[_combo_index]
	_play_move(move, user)
	_combo_index += 1
	if _combo_index >= light_moves.size():
		_combo_index = 0
	_combo_reset_timer = combo_reset_time


func _do_charged_attack(user: Node, ratio: float) -> void:
	if charged_moves.is_empty():
		return
	if charged_flurry_max > 1:
		var count := clampi(1 + int(round(ratio * float(charged_flurry_max - 1))), 1, charged_flurry_max)
		var seq: Array = []
		for i in range(count):
			seq.append_array(charged_moves)
		_start_flurry(seq, user)
	elif charged_moves.size() == 1:
		_play_move(charged_moves[0], user)
	else:
		_start_flurry(charged_moves.duplicate(), user)


# ---- Flurry engine ----

func _start_flurry(moves: Array, user: Node) -> void:
	_flurry_queue = moves
	_flurry_active = true
	_flurry_timer = 0.0
	_advance_flurry(user)


func _advance_flurry(user: Node) -> void:
	if _flurry_queue.is_empty():
		_flurry_active = false
		return
	var move = _flurry_queue.pop_front()
	_play_move(move, user)
	_flurry_timer = flurry_step_time


# ---- Per-frame timers ----

func _tick_impl(delta: float) -> void:
	if _charging:
		_charge_time = minf(_charge_time + delta, charge_time_full)
		_on_charge_tick(_current_user, delta, get_charge_ratio())
	if _flurry_active:
		_flurry_timer -= delta
		if _flurry_timer <= 0.0:
			_advance_flurry(_current_user)
	if _combo_reset_timer > 0.0:
		_combo_reset_timer -= delta
		if _combo_reset_timer <= 0.0:
			_combo_index = 0


# ---- Seams overridden by subclasses / replaced in Task 6 ----

func _play_move(_move, _user) -> void:
	pass


func _on_charge_tick(_user, _delta: float, _ratio: float) -> void:
	pass
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN="${GODOT_BIN:-godot}" bash addons/gdUnit4/runtest.sh -a tests/unit/test_advanced_melee_charge.gd`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/advanced_melee_weapon.gd tests/unit/test_advanced_melee_charge.gd
git commit -m "feat: AdvancedMeleeWeapon skeleton with charge controller and move factories"
```

---

## Task 5: Combo sequencer (tap-chain + auto-flurry)

The sequencer code already exists from Task 4; this task adds tests that pin tap-chain advancement/reset/wrap and auto-flurry input-lock, fixing any gaps they reveal.

**Files:**
- Test: `tests/unit/test_advanced_melee_combo.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_advanced_melee_combo.gd`:

```gdscript
extends GdUnitTestSuite

class TapChainProbe extends AdvancedMeleeWeapon:
	var played: Array = []
	func _setup_moves() -> void:
		combo_mode = ComboMode.TAP_CHAIN
		combo_reset_time = 0.5
		light_moves = [_slash(0.0), _slash(0.0), _thrust()]
	func _play_move(move, _user) -> void:
		played.append(move.shape)

class FlurryProbe extends AdvancedMeleeWeapon:
	var played: Array = []
	func _setup_moves() -> void:
		combo_mode = ComboMode.AUTO_FLURRY
		flurry_step_time = 0.1
		light_moves = [_thrust(), _thrust(), _thrust()]
	func _play_move(move, _user) -> void:
		played.append(move.shape)

func _tap_probe() -> TapChainProbe:
	var w := TapChainProbe.new()
	w.weapon_reach = 30.0
	w.arc_angle = PI / 2.0
	w.cooldown = 0.0
	return w

func test_tap_chain_advances_then_wraps() -> void:
	var w := _tap_probe()
	w.on_press(null)   # step 0 slash
	w.on_press(null)   # step 1 slash
	w.on_press(null)   # step 2 thrust -> wraps to 0
	w.on_press(null)   # step 0 slash again
	assert_array(w.played).is_equal([
		AdvancedMeleeWeapon.MoveShape.SLASH,
		AdvancedMeleeWeapon.MoveShape.SLASH,
		AdvancedMeleeWeapon.MoveShape.THRUST,
		AdvancedMeleeWeapon.MoveShape.SLASH,
	])

func test_tap_chain_resets_after_window() -> void:
	var w := _tap_probe()
	w.on_press(null)            # step 0
	w._tick_impl(0.6)           # window (0.5) elapses -> index resets to 0
	w.on_press(null)            # step 0 again, not step 1
	assert_array(w.played).is_equal([
		AdvancedMeleeWeapon.MoveShape.SLASH,
		AdvancedMeleeWeapon.MoveShape.SLASH,
	])

func test_auto_flurry_plays_all_and_locks_input() -> void:
	var w := FlurryProbe.new()
	w.weapon_reach = 30.0
	w.arc_angle = PI / 2.0
	w.cooldown = 0.0
	w.on_press(null)            # starts flurry, plays move 1 immediately
	assert_int(w.played.size()).is_equal(1)
	w.on_press(null)            # ignored: flurry active
	assert_int(w.played.size()).is_equal(1)
	w._tick_impl(0.1)           # move 2
	w._tick_impl(0.1)           # move 3
	assert_int(w.played.size()).is_equal(3)
	w._tick_impl(0.1)           # queue drained -> flurry ends
	assert_bool(w._flurry_active).is_false()
```

- [ ] **Step 2: Run test to verify it passes (or reveals a gap)**

Run: `GODOT_BIN="${GODOT_BIN:-godot}" bash addons/gdUnit4/runtest.sh -a tests/unit/test_advanced_melee_combo.gd`
Expected: PASS (3 tests). If `test_tap_chain_resets_after_window` fails because the index already wrapped, that is fine only if the played sequence still matches; otherwise fix `_do_light_attack`/`_tick_impl` per the code in Task 4.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_advanced_melee_combo.gd
git commit -m "test: pin tap-chain and auto-flurry combo sequencing"
```

---

## Task 6: Move runner — real hits + bespoke animations

Replace the `_play_move` stub with code that applies the move's hit immediately (like the existing melee) and starts a shape-specific cosmetic animation. Animations are verified manually.

**Files:**
- Modify: `src/weapons/advanced_melee_weapon.gd`

- [ ] **Step 1: Implement `_play_move`, hit application, and animation state**

In `src/weapons/advanced_melee_weapon.gd`, add an active-move field near the other vars (after `var _flurry_active`):

```gdscript
var _active_move: Move = null
var _move_phase_time: float = 0.0
var _spin_from_angle: float = 0.0
```

Replace the `_play_move` stub with:

```gdscript
func _play_move(move: Move, user: Node) -> void:
	if user == null:
		return
	var pos: Vector2 = user.global_position
	var direction := _get_facing_direction(user)
	_apply_move_hit(move, user, pos, direction)
	if move.dash_distance > 0.0 and user.has_method("request_dash"):
		user.request_dash(direction, move.dash_distance * 6.0)
	_start_move_anim(move, direction)


func _apply_move_hit(move: Move, user: Node, pos: Vector2, direction: Vector2) -> void:
	_carve_and_push(pos, direction, move.reach, move.arc, damage * move.damage_mult)
	_hit_attackables(user, pos, direction, move.reach, move.arc, move.damage_mult, move.force_crit, move.ignore_parry)
```

- [ ] **Step 2: Implement shape-specific animation dispatch**

Add the animation entry point and per-shape routines. SLASH reuses the inherited swing; THRUST and SPIN are bespoke pose machines applied in `update_visual`.

```gdscript
func _start_move_anim(move: Move, direction: Vector2) -> void:
	_active_move = move
	_move_phase_time = 0.0
	match move.shape:
		MoveShape.SLASH:
			if move.swing_dir != 0.0:
				_swing_toggle = -move.swing_dir      # _start_swing negates, so pre-invert to force up/down
			_start_swing(direction)                  # inherited cosmetic swing
			_active_move = null                      # slash uses the parent state machine
		MoveShape.THRUST, MoveShape.SPIN:
			_facing_angle = direction.angle()
			if absf(direction.x) > 0.01:
				_facing_sign = signf(direction.x)
			_spin_from_angle = _facing_angle
			_is_swinging = true                      # block idle pose; we drive it below


func update_visual(delta: float, user: Node) -> void:
	# Bespoke thrust/spin run here; everything else defers to MeleeWeapon's swing.
	if _active_move != null and (_active_move.shape == MoveShape.THRUST or _active_move.shape == MoveShape.SPIN):
		_process_special_move(delta, user)
		return
	super.update_visual(delta, user)


func _process_special_move(delta: float, user: Node) -> void:
	if visual == null:
		return
	_current_user = user
	var dir := _get_facing_direction(user)
	_facing_angle = dir.angle()
	_move_phase_time += delta
	var facing := _facing_unit()
	match _active_move.shape:
		MoveShape.THRUST:
			_animate_thrust(facing)
		MoveShape.SPIN:
			_animate_spin()


func _animate_thrust(facing: Vector2) -> void:
	# Fast stab out then snap back over ~0.18s.
	var dur := 0.18
	var t := clampf(_move_phase_time / dur, 0.0, 1.0)
	var out := sin(t * PI)                                   # 0 -> 1 -> 0
	var lunge := weapon_reach * 0.6
	_pose_pos = _rest_pos() + facing * (rest_forward + lunge * out)
	_pose_rot = _blade_to_sprite_rot(_facing_angle)
	_pose_scale = Vector2(1.0 + 0.25 * out, 1.0 - 0.15 * out)
	_apply_pose()
	if _active_move != null and t >= 1.0:
		_end_special_move()


func _animate_spin() -> void:
	# One full blade revolution around the player over ~0.3s, with a body lean.
	var dur := 0.3
	var t := clampf(_move_phase_time / dur, 0.0, 1.0)
	var eased := _ease_out_cubic(t)
	var blade := _spin_from_angle + TAU * eased
	_pose_pos = _rest_pos() + Vector2(cos(blade), sin(blade)) * (weapon_reach * 0.35)
	_pose_rot = _blade_to_sprite_rot(blade)
	_pose_scale = Vector2(1.1, 0.95)
	_apply_pose()
	if t >= 1.0:
		_end_special_move()


func _end_special_move() -> void:
	_active_move = null
	_is_swinging = false
	_process_idle()
```

- [ ] **Step 3: Run the full unit suite (no regressions; logic tests still pass)**

Run: `GODOT_BIN="${GODOT_BIN:-godot}" bash addons/gdUnit4/runtest.sh -a tests/unit`
Expected: PASS. (Charge/combo probes override `_play_move`, so the new animation code is not exercised by them.)

- [ ] **Step 4: Manual smoke test in the editor**

Launch the project, open the console, run `spawn weapon dragon_fang`, pick it up, and attack: confirm three thrust stabs play in sequence. The base melee weapon (slot test weapon) should still swing normally.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/advanced_melee_weapon.gd
git commit -m "feat: AdvancedMeleeWeapon move runner with thrust/spin animations"
```

---

## Task 7: Player dash hook + charge visual tell

**Files:**
- Modify: `src/player/player_controller.gd`
- Test: `tests/unit/test_player_dash.gd`

- [ ] **Step 1: Write the failing dash test**

Create `tests/unit/test_player_dash.gd`:

```gdscript
extends GdUnitTestSuite

const PlayerScript = preload("res://src/player/player_controller.gd")

func test_request_dash_sets_decaying_velocity() -> void:
	var p: PlayerController = auto_free(PlayerScript.new())
	p.request_dash(Vector2.RIGHT, 90.0)
	assert_float(p._dash_velocity.length()).is_equal_approx(90.0, 0.01)
	# Decays toward zero over time.
	p._decay_dash(0.1)
	assert_float(p._dash_velocity.length()).is_less(90.0)

func test_request_dash_ignores_zero_direction() -> void:
	var p: PlayerController = auto_free(PlayerScript.new())
	p.request_dash(Vector2.ZERO, 90.0)
	assert_float(p._dash_velocity.length()).is_equal_approx(0.0, 0.01)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN="${GODOT_BIN:-godot}" bash addons/gdUnit4/runtest.sh -a tests/unit/test_player_dash.gd`
Expected: FAIL — `request_dash` / `_dash_velocity` not found.

- [ ] **Step 3: Add the dash hook to `src/player/player_controller.gd`**

Add a constant next to `KNOCKBACK_DECAY` (after line 22):

```gdscript
const DASH_DECAY := 9.0
```

Add a field next to `_knockback_velocity` (after line 32):

```gdscript
var _dash_velocity: Vector2 = Vector2.ZERO
```

Add these methods (near `on_hit_impact`, e.g. after line 313):

```gdscript
func request_dash(direction: Vector2, speed: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	_dash_velocity = direction.normalized() * speed


func _decay_dash(delta: float) -> void:
	if _dash_velocity.length_squared() > 0.01:
		_dash_velocity *= exp(-DASH_DECAY * delta)
	else:
		_dash_velocity = Vector2.ZERO
```

In `_physics_process`, decay and apply the dash. After the knockback decay line (line 96 `_knockback_velocity *= exp(...)`), add:

```gdscript
	_decay_dash(delta)
```

And where knockback is added to velocity (line 119 `velocity += _knockback_velocity`), change it to:

```gdscript
	velocity += _knockback_velocity + _dash_velocity
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN="${GODOT_BIN:-godot}" bash addons/gdUnit4/runtest.sh -a tests/unit/test_player_dash.gd`
Expected: PASS (2 tests).

- [ ] **Step 5: Add a charge visual tell (manual-verified)**

In `src/weapons/advanced_melee_weapon.gd`, append to the end of `update_visual` is not possible (it returns early); instead add a tint in `_process_idle` override. Add this method to `advanced_melee_weapon.gd`:

```gdscript
func _process_idle() -> void:
	super._process_idle()
	if _charging and _sprite != null:
		var r := get_charge_ratio()
		_sprite.modulate = Color(1.0, 1.0, 1.0).lerp(Color(2.0, 1.6, 0.6), r)
	elif _sprite != null:
		_sprite.modulate = Color(1.0, 1.0, 1.0)
```

- [ ] **Step 6: Run the full suite**

Run: `GODOT_BIN="${GODOT_BIN:-godot}" bash addons/gdUnit4/runtest.sh -a tests/unit`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/player/player_controller.gd src/weapons/advanced_melee_weapon.gd tests/unit/test_player_dash.gd
git commit -m "feat: player dash hook and charge visual tell"
```

---

## Task 8: Wire the nine weapons

Create the per-weapon subclasses, the `void_sword` pull override, repoint the `.tres` files, and add a data-load test.

**Files:**
- Create: nine scripts in `src/weapons/`
- Modify: nine `.tres` files in `resources/weapons/`
- Test: `tests/unit/test_charge_combo_weapons_data.gd`

- [ ] **Step 1: Write the failing data-load test**

Create `tests/unit/test_charge_combo_weapons_data.gd`:

```gdscript
extends GdUnitTestSuite

func _w(id: String) -> AdvancedMeleeWeapon:
	var w = WeaponRegistry.get_weapon_by_id(id)
	w._ensure_moves()
	return w

func test_all_load_as_advanced() -> void:
	for id in ["willowblade", "executioner", "blood_blade", "void_sword",
			"dragon_fang", "grand_knight_sword", "deep_dark_blade",
			"phantom_blade", "qinggang_sword"]:
		var w = WeaponRegistry.get_weapon_by_id(id)
		assert_that(w is AdvancedMeleeWeapon).override_failure_message(
			"'%s' is not AdvancedMeleeWeapon" % id).is_true()

func test_dragon_fang_is_three_thrust_flurry() -> void:
	var w := _w("dragon_fang")
	assert_int(w.combo_mode).is_equal(AdvancedMeleeWeapon.ComboMode.AUTO_FLURRY)
	assert_int(w.light_moves.size()).is_equal(3)
	for m in w.light_moves:
		assert_int(m.shape).is_equal(AdvancedMeleeWeapon.MoveShape.THRUST)

func test_grand_knight_is_slash_slash_thrust() -> void:
	var w := _w("grand_knight_sword")
	assert_int(w.combo_mode).is_equal(AdvancedMeleeWeapon.ComboMode.TAP_CHAIN)
	var shapes := []
	for m in w.light_moves:
		shapes.append(m.shape)
	assert_array(shapes).is_equal([
		AdvancedMeleeWeapon.MoveShape.SLASH,
		AdvancedMeleeWeapon.MoveShape.SLASH,
		AdvancedMeleeWeapon.MoveShape.THRUST,
	])

func test_willowblade_charged_thrust_is_force_crit() -> void:
	var w := _w("willowblade")
	assert_int(w.charged_moves.size()).is_equal(1)
	assert_int(w.charged_moves[0].shape).is_equal(AdvancedMeleeWeapon.MoveShape.THRUST)
	assert_bool(w.charged_moves[0].force_crit).is_true()

func test_executioner_charged_spin_scales() -> void:
	var w := _w("executioner")
	assert_int(w.charged_flurry_max).is_equal(2)
	assert_int(w.charged_moves[0].shape).is_equal(AdvancedMeleeWeapon.MoveShape.SPIN)

func test_blood_blade_charged_slash_has_dash() -> void:
	var w := _w("blood_blade")
	assert_float(w.charged_moves[0].dash_distance).is_greater(0.0)

func test_phantom_thrust_ignores_parry() -> void:
	var w := _w("phantom_blade")
	var thrust = w.light_moves[1]
	assert_int(thrust.shape).is_equal(AdvancedMeleeWeapon.MoveShape.THRUST)
	assert_bool(thrust.ignore_parry).is_true()

func test_deep_dark_is_spin_then_thrust() -> void:
	var w := _w("deep_dark_blade")
	assert_int(w.light_moves[0].shape).is_equal(AdvancedMeleeWeapon.MoveShape.SPIN)
	assert_int(w.light_moves[1].shape).is_equal(AdvancedMeleeWeapon.MoveShape.THRUST)

func test_qinggang_alternates_swing_dir() -> void:
	var w := _w("qinggang_sword")
	assert_float(w.light_moves[0].swing_dir).is_equal(1.0)
	assert_float(w.light_moves[1].swing_dir).is_equal(-1.0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN="${GODOT_BIN:-godot}" bash addons/gdUnit4/runtest.sh -a tests/unit/test_charge_combo_weapons_data.gd`
Expected: FAIL — weapons still load as plain `MeleeWeapon`.

- [ ] **Step 3: Create the eight data-only subclasses**

`src/weapons/willowblade_weapon.gd`:
```gdscript
class_name WillowbladeWeapon
extends AdvancedMeleeWeapon

func _setup_moves() -> void:
	combo_mode = ComboMode.TAP_CHAIN
	charge_time_full = 0.5
	tap_threshold = 0.12
	charged_flurry_max = 1
	light_moves = [_slash()]
	charged_moves = [_thrust(true, false, 0.0)]   # guaranteed-crit thrust
```

`src/weapons/executioner_weapon.gd`:
```gdscript
class_name ExecutionerWeapon
extends AdvancedMeleeWeapon

func _setup_moves() -> void:
	combo_mode = ComboMode.TAP_CHAIN
	charge_time_full = 0.55
	charged_flurry_max = 2
	light_moves = [_slash()]
	charged_moves = [_spin(1.0)]
```

`src/weapons/blood_blade_weapon.gd`:
```gdscript
class_name BloodBladeWeapon
extends AdvancedMeleeWeapon

func _setup_moves() -> void:
	combo_mode = ComboMode.TAP_CHAIN
	charge_time_full = 0.6
	charged_flurry_max = 4
	flurry_step_time = 0.12
	light_moves = [_slash()]
	var lunge := _slash()
	lunge.dash_distance = 36.0
	charged_moves = [lunge]
```

`src/weapons/dragon_fang_weapon.gd`:
```gdscript
class_name DragonFangWeapon
extends AdvancedMeleeWeapon

func _setup_moves() -> void:
	combo_mode = ComboMode.AUTO_FLURRY
	flurry_step_time = 0.14
	light_moves = [_thrust(), _thrust(), _thrust()]
```

`src/weapons/grand_knight_weapon.gd`:
```gdscript
class_name GrandKnightWeapon
extends AdvancedMeleeWeapon

func _setup_moves() -> void:
	combo_mode = ComboMode.TAP_CHAIN
	combo_reset_time = 0.6
	light_moves = [_slash(), _slash(), _thrust()]
```

`src/weapons/deep_dark_weapon.gd`:
```gdscript
class_name DeepDarkWeapon
extends AdvancedMeleeWeapon

func _setup_moves() -> void:
	combo_mode = ComboMode.TAP_CHAIN
	combo_reset_time = 0.6
	light_moves = [_spin(), _thrust()]
```

`src/weapons/phantom_blade_weapon.gd`:
```gdscript
class_name PhantomBladeWeapon
extends AdvancedMeleeWeapon

func _setup_moves() -> void:
	combo_mode = ComboMode.TAP_CHAIN
	combo_reset_time = 0.5
	light_moves = [_slash(1.0), _thrust(false, true, 0.0)]   # up-slash, ghost thrust
```

`src/weapons/qinggang_weapon.gd`:
```gdscript
class_name QinggangWeapon
extends AdvancedMeleeWeapon

func _setup_moves() -> void:
	combo_mode = ComboMode.TAP_CHAIN
	combo_reset_time = 0.5
	light_moves = [_slash(1.0), _slash(-1.0)]   # alternating up/down
```

- [ ] **Step 4: Create the void_sword subclass with the charge pull**

`src/weapons/void_sword_weapon.gd`:
```gdscript
class_name VoidSwordWeapon
extends AdvancedMeleeWeapon

const PULL_RADIUS := 120.0
const PULL_SPEED := 70.0
const ATTACKABLE_LAYER := 1 << 7

func _setup_moves() -> void:
	combo_mode = ComboMode.TAP_CHAIN
	charge_time_full = 0.7
	charged_flurry_max = 1
	light_moves = [_slash()]
	var sweep := _slash(0.0, 1.2)
	sweep.arc = PI            # wide finishing arc
	charged_moves = [sweep]

func _on_charge_tick(user, delta: float, ratio: float) -> void:
	if user == null or not (user is Node2D):
		return
	var origin: Vector2 = user.global_position
	var space_state: PhysicsDirectSpaceState2D = user.get_world_2d().direct_space_state
	var circle := CircleShape2D.new()
	circle.radius = PULL_RADIUS
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = circle
	params.transform = Transform2D(0.0, origin)
	params.collision_mask = ATTACKABLE_LAYER
	params.collide_with_areas = true
	params.collide_with_bodies = true
	var hits := space_state.intersect_shape(params, 32)
	for hit in hits:
		var node = hit.get("collider", null)
		if node == null or node == user or not (node is Node2D):
			continue
		var to_origin: Vector2 = origin - node.global_position
		if to_origin.length() < 4.0:
			continue
		node.global_position += to_origin.normalized() * PULL_SPEED * ratio * delta
```

- [ ] **Step 5: Repoint the nine `.tres` files**

For each weapon, change the script path in its `.tres`. Example — `resources/weapons/willowblade.tres` currently:
```
[gd_resource type="Resource" script_class="MeleeWeapon" format=3 uid="uid://wwillowblade"]
[ext_resource type="Script" path="res://src/weapons/melee_weapon.gd" id="1"]
[resource]
script = ExtResource("1")
weapon_reach = 28.0
arc_angle = 1.5707963268
```
Change the two referenced lines to:
```
[gd_resource type="Resource" script_class="WillowbladeWeapon" format=3 uid="uid://wwillowblade"]
[ext_resource type="Script" path="res://src/weapons/willowblade_weapon.gd" id="1"]
```
(Keep the `[resource]` block, `uid`, and stat fields unchanged.)

Apply the same edit to each file, using its matching script:

| `.tres` | `script_class` | `path` |
|---|---|---|
| `executioner.tres` | `ExecutionerWeapon` | `res://src/weapons/executioner_weapon.gd` |
| `blood_blade.tres` | `BloodBladeWeapon` | `res://src/weapons/blood_blade_weapon.gd` |
| `void_sword.tres` | `VoidSwordWeapon` | `res://src/weapons/void_sword_weapon.gd` |
| `dragon_fang.tres` | `DragonFangWeapon` | `res://src/weapons/dragon_fang_weapon.gd` |
| `grand_knight_sword.tres` | `GrandKnightWeapon` | `res://src/weapons/grand_knight_weapon.gd` |
| `deep_dark_blade.tres` | `DeepDarkWeapon` | `res://src/weapons/deep_dark_weapon.gd` |
| `phantom_blade.tres` | `PhantomBladeWeapon` | `res://src/weapons/phantom_blade_weapon.gd` |
| `qinggang_sword.tres` | `QinggangWeapon` | `res://src/weapons/qinggang_weapon.gd` |

If a `.tres` references the script by a different `id` (e.g. `id="1"`), keep that id; only the `script_class`, the `ext_resource path`, and (if present) `script = ExtResource(...)` must point to the new script.

- [ ] **Step 6: Run the data-load test**

Run: `GODOT_BIN="${GODOT_BIN:-godot}" bash addons/gdUnit4/runtest.sh -a tests/unit/test_charge_combo_weapons_data.gd`
Expected: PASS (9 tests).

- [ ] **Step 7: Run the full suite (confirm `test_new_swords_load` still passes — IS-A MeleeWeapon)**

Run: `GODOT_BIN="${GODOT_BIN:-godot}" bash addons/gdUnit4/runtest.sh -a tests/unit`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add src/weapons/*_weapon.gd resources/weapons/*.tres tests/unit/test_charge_combo_weapons_data.gd
git commit -m "feat: wire nine charge/combo weapons to AdvancedMeleeWeapon"
```

---

## Task 9: Integration playtest + close out

**Files:**
- Modify: `docs/design_docs/implementation_todo.md`

- [ ] **Step 1: Manual playtest each weapon in the editor**

Launch the project. For each id, open the console, run `spawn weapon <id>`, pick it up, and verify against the CSV description:
- `willowblade` — tap swings; held release lands a crit thrust (yellow charge tint while holding).
- `executioner` — tap chop; held release does one or two spins depending on charge.
- `blood_blade` — held release lunges the player forward through a burst of slashes.
- `void_sword` — holding pulls nearby dummies inward; release sweeps a wide arc.
- `dragon_fang` — one press → three thrusts.
- `grand_knight_sword` — three taps → slash, slash, thrust; pausing resets the chain.
- `deep_dark_blade` — spin then thrust.
- `phantom_blade` — up-slash then thrust; thrust passes through a `spawn static_slash` parry dummy.
- `qinggang_sword` — alternating up/down slashes.

Use `spawn enemy dummy` and `spawn static_slash` for targets.

- [ ] **Step 2: Check off the Sub-project 2 rows in `docs/design_docs/implementation_todo.md`**

In the "Sub-project 2: Charge + Combos" table (lines 141-146), set the `Done` cell to `x` for all three rows:
```
| x | P1 | High | Charge input | Hold-to-charge attack input + Weapon charge API |
| x | P1 | High | Combo sequencing | Sequential multi-step attacks (slashes/thrusts/spins) |
| x | P1 | High | Wire charge/combo weapons | willowblade, blood_blade, executioner, void_sword, dragon_fang, grand_knight, deep_dark, phantom_blade, qinggang |
```

- [ ] **Step 3: Final full suite run**

Run: `GODOT_BIN="${GODOT_BIN:-godot}" bash addons/gdUnit4/runtest.sh -a tests/unit`
Expected: PASS (all suites, including the new charge/combo/dash/data tests).

- [ ] **Step 4: Commit**

```bash
git add docs/design_docs/implementation_todo.md
git commit -m "docs: mark Sub-project 2 (charge + combos) complete"
```

---

## Notes for the implementer

- **Why hits fire on `_play_move`, not during animation:** the existing `MeleeWeapon` applies damage synchronously in `_use_impl`; the swing animation is purely cosmetic. `AdvancedMeleeWeapon` follows that model — `_apply_move_hit` runs immediately, animations are decoration. This is what makes the charge/combo logic unit-testable by overriding `_play_move`.
- **Lazy `_ensure_moves`:** moves are built on first use (not in `_init`) because `.tres` stats like `weapon_reach` are applied *after* `_init`. `duplicate(true)` resets `_moves_built` to false via member-initializer, so a dropped/copied weapon rebuilds correctly — sidestepping the `@export`/`duplicate()` hazard.
- **Thrust as a narrow arc:** thrust hit detection reuses `_hit_attackables` with a narrow `arc` (~20°) and longer `reach`, rather than a separate capsule query — DRY and sufficient.
- **Spin as a full-circle arc:** `arc = TAU` makes `_is_inside_arc` accept all directions.
```
