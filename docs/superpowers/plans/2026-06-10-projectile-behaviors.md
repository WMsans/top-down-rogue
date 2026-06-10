# Projectile Behaviors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four reusable, composable projectile behaviors — bounce, split, penetrate, and clear-bullets — that Sub-project 4's modifiers will attach to projectiles.

**Architecture:** A `ProjectileBehavior` (RefCounted) base with semantic, no-op hooks. `Projectile` holds a `behaviors` array, dispatches lifecycle events to them, and frees itself on a hit only if no behavior voted keep-alive (so behavior-less projectiles are unchanged). Each behavior lives in its own file under `src/weapons/projectile_behaviors/`. A console command fires each behavior live.

**Tech Stack:** Godot 4 / GDScript, gdUnit4 for unit tests.

---

## Conventions for every task

**Run a single test suite** (from repo root). The `--import` step is needed once per worktree; harmless to repeat:

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_projectile_behaviors.gd
```

A passing run prints a summary with `0 errors` / all tests green; a failing run lists the failed assertions and exits non-zero.

**Key existing facts the engineer needs:**
- `Projectile` is `src/weapons/projectile.gd`, an `Area2D`. It moves along `direction` (unit vector) at `speed`, expires after `lifetime`, and on hit runs damage/crit/carve then `queue_free()`s. It already joins group `"projectile"` and exposes `is_enemy_projectile`, `direction`, `source_node`, `damage`.
- `Projectile._handle_hit(target)` is called by both `_on_body_entered` and `_on_area_entered`. It currently branches on `is_enemy_projectile`, then on `target.is_in_group("attackable")` / `target is StaticBody2D`.
- The projectile scene is `res://scenes/projectile.tscn` (preloaded elsewhere as `PROJECTILE_SCENE`).
- `ProjectileBlockFX.play(pos: Vector2, dir: Vector2)` is a static method in `src/player/feedback/projectile_block_fx.gd` that plays the bullet-shatter FX.
- Terrain solidity: `world_manager.nav_field.is_solid_world(pos: Vector2) -> bool` (world_manager is in group `"world_manager"`; `nav_field` is a `NavField`).
- Tests use gdUnit4: suites `extends GdUnitTestSuite`; use `auto_free(node)` for cleanup, `assert_that(x).is_true()/.is_false()/.is_equal(...)/.is_greater(...)`.

---

## Task 1: `ProjectileBehavior` base class

**Files:**
- Create: `src/weapons/projectile_behaviors/projectile_behavior.gd`
- Test: `tests/unit/test_projectile_behaviors.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_projectile_behaviors.gd`:

```gdscript
extends GdUnitTestSuite

func test_base_behavior_hooks_are_noops() -> void:
	var b: ProjectileBehavior = ProjectileBehavior.new()
	var proj: Projectile = auto_free(Projectile.new())
	# Defaults: hits do NOT keep the projectile alive; overlap hook returns nothing.
	assert_that(b.on_enemy_hit(proj, null)).is_false()
	assert_that(b.on_terrain_hit(proj)).is_false()
	b.on_spawn(proj)
	b.on_process(proj, 0.1)
	b.on_enemy_projectile_overlap(proj, null)
```

- [ ] **Step 2: Run test to verify it fails**

Run the suite (see Conventions). Expected: FAIL — `Identifier "ProjectileBehavior" not declared`.

- [ ] **Step 3: Write minimal implementation**

Create `src/weapons/projectile_behaviors/projectile_behavior.gd`:

```gdscript
class_name ProjectileBehavior
extends RefCounted

# Called once when the projectile enters the tree.
func on_spawn(_proj) -> void:
	pass

# Called every frame, after the projectile has moved.
func on_process(_proj, _delta: float) -> void:
	pass

# Called after the projectile's damage has been applied to an attackable enemy.
# Return true to keep the projectile alive (suppress the default destroy).
func on_enemy_hit(_proj, _target) -> bool:
	return false

# Called when the projectile overlaps a solid wall (StaticBody2D), BEFORE carving.
# Return true to keep the projectile alive (suppress carve + destroy).
func on_terrain_hit(_proj) -> bool:
	return false

# Called when a PLAYER projectile overlaps an ENEMY projectile. Informational —
# does not affect this projectile's own death policy.
func on_enemy_projectile_overlap(_proj, _enemy_proj) -> void:
	pass
```

- [ ] **Step 4: Run test to verify it passes**

