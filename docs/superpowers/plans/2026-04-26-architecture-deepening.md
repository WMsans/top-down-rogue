# Architecture Deepening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor 6 shallow module clusters into deep modules behind well-defined seams, increasing locality and leverage across the entire codebase.

**Architecture:** Six sequential deepening operations. Tier A (HitReaction, TerrainSurface) run first in parallel. Tier B (TerrainPhysical) builds on TerrainSurface. Tier C (PickupContext, PlayerInventory) builds on Tier B. Tier D (WeaponDelivery) builds on PickupContext + PlayerInventory. Each step replaces scattered autoloads and fragile scene-tree traversal with deeper interfaces.

**Tech Stack:** Godot 4.6, GDScript, gdUnit4 test framework

---

### Task 0: Scaffold test directory

**Files:**
- Create: `tests/unit/.gdignore`
- Create: `tests/unit/run_all_tests.gd`

- [ ] **Step 1: Create test directory and ignore file**

```bash
mkdir -p tests/unit
echo "" > tests/unit/.gdignore
```

- [ ] **Step 2: Create all test stub files**

For each test file below, create a stub that extends `GdUnitTestSuite`:

```gdscript
# tests/unit/test_hit_reaction.gd
extends GdUnitTestSuite

func test_placeholder() -> void:
    assert_that(1 + 1).is_equal(2)
```

Create stubs for all 6 test files:
```bash
cat > tests/unit/test_hit_reaction.gd << 'GDEOF'
extends GdUnitTestSuite

func test_create_hit_spec() -> void:
    var spec := HitSpec.new()
    spec.position = Vector2(10, 20)
    assert_that(spec.position).is_equal(Vector2(10, 20))
GDEOF
```

Do NOT create the actual test stubs manually — each test file is created in its respective task below. Just create the directory.

- [ ] **Step 3: Commit**

```bash
git add tests/
git commit -m "chore: scaffold test directory"
```

---

## Tier A (parallel-safe)

### Task 1: HitReaction — Create HitSpec resource and HitReaction autoload

**Files:**
- Create: `src/core/juice/hit_spec.gd`
- Create: `src/core/juice/hit_reaction.gd`
- Create: `tests/unit/test_hit_reaction.gd`
- Modify: `project.godot` (autoload section)
- Delete: `src/core/juice/hit_spark_manager.gd`
- Delete: `src/core/juice/damage_number_manager.gd`
- Delete: `src/core/juice/screen_shake_manager.gd`
- Delete: `src/core/juice/chromatic_flash_manager.gd`
- Delete: `src/core/juice/hit_stop_manager.gd`

- [ ] **Step 1: Create HitSpec resource**

```gdscript
# src/core/juice/hit_spec.gd
class_name HitSpec
extends Resource

var position: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.ZERO
var damage: float = 0.0
var is_kill: bool = false
var source_color: Color = Color.WHITE
var source_radius: float = 8.0
```

- [ ] **Step 2: Create HitReaction autoload (merged 5 managers)**

```gdscript
# src/core/juice/hit_reaction.gd
extends Node

# HitStop constants
const HIT_STOP_BASE: float = 0.06
const HIT_STOP_KILL_BONUS: float = 0.04

# ScreenShake constants
const SHAKE_AMOUNT: float = 3.0
const SHAKE_DURATION: float = 0.18

# HitSpark constants
const SPARK_COUNT_MIN: int = 6
const SPARK_COUNT_MAX: int = 8
const SPARK_SPEED_MIN: float = 80.0
const SPARK_SPEED_MAX: float = 160.0
const SPARK_LIFETIME: float = 0.15
const SPARK_CONE_HALF_ANGLE: float = PI / 6.0
const SPARK_SIZE: Vector2 = Vector2(2, 2)

# DamageNumber constants
const DAMAGE_NUMBER_LIFETIME: float = 0.6
const HOLD_FRACTION: float = 2.0 / 3.0
const POP_DURATION: float = 0.12
const POP_SCALE: Vector2 = Vector2(1.2, 1.2)
const INITIAL_VELOCITY_Y: float = -80.0
const INITIAL_VELOCITY_X_RANGE: float = 30.0
const GRAVITY: float = 200.0
const SPAWN_OFFSET: Vector2 = Vector2(0, -8)

# ChromaticFlash constants
const CHROMATIC_STRENGTH: float = 0.6
const CHROMATIC_DURATION: float = 0.12

const DAMAGE_NUMBER_SCENE := preload("res://scenes/fx/damage_number.tscn")
const CHROMATIC_FLASH_SCENE := preload("res://scenes/fx/chromatic_flash.tscn")

# Screen shake state
var _shake_amount: float = 0.0
var _shake_duration: float = 0.0
var _shake_elapsed: float = 0.0
var _shake_dir_bias: Vector2 = Vector2.ZERO

# Hit stop state
var _active_stop_timer: SceneTreeTimer = null

# Chromatic flash state
var _chromatic_layer: CanvasLayer = null
var _chromatic_rect: ColorRect = null
var _chromatic_material: ShaderMaterial = null
var _chromatic_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_chromatic_flash()


func play(spec: HitSpec) -> void:
	var dmg_int: int = floori(spec.damage)
	_spawn_sparks(spec.position, spec.direction, spec.source_color)
	_spawn_damage_number(spec.position, dmg_int)
	_do_screen_shake(spec.damage, spec.is_kill, spec.direction)
	_do_chromatic_flash(spec.damage, spec.is_kill)
	_do_hit_stop(spec.damage, spec.is_kill)


# ---- HitSpark adapter ----

func _spawn_sparks(point: Vector2, dir: Vector2, color: Color) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var base_angle: float = dir.angle() if dir.length_squared() > 0.0001 else 0.0
	var count: int = randi_range(SPARK_COUNT_MIN, SPARK_COUNT_MAX)
	for i in count:
		var spark := ColorRect.new()
		spark.color = color
		spark.size = SPARK_SIZE
		spark.pivot_offset = SPARK_SIZE / 2.0
		spark.position = point - SPARK_SIZE / 2.0
		spark.z_index = 100
		spark.z_as_relative = false
		scene_root.add_child(spark)
		var angle := base_angle + randf_range(-SPARK_CONE_HALF_ANGLE, SPARK_CONE_HALF_ANGLE)
		var speed := randf_range(SPARK_SPEED_MIN, SPARK_SPEED_MAX)
		var velocity := Vector2(cos(angle), sin(angle)) * speed
		var target_pos := spark.position + velocity * SPARK_LIFETIME
		var tween := spark.create_tween()
		tween.set_parallel(true)
		tween.tween_property(spark, "position", target_pos, SPARK_LIFETIME)
		tween.tween_property(spark, "modulate:a", 0.0, SPARK_LIFETIME)
		tween.chain().tween_callback(spark.queue_free)


# ---- DamageNumber adapter ----

func _spawn_damage_number(pos: Vector2, amount: int) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var label: Label = DAMAGE_NUMBER_SCENE.instantiate()
	label.text = str(amount)
	label.global_position = pos + SPAWN_OFFSET
	label.scale = Vector2(0.5, 0.5)
	label.z_index = 100
	label.z_as_relative = false
	scene_root.add_child(label)

	var hold_time: float = DAMAGE_NUMBER_LIFETIME * HOLD_FRACTION
	var fade_time: float = DAMAGE_NUMBER_LIFETIME - hold_time
	var velocity := Vector2(randf_range(-INITIAL_VELOCITY_X_RANGE, INITIAL_VELOCITY_X_RANGE), INITIAL_VELOCITY_Y)

	var pop := label.create_tween()
	pop.tween_property(label, "scale", POP_SCALE, POP_DURATION * 0.5)
	pop.tween_property(label, "scale", Vector2.ONE, POP_DURATION * 0.5)

	var motion := label.create_tween()
	motion.tween_method(_drive_damage_motion.bind(label, velocity, pos + SPAWN_OFFSET), 0.0, DAMAGE_NUMBER_LIFETIME, DAMAGE_NUMBER_LIFETIME)

	var fade := label.create_tween()
	fade.tween_interval(hold_time)
	fade.tween_property(label, "modulate:a", 0.0, fade_time)
	fade.tween_callback(label.queue_free)


func _drive_damage_motion(t: float, label: Label, initial_vel: Vector2, start_pos: Vector2) -> void:
	if not is_instance_valid(label):
		return
	var pos := start_pos + initial_vel * t + Vector2(0, 0.5 * GRAVITY * t * t)
	label.global_position = pos


# ---- ScreenShake adapter ----

func _do_screen_shake(damage: float, is_kill: bool, dir: Vector2) -> void:
	var amount := SHAKE_AMOUNT
	var duration := SHAKE_DURATION
	# kill bonus: stronger shake on killing blows
	if is_kill:
		amount *= 1.5
		duration *= 1.3
	_shake_amount = amount
	_shake_duration = duration
	_shake_elapsed = 0.0
	_shake_dir_bias = dir


func _process(delta: float) -> void:
	if _shake_duration > 0.0:
		_shake_elapsed += delta
		if _shake_elapsed >= _shake_duration:
			var cam := get_viewport().get_camera_2d()
			if cam:
				cam.offset = Vector2.ZERO
			_shake_duration = 0.0
		else:
			var t: float = 1.0 - (_shake_elapsed / _shake_duration)
			var current: float = _shake_amount * t
			var rand_offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * current
			var bias := _shake_dir_bias * 0.5 * current
			var cam := get_viewport().get_camera_2d()
			if cam:
				cam.offset = rand_offset + bias


# ---- ChromaticFlash adapter ----

func _setup_chromatic_flash() -> void:
	_chromatic_layer = CHROMATIC_FLASH_SCENE.instantiate()
	add_child(_chromatic_layer)
	_chromatic_rect = _chromatic_layer.get_node("Rect")
	_chromatic_material = _chromatic_rect.material as ShaderMaterial
	_chromatic_material.set_shader_parameter("strength", 0.0)


func _do_chromatic_flash(damage: float, is_kill: bool) -> void:
	if _chromatic_material == null:
		return
	var strength := CHROMATIC_STRENGTH
	var duration := CHROMATIC_DURATION
	if is_kill:
		strength *= 1.4
		duration *= 1.3
	if _chromatic_tween and _chromatic_tween.is_valid():
		_chromatic_tween.kill()
	_chromatic_material.set_shader_parameter("strength", strength)
	_chromatic_tween = create_tween()
	_chromatic_tween.tween_method(_set_chromatic_strength, strength, 0.0, duration)


func _set_chromatic_strength(value: float) -> void:
	if _chromatic_material:
		_chromatic_material.set_shader_parameter("strength", value)


# ---- HitStop adapter ----

func _do_hit_stop(damage: float, is_kill: bool) -> void:
	var duration: float = HIT_STOP_BASE
	if is_kill:
		duration += HIT_STOP_KILL_BONUS
	if duration <= 0.0:
		return
	Engine.time_scale = 0.0
	_active_stop_timer = get_tree().create_timer(duration, true, false, true)
	var my_timer := _active_stop_timer
	await my_timer.timeout
	if _active_stop_timer == my_timer:
		Engine.time_scale = 1.0
		_active_stop_timer = null
```

