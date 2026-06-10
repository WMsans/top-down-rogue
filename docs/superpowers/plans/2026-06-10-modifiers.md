# Modifiers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the ten weapon modifiers in `docs/design_docs/modifiers.csv` — swing-triggered projectile fans, cadence-gated combo volleys, and charge/chance effects — reusing the Sub-project 3 projectile behaviors.

**Architecture:** One new `Modifier.on_attack(weapon, user, ctx)` hook fired once per swing/shot/combo-step via `Weapon.notify_attack`. A `ProjectileModifier` base fires on a self-counted "every N hits" cadence (no weapon combo state queried). A static `ModifierProjectile` helper spawns the projectiles. Two charge/chance modifiers (`penetrating_shockwave`, `lightning_bolt`) override `on_attack` directly. `Projectile` gains a `hit_status` field so themed projectiles apply burn/chill on hit.

**Tech Stack:** Godot 4 / GDScript, gdUnit4 for tests.

---

## Conventions

**Run the modifier test suite** (used throughout — import first so a fresh worktree resolves assets):

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_modifiers.gd
```

**Regression suite** (projectile + weapon tests that this plan touches):

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode \
  -a res://tests/unit/test_projectile.gd \
  -a res://tests/unit/test_projectile_behaviors.gd \
  -a res://tests/unit/test_advanced_melee_combo.gd \
  -a res://tests/unit/test_ranged_weapon.gd \
  -a res://tests/unit/test_weapon_registry_pools.gd
```

gdUnit4 assertion API in this repo: `assert_that(x).is_equal(y)` / `.is_true()` / `.is_greater(0.0)`, `assert_int(x).is_equal(n)`, `assert_str(s).is_equal(t)`, `assert_bool(b).is_true()`, `assert_array(a).is_equal(b)`. Use `auto_free(...)` for nodes you don't add to a self-freeing parent. Test suites `extends GdUnitTestSuite`.

---

## File Structure

**New files**
- `src/weapons/modifiers/modifier_projectile.gd` — `ModifierProjectile`: static projectile-spawn helper (one + fan).
- `src/weapons/modifiers/projectile_modifier.gd` — `ProjectileModifier`: cadence base (`period`/`fire_on`/`_fire`).
- `src/weapons/modifiers/fireball_fan_modifier.gd` — `FireballFanModifier`
- `src/weapons/modifiers/icicle_volley_modifier.gd` — `IcicleVolleyModifier`
- `src/weapons/modifiers/gleaming_projectile_modifier.gd` — `GleamingProjectileModifier`
- `src/weapons/modifiers/green_crescent_modifier.gd` — `GreenCrescentModifier`
- `src/weapons/modifiers/arc_volley_modifier.gd` — `ArcVolleyModifier`
- `src/weapons/modifiers/triangular_volley_modifier.gd` — `TriangularVolleyModifier`
- `src/weapons/modifiers/splitting_rounds_modifier.gd` — `SplittingRoundsModifier`
- `src/weapons/modifiers/bouncing_bullets_modifier.gd` — `BouncingBulletsModifier`
- `src/weapons/modifiers/penetrating_shockwave_modifier.gd` — `PenetratingShockwaveModifier`
- `src/weapons/modifiers/lightning_bolt_modifier.gd` — `LightningBoltModifier`
- `tests/unit/test_modifiers.gd` — all modifier unit tests.

**Modified files**
- `src/weapons/modifier.gd` — add `on_attack` no-op hook.
- `src/weapons/weapon.gd` — add `notify_attack`.
- `src/weapons/projectile.gd` — add `hit_status` field + on-hit stain.
- `src/weapons/melee_weapon.gd` — call `notify_attack` in `_use_impl`.
- `src/weapons/ranged_weapon.gd` — call `notify_attack` in `_use_impl`.
- `src/weapons/advanced_melee_weapon.gd` — set charge fields + call `notify_attack` in `_play_move`.
- `src/autoload/weapon_registry.gd` — register ten scripts; assign drop tiers; update `lava_emitter` paths.
- `docs/design_docs/implementation_todo.md` — mark Sub-project 4 rows done.

**Moved**
- `src/weapons/lava_emitter_modifier.gd` → `src/weapons/modifiers/lava_emitter_modifier.gd` (+ `.uid`).

---

### Task 1: `Projectile.hit_status` — apply status on hit (not just crit)

**Files:**
- Modify: `src/weapons/projectile.gd`
- Test: `tests/unit/test_modifiers.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_modifiers.gd`:

```gdscript
extends GdUnitTestSuite

# A minimal attackable target with a StatusComponent, used across the suite.
class _StubTarget extends Node2D:
	var hits: Array = []
	func _init() -> void:
		add_to_group("attackable")
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)
	func on_hit_impact(_point: Vector2, _dir: Vector2, dmg: int) -> void:
		hits.append(dmg)


func test_projectile_hit_status_applies_on_non_crit_hit() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var target := _StubTarget.new()
	parent.add_child(target)
	var p: Projectile = Projectile.new()  # frees itself on hit
	p.is_enemy_projectile = false
	p.damage = 5.0
	p.crit_chance = 0.0
	p.hit_status = "on_fire"
	parent.add_child(p)
	p._handle_hit(target)
	var sc: StatusComponent = target.get_node("StatusComponent")
	assert_that(sc.get_stain("on_fire")).is_greater(0.0)


func test_projectile_no_hit_status_applies_nothing() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var target := _StubTarget.new()
	parent.add_child(target)
	var p: Projectile = Projectile.new()
	p.is_enemy_projectile = false
	p.damage = 5.0
	p.crit_chance = 0.0
	parent.add_child(p)
	p._handle_hit(target)
	var sc: StatusComponent = target.get_node("StatusComponent")
	assert_that(sc.get_stain("on_fire")).is_equal(0.0)
```

- [ ] **Step 2: Run test to verify it fails**

Run the modifier test suite (see Conventions).
Expected: FAIL — `hit_status` is not a property of `Projectile` (parse/assign error).

- [ ] **Step 3: Implement the field + on-hit application**

In `src/weapons/projectile.gd`, add the constant next to the existing `CRIT_STATUS_STAIN`:

```gdscript
const CRIT_STATUS_STAIN := 2.0
const HIT_STATUS_STAIN := 2.0
```

Add the export next to the other crit exports (after `crit_status`):

```gdscript
@export var crit_status: String = ""
@export var hit_status: String = ""
```

In `_handle_hit`, in the attackable branch, after the existing crit-status block and before the keep-alive loop, apply the on-hit stain:

```gdscript
				if is_crit and crit_status != "":
					var sc = target.get_node_or_null("StatusComponent")
					if sc != null:
						sc.add_stain(crit_status, CRIT_STATUS_STAIN)
				if hit_status != "":
					var hs = target.get_node_or_null("StatusComponent")
					if hs != null:
						hs.add_stain(hit_status, HIT_STATUS_STAIN)
```

- [ ] **Step 4: Run test to verify it passes**

Run the modifier test suite.
Expected: PASS (both new tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/projectile.gd tests/unit/test_modifiers.gd
git commit -m "feat: Projectile.hit_status applies a status on every hit"
```

---

### Task 2: `on_attack` hook + `notify_attack` dispatcher

**Files:**
- Modify: `src/weapons/modifier.gd`
- Modify: `src/weapons/weapon.gd`
- Test: `tests/unit/test_modifiers.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_modifiers.gd`:

```gdscript
# Records on_attack calls.
class _RecordMod extends Modifier:
	var attacks: int = 0
	var last_ctx: Dictionary = {}
	func on_attack(_weapon: Weapon, _user: Node, ctx: Dictionary) -> void:
		attacks += 1
		last_ctx = ctx


func test_notify_attack_dispatches_to_all_modifiers() -> void:
	var w: Weapon = Weapon.new()
	var m1 := _RecordMod.new()
	var m2 := _RecordMod.new()
	w.modifiers = [m1, null, m2]
	var ctx := { "direction": Vector2.RIGHT, "origin": Vector2.ZERO, "charged": true, "charge_ratio": 1.0 }
	w.notify_attack(null, ctx)
	assert_int(m1.attacks).is_equal(1)
	assert_int(m2.attacks).is_equal(1)
	assert_that(m1.last_ctx["charged"]).is_true()


func test_base_modifier_on_attack_is_noop() -> void:
	var m: Modifier = Modifier.new()
	m.on_attack(null, null, {})  # must not error
```

- [ ] **Step 2: Run test to verify it fails**

Run the modifier test suite.
Expected: FAIL — `notify_attack` not found on `Weapon` / `on_attack` not found on `Modifier`.

- [ ] **Step 3: Implement the hook and dispatcher**

In `src/weapons/modifier.gd`, add after `on_use`:

```gdscript
func on_attack(_weapon: Weapon, _user: Node, _ctx: Dictionary) -> void:
	pass
```

In `src/weapons/weapon.gd`, add after `on_press`/`on_release` (anywhere at top-level scope):

```gdscript
func notify_attack(user: Node, ctx: Dictionary) -> void:
	for modifier in modifiers:
		if modifier != null:
			modifier.on_attack(self, user, ctx)
```

- [ ] **Step 4: Run test to verify it passes**

Run the modifier test suite.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/modifier.gd src/weapons/weapon.gd tests/unit/test_modifiers.gd
git commit -m "feat: Modifier.on_attack hook + Weapon.notify_attack dispatcher"
```

---

### Task 3: Wire `notify_attack` into weapon attack paths

`MeleeWeapon._use_impl` (plain swing), `RangedWeapon._use_impl` (per shot), and `AdvancedMeleeWeapon._play_move` (per combo/charged/flurry step). `_play_move`'s signature stays `(move, user)` so the existing combo-test probes keep working; charge context is passed via two instance fields set by the dispatch callers.

**Files:**
- Modify: `src/weapons/melee_weapon.gd:111-117`
- Modify: `src/weapons/ranged_weapon.gd:47-57`
- Modify: `src/weapons/advanced_melee_weapon.gd`
- Test: `tests/unit/test_modifiers.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_modifiers.gd`:

```gdscript
# Advanced melee weapon that skips terrain/visual side-effects so _play_move
# can run headless; the base _play_move (with notify_attack) is NOT overridden.
class _NoHitAdvanced extends AdvancedMeleeWeapon:
	func _setup_moves() -> void:
		combo_mode = ComboMode.TAP_CHAIN
		combo_reset_time = 0.5
		light_moves = [_slash(), _slash(), _thrust()]
	func _apply_move_hit(_move, _user, _pos, _dir) -> void:
		pass
	func _start_move_anim(_move, _dir) -> void:
		pass


func test_advanced_play_move_notifies_per_step() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var user: Node2D = Node2D.new()
	parent.add_child(user)
	var w := _NoHitAdvanced.new()
	w.weapon_reach = 30.0
	w.arc_angle = PI / 2.0
	w.cooldown = 0.0
	var m := _RecordMod.new()
	w.modifiers = [m, null, null]
	w.on_press(user)  # step 0
	w.on_press(user)  # step 1
	assert_int(m.attacks).is_equal(2)
	assert_that(m.last_ctx["charged"]).is_false()
```

- [ ] **Step 2: Run test to verify it fails**

Run the modifier test suite.
Expected: FAIL — `m.attacks` is 0 (no notify wired into `_play_move`).

- [ ] **Step 3: Wire the call sites**

In `src/weapons/melee_weapon.gd`, `_use_impl` — add the notify after `_hit_attackables`:

```gdscript
func _use_impl(user: Node) -> void:
	_current_user = user
	var pos: Vector2 = user.global_position
	var direction := _get_facing_direction(user)
	_start_swing(direction)
	_carve_and_push(pos, direction, weapon_reach, arc_angle, damage)
	_hit_attackables(user, pos, direction, weapon_reach, arc_angle, 1.0, false, false)
	notify_attack(user, {
		"direction": direction,
		"origin": pos,
		"charged": false,
		"charge_ratio": 0.0,
	})
```

In `src/weapons/ranged_weapon.gd`, `_use_impl` — add the notify after the spawn loop:

```gdscript
func _use_impl(user: Node) -> void:
	var direction := _get_facing_direction(user)
	var base_angle := direction.angle()
	var half_spread := deg_to_rad(spread_angle) / 2.0

	for i in range(projectile_count):
		var angle_offset: float = 0.0
		if projectile_count > 1:
			angle_offset = lerpf(-half_spread, half_spread, float(i) / float(projectile_count - 1))
		var proj_dir := Vector2(cos(base_angle + angle_offset), sin(base_angle + angle_offset))
		_spawn_projectile(user, proj_dir)

	notify_attack(user, {
		"direction": direction,
		"origin": user.global_position,
		"charged": false,
		"charge_ratio": 0.0,
	})
```

In `src/weapons/advanced_melee_weapon.gd`:

Add two instance fields near the other state vars (after `var _active_move: Move = null`):

```gdscript
var _active_move: Move = null
var _attack_charged: bool = false
var _attack_charge_ratio: float = 0.0
```

In `_do_light_attack`, set the fields at the top (light attacks are never charged):

```gdscript
func _do_light_attack(user: Node) -> void:
	_attack_charged = false
	_attack_charge_ratio = 0.0
	if combo_mode == ComboMode.AUTO_FLURRY:
		_start_flurry(light_moves.duplicate(), user)
		return
```

In `_do_charged_attack`, set the fields at the top:

```gdscript
func _do_charged_attack(user: Node, ratio: float) -> void:
	_attack_charged = true
	_attack_charge_ratio = ratio
	if charged_moves.is_empty():
		return
```

In `_play_move`, after `_start_move_anim`, emit the notification (this runs for every combo step, flurry step, and charged move, and reads the fields set above). `_play_move` already computed `pos` and `direction` locally — reuse them:

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
	notify_attack(user, {
		"direction": direction,
		"origin": pos,
		"charged": _attack_charged,
		"charge_ratio": _attack_charge_ratio,
	})
```

Leave `_apply_move_hit` unchanged. Putting the notify in `_play_move` (which the test probe does **not** override) means the `_NoHitAdvanced` probe — which overrides only `_apply_move_hit` and `_start_move_anim` to skip terrain/visuals — still runs the real notify dispatch. The existing combo-test probes in `test_advanced_melee_combo.gd` override `_play_move` entirely, so they bypass notify (they don't test modifiers) and remain unaffected.

- [ ] **Step 4: Run test to verify it passes**

Run the modifier test suite.
Expected: PASS — `m.attacks == 2`.

- [ ] **Step 5: Run the regression suite**

Run the Regression suite (see Conventions). Expected: PASS (combo/charge/ranged tests unaffected — `_play_move` signature unchanged).

- [ ] **Step 6: Commit**

```bash
git add src/weapons/melee_weapon.gd src/weapons/ranged_weapon.gd src/weapons/advanced_melee_weapon.gd tests/unit/test_modifiers.gd
git commit -m "feat: emit notify_attack from melee/ranged/advanced attack paths"
```

---

### Task 4: `ModifierProjectile` spawn helper

**Files:**
- Create: `src/weapons/modifiers/modifier_projectile.gd`
- Test: `tests/unit/test_modifiers.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_modifiers.gd`:

```gdscript
func _count_projectiles(parent: Node) -> int:
	var n := 0
	for c in parent.get_children():
		if c is Projectile:
			n += 1
	return n


func test_modifier_projectile_spawn_one_under_user_parent() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var user: Node2D = Node2D.new()
	parent.add_child(user)
	var p: Projectile = ModifierProjectile.spawn_one(user, Vector2.ZERO, Vector2.RIGHT, 4.0,
		{ "hit_status": "on_fire" })
	assert_that(p).is_not_null()
	assert_bool(p.get_parent() == parent).is_true()
	assert_that(p.damage).is_equal(4.0)
	assert_str(p.hit_status).is_equal("on_fire")
	assert_that(p.is_enemy_projectile).is_false()


func test_modifier_projectile_spawn_fan_count() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var user: Node2D = Node2D.new()
	parent.add_child(user)
	ModifierProjectile.spawn_fan(user, Vector2.ZERO, Vector2.RIGHT, 2.0, 5, 30.0, {})
	assert_int(_count_projectiles(parent)).is_equal(5)


func test_modifier_projectile_fan_makes_fresh_behaviors() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var user: Node2D = Node2D.new()
	parent.add_child(user)
	ModifierProjectile.spawn_fan(user, Vector2.ZERO, Vector2.RIGHT, 3.0, 3, 20.0,
		{ "make_behaviors": func() -> Array: return [BounceBehavior.new()] })
	var seen: Array = []
	for c in parent.get_children():
		if c is Projectile:
			assert_int(c.behaviors.size()).is_equal(1)
			assert_that(c.behaviors[0] is BounceBehavior).is_true()
			assert_that(seen.has(c.behaviors[0])).is_false()  # distinct instance per projectile
			seen.append(c.behaviors[0])
```

- [ ] **Step 2: Run test to verify it fails**

Run the modifier test suite.
Expected: FAIL — `ModifierProjectile` is an unknown identifier.

- [ ] **Step 3: Implement the helper**

Create `src/weapons/modifiers/modifier_projectile.gd`:

```gdscript
class_name ModifierProjectile
extends RefCounted

# Shared projectile-spawn recipe for modifiers. Factors out the configuration
# duplicated between RangedWeapon._spawn_projectile and the spawn console command.

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
const DEFAULT_TEXTURE := preload("res://textures/wall.png")
const DEFAULT_SPEED := 140.0
const DEFAULT_LIFETIME := 1.5

# opts (all optional): speed, lifetime, hit_status (String), tint (Color),
#   texture (Texture2D), behaviors (Array — used by spawn_one).
static func spawn_one(user: Node, origin: Vector2, direction: Vector2, damage: float,
		opts: Dictionary = {}) -> Projectile:
	var parent := _resolve_parent(user)
	if parent == null:
		return null
	var proj: Projectile = PROJECTILE_SCENE.instantiate()
	proj.direction = direction.normalized()
	proj.damage = damage
	proj.speed = opts.get("speed", DEFAULT_SPEED)
	proj.lifetime = opts.get("lifetime", DEFAULT_LIFETIME)
	proj.hit_status = opts.get("hit_status", "")
	proj.source_node = user
	proj.is_enemy_projectile = user.is_in_group("attackable") or user.is_in_group("cave_spawned")
	if opts.has("behaviors"):
		proj.behaviors = opts["behaviors"]
	var sprite: Sprite2D = proj.get_node_or_null("Sprite2D")
	if sprite != null:
		sprite.texture = opts.get("texture", DEFAULT_TEXTURE)
		if opts.has("tint"):
			sprite.modulate = opts["tint"]
	parent.add_child(proj)
	proj.global_position = origin
	return proj

# Distributes `count` projectiles evenly across `spread_deg` centered on base_dir.
# For per-projectile behaviors, pass opts["make_behaviors"]: a Callable returning
# a fresh Array each call (behaviors are stateful and must not be shared).
static func spawn_fan(user: Node, origin: Vector2, base_dir: Vector2, damage: float,
		count: int, spread_deg: float, opts: Dictionary = {}) -> void:
	var base_angle := base_dir.angle()
	var half := deg_to_rad(spread_deg) / 2.0
	for i in range(count):
		var t: float = 0.0 if count <= 1 else float(i) / float(count - 1)
		var angle := base_angle + lerpf(-half, half, t)
		var dir := Vector2(cos(angle), sin(angle))
		var per_opts := opts.duplicate()
		if opts.has("make_behaviors"):
			per_opts["behaviors"] = opts["make_behaviors"].call()
		spawn_one(user, origin, dir, damage, per_opts)

static func _resolve_parent(user: Node) -> Node:
	if user == null:
		return null
	var tree := user.get_tree()
	if tree != null:
		var wm := tree.get_first_node_in_group("world_manager")
		if wm != null and wm.has_method("get_chunk_container"):
			var container = wm.get_chunk_container()
			if container != null:
				return container
	return user.get_parent()
```

- [ ] **Step 4: Run test to verify it passes**

Run the modifier test suite.
Expected: PASS (all three new tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/modifiers/modifier_projectile.gd tests/unit/test_modifiers.gd
git commit -m "feat: ModifierProjectile spawn helper (one + fan)"
```

---

### Task 5: `ProjectileModifier` cadence base

**Files:**
- Create: `src/weapons/modifiers/projectile_modifier.gd`
- Test: `tests/unit/test_modifiers.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_modifiers.gd`:

```gdscript
# Counts _fire calls without spawning anything.
class _CountingMod extends ProjectileModifier:
	var fires: int = 0
	func _fire(_weapon, _user, _ctx) -> void:
		fires += 1


func test_cadence_every_hit_by_default() -> void:
	var m := _CountingMod.new()
	for i in range(4):
		m.on_attack(null, null, {})
	assert_int(m.fires).is_equal(4)


func test_cadence_period_three_fire_on_zero_and_one() -> void:
	var m := _CountingMod.new()
	m.period = 3
	m.fire_on = [0, 1]
	# positions across 5 calls: 0,1,2,0,1 -> fire on 0,1,_,0,1 = 4 fires
	for i in range(5):
		m.on_attack(null, null, {})
	assert_int(m.fires).is_equal(4)


func test_cadence_period_three_fire_on_last_only() -> void:
	var m := _CountingMod.new()
	m.period = 3
	m.fire_on = [2]
	# positions across 6 calls: 0,1,2,0,1,2 -> fire on the two 2s = 2 fires
	for i in range(6):
		m.on_attack(null, null, {})
	assert_int(m.fires).is_equal(2)
```

- [ ] **Step 2: Run test to verify it fails**

Run the modifier test suite.
Expected: FAIL — `ProjectileModifier` is an unknown identifier.

- [ ] **Step 3: Implement the base class**

Create `src/weapons/modifiers/projectile_modifier.gd`:

```gdscript
class_name ProjectileModifier
extends Modifier

# Fires on a self-counted cadence: every `period` hits, on the cycle positions
# listed in `fire_on` (0-indexed). The counter runs continuously with no idle
# reset, so firing never depends on the weapon's combo state.

var period: int = 1
var fire_on: Array = [0]
var _hits: int = 0


func on_attack(weapon: Weapon, user: Node, ctx: Dictionary) -> void:
	var pos: int = _hits % period
	_hits += 1
	if pos in fire_on:
		_fire(weapon, user, ctx)


# Subclasses override to spawn their projectiles.
func _fire(_weapon: Weapon, _user: Node, _ctx: Dictionary) -> void:
	pass
```

- [ ] **Step 4: Run test to verify it passes**

Run the modifier test suite.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/modifiers/projectile_modifier.gd tests/unit/test_modifiers.gd
git commit -m "feat: ProjectileModifier cadence base (every-N-hits)"
```

---

### Task 6: Group A — swing-triggered modifiers (every hit)

`fireball_fan`, `icicle_volley`, `gleaming_projectile`, `green_crescent`.

**Files:**
- Create: `src/weapons/modifiers/fireball_fan_modifier.gd`
- Create: `src/weapons/modifiers/icicle_volley_modifier.gd`
- Create: `src/weapons/modifiers/gleaming_projectile_modifier.gd`
- Create: `src/weapons/modifiers/green_crescent_modifier.gd`
- Test: `tests/unit/test_modifiers.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_modifiers.gd`:

```gdscript
func _spawn_parent_and_user() -> Array:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var user: Node2D = Node2D.new()
	parent.add_child(user)
	return [parent, user]

func _ctx(charged: bool = false, ratio: float = 0.0) -> Dictionary:
	return { "direction": Vector2.RIGHT, "origin": Vector2.ZERO, "charged": charged, "charge_ratio": ratio }


func test_fireball_fan_spawns_five_burning() -> void:
	var pu := _spawn_parent_and_user()
	FireballFanModifier.new().on_attack(null, pu[1], _ctx())
	assert_int(_count_projectiles(pu[0])).is_equal(5)
	for c in pu[0].get_children():
		if c is Projectile:
			assert_str(c.hit_status).is_equal("on_fire")


func test_icicle_volley_spawns_five_chilly() -> void:
	var pu := _spawn_parent_and_user()
	IcicleVolleyModifier.new().on_attack(null, pu[1], _ctx())
	assert_int(_count_projectiles(pu[0])).is_equal(5)
	for c in pu[0].get_children():
		if c is Projectile:
			assert_str(c.hit_status).is_equal("chilly")


func test_gleaming_projectile_has_clear_behavior() -> void:
	var pu := _spawn_parent_and_user()
	GleamingProjectileModifier.new().on_attack(null, pu[1], _ctx())
	assert_int(_count_projectiles(pu[0])).is_equal(1)
	for c in pu[0].get_children():
		if c is Projectile:
			assert_that(c.behaviors[0] is ClearBulletsBehavior).is_true()


func test_green_crescent_has_penetrate_behavior() -> void:
	var pu := _spawn_parent_and_user()
	GreenCrescentModifier.new().on_attack(null, pu[1], _ctx())
	assert_int(_count_projectiles(pu[0])).is_equal(1)
	for c in pu[0].get_children():
		if c is Projectile:
			assert_that(c.behaviors[0] is PenetrateBehavior).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run the modifier test suite.
Expected: FAIL — the four modifier classes are unknown identifiers.

- [ ] **Step 3: Implement the four modifiers**

Create `src/weapons/modifiers/fireball_fan_modifier.gd`:

```gdscript
class_name FireballFanModifier
extends ProjectileModifier

func _init() -> void:
	name = "Fireball Fan"
	description = "Every swing looses a fan of five fireballs."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_fan(user, ctx["origin"], ctx["direction"], 2.0, 5, 30.0,
		{ "hit_status": "on_fire", "tint": Color(1.0, 0.5, 0.1) })
```

Create `src/weapons/modifiers/icicle_volley_modifier.gd`:

```gdscript
class_name IcicleVolleyModifier
extends ProjectileModifier

func _init() -> void:
	name = "Icicle Volley"
	description = "Every strike fires five icicles."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_fan(user, ctx["origin"], ctx["direction"], 2.0, 5, 30.0,
		{ "hit_status": "chilly", "tint": Color(0.5, 0.8, 1.0) })
```

Create `src/weapons/modifiers/gleaming_projectile_modifier.gd`:

```gdscript
class_name GleamingProjectileModifier
extends ProjectileModifier

func _init() -> void:
	name = "Gleaming Projectile"
	description = "Every swing releases a gleaming projectile that shatters incoming enemy bullets clearing a path through gunfire."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_one(user, ctx["origin"], ctx["direction"], 3.0,
		{ "behaviors": [ClearBulletsBehavior.new()], "tint": Color(1.0, 1.0, 0.7) })
```

Create `src/weapons/modifiers/green_crescent_modifier.gd`:

```gdscript
class_name GreenCrescentModifier
extends ProjectileModifier

func _init() -> void:
	name = "Green Crescent"
	description = "Spin slash hurls a crescent of green energy that cuts through enemies in its path."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_one(user, ctx["origin"], ctx["direction"], 5.0,
		{ "behaviors": [PenetrateBehavior.new()], "tint": Color(0.4, 1.0, 0.4) })
```

- [ ] **Step 4: Run test to verify it passes**

Run the modifier test suite.
Expected: PASS (four new tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/modifiers/fireball_fan_modifier.gd src/weapons/modifiers/icicle_volley_modifier.gd src/weapons/modifiers/gleaming_projectile_modifier.gd src/weapons/modifiers/green_crescent_modifier.gd tests/unit/test_modifiers.gd
git commit -m "feat: Group A swing-triggered projectile modifiers"
```

---

### Task 7: Group B — cadence-gated combo modifiers

`arc_volley` (period 3, fire_on [0,1]), `triangular_volley` (period 3, fire_on [2]), `splitting_rounds` (period 2, fire_on [1]), `bouncing_bullets` (period 3, fire_on [2]).

**Files:**
- Create: `src/weapons/modifiers/arc_volley_modifier.gd`
- Create: `src/weapons/modifiers/triangular_volley_modifier.gd`
- Create: `src/weapons/modifiers/splitting_rounds_modifier.gd`
- Create: `src/weapons/modifiers/bouncing_bullets_modifier.gd`
- Test: `tests/unit/test_modifiers.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_modifiers.gd`:

```gdscript
func test_arc_volley_fires_seven_on_first_two_of_three() -> void:
	var pu := _spawn_parent_and_user()
	var m := ArcVolleyModifier.new()
	m.on_attack(null, pu[1], _ctx())  # pos 0 -> fire 7
	assert_int(_count_projectiles(pu[0])).is_equal(7)
	m.on_attack(null, pu[1], _ctx())  # pos 1 -> fire 7
	assert_int(_count_projectiles(pu[0])).is_equal(14)
	m.on_attack(null, pu[1], _ctx())  # pos 2 -> none
	assert_int(_count_projectiles(pu[0])).is_equal(14)
	m.on_attack(null, pu[1], _ctx())  # pos 0 -> fire 7
	assert_int(_count_projectiles(pu[0])).is_equal(21)


func test_triangular_volley_fires_thirteen_on_third() -> void:
	var pu := _spawn_parent_and_user()
	var m := TriangularVolleyModifier.new()
	m.on_attack(null, pu[1], _ctx())  # pos 0 -> none
	m.on_attack(null, pu[1], _ctx())  # pos 1 -> none
	assert_int(_count_projectiles(pu[0])).is_equal(0)
	m.on_attack(null, pu[1], _ctx())  # pos 2 -> fire 13
	assert_int(_count_projectiles(pu[0])).is_equal(13)


func test_splitting_rounds_fires_three_with_split_on_second() -> void:
	var pu := _spawn_parent_and_user()
	var m := SplittingRoundsModifier.new()
	m.on_attack(null, pu[1], _ctx())  # pos 0 -> none
	assert_int(_count_projectiles(pu[0])).is_equal(0)
	m.on_attack(null, pu[1], _ctx())  # pos 1 -> fire 3
	assert_int(_count_projectiles(pu[0])).is_equal(3)
	for c in pu[0].get_children():
		if c is Projectile:
			assert_that(c.behaviors[0] is SplitBehavior).is_true()


func test_bouncing_bullets_fires_four_with_bounce_on_third() -> void:
	var pu := _spawn_parent_and_user()
	var m := BouncingBulletsModifier.new()
	m.on_attack(null, pu[1], _ctx())  # pos 0
	m.on_attack(null, pu[1], _ctx())  # pos 1
	assert_int(_count_projectiles(pu[0])).is_equal(0)
	m.on_attack(null, pu[1], _ctx())  # pos 2 -> fire 4
	assert_int(_count_projectiles(pu[0])).is_equal(4)
	for c in pu[0].get_children():
		if c is Projectile:
			assert_that(c.behaviors[0] is BounceBehavior).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run the modifier test suite.
Expected: FAIL — the four classes are unknown identifiers.

- [ ] **Step 3: Implement the four modifiers**

Create `src/weapons/modifiers/arc_volley_modifier.gd`:

```gdscript
class_name ArcVolleyModifier
extends ProjectileModifier

func _init() -> void:
	name = "Arc Volley"
	description = "First two hits of a three-hit combo each fire seven projectiles."
	icon_texture = preload("res://textures/wall.png")
	period = 3
	fire_on = [0, 1]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_fan(user, ctx["origin"], ctx["direction"], 1.5, 7, 45.0,
		{ "tint": Color(0.9, 0.9, 1.0) })
```

Create `src/weapons/modifiers/triangular_volley_modifier.gd`:

```gdscript
class_name TriangularVolleyModifier
extends ProjectileModifier

func _init() -> void:
	name = "Triangular Volley"
	description = "Third hit of a three-hit combo sprays thirteen bolts in a triangular volley."
	icon_texture = preload("res://textures/wall.png")
	period = 3
	fire_on = [2]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_fan(user, ctx["origin"], ctx["direction"], 1.5, 13, 60.0,
		{ "tint": Color(0.8, 0.9, 1.0) })
```

Create `src/weapons/modifiers/splitting_rounds_modifier.gd`:

```gdscript
class_name SplittingRoundsModifier
extends ProjectileModifier

func _init() -> void:
	name = "Splitting Rounds"
	description = "Follow-up thrust scatters three rounds that split into four shards on impact."
	icon_texture = preload("res://textures/wall.png")
	period = 2
	fire_on = [1]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_fan(user, ctx["origin"], ctx["direction"], 3.0, 3, 20.0,
		{ "tint": Color(1.0, 0.85, 0.4), "make_behaviors": func() -> Array: return [SplitBehavior.new()] })
```

Create `src/weapons/modifiers/bouncing_bullets_modifier.gd`:

```gdscript
class_name BouncingBulletsModifier
extends ProjectileModifier

func _init() -> void:
	name = "Bouncing Bullets"
	description = "Forward spin summons a skyward shockwave that looses four bouncing bullets."
	icon_texture = preload("res://textures/wall.png")
	period = 3
	fire_on = [2]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_fan(user, ctx["origin"], ctx["direction"], 3.0, 4, 40.0,
		{ "tint": Color(0.7, 0.95, 1.0), "make_behaviors": func() -> Array: return [BounceBehavior.new()] })
```

- [ ] **Step 4: Run test to verify it passes**

Run the modifier test suite.
Expected: PASS (four new tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/modifiers/arc_volley_modifier.gd src/weapons/modifiers/triangular_volley_modifier.gd src/weapons/modifiers/splitting_rounds_modifier.gd src/weapons/modifiers/bouncing_bullets_modifier.gd tests/unit/test_modifiers.gd
git commit -m "feat: Group B cadence-gated combo projectile modifiers"
```

---

### Task 8: Group C — `penetrating_shockwave` + `lightning_bolt`

Both override `on_attack` directly (no cadence). `penetrating_shockwave` fires only on a full-charge release; `lightning_bolt` rolls a chance, hits the nearest enemy in range, and applies `frozen` as the "stun".

**Files:**
- Create: `src/weapons/modifiers/penetrating_shockwave_modifier.gd`
- Create: `src/weapons/modifiers/lightning_bolt_modifier.gd`
- Test: `tests/unit/test_modifiers.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_modifiers.gd`:

```gdscript
func test_shockwave_fires_only_on_full_charge() -> void:
	var pu := _spawn_parent_and_user()
	var m := PenetratingShockwaveModifier.new()
	m.on_attack(null, pu[1], _ctx(false, 0.0))  # not charged
	assert_int(_count_projectiles(pu[0])).is_equal(0)
	m.on_attack(null, pu[1], _ctx(true, 0.5))   # partial charge
	assert_int(_count_projectiles(pu[0])).is_equal(0)
	m.on_attack(null, pu[1], _ctx(true, 1.0))   # full charge
	assert_int(_count_projectiles(pu[0])).is_equal(1)
	for c in pu[0].get_children():
		if c is Projectile:
			var has_pen := false
			var has_clear := false
			for b in c.behaviors:
				has_pen = has_pen or b is PenetrateBehavior
				has_clear = has_clear or b is ClearBulletsBehavior
			assert_bool(has_pen).is_true()
			assert_bool(has_clear).is_true()


func test_lightning_damages_nearest_and_applies_frozen() -> void:
	var pu := _spawn_parent_and_user()
	(pu[1] as Node2D).global_position = Vector2.ZERO
	var target := _StubTarget.new()
	pu[0].add_child(target)
	target.global_position = Vector2(20, 0)
	var m := LightningBoltModifier.new()
	m.proc_chance = 1.0  # always fire
	m.on_attack(null, pu[1], _ctx())
	assert_int(target.hits.size()).is_equal(1)
	var sc: StatusComponent = target.get_node("StatusComponent")
	assert_that(sc.get_stain("frozen")).is_greater(0.0)


func test_lightning_no_proc_does_nothing() -> void:
	var pu := _spawn_parent_and_user()
	var target := _StubTarget.new()
	pu[0].add_child(target)
	target.global_position = Vector2(20, 0)
	var m := LightningBoltModifier.new()
	m.proc_chance = 0.0  # never fire
	m.on_attack(null, pu[1], _ctx())
	assert_int(target.hits.size()).is_equal(0)
```

- [ ] **Step 2: Run test to verify it fails**

Run the modifier test suite.
Expected: FAIL — the two classes are unknown identifiers.

- [ ] **Step 3: Implement the two modifiers**

Create `src/weapons/modifiers/penetrating_shockwave_modifier.gd`:

```gdscript
class_name PenetratingShockwaveModifier
extends Modifier

func _init() -> void:
	name = "Penetrating Shockwave"
	description = "Full charge fires a massive penetrating shockwave that deletes enemy projectiles as it travels."
	icon_texture = preload("res://textures/wall.png")

func on_attack(_weapon, user, ctx) -> void:
	if not ctx.get("charged", false):
		return
	if ctx.get("charge_ratio", 0.0) < 1.0:
		return
	ModifierProjectile.spawn_one(user, ctx["origin"], ctx["direction"], 8.0, {
		"behaviors": [PenetrateBehavior.new(), ClearBulletsBehavior.new()],
		"speed": 180.0,
		"lifetime": 2.5,
		"tint": Color(0.6, 0.4, 1.0),
	})
```

Create `src/weapons/modifiers/lightning_bolt_modifier.gd`:

```gdscript
class_name LightningBoltModifier
extends Modifier

const RANGE := 160.0
const DAMAGE := 6
const FROZEN_STAIN := 3.0

var proc_chance: float = 0.25

func _init() -> void:
	name = "Lightning Bolt"
	description = "Calls a bolt of lightning down onto a marked target with a chance to stun. Not triggered every attack."
	icon_texture = preload("res://textures/wall.png")

func on_attack(_weapon, user, _ctx) -> void:
	if randf() >= proc_chance:
		return
	var target := _nearest_target(user)
	if target == null:
		return
	if target.has_method("on_hit_impact"):
		var dir: Vector2 = target.global_position - user.global_position
		target.on_hit_impact(target.global_position, dir, DAMAGE)
	var sc = target.get_node_or_null("StatusComponent")
	if sc != null:
		sc.add_stain("frozen", FROZEN_STAIN)
	_play_fx(user, target.global_position)

func _nearest_target(user: Node) -> Node2D:
	var tree := user.get_tree()
	if tree == null:
		return null
	var best: Node2D = null
	var best_d := RANGE * RANGE
	for n in tree.get_nodes_in_group("attackable"):
		if n == user or not is_instance_valid(n) or not (n is Node2D):
			continue
		var d: float = (user as Node2D).global_position.distance_squared_to((n as Node2D).global_position)
		if d <= best_d:
			best_d = d
			best = n
	return best

func _play_fx(user: Node, pos: Vector2) -> void:
	var parent := user.get_parent()
	if parent == null:
		return
	var fx := Sprite2D.new()
	fx.texture = preload("res://textures/wall.png")
	fx.modulate = Color(0.8, 0.85, 1.0)
	parent.add_child(fx)
	fx.global_position = pos
	var tree := user.get_tree()
	if tree != null:
		tree.create_timer(0.15).timeout.connect(fx.queue_free)
```

> `randf() >= proc_chance`: with `proc_chance = 1.0` the roll (in `[0, 1)`) is essentially always `< 1.0`, so it always fires; with `proc_chance = 0.0` it never fires. This makes the chance testable without seeding RNG.

- [ ] **Step 4: Run test to verify it passes**

Run the modifier test suite.
Expected: PASS (three new tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/modifiers/penetrating_shockwave_modifier.gd src/weapons/modifiers/lightning_bolt_modifier.gd tests/unit/test_modifiers.gd
git commit -m "feat: penetrating_shockwave + lightning_bolt modifiers"
```

---

### Task 9: Move `lava_emitter` + register all modifiers in the registry

**Files:**
- Move: `src/weapons/lava_emitter_modifier.gd` → `src/weapons/modifiers/lava_emitter_modifier.gd` (+ `.uid`)
- Modify: `src/autoload/weapon_registry.gd`
- Test: `tests/unit/test_modifiers.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_modifiers.gd`:

```gdscript
func test_all_csv_modifiers_registered() -> void:
	var ids := [
		"lava_emitter", "fireball_fan", "icicle_volley", "gleaming_projectile",
		"green_crescent", "arc_volley", "triangular_volley", "splitting_rounds",
		"bouncing_bullets", "penetrating_shockwave", "lightning_bolt",
	]
	for id in ids:
		assert_bool(WeaponRegistry.modifier_scripts.has(id)).is_true()


func test_make_modifier_overlays_csv_data() -> void:
	var m: Modifier = WeaponRegistry._make_modifier("fireball_fan")
	assert_that(m).is_not_null()
	assert_str(m.name).is_equal("Fireball Fan")
```

- [ ] **Step 2: Run test to verify it fails**

Run the modifier test suite.
Expected: FAIL — only `lava_emitter` is in `modifier_scripts`; the other ten ids are missing.

- [ ] **Step 3: Move the lava_emitter file**

```bash
git mv src/weapons/lava_emitter_modifier.gd src/weapons/modifiers/lava_emitter_modifier.gd
git mv src/weapons/lava_emitter_modifier.gd.uid src/weapons/modifiers/lava_emitter_modifier.gd.uid
```

Verify no other source references the old path:

```bash
grep -rn "weapons/lava_emitter_modifier" src tests
```

Expected: only matches inside `src/autoload/weapon_registry.gd` (fixed next).

- [ ] **Step 4: Update the registry**

In `src/autoload/weapon_registry.gd`, replace the single `modifier_scripts["lava_emitter"]` line in `_ready` with the full set (new path for lava_emitter):

```gdscript
	modifier_scripts["lava_emitter"] = preload("res://src/weapons/modifiers/lava_emitter_modifier.gd")
	modifier_scripts["fireball_fan"] = preload("res://src/weapons/modifiers/fireball_fan_modifier.gd")
	modifier_scripts["icicle_volley"] = preload("res://src/weapons/modifiers/icicle_volley_modifier.gd")
	modifier_scripts["gleaming_projectile"] = preload("res://src/weapons/modifiers/gleaming_projectile_modifier.gd")
	modifier_scripts["green_crescent"] = preload("res://src/weapons/modifiers/green_crescent_modifier.gd")
	modifier_scripts["arc_volley"] = preload("res://src/weapons/modifiers/arc_volley_modifier.gd")
	modifier_scripts["triangular_volley"] = preload("res://src/weapons/modifiers/triangular_volley_modifier.gd")
	modifier_scripts["splitting_rounds"] = preload("res://src/weapons/modifiers/splitting_rounds_modifier.gd")
	modifier_scripts["bouncing_bullets"] = preload("res://src/weapons/modifiers/bouncing_bullets_modifier.gd")
	modifier_scripts["penetrating_shockwave"] = preload("res://src/weapons/modifiers/penetrating_shockwave_modifier.gd")
	modifier_scripts["lightning_bolt"] = preload("res://src/weapons/modifiers/lightning_bolt_modifier.gd")
```

Replace the body of `_populate_modifier_tiers` to assign drop tiers from `modifier_scripts` (uses the new lava_emitter path):

```gdscript
func _populate_modifier_tiers() -> void:
	modifier_tiers[DropTable.ItemTier.COMMON] = [
		ModifierDropEntry.new(modifier_scripts["lava_emitter"], 1.0),
		ModifierDropEntry.new(modifier_scripts["fireball_fan"], 1.0),
		ModifierDropEntry.new(modifier_scripts["icicle_volley"], 1.0),
	]
	modifier_tiers[DropTable.ItemTier.UNCOMMON] = [
		ModifierDropEntry.new(modifier_scripts["gleaming_projectile"], 1.0),
		ModifierDropEntry.new(modifier_scripts["green_crescent"], 1.0),
		ModifierDropEntry.new(modifier_scripts["splitting_rounds"], 1.0),
		ModifierDropEntry.new(modifier_scripts["bouncing_bullets"], 1.0),
	]
	modifier_tiers[DropTable.ItemTier.RARE] = [
		ModifierDropEntry.new(modifier_scripts["arc_volley"], 1.0),
		ModifierDropEntry.new(modifier_scripts["triangular_volley"], 1.0),
		ModifierDropEntry.new(modifier_scripts["penetrating_shockwave"], 1.0),
		ModifierDropEntry.new(modifier_scripts["lightning_bolt"], 1.0),
	]
```

- [ ] **Step 5: Run test to verify it passes**

Run the modifier test suite.
Expected: PASS (both new tests).

- [ ] **Step 6: Run regression + registry pool tests**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode \
  -a res://tests/unit/test_weapon_registry_pools.gd \
  -a res://tests/unit/test_shop_modifier_drop.gd \
  -a res://tests/unit/test_weapon_resources.gd
```

Expected: PASS (the moved file and new tiers don't break registry/drop tests). If `test_shop_modifier_drop.gd` or another test referenced the old lava_emitter path, update that reference to `res://src/weapons/modifiers/lava_emitter_modifier.gd` and re-run.

- [ ] **Step 7: Commit**

```bash
git add src/weapons/modifiers/lava_emitter_modifier.gd src/weapons/modifiers/lava_emitter_modifier.gd.uid src/autoload/weapon_registry.gd tests/unit/test_modifiers.gd
git commit -m "feat: register all modifiers + relocate lava_emitter into modifiers/"
```

---

### Task 10: Mark Sub-project 4 done + full verification

**Files:**
- Modify: `docs/design_docs/implementation_todo.md:156-161`

- [ ] **Step 1: Run the full modifier + regression suites**

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode \
  -a res://tests/unit/test_modifiers.gd \
  -a res://tests/unit/test_projectile.gd \
  -a res://tests/unit/test_projectile_behaviors.gd \
  -a res://tests/unit/test_advanced_melee_combo.gd \
  -a res://tests/unit/test_advanced_melee_charge.gd \
  -a res://tests/unit/test_ranged_weapon.gd \
  -a res://tests/unit/test_weapon_registry_pools.gd
```

Expected: PASS, no failures/errors.

- [ ] **Step 2: Manual smoke test (optional but recommended)**

Launch the game, open the console, run e.g. `spawn mod fireball_fan`, pick it up onto a weapon, and attack — confirm a fan of fireballs spawns. Try `spawn mod bouncing_bullets` on a spin/combo weapon and `spawn mod penetrating_shockwave` on a chargeable weapon (e.g. `executioner`).

- [ ] **Step 3: Mark the todo rows done**

In `docs/design_docs/implementation_todo.md`, change the three Sub-project 4 rows' `Done` column from blank to `x`:

```markdown
| x | P2 | Medium | Swing-triggered projectile modifiers | fireball_fan, icicle_volley, gleaming_projectile, green_crescent |
| x | P2 | Medium | Combo-step modifiers | arc_volley, triangular_volley, splitting_rounds, bouncing_bullets |
| x | P2 | Medium | Charge & chance modifiers | penetrating_shockwave, lightning_bolt |
```

- [ ] **Step 4: Commit**

```bash
git add docs/design_docs/implementation_todo.md
git commit -m "docs: mark Phase 7 sub-project 4 (modifiers) done"
```

---

## Self-Review notes

- **Spec coverage:** on_attack hook (Task 2) + call sites (Task 3); ProjectileModifier cadence (Task 5); ModifierProjectile helper (Task 4); Projectile.hit_status (Task 1); all ten modifiers (Tasks 6–8); registration + tiers + lava_emitter move (Task 9); `spawn mod <id>` is auto-registered by the existing `spawn_command` loop over `modifier_scripts` (no edit needed — verified in Task 10 smoke test); todo marked (Task 10). All spec sections map to a task.
- **No combo query:** firing decisions read only the per-modifier counter (`_hits`) or `ctx` (`charged`/`charge_ratio`) — never weapon combo state, per the design.
- **Type consistency:** `ModifierProjectile.spawn_one/spawn_fan`, `ProjectileModifier.period/fire_on/_fire`, `Projectile.hit_status`, `Weapon.notify_attack`, `Modifier.on_attack`, and `LightningBoltModifier.proc_chance` are used identically across tasks.
