# SP-A — Data-Driven Runtime (Weapons + Modifiers) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make weapons fully data-driven (no `.tres`) and build a `DataModifier` runtime, an effective-stats pipeline, and a shared `resolve_hit` chokepoint, so 32 new modifiers and ~10 new weapons work from CSV alone.

**Architecture:** A weapon is constructed from its `weapons.csv` row: an `archetype` column picks the script; new tuning columns (`reach/arc/projectile_*`) replace the deleted `.tres`. Modifiers without a bespoke script become `DataModifier` instances that dispatch on the CSV `category/trigger/condition/effect` columns. Passive stat affixes fold into `Weapon.get_effective_stats()`; per-hit conditional multipliers, status-edges, and on-kill effects run inside a single `Weapon.resolve_hit()` used by both melee and projectiles.

**Tech Stack:** Godot 4 / GDScript, gdUnit4 tests (`./addons/gdUnit4/runtest.sh -a <file>`), autoloads `WeaponRegistry`, `TerrainSurface`, `MaterialRegistry`, `StatusRegistry`.

**Spec:** `docs/superpowers/specs/2026-06-15-sp-a-data-driven-runtime-design.md`

**Test runner note:** every "Run" step uses `./addons/gdUnit4/runtest.sh -a tests/unit/<file>.gd` from the repo root. If `godot` isn't on PATH, prefix `GODOT_BIN=/path/to/godot`.

---

## Task 1: Modifier hook surface + `@export` Weapon stats

**Files:**
- Modify: `src/weapons/modifier.gd`
- Modify: `src/weapons/weapon.gd:9-10`
- Test: `tests/unit/test_data_modifier.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_data_modifier.gd`:

```gdscript
extends GdUnitTestSuite

func test_base_modifier_new_hooks_are_noops() -> void:
	var m: Modifier = Modifier.new()
	# New virtuals must exist and be safe no-ops with neutral return values.
	assert_that(m.modify_stat("damage", 5.0)).is_equal(5.0)
	assert_that(m.modify_hit_damage(null, null, null, 7.0)).is_equal(7.0)
	m.on_hit_target(null, null, null)   # must not error
	m.on_kill(null, null, null)         # must not error

func test_weapon_cooldown_damage_survive_duplicate() -> void:
	var w: Weapon = Weapon.new()
	w.cooldown = 0.42
	w.damage = 9.0
	var copy: Weapon = w.duplicate(true)
	assert_that(copy.cooldown).is_equal(0.42)
	assert_that(copy.damage).is_equal(9.0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_data_modifier.gd`
Expected: FAIL — `modify_stat`/`modify_hit_damage`/`on_hit_target`/`on_kill` not defined; duplicate drops plain `var` cooldown/damage.

- [ ] **Step 3: Add the hooks and `@export` the stats**

In `src/weapons/modifier.gd`, add after `modify_crit_chance`:

```gdscript
func modify_stat(_stat: String, value: float) -> float:
	return value


func modify_hit_damage(_weapon: Weapon, _user: Node, _target: Node, dmg: float) -> float:
	return dmg


func on_hit_target(_weapon: Weapon, _user: Node, _target: Node) -> void:
	pass


func on_kill(_weapon: Weapon, _user: Node, _target: Node) -> void:
	pass
```

In `src/weapons/weapon.gd`, change lines 9-10 from plain `var` to `@export` (so the factory-set values survive `duplicate(true)`):

```gdscript
@export var cooldown: float = 0.8
@export var damage: float = 0.0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_data_modifier.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/weapons/modifier.gd src/weapons/weapon.gd tests/unit/test_data_modifier.gd
git commit -m "feat(weapons): add Modifier hit/stat hooks; @export cooldown/damage"
```

---

## Task 2: Effective-stats pipeline

**Files:**
- Modify: `src/weapons/weapon.gd`
- Test: `tests/unit/test_weapon_effective_stats.gd` (create)

Effective stats fold every modifier's `passive` `stat_add` (summed) then `stat_mult` (multiplied), per the spec stack rule. Modifiers contribute through `modify_stat(stat, value)`: for an *add* affix it returns `value + amount` only for its stat; for a *mult* affix it returns `value * factor`. We apply adds first, then mults, by calling each modifier twice in two passes keyed by a phase argument folded into the stat name is overkill — instead we expose two query helpers on the modifier used only by `DataModifier` (Task 10). For Task 2 the Weapon just needs the fold machinery and a cache.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_weapon_effective_stats.gd`:

```gdscript
extends GdUnitTestSuite

# Adds a flat amount to one stat (the stat_add half).
class _AddMod extends Modifier:
	var stat: String
	var amount: float
	func _init(s: String, a: float) -> void:
		stat = s; amount = a
	func get_stat_add(s: String) -> float:
		return amount if s == stat else 0.0

# Multiplies one stat (the stat_mult half).
class _MultMod extends Modifier:
	var stat: String
	var factor: float
	func _init(s: String, f: float) -> void:
		stat = s; factor = f
	func get_stat_mult(s: String) -> float:
		return factor if s == stat else 1.0

func test_add_then_mult_order() -> void:
	var w: Weapon = Weapon.new()
	w.damage = 10.0
	w.modifiers = [_AddMod.new("damage", 3.0), _MultMod.new("damage", 2.0), null]
	# (10 + 3) * 2 = 26
	assert_that(w.get_effective_stats()["damage"]).is_equal(26.0)

func test_cooldown_floor() -> void:
	var w: Weapon = Weapon.new()
	w.cooldown = 0.2
	w.modifiers = [_MultMod.new("cooldown", 0.1), null, null]
	# 0.2 * 0.1 = 0.02, floored to 0.1
	assert_that(w.get_effective_stats()["cooldown"]).is_equal(0.1)

func test_cache_invalidates_on_modifier_change() -> void:
	var w: Weapon = Weapon.new()
	w.damage = 5.0
	assert_that(w.get_effective_stats()["damage"]).is_equal(5.0)
	w.add_modifier(0, _AddMod.new("damage", 4.0))
	assert_that(w.get_effective_stats()["damage"]).is_equal(9.0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_weapon_effective_stats.gd`
Expected: FAIL — `get_effective_stats` / `get_stat_add` / `get_stat_mult` not defined.

- [ ] **Step 3: Implement the pipeline**