Run the suite. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/projectile_behaviors/projectile_behavior.gd tests/unit/test_projectile_behaviors.gd
git commit -m "feat: ProjectileBehavior base contract"
```

---

## Task 2: Wire behaviors into `Projectile` lifecycle + solidity probe

This task adds the `behaviors` array, lifecycle dispatch, keep-alive voting, the enemy-projectile-overlap branch, and the injectable `is_solid_at` probe. Existing damage/crit/carve code is preserved.

**Files:**
- Modify: `src/weapons/projectile.gd`
- Test: `tests/unit/test_projectile_behaviors.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_projectile_behaviors.gd`:

```gdscript
# A test behavior that records calls and votes keep-alive on demand.
class _RecordingBehavior extends ProjectileBehavior:
	var keep_enemy: bool = false
	var keep_terrain: bool = false
	var spawned: int = 0
	var processed: int = 0
	var enemy_hits: int = 0
	var overlaps: Array = []
	func on_spawn(_proj) -> void: spawned += 1
	func on_process(_proj, _delta: float) -> void: processed += 1
	func on_enemy_hit(_proj, _target) -> bool:
		enemy_hits += 1
		return keep_enemy
	func on_terrain_hit(_proj) -> bool:
		return keep_terrain
	func on_enemy_projectile_overlap(_proj, enemy_proj) -> void:
		overlaps.append(enemy_proj)

func test_on_spawn_called_on_ready() -> void:
	var b := _RecordingBehavior.new()
	var p: Projectile = auto_free(Projectile.new())
	p.behaviors = [b]
	add_child(p)
	assert_that(b.spawned).is_equal(1)

func test_on_process_called_each_frame() -> void:
	var b := _RecordingBehavior.new()
	var p: Projectile = auto_free(Projectile.new())
	p.behaviors = [b]
	p.lifetime = 10.0
	p._process(0.1)
	assert_that(b.processed).is_equal(1)

func test_behavior_keep_alive_on_enemy_hit() -> void:
	var b := _RecordingBehavior.new()
	b.keep_enemy = true
	var p: Projectile = auto_free(Projectile.new())
	p.behaviors = [b]
	p.is_enemy_projectile = false
	p.damage = 5.0
	var target: Enemy = auto_free(Enemy.new())
	p._handle_hit(target)
	assert_that(b.enemy_hits).is_equal(1)
	assert_that(is_instance_valid(p)).is_true()

func test_no_behavior_still_dies_on_enemy_hit() -> void:
	var p: Projectile = auto_free(Projectile.new())
	p.is_enemy_projectile = false
	p.damage = 5.0
	var target: Enemy = auto_free(Enemy.new())
	p._handle_hit(target)
	assert_that(is_instance_valid(p)).is_false()

func test_is_solid_at_uses_injected_oracle() -> void:
	var p: Projectile = auto_free(Projectile.new())
	p.solidity_oracle = func(pos: Vector2) -> bool: return pos.x > 0.0
	assert_that(p.is_solid_at(Vector2(5, 0))).is_true()
	assert_that(p.is_solid_at(Vector2(-5, 0))).is_false()
```

- [ ] **Step 2: Run tests to verify they fail**

Run the suite. Expected: FAIL — `Invalid set index 'behaviors'` / `Invalid set index 'solidity_oracle'` / missing `is_solid_at`.

- [ ] **Step 3: Implement the changes in `src/weapons/projectile.gd`**

Add these fields after the existing `@export` block (after line `var source_node: Node2D = null`):

```gdscript
var behaviors: Array = []  # of ProjectileBehavior
var solidity_oracle: Callable = Callable()  # injectable; tests supply a stub
```

In `_ready`, after the existing body, append the spawn dispatch:

```gdscript
func _ready() -> void:
	add_to_group("projectile")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	for b in behaviors:
		b.on_spawn(self)
```

In `_process`, append the per-frame dispatch after the sprite-rotation block (do not move the lifetime/age guard, which stays first):

```gdscript
func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	global_position += direction * speed * delta
	var sprite := get_node_or_null("Sprite2D")
	if sprite:
		sprite.rotation = direction.angle() + PI * 3.0 / 4.0
	for b in behaviors:
		b.on_process(self, delta)
