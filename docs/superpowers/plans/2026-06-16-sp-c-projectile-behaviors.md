# SP-C: New Projectile Behaviors + Projectile Modifiers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the six remaining `projectile`-category modifiers (`homing_hex`, `boomerang_arc`, `ricochet_shard`, `piercing_lance`, `cluster_bomb`, `spectral_echo`) by adding two new steering behaviors and reusing the existing SP-3 projectile-behavior foundations.

**Architecture:** Two new `ProjectileBehavior` subclasses (`HomingBehavior`, `ReturnBehavior`) plus six bespoke `ProjectileModifier` scripts registered by id in `weapon_registry.gd`. `ricochet_shard`/`piercing_lance`/`cluster_bomb` reuse existing `BounceBehavior`/`PenetrateBehavior`/`SplitBehavior`; `cluster_bomb` needs a small `shard_hit_status` addition to `SplitBehavior`. `spectral_echo` schedules a delayed ghost projectile via a SceneTree timer — no new behavior class.

**Tech Stack:** Godot 4 / GDScript, gdUnit4 tests (headless).

**Spec:** `docs/superpowers/specs/2026-06-16-sp-c-projectile-behaviors-design.md`

**Reference patterns (read before starting):**
- Behavior base + concretes: `src/weapons/projectile_behaviors/projectile_behavior.gd`, `bounce_behavior.gd`, `split_behavior.gd`, `penetrate_behavior.gd`
- Modifier base + bespoke examples: `src/weapons/modifiers/projectile_modifier.gd`, `gleaming_projectile_modifier.gd`, `bouncing_bullets_modifier.gd`, `penetrating_shockwave_modifier.gd`
- Spawn helper: `src/weapons/modifiers/modifier_projectile.gd`
- Registry: `src/autoload/weapon_registry.gd` (`_ready()` registration block, `_make_modifier`)
- Existing tests to mirror: `tests/unit/test_projectile_behaviors.gd`, `tests/unit/test_modifiers.gd`

**Running tests (used throughout):**
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_projectile_behaviors.gd
```
For modifier tests swap the `-a` target to `res://tests/unit/test_modifiers.gd`. The `--import` step is required after adding new `.gd` files so Godot registers their `class_name`.

---

## Task 1: Add `shard_hit_status` to `SplitBehavior`

Lets shards carry a status (used by `cluster_bomb` to apply `burn`). Default `""` keeps `splitting_rounds` unchanged.

**Files:**
- Modify: `src/weapons/projectile_behaviors/split_behavior.gd`
- Test: `tests/unit/test_projectile_behaviors.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_projectile_behaviors.gd`:

```gdscript
func test_split_shards_inherit_hit_status_when_set() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var p: Projectile = Projectile.new()
	p.is_enemy_projectile = false
	p.damage = 10.0
	var b := SplitBehavior.new()
	b.shard_count = 3
	b.shard_hit_status = "burn"
	p.behaviors = [b]
	parent.add_child(p)
	var target: Enemy = auto_free(Enemy.new())
	parent.add_child(target)
	p._handle_hit(target)
	await get_tree().process_frame
	for c in parent.get_children():
		if c is Projectile:
			assert_str(c.hit_status).is_equal("burn")

func test_split_shards_default_no_hit_status() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var p: Projectile = Projectile.new()
	p.is_enemy_projectile = false
	p.damage = 10.0
	var b := SplitBehavior.new()
	b.shard_count = 2
	p.behaviors = [b]
	parent.add_child(p)
	var target: Enemy = auto_free(Enemy.new())
	parent.add_child(target)
	p._handle_hit(target)
	await get_tree().process_frame
	for c in parent.get_children():
		if c is Projectile:
			assert_str(c.hit_status).is_equal("")
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_projectile_behaviors.gd
```
Expected: FAIL — `Invalid set index 'shard_hit_status'` (member does not exist on `SplitBehavior`).

- [ ] **Step 3: Add the field and assignment**

In `src/weapons/projectile_behaviors/split_behavior.gd`, add the field after the existing `var spawn_offset: float = 12.0` line:

```gdscript
var shard_hit_status: String = ""
```

Then in `_split()`, immediately after the line `shard.collisionless_time = shard_collisionless_time`, add:

```gdscript
		if shard_hit_status != "":
			shard.hit_status = shard_hit_status
```

- [ ] **Step 4: Run tests to verify they pass**