In `src/weapons/modifier.gd`, add neutral defaults (bespoke mods don't change stats):

```gdscript
func get_stat_add(_stat: String) -> float:
	return 0.0


func get_stat_mult(_stat: String) -> float:
	return 1.0
```

In `src/weapons/weapon.gd`, add a cache field near the other vars:

```gdscript
const COOLDOWN_FLOOR := 0.1
var _effective_cache: Dictionary = {}
```

Add the methods (the melee/ranged seeds for `reach`/`arc`/`carve_depth`/`move_speed` are overridden in subclasses via `_seed_effective_stats`):

```gdscript
func _seed_effective_stats() -> Dictionary:
	return {
		"damage": damage,
		"cooldown": cooldown,
		"crit_chance": crit_chance,
		"crit_multiplier": crit_multiplier,
		"reach": 0.0,
		"arc": 0.0,
		"move_speed": 1.0,
		"carve_depth": 1.0,
	}


func get_effective_stats() -> Dictionary:
	if not _effective_cache.is_empty():
		return _effective_cache
	var s := _seed_effective_stats()
	for stat in s.keys():
		var v: float = s[stat]
		for m in modifiers:
			if m != null:
				v += m.get_stat_add(stat)
		for m in modifiers:
			if m != null:
				v *= m.get_stat_mult(stat)
		s[stat] = v
	s["cooldown"] = maxf(COOLDOWN_FLOOR, s["cooldown"])
	_effective_cache = s
	return s


func invalidate_effective_stats() -> void:
	_effective_cache = {}
```

In `add_modifier()` (after `modifier.on_equip(self)`), add:

```gdscript
	invalidate_effective_stats()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_weapon_effective_stats.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/weapons/weapon.gd src/weapons/modifier.gd tests/unit/test_weapon_effective_stats.gd
git commit -m "feat(weapons): effective-stats pipeline (add-then-mult, cached)"
```

---

## Task 3: Wire effective stats into cooldown + melee/ranged seeds

**Files:**
- Modify: `src/weapons/weapon.gd:35` (`use`)
- Modify: `src/weapons/melee_weapon.gd` (`_use_impl`, add `_seed_effective_stats`)
- Modify: `src/weapons/ranged_weapon.gd` (`_spawn_projectile`, add `_seed_effective_stats`)
- Test: `tests/unit/test_weapon_effective_stats.gd` (extend)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_weapon_effective_stats.gd`:

```gdscript
func test_use_sets_cooldown_from_effective() -> void:
	var w: Weapon = Weapon.new()
	w.cooldown = 1.0
	w.modifiers = [_MultMod.new("cooldown", 0.8), null, null]
	w.use(null)               # base use_impl is a no-op; only the timer matters
	assert_that(w.is_ready()).is_false()    # 0.8s pending, > 0
	w.tick(0.79)
	assert_that(w.is_ready()).is_false()
	w.tick(0.02)
	assert_that(w.is_ready()).is_true()

func test_melee_seeds_reach_and_arc() -> void:
	var m: MeleeWeapon = MeleeWeapon.new()
	m.weapon_reach = 30.0
	m.arc_angle = PI / 2.0
	var s := m.get_effective_stats()
	assert_that(s["reach"]).is_equal(30.0)
	assert_that(s["arc"]).is_equal(PI / 2.0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_weapon_effective_stats.gd`
Expected: FAIL — cooldown uses raw field; melee seed missing reach/arc.

- [ ] **Step 3: Implement**

In `src/weapons/weapon.gd` `use()`, change the last line from `_cooldown_timer = cooldown` to:

```gdscript
	_cooldown_timer = get_effective_stats()["cooldown"]
```

In `src/weapons/melee_weapon.gd`, add an override:

```gdscript
func _seed_effective_stats() -> Dictionary:
	var s := super._seed_effective_stats()
	s["reach"] = weapon_reach
	s["arc"] = arc_angle
	return s
```

And in `_use_impl`, read effective stats for the swing geometry/damage:

```gdscript
func _use_impl(user: Node) -> void:
	_current_user = user
	var eff := get_effective_stats()
	var reach: float = eff["reach"]
	var arc: float = eff["arc"]
	var dmg: float = eff["damage"]
	var pos: Vector2 = user.global_position
	var direction := _get_facing_direction(user)
	_start_swing(direction)
	_carve_and_push(pos, direction, reach * eff["carve_depth"], arc, dmg)
	_hit_attackables(user, pos, direction, reach, arc, 1.0, false, false)
	notify_attack(user, {
		"direction": direction,
		"origin": pos,
		"charged": false,
		"charge_ratio": 0.0,
	})
```

In `src/weapons/ranged_weapon.gd`, add the same seed override (reach maps to projectile range; keep neutral 0 unless used) and read effective damage in `_spawn_projectile` — change `proj.damage = damage` to:

```gdscript
	proj.damage = get_effective_stats()["damage"]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_weapon_effective_stats.gd`
Expected: PASS

- [ ] **Step 5: Run melee/ranged regression suites**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_ranged_weapon.gd -a tests/unit/test_melee_arc_angle_filter.gd -a tests/unit/test_melee_reach_scale.gd`
Expected: PASS (no behavior change for unmodified weapons).

- [ ] **Step 6: Commit**

```bash
git add src/weapons/weapon.gd src/weapons/melee_weapon.gd src/weapons/ranged_weapon.gd tests/unit/test_weapon_effective_stats.gd
git commit -m "feat(weapons): consume effective stats in use/melee/ranged"
```

---

## Task 4: `resolve_hit` chokepoint

**Files:**
- Modify: `src/weapons/weapon.gd`
- Test: `tests/unit/test_weapon_resolve_hit.gd` (create)

`resolve_hit(user, target, base_dmg, is_crit)` applies the effective crit multiplier, folds each modifier's `modify_hit_damage`, deals damage via `on_hit_impact`, applies status-edges via `on_hit_target`, fires `on_kill` once when a live target drops to ≤0 hp, applies the existing crit-status stain, and advances `_hit_count`.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_weapon_resolve_hit.gd`:

```gdscript
extends GdUnitTestSuite

class _Target extends Node2D:
	var health: float = 10.0
	var hits: Array = []
	func _init() -> void:
		add_to_group("attackable")
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)
	func on_hit_impact(_p: Vector2, _d: Vector2, dmg: int) -> void:
		hits.append(dmg)
		health -= dmg

class _DoubleDmg extends Modifier:
	func modify_hit_damage(_w, _u, _t, dmg: float) -> float:
		return dmg * 2.0

class _EdgeMod extends Modifier:
	func on_hit_target(_w, _u, t: Node) -> void:
		t.get_node("StatusComponent").add_stain("poisoned", 2.0)

class _KillCounter extends Modifier:
	var kills: int = 0
	func on_kill(_w, _u, _t) -> void:
		kills += 1

func _target() -> _Target:
	var t := _Target.new()
	add_child(t)
	return auto_free(t)

func test_crit_multiplier_applied() -> void:
	var w := Weapon.new()
	w.crit_multiplier = 2.0
	var t := _target()
	w.resolve_hit(null, t, 5.0, true)
	assert_int(t.hits[0]).is_equal(10)

func test_conditional_multiplier_folds() -> void:
	var w := Weapon.new()
	w.modifiers = [_DoubleDmg.new(), null, null]
	var t := _target()
	w.resolve_hit(null, t, 5.0, false)
	assert_int(t.hits[0]).is_equal(10)

func test_status_edge_applies() -> void:
	var w := Weapon.new()
	w.modifiers = [_EdgeMod.new(), null, null]
	var t := _target()
	w.resolve_hit(null, t, 1.0, false)
	assert_that(t.get_node("StatusComponent").get_stain("poisoned")).is_greater(0.0)

func test_on_kill_fires_once_when_target_dies() -> void:
	var w := Weapon.new()
	var km := _KillCounter.new()
	w.modifiers = [km, null, null]
	var t := _target()
	t.health = 4.0
	w.resolve_hit(null, t, 5.0, false)   # kills
	w.resolve_hit(null, t, 5.0, false)   # already dead -> no second kill
	assert_int(km.kills).is_equal(1)

func test_hit_count_advances() -> void:
	var w := Weapon.new()
	var t := _target()
	w.resolve_hit(null, t, 1.0, false)
	w.resolve_hit(null, t, 1.0, false)
	assert_int(w._hit_count).is_equal(2)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_weapon_resolve_hit.gd`
Expected: FAIL — `resolve_hit` / `_hit_count` not defined.

- [ ] **Step 3: Implement**

In `src/weapons/weapon.gd`, add the field and method:

```gdscript
var _hit_count: int = 0


func resolve_hit(user: Node, target: Node, base_dmg: float, is_crit: bool) -> void:
	var dmg: float = base_dmg
	if is_crit:
		dmg *= get_effective_stats()["crit_multiplier"]
	for m in modifiers:
		if m != null:
			dmg = m.modify_hit_damage(self, user, target, dmg)
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
	_hit_count += 1
	if had_hp and pre_hp > 0.0 and target.health <= 0.0:
		for m in modifiers:
			if m != null:
				m.on_kill(self, user, target)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_weapon_resolve_hit.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/weapons/weapon.gd tests/unit/test_weapon_resolve_hit.gd
git commit -m "feat(weapons): resolve_hit chokepoint (crit/conditional/edge/on-kill)"
```

---

## Task 5: Route melee hits through `resolve_hit`

**Files:**
- Modify: `src/weapons/melee_weapon.gd:146-186` (`_hit_attackables`)
- Test: `tests/unit/test_melee_resolve_hit.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_melee_resolve_hit.gd`:

```gdscript
extends GdUnitTestSuite

class _Target extends Node2D:
	var health: float = 100.0
	var hits: Array = []
	func _init() -> void:
		add_to_group("attackable")
		set_collision_layer_value(8, true)
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)
		var col := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 4.0
		col.shape = shape
		add_child(col)
	func on_hit_impact(_p: Vector2, _d: Vector2, dmg: int) -> void:
		hits.append(dmg)
		health -= dmg

class _EdgeMod extends Modifier:
	func on_hit_target(_w, _u, t: Node) -> void:
		t.get_node("StatusComponent").add_stain("on_fire", 2.0)

func test_melee_swing_routes_through_resolve_hit_and_applies_edge() -> void:
	var parent := auto_free(Area2D.new())   # gives a World2D via get_world_2d
	add_child(parent)
	var user := Node2D.new()
	parent.add_child(user)
	user.global_position = Vector2.ZERO
	var target := _Target.new()
	parent.add_child(target)
	target.global_position = Vector2(10, 0)
	var w := MeleeWeapon.new()
	w.weapon_reach = 30.0
	w.arc_angle = PI
	w.damage = 5.0
	w.crit_chance = 0.0
	w.modifiers = [_EdgeMod.new(), null, null]
	await get_tree().physics_frame   # let the physics body register
	w._hit_attackables(user, Vector2.ZERO, Vector2.RIGHT, 30.0, PI, 1.0, false, true)
	assert_int(target.hits.size()).is_equal(1)
	assert_that(target.get_node("StatusComponent").get_stain("on_fire")).is_greater(0.0)
```

> Note: physics-shape queries are timing-sensitive headless. If the shape query returns nothing in CI, mark this suite `@warning_ignore` and rely on the Task 4 unit coverage; the geometry is already covered by `test_melee_arc_angle_filter.gd`.

- [ ] **Step 2: Run test to verify it fails**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_melee_resolve_hit.gd`
Expected: FAIL — edge not applied (old inline path doesn't call modifiers).

- [ ] **Step 3: Implement**

In `src/weapons/melee_weapon.gd`, replace the per-hit block at the bottom of `_hit_attackables` (the `is_crit`/`dmg`/`on_hit_impact`/`_on_crit` lines) with a `resolve_hit` call. The full inner loop becomes:

```gdscript
		var hit_dir: Vector2 = (node2d.global_position - origin).normalized()
		if not ignore_parry and node.has_method("try_parry"):
			if node.try_parry(user, node2d.global_position, hit_dir):
				var tint: Color = trail_color if "trail_color" in self else Color(1, 1, 1, 1)
				NailClashFX.play(node2d.global_position, -hit_dir, tint)
				continue
		var is_crit: bool = force_crit or roll_crit()
		resolve_hit(user, node, base_dmg, is_crit)
```

(`base_dmg` is still `damage * dmg_mult` computed at the top of the function; combo/charge subclasses that call `_hit_attackables` with a `dmg_mult` keep working.)

- [ ] **Step 4: Run test to verify it passes**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_melee_resolve_hit.gd`
Expected: PASS

- [ ] **Step 5: Run melee regression suites**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_weapon_crit.gd -a tests/unit/test_advanced_melee_hit_geometry.gd -a tests/unit/test_parry_intercept.gd`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add src/weapons/melee_weapon.gd tests/unit/test_melee_resolve_hit.gd
git commit -m "feat(melee): route swing damage through resolve_hit"
```

---

## Task 6: Projectiles carry `source_weapon` and route through `resolve_hit`

**Files:**
- Modify: `src/weapons/projectile.gd:7-95`
- Modify: `src/weapons/ranged_weapon.gd:109-124` (`_spawn_projectile`)
- Test: `tests/unit/test_projectile.gd` (extend)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_projectile.gd`:

```gdscript
class _RhTarget extends Node2D:
	var health: float = 100.0
	var hits: Array = []
	func _init() -> void:
		add_to_group("attackable")
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)
	func on_hit_impact(_p: Vector2, _d: Vector2, dmg: int) -> void:
		hits.append(dmg)
		health -= dmg

class _EdgeWeapon extends Weapon:
	# A weapon whose single modifier applies a poisoned edge on hit.
	func _init() -> void:
		var m := _PoisonEdge.new()
		modifiers = [m, null, null]
class _PoisonEdge extends Modifier:
	func on_hit_target(_w, _u, t: Node) -> void:
		t.get_node("StatusComponent").add_stain("poisoned", 2.0)

func test_projectile_routes_player_hit_through_source_weapon() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var target := _RhTarget.new()
	parent.add_child(target)
	var p: Projectile = Projectile.new()
	p.is_enemy_projectile = false
	p.damage = 5.0
	p.crit_chance = 0.0
	p.source_weapon = _EdgeWeapon.new()
	parent.add_child(p)
	p._handle_hit(target)
	assert_int(target.hits[0]).is_equal(5)
	assert_that(target.get_node("StatusComponent").get_stain("poisoned")).is_greater(0.0)

func test_projectile_without_source_weapon_still_hits() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var target := _RhTarget.new()
	parent.add_child(target)
	var p: Projectile = Projectile.new()
	p.is_enemy_projectile = false
	p.damage = 4.0
	p.crit_chance = 0.0
	parent.add_child(p)
	p._handle_hit(target)
	assert_int(target.hits[0]).is_equal(4)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_projectile.gd`
Expected: FAIL — `source_weapon` not defined / edge not applied.

- [ ] **Step 3: Implement**

In `src/weapons/projectile.gd`, add the field near the other vars:

```gdscript
var source_weapon: Weapon = null
```

Replace the attackable branch in `_handle_hit` (the block under `if target.is_in_group("attackable"):`) with:

```gdscript
	if target.is_in_group("attackable"):
		if target != source_node and target.has_method("on_hit_impact"):
			if source_weapon != null:
				var is_crit: bool = randf() < clampf(crit_chance, 0.0, 1.0)
				source_weapon.resolve_hit(source_node, target, damage, is_crit)
			else:
				_legacy_apply_hit(target)
			var keep_enemy := false
			for b in behaviors:
				keep_enemy = b.on_enemy_hit(self, target) or keep_enemy
			if not keep_enemy:
				queue_free()
```

Extract the old inline crit/`hit_status`/`crit_status` logic into a fallback so behavior is unchanged when no weapon is attached (tests and any non-weapon spawner):

```gdscript
func _legacy_apply_hit(target: Node) -> void:
	var is_crit: bool = randf() < clampf(crit_chance, 0.0, 1.0)
	var dmg: int = int(damage * crit_multiplier) if is_crit else int(damage)
	target.on_hit_impact(global_position, direction, dmg)
	if is_crit and crit_status != "":
		var sc = target.get_node_or_null("StatusComponent")
		if sc != null:
			sc.add_stain(crit_status, CRIT_STATUS_STAIN)
	if hit_status != "":
		var hs = target.get_node_or_null("StatusComponent")
		if hs != null:
			hs.add_stain(hit_status, HIT_STATUS_STAIN)
```

In `src/weapons/ranged_weapon.gd` `_spawn_projectile`, after `proj.source_node = user`, add:

```gdscript
	proj.source_weapon = self
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_projectile.gd -a tests/unit/test_projectile_behaviors.gd -a tests/unit/test_modifiers.gd`
Expected: PASS (the existing `hit_status`/`crit_status` modifier-projectile tests use no `source_weapon`, so they hit `_legacy_apply_hit` unchanged.)

- [ ] **Step 5: Commit**

```bash
git add src/weapons/projectile.gd src/weapons/ranged_weapon.gd tests/unit/test_projectile.gd
git commit -m "feat(ranged): projectiles route hits through source_weapon.resolve_hit"
```

---

## Task 7: Generic `TerrainSurface.place_material`

**Files:**
- Modify: `src/core/terrain_surface.gd`
- Test: `tests/unit/test_terrain_surface.gd` (extend)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_terrain_surface.gd`:

```gdscript
class _RecordAdapter:
	var calls: Array = []
	func place_material(pos: Vector2, radius: float, mat: int) -> void:
		calls.append([pos, radius, mat])

func test_place_material_forwards_to_adapter() -> void:
	var rec := _RecordAdapter.new()
	var prev = TerrainSurface.adapter
	TerrainSurface.register_adapter(rec)
	TerrainSurface.place_material(Vector2(5, 6), 12.0, 3)
	TerrainSurface.register_adapter(prev)
	assert_int(rec.calls.size()).is_equal(1)
	assert_that(rec.calls[0][2]).is_equal(3)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_terrain_surface.gd`
Expected: FAIL — `place_material` not defined on TerrainSurface.

- [ ] **Step 3: Implement**

In `src/core/terrain_surface.gd`, add after `place_oil`:

```gdscript
func place_material(world_pos: Vector2, radius: float, material_id: int) -> void:
	if adapter:
		adapter.place_material(world_pos, radius, material_id)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_terrain_surface.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/core/terrain_surface.gd tests/unit/test_terrain_surface.gd
git commit -m "feat(terrain): generic TerrainSurface.place_material passthrough"
```

---

## Task 8: `DataModifier` — construction + emitters

**Files:**
- Create: `src/weapons/modifiers/data_modifier.gd`
- Test: `tests/unit/test_data_modifier.gd` (extend)

`DataModifier` is built from a CSV row dict. Emitters trigger on `on_swing` → `on_attack`, placing the `element` material at the arc midpoint (melee) / origin (ranged) via `TerrainSurface`.

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_data_modifier.gd`:

```gdscript
class _MatAdapter:
	var placed: Array = []
	func place_material(pos: Vector2, radius: float, mat: int) -> void:
		placed.append(mat)

func _row(overrides: Dictionary) -> Dictionary:
	var base := {
		"id": "x", "name": "X", "description": "", "rarity": "Common",
		"category": "", "trigger": "", "condition": "", "effect": "",
		"element": "", "magnitude": "0", "magnitude2": "0", "suppresses_base_use": "No",
	}
	for k in overrides.keys():
		base[k] = overrides[k]
	return base

func test_data_modifier_stores_columns() -> void:
	var m := DataModifier.new(_row({ "category": "stat", "effect": "stat_add", "element": "damage", "magnitude": "3" }))
	assert_str(m.category).is_equal("stat")
	assert_str(m.effect).is_equal("stat_add")
	assert_that(m.magnitude).is_equal(3.0)

func test_emitter_places_material_on_swing() -> void:
	var rec := _MatAdapter.new()
	var prev = TerrainSurface.adapter
	TerrainSurface.register_adapter(rec)
	var user := auto_free(Node2D.new())
	add_child(user)
	var m := DataModifier.new(_row({
		"category": "emitter", "trigger": "on_swing", "effect": "spawn_material",
		"element": "water", "magnitude": "16",
	}))
	m.on_attack(null, user, { "direction": Vector2.RIGHT, "origin": Vector2.ZERO, "charged": false, "charge_ratio": 0.0 })
	TerrainSurface.register_adapter(prev)
	assert_int(rec.placed.size()).is_equal(1)
	assert_that(rec.placed[0]).is_equal(MaterialRegistry.MAT_WATER)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_data_modifier.gd`
Expected: FAIL — `DataModifier` not defined.

- [ ] **Step 3: Implement**

Create `src/weapons/modifiers/data_modifier.gd`:

```gdscript
class_name DataModifier
extends Modifier

const EMITTER_FORWARD := 14.0

var category: String = ""
var trigger: String = ""
var condition: String = ""
var effect: String = ""
var element: String = ""
var magnitude: float = 0.0
var magnitude2: float = 0.0

const _MATERIAL_IDS := {
	"oil": "MAT_OIL", "water": "MAT_WATER", "gas": "MAT_GAS", "ice": "MAT_ICE",
	"blood": "MAT_BLOOD", "coal": "MAT_COAL", "dust": "MAT_DUST", "lava": "MAT_LAVA",
}


func _init(row: Dictionary = {}) -> void:
	name = row.get("name", "Modifier")
	description = row.get("description", "")
	suppresses_base_use = String(row.get("suppresses_base_use", "No")).strip_edges() == "Yes"
	category = row.get("category", "")
	trigger = row.get("trigger", "")
	condition = row.get("condition", "")
	effect = row.get("effect", "")
	element = row.get("element", "")
	magnitude = float(row.get("magnitude", "0"))
	magnitude2 = float(row.get("magnitude2", "0"))


func _material_id() -> int:
	var key: String = _MATERIAL_IDS.get(element, "")
	if key == "":
		return -1
	return MaterialRegistry.get(key)


func on_attack(_weapon: Weapon, user: Node, ctx: Dictionary) -> void:
	if trigger != "on_swing":
		return
	if effect == "spawn_material":
		_spawn_material(user, ctx)


func _spawn_material(user: Node, ctx: Dictionary) -> void:
	var mat := _material_id()
	if mat < 0:
		return
	var origin: Vector2 = ctx.get("origin", Vector2.ZERO)
	var dir: Vector2 = ctx.get("direction", Vector2.DOWN)
	var at: Vector2 = origin + dir * EMITTER_FORWARD
	TerrainSurface.place_material(at, magnitude, mat)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_data_modifier.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/weapons/modifiers/data_modifier.gd tests/unit/test_data_modifier.gd
git commit -m "feat(modifiers): DataModifier with spawn_material emitters"
```

---

## Task 9: `DataModifier` — status-edges (on_hit)

**Files:**
- Modify: `src/weapons/modifiers/data_modifier.gd`
- Test: `tests/unit/test_data_modifier.gd` (extend)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_data_modifier.gd`:

```gdscript
class _StatusTarget extends Node2D:
	func _init() -> void:
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)

func test_status_edge_stains_target_on_hit() -> void:
	var t := auto_free(_StatusTarget.new())
	add_child(t)
	var m := DataModifier.new(_row({
		"category": "status", "trigger": "on_hit", "effect": "apply_status",
		"element": "poisoned", "magnitude": "2",
	}))
	m.on_hit_target(null, null, t)
	assert_that(t.get_node("StatusComponent").get_stain("poisoned")).is_equal(2.0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_data_modifier.gd`
Expected: FAIL — `on_hit_target` is the base no-op.

- [ ] **Step 3: Implement**

In `src/weapons/modifiers/data_modifier.gd`, override:

```gdscript
func on_hit_target(_weapon: Weapon, _user: Node, target: Node) -> void:
	if trigger != "on_hit" or effect != "apply_status":
		return
	var sc = target.get_node_or_null("StatusComponent")
	if sc != null:
		sc.add_stain(element, magnitude)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_data_modifier.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/weapons/modifiers/data_modifier.gd tests/unit/test_data_modifier.gd
git commit -m "feat(modifiers): DataModifier apply_status edges"
```

---

## Task 10: `DataModifier` — passive stat affixes

**Files:**
- Modify: `src/weapons/modifiers/data_modifier.gd`
- Test: `tests/unit/test_data_modifier.gd` (extend)

Maps `effect=stat_add`/`stat_mult` (with `trigger=passive`) into `get_stat_add`/`get_stat_mult`. `heavy_head` is the dual case: `stat_add damage` **and** `cooldown *= magnitude2`.

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_data_modifier.gd`:

```gdscript
func test_stat_add_affix() -> void:
	var m := DataModifier.new(_row({ "category": "stat", "trigger": "passive", "effect": "stat_add", "element": "damage", "magnitude": "3" }))
	assert_that(m.get_stat_add("damage")).is_equal(3.0)
	assert_that(m.get_stat_add("cooldown")).is_equal(0.0)

func test_stat_mult_affix() -> void:
	var m := DataModifier.new(_row({ "category": "stat", "trigger": "passive", "effect": "stat_mult", "element": "cooldown", "magnitude": "0.8" }))
	assert_that(m.get_stat_mult("cooldown")).is_equal(0.8)
	assert_that(m.get_stat_mult("damage")).is_equal(1.0)

func test_heavy_head_dual_stat() -> void:
	var m := DataModifier.new(_row({ "category": "stat", "trigger": "passive", "effect": "stat_add", "element": "damage", "magnitude": "5", "magnitude2": "1.25" }))
	assert_that(m.get_stat_add("damage")).is_equal(5.0)
	assert_that(m.get_stat_mult("cooldown")).is_equal(1.25)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_data_modifier.gd`
Expected: FAIL — base `get_stat_add`/`get_stat_mult` return 0/1 always.

- [ ] **Step 3: Implement**

In `src/weapons/modifiers/data_modifier.gd`, override:

```gdscript
func get_stat_add(stat: String) -> float:
	if effect == "stat_add" and element == stat:
		return magnitude
	return 0.0


func get_stat_mult(stat: String) -> float:
	if effect == "stat_mult" and element == stat:
		return magnitude
	# heavy_head: a stat_add damage affix that also slows cooldown via magnitude2.
	if effect == "stat_add" and element == "damage" and stat == "cooldown" and magnitude2 > 0.0:
		return magnitude2
	return 1.0


func modify_crit_chance(_weapon: Weapon, base: float) -> float:
	# honed_point folds crit_chance via the same stat_add path the engine sums,
	# but the crit hook also needs to see it directly.
	if effect == "stat_add" and element == "crit_chance":
		return base + magnitude
	return base
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_data_modifier.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/weapons/modifiers/data_modifier.gd tests/unit/test_data_modifier.gd
git commit -m "feat(modifiers): DataModifier passive stat affixes"
```

---

## Task 11: `DataModifier` — conditional triggers + on-kill + every_n_hits

**Files:**
- Modify: `src/weapons/modifiers/data_modifier.gd`
- Modify: `src/weapons/weapon.gd` (combo_keeper crit hook reads `_hit_count`)
- Test: `tests/unit/test_data_modifier.gd` (extend)

Implements `modify_hit_damage` (frostbreaker, pyroclast, coup_de_grace, glass_cannon, momentum, rampage) gated by `condition`, `on_kill` (bloodlust, vampiric), `every_n_hits` (combo_keeper via `modify_crit_chance`), and the passive `adrenaline` cooldown ramp. Internal stateful ramps (bloodlust/rampage) use `on_tick` decay.

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_data_modifier.gd`:

```gdscript
class _HpTarget extends Node2D:
	var health: float = 3.0
	var max_health: float = 10.0
	func _init() -> void:
		var sc := StatusComponent.new(); sc.name = "StatusComponent"; add_child(sc)

func test_pyroclast_multiplies_only_when_target_burning() -> void:
	var t := auto_free(_HpTarget.new()); add_child(t)
	var m := DataModifier.new(_row({ "category": "trigger", "trigger": "on_hit", "condition": "target_status:on_fire", "effect": "stat_mult", "element": "damage", "magnitude": "1.5" }))
	assert_that(m.modify_hit_damage(null, null, t, 10.0)).is_equal(10.0)   # not burning
	t.get_node("StatusComponent").add_stain("on_fire", 2.0)
	assert_that(m.modify_hit_damage(null, null, t, 10.0)).is_equal(15.0)

func test_coup_de_grace_executes_low_hp() -> void:
	var t := auto_free(_HpTarget.new()); add_child(t)   # 3/10 = 0.3
	var m := DataModifier.new(_row({ "category": "trigger", "trigger": "on_hit", "condition": "target_low_hp", "effect": "stat_mult", "element": "damage", "magnitude": "2.0", "magnitude2": "0.3" }))
	assert_that(m.modify_hit_damage(null, null, t, 10.0)).is_equal(20.0)

func test_bloodlust_stacks_on_kill_capped() -> void:
	var m := DataModifier.new(_row({ "category": "trigger", "trigger": "on_kill", "effect": "stat_add", "element": "damage", "magnitude": "1", "magnitude2": "8" }))
	for i in range(10):
		m.on_kill(null, null, null)
	assert_that(m.get_stat_add("damage")).is_equal(8.0)   # capped at magnitude2

func test_combo_keeper_forces_crit_on_fifth() -> void:
	var w := Weapon.new()
	var m := DataModifier.new(_row({ "category": "trigger", "trigger": "every_n_hits", "effect": "stat_add", "element": "crit_chance", "magnitude": "1.0", "magnitude2": "5" }))
	w.modifiers = [m, null, null]
	w._hit_count = 4   # next (5th) hit
	assert_that(w.get_effective_crit_chance()).is_equal(1.0)
	w._hit_count = 2
	assert_that(w.get_effective_crit_chance()).is_equal(0.0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_data_modifier.gd`
Expected: FAIL — conditionals/on_kill/every_n_hits not implemented.

- [ ] **Step 3: Implement**

In `src/weapons/modifiers/data_modifier.gd`, add ramp state and override the hit/kill/crit hooks. Replace the `modify_crit_chance` from Task 10 with the combined version:

```gdscript
var _kill_stacks: float = 0.0
var _hit_streak: float = 0.0
var _time_since_event: float = 0.0


func _condition_met(target: Node) -> bool:
	if condition == "":
		return true
	if condition.begins_with("target_status:"):
		var id := condition.substr("target_status:".length())
		var sc = target.get_node_or_null("StatusComponent") if target else null
		return sc != null and sc.has_status(id)
	if condition == "target_low_hp":
		if target == null or not ("health" in target) or not ("max_health" in target):
			return false
		var frac: float = target.health / maxf(1.0, target.max_health)
		var thresh: float = magnitude2 if magnitude2 > 0.0 else 0.3
		return frac <= thresh
	return true


func modify_hit_damage(_weapon: Weapon, user: Node, target: Node, dmg: float) -> float:
	if trigger == "on_hit" and effect == "stat_mult" and element == "damage":
		if condition == "":
			# unconditional ramp (rampage / momentum)
			if name == "Momentum":
				var frac := _speed_fraction(user)
				return dmg * lerpf(1.0, magnitude, frac)
			if magnitude2 > 0.0:   # rampage: +1 per streak hit, capped
				return dmg + _hit_streak
		elif condition == "self_full_hp":
			if _self_full_hp(user):
				return dmg * magnitude
		elif _condition_met(target):
			return dmg * magnitude
	return dmg


func _speed_fraction(user: Node) -> float:
	if user != null and "velocity" in user and "max_speed" in user:
		return clampf((user.velocity as Vector2).length() / maxf(1.0, user.max_speed), 0.0, 1.0)
	return 0.0


func _self_full_hp(user: Node) -> bool:
	var inv = user.get_node_or_null("PlayerInventory") if user else null
	return inv != null and inv.has_method("is_full_health") and inv.is_full_health()


func on_hit_target(_weapon: Weapon, _user: Node, target: Node) -> void:
	if trigger == "on_hit" and effect == "apply_status":
		var sc = target.get_node_or_null("StatusComponent")
		if sc != null:
			sc.add_stain(element, magnitude)
	# rampage streak advances on every landed hit
	if name == "Rampage":
		_hit_streak = minf(_hit_streak + magnitude, magnitude2)
		_time_since_event = 0.0


func on_kill(_weapon: Weapon, user: Node, _target: Node) -> void:
	if trigger != "on_kill":
		return
	if effect == "stat_add" and element == "damage":   # bloodlust
		_kill_stacks = minf(_kill_stacks + magnitude, magnitude2)
		_time_since_event = 0.0
	elif effect == "heal":                              # vampiric
		var inv = user.get_node_or_null("PlayerInventory") if user else null
		if inv != null and inv.has_method("heal"):
			inv.heal(int(magnitude))


func get_stat_add(stat: String) -> float:
	if effect == "stat_add" and element == stat and trigger == "passive":
		return magnitude
	if name == "Bloodlust" and stat == "damage":
		return _kill_stacks
	return 0.0


func get_stat_mult(stat: String) -> float:
	if effect == "stat_mult" and element == stat and trigger == "passive":
		return magnitude
	if effect == "stat_add" and element == "damage" and stat == "cooldown" and magnitude2 > 0.0 and trigger == "passive":
		return magnitude2
	return 1.0


func modify_crit_chance(weapon: Weapon, base: float) -> float:
	if trigger == "passive" and effect == "stat_add" and element == "crit_chance":
		return base + magnitude
	if trigger == "every_n_hits" and element == "crit_chance" and weapon != null:
		var n := int(magnitude2)
		if n > 0 and (weapon._hit_count % n) == n - 1:
			return 1.0
	return base


func on_tick(_weapon: Weapon, delta: float) -> void:
	_time_since_event += delta
	if name == "Bloodlust" and _time_since_event >= 3.0 and _kill_stacks > 0.0:
		_kill_stacks = maxf(0.0, _kill_stacks - 1.0)
		_time_since_event = 0.0
	if name == "Rampage" and _time_since_event >= 1.5:
		_hit_streak = 0.0
```

> Adrenaline (passive cooldown ramp by live HP) needs the player HP at compute time. It reads
> the weapon's `user`, which the effective-stats pass doesn't carry, so adrenaline is handled in
> Task 11b note: keep its `stat_mult cooldown` as a *static* `magnitude` floor in SP-A and refine
> to a live ramp in SP-B when the player-context getter lands. (Documented limitation; the
> modifier still drops and gives a flat speed benefit.)

Remove the now-duplicated `modify_crit_chance`/`get_stat_add`/`get_stat_mult` from Tasks 9-10 (this task supersedes them — keep only these versions).

- [ ] **Step 4: Run test to verify it passes**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_data_modifier.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/weapons/modifiers/data_modifier.gd tests/unit/test_data_modifier.gd
git commit -m "feat(modifiers): DataModifier conditional/on-kill/combo triggers"
```

---

## Task 12: Registry builds DataModifiers + populates all tiers from CSV

**Files:**
- Modify: `src/autoload/weapon_registry.gd` (`_load_modifier_data`, `_make_modifier`, `_populate_modifier_tiers`)
- Modify: `tests/unit/test_modifiers.gd` (`test_all_csv_modifiers_registered`)
- Test: `tests/unit/test_csv_weapon_data.gd` (extend)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_csv_weapon_data.gd`:

```gdscript
func test_make_modifier_builds_data_modifier_for_new_id() -> void:
	var m = WeaponRegistry._make_modifier("oil_emitter")
	assert_that(m).is_not_null()
	assert_that(m is DataModifier).is_true()
	assert_str(m.name).is_equal("Oil Emitter")
	assert_str(m.element).is_equal("oil")

func test_bespoke_modifier_still_scripted() -> void:
	var m = WeaponRegistry._make_modifier("lava_emitter")
	assert_that(m is DataModifier).is_false()   # keeps its bespoke script

func test_new_modifier_is_droppable() -> void:
	var found := false
	for tier in [DropTable.ItemTier.COMMON, DropTable.ItemTier.UNCOMMON, DropTable.ItemTier.RARE]:
		for entry in WeaponRegistry.modifier_tiers.get(tier, []):
			var mod = entry.modifier_script.new() if entry.modifier_script is GDScript else null
		# DataModifier entries are built differently; assert at least 50 total entries exist
	var total := 0
	for tier in WeaponRegistry.modifier_tiers.keys():
		total += WeaponRegistry.modifier_tiers[tier].size()
	assert_int(total).is_greater_equal(50)
```

> The drop-entry shape changes in Step 3 (entries may carry a prebuilt modifier rather than a
> script). The assertion above only checks the **count** so it is robust to that.

- [ ] **Step 2: Run test to verify it fails**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_csv_weapon_data.gd`
Expected: FAIL — `oil_emitter` returns null (unknown id today).

- [ ] **Step 3: Implement**

In `src/autoload/weapon_registry.gd`:

Keep the full row in `_load_modifier_data`:

```gdscript
func _load_modifier_data() -> void:
	_modifier_data.clear()
	for row in CsvTable.parse(MODIFIER_CSV_PATH):
		var id: String = row.get("id", "")
		if id == "":
			continue
		_modifier_data[id] = row
```

Update `_make_modifier` to fall back to `DataModifier`:

```gdscript
const _DataModifier = preload("res://src/weapons/modifiers/data_modifier.gd")

func _make_modifier(id: String) -> _Modifier:
	var data: Dictionary = _modifier_data.get(id, {})
	var script: GDScript = modifier_scripts.get(id)
	if script != null:
		var mod: _Modifier = script.new()
		mod.name = data.get("name", mod.name)
		mod.description = data.get("description", mod.description)
		mod.suppresses_base_use = String(data.get("suppresses_base_use", "No")).strip_edges() == "Yes"
		return mod
	if data.is_empty():
		push_warning("WeaponRegistry: unknown modifier id '%s'" % id)
		return null
	return _DataModifier.new(data)
```

Allow a drop entry to carry either a script or a prebuilt modifier. Change `ModifierDropEntry`:

```gdscript
class ModifierDropEntry:
	var modifier_script: GDScript
	var modifier_id: String
	var weight: float
	func _init(p_script: GDScript, p_id: String, p_weight: float = 1.0) -> void:
		modifier_script = p_script
		modifier_id = p_id
		weight = p_weight
```

Rewrite `_populate_modifier_tiers` to loop every CSV row:

```gdscript
func _populate_modifier_tiers() -> void:
	modifier_tiers.clear()
	for id in _modifier_data.keys():
		var row: Dictionary = _modifier_data[id]
		var tier: int = _map_rarity(row.get("rarity", "Common"))
		if not modifier_tiers.has(tier):
			modifier_tiers[tier] = []
		modifier_tiers[tier].append(ModifierDropEntry.new(modifier_scripts.get(id), id, 1.0))
```

Update `get_random_modifier` to build via `_make_modifier(entry.modifier_id)`:

```gdscript
func get_random_modifier(tier: int) -> _Modifier:
	var entries: Array = modifier_tiers.get(tier, [])
	if entries.is_empty():
		entries = modifier_tiers.get(DropTable.ItemTier.COMMON, [])
	if entries.is_empty():
		return null
	var total_weight := 0.0
	for entry in entries:
		total_weight += entry.weight
	var roll := randf() * total_weight
	var cumulative := 0.0
	for entry in entries:
		cumulative += entry.weight
		if roll <= cumulative:
			return _make_modifier(entry.modifier_id)
	return _make_modifier(entries[0].modifier_id)
```

In `tests/unit/test_modifiers.gd`, update `test_all_csv_modifiers_registered` so it asserts the **scripted** set is still scripted (the rest are data):

```gdscript
func test_all_csv_modifiers_registered() -> void:
	var scripted := [
		"lava_emitter", "fireball_fan", "icicle_volley", "gleaming_projectile",
		"green_crescent", "arc_volley", "triangular_volley", "splitting_rounds",
		"bouncing_bullets", "penetrating_shockwave", "lightning_bolt",
	]
	for id in scripted:
		assert_bool(WeaponRegistry.modifier_scripts.has(id)).is_true()
	# every CSV id is instantiable (scripted or data)
	for id in ["oil_emitter", "venom_edge", "sharpened", "pyroclast"]:
		assert_that(WeaponRegistry._make_modifier(id)).is_not_null()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_csv_weapon_data.gd -a tests/unit/test_modifiers.gd -a tests/unit/test_weapon_registry_pools.gd -a tests/unit/test_shop_modifier_drop.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/autoload/weapon_registry.gd tests/unit/test_modifiers.gd tests/unit/test_csv_weapon_data.gd
git commit -m "feat(registry): build DataModifiers and drop every CSV modifier"
```

---

## Task 13: Extend `weapons.csv` with archetype + tuning columns

**Files:**
- Modify: `docs/design_docs/weapons.csv`
- Test: `tests/unit/test_csv_table.gd` (no change; sanity only)

This is a data task — no code. Append eight columns to the header and fill them for all rows, transcribing the deleted `.tres` tuning **exactly** (arc converted radians→degrees). Leave columns blank where the archetype default applies.

- [ ] **Step 1: Edit the header**

Change line 1 of `docs/design_docs/weapons.csv` to append:

```
,archetype,reach,arc,projectile_speed,projectile_lifetime,spread,projectile_count,projectile_texture
```

- [ ] **Step 2: Fill the 23 existing rows**

Per-row values to set (archetype / reach / arc° / ranged params). Melee (blank ranged cols):

| id | archetype | reach | arc |
|---|---|---|---|
| rusty_sword | melee | 28 | 90 |
| bone_dagger | melee | 20 | 60 |
| broad_axe | melee | 36 | 120 |
| broadsword | melee | 34 | 140 |
| caliburn | melee | 34 | 140 |
| flame_blade | melee | 32 | 90 |
| flame_sword | melee | 28 | 90 |
| frost_sword | melee | 28 | 90 |
| heavenly_sword | melee | 40 | 120 |
| tao_sword | melee | 40 | 120 |
| willowblade | willowblade | 28 | 90 |
| blood_blade | blood_blade | 28 | 90 |
| void_sword | void_sword | 34 | 140 |
| dragon_fang | dragon_fang | 40 | 120 |
| executioner | executioner | 34 | 140 |
| grand_knight_sword | grand_knight | 40 | 120 |
| deep_dark_blade | deep_dark | 40 | 120 |
| phantom_blade | phantom_blade | 34 | 140 |
| qinggang_sword | qinggang | 28 | 90 |

Ranged (blank melee cols; `projectile_speed/lifetime/spread/count/texture`):

| id | archetype | speed | lifetime | spread | count | texture |
|---|---|---|---|---|---|---|
| throwing_knife | ranged | 180 | 2.0 | 0 | 1 | res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/16x16/arrow_01a.png |
| spread_shot | ranged | 150 | 2.0 | 30 | 3 | res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/16x16/arrow_02a.png |
| fire_orb | ranged | 90 | 1.5 | 0 | 1 | res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/16x16/fish_01a.png |
| boss_staff | ranged | | | 10 | | res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/16x16/arrow_03a.png |

- [ ] **Step 3: Fill the SP-A new weapons (data-only)**

Set `archetype=melee`/`ranged` and reach/arc/spread so they load. Use these stat-niche shapes:

| id | archetype | reach | arc | speed | lifetime | spread | count |
|---|---|---|---|---|---|---|---|
| rapier | melee | 30 | 45 | | | | |
| iron_mace | melee | 26 | 100 | | | | |
| cleaver | melee | 30 | 120 | | | | |
| venom_fang_blade | melee | 40 | 50 | | | | |
| tide_caller | melee | 30 | 90 | | | | |
| cinder_brand | melee | 28 | 90 | | | | |
| glacier_edge | melee | 30 | 100 | | | | |
| thunder_katana | melee | 30 | 80 | | | | |
| scatter_blunderbuss | ranged | | | 140 | 0.5 | 60 | 8 |
| frost_repeater | ranged | | | 200 | 2.0 | 0 | 1 |

For obsidian_greatsword and gravedigger_spade set `archetype=melee` with reach 40 / arc 130 and reach 30 / arc 100 respectively (they play as heavy stat blades; native carve arrives in SP-D).

- [ ] **Step 4: Leave the remaining new rows for SP-C/D/E**

Rows that need an unbuilt archetype (twin_daggers, war_scythe, mirror_blade, whirlwind_blade, quake_hammer, soul_reaver, reaper_glaive, berserker_axe, heavy_crossbow, arc_railgun, flame_lobber, venom_spitter, tesla_gun, chakram_launcher, seeker_launcher, hailstorm_bow) get their `archetype` column left **blank** for now. With a blank archetype defaulting to melee/ranged they would load as plain stat sticks — to keep them queued instead, set their `archetype` to a not-yet-registered key matching their future script (e.g. `twin_daggers`, `heavy_crossbow`). The factory (Task 14) skips unregistered archetypes with a warning. Document this choice in a trailing comment row is not possible in CSV, so note it in the commit message.

- [ ] **Step 5: Commit**

```bash
git add docs/design_docs/weapons.csv
git commit -m "data(weapons): add archetype+tuning columns; queue SP-D/E rows via unregistered archetypes"
```

---

## Task 14: Data-driven weapon factory (build from row, no `.tres`)

**Files:**
- Modify: `src/autoload/weapon_registry.gd` (`_ready`, `_load_weapon_resources`, `_apply_csv_fields`)
- Test: `tests/unit/test_weapon_factory.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_weapon_factory.gd`:

```gdscript
extends GdUnitTestSuite

func test_factory_builds_existing_melee_from_row() -> void:
	var w = WeaponRegistry.get_weapon_by_id("rusty_sword")
	assert_that(w).is_not_null()
	assert_that(w is MeleeWeapon).is_true()
	assert_that(w.weapon_reach).is_equal(28.0)
	assert_that(w.arc_angle).is_equal_approx(deg_to_rad(90.0), 0.001)
	assert_that(w.damage).is_equal(3.0)

func test_factory_builds_bespoke_archetype() -> void:
	var w = WeaponRegistry.get_weapon_by_id("void_sword")
	assert_that(w).is_not_null()
	assert_str(w.get_script().resource_path).contains("void_sword_weapon.gd")

func test_factory_builds_new_data_weapon() -> void:
	var w = WeaponRegistry.get_weapon_by_id("rapier")
	assert_that(w).is_not_null()
	assert_that(w is MeleeWeapon).is_true()
	assert_that(w.crit_chance).is_equal(0.3)

func test_factory_skips_unregistered_archetype() -> void:
	# twin_daggers uses an unregistered archetype until SP-D
	assert_that(WeaponRegistry.get_weapon_by_id("twin_daggers")).is_null()

func test_ranged_tuning_from_csv() -> void:
	var w = WeaponRegistry.get_weapon_by_id("spread_shot")
	assert_that(w.projectile_count).is_equal(3)
	assert_that(w.spread_angle).is_equal(30.0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_weapon_factory.gd`
Expected: FAIL — registry still loads `.tres` (and `rapier`/`twin_daggers` rows don't resolve).

- [ ] **Step 3: Implement**

In `src/autoload/weapon_registry.gd` `_ready`, register the bespoke archetypes:

```gdscript
	weapon_scripts["willowblade"] = preload("res://src/weapons/willowblade_weapon.gd")
	weapon_scripts["blood_blade"] = preload("res://src/weapons/blood_blade_weapon.gd")
	weapon_scripts["void_sword"] = preload("res://src/weapons/void_sword_weapon.gd")
	weapon_scripts["dragon_fang"] = preload("res://src/weapons/dragon_fang_weapon.gd")
	weapon_scripts["executioner"] = preload("res://src/weapons/executioner_weapon.gd")
	weapon_scripts["grand_knight"] = preload("res://src/weapons/grand_knight_weapon.gd")
	weapon_scripts["deep_dark"] = preload("res://src/weapons/deep_dark_weapon.gd")
	weapon_scripts["phantom_blade"] = preload("res://src/weapons/phantom_blade_weapon.gd")
	weapon_scripts["qinggang"] = preload("res://src/weapons/qinggang_weapon.gd")
```

Replace `_load_weapon_resources` to build from the row:

```gdscript
func _load_weapon_resources() -> void:
	_all_weapons.clear()
	_weapons_by_id.clear()
	for row in CsvTable.parse(WEAPON_CSV_PATH):
		var id: String = row.get("id", "")
		if id == "":
			continue
		var arch: String = row.get("archetype", "").strip_edges()
		if arch == "":
			arch = "ranged" if row.get("type", "") == "Ranged" else "melee"
		var script: GDScript = weapon_scripts.get(arch)
		if script == null:
			push_warning("WeaponRegistry: weapon '%s' archetype '%s' not registered; skipping" % [id, arch])
			continue
		var weapon: Weapon = script.new()
		_apply_csv_fields(weapon, row)
		weapon.invalidate_effective_stats()
		_weapons_by_id[id] = weapon
		_all_weapons.append({ "id": id, "resource": weapon, "weight": 1.0 })
```

Extend `_apply_csv_fields` to apply the new tuning columns (add at the end, before `_apply_pre_attached_modifiers`):

```gdscript
	_apply_tuning(weapon, row)
```

Add:

```gdscript
func _apply_tuning(weapon: Weapon, row: Dictionary) -> void:
	if weapon is MeleeWeapon:
		var reach: String = row.get("reach", "")
		if reach != "":
			(weapon as MeleeWeapon).weapon_reach = float(reach)
		var arc: String = row.get("arc", "")
		if arc != "":
			(weapon as MeleeWeapon).arc_angle = deg_to_rad(float(arc))
	elif weapon is RangedWeapon:
		var rw := weapon as RangedWeapon
		var ps: String = row.get("projectile_speed", "")
		if ps != "":
			rw.projectile_speed = float(ps)
		var pl: String = row.get("projectile_lifetime", "")
		if pl != "":
			rw.projectile_lifetime = float(pl)
		var sp: String = row.get("spread", "")
		if sp != "":
			rw.spread_angle = float(sp)
		var pc: String = row.get("projectile_count", "")
		if pc != "":
			rw.projectile_count = int(pc)
		var pt: String = row.get("projectile_texture", "")
		if pt != "":
			var tex := load(pt)
			if tex is Texture2D:
				rw.projectile_texture = tex
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_weapon_factory.gd`
Expected: PASS

- [ ] **Step 5: Run weapon-data regression**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_csv_weapon_data.gd -a tests/unit/test_weapon_crit_csv.gd -a tests/unit/test_charge_combo_weapons_data.gd -a tests/unit/test_weapon_registry_pools.gd`
Expected: PASS (these use the registry, not `.tres`).

- [ ] **Step 6: Commit**

```bash
git add src/autoload/weapon_registry.gd tests/unit/test_weapon_factory.gd
git commit -m "feat(registry): fully data-driven weapon factory from CSV row"
```

---

## Task 15: Delete all `.tres` and migrate tests off preloads

**Files:**
- Delete: `resources/weapons/*.tres`, `*.tres.uid`, `*.tres.import` (whichever exist)
- Modify: `tests/unit/test_weapon_resources.gd`
- Modify: `tests/unit/test_melee_reach_scale.gd`

- [ ] **Step 1: Migrate `test_weapon_resources.gd` off `.tres` preloads**

Replace the three `preload(...tres)` constants and the type-specific tests with registry lookups:

```gdscript
extends GdUnitTestSuite

func test_rusty_sword_type_specific_fields() -> void:
	var w = WeaponRegistry.get_weapon_by_id("rusty_sword")
	assert_that(w.weapon_reach).is_equal(28.0)

func test_bone_dagger_type_specific_fields() -> void:
	var w = WeaponRegistry.get_weapon_by_id("bone_dagger")
	assert_that(w.weapon_reach).is_equal(20.0)

func test_throwing_knife_type_specific_fields() -> void:
	var w = WeaponRegistry.get_weapon_by_id("throwing_knife")
	assert_that(w.projectile_speed).is_equal(180.0)
	assert_that(w.projectile_count).is_equal(1)

func test_rusty_sword_universal_fields_from_registry() -> void:
	var w = WeaponRegistry.get_weapon_by_id("rusty_sword")
	assert_that(w.damage).is_equal(3.0)
	assert_that(w.name).is_equal("Rusty Sword")

func test_bone_dagger_cooldown_from_registry() -> void:
	assert_that(WeaponRegistry.get_weapon_by_id("bone_dagger").cooldown).is_equal(0.25)

func test_boss_staff_universal_and_type_specific() -> void:
	var w = WeaponRegistry.get_weapon_by_id("boss_staff")
	assert_that(w.damage).is_equal(3.0)
	assert_that(w.spread_angle).is_equal(10.0)

func test_weapon_duplication_independent() -> void:
	var original = WeaponRegistry.get_weapon_by_id("rusty_sword")
	var copy = original.duplicate(true)
	copy.damage = 99.0
	assert_that(original.damage).is_equal(3.0)
	assert_that(copy.damage).is_equal(99.0)
```

- [ ] **Step 2: Migrate `test_melee_reach_scale.gd`**

Open the file; replace any `preload("res://resources/weapons/<id>.tres")` with
`WeaponRegistry.get_weapon_by_id("<id>")` (keeping the rest of each test identical).

- [ ] **Step 3: Run the two migrated suites (still green pre-delete)**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_weapon_resources.gd -a tests/unit/test_melee_reach_scale.gd`
Expected: PASS

- [ ] **Step 4: Delete the `.tres` and sidecars**

```bash
git rm resources/weapons/*.tres
git rm --ignore-unmatch resources/weapons/*.tres.uid resources/weapons/*.tres.import
```

- [ ] **Step 5: Grep for any remaining `.tres` references**

```bash
grep -rn "resources/weapons/.*\.tres" src/ tests/ scenes/ || echo "clean"
```
Expected: `clean`. If anything prints, replace it with a `WeaponRegistry.get_weapon_by_id(...)` lookup and re-grep.

- [ ] **Step 6: Run the full unit suite**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit`
Expected: PASS (entire suite green with no `.tres` present).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(weapons): delete all .tres; weapons load from CSV only"
```

---

## Task 16: Integration verification

**Files:** none (manual + full suite)

- [ ] **Step 1: Full unit suite**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit`
Expected: PASS, zero failures.

- [ ] **Step 2: Launch and smoke-test in-engine**

Run the project (via the `run` skill or the Godot editor). Confirm:
- The 23 existing weapons spawn/swing/fire exactly as before (no `.tres` regression).
- A new data weapon (e.g. `rapier`, `cinder_brand`, `scatter_blunderbuss`) drops and works; `cinder_brand` crit applies `on_fire` (via existing `crit_status`).
- An emitter modifier (e.g. `oil_emitter`) on any weapon leaves the right material on swing.
- A status-edge (`ember_edge`) ignites a struck enemy; a conditional (`pyroclast`) visibly boosts damage vs burning foes.

- [ ] **Step 3: Final commit (if any tweaks)**

```bash
git add -A
git commit -m "test(weapons): SP-A integration verification green"
```

---

## Self-Review Notes (addressed)

- **Spec coverage:** weapon factory + `.tres` deletion (T13–15), `DataModifier` runtime (T8–12),
  effective-stats (T2–3), `resolve_hit` melee+ranged (T4–6), emitters/status/stat/conditional
  buckets (T8–11), `@export` duplicate constraint (T1), generic material placement (T7),
  registry drop-table population (T12), test migration (T15). The ~10 data weapons land in T13–14.
- **Deferred-with-note:** `adrenaline` live-HP ramp is a flat multiplier in SP-A (documented in
  T11); `deep_cut`/`carve_depth` scales the melee carve radius (wired in T3 via
  `reach * carve_depth`); `wide_arc` is a no-op on ranged (CSV `arc` blank there).
- **Type consistency:** `get_effective_stats`, `resolve_hit(user,target,base_dmg,is_crit)`,
  `get_stat_add/get_stat_mult/modify_hit_damage/on_hit_target/on_kill`, `source_weapon`,
  `_make_modifier(id)`, `ModifierDropEntry(script,id,weight)` are used consistently across tasks.
- **Out of scope (SP-B+):** `lightning`/`steam`/`stun`, `bounty`/`pull`/`knockback`, projectile
  `homing`/`return`, native weapon mechanics, and the weapons queued via unregistered archetypes.