```

Replace the player-projectile branch of `_handle_hit` (the `else:` block, currently the
`attackable` + `StaticBody2D` handling) so each hit polls behaviors before freeing, and add the
enemy-projectile-overlap branch. The full method becomes:

```gdscript
func _handle_hit(target: Node) -> void:
	if is_enemy_projectile:
		if target.is_in_group("player"):
			if target.has_method("on_hit_impact"):
				target.on_hit_impact(global_position, direction, int(damage))
			queue_free()
		elif target is StaticBody2D:
			_carve_terrain()
			queue_free()
		return

	# Player projectile passing an enemy projectile: opt-in clear hook, no self death.
	if target != self and target.is_in_group("projectile") and "is_enemy_projectile" in target and target.is_enemy_projectile:
		for b in behaviors:
			b.on_enemy_projectile_overlap(self, target)
		return

	if target.is_in_group("attackable"):
		if target != source_node and target.has_method("on_hit_impact"):
			var is_crit: bool = randf() < clampf(crit_chance, 0.0, 1.0)
			var dmg: int = int(damage * crit_multiplier) if is_crit else int(damage)
			target.on_hit_impact(global_position, direction, dmg)
			if is_crit and crit_status != "":
				var sc = target.get_node_or_null("StatusComponent")
				if sc != null:
					sc.add_stain(crit_status, CRIT_STATUS_STAIN)
			var keep_enemy := false
			for b in behaviors:
				keep_enemy = b.on_enemy_hit(self, target) or keep_enemy
			if not keep_enemy:
				queue_free()
	elif target is StaticBody2D:
		var keep_terrain := false
		for b in behaviors:
			keep_terrain = b.on_terrain_hit(self) or keep_terrain
		if keep_terrain:
			return
		_carve_terrain()
		queue_free()
```

Add the solidity probe method at the end of the file:

```gdscript
func is_solid_at(pos: Vector2) -> bool:
	if solidity_oracle.is_valid():
		return solidity_oracle.call(pos)
	var wm := get_tree().get_first_node_in_group("world_manager")
	if wm != null and wm.nav_field != null:
		return wm.nav_field.is_solid_world(pos)
	return false
```

- [ ] **Step 4: Run tests to verify they pass**

Run the suite. Expected: PASS for the five new tests. Also run the existing projectile suite to confirm no regression:

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_projectile.gd
```

Expected: all existing projectile tests still PASS.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/projectile.gd tests/unit/test_projectile_behaviors.gd
git commit -m "feat: Projectile dispatches lifecycle to behaviors + solidity probe"
```

---

## Task 3: `BounceBehavior`

**Files:**
- Create: `src/weapons/projectile_behaviors/bounce_behavior.gd`
- Test: `tests/unit/test_projectile_behaviors.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_projectile_behaviors.gd`:

```gdscript
func test_bounce_flips_blocked_x_axis() -> void:
	var p: Projectile = auto_free(Projectile.new())
	p.global_position = Vector2.ZERO
	p.direction = Vector2.RIGHT
	# Wall ahead on +X only.
	p.solidity_oracle = func(pos: Vector2) -> bool: return pos.x > 0.0
	var b := BounceBehavior.new()
	b.max_bounces = 3
	var keep := b.on_terrain_hit(p)
	assert_that(keep).is_true()
	assert_that(p.direction.x).is_less(0.0)
	assert_that(b.max_bounces).is_equal(2)

func test_bounce_dies_when_exhausted() -> void:
	var p: Projectile = auto_free(Projectile.new())
	p.direction = Vector2.RIGHT
	p.solidity_oracle = func(_pos: Vector2) -> bool: return true
	var b := BounceBehavior.new()
	b.max_bounces = 0
	assert_that(b.on_terrain_hit(p)).is_false()
```

- [ ] **Step 2: Run tests to verify they fail**

Run the suite. Expected: FAIL — `Identifier "BounceBehavior" not declared`.

- [ ] **Step 3: Write minimal implementation**

Create `src/weapons/projectile_behaviors/bounce_behavior.gd`:

```gdscript
class_name BounceBehavior
extends ProjectileBehavior

var max_bounces: int = 3
var probe_step: float = 6.0


func on_terrain_hit(proj) -> bool:
	if max_bounces <= 0:
		return false  # default carve + die
	var d: Vector2 = proj.direction
	var p: Vector2 = proj.global_position
	var sx: float = signf(d.x) if absf(d.x) > 0.0001 else 0.0
	var sy: float = signf(d.y) if absf(d.y) > 0.0001 else 0.0
	var hit_x: bool = sx != 0.0 and proj.is_solid_at(p + Vector2(sx * probe_step, 0.0))
	var hit_y: bool = sy != 0.0 and proj.is_solid_at(p + Vector2(0.0, sy * probe_step))
	if not hit_x and not hit_y:
		# Ambiguous (corner / coarse grid): reverse fully.
		d = -d
	else:
		if hit_x:
			d.x = -d.x
		if hit_y:
			d.y = -d.y
	proj.direction = d.normalized()
	proj.global_position = p + proj.direction * probe_step  # clear the wall
	max_bounces -= 1
	return true
