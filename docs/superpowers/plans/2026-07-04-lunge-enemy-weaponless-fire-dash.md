# Lunge Enemy: Weaponless, Larger, Fire Dash VFX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `LungeEnemy` never hold or drop a weapon, render at 1.6x scale, and show a
fire-like VFX ahead of it while dashing.

**Architecture:** Add a `carries_weapon: bool = true` export to the base `Enemy` class;
`MeleeEnemy._ready()` skips weapon construction when it's `false`. `LungeEnemy` sets it
`false` via `_init()`, gains its own `dash_damage` export (replacing its read of
`weapon.damage`), scales itself 1.6x, and owns a small new `DashFireVfx` child node
(CPUParticles2D-based, matching the existing `on_fire` status particle style) that it
starts/stops around the dash window.

**Tech Stack:** Godot 4 / GDScript, GdUnit4 for headless unit tests.

## Global Constraints

- `carries_weapon` must default to `true` on `Enemy` — every existing enemy type (melee,
  ranged, sniper, boss) must build its weapon exactly as it does today. No behavior change
  for any enemy other than `LungeEnemy`.
- `LungeEnemy`'s effective dash-contact damage must match its current output (previously
  `weapon.damage` off a bare `MeleeWeapon.new()`, which defaults `damage = 5.0`), including
  floor-based `damage_scale` scaling, which today happens via
  `Enemy._apply_damage_scale()` multiplying `weapon.damage`. Since `LungeEnemy` will have
  no `weapon`, `dash_damage` must be explicitly scaled by `damage_scale` at the point of
  use to avoid silently losing floor-difficulty scaling.
- No changes to dash movement, telegraph, state flow, or `spawn_dispatcher.gd` — spawn
  code still assigns `weapon_resource` to `LungeEnemy` instances (`src/core/spawn_dispatcher.gd:217`)
  but this becomes inert once `carries_weapon` is `false`, since `MeleeEnemy._ready()` will
  ignore `weapon_resource` in that case. Verified harmless; not part of this plan's changes.
- Run every test with:
  `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a <path> 2>&1 | tail -60`

---

### Task 1: `carries_weapon` flag on base `Enemy`

**Files:**
- Modify: `src/enemies/enemy.gd:24` (add export near the other exports)
- Test: `tests/unit/test_enemy_carries_weapon.gd` (new)

**Interfaces:**
- Produces: `Enemy.carries_weapon: bool` (export, default `true`), readable/settable by
  any subclass or test.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_enemy_carries_weapon.gd`:

```gdscript
extends GdUnitTestSuite


func test_carries_weapon_defaults_true() -> void:
	var e: Enemy = auto_free(Enemy.new())
	add_child(e)
	assert_bool(e.carries_weapon).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_carries_weapon.gd 2>&1 | tail -60`
Expected: FAIL — `Invalid get index 'carries_weapon'` (property doesn't exist yet).

- [ ] **Step 3: Add the export**

In `src/enemies/enemy.gd`, immediately after line 24 (`@export var damage_scale: float = 1.0`), add:

```gdscript
@export var carries_weapon: bool = true
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_carries_weapon.gd 2>&1 | tail -60`
Expected: PASS (1 test, 0 failures).

- [ ] **Step 5: Commit**

```bash
git add src/enemies/enemy.gd tests/unit/test_enemy_carries_weapon.gd
git commit -m "feat(enemies): add carries_weapon flag to base Enemy"
```

---

### Task 2: `MeleeEnemy` skips weapon construction when weaponless

**Files:**
- Modify: `src/enemies/melee_enemy.gd:7-21` (the `_ready()` method)
- Test: `tests/unit/test_melee_enemy.gd` (new — no existing test file for `MeleeEnemy`
  itself; `test_lunge_enemy.gd:4-7` only tests the inherited `_moves_during_attack`)

**Interfaces:**
- Consumes: `Enemy.carries_weapon` (from Task 1).
- Produces: no new public API — `MeleeEnemy._ready()` behavior change only; `weapon`
  stays `null` when `carries_weapon == false`.

- [ ] **Step 1: Write the failing tests**

Create `tests/unit/test_melee_enemy.gd`:

```gdscript
extends GdUnitTestSuite