Run the same command as Step 2.
Expected: PASS — both new tests green, and the existing `test_split_*` tests still pass.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/projectile_behaviors/split_behavior.gd tests/unit/test_projectile_behaviors.gd
git commit -m "feat: add shard_hit_status to SplitBehavior"
```

---

## Task 2: `HomingBehavior`

Steers a projectile toward the nearest enemy each frame, capped by a max turn rate.

**Files:**
- Create: `src/weapons/projectile_behaviors/homing_behavior.gd`
- Test: `tests/unit/test_projectile_behaviors.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_projectile_behaviors.gd`:

```gdscript
func test_homing_turns_toward_target_capped() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var p: Projectile = auto_free(Projectile.new())
	p.is_enemy_projectile = false
	p.direction = Vector2.RIGHT  # angle 0
	parent.add_child(p)
	p.global_position = Vector2.ZERO
	var target: Node2D = auto_free(Node2D.new())
	target.add_to_group("attackable")
	parent.add_child(target)
	target.global_position = Vector2(0, 100)  # desired angle +PI/2
	var b := HomingBehavior.new()
	b.turn_rate_rad = PI * 2.0
	b.on_process(p, 0.1)  # max step 0.628 rad
	# Turned toward target but capped short of PI/2.
	assert_float(p.direction.angle()).is_greater(0.0)
	assert_float(p.direction.angle()).is_less(PI / 2.0)

func test_homing_no_target_keeps_direction() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var p: Projectile = auto_free(Projectile.new())
	p.is_enemy_projectile = false
	p.direction = Vector2.RIGHT
	parent.add_child(p)
	var b := HomingBehavior.new()
	b.on_process(p, 0.1)
	assert_float(p.direction.angle()).is_equal_approx(0.0, 0.0001)
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_projectile_behaviors.gd
```
Expected: FAIL — `Identifier "HomingBehavior" not declared`.

- [ ] **Step 3: Create the behavior**

Create `src/weapons/projectile_behaviors/homing_behavior.gd`:

```gdscript
class_name HomingBehavior
extends ProjectileBehavior

var turn_rate_rad: float = PI * 2.0


func on_process(proj, delta: float) -> void:
	var target := _nearest_target(proj)
	if target == null:
		return
	var desired: Vector2 = target.global_position - proj.global_position
	if desired == Vector2.ZERO:
		return
	var cur_angle: float = proj.direction.angle()
	var diff: float = angle_difference(cur_angle, desired.angle())
	var max_step: float = turn_rate_rad * delta
	var new_angle: float = cur_angle + clampf(diff, -max_step, max_step)
	proj.direction = Vector2(cos(new_angle), sin(new_angle))


