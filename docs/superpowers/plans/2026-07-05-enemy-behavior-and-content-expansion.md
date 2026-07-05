# Enemy Behavior Depth & Content Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 5 melee archetypes (Grunt/Brute/Skirmisher/Armored/Cultist) and 3 ranged archetypes (Archer/Mage/Lobber), each combining stats, one AI sub-behavior, a wander mode, and a weapon pool — reconciling the existing random weapon-pick spawn logic with the new archetypes and tying weapon rarity to floor depth, kill streak, and boss distance.

**Architecture:** One new `.gd` subclass per archetype (matches the existing `LungeEnemy`/`SniperEnemy` precedent) plus matching `.tscn` scenes. A new `EnemyWeaponPools` static utility builds per-archetype weapon pools from `weapons.csv` (rule-based for melee, explicit lists for ranged) and rolls a rarity tier from floor/kill-streak/sector-tier before picking a weapon ID. `spawn_dispatcher.gd`/`cave_spawner.gd` roll a weighted archetype, then pull a weapon from that archetype's pool.

**Tech Stack:** Godot 4 / GDScript, GdUnitTestSuite for tests (`tests/unit/*.gd`, `assert_bool`/`assert_int`/`assert_float`/`assert_object`/`assert_str`/`assert_vector`).

## Global Constraints

- Per the design spec (`docs/superpowers/specs/2026-07-05-enemy-behavior-and-content-expansion-design.md`): no per-biome roster, no rare spawn enemies, no enemy-environment hazard interaction, no changes to `SniperEnemy` or the boss spawn path.
- No new `ProjectileBehavior`/weapon scripts — Mage uses the already-registered `seeker_launcher_weapon.gd` (homing) and Lobber uses `flame_lobber_weapon.gd` (arc AoE), both already wired in `WeaponRegistry`.
- `EncounterDirector`'s old `aggression_delta`/token-gating system was deliberately removed (2026-06-13 "Remove Attack Tokens" design) and must **not** be reintroduced. The new `kill_streak` field in this plan is narrowly scoped to the rarity roll only.
- All new archetype stat multipliers apply **after** `super._ready()` so they compose correctly with floor-scaling multipliers applied by the spawner before the node enters the tree (before `_ready()` fires).
- Follow existing code style: tabs for indentation, `class_name` + `extends` header, `@export` for tunable fields, GdUnitTestSuite `auto_free()` for test node cleanup.

---

### Task 1: Fix Lunge/Armored sprite mismatch

`LungeEnemy` currently uses the `caves_brute1/2.png` sprite set, but the new dedicated `BruteEnemy` archetype (Task 9) needs that set for itself. Reassign `LungeEnemy` to the `caves_armored1/2.png` set instead, freeing `brute` for the new archetype. (`ArmoredEnemy`, Task 11, will also use the `armored` set — intentional shared reuse, both read as "heavy/tank".)

**Files:**
- Modify: `scenes/enemies/lunge_enemy.tscn`
- Modify: `tests/unit/test_lunge_enemy.gd:217-244`

**Interfaces:**
- Produces: nothing new; purely an asset/test reassignment.

- [ ] **Step 1: Update the failing assertions first**

Edit `tests/unit/test_lunge_enemy.gd`, changing the two texture-path assertions:

```gdscript
func test_windup_holds_breathe_frame() -> void:
	var e := _lunge_from_scene()
	await get_tree().process_frame
	e._change_state(Enemy.State.WINDUP)
	var animator: EnemyAnimator = e.get_node("EnemyAnimator")
	assert_int(animator._hold).is_equal(EnemyAnimator.Hold.BREATHE)
	var sprite: Sprite2D = e.get_node("Sprite2D")
	assert_str(sprite.texture.resource_path).contains("caves_armored2")

func test_attack_holds_normal_frame() -> void:
	var e := _lunge_from_scene()
	await get_tree().process_frame
	e._change_state(Enemy.State.WINDUP)
	e._change_state(Enemy.State.ATTACK)
	var animator: EnemyAnimator = e.get_node("EnemyAnimator")
	assert_int(animator._hold).is_equal(EnemyAnimator.Hold.NORMAL)
	var sprite: Sprite2D = e.get_node("Sprite2D")
	assert_str(sprite.texture.resource_path).contains("caves_armored1")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lunge_enemy.gd`
Expected: FAIL on `test_windup_holds_breathe_frame` / `test_attack_holds_normal_frame` — texture path still contains "caves_brute", not "caves_armored".

- [ ] **Step 3: Reassign the scene's sprite textures**

Edit `scenes/enemies/lunge_enemy.tscn`, replacing the brute texture references with armored ones:

```
[gd_scene format=3 uid="uid://lungeenemy01"]

[ext_resource type="PackedScene" uid="uid://enemybase01" path="res://scenes/enemies/enemy.tscn" id="1"]
[ext_resource type="Script" path="res://src/enemies/lunge_enemy.gd" id="2"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/armered/caves_armored1.png" id="3_armored1"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/armered/caves_armored2.png" id="4_armored2"]
[ext_resource type="Script" path="res://src/enemies/feedback/enemy_animator.gd" id="5"]

[node name="LungeEnemy" instance=ExtResource("1")]
script = ExtResource("2")
carries_weapon = false
weapon_resource = null

[node name="Sprite2D" parent="." index="0"]
texture = ExtResource("3_armored1")

[node name="EnemyAnimator" type="Node" parent="."]
script = ExtResource("5")
texture_normal = ExtResource("3_armored1")
texture_breathe = ExtResource("4_armored2")
```

Note the directory is `textures/Enemies/caves/armered/` (existing typo in the asset folder name — verified via `find`, do not "fix" the typo here, just point at the real path).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lunge_enemy.gd`
Expected: PASS, full suite green.

- [ ] **Step 5: Commit**

```bash
git add scenes/enemies/lunge_enemy.tscn tests/unit/test_lunge_enemy.gd
git commit -m "fix: reassign LungeEnemy to armored sprites, freeing brute for BruteEnemy"
```

---

### Task 2: Enemy base — generalized wander parameters

Generalize `Enemy._process_idle`'s hardcoded wander timing into exported fields so subclasses can express "patrol" (default, unchanged), "stationary guard" (long pauses), "random drift" (short timers), or "none" (disabled) without overriding the method.

**Files:**
- Modify: `src/enemies/enemy.gd:319-346` (`_process_idle`), add exports near line 25
- Test: `tests/unit/test_enemy_wander_modes.gd`

**Interfaces:**
- Produces: `Enemy.wander_enabled: bool` (default `true`), `Enemy.wander_move_time_min/max: float` (default 1.0/3.0), `Enemy.wander_pause_time_min/max: float` (default 0.5/1.5), `Enemy.wander_speed_mult: float` (default 0.5). All `@export`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

class MockEnemy extends Enemy:
	func _execute_attack() -> void:
		pass


func test_wander_disabled_holds_still() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	e.wander_enabled = false
	e._wander_timer = 0.0
	e._wander_is_paused = true
	e._process_idle(0.1)
	assert_vector(e.velocity).is_equal(Vector2.ZERO)


func test_wander_default_matches_original_timing_bounds() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	assert_float(e.wander_move_time_min).is_equal(1.0)
	assert_float(e.wander_move_time_max).is_equal(3.0)
	assert_float(e.wander_pause_time_min).is_equal(0.5)
	assert_float(e.wander_pause_time_max).is_equal(1.5)
	assert_float(e.wander_speed_mult).is_equal(0.5)


func test_custom_wander_speed_mult_applied_while_moving() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	e.speed = 100.0
	e.wander_speed_mult = 1.0
	e._wander_is_paused = false
	e._wander_direction = Vector2.RIGHT
	e._wander_timer = 5.0
	e._process_idle(0.016)
	assert_float(e.velocity.x).is_equal_approx(100.0, 0.5)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_wander_modes.gd`
Expected: FAIL — `wander_enabled`/`wander_move_time_min` etc. do not exist on `Enemy`.

- [ ] **Step 3: Add exports and generalize `_process_idle`**

In `src/enemies/enemy.gd`, add near the other `@export` fields (after `crowd_spacing_scale` at line 22):

```gdscript
@export var wander_enabled: bool = true
@export var wander_move_time_min: float = 1.0
@export var wander_move_time_max: float = 3.0
@export var wander_pause_time_min: float = 0.5
@export var wander_pause_time_max: float = 1.5
@export var wander_speed_mult: float = 0.5
```

Replace `_process_idle` (lines 319-346):

```gdscript
func _process_idle(delta: float) -> void:
	if _player_ref and is_instance_valid(_player_ref) and _player_in_range:
		_change_state(State.CHASE)
		return

	if _get_director() != null and _world_manager != null and is_instance_valid(_world_manager):
		var grid = _world_manager.swarm_grid
		if grid != null:
			var neighbors: Array = grid.query_neighbors(global_position)
			if EncounterDirector.should_aggro_from_neighbors(self, neighbors):
				_aggroed = true
				_change_state(State.CHASE)
				return

	if not wander_enabled:
		velocity = Vector2.ZERO
		return

	_wander_timer -= delta
	if _wander_timer <= 0.0:
		if _wander_is_paused:
			_wander_is_paused = false
			_wander_direction = Vector2.RIGHT.rotated(randf() * TAU)
			_wander_timer = randf_range(wander_move_time_min, wander_move_time_max)
		else:
			_wander_is_paused = true
			velocity = Vector2.ZERO
			_wander_timer = randf_range(wander_pause_time_min, wander_pause_time_max)
			return

	if not _wander_is_paused:
		velocity = _wander_direction * _get_effective_speed() * wander_speed_mult
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_wander_modes.gd`
Expected: PASS

- [ ] **Step 5: Run the full enemy test suite to check for regressions**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/`
Expected: PASS (defaults reproduce prior hardcoded behavior exactly, so no existing test should change outcome).

- [ ] **Step 6: Commit**

```bash
git add src/enemies/enemy.gd tests/unit/test_enemy_wander_modes.gd
git commit -m "feat: generalize enemy wander timing into exported parameters"
```

---

### Task 3: Enemy base — elite knockback stagger resistance

Directional knockback already exists (`on_hit_impact` → `hit_dir` → `apply_knockback`). Add elite stagger resistance: elites take reduced knockback.

**Files:**
- Modify: `src/enemies/enemy.gd:813-817` (`apply_knockback`)
- Test: `tests/unit/test_enemy_elite_knockback.gd`

**Interfaces:**
- Produces: `Enemy.ELITE_KNOCKBACK_RESIST_MULT: float = 0.4` (const). `apply_knockback(direction, strength)` behavior unchanged in signature, only elites get scaled strength.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

class MockEnemy extends Enemy:
	func _execute_attack() -> void:
		pass


func test_non_elite_enemy_gets_full_knockback() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	e.is_elite = false
	e.apply_knockback(Vector2.RIGHT, 100.0)
	assert_float(e._knockback_velocity.length()).is_equal_approx(100.0, 0.5)


func test_elite_enemy_gets_reduced_knockback() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	e.is_elite = true
	e.apply_knockback(Vector2.RIGHT, 100.0)
	assert_float(e._knockback_velocity.length()).is_equal_approx(40.0, 0.5)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_elite_knockback.gd`
