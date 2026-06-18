# SP-B.1 Modifier Scripts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build behavior for the seven SP-B content modifiers (chain_spark, steam_burst, concussive_edge, repulsor_nova, shockwave_stomp, magnet_field, midas_touch) on top of SP-B's statuses and combat verbs.

**Architecture:** Hybrid. Six modifiers are parameterized verbs added to the existing `DataModifier` dispatch tables (no new files; they route through `WeaponRegistry._make_modifier`'s `DataModifier` fallback). chain_spark — which chains lightning to multiple targets and draws arc VFX — is a bespoke `Modifier` subclass plus a reusable self-drawing `LightningArcFX`. Two small infra additions support them: an `on_crit` modifier hook in `Weapon.resolve_hit`, and a `"pickup"` group on drop nodes.

**Tech Stack:** Godot 4 / GDScript, gdUnit4 tests (headless).

**Spec:** `docs/superpowers/specs/2026-06-16-sp-b1-modifier-scripts-design.md`

**Test command (run from repo root):**
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/<file>.gd
```

---

## File Structure

| File | Responsibility |
|---|---|
| `src/weapons/modifier.gd` | base `Modifier`: add `on_crit` no-op hook |
| `src/weapons/weapon.gd` | `resolve_hit`: invoke `on_crit` on modifiers when `is_crit` |
| `src/drops/gold_drop.gd`, `src/drops/drop.gd` | join `"pickup"` group so magnet_field can find them |
| `src/weapons/modifiers/data_modifier.gd` | dispatch for knockback, pull, bounty, stun, conditional-steam |
| `src/weapons/fx/lightning_arc_fx.gd` | self-drawing jagged bolt + impact starburst VFX |
| `src/weapons/modifiers/chain_spark_modifier.gd` | bespoke on-crit lightning chain |
| `src/autoload/weapon_registry.gd` | register `chain_spark` bespoke script |
| `tests/unit/test_weapon_resolve_hit.gd` | on_crit hook test |
| `tests/unit/test_data_modifier.gd` | knockback / pull / bounty / stun / steam tests |
| `tests/unit/test_lightning_arc_fx.gd` | FX spawn smoke test |
| `tests/unit/test_chain_spark.gd` | chain targeting / range / status tests |

---

## Task 1: `on_crit` modifier hook

**Files:**
- Modify: `src/weapons/modifier.gd`
- Modify: `src/weapons/weapon.gd` (in `resolve_hit`, ~line 175)
- Test: `tests/unit/test_weapon_resolve_hit.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_weapon_resolve_hit.gd` (after the existing `_KillCounter` class, add a new modifier class near the other test classes and two tests at the end):

```gdscript
class _CritCounter extends Modifier:
	var crits: int = 0
	func on_crit(_w, _u, _t) -> void:
		crits += 1

func test_on_crit_hook_fires_on_crit() -> void:
	var w := Weapon.new()
	var cm := _CritCounter.new()
	w.modifiers = [cm, null, null]
	var t := _target()
	w.resolve_hit(null, t, 5.0, true)
	assert_int(cm.crits).is_equal(1)

func test_on_crit_hook_silent_on_non_crit() -> void:
	var w := Weapon.new()
	var cm := _CritCounter.new()
	w.modifiers = [cm, null, null]
	var t := _target()
	w.resolve_hit(null, t, 5.0, false)
	assert_int(cm.crits).is_equal(0)
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_weapon_resolve_hit.gd
```
Expected: FAIL — `on_crit` is not a member of `Modifier` (or crits stays 0).

- [ ] **Step 3: Add the base hook**

In `src/weapons/modifier.gd`, after `on_kill` (around line 51), add:

```gdscript
func on_crit(_weapon: Weapon, _user: Node, _target: Node) -> void:
	pass
```

- [ ] **Step 4: Invoke the hook in resolve_hit**

In `src/weapons/weapon.gd`, in `resolve_hit`, replace the existing crit block:

```gdscript
	if is_crit:
		_on_crit(target)
```

with:

```gdscript
	if is_crit:
		_on_crit(target)
		for m in modifiers:
			if m != null:
				m.on_crit(self, user, target)
```

- [ ] **Step 5: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS (all tests in the file green).

- [ ] **Step 6: Commit**

```bash
git add src/weapons/modifier.gd src/weapons/weapon.gd tests/unit/test_weapon_resolve_hit.gd
git commit -m "feat: add on_crit modifier hook in resolve_hit"
```

---

## Task 2: `"pickup"` group on drops

**Files:**
- Modify: `src/drops/gold_drop.gd` (`_ready`)
- Modify: `src/drops/drop.gd` (`_ready`)
- Test: `tests/unit/test_data_modifier.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_data_modifier.gd`:

```gdscript
func test_gold_drop_joins_pickup_group() -> void:
	var g: GoldDrop = auto_free(preload("res://scenes/gold_drop.tscn").instantiate())
	add_child(g)
	assert_bool(g.is_in_group("pickup")).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_data_modifier.gd
```
Expected: FAIL — not in group "pickup".

- [ ] **Step 3: Add group membership**

In `src/drops/gold_drop.gd` `_ready()`, add as the first line of the function body:

```gdscript
	add_to_group("pickup")
```

In `src/drops/drop.gd` `_ready()`, add as the first line of the function body:

```gdscript
	add_to_group("pickup")
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/drops/gold_drop.gd src/drops/drop.gd tests/unit/test_data_modifier.gd
git commit -m "feat: add drops to pickup group for magnet_field"
```

---

## Task 3: DataModifier — knockback (shockwave_stomp, repulsor_nova)

**Files:**
- Modify: `src/weapons/modifiers/data_modifier.gd`
- Test: `tests/unit/test_data_modifier.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_data_modifier.gd`:

```gdscript
class _KnockTarget extends Node2D:
	var knocks: Array = []
	func _init() -> void:
		add_to_group("attackable")
	func apply_knockback(dir: Vector2, strength: float) -> void:
		knocks.append({ "dir": dir, "strength": strength })

func test_shockwave_stomp_knocks_in_range_on_swing() -> void:
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	var near: _KnockTarget = auto_free(_KnockTarget.new())
	add_child(near)
	near.global_position = Vector2(30, 0)   # within 40*1.8=72
	var far: _KnockTarget = auto_free(_KnockTarget.new())
	add_child(far)
	far.global_position = Vector2(300, 0)   # outside
	var m := DataModifier.new(_row({
		"category": "utility", "trigger": "on_swing", "effect": "knockback", "magnitude": "40",
	}))
	m.on_attack(null, user, { "origin": Vector2.ZERO, "direction": Vector2.RIGHT, "charged": false, "charge_ratio": 0.0 })
	assert_int(near.knocks.size()).is_equal(1)
	assert_that(near.knocks[0]["strength"]).is_equal(40.0)
	assert_int(far.knocks.size()).is_equal(0)

func test_repulsor_nova_only_on_full_charge() -> void:
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	var near: _KnockTarget = auto_free(_KnockTarget.new())
	add_child(near)
	near.global_position = Vector2(50, 0)   # within 80*1.8=144
	var m := DataModifier.new(_row({
		"category": "utility", "trigger": "on_charge", "effect": "knockback", "magnitude": "80",
	}))
	# partial charge: no knockback
	m.on_attack(null, user, { "origin": Vector2.ZERO, "direction": Vector2.RIGHT, "charged": true, "charge_ratio": 0.5 })
	assert_int(near.knocks.size()).is_equal(0)
	# full charge: knockback
	m.on_attack(null, user, { "origin": Vector2.ZERO, "direction": Vector2.RIGHT, "charged": true, "charge_ratio": 1.0 })
	assert_int(near.knocks.size()).is_equal(1)
	assert_that(near.knocks[0]["strength"]).is_equal(80.0)
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_data_modifier.gd
```
Expected: FAIL — knockback effect not dispatched (knocks stays empty).

- [ ] **Step 3: Implement knockback dispatch**

In `src/weapons/modifiers/data_modifier.gd`, add a constant near the top (after `const EMITTER_FORWARD`):

```gdscript
const KNOCKBACK_RADIUS_FACTOR := 1.8
```

Replace the existing `on_attack` method:

```gdscript
func on_attack(_weapon: Weapon, user: Node, ctx: Dictionary) -> void:
	if trigger != "on_swing":
		return
	if effect == "spawn_material":
		_spawn_material(user, ctx)
```

with:

```gdscript
func on_attack(_weapon: Weapon, user: Node, ctx: Dictionary) -> void:
	if effect == "spawn_material" and trigger == "on_swing":
		_spawn_material(user, ctx)
	elif effect == "knockback":
		_do_knockback(user, ctx)
```

Add these methods after `_spawn_material`:

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
	for n in _radial_targets(user, radius):
		var dir: Vector2 = (n as Node2D).global_position - (user as Node2D).global_position
		if dir == Vector2.ZERO:
			dir = Vector2.DOWN
		n.apply_knockback(dir, magnitude)


func _radial_targets(user: Node, radius: float) -> Array:
	var out: Array = []
	var tree := user.get_tree()
	if tree == null:
		return out
	var origin: Vector2 = (user as Node2D).global_position
	var r2: float = radius * radius
	for n in tree.get_nodes_in_group("attackable"):
		if n == user or not is_instance_valid(n) or not (n is Node2D):
			continue
		if not n.has_method("apply_knockback"):
			continue
		if origin.distance_squared_to((n as Node2D).global_position) <= r2:
			out.append(n)
	return out
```

- [ ] **Step 4: Run tests to verify they pass**

Run the same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/modifiers/data_modifier.gd tests/unit/test_data_modifier.gd
git commit -m "feat: DataModifier radial knockback (shockwave_stomp, repulsor_nova)"
```

---

## Task 4: DataModifier — pull (magnet_field)

**Files:**
- Modify: `src/weapons/modifiers/data_modifier.gd`
- Test: `tests/unit/test_data_modifier.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_data_modifier.gd`:

```gdscript
class _FakeGold extends Node2D:
	var _velocity: Vector2 = Vector2.ZERO
	func _init() -> void:
		add_to_group("pickup")

func test_magnet_field_pulls_pickup_in_range() -> void:
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	user.global_position = Vector2.ZERO
	var near: _FakeGold = auto_free(_FakeGold.new())
	add_child(near)
	near.global_position = Vector2(20, 0)    # within 48
	var far: _FakeGold = auto_free(_FakeGold.new())
	add_child(far)
	far.global_position = Vector2(200, 0)    # outside 48
	var m := DataModifier.new(_row({
		"category": "utility", "trigger": "on_swing", "effect": "pull", "magnitude": "48",
	}))
	m.on_attack(null, user, { "origin": Vector2.ZERO, "direction": Vector2.RIGHT, "charged": false, "charge_ratio": 0.0 })
	# near pulled toward user (negative x), far untouched
	assert_that(near._velocity.x).is_less(0.0)
	assert_that(far._velocity).is_equal(Vector2.ZERO)
```

Note: `_FakeGold` is a Node2D stub matching `GoldDrop`'s `_velocity` field. The pull code branches on `is GoldDrop` / `is Drop`; the test additionally needs `_do_pull` to handle a generic Node2D fallback so the stub is exercised. The implementation in Step 3 handles real `GoldDrop`/`Drop` AND a `_velocity`-bearing fallback (covers the stub and is harmless in production).

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_data_modifier.gd
```
Expected: FAIL — pull effect not dispatched (`near._velocity` stays zero).

- [ ] **Step 3: Implement pull dispatch**

In `src/weapons/modifiers/data_modifier.gd`, add a constant near `KNOCKBACK_RADIUS_FACTOR`:

```gdscript
const PULL_IMPULSE := 220.0
```

Extend `on_attack` to add the pull branch:

```gdscript
func on_attack(_weapon: Weapon, user: Node, ctx: Dictionary) -> void:
	if effect == "spawn_material" and trigger == "on_swing":
		_spawn_material(user, ctx)
	elif effect == "knockback":
		_do_knockback(user, ctx)
	elif effect == "pull" and trigger == "on_swing":
		_do_pull(user)
```

Add this method after `_radial_targets`:

```gdscript
func _do_pull(user: Node) -> void:
	if user == null or not (user is Node2D):
		return
	var tree := user.get_tree()
	if tree == null:
		return
	var origin: Vector2 = (user as Node2D).global_position
	var r2: float = magnitude * magnitude
	for n in tree.get_nodes_in_group("pickup"):
		if not is_instance_valid(n) or not (n is Node2D):
			continue
		var to_user: Vector2 = origin - (n as Node2D).global_position
		if to_user.length_squared() > r2:
			continue
		var dir: Vector2 = to_user.normalized()
		if n is RigidBody2D:
			(n as RigidBody2D).apply_central_impulse(dir * PULL_IMPULSE)
		elif "_velocity" in n:
			n._velocity += dir * PULL_IMPULSE
```

(`Drop` is a `RigidBody2D`; `GoldDrop` and the test stub expose `_velocity`. This covers both without importing the drop classes.)

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/modifiers/data_modifier.gd tests/unit/test_data_modifier.gd
git commit -m "feat: DataModifier pull (magnet_field)"
```

---

## Task 5: DataModifier — bounty (midas_touch)

**Files:**
- Modify: `src/weapons/modifiers/data_modifier.gd`
- Test: `tests/unit/test_data_modifier.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_data_modifier.gd`:

```gdscript
class _GoldUser extends Node2D:
	var gold: int = 0
	func _init() -> void:
		var inv := Node.new()
		inv.name = "PlayerInventory"
		inv.set_script(_make_inv_script())
		add_child(inv)
	func _make_inv_script() -> GDScript:
		var s := GDScript.new()
		s.source_code = "extends Node\nvar owner_ref\nfunc add_gold(a: int) -> void:\n\tget_parent().gold += a\n"
		s.reload()
		return s

func test_midas_touch_adds_gold_on_kill() -> void:
	var user: _GoldUser = auto_free(_GoldUser.new())
	add_child(user)
	var m := DataModifier.new(_row({
		"category": "utility", "trigger": "on_kill", "effect": "bounty", "magnitude": "5",
	}))
	m.on_kill(null, user, null)
	assert_int(user.gold).is_equal(5)
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_data_modifier.gd
```
Expected: FAIL — gold stays 0.

- [ ] **Step 3: Implement bounty dispatch**

In `src/weapons/modifiers/data_modifier.gd`, in `on_kill`, add a branch to the existing `if effect == ... elif ...` chain. The method becomes:

```gdscript
func on_kill(_weapon: Weapon, user: Node, _target: Node) -> void:
	if trigger != "on_kill":
		return
	if effect == "stat_add" and element == "damage":
		_kill_stacks = minf(_kill_stacks + magnitude, magnitude2)
		_time_since_event = 0.0
	elif effect == "heal":
		var inv = user.get_node_or_null("PlayerInventory") if user else null
		if inv != null and inv.has_method("heal"):
			inv.heal(int(magnitude))
	elif effect == "bounty":
		var ginv = user.get_node_or_null("PlayerInventory") if user else null
		if ginv != null and ginv.has_method("add_gold"):
			ginv.add_gold(int(magnitude))
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/modifiers/data_modifier.gd tests/unit/test_data_modifier.gd
git commit -m "feat: DataModifier bounty (midas_touch)"
```

---

## Task 6: DataModifier — stun chance (concussive_edge)

**Files:**
- Modify: `src/weapons/modifiers/data_modifier.gd`
- Test: `tests/unit/test_data_modifier.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_data_modifier.gd` (reuses the existing `_StatusTarget` class in the file):

```gdscript
func test_concussive_edge_stuns_when_chance_certain() -> void:
	var t: _StatusTarget = auto_free(_StatusTarget.new())
	add_child(t)
	var m := DataModifier.new(_row({
		"category": "trigger", "trigger": "on_hit", "effect": "stun",
		"magnitude": "0.5", "magnitude2": "1",
	}))
	m.on_hit_target(null, null, t)
	assert_bool(t.get_node("StatusComponent").has_timed_status("stun")).is_true()

func test_concussive_edge_never_stuns_when_chance_zero() -> void:
	var t: _StatusTarget = auto_free(_StatusTarget.new())
	add_child(t)
	var m := DataModifier.new(_row({
		"category": "trigger", "trigger": "on_hit", "effect": "stun",
		"magnitude": "0.5", "magnitude2": "0",
	}))
	m.on_hit_target(null, null, t)
	assert_bool(t.get_node("StatusComponent").has_timed_status("stun")).is_false()
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_data_modifier.gd
```
Expected: FAIL — `test_concussive_edge_stuns_when_chance_certain` fails (no stun applied).

- [ ] **Step 3: Implement stun dispatch**

In `src/weapons/modifiers/data_modifier.gd`, in `on_hit_target`, add a stun branch. After the existing `apply_status` block and before the `if name == "Rampage":` block, insert:

```gdscript
	if trigger == "on_hit" and effect == "stun":
		if randf() < magnitude2:
			var scs = target.get_node_or_null("StatusComponent")
			if scs != null:
				scs.add_timed_status("stun", magnitude)
```

- [ ] **Step 4: Run tests to verify they pass**

Run the same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/modifiers/data_modifier.gd tests/unit/test_data_modifier.gd
git commit -m "feat: DataModifier stun chance (concussive_edge)"
```

---

## Task 7: DataModifier — conditional steam (steam_burst)

**Files:**
- Modify: `src/weapons/modifiers/data_modifier.gd`
- Test: `tests/unit/test_data_modifier.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_data_modifier.gd`:

```gdscript
class _SteamAdapter:
	var steamed: Array = []
	func place_steam(pos: Vector2, radius: float, density: int) -> void:
		steamed.append({ "pos": pos, "radius": radius, "density": density })
	func place_material(_pos: Vector2, _radius: float, _mat: int) -> void:
		pass

func test_steam_burst_erupts_only_on_wet_target() -> void:
	var rec := _SteamAdapter.new()
	var prev: Variant = TerrainSurface.adapter
	TerrainSurface.register_adapter(rec)
	var dry: _StatusTarget = auto_free(_StatusTarget.new())
	add_child(dry)
	var wet: _StatusTarget = auto_free(_StatusTarget.new())
	add_child(wet)
	wet.get_node("StatusComponent").add_stain("wet", 5.0)
	var m := DataModifier.new(_row({
		"category": "trigger", "trigger": "on_hit", "condition": "target_status:wet",
		"effect": "apply_status", "element": "steam", "magnitude": "3",
	}))
	m.on_hit_target(null, null, dry)   # not wet -> nothing
	m.on_hit_target(null, null, wet)   # wet -> steam cloud + stain
	TerrainSurface.register_adapter(prev)
	assert_int(rec.steamed.size()).is_equal(1)
	assert_that(wet.get_node("StatusComponent").get_stain("steam")).is_equal(3.0)
	assert_that(dry.get_node("StatusComponent").get_stain("steam")).is_equal(0.0)

func test_unconditional_status_edge_still_applies() -> void:
	var t: _StatusTarget = auto_free(_StatusTarget.new())
	add_child(t)
	var m := DataModifier.new(_row({
		"category": "status", "trigger": "on_hit", "effect": "apply_status",
		"element": "poisoned", "magnitude": "2",
	}))
	m.on_hit_target(null, null, t)
	assert_that(t.get_node("StatusComponent").get_stain("poisoned")).is_equal(2.0)
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_data_modifier.gd
```
Expected: FAIL — `test_steam_burst_erupts_only_on_wet_target` fails (no `place_steam`; or steam stain applied unconditionally to dry target by the old code path).

- [ ] **Step 3: Implement conditional + steam-cloud dispatch**

In `src/weapons/modifiers/data_modifier.gd`, add constants near the others:

```gdscript
const STEAM_BURST_RADIUS := 14.0
const STEAM_BURST_DENSITY := 180
```

Replace the existing `apply_status` block at the top of `on_hit_target`:

```gdscript
	if trigger == "on_hit" and effect == "apply_status":
		var sc = target.get_node_or_null("StatusComponent")
		if sc != null:
			sc.add_stain(element, magnitude)
```

with:

```gdscript
	if trigger == "on_hit" and effect == "apply_status" and _condition_met(target):
		var sc = target.get_node_or_null("StatusComponent")
		if sc != null:
			if element == "steam":
				if target is Node2D:
					TerrainSurface.place_steam((target as Node2D).global_position, STEAM_BURST_RADIUS, STEAM_BURST_DENSITY)
				sc.add_stain("steam", magnitude)
			else:
				sc.add_stain(element, magnitude)
```

(The `_condition_met` helper already exists and returns `true` for an empty condition, so the SP-A status-edge modifiers are unaffected.)

- [ ] **Step 4: Run tests to verify they pass**

Run the same command as Step 2.
Expected: PASS (all tests in the file, including the existing `test_status_edge_stains_target_on_hit`).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/modifiers/data_modifier.gd tests/unit/test_data_modifier.gd
git commit -m "feat: DataModifier conditional steam burst (steam_burst)"
```

---

## Task 8: `LightningArcFX` self-drawing VFX

**Files:**
- Create: `src/weapons/fx/lightning_arc_fx.gd`
- Test: `tests/unit/test_lightning_arc_fx.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_lightning_arc_fx.gd`:

```gdscript
extends GdUnitTestSuite

func test_play_spawns_fx_node_under_host() -> void:
	var host: Node2D = auto_free(Node2D.new())
	add_child(host)
	LightningArcFX.play(host, Vector2.ZERO, Vector2(40, 0), Color(0.9, 0.95, 1.0))
	assert_int(host.get_child_count()).is_equal(1)
	assert_bool(host.get_child(0) is LightningArcFX).is_true()

func test_play_null_host_is_noop() -> void:
	# must not crash
	LightningArcFX.play(null, Vector2.ZERO, Vector2(10, 0), Color.WHITE)
	assert_bool(true).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_lightning_arc_fx.gd
```
Expected: FAIL — `LightningArcFX` is not a known class.

- [ ] **Step 3: Implement the FX**

Create `src/weapons/fx/lightning_arc_fx.gd`:

```gdscript
class_name LightningArcFX
extends Node2D

const SEGMENTS := 7
const JITTER := 6.0
const LIFETIME := 0.15

var _points: PackedVector2Array = PackedVector2Array()
var _end: Vector2 = Vector2.ZERO
var _tint: Color = Color(0.9, 0.95, 1.0)


static func play(host: Node, from: Vector2, to: Vector2, tint: Color) -> void:
	if host == null:
		return
	var fx := LightningArcFX.new()
	host.add_child(fx)
	fx.global_position = from
	fx._setup(to - from, tint)


func _setup(delta: Vector2, tint: Color) -> void:
	_tint = tint
	_end = delta
	_build_points(delta)
	queue_redraw()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, LIFETIME)
	tw.tween_callback(queue_free)