func _nearest_target(proj) -> Node2D:
	var tree := proj.get_tree()
	if tree == null:
		return null
	var group: String = "player" if proj.is_enemy_projectile else "attackable"
	var best: Node2D = null
	var best_d2: float = INF
	for n in tree.get_nodes_in_group(group):
		if n == proj.source_node or not is_instance_valid(n) or not (n is Node2D):
			continue
		var d2: float = proj.global_position.distance_squared_to((n as Node2D).global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = n
	return best
```

- [ ] **Step 4: Run tests to verify they pass**

Run the same command as Step 2.
Expected: PASS — both homing tests green.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/projectile_behaviors/homing_behavior.gd tests/unit/test_projectile_behaviors.gd
git commit -m "feat: add HomingBehavior steering"
```

---

## Task 3: `ReturnBehavior`

Flies outbound for `out_time`, then reverses toward the source node; passes through enemies so it hits on both legs.

**Files:**
- Create: `src/weapons/projectile_behaviors/return_behavior.gd`
- Test: `tests/unit/test_projectile_behaviors.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_projectile_behaviors.gd`:

```gdscript
func test_return_reverses_toward_source_after_out_time() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var source: Node2D = auto_free(Node2D.new())
	parent.add_child(source)
	source.global_position = Vector2.ZERO
	var p: Projectile = auto_free(Projectile.new())
	p.direction = Vector2.RIGHT
	p.source_node = source
	parent.add_child(p)
	p.global_position = Vector2(100, 0)
	var b := ReturnBehavior.new()
	b.out_time = 0.5
	b.on_spawn(p)
	# Before out_time: outbound, unchanged.
	b.on_process(p, 0.1)
	assert_float(p.direction.x).is_greater(0.0)
	# Cross out_time, then steer: now points back toward source (-X).
	b.on_process(p, 0.5)
	b.on_process(p, 0.1)
	assert_float(p.direction.x).is_less(0.0)

func test_return_passes_through_enemies() -> void:
	var b := ReturnBehavior.new()
	var p: Projectile = auto_free(Projectile.new())
	assert_bool(b.on_enemy_hit(p, null)).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_projectile_behaviors.gd
```
Expected: FAIL — `Identifier "ReturnBehavior" not declared`.

- [ ] **Step 3: Create the behavior**

Create `src/weapons/projectile_behaviors/return_behavior.gd`:

```gdscript
class_name ReturnBehavior
extends ProjectileBehavior

var out_time: float = 0.5
var return_catch_radius: float = 14.0
var _elapsed: float = 0.0
var _returning: bool = false
var _source: Node2D = null


func on_spawn(proj) -> void:
	_elapsed = 0.0
	_returning = false
	if proj.source_node is Node2D:
		_source = proj.source_node


func on_process(proj, delta: float) -> void:
	_elapsed += delta
	if not _returning:
		if _elapsed >= out_time:
			_returning = true
		return
	if _source == null or not is_instance_valid(_source):
		return
	var to_src: Vector2 = _source.global_position - proj.global_position
	if to_src.length() <= return_catch_radius:
		proj.queue_free()
		return
	proj.direction = to_src.normalized()


func on_enemy_hit(_proj, _target) -> bool:
	return true
```

- [ ] **Step 4: Run tests to verify they pass**

Run the same command as Step 2.
Expected: PASS — both return tests green.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/projectile_behaviors/return_behavior.gd tests/unit/test_projectile_behaviors.gd
git commit -m "feat: add ReturnBehavior steering"
```

---

## Task 4: `ricochet_shard` + `piercing_lance` modifiers (reuse behaviors)

Two simple on-swing modifiers reusing `BounceBehavior` and `PenetrateBehavior`. Register both in the registry.

**Files:**
- Create: `src/weapons/modifiers/ricochet_shard_modifier.gd`
- Create: `src/weapons/modifiers/piercing_lance_modifier.gd`
- Modify: `src/autoload/weapon_registry.gd` (registration block in `_ready()`)
- Test: `tests/unit/test_modifiers.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_modifiers.gd`:

```gdscript
func test_ricochet_shard_has_bounce_behavior() -> void:
	var pu := _spawn_parent_and_user()
	RicochetShardModifier.new().on_attack(null, pu[1], _ctx())
	assert_int(_count_projectiles(pu[0])).is_equal(1)
	for c in pu[0].get_children():
		if c is Projectile:
			assert_that(c.behaviors[0] is BounceBehavior).is_true()
			assert_int((c.behaviors[0] as BounceBehavior).max_bounces).is_equal(3)

func test_piercing_lance_has_penetrate_behavior() -> void:
	var pu := _spawn_parent_and_user()
	PiercingLanceModifier.new().on_attack(null, pu[1], _ctx())
	assert_int(_count_projectiles(pu[0])).is_equal(1)
	for c in pu[0].get_children():
		if c is Projectile:
			assert_that(c.behaviors[0] is PenetrateBehavior).is_true()
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_modifiers.gd
```
Expected: FAIL — `Identifier "RicochetShardModifier" not declared`.

- [ ] **Step 3: Create the two modifiers**

Create `src/weapons/modifiers/ricochet_shard_modifier.gd`:

```gdscript
class_name RicochetShardModifier
extends ProjectileModifier

const SHARD_DAMAGE := 3.0
const BOUNCES := 3

func _init() -> void:
	name = "Ricochet Shard"
	description = "Swings fling a shard that ricochets off walls, striking again."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon, user, ctx) -> void:
	var b := BounceBehavior.new()
	b.max_bounces = BOUNCES
	ModifierProjectile.spawn_one(user, ctx["origin"], ctx["direction"], SHARD_DAMAGE,
		{ "behaviors": [b], "tint": Color(0.8, 0.9, 1.0) })
```

Create `src/weapons/modifiers/piercing_lance_modifier.gd`:

```gdscript
class_name PiercingLanceModifier
extends ProjectileModifier

const LANCE_DAMAGE := 4.0
const LANCE_LIFETIME := 2.0

func _init() -> void:
	name = "Piercing Lance"
	description = "Looses a lance that skewers every foe in a line."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_one(user, ctx["origin"], ctx["direction"], LANCE_DAMAGE,
		{ "behaviors": [PenetrateBehavior.new()], "lifetime": LANCE_LIFETIME, "tint": Color(1.0, 0.9, 0.5) })