```

- [ ] **Step 4: Run tests to verify they pass**

Run the suite. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/projectile_behaviors/bounce_behavior.gd tests/unit/test_projectile_behaviors.gd
git commit -m "feat: BounceBehavior (axis-probe terrain ricochet)"
```

---

## Task 4: `SplitBehavior`

**Files:**
- Create: `src/weapons/projectile_behaviors/split_behavior.gd`
- Test: `tests/unit/test_projectile_behaviors.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_projectile_behaviors.gd`:

```gdscript
func test_split_spawns_shards_on_enemy_hit_then_dies() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var p: Projectile = Projectile.new()  # NOT auto_free: it should queue_free itself
	p.is_enemy_projectile = false
	p.damage = 10.0
	var b := SplitBehavior.new()
	b.shard_count = 4
	p.behaviors = [b]
	parent.add_child(p)
	var target: Enemy = auto_free(Enemy.new())
	p._handle_hit(target)
	await get_tree().process_frame  # let queue_free settle
	# 4 shards added under the same parent; original removed.
	var shards := 0
	for c in parent.get_children():
		if c is Projectile:
			shards += 1
	assert_that(shards).is_equal(4)

func test_split_shards_have_no_behaviors_and_reduced_damage() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var p: Projectile = Projectile.new()
	p.is_enemy_projectile = false
	p.damage = 10.0
	var b := SplitBehavior.new()
	b.shard_count = 3
	b.damage_factor = 0.5
	p.behaviors = [b]
	parent.add_child(p)
	p._handle_hit(auto_free(Enemy.new()))
	await get_tree().process_frame
	for c in parent.get_children():
		if c is Projectile:
			assert_that(c.behaviors.is_empty()).is_true()
			assert_that(c.damage).is_equal(5.0)
```

- [ ] **Step 2: Run tests to verify they fail**

Run the suite. Expected: FAIL — `Identifier "SplitBehavior" not declared`.

- [ ] **Step 3: Write minimal implementation**

Create `src/weapons/projectile_behaviors/split_behavior.gd`:

```gdscript
class_name SplitBehavior
extends ProjectileBehavior

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")

var shard_count: int = 4
var damage_factor: float = 0.5
var spread_deg: float = 60.0
var shard_speed: float = 140.0
var shard_lifetime: float = 0.6


func on_enemy_hit(proj, _target) -> bool:
	_split(proj)
	return false  # let the projectile die normally


func on_terrain_hit(proj) -> bool:
	_split(proj)
	return false  # let the projectile carve + die normally


func _split(proj) -> void:
	var parent := proj.get_parent()
	if parent == null:
		return
	var base_angle: float = proj.direction.angle()
	var half: float = deg_to_rad(spread_deg) / 2.0
	for i in range(shard_count):
		var t: float = 0.0 if shard_count == 1 else float(i) / float(shard_count - 1)
		var angle: float = base_angle + lerpf(-half, half, t)
		var shard: Projectile = PROJECTILE_SCENE.instantiate()
		shard.direction = Vector2(cos(angle), sin(angle))
		shard.damage = proj.damage * damage_factor
		shard.speed = shard_speed
		shard.lifetime = shard_lifetime
		shard.is_enemy_projectile = proj.is_enemy_projectile
		shard.source_node = proj.source_node
		shard.global_position = proj.global_position
		var src_sprite = proj.get_node_or_null("Sprite2D")
		var shard_sprite = shard.get_node_or_null("Sprite2D")
		if src_sprite != null and shard_sprite != null:
			shard_sprite.texture = src_sprite.texture
		parent.add_child(shard)
```

- [ ] **Step 4: Run tests to verify they pass**

Run the suite. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/projectile_behaviors/split_behavior.gd tests/unit/test_projectile_behaviors.gd
git commit -m "feat: SplitBehavior (shard fan on impact)"
```

---

## Task 5: `PenetrateBehavior`

**Files:**
- Create: `src/weapons/projectile_behaviors/penetrate_behavior.gd`
- Test: `tests/unit/test_projectile_behaviors.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_projectile_behaviors.gd`:

```gdscript
func test_penetrate_passes_through_enemies() -> void:
	var p: Projectile = auto_free(Projectile.new())
	p.is_enemy_projectile = false
	p.damage = 5.0
	p.behaviors = [PenetrateBehavior.new()]
	p._handle_hit(auto_free(Enemy.new()))
	assert_that(is_instance_valid(p)).is_true()
	p._handle_hit(auto_free(Enemy.new()))
	assert_that(is_instance_valid(p)).is_true()

