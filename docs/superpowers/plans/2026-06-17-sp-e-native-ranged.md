# SP-E Native Ranged Mechanics + 10 Ranged Weapons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire all 10 SP-E ranged weapons to drop and function by adding the small shared plumbing (charge-to-fire base, impact-splat + lightning-chain behaviors, projectile `hit_status`, an `on_expire` hook) their native identities hang off.

**Architecture:** `RangedWeapon` already exposes `_configure()` (stat defaults) and `_make_behaviors()` (per-shot `ProjectileBehavior` list) override seams; SP-C already shipped `Penetrate`/`Return`/`Homing` behaviors. Each of the 8 new archetypes is a thin `RangedWeapon` subclass overriding those seams. Two new behaviors (`SplatBehavior`, `ChainBehavior`), one new base (`ChargedRangedWeapon`), a projectile `on_expire` hook, and a `hit_status` CSV column complete it. Two weapons (`scatter_blunderbuss`, `frost_repeater`) stay data-only on the `ranged` archetype.

**Tech Stack:** Godot 4 / GDScript, gdUnit4 tests (`tests/unit/`).

---

## Conventions (read once)

**Run the full unit suite** (used at most task boundaries):

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit
```

**Run a single test file:**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/<file>.gd
```

**Deviation from spec §6 (intentional):** archetype stat values (`projectile_speed`/`lifetime`/`spread`/`count`) are set in each weapon's `_configure()` rather than filled into CSV cells. This matches every existing ranged archetype (`sniper_weapon.gd`, `fan_weapon.gd` set their own stats; their CSV stat cells are blank) and `_apply_tuning()` only overrides when a CSV cell is non-empty, so blank cells keep the `_configure()` defaults. The CSV gets exactly one new column: `hit_status`.

**Spec reconciliation — arc_railgun:** because a partial charge fizzles (confirmed design decision), the rail only ever fires at full charge, so there is no variable "charge depth." The rail is a fixed deep-pierce shot; the charge *gate* (must hold to full to fire at all) is the mechanic. No ratio-scaling code.

---

## File Structure

**New files:**
- `src/weapons/charged_ranged_weapon.gd` — `ChargedRangedWeapon`: hold-to-full-charge-then-fire base for ranged.
- `src/weapons/projectile_behaviors/splat_behavior.gd` — `SplatBehavior`: spawns a material pool on impact/expiry.
- `src/weapons/projectile_behaviors/chain_behavior.gd` — `ChainBehavior`: forks lightning foe-to-foe on enemy hit.
- `src/weapons/heavy_crossbow_weapon.gd`, `arc_railgun_weapon.gd`, `flame_lobber_weapon.gd`, `venom_spitter_weapon.gd`, `tesla_gun_weapon.gd`, `chakram_launcher_weapon.gd`, `seeker_launcher_weapon.gd`, `hailstorm_bow_weapon.gd` — the 8 archetype scripts.
- `tests/unit/test_on_expire_hook.gd`, `test_combat_util_nearest.gd`, `test_splat_behavior.gd`, `test_chain_behavior.gd`, `test_ranged_hit_status.gd`, `test_charged_ranged_weapon.gd`, `test_sp_e_weapons.gd`, `test_sp_e_weapons_build.gd` — tests.

**Modified files:**
- `src/weapons/projectile_behaviors/projectile_behavior.gd` — add `on_expire` virtual.
- `src/weapons/projectile.gd` — call `on_expire` before lifetime free.
- `src/weapons/combat_util.gd` — add `nearest_attackables` static helper.
- `src/weapons/ranged_weapon.gd` — `hit_status` field + set on spawn.
- `src/autoload/weapon_registry.gd` — register 8 archetypes; read `hit_status` in `_apply_tuning`.
- `docs/design_docs/weapons.csv` — add `hit_status` column; `freeze` for `frost_repeater`.
- `docs/design_docs/implementation_todo.md` — mark SP-E done.

---

### Task 1: `on_expire` hook on `ProjectileBehavior` + `Projectile`

**Files:**
- Modify: `src/weapons/projectile_behaviors/projectile_behavior.gd`
- Modify: `src/weapons/projectile.gd:36-40` (the lifetime branch in `_process`)
- Test: `tests/unit/test_on_expire_hook.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_on_expire_hook.gd`:

```gdscript
extends GdUnitTestSuite

class _ExpireRecorder extends ProjectileBehavior:
	var expired: int = 0
	func on_expire(_proj) -> void:
		expired += 1

func test_base_on_expire_is_noop() -> void:
	var b: ProjectileBehavior = ProjectileBehavior.new()
	var p: Projectile = auto_free(Projectile.new())
	b.on_expire(p)  # must not error

func test_projectile_calls_on_expire_at_lifetime_end() -> void:
	var b := _ExpireRecorder.new()
	var p: Projectile = auto_free(Projectile.new())
	p.behaviors = [b]
	p.lifetime = 0.1
	p._process(0.2)  # age exceeds lifetime -> expire
	assert_int(b.expired).is_equal(1)

func test_projectile_does_not_expire_before_lifetime() -> void:
	var b := _ExpireRecorder.new()
	var p: Projectile = auto_free(Projectile.new())
	p.behaviors = [b]
	p.lifetime = 10.0
	p._process(0.1)
	assert_int(b.expired).is_equal(0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_on_expire_hook.gd`
Expected: FAIL — `on_expire` not defined on `ProjectileBehavior` / not called.