```

- [ ] **Step 4: Register both ids**

In `src/autoload/weapon_registry.gd`, in `_ready()` immediately after the line
`modifier_scripts["chain_spark"] = preload("res://src/weapons/modifiers/chain_spark_modifier.gd")`, add:

```gdscript
	modifier_scripts["ricochet_shard"] = preload("res://src/weapons/modifiers/ricochet_shard_modifier.gd")
	modifier_scripts["piercing_lance"] = preload("res://src/weapons/modifiers/piercing_lance_modifier.gd")
```

- [ ] **Step 5: Run tests to verify they pass**

Run the same command as Step 2.
Expected: PASS — both new modifier tests green.

- [ ] **Step 6: Commit**

```bash
git add src/weapons/modifiers/ricochet_shard_modifier.gd src/weapons/modifiers/piercing_lance_modifier.gd src/autoload/weapon_registry.gd tests/unit/test_modifiers.gd
git commit -m "feat: add ricochet_shard and piercing_lance modifiers"
```

---

## Task 5: `cluster_bomb` modifier (reuse SplitBehavior + burn)

A single bomb projectile that, on impact, bursts into an 8-shard 360° ring whose shards apply `burn`.

**Files:**
- Create: `src/weapons/modifiers/cluster_bomb_modifier.gd`
- Modify: `src/autoload/weapon_registry.gd`
- Test: `tests/unit/test_modifiers.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_modifiers.gd`:

```gdscript
func test_cluster_bomb_has_split_behavior_with_burn_ring() -> void:
	var pu := _spawn_parent_and_user()
	ClusterBombModifier.new().on_attack(null, pu[1], _ctx())
	assert_int(_count_projectiles(pu[0])).is_equal(1)
	for c in pu[0].get_children():
		if c is Projectile:
			var sb := c.behaviors[0] as SplitBehavior
			assert_that(sb).is_not_null()
			assert_int(sb.shard_count).is_equal(8)
			assert_float(sb.spread_deg).is_equal(360.0)
			assert_str(sb.shard_hit_status).is_equal("burn")
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_modifiers.gd
```
Expected: FAIL — `Identifier "ClusterBombModifier" not declared`.

- [ ] **Step 3: Create the modifier**

Create `src/weapons/modifiers/cluster_bomb_modifier.gd`:

```gdscript
class_name ClusterBombModifier
extends ProjectileModifier

const BOMB_DAMAGE := 5.0
const FRAGMENTS := 8

func _init() -> void:
	name = "Cluster Bomb"
	description = "Hurls a bomb that bursts into a ring of fragments."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon, user, ctx) -> void:
	var sb := SplitBehavior.new()
	sb.shard_count = FRAGMENTS
	sb.spread_deg = 360.0
	sb.shard_hit_status = "burn"
	ModifierProjectile.spawn_one(user, ctx["origin"], ctx["direction"], BOMB_DAMAGE,
		{ "behaviors": [sb], "tint": Color(1.0, 0.6, 0.3) })
```

- [ ] **Step 4: Register the id**

In `src/autoload/weapon_registry.gd` `_ready()`, after the `piercing_lance` line added in Task 4, add:

```gdscript
	modifier_scripts["cluster_bomb"] = preload("res://src/weapons/modifiers/cluster_bomb_modifier.gd")
```

- [ ] **Step 5: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS — `test_cluster_bomb_has_split_behavior_with_burn_ring` green.

- [ ] **Step 6: Commit**

```bash
git add src/weapons/modifiers/cluster_bomb_modifier.gd src/autoload/weapon_registry.gd tests/unit/test_modifiers.gd
git commit -m "feat: add cluster_bomb modifier"
```

---

## Task 6: `homing_hex` + `boomerang_arc` modifiers (new behaviors)

On-swing modifiers wiring the two new steering behaviors.

**Files:**
- Create: `src/weapons/modifiers/homing_hex_modifier.gd`
- Create: `src/weapons/modifiers/boomerang_arc_modifier.gd`
- Modify: `src/autoload/weapon_registry.gd`
- Test: `tests/unit/test_modifiers.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_modifiers.gd`:

```gdscript
func test_homing_hex_has_homing_behavior() -> void:
	var pu := _spawn_parent_and_user()
	HomingHexModifier.new().on_attack(null, pu[1], _ctx())
	assert_int(_count_projectiles(pu[0])).is_equal(1)
	for c in pu[0].get_children():
		if c is Projectile:
			assert_that(c.behaviors[0] is HomingBehavior).is_true()