func _build_points(delta: Vector2) -> void:
	_points = PackedVector2Array()
	var perp := Vector2(-delta.y, delta.x).normalized()
	for i in range(SEGMENTS + 1):
		var t := float(i) / float(SEGMENTS)
		var base := delta * t
		var off := 0.0
		if i != 0 and i != SEGMENTS:
			off = randf_range(-JITTER, JITTER)
		_points.append(base + perp * off)


func _draw() -> void:
	if _points.size() >= 2:
		draw_polyline(_points, Color(_tint.r, _tint.g, _tint.b, 0.35), 3.0)
		draw_polyline(_points, _tint, 1.0)
	draw_circle(_end, 3.0, _tint)
	for i in range(4):
		var a := PI * 0.5 * float(i) + PI * 0.25
		draw_line(_end, _end + Vector2(cos(a), sin(a)) * 6.0, _tint, 1.0)
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/fx/lightning_arc_fx.gd tests/unit/test_lightning_arc_fx.gd
git commit -m "feat: add LightningArcFX self-drawing arc VFX"
```

---

## Task 9: `chain_spark` bespoke modifier + registration

**Files:**
- Create: `src/weapons/modifiers/chain_spark_modifier.gd`
- Modify: `src/autoload/weapon_registry.gd` (`_ready`, ~line 72)
- Test: `tests/unit/test_chain_spark.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/unit/test_chain_spark.gd`:

```gdscript
extends GdUnitTestSuite