- [ ] **Step 3: Add the virtual to `ProjectileBehavior`**

Append to `src/weapons/projectile_behaviors/projectile_behavior.gd`:

```gdscript
func on_expire(_proj) -> void:
	pass
```

- [ ] **Step 4: Call it before the lifetime free in `Projectile._process`**

In `src/weapons/projectile.gd`, change the lifetime branch (currently):

```gdscript
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
```

to:

```gdscript
	_age += delta
	if _age >= lifetime:
		for b in behaviors:
			b.on_expire(self)
		queue_free()
		return
```

- [ ] **Step 5: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add src/weapons/projectile_behaviors/projectile_behavior.gd src/weapons/projectile.gd tests/unit/test_on_expire_hook.gd
git commit -m "feat: add on_expire hook to projectile behaviors"
```

---

### Task 2: `CombatUtil.nearest_attackables` helper

**Files:**
- Modify: `src/weapons/combat_util.gd`
- Test: `tests/unit/test_combat_util_nearest.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_combat_util_nearest.gd`:

```gdscript
extends GdUnitTestSuite

func _enemy(at: Vector2) -> Node2D:
	var n: Node2D = auto_free(Node2D.new())
	n.add_to_group("attackable")
	add_child(n)
	n.global_position = at
	return n

func test_returns_nearest_within_range_sorted() -> void:
	var near := _enemy(Vector2(10, 0))
	var far := _enemy(Vector2(50, 0))
	var out := CombatUtil.nearest_attackables(get_tree(), Vector2.ZERO, [], 2, 100.0)
	assert_int(out.size()).is_equal(2)
	assert_object(out[0]).is_same(near)
	assert_object(out[1]).is_same(far)

func test_excludes_listed_nodes() -> void:
	var a := _enemy(Vector2(10, 0))
	var b := _enemy(Vector2(20, 0))
	var out := CombatUtil.nearest_attackables(get_tree(), Vector2.ZERO, [a], 5, 100.0)
	assert_int(out.size()).is_equal(1)
	assert_object(out[0]).is_same(b)