Expected: FAIL on `test_elite_enemy_gets_reduced_knockback` — elite currently receives full 100.0 knockback.

- [ ] **Step 3: Implement elite stagger resistance**

In `src/enemies/enemy.gd`, add near `KNOCKBACK_SPEED`/`KNOCKBACK_DECAY` (line 27):

```gdscript
const ELITE_KNOCKBACK_RESIST_MULT: float = 0.4
```

Replace `apply_knockback` (lines 813-817):

```gdscript
func apply_knockback(direction: Vector2, strength: float) -> void:
	if not is_finite(direction.x) or not is_finite(direction.y):
		return
	var effective_strength := strength
	if is_elite:
		effective_strength *= ELITE_KNOCKBACK_RESIST_MULT
	if direction.length_squared() > 0.0001:
		_knockback_velocity += direction / direction.length() * effective_strength
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_elite_knockback.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/enemies/enemy.gd tests/unit/test_enemy_elite_knockback.gd
git commit -m "feat: elite enemies resist knockback stagger"
```

---

### Task 4: Enemy base — telegraph polish (z-index + proportional timing)

Ensure the "!" windup label always draws above terrain/VFX, and scale its bounce-in/fade timing proportionally to each archetype's `windup_duration` instead of using a fixed 0.05s regardless of windup length.

**Files:**
- Modify: `src/enemies/enemy.gd:122-130` (`_ready` label setup), `674-696` (`_show_exclaim`/`_hide_exclaim`)
- Test: `tests/unit/test_enemy_telegraph.gd`

**Interfaces:**
- Produces: `Enemy._exclaim_label.z_index == 10` and `z_as_relative == false` after `_ready()`. `_show_exclaim()`/`_hide_exclaim()` scale tween duration by `clampf(windup_duration / 0.35, 0.6, 1.8)`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

class MockEnemy extends Enemy:
	func _execute_attack() -> void:
		pass


func test_exclaim_label_draws_above_terrain() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	assert_int(e._exclaim_label.z_index).is_equal(10)
	assert_bool(e._exclaim_label.z_as_relative).is_false()


func test_show_exclaim_scales_tween_with_windup_duration() -> void:
	var fast: MockEnemy = auto_free(MockEnemy.new())
	add_child(fast)
	fast.windup_duration = 0.2
	var slow: MockEnemy = auto_free(MockEnemy.new())
	add_child(slow)
	slow.windup_duration = 0.6
	assert_float(fast._telegraph_scale()).is_less(slow._telegraph_scale())
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_telegraph.gd`
Expected: FAIL — `z_index` defaults to 0, `_telegraph_scale()` does not exist.

- [ ] **Step 3: Implement z-index and proportional timing**

In `src/enemies/enemy.gd`, in `_ready()` where `_exclaim_label` is built (after line 129 `_exclaim_label.scale = Vector2.ZERO`), add:

```gdscript
	_exclaim_label.z_index = 10
	_exclaim_label.z_as_relative = false
```

Add a helper near `_show_exclaim` (line 674):

```gdscript
func _telegraph_scale() -> float:
	return clampf(windup_duration / 0.35, 0.6, 1.8)
```

Replace `_show_exclaim`/`_hide_exclaim` (lines 674-696):

```gdscript
func _show_exclaim() -> void:
	if _exclaim_label == null:
		return
	if _exclaim_tween and _exclaim_tween.is_valid():
		_exclaim_tween.kill()
	_exclaim_label.scale = Vector2.ZERO
	var t := _telegraph_scale()
	_exclaim_tween = create_tween()
	_exclaim_tween.set_trans(Tween.TRANS_BACK)
	_exclaim_tween.set_ease(Tween.EASE_OUT)
	_exclaim_tween.tween_property(_exclaim_label, "scale", Vector2(1.2, 1.2), 0.05 * t)
	_exclaim_tween.tween_property(_exclaim_label, "scale", Vector2.ONE, 0.05 * t)
	if _uses_windup_telegraph_vfx() and _windup_vfx:
		_windup_vfx.play()


func _hide_exclaim() -> void:
	if _exclaim_label == null:
		return
	if _exclaim_tween and _exclaim_tween.is_valid():
		_exclaim_tween.kill()
	_exclaim_tween = create_tween()
	_exclaim_tween.tween_property(_exclaim_label, "scale", Vector2.ZERO, 0.05 * _telegraph_scale())
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_telegraph.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/enemies/enemy.gd tests/unit/test_enemy_telegraph.gd
git commit -m "feat: telegraph label always draws on top, timing scales with windup duration"
```

---

### Task 5: EncounterDirector kill_streak field

Add a small, purpose-built `kill_streak` field for the weapon-rarity roll only — **not** a reintroduction of the removed attack-token/aggression system.

**Files:**
- Modify: `src/core/encounter_director.gd`
- Modify: `src/enemies/enemy.gd:787-792` (`die()`)
- Modify: `src/player/player_controller.gd:356-366` (`on_hit_impact`)
- Test: `tests/unit/test_encounter_director_kill_streak.gd`

**Interfaces:**
- Produces: `EncounterDirector.kill_streak: int` (starts 0, clamped to `[KILL_STREAK_MIN, KILL_STREAK_MAX]` = `[-2, 4]`), `EncounterDirector.register_kill() -> void`, `EncounterDirector.register_player_hit() -> void`.
- Consumes (in `enemy.gd`/`player_controller.gd`): `_get_director()` (enemy.gd, existing) and `get_tree().get_first_node_in_group("world_manager")` (player_controller.gd, new lookup) to reach the `EncounterDirector` instance.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite


func test_kill_streak_starts_at_zero() -> void:
	var dir := EncounterDirector.new()
	assert_int(dir.kill_streak).is_equal(0)


func test_register_kill_increments_by_two() -> void:
	var dir := EncounterDirector.new()
	dir.register_kill()
	assert_int(dir.kill_streak).is_equal(2)


func test_register_kill_clamps_at_max() -> void:
	var dir := EncounterDirector.new()
	for i in range(10):
		dir.register_kill()
	assert_int(dir.kill_streak).is_equal(4)


func test_register_player_hit_decrements_by_one() -> void:
	var dir := EncounterDirector.new()
	dir.register_kill()
	dir.register_kill()
	dir.register_player_hit()
	assert_int(dir.kill_streak).is_equal(3)


func test_register_player_hit_clamps_at_min() -> void:
	var dir := EncounterDirector.new()
	for i in range(10):
		dir.register_player_hit()
	assert_int(dir.kill_streak).is_equal(-2)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_encounter_director_kill_streak.gd`
Expected: FAIL — `kill_streak`/`register_kill`/`register_player_hit` do not exist.

- [ ] **Step 3: Add the field and methods**

In `src/core/encounter_director.gd`, add after the existing constants (after `RAMP_BAND` at line 8):

```gdscript
const KILL_STREAK_MIN := -2
const KILL_STREAK_MAX := 4
const KILL_STREAK_GAIN := 2
const KILL_STREAK_LOSS := 1

var kill_streak: int = 0


func register_kill() -> void:
	kill_streak = clampi(kill_streak + KILL_STREAK_GAIN, KILL_STREAK_MIN, KILL_STREAK_MAX)


func register_player_hit() -> void:
	kill_streak = clampi(kill_streak - KILL_STREAK_LOSS, KILL_STREAK_MIN, KILL_STREAK_MAX)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_encounter_director_kill_streak.gd`
Expected: PASS

- [ ] **Step 5: Wire `Enemy.die()` to register kills**

In `src/enemies/enemy.gd`, modify `die()` (lines 787-792):

```gdscript
func die() -> void:
	var dir = _get_director()
	if dir != null:
		dir.unregister(self)
		dir.register_kill()
	died.emit()
	_on_death()
```

- [ ] **Step 6: Wire `player_controller.gd` to register player hits**

In `src/player/player_controller.gd`, modify `on_hit_impact` (lines 356-366):

```gdscript
func on_hit_impact(impact_point: Vector2, hit_dir: Vector2, damage: int) -> void:
	if hit_dir.length_squared() > 0.0001:
		apply_knockback(hit_dir, KNOCKBACK_SPEED)

	_play_hit_flash()
	_play_squash()
	_play_zoom_punch(damage)

	var wm := get_tree().get_first_node_in_group("world_manager")
	if wm != null and is_instance_valid(wm):
		var dir = wm.get("encounter_director")
		if dir != null:
			dir.register_player_hit()

	var inventory := get_node_or_null("PlayerInventory")
	if inventory:
		inventory.take_damage(damage, hit_dir)
```

- [ ] **Step 7: Run the full test suite to check for regressions**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add src/core/encounter_director.gd src/enemies/enemy.gd src/player/player_controller.gd tests/unit/test_encounter_director_kill_streak.gd
git commit -m "feat: add narrowly-scoped kill_streak tracker for weapon-rarity rolls"
```

---

### Task 6: EnemyWeaponPools — melee rule-based pool

Add a static utility that classifies every melee weapon in `weapons.csv` into one or more of the 5 archetype pools by a numeric rule (not a hardcoded list), so newly-added weapons auto-classify.

**Files:**
- Create: `src/core/enemy_weapon_pools.gd`
- Test: `tests/unit/test_enemy_weapon_pools.gd`

**Interfaces:**
- Produces: `EnemyWeaponPools.melee_weapon_fits(row: Dictionary, archetype: String) -> bool`, `EnemyWeaponPools.build_melee_pool(archetype: String) -> Array[Dictionary]` where each entry is `{"id": String, "rarity": String}`.
- Consumes: `CsvTable.parse(path) -> Array[Dictionary]` (existing, `src/util/csv_table.gd`), `WeaponRegistry.WEAPON_CSV_PATH` (existing const, `src/autoload/weapon_registry.gd:31`).

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite


func test_skirmisher_pool_contains_fast_weapon() -> void:
	var pool := EnemyWeaponPools.build_melee_pool("skirmisher")
	var ids: Array = pool.map(func(e): return e["id"])
	assert_bool(ids.has("bone_dagger")).is_true()


func test_skirmisher_pool_excludes_slow_heavy_weapon() -> void:
	var pool := EnemyWeaponPools.build_melee_pool("skirmisher")
	var ids: Array = pool.map(func(e): return e["id"])
	assert_bool(ids.has("broad_axe")).is_false()


func test_brute_pool_contains_slow_heavy_weapon() -> void:
	var pool := EnemyWeaponPools.build_melee_pool("brute")
	var ids: Array = pool.map(func(e): return e["id"])
	assert_bool(ids.has("broad_axe")).is_true()


func test_armored_pool_contains_long_reach_weapon() -> void:
	var pool := EnemyWeaponPools.build_melee_pool("armored")
	var ids: Array = pool.map(func(e): return e["id"])
	assert_bool(ids.has("war_scythe")).is_true()


func test_cultist_pool_contains_weak_weapon() -> void:
	var pool := EnemyWeaponPools.build_melee_pool("cultist")
	var ids: Array = pool.map(func(e): return e["id"])
	assert_bool(ids.has("bone_dagger")).is_true()


func test_every_melee_weapon_lands_in_at_least_one_pool() -> void:
	var all_ids: Array = []
	for row in CsvTable.parse(WeaponRegistry.WEAPON_CSV_PATH):
		if row.get("type", "") == "Melee":
			all_ids.append(row.get("id", ""))
	var covered: Dictionary = {}
	for archetype in ["grunt", "brute", "skirmisher", "armored", "cultist"]:
		for entry in EnemyWeaponPools.build_melee_pool(archetype):
			covered[entry["id"]] = true
	for id in all_ids:
		assert_bool(covered.has(id)).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_weapon_pools.gd`