class _SparkEnemy extends Node2D:
	var hit_dmg: int = -1
	func _init() -> void:
		add_to_group("attackable")
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)
	func on_hit_impact(_p: Vector2, _d: Vector2, dmg: int) -> void:
		hit_dmg = dmg

func test_chain_spark_hits_up_to_three_nearest() -> void:
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	var enemies: Array = []
	for i in range(5):
		var e: _SparkEnemy = auto_free(_SparkEnemy.new())
		add_child(e)
		e.global_position = Vector2(10.0 * float(i + 1), 0.0)   # x = 10..50, all within RANGE
		enemies.append(e)
	var m := ChainSparkModifier.new()
	m.on_crit(null, user, null)
	var hits := 0
	for e in enemies:
		if e.hit_dmg >= 0:
			hits += 1
	assert_int(hits).is_equal(3)
	# nearest three got lightning status
	assert_that(enemies[0].get_node("StatusComponent").get_timed_remaining("lightning")).is_greater(0.0)

func test_chain_spark_respects_range() -> void:
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	var near: _SparkEnemy = auto_free(_SparkEnemy.new())
	add_child(near)
	near.global_position = Vector2(20.0, 0.0)
	var far: _SparkEnemy = auto_free(_SparkEnemy.new())
	add_child(far)
	far.global_position = Vector2(500.0, 0.0)   # outside RANGE 160
	var m := ChainSparkModifier.new()
	m.on_crit(null, user, null)
	assert_bool(near.hit_dmg >= 0).is_true()
	assert_bool(far.hit_dmg >= 0).is_false()
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_chain_spark.gd
```
Expected: FAIL — `ChainSparkModifier` is not a known class.

- [ ] **Step 3: Implement the modifier**

Create `src/weapons/modifiers/chain_spark_modifier.gd`:

```gdscript
class_name ChainSparkModifier
extends Modifier

