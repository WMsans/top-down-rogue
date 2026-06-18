# SP-D — Native Melee Mechanics + 18 Melee Weapons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all 18 SP-D melee weapons drop and function, by adding the native melee mechanics their identities require (double-hit, surround sweep, charged spin/shockwave, projectile reflect, heal-on-kill, low-HP ramp, per-kill stacking, free-carve).

**Architecture:** Two new overridable seams on `Weapon` (`_native_modify_hit_damage`, `_native_on_kill`) let bespoke archetypes inject native behavior through the existing `resolve_hit` chokepoint. Eight new archetype scripts (extending `MeleeWeapon`/`AdvancedMeleeWeapon`) own one behavior each; two weapons get native carve via a `free_carve` data flag. A shared `CombatUtil.radial_knockback` factors the existing knockback loop. Per spec `docs/superpowers/specs/2026-06-17-sp-d-native-melee-design.md`.

**Tech Stack:** Godot 4 / GDScript, gdUnit4 tests, CSV-driven weapon factory (SP-A).

**Test command (used throughout):**
```bash
GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/<file>.gd
```

**Context already verified:**
- `Weapon.resolve_hit()` is `src/weapons/weapon.gd:158-184`; `get_effective_stats`/`_seed_effective_stats` at `:118-152`.
- `MeleeWeapon._carve_and_push()` is `src/weapons/melee_weapon.gd:144-154`; `_destroy_projectiles_in_arc()` is `:455-477`; `@export` block starts `:4`.
- `AdvancedMeleeWeapon` move helpers `_slash()/_thrust()/_spin()` at `src/weapons/advanced_melee_weapon.gd:58-86`; charged dispatch `_do_charged_attack` at `:163-178`.
- `DataModifier._do_knockback/_radial_targets` at `src/weapons/modifiers/data_modifier.gd:66-96`.
- `weapon_registry._ready()` archetype block ends `src/autoload/weapon_registry.gd:61`; `_apply_tuning()` melee branch `:155-161`.
- `PlayerInventory` (`src/player/player_inventory.gd`): `max_health` `:12`, `_current_health` `:20`, `heal()` `:127`.
- `Projectile` (`src/weapons/projectile.gd`): `is_enemy_projectile` `:7`, `direction` `:18`, `source_weapon` `:20`, mask includes attackable layer `:29`.

---

## Task 1: Native hook seams on `Weapon` + `resolve_hit` wiring

**Files:**
- Modify: `src/weapons/weapon.gd` (add two virtuals; call them inside `resolve_hit`)
- Test: `tests/unit/test_native_weapon_hooks.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_native_weapon_hooks.gd`:

```gdscript
extends GdUnitTestSuite

class _Target extends Node2D:
	var health: float = 10.0
	func _init() -> void:
		add_to_group("attackable")
	func on_hit_impact(_p: Vector2, _d: Vector2, dmg: int) -> void:
		health -= dmg

class _NativeWeapon extends Weapon:
	var killed: int = 0
	var dmg_calls: int = 0
	func _native_modify_hit_damage(_u: Node, _t: Node, dmg: float) -> float:
		dmg_calls += 1
		return dmg * 2.0
	func _native_on_kill(_u: Node, _t: Node) -> void:
		killed += 1

func test_native_modify_hit_damage_folds_into_resolve_hit() -> void:
	var w := _NativeWeapon.new()
	var t := auto_free(_Target.new())
	add_child(t)
	w.resolve_hit(null, t, 3.0, false)
	# 3.0 base * 2.0 native = 6 -> health 10 - 6 = 4
	assert_int(w.dmg_calls).is_equal(1)
	assert_float(t.health).is_equal_approx(4.0, 0.001)

func test_native_on_kill_fires_once_on_lethal_hit() -> void:
	var w := _NativeWeapon.new()
	var t := auto_free(_Target.new())
	t.health = 4.0
	add_child(t)
	w.resolve_hit(null, t, 3.0, false)  # 3*2=6 >= 4 -> kill
	assert_int(w.killed).is_equal(1)

func test_native_on_kill_does_not_fire_on_nonlethal_hit() -> void:
	var w := _NativeWeapon.new()
	var t := auto_free(_Target.new())
	t.health = 100.0
	add_child(t)
	w.resolve_hit(null, t, 3.0, false)
	assert_int(w.killed).is_equal(0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_native_weapon_hooks.gd`
Expected: FAIL (default `resolve_hit` does not double damage / does not increment `killed`).

- [ ] **Step 3: Add the seams and wire them in**

In `src/weapons/weapon.gd`, add the two virtuals immediately after `resolve_hit` (after line 184):

```gdscript
func _native_modify_hit_damage(_user: Node, _target: Node, dmg: float) -> float:
	return dmg


func _native_on_kill(_user: Node, _target: Node) -> void:
	pass
```

Then edit `resolve_hit` (`src/weapons/weapon.gd:158-184`). After the modifier damage loop and before reading `had_hp`, insert the native damage fold; inside the kill branch after the modifier `on_kill` loop, insert the native kill call. The function becomes:

```gdscript
func resolve_hit(user: Node, target: Node, base_dmg: float, is_crit: bool) -> void:
	var dmg: float = base_dmg
	if is_crit:
		dmg *= get_effective_stats()["crit_multiplier"]
	for m in modifiers:
		if m != null:
			dmg = m.modify_hit_damage(self, user, target, dmg)
	dmg = _native_modify_hit_damage(user, target, dmg)
	var had_hp: bool = ("health" in target)
	var pre_hp: float = target.health if had_hp else 1.0
	if target.has_method("on_hit_impact"):
		var hit_dir: Vector2 = Vector2.ZERO
		if target is Node2D and user is Node2D:
			hit_dir = (target.global_position - user.global_position).normalized()
		target.on_hit_impact(target.global_position if target is Node2D else Vector2.ZERO, hit_dir, int(dmg))
	for m in modifiers:
		if m != null:
			m.on_hit_target(self, user, target)
	if is_crit:
		_on_crit(target)
		for m in modifiers:
			if m != null:
				m.on_crit(self, user, target)
	_hit_count += 1
	if had_hp and pre_hp > 0.0 and target.health <= 0.0:
		for m in modifiers:
			if m != null:
				m.on_kill(self, user, target)
		_native_on_kill(user, target)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_native_weapon_hooks.gd`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/weapon.gd tests/unit/test_native_weapon_hooks.gd
git commit -m "feat: native hit-damage and on-kill seams on Weapon.resolve_hit"
```

---

## Task 2: `PlayerInventory.get_health_fraction()`

**Files:**
- Modify: `src/player/player_inventory.gd` (add getter near `heal()`)
- Test: `tests/unit/test_player_health_fraction.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_player_health_fraction.gd`:

```gdscript
extends GdUnitTestSuite

func test_full_health_is_one() -> void:
	var inv := auto_free(PlayerInventory.new())
	inv.max_health = 100
	add_child(inv)  # _ready sets _current_health = max_health
	assert_float(inv.get_health_fraction()).is_equal_approx(1.0, 0.001)

func test_fraction_scales_with_current_health() -> void:
	var inv := auto_free(PlayerInventory.new())
	inv.max_health = 100
	add_child(inv)
	inv.take_damage(75)
	assert_float(inv.get_health_fraction()).is_equal_approx(0.25, 0.02)
```

(If `take_damage` has a different name, check `src/player/player_inventory.gd` and use the actual damage method; the assertion on the fraction is what matters.)

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_player_health_fraction.gd`
Expected: FAIL with "Invalid call ... get_health_fraction".

- [ ] **Step 3: Add the getter**

In `src/player/player_inventory.gd`, add directly above `func heal(amount: int) -> void:` (`:127`):

```gdscript
func get_health_fraction() -> float:
	return float(_current_health) / float(maxi(1, max_health))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_player_health_fraction.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/player/player_inventory.gd tests/unit/test_player_health_fraction.gd
git commit -m "feat: PlayerInventory.get_health_fraction getter"
```

---

## Task 3: `CombatUtil.radial_knockback` (factor existing knockback)

**Files:**
- Create: `src/weapons/combat_util.gd`
- Modify: `src/weapons/modifiers/data_modifier.gd:66-96` (call the helper)
- Test: `tests/unit/test_combat_util_radial_knockback.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_combat_util_radial_knockback.gd`:

```gdscript
extends GdUnitTestSuite

const CombatUtilScript = preload("res://src/weapons/combat_util.gd")

class _Foe extends Node2D:
	var last_dir: Vector2 = Vector2.ZERO
	var last_strength: float = -1.0
	func _init() -> void:
		add_to_group("attackable")
	func apply_knockback(direction: Vector2, strength: float) -> void:
		last_dir = direction
		last_strength = strength

func test_knocks_back_targets_inside_radius_away_from_source() -> void:
	var src := auto_free(Node2D.new())
	add_child(src)
	src.global_position = Vector2.ZERO
	var near := _Foe.new()
	src.add_child(near)
	near.global_position = Vector2(10, 0)
	var far := _Foe.new()
	src.add_child(far)
	far.global_position = Vector2(500, 0)
	CombatUtilScript.radial_knockback(src, 50.0, 120.0)
	assert_float(near.last_strength).is_equal_approx(120.0, 0.001)
	assert_float(near.last_dir.x).is_greater(0.0)   # pushed away from source (+x)
	assert_float(far.last_strength).is_equal(-1.0)   # outside radius, untouched
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_combat_util_radial_knockback.gd`
Expected: FAIL (file does not exist).

- [ ] **Step 3: Create the helper**

Create `src/weapons/combat_util.gd`:

```gdscript
class_name CombatUtil
extends RefCounted

# Push every attackable within `radius` of `source` away from it at `strength`.
static func radial_knockback(source: Node, radius: float, strength: float) -> void:
	if source == null or not (source is Node2D):
		return
	var tree := source.get_tree()
	if tree == null:
		return
	var origin: Vector2 = (source as Node2D).global_position
	var r2: float = radius * radius
	for n in tree.get_nodes_in_group("attackable"):
		if n == source or not is_instance_valid(n) or not (n is Node2D):
			continue
		if not n.has_method("apply_knockback"):
			continue
		var to_n: Vector2 = (n as Node2D).global_position - origin
		if to_n.length_squared() > r2:
			continue
		var dir: Vector2 = to_n.normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.DOWN
		n.apply_knockback(dir, strength)
```

- [ ] **Step 4: Refactor `DataModifier` to use it**

Replace `DataModifier._do_knockback` and `_radial_targets` (`src/weapons/modifiers/data_modifier.gd:66-96`) with:

```gdscript
func _do_knockback(user: Node, ctx: Dictionary) -> void:
	if trigger == "on_charge":
		if not ctx.get("charged", false) or ctx.get("charge_ratio", 0.0) < 1.0:
			return
	elif trigger != "on_swing":
		return
	if user == null or not (user is Node2D):
		return
	var radius: float = magnitude * KNOCKBACK_RADIUS_FACTOR
	CombatUtil.radial_knockback(user, radius, magnitude)
```