Expected: FAIL — `EnemyWeaponPools` class does not exist.

- [ ] **Step 3: Implement the utility**

Create `src/core/enemy_weapon_pools.gd`:

```gdscript
class_name EnemyWeaponPools
extends RefCounted


static func melee_weapon_fits(row: Dictionary, archetype: String) -> bool:
	var cooldown: float = float(row.get("cooldown", "0"))
	var damage: float = float(row.get("damage", "0"))
	var reach: float = float(row.get("reach", "0"))
	match archetype:
		"skirmisher":
			return cooldown <= 0.40
		"grunt":
			return cooldown >= 0.40 and cooldown <= 0.60 and reach >= 26.0 and reach <= 34.0
		"brute":
			return cooldown >= 0.60 or damage >= 6.0
		"armored":
			return reach >= 34.0
		"cultist":
			return damage <= 3.0
	return false


static func build_melee_pool(archetype: String) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for row in CsvTable.parse(WeaponRegistry.WEAPON_CSV_PATH):
		if row.get("type", "") != "Melee":
			continue
		var id: String = row.get("id", "")
		if id == "":
			continue
		if melee_weapon_fits(row, archetype):
			pool.append({"id": id, "rarity": row.get("rarity", "Common")})
	return pool
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_weapon_pools.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/core/enemy_weapon_pools.gd tests/unit/test_enemy_weapon_pools.gd
git commit -m "feat: rule-based melee weapon pool per enemy archetype"
```

---

### Task 7: EnemyWeaponPools — ranged explicit pool

Add explicit per-archetype ranged weapon lists (no clean numeric CSV axis exists for "trajectory shape").

**Files:**
- Modify: `src/core/enemy_weapon_pools.gd`
- Modify: `tests/unit/test_enemy_weapon_pools.gd`

**Interfaces:**
- Produces: `EnemyWeaponPools.build_ranged_pool(archetype: String) -> Array[Dictionary]` (same `{"id", "rarity"}` shape as melee).

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_enemy_weapon_pools.gd`:

```gdscript
func test_mage_pool_contains_seeker_launcher() -> void:
	var pool := EnemyWeaponPools.build_ranged_pool("mage")
	var ids: Array = pool.map(func(e): return e["id"])
	assert_bool(ids.has("seeker_launcher")).is_true()


func test_lobber_pool_contains_flame_lobber() -> void:
	var pool := EnemyWeaponPools.build_ranged_pool("lobber")
	var ids: Array = pool.map(func(e): return e["id"])
	assert_bool(ids.has("flame_lobber")).is_true()


func test_archer_pool_contains_throwing_knife() -> void:
	var pool := EnemyWeaponPools.build_ranged_pool("archer")
	var ids: Array = pool.map(func(e): return e["id"])
	assert_bool(ids.has("throwing_knife")).is_true()


func test_ranged_pools_exclude_boss_staff() -> void:
	for archetype in ["archer", "mage", "lobber"]:
		var pool := EnemyWeaponPools.build_ranged_pool(archetype)
		var ids: Array = pool.map(func(e): return e["id"])
		assert_bool(ids.has("boss_staff")).is_false()


func test_ranged_pool_ids_resolve_via_weapon_registry() -> void:
	for archetype in ["archer", "mage", "lobber"]:
		for entry in EnemyWeaponPools.build_ranged_pool(archetype):
			var w := WeaponRegistry.get_weapon_by_id(entry["id"])
			assert_object(w).is_not_null()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_weapon_pools.gd`
Expected: FAIL — `build_ranged_pool` does not exist.

- [ ] **Step 3: Implement the ranged pool**

Append to `src/core/enemy_weapon_pools.gd`:

```gdscript
const RANGED_POOL_IDS := {
	"archer": ["throwing_knife", "frost_repeater", "heavy_crossbow", "spread_shot", "scatter_blunderbuss", "tesla_gun", "arc_railgun", "chakram_launcher"],
	"mage": ["seeker_launcher", "fire_orb"],
	"lobber": ["flame_lobber", "venom_spitter", "hailstorm_bow"],
}


static func build_ranged_pool(archetype: String) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	var ids: Array = RANGED_POOL_IDS.get(archetype, [])
	if ids.is_empty():
		return pool
	var rarity_by_id: Dictionary = {}
	for row in CsvTable.parse(WeaponRegistry.WEAPON_CSV_PATH):
		rarity_by_id[row.get("id", "")] = row.get("rarity", "Common")
	for id in ids:
		pool.append({"id": id, "rarity": rarity_by_id.get(id, "Common")})
	return pool
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_weapon_pools.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/core/enemy_weapon_pools.gd tests/unit/test_enemy_weapon_pools.gd
git commit -m "feat: explicit ranged weapon pools per archetype"
```

---

### Task 8: EnemyWeaponPools — rarity weighting + pick_weapon_id

Add the floor/kill-streak/sector-tier rarity weighting formula and a weighted picker that rolls a tier then uniform-picks a weapon ID from a pool filtered to that tier.

**Files:**
- Modify: `src/core/enemy_weapon_pools.gd`
- Modify: `tests/unit/test_enemy_weapon_pools.gd`

**Interfaces:**
- Consumes: `DropTable.EnemyTier.{EASY, NORMAL, HARD}` (existing, `src/enemies/drop_table.gd:6`, values 0/1/2).
- Produces: `EnemyWeaponPools.base_weights_for_floor(floor_num: int) -> Dictionary` (`{"Common": float, "Uncommon": float, "Rare": float}`), `EnemyWeaponPools.rarity_weights(floor_num: int, kill_streak: int, sector_tier: int) -> Dictionary` (same shape, normalized to sum 1.0), `EnemyWeaponPools.roll_rarity_tier(weights: Dictionary) -> String`, `EnemyWeaponPools.pick_weapon_id(pool: Array[Dictionary], floor_num: int, kill_streak: int, sector_tier: int) -> String` (empty string if pool is empty).

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_enemy_weapon_pools.gd`:

```gdscript
func test_base_weights_floor_1_is_common_heavy() -> void:
	var w := EnemyWeaponPools.base_weights_for_floor(1)
	assert_float(w["Common"]).is_equal_approx(0.85, 0.001)
	assert_float(w["Uncommon"]).is_equal_approx(0.15, 0.001)
	assert_float(w["Rare"]).is_equal_approx(0.0, 0.001)


func test_base_weights_floor_5_unlocks_rare() -> void:
	var w := EnemyWeaponPools.base_weights_for_floor(5)
	assert_float(w["Common"]).is_equal_approx(0.50, 0.001)
	assert_float(w["Uncommon"]).is_equal_approx(0.35, 0.001)
	assert_float(w["Rare"]).is_equal_approx(0.15, 0.001)


func test_rarity_weights_sum_to_one() -> void:
	var w := EnemyWeaponPools.rarity_weights(5, 4, DropTable.EnemyTier.HARD)
	var total: float = w["Common"] + w["Uncommon"] + w["Rare"]
	assert_float(total).is_equal_approx(1.0, 0.001)


func test_kill_streak_shifts_weight_toward_rare() -> void:
	var base := EnemyWeaponPools.rarity_weights(1, 0, DropTable.EnemyTier.EASY)
	var boosted := EnemyWeaponPools.rarity_weights(1, 4, DropTable.EnemyTier.EASY)
	assert_float(boosted["Rare"]).is_greater(base["Rare"])


func test_hard_sector_tier_shifts_weight_toward_rare() -> void:
	var easy := EnemyWeaponPools.rarity_weights(1, 0, DropTable.EnemyTier.EASY)
	var hard := EnemyWeaponPools.rarity_weights(1, 0, DropTable.EnemyTier.HARD)
	assert_float(hard["Rare"]).is_greater(easy["Rare"])


func test_pick_weapon_id_returns_empty_for_empty_pool() -> void:
	var id := EnemyWeaponPools.pick_weapon_id([], 1, 0, DropTable.EnemyTier.EASY)
	assert_str(id).is_equal("")


func test_pick_weapon_id_returns_id_from_pool() -> void:
	var pool: Array[Dictionary] = [{"id": "only_option", "rarity": "Common"}]
	var id := EnemyWeaponPools.pick_weapon_id(pool, 1, 0, DropTable.EnemyTier.EASY)
	assert_str(id).is_equal("only_option")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_weapon_pools.gd`
Expected: FAIL — `base_weights_for_floor`/`rarity_weights`/`roll_rarity_tier`/`pick_weapon_id` do not exist.

- [ ] **Step 3: Implement rarity weighting**

Append to `src/core/enemy_weapon_pools.gd`:

```gdscript
const FLOOR_BASE_WEIGHTS := [
	{"max_floor": 2, "weights": {"Common": 0.85, "Uncommon": 0.15, "Rare": 0.0}},
	{"max_floor": 4, "weights": {"Common": 0.65, "Uncommon": 0.30, "Rare": 0.05}},
	{"max_floor": 999, "weights": {"Common": 0.50, "Uncommon": 0.35, "Rare": 0.15}},
]


static func base_weights_for_floor(floor_num: int) -> Dictionary:
	for band in FLOOR_BASE_WEIGHTS:
		if floor_num <= band["max_floor"]:
			return band["weights"].duplicate()
	return FLOOR_BASE_WEIGHTS[-1]["weights"].duplicate()


static func rarity_weights(floor_num: int, kill_streak: int, sector_tier: int) -> Dictionary:
	var w: Dictionary = base_weights_for_floor(floor_num)
	var rare_bonus := 0.0
	var uncommon_bonus := 0.0
	if kill_streak > 0:
		rare_bonus += float(kill_streak) * 0.02
		uncommon_bonus += float(kill_streak) * 0.01
	if sector_tier == DropTable.EnemyTier.HARD:
		rare_bonus += 0.10
		uncommon_bonus += 0.05
	elif sector_tier == DropTable.EnemyTier.NORMAL:
		rare_bonus += 0.05
		uncommon_bonus += 0.03
	w["Rare"] = w["Rare"] + rare_bonus
	w["Uncommon"] = w["Uncommon"] + uncommon_bonus
	w["Common"] = maxf(0.0, w["Common"] - rare_bonus - uncommon_bonus)
	var total: float = w["Common"] + w["Uncommon"] + w["Rare"]
	if total <= 0.0:
		return {"Common": 1.0, "Uncommon": 0.0, "Rare": 0.0}
	w["Common"] /= total
	w["Uncommon"] /= total
	w["Rare"] /= total
	return w


static func roll_rarity_tier(weights: Dictionary) -> String:
	var roll := randf()
	var cumulative := 0.0
	for tier in ["Common", "Uncommon", "Rare"]:
		cumulative += float(weights.get(tier, 0.0))
		if roll <= cumulative:
			return tier
	return "Common"


static func pick_weapon_id(pool: Array[Dictionary], floor_num: int, kill_streak: int, sector_tier: int) -> String:
	if pool.is_empty():
		return ""
	var weights := rarity_weights(floor_num, kill_streak, sector_tier)
	var tier := roll_rarity_tier(weights)
	var candidates: Array[Dictionary] = pool.filter(func(e): return e["rarity"] == tier)
	if candidates.is_empty():
		candidates = pool.filter(func(e): return e["rarity"] == "Common")
	if candidates.is_empty():
		candidates = pool
	return candidates[randi() % candidates.size()]["id"]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_weapon_pools.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/core/enemy_weapon_pools.gd tests/unit/test_enemy_weapon_pools.gd
git commit -m "feat: rarity weighting by floor, kill streak, and boss-distance tier"
```