const RANGE := 160.0
const DAMAGE := 6
const LIGHTNING_DURATION := 0.4
const STUN_CHANCE := 0.25
const STUN_DURATION := 0.3
const TINT := Color(0.9, 0.95, 1.0)

var chain_count: int = 3


func _init() -> void:
	name = "Chain Spark"
	description = "Critical hits arc lightning to nearby enemies, with a chance to stun."


func on_crit(_weapon: Weapon, user: Node, _target: Node) -> void:
	if user == null or not (user is Node2D):
		return
	var host := _resolve_host(user)
	var origin: Vector2 = (user as Node2D).global_position
	for n in _nearest_targets(user, chain_count, RANGE):
		var pos: Vector2 = (n as Node2D).global_position
		if n.has_method("on_hit_impact"):
			n.on_hit_impact(pos, (pos - origin).normalized(), DAMAGE)
		var sc = n.get_node_or_null("StatusComponent")
		if sc != null:
			sc.add_timed_status("lightning", LIGHTNING_DURATION)
			if randf() < STUN_CHANCE:
				sc.add_timed_status("stun", STUN_DURATION)
		LightningArcFX.play(host, origin, pos, TINT)


func _nearest_targets(user: Node, count: int, range_px: float) -> Array:
	var tree := user.get_tree()
	if tree == null:
		return []
	var origin: Vector2 = (user as Node2D).global_position
	var r2: float = range_px * range_px
	var candidates: Array = []
	for n in tree.get_nodes_in_group("attackable"):
		if n == user or not is_instance_valid(n) or not (n is Node2D):
			continue
		var d: float = origin.distance_squared_to((n as Node2D).global_position)
		if d <= r2:
			candidates.append({ "node": n, "d": d })
	candidates.sort_custom(func(a, b): return a["d"] < b["d"])
	var out: Array = []
	for i in range(mini(count, candidates.size())):
		out.append(candidates[i]["node"])
	return out