- [ ] **Step 5: Run knockback + existing SP-B modifier tests**

Run:
```bash
GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_combat_util_radial_knockback.gd
```
Expected: PASS. Then run any SP-B knockback modifier suite if present (e.g. `test_sp_b1_modifier_scripts.gd` / repulsor/shockwave tests) to confirm no regression:
```bash
GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit
```
Expected: PASS (no new failures).

- [ ] **Step 6: Commit**

```bash
git add src/weapons/combat_util.gd src/weapons/modifiers/data_modifier.gd tests/unit/test_combat_util_radial_knockback.gd
git commit -m "refactor: extract CombatUtil.radial_knockback shared helper"
```

---

## Task 4: Free-carve flag on `MeleeWeapon` + factory column

**Files:**
- Modify: `src/weapons/melee_weapon.gd` (add `@export var free_carve`, `_solid_carve_strength()`, use it in `_carve_and_push`)
- Modify: `src/autoload/weapon_registry.gd:155-161` (read `free_carve` CSV column)
- Test: `tests/unit/test_free_carve_flag.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_free_carve_flag.gd`:

```gdscript
extends GdUnitTestSuite

func test_default_carve_strength_is_damage() -> void:
	var w := MeleeWeapon.new()
	w.damage = 5.0
	assert_float(w._solid_carve_strength(5.0)).is_equal_approx(5.0, 0.001)

func test_free_carve_uses_overwhelming_strength() -> void:
	var w := MeleeWeapon.new()
	w.free_carve = true
	assert_float(w._solid_carve_strength(5.0)).is_equal(MeleeWeapon.FREE_CARVE_STRENGTH)

func test_free_carve_survives_duplicate() -> void:
	var w := MeleeWeapon.new()
	w.free_carve = true
	var copy: MeleeWeapon = w.duplicate(true)
	assert_bool(copy.free_carve).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_free_carve_flag.gd`
Expected: FAIL ("Invalid get index 'free_carve'" / "_solid_carve_strength").

- [ ] **Step 3: Add the flag and strength helper**

In `src/weapons/melee_weapon.gd`, add after `@export var weapon_reach: float = 36.0` (`:8`):

```gdscript
@export var free_carve: bool = false
const FREE_CARVE_STRENGTH := 1.0e9
```

Add this method anywhere in the class (e.g. just after `_carve_and_push`):

```gdscript
func _solid_carve_strength(dmg: float) -> float:
	return FREE_CARVE_STRENGTH if free_carve else dmg
```

Edit `_carve_and_push` (`:144-154`) so the solids clear uses the helper. Change the final call's damage argument from `dmg` to `_solid_carve_strength(dmg)`:

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
	TerrainSurface.clear_and_push_materials_in_arc(pos, direction, reach, arc, 0.0, 0.0, solids, _solid_carve_strength(dmg))
```

- [ ] **Step 4: Read the CSV column in the factory**

In `src/autoload/weapon_registry.gd`, inside `_apply_tuning`'s `if weapon is MeleeWeapon:` branch (`:155-161`), add after the arc handling:

```gdscript
		var fc: String = row.get("free_carve", "").strip_edges()
		if fc != "":
			(weapon as MeleeWeapon).free_carve = (fc == "Yes")
```

- [ ] **Step 5: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_free_carve_flag.gd`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add src/weapons/melee_weapon.gd src/autoload/weapon_registry.gd tests/unit/test_free_carve_flag.gd
git commit -m "feat: free_carve flag carves any terrain (data-driven)"
```

---

## Task 5: `war_scythe` archetype (surround/rear sweep)

**Files:**
- Create: `src/weapons/war_scythe_weapon.gd`
- Test: `tests/unit/test_war_scythe_weapon.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_war_scythe_weapon.gd`:

```gdscript
extends GdUnitTestSuite

const WarScythe = preload("res://src/weapons/war_scythe_weapon.gd")

class _Target extends Area2D:
	var hits: Array = []
	var health: float = 100.0
	func _init() -> void:
		add_to_group("attackable")
		set_collision_layer_value(8, true)
		var col := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 4.0
		col.shape = shape
		add_child(col)
	func on_hit_impact(_p: Vector2, _d: Vector2, dmg: int) -> void:
		hits.append(dmg)

func test_arc_is_300_degrees() -> void:
	var w := WarScythe.new()
	assert_float(rad_to_deg(w.arc_angle)).is_equal_approx(300.0, 0.5)

