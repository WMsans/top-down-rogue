# Dash Fire Particle-Swarm Bullet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the static `Polygon2D` bullet shapes in `DashFireVfx` with a swarm of small `CPUParticles2D` flame particles spawned inside the bullet silhouette, so the lunge enemy's dash-fire effect reads as flickering, "jumping" flame instead of a rigid solid bullet.

**Architecture:** `DashFireVfx` (`src/enemies/feedback/dash_fire_vfx.gd`) keeps its existing `GPUParticles2D` trailing-tail spray unchanged (node name `Particles`, already covered by existing tests). It gains a new `CPUParticles2D` child named `FlameFill` whose `emission_points` are pre-sampled at `_ready()` by rejection-sampling random points against the existing `BULLET_UNIT_POINTS` polygon, scaled by `body_length`/`body_width`. Both particle systems are started/stopped together from `start()`/`stop()`. All `Polygon2D`, `Tween`, and per-frame wobble code is deleted — the particle systems' own emission and lifetime naturally produce the flicker/fade look, so `_process()` is no longer needed.

**Tech Stack:** Godot 4.7, GDScript, gdUnit4 (test suite already exists at `tests/unit/test_dash_fire_vfx.gd`, run via `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_dash_fire_vfx.gd`).

## Global Constraints

- Keep the `GPUParticles2D` tail layer's node name as `"Particles"` — existing tests (`test_start_sets_emitting_true`, `test_stop_sets_emitting_false`) call `v.get_node("Particles")` and must keep passing unmodified.
- Keep `offset_distance`, `body_length`, `body_width` as `@export` vars on `DashFireVfx` — `lunge_enemy.gd` and the scene may rely on these being configurable in the editor.
- No gameplay logic changes — this is a visual-only effect; `start(direction: Vector2)` and `stop()` keep their exact signatures since `lunge_enemy.gd:69` and `lunge_enemy.gd:93` call them.

---

### Task 1: Particle-swarm flame-fill layer

**Files:**
- Modify: `src/enemies/feedback/dash_fire_vfx.gd` (full rewrite of body, same `class_name`/`extends`)
- Modify: `tests/unit/test_dash_fire_vfx.gd` (add new tests, keep the 4 existing ones intact)

**Interfaces:**
- Consumes: nothing new — `EnemyVfxShared.soft_dot_texture()` (already used, returns `GradientTexture2D`) is the only shared helper touched.
- Produces: `DashFireVfx` still exposes `start(direction: Vector2) -> void` and `stop() -> void`, and still has a `GPUParticles2D` child named `"Particles"`. New: a `CPUParticles2D` child named `"FlameFill"` with a populated `emission_points: PackedVector2Array` (non-empty, `emission_shape == CPUParticles2D.EMISSION_SHAPE_POINTS`).

- [ ] **Step 1: Write the failing tests for the new flame-fill layer**

Open `tests/unit/test_dash_fire_vfx.gd` and add these four tests after the existing `test_start_rotates_to_upward_direction` (keep all 4 existing tests untouched):

```gdscript
func test_flame_fill_layer_exists() -> void:
	var v := _make_vfx()
	var flame_fill: CPUParticles2D = v.get_node("FlameFill")
	assert_object(flame_fill).is_not_null()
	assert_int(flame_fill.emission_shape).is_equal(CPUParticles2D.EMISSION_SHAPE_POINTS)


func test_flame_fill_emission_points_are_populated() -> void:
	var v := _make_vfx()
	var flame_fill: CPUParticles2D = v.get_node("FlameFill")
	assert_int(flame_fill.emission_points.size()).is_greater(0)


func test_flame_fill_emission_points_stay_within_bullet_bounds() -> void:
	var v := _make_vfx()
	var flame_fill: CPUParticles2D = v.get_node("FlameFill")
	for pt in flame_fill.emission_points:
		assert_float(absf(pt.x)).is_less_equal(v.body_length * 0.5 + 0.01)
		assert_float(absf(pt.y)).is_less_equal(v.body_width * 0.5 + 0.01)


func test_start_sets_flame_fill_emitting_true() -> void:
	var v := _make_vfx()
	v.start(Vector2.RIGHT)
	var flame_fill: CPUParticles2D = v.get_node("FlameFill")
	assert_bool(flame_fill.emitting).is_true()


func test_stop_sets_flame_fill_emitting_false() -> void:
	var v := _make_vfx()
	v.start(Vector2.RIGHT)
	v.stop()
	var flame_fill: CPUParticles2D = v.get_node("FlameFill")
	assert_bool(flame_fill.emitting).is_false()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_dash_fire_vfx.gd`