---

### Task 9: BruteEnemy — rusher archetype

**Files:**
- Create: `src/enemies/brute_enemy.gd`
- Create: `scenes/enemies/brute_enemy.tscn`
- Test: `tests/unit/test_brute_enemy.gd`

**Interfaces:**
- Consumes: `MeleeEnemy` (`src/enemies/melee_enemy.gd`), `Enemy.wander_enabled`/`wander_move_time_min/max`/`wander_pause_time_min/max` (Task 2).
- Produces: `class_name BruteEnemy extends MeleeEnemy`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite


func _brute() -> BruteEnemy:
	var e: BruteEnemy = auto_free(BruteEnemy.new())
	add_child(e)
	return e


func test_brute_has_boosted_health() -> void:
	var e := _brute()
	assert_int(e.max_health).is_equal(27)
	assert_int(e.health).is_equal(27)


func test_brute_has_reduced_speed() -> void:
	var e := _brute()
	assert_float(e.speed).is_equal_approx(42.0, 0.5)


func test_brute_has_boosted_weapon_damage() -> void:
	var e := _brute()
	assert_float(e.weapon.damage).is_equal_approx(MeleeWeapon.new().damage * 1.3, 0.01)


func test_brute_has_wider_commit_range() -> void:
	var e := _brute()
	assert_float(e._attack_range).is_equal_approx(28.0 * 1.3, 0.1)


func test_brute_has_longer_windup() -> void:
	var e := _brute()
	assert_float(e.windup_duration).is_equal_approx(0.35 * 1.3, 0.01)


func test_brute_wanders_rarely() -> void:
	var e := _brute()
	assert_float(e.wander_pause_time_min).is_greater(2.0)


func test_scene_instantiates_as_brute_enemy() -> void:
	var scene: PackedScene = load("res://scenes/enemies/brute_enemy.tscn")
	assert_object(scene).is_not_null()
	var e = auto_free(scene.instantiate())
	add_child(e)
	assert_bool(e is BruteEnemy).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_brute_enemy.gd`
Expected: FAIL — `BruteEnemy` class does not exist.

- [ ] **Step 3: Implement `BruteEnemy`**

Create `src/enemies/brute_enemy.gd`:

```gdscript
class_name BruteEnemy
extends MeleeEnemy

const HP_MULT: float = 1.8
const SPEED_MULT: float = 0.7
const DAMAGE_MULT: float = 1.3
const COMMIT_RANGE_MULT: float = 1.3
const WINDUP_MULT: float = 1.3


func _ready() -> void:
	super._ready()
	max_health = int(float(max_health) * HP_MULT)
	health = max_health
	speed = _speed_base * SPEED_MULT
	_speed_base = speed
	if weapon:
		weapon.damage *= DAMAGE_MULT
	_attack_range *= COMMIT_RANGE_MULT
	windup_duration *= WINDUP_MULT
	# Rusher: mostly holds ground, only brief shuffles between long pauses.
	wander_move_time_min = 0.3
	wander_move_time_max = 0.8
	wander_pause_time_min = 3.0
	wander_pause_time_max = 6.0
```

Create `scenes/enemies/brute_enemy.tscn`:

```
[gd_scene format=3 uid="uid://bruteenemy01"]

[ext_resource type="PackedScene" uid="uid://enemybase01" path="res://scenes/enemies/enemy.tscn" id="1"]
[ext_resource type="Script" path="res://src/enemies/brute_enemy.gd" id="2"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/brute/caves_brute1.png" id="3_brute1"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/brute/caves_brute2.png" id="4_brute2"]
[ext_resource type="Script" path="res://src/enemies/feedback/enemy_animator.gd" id="5"]

[node name="BruteEnemy" instance=ExtResource("1")]
script = ExtResource("2")
weapon_resource = null

[node name="Sprite2D" parent="." index="0"]
texture = ExtResource("3_brute1")

[node name="EnemyAnimator" type="Node" parent="."]
script = ExtResource("5")
texture_normal = ExtResource("3_brute1")
texture_breathe = ExtResource("4_brute2")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_brute_enemy.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/enemies/brute_enemy.gd scenes/enemies/brute_enemy.tscn tests/unit/test_brute_enemy.gd
git commit -m "feat: add BruteEnemy (rusher melee archetype)"
```

---

### Task 10: SkirmisherEnemy — flanker archetype

**Files:**
- Create: `src/enemies/skirmisher_enemy.gd`
- Create: `scenes/enemies/skirmisher_enemy.tscn`
- Test: `tests/unit/test_skirmisher_enemy.gd`

**Interfaces:**
- Consumes: `MeleeEnemy`, `Enemy._safe_normalized`, `Enemy._apply_separation`, `Enemy._nav_field_dir`, `Enemy._can_see_player`.
- Produces: `class_name SkirmisherEnemy extends MeleeEnemy`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite


func _skirmisher_at(origin: Vector2, player_pos: Vector2) -> SkirmisherEnemy:
	var e: SkirmisherEnemy = auto_free(SkirmisherEnemy.new())
	add_child(e)
	e.global_position = origin
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = player_pos
	e._player_ref = p
	e._aggroed = true
	return e


func test_skirmisher_has_reduced_health() -> void:
	var e := _skirmisher_at(Vector2.ZERO, Vector2(200, 0))
	assert_int(e.max_health).is_equal(9)


func test_skirmisher_has_boosted_speed() -> void:
	var e := _skirmisher_at(Vector2.ZERO, Vector2(200, 0))
	assert_float(e.speed).is_equal_approx(84.0, 0.5)


func test_skirmisher_has_reduced_weapon_damage() -> void:
	var e := _skirmisher_at(Vector2.ZERO, Vector2(200, 0))
	assert_float(e.weapon.damage).is_equal_approx(MeleeWeapon.new().damage * 0.7, 0.01)


func test_skirmisher_flanks_when_far_from_commit_range() -> void:
	var e := _skirmisher_at(Vector2.ZERO, Vector2(300, 0))
	e._flank_sign = 1.0
	e._flank_angle = deg_to_rad(60.0)
	e._process_chase(0.016)
	var to_player_dir := Vector2(300, 0).normalized()
	var dot := e.velocity.normalized().dot(to_player_dir)
	assert_float(dot).is_less(0.9)


func test_skirmisher_moves_straight_within_commit_range() -> void:
	var e := _skirmisher_at(Vector2.ZERO, Vector2(30, 0))
	e._process_chase(0.016)
	assert_float(e.velocity.normalized().dot(Vector2.RIGHT)).is_greater(0.99)


func test_scene_instantiates_as_skirmisher_enemy() -> void:
	var scene: PackedScene = load("res://scenes/enemies/skirmisher_enemy.tscn")
	assert_object(scene).is_not_null()
	var e = auto_free(scene.instantiate())
	add_child(e)
	assert_bool(e is SkirmisherEnemy).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_skirmisher_enemy.gd`
Expected: FAIL — `SkirmisherEnemy` class does not exist.

- [ ] **Step 3: Implement `SkirmisherEnemy`**

Create `src/enemies/skirmisher_enemy.gd`:

```gdscript
class_name SkirmisherEnemy
extends MeleeEnemy

const HP_MULT: float = 0.6
const SPEED_MULT: float = 1.4
const DAMAGE_MULT: float = 0.7
const FLANK_COMMIT_RANGE_MULT: float = 1.8
const FLANK_ANGLE_MIN: float = 0.785398  # 45 deg
const FLANK_ANGLE_MAX: float = 1.047198  # 60 deg

var _flank_sign: float = 1.0
var _flank_angle: float = 0.0


func _ready() -> void:
	super._ready()
	max_health = int(float(max_health) * HP_MULT)
	health = max_health
	speed = _speed_base * SPEED_MULT
	_speed_base = speed
	if weapon:
		weapon.damage *= DAMAGE_MULT
	_flank_sign = 1.0 if randf() > 0.5 else -1.0
	_flank_angle = randf_range(FLANK_ANGLE_MIN, FLANK_ANGLE_MAX)
	# Random drift: short, frequent wander bursts.
	wander_move_time_min = 0.4
	wander_move_time_max = 1.0
	wander_pause_time_min = 0.2
	wander_pause_time_max = 0.6


func _process_chase(_delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		_aggroed = false
		_change_state(State.WANDER)
		return

	var to_player := _player_ref.global_position - global_position
	var dist := to_player.length()
	var sees := _can_see_player()

	if sees:
		_aggroed = true
	elif not _aggroed:
		_change_state(State.WANDER)
		return

	if dist < 1.0:
		velocity = Vector2.ZERO
		return

	if sees and dist <= _attack_range:
		velocity = Vector2.ZERO
		_change_state(State.WINDUP)
		return

	var move_dir: Vector2
	if sees:
		if dist <= _attack_range * FLANK_COMMIT_RANGE_MULT:
			move_dir = _safe_normalized(to_player)
		else:
			move_dir = _safe_normalized(to_player).rotated(_flank_angle * _flank_sign)
	else:
		var fd := _nav_field_dir()
		move_dir = fd if fd != Vector2.ZERO else _safe_normalized(to_player)

	move_dir = _apply_separation(move_dir)
	velocity = move_dir * _get_effective_speed()
```

Create `scenes/enemies/skirmisher_enemy.tscn`:

```
[gd_scene format=3 uid="uid://skirmisherenemy01"]

[ext_resource type="PackedScene" uid="uid://enemybase01" path="res://scenes/enemies/enemy.tscn" id="1"]
[ext_resource type="Script" path="res://src/enemies/skirmisher_enemy.gd" id="2"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/skirmisher/caves_skirmisher1.png" id="3_skirmisher1"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/skirmisher/caves_skirmisher2.png" id="4_skirmisher2"]
[ext_resource type="Script" path="res://src/enemies/feedback/enemy_animator.gd" id="5"]

[node name="SkirmisherEnemy" instance=ExtResource("1")]
script = ExtResource("2")
weapon_resource = null

[node name="Sprite2D" parent="." index="0"]
texture = ExtResource("3_skirmisher1")

[node name="EnemyAnimator" type="Node" parent="."]
script = ExtResource("5")
texture_normal = ExtResource("3_skirmisher1")
texture_breathe = ExtResource("4_skirmisher2")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_skirmisher_enemy.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/enemies/skirmisher_enemy.gd scenes/enemies/skirmisher_enemy.tscn tests/unit/test_skirmisher_enemy.gd
git commit -m "feat: add SkirmisherEnemy (flanker melee archetype)"
```