- [ ] **Step 3: Register HitReaction as autoload in project.godot**

```bash
git add src/core/juice/hit_reaction.gd src/core/juice/hit_spec.gd
git commit -m "feat: create HitReaction autoload with HitSpec resource"
```

Edit `project.godot` — replace all 5 juice autoloads with the single HitReaction:

Under `[autoload]`, remove these 5 lines:
```
HitStopManager="*res://src/core/juice/hit_stop_manager.gd"
ScreenShakeManager="*res://src/core/juice/screen_shake_manager.gd"
HitSparkManager="*res://src/core/juice/hit_spark_manager.gd"
DamageNumberManager="*res://src/core/juice/damage_number_manager.gd"
ChromaticFlashManager="*res://src/core/juice/chromatic_flash_manager.gd"
```

Add:
```
HitReaction="*res://src/core/juice/hit_reaction.gd"
```

- [ ] **Step 5: Commit project.godot autoload changes**

```bash
git add project.godot
git commit -m "refactor: replace 5 juice autoloads with single HitReaction"
```

- [ ] **Step 6: Write HitReaction test**

```gdscript
# tests/unit/test_hit_reaction.gd
extends GdUnitTestSuite

func test_create_hit_spec() -> void:
    var spec := HitSpec.new()
    spec.position = Vector2(10, 20)
    spec.direction = Vector2(1, 0)
    spec.damage = 25.0
    spec.is_kill = false
    spec.source_color = Color.RED
    assert_that(spec.position).is_equal(Vector2(10, 20))
    assert_that(spec.direction).is_equal(Vector2(1, 0))
    assert_that(spec.damage).is_equal(25.0)
    assert_that(spec.is_kill).is_false()
    assert_that(spec.source_color).is_equal(Color.RED)

func test_hit_spec_defaults() -> void:
    var spec := HitSpec.new()
    assert_that(spec.position).is_equal(Vector2.ZERO)
    assert_that(spec.is_kill).is_false()
    assert_that(spec.source_color).is_equal(Color.WHITE)
    assert_that(spec.source_radius).is_equal(8.0)
```

- [ ] **Step 7: Commit test**

```bash
git add tests/unit/test_hit_reaction.gd
git commit -m "test: add HitSpec resource tests"
```

- [ ] **Step 8: Update enemy.gd to use HitReaction**

In `src/enemies/enemy.gd`, replace the `on_hit_impact` function:

```gdscript
func on_hit_impact(impact_point: Vector2, hit_dir: Vector2, damage: int) -> void:
	if hit_dir.length_squared() > 0.0001:
		_knockback_velocity += hit_dir.normalized() * KNOCKBACK_SPEED
	var lethal: bool = damage >= health
	var spec := HitSpec.new()
	spec.position = impact_point
	spec.direction = hit_dir
	spec.damage = float(damage)
	spec.is_kill = lethal
	spec.source_color = Color.WHITE
	spec.source_radius = 8.0
	HitReaction.play(spec)
	hit(damage)
```

- [ ] **Step 9: Delete old juice manager files**

```bash
rm src/core/juice/hit_spark_manager.gd
rm src/core/juice/damage_number_manager.gd
rm src/core/juice/screen_shake_manager.gd
rm src/core/juice/chromatic_flash_manager.gd
rm src/core/juice/hit_stop_manager.gd
```

- [ ] **Step 10: Commit enemy update and deletions**

```bash
git add src/enemies/enemy.gd
git add -u src/core/juice/
git commit -m "refactor: migrate enemy to HitReaction, delete 5 juice managers"
```

---

### Task 2: TerrainSurface — Create autoload seam for terrain operations

**Files:**
- Create: `src/core/terrain_surface.gd`
- Modify: `src/core/world_manager.gd` (implements adapter interface, registers with TerrainSurface)
- Modify: `src/weapons/melee_weapon.gd` (use TerrainSurface instead of world_manager)
- Modify: `src/weapons/test_weapon.gd` (use TerrainSurface instead of world_manager)
- Modify: `src/weapons/lava_emitter_modifier.gd` (use TerrainSurface instead of world_manager)
- Modify: `src/player/player_controller.gd` (use TerrainSurface for spawn position)
- Modify: `src/debug/chunk_grid_overlay.gd` (use TerrainSurface)
- Modify: `src/debug/collision_overlay.gd` (use TerrainSurface)
- Modify: `project.godot` (add TerrainSurface autoload)
- Create: `tests/unit/test_terrain_surface.gd`

- [ ] **Step 1: Create TerrainSurface autoload**

```gdscript
# src/core/terrain_surface.gd
extends Node

var adapter = null

func register_adapter(a) -> void:
	adapter = a

func place_gas(world_pos: Vector2, radius: float, density: int, velocity: Vector2i = Vector2i.ZERO) -> void:
	if adapter:
		adapter.place_gas(world_pos, radius, density, velocity)

func place_lava(world_pos: Vector2, radius: float) -> void:
	if adapter:
		adapter.place_lava(world_pos, radius)

func place_fire(world_pos: Vector2, radius: float) -> void:
	if adapter:
		adapter.place_fire(world_pos, radius)

func clear_and_push_materials_in_arc(origin: Vector2, direction: Vector2, radius: float, arc_angle: float, push_speed: float, edge_fraction: float, materials: Array) -> void:
	if adapter:
		adapter.clear_and_push_materials_in_arc(origin, direction, radius, arc_angle, push_speed, edge_fraction, materials)

func read_region(rect: Rect2i) -> PackedByteArray:
	if adapter:
		return adapter.read_region(rect)
	return PackedByteArray()

func find_spawn_position(origin: Vector2i, body_size: Vector2i, max_radius: float = 800.0) -> Vector2i:
	if adapter:
		return adapter.find_spawn_position(origin, body_size, max_radius)
	return Vector2i.ZERO

func get_active_chunk_coords() -> Array:
	if adapter:
		return adapter.get_active_chunk_coords()
	return []
```

- [ ] **Step 2: Add TerrainSurface to project.godot autoloads**

Add to `[autoload]` section:
```
TerrainSurface="*res://src/core/terrain_surface.gd"
```

```bash
git add src/core/terrain_surface.gd project.godot
git commit -m "feat: create TerrainSurface autoload seam"
```

- [ ] **Step 3: Update world_manager.gd to register as adapter**

In `src/core/world_manager.gd`, add to `_ready()` after creating sub-managers:

```gdscript
func _ready() -> void:
    # ... existing init code ...
    TerrainSurface.register_adapter(self)
```

Remove the `get_active_chunk_coords()` method from WorldManager since it's now accessed through TerrainSurface. (Keep the method but note callers should use TerrainSurface.)

Actually — WorldManager still needs the method. Keep it as-is. Just add the `register_adapter` call.

- [ ] **Step 4: Commit world_manager registration**

```bash
git add src/core/world_manager.gd
git commit -m "refactor: register WorldManager as TerrainSurface adapter"
```

- [ ] **Step 5: Update weapons to use TerrainSurface**

In `src/weapons/melee_weapon.gd`, replace the `_use_impl` function's terrain calls:

```gdscript
func _use_impl(user: Node) -> void:
	var pos: Vector2 = user.global_position
	var direction := _get_facing_direction(user)
	_start_swing(direction)
	var materials: Array[int] = MaterialRegistry.get_fluids()
	TerrainSurface.clear_and_push_materials_in_arc(pos, direction, RANGE, ARC_ANGLE, PUSH_SPEED, 0.25, materials)
	_hit_attackables_in_arc(user, pos, direction)
```

