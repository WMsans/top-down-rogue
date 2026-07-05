# Enemy Visual Identity + Action Juice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace placeholder enemy textures with the existing caves sprite set, add a lightweight idle/walk breathing animation, layer new GPU-particle "juice" onto existing combat feedback moments (hurt, walking, windup, attack, dash-windup, dash, death), and give elites a distinct visual overlay.

**Architecture:** A new `EnemyAnimator` component drives two-frame texture swaps on the existing `Sprite2D` node, driven each physics tick from the enemy's state/velocity. Five new small `GPUParticles2D`-based VFX components (hurt spark, footstep dust, windup telegraph, attack slash, dash windup) follow the existing procedural-node pattern already used by `DashFireVfx`/`NailClashFX` — each is a `Node2D` subclass that builds its own `GPUParticles2D` child in `_ready()` and exposes one trigger method. `DashFireVfx` itself is converted from `CPUParticles2D` to `GPUParticles2D`. All new hook points live in `Enemy`'s existing state-machine call sites (`_on_hit`, `_change_state`, `_process_attack`, `_physics_process`, `_process_death`), gated by small virtual methods (`_uses_footstep_vfx()`, `_uses_windup_telegraph_vfx()`, `_uses_attack_slash_vfx()`) that `LungeEnemy` overrides off since it has its own dash-specific VFX.

**Tech Stack:** Godot 4.7 / GDScript, gdUnit4 tests (headless).

**Spec:** `docs/superpowers/specs/2026-07-05-enemy-visual-identity-design.md`