---

### Task 11: ArmoredEnemy — ambusher archetype

**Files:**
- Create: `src/enemies/armored_enemy.gd`
- Create: `scenes/enemies/armored_enemy.tscn`
- Test: `tests/unit/test_armored_enemy.gd`

**Interfaces:**
- Consumes: `MeleeEnemy`, `Enemy.apply_knockback` (Task 3), `Enemy.wander_enabled`.
- Produces: `class_name ArmoredEnemy extends MeleeEnemy`, `ArmoredEnemy.KNOCKBACK_RESIST_MULT: float = 0.25`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite


func _armored() -> ArmoredEnemy:
	var e: ArmoredEnemy = auto_free(ArmoredEnemy.new())
	add_child(e)
	return e


func test_armored_has_boosted_health() -> void:
	var e := _armored()
	assert_int(e.max_health).is_equal(21)


func test_armored_has_reduced_speed() -> void:
	var e := _armored()
	assert_float(e.speed).is_equal_approx(51.0, 0.5)


func test_armored_does_not_wander() -> void:
	var e := _armored()
	assert_bool(e.wander_enabled).is_false()


func test_armored_has_longer_windup() -> void:
	var e := _armored()
	assert_float(e.windup_duration).is_equal_approx(0.35 * 1.3, 0.01)


func test_armored_resists_knockback() -> void:
	var e := _armored()
	e.is_elite = false
	e.apply_knockback(Vector2.RIGHT, 100.0)
	assert_float(e._knockback_velocity.length()).is_equal_approx(25.0, 0.5)


func test_armored_elite_stacks_knockback_resistance() -> void:
	var e: ArmoredEnemy = auto_free(ArmoredEnemy.new())
	e.is_elite = true
	add_child(e)
	e.apply_knockback(Vector2.RIGHT, 100.0)
	assert_float(e._knockback_velocity.length()).is_equal_approx(10.0, 0.5)


func test_scene_instantiates_as_armored_enemy() -> void:
	var scene: PackedScene = load("res://scenes/enemies/armored_enemy.tscn")
	assert_object(scene).is_not_null()
	var e = auto_free(scene.instantiate())
	add_child(e)
	assert_bool(e is ArmoredEnemy).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_armored_enemy.gd`
Expected: FAIL — `ArmoredEnemy` class does not exist.

- [ ] **Step 3: Implement `ArmoredEnemy`**

Create `src/enemies/armored_enemy.gd`:

```gdscript
class_name ArmoredEnemy
extends MeleeEnemy

const HP_MULT: float = 1.4
const SPEED_MULT: float = 0.85
const WINDUP_MULT: float = 1.3
const KNOCKBACK_RESIST_MULT: float = 0.25


func _ready() -> void:
	super._ready()
	max_health = int(float(max_health) * HP_MULT)
	health = max_health
	speed = _speed_base * SPEED_MULT
	_speed_base = speed
	windup_duration *= WINDUP_MULT
	# Ambusher: holds a guard spot, no independent wander.
	wander_enabled = false


func apply_knockback(direction: Vector2, strength: float) -> void:
	super.apply_knockback(direction, strength * KNOCKBACK_RESIST_MULT)
```

Create `scenes/enemies/armored_enemy.tscn`:

```
[gd_scene format=3 uid="uid://armoredenemy01"]

[ext_resource type="PackedScene" uid="uid://enemybase01" path="res://scenes/enemies/enemy.tscn" id="1"]
[ext_resource type="Script" path="res://src/enemies/armored_enemy.gd" id="2"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/armered/caves_armored1.png" id="3_armored1"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/armered/caves_armored2.png" id="4_armored2"]
[ext_resource type="Script" path="res://src/enemies/feedback/enemy_animator.gd" id="5"]

[node name="ArmoredEnemy" instance=ExtResource("1")]
script = ExtResource("2")
weapon_resource = null

[node name="Sprite2D" parent="." index="0"]
texture = ExtResource("3_armored1")

[node name="EnemyAnimator" type="Node" parent="."]
script = ExtResource("5")
texture_normal = ExtResource("3_armored1")
texture_breathe = ExtResource("4_armored2")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_armored_enemy.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/enemies/armored_enemy.gd scenes/enemies/armored_enemy.tscn tests/unit/test_armored_enemy.gd
git commit -m "feat: add ArmoredEnemy (ambusher melee archetype)"
```

---

### Task 12: CultistEnemy — support/follower archetype

**Files:**
- Create: `src/enemies/cultist_enemy.gd`
- Create: `scenes/enemies/cultist_enemy.tscn`
- Test: `tests/unit/test_cultist_enemy.gd`

**Interfaces:**
- Consumes: `MeleeEnemy`, `_world_manager.swarm_grid.query_neighbors(pos) -> Array` (existing, used by `Enemy._apply_separation`).
- Produces: `class_name CultistEnemy extends MeleeEnemy`, `heal_radius: float = 100.0`, `heal_cooldown: float = 6.0`, `heal_fraction: float = 0.2`, `_find_wounded_ally() -> Node`, `_heal_ally(ally: Node) -> void`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

class FakeWorld extends Node:
	var swarm_grid = preload("res://src/core/swarm_grid.gd").new(32.0)
	var nav_field = null

class WoundedAlly extends Node2D:
	var health: int = 5
	var max_health: int = 20
	signal health_changed(current: int, maximum: int)


func _cultist_with_world() -> Dictionary:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	var e: CultistEnemy = auto_free(CultistEnemy.new())
	add_child(e)
	e._world_manager = world
	e.global_position = Vector2.ZERO
	return {"world": world, "cultist": e}


func test_cultist_has_reduced_health() -> void:
	var e: CultistEnemy = auto_free(CultistEnemy.new())
	add_child(e)
	assert_int(e.max_health).is_equal(12)


func test_cultist_does_not_wander_independently() -> void:
	var e: CultistEnemy = auto_free(CultistEnemy.new())
	add_child(e)
	assert_bool(e.wander_enabled).is_false()


func test_cultist_heals_wounded_ally_in_radius() -> void:
	var ctx := _cultist_with_world()
	var world: FakeWorld = ctx["world"]
	var e: CultistEnemy = ctx["cultist"]
	var ally: WoundedAlly = auto_free(WoundedAlly.new())
	add_child(ally)
	ally.global_position = Vector2(50, 0)
	world.swarm_grid.rebuild([e, ally])
	e._heal_timer = 0.0
	e._process_idle(0.016)
	assert_int(ally.health).is_equal(9)  # 5 + int(20 * 0.2)


func test_cultist_ignores_full_health_ally() -> void:
	var ctx := _cultist_with_world()
	var world: FakeWorld = ctx["world"]
	var e: CultistEnemy = ctx["cultist"]
	var ally: WoundedAlly = auto_free(WoundedAlly.new())
	add_child(ally)
	ally.global_position = Vector2(50, 0)
	ally.health = 20
	world.swarm_grid.rebuild([e, ally])
	e._heal_timer = 0.0
	e._process_idle(0.016)
	assert_int(ally.health).is_equal(20)


func test_cultist_respects_cooldown() -> void:
	var ctx := _cultist_with_world()
	var world: FakeWorld = ctx["world"]
	var e: CultistEnemy = ctx["cultist"]
	var ally: WoundedAlly = auto_free(WoundedAlly.new())
	add_child(ally)
	ally.global_position = Vector2(50, 0)
	world.swarm_grid.rebuild([e, ally])
	e._heal_timer = 0.0
	e._process_idle(0.016)
	var healed_once: int = ally.health
	e._process_idle(0.016)
	assert_int(ally.health).is_equal(healed_once)


func test_scene_instantiates_as_cultist_enemy() -> void:
	var scene: PackedScene = load("res://scenes/enemies/cultist_enemy.tscn")
	assert_object(scene).is_not_null()
	var e = auto_free(scene.instantiate())
	add_child(e)
	assert_bool(e is CultistEnemy).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_cultist_enemy.gd`
Expected: FAIL — `CultistEnemy` class does not exist.

- [ ] **Step 3: Implement `CultistEnemy`**

Create `src/enemies/cultist_enemy.gd`:

```gdscript
class_name CultistEnemy
extends MeleeEnemy

const HP_MULT: float = 0.8
const DAMAGE_MULT: float = 0.6

@export var heal_radius: float = 100.0
@export var heal_cooldown: float = 6.0
@export var heal_fraction: float = 0.2

var _heal_timer: float = 0.0
var _callout_label: Label = null


func _ready() -> void:
	super._ready()
	max_health = int(float(max_health) * HP_MULT)
	health = max_health
	if weapon:
		weapon.damage *= DAMAGE_MULT
	# Support/follower: does not wander independently, stays near the swarm.
	wander_enabled = false

	_callout_label = Label.new()
	_callout_label.name = "CalloutLabel"
	_callout_label.text = "Caw cawww"
	_callout_label.position = Vector2(-24, -30)
	_callout_label.add_theme_font_size_override("font_size", 12)
	_callout_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_callout_label.scale = Vector2.ZERO
	_callout_label.z_index = 10
	_callout_label.z_as_relative = false
	add_child(_callout_label)


func _process_idle(delta: float) -> void:
	if _player_ref and is_instance_valid(_player_ref) and _player_in_range:
		_change_state(State.CHASE)
		return

	_heal_timer -= delta
	if _heal_timer <= 0.0:
		var ally := _find_wounded_ally()
		if ally != null:
			_heal_ally(ally)
			_heal_timer = heal_cooldown
			return

	velocity = Vector2.ZERO


func _find_wounded_ally() -> Node:
	if _world_manager == null or not is_instance_valid(_world_manager):
		return null
	var grid = _world_manager.swarm_grid
	if grid == null:
		return null
	var best: Node = null
	var best_dist := heal_radius
	for candidate in grid.query_neighbors(global_position):
		if candidate == self or not is_instance_valid(candidate):
			continue
		if not ("health" in candidate) or not ("max_health" in candidate):
			continue
		if candidate.health >= candidate.max_health:
			continue
		var dist: float = global_position.distance_to(candidate.global_position)
		if dist <= best_dist:
			best = candidate
			best_dist = dist
	return best


func _heal_ally(ally: Node) -> void:
	var heal_amount: int = int(float(ally.max_health) * heal_fraction)
	ally.health = mini(ally.max_health, ally.health + heal_amount)
	if ally.has_signal("health_changed"):
		ally.health_changed.emit(ally.health, ally.max_health)
	_show_callout()


func _show_callout() -> void:
	if _callout_label == null:
		return
	var tween := create_tween()
	tween.tween_property(_callout_label, "scale", Vector2.ONE, 0.1)
	tween.tween_interval(1.0)
	tween.tween_property(_callout_label, "scale", Vector2.ZERO, 0.2)
```

Create `scenes/enemies/cultist_enemy.tscn`:

```
[gd_scene format=3 uid="uid://cultistenemy01"]

[ext_resource type="PackedScene" uid="uid://enemybase01" path="res://scenes/enemies/enemy.tscn" id="1"]
[ext_resource type="Script" path="res://src/enemies/cultist_enemy.gd" id="2"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/cultist/caves_cultist1.png" id="3_cultist1"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/cultist/caves_cultist2.png" id="4_cultist2"]
[ext_resource type="Script" path="res://src/enemies/feedback/enemy_animator.gd" id="5"]

[node name="CultistEnemy" instance=ExtResource("1")]
script = ExtResource("2")
weapon_resource = null

[node name="Sprite2D" parent="." index="0"]
texture = ExtResource("3_cultist1")

[node name="EnemyAnimator" type="Node" parent="."]
script = ExtResource("5")
texture_normal = ExtResource("3_cultist1")
texture_breathe = ExtResource("4_cultist2")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_cultist_enemy.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/enemies/cultist_enemy.gd scenes/enemies/cultist_enemy.tscn tests/unit/test_cultist_enemy.gd
git commit -m "feat: add CultistEnemy (support/heal-ally melee archetype)"
```

---

### Task 13: ArcherEnemy — kiter archetype

**Files:**
- Create: `src/enemies/archer_enemy.gd`
- Create: `scenes/enemies/archer_enemy.tscn`
- Test: `tests/unit/test_archer_enemy.gd`

**Interfaces:**
- Consumes: `RangedEnemy` (`src/enemies/ranged_enemy.gd`), `RangedEnemy.preferred_distance`, `RangedEnemy._strafe_direction`/`_strafe_re_roll`, `RangedEnemy.strafe_speed`.
- Produces: `class_name ArcherEnemy extends RangedEnemy`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite


func _archer_at(origin: Vector2, player_pos: Vector2) -> ArcherEnemy:
	var e: ArcherEnemy = auto_free(ArcherEnemy.new())
	add_child(e)
	e.global_position = origin
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = player_pos
	e._player_ref = p
	e._player_in_range = true
	return e


func test_archer_uses_default_ranged_stats() -> void:
	var e := _archer_at(Vector2.ZERO, Vector2(200, 0))
	assert_int(e.max_health).is_equal(12)


func test_archer_retreats_earlier_than_preferred_distance() -> void:
	# 100px is within the base preferred_distance (120) - the un-kited archer
	# would strafe here, but the kiter should already be retreating (1.3x * 120 = 156).
	var e := _archer_at(Vector2.ZERO, Vector2(100, 0))
	e._process_chase(0.016)
	assert_float(e.velocity.dot(Vector2.RIGHT)).is_less(0.0)


func test_archer_retreat_speed_is_boosted() -> void:
	var e := _archer_at(Vector2.ZERO, Vector2(100, 0))
	e._process_chase(0.016)
	assert_float(e.velocity.length()).is_greater_equal(e.speed * 1.19)


func test_scene_instantiates_as_archer_enemy() -> void:
	var scene: PackedScene = load("res://scenes/enemies/archer_enemy.tscn")
	assert_object(scene).is_not_null()
	var e = auto_free(scene.instantiate())
	add_child(e)
	assert_bool(e is ArcherEnemy).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_archer_enemy.gd`
Expected: FAIL — `ArcherEnemy` class does not exist.

- [ ] **Step 3: Implement `ArcherEnemy`**

Create `src/enemies/archer_enemy.gd`:

```gdscript
class_name ArcherEnemy
extends RangedEnemy

const KITE_DISTANCE_MULT: float = 1.3
const KITE_SPEED_MULT: float = 1.2

const ARCHER_NORMAL: Texture2D = preload("res://textures/Enemies/caves/archer/caves_archer1.png")
const ARCHER_BREATHE: Texture2D = preload("res://textures/Enemies/caves/archer/caves_archer2.png")


func _ready() -> void:
	if weapon_resource == null:
		weapon_resource = WeaponRegistry.get_weapon_by_id("throwing_knife")
	super._ready()


func _select_sprite_textures() -> Array:
	return [ARCHER_NORMAL, ARCHER_BREATHE]