func test_drops_targets_out_of_range() -> void:
	_enemy(Vector2(500, 0))
	var out := CombatUtil.nearest_attackables(get_tree(), Vector2.ZERO, [], 5, 100.0)
	assert_int(out.size()).is_equal(0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_combat_util_nearest.gd`
Expected: FAIL — `nearest_attackables` not defined.

- [ ] **Step 3: Add the helper**

Append to `src/weapons/combat_util.gd`:

```gdscript
static func nearest_attackables(tree: SceneTree, from_pos: Vector2, exclude: Array,
		count: int, range_px: float) -> Array:
	if tree == null:
		return []
	var r2: float = range_px * range_px
	var candidates: Array = []
	for n in tree.get_nodes_in_group("attackable"):
		if not is_instance_valid(n) or not (n is Node2D) or exclude.has(n):
			continue
		var d: float = from_pos.distance_squared_to((n as Node2D).global_position)
		if d <= r2:
			candidates.append({ "node": n, "d": d })
	candidates.sort_custom(func(a, b): return a["d"] < b["d"])
	var out: Array = []
	for i in range(mini(count, candidates.size())):
		out.append(candidates[i]["node"])
	return out
```

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/combat_util.gd tests/unit/test_combat_util_nearest.gd
git commit -m "feat: add CombatUtil.nearest_attackables helper"
```

---

### Task 3: `SplatBehavior` (impact-material)

**Files:**
- Create: `src/weapons/projectile_behaviors/splat_behavior.gd`
- Test: `tests/unit/test_splat_behavior.gd`

`TerrainSurface.place_lava(pos, radius)` / `place_gas(pos, radius, density)` are static and need a live world, so the behavior exposes an injectable `place_sink: Callable` (mirrors `Projectile.solidity_oracle`) that tests stub.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_splat_behavior.gd`:

```gdscript
extends GdUnitTestSuite

func _proj() -> Projectile:
	var p: Projectile = auto_free(Projectile.new())
	p.global_position = Vector2(7, 3)
	return p

func test_splats_lava_on_terrain_hit() -> void:
	var calls: Array = []
	var b := SplatBehavior.new()
	b.material = "lava"
	b.radius = 6.0
	b.place_sink = func(mat, pos, rad, _dens): calls.append([mat, pos, rad])
	var keep := b.on_terrain_hit(_proj())
	assert_bool(keep).is_false()
	assert_int(calls.size()).is_equal(1)
	assert_str(calls[0][0]).is_equal("lava")
	assert_vector(calls[0][1]).is_equal(Vector2(7, 3))

func test_splats_on_enemy_hit() -> void:
	var calls: Array = []
	var b := SplatBehavior.new()
	b.material = "gas"
	b.place_sink = func(mat, _pos, _rad, _dens): calls.append(mat)
	var keep := b.on_enemy_hit(_proj(), null)
	assert_bool(keep).is_false()
	assert_int(calls.size()).is_equal(1)
	assert_str(calls[0]).is_equal("gas")

func test_splats_on_expire() -> void:
	var calls: Array = []
	var b := SplatBehavior.new()
	b.place_sink = func(_m, _p, _r, _d): calls.append(1)
	b.on_expire(_proj())
	assert_int(calls.size()).is_equal(1)

func test_done_guard_prevents_double_splat() -> void:
	var calls: Array = []
	var b := SplatBehavior.new()
	b.place_sink = func(_m, _p, _r, _d): calls.append(1)
	var p := _proj()
	b.on_enemy_hit(p, null)
	b.on_expire(p)  # must NOT splat again
	assert_int(calls.size()).is_equal(1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_splat_behavior.gd`
Expected: FAIL — `SplatBehavior` not defined.

- [ ] **Step 3: Create the behavior**

Create `src/weapons/projectile_behaviors/splat_behavior.gd`:

```gdscript
class_name SplatBehavior
extends ProjectileBehavior

var material: String = "lava"   # "lava" or "gas"
var radius: float = 6.0
var gas_density: int = 200
var place_sink: Callable = Callable()  # injectable for tests: (mat, pos, radius, density)

var _done: bool = false


func on_enemy_hit(proj, _target) -> bool:
	_splat(proj)
	return false  # die after delivering the splat


func on_terrain_hit(proj) -> bool:
	_splat(proj)
	return false  # let the projectile carve + die normally


func on_expire(proj) -> void:
	_splat(proj)


func _splat(proj) -> void:
	if _done:
		return
	_done = true
	var pos: Vector2 = proj.global_position if proj != null else Vector2.ZERO
	if place_sink.is_valid():
		place_sink.call(material, pos, radius, gas_density)
		return
	if material == "gas":
		TerrainSurface.place_gas(pos, radius, gas_density)
	else:
		TerrainSurface.place_lava(pos, radius)
```

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/projectile_behaviors/splat_behavior.gd tests/unit/test_splat_behavior.gd
git commit -m "feat: add SplatBehavior impact-material projectile behavior"
```

---

### Task 4: `ChainBehavior` (lightning fork)

**Files:**
- Create: `src/weapons/projectile_behaviors/chain_behavior.gd`
- Test: `tests/unit/test_chain_behavior.gd`

Reuses `CombatUtil.nearest_attackables` (Task 2) and `LightningArcFX.play(host, from, to, tint)`. Damage routes through `proj.source_weapon.resolve_hit(...)` so weapon crit/modifiers apply.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_chain_behavior.gd`:

```gdscript
extends GdUnitTestSuite

# Records every resolve_hit target.
class _RecWeapon extends Weapon:
	var hit_targets: Array = []
	func resolve_hit(_user, target, _dmg, _crit) -> void:
		hit_targets.append(target)

func _enemy(at: Vector2) -> Node2D:
	var n: Node2D = auto_free(Node2D.new())
	n.add_to_group("attackable")
	add_child(n)
	n.global_position = at
	return n

func _proj(weapon: Weapon) -> Projectile:
	var p: Projectile = auto_free(Projectile.new())
	add_child(p)
	p.global_position = Vector2.ZERO
	p.source_weapon = weapon
	p.source_node = null
	p.damage = 4.0
	return p

func test_forks_to_jumps_nearest_via_resolve_hit() -> void:
	var w := _RecWeapon.new()
	var first := _enemy(Vector2(10, 0))
	_enemy(Vector2(20, 0))
	_enemy(Vector2(30, 0))
	var p := _proj(w)
	var b := ChainBehavior.new()
	b.jumps = 3
	b.range_px = 200.0
	var keep := b.on_enemy_hit(p, first)
	assert_bool(keep).is_false()
	# 3 jumps to the other enemies; never re-hits `first`.
	assert_int(w.hit_targets.size()).is_equal(2)  # only 2 other enemies exist
	assert_array(w.hit_targets).not_contains([first])

func test_stops_when_no_unvisited_target() -> void:
	var w := _RecWeapon.new()
	var only := _enemy(Vector2(10, 0))
	var p := _proj(w)
	var b := ChainBehavior.new()
	b.jumps = 5
	b.range_px = 200.0
	b.on_enemy_hit(p, only)
	assert_int(w.hit_targets.size()).is_equal(0)  # no other enemies to jump to
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_chain_behavior.gd`
Expected: FAIL — `ChainBehavior` not defined.

- [ ] **Step 3: Create the behavior**

Create `src/weapons/projectile_behaviors/chain_behavior.gd`:

```gdscript
class_name ChainBehavior
extends ProjectileBehavior

const LIGHTNING_DURATION := 0.4
const TINT := Color(0.9, 0.95, 1.0)

var jumps: int = 3
var range_px: float = 160.0


func on_enemy_hit(proj, target) -> bool:
	var tree: SceneTree = proj.get_tree()
	if tree == null:
		return false
	var host: Node = _resolve_host(proj)
	var visited: Array = [proj.source_node, target]
	var from: Node2D = target as Node2D
	for _i in range(jumps):
		if from == null:
			break
		var nxt_list := CombatUtil.nearest_attackables(tree, from.global_position, visited, 1, range_px)
		if nxt_list.is_empty():
			break
		var nxt: Node2D = nxt_list[0]
		if proj.source_weapon != null:
			var is_crit: bool = randf() < clampf(proj.crit_chance, 0.0, 1.0)
			proj.source_weapon.resolve_hit(proj.source_node, nxt, proj.damage, is_crit)
		var sc = nxt.get_node_or_null("StatusComponent")
		if sc != null:
			sc.add_timed_status("lightning", LIGHTNING_DURATION)
		if host != null:
			LightningArcFX.play(host, from.global_position, nxt.global_position, TINT)
		visited.append(nxt)
		from = nxt
	return false  # bolt spent after delivering the chain


func _resolve_host(proj) -> Node:
	var tree: SceneTree = proj.get_tree()
	if tree != null:
		var wm := tree.get_first_node_in_group("world_manager")
		if wm != null and wm.has_method("get_chunk_container"):
			var c = wm.get_chunk_container()
			if c != null:
				return c
	return proj.get_parent()
```

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/projectile_behaviors/chain_behavior.gd tests/unit/test_chain_behavior.gd
git commit -m "feat: add ChainBehavior lightning-fork projectile behavior"
```

---

### Task 5: Projectile `hit_status` on `RangedWeapon` + registry tuning

**Files:**
- Modify: `src/weapons/ranged_weapon.gd` (add field; set in `_spawn_projectile`)
- Modify: `src/autoload/weapon_registry.gd:173-191` (RangedWeapon branch of `_apply_tuning`)
- Test: `tests/unit/test_ranged_hit_status.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_ranged_hit_status.gd`:

```gdscript
extends GdUnitTestSuite

func test_spawn_sets_hit_status_on_projectile() -> void:
	var w := RangedWeapon.new()
	w.hit_status = "freeze"
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)  # user.get_parent() == this suite (no world_manager in test)
	w._spawn_projectile(user, Vector2.RIGHT)
	await get_tree().process_frame
	var found: Projectile = null
	for c in get_children():
		if c is Projectile:
			found = c
	assert_object(found).is_not_null()
	if found != null:
		assert_str(found.hit_status).is_equal("freeze")
		found.queue_free()

func test_default_hit_status_blank() -> void:
	var w := RangedWeapon.new()
	assert_str(w.hit_status).is_equal("")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_ranged_hit_status.gd`
Expected: FAIL — `hit_status` not a property of `RangedWeapon`.

- [ ] **Step 3: Add the field to `RangedWeapon`**

In `src/weapons/ranged_weapon.gd`, after the `projectile_texture` export (line ~17), add:

```gdscript
@export var hit_status: String = ""
```

(`@export` is mandatory so `duplicate(true)` preserves it — see `[[weapon-csv-fields-must-be-export]]`.)

- [ ] **Step 4: Set it on the spawned projectile**

In `src/weapons/ranged_weapon.gd`, inside `_spawn_projectile`, after `proj.crit_status = crit_status` (line ~123), add:

```gdscript
	proj.hit_status = hit_status
```

- [ ] **Step 5: Read the column in the registry**

In `src/autoload/weapon_registry.gd`, inside the `elif weapon is RangedWeapon:` branch of `_apply_tuning` (after the `projectile_texture` block, ~line 191), add:

```gdscript
		var hs: String = row.get("hit_status", "")
		if hs != "":
			rw.hit_status = hs
```

- [ ] **Step 6: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
git add src/weapons/ranged_weapon.gd src/autoload/weapon_registry.gd tests/unit/test_ranged_hit_status.gd
git commit -m "feat: ranged weapon hit_status field + CSV tuning"
```

---

### Task 6: `ChargedRangedWeapon` base

**Files:**
- Create: `src/weapons/charged_ranged_weapon.gd`
- Test: `tests/unit/test_charged_ranged_weapon.gd`

Mirrors `AdvancedMeleeWeapon`'s charge controller for ranged. Uses `RangedWeapon.shot_sink` (an existing injectable `Callable` that `_spawn_projectile` calls instead of instancing a real projectile) so the test can count shots without a world.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_charged_ranged_weapon.gd`:

```gdscript
extends GdUnitTestSuite

func _weapon() -> ChargedRangedWeapon:
	var w := ChargedRangedWeapon.new()
	w.charge_time_full = 0.5
	w.cooldown = 1.0
	return w

func test_partial_charge_release_fires_nothing() -> void:
	var shots: Array = []
	var w := _weapon()
	w.shot_sink = func(_dir): shots.append(1)
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	w.on_press(user)
	w.tick(0.2)  # below charge_time_full
	w.on_release(user)
	assert_int(shots.size()).is_equal(0)

func test_full_charge_release_fires_once() -> void:
	var shots: Array = []
	var w := _weapon()
	w.shot_sink = func(_dir): shots.append(1)
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	w.on_press(user)
	w.tick(0.6)  # >= charge_time_full
	assert_float(w.get_charge_ratio()).is_equal_approx(1.0, 0.001)
	assert_bool(w.is_charging()).is_true()
	w.on_release(user)
	assert_int(shots.size()).is_equal(1)
	assert_bool(w.is_charging()).is_false()

func test_is_chargeable_true() -> void:
	assert_bool(_weapon().is_chargeable()).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_charged_ranged_weapon.gd`
Expected: FAIL — `ChargedRangedWeapon` not defined.

- [ ] **Step 3: Create the base**

Create `src/weapons/charged_ranged_weapon.gd`:

```gdscript
class_name ChargedRangedWeapon
extends RangedWeapon

@export var charge_time_full: float = 0.7

var _charge_time: float = 0.0
var _charging: bool = false
var _current_user: Node = null


func get_charge_ratio() -> float:
	return clampf(_charge_time / charge_time_full, 0.0, 1.0)


func is_chargeable() -> bool:
	return true


func is_charging() -> bool:
	return _charging


func on_press(user: Node) -> void:
	if not is_ready():
		return
	_current_user = user
	_charging = true
	_charge_time = 0.0


func on_release(user: Node) -> void:
	if not _charging:
		return
	_charging = false
	_current_user = user
	if get_charge_ratio() >= 1.0:
		_fire_charged(user)


func _fire_charged(user: Node) -> void:
	for m in modifiers:
		if m != null:
			m.on_use(self, user)
	_emit_shot(user, _get_facing_direction(user))
	_cooldown_timer = get_effective_stats()["cooldown"]


func _tick_impl(delta: float) -> void:
	super._tick_impl(delta)  # RangedWeapon burst ticking
	if _charging:
		_charge_time = minf(_charge_time + delta, charge_time_full)
```

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/charged_ranged_weapon.gd tests/unit/test_charged_ranged_weapon.gd
git commit -m "feat: add ChargedRangedWeapon hold-to-fire base"
```

---

### Task 7: Reuse-behavior weapons — heavy_crossbow, chakram_launcher, seeker_launcher

**Files:**
- Create: `src/weapons/heavy_crossbow_weapon.gd`, `src/weapons/chakram_launcher_weapon.gd`, `src/weapons/seeker_launcher_weapon.gd`
- Modify: `src/autoload/weapon_registry.gd:69` (register 3 archetypes)
- Test: `tests/unit/test_sp_e_weapons.gd` (created here; extended in later tasks)

Each folds one existing SP-C/sniper behavior into `_make_behaviors()`. `PenetrateBehavior` (Task-1 file already present) passes through all enemies, dies on terrain — exactly the pierce-line.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_sp_e_weapons.gd`:

```gdscript
extends GdUnitTestSuite

func test_heavy_crossbow_pierces_enemies() -> void:
	var w := HeavyCrossbowWeapon.new()
	var b: Array = w._make_behaviors()
	assert_int(b.size()).is_equal(1)
	assert_bool(b[0] is PenetrateBehavior).is_true()
	# PenetrateBehavior keeps the projectile alive through an enemy.
	var p: Projectile = auto_free(Projectile.new())
	p.is_enemy_projectile = false
	p.damage = 5.0
	p.behaviors = [b[0]]
	p._handle_hit(auto_free(Enemy.new()))
	assert_bool(is_instance_valid(p)).is_true()

func test_chakram_returns() -> void:
	var b: Array = ChakramLauncherWeapon.new()._make_behaviors()
	assert_int(b.size()).is_equal(1)
	assert_bool(b[0] is ReturnBehavior).is_true()

func test_seeker_homes() -> void:
	var b: Array = SeekerLauncherWeapon.new()._make_behaviors()
	assert_int(b.size()).is_equal(1)
	assert_bool(b[0] is HomingBehavior).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_sp_e_weapons.gd`
Expected: FAIL — weapon classes not defined.

- [ ] **Step 3: Create the three weapons**

Create `src/weapons/heavy_crossbow_weapon.gd`:

```gdscript
class_name HeavyCrossbowWeapon
extends RangedWeapon

func _configure() -> void:
	damage = 5.0
	cooldown = 1.2
	projectile_count = 1
	spread_angle = 0.0
	projectile_speed = 280.0
	projectile_lifetime = 2.0

func _make_behaviors() -> Array:
	return [PenetrateBehavior.new()]
```

Create `src/weapons/chakram_launcher_weapon.gd`:

```gdscript
class_name ChakramLauncherWeapon
extends RangedWeapon

func _configure() -> void:
	damage = 3.5
	cooldown = 1.2
	projectile_count = 1
	spread_angle = 0.0
	projectile_speed = 160.0
	projectile_lifetime = 2.0

func _make_behaviors() -> Array:
	var r := ReturnBehavior.new()
	r.out_time = 0.5
	return [r]
```

Create `src/weapons/seeker_launcher_weapon.gd`:

```gdscript
class_name SeekerLauncherWeapon
extends RangedWeapon

func _configure() -> void:
	damage = 4.0
	cooldown = 1.5
	projectile_count = 1
	spread_angle = 0.0
	projectile_speed = 140.0
	projectile_lifetime = 3.5

func _make_behaviors() -> Array:
	var h := HomingBehavior.new()
	h.turn_rate_rad = PI
	return [h]
```

- [ ] **Step 4: Register the three archetypes**

In `src/autoload/weapon_registry.gd`, after the `qinggang` weapon-script line (~line 61, before the SP-D block) add:

```gdscript
	weapon_scripts["heavy_crossbow"] = preload("res://src/weapons/heavy_crossbow_weapon.gd")
	weapon_scripts["chakram_launcher"] = preload("res://src/weapons/chakram_launcher_weapon.gd")
	weapon_scripts["seeker_launcher"] = preload("res://src/weapons/seeker_launcher_weapon.gd")
```

- [ ] **Step 5: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add src/weapons/heavy_crossbow_weapon.gd src/weapons/chakram_launcher_weapon.gd src/weapons/seeker_launcher_weapon.gd src/autoload/weapon_registry.gd tests/unit/test_sp_e_weapons.gd
git commit -m "feat: add heavy_crossbow, chakram_launcher, seeker_launcher weapons"
```

---

### Task 8: `arc_railgun` (charged pierce rail)

**Files:**
- Create: `src/weapons/arc_railgun_weapon.gd`
- Modify: `src/autoload/weapon_registry.gd` (register `arc_railgun`)
- Test: extend `tests/unit/test_sp_e_weapons.gd`

- [ ] **Step 1: Add the failing test**

Append to `tests/unit/test_sp_e_weapons.gd`:

```gdscript
func test_arc_railgun_is_charged_and_pierces() -> void:
	var w := ArcRailgunWeapon.new()
	assert_bool(w is ChargedRangedWeapon).is_true()
	assert_bool(w.is_chargeable()).is_true()
	var b: Array = w._make_behaviors()
	assert_int(b.size()).is_equal(1)
	assert_bool(b[0] is PenetrateBehavior).is_true()

func test_arc_railgun_only_fires_at_full_charge() -> void:
	var shots: Array = []
	var w := ArcRailgunWeapon.new()
	w.charge_time_full = 0.5
	w.shot_sink = func(_dir): shots.append(1)
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	w.on_press(user)
	w.tick(0.1)
	w.on_release(user)   # partial -> nothing
	assert_int(shots.size()).is_equal(0)
	w.on_press(user)
	w.tick(0.6)
	w.on_release(user)   # full -> one rail
	assert_int(shots.size()).is_equal(1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_sp_e_weapons.gd`
Expected: FAIL — `ArcRailgunWeapon` not defined.

- [ ] **Step 3: Create the weapon**

Create `src/weapons/arc_railgun_weapon.gd`:

```gdscript
class_name ArcRailgunWeapon
extends ChargedRangedWeapon

func _configure() -> void:
	damage = 8.0
	cooldown = 1.6
	charge_time_full = 0.7
	projectile_count = 1
	spread_angle = 0.0
	projectile_speed = 320.0
	projectile_lifetime = 2.0

func _make_behaviors() -> Array:
	return [PenetrateBehavior.new()]
```

- [ ] **Step 4: Register the archetype**

In `src/autoload/weapon_registry.gd`, alongside the Task-7 registrations, add:

```gdscript
	weapon_scripts["arc_railgun"] = preload("res://src/weapons/arc_railgun_weapon.gd")
```

- [ ] **Step 5: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (all `test_sp_e_weapons.gd` tests).

- [ ] **Step 6: Commit**

```bash
git add src/weapons/arc_railgun_weapon.gd src/autoload/weapon_registry.gd tests/unit/test_sp_e_weapons.gd
git commit -m "feat: add arc_railgun charged pierce-rail weapon"
```

---

### Task 9: `flame_lobber` + `venom_spitter` (splat weapons)

**Files:**
- Create: `src/weapons/flame_lobber_weapon.gd`, `src/weapons/venom_spitter_weapon.gd`
- Modify: `src/autoload/weapon_registry.gd` (register both)
- Test: extend `tests/unit/test_sp_e_weapons.gd`

- [ ] **Step 1: Add the failing test**

Append to `tests/unit/test_sp_e_weapons.gd`:

```gdscript
func test_flame_lobber_splats_lava() -> void:
	var b: Array = FlameLobberWeapon.new()._make_behaviors()
	assert_int(b.size()).is_equal(1)
	assert_bool(b[0] is SplatBehavior).is_true()
	assert_str((b[0] as SplatBehavior).material).is_equal("lava")

func test_venom_spitter_splats_gas() -> void:
	var b: Array = VenomSpitterWeapon.new()._make_behaviors()
	assert_int(b.size()).is_equal(1)
	assert_bool(b[0] is SplatBehavior).is_true()
	assert_str((b[0] as SplatBehavior).material).is_equal("gas")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_sp_e_weapons.gd`
Expected: FAIL — weapon classes not defined.

- [ ] **Step 3: Create the two weapons**

Create `src/weapons/flame_lobber_weapon.gd`:

```gdscript
class_name FlameLobberWeapon
extends RangedWeapon

func _configure() -> void:
	damage = 3.0
	cooldown = 1.5
	projectile_count = 1
	spread_angle = 0.0
	projectile_speed = 110.0
	projectile_lifetime = 0.6

func _make_behaviors() -> Array:
	var s := SplatBehavior.new()
	s.material = "lava"
	s.radius = 6.0
	return [s]
```

Create `src/weapons/venom_spitter_weapon.gd`:

```gdscript
class_name VenomSpitterWeapon
extends RangedWeapon

func _configure() -> void:
	damage = 2.5
	cooldown = 1.3
	projectile_count = 1
	spread_angle = 0.0
	projectile_speed = 120.0
	projectile_lifetime = 0.6

func _make_behaviors() -> Array:
	var s := SplatBehavior.new()
	s.material = "gas"
	s.radius = 6.0
	s.gas_density = 200
	return [s]
```

- [ ] **Step 4: Register both archetypes**

In `src/autoload/weapon_registry.gd`, alongside the prior registrations, add:

```gdscript
	weapon_scripts["flame_lobber"] = preload("res://src/weapons/flame_lobber_weapon.gd")
	weapon_scripts["venom_spitter"] = preload("res://src/weapons/venom_spitter_weapon.gd")
```

- [ ] **Step 5: Run test to verify it passes**

Run the Step 2 command. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/weapons/flame_lobber_weapon.gd src/weapons/venom_spitter_weapon.gd src/autoload/weapon_registry.gd tests/unit/test_sp_e_weapons.gd
git commit -m "feat: add flame_lobber and venom_spitter splat weapons"
```

---

### Task 10: `tesla_gun` (chain weapon)

**Files:**
- Create: `src/weapons/tesla_gun_weapon.gd`
- Modify: `src/autoload/weapon_registry.gd` (register `tesla_gun`)
- Test: extend `tests/unit/test_sp_e_weapons.gd`

- [ ] **Step 1: Add the failing test**

Append to `tests/unit/test_sp_e_weapons.gd`:

```gdscript
func test_tesla_gun_chains() -> void:
	var w := TeslaGunWeapon.new()
	var b: Array = w._make_behaviors()
	assert_int(b.size()).is_equal(1)
	assert_bool(b[0] is ChainBehavior).is_true()
	assert_int((b[0] as ChainBehavior).jumps).is_greater(0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_sp_e_weapons.gd`
Expected: FAIL — `TeslaGunWeapon` not defined.

- [ ] **Step 3: Create the weapon**

Create `src/weapons/tesla_gun_weapon.gd`:

```gdscript
class_name TeslaGunWeapon
extends RangedWeapon

func _configure() -> void:
	damage = 3.0
	cooldown = 1.1
	projectile_count = 1
	spread_angle = 0.0
	projectile_speed = 220.0
	projectile_lifetime = 2.0

func _make_behaviors() -> Array:
	var c := ChainBehavior.new()
	c.jumps = 3
	c.range_px = 160.0
	return [c]
```

- [ ] **Step 4: Register the archetype**

In `src/autoload/weapon_registry.gd`, alongside the prior registrations, add:

```gdscript
	weapon_scripts["tesla_gun"] = preload("res://src/weapons/tesla_gun_weapon.gd")
```

- [ ] **Step 5: Run test to verify it passes**

Run the Step 2 command. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/weapons/tesla_gun_weapon.gd src/autoload/weapon_registry.gd tests/unit/test_sp_e_weapons.gd
git commit -m "feat: add tesla_gun chaining weapon"
```

---

### Task 11: `hailstorm_bow` (native jittered volley)

**Files:**
- Create: `src/weapons/hailstorm_bow_weapon.gd`
- Modify: `src/autoload/weapon_registry.gd` (register `hailstorm_bow`)
- Test: extend `tests/unit/test_sp_e_weapons.gd`

Overrides `_emit_shot` to loose one wide volley of `volley_count` shots with per-shot random angle/speed jitter. Uses `shot_sink` so the test counts directions without a world.

- [ ] **Step 1: Add the failing test**

Append to `tests/unit/test_sp_e_weapons.gd`:

```gdscript
func test_hailstorm_emits_full_jittered_volley() -> void:
	var dirs: Array = []
	var w := HailstormBowWeapon.new()
	w.shot_sink = func(dir): dirs.append(dir)
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	w._emit_shot(user, Vector2.RIGHT)
	assert_int(dirs.size()).is_equal(w.volley_count)
	# Jitter: not all angles identical, and they span a wide arc.
	var angles: Array = []
	for d in dirs:
		angles.append((d as Vector2).angle())
	angles.sort()
	assert_float(angles[angles.size() - 1] - angles[0]).is_greater(0.3)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_sp_e_weapons.gd`
Expected: FAIL — `HailstormBowWeapon` not defined.

- [ ] **Step 3: Create the weapon**

Create `src/weapons/hailstorm_bow_weapon.gd`:

```gdscript
class_name HailstormBowWeapon
extends RangedWeapon

@export var volley_count: int = 12
@export var volley_spread_deg: float = 120.0
@export var speed_jitter: float = 40.0

func _configure() -> void:
	damage = 2.5
	cooldown = 1.4
	projectile_count = 1   # base spread path unused; _emit_shot overridden
	spread_angle = 0.0
	projectile_speed = 150.0
	projectile_lifetime = 1.2

func _emit_shot(user: Node, base_dir: Vector2) -> void:
	var base_angle: float = base_dir.angle()
	var half: float = deg_to_rad(volley_spread_deg) / 2.0
	var base_speed: float = projectile_speed
	for i in range(volley_count):
		var jitter: float = randf_range(-half, half)
		var ang: float = base_angle + jitter
		var dir := Vector2(cos(ang), sin(ang))
		projectile_speed = base_speed + randf_range(-speed_jitter, speed_jitter)
		_spawn_projectile(user, dir)
	projectile_speed = base_speed
	notify_attack(user, {
		"direction": base_dir,
		"origin": user.global_position,
		"charged": false,
		"charge_ratio": 0.0,
	})
```

- [ ] **Step 4: Register the archetype**

In `src/autoload/weapon_registry.gd`, alongside the prior registrations, add:

```gdscript
	weapon_scripts["hailstorm_bow"] = preload("res://src/weapons/hailstorm_bow_weapon.gd")
```

- [ ] **Step 5: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (all `test_sp_e_weapons.gd` tests).

- [ ] **Step 6: Commit**

```bash
git add src/weapons/hailstorm_bow_weapon.gd src/autoload/weapon_registry.gd tests/unit/test_sp_e_weapons.gd
git commit -m "feat: add hailstorm_bow area-volley weapon"
```

---

### Task 12: CSV `hit_status` column + `frost_repeater` + build test

**Files:**
- Modify: `docs/design_docs/weapons.csv` (add `hit_status` column; `freeze` for `frost_repeater`)
- Test: `tests/unit/test_sp_e_weapons_build.gd`

- [ ] **Step 1: Write the failing build test**

Create `tests/unit/test_sp_e_weapons_build.gd`:

```gdscript
extends GdUnitTestSuite

func test_all_sp_e_archetype_weapons_build() -> void:
	for id in ["heavy_crossbow", "arc_railgun", "flame_lobber", "venom_spitter",
			"tesla_gun", "chakram_launcher", "seeker_launcher", "hailstorm_bow"]:
		var w: Weapon = WeaponRegistry.get_weapon_by_id(id)
		assert_object(w).override_failure_message("missing weapon: %s" % id).is_not_null()

func test_bucket1_ranged_weapons_build() -> void:
	for id in ["scatter_blunderbuss", "frost_repeater"]:
		var w: Weapon = WeaponRegistry.get_weapon_by_id(id)
		assert_object(w).override_failure_message("missing weapon: %s" % id).is_not_null()

func test_frost_repeater_has_freeze_hit_status() -> void:
	var w = WeaponRegistry.get_weapon_by_id("frost_repeater")
	assert_object(w).is_not_null()
	assert_str((w as RangedWeapon).hit_status).is_equal("freeze")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_sp_e_weapons_build.gd`
Expected: FAIL — `frost_repeater` `hit_status` is empty (no CSV column yet). The two build tests should already pass (archetypes registered in Tasks 7–11; rows already exist in CSV).

- [ ] **Step 3: Add the `hit_status` column**

Run this from the repo root (appends one trailing column to every row; `freeze` for `frost_repeater`, blank elsewhere; whole-line append is safe against commas inside quoted descriptions):

```bash
awk '{ if (NR==1) print $0",hit_status"; else if ($0=="") print; else if ($0 ~ /^frost_repeater,/) print $0",freeze"; else print $0"," }' docs/design_docs/weapons.csv > /tmp/weapons_e.csv && mv /tmp/weapons_e.csv docs/design_docs/weapons.csv
```

- [ ] **Step 4: Verify the CSV header and frost row**

Run: `head -1 docs/design_docs/weapons.csv | tr ',' '\n' | tail -1` → expect `hit_status`.
Run: `grep '^frost_repeater,' docs/design_docs/weapons.csv` → the line ends with `,freeze`.

- [ ] **Step 5: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add docs/design_docs/weapons.csv tests/unit/test_sp_e_weapons_build.gd
git commit -m "feat: add hit_status CSV column; frost_repeater freezes; SP-E build test"
```

---

### Task 13: Mark SP-E done + full-suite regression

**Files:**
- Modify: `docs/design_docs/implementation_todo.md:215-221` (the SP-E table)

- [ ] **Step 1: Run the entire unit suite (regression)**

Run:

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit
```

Expected: all tests pass (SP-E suites green; no pre-existing tests regressed). If any fail, fix before continuing.

- [ ] **Step 2: Mark the SP-E rows done**

In `docs/design_docs/implementation_todo.md`, in the "Sub-project E (9)" table (lines ~215–221), set the `Done` cell of all four task rows from blank to `x`:

```
| x | P2 | Medium | Line-pierce + charged rail | heavy_crossbow pierce; arc_railgun charge-to-fire rail |
| x | P2 | Medium | Lob-splat + chain/fork | flame_lobber/venom_spitter impact hazard; tesla_gun chaining |
| x | P2 | Medium | Area-volley + folded-native | hailstorm_bow volley; chakram return, seeker homing fold native |
| x | P2 | Medium | Ranged `.tres` + stat wiring | heavy_crossbow, scatter_blunderbuss, arc_railgun, flame_lobber, frost_repeater, venom_spitter, tesla_gun, chakram_launcher, seeker_launcher, hailstorm_bow |
```

- [ ] **Step 3: Commit**

```bash
git add docs/design_docs/implementation_todo.md
git commit -m "docs: mark Phase 7 SP-E (native ranged + 10 weapons) done"
```

---

## Self-Review (completed during planning)

**Spec coverage:**
- §2 Bucket 1 (scatter_blunderbuss, frost_repeater) → Task 12 build test confirms both drop; frost via `hit_status` (Tasks 5 + 12). ✓
- §3.1 `hit_status` column → Task 5 (code) + Task 12 (CSV). ✓
- §3.2 `ChargedRangedWeapon` → Task 6; consumed by arc_railgun Task 8. ✓
- §3.3 `on_expire` hook → Task 1; consumed by SplatBehavior Task 3. ✓
- §3.4 `CombatUtil.nearest_attackables` → Task 2; consumed by ChainBehavior Task 4. ✓
- §3.5 `SplatBehavior` → Task 3; `ChainBehavior` → Task 4. ✓
- §4 eight archetypes → Tasks 7–11. ✓
- §6 registry registration → distributed across Tasks 7–11; CSV column Task 12. ✓
- §7 tests → each task ships its tests; build/registry test Task 12; full regression Task 13. ✓

**Placeholder scan:** none — every step has concrete code/commands.

**Type consistency:** `hit_status` (field), `place_sink(mat,pos,radius,density)` (Task 3 sig matches test), `nearest_attackables(tree, from_pos, exclude, count, range_px)` (Tasks 2/4 match), `_make_behaviors()`/`_configure()`/`_emit_shot(user, base_dir)`/`_spawn_projectile(user, dir)`/`shot_sink` (match `ranged_weapon.gd`), `ChainBehavior.jumps`/`range_px`, `SplatBehavior.material`/`radius`/`gas_density` — all consistent across tasks.

**Deviations from spec (documented above):** archetype stats live in `_configure()` not CSV (matches existing archetypes); arc_railgun has no charge-depth scaling (fizzle decision makes it vacuous).