func test_hits_rear_flank_but_not_directly_behind() -> void:
	var parent: Area2D = auto_free(Area2D.new())
	add_child(parent)
	var user := Node2D.new()
	parent.add_child(user)
	user.global_position = Vector2.ZERO
	# Facing +x. Rear-flank target at 150-ish deg (within 300 arc).
	var flank := _Target.new()
	parent.add_child(flank)
	flank.global_position = Vector2(-8.66, 5.0)   # ~150 deg, dist 10
	# Directly-behind target at 180 deg (in the ~60 deg blind spot).
	var behind := _Target.new()
	parent.add_child(behind)
	behind.global_position = Vector2(-10.0, 0.0)
	var w := WarScythe.new()
	w.crit_chance = 0.0
	await get_tree().physics_frame
	w._hit_attackables(user, Vector2.ZERO, Vector2.RIGHT, w.weapon_reach, w.arc_angle, 1.0, false, true)
	assert_int(flank.hits.size()).is_equal(1)
	assert_int(behind.hits.size()).is_equal(0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_war_scythe_weapon.gd`
Expected: FAIL (file does not exist).

- [ ] **Step 3: Create the archetype**

Create `src/weapons/war_scythe_weapon.gd`:

```gdscript
class_name WarScytheWeapon
extends MeleeWeapon

func _init() -> void:
	super._init()
	weapon_reach = 44.0
	arc_angle = deg_to_rad(300.0)   # hit detection: flanks + behind, ~60 deg blind spot
	half_arc = deg_to_rad(150.0)    # cosmetic sweep wraps to match the hit arc
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_war_scythe_weapon.gd`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/war_scythe_weapon.gd tests/unit/test_war_scythe_weapon.gd
git commit -m "feat: war_scythe archetype (300-degree reaping sweep)"
```

---

## Task 6: `twin_daggers` archetype (double-hit)

**Files:**
- Create: `src/weapons/twin_daggers_weapon.gd`
- Test: `tests/unit/test_twin_daggers_weapon.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_twin_daggers_weapon.gd`:

```gdscript
extends GdUnitTestSuite

const TwinDaggers = preload("res://src/weapons/twin_daggers_weapon.gd")

# Probe records dispatched moves without touching physics/animation.
class Probe extends TwinDaggers:
	var played: Array = []
	func _play_move(move, _user) -> void:
		played.append(move)

func test_one_attack_dispatches_two_passes() -> void:
	var w := Probe.new()
	w._use_impl(null)               # AUTO_FLURRY: first pass immediate
	assert_int(w.played.size()).is_equal(1)
	w._tick_impl(1.0)               # drain the second pass
	assert_int(w.played.size()).is_equal(2)

func test_uses_auto_flurry_with_two_light_moves() -> void:
	var w := TwinDaggers.new()
	w._ensure_moves()
	assert_int(w.combo_mode).is_equal(AdvancedMeleeWeapon.ComboMode.AUTO_FLURRY)
	assert_int(w.light_moves.size()).is_equal(2)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_twin_daggers_weapon.gd`
Expected: FAIL (file does not exist).

- [ ] **Step 3: Create the archetype**

Create `src/weapons/twin_daggers_weapon.gd`:

```gdscript
class_name TwinDaggersWeapon
extends AdvancedMeleeWeapon

func _init() -> void:
	super._init()
	weapon_reach = 22.0
	arc_angle = deg_to_rad(60.0)

func _setup_moves() -> void:
	combo_mode = ComboMode.AUTO_FLURRY
	flurry_step_time = 0.05
	light_moves = [_slash(), _slash()]
	charged_moves = []
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_twin_daggers_weapon.gd`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/twin_daggers_weapon.gd tests/unit/test_twin_daggers_weapon.gd
git commit -m "feat: twin_daggers archetype (double-hit flurry)"
```

---

## Task 7: `whirlwind_blade` archetype (charged 360 spin)

**Files:**
- Create: `src/weapons/whirlwind_blade_weapon.gd`
- Test: `tests/unit/test_whirlwind_blade_weapon.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_whirlwind_blade_weapon.gd`:

```gdscript
extends GdUnitTestSuite

const Whirlwind = preload("res://src/weapons/whirlwind_blade_weapon.gd")

class Probe extends Whirlwind:
	var played: Array = []
	func _play_move(move, _user) -> void:
		played.append(move)

func test_tap_plays_normal_slash() -> void:
	var w := Probe.new()
	w.on_press(null)
	w._tick_impl(0.05)          # below tap threshold
	w.on_release(null)
	assert_int(w.played.size()).is_equal(1)
	assert_int(w.played[0].shape).is_equal(AdvancedMeleeWeapon.MoveShape.SLASH)

func test_full_charge_plays_360_spin() -> void:
	var w := Probe.new()
	w.on_press(null)
	w._tick_impl(2.0)           # full charge
	w.on_release(null)
	assert_int(w.played.size()).is_equal(1)
	assert_int(w.played[0].shape).is_equal(AdvancedMeleeWeapon.MoveShape.SPIN)
	assert_float(w.played[0].arc).is_equal_approx(TAU, 0.001)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_whirlwind_blade_weapon.gd`
Expected: FAIL (file does not exist).

- [ ] **Step 3: Create the archetype**

Create `src/weapons/whirlwind_blade_weapon.gd`:

```gdscript
class_name WhirlwindBladeWeapon
extends AdvancedMeleeWeapon

func _init() -> void:
	super._init()
	weapon_reach = 30.0
	arc_angle = deg_to_rad(90.0)

func _setup_moves() -> void:
	combo_mode = ComboMode.TAP_CHAIN
	charge_time_full = 0.6
	charged_flurry_max = 1
	light_moves = [_slash()]
	charged_moves = [_spin()]   # _spin() arc is TAU (full circle)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_whirlwind_blade_weapon.gd`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/whirlwind_blade_weapon.gd tests/unit/test_whirlwind_blade_weapon.gd
git commit -m "feat: whirlwind_blade archetype (charged 360 spin)"
```

---

## Task 8: `quake_hammer` archetype (charged shockwave)

**Files:**
- Create: `src/weapons/quake_hammer_weapon.gd`
- Test: `tests/unit/test_quake_hammer_weapon.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_quake_hammer_weapon.gd`:

```gdscript
extends GdUnitTestSuite

const QuakeHammer = preload("res://src/weapons/quake_hammer_weapon.gd")

class _Foe extends Node2D:
	var knocked: bool = false
	func _init() -> void:
		add_to_group("attackable")
	func apply_knockback(_dir: Vector2, _strength: float) -> void:
		knocked = true

class Probe extends QuakeHammer:
	var shockwaves: int = 0
	func _play_move(_move, _user) -> void:
		pass                       # skip physics/animation
	func _emit_shockwave(_user) -> void:
		shockwaves += 1

func test_shockwave_knocks_back_nearby_attackables() -> void:
	var user := auto_free(Node2D.new())
	add_child(user)
	user.global_position = Vector2.ZERO
	var foe := _Foe.new()
	user.add_child(foe)
	foe.global_position = Vector2(20, 0)
	var w := QuakeHammer.new()
	w._emit_shockwave(user)
	assert_bool(foe.knocked).is_true()

func test_charged_release_emits_shockwave_tap_does_not() -> void:
	var w := Probe.new()
	w.on_press(null)
	w._tick_impl(2.0)              # full charge
	w.on_release(null)
	assert_int(w.shockwaves).is_equal(1)

	var w2 := Probe.new()
	w2.on_press(null)
	w2._tick_impl(0.05)           # tap
	w2.on_release(null)
	assert_int(w2.shockwaves).is_equal(0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_quake_hammer_weapon.gd`
Expected: FAIL (file does not exist).

- [ ] **Step 3: Create the archetype**

Create `src/weapons/quake_hammer_weapon.gd`:

```gdscript
class_name QuakeHammerWeapon
extends AdvancedMeleeWeapon

const SHOCKWAVE_RADIUS := 70.0
const SHOCKWAVE_STRENGTH := 140.0

func _init() -> void:
	super._init()
	weapon_reach = 32.0
	arc_angle = deg_to_rad(110.0)

func _setup_moves() -> void:
	combo_mode = ComboMode.TAP_CHAIN
	charge_time_full = 0.8
	charged_flurry_max = 1
	light_moves = [_slash()]
	charged_moves = [_slash(0.0, 1.0)]   # heavy slam hit; shockwave added below

func _do_charged_attack(user: Node, ratio: float) -> void:
	super._do_charged_attack(user, ratio)
	_emit_shockwave(user)

func _emit_shockwave(user) -> void:
	CombatUtil.radial_knockback(user, SHOCKWAVE_RADIUS, SHOCKWAVE_STRENGTH)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_quake_hammer_weapon.gd`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/quake_hammer_weapon.gd tests/unit/test_quake_hammer_weapon.gd
git commit -m "feat: quake_hammer archetype (charged knockback shockwave)"
```

---

## Task 9: `mirror_blade` archetype (reflect projectiles)

**Files:**
- Create: `src/weapons/mirror_blade_weapon.gd`
- Test: `tests/unit/test_mirror_blade_weapon.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_mirror_blade_weapon.gd`:

```gdscript
extends GdUnitTestSuite

const MirrorBlade = preload("res://src/weapons/mirror_blade_weapon.gd")
const ProjectileScript = preload("res://src/weapons/projectile.gd")

func test_enemy_projectile_in_arc_is_reflected_not_freed() -> void:
	var user := auto_free(Node2D.new())
	add_child(user)
	user.global_position = Vector2.ZERO
	var proj: Projectile = ProjectileScript.new()
	proj.is_enemy_projectile = true
	proj.direction = Vector2.LEFT          # incoming toward player
	add_child(proj)                        # _ready adds to "projectile" group
	proj.global_position = Vector2(10, 0)  # in front, facing +x, within reach
	var w := MirrorBlade.new()
	await get_tree().physics_frame
	w._destroy_projectiles_in_arc(user, Vector2.ZERO, Vector2.RIGHT)
	assert_bool(is_instance_valid(proj)).is_true()
	assert_bool(proj.is_enemy_projectile).is_false()
	assert_float(proj.direction.x).is_greater(0.0)   # reversed to fly outward
	assert_object(proj.source_weapon).is_same(w)
	proj.queue_free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_mirror_blade_weapon.gd`
Expected: FAIL (file does not exist).

- [ ] **Step 3: Create the archetype**

Create `src/weapons/mirror_blade_weapon.gd`. It overrides the swing's projectile pass (same signature as `MeleeWeapon._destroy_projectiles_in_arc`) to reflect instead of delete:

```gdscript
class_name MirrorBladeWeapon
extends MeleeWeapon

func _init() -> void:
	super._init()
	weapon_reach = 30.0
	arc_angle = deg_to_rad(100.0)

func _destroy_projectiles_in_arc(user: Node, origin: Vector2, direction: Vector2) -> void:
	if user == null:
		return
	var dir_angle: float = direction.angle()
	var half_arc_angle: float = arc_angle / 2.0
	var reflected: int = 0
	for node in user.get_tree().get_nodes_in_group("projectile"):
		if reflected >= 8:
			return
		if not (node is Projectile):
			continue
		var p: Projectile = node
		if not p.is_enemy_projectile:
			continue
		var to_target: Vector2 = p.global_position - origin
		var dist: float = to_target.length()
		if dist > weapon_reach or dist <= 0.001:
			continue
		if absf(angle_difference(dir_angle, to_target.angle())) > half_arc_angle:
			continue
		_reflect(p, origin)
		reflected += 1

func _reflect(p: Projectile, origin: Vector2) -> void:
	p.is_enemy_projectile = false
	# Fly back outward, away from the player.
	var outward: Vector2 = (p.global_position - origin)
	p.direction = outward.normalized() if outward.length() > 0.001 else -p.direction
	p.source_weapon = self
	p.source_node = null
	var sprite := p.get_node_or_null("Sprite2D")
	if sprite:
		sprite.rotation = p.direction.angle() + PI * 3.0 / 4.0
	ProjectileBlockFX.play(p.global_position, -p.direction)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_mirror_blade_weapon.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/mirror_blade_weapon.gd tests/unit/test_mirror_blade_weapon.gd
git commit -m "feat: mirror_blade archetype (reflect enemy projectiles)"
```

---

## Task 10: `reaper_glaive` archetype (heal-on-kill)

**Files:**
- Create: `src/weapons/reaper_glaive_weapon.gd`
- Test: `tests/unit/test_reaper_glaive_weapon.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_reaper_glaive_weapon.gd`:

```gdscript
extends GdUnitTestSuite

const ReaperGlaive = preload("res://src/weapons/reaper_glaive_weapon.gd")

class _Inv extends Node:
	var healed: int = 0
	func _init() -> void:
		name = "PlayerInventory"
	func heal(amount: int) -> void:
		healed += amount

func test_kill_heals_player() -> void:
	var user := auto_free(Node2D.new())
	add_child(user)
	var inv := _Inv.new()
	user.add_child(inv)
	var w := ReaperGlaive.new()
	w._native_on_kill(user, null)
	assert_int(inv.healed).is_equal(ReaperGlaive.REAP_HEAL)

func test_long_reach() -> void:
	var w := ReaperGlaive.new()
	assert_float(w.weapon_reach).is_greater(40.0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_reaper_glaive_weapon.gd`
Expected: FAIL (file does not exist).

- [ ] **Step 3: Create the archetype**

Create `src/weapons/reaper_glaive_weapon.gd`:

```gdscript
class_name ReaperGlaiveWeapon
extends MeleeWeapon

const REAP_HEAL := 2

func _init() -> void:
	super._init()
	weapon_reach = 44.0
	arc_angle = deg_to_rad(100.0)

func _native_on_kill(user: Node, _target: Node) -> void:
	if user == null:
		return
	var inv = user.get_node_or_null("PlayerInventory")
	if inv != null and inv.has_method("heal"):
		inv.heal(REAP_HEAL)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_reaper_glaive_weapon.gd`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/reaper_glaive_weapon.gd tests/unit/test_reaper_glaive_weapon.gd
git commit -m "feat: reaper_glaive archetype (native heal-on-kill)"
```

---

## Task 11: `berserker_axe` archetype (low-HP damage ramp)

**Files:**
- Create: `src/weapons/berserker_axe_weapon.gd`
- Test: `tests/unit/test_berserker_axe_weapon.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_berserker_axe_weapon.gd`:

```gdscript
extends GdUnitTestSuite

const BerserkerAxe = preload("res://src/weapons/berserker_axe_weapon.gd")

class _Inv extends Node:
	var frac: float = 1.0
	func _init() -> void:
		name = "PlayerInventory"
	func get_health_fraction() -> float:
		return frac

func _user_with_hp(frac: float) -> Node2D:
	var user := auto_free(Node2D.new())
	add_child(user)
	var inv := _Inv.new()
	inv.frac = frac
	user.add_child(inv)
	return user

func test_full_hp_no_ramp() -> void:
	var w := BerserkerAxe.new()
	var user := _user_with_hp(1.0)
	assert_float(w._native_modify_hit_damage(user, null, 10.0)).is_equal_approx(10.0, 0.01)

func test_near_death_max_ramp() -> void:
	var w := BerserkerAxe.new()
	var user := _user_with_hp(0.0)
	assert_float(w._native_modify_hit_damage(user, null, 10.0)).is_equal_approx(10.0 * BerserkerAxe.MAX_RAMP, 0.01)

func test_missing_inventory_defaults_to_no_ramp() -> void:
	var w := BerserkerAxe.new()
	var bare := auto_free(Node2D.new())
	add_child(bare)
	assert_float(w._native_modify_hit_damage(bare, null, 10.0)).is_equal_approx(10.0, 0.01)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_berserker_axe_weapon.gd`
Expected: FAIL (file does not exist).

- [ ] **Step 3: Create the archetype**

Create `src/weapons/berserker_axe_weapon.gd`:

```gdscript
class_name BerserkerAxeWeapon
extends MeleeWeapon

const MAX_RAMP := 1.6

func _init() -> void:
	super._init()
	weapon_reach = 34.0
	arc_angle = deg_to_rad(110.0)

func _native_modify_hit_damage(user: Node, _target: Node, dmg: float) -> float:
	var frac: float = 1.0
	if user != null:
		var inv = user.get_node_or_null("PlayerInventory")
		if inv != null and inv.has_method("get_health_fraction"):
			frac = inv.get_health_fraction()
	return dmg * lerpf(1.0, MAX_RAMP, 1.0 - clampf(frac, 0.0, 1.0))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_berserker_axe_weapon.gd`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/berserker_axe_weapon.gd tests/unit/test_berserker_axe_weapon.gd
git commit -m "feat: berserker_axe archetype (low-HP damage ramp)"
```

---

## Task 12: `soul_reaver` archetype (per-kill stacking)

**Files:**
- Create: `src/weapons/soul_reaver_weapon.gd`
- Test: `tests/unit/test_soul_reaver_weapon.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_soul_reaver_weapon.gd`:

```gdscript
extends GdUnitTestSuite

const SoulReaver = preload("res://src/weapons/soul_reaver_weapon.gd")

func test_kill_raises_effective_damage_by_one_stack() -> void:
	var w := SoulReaver.new()
	w.damage = 5.0
	var base: float = w.get_effective_stats()["damage"]
	w._native_on_kill(null, null)
	assert_float(w.get_effective_stats()["damage"]).is_equal_approx(base + SoulReaver.STACK_GAIN, 0.001)

func test_stacks_cap() -> void:
	var w := SoulReaver.new()
	w.damage = 5.0
	for i in range(100):
		w._native_on_kill(null, null)
	assert_float(w.get_effective_stats()["damage"]).is_equal_approx(5.0 + SoulReaver.STACK_CAP, 0.001)

func test_decay_after_delay_reduces_stacks() -> void:
	var w := SoulReaver.new()
	w.damage = 5.0
	w._native_on_kill(null, null)
	w._native_on_kill(null, null)            # 2 stacks * gain
	var before: float = w.get_effective_stats()["damage"]
	w._tick_impl(SoulReaver.DECAY_DELAY + 0.01)   # cross the decay threshold (drops one step)
	assert_float(w.get_effective_stats()["damage"]).is_less(before)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_soul_reaver_weapon.gd`
Expected: FAIL (file does not exist).

- [ ] **Step 3: Create the archetype**

Create `src/weapons/soul_reaver_weapon.gd`:

```gdscript
class_name SoulReaverWeapon
extends MeleeWeapon

const STACK_GAIN := 0.5
const STACK_CAP := 8.0
const DECAY_DELAY := 3.0     # seconds without a kill before stacks bleed
const DECAY_STEP := 1.0      # stacks lost per DECAY_DELAY once decaying

var _kill_stacks: float = 0.0
var _decay_timer: float = 0.0

func _init() -> void:
	super._init()
	weapon_reach = 34.0
	arc_angle = deg_to_rad(100.0)

func _seed_effective_stats() -> Dictionary:
	var s := super._seed_effective_stats()
	s["damage"] += _kill_stacks
	return s

func _native_on_kill(_user: Node, _target: Node) -> void:
	_kill_stacks = minf(_kill_stacks + STACK_GAIN, STACK_CAP)
	_decay_timer = 0.0
	invalidate_effective_stats()

func _tick_impl(delta: float) -> void:
	super._tick_impl(delta)
	if _kill_stacks <= 0.0:
		return
	_decay_timer += delta
	if _decay_timer >= DECAY_DELAY:
		_kill_stacks = maxf(0.0, _kill_stacks - DECAY_STEP)
		_decay_timer = 0.0
		invalidate_effective_stats()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_soul_reaver_weapon.gd`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/soul_reaver_weapon.gd tests/unit/test_soul_reaver_weapon.gd
git commit -m "feat: soul_reaver archetype (per-kill stacking damage)"
```

---

## Task 13: Register archetypes + CSV wiring (reach/arc/free_carve)

**Files:**
- Modify: `src/autoload/weapon_registry.gd:45-61` (register 8 archetypes)
- Modify: `docs/design_docs/weapons.csv` (fill reach/arc for 8 rows; add `free_carve` column)
- Test: `tests/unit/test_sp_d_weapons_build.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_sp_d_weapons_build.gd`:

```gdscript
extends GdUnitTestSuite

# WeaponRegistry is an autoload; in tests reach it via the scene tree root.
func _registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("WeaponRegistry")

func test_all_sp_d_archetype_weapons_build() -> void:
	var reg := _registry()
	assert_object(reg).is_not_null()
	for id in ["war_scythe", "twin_daggers", "whirlwind_blade", "quake_hammer",
			"mirror_blade", "reaper_glaive", "berserker_axe", "soul_reaver"]:
		var w: Weapon = reg.get_weapon_by_id(id)
		assert_object(w).override_failure_message("missing weapon: %s" % id).is_not_null()

func test_free_carve_weapons_have_flag_set() -> void:
	var reg := _registry()
	for id in ["obsidian_greatsword", "gravedigger_spade"]:
		var w = reg.get_weapon_by_id(id)
		assert_object(w).is_not_null()
		assert_bool((w as MeleeWeapon).free_carve).override_failure_message("free_carve not set on %s" % id).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_sp_d_weapons_build.gd`
Expected: FAIL (archetypes unregistered → `get_weapon_by_id` warns and returns null; `free_carve` false).

- [ ] **Step 3: Register the 8 archetypes**

In `src/autoload/weapon_registry.gd`, add these lines immediately after the `qinggang` registration (`:61`):

```gdscript
	weapon_scripts["war_scythe"] = preload("res://src/weapons/war_scythe_weapon.gd")
	weapon_scripts["twin_daggers"] = preload("res://src/weapons/twin_daggers_weapon.gd")
	weapon_scripts["whirlwind_blade"] = preload("res://src/weapons/whirlwind_blade_weapon.gd")
	weapon_scripts["quake_hammer"] = preload("res://src/weapons/quake_hammer_weapon.gd")
	weapon_scripts["mirror_blade"] = preload("res://src/weapons/mirror_blade_weapon.gd")
	weapon_scripts["reaper_glaive"] = preload("res://src/weapons/reaper_glaive_weapon.gd")
	weapon_scripts["berserker_axe"] = preload("res://src/weapons/berserker_axe_weapon.gd")
	weapon_scripts["soul_reaver"] = preload("res://src/weapons/soul_reaver_weapon.gd")
```

- [ ] **Step 4: Add the `free_carve` CSV column**

Edit `docs/design_docs/weapons.csv`. Append `,free_carve` to the **header** row (after the final `projectile_texture` column). For every existing data row, append one trailing empty field (`,`) **except** `obsidian_greatsword` and `gravedigger_spade`, whose new trailing field is `Yes`.

Concretely, the header line ends:
```
...,spread,projectile_count,projectile_texture,free_carve
```
The obsidian row and gravedigger row each end with `,Yes`; all other rows end with `,` (one extra empty trailing value). Verify the column count is consistent afterward:

```bash
awk -F, 'NR==1{n=NF} NF!=n{print "BAD COLUMN COUNT line " NR ": " NF " vs " n}' docs/design_docs/weapons.csv
```
Expected: no output (all rows have equal column count). Note: descriptions are quoted and may contain commas; if `awk` reports false positives on quoted rows, instead spot-check that the header gained `free_carve` and the two carve rows end in `Yes`.

- [ ] **Step 5: (optional) fill reach/arc for the 8 archetype rows**

The archetype scripts set their own `weapon_reach`/`arc_angle` in `_init`, so blank CSV cells already produce correct values (the factory only overrides when a cell is non-empty). To make the tuning visible as data, set these cells in `docs/design_docs/weapons.csv` (`reach` / `arc` columns) to match the scripts:

| id | reach | arc |
|---|---|---|
| war_scythe | 44 | 300 |
| twin_daggers | 22 | 60 |
| whirlwind_blade | 30 | 90 |
| quake_hammer | 32 | 110 |
| mirror_blade | 30 | 100 |
| reaper_glaive | 44 | 100 |
| berserker_axe | 34 | 110 |
| soul_reaver | 34 | 100 |

(Leave blank if you prefer the script defaults as the single source of truth — the tests in Tasks 5-12 read the script values directly, so either choice keeps them green.)

- [ ] **Step 6: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_sp_d_weapons_build.gd`
Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
git add src/autoload/weapon_registry.gd docs/design_docs/weapons.csv tests/unit/test_sp_d_weapons_build.gd
git commit -m "feat: register SP-D melee archetypes + free_carve CSV column"
```

---

## Task 14: Full suite, manual verification, mark todo done

**Files:**
- Modify: `docs/design_docs/implementation_todo.md` (check the SP-D rows)

- [ ] **Step 1: Run the entire unit suite**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit`
Expected: all tests PASS (no regressions; the new SP-D suites green).

- [ ] **Step 2: Manual in-game verification**

Launch the game (`/usr/bin/godot --path .` or the editor), use the cheat console to spawn each weapon, and confirm:
- `twin_daggers`: two hits register per swing (e.g. an on-hit edge stains twice).
- `war_scythe`: a swing hits an enemy beside/behind the player; one directly behind survives.
- `whirlwind_blade`: tap = front arc; hold-to-full = full-circle spin hitting all around.
- `quake_hammer`: full-charge slam knocks surrounding enemies back.
- `mirror_blade`: swinging into an enemy bolt sends it back outward and it damages an enemy.
- `reaper_glaive`: a kill restores a sliver of player HP.
- `berserker_axe`: damage noticeably higher at low HP.
- `soul_reaver`: damage climbs across consecutive kills, bleeds off after a lull.
- `obsidian_greatsword` / `gravedigger_spade`: swings carve through stone walls.
- All ten Bucket-1 + carve weapons show 3 empty modifier slots.

- [ ] **Step 3: Mark the SP-D todo rows done**

In `docs/design_docs/implementation_todo.md`, set the four `Sub-project D (8)` table rows' `Done` column to `x` (the "Native arc shapes", "Double-hit + charged spin", "Native attrition/charge traits", and "Melee `.tres` + stat wiring" rows — the last now means CSV stat wiring, the system being `.tres`-free post-SP-A).

- [ ] **Step 4: Commit**

```bash
git add docs/design_docs/implementation_todo.md
git commit -m "docs: mark Phase 7 SP-D (native melee + 18 weapons) done"
```

---

## Self-Review Notes (for the implementer)

- **Spec coverage:** Task 1 = native seams; Task 2 = HP fraction; Task 3 = shared knockback; Task 4 = free-carve flag; Tasks 5-12 = the 8 archetypes (war_scythe, twin_daggers, whirlwind, quake, mirror, reaper, berserker, soul_reaver); Task 13 = registry + CSV; Task 14 = suite + manual + todo. Bucket-1's 8 weapons need no code (verified live from SP-A) and are spot-checked in Task 14 step 2.
- **Type consistency:** seam names `_native_modify_hit_damage` / `_native_on_kill` are identical in Task 1 and Tasks 10-12. `CombatUtil.radial_knockback(source, radius, strength)` identical in Tasks 3 and 8. `FREE_CARVE_STRENGTH`, `_solid_carve_strength`, `free_carve`, `get_health_fraction`, `REAP_HEAL`, `MAX_RAMP`, `STACK_GAIN/STACK_CAP/DECAY_DELAY/DECAY_STEP` all referenced consistently between their defining task and their tests.
- **Carve test note:** the terrain-clearing integration (stone actually disappearing) is covered by Task 14's manual check, not a unit test — `clear_and_push_materials_in_arc` is an autoload needing a live world. Task 4 unit-tests the observable decision point (`_solid_carve_strength`) instead.