func _process_chase(delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		_change_state(State.WANDER)
		return
	if not _player_in_range:
		_change_state(State.WANDER)
		return
	if not _can_see_player():
		_change_state(State.WANDER)
		return

	var to_player := _player_ref.global_position - global_position
	var dist := to_player.length()
	if dist < 1.0:
		velocity = Vector2.ZERO
		return

	var kite_distance := preferred_distance * KITE_DISTANCE_MULT
	var move_dir: Vector2
	if dist < kite_distance - 20.0:
		move_dir = -to_player.normalized()
		velocity = move_dir * _get_effective_speed() * KITE_SPEED_MULT
	elif dist > preferred_distance + 20.0:
		move_dir = to_player.normalized()
		velocity = move_dir * _get_effective_speed()
	else:
		_strafe_re_roll -= delta
		if _strafe_re_roll <= 0.0:
			_strafe_direction = 1.0 if randf() > 0.5 else -1.0
			_strafe_re_roll = 1.5
		var perpendicular := Vector2(-to_player.y, to_player.x).normalized()
		velocity = perpendicular * _strafe_direction * strafe_speed

	velocity = _apply_separation(velocity)

	if dist <= _attack_range:
		_change_state(State.WINDUP)
		return
```

Create `scenes/enemies/archer_enemy.tscn`:

```
[gd_scene format=3 uid="uid://archerenemy01"]

[ext_resource type="PackedScene" uid="uid://enemybase01" path="res://scenes/enemies/enemy.tscn" id="1"]
[ext_resource type="Script" path="res://src/enemies/archer_enemy.gd" id="2"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/archer/caves_archer1.png" id="3_archer1"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/archer/caves_archer2.png" id="4_archer2"]
[ext_resource type="Script" path="res://src/enemies/feedback/enemy_animator.gd" id="5"]

[node name="ArcherEnemy" instance=ExtResource("1")]
script = ExtResource("2")
weapon_resource = null
preferred_distance = 120.0
strafe_speed = 40.0
back_away_acceleration = 200.0

[node name="Sprite2D" parent="." index="0"]
texture = ExtResource("3_archer1")

[node name="EnemyAnimator" type="Node" parent="."]
script = ExtResource("5")
texture_normal = ExtResource("3_archer1")
texture_breathe = ExtResource("4_archer2")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_archer_enemy.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/enemies/archer_enemy.gd scenes/enemies/archer_enemy.tscn tests/unit/test_archer_enemy.gd
git commit -m "feat: add ArcherEnemy (kiter ranged archetype)"
```

---

### Task 14: MageEnemy — turret archetype

**Files:**
- Create: `src/enemies/mage_enemy.gd`
- Create: `scenes/enemies/mage_enemy.tscn`
- Test: `tests/unit/test_mage_enemy.gd`

**Interfaces:**
- Consumes: `RangedEnemy`, `WeaponRegistry.get_weapon_by_id("seeker_launcher")` (existing, homing weapon).
- Produces: `class_name MageEnemy extends RangedEnemy`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite


func _mage_at(origin: Vector2, player_pos: Vector2) -> MageEnemy:
	var e: MageEnemy = auto_free(MageEnemy.new())
	add_child(e)
	e.global_position = origin
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = player_pos
	e._player_ref = p
	e._player_in_range = true
	return e


func test_mage_has_reduced_health() -> void:
	var e := _mage_at(Vector2.ZERO, Vector2(300, 0))
	assert_int(e.max_health).is_equal(10)  # int(12 * 0.9) = 10


func test_mage_has_reduced_speed() -> void:
	var e := _mage_at(Vector2.ZERO, Vector2(300, 0))
	assert_float(e.speed).is_equal_approx(50.0 * 0.6, 0.5)


func test_mage_defaults_to_seeker_launcher_weapon() -> void:
	var e := _mage_at(Vector2.ZERO, Vector2(300, 0))
	assert_bool(e.weapon != null).is_true()


func test_mage_walks_straight_toward_player_when_out_of_range() -> void:
	var e := _mage_at(Vector2.ZERO, Vector2(300, 0))
	e._process_chase(0.016)
	assert_float(e.velocity.normalized().dot(Vector2.RIGHT)).is_greater(0.99)


func test_mage_stops_moving_once_in_attack_range() -> void:
	var e := _mage_at(Vector2.ZERO, Vector2(50, 0))
	e._state = Enemy.State.CHASE
	e._process_chase(0.016)
	assert_int(e._state).is_equal(Enemy.State.WINDUP)
	assert_vector(e.velocity).is_equal(Vector2.ZERO)


func test_scene_instantiates_as_mage_enemy() -> void:
	var scene: PackedScene = load("res://scenes/enemies/mage_enemy.tscn")
	assert_object(scene).is_not_null()
	var e = auto_free(scene.instantiate())
	add_child(e)
	assert_bool(e is MageEnemy).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_mage_enemy.gd`
Expected: FAIL — `MageEnemy` class does not exist.

- [ ] **Step 3: Implement `MageEnemy`**

Create `src/enemies/mage_enemy.gd`:

```gdscript
class_name MageEnemy
extends RangedEnemy

const HP_MULT: float = 0.9
const SPEED_MULT: float = 0.6
const MAGE_ATTACK_RANGE: float = 220.0
const MAGE_WINDUP: float = 0.8

const MAGE_NORMAL: Texture2D = preload("res://textures/Enemies/caves/mage/caves_mage1.png")
const MAGE_BREATHE: Texture2D = preload("res://textures/Enemies/caves/mage/caves_mage2.png")


func _ready() -> void:
	if weapon_resource == null:
		weapon_resource = WeaponRegistry.get_weapon_by_id("seeker_launcher")
	super._ready()
	max_health = int(float(max_health) * HP_MULT)
	health = max_health
	speed = _speed_base * SPEED_MULT
	_speed_base = speed
	_attack_range = MAGE_ATTACK_RANGE
	windup_duration = MAGE_WINDUP


func _select_sprite_textures() -> Array:
	return [MAGE_NORMAL, MAGE_BREATHE]


func _process_chase(_delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		_change_state(State.WANDER)
		return
	if not _player_in_range or not _can_see_player():
		_change_state(State.WANDER)
		return

	var to_player := _player_ref.global_position - global_position
	var dist := to_player.length()
	if dist <= _attack_range:
		velocity = Vector2.ZERO
		_change_state(State.WINDUP)
		return

	var move_dir := _safe_normalized(to_player)
	move_dir = _apply_separation(move_dir)
	velocity = move_dir * _get_effective_speed()
```

Create `scenes/enemies/mage_enemy.tscn`:

```
[gd_scene format=3 uid="uid://mageenemy01"]

[ext_resource type="PackedScene" uid="uid://enemybase01" path="res://scenes/enemies/enemy.tscn" id="1"]
[ext_resource type="Script" path="res://src/enemies/mage_enemy.gd" id="2"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/mage/caves_mage1.png" id="3_mage1"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/mage/caves_mage2.png" id="4_mage2"]
[ext_resource type="Script" path="res://src/enemies/feedback/enemy_animator.gd" id="5"]

[node name="MageEnemy" instance=ExtResource("1")]
script = ExtResource("2")
weapon_resource = null
preferred_distance = 120.0
strafe_speed = 40.0
back_away_acceleration = 200.0

[node name="Sprite2D" parent="." index="0"]
texture = ExtResource("3_mage1")

[node name="EnemyAnimator" type="Node" parent="."]
script = ExtResource("5")
texture_normal = ExtResource("3_mage1")
texture_breathe = ExtResource("4_mage2")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_mage_enemy.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/enemies/mage_enemy.gd scenes/enemies/mage_enemy.tscn tests/unit/test_mage_enemy.gd
git commit -m "feat: add MageEnemy (turret ranged archetype)"
```

---

### Task 15: LobberEnemy — skirmisher-reposition archetype

**Files:**
- Create: `src/enemies/lobber_enemy.gd`
- Create: `scenes/enemies/lobber_enemy.tscn`
- Test: `tests/unit/test_lobber_enemy.gd`

**Interfaces:**
- Consumes: `RangedEnemy`, `RangedEnemy.LOBBER_NORMAL`/`LOBBER_BREATHE` (existing consts), `WeaponRegistry.get_weapon_by_id("flame_lobber")` (existing, arc-AoE weapon).
- Produces: `class_name LobberEnemy extends RangedEnemy`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite


func _lobber_at(origin: Vector2, player_pos: Vector2) -> LobberEnemy:
	var e: LobberEnemy = auto_free(LobberEnemy.new())
	add_child(e)
	e.global_position = origin
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = player_pos
	e._player_ref = p
	e._player_in_range = true
	return e


func test_lobber_defaults_to_flame_lobber_weapon() -> void:
	var e := _lobber_at(Vector2.ZERO, Vector2(200, 0))
	assert_bool(e.weapon != null).is_true()


func test_lobber_sets_reposition_target_after_attack() -> void:
	var e := _lobber_at(Vector2.ZERO, Vector2(100, 0))
	e._state = Enemy.State.ATTACK
	e._change_state(Enemy.State.COOLDOWN)
	assert_bool(e._has_reposition_target).is_true()
	# Target should be biased away from the player (negative X since player is at +X).
	assert_float(e._reposition_target.x).is_less(0.0)


func test_lobber_moves_toward_reposition_target_during_chase() -> void:
	var e := _lobber_at(Vector2.ZERO, Vector2(200, 0))
	e._has_reposition_target = true
	e._reposition_target = Vector2(-80, 0)
	e._process_chase(0.016)
	assert_float(e.velocity.normalized().dot(Vector2.LEFT)).is_greater(0.99)


func test_lobber_clears_reposition_target_on_arrival() -> void:
	var e := _lobber_at(Vector2.ZERO, Vector2(200, 0))
	e._has_reposition_target = true
	e._reposition_target = Vector2(2, 0)
	e._process_chase(0.016)
	assert_bool(e._has_reposition_target).is_false()


func test_scene_instantiates_as_lobber_enemy() -> void:
	var scene: PackedScene = load("res://scenes/enemies/lobber_enemy.tscn")
	assert_object(scene).is_not_null()
	var e = auto_free(scene.instantiate())
	add_child(e)
	assert_bool(e is LobberEnemy).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lobber_enemy.gd`
Expected: FAIL — `LobberEnemy` class does not exist.

- [ ] **Step 3: Implement `LobberEnemy`**

Create `src/enemies/lobber_enemy.gd`:

```gdscript
class_name LobberEnemy
extends RangedEnemy

const SPEED_MULT: float = 0.9
const LOBBER_ATTACK_RANGE: float = 200.0
const LOBBER_WINDUP: float = 0.5
const REPOSITION_MIN_DIST: float = 60.0
const REPOSITION_MAX_DIST: float = 120.0
const REPOSITION_ARRIVE_DIST: float = 12.0

var _reposition_target: Vector2 = Vector2.ZERO
var _has_reposition_target: bool = false


func _ready() -> void:
	if weapon_resource == null:
		weapon_resource = WeaponRegistry.get_weapon_by_id("flame_lobber")
	super._ready()
	speed = _speed_base * SPEED_MULT
	_speed_base = speed
	_attack_range = LOBBER_ATTACK_RANGE
	windup_duration = LOBBER_WINDUP


func _select_sprite_textures() -> Array:
	return [LOBBER_NORMAL, LOBBER_BREATHE]


func _change_state(new_state: int) -> void:
	if new_state == State.COOLDOWN and _state == State.ATTACK:
		_pick_reposition_target()
	super._change_state(new_state)


func _pick_reposition_target() -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		_has_reposition_target = false
		return
	var away := global_position - _player_ref.global_position
	away = _safe_normalized(away) if away.length_squared() > 0.0001 else Vector2.RIGHT.rotated(randf() * TAU)
	var dist := randf_range(REPOSITION_MIN_DIST, REPOSITION_MAX_DIST)
	_reposition_target = global_position + away * dist
	_has_reposition_target = true


func _process_chase(delta: float) -> void:
	if _has_reposition_target:
		var to_target := _reposition_target - global_position
		if to_target.length() <= REPOSITION_ARRIVE_DIST:
			_has_reposition_target = false
		else:
			var move_dir := _apply_separation(_safe_normalized(to_target))
			velocity = move_dir * _get_effective_speed()
			return
	super._process_chase(delta)
```

Create `scenes/enemies/lobber_enemy.tscn`:

```
[gd_scene format=3 uid="uid://lobberenemy01"]

[ext_resource type="PackedScene" uid="uid://enemybase01" path="res://scenes/enemies/enemy.tscn" id="1"]
[ext_resource type="Script" path="res://src/enemies/lobber_enemy.gd" id="2"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/lobber/caves_lobber1.png" id="3_lobber1"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/lobber/caves_lobber2.png" id="4_lobber2"]
[ext_resource type="Script" path="res://src/enemies/feedback/enemy_animator.gd" id="5"]

[node name="LobberEnemy" instance=ExtResource("1")]
script = ExtResource("2")
weapon_resource = null
preferred_distance = 120.0
strafe_speed = 40.0
back_away_acceleration = 200.0

[node name="Sprite2D" parent="." index="0"]
texture = ExtResource("3_lobber1")

[node name="EnemyAnimator" type="Node" parent="."]
script = ExtResource("5")
texture_normal = ExtResource("3_lobber1")
texture_breathe = ExtResource("4_lobber2")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lobber_enemy.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/enemies/lobber_enemy.gd scenes/enemies/lobber_enemy.tscn tests/unit/test_lobber_enemy.gd
git commit -m "feat: add LobberEnemy (reposition-after-fire ranged archetype)"
```

---

### Task 16: Separation tuning for Brute/Armored

Brute and Armored read as visually bulkier — widen their separation radius so packs of them don't visually overlap/jitter.

**Files:**
- Modify: `src/enemies/brute_enemy.gd`
- Modify: `src/enemies/armored_enemy.gd`
- Modify: `tests/unit/test_brute_enemy.gd`
- Modify: `tests/unit/test_armored_enemy.gd`

**Interfaces:**
- Produces: `BruteEnemy`/`ArmoredEnemy` set `separation_radius = 22.0 * 1.3` and `crowd_spacing_scale = 1.3` in `_ready()`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_brute_enemy.gd`:

```gdscript
func test_brute_has_wider_separation_radius() -> void:
	var e := _brute()
	assert_float(e.separation_radius).is_greater(22.0)


func test_brute_has_wider_crowd_spacing() -> void:
	var e := _brute()
	assert_float(e.crowd_spacing_scale).is_greater(1.0)
```

Append to `tests/unit/test_armored_enemy.gd`:

```gdscript
func test_armored_has_wider_separation_radius() -> void:
	var e := _armored()
	assert_float(e.separation_radius).is_greater(22.0)


func test_armored_has_wider_crowd_spacing() -> void:
	var e := _armored()
	assert_float(e.crowd_spacing_scale).is_greater(1.0)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_brute_enemy.gd tests/unit/test_armored_enemy.gd`
Expected: FAIL — both default to base `separation_radius = 22.0`/`crowd_spacing_scale = 1.0`.

- [ ] **Step 3: Widen separation for both archetypes**

In `src/enemies/brute_enemy.gd`, add to `_ready()` (after the wander tuning lines):

```gdscript
	separation_radius = 22.0 * 1.3
	crowd_spacing_scale = 1.3
```

In `src/enemies/armored_enemy.gd`, add to `_ready()` (after `wander_enabled = false`):

```gdscript
	separation_radius = 22.0 * 1.3
	crowd_spacing_scale = 1.3
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_brute_enemy.gd tests/unit/test_armored_enemy.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/enemies/brute_enemy.gd src/enemies/armored_enemy.gd tests/unit/test_brute_enemy.gd tests/unit/test_armored_enemy.gd
git commit -m "feat: widen separation for bulkier Brute/Armored archetypes"
```

---

### Task 17: spawn_dispatcher.gd — weighted archetype rolls + pooled weapons

Replace the flat melee/ranged split and the old `_pick_melee_weapon()`/`_pick_ranged_weapon()` with weighted archetype rolls that draw from `EnemyWeaponPools`.

**Files:**
- Modify: `src/core/spawn_dispatcher.gd`
- Test: `tests/unit/test_spawn_dispatcher_archetypes.gd`

**Interfaces:**
- Consumes: `EnemyWeaponPools.build_melee_pool`/`build_ranged_pool`/`pick_weapon_id` (Tasks 6-8), `EncounterDirector.kill_streak` (Task 5), `SectorGrid.enemy_tier_for_distance` (existing).
- Produces: `SpawnDispatcher._weighted_pick(weights: Dictionary) -> String`, `SpawnDispatcher._pick_pooled_weapon(archetype: String, is_melee: bool, floor_num: int, sector_dist: int) -> Weapon`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite


func test_weighted_pick_respects_zero_weight_exclusion() -> void:
	var weights := {"a": 1.0, "b": 0.0}
	for i in range(20):
		assert_str(SpawnDispatcher._weighted_pick(weights)).is_equal("a")


func test_weighted_pick_only_returns_known_keys() -> void:
	var weights := {"grunt": 40.0, "brute": 15.0, "skirmisher": 20.0, "armored": 15.0, "cultist": 10.0}
	for i in range(50):
		assert_bool(weights.has(SpawnDispatcher._weighted_pick(weights))).is_true()


func test_pick_pooled_weapon_returns_valid_melee_weapon() -> void:
	var dispatcher := SpawnDispatcher.new()
	var w := dispatcher._pick_pooled_weapon("grunt", true, 1, 0)
	assert_object(w).is_not_null()


func test_pick_pooled_weapon_returns_valid_ranged_weapon() -> void:
	var dispatcher := SpawnDispatcher.new()
	var w := dispatcher._pick_pooled_weapon("archer", false, 1, 0)
	assert_object(w).is_not_null()
```

Note: `SpawnDispatcher` is currently an unnamed `extends Node` script (`src/core/spawn_dispatcher.gd`) with no `class_name`. Add one so it's referenceable by static/instance calls from the test.

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_spawn_dispatcher_archetypes.gd`
Expected: FAIL — `SpawnDispatcher` class name and `_weighted_pick`/`_pick_pooled_weapon` do not exist yet.

- [ ] **Step 3: Add `class_name` and archetype scene/weight tables**

In `src/core/spawn_dispatcher.gd`, change line 1 from `extends Node` to:

```gdscript
class_name SpawnDispatcher
extends Node
```

Add new scene consts after the existing ones (after line 7 `LUNGE_ENEMY_SCENE`):

```gdscript
const BRUTE_ENEMY_SCENE := preload("res://scenes/enemies/brute_enemy.tscn")
const SKIRMISHER_ENEMY_SCENE := preload("res://scenes/enemies/skirmisher_enemy.tscn")
const ARMORED_ENEMY_SCENE := preload("res://scenes/enemies/armored_enemy.tscn")
const CULTIST_ENEMY_SCENE := preload("res://scenes/enemies/cultist_enemy.tscn")
const ARCHER_ENEMY_SCENE := preload("res://scenes/enemies/archer_enemy.tscn")
const MAGE_ENEMY_SCENE := preload("res://scenes/enemies/mage_enemy.tscn")
const LOBBER_ENEMY_SCENE := preload("res://scenes/enemies/lobber_enemy.tscn")

const MELEE_ARCHETYPE_SCENES := {
	"grunt": MELEE_ENEMY_SCENE,
	"brute": BRUTE_ENEMY_SCENE,
	"skirmisher": SKIRMISHER_ENEMY_SCENE,
	"armored": ARMORED_ENEMY_SCENE,
	"cultist": CULTIST_ENEMY_SCENE,
}
const MELEE_ARCHETYPE_WEIGHTS := {
	"grunt": 40.0, "brute": 15.0, "skirmisher": 20.0, "armored": 15.0, "cultist": 10.0,
}
const RANGED_ARCHETYPE_SCENES := {
	"archer": ARCHER_ENEMY_SCENE, "mage": MAGE_ENEMY_SCENE, "lobber": LOBBER_ENEMY_SCENE,
}
const RANGED_ARCHETYPE_WEIGHTS := {
	"archer": 45.0, "mage": 25.0, "lobber": 30.0,
}
```

- [ ] **Step 4: Add `_weighted_pick` and `_pick_pooled_weapon`, remove the old pickers**

Replace `_pick_melee_weapon()`/`_pick_ranged_weapon()` (lines 255-267) with:

```gdscript
static func _weighted_pick(weights: Dictionary) -> String:
	var total := 0.0
	for w in weights.values():
		total += w
	var roll := randf() * total
	var cumulative := 0.0
	for key in weights.keys():
		cumulative += weights[key]
		if roll <= cumulative:
			return key
	return weights.keys()[0]


func _pick_pooled_weapon(archetype: String, is_melee: bool, floor_num: int, sector_dist: int) -> Weapon:
	var pool: Array[Dictionary] = EnemyWeaponPools.build_melee_pool(archetype) if is_melee else EnemyWeaponPools.build_ranged_pool(archetype)
	var sector_tier := SectorGrid.enemy_tier_for_distance(sector_dist)
	var kill_streak := 0
	if _world_manager != null and is_instance_valid(_world_manager):
		var dir = _world_manager.get("encounter_director")
		if dir != null and "kill_streak" in dir:
			kill_streak = dir.kill_streak
	var id := EnemyWeaponPools.pick_weapon_id(pool, floor_num, kill_streak, sector_tier)
	if id == "":
		return WeaponRegistry.get_weapon_by_id("rusty_sword") if is_melee else WeaponRegistry.get_weapon_by_id("throwing_knife")
	return WeaponRegistry.get_weapon_by_id(id)
```

- [ ] **Step 5: Wire archetype rolls into `_spawn_enemy`**

Replace the melee/elite/ranged branch of `_spawn_enemy` (lines 205-222):

```gdscript
		if is_elite:
			var elite_archetype := _weighted_pick(MELEE_ARCHETYPE_WEIGHTS)
			enemy = MELEE_ARCHETYPE_SCENES[elite_archetype].instantiate()
			enemy.is_elite = true
			enemy.elite_ability = randi() % 4 + 1
			enemy.weapon_resource = _pick_pooled_weapon(elite_archetype, true, floor_num, sector_dist)
		else:
			if randf() < 0.8:
				if roll_melee_is_lunge(randf()):
					enemy = LUNGE_ENEMY_SCENE.instantiate()
				else:
					var melee_archetype := _weighted_pick(MELEE_ARCHETYPE_WEIGHTS)
					enemy = MELEE_ARCHETYPE_SCENES[melee_archetype].instantiate()
					enemy.weapon_resource = _pick_pooled_weapon(melee_archetype, true, floor_num, sector_dist)
			elif randf() < 0.15:
				enemy = SNIPER_ENEMY_SCENE.instantiate()
			else:
				var ranged_archetype := _weighted_pick(RANGED_ARCHETYPE_WEIGHTS)
				enemy = RANGED_ARCHETYPE_SCENES[ranged_archetype].instantiate()
				enemy.weapon_resource = _pick_pooled_weapon(ranged_archetype, false, floor_num, sector_dist)
```

- [ ] **Step 6: Run test to verify it passes**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_spawn_dispatcher_archetypes.gd`
Expected: PASS

- [ ] **Step 7: Run the full test suite to check for regressions**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add src/core/spawn_dispatcher.gd tests/unit/test_spawn_dispatcher_archetypes.gd
git commit -m "feat: weighted archetype rolls + pooled weapons in spawn_dispatcher"
```

---

### Task 18: cave_spawner.gd — mirror archetype rolls

Mirror the same archetype-roll + pooled-weapon pattern in the open-world cave spawner so wandering spawns also use the new archetypes.

**Files:**
- Modify: `src/core/cave_spawner.gd`
- Test: `tests/unit/test_cave_spawner_archetypes.gd`

**Interfaces:**
- Consumes: `EnemyWeaponPools` (Tasks 6-8), `SpawnDispatcher.MELEE_ARCHETYPE_SCENES`/`MELEE_ARCHETYPE_WEIGHTS`/`RANGED_ARCHETYPE_SCENES`/`RANGED_ARCHETYPE_WEIGHTS`/`_weighted_pick` (Task 17, reused directly rather than duplicated).
- Produces: `CaveSpawner._pick_pooled_weapon(archetype: String, is_melee: bool) -> Weapon`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite


func test_cave_spawner_picks_valid_melee_weapon_for_each_archetype() -> void:
	var spawner := CaveSpawner.new()
	for archetype in SpawnDispatcher.MELEE_ARCHETYPE_WEIGHTS.keys():
		var w := spawner._pick_pooled_weapon(archetype, true)
		assert_object(w).is_not_null()


func test_cave_spawner_picks_valid_ranged_weapon_for_each_archetype() -> void:
	var spawner := CaveSpawner.new()
	for archetype in SpawnDispatcher.RANGED_ARCHETYPE_WEIGHTS.keys():
		var w := spawner._pick_pooled_weapon(archetype, false)
		assert_object(w).is_not_null()
```

Note: `CaveSpawner` is currently an unnamed `extends Node` script (`src/core/cave_spawner.gd`) with no `class_name`. Add one so it's referenceable from the test.

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_cave_spawner_archetypes.gd`
Expected: FAIL — `CaveSpawner` class name and `_pick_pooled_weapon` do not exist yet.

- [ ] **Step 3: Add `class_name` and replace the enemy-picking logic**

In `src/core/cave_spawner.gd`, change line 1 from `extends Node` to:

```gdscript
class_name CaveSpawner
extends Node
```

Replace `_pick_melee_weapon()`/`_pick_ranged_weapon()`/`_pick_elite_melee_weapon()` (lines 74-89) with:

```gdscript
func _pick_pooled_weapon(archetype: String, is_melee: bool) -> Weapon:
	var pool: Array[Dictionary] = EnemyWeaponPools.build_melee_pool(archetype) if is_melee else EnemyWeaponPools.build_ranged_pool(archetype)
	var floor_num: int = LevelManager.floor_number
	var sector_tier := DropTable.EnemyTier.NORMAL
	var grid: SectorGrid = LevelManager.get_grid()
	if grid != null and _world_manager != null and is_instance_valid(_world_manager):
		var sector := grid.world_to_sector(_world_manager.tracking_position)
		var dist := grid.chebyshev_distance(sector, Vector2i.ZERO)
		sector_tier = SectorGrid.enemy_tier_for_distance(dist)
	var kill_streak := 0
	if _world_manager != null and is_instance_valid(_world_manager):
		var dir = _world_manager.get("encounter_director")
		if dir != null and "kill_streak" in dir:
			kill_streak = dir.kill_streak
	var id := EnemyWeaponPools.pick_weapon_id(pool, floor_num, kill_streak, sector_tier)
	if id == "":
		return WeaponRegistry.get_weapon_by_id("rusty_sword") if is_melee else WeaponRegistry.get_weapon_by_id("throwing_knife")
	return WeaponRegistry.get_weapon_by_id(id)
```

Replace `_pick_enemy_scene()` (lines 68-71) and the body of `_spawn_enemy` (lines 178-199) to roll archetypes:

```gdscript
func _pick_enemy_scene() -> PackedScene:
	if randf() < 0.8:
		var archetype := SpawnDispatcher._weighted_pick(SpawnDispatcher.MELEE_ARCHETYPE_WEIGHTS)
		return SpawnDispatcher.MELEE_ARCHETYPE_SCENES[archetype]
	var archetype := SpawnDispatcher._weighted_pick(SpawnDispatcher.RANGED_ARCHETYPE_WEIGHTS)
	return SpawnDispatcher.RANGED_ARCHETYPE_SCENES[archetype]


func _archetype_for_scene(scene: PackedScene) -> String:
	for archetype in SpawnDispatcher.MELEE_ARCHETYPE_SCENES:
		if SpawnDispatcher.MELEE_ARCHETYPE_SCENES[archetype] == scene:
			return archetype
	for archetype in SpawnDispatcher.RANGED_ARCHETYPE_SCENES:
		if SpawnDispatcher.RANGED_ARCHETYPE_SCENES[archetype] == scene:
			return archetype
	return "grunt"


func _spawn_enemy(world_pos: Vector2) -> void:
	if _spawn_parent == null:
		return
	var scene := _pick_enemy_scene()
	var enemy := scene.instantiate()
	var archetype := _archetype_for_scene(scene)
	var is_melee: bool = SpawnDispatcher.MELEE_ARCHETYPE_SCENES.has(archetype)

	var is_elite_roll := randf() < elite_chance
	if is_elite_roll:
		enemy.is_elite = true
		enemy.elite_ability = randi() % 4 + 1

	enemy.weapon_resource = _pick_pooled_weapon(archetype, is_melee)

	enemy.global_position = world_pos
	enemy.add_to_group("cave_spawned")
	_spawn_parent.add_child(enemy)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_cave_spawner_archetypes.gd`
Expected: PASS

- [ ] **Step 5: Run the full test suite to check for regressions**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add src/core/cave_spawner.gd tests/unit/test_cave_spawner_archetypes.gd
git commit -m "feat: mirror weighted archetype rolls in cave_spawner"
```

---

## Post-plan checklist

- [ ] Run the full test suite one final time: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/`
- [ ] Manually spot-check in the running game (per the `run`/`verify` skills): confirm Brute/Skirmisher/Armored/Cultist/Archer/Mage/Lobber all spawn, look visually distinct, and behave per their archetype (Brute commits from farther out, Skirmisher flanks, Armored holds ground, Cultist heals allies and shows "Caw cawww", Archer kites, Mage plants and fires a homing orb, Lobber repositions after firing).
- [ ] Run `graphify update .` to refresh the knowledge graph with the new files.