In `src/weapons/test_weapon.gd`, replace `_use_impl`:

```gdscript
func _use_impl(user: Node) -> void:
	var pos: Vector2 = _sprite.global_position if _sprite else user.global_position
	TerrainSurface.place_gas(pos, GAS_RADIUS, GAS_DENSITY)
	_start_bounce()
```

In `src/weapons/lava_emitter_modifier.gd`, replace `on_use`:

```gdscript
func on_use(_weapon: Weapon, user: Node) -> void:
	var pos: Vector2 = _weapon._sprite.global_position if _weapon._sprite else user.global_position
	TerrainSurface.place_lava(pos, LAVA_RADIUS)
```

- [ ] **Step 6: Remove `_get_world_manager()` from melee_weapon.gd, test_weapon.gd, lava_emitter_modifier.gd**

These functions are no longer needed since weapons now use TerrainSurface autoload directly.

- [ ] **Step 7: Commit weapon updates**

```bash
git add src/weapons/melee_weapon.gd src/weapons/test_weapon.gd src/weapons/lava_emitter_modifier.gd
git commit -m "refactor: weapons use TerrainSurface autoload instead of WorldManager lookup"
```

- [ ] **Step 8: Update player_controller.gd to use TerrainSurface**

In `src/player/player_controller.gd`, replace the spawn position lookup. Remove the `_world_manager` onready var and shadow_grid assignment. Replace the `_ready()` function:

```gdscript
func _ready() -> void:
	_color_rect.pivot_offset = Vector2(BODY_WIDTH / 2.0, BODY_HEIGHT / 2.0)
	add_to_group("player")
	collision_mask = 3
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("gas_interactors")
	await get_tree().process_frame
	await get_tree().process_frame
	var spawn_pos: Vector2i = TerrainSurface.find_spawn_position(Vector2i.ZERO, Vector2i(BODY_WIDTH, BODY_HEIGHT))
	position = Vector2(spawn_pos) + Vector2(BODY_WIDTH / 2.0, BODY_HEIGHT)
```

Remove `_physics_process` references to `shadow_grid` and `_world_manager.tracking_position`. Keep `shadow_grid = null` guard temporarily (will be removed in Task 4 when TerrainPhysical replaces ShadowGrid).

Remove the `get_world_manager()` method and the `_world_manager` variable.

Replace the `_physics_process` function:

```gdscript
func _physics_process(delta: float) -> void:
	var health_component := get_node_or_null("HealthComponent")
	if health_component and health_component.is_dead():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var input_dir := _get_input_direction()
	if input_dir != Vector2.ZERO:
		_last_facing = input_dir
		if input_dir.x < -0.01:
			_facing_left = true
		elif input_dir.x > 0.01:
			_facing_left = false
		if _color_rect != null:
			_color_rect.scale.x = -1.0 if _facing_left else 1.0
	_apply_movement(input_dir, delta)
	move_and_slide()

	var wm := get_parent().get_node_or_null("WorldManager")
	if wm:
		wm.tracking_position = global_position
```

- [ ] **Step 9: Update debug overlays**

In `src/debug/chunk_grid_overlay.gd`:

Replace the deep parent traversal with TerrainSurface:
```gdscript
func _draw() -> void:
	var coords: Array = TerrainSurface.get_active_chunk_coords()
	# ... rest of drawing code using coords ...
```

In `src/debug/collision_overlay.gd`:
```gdscript
func _draw() -> void:
	var coords: Array = TerrainSurface.get_active_chunk_coords()
	# ... rest of drawing code using coords ...
```

- [ ] **Step 10: Commit player and debug updates**

```bash
git add src/player/player_controller.gd src/debug/chunk_grid_overlay.gd src/debug/collision_overlay.gd
git commit -m "refactor: player and debug use TerrainSurface, remove WorldManager scene-tree dependency"
```

- [ ] **Step 11: Write TerrainSurface test**

```gdscript
# tests/unit/test_terrain_surface.gd
extends GdUnitTestSuite

class FakeAdapter:
    var place_gas_calls := []
    var place_lava_calls := []
    var read_result: PackedByteArray

    func place_gas(pos: Vector2, radius: float, density: int, velocity: Vector2i) -> void:
        place_gas_calls.append({"pos": pos, "radius": radius, "density": density})

    func place_lava(pos: Vector2, radius: float) -> void:
        place_lava_calls.append({"pos": pos, "radius": radius})

    func read_region(rect: Rect2i) -> PackedByteArray:
        return read_result

    func find_spawn_position(origin: Vector2i, body_size: Vector2i, max_radius: float) -> Vector2i:
        return Vector2i(100, 100)

    func get_active_chunk_coords() -> Array:
        return []


func test_place_gas_delegates_to_adapter() -> void:
    var fake := FakeAdapter.new()
    var surface := TerrainSurface.new()
    surface.adapter = fake
    surface.place_gas(Vector2(10, 20), 5.0, 200)
    assert_that(fake.place_gas_calls.size()).is_equal(1)
    assert_that(fake.place_gas_calls[0].density).is_equal(200)

func test_place_lava_delegates_to_adapter() -> void:
    var fake := FakeAdapter.new()
    var surface := TerrainSurface.new()
    surface.adapter = fake
    surface.place_lava(Vector2(30, 40), 8.0)
    assert_that(fake.place_lava_calls.size()).is_equal(1)

func test_null_adapter_does_not_crash() -> void:
    var surface := TerrainSurface.new()
    surface.place_gas(Vector2.ZERO, 1.0, 100)
    surface.place_lava(Vector2.ZERO, 1.0)
    assert_bool(true).is_true()  # no crash
```

- [ ] **Step 12: Commit test**

```bash
git add tests/unit/test_terrain_surface.gd
git commit -m "test: add TerrainSurface adapter delegation tests"
```

---

## Tier B

### Task 3: TerrainPhysical — Unified terrain query + collision

**Files:**
- Create: `src/core/terrain_cell.gd`
- Create: `src/core/terrain_physical.gd`
- Modify: `src/core/world_manager.gd` (creates TerrainPhysical, feeds tracking_position)
- Modify: `src/core/terrain_modifier.gd` (calls TerrainPhysical.invalidate_rect after writes)
- Modify: `src/player/lava_damage_checker.gd` (uses TerrainPhysical.query)
- Modify: `src/player/player_controller.gd` (passes tracking_position to TerrainPhysical via WorldManager)
- Modify: `src/physics/gas_injector.gd` (uses TerrainPhysical.query instead of direct texture reads)
- Delete: `src/core/shadow_grid.gd`
- Delete: `src/core/terrain_reader.gd`
- Delete: `src/core/collision_manager.gd`
- Create: `tests/unit/test_terrain_physical.gd`

- [ ] **Step 1: Create TerrainCell resource**

```gdscript
# src/core/terrain_cell.gd
class_name TerrainCell
extends Resource

var material_id: int = 0
var is_solid: bool = false
var is_fluid: bool = false
var damage: float = 0.0

func _init(p_material_id: int = 0, p_is_solid: bool = false, p_is_fluid: bool = false, p_damage: float = 0.0) -> void:
	material_id = p_material_id
	is_solid = p_is_solid
	is_fluid = p_is_fluid
	damage = p_damage
```

- [ ] **Step 2: Create TerrainPhysical module**

```gdscript
# src/core/terrain_physical.gd
extends Node

## CPU-side cache: Vector2i(world_x, world_y) -> int (material_id)
var _grid: Dictionary = {}

## Grid center in world coords
var _grid_center: Vector2i = Vector2i.ZERO
var _grid_size: int = 128
var _half_grid: int = 64

## Dirty sectors waiting for collision rebuild
var _dirty_sectors: Array[Rect2i] = []

## Reference to WorldManager for GPU readback and collision building
var world_manager: Node2D = null

## Collision segments per chunk (for debug/collision queries)
var _segments_per_chunk: Dictionary = {}  # Vector2i -> Array[Vector2]


func query(world_pos: Vector2) -> TerrainCell:
	var cell_pos := Vector2i(int(floor(world_pos.x)), int(floor(world_pos.y)))
	if _grid.has(cell_pos):
		var mat_id: int = _grid[cell_pos]
		return _cell_from_material(mat_id)
	return TerrainCell.new()


func invalidate_rect(rect: Rect2i) -> void:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			_grid.erase(Vector2i(x, y))
	_dirty_sectors.append(rect)


func set_center(world_center: Vector2i) -> void:
	_grid_center = world_center


func _cell_from_material(mat_id: int) -> TerrainCell:
	var is_solid := MaterialRegistry.has_collider(mat_id)
	var is_fluid := MaterialRegistry.is_fluid(mat_id)
	var dmg := MaterialRegistry.get_damage(mat_id)
	return TerrainCell.new(mat_id, is_solid, is_fluid, dmg)
```

- [ ] **Step 3: Update WorldManager to create TerrainPhysical**

In `src/core/world_manager.gd`:
- Remove `collision_manager: CollisionManager` var declaration
- Add `var terrain_physical: TerrainPhysical` var declaration
- Add `var _collision_helper: RefCounted`