func _resolve_host(user: Node) -> Node:
	var tree := user.get_tree()
	if tree != null:
		var wm := tree.get_first_node_in_group("world_manager")
		if wm != null and wm.has_method("get_chunk_container"):
			var c = wm.get_chunk_container()
			if c != null:
				return c
	return user.get_parent()
```

- [ ] **Step 4: Run tests to verify they pass**

Run the same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Register the bespoke script**

In `src/autoload/weapon_registry.gd`, in `_ready`, after the existing `modifier_scripts["lightning_bolt"] = ...` line, add:

```gdscript
	modifier_scripts["chain_spark"] = preload("res://src/weapons/modifiers/chain_spark_modifier.gd")
```

- [ ] **Step 6: Verify registration with the full unit suite**

Run the whole unit test directory to confirm nothing regressed and chain_spark loads:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit
```
Expected: PASS (no load errors, all suites green).

- [ ] **Step 7: Commit**

```bash
git add src/weapons/modifiers/chain_spark_modifier.gd src/autoload/weapon_registry.gd tests/unit/test_chain_spark.gd
git commit -m "feat: add chain_spark modifier and register bespoke script"
```

---

## Task 10: Full suite verification + todo update

**Files:**
- Modify: `docs/design_docs/implementation_todo.md` (SP-B.1 rows)