func test_penetrate_dies_on_wall() -> void:
	var b := PenetrateBehavior.new()
	var p: Projectile = auto_free(Projectile.new())
	assert_that(b.on_terrain_hit(p)).is_false()
```

- [ ] **Step 2: Run tests to verify they fail**

Run the suite. Expected: FAIL — `Identifier "PenetrateBehavior" not declared`.

- [ ] **Step 3: Write minimal implementation**

Create `src/weapons/projectile_behaviors/penetrate_behavior.gd`:

```gdscript
class_name PenetrateBehavior
extends ProjectileBehavior

# Pass through every enemy (damage is applied once per Area2D enter); stopped by walls.
func on_enemy_hit(_proj, _target) -> bool:
	return true


func on_terrain_hit(_proj) -> bool:
	return false  # default carve + die
```

- [ ] **Step 4: Run tests to verify they pass**

Run the suite. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/projectile_behaviors/penetrate_behavior.gd tests/unit/test_projectile_behaviors.gd
git commit -m "feat: PenetrateBehavior (pass through enemies, stop at walls)"
```

---

## Task 6: `ClearBulletsBehavior`

**Files:**
- Create: `src/weapons/projectile_behaviors/clear_bullets_behavior.gd`
- Test: `tests/unit/test_projectile_behaviors.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_projectile_behaviors.gd`:

```gdscript
func test_clear_destroys_overlapping_enemy_projectile() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	# Player projectile with clear behavior.
	var p: Projectile = auto_free(Projectile.new())
	p.is_enemy_projectile = false
	p.behaviors = [ClearBulletsBehavior.new()]
	parent.add_child(p)
	# Enemy projectile it overlaps.
	var enemy_proj: Projectile = Projectile.new()
	enemy_proj.is_enemy_projectile = true
	enemy_proj.direction = Vector2.LEFT
	parent.add_child(enemy_proj)
	p._handle_hit(enemy_proj)
	await get_tree().process_frame
	assert_that(is_instance_valid(enemy_proj)).is_false()
	assert_that(is_instance_valid(p)).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run the suite. Expected: FAIL — `Identifier "ClearBulletsBehavior" not declared`.

- [ ] **Step 3: Write minimal implementation**

Create `src/weapons/projectile_behaviors/clear_bullets_behavior.gd`:

```gdscript
class_name ClearBulletsBehavior
extends ProjectileBehavior

func on_enemy_projectile_overlap(_proj, enemy_proj) -> void:
	if not is_instance_valid(enemy_proj):
		return
	ProjectileBlockFX.play(enemy_proj.global_position, -enemy_proj.direction)
	enemy_proj.queue_free()
```

- [ ] **Step 4: Run test to verify it passes**

Run the suite. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/projectile_behaviors/clear_bullets_behavior.gd tests/unit/test_projectile_behaviors.gd
git commit -m "feat: ClearBulletsBehavior (shatter overlapping enemy projectiles)"
```

---

## Task 7: Console command — `spawn projectile <behavior>`

**Files:**
- Modify: `src/console/commands/spawn_command.gd`

This task has no unit test (console wiring is verified manually in-game); it ends with a headless smoke check that the file parses.

- [ ] **Step 1: Add the registrations**

In `src/console/commands/spawn_command.gd`, inside `static func register(registry: CommandRegistry)`, after the existing `spawn static_projectile` line, add:

```gdscript
	registry.register("spawn projectile bounce", "Fire a bouncing projectile", _spawn_behavior_projectile.bind("bounce"))
	registry.register("spawn projectile split", "Fire a splitting projectile", _spawn_behavior_projectile.bind("split"))
	registry.register("spawn projectile penetrate", "Fire a penetrating projectile", _spawn_behavior_projectile.bind("penetrate"))
	registry.register("spawn projectile clear", "Fire a bullet-clearing projectile", _spawn_behavior_projectile.bind("clear"))
	registry.register("spawn projectile shockwave", "Fire a penetrating + bullet-clearing shockwave", _spawn_behavior_projectile.bind("shockwave"))
```