In `_ready()`:
```gdscript
# Replace: collision_manager = CollisionManager.new(self)
# With:
_collision_helper = TerrainCollisionHelper.new()
_collision_helper.world_manager = self
```

And add:
```gdscript
terrain_physical = TerrainPhysical.new()
terrain_physical.name = "TerrainPhysical"
terrain_physical.world_manager = self
add_child(terrain_physical)
```

In `_process(delta)`:
```gdscript
# Replace: collision_manager.rebuild_dirty_collisions(chunks, delta)
# With:
_collision_helper.rebuild_dirty(chunks, delta)
terrain_physical.set_center(Vector2i(tracking_position))
```

Also keep `_world_manager.tracking_position` updated. In `src/player/player_controller.gd`, restore the tracking_position update in `_physics_process`:
```gdscript
# At the end of _physics_process, before move_and_slide:
var wm := get_parent().get_node_or_null("WorldManager")
if wm:
    wm.tracking_position = global_position
```

- [ ] **Step 4: Update terrain_modifier.gd to invalidate TerrainPhysical cache**

After each write operation in `src/core/terrain_modifier.gd` (`place_gas`, `place_lava`, `place_fire`, `disperse_materials_in_arc`, `clear_and_push_materials_in_arc`), add a call to `TerrainPhysical.invalidate_rect(affected_rect)`.

Since TerrainModifier needs access to TerrainPhysical (which is a child of WorldManager), pass it through the constructor. Update WorldManager's TerrainModifier creation:

```gdscript
terrain_modifier = TerrainModifier.new(self)
terrain_modifier.terrain_physical = terrain_physical
```

In each write method of `src/core/terrain_modifier.gd`, after the write completes, add:
```gdscript
if terrain_physical:
    terrain_physical.invalidate_rect(affected_rect)
```

- [ ] **Step 5: Update lava_damage_checker.gd**

Replace ShadowGrid usage with TerrainPhysical:

```gdscript
# src/player/lava_damage_checker.gd
extends Node

const SAMPLE_GRID_SIZE := 3  # 3x3 samples

var _player: CharacterBody2D
var _terrain_physical: Node


func _ready() -> void:
    _player = get_parent() as CharacterBody2D
    # Get TerrainPhysical from WorldManager
    var wm := get_parent().get_parent().get_node_or_null("WorldManager")
    if wm:
        _terrain_physical = wm.get_node_or_null("TerrainPhysical")


func _physics_process(delta: float) -> void:
    if _terrain_physical == null:
        return
    var pos := _player.global_position
    var half := SAMPLE_GRID_SIZE / 2
    var total_damage: float = 0.0
    for dx in range(-half, half + 1):
        for dy in range(-half, half + 1):
            var sample_pos := pos + Vector2(dx, dy)
            var cell: TerrainCell = _terrain_physical.query(sample_pos)
            total_damage += cell.damage
    if total_damage > 0.0:
        var health_comp := get_node_or_null("../HealthComponent")
        if health_comp:
            health_comp.take_damage(floori(total_damage))
```

- [ ] **Step 6: Rename collision_manager.gd, delete shadow_grid.gd and terrain_reader.gd**

```bash
# Rename: collision_manager.gd becomes terrain_collision_helper.gd
mv src/core/collision_manager.gd src/core/terrain_collision_helper.gd
# Update class_name in renamed file from CollisionManager to TerrainCollisionHelper
# And rename the method from rebuild_dirty_collisions to rebuild_dirty
rm src/core/shadow_grid.gd
rm src/core/terrain_reader.gd
```

In `src/core/terrain_collision_helper.gd`:
- Change `class_name CollisionManager` to `class_name TerrainCollisionHelper`
- Change method `rebuild_dirty_collisions(chunks: Dictionary, delta: float)` to `rebuild_dirty(chunks: Dictionary, delta: float)`

- [ ] **Step 7: Create stub collision rebuild in TerrainPhysical**

TerrainPhysical delegates collision rebuilding to a helper that wraps the existing CollisionManager logic. Create `src/core/terrain_collision_helper.gd` as an internal adapter:

```gdscript
# src/core/terrain_collision_helper.gd
extends RefCounted

## Internal helper that wraps the GPU collider + CPU marching squares logic.
## This is the old CollisionManager, now owned by TerrainPhysical.

const CHUNK_SIZE := 256
const COLLISION_REBUILD_INTERVAL := 0.2
const COLLISIONS_PER_FRAME := 4

var world_manager: Node2D
var _collision_rebuild_timer: float = 0.0
var _collision_rebuild_index: int = 0


func rebuild_dirty(chunks: Dictionary, dirty_rects: Array[Rect2i], delta: float) -> void:
	_collision_rebuild_timer += delta
	if _collision_rebuild_timer < COLLISION_REBUILD_INTERVAL:
		return
	_collision_rebuild_timer = 0.0

	var chunk_coords: Array[Vector2i] = []
	for coord in chunks:
		chunk_coords.append(coord)

	var count := mini(COLLISIONS_PER_FRAME, chunk_coords.size())
	for i in range(count):
		var idx := (_collision_rebuild_index + i) % chunk_coords.size()
		var coord: Vector2i = chunk_coords[idx]
		var chunk: Chunk = chunks[coord]
		var success := _rebuild_chunk_collision_gpu(chunk)
		if not success:
			_rebuild_chunk_collision_cpu(chunk)

	_collision_rebuild_index = (_collision_rebuild_index + count) % max(1, chunk_coords.size())


func _rebuild_chunk_collision_cpu(chunk: Chunk) -> void:
	var chunk_data: PackedByteArray = world_manager.rd.texture_get_data(chunk.rd_texture, 0)
	var material_data := PackedByteArray()
	material_data.resize(CHUNK_SIZE * CHUNK_SIZE)
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			var src_idx := (y * CHUNK_SIZE + x) * 4
			var mat: int = chunk_data[src_idx]
			material_data[y * CHUNK_SIZE + x] = mat if MaterialRegistry.has_collider(mat) else 0

	var world_offset := chunk.coord * CHUNK_SIZE
	if chunk.static_body.get_child_count() > 0:
		for child in chunk.static_body.get_children():
			child.queue_free()

	var collision_shape := TerrainCollider.build_collision(material_data, CHUNK_SIZE, chunk.static_body, world_offset)
	if collision_shape != null:
		chunk.static_body.add_child(collision_shape)


func _rebuild_chunk_collision_gpu(chunk: Chunk) -> bool:
	var compute: ComputeDevice = world_manager.compute_device
	var buffer_data := PackedByteArray()
	buffer_data.resize(4)
	buffer_data.encode_u32(0, 0)
	world_manager.rd.buffer_update(compute.collider_storage_buffer, 0, buffer_data.size(), buffer_data)

	var uniforms: Array[RDUniform] = []
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(chunk.rd_texture)
	uniforms.append(u0)

	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u1.binding = 1
	u1.add_id(compute.collider_storage_buffer)
	uniforms.append(u1)

	var uniform_set: RID = world_manager.rd.uniform_set_create(uniforms, compute.collider_shader, 0)
	var compute_list: int = world_manager.rd.compute_list_begin()
	world_manager.rd.compute_list_bind_compute_pipeline(compute_list, compute.collider_pipeline)
	world_manager.rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	world_manager.rd.compute_list_dispatch(compute_list, 16, 16, 1)
	world_manager.rd.compute_list_end()
	world_manager.rd.free_rid(uniform_set)

	var result_data: PackedByteArray = world_manager.rd.buffer_get_data(compute.collider_storage_buffer)
	if result_data.size() < 4:
		return false

	var segment_count: int = result_data.decode_u32(0)
	if segment_count == 0:
		if chunk.static_body.get_child_count() > 0:
			for child in chunk.static_body.get_children():
				child.queue_free()
		return true

	var segments := _parse_segment_buffer(result_data.slice(4), segment_count * 4)

	var world_offset := chunk.coord * CHUNK_SIZE
	if chunk.static_body.get_child_count() > 0:
		for child in chunk.static_body.get_children():
			child.queue_free()

	if segments.size() >= 4:
		var collision_shape := TerrainCollider.build_from_segments(segments, chunk.static_body, world_offset)
		if collision_shape != null:
			chunk.static_body.add_child(collision_shape)

		for occluder in chunk.occluder_instances:
			if is_instance_valid(occluder):
				occluder.queue_free()
		chunk.occluder_instances.clear()

		var occluder_polygons := TerrainCollider.create_occluder_polygons(segments)
		var chunk_pos := Vector2(chunk.coord.x * CHUNK_SIZE, chunk.coord.y * CHUNK_SIZE)
		for poly in occluder_polygons:
			var occ := LightOccluder2D.new()
			occ.position = chunk_pos
			occ.occluder = poly
			world_manager.collision_container.add_child(occ)
			chunk.occluder_instances.append(occ)

	return true


func _parse_segment_buffer(data: PackedByteArray, max_offset: int) -> PackedVector2Array:
	var segments := PackedVector2Array()
	var offset := 0
	while offset + 16 <= data.size() and offset < max_offset:
		var x1 := float(data.decode_u32(offset))
		var y1 := float(data.decode_u32(offset + 4))
		var x2 := float(data.decode_u32(offset + 8))
		var y2 := float(data.decode_u32(offset + 12))
		if x1 == 0.0 and y1 == 0.0 and x2 == 0.0 and y2 == 0.0:
			break
		segments.append(Vector2(x1, y1))
		segments.append(Vector2(x2, y2))
		offset += 16
	return segments
```