func test_boomerang_arc_has_return_behavior() -> void:
	var pu := _spawn_parent_and_user()
	BoomerangArcModifier.new().on_attack(null, pu[1], _ctx())
	assert_int(_count_projectiles(pu[0])).is_equal(1)
	for c in pu[0].get_children():
		if c is Projectile:
			assert_that(c.behaviors[0] is ReturnBehavior).is_true()
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_modifiers.gd
```
Expected: FAIL — `Identifier "HomingHexModifier" not declared`.

- [ ] **Step 3: Create the two modifiers**

Create `src/weapons/modifiers/homing_hex_modifier.gd`:

```gdscript
class_name HomingHexModifier
extends ProjectileModifier

const HEX_DAMAGE := 3.0

func _init() -> void:
	name = "Homing Hex"
	description = "Every swing looses a bolt that curves toward the nearest foe."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_one(user, ctx["origin"], ctx["direction"], HEX_DAMAGE,
		{ "behaviors": [HomingBehavior.new()], "tint": Color(0.7, 0.4, 1.0) })
```

Create `src/weapons/modifiers/boomerang_arc_modifier.gd`:

```gdscript
class_name BoomerangArcModifier
extends ProjectileModifier

const ARC_DAMAGE := 3.0

func _init() -> void:
	name = "Boomerang Arc"
	description = "Throws a blade-arc that returns, hitting foes both ways."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_one(user, ctx["origin"], ctx["direction"], ARC_DAMAGE,
		{ "behaviors": [ReturnBehavior.new()], "tint": Color(0.9, 0.85, 0.6) })
```

- [ ] **Step 4: Register both ids**

In `src/autoload/weapon_registry.gd` `_ready()`, after the `cluster_bomb` line added in Task 5, add:

```gdscript
	modifier_scripts["homing_hex"] = preload("res://src/weapons/modifiers/homing_hex_modifier.gd")
	modifier_scripts["boomerang_arc"] = preload("res://src/weapons/modifiers/boomerang_arc_modifier.gd")
```

- [ ] **Step 5: Run tests to verify they pass**

Run the same command as Step 2.
Expected: PASS — both new modifier tests green.

- [ ] **Step 6: Commit**

```bash
git add src/weapons/modifiers/homing_hex_modifier.gd src/weapons/modifiers/boomerang_arc_modifier.gd src/autoload/weapon_registry.gd tests/unit/test_modifiers.gd
git commit -m "feat: add homing_hex and boomerang_arc modifiers"
```

---

## Task 7: `spectral_echo` modifier (delayed ghost projectile)

On swing, schedules a translucent half-damage projectile ~0.3s later via a SceneTree timer.

**Files:**
- Create: `src/weapons/modifiers/spectral_echo_modifier.gd`
- Modify: `src/autoload/weapon_registry.gd`
- Test: `tests/unit/test_modifiers.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_modifiers.gd`:

```gdscript
func test_spectral_echo_spawn_is_translucent_ghost() -> void:
	var pu := _spawn_parent_and_user()
	var m := SpectralEchoModifier.new()
	m._spawn_echo(pu[1], Vector2.ZERO, Vector2.RIGHT)
	assert_int(_count_projectiles(pu[0])).is_equal(1)
	for c in pu[0].get_children():
		if c is Projectile:
			assert_float(c.damage).is_equal(SpectralEchoModifier.ECHO_DAMAGE)
			var sprite: Sprite2D = c.get_node_or_null("Sprite2D")
			assert_that(sprite).is_not_null()
			assert_float(sprite.modulate.a).is_less(1.0)

func test_spectral_echo_fire_delays_then_spawns() -> void:
	var pu := _spawn_parent_and_user()
	var m := SpectralEchoModifier.new()
	m._fire(null, pu[1], _ctx())
	assert_int(_count_projectiles(pu[0])).is_equal(0)  # nothing yet
	await get_tree().create_timer(SpectralEchoModifier.ECHO_DELAY + 0.1).timeout
	assert_int(_count_projectiles(pu[0])).is_equal(1)
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_modifiers.gd
```
Expected: FAIL — `Identifier "SpectralEchoModifier" not declared`.

- [ ] **Step 3: Create the modifier**

Create `src/weapons/modifiers/spectral_echo_modifier.gd`:

```gdscript
class_name SpectralEchoModifier
extends ProjectileModifier

const ECHO_DELAY := 0.3
const ECHO_DAMAGE := 3.0