- [ ] **Step 1: Run the entire unit test suite**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit
```
Expected: PASS — all suites green, no `.gd` load/parse errors in output.

- [ ] **Step 2: Mark SP-B.1 tasks done**

In `docs/design_docs/implementation_todo.md`, under `### Sub-project B.1 (6.5): SP-B modifier scripts`, change the three rows' `Done` column from blank to `x`:

```markdown
| x | P2 | Medium | chain_spark, steam_burst, concussive_edge | New on_hit/on_crit modifiers |
| x | P2 | Medium | repulsor_nova, shockwave_stomp | Knockback/area modifiers |
| x | P2 | Medium | magnet_field, midas_touch | Pull/bounty utility modifiers |
```

- [ ] **Step 3: Commit**

```bash
git add docs/design_docs/implementation_todo.md
git commit -m "docs: mark SP-B.1 modifier scripts complete"
```

---

## Self-Review Notes

- **Spec coverage:** on_crit hook (§3.1 → Task 1); pickup group (§3.2 → Task 2); knockback §4.1 → Task 3; pull §4.2 → Task 4; bounty §4.3 → Task 5; stun §4.4 → Task 6; conditional steam §4.5 → Task 7; LightningArcFX §6 → Task 8; chain_spark §5 + registration §7 → Task 9; testing §9 spread across tasks; acceptance §10 → Task 10. All covered.
- **Type consistency:** `_radial_targets(user, radius)` defined in Task 3, not reused elsewhere (pull uses the `"pickup"` group directly). `LightningArcFX.play(host, from, to, tint)` signature matches its call in chain_spark. `add_timed_status(id, duration)`, `get_timed_remaining(id)`, `add_stain(id, amt)`, `add_gold(int)`, `heal(int)`, `place_steam(pos, radius, density)` all match existing source signatures.
- **Registration note:** the six DataModifier-backed modifiers need no registration — `WeaponRegistry._make_modifier` already falls back to `DataModifier.new(row)` for any id without a bespoke script. Only chain_spark is registered (Task 9 Step 5).
