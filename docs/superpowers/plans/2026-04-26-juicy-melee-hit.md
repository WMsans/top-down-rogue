# Juicy Melee Hit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the bug where the melee weapon does no damage to enemies, then layer in juice (knockback, flash+squash, hit-sparks, damage numbers, hit-stop, screen shake, chromatic flash) for an extremely meaty hit feel.

**Architecture:** The bug fix lives in `MeleeWeapon._use_impl`, which gains an enemy-arc scan that calls a new `Enemy.on_hit_impact(point, dir, damage)` method. Per-enemy juice (knockback, flash, squash) lives on `Enemy`/`DummyEnemy`. Global juice is split into five focused autoloads under `src/core/juice/`: `HitSparkManager`, `DamageNumberManager`, `HitStopManager`, `ScreenShakeManager`, `ChromaticFlashManager`. Each autoload has a single responsibility and `PROCESS_MODE_ALWAYS` so hit-stop doesn't freeze its own timers.

**Tech Stack:** Godot 4.6, GDScript, gdUnit4 (installed but no juice tests planned — visual feel verified by manual playtest via the existing `spawn enemy dummy` console command).

**Verification approach:** Each task ends with a manual playtest checklist in the running editor. Open Godot 4.6, run the project (`F5`), open the in-game console, run `spawn enemy dummy`, swing the melee weapon at the dummy, and confirm the listed outcome.

**Spec:** `docs/superpowers/specs/2026-04-26-juicy-melee-hit-design.md`

---

## File Structure

**New files**
- `src/core/juice/hit_spark_manager.gd` — autoload, spawns radial spark bursts
- `src/core/juice/damage_number_manager.gd` — autoload, spawns floating damage numbers
- `src/core/juice/hit_stop_manager.gd` — autoload, freezes `Engine.time_scale`
- `src/core/juice/screen_shake_manager.gd` — autoload, drives the active `Camera2D` offset
- `src/core/juice/chromatic_flash_manager.gd` — autoload, owns the chromatic-flash CanvasLayer + shader
- `scenes/fx/damage_number.tscn` — packed scene used by `DamageNumberManager`
- `scenes/fx/chromatic_flash.tscn` — packed scene used by `ChromaticFlashManager`
- `shaders/chromatic_flash.gdshader` — RGB-shift screen shader

**Modified files**
- `src/weapons/melee_weapon.gd` — enemy-arc scan + `on_hit_impact` calls
- `src/enemies/enemy.gd` — group join, `on_hit_impact`, knockback state, flash, squash; track base color so subtypes override the resting color
- `src/enemies/dummy_enemy.gd` — apply `_knockback_velocity` in movement; declare base color = green via the new shared API
- `project.godot` — register all five juice manager autoloads

---

## Task 1: Bug Fix — Melee actually damages enemies (no juice yet)

**Files:**
- Modify: `src/enemies/enemy.gd`
- Modify: `src/weapons/melee_weapon.gd`

This task fixes only the bug. Juice is added in subsequent tasks so each layer can be verified independently.

- [ ] **Step 1: Add the `attackable` group join to `Enemy._ready`**

Edit `src/enemies/enemy.gd`. Replace `_ready`:

```gdscript
func _ready() -> void:
	add_to_group("attackable")
	health = max_health
```

- [ ] **Step 2: Add a placeholder `on_hit_impact` to `Enemy`**

In the same file, append below `hit`:

```gdscript
func on_hit_impact(_impact_point: Vector2, _hit_dir: Vector2, damage: int) -> void:
	hit(damage)
```

This is just the bug-fix path — later tasks expand this method.

- [ ] **Step 3: Scan the swing arc for attackables in `MeleeWeapon._use_impl`**

Edit `src/weapons/melee_weapon.gd`. Replace `_use_impl` with:

```gdscript
func _use_impl(user: Node) -> void:
	var world_manager := _get_world_manager(user)
	if world_manager == null:
		return
	var pos: Vector2 = user.global_position
	var direction := _get_facing_direction(user)
	_start_swing(direction)
	var materials: Array[int] = MaterialRegistry.get_fluids()
	world_manager.clear_and_push_materials_in_arc(pos, direction, RANGE, ARC_ANGLE, PUSH_SPEED, 0.25, materials)
	_hit_attackables_in_arc(user, pos, direction)


func _hit_attackables_in_arc(user: Node, origin: Vector2, direction: Vector2) -> void:
	var dmg: int = int(damage)
	if dmg <= 0:
		return
	var dir_angle: float = direction.angle()
	var half_arc: float = ARC_ANGLE / 2.0
	for node in user.get_tree().get_nodes_in_group("attackable"):
		if not (node is Node2D):
			continue
		if not node.has_method("on_hit_impact"):
			continue
		var to_target: Vector2 = node.global_position - origin
		var dist: float = to_target.length()
		if dist > RANGE or dist <= 0.001:
			continue
		if absf(angle_difference(dir_angle, to_target.angle())) > half_arc:
			continue
		var hit_dir: Vector2 = to_target / dist
		node.on_hit_impact(node.global_position, hit_dir, dmg)
```

- [ ] **Step 4: Manual verification — bug fix only**

1. Open Godot 4.6, press F5 to run.
2. Walk the player near a wall, open console (default key, see ConsoleManager), run `spawn enemy dummy`.
3. Swing the melee weapon at the dummy. Expected: the existing simpler green-flash from `DummyEnemy._on_hit` triggers, dummy HP decreases by 5 per swing (max_health 20 → 4 hits to kill), dummy is freed and drops loot on the 4th hit.
4. Swing while not facing the dummy: no damage.
5. Swing further than ~36px from the dummy: no damage.

If anything fails, debug before moving on.

- [ ] **Step 5: Commit**

```bash
git add src/enemies/enemy.gd src/weapons/melee_weapon.gd
git commit -m "fix: melee weapon now damages attackables in swing arc"
```

---

## Task 2: Per-Enemy Juice — Knockback

**Files:**
- Modify: `src/enemies/enemy.gd`
- Modify: `src/enemies/dummy_enemy.gd`

- [ ] **Step 1: Add knockback state and decay to `Enemy`**

Edit `src/enemies/enemy.gd`. Add constants near the top of the class body, below `@export`s:

```gdscript
const KNOCKBACK_SPEED: float = 180.0
const KNOCKBACK_DECAY: float = 12.0
```

Add field next to `health`:

```gdscript
var _knockback_velocity: Vector2 = Vector2.ZERO
```