Expected: the 4 pre-existing tests PASS, the 5 new tests FAIL (error: `Node not found: "FlameFill"` or similar, since `FlameFill` doesn't exist yet).

- [ ] **Step 3: Rewrite `dash_fire_vfx.gd`**

Replace the full contents of `src/enemies/feedback/dash_fire_vfx.gd` with:

```gdscript
class_name DashFireVfx
extends Node2D

@export var offset_distance: float = 6.0
@export var body_length: float = 34.0
@export var body_width: float = 26.0

const FIRE_COLOR := Color(1.0, 0.55, 0.15, 0.85)
const FIRE_COLOR_FADE := Color(1.0, 0.2, 0.05, 0.0)
const FLAME_FILL_COUNT := 50

const BULLET_UNIT_POINTS: Array[Vector2] = [
	Vector2(-0.5, -0.32), Vector2(-0.5, 0.32),
	Vector2(-0.38, 0.46), Vector2(-0.15, 0.5),
	Vector2(0.15, 0.42), Vector2(0.35, 0.22),
	Vector2(0.5, 0.0),
	Vector2(0.35, -0.22), Vector2(0.15, -0.42),
	Vector2(-0.15, -0.5), Vector2(-0.38, -0.46),
]

var _tail: GPUParticles2D = null
var _flame_fill: CPUParticles2D = null


func _ready() -> void:
	z_index = 6
	z_as_relative = false
	_flame_fill = _build_flame_fill()
	add_child(_flame_fill)
	_tail = _build_tail()
	add_child(_tail)


func start(direction: Vector2) -> void:
	if direction.length_squared() > 0.0001:
		var dir := direction.normalized()
		rotation = dir.angle()
		position = dir * offset_distance
	_flame_fill.restart()
	_flame_fill.emitting = true
	_tail.restart()
	_tail.emitting = true


func stop() -> void:
	_flame_fill.emitting = false
	_tail.emitting = false


func _build_flame_fill() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "FlameFill"
	p.emitting = false
	p.amount = FLAME_FILL_COUNT
	p.lifetime = 0.15
	p.texture = EnemyVfxShared.soft_dot_texture()
	p.z_as_relative = false
	p.z_index = 6
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = _sample_bullet_points(FLAME_FILL_COUNT)
	p.direction = Vector2.RIGHT
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 22.0
	p.damping_min = 6.0
	p.damping_max = 10.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.scale_amount_curve = _build_pop_curve()
	p.hue_variation_min = -0.05
	p.hue_variation_max = 0.05
	p.color_ramp = _build_gradient(FIRE_COLOR, FIRE_COLOR_FADE)
	return p


func _build_pop_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.3))
	c.add_point(Vector2(0.25, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	return c


func _build_gradient(hot: Color, fade: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, hot)
	g.set_color(1, fade)
	return g


func _sample_bullet_points(count: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var attempts := 0
	var max_attempts := count * 50
	while pts.size() < count and attempts < max_attempts:
		attempts += 1
		var candidate := Vector2(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5))
		if _point_in_bullet_polygon(candidate):
			pts.append(Vector2(candidate.x * body_length, candidate.y * body_width))
	return pts


func _point_in_bullet_polygon(pt: Vector2) -> bool:
	var inside := false
	var n := BULLET_UNIT_POINTS.size()
	var j := n - 1
	for i in n:
		var pi: Vector2 = BULLET_UNIT_POINTS[i]
		var pj: Vector2 = BULLET_UNIT_POINTS[j]
		if (pi.y > pt.y) != (pj.y > pt.y):
			var x_intersect := (pj.x - pi.x) * (pt.y - pi.y) / (pj.y - pi.y) + pi.x
			if pt.x < x_intersect:
				inside = not inside
		j = i
	return inside


func _build_tail() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = "Particles"
	p.emitting = false
	p.amount = 14
	p.lifetime = 0.2
	p.texture = EnemyVfxShared.soft_dot_texture()
	p.process_material = _build_tail_process_material()
	p.z_as_relative = false
	p.z_index = 5
	return p


func _build_tail_process_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(-1.0, 0.0, 0.0)
	m.spread = 16.0
	m.gravity = Vector3.ZERO
	m.initial_velocity_min = 55.0
	m.initial_velocity_max = 100.0
	m.scale_min = 1.2
	m.scale_max = 2.4
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 1.8
	m.turbulence_noise_scale = 2.5
	m.turbulence_influence_min = 0.3
	m.turbulence_influence_max = 0.6
	m.color = FIRE_COLOR
	m.color_ramp = EnemyVfxShared.fade_gradient(FIRE_COLOR, FIRE_COLOR_FADE)
	return m
```

This deletes `_bullet_outer`, `_bullet_inner`, `_fade_tween`, `_intensity`, `_time`, `_process()`, `_animate_intensity()`, `_set_intensity()`, `_apply_visual()`, `_wobble_points()`, and `_build_bullet_polygon()` entirely, and renames the old `_particles`/`_build_particles`/`_build_process_material` to `_tail`/`_build_tail`/`_build_tail_process_material` (kept behaviorally identical to the current tail spray).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_dash_fire_vfx.gd`

Expected: `9 test cases | 0 errors | 0 failures` (the 4 original tests plus the 5 new ones), overall `PASSED`.

- [ ] **Step 5: Run the full test suite to check for regressions**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit`

Expected: no new failures compared to the pre-change baseline (in particular `tests/unit/test_lunge_enemy.gd` must still pass, since `LungeEnemy` calls `DashFireVfx.start()`/`stop()`).

- [ ] **Step 6: Manual visual check**

Launch the game, open the dev console, and run:

```
spawn enemy lunge
```

Let the lunge enemy dash at the player (or lure it into range) and visually confirm: the bullet-shaped silhouette is now made of many small flickering flame particles that pop and fade in place ("jumping flame" look) rather than a static solid shape, while a fainter particle trail streams behind it as it moves. Confirm the effect still points in the dash direction and disappears when the dash ends.

- [ ] **Step 7: Commit**

```bash
git add src/enemies/feedback/dash_fire_vfx.gd tests/unit/test_dash_fire_vfx.gd
git commit -m "feat: make dash fire a particle swarm instead of a static bullet shape"
```