**Reference patterns (read before starting):**
- State machine + existing feedback hooks: `src/enemies/enemy.gd` (`_on_hit`, `_change_state`, `_process_attack`, `_physics_process`, `_process_death`, `_play_hit_flash`, `_play_squash`)
- Existing procedural particle component: `src/enemies/feedback/dash_fire_vfx.gd` (being converted from CPU to GPU in Task 12 — read it first, it's the template every new VFX file follows)
- Scene-based GPU particle FX for reference on `ParticleProcessMaterial`/`texture` wiring: `scenes/fx/nail_clash.tscn`, `src/player/feedback/nail_clash_fx.gd`
- Existing tests to mirror: `tests/unit/test_enemy_state_machine.gd`, `tests/unit/test_dash_fire_vfx.gd`, `tests/unit/test_lunge_enemy.gd`
- Spawn dispatcher (for context only, not modified): `src/core/spawn_dispatcher.gd`

**Running tests (used throughout):**
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
The `--import` step is required after adding new `.gd` files (registers `class_name`) and after adding new texture files (generates `.import` metadata) — run it before every test invocation in this plan, even when a step doesn't add a texture, since it's cheap and idempotent.

## Global Constraints

- All new particle VFX use `GPUParticles2D` with a `ParticleProcessMaterial`, never `CPUParticles2D`.
- All biomes reuse the caves sprite set (`textures/Enemies/caves/...`) as a placeholder — no per-biome palette work in this plan.
- Sprite variant is fixed per archetype/weapon (not random): `melee_enemy.gd`→grunt, `lunge_enemy.gd`→brute, `sniper_enemy.gd`→mage, `ranged_enemy.gd`+`AimedBurstWeapon`(or no weapon set)→archer, `ranged_enemy.gd`+`SplitShotWeapon`/`FanWeapon`→lobber.
- `boss_enemy.gd`, `dummy_enemy.gd`, `parry_dummy.gd` are out of scope — do not touch their scenes or scripts.
- No directional sprite flipping — the caves sprites are a normal/breathe-out pair, not walk-cycle direction frames.
- Reuse `shaders/visual/outline.gdshader` for the elite glow — do not author a new shader.

---

## Task 1: Shared particle texture helper (`EnemyVfxShared`)

Every new VFX component in this plan needs a small soft-edged dot texture and a two-stop fade gradient for its `GPUParticles2D`. Building this once avoids duplicating the same 15 lines across six files.

**Files:**
- Create: `src/enemies/feedback/enemy_vfx_shared.gd`
- Test: `tests/unit/test_enemy_visual_identity.gd`

**Interfaces:**
- Produces: `EnemyVfxShared.soft_dot_texture(size: int = 8) -> GradientTexture2D`, `EnemyVfxShared.fade_gradient(hot: Color, fade: Color) -> GradientTexture1D` — used by every VFX component created in Tasks 7–11.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_enemy_visual_identity.gd`:

```gdscript
extends GdUnitTestSuite


func test_soft_dot_texture_is_radial_fill() -> void:
	var tex := EnemyVfxShared.soft_dot_texture(8)
	assert_int(tex.fill).is_equal(GradientTexture2D.FILL_RADIAL)
	assert_int(tex.width).is_equal(8)
	assert_int(tex.height).is_equal(8)


func test_fade_gradient_interpolates_hot_to_fade() -> void:
	var hot := Color(1.0, 0.5, 0.2, 1.0)
	var fade := Color(1.0, 0.5, 0.2, 0.0)
	var tex := EnemyVfxShared.fade_gradient(hot, fade)
	assert_that(tex.gradient.get_color(0)).is_equal(hot)
	assert_that(tex.gradient.get_color(1)).is_equal(fade)
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
Expected: FAIL — `Identifier "EnemyVfxShared" not declared` (class does not exist yet).

- [ ] **Step 3: Create the helper**

Create `src/enemies/feedback/enemy_vfx_shared.gd`:

```gdscript
class_name EnemyVfxShared
extends RefCounted


static func soft_dot_texture(size: int = 8) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = size
	tex.height = size
	return tex


static func fade_gradient(hot: Color, fade: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, hot)
	g.set_color(1, fade)
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/enemies/feedback/enemy_vfx_shared.gd tests/unit/test_enemy_visual_identity.gd
git commit -m "feat: add shared particle texture helper for enemy VFX"
```

---

## Task 2: `EnemyAnimator` idle/walk/hold frame system

**Files:**
- Create: `src/enemies/feedback/enemy_animator.gd`
- Test: `tests/unit/test_enemy_visual_identity.gd`

**Interfaces:**
- Produces: `EnemyAnimator` (extends `Node`) with `texture_normal: Texture2D`, `texture_breathe: Texture2D` exports; `set_textures(normal: Texture2D, breathe: Texture2D) -> void`; `set_hold(mode: int) -> void` where `mode` is one of `EnemyAnimator.Hold.NONE/BREATHE/NORMAL`; `tick(delta: float, is_moving: bool, speed_ratio: float) -> void`. Consumed by `Enemy` in Task 3 and `LungeEnemy` in Task 6.

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_enemy_visual_identity.gd`:

```gdscript
func test_flicker_interval_idle_is_slow() -> void:
	var a: EnemyAnimator = auto_free(EnemyAnimator.new())
	assert_float(a._flicker_interval(false, 0.0)).is_equal(EnemyAnimator.IDLE_INTERVAL)


func test_flicker_interval_moving_fast_is_quick() -> void:
	var a: EnemyAnimator = auto_free(EnemyAnimator.new())
	assert_float(a._flicker_interval(true, 1.0)).is_equal(EnemyAnimator.MIN_MOVING_INTERVAL)


func test_flicker_interval_moving_scales_with_speed() -> void:
	var a: EnemyAnimator = auto_free(EnemyAnimator.new())
	var slow := a._flicker_interval(true, 0.2)
	var fast := a._flicker_interval(true, 0.8)
	assert_float(fast).is_less(slow)


func test_set_hold_breathe_forces_frame_and_blocks_tick() -> void:
	var a: EnemyAnimator = auto_free(EnemyAnimator.new())
	a.texture_normal = PlaceholderTexture2D.new()
	a.texture_breathe = PlaceholderTexture2D.new()
	a.set_hold(EnemyAnimator.Hold.BREATHE)
	assert_bool(a._showing_breathe).is_true()
	a.tick(1.0, true, 1.0)
	assert_bool(a._showing_breathe).is_true()


func test_set_hold_normal_forces_frame() -> void:
	var a: EnemyAnimator = auto_free(EnemyAnimator.new())
	a.texture_normal = PlaceholderTexture2D.new()
	a.texture_breathe = PlaceholderTexture2D.new()
	a.set_hold(EnemyAnimator.Hold.BREATHE)
	a.set_hold(EnemyAnimator.Hold.NORMAL)
	assert_bool(a._showing_breathe).is_false()


func test_tick_toggles_frame_after_interval() -> void:
	var a: EnemyAnimator = auto_free(EnemyAnimator.new())
	a.texture_normal = PlaceholderTexture2D.new()
	a.texture_breathe = PlaceholderTexture2D.new()
	a.tick(EnemyAnimator.IDLE_INTERVAL + 0.01, false, 0.0)
	assert_bool(a._showing_breathe).is_true()


func test_set_textures_assigns_both_fields() -> void:
	var a: EnemyAnimator = auto_free(EnemyAnimator.new())
	var n := PlaceholderTexture2D.new()
	var b := PlaceholderTexture2D.new()
	a.set_textures(n, b)
	assert_object(a.texture_normal).is_equal(n)
	assert_object(a.texture_breathe).is_equal(b)
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
Expected: FAIL — `Identifier "EnemyAnimator" not declared`.

- [ ] **Step 3: Create `EnemyAnimator`**

Create `src/enemies/feedback/enemy_animator.gd`:

```gdscript
class_name EnemyAnimator
extends Node

enum Hold { NONE, BREATHE, NORMAL }

const IDLE_INTERVAL: float = 0.6
const MIN_MOVING_INTERVAL: float = 0.12

@export var texture_normal: Texture2D = null
@export var texture_breathe: Texture2D = null

var _hold: int = Hold.NONE
var _timer: float = 0.0
var _showing_breathe: bool = false
var _sprite: Sprite2D = null


func _ready() -> void:
	_sprite = get_parent().get_node_or_null("Sprite2D")


func set_textures(normal: Texture2D, breathe: Texture2D) -> void:
	texture_normal = normal
	texture_breathe = breathe


func set_hold(mode: int) -> void:
	if _hold == mode:
		return
	_hold = mode
	if mode == Hold.BREATHE:
		_apply_frame(true)
	elif mode == Hold.NORMAL:
		_apply_frame(false)


func tick(delta: float, is_moving: bool, speed_ratio: float) -> void:
	if texture_normal == null or texture_breathe == null:
		return
	if _hold != Hold.NONE:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = _flicker_interval(is_moving, speed_ratio)
		_apply_frame(not _showing_breathe)


func _flicker_interval(is_moving: bool, speed_ratio: float) -> float:
	if not is_moving:
		return IDLE_INTERVAL
	var t: float = clampf(speed_ratio, 0.0, 1.0)
	return lerpf(IDLE_INTERVAL, MIN_MOVING_INTERVAL, t)


func _apply_frame(show_breathe: bool) -> void:
	_showing_breathe = show_breathe
	if _sprite == null:
		return
	_sprite.texture = texture_breathe if show_breathe else texture_normal
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add src/enemies/feedback/enemy_animator.gd tests/unit/test_enemy_visual_identity.gd
git commit -m "feat: add EnemyAnimator idle/walk/hold frame component"
```

---

## Task 3: Wire `EnemyAnimator` into `Enemy`'s tick loop

**Files:**
- Modify: `src/enemies/enemy.gd`
- Test: `tests/unit/test_enemy_visual_identity.gd`

**Interfaces:**
- Consumes: `EnemyAnimator.tick(delta, is_moving, speed_ratio)` from Task 2.
- Produces: `Enemy._animator` looked up by node name `"EnemyAnimator"` — any enemy scene that adds a child node named `EnemyAnimator` gets it ticked automatically every physics frame.

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_enemy_visual_identity.gd`:

```gdscript
class MockAnimatorEnemy extends Enemy:
	func _execute_attack() -> void:
		pass


func test_enemy_ticks_animator_when_present() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	e.add_child(sprite)
	var animator := EnemyAnimator.new()
	animator.name = "EnemyAnimator"
	animator.texture_normal = PlaceholderTexture2D.new()
	animator.texture_breathe = PlaceholderTexture2D.new()
	e.add_child(animator)
	add_child(e)
	await get_tree().process_frame
	e.speed = 60.0
	e.velocity = Vector2.ZERO
	e._physics_process(EnemyAnimator.IDLE_INTERVAL + 0.01)
	assert_object(sprite.texture).is_equal(animator.texture_breathe)


func test_enemy_without_animator_does_not_error() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	add_child(e)
	await get_tree().process_frame
	e._physics_process(0.5)
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
Expected: FAIL — sprite texture stays `null` (animator never ticked).

- [ ] **Step 3: Cache the animator and tick it in `_physics_process`**

In `src/enemies/enemy.gd`, add a new var near `_weapon_sprite` (around line 73):

```gdscript
var _weapon_sprite: Sprite2D = null
var _animator: EnemyAnimator = null
```

In `_ready()` (around line 96, right after the `if is_elite:` block), add:

```gdscript
	if is_elite:
		_apply_elite_scaling()
	_animator = get_node_or_null("EnemyAnimator")
```

At the end of `_physics_process` (after the `_resolve_crowd_overlap()` call, around line 217), add:

```gdscript
	if _animator:
		var moving := velocity.length_squared() > 4.0
		var ratio := 0.0
		if speed > 0.001:
			ratio = clampf(velocity.length() / speed, 0.0, 1.0)
		_animator.tick(delta, moving, ratio)
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
Expected: PASS (11 tests).

- [ ] **Step 5: Run the full enemy state machine suite to check nothing regressed**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_state_machine.gd
```
Expected: PASS (all existing tests still green).

- [ ] **Step 6: Commit**

```bash
git add src/enemies/enemy.gd tests/unit/test_enemy_visual_identity.gd
git commit -m "feat: tick EnemyAnimator from Enemy physics loop"
```

---

## Task 4: Fixed archetype sprite wiring (grunt, brute, mage)

Replaces placeholder textures with real caves sprites for the three archetypes whose sprite is fixed regardless of loadout: `melee_enemy.tscn` (grunt), `lunge_enemy.tscn` (brute), `sniper_enemy.tscn` (mage).

**Files:**
- Modify: `scenes/enemies/melee_enemy.tscn`
- Modify: `scenes/enemies/lunge_enemy.tscn`
- Modify: `scenes/enemies/sniper_enemy.tscn`
- Test: `tests/unit/test_enemy_visual_identity.gd`

**Interfaces:**
- Consumes: `EnemyAnimator` node (Task 2), texture files at `res://textures/Enemies/caves/grunt/`, `.../brute/`, `.../mage/`.

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_enemy_visual_identity.gd`:

```gdscript
func test_melee_enemy_scene_uses_grunt_sprites() -> void:
	var scene: PackedScene = load("res://scenes/enemies/melee_enemy.tscn")
	var e := auto_free(scene.instantiate())
	var sprite: Sprite2D = e.get_node("Sprite2D")
	var animator: EnemyAnimator = e.get_node("EnemyAnimator")
	assert_str(sprite.texture.resource_path).contains("caves_grunt1")
	assert_str(animator.texture_normal.resource_path).contains("caves_grunt1")
	assert_str(animator.texture_breathe.resource_path).contains("caves_grunt2")


func test_lunge_enemy_scene_uses_brute_sprites() -> void:
	var scene: PackedScene = load("res://scenes/enemies/lunge_enemy.tscn")
	var e := auto_free(scene.instantiate())
	var sprite: Sprite2D = e.get_node("Sprite2D")
	var animator: EnemyAnimator = e.get_node("EnemyAnimator")
	assert_str(sprite.texture.resource_path).contains("caves_brute1")
	assert_str(animator.texture_breathe.resource_path).contains("caves_brute2")


func test_sniper_enemy_scene_uses_mage_sprites() -> void:
	var scene: PackedScene = load("res://scenes/enemies/sniper_enemy.tscn")
	var e := auto_free(scene.instantiate())
	var sprite: Sprite2D = e.get_node("Sprite2D")
	var animator: EnemyAnimator = e.get_node("EnemyAnimator")
	assert_str(sprite.texture.resource_path).contains("caves_mage1")
	assert_str(animator.texture_breathe.resource_path).contains("caves_mage2")
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
Expected: FAIL — `Node not found: "EnemyAnimator"` (scenes don't have the node yet) and texture paths still contain `melee_test`/`ranged_test`.

- [ ] **Step 3: Rewrite `scenes/enemies/melee_enemy.tscn`**

Replace the full file contents with:

```
[gd_scene format=3 uid="uid://gi0acq1fmseu"]

[ext_resource type="PackedScene" uid="uid://enemybase01" path="res://scenes/enemies/enemy.tscn" id="1"]
[ext_resource type="Script" uid="uid://2p0rviaql6ea" path="res://src/enemies/melee_enemy.gd" id="2"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/grunt/caves_grunt1.png" id="3_grunt1"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/grunt/caves_grunt2.png" id="4_grunt2"]
[ext_resource type="Script" path="res://src/enemies/feedback/enemy_animator.gd" id="5"]

[node name="MeleeEnemy" unique_id=1872446034 instance=ExtResource("1")]
script = ExtResource("2")
weapon_resource = null

[node name="Sprite2D" parent="." index="0"]
texture = ExtResource("3_grunt1")

[node name="EnemyAnimator" type="Node" parent="."]
script = ExtResource("5")
texture_normal = ExtResource("3_grunt1")
texture_breathe = ExtResource("4_grunt2")
```

- [ ] **Step 4: Rewrite `scenes/enemies/lunge_enemy.tscn`**

Replace the full file contents with:

```
[gd_scene format=3 uid="uid://lungeenemy01"]

[ext_resource type="PackedScene" uid="uid://enemybase01" path="res://scenes/enemies/enemy.tscn" id="1"]
[ext_resource type="Script" path="res://src/enemies/lunge_enemy.gd" id="2"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/brute/caves_brute1.png" id="3_brute1"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/brute/caves_brute2.png" id="4_brute2"]
[ext_resource type="Script" path="res://src/enemies/feedback/enemy_animator.gd" id="5"]

[node name="LungeEnemy" instance=ExtResource("1")]
script = ExtResource("2")
weapon_resource = null

[node name="Sprite2D" parent="." index="0"]
texture = ExtResource("3_brute1")

[node name="EnemyAnimator" type="Node" parent="."]
script = ExtResource("5")
texture_normal = ExtResource("3_brute1")
texture_breathe = ExtResource("4_brute2")
```

- [ ] **Step 5: Rewrite `scenes/enemies/sniper_enemy.tscn`**

Replace the full file contents with:

```
[gd_scene format=3 uid="uid://sniperenemy01"]

[ext_resource type="PackedScene" uid="uid://enemybase01" path="res://scenes/enemies/enemy.tscn" id="1"]
[ext_resource type="Script" path="res://src/enemies/sniper_enemy.gd" id="2"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/mage/caves_mage1.png" id="3_mage1"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/mage/caves_mage2.png" id="4_mage2"]
[ext_resource type="Script" path="res://src/enemies/feedback/enemy_animator.gd" id="5"]

[node name="SniperEnemy" instance=ExtResource("1")]
script = ExtResource("2")
preferred_distance = 160.0

[node name="Sprite2D" parent="." index="0"]
texture = ExtResource("3_mage1")

[node name="EnemyAnimator" type="Node" parent="."]
script = ExtResource("5")
texture_normal = ExtResource("3_mage1")
texture_breathe = ExtResource("4_mage2")
```

- [ ] **Step 6: Run test to verify it passes**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
Expected: PASS (14 tests).

- [ ] **Step 7: Run the lunge enemy suite to check the scene change didn't break it**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_lunge_enemy.gd
```
Expected: PASS (all existing tests still green, including `test_scene_instantiates_as_lunge_enemy`).

- [ ] **Step 8: Commit**

```bash
git add scenes/enemies/melee_enemy.tscn scenes/enemies/lunge_enemy.tscn scenes/enemies/sniper_enemy.tscn tests/unit/test_enemy_visual_identity.gd
git commit -m "feat: wire grunt/brute/mage caves sprites into melee/lunge/sniper scenes"
```

---

## Task 5: Ranged enemy weapon-based sprite selection (archer / lobber)

**Files:**
- Modify: `src/enemies/ranged_enemy.gd`
- Modify: `scenes/enemies/ranged_enemy.tscn`
- Test: `tests/unit/test_enemy_visual_identity.gd`

**Interfaces:**
- Consumes: `EnemyAnimator.set_textures()` (Task 2), `AimedBurstWeapon`, `SplitShotWeapon`, `FanWeapon` classes (`src/weapons/aimed_burst_weapon.gd`, `split_shot_weapon.gd`, `fan_weapon.gd`).
- Produces: `RangedEnemy._select_sprite_textures() -> Array` (returns `[normal_texture, breathe_texture]`), consumed only within this file.

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_enemy_visual_identity.gd`:

```gdscript
func test_ranged_enemy_defaults_to_archer_sprite() -> void:
	var scene: PackedScene = load("res://scenes/enemies/ranged_enemy.tscn")
	var e: RangedEnemy = auto_free(scene.instantiate())
	add_child(e)
	await get_tree().process_frame
	var sprite: Sprite2D = e.get_node("Sprite2D")
	assert_str(sprite.texture.resource_path).contains("caves_archer1")


func test_ranged_enemy_with_aimed_burst_uses_archer_sprite() -> void:
	var scene: PackedScene = load("res://scenes/enemies/ranged_enemy.tscn")
	var e: RangedEnemy = auto_free(scene.instantiate())
	e.weapon_resource = AimedBurstWeapon.new()
	add_child(e)
	await get_tree().process_frame
	var sprite: Sprite2D = e.get_node("Sprite2D")
	assert_str(sprite.texture.resource_path).contains("caves_archer1")


func test_ranged_enemy_with_splitshot_uses_lobber_sprite() -> void:
	var scene: PackedScene = load("res://scenes/enemies/ranged_enemy.tscn")
	var e: RangedEnemy = auto_free(scene.instantiate())
	e.weapon_resource = SplitShotWeapon.new()
	add_child(e)
	await get_tree().process_frame
	var sprite: Sprite2D = e.get_node("Sprite2D")
	var animator: EnemyAnimator = e.get_node("EnemyAnimator")
	assert_str(sprite.texture.resource_path).contains("caves_lobber1")
	assert_str(animator.texture_breathe.resource_path).contains("caves_lobber2")


func test_ranged_enemy_with_fan_uses_lobber_sprite() -> void:
	var scene: PackedScene = load("res://scenes/enemies/ranged_enemy.tscn")
	var e: RangedEnemy = auto_free(scene.instantiate())
	e.weapon_resource = FanWeapon.new()
	add_child(e)
	await get_tree().process_frame
	var sprite: Sprite2D = e.get_node("Sprite2D")
	assert_str(sprite.texture.resource_path).contains("caves_lobber1")
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
Expected: FAIL — `Node not found: "EnemyAnimator"` and texture paths still contain `ranged_test`.

- [ ] **Step 3: Rewrite `scenes/enemies/ranged_enemy.tscn`**

Replace the full file contents with:

```
[gd_scene format=3 uid="uid://dvh7a7xjfwol6"]

[ext_resource type="PackedScene" uid="uid://enemybase01" path="res://scenes/enemies/enemy.tscn" id="1"]
[ext_resource type="Script" uid="uid://clhtbu0k0sbp0" path="res://src/enemies/ranged_enemy.gd" id="2"]
[ext_resource type="Texture2D" path="res://textures/Enemies/caves/archer/caves_archer1.png" id="3_archer1"]
[ext_resource type="Script" path="res://src/enemies/feedback/enemy_animator.gd" id="4"]

[node name="RangedEnemy" unique_id=1792751980 instance=ExtResource("1")]
script = ExtResource("2")
weapon_resource = null
preferred_distance = 120.0
strafe_speed = 40.0
back_away_acceleration = 200.0

[node name="Sprite2D" parent="." index="0"]
texture = ExtResource("3_archer1")

[node name="EnemyAnimator" type="Node" parent="."]
script = ExtResource("4")
```

- [ ] **Step 4: Add sprite selection to `ranged_enemy.gd`**

In `src/enemies/ranged_enemy.gd`, add constants near the top (after the `@export var back_away_acceleration` line):

```gdscript
const ARCHER_NORMAL: Texture2D = preload("res://textures/Enemies/caves/archer/caves_archer1.png")
const ARCHER_BREATHE: Texture2D = preload("res://textures/Enemies/caves/archer/caves_archer2.png")
const LOBBER_NORMAL: Texture2D = preload("res://textures/Enemies/caves/lobber/caves_lobber1.png")
const LOBBER_BREATHE: Texture2D = preload("res://textures/Enemies/caves/lobber/caves_lobber2.png")
```

At the end of `_ready()` (after `_setup_drop_table()`), add a call to a new method:

```gdscript
	_setup_drop_table()
	_apply_sprite_variant()
```

Add the new method at the bottom of the file:

```gdscript
func _select_sprite_textures() -> Array:
	if weapon_resource is SplitShotWeapon or weapon_resource is FanWeapon:
		return [LOBBER_NORMAL, LOBBER_BREATHE]
	return [ARCHER_NORMAL, ARCHER_BREATHE]


func _apply_sprite_variant() -> void:
	var textures := _select_sprite_textures()
	var sprite := get_node_or_null("Sprite2D")
	if sprite:
		sprite.texture = textures[0]
	var animator := get_node_or_null("EnemyAnimator")
	if animator:
		animator.set_textures(textures[0], textures[1])
```

- [ ] **Step 5: Run test to verify it passes**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
Expected: PASS (18 tests).

- [ ] **Step 6: Commit**

```bash
git add src/enemies/ranged_enemy.gd scenes/enemies/ranged_enemy.tscn tests/unit/test_enemy_visual_identity.gd
git commit -m "feat: pick archer/lobber sprite by ranged enemy weapon type"
```

---

## Task 6: Lunge dash-hold frame integration

Makes the brute's sprite hold the "breathe" (coiled) frame during dash windup and the "normal" (extended) frame during the dash itself, per the spec's animation rules.

**Files:**
- Modify: `src/enemies/lunge_enemy.gd`
- Test: `tests/unit/test_lunge_enemy.gd`

**Interfaces:**
- Consumes: `EnemyAnimator.set_hold(mode)` and `EnemyAnimator.Hold` enum (Task 2).

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_lunge_enemy.gd`:

```gdscript
# --- Enemy Visual Identity: dash-hold frame ---

func _lunge_from_scene() -> LungeEnemy:
	var scene: PackedScene = load("res://scenes/enemies/lunge_enemy.tscn")
	var e: LungeEnemy = auto_free(scene.instantiate())
	add_child(e)
	return e

func test_windup_holds_breathe_frame() -> void:
	var e := _lunge_from_scene()
	await get_tree().process_frame
	e._change_state(Enemy.State.WINDUP)
	var animator: EnemyAnimator = e.get_node("EnemyAnimator")
	assert_int(animator._hold).is_equal(EnemyAnimator.Hold.BREATHE)
	var sprite: Sprite2D = e.get_node("Sprite2D")
	assert_str(sprite.texture.resource_path).contains("caves_brute2")

func test_attack_holds_normal_frame() -> void:
	var e := _lunge_from_scene()
	await get_tree().process_frame
	e._change_state(Enemy.State.WINDUP)
	e._change_state(Enemy.State.ATTACK)
	var animator: EnemyAnimator = e.get_node("EnemyAnimator")
	assert_int(animator._hold).is_equal(EnemyAnimator.Hold.NORMAL)
	var sprite: Sprite2D = e.get_node("Sprite2D")
	assert_str(sprite.texture.resource_path).contains("caves_brute1")

func test_cooldown_releases_hold() -> void:
	var e := _lunge_from_scene()
	await get_tree().process_frame
	e._change_state(Enemy.State.WINDUP)
	e._change_state(Enemy.State.ATTACK)
	e._change_state(Enemy.State.COOLDOWN)
	var animator: EnemyAnimator = e.get_node("EnemyAnimator")
	assert_int(animator._hold).is_equal(EnemyAnimator.Hold.NONE)
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_lunge_enemy.gd
```
Expected: FAIL — `animator._hold` stays `EnemyAnimator.Hold.NONE` (lunge_enemy.gd doesn't set it yet).

- [ ] **Step 3: Extend `_change_state` in `lunge_enemy.gd`**

Replace the existing `_change_state` override:

```gdscript
func _change_state(new_state: int) -> void:
	if new_state == State.WINDUP:
		_dash_done = false
		_play_windup_telegraph()
	super._change_state(new_state)
```

with:

```gdscript
func _change_state(new_state: int) -> void:
	if new_state == State.WINDUP:
		_dash_done = false
		_play_windup_telegraph()
		_set_animator_hold(EnemyAnimator.Hold.BREATHE)
	elif new_state == State.ATTACK:
		_set_animator_hold(EnemyAnimator.Hold.NORMAL)
	elif new_state != State.HURT:
		_set_animator_hold(EnemyAnimator.Hold.NONE)
	super._change_state(new_state)


func _set_animator_hold(mode: int) -> void:
	var animator := get_node_or_null("EnemyAnimator")
	if animator:
		animator.set_hold(mode)
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_lunge_enemy.gd
```
Expected: PASS (all tests in the file, including the 3 new ones).

- [ ] **Step 5: Commit**

```bash
git add src/enemies/lunge_enemy.gd tests/unit/test_lunge_enemy.gd
git commit -m "feat: hold brute sprite frame during lunge windup/dash"
```

---

## Task 7: Hurt impact spark VFX

**Files:**
- Create: `src/enemies/feedback/hurt_spark_vfx.gd`
- Modify: `src/enemies/enemy.gd`
- Test: `tests/unit/test_enemy_visual_identity.gd`

**Interfaces:**
- Consumes: `EnemyVfxShared.soft_dot_texture()`, `EnemyVfxShared.fade_gradient()` (Task 1).
- Produces: `HurtSparkVfx.burst() -> void`. `Enemy._hurt_vfx` child node created in `_ready()`, triggered from `_on_hit()`.

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_enemy_visual_identity.gd`:

```gdscript
func test_enemy_has_hurt_vfx_child() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	add_child(e)
	await get_tree().process_frame
	assert_object(e._hurt_vfx).is_not_null()
	assert_bool(e._hurt_vfx is HurtSparkVfx).is_true()


func test_on_hit_bursts_hurt_vfx() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	e.health = 100
	add_child(e)
	await get_tree().process_frame
	e.hit(5)
	var particles: GPUParticles2D = e._hurt_vfx.get_node("Particles")
	assert_bool(particles.emitting).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
Expected: FAIL — `Identifier "HurtSparkVfx" not declared`.

- [ ] **Step 3: Create `HurtSparkVfx`**

Create `src/enemies/feedback/hurt_spark_vfx.gd`:

```gdscript
class_name HurtSparkVfx
extends Node2D

const SPARK_COLOR := Color(1.0, 0.95, 0.85, 1.0)
const SPARK_COLOR_FADE := Color(1.0, 0.3, 0.2, 0.0)

var _particles: GPUParticles2D = null


func _ready() -> void:
	z_index = 7
	z_as_relative = false
	_particles = _build_particles()
	add_child(_particles)


func burst() -> void:
	_particles.restart()
	_particles.emitting = true


func _build_particles() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = "Particles"
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 10
	p.lifetime = 0.2
	p.texture = EnemyVfxShared.soft_dot_texture()
	p.process_material = _build_process_material()
	p.z_as_relative = false
	p.z_index = 7
	return p


func _build_process_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0.0, -1.0, 0.0)
	m.spread = 180.0
	m.gravity = Vector3.ZERO
	m.initial_velocity_min = 60.0
	m.initial_velocity_max = 130.0
	m.scale_min = 0.6
	m.scale_max = 1.2
	m.color = SPARK_COLOR
	m.color_ramp = EnemyVfxShared.fade_gradient(SPARK_COLOR, SPARK_COLOR_FADE)
	return m
```

- [ ] **Step 4: Wire it into `Enemy`**

In `src/enemies/enemy.gd`, add a var near `_animator` (from Task 3):

```gdscript
var _animator: EnemyAnimator = null
var _hurt_vfx: HurtSparkVfx = null
```

In `_ready()`, after the `_setup_weapon_visual.call_deferred()` line, add:

```gdscript
	var hurt_vfx := HurtSparkVfx.new()
	hurt_vfx.name = "HurtSparkVfx"
	add_child(hurt_vfx)
	_hurt_vfx = hurt_vfx
```

In `_on_hit()`, change:

```gdscript
func _on_hit() -> void:
	_play_hit_flash()
	_play_squash()
```

to:

```gdscript
func _on_hit() -> void:
	_play_hit_flash()
	_play_squash()
	if _hurt_vfx:
		_hurt_vfx.burst()
```

- [ ] **Step 5: Run test to verify it passes**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
Expected: PASS (20 tests).

- [ ] **Step 6: Run the full enemy state machine suite to check nothing regressed**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_state_machine.gd
```
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/enemies/feedback/hurt_spark_vfx.gd src/enemies/enemy.gd tests/unit/test_enemy_visual_identity.gd
git commit -m "feat: add hurt impact spark VFX on enemy hit"
```

---

## Task 8: Footstep dust VFX (walking)

**Files:**
- Create: `src/enemies/feedback/footstep_dust_vfx.gd`
- Modify: `src/enemies/enemy.gd`
- Modify: `src/enemies/melee_enemy.gd`
- Test: `tests/unit/test_enemy_visual_identity.gd`

**Interfaces:**
- Consumes: `EnemyVfxShared` (Task 1).
- Produces: `FootstepDustVfx.puff() -> void`; `Enemy._uses_footstep_vfx() -> bool` (base returns `false`), `MeleeEnemy._uses_footstep_vfx() -> bool` (returns `true`); `Enemy._footstep_vfx` child triggered periodically from `_physics_process` while `State.CHASE` and moving.

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_enemy_visual_identity.gd`:

```gdscript
func test_base_enemy_does_not_use_footstep_vfx() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	assert_bool(e._uses_footstep_vfx()).is_false()


func test_melee_enemy_uses_footstep_vfx() -> void:
	var e: MeleeEnemy = auto_free(MeleeEnemy.new())
	assert_bool(e._uses_footstep_vfx()).is_true()


func test_lunge_enemy_does_not_use_footstep_vfx() -> void:
	var e: LungeEnemy = auto_free(LungeEnemy.new())
	assert_bool(e._uses_footstep_vfx()).is_false()


func test_chasing_melee_enemy_puffs_footstep_dust() -> void:
	var scene: PackedScene = load("res://scenes/enemies/melee_enemy.tscn")
	var e: MeleeEnemy = auto_free(scene.instantiate())
	add_child(e)
	await get_tree().process_frame
	e._state = Enemy.State.CHASE
	e.velocity = Vector2(60, 0)
	e._physics_process(FootstepDustVfx.FOOTSTEP_INTERVAL + 0.01)
	var particles: GPUParticles2D = e._footstep_vfx.get_node("Particles")
	assert_bool(particles.emitting).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
Expected: FAIL — `Function "_uses_footstep_vfx()" not found` and `Identifier "FootstepDustVfx" not declared`.

- [ ] **Step 3: Create `FootstepDustVfx`**

Create `src/enemies/feedback/footstep_dust_vfx.gd`:

```gdscript
class_name FootstepDustVfx
extends Node2D

const FOOTSTEP_INTERVAL: float = 0.28
const DUST_COLOR := Color(0.6, 0.5, 0.4, 0.6)
const DUST_COLOR_FADE := Color(0.6, 0.5, 0.4, 0.0)

var _particles: GPUParticles2D = null


func _ready() -> void:
	z_index = -1
	z_as_relative = false
	position = Vector2(0.0, 6.0)
	_particles = _build_particles()
	add_child(_particles)


func puff() -> void:
	_particles.restart()
	_particles.emitting = true


func _build_particles() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = "Particles"
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 6
	p.lifetime = 0.35
	p.texture = EnemyVfxShared.soft_dot_texture()
	p.process_material = _build_process_material()
	p.z_as_relative = false
	p.z_index = -1
	return p


func _build_process_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0.0, -1.0, 0.0)
	m.spread = 100.0
	m.gravity = Vector3.ZERO
	m.initial_velocity_min = 8.0
	m.initial_velocity_max = 20.0
	m.scale_min = 0.8
	m.scale_max = 1.4
	m.color = DUST_COLOR
	m.color_ramp = EnemyVfxShared.fade_gradient(DUST_COLOR, DUST_COLOR_FADE)
	return m
```

- [ ] **Step 4: Add the virtual method and footstep timer to `Enemy`**

In `src/enemies/enemy.gd`, add a constant near `SQUASH_DURATION`:

```gdscript
const SQUASH_DURATION: float = 0.18
const FOOTSTEP_MIN_SPEED_SQ: float = 100.0
```

Add vars near `_hurt_vfx` (from Task 7):

```gdscript
var _hurt_vfx: HurtSparkVfx = null
var _footstep_vfx: FootstepDustVfx = null
var _footstep_timer: float = 0.0
```

In `_ready()`, after the `HurtSparkVfx` block added in Task 7, add:

```gdscript
	var footstep_vfx := FootstepDustVfx.new()
	footstep_vfx.name = "FootstepDustVfx"
	add_child(footstep_vfx)
	_footstep_vfx = footstep_vfx
```

Add the virtual method near `_moves_during_attack()`:

```gdscript
func _uses_footstep_vfx() -> bool:
	return false
```

In `_physics_process`, after the `_animator` tick block added in Task 3, add:

```gdscript
	if _uses_footstep_vfx() and _state == State.CHASE and velocity.length_squared() > FOOTSTEP_MIN_SPEED_SQ:
		_footstep_timer -= delta
		if _footstep_timer <= 0.0:
			_footstep_timer = FootstepDustVfx.FOOTSTEP_INTERVAL
			if _footstep_vfx:
				_footstep_vfx.puff()
	else:
		_footstep_timer = 0.0
```

- [ ] **Step 5: Override the virtual method in `melee_enemy.gd`**

In `src/enemies/melee_enemy.gd`, add:

```gdscript
func _uses_footstep_vfx() -> bool:
	return true
```

- [ ] **Step 6: Override the virtual method in `lunge_enemy.gd`**

In `src/enemies/lunge_enemy.gd`, add (it extends `MeleeEnemy`, so it must explicitly turn the dust back off):

```gdscript
func _uses_footstep_vfx() -> bool:
	return false
```

- [ ] **Step 7: Run test to verify it passes**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
Expected: PASS (24 tests).

- [ ] **Step 8: Commit**

```bash
git add src/enemies/feedback/footstep_dust_vfx.gd src/enemies/enemy.gd src/enemies/melee_enemy.gd src/enemies/lunge_enemy.gd tests/unit/test_enemy_visual_identity.gd
git commit -m "feat: add footstep dust VFX for chasing melee enemies"
```

---

## Task 9: Windup telegraph VFX (preparing attack)

**Files:**
- Create: `src/enemies/feedback/windup_telegraph_vfx.gd`
- Modify: `src/enemies/enemy.gd`
- Modify: `src/enemies/lunge_enemy.gd`
- Test: `tests/unit/test_enemy_visual_identity.gd`

**Interfaces:**
- Consumes: `EnemyVfxShared` (Task 1).
- Produces: `WindupTelegraphVfx.play() -> void`; `Enemy._uses_windup_telegraph_vfx() -> bool` (base `true`), `LungeEnemy` override (`false`); `Enemy._windup_vfx` triggered from `_show_exclaim()`.

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_enemy_visual_identity.gd`:

```gdscript
func test_base_enemy_uses_windup_telegraph_vfx() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	assert_bool(e._uses_windup_telegraph_vfx()).is_true()


func test_lunge_enemy_does_not_use_windup_telegraph_vfx() -> void:
	var e: LungeEnemy = auto_free(LungeEnemy.new())
	assert_bool(e._uses_windup_telegraph_vfx()).is_false()


func test_windup_plays_telegraph_vfx_for_melee() -> void:
	var scene: PackedScene = load("res://scenes/enemies/melee_enemy.tscn")
	var e: MeleeEnemy = auto_free(scene.instantiate())
	add_child(e)
	await get_tree().process_frame
	e._change_state(Enemy.State.WINDUP)
	var particles: GPUParticles2D = e._windup_vfx.get_node("Particles")
	assert_bool(particles.emitting).is_true()


func test_windup_does_not_play_telegraph_vfx_for_lunge() -> void:
	var scene: PackedScene = load("res://scenes/enemies/lunge_enemy.tscn")
	var e: LungeEnemy = auto_free(scene.instantiate())
	add_child(e)
	await get_tree().process_frame
	e._change_state(Enemy.State.WINDUP)
	var particles: GPUParticles2D = e._windup_vfx.get_node("Particles")
	assert_bool(particles.emitting).is_false()
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
Expected: FAIL — `Function "_uses_windup_telegraph_vfx()" not found`.

- [ ] **Step 3: Create `WindupTelegraphVfx`**

Create `src/enemies/feedback/windup_telegraph_vfx.gd`:

```gdscript
class_name WindupTelegraphVfx
extends Node2D

const GLOW_COLOR := Color(1.0, 0.9, 0.3, 0.8)
const GLOW_COLOR_FADE := Color(1.0, 0.9, 0.3, 0.0)

var _particles: GPUParticles2D = null


func _ready() -> void:
	z_index = 5
	z_as_relative = false
	position = Vector2(0.0, -6.0)
	_particles = _build_particles()
	add_child(_particles)


func play() -> void:
	_particles.restart()
	_particles.emitting = true


func _build_particles() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = "Particles"
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 8
	p.lifetime = 0.3
	p.texture = EnemyVfxShared.soft_dot_texture()
	p.process_material = _build_process_material()
	p.z_as_relative = false
	p.z_index = 5
	return p


func _build_process_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0.0, -1.0, 0.0)
	m.spread = 20.0
	m.gravity = Vector3.ZERO
	m.initial_velocity_min = 10.0
	m.initial_velocity_max = 24.0
	m.scale_min = 0.5
	m.scale_max = 1.0
	m.color = GLOW_COLOR
	m.color_ramp = EnemyVfxShared.fade_gradient(GLOW_COLOR, GLOW_COLOR_FADE)
	return m
```

- [ ] **Step 4: Wire it into `Enemy`**

Add a var near `_footstep_timer` (from Task 8):

```gdscript
var _windup_vfx: WindupTelegraphVfx = null
```

In `_ready()`, after the `FootstepDustVfx` block from Task 8, add:

```gdscript
	var windup_vfx := WindupTelegraphVfx.new()
	windup_vfx.name = "WindupTelegraphVfx"
	add_child(windup_vfx)
	_windup_vfx = windup_vfx
```

Add the virtual method near `_uses_footstep_vfx()`:

```gdscript
func _uses_windup_telegraph_vfx() -> bool:
	return true
```

In `_show_exclaim()`, after the existing tween setup, add:

```gdscript
func _show_exclaim() -> void:
	if _exclaim_label == null:
		return
	if _exclaim_tween and _exclaim_tween.is_valid():
		_exclaim_tween.kill()
	_exclaim_label.scale = Vector2.ZERO
	_exclaim_tween = create_tween()
	_exclaim_tween.set_trans(Tween.TRANS_BACK)
	_exclaim_tween.set_ease(Tween.EASE_OUT)
	_exclaim_tween.tween_property(_exclaim_label, "scale", Vector2(1.2, 1.2), 0.05)
	_exclaim_tween.tween_property(_exclaim_label, "scale", Vector2.ONE, 0.05)
	if _uses_windup_telegraph_vfx() and _windup_vfx:
		_windup_vfx.play()
```

- [ ] **Step 5: Override the virtual method in `lunge_enemy.gd`**

Add:

```gdscript
func _uses_windup_telegraph_vfx() -> bool:
	return false
```

- [ ] **Step 6: Run test to verify it passes**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
Expected: PASS (28 tests).

- [ ] **Step 7: Run the full enemy + lunge suites to check nothing regressed**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_state_machine.gd && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_lunge_enemy.gd
```
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add src/enemies/feedback/windup_telegraph_vfx.gd src/enemies/enemy.gd src/enemies/lunge_enemy.gd tests/unit/test_enemy_visual_identity.gd
git commit -m "feat: add windup telegraph VFX for non-lunge attack preparation"
```

---

## Task 10: Attack slash VFX (attacking)

**Files:**
- Create: `src/enemies/feedback/attack_slash_vfx.gd`
- Modify: `src/enemies/enemy.gd`
- Modify: `src/enemies/lunge_enemy.gd`
- Test: `tests/unit/test_enemy_visual_identity.gd`

**Interfaces:**
- Consumes: `EnemyVfxShared` (Task 1), `Enemy.get_facing_direction()`.
- Produces: `AttackSlashVfx.play(direction: Vector2) -> void`; `Enemy._uses_attack_slash_vfx() -> bool` (base `true`), `LungeEnemy` override (`false`); `Enemy._attack_vfx` triggered from `_process_attack()`.

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_enemy_visual_identity.gd`:

```gdscript
func test_base_enemy_uses_attack_slash_vfx() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	assert_bool(e._uses_attack_slash_vfx()).is_true()


func test_lunge_enemy_does_not_use_attack_slash_vfx() -> void:
	var e: LungeEnemy = auto_free(LungeEnemy.new())
	assert_bool(e._uses_attack_slash_vfx()).is_false()


func test_attack_plays_slash_vfx_for_melee() -> void:
	var scene: PackedScene = load("res://scenes/enemies/melee_enemy.tscn")
	var e: MeleeEnemy = auto_free(scene.instantiate())
	add_child(e)
	await get_tree().process_frame
	e._state = Enemy.State.ATTACK
	e._attack_started = false
	e._process_attack(0.01)
	var particles: GPUParticles2D = e._attack_vfx.get_node("Particles")
	assert_bool(particles.emitting).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
Expected: FAIL — `Function "_uses_attack_slash_vfx()" not found`.

- [ ] **Step 3: Create `AttackSlashVfx`**

Create `src/enemies/feedback/attack_slash_vfx.gd`:

```gdscript
class_name AttackSlashVfx
extends Node2D

const SLASH_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const SLASH_COLOR_FADE := Color(1.0, 1.0, 1.0, 0.0)

var _particles: GPUParticles2D = null


func _ready() -> void:
	z_index = 6
	z_as_relative = false
	_particles = _build_particles()
	add_child(_particles)


func play(direction: Vector2) -> void:
	if direction.length_squared() > 0.0001:
		rotation = direction.angle()
	_particles.restart()
	_particles.emitting = true


func _build_particles() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = "Particles"
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 12
	p.lifetime = 0.18
	p.texture = EnemyVfxShared.soft_dot_texture()
	p.process_material = _build_process_material()
	p.z_as_relative = false
	p.z_index = 6
	return p


func _build_process_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(1.0, 0.0, 0.0)
	m.spread = 30.0
	m.gravity = Vector3.ZERO
	m.initial_velocity_min = 90.0
	m.initial_velocity_max = 160.0
	m.scale_min = 0.8
	m.scale_max = 1.5
	m.color = SLASH_COLOR
	m.color_ramp = EnemyVfxShared.fade_gradient(SLASH_COLOR, SLASH_COLOR_FADE)
	return m
```

- [ ] **Step 4: Wire it into `Enemy`**

Add a var near `_windup_vfx` (from Task 9):

```gdscript
var _attack_vfx: AttackSlashVfx = null
```

In `_ready()`, after the `WindupTelegraphVfx` block from Task 9, add:

```gdscript
	var attack_vfx := AttackSlashVfx.new()
	attack_vfx.name = "AttackSlashVfx"
	add_child(attack_vfx)
	_attack_vfx = attack_vfx
```

Add the virtual method near `_uses_windup_telegraph_vfx()`:

```gdscript
func _uses_attack_slash_vfx() -> bool:
	return true
```

Replace `_process_attack`:

```gdscript
func _process_attack(_delta: float) -> void:
	if _status_component != null and _status_component.is_stunned():
		_change_state(State.CHASE)
		return
	if not _attack_started:
		_attack_started = true
		_execute_attack()
	if not _attack_in_progress():
		_change_state(State.COOLDOWN)
```

with:

```gdscript
func _process_attack(_delta: float) -> void:
	if _status_component != null and _status_component.is_stunned():
		_change_state(State.CHASE)
		return
	if not _attack_started:
		_attack_started = true
		_execute_attack()
		if _uses_attack_slash_vfx() and _attack_vfx:
			_attack_vfx.play(get_facing_direction())
	if not _attack_in_progress():
		_change_state(State.COOLDOWN)
```

- [ ] **Step 5: Override the virtual method in `lunge_enemy.gd`**

Add:

```gdscript
func _uses_attack_slash_vfx() -> bool:
	return false
```

- [ ] **Step 6: Run test to verify it passes**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
Expected: PASS (31 tests).

- [ ] **Step 7: Run the full enemy + lunge + ranged/sniper suites to check nothing regressed**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_state_machine.gd && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_lunge_enemy.gd
```
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add src/enemies/feedback/attack_slash_vfx.gd src/enemies/enemy.gd src/enemies/lunge_enemy.gd tests/unit/test_enemy_visual_identity.gd
git commit -m "feat: add attack slash VFX for non-lunge attacks"
```

---

## Task 11: Dash windup VFX (preparing dash)

**Files:**
- Create: `src/enemies/feedback/dash_windup_vfx.gd`
- Modify: `src/enemies/lunge_enemy.gd`
- Test: `tests/unit/test_lunge_enemy.gd`

**Interfaces:**
- Consumes: `EnemyVfxShared` (Task 1).
- Produces: `DashWindupVfx.play() -> void`; `LungeEnemy._dash_windup_vfx` triggered from `_play_windup_telegraph()`.

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_lunge_enemy.gd`:

```gdscript
func test_lunge_has_dash_windup_vfx_child() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	assert_object(e._dash_windup_vfx).is_not_null()
	assert_bool(e._dash_windup_vfx is DashWindupVfx).is_true()


func test_windup_plays_dash_windup_vfx() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	e._change_state(Enemy.State.WINDUP)
	var particles: GPUParticles2D = e._dash_windup_vfx.get_node("Particles")
	assert_bool(particles.emitting).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_lunge_enemy.gd
```
Expected: FAIL — `Identifier "DashWindupVfx" not declared`.

- [ ] **Step 3: Create `DashWindupVfx`**

Create `src/enemies/feedback/dash_windup_vfx.gd`:

```gdscript
class_name DashWindupVfx
extends Node2D

const SWIRL_COLOR := Color(1.0, 0.6, 0.2, 0.9)
const SWIRL_COLOR_FADE := Color(1.0, 0.3, 0.1, 0.0)

var _particles: GPUParticles2D = null


func _ready() -> void:
	z_index = 5
	z_as_relative = false
	_particles = _build_particles()
	add_child(_particles)


func play() -> void:
	_particles.restart()
	_particles.emitting = true


func _build_particles() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = "Particles"
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 14
	p.lifetime = 0.35
	p.texture = EnemyVfxShared.soft_dot_texture()
	p.process_material = _build_process_material()
	p.z_as_relative = false
	p.z_index = 5
	return p


func _build_process_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0.0, 0.0, 0.0)
	m.spread = 180.0
	m.gravity = Vector3.ZERO
	# Negative velocity pulls particles spawned on the ring inward, reading as a
	# tightening "coil" rather than an outward burst.
	m.initial_velocity_min = -70.0
	m.initial_velocity_max = -30.0
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_ring_radius = 14.0
	m.emission_ring_inner_radius = 12.0
	m.emission_ring_height = 0.0
	m.emission_ring_axis = Vector3(0.0, 0.0, 1.0)
	m.scale_min = 0.5
	m.scale_max = 1.0
	m.color = SWIRL_COLOR
	m.color_ramp = EnemyVfxShared.fade_gradient(SWIRL_COLOR, SWIRL_COLOR_FADE)
	return m
```

- [ ] **Step 4: Wire it into `lunge_enemy.gd`**

Add a var near `_fire_vfx`:

```gdscript
var _fire_vfx: DashFireVfx = null
var _dash_windup_vfx: DashWindupVfx = null
```

In `_ready()`, after the `_fire_vfx` setup, add:

```gdscript
	_dash_windup_vfx = DashWindupVfx.new()
	_dash_windup_vfx.name = "DashWindupVfx"
	add_child(_dash_windup_vfx)
```

Update `_play_windup_telegraph()`:

```gdscript
func _play_windup_telegraph() -> void:
	_play_hit_flash()
	_play_squash()
	if _dash_windup_vfx:
		_dash_windup_vfx.play()
```

- [ ] **Step 5: Run test to verify it passes**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_lunge_enemy.gd
```
Expected: PASS (all tests in the file, including the 2 new ones).

- [ ] **Step 6: Commit**

```bash
git add src/enemies/feedback/dash_windup_vfx.gd src/enemies/lunge_enemy.gd tests/unit/test_lunge_enemy.gd
git commit -m "feat: add dash windup swirl VFX for lunge enemy"
```

---

## Task 12: Convert `DashFireVfx` from CPU to GPU particles

**Files:**
- Modify: `src/enemies/feedback/dash_fire_vfx.gd`
- Modify: `tests/unit/test_dash_fire_vfx.gd`
- Modify: `tests/unit/test_lunge_enemy.gd`

**Interfaces:**
- Consumes: `EnemyVfxShared` (Task 1).
- Preserves: `DashFireVfx.start(direction: Vector2) -> void`, `DashFireVfx.stop() -> void`, `offset_distance: float` export — no call-site changes needed in `lunge_enemy.gd`.

- [ ] **Step 1: Update the existing tests to expect `GPUParticles2D`**

In `tests/unit/test_dash_fire_vfx.gd`, change the two `CPUParticles2D` type annotations to `GPUParticles2D`:

```gdscript
func test_start_sets_emitting_true() -> void:
	var v := _make_vfx()
	v.start(Vector2.RIGHT)
	var particles: GPUParticles2D = v.get_node("Particles")
	assert_bool(particles.emitting).is_true()


func test_stop_sets_emitting_false() -> void:
	var v := _make_vfx()
	v.start(Vector2.RIGHT)
	v.stop()
	var particles: GPUParticles2D = v.get_node("Particles")
	assert_bool(particles.emitting).is_false()
```

In `tests/unit/test_lunge_enemy.gd`, change the two `CPUParticles2D` type annotations (in `test_begin_dash_starts_fire_vfx_along_lock_dir` and `test_dash_end_stops_fire_vfx`) to `GPUParticles2D`.

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_dash_fire_vfx.gd
```
Expected: FAIL — type mismatch, `get_node("Particles")` still returns a `CPUParticles2D`.

- [ ] **Step 3: Convert `dash_fire_vfx.gd` to build a `GPUParticles2D`**

Replace the full contents of `src/enemies/feedback/dash_fire_vfx.gd`:

```gdscript
class_name DashFireVfx
extends Node2D

@export var offset_distance: float = 16.0

const FIRE_COLOR := Color(1.0, 0.55, 0.15, 0.9)
const FIRE_COLOR_FADE := Color(1.0, 0.2, 0.05, 0.0)

var _particles: GPUParticles2D = null


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


func _build_particles() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = "Particles"
	p.emitting = false
	p.amount = 24
	p.lifetime = 0.25
	p.texture = EnemyVfxShared.soft_dot_texture()
	p.process_material = _build_process_material()
	p.z_as_relative = false
	p.z_index = 6
	return p


func _build_process_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(1.0, 0.0, 0.0)
	m.spread = 18.0
	m.gravity = Vector3.ZERO
	m.initial_velocity_min = 60.0
	m.initial_velocity_max = 110.0
	m.scale_min = 1.5
	m.scale_max = 3.0
	m.color = FIRE_COLOR
	m.color_ramp = EnemyVfxShared.fade_gradient(FIRE_COLOR, FIRE_COLOR_FADE)
	return m
```

Note `one_shot` is intentionally left at its default `false` (continuous emission while `emitting = true`) since `lunge_enemy.gd` calls `start()` at dash begin and `stop()` at dash end, expecting a continuous trail for the ~0.22s dash — same behavior as the original `CPUParticles2D` version.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_dash_fire_vfx.gd && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_lunge_enemy.gd
```
Expected: PASS (both files, including all pre-existing tests).

- [ ] **Step 5: Commit**

```bash
git add src/enemies/feedback/dash_fire_vfx.gd tests/unit/test_dash_fire_vfx.gd tests/unit/test_lunge_enemy.gd
git commit -m "refactor: convert DashFireVfx from CPUParticles2D to GPUParticles2D"
```

---

## Task 13: Elite visual overlay (outline + per-ability tint)

**Files:**
- Modify: `src/enemies/enemy.gd`
- Test: `tests/unit/test_enemy_visual_identity.gd`

**Interfaces:**
- Consumes: `shaders/visual/outline.gdshader` (existing, has `outline_width`/`outline_color` uniforms).
- Produces: `Enemy._elite_outline_tint(ability: int) -> Color` (static), `Enemy._elite_tint_color: Color` (instance var set by `_apply_elite_visuals()`).

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_enemy_visual_identity.gd`:

```gdscript
func test_elite_outline_tint_fast_is_cyan() -> void:
	assert_that(Enemy._elite_outline_tint(Enemy.EliteAbility.FAST)).is_equal(Color(0.3, 0.9, 1.0))


func test_elite_outline_tint_tank_is_steel() -> void:
	assert_that(Enemy._elite_outline_tint(Enemy.EliteAbility.TANK)).is_equal(Color(0.6, 0.6, 0.65))


func test_elite_outline_tint_teleport_is_purple() -> void:
	assert_that(Enemy._elite_outline_tint(Enemy.EliteAbility.TELEPORT)).is_equal(Color(0.7, 0.3, 1.0))


func test_elite_outline_tint_enrage_is_red() -> void:
	assert_that(Enemy._elite_outline_tint(Enemy.EliteAbility.ENRAGE)).is_equal(Color(1.0, 0.2, 0.2))


func test_elite_outline_tint_none_is_gold() -> void:
	assert_that(Enemy._elite_outline_tint(Enemy.EliteAbility.NONE)).is_equal(Color(1.0, 0.85, 0.3))


func test_elite_visuals_apply_shader_and_tint() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	e.add_child(sprite)
	e.is_elite = true
	e.elite_ability = Enemy.EliteAbility.ENRAGE
	add_child(e)
	await get_tree().process_frame
	assert_bool(sprite.material is ShaderMaterial).is_true()
	assert_that(e._elite_tint_color).is_equal(Color(1.0, 0.2, 0.2))


func test_non_elite_has_no_outline_material() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	e.add_child(sprite)
	add_child(e)
	await get_tree().process_frame
	assert_object(sprite.material).is_null()
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
Expected: FAIL — `Function "_elite_outline_tint()" not found`.

- [ ] **Step 3: Add the elite visuals to `enemy.gd`**

Add a constant near `SQUASH_DURATION`:

```gdscript
const ELITE_OUTLINE_SHADER: Shader = preload("res://shaders/visual/outline.gdshader")
const ELITE_OUTLINE_WIDTH: float = 1.5
const ELITE_TINT_BLEND: float = 0.35
```

Add a var near `_base_modulate`:

```gdscript
var _base_modulate: Color = Color.WHITE
var _elite_tint_color: Color = Color.WHITE
```

Change `_apply_elite_scaling()` to call the new visuals method at the end:

```gdscript
func _apply_elite_scaling() -> void:
	max_health = int(float(max_health) * 3.0)
	health = max_health
	speed *= 1.3
	if weapon:
		weapon.damage *= 1.5
	scale *= 1.3

	match elite_ability:
		EliteAbility.FAST:
			windup_duration = maxf(0.2, windup_duration * 0.5)
			cooldown_duration *= 0.5
		EliteAbility.TANK:
			max_health *= 2
			health = max_health
			speed = _speed_base * 0.7
		EliteAbility.ENRAGE:
			pass  # dynamically applied in _process

	_apply_elite_visuals()


func _apply_elite_visuals() -> void:
	_elite_tint_color = _elite_outline_tint(elite_ability)
	var sprite := get_node_or_null("Sprite2D")
	if sprite == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = ELITE_OUTLINE_SHADER
	mat.set_shader_parameter("outline_width", ELITE_OUTLINE_WIDTH)
	mat.set_shader_parameter("outline_color", _elite_tint_color)
	sprite.material = mat


static func _elite_outline_tint(ability: int) -> Color:
	match ability:
		EliteAbility.FAST:
			return Color(0.3, 0.9, 1.0)
		EliteAbility.TANK:
			return Color(0.6, 0.6, 0.65)
		EliteAbility.TELEPORT:
			return Color(0.7, 0.3, 1.0)
		EliteAbility.ENRAGE:
			return Color(1.0, 0.2, 0.2)
	return Color(1.0, 0.85, 0.3)
```

Blend the elite tint into the per-frame status tint in `_physics_process` (this keeps the tint alive even though `_base_modulate` is recomputed from `StatusComponent` every frame). Change:

```gdscript
	var tint_status := _status_component
	if tint_status:
		_base_modulate = tint_status.get_blended_tint()
		if _burn_flash > 0.0:
```

to:

```gdscript
	var tint_status := _status_component
	if tint_status:
		_base_modulate = tint_status.get_blended_tint()
		if is_elite:
			_base_modulate = _base_modulate.lerp(_elite_tint_color, ELITE_TINT_BLEND)
		if _burn_flash > 0.0:
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
Expected: PASS (38 tests).

- [ ] **Step 5: Run the full enemy state machine suite to check nothing regressed**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_state_machine.gd
```
Expected: PASS (including `test_elite_stat_scaling`, `test_elite_tank_speed`, `test_elite_fast_windup_floor`).

- [ ] **Step 6: Commit**

```bash
git add src/enemies/enemy.gd tests/unit/test_enemy_visual_identity.gd
git commit -m "feat: add elite glow outline and per-ability tint overlay"
```

---

## Task 14: Enhanced death animation (knockback rotation + dissolve particles)

**Files:**
- Create: `src/enemies/feedback/death_dissolve_vfx.gd`
- Modify: `src/enemies/enemy.gd`
- Test: `tests/unit/test_enemy_visual_identity.gd`

**Interfaces:**
- Consumes: `EnemyVfxShared` (Task 1).
- Produces: `DeathDissolveVfx.burst(tint: Color) -> void`; `Enemy._death_rotation_target() -> float`; `Enemy._death_vfx` triggered on entering `State.DEATH`.

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_enemy_visual_identity.gd`:

```gdscript
func test_death_rotation_target_uses_knockback_direction() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	e._knockback_velocity = Vector2(1, 0)
	assert_float(e._death_rotation_target()).is_equal_approx(0.0, 0.01)


func test_death_rotation_target_falls_back_to_facing_direction() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	e._knockback_velocity = Vector2.ZERO
	var player: Node2D = auto_free(Node2D.new())
	add_child(player)
	player.global_position = Vector2(0, 1)
	e._player_ref = player
	e.global_position = Vector2.ZERO
	assert_float(e._death_rotation_target()).is_equal_approx(Vector2.DOWN.angle(), 0.01)


func test_entering_death_bursts_dissolve_vfx() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	add_child(e)
	await get_tree().process_frame
	e._change_state(Enemy.State.DEATH)
	var particles: GPUParticles2D = e._death_vfx.get_node("Particles")
	assert_bool(particles.emitting).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
Expected: FAIL — `Function "_death_rotation_target()" not found`.

- [ ] **Step 3: Create `DeathDissolveVfx`**

Create `src/enemies/feedback/death_dissolve_vfx.gd`:

```gdscript
class_name DeathDissolveVfx
extends Node2D

var _particles: GPUParticles2D = null


func _ready() -> void:
	z_index = 4
	z_as_relative = false
	_particles = _build_particles()
	add_child(_particles)


func burst(tint: Color) -> void:
	_particles.modulate = tint
	_particles.restart()
	_particles.emitting = true


func _build_particles() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = "Particles"
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 18
	p.lifetime = 0.4
	p.texture = EnemyVfxShared.soft_dot_texture()
	p.process_material = _build_process_material()
	p.z_as_relative = false
	p.z_index = 4
	return p


func _build_process_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0.0, 0.0, 0.0)
	m.spread = 180.0
	m.gravity = Vector3.ZERO
	m.initial_velocity_min = 30.0
	m.initial_velocity_max = 90.0
	m.scale_min = 0.6
	m.scale_max = 1.3
	m.color = Color.WHITE
	m.color_ramp = EnemyVfxShared.fade_gradient(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	return m
```

- [ ] **Step 4: Wire it into `Enemy`**

Add a var near `_death_tween`:

```gdscript
var _death_tween: Tween = null
var _death_vfx: DeathDissolveVfx = null
```

In `_ready()`, after the `AttackSlashVfx` block (from Task 10), add:

```gdscript
	var death_vfx := DeathDissolveVfx.new()
	death_vfx.name = "DeathDissolveVfx"
	add_child(death_vfx)
	_death_vfx = death_vfx
```

In `_change_state()`, change:

```gdscript
		State.DEATH:
			_state_timer = death_duration
			_death_tween = null
```

to:

```gdscript
		State.DEATH:
			_state_timer = death_duration
			_death_tween = null
			if _death_vfx:
				_death_vfx.burst(_base_modulate)
```

Add the rotation-target helper near `_process_death`:

```gdscript
func _death_rotation_target() -> float:
	if _knockback_velocity.length_squared() > 1.0:
		return _knockback_velocity.angle()
	return get_facing_direction().angle()
```

Update `_process_death()`:

```gdscript
func _process_death(delta: float) -> void:
	_state_timer -= delta
	var t := 1.0 - (_state_timer / death_duration)
	var sprite := get_node_or_null("Sprite2D")
	if sprite:
		sprite.scale = Vector2.ONE * maxf(0.0, 1.0 - t)
		sprite.rotation = lerp_angle(sprite.rotation, _death_rotation_target(), t)
	if _state_timer <= 0.0:
		_spawn_drops()
		queue_free()
```

- [ ] **Step 5: Run test to verify it passes**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_visual_identity.gd
```
Expected: PASS (41 tests).

- [ ] **Step 6: Run the full enemy + lunge suites to check nothing regressed**

Run:
```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_enemy_state_machine.gd && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_lunge_enemy.gd && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_dash_fire_vfx.gd
```
Expected: PASS across all three files.

- [ ] **Step 7: Commit**

```bash
git add src/enemies/feedback/death_dissolve_vfx.gd src/enemies/enemy.gd tests/unit/test_enemy_visual_identity.gd
git commit -m "feat: add knockback-rotation and dissolve particles to enemy death"
```

---

## Final verification

- [ ] **Run the entire unit test directory to catch any cross-file regression:**

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit
```
Expected: PASS across the whole suite.

- [ ] **Manual verification in-editor** (per the spec's Testing section — particle look/feel and animation timing can't be asserted by unit tests):
  - Spawn a melee enemy (grunt) and confirm idle breathing, walk-speed-scaled flicker, windup telegraph glow, attack slash, hurt spark, footstep dust while chasing, and the enhanced death (rotate + dissolve).
  - Spawn a lunge enemy (brute) and confirm the coiled dash-windup swirl + held breathe frame, then the extended dash + fire trail + held normal frame.
  - Spawn a ranged enemy with each weapon type and confirm archer sprite for `AimedBurstWeapon`/default, lobber sprite for `SplitShotWeapon`/`FanWeapon`.
  - Spawn a sniper enemy and confirm the mage sprite.
  - Force-spawn an elite melee enemy (each `EliteAbility`) and confirm the outline glow + tint matches the ability.