Add a helper to decay it (called by subclasses' `_process`, since subclasses override `_process` for movement):

```gdscript
func _tick_knockback(delta: float) -> void:
	if _knockback_velocity.length_squared() < 1.0:
		_knockback_velocity = Vector2.ZERO
		return
	_knockback_velocity *= exp(-KNOCKBACK_DECAY * delta)
```

- [ ] **Step 2: Apply knockback impulse in `on_hit_impact`**

Replace the placeholder `on_hit_impact`:

```gdscript
func on_hit_impact(_impact_point: Vector2, hit_dir: Vector2, damage: int) -> void:
	if hit_dir.length_squared() > 0.0001:
		_knockback_velocity += hit_dir.normalized() * KNOCKBACK_SPEED
	hit(damage)
```

- [ ] **Step 3: Apply `_knockback_velocity` to `DummyEnemy` movement**

Edit `src/enemies/dummy_enemy.gd`. Replace `_process`:

```gdscript
func _process(delta: float) -> void:
	global_position += _knockback_velocity * delta
	_tick_knockback(delta)
	if _player == null or not is_instance_valid(_player):
		return
	var dir: Vector2 = _player.global_position - global_position
	if dir.length() < 4.0:
		return
	global_position += dir.normalized() * speed * delta
```

- [ ] **Step 4: Manual verification — knockback**

1. Run the game, spawn dummy, hit it.
2. Expected: dummy visibly slides ~10–20 px in the swing direction on each hit, then resumes chasing.
3. Hit it from multiple angles — knockback direction should follow the swing direction (player → enemy).

- [ ] **Step 5: Commit**

```bash
git add src/enemies/enemy.gd src/enemies/dummy_enemy.gd
git commit -m "feat: enemies get knockback on melee hit"
```

---

## Task 3: Per-Enemy Juice — Hit Flash + Squash-Stretch

**Files:**
- Modify: `src/enemies/enemy.gd`
- Modify: `src/enemies/dummy_enemy.gd`

- [ ] **Step 1: Move base modulate tracking into `Enemy`**

Edit `src/enemies/enemy.gd`. Add constants:

```gdscript
const FLASH_COLOR: Color = Color(3.0, 3.0, 3.0)
const FLASH_DECAY: float = 0.12
const SQUASH_SCALE: Vector2 = Vector2(1.4, 0.7)
const SQUASH_DURATION: float = 0.18
```

Add fields:

```gdscript
var _base_modulate: Color = Color.WHITE
var _flash_tween: Tween = null
var _squash_tween: Tween = null
```

Replace the existing `_hit_flash_tween` field (delete it — it was unused).

Add helper methods (above `_on_hit`):

```gdscript
func _set_base_modulate(c: Color) -> void:
	_base_modulate = c
	var sprite := get_node_or_null("Sprite2D")
	if sprite:
		sprite.modulate = c


func _play_hit_flash() -> void:
	var sprite := get_node_or_null("Sprite2D")
	if sprite == null:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	sprite.modulate = FLASH_COLOR
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", _base_modulate, FLASH_DECAY)


func _play_squash() -> void:
	var sprite := get_node_or_null("Sprite2D")
	if sprite == null:
		return
	if _squash_tween and _squash_tween.is_valid():
		_squash_tween.kill()
	sprite.scale = SQUASH_SCALE
	_squash_tween = create_tween()
	_squash_tween.set_trans(Tween.TRANS_ELASTIC)
	_squash_tween.set_ease(Tween.EASE_OUT)
	_squash_tween.tween_property(sprite, "scale", Vector2.ONE, SQUASH_DURATION)
```

- [ ] **Step 2: Replace `Enemy._on_hit` to drive flash + squash by default**

```gdscript
func _on_hit() -> void:
	_play_hit_flash()
	_play_squash()
```

- [ ] **Step 3: Update `DummyEnemy` to use the new base-color API**

Edit `src/enemies/dummy_enemy.gd`. Replace `_sprite_modulate_green` and `_on_hit`:

```gdscript
func _sprite_modulate_green() -> void:
	_set_base_modulate(Color(0.2, 0.8, 0.2))


func _on_hit() -> void:
	super._on_hit()
```

(The override is a no-op pass-through; we keep it so future per-dummy hooks have a place to live. If you prefer, delete `_on_hit` from `dummy_enemy.gd` entirely — it inherits the base behavior cleanly.)

- [ ] **Step 4: Manual verification — flash + squash**

1. Run, spawn dummy, hit it.
2. Expected: dummy briefly flashes nearly white, then fades back to green over ~0.12s.
3. Dummy sprite squashes wide-and-short on impact, then springs back with elastic ease over ~0.18s.
4. Rapid swings cancel previous tweens cleanly (no stuck modulate or scale).

- [ ] **Step 5: Commit**

```bash
git add src/enemies/enemy.gd src/enemies/dummy_enemy.gd
git commit -m "feat: enemies flash and squash on hit"
```

---

## Task 4: Global Juice — `HitStopManager` autoload

**Files:**
- Create: `src/core/juice/hit_stop_manager.gd`
- Modify: `project.godot`
- Modify: `src/enemies/enemy.gd`

- [ ] **Step 1: Create `HitStopManager`**

Create `src/core/juice/hit_stop_manager.gd`:

```gdscript
extends Node

const HIT_STOP_BASE: float = 0.06
const HIT_STOP_KILL_BONUS: float = 0.04

var _active_timer: SceneTreeTimer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func stop(duration: float) -> void:
	if duration <= 0.0:
		return
	Engine.time_scale = 0.0
	# Latest-call-wins: drop reference to old timer, start a new one.
	# `process_always = true` and `ignore_time_scale = true` so it fires while frozen.
	_active_timer = get_tree().create_timer(duration, true, false, true)
	var my_timer := _active_timer
	await my_timer.timeout
	if _active_timer == my_timer:
		Engine.time_scale = 1.0
		_active_timer = null
```

- [ ] **Step 2: Register the autoload**

Edit `project.godot`. Find the `[autoload]` section and add at the end:

```
HitStopManager="*res://src/core/juice/hit_stop_manager.gd"
```

- [ ] **Step 3: Call hit-stop from `Enemy.on_hit_impact`**

Edit `src/enemies/enemy.gd`. Replace `on_hit_impact`:

```gdscript
func on_hit_impact(_impact_point: Vector2, hit_dir: Vector2, damage: int) -> void:
	if hit_dir.length_squared() > 0.0001:
		_knockback_velocity += hit_dir.normalized() * KNOCKBACK_SPEED
	var lethal: bool = damage >= health
	var stop_duration: float = HitStopManager.HIT_STOP_BASE
	if lethal:
		stop_duration += HitStopManager.HIT_STOP_KILL_BONUS
	HitStopManager.stop(stop_duration)
	hit(damage)
```

- [ ] **Step 4: Manual verification — hit-stop**

1. Run, spawn dummy, hit it.
2. Expected: each hit produces a 60ms freeze of all motion (player, enemy, fluid sim). Subtle but noticeable — the swing animation visibly snaps to a halt then resumes.
3. Killing blow: ~100ms freeze, longer than non-lethal hits.
4. Rapid swings should not leave `time_scale` stuck at 0 (latest call wins, no orphan restores).

- [ ] **Step 5: Commit**

```bash
git add src/core/juice/hit_stop_manager.gd project.godot src/enemies/enemy.gd
git commit -m "feat: hit-stop manager + apply on melee impact"
```

---

## Task 5: Global Juice — `ScreenShakeManager` autoload

**Files:**
- Create: `src/core/juice/screen_shake_manager.gd`
- Modify: `project.godot`
- Modify: `src/enemies/enemy.gd`

- [ ] **Step 1: Create `ScreenShakeManager`**

Create `src/core/juice/screen_shake_manager.gd`:

```gdscript
extends Node

const SHAKE_AMOUNT: float = 3.0
const SHAKE_DURATION: float = 0.18

var _amount: float = 0.0
var _duration: float = 0.0
var _elapsed: float = 0.0
var _dir_bias: Vector2 = Vector2.ZERO
var _camera: Camera2D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func shake(amount: float, duration: float, dir: Vector2 = Vector2.ZERO) -> void:
	# Latest-call-wins.
	_amount = amount
	_duration = duration
	_elapsed = 0.0
	_dir_bias = dir
	_camera = get_viewport().get_camera_2d()


func _process(delta: float) -> void:
	if _camera == null or _duration <= 0.0:
		return
	_elapsed += delta
	if _elapsed >= _duration:
		_camera.offset = Vector2.ZERO
		_duration = 0.0
		return
	var t: float = 1.0 - (_elapsed / _duration)
	var current: float = _amount * t
	var rand_offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * current
	var bias := _dir_bias * 0.5 * current
	_camera.offset = rand_offset + bias
```

- [ ] **Step 2: Register the autoload**

Edit `project.godot`, append to `[autoload]`:

```
ScreenShakeManager="*res://src/core/juice/screen_shake_manager.gd"
```

- [ ] **Step 3: Call shake from `Enemy.on_hit_impact`**

Edit `src/enemies/enemy.gd`. Replace `on_hit_impact`:

```gdscript
func on_hit_impact(_impact_point: Vector2, hit_dir: Vector2, damage: int) -> void:
	if hit_dir.length_squared() > 0.0001:
		_knockback_velocity += hit_dir.normalized() * KNOCKBACK_SPEED
	var lethal: bool = damage >= health
	ScreenShakeManager.shake(ScreenShakeManager.SHAKE_AMOUNT, ScreenShakeManager.SHAKE_DURATION, hit_dir)
	var stop_duration: float = HitStopManager.HIT_STOP_BASE
	if lethal:
		stop_duration += HitStopManager.HIT_STOP_KILL_BONUS
	HitStopManager.stop(stop_duration)
	hit(damage)
```

- [ ] **Step 4: Manual verification — screen shake**

1. Run, spawn dummy, hit it.
2. Expected: screen jolts ~3px on each hit, decaying to zero over ~0.18s.
3. Bias: shake feels slightly directional toward the swing direction (subtle).
4. Camera returns to exactly its rest offset after the shake (no permanent drift).

- [ ] **Step 5: Commit**

```bash
git add src/core/juice/screen_shake_manager.gd project.godot src/enemies/enemy.gd
git commit -m "feat: screen shake on melee impact"
```

---

## Task 6: Global Juice — `HitSparkManager` autoload

**Files:**
- Create: `src/core/juice/hit_spark_manager.gd`
- Modify: `project.godot`
- Modify: `src/enemies/enemy.gd`

- [ ] **Step 1: Create `HitSparkManager`**

Create `src/core/juice/hit_spark_manager.gd`:

```gdscript
extends Node

const SPARK_COUNT_MIN: int = 6
const SPARK_COUNT_MAX: int = 8
const SPARK_SPEED_MIN: float = 80.0
const SPARK_SPEED_MAX: float = 160.0
const SPARK_LIFETIME: float = 0.15
const SPARK_CONE_HALF_ANGLE: float = PI / 6.0  # 30°
const SPARK_SIZE: Vector2 = Vector2(2, 2)
const SPARK_COLOR: Color = Color(1.0, 1.0, 0.85, 1.0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func spawn(point: Vector2, dir: Vector2) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var base_angle: float = dir.angle() if dir.length_squared() > 0.0001 else 0.0
	var count: int = randi_range(SPARK_COUNT_MIN, SPARK_COUNT_MAX)
	for i in count:
		var spark := ColorRect.new()
		spark.color = SPARK_COLOR
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
```

- [ ] **Step 2: Register the autoload**

Edit `project.godot`, append to `[autoload]`:

```
HitSparkManager="*res://src/core/juice/hit_spark_manager.gd"
```

- [ ] **Step 3: Call spark spawn from `Enemy.on_hit_impact`**

Edit `src/enemies/enemy.gd`. Replace `on_hit_impact`:

```gdscript
func on_hit_impact(impact_point: Vector2, hit_dir: Vector2, damage: int) -> void:
	if hit_dir.length_squared() > 0.0001:
		_knockback_velocity += hit_dir.normalized() * KNOCKBACK_SPEED
	HitSparkManager.spawn(impact_point, hit_dir)
	var lethal: bool = damage >= health
	ScreenShakeManager.shake(ScreenShakeManager.SHAKE_AMOUNT, ScreenShakeManager.SHAKE_DURATION, hit_dir)
	var stop_duration: float = HitStopManager.HIT_STOP_BASE
	if lethal:
		stop_duration += HitStopManager.HIT_STOP_KILL_BONUS
	HitStopManager.stop(stop_duration)
	hit(damage)
```

- [ ] **Step 4: Manual verification — sparks**

1. Run, spawn dummy, hit it.
2. Expected: 6–8 small pale-yellow square sparks burst in a 60° cone aligned with the swing direction, fade and disappear within ~0.15s.
3. Sparks survive across the hit-stop frame (they exist but don't move while frozen, then resume).

- [ ] **Step 5: Commit**

```bash
git add src/core/juice/hit_spark_manager.gd project.godot src/enemies/enemy.gd
git commit -m "feat: hit spark burst on melee impact"
```

---

## Task 7: Global Juice — `DamageNumberManager` autoload + scene

**Files:**
- Create: `scenes/fx/damage_number.tscn`
- Create: `src/core/juice/damage_number_manager.gd`
- Modify: `project.godot`
- Modify: `src/enemies/enemy.gd`

- [ ] **Step 1: Create the `damage_number.tscn` scene file**

Create `scenes/fx/damage_number.tscn`:

```
[gd_scene format=3 uid="uid://damage_number_fx"]

[sub_resource type="LabelSettings" id="LabelSettings_dmg"]
font_size = 12
font_color = Color(1, 1, 1, 1)
outline_size = 2
outline_color = Color(0, 0, 0, 1)

[node name="DamageNumber" type="Label"]
horizontal_alignment = 1
vertical_alignment = 1
label_settings = SubResource("LabelSettings_dmg")
```

This is a minimal Label scene; the manager scripts the motion on it directly.

- [ ] **Step 2: Create `DamageNumberManager`**

Create `src/core/juice/damage_number_manager.gd`:

```gdscript
extends Node

const DAMAGE_NUMBER_LIFETIME: float = 0.6
const HOLD_FRACTION: float = 2.0 / 3.0  # 0.4s hold, 0.2s fade
const POP_DURATION: float = 0.12
const POP_SCALE: Vector2 = Vector2(1.2, 1.2)
const INITIAL_VELOCITY_Y: float = -80.0
const INITIAL_VELOCITY_X_RANGE: float = 30.0
const GRAVITY: float = 200.0
const SPAWN_OFFSET: Vector2 = Vector2(0, -8)

const SCENE := preload("res://scenes/fx/damage_number.tscn")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func spawn(pos: Vector2, amount: int) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var label: Label = SCENE.instantiate()
	label.text = str(amount)
	label.global_position = pos + SPAWN_OFFSET
	label.scale = Vector2(0.5, 0.5)
	label.z_index = 100
	label.z_as_relative = false
	scene_root.add_child(label)

	var hold_time: float = DAMAGE_NUMBER_LIFETIME * HOLD_FRACTION
	var fade_time: float = DAMAGE_NUMBER_LIFETIME - hold_time
	var velocity := Vector2(randf_range(-INITIAL_VELOCITY_X_RANGE, INITIAL_VELOCITY_X_RANGE), INITIAL_VELOCITY_Y)

	# Pop scale: 0.5 -> 1.2 -> 1.0
	var pop := label.create_tween()
	pop.tween_property(label, "scale", POP_SCALE, POP_DURATION * 0.5)
	pop.tween_property(label, "scale", Vector2.ONE, POP_DURATION * 0.5)

	# Position via custom updater so we can apply gravity
	var motion := label.create_tween()
	motion.tween_method(_drive_motion.bind(label, velocity, pos + SPAWN_OFFSET), 0.0, DAMAGE_NUMBER_LIFETIME, DAMAGE_NUMBER_LIFETIME)

	# Alpha: hold then fade
	var fade := label.create_tween()
	fade.tween_interval(hold_time)
	fade.tween_property(label, "modulate:a", 0.0, fade_time)
	fade.tween_callback(label.queue_free)


func _drive_motion(t: float, label: Label, initial_vel: Vector2, start_pos: Vector2) -> void:
	if not is_instance_valid(label):
		return
	var pos := start_pos + initial_vel * t + Vector2(0, 0.5 * GRAVITY * t * t)
	label.global_position = pos
```

- [ ] **Step 3: Register the autoload**

Edit `project.godot`, append to `[autoload]`:

```
DamageNumberManager="*res://src/core/juice/damage_number_manager.gd"
```

- [ ] **Step 4: Call damage-number spawn from `Enemy.on_hit_impact`**

Edit `src/enemies/enemy.gd`. Replace `on_hit_impact`:

```gdscript
func on_hit_impact(impact_point: Vector2, hit_dir: Vector2, damage: int) -> void:
	if hit_dir.length_squared() > 0.0001:
		_knockback_velocity += hit_dir.normalized() * KNOCKBACK_SPEED
	HitSparkManager.spawn(impact_point, hit_dir)
	DamageNumberManager.spawn(global_position, damage)
	var lethal: bool = damage >= health
	ScreenShakeManager.shake(ScreenShakeManager.SHAKE_AMOUNT, ScreenShakeManager.SHAKE_DURATION, hit_dir)
	var stop_duration: float = HitStopManager.HIT_STOP_BASE
	if lethal:
		stop_duration += HitStopManager.HIT_STOP_KILL_BONUS
	HitStopManager.stop(stop_duration)
	hit(damage)
```

- [ ] **Step 5: Manual verification — damage numbers**

1. Run, spawn dummy, hit it.
2. Expected: a white "5" with a black outline pops above the enemy, scales up briefly (pop), drifts upward then falls back with gravity, fades over ~0.6s.
3. Multiple hits in quick succession: numbers stack with random horizontal drift, each independent.

- [ ] **Step 6: Commit**

```bash
git add scenes/fx/damage_number.tscn src/core/juice/damage_number_manager.gd project.godot src/enemies/enemy.gd
git commit -m "feat: floating damage numbers on hit"
```

---

## Task 8: Global Juice — `ChromaticFlashManager` autoload + shader + scene

**Files:**
- Create: `shaders/chromatic_flash.gdshader`
- Create: `scenes/fx/chromatic_flash.tscn`
- Create: `src/core/juice/chromatic_flash_manager.gd`
- Modify: `project.godot`
- Modify: `src/enemies/enemy.gd`

- [ ] **Step 1: Create the chromatic-flash shader**

Create `shaders/chromatic_flash.gdshader`:

```glsl
shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec2 axis = vec2(1.0, 0.0);

void fragment() {
	vec2 offset = axis * strength * 0.012;
	float r = texture(SCREEN_TEXTURE, SCREEN_UV - offset).r;
	float g = texture(SCREEN_TEXTURE, SCREEN_UV).g;
	float b = texture(SCREEN_TEXTURE, SCREEN_UV + offset).b;
	float a = strength;
	COLOR = vec4(r, g, b, a);
}
```

Note: Godot 4 `canvas_item` shaders need `hint_screen_texture` and `filter_nearest` to read SCREEN_TEXTURE. Replace the uniform list with:

```glsl
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec2 axis = vec2(1.0, 0.0);

void fragment() {
	vec2 offset = axis * strength * 0.012;
	float r = texture(screen_tex, SCREEN_UV - offset).r;
	float g = texture(screen_tex, SCREEN_UV).g;
	float b = texture(screen_tex, SCREEN_UV + offset).b;
	COLOR = vec4(r, g, b, strength);
}
```

Use this second version. (The first is shown for context — Godot 4 requires the explicit `hint_screen_texture` uniform.)

- [ ] **Step 2: Create `chromatic_flash.tscn`**

Create `scenes/fx/chromatic_flash.tscn`:

```
[gd_scene load_steps=3 format=3 uid="uid://chromatic_flash_fx"]

[ext_resource type="Shader" path="res://shaders/chromatic_flash.gdshader" id="1"]

[sub_resource type="ShaderMaterial" id="ShaderMaterial_chrom"]
shader = ExtResource("1")
shader_parameter/strength = 0.0
shader_parameter/axis = Vector2(1, 0)

[node name="ChromaticFlash" type="CanvasLayer"]
layer = 100

[node name="Rect" type="ColorRect" parent="."]
material = SubResource("ShaderMaterial_chrom")
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 2
color = Color(1, 1, 1, 0)
```

- [ ] **Step 3: Create `ChromaticFlashManager`**

Create `src/core/juice/chromatic_flash_manager.gd`:

```gdscript
extends Node

const CHROMATIC_STRENGTH: float = 0.6
const CHROMATIC_DURATION: float = 0.12

const SCENE := preload("res://scenes/fx/chromatic_flash.tscn")

var _layer: CanvasLayer = null
var _rect: ColorRect = null
var _material: ShaderMaterial = null
var _tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = SCENE.instantiate()
	add_child(_layer)
	_rect = _layer.get_node("Rect")
	_material = _rect.material as ShaderMaterial
	_material.set_shader_parameter("strength", 0.0)


func flash(strength: float = CHROMATIC_STRENGTH, duration: float = CHROMATIC_DURATION) -> void:
	if _material == null:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_material.set_shader_parameter("strength", strength)
	_tween = create_tween()
	_tween.tween_method(_set_strength, strength, 0.0, duration)


func _set_strength(value: float) -> void:
	if _material:
		_material.set_shader_parameter("strength", value)
```

- [ ] **Step 4: Register the autoload**

Edit `project.godot`, append to `[autoload]`:

```
ChromaticFlashManager="*res://src/core/juice/chromatic_flash_manager.gd"
```

- [ ] **Step 5: Call chromatic flash from `Enemy.on_hit_impact`**

Edit `src/enemies/enemy.gd`. Replace `on_hit_impact`:

```gdscript
func on_hit_impact(impact_point: Vector2, hit_dir: Vector2, damage: int) -> void:
	if hit_dir.length_squared() > 0.0001:
		_knockback_velocity += hit_dir.normalized() * KNOCKBACK_SPEED
	HitSparkManager.spawn(impact_point, hit_dir)
	DamageNumberManager.spawn(global_position, damage)
	var lethal: bool = damage >= health
	ScreenShakeManager.shake(ScreenShakeManager.SHAKE_AMOUNT, ScreenShakeManager.SHAKE_DURATION, hit_dir)
	ChromaticFlashManager.flash()
	var stop_duration: float = HitStopManager.HIT_STOP_BASE
	if lethal:
		stop_duration += HitStopManager.HIT_STOP_KILL_BONUS
	HitStopManager.stop(stop_duration)
	hit(damage)
```

- [ ] **Step 6: Manual verification — chromatic flash**

1. Run, spawn dummy, hit it.
2. Expected: a brief RGB-shift fringing flashes across the entire screen on each hit, fading to zero over ~0.12s.
3. Effect persists across scene changes (manager is autoload). Test by hitting an enemy, then moving to a new chunk, then hitting again.
4. No permanent overlay tint — when at rest, the screen looks identical to before this task.

If the shader fails to compile or `SCREEN_TEXTURE` doesn't sample correctly, double-check that the `hint_screen_texture` uniform line is present.

- [ ] **Step 7: Commit**

```bash
git add shaders/chromatic_flash.gdshader scenes/fx/chromatic_flash.tscn src/core/juice/chromatic_flash_manager.gd project.godot src/enemies/enemy.gd
git commit -m "feat: chromatic flash overlay on melee impact"
```

---

## Task 9: Final integration verification

**Files:** none modified — purely a playtest.

- [ ] **Step 1: Multi-enemy stress test**

1. Run, spawn 3–5 dummies via repeated `spawn enemy dummy`.
2. Group them and swing through all of them with one melee swing.
3. Expected:
   - All enemies in arc take damage on the same swing.
   - Each gets its own knockback, flash, squash, spark burst, damage number.
   - Hit-stop / shake / chromatic flash do not stack — they replace (latest-call-wins). No frozen-time bug, no permanent camera offset, no stuck shader strength.
4. Kill all enemies. Confirm loot drops still work and the killing-blow hit-stop is slightly longer than non-lethal.

- [ ] **Step 2: Edge cases**

1. Swing at empty space: no juice fires.
2. Swing past an enemy outside the arc: no damage, no juice.
3. Swing at maximum range (~36 px): hits register.
4. Swing at minimum range (touching): hits register; sparks/numbers spawn at sensible positions.

- [ ] **Step 3: No regressions**

1. Fluid push still works — swing into water/lava and confirm fluids are pushed (the original `clear_and_push_materials_in_arc` call is intact).
2. Player health/death system, drop pickups, weapon UI, modifier slots all behave as before.

- [ ] **Step 4: Commit (optional, only if verification revealed needed tweaks)**

If you found and fixed a bug during this task, commit with a descriptive message. Otherwise no commit needed.

---

## Notes for Implementer

- **Autoload order:** Godot loads autoloads in the order they appear in `project.godot`. The five juice managers have no inter-dependencies, so order doesn't matter for them. Just keep them grouped at the bottom of the existing `[autoload]` block.
- **Why `PROCESS_MODE_ALWAYS` on every juice manager:** `HitStopManager` sets `Engine.time_scale = 0`, which would otherwise freeze the very managers that need to keep ticking (the shake interpolation, the flash tween, the spark motion). All managers being process-always keeps animations smooth across the freeze.
- **Why scene-root parenting for sparks and damage numbers:** They're throw-away cosmetic nodes that should sit in worldspace alongside enemies and despawn cleanly. The autoloads themselves persist across scene changes, so spawning into `get_tree().current_scene` is correct.
- **`SCENE_TEXTURE` quirks in Godot 4:** The chromatic shader uses the `hint_screen_texture` uniform pattern shown in Task 8 Step 1's *second* code block. The first block is illustrative only.
- **No automated tests:** This is a feel feature. Verify by playing.