func test_default_melee_enemy_builds_bare_weapon() -> void:
	var e: MeleeEnemy = auto_free(MeleeEnemy.new())
	add_child(e)
	assert_object(e.weapon).is_not_null()
	assert_float(e._attack_range).is_equal(28.0)


func test_melee_enemy_with_weapon_resource_uses_it() -> void:
	var res := MeleeWeapon.new()
	res.weapon_reach = 40.0
	res.cooldown = 1.2
	var e: MeleeEnemy = auto_free(MeleeEnemy.new())
	e.weapon_resource = res
	add_child(e)
	assert_float(e._attack_range).is_equal(40.0)
	assert_float(e.cooldown_duration).is_equal(1.2)


func test_weaponless_melee_enemy_has_no_weapon() -> void:
	var e: MeleeEnemy = auto_free(MeleeEnemy.new())
	e.carries_weapon = false
	add_child(e)
	assert_object(e.weapon).is_null()
```

Note: `test_weaponless_melee_enemy_has_no_weapon` sets `carries_weapon` before
`add_child` (i.e. before `_ready()` runs), which is how `_init()`-driven subclasses like
`LungeEnemy` will do it in Task 3.

- [ ] **Step 2: Run tests to verify the third one fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_melee_enemy.gd 2>&1 | tail -60`
Expected: first two PASS (current behavior already supports them), third FAILS because
`MeleeEnemy._ready()` currently always builds a `weapon` regardless of `carries_weapon`
(the flag doesn't affect it yet).

- [ ] **Step 3: Guard weapon construction in `_ready()`**

Replace `src/enemies/melee_enemy.gd:7-21` with:

```gdscript
func _ready() -> void:
	if not carries_weapon:
		weapon = null
		_attack_range = 28.0
		speed = 60.0
		max_health = 15
		_speed_base = speed
		cooldown_duration = 0.8
	elif weapon_resource:
		weapon = weapon_resource.duplicate()
		_attack_range = weapon.weapon_reach
		cooldown_duration = weapon_resource.cooldown
		speed = 60.0
	else:
		weapon = MeleeWeapon.new()
		_attack_range = 28.0
		speed = 60.0
		max_health = 15
		_speed_base = speed
		cooldown_duration = weapon.cooldown
	super._ready()
	_setup_drop_table()
```

(The `elif`/`else` branches are byte-for-byte the original two branches — only the new
`if not carries_weapon` branch is added.)

- [ ] **Step 4: Run tests to verify all pass**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_melee_enemy.gd 2>&1 | tail -60`
Expected: PASS (3 tests, 0 failures).

- [ ] **Step 5: Run the full enemy test suite for regressions**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit 2>&1 | tail -60`
Expected: PASS — no existing enemy tests broken (in particular
`tests/unit/test_lunge_enemy.gd` should still be green at this point since `LungeEnemy`
hasn't changed yet).

- [ ] **Step 6: Commit**

```bash
git add src/enemies/melee_enemy.gd tests/unit/test_melee_enemy.gd
git commit -m "feat(enemies): skip weapon construction for weaponless MeleeEnemy subclasses"
```

---

### Task 3: `LungeEnemy` goes weaponless with its own `dash_damage`

**Files:**
- Modify: `src/enemies/lunge_enemy.gd`
- Modify: `tests/unit/test_lunge_enemy.gd:90-102` (`test_body_check_hits_once_within_contact_radius`
  currently sets `e.weapon.damage = 7.0`, which will break once `weapon` is `null`)

**Interfaces:**
- Consumes: `Enemy.carries_weapon` (Task 1), `Enemy.damage_scale` (existing,
  `src/enemies/enemy.gd:24`).
- Produces: `LungeEnemy.dash_damage: float` (export, default `5.0`, matching the previous
  effective default of a bare `MeleeWeapon.new().damage`).

- [ ] **Step 1: Write the failing tests**

Add to `tests/unit/test_lunge_enemy.gd` (new section at the end):

```gdscript
# --- Task 3: weaponless dash damage ---

func test_lunge_enemy_has_no_weapon() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	assert_object(e.weapon).is_null()

func test_lunge_enemy_carries_weapon_is_false() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	assert_bool(e.carries_weapon).is_false()

func test_body_check_uses_dash_damage_scaled_by_damage_scale() -> void:
	var e := _lunge_to_recording(Vector2.ZERO, Vector2(5, 0))
	e.dash_damage = 7.0
	e.damage_scale = 2.0
	e._state = Enemy.State.ATTACK
	e._attack_started = false
	e._dash_done = false
	for i in range(20):
		if e._state != Enemy.State.ATTACK:
			break
		e._process_attack(0.05)
	var hits: Array = e._player_ref.hits
	assert_int(hits.size()).is_equal(1)
	assert_int(hits[0]["dmg"]).is_equal(14)
```

Update the existing `test_body_check_hits_once_within_contact_radius` (currently at
`tests/unit/test_lunge_enemy.gd:90-102`) to use `dash_damage` instead of `weapon.damage`:

```gdscript
func test_body_check_hits_once_within_contact_radius() -> void:
	var e := _lunge_to_recording(Vector2.ZERO, Vector2(5, 0))
	e.dash_damage = 7.0
	e._state = Enemy.State.ATTACK
	e._attack_started = false
	e._dash_done = false
	for i in range(20):
		if e._state != Enemy.State.ATTACK:
			break
		e._process_attack(0.05)
	var hits: Array = e._player_ref.hits
	assert_int(hits.size()).is_equal(1)
	assert_int(hits[0]["dmg"]).is_equal(7)
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lunge_enemy.gd 2>&1 | tail -60`
Expected: `test_lunge_enemy_has_no_weapon` and `test_lunge_enemy_carries_weapon_is_false`
FAIL (weapon is still built; `carries_weapon` still `true`). The updated
`test_body_check_hits_once_within_contact_radius` FAILS with an error reading
`dash_damage` (property doesn't exist yet). `test_body_check_uses_dash_damage_scaled_by_damage_scale`
FAILS the same way.

- [ ] **Step 3: Update `LungeEnemy`**

Replace the top of `src/enemies/lunge_enemy.gd` (lines 1-13) with:

```gdscript
class_name LungeEnemy
extends MeleeEnemy

@export var lunge_range: float = 120.0
@export var dash_speed: float = 420.0
@export var dash_duration: float = 0.22
@export var contact_radius: float = 18.0
@export var recovery_duration: float = 1.0
@export var dash_damage: float = 5.0

var _lock_dir: Vector2 = Vector2.DOWN
var _dash_timer: float = 0.0
var _dash_hit: bool = false
var _dash_done: bool = false


func _init() -> void:
	carries_weapon = false
```

Then replace `_check_body_contact()` (currently lines 65-76) with:

```gdscript
func _check_body_contact() -> void:
	if _dash_hit:
		return
	if _player_ref == null or not is_instance_valid(_player_ref):
		return
	if global_position.distance_to(_player_ref.global_position) > contact_radius:
		return
	_dash_hit = true
	if _player_ref.has_method("on_hit_impact"):
		var dmg: int = int(dash_damage * damage_scale)
		_player_ref.on_hit_impact(global_position, _lock_dir, dmg)
```

- [ ] **Step 4: Run tests to verify all pass**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lunge_enemy.gd 2>&1 | tail -60`
Expected: PASS (all tests in the file, including the pre-existing ones from the original
lunge design).

- [ ] **Step 5: Run the full test suite for regressions**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit 2>&1 | tail -60`
Expected: PASS — no regressions elsewhere (in particular `test_lunge_spawn.gd` and
`test_melee_enemy.gd` from Task 2 stay green).

- [ ] **Step 6: Commit**

```bash
git add src/enemies/lunge_enemy.gd tests/unit/test_lunge_enemy.gd
git commit -m "feat(enemies): make LungeEnemy weaponless with its own scaled dash_damage"
```

---

### Task 4: `LungeEnemy` renders at 1.6x scale

**Files:**
- Modify: `src/enemies/lunge_enemy.gd` (`_ready()`)
- Test: `tests/unit/test_lunge_enemy.gd` (new test)

**Interfaces:**
- Consumes: none new.
- Produces: `LungeEnemy.scale == Vector2(1.6, 1.6)` after `_ready()`.

- [ ] **Step 1: Write the failing test**

Add to `tests/unit/test_lunge_enemy.gd`:

```gdscript
# --- Task 4: larger scale ---

func test_lunge_enemy_scales_up() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	assert_vector(e.scale).is_equal(Vector2(1.6, 1.6))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lunge_enemy.gd 2>&1 | tail -60`
Expected: FAIL — `e.scale` is `Vector2(1, 1)` (default, unset).

- [ ] **Step 3: Set the scale in `_ready()`**

In `src/enemies/lunge_enemy.gd`, in `_ready()` (currently):

```gdscript
func _ready() -> void:
	super._ready()
	_attack_range = lunge_range
	windup_duration = 0.45
	cooldown_duration = recovery_duration
```

add one line:

```gdscript
func _ready() -> void:
	super._ready()
	_attack_range = lunge_range
	windup_duration = 0.45
	cooldown_duration = recovery_duration
	scale = Vector2(1.6, 1.6)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lunge_enemy.gd 2>&1 | tail -60`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/enemies/lunge_enemy.gd tests/unit/test_lunge_enemy.gd
git commit -m "feat(enemies): render LungeEnemy at 1.6x scale"
```

---

### Task 5: `DashFireVfx` scene + script (fire cone, start/stop)

**Files:**
- Create: `src/enemies/feedback/dash_fire_vfx.gd`
- Create: `scenes/fx/dash_fire_vfx.tscn`
- Test: `tests/unit/test_dash_fire_vfx.gd` (new)

**Interfaces:**
- Produces: `DashFireVfx` (class_name, extends `Node2D`):
  - `start(direction: Vector2) -> void` — rotates the node to face `direction`, offsets
    it `offset_distance` px along `direction`, and sets the internal particles emitting.
  - `stop() -> void` — stops emission (already-emitted particles finish their lifetime).
  - `@export var offset_distance: float = 16.0`

- [ ] **Step 1: Write the failing tests**

Create `tests/unit/test_dash_fire_vfx.gd`:

```gdscript
extends GdUnitTestSuite


func _make_vfx() -> DashFireVfx:
	var v: DashFireVfx = auto_free(DashFireVfx.new())
	add_child(v)
	return v


func test_start_faces_direction_and_offsets_forward() -> void:
	var v := _make_vfx()
	v.start(Vector2.RIGHT)
	assert_float(v.rotation).is_equal_approx(0.0, 0.01)
	assert_float(v.position.x).is_equal_approx(v.offset_distance, 0.01)
	assert_float(v.position.y).is_equal_approx(0.0, 0.01)


func test_start_sets_emitting_true() -> void:
	var v := _make_vfx()
	v.start(Vector2.RIGHT)
	var particles: CPUParticles2D = v.get_node("Particles")
	assert_bool(particles.emitting).is_true()


func test_stop_sets_emitting_false() -> void:
	var v := _make_vfx()
	v.start(Vector2.RIGHT)
	v.stop()
	var particles: CPUParticles2D = v.get_node("Particles")
	assert_bool(particles.emitting).is_false()


func test_start_rotates_to_upward_direction() -> void:
	var v := _make_vfx()
	v.start(Vector2.UP)
	assert_float(v.rotation).is_equal_approx(Vector2.UP.angle(), 0.01)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_dash_fire_vfx.gd 2>&1 | tail -60`
Expected: FAIL — `DashFireVfx` class doesn't exist yet (parse/identifier error).

- [ ] **Step 3: Write `src/enemies/feedback/dash_fire_vfx.gd`**

```gdscript
class_name DashFireVfx
extends Node2D

@export var offset_distance: float = 16.0

const FIRE_COLOR := Color(1.0, 0.55, 0.15, 0.9)
const FIRE_COLOR_HOT := Color(1.0, 0.85, 0.3, 1.0)
const FIRE_COLOR_FADE := Color(1.0, 0.2, 0.05, 0.0)

var _particles: CPUParticles2D = null


func _ready() -> void:
	z_index = 6
	z_as_relative = false
	_particles = _build_particles()
	add_child(_particles)


func start(direction: Vector2) -> void:
	if direction.length_squared() > 0.0001:
		var dir := direction.normalized()
		rotation = dir.angle()
		position = dir * offset_distance
	_particles.restart()
	_particles.emitting = true


func stop() -> void:
	_particles.emitting = false


func _build_particles() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Particles"
	p.emitting = false
	p.local_coords = true
	p.amount = 24
	p.lifetime = 0.25
	p.direction = Vector2(1.0, 0.0)
	p.spread = 18.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 110.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.color = FIRE_COLOR
	p.color_ramp = _build_gradient()
	p.z_as_relative = false
	p.z_index = 6
	return p


func _build_gradient() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, FIRE_COLOR_HOT)
	g.set_color(1, FIRE_COLOR_FADE)
	return g
```

- [ ] **Step 4: Write `scenes/fx/dash_fire_vfx.tscn`**

```
[gd_scene format=3 uid="uid://dashfirevfx01"]

[ext_resource type="Script" path="res://src/enemies/feedback/dash_fire_vfx.gd" id="1"]

[node name="DashFireVfx" type="Node2D"]
script = ExtResource("1")
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_dash_fire_vfx.gd 2>&1 | tail -60`
Expected: PASS (4 tests, 0 failures).

- [ ] **Step 6: Commit**

```bash
git add src/enemies/feedback/dash_fire_vfx.gd scenes/fx/dash_fire_vfx.tscn tests/unit/test_dash_fire_vfx.gd
git commit -m "feat(fx): add DashFireVfx forward-facing fire cone effect"
```

---

### Task 6: Wire `DashFireVfx` into `LungeEnemy`'s dash

**Files:**
- Modify: `src/enemies/lunge_enemy.gd`
- Test: `tests/unit/test_lunge_enemy.gd` (new tests)

**Interfaces:**
- Consumes: `DashFireVfx.start(direction: Vector2)`, `DashFireVfx.stop()` (Task 5).
- Produces: `LungeEnemy._fire_vfx: DashFireVfx` (internal, instanced as a child in
  `_ready()`), started in `_begin_dash()`, stopped wherever the dash ends
  (`_tick_dash()`'s timer-expiry branch).

- [ ] **Step 1: Write the failing tests**

Add to `tests/unit/test_lunge_enemy.gd`:

```gdscript
# --- Task 6: dash fire VFX wiring ---

func test_lunge_enemy_has_fire_vfx_child() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	assert_object(e._fire_vfx).is_not_null()
	assert_bool(e._fire_vfx is DashFireVfx).is_true()

func test_begin_dash_starts_fire_vfx_along_lock_dir() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	e._begin_dash()
	var particles: CPUParticles2D = e._fire_vfx.get_node("Particles")
	assert_bool(particles.emitting).is_true()
	assert_float(e._fire_vfx.rotation).is_equal_approx(e._lock_dir.angle(), 0.01)

func test_dash_end_stops_fire_vfx() -> void:
	var e := _lunge_to_recording(Vector2.ZERO, Vector2(100, 0))
	e._state = Enemy.State.ATTACK
	e._attack_started = false
	e._dash_done = false
	for i in range(20):
		if e._state != Enemy.State.ATTACK:
			break
		e._process_attack(0.05)
	var particles: CPUParticles2D = e._fire_vfx.get_node("Particles")
	assert_bool(particles.emitting).is_false()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lunge_enemy.gd 2>&1 | tail -60`
Expected: FAIL — `e._fire_vfx` doesn't exist yet (null / invalid get index).

- [ ] **Step 3: Wire it up in `lunge_enemy.gd`**

Add the preload and instance var near the top (after the `@export`/`var` block):

```gdscript
const DASH_FIRE_VFX_SCENE: PackedScene = preload("res://scenes/fx/dash_fire_vfx.tscn")

var _fire_vfx: DashFireVfx = null
```

In `_ready()`, after setting `scale` (from Task 4):

```gdscript
func _ready() -> void:
	super._ready()
	_attack_range = lunge_range
	windup_duration = 0.45
	cooldown_duration = recovery_duration
	scale = Vector2(1.6, 1.6)
	_fire_vfx = DASH_FIRE_VFX_SCENE.instantiate()
	add_child(_fire_vfx)
```

In `_begin_dash()`, add the VFX start call:

```gdscript
func _begin_dash() -> void:
	_lock_dir = get_facing_direction()
	_dash_timer = dash_duration
	_dash_hit = false
	_fire_vfx.start(_lock_dir)
```

In `_tick_dash()`, stop the VFX where the dash ends:

```gdscript
func _tick_dash(delta: float) -> void:
	velocity = _lock_dir * dash_speed
	_check_body_contact()
	_dash_timer -= delta
	if _dash_timer <= 0.0:
		_dash_done = true
		velocity = Vector2.ZERO
		_fire_vfx.stop()
		_change_state(State.COOLDOWN)
```

- [ ] **Step 4: Run tests to verify all pass**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lunge_enemy.gd 2>&1 | tail -60`
Expected: PASS (all tests in the file).

- [ ] **Step 5: Run the full test suite for regressions**

Run: `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit 2>&1 | tail -60`
Expected: PASS — full suite green, no regressions in any other enemy/spawn/weapon test.

- [ ] **Step 6: Commit**

```bash
git add src/enemies/lunge_enemy.gd tests/unit/test_lunge_enemy.gd
git commit -m "feat(enemies): start/stop DashFireVfx around LungeEnemy's dash"
```

---

### Task 7: Manual playtest verification

**Files:** none (manual verification only).

- [ ] **Step 1: Launch the project and encounter a lunge enemy**

Use the `run` skill or `godot --path .` to launch the game, reach a floor with melee
spawns, and identify a `LungeEnemy` (it's ~25% of melee spawns per
`SpawnDispatcher.LUNGE_MELEE_CHANCE`, per `test_lunge_spawn.gd`).

- [ ] **Step 2: Verify visual size**

Confirm the lunge enemy reads as noticeably larger (1.6x) than a standard melee enemy
standing next to it.

- [ ] **Step 3: Verify no weapon visual or drop**

Confirm no weapon sprite is ever visible on the lunge enemy, and kill several to confirm
none ever drop a weapon pickup (gold/modifier drops from `drop_table` should still work
normally).

- [ ] **Step 4: Verify the dash fire VFX**

Trigger several dashes and confirm: the fire cone appears ahead of the enemy in the dash
direction, is clearly visible without obscuring the telegraph/tell, and fades out cleanly
when the dash ends (no lingering emission into COOLDOWN).

- [ ] **Step 5: Note any tuning feedback**

If `dash_damage`, `offset_distance`, or the particle look need adjustment, note the
desired values — this is expected per the design spec's tuning-pass risk and can be a
quick follow-up edit to the exported values, no further plan needed.