- [ ] **Step 2: Add the handler**

At the end of `src/console/commands/spawn_command.gd`, add:

```gdscript
static func _spawn_behavior_projectile(_args: Array[String], ctx: Dictionary, kind: String) -> String:
	var parent := _get_spawn_parent(ctx)
	if parent == null:
		return "error: no spawn parent available"
	var dir := Vector2.RIGHT
	var player = ctx.get("player")
	if player != null and player.has_method("get_facing_direction"):
		dir = player.get_facing_direction()
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT

	var proj: Projectile = PROJECTILE_SCENE.instantiate()
	proj.is_enemy_projectile = false
	proj.direction = dir.normalized()
	proj.speed = 140.0
	proj.lifetime = 3.0
	proj.damage = 5.0
	var proj_sprite := proj.get_node_or_null("Sprite2D")
	if proj_sprite:
		proj_sprite.texture = PROJECTILE_TEX

	match kind:
		"bounce":
			proj.behaviors = [BounceBehavior.new()]
		"split":
			proj.behaviors = [SplitBehavior.new()]
		"penetrate":
			proj.behaviors = [PenetrateBehavior.new()]
		"clear":
			proj.behaviors = [ClearBulletsBehavior.new()]
		"shockwave":
			proj.behaviors = [PenetrateBehavior.new(), ClearBulletsBehavior.new()]
		_:
			return "error: unknown projectile kind '" + kind + "'"

	parent.add_child(proj)
	proj.global_position = ctx.get("world_pos", Vector2.ZERO)
	return "Spawned " + kind + " projectile"
```

- [ ] **Step 3: Smoke-check that the project still imports/parses**

Run:

```bash
godot --headless --path . --import
```

Expected: completes with no GDScript parse errors mentioning `spawn_command.gd` or the behavior classes. (The `class_name` globals — `BounceBehavior`, `SplitBehavior`, `PenetrateBehavior`, `ClearBulletsBehavior`, `Projectile` — resolve project-wide, so no preloads are needed.)

- [ ] **Step 4: Run the full behavior suite once more**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_projectile_behaviors.gd
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/console/commands/spawn_command.gd
git commit -m "feat: spawn projectile <behavior> console command"
```

---

## Task 8: Mark Sub-project 3 done in the todo

**Files:**
- Modify: `docs/design_docs/implementation_todo.md`

- [ ] **Step 1: Edit the table**

In `docs/design_docs/implementation_todo.md`, under `### Sub-project 3: Projectile Behaviors`, change the leading `|  |` (empty Done cell) to `| x |` for all four rows:

```
| x | P2 | Medium | Bouncing projectiles | Projectiles that ricochet off terrain |
| x | P2 | Medium | Splitting projectiles | Projectiles that split into shards on impact |
| x | P2 | Medium | Penetrating projectiles | Pass-through shockwaves that delete enemy bullets |
| x | P2 | Medium | Bullet-clearing projectiles | Shatter incoming enemy projectiles |
```

- [ ] **Step 2: Commit**

```bash
git add docs/design_docs/implementation_todo.md
git commit -m "docs: mark Phase 7 sub-project 3 (projectile behaviors) done"
```

---

## Manual verification (after all tasks)

In-game, open the console (backtick) and run each command, confirming the visual behavior:
- `spawn projectile bounce` near a wall → ricochets off terrain up to 3 times.
- `spawn projectile split` → on hitting an enemy/wall, spawns a fan of 4 short-lived shards.
- `spawn projectile penetrate` → passes through multiple enemies, stops at a wall.
- `spawn projectile clear` → with enemy bullets incoming (`spawn static_projectile`), shatters them on contact (block FX) while continuing.
- `spawn projectile shockwave` → passes through enemies AND clears enemy bullets in its path.

---

## Self-review notes (coverage map)

- Spec §1 behavior contract → Task 1.
- Spec §2 Projectile changes (behaviors array, dispatch, keep-alive, enemy-projectile branch, `is_solid_at`/`solidity_oracle`) → Task 2.
- Spec §3 BounceBehavior → Task 3; SplitBehavior → Task 4; PenetrateBehavior → Task 5; ClearBulletsBehavior → Task 6.
- Spec §4 console command (5 sub-commands incl. composed `shockwave`) → Task 7.
- Spec §5 testing (bounce flip, split count, penetrate keep-alive/die, clear, behavior-less regression) → Tasks 1–6 + existing `test_projectile.gd` rerun in Task 2.
- Todo bookkeeping → Task 8.