In `src/core/terrain_physical.gd`, add the collision helper:
```gdscript
var _collision_helper: RefCounted

func _process(delta: float) -> void:
    if _collision_helper and world_manager:
        _collision_helper.rebuild_dirty(world_manager.chunks, _dirty_sectors, delta)
```

In `src/core/world_manager.gd`, update `_process`:
```gdscript
terrain_physical.set_center(Vector2i(tracking_position))
var helper := terrain_physical._collision_helper
if helper:
    helper.rebuild_dirty(chunks, terrain_physical._dirty_sectors, delta)
```

And set up the helper in `_ready()`:
```gdscript
terrain_physical._collision_helper = TerrainCollisionHelper.new()
terrain_physical._collision_helper.world_manager = self
```

-- Actually, the simplest approach: just have WorldManager own the collision helper and call it directly. TerrainPhysical doesn't need to own collision building — it just owns terrain queries. Collision building stays in WorldManager's `_process`. The file `collision_manager.gd` is renamed to `terrain_collision_helper.gd` and used as an internal class.

Simplify: CollisionManager.gd file is renamed, WorldManager uses it directly. No change to collision flow. TerrainPhysical focuses on query+cache only.

So `collision_manager.gd` becomes `src/core/terrain_collision_helper.gd`. WorldManager creates it in `_ready()`. WorldManager._process calls `_collision_helper.rebuild_dirty(chunks, delta)`. No changes to how collisions work.

```
rm src/core/collision_manager.gd
# create src/core/terrain_collision_helper.gd with same content, renamed class
```

In WorldManager._ready(), replace:
```gdscript
collision_manager = CollisionManager.new(self)
```
with:
```gdscript
_collision_helper = TerrainCollisionHelper.new()
_collision_helper.world_manager = self
```

In WorldManager._process(), replace:
```gdscript
collision_manager.rebuild_dirty_collisions(chunks, delta)
```
with:
```gdscript
_collision_helper.rebuild_dirty(chunks, delta)
```

- [ ] **Step 8: Commit TerrainPhysical implementation**

```bash
git add src/core/terrain_cell.gd src/core/terrain_physical.gd
git add src/core/world_manager.gd src/core/terrain_modifier.gd
git add src/player/lava_damage_checker.gd
git add -u src/core/
git commit -m "refactor: create TerrainPhysical module, absorb ShadowGrid/CollisionManager/TerrainReader"
```

- [ ] **Step 9: Write TerrainPhysical test**

```gdscript
# tests/unit/test_terrain_physical.gd
extends GdUnitTestSuite

func test_query_empty_grid_returns_default_cell() -> void:
    var tp := TerrainPhysical.new()
    var cell := tp.query(Vector2(50, 60))
    assert_that(cell.material_id).is_equal(0)
    assert_that(cell.is_solid).is_false()
    assert_that(cell.damage).is_equal(0.0)

func test_query_cached_cell() -> void:
    var tp := TerrainPhysical.new()
    # Directly populate the cache for testing
    tp._grid[Vector2i(10, 20)] = MaterialRegistry.WOOD
    var cell := tp.query(Vector2(10, 20))
    assert_that(cell.material_id).is_equal(MaterialRegistry.WOOD)

func test_invalidate_removes_from_cache() -> void:
    var tp := TerrainPhysical.new()
    tp._grid[Vector2i(15, 25)] = MaterialRegistry.STONE
    tp.invalidate_rect(Rect2i(10, 20, 10, 10))
    var cell := tp.query(Vector2(15, 25))
    assert_that(cell.material_id).is_equal(0)  # erased by invalidate

func test_set_center_updates_grid_center() -> void:
    var tp := TerrainPhysical.new()
    tp.set_center(Vector2i(500, 500))
    assert_that(tp._grid_center).is_equal(Vector2i(500, 500))
```

- [ ] **Step 10: Commit test**

```bash
git add tests/unit/test_terrain_physical.gd
git commit -m "test: add TerrainPhysical cache and query tests"
```

---

## Tier C

### Task 4: PickupContext + Pickupable — Unified drop detection and interface

**Files:**
- Create: `src/player/pickup_context.gd`
- Modify: `src/drops/drop.gd` (add Pickupable methods)
- Modify: `src/drops/gold_drop.gd` (add Pickupable methods)
- Modify: `src/drops/weapon_drop.gd` (add Pickupable methods)
- Modify: `src/drops/modifier_drop.gd` (add Pickupable methods)
- Modify: `src/player/player_controller.gd` (create PickupContext child)
- Delete: `src/player/interaction_controller.gd`
- Delete: `src/interactables/interactable.gd`
- Create: `tests/unit/test_pickup_context.gd`

Note: Pickupable in GDScript is a convention, not a formal interface. Drops implement `get_pickup_type()`, `get_pickup_payload()`, and `should_auto_pickup()`.

- [ ] **Step 1: Add Pickupable methods to drops**

In `src/drops/drop.gd`, add:
```gdscript
enum PickupType { GOLD, WEAPON, MODIFIER }

func get_pickup_type() -> int:
    return PickupType.WEAPON  # overridden by subclasses

func get_pickup_payload():
    return null

func should_auto_pickup() -> bool:
    return false
```

In `src/drops/gold_drop.gd`, add:
```gdscript
func get_pickup_type() -> int:
    return Drop.PickupType.GOLD

func get_pickup_payload():
    return amount

func should_auto_pickup() -> bool:
    return true
```

In `src/drops/weapon_drop.gd`, add:
```gdscript
func get_pickup_type() -> int:
    return Drop.PickupType.WEAPON

func get_pickup_payload():
    return weapon
```

In `src/drops/modifier_drop.gd`, add:
```gdscript
func get_pickup_type() -> int:
    return Drop.PickupType.MODIFIER

func get_pickup_payload():
    return modifier
```

- [ ] **Step 2: Create PickupContext module**

```gdscript
# src/player/pickup_context.gd
extends Node

const DETECTION_RADIUS: float = 12.0

var _player: CharacterBody2D
var _detection_area: Area2D
var _nearby_pickups: Array[Node2D] = []
var _highlighted: Node2D = null


func _ready() -> void:
	_player = get_parent() as CharacterBody2D
	_detection_area = Area2D.new()
	_detection_area.name = "DetectionArea"
	var shape := CircleShape2D.new()
	shape.radius = DETECTION_RADIUS
	var collision_shape := CollisionShape2D.new()
	collision_shape.shape = shape
	_detection_area.add_child(collision_shape)
	_detection_area.collision_mask = 2
	_detection_area.monitoring = true
	_detection_area.body_entered.connect(_on_body_entered)
	_detection_area.body_exited.connect(_on_body_exited)
	_player.add_child.call_deferred(_detection_area)


func _process(_delta: float) -> void:
	var closest := _find_closest_pickup()
	if _highlighted != closest:
		if _highlighted and is_instance_valid(_highlighted) and _highlighted.has_method("set_highlighted"):
			_highlighted.set_highlighted(false)
		_highlighted = closest
		if _highlighted and _highlighted.has_method("set_highlighted"):
			_highlighted.set_highlighted(true)


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event.is_action_pressed("interact") and _highlighted:
		if _highlighted.has_method("interact"):
			_highlighted.interact(_player)
		get_viewport().set_input_as_handled()


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("get_pickup_type") and body.has_method("should_auto_pickup"):
		if body.should_auto_pickup():
			return  # auto-pickup drops handle themselves
		if not _nearby_pickups.has(body):
			_nearby_pickups.append(body)


func _on_body_exited(body: Node2D) -> void:
	_nearby_pickups.erase(body)
	if _highlighted == body:
		if _highlighted and is_instance_valid(_highlighted) and _highlighted.has_method("set_highlighted"):
			_highlighted.set_highlighted(false)
		_highlighted = null


func _find_closest_pickup() -> Node2D:
	var closest: Node2D = null
	var closest_dist: float = INF
	var player_pos: Vector2 = _player.global_position
	for pickup in _nearby_pickups:
		if not is_instance_valid(pickup):
			_nearby_pickups.erase(pickup)
			continue
		var dist: float = pickup.global_position.distance_to(player_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = pickup
	return closest
```

- [ ] **Step 3: Update Drop base class for highlighting without Interactable**

In `src/drops/drop.gd`, remove `@onready var _interactable: Interactable = $Interactable` and replace `set_highlighted`:

```gdscript
func set_highlighted(enabled: bool) -> void:
	if _sprite and _sprite.material is ShaderMaterial:
		(_sprite.material as ShaderMaterial).set_shader_parameter("outline_width", 1.0 if enabled else 0.0)
```

Remove the `interact` method (it was a pass-through). Each drop subclass keeps its own `interact` which calls `_pickup`.

Actually — keep `interact` on the base Drop since PickupContext calls it. The base `interact` already calls `_pickup(player)`:

```gdscript
func interact(player: Node) -> void:
    _pickup(player)
```

This stays.

- [ ] **Step 4: Update player_controller.gd**