func _init() -> void:
	name = "Spectral Echo"
	description = "A ghostly copy repeats your swing a moment later."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon, user, ctx) -> void:
	if user == null:
		return
	var tree := user.get_tree()
	if tree == null:
		return
	var origin: Vector2 = ctx.get("origin", Vector2.ZERO)
	var dir: Vector2 = ctx.get("direction", Vector2.RIGHT)
	tree.create_timer(ECHO_DELAY).timeout.connect(_spawn_echo.bind(user, origin, dir))

func _spawn_echo(user, origin: Vector2, direction: Vector2) -> void:
	if not is_instance_valid(user):
		return
	ModifierProjectile.spawn_one(user, origin, direction, ECHO_DAMAGE,
		{ "tint": Color(0.7, 0.7, 1.0, 0.5) })
```

- [ ] **Step 4: Register the id**

In `src/autoload/weapon_registry.gd` `_ready()`, after the `boomerang_arc` line added in Task 6, add:

```gdscript
	modifier_scripts["spectral_echo"] = preload("res://src/weapons/modifiers/spectral_echo_modifier.gd")
```

- [ ] **Step 5: Run tests to verify they pass**

Run the same command as Step 2.
Expected: PASS — both spectral_echo tests green (the second waits ~0.4s for the timer).

- [ ] **Step 6: Commit**

```bash
git add src/weapons/modifiers/spectral_echo_modifier.gd src/autoload/weapon_registry.gd tests/unit/test_modifiers.gd
git commit -m "feat: add spectral_echo modifier"
```

---

## Task 8: Registry coverage test + mark SP-C done

Confirm all six ids resolve to non-null modifiers, then update the todo.

**Files:**
- Modify: `tests/unit/test_modifiers.gd`
- Modify: `docs/design_docs/implementation_todo.md`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_modifiers.gd`:

```gdscript
func test_sp_c_projectile_modifiers_registered() -> void:
	for id in ["homing_hex", "boomerang_arc", "ricochet_shard", "piercing_lance", "cluster_bomb", "spectral_echo"]:
		assert_bool(WeaponRegistry.modifier_scripts.has(id)).is_true()
		assert_that(WeaponRegistry._make_modifier(id)).is_not_null()
```

- [ ] **Step 2: Run test to verify it passes**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_modifiers.gd
```
Expected: PASS — all six ids are registered (added in Tasks 4-7) and resolve. If any id is missing, fix its registration in `weapon_registry.gd`.

- [ ] **Step 3: Mark SP-C complete in the todo**

In `docs/design_docs/implementation_todo.md`, in the `### Sub-project C (7)` table, change the three `|  |` (empty Done) cells to `| x |`:

```markdown
### Sub-project C (7): New projectile behaviors + projectile modifiers
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P2 | Medium | `homing` steering | Curve toward nearest enemy with capped turn rate |
| x | P2 | Medium | `return` steering | Travel out then reverse to player, hitting both legs |
| x | P2 | Medium | Projectile modifiers | homing_hex, boomerang_arc, ricochet_shard, piercing_lance, cluster_bomb, spectral_echo |
```

- [ ] **Step 4: Run the full projectile + modifier suites one last time**

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode \
  -a res://tests/unit/test_projectile_behaviors.gd -a res://tests/unit/test_modifiers.gd
```
Expected: PASS — all tests in both suites green.

- [ ] **Step 5: Commit**

```bash
git add tests/unit/test_modifiers.gd docs/design_docs/implementation_todo.md
git commit -m "test: SP-C registry coverage; mark sub-project C done"
```

---

## Self-Review Notes

- **Spec coverage:** `homing` steering → Task 2; `return` steering → Task 3; six modifiers → Tasks 4-7 (`ricochet_shard`/`piercing_lance` T4, `cluster_bomb` T5, `homing_hex`/`boomerang_arc` T6, `spectral_echo` T7); `SplitBehavior.shard_hit_status` → Task 1; registration + registry test → Tasks 4-8; todo update → Task 8. All spec "Files" entries are covered.
- **Type consistency:** `shard_hit_status` (String), `turn_rate_rad`, `out_time`/`return_catch_radius`, `ECHO_DELAY`/`ECHO_DAMAGE` are named identically wherever referenced across tasks and tests.
- **Reuse:** `BounceBehavior.max_bounces`, `PenetrateBehavior`, `SplitBehavior.shard_count`/`spread_deg`/`shard_hit_status` match the existing classes' real field names.