Replace `InteractionController` creation with `PickupContext`:

In `_ready()`, remove any InteractionController references. Add:
```gdscript
var pickup_context := PickupContext.new()
pickup_context.name = "PickupContext"
add_child(pickup_context)
```

- [ ] **Step 5: Delete InteractionController and Interactable**

```bash
rm src/player/interaction_controller.gd
rm src/interactables/interactable.gd
```

- [ ] **Step 6: Commit pickup refactor**

```bash
git add src/player/pickup_context.gd
git add src/drops/drop.gd src/drops/gold_drop.gd src/drops/weapon_drop.gd src/drops/modifier_drop.gd
git add src/player/player_controller.gd
git add -u src/player/interaction_controller.gd src/interactables/interactable.gd
git commit -m "refactor: create PickupContext, add Pickupable methods to drops, delete Interactable/InteractionController"
```

---

### Task 5: PlayerInventory — Unified player state

**Files:**
- Create: `src/player/player_inventory.gd`
- Modify: `src/player/player_controller.gd` (create PlayerInventory child)
- Modify: `src/weapons/weapon_manager.gd` (move slot management to PlayerInventory, keep input handling)
- Modify: `src/ui/currency_hud.gd` (listen to PlayerInventory signals)
- Modify: `src/ui/health_ui.gd` (listen to PlayerInventory signals)
- Modify: `src/ui/death_screen.gd` (listen to PlayerInventory signals)
- Modify: `src/ui/weapon_button.gd` (listen to PlayerInventory signals)
- Modify: `src/drops/gold_drop.gd` (use PlayerInventory)
- Modify: `src/economy/shop_ui.gd` (use PlayerInventory)
- Modify: `src/console/commands/gold_command.gd` (use PlayerInventory)
- Delete: `src/player/wallet_component.gd`
- Delete: `src/player/modifier_inventory.gd`
- Delete: `src/player/health_component.gd`
- Create: `tests/unit/test_player_inventory.gd`

- [ ] **Step 1: Create PlayerInventory module**

```gdscript
# src/player/player_inventory.gd
class_name PlayerInventory
extends Node

signal gold_changed(new_amount: int)
signal health_changed(current: int, maximum: int)
signal weapon_changed(slot: int)
signal modifier_changed(weapon_slot: int, modifier_slot: int)
signal player_died()

@export var max_health: int = 100
@export var invincibility_duration: float = 1.0

const BLINK_INTERVAL := 0.08
const MAX_WEAPON_SLOTS := 3

var gold: int = 0
var _current_health: int
var _invincible_timer: float = 0.0
var _is_dead: bool = false
var _is_invincible: bool = false
var _blink_timer: float = 0.0
var _color_rect: ColorRect

var weapons: Array = []  # Array[Weapon], size MAX_WEAPON_SLOTS, null for empty
var active_weapon_slot: int = 0


func _ready() -> void:
	_current_health = max_health
	weapons.resize(MAX_WEAPON_SLOTS)
	# color_rect for invincibility blink — parent is Player (CharacterBody2D)
	var parent_player := get_parent()
	if parent_player:
		_color_rect = parent_player.get_node_or_null("ColorRect")


func _physics_process(delta: float) -> void:
	if _is_invincible:
		_invincible_timer -= delta
		if _invincible_timer <= 0.0:
			_is_invincible = false
			_invincible_timer = 0.0
			if not _is_dead and _color_rect:
				_color_rect.visible = true


func _process(delta: float) -> void:
	if _is_invincible and not _is_dead and _color_rect:
		_blink_timer += delta
		if _blink_timer >= BLINK_INTERVAL:
			_blink_timer -= BLINK_INTERVAL
			_color_rect.visible = not _color_rect.visible


# ---- Gold ----

func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


# ---- Health ----

func take_damage(amount: int) -> void:
	if _is_dead or _is_invincible:
		return
	_current_health = maxi(_current_health - amount, 0)
	_is_invincible = true
	_invincible_timer = invincibility_duration
	health_changed.emit(_current_health, max_health)
	if _current_health <= 0:
		_is_dead = true
		if _color_rect:
			_color_rect.visible = true
		player_died.emit()


func heal(amount: int) -> void:
	if _is_dead:
		return
	_current_health = mini(_current_health + amount, max_health)
	health_changed.emit(_current_health, max_health)


func is_dead() -> bool:
	return _is_dead


func get_health() -> int:
	return _current_health


func get_max_health() -> int:
	return max_health


# ---- Weapons ----

func equip_weapon(slot: int, weapon) -> void:
	if slot < 0 or slot >= MAX_WEAPON_SLOTS:
		return
	weapons[slot] = weapon
	weapon_changed.emit(slot)


func remove_weapon(slot: int):
	if slot < 0 or slot >= MAX_WEAPON_SLOTS:
		return null
	var old := weapons[slot]
	weapons[slot] = null
	weapon_changed.emit(slot)
	return old


func get_weapon(slot: int):
	if slot < 0 or slot >= MAX_WEAPON_SLOTS:
		return null
	return weapons[slot]


func get_weapon_count() -> int:
	var count := 0
	for w in weapons:
		if w != null:
			count += 1
	return count


func has_empty_weapon_slot() -> bool:
	for w in weapons:
		if w == null:
			return true
	return false


func find_empty_weapon_slot() -> int:
	for i in range(MAX_WEAPON_SLOTS):
		if weapons[i] == null:
			return i
	return -1


# ---- Modifiers ----

func can_equip_modifier(weapon_slot: int) -> bool:
	var weapon = get_weapon(weapon_slot)
	if weapon == null:
		return false
	return weapon.find_empty_modifier_slot() >= 0


func add_modifier_to_weapon(weapon_slot: int, modifier_slot: int, modifier) -> void:
	var weapon = get_weapon(weapon_slot)
	if weapon == null:
		return
	weapon.add_modifier(modifier_slot, modifier)
	modifier_changed.emit(weapon_slot, modifier_slot)


func get_free_modifier_slot(weapon_slot: int) -> int:
	var weapon = get_weapon(weapon_slot)
	if weapon == null:
		return -1
	return weapon.find_empty_modifier_slot()


func get_all_modifiers() -> Array:
	var result: Array = []
	for weapon in weapons:
		if weapon == null:
			continue
		for m in weapon.modifiers:
			if m != null:
				result.append(m)
	return result
```

- [ ] **Step 2: Update player_controller.gd**

In `_ready()`, add PlayerInventory creation:
```gdscript
var inventory := PlayerInventory.new()
inventory.name = "PlayerInventory"
add_child(inventory)
```

In `_physics_process`, replace the `get_node_or_null("HealthComponent")` check with:
```gdscript
var inventory := get_node_or_null("PlayerInventory")
if inventory and inventory.is_dead():
    velocity = Vector2.ZERO
    move_and_slide()
    return
```

- [ ] **Step 3: Update weapon_manager.gd — move slot management to PlayerInventory**

The WeaponManager in `src/weapons/weapon_manager.gd` should become thinner — only input handling and visual management. Remove `weapons`, `active_slot`, `try_add_weapon`, `swap_weapon`, `swap_weapons`, `has_empty_slot`, `add_modifier_to_weapon`. Keep `_player`, `_visual`, `_sprite`, `_active_weapon`, `_setup_visual`, `_input`, `_activate_weapon`, `_process` (visual update), `_physics_process` (tick).

Replace direct weapon array access with PlayerInventory:

```gdscript
# In _ready(), replace weapons array setup:
func _ready() -> void:
    _player = get_parent()
    _setup_visual.call_deferred()


# In _input, replace weapon[s] access:
var inventory: PlayerInventory = _player.get_node_or_null("PlayerInventory")
if not inventory:
    return
var weapon = inventory.get_weapon(slot)
if weapon != null and weapon.is_ready():
    _activate_weapon(weapon)
    weapon.use(_player)
    inventory.active_weapon_slot = slot
    weapon_activated.emit(slot)


# In _physics_process, replace weapons iteration:
var inventory: PlayerInventory = _player.get_node_or_null("PlayerInventory")
if inventory:
    for i in range(PlayerInventory.MAX_WEAPON_SLOTS):
        var weapon = inventory.get_weapon(i)
        if weapon != null:
            weapon.tick(delta)
```

Delete methods: `swap_weapons`, `try_add_weapon`, `swap_weapon`, `has_empty_slot`, `add_modifier_to_weapon`.

- [ ] **Step 4: Update UI to listen to PlayerInventory signals**

In `src/ui/currency_hud.gd`:
```gdscript
func _ready() -> void:
    var player := get_tree().get_first_node_in_group("player")
    if player:
        var inventory: PlayerInventory = player.get_node_or_null("PlayerInventory")
        if inventory:
            inventory.gold_changed.connect(_on_gold_changed)
```

In `src/ui/health_ui.gd`:
```gdscript
func _ready() -> void:
    var player := get_tree().get_first_node_in_group("player")
    if player:
        var inventory: PlayerInventory = player.get_node_or_null("PlayerInventory")
        if inventory:
            inventory.health_changed.connect(_on_health_changed)
```

In `src/ui/death_screen.gd`:
```gdscript
func _ready() -> void:
    var player := get_tree().get_first_node_in_group("player")
    if player:
        var inventory: PlayerInventory = player.get_node_or_null("PlayerInventory")
        if inventory:
            inventory.player_died.connect(_on_player_died)
```

In `src/ui/weapon_button.gd`:
```gdscript
func _ready() -> void:
    var player := get_tree().get_first_node_in_group("player")
    if player:
        var inventory: PlayerInventory = player.get_node_or_null("PlayerInventory")
        if inventory:
            inventory.weapon_changed.connect(_on_weapon_changed)
            inventory.modifier_changed.connect(_on_modifier_changed)
```

- [ ] **Step 5: Update gold_drop.gd to use PlayerInventory**

```gdscript
if dist_sq <= PICKUP_RANGE * PICKUP_RANGE:
    var inventory: PlayerInventory = player.get_node_or_null("PlayerInventory")
    if inventory:
        inventory.add_gold(amount)
    queue_free()
```

- [ ] **Step 6: Update shop_ui.gd to use PlayerInventory**

Replace all `WalletComponent` references:
- `player.get_node("WalletComponent")` → `player.get_node("PlayerInventory")`
- `wallet.gold_changed` → `inventory.gold_changed`
- `wallet.spend_gold(...)` → `inventory.spend_gold(...)`
- `wallet.add_gold(...)` → `inventory.add_gold(...)`

- [ ] **Step 7: Update gold_command.gd to use PlayerInventory**

Replace `WalletComponent` references with `PlayerInventory`.

- [ ] **Step 8: Delete old component files**

```bash
rm src/player/wallet_component.gd
rm src/player/modifier_inventory.gd
rm src/player/health_component.gd
```

- [ ] **Step 9: Commit PlayerInventory**

```bash
git add src/player/player_inventory.gd
git add src/player/player_controller.gd
git add src/weapons/weapon_manager.gd
git add src/ui/currency_hud.gd src/ui/health_ui.gd src/ui/death_screen.gd src/ui/weapon_button.gd
git add src/drops/gold_drop.gd src/economy/shop_ui.gd src/console/commands/gold_command.gd
git add -u src/player/wallet_component.gd src/player/modifier_inventory.gd src/player/health_component.gd
git commit -m "refactor: create PlayerInventory, merge Wallet/Health/Modifier/WeaponSlots"
```

- [ ] **Step 10: Write PlayerInventory test**

```gdscript
# tests/unit/test_player_inventory.gd
extends GdUnitTestSuite


func test_add_gold_increases_gold() -> void:
    var inv := PlayerInventory.new()
    inv.add_gold(10)
    assert_that(inv.gold).is_equal(10)


func test_spend_gold_succeeds_with_sufficient_gold() -> void:
    var inv := PlayerInventory.new()
    inv.add_gold(20)
    assert_that(inv.spend_gold(5)).is_true()
    assert_that(inv.gold).is_equal(15)


func test_spend_gold_fails_with_insufficient_gold() -> void:
    var inv := PlayerInventory.new()
    inv.add_gold(3)
    assert_that(inv.spend_gold(10)).is_false()
    assert_that(inv.gold).is_equal(3)


func test_take_damage_reduces_health() -> void:
    var inv := PlayerInventory.new()
    inv.take_damage(30)
    assert_that(inv.get_health()).is_equal(inv.max_health - 30)


func test_take_damage_does_not_go_below_zero() -> void:
    var inv := PlayerInventory.new()
    inv.take_damage(9999)
    assert_that(inv.get_health()).is_equal(0)
    assert_that(inv.is_dead()).is_true()


func test_invincibility_prevents_double_damage() -> void:
    var inv := PlayerInventory.new()
    inv.take_damage(10)
    inv.take_damage(10)  # blocked by invincibility
    assert_that(inv.get_health()).is_equal(inv.max_health - 10)


func test_heal_restores_health() -> void:
    var inv := PlayerInventory.new()
    var half := inv.max_health / 2
    inv.take_damage(half)
    inv.heal(20)
    assert_that(inv.get_health()).is_equal(inv.max_health - half + 20)


func test_equip_weapon_sets_slot() -> void:
    var inv := PlayerInventory.new()
    var weapon := Weapon.new()
    inv.equip_weapon(0, weapon)
    assert_that(inv.get_weapon(0)).is_equal(weapon)


func test_has_empty_weapon_slot() -> void:
    var inv := PlayerInventory.new()
    assert_that(inv.has_empty_weapon_slot()).is_true()
    inv.equip_weapon(0, Weapon.new())
    inv.equip_weapon(1, Weapon.new())
    inv.equip_weapon(2, Weapon.new())
    assert_that(inv.has_empty_weapon_slot()).is_false()
```

- [ ] **Step 11: Commit test**

```bash
git add tests/unit/test_player_inventory.gd
git commit -m "test: add PlayerInventory tests for gold, health, and weapon slots"
```

---

## Tier D

### Task 6: WeaponDelivery — Unified pickup flow

**Files:**
- Create: `src/player/weapon_offer_spec.gd`
- Create: `src/player/weapon_delivery.gd`
- Modify: `src/drops/weapon_drop.gd` (use WeaponDelivery)
- Modify: `src/drops/modifier_drop.gd` (use WeaponDelivery)
- Modify: `src/economy/shop_ui.gd` (use WeaponDelivery)
- Modify: `src/player/player_controller.gd` (create WeaponDelivery child)
- Create: `tests/unit/test_weapon_delivery.gd`

- [ ] **Step 1: Create WeaponOfferSpec resource**

```gdscript
# src/player/weapon_offer_spec.gd
class_name WeaponOfferSpec
extends Resource

enum OfferType { WEAPON, MODIFIER, REMOVE_MODIFIER }

var type: int = OfferType.WEAPON
var weapon = null  # Weapon
var modifier = null  # Modifier
var suggested_slot: int = 0
```

- [ ] **Step 2: Create WeaponDelivery module**

```gdscript
# src/player/weapon_delivery.gd
extends Node

var _player: Node2D
var _inventory: PlayerInventory
var _popup = null  # WeaponPopup reference
var _pending_callback: Callable
var _test_mode: bool = false
var _test_response_accepted: bool = false
var _test_response_slot: int = 0


func _ready() -> void:
	_player = get_parent()
	_inventory = _player.get_node_or_null("PlayerInventory")


func offer(spec: WeaponOfferSpec, callback: Callable) -> void:
	match spec.type:
		WeaponOfferSpec.OfferType.WEAPON:
			_offer_weapon(spec, callback)
		WeaponOfferSpec.OfferType.MODIFIER:
			_offer_modifier(spec, callback)
		WeaponOfferSpec.OfferType.REMOVE_MODIFIER:
			_offer_remove_modifier(spec, callback)


func _offer_weapon(spec: WeaponOfferSpec, callback: Callable) -> void:
	if not _inventory:
		callback.call(false, -1)
		return
	if _test_mode:
		# In test mode, directly apply and invoke callback
		if _test_response_accepted:
			var old := _inventory.remove_weapon(_test_response_slot)
			_inventory.equip_weapon(_test_response_slot, spec.weapon)
			# Transfer modifiers from old weapon if any
			if old and spec.weapon and old.modifiers:
				for i in range(min(old.modifiers.size(), spec.weapon.modifier_slot_count)):
					if old.modifiers[i] != null:
						spec.weapon.add_modifier(i, old.modifiers[i])
		callback.call(_test_response_accepted, _test_response_slot)
		return
	# Production: open WeaponPopup
	var popup := _get_weapon_popup()
	if popup == null:
		callback.call(false, -1)
		return
	var weapon_manager := _player.get_node_or_null("WeaponManager")
	_pending_callback = callback
	popup.open_for_pickup(weapon_manager, spec.weapon, _on_weapon_slot_selected)


func _offer_modifier(spec: WeaponOfferSpec, callback: Callable) -> void:
	if not _inventory:
		callback.call(false, -1)
		return
	if not _inventory.can_equip_modifier(spec.suggested_slot):
		# Check all weapons for any empty modifier slot
		var found := false
		for i in range(PlayerInventory.MAX_WEAPON_SLOTS):
			var free_slot := _inventory.get_free_modifier_slot(i)
			if free_slot >= 0:
				spec.suggested_slot = i
				found = true
				break
		if not found:
			# Flash weapon button to indicate no slots available
			var wpn_button := _player.get_parent().get_node_or_null("WeaponButton")
			if wpn_button and wpn_button.has_method("flash_slots_full"):
				wpn_button.flash_slots_full()
			callback.call(false, -1)
			return
	if _test_mode:
		if _test_response_accepted:
			_inventory.add_modifier_to_weapon(spec.suggested_slot, _test_response_slot, spec.modifier)
		callback.call(_test_response_accepted, _test_response_slot)
		return
	var popup := _get_weapon_popup()
	if popup == null:
		callback.call(false, -1)
		return
	var weapon_manager := _player.get_node_or_null("WeaponManager")
	_pending_callback = callback
	popup.open_for_modifier(weapon_manager, spec.modifier, _on_modifier_applied)


func _offer_remove_modifier(spec: WeaponOfferSpec, callback: Callable) -> void:
	if _test_mode:
		callback.call(_test_response_accepted, _test_response_slot)
		return
	var popup := _get_weapon_popup()
	if popup == null:
		callback.call(false, -1)
		return
	var weapon_manager := _player.get_node_or_null("WeaponManager")
	_pending_callback = callback
	popup.open_for_remove_modifier(weapon_manager, _on_remove_modifier_applied)


func _on_weapon_slot_selected(slot_index: int, modifier, _player_node: Node) -> void:
	if _pending_callback.is_valid():
		_pending_callback.call(true, slot_index)
	_pending_callback = Callable()


func _on_modifier_applied() -> void:
	if _pending_callback.is_valid():
		_pending_callback.call(true, 0)
	_pending_callback = Callable()


func _on_remove_modifier_applied() -> void:
	if _pending_callback.is_valid():
		_pending_callback.call(true, 0)
	_pending_callback = Callable()


func _get_weapon_popup():
	if _popup and is_instance_valid(_popup):
		return _popup
	var root := _player.get_parent()
	if root:
		_popup = root.get_node_or_null("WeaponPopup")
	return _popup
```

- [ ] **Step 3: Update weapon_drop.gd to use WeaponDelivery**

```gdscript
func _pickup(player: Node) -> void:
    var delivery: WeaponDelivery = player.get_node_or_null("WeaponDelivery")
    if delivery == null:
        return
    var spec := WeaponOfferSpec.new()
    spec.type = WeaponOfferSpec.OfferType.WEAPON
    spec.weapon = weapon
    delivery.offer(spec, _on_delivery_result)


func _on_delivery_result(accepted: bool, _slot: int) -> void:
    if accepted:
        queue_free()
```

- [ ] **Step 4: Update modifier_drop.gd to use WeaponDelivery**

```gdscript
func _pickup(player: Node) -> void:
    var delivery: WeaponDelivery = player.get_node_or_null("WeaponDelivery")
    if delivery == null:
        return
    var spec := WeaponOfferSpec.new()
    spec.type = WeaponOfferSpec.OfferType.MODIFIER
    spec.modifier = modifier
    spec.suggested_slot = 0
    delivery.offer(spec, _on_delivery_result)


func _on_delivery_result(accepted: bool, _slot: int) -> void:
    if accepted:
        queue_free()
```

- [ ] **Step 5: Update shop_ui.gd to use WeaponDelivery**

Replace the direct WeaponPopup opening in `_on_buy_pressed` with:
```gdscript
var player := get_tree().get_first_node_in_group("player")
var delivery: WeaponDelivery = player.get_node_or_null("WeaponDelivery")
if delivery == null:
    return
var spec := WeaponOfferSpec.new()
spec.type = WeaponOfferSpec.OfferType.MODIFIER
spec.modifier = card.modifier
spec.suggested_slot = 0
delivery.offer(spec, _on_modifier_purchase_result)
```

- [ ] **Step 6: Add WeaponDelivery to PlayerController**

In `src/player/player_controller.gd`, add to `_ready()`:
```gdscript
var delivery := WeaponDelivery.new()
delivery.name = "WeaponDelivery"
add_child(delivery)
```

- [ ] **Step 7: Commit WeaponDelivery**

```bash
git add src/player/weapon_offer_spec.gd src/player/weapon_delivery.gd
git add src/drops/weapon_drop.gd src/drops/modifier_drop.gd
git add src/economy/shop_ui.gd src/player/player_controller.gd
git commit -m "refactor: create WeaponDelivery module, unify pickup flow"
```

- [ ] **Step 8: Write WeaponDelivery test**

```gdscript
# tests/unit/test_weapon_delivery.gd
extends GdUnitTestSuite


func test_offer_weapon_accepts_and_calls_callback() -> void:
    var delivery := WeaponDelivery.new()
    delivery._test_mode = true
    delivery._test_response_accepted = true
    delivery._test_response_slot = 1

    var captured_accepted := false
    var captured_slot := -1
    var callback := func(accepted: bool, slot: int) -> void:
        captured_accepted = accepted
        captured_slot = slot

    var spec := WeaponOfferSpec.new()
    spec.type = WeaponOfferSpec.OfferType.WEAPON
    spec.weapon = Weapon.new()

    delivery.offer(spec, callback)
    assert_that(captured_accepted).is_true()
    assert_that(captured_slot).is_equal(1)


func test_offer_weapon_rejects_and_calls_callback() -> void:
    var delivery := WeaponDelivery.new()
    delivery._test_mode = true
    delivery._test_response_accepted = false

    var captured_accepted := true
    var callback := func(accepted: bool, _slot: int) -> void:
        captured_accepted = accepted

    var spec := WeaponOfferSpec.new()
    spec.type = WeaponOfferSpec.OfferType.WEAPON
    spec.weapon = Weapon.new()

    delivery.offer(spec, callback)
    assert_that(captured_accepted).is_false()


func test_offer_modifier_rejected_when_no_slots() -> void:
    var delivery := WeaponDelivery.new()
    delivery._test_mode = true
    # No PlayerInventory set, should call callback(false, -1)
    var captured_accepted := true
    var callback := func(accepted: bool, _slot: int) -> void:
        captured_accepted = accepted

    var spec := WeaponOfferSpec.new()
    spec.type = WeaponOfferSpec.OfferType.MODIFIER
    spec.modifier = Modifier.new()

    delivery.offer(spec, callback)
    assert_that(captured_accepted).is_false()
```

- [ ] **Step 9: Commit test**

```bash
git add tests/unit/test_weapon_delivery.gd
git commit -m "test: add WeaponDelivery callback and validation tests"
```

---

### Task 7: Scene file updates

**Files:**
- Modify: `scenes/levels/game.tscn` (and any other level scenes)

- [ ] **Step 1: Update game.tscn Player child nodes**

Open `scenes/levels/game.tscn` in the Godot editor or edit directly:

Remove these child nodes from the Player node:
- `HealthComponent` → deleted, now in PlayerInventory
- `WalletComponent` → deleted, now in PlayerInventory
- `ModifierInventory` → deleted, now in PlayerInventory
- `InteractionController` → deleted, now PickupContext

Add these child nodes to the Player node:
- `PlayerInventory` (Node, script: `res://src/player/player_inventory.gd`)
- `PickupContext` (Node, script: `res://src/player/pickup_context.gd`)
- `WeaponDelivery` (Node, script: `res://src/player/weapon_delivery.gd`)

Note: `WeaponManager` stays as a child of Player (it handles input and visuals).

- [ ] **Step 2: Verify no stale references to deleted nodes**

Search for any remaining references to deleted files:
```bash
rg "HealthComponent|WalletComponent|ModifierInventory|InteractionController|Interactable|ShadowGrid|TerrainReader|HitStopManager|ScreenShakeManager|HitSparkManager|DamageNumberManager|ChromaticFlashManager" src/ scenes/ --include '*.gd' --include '*.tscn'
```

Fix any remaining references.

- [ ] **Step 3: Commit scene updates**

```bash
git add scenes/levels/
git commit -m "refactor: update game scene for new PlayerInventory/PickupContext/WeaponDelivery children"
```

---

### Task 8: Final cleanup — remove dead code

- [ ] **Step 1: Remove `get_world_manager()` from PlayerController**

In `src/player/player_controller.gd`, delete the `get_world_manager()` method and the `ShadowGridScript` preload.

- [ ] **Step 2: Remove `_get_world_manager()` from TestWeapon and MeleeWeapon**

In `src/weapons/test_weapon.gd` and `src/weapons/melee_weapon.gd`, delete the `_get_world_manager()` function (weapons now use TerrainSurface).

- [ ] **Step 3: Verify all deleted files are committed**

```bash
git status
```

Ensure no stale `.uid` files for deleted scripts remain:
```bash
find src/ -name "*.gd.uid" | while read f; do
  base="${f%.uid}"
  if [ ! -f "$base" ]; then
    rm "$f"
  fi
done
```

- [ ] **Step 4: Commit cleanup**

```bash
git add -u
git commit -m "chore: remove dead code and stale references from all 6 refactors"
```

---

### Task 9: Run game to verify nothing is broken

- [ ] **Step 1: Start the Godot editor and run the game**

Open the project in Godot and verify:
1. Game starts without errors
2. Player can move with WASD
3. Melee weapon (X key) works — terrain clears, enemies take damage, juice plays, gold drops
4. Test weapon (Z key) works — gas places correctly
5. Gold auto-pickup works — gold adds to wallet, HUD updates
6. Weapon drops can be picked up — WeaponPopup shows, weapon equips
7. Modifier drops can be picked up — modifier applies to weapon
8. Shop works — gold is spent, modifiers are equipped
9. Debug overlays (F3) work — chunk grid and collision overlay display
10. Console (~) works — commands function
11. Pause menu works
12. Death screen works

---

## Verification Checklist

After all tasks are complete:

- [ ] All 8 autoloads in `project.godot` are correct (MaterialRegistry, SceneManager, ConsoleManager, WeaponRegistry, HitReaction, TerrainSurface — 6 total, down from 9)
- [ ] No file references any deleted class (HealthComponent, WalletComponent, ModifierInventory, InteractionController, Interactable, ShadowGrid, TerrainReader, CollisionManager, HitStopManager, ScreenShakeManager, HitSparkManager, DamageNumberManager, ChromaticFlashManager)
- [ ] All scene files load without errors
- [ ] Game runs without script errors
- [ ] All gdUnit4 tests pass
